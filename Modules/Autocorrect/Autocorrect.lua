local addonName, ns = ...

-- Autocorrect module: fixes the player's chat line as they type. A finished word (space or punctuation typed after
-- it) is fixed in the edit box, a note above the box shows what changed, and Backspace right after puts it back (and
-- that fix is never made again). Enter fixes the last word too. Pure rules in Rules.lua and Line.lua, tables in
-- Data.lua and the generated Words.lua, the note in Note.lua.
--
-- Taint (EllesmereUIChat's in-game findings, retail 12.x): a HookScript("OnTextChanged") on a Blizzard chat edit box
-- runs inside Deactivate's SetText("") right before Blizzard writes the box's chatType, which then taints every later
-- send; hooks on temporary whisper windows poison the chat history through their secret tellTarget. So only OnChar
-- and OnKeyDown (real key presses only) on the permanent windows' boxes, plus EventRegistry callbacks (run through
-- securecallfunction). Text an addon set makes that one send a tainted caller, which chat messaging lockdown
-- (encounters, Mythic+, PvP matches) silently drops: Autocorrect does nothing while it's on.

local OWNER = "TomteAutocorrect" -- EventRegistry callback owner
local NAMES_DELAY = 2 -- seconds to gather a burst of roster updates into one names refresh
local LEARN_AFTER = 2 -- a word other players used this many times this session counts as a real word
local LEARN_MAX = 5000 -- learned words per session, at most
local MAP_ROOT = 946 -- the Cosmic map: every zone and continent hangs under it
local CHAT_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL",
}
local ROSTER_EVENTS = { "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", "BN_FRIEND_INFO_CHANGED" }
local TAINTED_SEND = "Autocorrect changed this line before chat was locked for the fight, so the game may drop it. If it didn't show up, send it again."

local UI = ns.UI
local IsSecret = ns.IsSecret

local module, db, dict
local ctx = { names = {}, places = {}, places2 = {} }
local boxes = {} -- [edit box] = true: the boxes hooked (permanent chat windows only)
local pending -- { box, change }: the last fix, while Backspace can still undo it
local pausedShown -- the "paused in combat chat" note was shown this lockdown
local changed = {} -- [edit box] = true: we set its text since it last opened or sent
local seen, learned = {}, 0 -- [word] = times other players used it; how many became words

-- Context ------------------------------------------------------------------------------------------------------------

local function AddName(set, name)
	if type(name) ~= "string" or IsSecret(name) then
		return
	end
	name = name:match("^[^%-]+")
	if name and name ~= "" then
		set[name:lower()] = true
	end
end

-- People's names: never corrected.
local function GatherNames()
	local names = {}
	AddName(names, UnitName("player"))
	if C_FriendList and C_FriendList.GetNumFriends then
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local info = C_FriendList.GetFriendInfoByIndex(i)
			AddName(names, info and info.name)
		end
	end
	if IsInGuild() then
		for i = 1, GetNumGuildMembers() or 0 do
			AddName(names, (GetGuildRosterInfo(i)))
		end
	end
	local unit = IsInRaid() and "raid" or "party"
	for i = 1, GetNumGroupMembers() or 0 do
		AddName(names, (UnitName(unit .. i)))
	end
	if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts then
		for i = 1, BNGetNumFriends() or 0 do
			for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
				local account = C_BattleNet.GetFriendGameAccountInfo(i, j)
				AddName(names, account and account.characterName)
			end
		end
	end
	for name in pairs(ctx.chatNames or {}) do
		names[name] = true
	end
	ctx.names = names
end

local function AddKnown(name)
	if type(name) ~= "string" or IsSecret(name) then
		return
	end
	local words = {}
	for word in name:gmatch("%a[%a']*") do
		words[word] = true
	end
	ns.Autocorrect_AddWords(dict, words)
end

