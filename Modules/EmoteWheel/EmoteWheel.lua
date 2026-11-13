local addonName, ns = ...

-- Emote wheel: hold a key, flick the mouse towards a slice, let go, and its emote or chat line goes out (to your
-- target). The key is an override binding that clicks a hidden button: its press opens the wheel, its release (a
-- hardware event, which /say needs outside instances) runs the slice. Also buff thanks (Thanks.lua). Rules in
-- Data.lua, the wheel in Wheel.lua.

local BUTTON_NAME = "TomteEmoteWheelKey" -- SetOverrideBindingClick needs a named button
local OWNER = "wheel"
local STUCK = 30 -- seconds: a wheel still open this long lost its key release (alt-tab) and closes on its own
local PREVIEW_PICK = 2 -- the slice a preview highlights
local PAGE_KEY = "emotewheel" -- the editor page (Page.lua)
-- Secure slash commands (Blizzard's SecureCmdList is private): the wheel can't run these.
local SECURE = { "CAST", "USE", "CASTSEQUENCE", "CASTRANDOM", "USERANDOM", "TARGET", "TARGET_EXACT", "TARGET_NEAREST_ENEMY",
	"ASSIST", "FOCUS", "CLEARTARGET", "CLEARFOCUS", "STOPCASTING", "STOPATTACK", "STARTATTACK", "PETATTACK", "CLICK",
	"EQUIP", "EQUIP_TO_SLOT", "SWAPACTIONBAR", "CHANGEACTIONBAR", "CANCELAURA", "CANCELFORM", "DISMOUNT",
	"STOPMACRO", "CLEARMAINTANK", "MAINTANK", "WORLD_MARKER", "CLEAR_WORLD_MARKER", "TARGET_MARKER" }
local CHAT_TYPES = { "SAY", "YELL", "EMOTE", "PARTY", "RAID", "RAID_WARNING", "INSTANCE_CHAT", "GUILD", "OFFICER",
	"WHISPER" }
local SLICES = { -- the starting wheel; empty slots up to EMOTEWHEEL_MAX
	{ "Thank", "/ty" }, { "Bow", "/bow" }, { "Wave", "/wave" }, { "Kiss", "/kiss" },
	{ "Cheer", "/cheer" }, { "Laugh", "/lol" }, { "Hug", "/hug" }, { "Salute", "/salute" },
}
local UI = ns.UI

local events = ns.EmoteWheel_Events
local db
local owner -- owns the override binding
local button
local pending = false -- a binding change waits for combat to end
local openedAt
local active = false -- between Start and Stop
local fixedLookups -- chat types, emotes and secure commands: the same all session

local function DefaultSlots()
	local slots = {}
	for i = 1, ns.EMOTEWHEEL_MAX do
		local s = SLICES[i]
		slots["s" .. i] = { name = s and s[1] or "", text = s and s[2] or "" }
	end
	return slots
end

-- Running a slice -----------------------------------------------------------------------------------------------------

-- Each "/cmd" (upper-cased) of a localized slash global family: SLASH_<key>1, SLASH_<key>2, ...
local function AddSlashes(into, key, value)
	local i = 1
	while true do
		local cmd = _G["SLASH_" .. key .. i]
		if type(cmd) ~= "string" then
			return
		end
		into[cmd:upper()] = value
		i = i + 1
	end
end

-- What the chat box knows, the way ChatFrameUtil.ImportEmoteTokensToHash reads it (localized, from the globals).
local function Lookups()
	if not fixedLookups then
		local chat, emotes, secure = {}, {}, {}
		for _, chatType in ipairs(CHAT_TYPES) do
			AddSlashes(chat, chatType, chatType)
		end
		for i = 1, MAXEMOTEINDEX or 0 do
			local token = _G["EMOTE" .. i .. "_TOKEN"]
			if token then
				local j = 1
				while _G["EMOTE" .. i .. "_CMD" .. j] do
					emotes[_G["EMOTE" .. i .. "_CMD" .. j]:upper()] = token
					j = j + 1
				end
			end
		end
		for _, key in ipairs(SECURE) do
			AddSlashes(secure, key, true)
		end
		fixedLookups = { chat = chat, emotes = emotes, secure = secure }
	end
	-- Addons add slash commands as they load: read SlashCmdList each time (a key release, not a hot path).
	local slash = {}
	for key in pairs(SlashCmdList) do
		AddSlashes(slash, key, key)
	end
	fixedLookups.slash = slash
	return fixedLookups
end

ns.EmoteWheel_Lookups = Lookups

-- The game's own command for each chat line the editor builds ("/s", "/p", ... localized).
function ns.EmoteWheel_LineCommands()
	local commands = {}
	for _, chatType in ipairs(ns.EMOTEWHEEL_LINE_TYPES) do
		commands[chatType] = _G["SLASH_" .. chatType .. "1"]
	end
	return commands
end

local emoteList -- every emote the chat box knows: the same all session

-- Every emote, by name: { { name = "Wave", token = "WAVE", commands = { "/wave", ... } }, ... }.
function ns.EmoteWheel_Emotes()
	if not emoteList then
		emoteList = {}
		for i = 1, MAXEMOTEINDEX or 0 do
			local token = _G["EMOTE" .. i .. "_TOKEN"]
			local first = _G["EMOTE" .. i .. "_CMD1"]
			if token and first then
				local commands, j = {}, 1
				while _G["EMOTE" .. i .. "_CMD" .. j] do
					commands[j] = _G["EMOTE" .. i .. "_CMD" .. j]
					j = j + 1
				end
				emoteList[#emoteList + 1] = { name = ns.EmoteWheel_Label({ text = first }), token = token,
					commands = commands }
			end
		end
		table.sort(emoteList, function(a, b)
			return a.name:lower() < b.name:lower()
		end)
	end
	return emoteList
end

-- The slices as the editor page edits them (copies: { name, text }, in order) and back.
function ns.EmoteWheel_EditList()
	local list = {}
	for i, slice in ipairs(ns.EmoteWheel_Slices(db.slots)) do
		list[i] = { name = slice.name, text = slice.text }
	end
	return list
end

function ns.EmoteWheel_SaveList(list)
	db.slots = ns.EmoteWheel_Store(list)
end

function ns.EmoteWheel_ResetSlices()
	db.slots = DefaultSlots()
end

-- How the editor page draws the wheel: as set, but %t left as it is.
function ns.EmoteWheel_Look()
	return { showCommand = db.showCommand, alpha = 1 }
end

-- Your target's name for %t (with the realm when it isn't yours), or nil.
local function TargetName()
	if not UnitExists("target") then
		return nil
	end
	local name, realm = UnitName("target")
	if not name or ns.IsSecret(name, realm) then
		return nil
	end
	return ns.EmoteWheel_FullName(name, realm)
