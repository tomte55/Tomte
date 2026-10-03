local addonName, ns = ...

-- Shared cinematic engine: camera zoom + tilt + slow orbit, letterbox + vignette, optional music, UI
-- faded out. What's drawn in the letterbox comes from a scene; the character showcase (Showcase.lua) is
-- optional per Enter.
-- The letterbox swallows mouse input so the player can't move the camera; a click or Esc pauses (or calls
-- opts.onDismiss, with opts.hint as the hint text). opts.passthrough instead leaves all input to the game
-- and dismisses on any key or click (short cinematics that must never take control away). A paused
-- cinematic comes back after state.resumeDelay seconds without clicks, key presses or open windows (the
-- owner's tick decides when to Enter again).
-- The UI must always come back: Exit is idempotent and waits for combat to end if needed.
--
-- Scene contract:
--   scene.Create(parent, letterbox)  once, on the scene's first Enter; draw into parent (the scene's frame)
--   scene.Begin(state)               every Enter
--   scene.Update(contentAlpha, dt)   every frame while the letterbox is visible
--   scene.End()                      optional, on Exit
-- state is the caller's persisted table. The engine records what it changed on it (zoomedOut, pitchLimited,
-- musicHandle, musicStarted, cinematic, orbitFactor, resumeAt, resumeDelay) so a /reload can still undo it.

local TARGET_ZOOM = 20 -- yards
local ORBIT_SPEED = 0.04 -- multiplier on the cameraYawMoveSpeed CVar
local LETTERBOX_FRACTION = 0.105 -- of screen height, per band
local LETTERBOX_EDGE = 24 -- soft gradient edge, pixels
local LETTERBOX_TIME = 1.2
local UI_FADE_OUT, UI_FADE_IN = 1, 0.6
local VIGNETTE_WIDTH = 0.16 -- of screen width, per side
local VIGNETTE_ALPHA = 0.6
local MUSIC_FADE_MS = 3000
local CINEMATIC_PITCH = 22 -- pitchlimit while cinematic: max degrees the camera sits above the character
local DEFAULT_PITCH = 88 -- the game's pitchlimit
local PITCH_EASE = 1.5 -- seconds to lower the limit (a top-down camera follows it down)
local PITCH_NUDGE_SPEED = 0.4 -- multiplier on cameraPitchMoveSpeed: lifts a low camera up to the limit
local PITCH_NUDGE_TIME = 2
local WATCH_INTERVAL = 0.2
local WORLD_SWEEP = 0.2
local DEFAULT_RESUME = 20 -- resume delay for a state paused before a /reload (it lacks resumeDelay)
local HINT_TIME = 4 -- seconds the pause hint stays up
local HINT_FADE = 0.5
local HINT_PAD = 48
local GREY = { 0.62, 0.62, 0.62 }
local UI_PANEL_KEYS = { "left", "center", "right", "doublewide", "fullscreen" }

-- Expansion main themes, newest first. Options show the names; a track is picked by index.
ns.MUSIC_TRACKS = {
	{ name = "Midnight", kit = "MUS_120_MAIN_TITLE" },
	{ name = "The War Within", kit = "MUS_110_MAIN_TITLE" },
	{ name = "Dragonflight", kit = "MUS_100_MAIN_TITLE" },
	{ name = "Shadowlands", kit = "MUS_90_MAIN_TITLE" },
	{ name = "Battle for Azeroth", kit = "MUS_80_MAIN_TITLE" },
	{ name = "Legion", kit = "MUS_70_MAIN_TITLE" },
	{ name = "Warlords of Draenor", kit = "MUS_60_MAIN_TITLE" },
	{ name = "Mists of Pandaria", kit = "MUS_50_HEART_OF_PANDARIA_MAINTITLE" },
	{ name = "World of Warcraft", kit = "MUS_1_0_MAINTITLE_ORIGINAL" },
}

local C = {}
ns.Cinematic = C

