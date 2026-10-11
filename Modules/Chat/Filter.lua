local addonName, ns = ...

-- Trade Filter module: Trade and the other chosen channels show only messages with one of your keywords (your
-- professions' names and their usual abbreviations, plus your own words), minus the ones with an ignore word.
-- A Blizzard chat message filter (ChatFrameUtil.AddMessageEventFilter). In chat lockdown (instances, encounters,
-- M+, PvP) the game skips addon filters, so everything shows there.

local OWNER = "tradefilter"
local TOAST_GAP = 300 -- seconds between toasts for the same sender
local SEEN_LIMIT = 500
local PROF_RECHECK = 5 -- seconds after the first loading screen before looking at the professions again

local UI = ns.UI
local module
local keywords, ignoreWords = {}, {}
local playerGUID
local stats = { hidden = 0, shown = 0 }
local seen, seenCount = {}, 0 -- [lineID] = true: the filter runs once per chat frame, count each message once
local lastToast = {} -- [sender] = GetTime()

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local Readable = ns.Readable

local function ReadProfessions()
	local profs = {}
	local first, second = GetProfessions()
	for _, index in pairs({ first, second }) do
		local name, _, _, _, _, _, skillLine = GetProfessionInfo(index)
		if name and skillLine then
			profs[#profs + 1] = { name = name, skillLine = skillLine }
		end
	end
	return profs
end

local function RebuildWords()
	local db = module.db
	keywords = ns.Chat_BuildKeywords(ReadProfessions(), db.profKeywords, db.keywords)
	ignoreWords = db.useIgnore and ns.Social_ParseWords(db.ignore) or {}
end

local function Highlight(word)
	return UI.Wrap(word, "accent")
end

local function SenderClass(guid)
	if guid and guid ~= "" then
		local _, englishClass = GetPlayerInfoByGUID(guid)
		return englishClass
	end
end

local function ShowToast(label, sender, guid, text, channelIndex, preview)
	local short = Ambiguate(sender, "short")
	local title = short
	local color = C_ClassColor.GetClassColor(SenderClass(guid) or "")
	if color then
		title = color:WrapTextInColorCode(short)
	end
	ns.Toast_Show({
		owner = OWNER,
		label = label,
		accent = ns.Toast_ChatColor(channelIndex and ("CHANNEL" .. channelIndex) or "CHANNEL"),
		title = title,
		text = ns.Social_PlainText(text),
		chat = true,
		mergeKey = "trade:" .. sender,
		digestName = short,
		holdInCombat = module.db.holdInCombat,
		onClick = function()
			if not preview then
				ChatFrameUtil.SendTell(sender)
			end
		end,
	})
end

-- First time this message is seen (by any chat frame): count it, maybe toast.
local function Note(lineID, show, text, sender, guid, channelIndex, baseName)
	if lineID then
		if seen[lineID] then
			return
		end
		if seenCount >= SEEN_LIMIT then
			seen, seenCount = {}, 0
		end
		seen[lineID] = true
		seenCount = seenCount + 1
	end
	if not show then
		stats.hidden = stats.hidden + 1
		return
	end
	stats.shown = stats.shown + 1
	if module.db.toast and sender and sender ~= "" then
		local now = GetTime()
		if not lastToast[sender] or now - lastToast[sender] >= TOAST_GAP then
			lastToast[sender] = now
			local label = (baseName and baseName ~= "") and baseName or "Trade"
			ShowToast(label, sender, guid, text, channelIndex)
		end
	end
end

-- (chatFrame, event, text, sender, language, channelName, target, flags, zoneChannelID, channelIndex,
-- channelBaseName, languageID, lineID, guid, ...). true hides; false + arguments replaces them.
local function Filter(chatFrame, event, text, ...)
	if not module.active or module.db.paused then
		return false
	end
	local sender, zoneID, channelIndex, baseName, lineID, guid = (...), select(6, ...), select(7, ...), select(8, ...), select(10, ...), select(11, ...)
	if not Readable(text, zoneID, guid) or type(text) ~= "string" then
		return false
	end
	local channel = ns.CHAT_CHANNEL_BY_ID[zoneID]
	if not channel or not module.db.channels[channel.key] then
		return false
	end
	if module.db.where == "exceptTab" and chatFrame == ns.ChatTabs_Frame() then
		return false
	end
	if guid and guid == playerGUID then
		return false
	end
	if #keywords == 0 and module.db.profKeywords then
		RebuildWords() -- professions weren't loaded yet
	end
	local show = ns.Chat_Decide(text, keywords, ignoreWords)
	Note(lineID, show, text, sender, guid, channelIndex, baseName)
	if not show then
		return true
	end
	if module.db.highlight then
		local marked = ns.Chat_Highlight(text, keywords, Highlight)
		if marked ~= text then
			return false, marked, ...
		end
	end
	return false
end

local function AddFilter()
	ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL", Filter)
end

local function RemoveFilter()
	ChatFrameUtil.RemoveMessageEventFilter("CHAT_MSG_CHANNEL", Filter)
end

local warned
local function WarnIfEmpty()
	if #keywords == 0 and not warned then
		warned = true
		ns.Print("Trade Filter: no keywords yet, so the filtered channels show nothing. Add some in the settings.")
	end
end

-- Professions can still be missing at the first loading screen: look again a little later before warning.
local worldEntered = false
function events:PLAYER_ENTERING_WORLD()
	playerGUID = UnitGUID("player")
	RebuildWords()
	if not worldEntered then
		worldEntered = true
		C_Timer.After(PROF_RECHECK, function()
			if module.active then
				RebuildWords()
				WarnIfEmpty()
			end
		end)
	end
end

function events:SKILL_LINES_CHANGED()
	RebuildWords()
end

local function Digest(held)
	local count, names = ns.Social_Digest(held)
	return {
		owner = OWNER,
		label = "While you were busy",
		accent = ns.Toast_ChatColor("CHANNEL"),
		title = count .. " trade matches",
		text = "From " .. ns.Social_NameList(names, 4) .. ".",
	}
end

local function Activate()
	playerGUID = UnitGUID("player")
	warned = false
	RebuildWords()
	if worldEntered then
		WarnIfEmpty()
	end
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("SKILL_LINES_CHANGED")
	AddFilter()
	ns.Toast_SetDigest(OWNER, Digest)
end

local function Deactivate()
	events:UnregisterAllEvents()
	RemoveFilter()
	ns.Toast_Clear(OWNER)
end

local function OnWordsChange()
	if module.active then
		RebuildWords()
	end
end

local function PrintKeywords()
	if not module.active then
		ns.Print("Trade Filter is off.")
		return
	end
	RebuildWords()
	if #keywords == 0 then
		ns.Print("Trade Filter: no keywords.")
	else
		ns.Print("Trade Filter keywords: " .. table.concat(keywords, ", "))
	end
	if #ignoreWords > 0 then
		ns.Print("Ignored when they also say: " .. table.concat(ignoreWords, ", "))
	end
end

local function PrintStats()
	if not module.active then
		ns.Print("Trade Filter is off.")
		return
	end
	ns.Print(("Trade Filter this session: %d hidden, %d shown%s."):format(stats.hidden, stats.shown,
		module.db.paused and " (paused now)" or ""))
end

local function Preview()
	if not module.active then
		ns.Print("Trade Filter is off.")
		return
	end
	ShowToast("Trade", "Thrall", nil, "LF blacksmith for a crafting order, paying well", nil, true)
end

local WHERE_CHOICES = {
	{ value = "exceptTab", text = "All except the Trade tab" },
	{ value = "all", text = "Every chat window" },
}

local options = {
	{ type = "checkbox", key = "paused", label = "Pause the filter",
		tooltip = "Show everything for now, for when you're shopping. Nothing is hidden or toasted while paused." },
	{ type = "header", label = "Keywords" },
	{ type = "checkbox", key = "profKeywords", label = "Your professions", onChange = OnWordsChange,
		tooltip = "This character's two professions, by name and by their usual abbreviations (Blacksmithing: BS, smith, blacksmith). Follows the character you play." },
	{ type = "input", key = "keywords", label = "Your own keywords", placeholder = "LF smith, thorium", onChange = OnWordsChange,
		tooltip = "Separated by commas, shared by all your characters. Whole words or phrases, not case sensitive; item links count by name.\n\nWith no keywords at all, the filtered channels show nothing." },
	{ type = "button", label = "Current keywords", text = "Print", onClick = PrintKeywords,
		tooltip = "List every keyword this character uses in the chat window." },
	{ type = "header", label = "Ignore" },
	{ type = "checkbox", key = "useIgnore", label = "Use the ignore list", onChange = OnWordsChange },
	{ type = "input", key = "ignore", label = "Hide anyway when they say", placeholder = "WTS, boost", onChange = OnWordsChange,
		tooltip = "A message with one of your keywords is still hidden when it also has one of these words. Keeps sellers and boosters out." },
	{ type = "header", label = "Channels" },
}
-- LocalDefense isn't offered (and has no default, so it's never filtered): it carries the game's "under attack"
-- notices, which no keyword would match, so filtering it would only hide them. Chat Tabs can still move it.
for _, channel in ipairs(ns.CHAT_CHANNELS) do
	if channel.key ~= "defense" then
		options[#options + 1] = { type = "checkbox", key = "channels." .. channel.key, label = channel.label }
	end
end
options[#options + 1] = { type = "dropdown", key = "where", label = "Filter in", choices = function()
	return WHERE_CHOICES
end, tooltip = "With the Chat Tabs module on, its tab can show everything while your main window shows only matches. Without that module there is no Trade tab and this changes nothing." }
options[#options + 1] = { type = "header", label = "Matches" }
options[#options + 1] = { type = "checkbox", key = "highlight", label = "Highlight matched words",
	tooltip = "Matched words in the theme's accent color." }
options[#options + 1] = { type = "checkbox", key = "toast", label = "Toast on match",
	tooltip = "A toast for a match, at most one per player every 5 minutes. Click it to whisper them." }
options[#options + 1] = { type = "checkbox", key = "holdInCombat", label = "Hold toasts during combat" }
options[#options + 1] = { type = "button", label = "Sample toast", text = "Show", onClick = Preview }
ns.Toast_Options(options)

module = ns.RegisterModule({
	key = "tradefilter",
	name = "Trade Filter",
	category = "Chat",
	description = "Trade chat shows only what you can help with: messages that name your professions or your own keywords, minus sellers and boosters.",
	enabledByDefault = false,
	keep = { "keywords", "ignore" }, -- typed by the user: a settings reset keeps them
	defaults = {
		profKeywords = true,
		keywords = "",
		useIgnore = true,
		ignore = "WTS, selling, boost, carry",
		channels = { trade = true, services = true, general = false, lfg = false },
		where = "exceptTab",
		highlight = true,
		toast = false,
		holdInCombat = true,
		paused = false,
	},
	toggle = function(active)
		if active then
			Activate()
		else
			Deactivate()
		end
	end,
	commands = {
		{ "stats", "messages hidden and shown this session", PrintStats },
		{ "keywords", "list the keywords in use", PrintKeywords },
		{ "preview", "show a sample toast", Preview },
	},
	options = options,
})