end

local function ChatLocked()
	return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function Run(slice)
	local text = ns.EmoteWheel_Fill(slice.text, TargetName())
	if not text then
		ns.Print(("%s needs a target."):format(UI.Wrap(ns.EmoteWheel_Label(slice), "accent")))
		return
	end
	local action = ns.EmoteWheel_Parse(text, Lookups())
	if not action then
		ns.Print(("%s has nothing to send: %s"):format(UI.Wrap(ns.EmoteWheel_Label(slice), "accent"), text))
	elseif action.kind == "emote" then
		ns.Chat_Emote(action.token, action.target)
	elseif action.kind == "chat" then
		if ChatLocked() then
			ns.Print("Chat is locked right now; try again after the fight.")
			return
		end
		ns.Chat_Send(action.text, action.chatType, nil, action.target)
	elseif action.kind == "slash" then
		-- Another addon's (or Blizzard's) command: it may error on what it was given.
		local editBox = ChatFrame1EditBox
		local ok, err = pcall(SlashCmdList[action.key], action.msg, editBox)
		if not ok then
			ns.Print(("%s failed: %s"):format(text, tostring(err)))
		end
	elseif action.kind == "secure" then
		ns.Print(("The wheel can't run %s: the game only lets its own buttons and macros do that."):format(
			action.command))
	else
		ns.Print(("Unknown command: %s"):format(action.command))
	end
end

-- The key ---------------------------------------------------------------------------------------------------------------