-- What the client can tell us: zone and continent names become places (Thunder Bluff), and their words, class names
-- and race names become known words. Once per session; a client without these just has fewer.
local function GatherGameWords()
	local mapNames = {}
	local ok, maps = pcall(C_Map.GetMapChildrenInfo, MAP_ROOT, nil, true)
	if ok and type(maps) == "table" then
		for _, info in ipairs(maps) do
			local name = info.name
			if type(name) == "string" and not IsSecret(name) and name ~= ""
				and (info.mapType == Enum.UIMapType.Zone or info.mapType == Enum.UIMapType.Continent) then
				mapNames[#mapNames + 1] = name
			end
		end
	end
	ns.Autocorrect_Places(mapNames, dict, ctx.places, ctx.places2)
	for _, name in ipairs(mapNames) do
		AddKnown(name)
	end
	for _, list in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
		for _, name in pairs(list or {}) do
			AddKnown(name)
		end
	end
	if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
		for id = 1, 100 do
			local info = C_CreatureInfo.GetRaceInfo(id)
			AddKnown(info and info.raceName)
		end
	end
end

local function EnsureDict()
	if dict then
		return
	end
	dict = ns.Autocorrect_NewDict(ns.AUTOCORRECT_WORDS, ns.AUTOCORRECT_UPPER, ns.AUTOCORRECT_CONTRACTIONS)
	ctx.places, ctx.places2 = ns.Autocorrect_Places(ns.AUTOCORRECT_PLACES, dict)
	GatherGameWords()
	GatherNames()
end

-- Frees the word list (several MB) while the module is off.
local function DropDict()
	dict, ctx.dict = nil, nil
	ctx.places, ctx.places2, ctx.names, ctx.chatNames = {}, {}, {}, nil
	seen, learned = {}, 0
end

-- The rules' context, from the current db (a reset or profile import replaces its tables).
local function Ctx()
	ctx.dict, ctx.kinds, ctx.own, ctx.keep, ctx.refused = dict, db.kinds, db.own, db.keep, db.refused
	return ctx
end

-- Chat messaging lockdown (encounters, Mythic+, PvP matches): anything we type into the box would be dropped.
local function Restricted()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local locked = C_ChatInfo.InChatMessagingLockdown()
		if locked or IsSecret(locked) then
			return true
		end
	end
	if C_CVar and C_CVar.GetCVar("addonChatRestrictionsForced") == "1" then
		return true
	end
	return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
		or false
end

-- Edit box ---------------------------------------------------------------------------------------------------------

local function ClearPending()
	pending = nil
	ns.AutocorrectNote_Hide()
end

-- The cursor as a byte offset into text, or nil when it can't be trusted. Plain ASCII: the cursor counts bytes. With
-- a link or other multi-byte text only the end of the line is safe (it's not measured whether the box counts bytes or
-- characters there), which is where the player types anyway.
local function Cursor(box, text)
	local cursor = box:GetCursorPosition()
	if not text:find("[|\128-\255]") then
		return cursor
	end
	if cursor == #text or cursor == strlenutf8(text) then
		return #text
	end
	return nil
end

local function OnChar(box, char)
	if not (module.active and dict) then
		return
	end
	if not ns.AUTOCORRECT_BOUNDARY[char] then
		ClearPending()
		return
	end
	if Restricted() then
		ClearPending()
		if not pausedShown then
			pausedShown = true
			ns.AutocorrectNote_Paused(box)
		end
		return
	end
	pausedShown = false
	local text = box:GetText()
	if type(text) ~= "string" or IsSecret(text) then
		return
	end
	local cursor = Cursor(box, text)
	local newText, newCursor, change
	if cursor then
		newText, newCursor, change = ns.Autocorrect_Finish(text, cursor, Ctx())
	end
	if not newText then
		ClearPending()
		return
	end
	box:SetText(newText)
	box:SetCursorPosition(newCursor)
	changed[box] = true
	pending = { box = box, change = change }
	if db.note then
		ns.AutocorrectNote_Show(box, change.typed, change.fix)
	else
		ns.AutocorrectNote_Hide()
	end
end

local function Remember(change)
	if change.remember then
		local list = db.refused[change.remember] or {}
		list[change.rememberFix] = true
		db.refused[change.remember] = list
	end
end

-- Backspace right after a fix: the line as typed. OnKeyDown runs before the box acts on the key (EllesmereUIChat
-- relies on that order for Enter), so the undone line gets one extra character before the cursor for the box's own
-- Backspace to delete. Should the box ignore that Backspace, the next frame finds the extra character still there and
-- sets the line straight.
local function OnKeyDown(box, key)
	if not (module.active and pending and pending.box == box and key == "BACKSPACE") or IsModifierKeyDown() then
		return
	end
	local change = pending.change
	local text = box:GetText()
	local before, at
	if type(text) == "string" and not IsSecret(text) then
		local cursor = Cursor(box, text)
		before, at = ns.Autocorrect_Undo(text, cursor, change)
	end
	ClearPending()
	if not before then
		return
	end
	local planted = before:sub(1, at) .. " " .. before:sub(at + 1)
	box:SetText(planted)
	box:SetCursorPosition(at + 1)
	changed[box] = true
	C_Timer.After(0, function()
		if box:GetText() == planted then
			box:SetText(before)
			box:SetCursorPosition(at)
		end
	end)
	Remember(change)
end

-- Enter: the last word has no space after it yet. A line we changed before chat locked down is a tainted send now,
-- which the game drops: say so, since it can't be undone.
local function OnPreSend(_, box)
	if not (module.active and dict and boxes[box]) then
		return
	end
	ClearPending()
	local wasChanged = changed[box]
	changed[box] = nil
	if Restricted() then
		if wasChanged then
			ns.Print(TAINTED_SEND)
		end
		return
	end
	local text = box:GetText()
	if type(text) ~= "string" or IsSecret(text) or text == "" then
		return
	end
	local newText = ns.Autocorrect_Finish(text, #text, Ctx(), true)
	if newText then
		box:SetText(newText)
	end
end

local function OnBoxHide(_, box)
	ClearPending()
	pausedShown = false
	changed[box] = nil
end

-- The undo only holds while the player is still on the line.
local function OnFocusLost()
	ClearPending()
end

-- Hooks can't be undone: each checks module.active first.
local function HookBoxes()
	for i = 1, NUM_CHAT_WINDOWS do
		local box = _G["ChatFrame" .. i .. "EditBox"]
		if box and not boxes[box] then
			boxes[box] = true
			box:HookScript("OnChar", OnChar)
			box:HookScript("OnKeyDown", OnKeyDown)
		end
	end
end

-- Events -------------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, event, ...)
end))

