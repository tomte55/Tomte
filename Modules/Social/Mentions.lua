local addonName, ns = ...

-- Mentions module: a toast (and a taskbar flash, Blizzard doesn't flash for these) when someone says your
-- character's name or one of your keywords in guild, group, say/yell or channel chat. Whole words only.
-- Left-click opens the chat box in that channel. In chat lockdown (instances, encounters, M+, PvP) chat
-- text is secret and can't be searched, so nothing is matched there.

local OWNER = "mentions"
local ACCENT = { 0.25, 1, 0.25 } -- guild green
-- event -> { label, group (option key), slash to answer in that channel }
local CHANNELS = {
	CHAT_MSG_GUILD = { "Guild", "guild", "/g " },
	CHAT_MSG_OFFICER = { "Officer", "guild", "/o " },
	CHAT_MSG_PARTY = { "Party", "group", "/p " },
	CHAT_MSG_PARTY_LEADER = { "Party leader", "group", "/p " },
	CHAT_MSG_RAID = { "Raid", "group", "/raid " },
	CHAT_MSG_RAID_LEADER = { "Raid leader", "group", "/raid " },
	CHAT_MSG_RAID_WARNING = { "Raid warning", "group", "/raid " },
	CHAT_MSG_INSTANCE_CHAT = { "Instance", "group", "/i " },
	CHAT_MSG_INSTANCE_CHAT_LEADER = { "Instance leader", "group", "/i " },
	CHAT_MSG_SAY = { "Say", "say", "/s " },
	CHAT_MSG_YELL = { "Yell", "say", "/y " },
	CHAT_MSG_CHANNEL = { "Channel", "channels" },
	CHAT_MSG_COMMUNITIES_CHANNEL = { "Community", "channels" },
}

local module
local words = {}

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self:OnChat(event, ...)
end)

local function Readable(...)
	return not canaccessallvalues or canaccessallvalues(...)
end

local function RebuildWords()
	local db = ns.mentionsDB
	words = ns.Social_ParseWords(db.keywords)
	if db.ownName then
		local name = UnitName("player")
		if name then
			table.insert(words, 1, name:lower())
		end
	end
end

local function RegisterEvents()
	events:UnregisterAllEvents()
	if not module.active then
		return
	end
	for event, channel in pairs(CHANNELS) do
		if ns.mentionsDB.channels[channel[2]] then
			events:RegisterEvent(event)
		end
	end
end

local function ShowMention(label, sender, class, text, slash, preview)
	local title = sender
	local color = class and C_ClassColor.GetClassColor(class)
	if color then
		title = color:WrapTextInColorCode(sender)
	end
	ns.Toast_Show({
		owner = OWNER,
		label = "Mention - " .. label,
		accent = ACCENT,
		title = title,
		text = text,
		mergeKey = label .. ":" .. sender,
		digestName = sender,
		holdInCombat = ns.mentionsDB.holdInCombat,
		onClick = function()
			if slash and not preview then
				ChatFrameUtil.OpenChat(slash)
			end
		end,
	})
	ns.Social_PlaySound(ns.mentionsDB.sound)
	if ns.mentionsDB.flash and not preview then
		FlashClientIcon()
	end
end

function events:OnChat(event, text, sender, _, _, _, _, _, channelIndex, channelBaseName, _, _, guid)
	if not Readable(text, sender, guid) then
		return -- chat lockdown
	end
	if guid and guid == UnitGUID("player") then
		return
	end
	if not ns.Social_FindMention(text, words) then
		return
	end
	local channel = CHANNELS[event]
	local label, slash = channel[1], channel[3]
	if event == "CHAT_MSG_CHANNEL" then
		label = (channelBaseName and channelBaseName ~= "") and channelBaseName or label
		slash = channelIndex and ("/" .. channelIndex .. " ") or nil
	end
	local class
	if guid and guid ~= "" then
		local _, englishClass = GetPlayerInfoByGUID(guid)
		class = englishClass
	end
	ShowMention(label, Ambiguate(sender, "short"), class, text, slash)
end

local function Digest(held)
	local count, names = ns.Social_Digest(held)
	return {
		owner = OWNER,
		label = "While you were busy",
		accent = ACCENT,
		title = count .. " mentions",
		text = "By " .. ns.Social_NameList(names, 4) .. ".",
	}
end

local function Preview()
	if not module.active then
		ns.Print("Mentions is off.")
		return
	end
	local me = UnitName("player") or "you"
	ShowMention("Guild", "Thrall", "SHAMAN", ("Anyone seen %s? Need help with the Sunwell weekly."):format(me), nil, true)
end

local function Activate()
	RebuildWords()
	RegisterEvents()
	ns.Toast_SetDigest(OWNER, Digest)
end

local function Deactivate()
	events:UnregisterAllEvents()
	ns.Toast_Clear(OWNER)
end

local options = {
	{ type = "header", label = "What counts" },
	{ type = "checkbox", key = "ownName", label = "Your character's name", onChange = RebuildWords,
		tooltip = "Whole word only: \"Tomte\" matches \"hi Tomte!\" but not \"Tomtes\"." },
	{ type = "input", key = "keywords", label = "Keywords", placeholder = "tank, healer", onChange = RebuildWords,
		tooltip = "More words or names, separated by commas. Not case sensitive, whole words only." },
	{ type = "header", label = "Where" },
	{ type = "checkbox", key = "channels.guild", label = "Guild and officer", onChange = RegisterEvents },
	{ type = "checkbox", key = "channels.group", label = "Party, raid and instance", onChange = RegisterEvents,
		tooltip = "Inside instances the game hides chat from addons, so only party chat outside instances is checked." },
	{ type = "checkbox", key = "channels.say", label = "Say and yell", onChange = RegisterEvents },
	{ type = "checkbox", key = "channels.channels", label = "Channels and communities", onChange = RegisterEvents,
		tooltip = "Trade, General, LFG and community channels. Can be busy." },
	{ type = "header", label = "Alert" },
	{ type = "checkbox", key = "holdInCombat", label = "Hold toasts during combat" },
	{ type = "checkbox", key = "flash", label = "Flash the taskbar icon",
		tooltip = "When WoW isn't the active window." },
	{ type = "dropdown", key = "sound", label = "Sound", onChange = ns.Social_PlaySound, choices = function()
		return ns.SOCIAL_SOUND_CHOICES
	end, tooltip = "Played on the Master channel." },
	{ type = "button", label = "Sample mention", text = "Show", onClick = Preview },
}
ns.Toast_Options(options)

module = ns.RegisterModule({
	key = "mentions",
	name = "Mentions",
	category = "Social",
	description = "A toast when someone says your name (or one of your keywords) in guild, group, say or channel chat. Click it to answer in that channel.",
	enabledByDefault = true,
	keep = { "keywords" }, -- typed by the user: a settings reset keeps it
	defaults = {
		ownName = true,
		keywords = "",
		channels = { guild = true, group = true, say = false, channels = false },
		holdInCombat = true,
		flash = true,
		sound = "chime",
	},
	init = function(db)
		ns.mentionsDB = db
	end,
	toggle = function(active)
		if active then
			Activate()
		else
			Deactivate()
		end
	end,
	commands = {
		{ "preview", "show a sample mention", Preview },
	},
	options = options,
})