local function Options()
	return {
		scale = db.scale,
		alpha = db.alpha,
		showCommand = db.showCommand,
		showTarget = db.showTarget,
		centerCancels = db.centerCancels,
		cancelText = db.centerCancels and "Cancel" or nil,
		target = TargetName(),
	}
end

local function Close(run)
	openedAt = nil
	local slice = ns.EmoteWheel_Close()
	if run and slice then
		Run(slice)
	end
end

local function Open()
	local slices = ns.EmoteWheel_Slices(db.slots)
	if #slices == 0 then
		ns.Print("The emote wheel has no slices: add some in its settings.")
		return
	end
	openedAt = GetTime()
	ns.EmoteWheel_Open(slices, Options())
	C_Timer.After(STUCK, function()
		if openedAt and GetTime() - openedAt >= STUCK then
			Close(false)
		end
	end)
end

local function OnKey(_, _, down)
	if not active then
		return
	end
	if down then
		Open()
	elseif ns.EmoteWheel_IsOpen() then
		Close(true)
	end
end

local function Button()
	if not button then
		button = CreateFrame("Button", BUTTON_NAME, UIParent)
		button:Hide()
		button:RegisterForClicks("AnyDown", "AnyUp")
		button:SetScript("OnClick", OnKey)
	end
	return button
end

-- Override bindings can't change in combat: a change then waits for its end.
local function ApplyKey()
	if InCombatLockdown() then
		pending = true
		events:Watch(OWNER, "PLAYER_REGEN_ENABLED")
		return
	end
	pending = false
	owner = owner or CreateFrame("Frame")
	ClearOverrideBindings(owner)
	if active and type(db.key) == "string" and db.key ~= "" then
		SetOverrideBindingClick(owner, true, db.key, Button():GetName(), "LeftButton")
	end
end

events:On(OWNER, "PLAYER_REGEN_ENABLED", function()
	events:Unwatch(OWNER, "PLAYER_REGEN_ENABLED")
	if pending then
		ApplyKey()
	end
end)

local function Start()
	active = true
	ApplyKey()
	ns.EmoteWheelThanks_Apply(true)
end

local function Stop()
	active = false
	Close(false)
	ApplyKey()
	ns.EmoteWheelThanks_Apply(false)
end

-- Settings ------------------------------------------------------------------------------------------------------------

local function Percent(v)
	return ("%d%%"):format(math.floor(v * 100 + 0.5))
end