local active
local current -- state of the active cinematic
local scene -- scene in the letterbox; stays set while the letterbox slides out
local dismiss -- opts.onDismiss of the active cinematic (click/Esc), nil = pause
local passthrough -- opts.passthrough of the active cinematic: input reaches the game, any input dismisses
local createdScenes = {}
local hidUI -- we only bring back a UI we hid ourselves (respects a manual Alt-Z)
local showUIAfterCombat
local uiFader = CreateFrame("Frame")
local letterbox, hintFrame, hint -- built on the first Enter
local hintTimer = 0
local showcaseCreated
local progress, target = 0, 0
local hiddenWorldFrames = {} -- other addons' WorldFrame children we hid (UIParent hiding doesn't reach them)
local sinceWorldSweep = 0
local cursorX, cursorY
local pitcher = CreateFrame("Frame")
local watcher = CreateFrame("Frame")
local watched -- paused state whose resume timer the watcher tops up
local sinceWatch = 0
local events = CreateFrame("Frame")

-- Combat events only while they matter: an active cinematic, or a UI waiting to be shown after combat.
local function UpdateEvents()
	if active then
		events:RegisterEvent("PLAYER_REGEN_DISABLED")
	else
		events:UnregisterEvent("PLAYER_REGEN_DISABLED")
	end
	if active or showUIAfterCombat then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
end

local function HideWorldFrameAddons()
	for _, child in ipairs({ WorldFrame:GetChildren() }) do
		-- Forbidden frames error on any other call, so check that first. Skip protected frames,
		-- engine-managed nameplates, and our own frames.
		if not child:IsForbidden() and not child:IsProtected() and child:IsShown() and not ns.ownFrames[child] then
			local name = child:GetName()
			if not (name and name:find("^NamePlate")) then
				child:Hide()
				hiddenWorldFrames[child] = true
			end
		end
	end
end

local function ShowWorldFrameAddons()
	for child in pairs(hiddenWorldFrames) do
		child:Show()
	end
	wipe(hiddenWorldFrames)
end

local function FadeUI(from, to, duration, onDone)
	local t = 0
	UIParent:SetAlpha(from)
	uiFader:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		local p = math.min(t / duration, 1)
		UIParent:SetAlpha(from + (to - from) * p)
		if p >= 1 then
			self:SetScript("OnUpdate", nil)
			if onDone then
				onDone()
			end
		end
	end)
end

local function HideUI()
	if InCombatLockdown() or not UIParent:IsShown() then
		return
	end
	hidUI = true
	FadeUI(1, 0, UI_FADE_OUT, function()
		if active and not InCombatLockdown() then
			UIParent:Hide()
		end
		-- Hidden anyway (or combat started mid-fade): full alpha so Alt-Z / showing it again gives a visible UI.
		UIParent:SetAlpha(1)
	end)
end

local function ShowUI()
	if not hidUI then
		return
	end
	if InCombatLockdown() then
		-- Can't Show() now, but alpha is allowed: never leave an invisible UI on screen.
		uiFader:SetScript("OnUpdate", nil)
		UIParent:SetAlpha(1)
		showUIAfterCombat = true
		return
	end
	hidUI, showUIAfterCombat = false, false
	local from = UIParent:IsShown() and UIParent:GetAlpha() or 0
	UIParent:Show()
	FadeUI(from, 1, UI_FADE_IN)
end

-- Undo exactly the zoom we applied (GetCameraZoom is mid-animation or collision-shortened at times).
local function RestoreZoom(state)
	if state.zoomedOut and state.zoomedOut > 0 then
		CameraZoomIn(state.zoomedOut)
	end
	state.zoomedOut = nil
end

local function Ease(p)
	return p * p * (3 - 2 * p)
end

-- No API reads or sets the camera pitch. Lowering the pitch limit drags a high camera down with it; a short
-- upward push then lifts a low camera until it rests on the limit. Either way it ends at CINEMATIC_PITCH.
local pitchLimit
local function SetPitchLimit(degrees)
	if degrees ~= pitchLimit then
		pitchLimit = degrees
		ConsoleExec("pitchlimit " .. degrees)
	end
end

local function LimitPitch(state)
	state.pitchLimited = true -- persisted so a /reload still resets the limit
	pitchLimit = nil
	local t, nudging = 0, false
	pitcher:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		if t < PITCH_EASE then
			local p = Ease(t / PITCH_EASE)
			-- Tenths of a degree: whole-degree steps make the camera stutter on the way down.
			SetPitchLimit(math.floor((DEFAULT_PITCH + (CINEMATIC_PITCH - DEFAULT_PITCH) * p) * 10 + 0.5) / 10)
		elseif not nudging then
			nudging = true
			SetPitchLimit(CINEMATIC_PITCH)
			MoveViewUpStart(PITCH_NUDGE_SPEED) -- "up" raises the camera (Down sent it under the character)
		elseif t >= PITCH_EASE + PITCH_NUDGE_TIME then
			MoveViewUpStop()
			self:SetScript("OnUpdate", nil)
		end
	end)
