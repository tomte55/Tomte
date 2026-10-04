local addonName, ns = ...

-- AFK Screen module: while the game flags you AFK, the cinematic engine shows the AFK scene (orbiting
-- camera, letterbox, character showcase, time away, clock, session stats, whispers received). Click or Esc
-- closes it and clears the AFK flag; a queue pop, ready check or invite closes it so the popup is visible.
-- Pure logic is in Data.lua. Nothing ticks while you're not AFK.

local TICK = 1 -- seconds between checks while AFK and the screen isn't up
local RESUME_DELAY = 20 -- combat paused the screen: back after this long idle
local MAX_WHISPERS = 20
local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_FLAGS_CHANGED" }
local AWAY_EVENTS = { -- only while AFK
	"CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
	"LFG_PROPOSAL_SHOW", "UPDATE_BATTLEFIELD_STATUS", "READY_CHECK", "PARTY_INVITE_REQUEST",
}
local SAMPLE_WHISPERS = {
	{ ago = 540, sender = "Thrall", class = "SHAMAN", text = "Raid tonight at 8, are you in?" },
	{ ago = 310, sender = "Jaina", class = "MAGE", text = "Left you a few Sunwell Shards in the mail. Don't spend them all at once." },
	{ ago = 75, sender = "Anduin", bn = true, text = "brb" },
}

local module
local away -- AFK state while flagged AFK or previewing (same table as ns.afkDB.current)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
local ticker = CreateFrame("Frame")
ticker:Hide()

-- true/false, or nil when the flag is a secret value (chat lockdown: instances, encounters, PvP matches).
local function IsAFK()
	local afk = UnitIsAFK("player")
	if issecretvalue and issecretvalue(afk) then
		return nil
	end
	return afk and true or false
end

local function Readable(...)
	return not canaccessallvalues or canaccessallvalues(...)
end

local function InChatLockdown()
	return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

local function SceneBlocked()
	return IsInInstance() or UnitOnTaxi("player") or InCombatLockdown()
		or (C_PetBattles and C_PetBattles.IsInBattle())
		or (InCinematic and InCinematic()) or (IsInCinematicScene and IsInCinematicScene())
		or (MovieFrame and MovieFrame:IsShown())
		or ns.Cinematic.IsActive()
end

local Dismiss -- forward: CinematicOptions hands it to the engine

local function CinematicOptions()
	local db = ns.afkDB
	return {
		orbit = db.orbit,
		showcase = db.showcase,
		resumeDelay = RESUME_DELAY,
		hint = "Click or Esc to return",
		onDismiss = Dismiss,
	}
end

-- Back from AFK (or the module turned off): undo everything and forget the state.
local function Finish()
	for _, event in ipairs(AWAY_EVENTS) do
		events:UnregisterEvent(event)
	end
	ticker:Hide()
	if away then
		ns.Cinematic.Release(away)
	end
	away = nil
	ns.afkDB.current = nil
end

local Tick

local function BeginAway(state)
	away = state
	ns.afkDB.current = state
	for _, event in ipairs(AWAY_EVENTS) do
		events:RegisterEvent(event)
	end
	if not state.dismissed then
		ticker:Show()
		Tick()
	end
end

-- Follow the AFK flag. An unreadable (secret) flag changes nothing.
local function Sync()
	local afk = IsAFK()
	if afk == nil then
		return
	end
	if afk then
		if not away then
			BeginAway({ since = GetTime(), whispers = {} })
		elseif away.preview then
			away.preview = nil -- went AFK for real during the preview: keep going as AFK
		end
	elseif away and not away.preview then
		Finish()
	end
end

-- Closed for the rest of this AFK: the screen stays down until the flag clears and comes back.
local function StayClosed()
	ns.Cinematic.Release(away)
	if away.preview then
		Finish()
		return
	end
	away.dismissed = true
	ticker:Hide()
end

-- Click or Esc on the screen.
function Dismiss()
	if not away then
		return
	end
	local preview = away.preview
	StayClosed()
	-- The AFK "channel" toggles: only send it while the flag reads as set.
	if not preview and ns.afkDB.clearAFK and IsAFK() and not InChatLockdown() then
		local send = C_ChatInfo.SendChatMessage or SendChatMessage
		send("", "AFK")
	end
end

function Tick()
	Sync() -- catches a flag change we missed (unreadable while it happened)
	if not away or away.dismissed then
		ticker:Hide()
		return
	end
	if ns.Cinematic.IsOwner(away) then
		if IsInInstance() then
			ns.Cinematic.Exit(away) -- summoned or ported in while AFK: back once out again
		end
		return
	end
	if away.resumeAt and GetTime() < away.resumeAt then
		ns.Cinematic.Watch(away) -- combat paused it
		return
	end
	if not SceneBlocked() then
		ns.Cinematic.Enter(ns.AFKScene, away, CinematicOptions())
	end
