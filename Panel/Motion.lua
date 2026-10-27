local addonName, ns = ...

-- Motion: the shared animation kit, so every widget eases, pops and fades with the same timing. Tweens run on one
-- driver frame whose OnUpdate is set only while a tween is running; the rest are AnimationGroups made once per region.
-- Fades for content that arrives after a read (UI.FadeIn, UI.ListArrivals) are in Controls.lua.
-- The Tomte window's Motion setting (ns.Window_Motion) scales it all: "full", "subtle" (eases and fades, no pops,
-- shakes, shines, bursts or overshoot) or "off" (everything lands at once). Its Sounds setting picks which UI.Sound
-- kinds play.

local HOVER_SECONDS = 0.12 -- border and fill easing toward the hover color and back
local SLIDE_SECONDS = 0.18 -- UI.SlideTo: a selection marker gliding to the newly selected row
local PRESS_SECONDS = 0.25 -- a pressed button's bright border easing back
local POP_SECONDS = 0.12 -- each half of UI.Pop
local FLASH_SECONDS = 0.45 -- a font string's accent flash in UI.Pop
local SHAKE_STEP = 0.04 -- one swing of UI.Shake
local SHAKE_PIXELS = 4
local SHINE_SECONDS = 0.7
local SHINE_SHARE = 0.35 -- the shine's width as a share of the frame's
local BURST_SECONDS = 0.6
local BURST_SPARKS = 10
local BURST_REACH = 34 -- how far the sparks fly, in UI units
local COUNT_SECONDS = 0.6 -- UI.CountTo's run from the old number to the new
local DELTA_SECONDS = 1.4 -- UI.Delta's float up and fade
local DELTA_RISE = 14
local APPEAR_SECONDS = 0.18
local DISAPPEAR_SECONDS = 0.12
local ENTER_SECONDS = 0.3 -- UI.EnterUp's fade and rise
local ENTER_RISE = 8
local ENTER_CHAIN = 6 -- how far UI.EnterUp follows a chain of anchors looking for a frame that is rising already
local STAGGER_STEP = 0.035 -- seconds between two cards in UI.EnterUpRows
local STAGGER_MAX = 10 -- only this many are spread out; the rest come with the last of them
local MIN_ANIM_SECONDS = 0.001

local UI = ns.UI

-- Motion and sound settings -----------------------------------------------------------------------------------------

-- "full", "subtle" or "off" (Tomte window settings; full until the window module has loaded).
function UI.MotionLevel()
	return ns.Window_Motion and ns.Window_Motion() or "full"
end

local function Full()
	return UI.MotionLevel() == "full"
end
UI.MotionFull = Full