end

local function RestorePitch(state)
	if pitcher:GetScript("OnUpdate") then
		pitcher:SetScript("OnUpdate", nil)
		MoveViewUpStop()
	end
	if state.pitchLimited then
		pitchLimit = nil
		SetPitchLimit(DEFAULT_PITCH)
		state.pitchLimited = nil
	end
end

-- Anything that means the player is using the game: keeps a paused cinematic from coming back.
local function PlayerBusy()
	if InCombatLockdown() or IsMouseButtonDown() or GetCurrentKeyBoardFocus() then
		return true
	end
	if IsAnyBagOpen and IsAnyBagOpen() then
		return true
	end
	for _, key in ipairs(UI_PANEL_KEYS) do
		if GetUIPanel(key) then
			return true
		end
	end
	for _, name in ipairs(UISpecialFrames) do
		local frame = _G[name]
		if type(frame) == "table" and frame.IsVisible and frame:IsVisible() then
			return true
		end
	end
	return (GameMenuFrame and GameMenuFrame:IsVisible()) or (WorldMapFrame and WorldMapFrame:IsVisible()) or false
end

local function TopUp()
	if watched and watched.resumeAt then
		watched.resumeAt = math.max(watched.resumeAt, GetTime() + (watched.resumeDelay or DEFAULT_RESUME))
	end
end

local function WatcherOnUpdate(self, elapsed)
	if not (watched and watched.resumeAt) then
		watched = nil
		self:Hide()
		return
	end
	sinceWatch = sinceWatch + elapsed
	if sinceWatch >= WATCH_INTERVAL then
		sinceWatch = 0
		if PlayerBusy() then
			TopUp()
		end
	end
end

local function Spaced(text)
	return (text:upper():gsub(".", "%0 "):sub(1, -2))
end

local function ShowHint()
	hintTimer = HINT_TIME
end

-- Click or Esc: the scene's own handler (AFK closes for good), otherwise pause.
local function Dismiss()
	if dismiss then
		dismiss(current)
	else
		C.Pause(current)
	end
end

local function UpdateHint(contentAlpha, dt)
	hintFrame:SetAlpha(contentAlpha)
	hintTimer = math.max(hintTimer - dt, 0)
	local alpha = hint:GetAlpha()
	if hintTimer > 0 then
		hint:SetAlpha(math.min(alpha + dt / HINT_FADE, 1))
	else
		hint:SetAlpha(math.max(alpha - dt / HINT_FADE, 0))
	end
end

local function LetterboxOnUpdate(self, elapsed)
	if active and passthrough and IsMouseButtonDown() then
		Dismiss() -- the click itself went through to the game
		return
	end
	if active then
		local x, y = GetCursorPosition()
		if cursorX and (x ~= cursorX or y ~= cursorY) then
			ShowHint()
		end
		cursorX, cursorY = x, y
	end
	if active and hidUI then
		sinceWorldSweep = sinceWorldSweep + elapsed
		if sinceWorldSweep >= WORLD_SWEEP then
			sinceWorldSweep = 0
			HideWorldFrameAddons() -- again and again: addons may re-show their frames
		end
	end
	local step = elapsed / LETTERBOX_TIME
	if target > progress then
		progress = math.min(progress + step, 1)
	else
		progress = math.max(progress - step, 0)
	end
	local e = Ease(progress)
	-- An even number of whole pixels: the scenes place their text from the band's center and edges.
	local pixel = PixelUtil.GetPixelToUIUnitFactor() / self:GetEffectiveScale()
	local h = 2 * math.floor(self:GetHeight() * LETTERBOX_FRACTION / pixel / 2 + 0.5) * pixel
	-- Only on change: re-setting it every frame re-lays out the title card anchored to the band, and its
	-- sub-pixel edges then round differently frame to frame (1px jitter).
	if h ~= self.bandHeight then
		self.bandHeight = h
		self.top:SetHeight(h)
		self.bottom:SetHeight(h)
	end
	-- The bands keep their height and slide in from off screen, soft edge included (0 once fully in).
	local offset = (1 - e) * (h + LETTERBOX_EDGE)
	if offset ~= self.bandOffset then
		self.bandOffset = offset
		self.top:SetPoint("TOPLEFT", 0, offset)
		self.top:SetPoint("TOPRIGHT", 0, offset)
		self.bottom:SetPoint("BOTTOMLEFT", 0, -offset)
		self.bottom:SetPoint("BOTTOMRIGHT", 0, -offset)
	end
	local w = self:GetWidth() * VIGNETTE_WIDTH
	self.vignetteLeft:SetWidth(w)
	self.vignetteRight:SetWidth(w)
	self.vignette:SetAlpha(e)
	-- Scene contents appear in the second half of the slide, the showcase a little after.
	local contentAlpha = math.max((e - 0.5) * 2, 0)
	if scene then
		scene.Update(contentAlpha, elapsed)
	end
	UpdateHint(contentAlpha, elapsed)
	if showcaseCreated then
		ns.Showcase_Update(math.max((e - 0.7) / 0.3, 0), elapsed)
	end
	if progress == 0 and target == 0 then
		self:Hide()
	end