-- The wheel as the settings stand (get reads them, the row's own value under the mouse), one slice lit.
local function WheelPreview()
	return function(host, get)
		local slices = ns.EmoteWheel_Slices(get("slots"))
		if #slices == 0 then
			return nil
		end
		return ns.EmoteWheel_Draw(host, slices, {
			scale = 0.85, -- the preview card's own limit would shrink a full-size wheel anyway
			alpha = get("alpha"),
			showCommand = get("showCommand"),
			showTarget = get("showTarget"),
			target = "Aldric",
		}, math.min(PREVIEW_PICK, #slices))
	end
end

local function Opts()
	local options = {
		{ type = "header", label = "Wheel" },
		{ type = "key", key = "key", label = "Hold to open", onChange = ApplyKey, preview = WheelPreview(),
			tooltip = "Hold this key or mouse button: the wheel opens at your cursor. Move towards a slice and let go. "
				.. "Click, then press a key or a mouse button (middle, 4 or 5); right-click clears it." },
		{ type = "slider", key = "scale", label = "Size", min = 0.6, max = 1.6, step = 0.05, format = Percent },
		{ type = "slider", key = "alpha", label = "Opacity", min = 0.3, max = 1, step = 0.05, format = Percent,
			preview = WheelPreview() },
		{ type = "checkbox", key = "showCommand", label = "Show the command under the name",
			preview = WheelPreview() },
		{ type = "checkbox", key = "centerCancels", label = "Letting go in the middle cancels",
			tooltip = "Off: letting go in the middle sends the last slice you pointed at." },
		{ type = "checkbox", key = "showTarget", label = "Show your target in the middle", preview = WheelPreview() },
		{ type = "button", label = "Slices", text = "Edit the wheel", preview = WheelPreview(), onClick = function()
			ns.Panel_OpenPage(PAGE_KEY)
		end, tooltip = "Pick emotes from a list, write chat lines, and drag slices around the wheel." },
	}

	local thanks = {
		{ type = "header", label = "Buff thanks" },
		{ type = "checkbox", key = "thanks.on", label = "Offer to thank who buffs you",
			onChange = function()
				ns.EmoteWheelThanks_Apply(active)
			end,
			tooltip = "When another player gives you a buff that lasts 10 minutes or more, out of combat, a toast says "
				.. "who. Click it to thank them, right-click to dismiss it." },
		{ type = "dropdown", key = "thanks.how", label = "Thank them by", parent = "thanks.on", choices = function()
			return { { value = "say", text = "Saying it" }, { value = "whisper", text = "Whisper" },
				{ value = "emote", text = "/thank" } }
		end },
		{ type = "input", key = "thanks.line", label = "What to say", parent = "thanks.on",
			placeholder = ns.EMOTEWHEEL_THANK_LINE, shown = function()
				return db.thanks.how ~= "emote"
			end, tooltip = "%t becomes their name and %b the buff." },
		{ type = "checkbox", key = "thanks.instances", label = "Also in dungeons and raids", parent = "thanks.on",
			tooltip = "Off: only out in the world, where a buff from a stranger is a kindness and not the group's routine." },
		{ type = "button", label = "Try it", text = "Show", parent = "thanks.on", onClick = function()
			ns.EmoteWheelThanks_Sample()
		end, tooltip = "Show a sample thank-you toast. Clicking it sends nothing." },
	}
	for _, row in ipairs(thanks) do
		options[#options + 1] = row
	end
	return options
end

ns.RegisterModule({
	key = "emotewheel",
	name = "Emote Wheel",
	category = "social",
	icon = 236550, -- achievement_halloween_smiley_01
	summary = "Hold a key, flick the mouse, let go: an emote or chat line for your target. And one click to thank "
		.. "who buffed you.",
	description = "Hold your chosen key or mouse button and a wheel of emotes opens at your cursor. Point at a slice "
		.. "and let go: its emote goes to your target. A slice can be any emote, chat command or line of text, and %t "
		.. "becomes your target's name. When another player buffs you, a toast offers to thank them with one click.",
	enabledByDefault = false,
	toasts = "Buff thanks",
	defaults = {
		key = "", -- a binding string ("BUTTON4", "CTRL-G"), held to open the wheel; "" for none
		scale = 1,
		alpha = 0.95,
		showCommand = true,
		centerCancels = true,
		showTarget = true,
		slots = DefaultSlots(), -- s1 .. s12 = { name, text }, clockwise from the top; text "" leaves a slot out
		thanks = { on = true, how = "say", line = "", instances = false }, -- how: "say" | "whisper" | "emote"
	},
	init = function(moduleDB)
		db = moduleDB
		ns.EmoteWheelThanks_Init(db)
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	home = {
		{ kind = "page", key = PAGE_KEY, order = 90, name = "Emote wheel", icon = 236550, noRail = true,
			page = ns.EmoteWheelPage,
			summary = function()
				return "The slices on your emote wheel: emotes, chat lines and their order."
			end },
	},
	commands = {
		{ "edit", "open the wheel editor", function()
			ns.Panel_OpenPage(PAGE_KEY)
		end },
		{ "thanks", "show a sample buff thank-you toast", function()
			ns.EmoteWheelThanks_Sample()
		end },
		{ "slices", "list the wheel's slices and what each one does", function()
			local lookups = Lookups()
			for _, slice in ipairs(ns.EmoteWheel_Slices(db.slots)) do
				local action = ns.EmoteWheel_Parse(ns.EmoteWheel_Fill(slice.text, "Target") or slice.text, lookups)
				ns.Print(("%d. %s: %s -> %s"):format(slice.slot, ns.EmoteWheel_Label(slice), slice.text,
					action and action.kind .. (action.token and (" " .. action.token) or action.chatType
						and (" " .. action.chatType) or "") or "nothing"))
			end
		end },
	},
	options = Opts(),
})
