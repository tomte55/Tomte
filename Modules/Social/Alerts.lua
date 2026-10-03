local addonName, ns = ...

-- Group Alerts module: party invites, dungeon/raid finder and PvP queue pops, ready checks and summons get
-- a sound on the Master channel (heard with effects muted) that repeats until you've answered, and a
-- taskbar flash where Blizzard has none (summons). Blizzard's own popups and sounds stay as they are.

local TICK = 0.5
local EVENTS = { "PARTY_INVITE_REQUEST", "LFG_PROPOSAL_SHOW", "UPDATE_BATTLEFIELD_STATUS", "READY_CHECK", "CONFIRM_SUMMON" }

local module
local active = {} -- [alert key] = { next = GetTime() of the next repeat, left = repeats left }
local pvpRung -- this PvP queue pop already rang: not again until it's answered

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
local ticker = CreateFrame("Frame")
ticker:Hide()

local function PvPReady()
	for i = 1, GetMaxBattlefieldID() do
		if GetBattlefieldStatus(i) == "confirm" then
			return true
		end
	end
	return false
end

-- In options order. pending() = still waiting for your answer; flash = Blizzard doesn't flash for it.
local ALERTS = {
	{ key = "invite", name = "Group invite", pending = function()
		return StaticPopup_Visible("PARTY_INVITE") ~= nil or (LFGInvitePopup ~= nil and LFGInvitePopup:IsShown())
	end },
	{ key = "lfg", name = "Dungeon or raid finder ready", pending = function()
		local exists, _, _, _, _, _, _, hasResponded = GetLFGProposal()
		return exists and not hasResponded
	end },
	{ key = "pvp", name = "PvP queue ready", pending = PvPReady },
	{ key = "readyCheck", name = "Ready check", pending = function()
		return ReadyCheckFrame ~= nil and ReadyCheckFrame:IsShown()
	end },
	{ key = "summon", name = "Summon", flash = true, pending = function()
		return C_SummonInfo.GetSummonConfirmTimeLeft() > 0
	end },
}
local byKey = {}
for _, alert in ipairs(ALERTS) do
	byKey[alert.key] = alert
end

local function Ring(alert)
	ns.Social_PlaySound(ns.alertsDB.sound)
	if alert.flash then
		FlashClientIcon()
	end
end

local function Trigger(key)
	local db = ns.alertsDB
	local alert = byKey[key]
	if not db.on[key] then
		return
	end
	Ring(alert)
	if db.repeats > 0 then
		active[key] = { next = GetTime() + db.interval, left = db.repeats }
		ticker:Show()
	end
end

local sinceTick = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick < TICK then
		return
	end
	sinceTick = 0
	local now = GetTime()
	for key, state in pairs(active) do
		local alert = byKey[key]
		if not alert.pending() then
			active[key] = nil
		elseif now >= state.next then
			Ring(alert)
			state.left = state.left - 1
			state.next = now + ns.alertsDB.interval
			if state.left <= 0 then
				active[key] = nil
			end
		end
	end
	if not next(active) then
		self:Hide()
	end
end)

-- Popups show on the same event: check they're up a moment later.
local function TriggerSoon(key)
	C_Timer.After(0.2, function()
		if module.active and byKey[key].pending() then
			Trigger(key)
		end
	end)
end

function events:PARTY_INVITE_REQUEST()
	TriggerSoon("invite")
end

function events:LFG_PROPOSAL_SHOW()
	TriggerSoon("lfg")
end

-- Fires per queue and on any queue change: ring once per pop.
function events:UPDATE_BATTLEFIELD_STATUS()
	local ready = PvPReady()
	if ready and not pvpRung then
		pvpRung = true
		Trigger("pvp")
	elseif not ready then
		pvpRung = nil
	end
end

function events:READY_CHECK()
	TriggerSoon("readyCheck")
end

function events:CONFIRM_SUMMON()
	TriggerSoon("summon")
end

local function SoundInBackground()
	if C_CVar.GetCVarBool("Sound_EnableSoundWhenGameIsInBG") then
		ns.Print("'Sound in Background' is already on.")
		return
	end
	C_CVar.SetCVar("Sound_EnableSoundWhenGameIsInBG", "1")
	ns.Print("'Sound in Background' turned on (Options > Audio): alerts are heard while WoW is in the background.")
end

local function Test()
	if not module.active then
		ns.Print("Group Alerts is off.")
		return
	end
	ns.Social_PlaySound(ns.alertsDB.sound)
	FlashClientIcon()
end

local options = {
	{ type = "header", label = "Alerts" },
}
for _, alert in ipairs(ALERTS) do
	options[#options + 1] = { type = "checkbox", key = "on." .. alert.key, label = alert.name,
		tooltip = alert.flash and "Also flashes the taskbar icon (Blizzard doesn't for this one)." or nil }
end
options[#options + 1] = { type = "header", label = "Sound" }
options[#options + 1] = { type = "dropdown", key = "sound", label = "Sound", onChange = ns.Social_PlaySound, choices = function()
	return ns.SOCIAL_SOUND_CHOICES
end, tooltip = "Played on the Master channel, on top of Blizzard's own sound." }
options[#options + 1] = { type = "slider", key = "repeats", label = "Repeat until answered", min = 0, max = 10, step = 1,
	format = function(value)
		return value == 0 and "off" or (value .. "x")
	end, tooltip = "Play the sound again this many times while the popup is still waiting for you." }
options[#options + 1] = { type = "slider", key = "interval", label = "Repeat every", min = 3, max = 15, step = 1,
	format = function(value)
		return value .. "s"
	end }
options[#options + 1] = { type = "button", label = "Sound in background", text = "Turn on", onClick = SoundInBackground,
	tooltip = "Without the game's 'Sound in Background' setting no sound is heard while WoW isn't the active window. This turns it on." }
options[#options + 1] = { type = "button", label = "Test", text = "Play", onClick = Test,
	tooltip = "Play the sound and flash the taskbar icon (switch to another window quickly to see the flash)." }

module = ns.RegisterModule({
	key = "alerts",
	name = "Group Alerts",
	category = "Social",
	description = "Invites, queue pops, ready checks and summons you can't miss: a sound on the Master channel that repeats until you've answered, and a taskbar flash for summons.",
	enabledByDefault = true,
	defaults = {
		on = { invite = true, lfg = true, pvp = true, readyCheck = true, summon = true },
		sound = "bell",
		repeats = 3,
		interval = 5,
	},
	init = function(db)
		ns.alertsDB = db
	end,
	toggle = function(on)
		if on then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
		else
			events:UnregisterAllEvents()
			wipe(active)
			ticker:Hide()
		end
	end,
	commands = {
		{ "test", "play the alert sound and flash the taskbar icon", Test },
	},
	options = options,
})