end

local function CreateEdge(band, below)
	local edge = letterbox:CreateTexture(nil, "ARTWORK")
	edge:SetColorTexture(1, 1, 1, 1)
	edge:SetHeight(LETTERBOX_EDGE)
	local black, clear = CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0)
	if below then
		edge:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
		edge:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
		edge:SetGradient("VERTICAL", clear, black)
	else
		edge:SetPoint("BOTTOMLEFT", band, "TOPLEFT")
		edge:SetPoint("BOTTOMRIGHT", band, "TOPRIGHT")
		edge:SetGradient("VERTICAL", black, clear)
	end
	return edge
end

local function CreateVignette(side)
	local tex = letterbox.vignette:CreateTexture(nil, "BACKGROUND")
	tex:SetColorTexture(1, 1, 1, 1)
	tex:SetPoint("TOP" .. side)
	tex:SetPoint("BOTTOM" .. side)
	local dark, clear = CreateColor(0, 0, 0, VIGNETTE_ALPHA), CreateColor(0, 0, 0, 0)
	if side == "LEFT" then
		tex:SetGradient("HORIZONTAL", dark, clear)
	else
		tex:SetGradient("HORIZONTAL", clear, dark)
	end
	return tex
end

-- Put the zone music volume back, unless the user changed it themselves in the meantime.
function C.RestoreMusicVolume()
	local backup = ns.db.cinematic.musicVolumeBackup
	if not backup then
		return
	end
	if tonumber(C_CVar.GetCVar("Sound_MusicVolume")) == 0 then
		C_CVar.SetCVar("Sound_MusicVolume", backup)
	end
	ns.db.cinematic.musicVolumeBackup = nil
end

-- Music: an expansion main theme on the Master channel, with the zone music volume at 0 meanwhile.
-- The handle lives on the state so a /reload doesn't double it; the volume backup lives in
-- TomteDB.cinematic so it is restored even if the state is never resumed.
local function StartMusic(state, trackIndex)
	if state.musicStarted then
		return
	end
	state.musicStarted = true
	local track = ns.MUSIC_TRACKS[trackIndex] or ns.MUSIC_TRACKS[1]
	local kit = SOUNDKIT[track.kit]
	if not kit then
		return
	end
	local willPlay, handle = PlaySound(kit, "Master")
	state.musicHandle = handle
	if willPlay and not ns.db.cinematic.musicVolumeBackup then
		ns.db.cinematic.musicVolumeBackup = C_CVar.GetCVar("Sound_MusicVolume")
		C_CVar.SetCVar("Sound_MusicVolume", "0")
	end
end

local function StopMusic(state)
	if state.musicHandle then
		StopSound(state.musicHandle, MUSIC_FADE_MS)
	end
	state.musicHandle, state.musicStarted = nil, nil
	C.RestoreMusicVolume()
end