-- What each kind of interface sound plays, and whether it's one of the few that still play on "Only important".
local SOUNDS = {
	open = { "IG_QUEST_LOG_OPEN" },
	close = { "IG_QUEST_LOG_CLOSE" },
	nav = { "IG_CHARACTER_INFO_TAB" },
	on = { "IG_MAINMENU_OPTION_CHECKBOX_ON" },
	off = { "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
	pick = { "IG_MAINMENU_OPTION_CHECKBOX_ON" }, -- a choice in a list or segments
	drop = { "UI_CURSOR_DROP_OBJECT" }, -- a widget let go in Edit Mode
	tick = { "U_CHAT_SCROLL_BUTTON" }, -- an arrow-key nudge
	confirm = { "IG_MAINMENU_OPTION", important = true },
	error = { "IG_PLAYER_INVITE_DECLINE", important = true },
	reward = { "UI_EPICLOOT_TOAST", important = true },
}

-- Plays the interface sound for kind (a SOUNDS key) if the Sounds setting lets it.
function UI.Sound(kind)
	local sound = SOUNDS[kind]
	local level = ns.Window_Sounds and ns.Window_Sounds() or "all"
	if not sound or level == "off" or (level == "important" and not sound.important) then
		return
	end
	local id = SOUNDKIT[sound[1]]
	if id then
		PlaySound(id)
	end
end

-- Easing ------------------------------------------------------------------------------------------------------------

function UI.EaseOut(p)
	local q = 1 - p
	return 1 - q * q * q
end

-- Overshoots a little past 1 and settles back (plain UI.EaseOut below full motion).
function UI.EaseOutBack(p)
	if not Full() then
		return UI.EaseOut(p)
	end
	local c = 1.7
	local q = p - 1
	return 1 + (c + 1) * q * q * q + c * q * q
end

local function Lerp(a, b, t)
	return a + (b - a) * t
end
UI.Lerp = Lerp

-- Tweens ------------------------------------------------------------------------------------------------------------

local tweens = {} -- [owner] = { [key] = { clock, seconds, delay, step, done, ease } }
local running = 0
local driver = CreateFrame("Frame")

local walkOwner, walkKey, walkTween = {}, {}, {} -- Drive's copy of what runs this frame, reused

local function Drive(_, elapsed)
	-- The walk goes over a copy of who and what is running: a step may start another tween (a scroll's step fades its
	-- edges), and Lua leaves pairs undefined when a table takes new keys mid-walk. A tween started or replaced during
	-- the walk runs from the next frame. Done callbacks run after the walk, the same way.
	local finished
	local n = 0
	for owner, list in pairs(tweens) do
		for key, t in pairs(list) do
			n = n + 1
			walkOwner[n], walkKey[n], walkTween[n] = owner, key, t
		end
	end
	for i = 1, n do
		local owner, key, t = walkOwner[i], walkKey[i], walkTween[i]
		walkOwner[i], walkKey[i], walkTween[i] = nil, nil, nil -- nothing kept alive past this frame
		local list = tweens[owner]
		if list and list[key] == t then -- not replaced or stopped by an earlier step this frame
			if t.delay > 0 then
				t.delay = t.delay - elapsed
			else
				t.clock = t.clock + elapsed
				local p = math.min(t.clock / t.seconds, 1)
				t.step(t.ease(p), p)
				if p >= 1 and list[key] == t then -- its own step may have replaced it
					list[key] = nil
					running = running - 1
					if t.done then
						finished = finished or {}
						finished[#finished + 1] = t.done
					end
				end
			end
		end
	end
	for owner, list in pairs(tweens) do
		if next(list) == nil then
			tweens[owner] = nil
		end
	end
	if finished then
		for _, done in ipairs(finished) do
			done()
		end
	end
	if running <= 0 then
		running = 0
		driver:SetScript("OnUpdate", nil)
	end
end

-- Runs step(eased, raw) every frame for seconds (eased by ease, UI.EaseOut by default), then done(). A new tween with
-- the same owner and key replaces the running one (its done doesn't run). delay holds it before it starts.
function UI.Tween(owner, key, seconds, step, done, ease, delay)
	if UI.MotionLevel() == "off" then
		UI.TweenStop(owner, key)
		step(1, 1)
		if done then
			done()
		end
		return
	end
	local list = tweens[owner]
	if not list then
		list = {}
		tweens[owner] = list
	end
	if not list[key] then
		running = running + 1
	end
	list[key] = { clock = 0, seconds = math.max(seconds, MIN_ANIM_SECONDS), delay = delay or 0, step = step,
		done = done, ease = ease or UI.EaseOut }
	driver:SetScript("OnUpdate", Drive)
end

-- Stops a tween where it is (its done doesn't run).
function UI.TweenStop(owner, key)
	local list = tweens[owner]
	if list and list[key] then
		list[key] = nil
		running = running - 1
	end
end

-- Borders and fills ---------------------------------------------------------------------------------------------------

-- Eases a UI.Border (or panel rule) from its current color to role at alpha.
function UI.BorderTo(frame, role, alpha, seconds)
	local r, g, b, a = UI.RGBA(role or "frame", alpha)
	a = a or 1
	local from = frame.borderColor
	if not from or not frame:IsVisible() then
		UI.SetBorderColor(frame, role, alpha)
		return
	end
	local fr, fg, fb, fa = from[1], from[2], from[3], from[4]
	UI.Tween(frame, "border", seconds or HOVER_SECONDS, function(t)
		local cr, cg, cb, ca = Lerp(fr, r, t), Lerp(fg, g, t), Lerp(fb, b, t), Lerp(fa, a, t)
		for _, edge in ipairs(frame.borderEdges) do
			edge:SetColorTexture(cr, cg, cb, ca)
		end
		frame.borderColor = { cr, cg, cb, ca }
	end)
end

-- Eases a region's alpha to target.
function UI.AlphaTo(region, target, seconds, done)
	local from = region:GetAlpha()
	UI.Tween(region, "alpha", seconds or HOVER_SECONDS, function(t)
		region:SetAlpha(Lerp(from, target, t))
	end, done)
end

-- A hover wash over a button: a texture in the hover color that eases in while the mouse is over it.
function UI.HoverWash(frame, layer)
	local wash = frame:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
	wash:SetAllPoints()
	wash:SetColorTexture(UI.Color("hover"))
	wash:SetAlpha(0)
	frame.hoverWash = wash
	return wash
end

-- Hovered kit buttons whose wash is up. Many callers replace a button's OnLeave with their own (SetScript drops the
-- kit's), so the wash doesn't wait to be told: a watcher, running only while one is up, fades it once the mouse is
-- off the button or the button hides.
local washed = {}
local washWatch = CreateFrame("Frame")

local function WashOff(frame)
	washed[frame] = nil
	UI.AlphaTo(frame.hoverWash, 0, HOVER_SECONDS * 2)
end

local function WatchWashes()
	for frame in pairs(washed) do
		if not frame:IsVisible() or not frame:IsMouseOver() then
			WashOff(frame)
		end
	end
	if next(washed) == nil then
		washWatch:SetScript("OnUpdate", nil)
	end
end

-- Hover in or out on a kit button: border to accent and the wash in, or back to role/alpha.
function UI.HoverOn(frame)
	UI.BorderTo(frame, "accent", 1)
	if frame.hoverWash then
		UI.AlphaTo(frame.hoverWash, 1)
		washed[frame] = true
		washWatch:SetScript("OnUpdate", WatchWashes)
	end
end

function UI.HoverOff(frame, role, alpha)
	UI.BorderTo(frame, role or "frame", alpha)
	if frame.hoverWash then
		WashOff(frame)
	end
end

-- A list row's highlight texture eased in (on) or out, like UI.HoverOn's wash; it lingers a little on the way out.
-- A hidden one, or instant, is set at once (a list being redrawn).
function UI.WashTo(region, on, instant)
	local target = on and 1 or 0
	if instant or not region:IsVisible() then
		UI.TweenStop(region, "alpha")
		region:SetAlpha(target)
		return
	end
	UI.AlphaTo(region, target, on and HOVER_SECONDS or HOVER_SECONDS * 2)
end

-- Moves a selection marker (a region anchored by its TOPLEFT to its parent) to x, -y with height, easing from where
-- it's drawn now. It jumps instead when it wasn't shown, isn't visible, or instant (another list was drawn).
function UI.SlideTo(region, x, y, height, instant)
	local wasShown = region:IsShown() and region.slideY ~= nil
	region:Show()
	local function Place(px, py, ph)
		region:SetPoint("TOPLEFT", region:GetParent(), "TOPLEFT", px, -py)
		region:SetHeight(ph)
		region.slideX, region.slideY, region.slideH = px, py, ph
	end
	if instant or not wasShown or not region:IsVisible() then
		UI.TweenStop(region, "slide")
		Place(x, y, height)
		return
	end
	local fx, fy, fh = region.slideX, region.slideY, region.slideH
	if fx == x and fy == y and fh == height then
		UI.TweenStop(region, "slide")
		return
	end
	UI.Tween(region, "slide", SLIDE_SECONDS, function(t)
		Place(Lerp(fx, x, t), Lerp(fy, y, t), Lerp(fh, height, t))
	end)
end

-- One-shot effects ----------------------------------------------------------------------------------------------------

local function ScaleGroup(region, field)
	local group = region[field]
	if not group then
		group = region:CreateAnimationGroup()
		group.out = group:CreateAnimation("Scale")
		group.out:SetOrder(1)
		group.out:SetOrigin("CENTER", 0, 0)
		group.out:SetSmoothing("OUT")
		group.back = group:CreateAnimation("Scale")
		group.back:SetOrder(2)
		group.back:SetOrigin("CENTER", 0, 0)
		group.back:SetSmoothing("IN_OUT")
		region[field] = group
	end
	group:Stop()
	return group
end

-- A button's press: its border flashes bright and eases back to the hover accent (the label's 1 px nudge is the
-- button's own). No scaling: a scaled label is redrawn at every size in between and jumped (measured in game).
function UI.Press(frame)
	if not frame.borderEdges or UI.MotionLevel() == "off" then
		return
	end
	UI.SetBorderColor(frame, "heading", 1)
	UI.BorderTo(frame, "accent", 1, PRESS_SECONDS)
end

-- Text flashes to the accent color and eases back to its own instead: a scaled font string is redrawn at every size
-- in between, which steps and jitters (measured in game).
local function FlashText(fs)
	if not fs.flashBase then
		fs.flashBase = { fs:GetTextColor() }
	end
	local base = fs.flashBase
	local r, g, b = UI.Color("accent")
	UI.Tween(fs, "flash", FLASH_SECONDS, function(t)
		fs:SetTextColor(Lerp(r, base[1], t), Lerp(g, base[2], t), Lerp(b, base[3], t), base[4])
	end, function()
		fs.flashBase = nil
	end, ns.Smoothstep)
end

-- Swells a frame or region by amount (default 0.15) and settles it back: a value that changed, an icon that arrived.
-- A font string flashes instead (FlashText).
function UI.Pop(region, amount)
	if region:IsObjectType("FontString") then
		if UI.MotionLevel() ~= "off" then
			FlashText(region)
		end
		return
	end
	if not Full() then
		return
	end
	local s = 1 + (amount or 0.15)
	local group = ScaleGroup(region, "popAnim")
	group.out:SetDuration(POP_SECONDS)
	group.out:SetScaleFrom(1, 1)
	group.out:SetScaleTo(s, s)
	group.back:SetDuration(POP_SECONDS * 1.5)
	group.back:SetScaleFrom(1, 1)
	group.back:SetScaleTo(1 / s, 1 / s)
	group:Play()
end

-- A short sideways shake: something can't be done.
function UI.Shake(frame)
	UI.Sound("error")
	if not Full() then
		return
	end
	local group = frame.shakeAnim
	if not group then
		group = frame:CreateAnimationGroup()
		local swings = { 1, -2, 2, -2, 1 }
		for i, swing in ipairs(swings) do
			local a = group:CreateAnimation("Translation")
			a:SetOrder(i)
			a:SetDuration(SHAKE_STEP)
			a:SetOffset(swing * SHAKE_PIXELS, 0)
		end
		frame.shakeAnim = group
	end
	group:Stop()
	group:Play()
end

-- A band of light that sweeps across frame once (accent tinted), clipped to it.
function UI.Shine(frame)
	if not Full() then
		return
	end
	local shine = frame.shine
	if not shine then
		shine = CreateFrame("Frame", nil, frame)
		shine:SetAllPoints()
		shine:SetClipsChildren(true)
		shine.band = shine:CreateTexture(nil, "OVERLAY")
		shine.band:SetColorTexture(1, 1, 1, 1)
		shine.band:SetBlendMode("ADD")
		shine.band:SetPoint("TOPRIGHT", shine, "TOPLEFT")
		shine.band:SetPoint("BOTTOMRIGHT", shine, "BOTTOMLEFT")
		shine.anim = shine.band:CreateAnimationGroup()
		shine.move = shine.anim:CreateAnimation("Translation")
		shine.move:SetDuration(SHINE_SECONDS)
		shine.move:SetSmoothing("IN_OUT")
		shine.anim:SetScript("OnFinished", function()
			shine:Hide()
		end)
		frame.shine = shine
	end
	local w = frame:GetWidth()
	if not (w and w > 1) then
		return
	end
	local clear, bright = UI.ColorObject("accent", 0), UI.ColorObject("accent", 0.28)
	local band = w * SHINE_SHARE
	shine.band:SetWidth(band)
	-- Two halves would need two textures; a gradient from clear to bright reads as a leading edge of light.
	shine.band:SetGradient("HORIZONTAL", clear, bright)
	shine.move:SetOffset(w + band, 0)
	shine:SetFrameLevel(frame:GetFrameLevel() + 10)
	shine:Show()
	shine.anim:Stop()
	shine.anim:Play()
end

-- A burst on a frame: a ring of light and sparks flying out from its center (or from region's center). For finishing
-- something: a weekly done, a check passed, something learned.
function UI.Burst(frame, region, silent)
	if not silent then
		UI.Sound("reward")
	end
	if not Full() then
		return
	end
	local burst = frame.burst
	if not burst then
		burst = CreateFrame("Frame", nil, frame)
		burst:SetSize(1, 1)
		burst.ring = burst:CreateTexture(nil, "OVERLAY")
		burst.ring:SetTexture(ns.Theme.media.glow)
		burst.ring:SetBlendMode("ADD")
		burst.ring:SetSize(48, 48)
		burst.ring:SetPoint("CENTER")
		burst.ring.anim = burst.ring:CreateAnimationGroup()
		local grow = burst.ring.anim:CreateAnimation("Scale")
		grow:SetScaleFrom(0.3, 0.3)
		grow:SetScaleTo(1.8, 1.8)
		grow:SetDuration(BURST_SECONDS)
		grow:SetSmoothing("OUT")
		local fade = burst.ring.anim:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.9)
		fade:SetToAlpha(0)
		fade:SetDuration(BURST_SECONDS)
		fade:SetSmoothing("IN")
		burst.ring.anim:SetScript("OnFinished", function()
			burst.ring:SetAlpha(0)
		end)
		burst.sparks = {}
		for i = 1, BURST_SPARKS do
			local spark = burst:CreateTexture(nil, "OVERLAY")
			spark:SetSize(3, 3)
			spark:SetPoint("CENTER")
			spark:SetBlendMode("ADD")
			spark:SetAlpha(0)
			local angle = (i - 1) / BURST_SPARKS * 2 * math.pi + 0.3
			local reach = BURST_REACH * (0.7 + 0.3 * ((i % 3) / 2))
			local group = spark:CreateAnimationGroup()
			local fly = group:CreateAnimation("Translation")
			fly:SetOffset(math.cos(angle) * reach, math.sin(angle) * reach)
			fly:SetDuration(BURST_SECONDS)
			fly:SetSmoothing("OUT")
			local dim = group:CreateAnimation("Alpha")
			dim:SetFromAlpha(1)
			dim:SetToAlpha(0)
			dim:SetDuration(BURST_SECONDS)
			dim:SetSmoothing("IN")
			group:SetScript("OnFinished", function()
				spark:SetAlpha(0)
			end)
			spark.anim = group
			burst.sparks[i] = spark
		end
		frame.burst = burst
	end
	burst:ClearAllPoints()
	burst:SetPoint("CENTER", region or frame)
	burst:SetFrameLevel(frame:GetFrameLevel() + 20)
	burst.ring:SetVertexColor(UI.Color("accent"))
	burst.ring.anim:Stop()
	burst.ring.anim:Play()
	local r, g, b = UI.Color("accent")
	for _, spark in ipairs(burst.sparks) do
		spark:SetColorTexture(r, g, b, 1)
		spark.anim:Stop()
		spark.anim:Play()
	end
end

-- Numbers -------------------------------------------------------------------------------------------------------------

-- Shows value on fs through format (ns.Thousands by default), running up or down from the number it showed last.
-- The first value (or a hidden fs) shows at once. Secret or non-number values are set as they are.
function UI.CountTo(fs, value, format, seconds)
	format = format or ns.Thousands
	if type(value) ~= "number" or ns.IsSecret(value) then
		UI.TweenStop(fs, "count")
		fs.countValue = nil
		fs:SetText(value ~= nil and format(value) or "")
		return
	end
	local from = fs.countValue
	fs.countValue = value
	if from == nil or from == value or not fs:IsVisible() then
		UI.TweenStop(fs, "count")
		fs:SetText(format(value))
		return
	end
	UI.Tween(fs, "count", seconds or COUNT_SECONDS, function(t)
		fs:SetText(format(math.floor(Lerp(from, value, t) + 0.5)))
	end)
end

-- Floats text (like "+1,234g") up from the right of anchor and fades it: a gain (role "success") or loss ("danger").
function UI.Delta(anchor, text, role)
	if UI.MotionLevel() == "off" then
		return
	end
	local parent = anchor:GetParent()
	local pool = parent.deltaPool
	if not pool then
		pool = {}
		parent.deltaPool = pool
	end
	local fs
	for _, f in ipairs(pool) do
		if not f.anim:IsPlaying() then
			fs = f
			break
		end
	end
	if not fs then
		fs = UI.Text(parent, 11, role or "success", "number")
		fs.anim = fs:CreateAnimationGroup()
		local rise = fs.anim:CreateAnimation("Translation")
		rise:SetOffset(0, DELTA_RISE)
		rise:SetDuration(DELTA_SECONDS)
		rise:SetSmoothing("OUT")
		local fade = fs.anim:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetStartDelay(DELTA_SECONDS * 0.4)
		fade:SetDuration(DELTA_SECONDS * 0.6)
		fs.anim:SetScript("OnFinished", function()
			fs:Hide()
		end)
		pool[#pool + 1] = fs
	end
	UI.SetTextRole(fs, role or "success")
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
	fs:SetText(text)
	fs:Show()
	fs.anim:Stop()
	fs.anim:Play()
end

-- Eases a UI.Bar to value instead of jumping. The first value shows at once.
function UI.BarTo(bar, value, seconds)
	value = math.min(math.max(value or 0, 0), 1)
	if not bar.shownOnce or not bar:IsVisible() then
		bar.shownOnce = true
		UI.TweenStop(bar, "bar")
		bar:SetValue(value)
		return
	end
	local from = bar.value
	UI.Tween(bar, "bar", seconds or COUNT_SECONDS, function(t)
		bar:SetValue(Lerp(from, value, t))
	end, function()
		if value >= 1 and from < 1 then
			UI.Shine(bar)
		end
	end)
end

-- Windows and pages ---------------------------------------------------------------------------------------------------

-- Models (PlayerModel, ModelScene) ignore their parents' alpha animations, so a window's fade would leave the character
-- standing at full strength. Frames holding one register it here, and fades set its model alpha by hand.
local models = setmetatable({}, { __mode = "k" })

function UI.FadeModel(model)
	models[model] = true
end

local function Inside(region, frame)
	local parent = region:GetParent()
	while parent do
		if parent == frame then
			return true
		end
		parent = parent:GetParent()
	end
	return false
end

local function ModelAlpha(frame, alpha)
	for model in pairs(models) do
		if model:IsShown() and Inside(model, frame) then
			model:SetModelAlpha(alpha)
		end
	end
end

-- Fades frame in from nothing (call right after Show). Alpha only: scaling a window full of text redraws every font
-- string at every size in between, which stuttered and made text step (measured in game).
function UI.Appear(frame)
	frame.disappearing = nil
	local from = frame:IsVisible() and frame:GetAlpha() < 1 and frame:GetAlpha() or 0
	frame:SetAlpha(from)
	ModelAlpha(frame, from)
	UI.Tween(frame, "fade", APPEAR_SECONDS * (1 - from), function(t)
		local a = Lerp(from, 1, t)
		frame:SetAlpha(a)
		ModelAlpha(frame, a)
	end)
end

-- Fades frame out, then hides it (and puts its alpha back for the next show). UI.Appear while it fades brings it back.
function UI.Disappear(frame)
	if not frame:IsShown() or frame.disappearing then
		return
	end
	frame.disappearing = true
	local from = frame:GetAlpha()
	UI.Tween(frame, "fade", DISAPPEAR_SECONDS, function(t)
		local a = Lerp(from, 0, t)
		frame:SetAlpha(a)
		ModelAlpha(frame, a)
	end, function()
		frame.disappearing = nil
		frame:Hide()
		frame:SetAlpha(1)
		ModelAlpha(frame, 1)
	end, ns.Smoothstep)
end

-- Whether frame is fading out (UI.Disappear): still shown, but on its way to hidden.
function UI.IsDisappearing(frame)
	return frame.disappearing == true
end

-- Fades frame (or a region) in while it rises a few pixels into place: a page or card that just opened. delay holds it
-- at nothing first. It moves the real anchors in whole screen pixels and puts them back at the end: a Translation
-- animation draws text at fractions of a pixel and it snapped a pixel at the end (measured in game), and models
-- inside didn't move with it at all. If something re-anchors the frame meanwhile, the rise stops where that put it.
local function PixelOffset(region, offset)
	local scaled = region.GetEffectiveScale and region or region:GetParent()
	return PixelUtil.GetNearestPixelSize(offset, scaled:GetEffectiveScale())
end

local function Shifted(region, points, dy)
	region:ClearAllPoints()
	for _, p in ipairs(points) do
		region:SetPoint(p[1], p[2], p[3], p[4], p[5] + dy)
	end
	region.enterY = select(5, region:GetPoint(1))
end

-- Whether region is anchored (directly or down a chain of anchors) to something that is rising already: it moves with
-- that, so shifting it too would add the two rises up.
local function FollowsRising(region, depth)
	if depth > ENTER_CHAIN then
		return false
	end
	for i = 1, region:GetNumPoints() do
		local relative = select(2, region:GetPoint(i))
		if relative and relative ~= region and (relative.enterPoints or (relative.GetNumPoints
			and FollowsRising(relative, depth + 1))) then
			return true
		end
	end
	return false
end

function UI.EnterUp(frame, delay)
	local points = frame.enterPoints
	if not points then
		-- Not rising already: what it ends at (nothing to move when it follows a rising frame: it only fades).
		points = {}
		if not FollowsRising(frame, 1) then
			for i = 1, frame:GetNumPoints() do
				points[i] = { frame:GetPoint(i) }
			end
		end
		frame.enterPoints = points
		frame.enterAlpha = frame:GetAlpha()
	end
	local target = frame.enterAlpha
	local function Done()
		frame.enterPoints, frame.enterAlpha, frame.enterY = nil, nil, nil
	end
	local function Step(t)
		if #points > 0 then
			if frame.enterY ~= nil and select(5, frame:GetPoint(1)) ~= frame.enterY then
				-- Laid out again by its owner: keep that, just finish the fade.
				points = {}
			else
				Shifted(frame, points, -PixelOffset(frame, ENTER_RISE * (1 - t)))
			end
		end
		frame:SetAlpha(target * t)
		ModelAlpha(frame, t)
	end
	Step(0)
	UI.Tween(frame, "enter", ENTER_SECONDS, Step, function()
		if #points > 0 and select(5, frame:GetPoint(1)) == frame.enterY then
			Shifted(frame, points, 0)
		end
		frame:SetAlpha(target)
		ModelAlpha(frame, 1)
		Done()
	end, nil, delay)
end

-- UI.EnterUp for frames[first..last], one after another. Only the first STAGGER_MAX are spread out.
function UI.EnterUpRows(frames, first, last)
	first, last = first or 1, last or #frames
	for i = first, last do
		UI.EnterUp(frames[i], math.min(i - first, STAGGER_MAX) * STAGGER_STEP)
	end
end