local namesSoon = UI.Debounce(NAMES_DELAY, function()
	if module.active and dict then
		GatherNames()
	end
end)
for _, event in ipairs(ROSTER_EVENTS) do
	events[event] = namesSoon
end

-- Words other players use (twice) are real words to this session: their slang, names and guild terms are never
-- "fixed". The player's own lines don't count, or their typos would teach themselves.
local function OnChat(_, _, msg, sender, ...)
	local guid = select(10, ...)
	if type(msg) ~= "string" or IsSecret(msg) or IsSecret(guid) or guid == UnitGUID("player") or not dict then
		return
	end
	if type(sender) == "string" and not IsSecret(sender) then
		local name = sender:match("^[^%-]+")
		if name then
			ctx.chatNames = ctx.chatNames or {}
			ctx.chatNames[name:lower()] = true
			ctx.names[name:lower()] = true
		end
	end
	if learned >= LEARN_MAX then
		return
	end
	msg = msg:gsub("|H.-|h", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	for word in msg:gmatch("%a[%a']*") do
		local lower = word:lower()
		if #lower >= 3 and not dict.level[lower] then
			seen[lower] = (seen[lower] or 0) + 1
			if seen[lower] >= LEARN_AFTER then
				ns.Autocorrect_AddWords(dict, { [lower] = true })
				seen[lower] = nil
				learned = learned + 1
			end
		end
	end
end
for _, event in ipairs(CHAT_EVENTS) do
	events[event] = OnChat
end

local function Start()
	EnsureDict()
	HookBoxes()
	for _, event in ipairs(ROSTER_EVENTS) do
		pcall(events.RegisterEvent, events, event) -- BN_FRIEND_INFO_CHANGED may not exist on every client
	end
	for _, event in ipairs(CHAT_EVENTS) do
		events:RegisterEvent(event)
	end
	if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster() -- the roster can be empty right after login; GUILD_ROSTER_UPDATE refreshes names
	end
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", OnPreSend, OWNER)
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxHide", OnBoxHide, OWNER)
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", OnFocusLost, OWNER)
end

local function Stop()
	events:UnregisterAllEvents()
	EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxPreSendText", OWNER)
	EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxHide", OWNER)
	EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxFocusLost", OWNER)
	ClearPending()
	pausedShown = false
	wipe(changed)
	DropDict()
end

-- Commands -----------------------------------------------------------------------------------------------------------

local function Keep(_, raw)
	local word = raw and raw:match("^(%S+)")
	if not word then
		ns.Print("usage: /tomte autocorrect keep <word>")
		return
	end
	db.keep[word:lower()] = true
	ns.Print("Autocorrect leaves " .. UI.Wrap(word, "accent") .. " alone from now on.")
end

local function Add(_, raw)
	local typo, fix = (raw or ""):match("^(%S+)%s+(.+)$")
	if not typo then
		ns.Print("usage: /tomte autocorrect add <typo> <fix>")
		return
	end
	fix = fix:match("^%s*(.-)%s*$")
	db.own[typo:lower()] = fix
	if db.refused[typo:lower()] then
		db.refused[typo:lower()][fix:lower()] = nil
	end
	ns.Print("Autocorrect now fixes " .. UI.Wrap(typo, "textMuted") .. " > " .. UI.Wrap(fix, "success") .. ".")
end

local function Forget(_, raw)
	local word = raw and raw:match("^(.-)%s*$")
	if not word or word == "" then
		ns.Print("usage: /tomte autocorrect forget <word>")
		return
	end
	local lower = word:lower()
	local found = db.keep[lower] or db.own[lower] or db.refused[lower]
	db.keep[lower], db.own[lower], db.refused[lower] = nil, nil, nil
	ns.Print(found and ("Autocorrect forgot what you told it about " .. UI.Wrap(word, "accent") .. ".")
		or ("Autocorrect had nothing saved for " .. word .. "."))
end

local function SortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

local function List()
	local keep = SortedKeys(db.keep)
	ns.Print("words you keep: " .. (#keep > 0 and table.concat(keep, ", ") or "none"))
	local own = {}
	for _, typo in ipairs(SortedKeys(db.own)) do
		own[#own + 1] = typo .. " > " .. db.own[typo]
	end
	ns.Print("your corrections: " .. (#own > 0 and table.concat(own, ", ") or "none"))
	local refused = {}
	for _, typed in ipairs(SortedKeys(db.refused)) do
		for _, fix in ipairs(SortedKeys(db.refused[typed])) do
			refused[#refused + 1] = typed .. " > " .. fix
		end
	end
	ns.Print("fixes you undid (never made again): " .. (#refused > 0 and table.concat(refused, ", ") or "none"))
end

local function Why(_, raw)
	local word = raw and raw:match("^(%S+)")
	if not word then
		ns.Print("usage: /tomte autocorrect why <word>")
		return
	end
	local temporary = not dict
	EnsureDict()
	local fix, kind, reason = ns.Autocorrect_Word(word, Ctx())
	if fix then
		ns.Print(UI.Wrap(word, "textMuted") .. " > " .. UI.Wrap(fix, "success") .. " (" .. kind .. "): " .. reason
			.. ".")
	else
		ns.Print(UI.Wrap(word, "accent") .. " stays: " .. reason .. ".")
	end
	if temporary then
		DropDict()
	end
end

-- Registration -------------------------------------------------------------------------------------------------------

local function Clear(key, what)
	return function()
		wipe(db[key])
		ns.Print("Autocorrect: " .. what .. " cleared.")
	end
end

module = ns.RegisterModule({
	key = "autocorrect",
	name = "Autocorrect",
	category = "chat",
	icon = 237171, -- inv_inscription_tradeskill01
	summary = "Fixes typos in your chat as you type; Backspace undoes a fix.",
	description = "Fixes your chat as you type: common typos and misspelled words, missing apostrophes (dont), capitals at the start of a sentence, place names (stormwind), word pairs (could of) and doubled words. A note above the chat box shows each fix, and Backspace right after puts your word back and remembers it. Leaves commands, links, names, numbers and chat shorthand alone. Pauses in boss fights, Mythic+ and PvP matches, where the game blocks addon-changed chat. English only.",
	enabledByDefault = false,
	defaults = {
		kinds = { spelling = true, apostrophes = true, capitals = true, names = true, pairs = true, tidying = true },
		note = true,
		refused = {}, -- [typed, lowercase] = { [fix, lowercase] = true }: fixes the player undid
		keep = {}, -- [word, lowercase] = true: never touched
		own = {}, -- [typo, lowercase] = fix: the player's own corrections
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = { -- all of them work while the module is off (they only read or change your saved words)
		{ "keep", "<word>: never change this word", Keep, whileOff = true },
		{ "add", "<typo> <fix>: a correction of your own", Add, whileOff = true },
		{ "forget", "<word>: drop what you told it about a word, and fixes you undid for it", Forget,
			whileOff = true },
		{ "list", "the words you keep, your corrections and the fixes you undid", List, whileOff = true },
		{ "why", "<word>: what it would do with a word, and why", Why, whileOff = true },
	},
	options = {
		{ type = "header", label = "Fixes" },
		{ type = "checkbox", key = "kinds.spelling", label = "Spelling",
			tooltip = "Common typos (teh, recieve), and misspelled words with one clear nearest match (kontest). A word it isn't sure about stays as you typed it." },
		{ type = "checkbox", key = "kinds.apostrophes", label = "Apostrophes",
			tooltip = "dont, im, youre become don't, I'm, you're." },
		{ type = "checkbox", key = "kinds.capitals", label = "Capitals",
			tooltip = "A capital at the start of each sentence, and I on its own." },
		{ type = "checkbox", key = "kinds.names", label = "Place names",
			tooltip = "stormwind, old town become Stormwind, Old Town." },
		{ type = "checkbox", key = "kinds.pairs", label = "Word pairs",
			tooltip = "could of, your late, ill meet become could have, you're late, I'll meet." },
		{ type = "checkbox", key = "kinds.tidying", label = "Tidying",
			tooltip = "Doubled words (the the) and words run together (tothe)." },
		{ type = "header", label = "Note" },
		{ type = "checkbox", key = "note", label = "Show each fix above the chat box",
			tooltip = "A small note with your word and the fix. Backspace right after a fix puts your word back, note or not." },
		{ type = "header", label = "Your words" },
		{ type = "button", label = "Words you keep", text = "Clear", onClick = Clear("keep", "words you keep"),
			confirm = "Clear the words you told Autocorrect to keep?",
			tooltip = "Added with /tomte autocorrect keep <word>." },
		{ type = "button", label = "Your corrections", text = "Clear", onClick = Clear("own", "your corrections"),
			confirm = "Clear your own corrections?", tooltip = "Added with /tomte autocorrect add <typo> <fix>." },
		{ type = "button", label = "Fixes you undid", text = "Clear", onClick = Clear("refused", "fixes you undid"),
			confirm = "Let Autocorrect make the fixes you undid again?",
			tooltip = "A fix you undo with Backspace is never made again. This lets it come back." },
	},
})