local function CreateLetterbox()
	letterbox = CreateFrame("Frame", nil, WorldFrame)
	ns.ownFrames[letterbox] = true
	letterbox:SetAllPoints(WorldFrame)
	letterbox:SetFrameStrata("FULLSCREEN")
	letterbox:Hide()

	-- Faded as a frame: alpha set on the gradient textures themselves is ignored (they'd pop out at the end).
	letterbox.vignette = CreateFrame("Frame", nil, letterbox)
	letterbox.vignette:SetAllPoints(letterbox)
	letterbox.vignetteLeft = CreateVignette("LEFT")
	letterbox.vignetteRight = CreateVignette("RIGHT")
	letterbox.top = letterbox:CreateTexture(nil, "ARTWORK")
	letterbox.top:SetColorTexture(0, 0, 0, 1)
	letterbox.top:SetPoint("TOPLEFT")
	letterbox.top:SetPoint("TOPRIGHT")
	letterbox.bottom = letterbox:CreateTexture(nil, "ARTWORK")
	letterbox.bottom:SetColorTexture(0, 0, 0, 1)
	letterbox.bottom:SetPoint("BOTTOMLEFT")
	letterbox.bottom:SetPoint("BOTTOMRIGHT")
	letterbox.topEdge = CreateEdge(letterbox.top, true)
	letterbox.bottomEdge = CreateEdge(letterbox.bottom, false)

	-- Top band, right: how to get control back. Shown briefly at the start and when the mouse moves.
	hintFrame = CreateFrame("Frame", nil, letterbox)
	hintFrame:SetAllPoints(letterbox)
	hintFrame:SetFrameLevel(letterbox:GetFrameLevel() + 10)
	hint = hintFrame:CreateFontString(nil, "OVERLAY")
	hint:SetFont(STANDARD_TEXT_FONT, 11, "")
	hint:SetTextColor(GREY[1], GREY[2], GREY[3])
	hint:SetShadowOffset(1, -1)
	hint:SetPoint("RIGHT", letterbox.top, "RIGHT", -HINT_PAD, 0)
	hint:SetAlpha(0)

	letterbox:SetScript("OnUpdate", LetterboxOnUpdate)

	-- Input is only enabled while active: clicks/drags and the wheel never reach the camera. A passthrough
	-- cinematic leaves the mouse alone (clicks are seen in OnUpdate) and lets keys through, and any of them
	-- dismisses it.
	letterbox:SetScript("OnMouseDown", Dismiss)
	letterbox:SetScript("OnMouseWheel", function() end)
	letterbox:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			return
		end
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false) -- no game menu
			Dismiss()
		else
			self:SetPropagateKeyboardInput(true)
			if passthrough then
				Dismiss()
			end
		end
	end)
end

local function ShowShowcase(enabled)
	if enabled and not showcaseCreated then
		ns.Showcase_Create(letterbox)
		showcaseCreated = true
	end
	if showcaseCreated then
		ns.Showcase_Show(enabled)
	end
end

function C.IsActive()
	return active
end

function C.IsOwner(state)
	return active and state ~= nil and current == state
end

function C.Enter(newScene, state, opts)
	if active or InCombatLockdown() then
		return
	end
	if not letterbox then
		CreateLetterbox()
	end
	if not createdScenes[newScene] then
		createdScenes[newScene] = true
		newScene.frame = CreateFrame("Frame", nil, letterbox)
		newScene.frame:SetAllPoints(letterbox)
		newScene.Create(newScene.frame, letterbox)
	end
	for s in pairs(createdScenes) do
		s.frame:SetShown(s == newScene)
	end
	scene = newScene
	dismiss = opts.onDismiss
	hint:SetText(Spaced(opts.hint or "Click or Esc to pause"))
	active = true
	current = state
	state.resumeAt = nil
	state.resumeDelay = opts.resumeDelay
	watched = nil
	watcher:Hide()
	state.cinematic = true -- persisted so a /reload can clean up
	if not opts.skipCamera then
		local zoomOut = TARGET_ZOOM - GetCameraZoom()
		if zoomOut > 0 then
			CameraZoomOut(zoomOut)
			state.zoomedOut = (state.zoomedOut or 0) + zoomOut
		end
	end
	state.orbitFactor = nil
	if opts.orbit and not opts.skipCamera then
		MoveViewLeftStart(ORBIT_SPEED)
		state.orbitFactor = 1
	end
	if not opts.skipCamera then
		LimitPitch(state)
	end
	if opts.music then
		StartMusic(state, opts.music)
	end
	scene.Begin(state)
	-- Same on-screen size as normal UI text, whatever the UI scale.
	hintFrame:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	target = 1
	cursorX, cursorY = nil, nil
	passthrough = opts.passthrough
	letterbox:EnableMouse(not passthrough)
	letterbox:EnableMouseWheel(not passthrough)
	letterbox:EnableKeyboard(true)
	letterbox:SetPropagateKeyboardInput(true)
	ShowHint()
	letterbox:Show()
	ShowShowcase(opts.showcase) -- after the letterbox is shown, so the model renders
	HideUI()
	UpdateEvents()
