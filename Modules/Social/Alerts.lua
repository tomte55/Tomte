local addonName, ns = ...

-- Group Alerts module: party invites, dungeon/raid finder and PvP queue pops, ready checks and summons get
-- a sound (on the effects channel by default, or Master to be heard with effects muted), optionally repeated until
-- you've answered, and a taskbar flash where Blizzard has none (summons). Blizzard's own popups and sounds stay.
-- Party and guild invite popups get a line under them with the inviter's level, class and guild where the game
-- knows them (friend lists, the guild roster, Battle.net, a nearby player's tooltip; never /who). The line is our
-- own frame laid against Blizzard's popup: the popup itself isn't touched.

local TICK = 0.5
local POPUP_DELAY = 0.2 -- seconds: Blizzard's popup shows on the same event as ours
local LINE_CHECK = 0.1 -- seconds between checks that the popup under the inviter line is still up
local LINE_PAD = 8
local CHANNEL_CHOICES = {
	{ value = "SFX", text = "Effects" },
	{ value = "Master", text = "Master" },
}
local EVENTS = {
	"PARTY_INVITE_REQUEST", "LFG_PROPOSAL_SHOW", "UPDATE_BATTLEFIELD_STATUS", "READY_CHECK", "CONFIRM_SUMMON",
	"GUILD_INVITE_REQUEST",
}
local UI = ns.UI
local IsSecret = ns.IsSecret

local module
local active = {} -- [alert key] = { next = GetTime() of the next repeat, left = repeats left }
local pvpRung -- this PvP queue pop already rang: not again until it's answered

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))
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
	ns.Social_PlaySound(ns.alertsDB.sound, ns.alertsDB.channel)
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
ticker:SetScript("OnUpdate", ns.Perf_Wrap(function(self, elapsed)
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
end, "OnUpdate"))

-- Popups show on the same event: check they're up a moment later.
local function TriggerSoon(key)
	C_Timer.After(POPUP_DELAY, function()
		if module.active and byKey[key].pending() then
			Trigger(key)
		end
	end)
end

-- Who invited you -----------------------------------------------------------------------------------------------

local line -- the frame under the popup: { text, popup, which }

-- A Battle.net friend playing the character with this GUID: their game account info, or nil.
local function BNetByGUID(guid)
	for i = 1, BNGetNumFriends() or 0 do
		for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
			local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
			if game and game.playerGuid == guid then
				return game
			end
		end
	end
	return nil
end

-- The level from the tooltip of a player near you (the game only has it for players it has seen).
local function TooltipLevel(guid)
	local data = C_TooltipInfo.GetHyperlink("unit:" .. guid)
	if not (data and data.lines) then
		return nil
	end
	local texts = {}
	for i, tipLine in ipairs(data.lines) do
		if IsSecret(tipLine.leftText) then
			return nil
		end
		texts[i] = tipLine.leftText
	end
	return ns.Social_LevelFromLines(texts, TOOLTIP_UNIT_LEVEL)
end

-- What the game knows about the inviter: { level, className, classFile, guild } (any may be nil). name: as the
-- event gives it ("Name" on your realm); guid: party invites only.
local function InviterInfo(name, guid)
	local info = {}
	if guid and not IsSecret(guid) then
		local className, classFile = GetPlayerInfoByGUID(guid)
		if not IsSecret(className) then
			info.className, info.classFile = className, classFile
		end
	end
	local key = ns.Social_FullName(name, GetNormalizedRealmName())
	local who = key and ns.InboxWho_Get and ns.InboxWho_Get({ with = key })
	if who then
		info.level = info.level or who.level
		info.className = info.className or who.className
		info.classFile = info.classFile or who.classFile
		if who.guild then
			info.guild = GetGuildInfo("player")
		end
	end
	if guid and not IsSecret(guid) then
		if not info.level then
			local game = BNetByGUID(guid)
			if game and game.characterLevel and game.characterLevel > 0 then
				info.level = game.characterLevel
			end
		end
		info.level = info.level or TooltipLevel(guid)
	end
	return info
end

local function PaintClass(className, classFile)
	return UI.ClassColored(className, classFile)
end

local function HideLine()
	if line then
		line:Hide()
	end
end

local sinceLineCheck = 0
local function LineOnUpdate(self, elapsed)
	sinceLineCheck = sinceLineCheck + elapsed
	if sinceLineCheck < LINE_CHECK then
		return
	end
	sinceLineCheck = 0
	local popup = self.popup
	-- Blizzard reuses its popup frames: one that now shows another dialog isn't the invite any more.
	if not (module.active and popup:IsShown()) or (self.which and popup.which ~= self.which) then
		self:Hide()
	end
end

-- The line's look, shared by the real line and the settings preview's still one.
local function DressLine(frame)
	UI.Panel(frame, { subtle = true })
	frame.text = UI.Text(frame, 12, "text")
	frame.text:SetPoint("CENTER")
end

-- Puts text in and sizes frame to it; returns the size.
local function FillLine(frame, text)
	frame.text:SetText(text)
	local w, h = frame.text:GetStringWidth() + 2 * LINE_PAD, frame.text:GetStringHeight() + LINE_PAD
	frame:SetSize(w, h)
	return w, h
end

local function CreateLine()
	line = CreateFrame("Frame", nil, UIParent)
	line:SetFrameStrata("DIALOG")
	DressLine(line)
	line:SetScript("OnUpdate", ns.Perf_Wrap(LineOnUpdate, "OnUpdate"))
	line:Hide()
end

