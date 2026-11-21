local addonName, ns = ...

-- Trade Filter module: Trade and the other chosen channels show only messages with one of your keywords (your
-- professions' names and their usual abbreviations, plus your own words), minus the ones with an ignore word. A
-- message naming a recipe shows only when you know it (rules in RecipeData.lua).
-- A Blizzard chat message filter (ns.Chat_AddFilter). In chat lockdown (instances, encounters,
-- M+, PvP) the game skips addon filters, so everything shows there.

local OWNER = "tradefilter"
local TOAST_GAP = 300 -- seconds between toasts for the same sender
local SEEN_LIMIT = 500
local PROF_RECHECK = 5 -- seconds after the first loading screen before looking at the professions again
-- The sample toast's and the settings preview's made-up match.
local SAMPLE_SENDER = "Aldric"
local SAMPLE_TEXT = "LF blacksmith for a crafting order, paying well"

local RECIPE_DELAY = 1 -- seconds: a recipe learned or a skill line changed comes with a burst of events

local UI = ns.UI
local module
local keywords, ignoreWords = {}, {}
local words = { prof = {}, own = {} } -- keywords split: your professions' words and your own (Chat_DecideRequest)
local recipeIndex -- Chat_RecipeIndex of your recipes; nil while "Only recipes you know" is off or not read yet
local playerGUID
local stats = { hidden = 0, shown = 0 }
local seen, seenCount = {}, 0 -- [lineID] = true: the filter runs once per chat frame, count each message once
local lastToast = {} -- [sender] = GetTime()

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

local Readable = ns.Readable

-- Forever: names only, from the skills list (no skill line IDs, so no abbreviations).
local function ReadSkillLineProfessions()
	local lines = {}
	for i = 1, GetNumSkillLines() do
		local name, isHeader = GetSkillLineInfo(i)
		lines[i] = { name = name, isHeader = isHeader }
	end
	local profs = {}
	for _, name in ipairs(ns.Chat_ProfessionNames(lines, TRADE_SKILLS)) do
		profs[#profs + 1] = { name = name }
	end
	return profs
end

local function ReadProfessions()
	if not GetProfessions then
		return ReadSkillLineProfessions()
	end
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
	local profs = ReadProfessions()
	keywords = ns.Chat_BuildKeywords(profs, db.profKeywords, db.keywords)
	words.prof = ns.Chat_BuildKeywords(profs, db.profKeywords, "")
	words.own = ns.Chat_BuildKeywords(nil, false, db.keywords)
	ignoreWords = db.useIgnore and ns.Social_ParseWords(db.ignore) or {}
end

-- Recipes ------------------------------------------------------------------------------------------------------------

-- Your recipes for Chat_RecipeIndex. Forever: every recipe of the game (RecipesForever.lua), known when the game says
-- the spell is known or Alts saw it learned; its profession window lists only what you know. Retail: what Alts read
-- from your profession windows (it lists unlearned recipes too).
local function ReadRecipes()
	local alts = ns.Alts_MyRecipes and ns.Alts_MyRecipes()
	local list = {}
	if ns.CHAT_RECIPES then
		local altsKnown = {}
		for _, r in ipairs(alts or {}) do
			altsKnown[r.id] = r.known or nil
		end
		for base, spells in pairs(ns.CHAT_RECIPES) do
			local start, any = #list, false
			for spell, item in pairs(spells) do
				local known = ns.SpellKnown(spell) or altsKnown[spell] == true
				any = any or known
				list[#list + 1] = { id = spell, item = item, base = base, known = known }
			end
			-- Names only for a profession you have (one known recipe): a skill-up shouldn't look up every recipe.
			for i = start + 1, any and #list or 0 do
				list[i].name = C_Spell.GetSpellName(list[i].id)
			end
		end
	else
		for _, r in ipairs(alts or {}) do
			list[#list + 1] = r
		end
	end
	return list
end

local function RebuildRecipes()
	recipeIndex = module.active and module.db.profKeywords and module.db.knownOnly
		and ns.Chat_RecipeIndex(ReadRecipes()) or nil
end

local RebuildRecipesSoon = UI.Debounce(RECIPE_DELAY, function()
	if module.active then
		RebuildRecipes()
	end
end)

local function Highlight(word)
	return UI.Wrap(word, "accent")
end

local function SenderClass(guid)
	if guid and guid ~= "" then
		local _, englishClass = GetPlayerInfoByGUID(guid)
		return englishClass
	end
end

local function ToastSpec(label, sender, guid, text, channelIndex, preview)
	local short = Ambiguate(sender, "short")
	local title = UI.ClassColored(short, SenderClass(guid))
	return {
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
				ns.Chat_SendTell(sender)
			end
		end,
	}
end

local function ShowToast(label, sender, guid, text, channelIndex, preview)
	ns.Toast_Show(ToastSpec(label, sender, guid, text, channelIndex, preview))
end

-- Settings preview (Panel/Preview.lua): a made-up Trade match, built by the real toast's spec code.
local function ToastPreview(host)
	local spec = ToastSpec("Trade", SAMPLE_SENDER, nil, SAMPLE_TEXT, nil, true)
	spec.test = true
	return ns.Toast_DrawSample(host, spec, 1)
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
	local show, _, recipe = ns.Chat_DecideRequest(text, words, ignoreWords, recipeIndex)
	Note(lineID, show, text, sender, guid, channelIndex, baseName)
	if not show then
		return true
	end
	if module.db.highlight then
		local marked = ns.Chat_Highlight(text, recipe and { recipe, unpack(keywords) } or keywords, Highlight)
		if marked ~= text then
			return false, marked, ...
		end
	end
	return false
end

local function AddFilter()
	ns.Chat_AddFilter("CHAT_MSG_CHANNEL", Filter)
end

local function RemoveFilter()
	ns.Chat_RemoveFilter("CHAT_MSG_CHANNEL", Filter)
end

local warned
local function WarnIfEmpty()
	if #keywords == 0 and not warned then
		warned = true
		ns.Print("Trade Filter: no keywords yet, so the filtered channels show nothing. Add some in the settings.")
	end
end

-- Professions can still be missing at the first loading screen: look again a little later before warning.
-- Also watched once from file load, module on or off: "Pause the filter" lasts one play session (a forgotten pause
-- would leave Trade unfiltered for good). A /reload keeps it.
local worldEntered = false
function events:PLAYER_ENTERING_WORLD(isInitialLogin)
	if isInitialLogin and module.db and module.db.paused then
		module.db.paused = false
	end
	if not module.active then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		return
	end
	playerGUID = UnitGUID("player")
	RebuildWords()
	RebuildRecipes()
	if not worldEntered then
		worldEntered = true
		C_Timer.After(PROF_RECHECK, function()
			if module.active then
				RebuildWords()
				RebuildRecipes()
				WarnIfEmpty()
			end
		end)
	end
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")

function events:SKILL_LINES_CHANGED()
	RebuildWords()
	RebuildRecipesSoon()
end

-- A recipe learned, or the profession window closed (Alts has read it by then).
function events:NEW_RECIPE_LEARNED()
	RebuildRecipesSoon()
end

function events:TRADE_SKILL_CLOSE()
	RebuildRecipesSoon()
end

-- Recipe events that may not exist on every client: registered when they do.
local RECIPE_EVENTS = { "NEW_RECIPE_LEARNED", "TRADE_SKILL_CLOSE" }

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
		RebuildRecipes()
	end
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("SKILL_LINES_CHANGED")
	for _, event in ipairs(RECIPE_EVENTS) do
		pcall(events.RegisterEvent, events, event)
	end
	AddFilter()
	ns.Toast_SetDigest(OWNER, Digest)
end

local function Deactivate()
	events:UnregisterAllEvents()
	recipeIndex = nil
	RemoveFilter()
	ns.Toast_Clear(OWNER)
end

local function OnWordsChange()
	if module.active then
		RebuildWords()
		RebuildRecipes()
	end
end

-- /tomte tradefilter why <message>: what the filter decides for a message, and why. Paste a line from chat
-- (shift-click links into it) to see why it showed or hid.
local function Why(_, rawArg)
	if not ns.Module_RequireOn(module) then
		return
	end
	RebuildWords()
	RebuildRecipes()
	local readable = {}
	for base in pairs(recipeIndex and recipeIndex.readable or {}) do
		readable[#readable + 1] = tostring(base)
	end
	ns.Print(("Trade Filter: %s; %d recipes of your professions read (skill lines: %s)."):format(
		module.db.knownOnly and "only recipes you know" or "recipes not checked", recipeIndex and recipeIndex.count or 0,
		#readable > 0 and table.concat(readable, ", ") or "none"))
	if rawArg and rawArg ~= "" then
		local show, why = ns.Chat_DecideRequest(rawArg, words, ignoreWords, recipeIndex)
		ns.Print(("%s: %s."):format(show and "Shown" or "Hidden", why))
	end
end

local function PrintKeywords()
	if not ns.Module_RequireOn(module) then
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
	if not ns.Module_RequireOn(module) then
		return
	end
	ns.Print(("Trade Filter this session: %d hidden, %d shown%s."):format(stats.hidden, stats.shown,
		module.db.paused and " (paused now)" or ""))
end

local function Preview()
	if not ns.Module_RequireOn(module) then
		return
	end
	ShowToast("Trade", SAMPLE_SENDER, nil, SAMPLE_TEXT, nil, true)
end

local WHERE_CHOICES = {
	{ value = "exceptTab", text = "All except the Trade tab" },
	{ value = "all", text = "Every chat window" },
}

local options = {
	{ type = "checkbox", key = "paused", label = "Pause the filter",
		tooltip = "Show everything until you log out, for when you're shopping. Nothing is hidden or toasted while paused." },
	{ type = "header", label = "Keywords" },
	{ type = "checkbox", key = "profKeywords", label = "Your professions", onChange = OnWordsChange,
		tooltip = "This character's two professions, by name and by their usual abbreviations (Blacksmithing: BS, smith, blacksmith). Follows the character you play." },
	{ type = "checkbox", key = "knownOnly", label = "Only recipes you know", parent = "profKeywords", onChange = OnWordsChange,
		tooltip = "A message that names a recipe of your profession shows only when you know that recipe, even without your profession's name in it. \"LF enchanter\" with no recipe named still shows.\n\nNeeds the Alts module on retail, and a look at your profession window once." },
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
		options[#options + 1] = { type = "checkbox", key = "channels." .. channel.key, label = channel.label,
			shown = channel.retail and ns.NotForever or nil }
	end
end
options[#options + 1] = { type = "dropdown", key = "where", label = "Filter in", choices = function()
	return WHERE_CHOICES
end, tooltip = "With the Chat Tabs module on, its tab can show everything while your main window shows only matches. Without that module there is no Trade tab and this changes nothing." }
options[#options + 1] = { type = "header", label = "Matches" }
options[#options + 1] = { type = "checkbox", key = "highlight", label = "Highlight matched words",
	tooltip = "Matched words in the theme's accent color." }
options[#options + 1] = { type = "checkbox", key = "toast", label = "Toast on match",
	preview = ns.Preview_When("toast", ToastPreview),
	tooltip = "A toast for a match, at most one per player every 5 minutes. Click it to whisper them." }
options[#options + 1] = { type = "checkbox", key = "holdInCombat", label = "Hold toasts during combat",
	parent = "toast" }
options[#options + 1] = { type = "button", label = "Sample toast", text = "Show", onClick = Preview }
ns.Toast_Options(options)

module = ns.RegisterModule({
	key = "tradefilter",
	name = "Trade Filter",
	category = "chat",
	icon = 134441, -- inv_misc_spyglass_02
	summary = "Trade chat shows only messages about your professions and keywords.",
	description = "Trade chat shows only what you can help with: messages that name your professions or your own keywords, minus sellers and boosters.",
	enabledByDefault = false,
	toasts = true,
	keep = { "keywords", "ignore" }, -- typed by the user: a settings reset keeps them
	defaults = {
		profKeywords = true,
		knownOnly = true, -- requests for a recipe you don't know are hidden (RecipeData.lua)
		keywords = "",
		useIgnore = true,
		ignore = "WTS, selling, boost, carry",
		channels = { trade = true, services = true, general = false, lfg = false },
		where = "exceptTab",
		highlight = true,
		toast = false,
		holdInCombat = true,
		paused = false, -- until logout: cleared on the next login (PLAYER_ENTERING_WORLD)
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
		{ debug = true, "preview", "show a sample toast", Preview },
		{ debug = true, "why", "<message>: whether a message would show, and why", Why },
	},
	options = options,
})