end

-- Called on the owner's tick while active: an orbitFactor below 1 eases the orbit out and the zoom back in
-- (the arrival shot). Scenes without an arrival shot pass 1.
function C.Update(state, orbitFactor)
	if not C.IsOwner(state) then
		return
	end
	if orbitFactor < 1 and state.zoomedOut then
		RestoreZoom(state) -- the engine animates the zoom, so this eases in on its own
	end
	if not state.orbitFactor then
		return -- orbit disabled
	end
	if math.abs(orbitFactor - state.orbitFactor) >= 0.05 or (orbitFactor == 0 and state.orbitFactor ~= 0) then
		state.orbitFactor = orbitFactor
		if orbitFactor > 0 then
			MoveViewLeftStart(ORBIT_SPEED * orbitFactor)
		else
			MoveViewLeftStop()
		end
	end
end

-- Also used on a stale state after /reload (not active, but the camera may still be orbiting/zoomed).
function C.Exit(state)
	if state and state.cinematic then
		MoveViewLeftStop()
		RestoreZoom(state)
		RestorePitch(state)
		StopMusic(state)
		state.cinematic = nil
		state.orbitFactor = nil
	end
	if not active or (state and state ~= current) then
		return
	end
	active = false
	current = nil
	dismiss = nil
	passthrough = nil
	target = 0
	if scene.End then
		scene.End()
	end
	letterbox:EnableMouse(false)
	letterbox:EnableMouseWheel(false)
	letterbox:EnableKeyboard(false)
	ShowWorldFrameAddons()
	ShowUI()
	UpdateEvents()
end

-- The state is finished (flight landed, module turned off): exit and stop watching it.
function C.Release(state)
	C.Exit(state)
	state.resumeAt = nil
	if watched == state then
		watched = nil
		watcher:Hide()
	end
end

-- Click/Esc (or combat): leave the cinematic and come back once the player is idle again.
function C.Pause(state)
	if not state then
		return
	end
	state.resumeAt = GetTime() + (state.resumeDelay or DEFAULT_RESUME)
	C.Exit(state)
	C.Watch(state)
end

-- Tops up state.resumeAt while the player is busy. Idempotent: owners call it every tick while paused,
-- which also restarts the watching after a /reload.
function C.Watch(state)
	if watched == state and watcher:IsShown() then
		return
	end
	if not watcher.keyboardReady and not InCombatLockdown() then
		-- Sees every key press but lets it through.
		watcher:EnableKeyboard(true)
		watcher:SetPropagateKeyboardInput(true)
		watcher.keyboardReady = true
	end
	watched = state
	sinceWatch = 0
	watcher:Show()
end

watcher:Hide()
watcher:SetScript("OnUpdate", WatcherOnUpdate)
watcher:SetScript("OnKeyDown", TopUp)

local function RestoreOrphanedMusic()
	if not active and not ns.AnyCinematicState() then
		C.RestoreMusicVolume()
	end
end

events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		-- Next frame, after the modules' own handlers had a chance to resume their state: a music-volume
		-- backup that no live state owns is left over from an interrupted cinematic.
		C_Timer.After(0, RestoreOrphanedMusic)
		return
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Handlers for this event still run before combat lockdown starts: last chance to show a hidden UI.
		-- Combat pauses the cinematic; it can come back once combat is over and the player is idle again.
		if active then
			C.Pause(current)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if showUIAfterCombat then
			ShowUI()
		end
	end
	UpdateEvents()
end)
events:RegisterEvent("PLAYER_ENTERING_WORLD")