end

local sinceTick = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick >= TICK then
		sinceTick = 0
		Tick()
	end
end)

-- After /reload while AFK: GetTime() keeps counting across reloads, so "away since" stays right.
local function ResumeOrCleanup()
	local cur = ns.afkDB.current
	if not away and cur then
		if not cur.preview and IsAFK() ~= false and (cur.since or math.huge) <= GetTime() then
			BeginAway(cur)
		else
			ns.Cinematic.Release(cur)
			ns.afkDB.current = nil
		end
	end
	Sync()
end

local function AddWhisper(entry)
	if not away or away.preview then
		return
	end
	ns.AFK_AddWhisper(away.whispers, entry, MAX_WHISPERS)
	ns.AFKScene_RefreshWhispers()
end

function events:PLAYER_ENTERING_WORLD()
	ResumeOrCleanup()
end

function events:PLAYER_FLAGS_CHANGED(unit)
	if unit == "player" then
		Sync()
	end
end

function events:CHAT_MSG_WHISPER(text, sender, _, _, _, _, _, _, _, _, _, guid)
	if not Readable(text, sender) then
		return -- secret in chat lockdown: can't be kept
	end
	local class
	if guid and Readable(guid) and guid ~= "" then
		local _, englishClass = GetPlayerInfoByGUID(guid)
		class = englishClass
	end
	AddWhisper({ at = time(), sender = Ambiguate(sender, "short"), class = class, text = text })
end

-- sender is a Battle.net name string (|K...|k): shows the real name, but addons can't read it.
function events:CHAT_MSG_BN_WHISPER(text, sender)
	if not Readable(text, sender) then
		return
	end
	AddWhisper({ at = time(), sender = sender, bn = true, text = text })
end

-- Something needs the UI: close so its popup is visible.
local function Interrupt()
	if away and not away.dismissed then
		StayClosed()
	end
end

events.LFG_PROPOSAL_SHOW = Interrupt
events.READY_CHECK = Interrupt
events.PARTY_INVITE_REQUEST = Interrupt

function events:UPDATE_BATTLEFIELD_STATUS(index)
	if index and GetBattlefieldStatus(index) == "confirm" then
		Interrupt()
	end
end

local function Preview()
	if not module.active then
		ns.Print("AFK Screen is off.")
		return
	end
	if away then
		ns.Print("you're already AFK.")
		return
	end
	if SceneBlocked() then
		ns.Print("the AFK screen can't show right now (instance, taxi, combat or another cinematic).")
		return
	end
	local whispers = {}
	for _, sample in ipairs(SAMPLE_WHISPERS) do
		whispers[#whispers + 1] = { at = time() - sample.ago, sender = sample.sender, class = sample.class, bn = sample.bn, text = sample.text }
	end
	BeginAway({ since = GetTime() - 754, whispers = whispers, preview = true })
end

local function Activate()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	-- Turned on from the panel: the world is already there.
	if ns.inWorld then
		ResumeOrCleanup()
	end
end

-- Must undo everything: UI, camera, ticker, events.
local function Deactivate()
	for _, event in ipairs(EVENTS) do
		events:UnregisterEvent(event)
	end
	Finish()
	local cur = ns.afkDB.current
	if cur then
		ns.Cinematic.Release(cur)
		ns.afkDB.current = nil
	end
end

module = ns.RegisterModule({
	key = "afk",
	name = "AFK Screen",
	category = "Ambience",
	description = "A cinematic screen while you're AFK: slowly orbiting camera, your character, time away, clock, session stats and whispers you missed.",
	enabledByDefault = true,
	defaults = {
		orbit = true,
		showcase = true,
		whispers = true,
		clearAFK = true,
	},
	init = function(db)
		ns.afkDB = db
	end,
	toggle = function(active)
		if active then
			Activate()
		else
			Deactivate()
		end
	end,
	cinematicState = function()
		return away
	end,
	commands = {
		{ "preview", "show the AFK screen with sample whispers", Preview },
	},
	options = {
		{ type = "header", label = "AFK screen" },
		{ type = "checkbox", key = "orbit", label = "Camera orbit",
			tooltip = "Zoomed-out camera slowly circles your character." },
		{ type = "checkbox", key = "showcase", label = "Character showcase",
			tooltip = "Your character model and gear on the left side of the screen." },
		{ type = "checkbox", key = "whispers", label = "Missed whispers",
			tooltip = "Whispers you received while AFK, on the right side of the screen.",
			onChange = function()
				ns.AFKScene_RefreshWhispers()
			end },
		{ type = "checkbox", key = "clearAFK", label = "Click clears AFK",
			tooltip = "Closing the screen with a click or Esc also ends your AFK status." },
		{ type = "button", label = "Preview", text = "Show", onClick = Preview,
			tooltip = "Show the AFK screen now, with sample whispers. Click or Esc closes it." },
	},
})