-- Shows text against popup: under it, or above it with above = true (the guild invite has its buttons at the
-- bottom). which: the StaticPopup dialog it belongs to, nil for a popup of its own.
local function ShowLine(popup, text, which, above)
	if not line then
		CreateLine()
	end
	line.popup, line.which = popup, which
	FillLine(line, text)
	line:SetFrameLevel(popup:GetFrameLevel() + 5)
	line:ClearAllPoints()
	if above then
		line:SetPoint("BOTTOM", popup, "TOP", 0, 4)
	else
		line:SetPoint("TOP", popup, "BOTTOM", 0, -4)
	end
	sinceLineCheck = 0
	line:Show()
end

local function ShowPartyInviter(name, guid)
	local popup, which
	if LFGInvitePopup and LFGInvitePopup:IsShown() then
		popup = LFGInvitePopup
	else
		popup = StaticPopup_FindVisible("PARTY_INVITE")
		which = "PARTY_INVITE"
	end
	local text = popup and ns.Social_InviterText(InviterInfo(name, guid), PaintClass)
	if text then
		ShowLine(popup, text, which)
	end
end

local function ShowGuildInviter(name)
	if not (GuildInviteFrame and GuildInviteFrame:IsShown()) then
		return
	end
	local text = ns.Social_InviterText(InviterInfo(name), PaintClass)
	if text then
		ShowLine(GuildInviteFrame, text, nil, true)
	end
end

function events:PARTY_INVITE_REQUEST(name, _, _, _, _, _, guid)
	TriggerSoon("invite")
	if ns.alertsDB.inviter and not IsSecret(name) then
		C_Timer.After(POPUP_DELAY, function()
			if module.active then
				ShowPartyInviter(name, guid)
			end
		end)
	end
end

function events:GUILD_INVITE_REQUEST(inviter)
	if ns.alertsDB.inviter and not IsSecret(inviter) then
		C_Timer.After(POPUP_DELAY, function()
			if module.active then
				ShowGuildInviter(inviter)
			end
		end)
	end
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

-- Settings preview (Panel/Preview.lua): the line as it shows under an invite from a made-up inviter.
local SAMPLE_CLASS_ID = 8 -- Mage: the class name comes from the game, in the player's language
local SAMPLE_GUILD = "Order of the Lantern"

local function InviterPreview(host)
	if not host.line then
		host.line = CreateFrame("Frame", nil, host)
		host.line:SetPoint("TOPLEFT")
		DressLine(host.line)
	end
	local class = C_CreatureInfo.GetClassInfo(SAMPLE_CLASS_ID)
	local text = ns.Social_InviterText({ level = 90, className = class and class.className,
		classFile = class and class.classFile, guild = SAMPLE_GUILD }, PaintClass)
	return FillLine(host.line, text)
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
	if not ns.Module_RequireOn(module) then
		return
	end
	ns.Social_PlaySound(ns.alertsDB.sound, ns.alertsDB.channel)
	FlashClientIcon()
end

local options = {
	{ type = "header", label = "Alerts" },
}
for _, alert in ipairs(ALERTS) do
	options[#options + 1] = { type = "checkbox", key = "on." .. alert.key, label = alert.name,
		tooltip = alert.flash and "Also flashes the taskbar icon (Blizzard doesn't for this one)." or nil }
end
options[#options + 1] = { type = "checkbox", key = "inviter", label = "Who's inviting",
	preview = ns.Preview_When("inviter", InviterPreview),
	onChange = function(on)
		if not on then
			HideLine()
		end
	end,
	tooltip = "Under a group or guild invite: the inviter's level, class and guild, when the game knows them (friends, your guild, Battle.net friends, players near you)." }
options[#options + 1] = { type = "header", label = "Sound" }
options[#options + 1] = { type = "dropdown", key = "sound", label = "Sound", onChange = function(value)
	ns.Social_PlaySound(value, ns.alertsDB.channel)
end, choices = function()
	return ns.SOCIAL_SOUND_CHOICES
end, tooltip = "Played on top of Blizzard's own sound." }
options[#options + 1] = { type = "dropdown", key = "channel", label = "Sound channel", onChange = function()
	ns.Social_PlaySound(ns.alertsDB.sound, ns.alertsDB.channel)
end, choices = function()
	return CHANNEL_CHOICES
end, tooltip = "Effects follows your sound effects volume and is silent with effects muted. Master is heard even with sound effects off." }
options[#options + 1] = { type = "slider", key = "repeats", label = "Repeat until answered", min = 0, max = 10, step = 1,
	format = function(value)
		return value == 0 and "off" or (value .. "x")
	end, tooltip = "Play the sound again this many times while the popup is still waiting for you." }
options[#options + 1] = { type = "slider", key = "interval", label = "Repeat every", min = 3, max = 15, step = 1,
	shown = function()
		return ns.alertsDB.repeats > 0
	end,
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
	category = "social",
	icon = 133706, -- inv_misc_bell_01
	summary = "Invites, queue pops and summons you can't miss.",
	description = "Invites, queue pops, ready checks and summons you can't miss: a sound (once, or repeating until you've answered), and a taskbar flash for summons. Group and guild invites show who's inviting: level, class and guild when the game knows them.",
	enabledByDefault = true,
	replaces = { { addon = "Plumber", why = "the inviter's level and class on group and guild invites" } },
	defaults = {
		on = { invite = true, lfg = true, pvp = true, readyCheck = true, summon = true },
		sound = "bell",
		channel = "SFX", -- "SFX" or "Master" (PlaySound channel)
		repeats = 0,
		interval = 5,
		inviter = true,
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
			HideLine()
		end
	end,
	commands = {
		{ "test", "play the alert sound and flash the taskbar icon", Test },
	},
	options = options,
})
