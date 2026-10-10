local addonName, ns = ...

-- Whispers module: every whisper (character or Battle.net) gets a toast (left-click replies, right-click
-- dismisses), back from AFK an unread recap stays on top of the toasts until you've answered or looked, and
-- an inbox window keeps the conversations. Toasts wait while a cinematic hides the UI (and, by default, during
-- combat) and come back as one "while you were busy" card. Optional extra sound on the Master channel.
-- Blizzard already flashes the taskbar icon for whispers.
-- In chat lockdown (instances, encounters, M+, PvP) the text and sender are secret: such whispers are shown
-- as they are (SetText takes secrets) but can't be compared or saved, so they live in a session-only
-- "In instance" conversation and reply goes to Blizzard's last tell target.

local OWNER = "whispers"
local BADGE = "whispers"
local RESTRICTED = "restricted" -- key of the session-only conversation with secret whispers
local DAY = 86400
-- Cards in the player's chat colors (ns.Toast_ChatColor): whisper pink, Battle.net whisper blue.
local WHISPER, BN_WHISPER = "WHISPER", "BN_WHISPER"
local GM_ACCENT = { 0.25, 0.75, 1 } -- theme: game meaning (GM); Blizzard has no GM chat color to read
local OUT_EVENTS = { "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM" }
local EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM",
	"PLAYER_FLAGS_CHANGED" }
local SAMPLES = {
	{ sender = "Thrall", class = "SHAMAN", text = "Raid tonight at 8, are you in?" },
	{ sender = "Jaina", class = "MAGE", text = "Left you a few Sunwell Shards in the mail." },
	{ sender = "Thrall", class = "SHAMAN", text = "Bring flasks!" },
}

local module
local MAX_RESTRICTED = 50 -- instance whispers kept this session
local restricted = { key = RESTRICTED, name = "In instance", restricted = true, unread = 0, messages = {} }
local bnTokens = {} -- [conversation key] = this session's |K account name, for replies
local recapUp = false -- the unread card is showing
local wasAFK = false

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Readable(...)
	return not canaccessallvalues or canaccessallvalues(...)
end

local function Store()
	return ns.whispersDB.store
end

-- "Name" -> "Name-Realm": whisper and inform events use full names, but not always for your own realm.
local function FullName(name)
	if not name:find("-", 1, true) then
		return name .. "-" .. GetNormalizedRealmName()
	end
	return name
end

-- Conversations for the inbox: the saved ones plus this session's secret ones.
function ns.Whispers_Convos()
	local list = ns.Social_SortedConvos(Store())
	if #restricted.messages > 0 then
		table.insert(list, 1, restricted)
	end
	return list
end

function ns.Whispers_Get(key)
	if key == RESTRICTED then
		return #restricted.messages > 0 and restricted or nil
	end
	return Store().convos[key]
end

local function UnreadTotal()
	local total, convos = ns.Social_Unread(Store())
	return total + restricted.unread, convos
end

-- The unread card only comes up when you're back from AFK; after that it follows the unread count until
-- everything's read (answered, opened in the inbox, or right-clicked).
local function UpdateBadge(show)
	local total, convos = UnreadTotal()
	if total == 0 or not ns.whispersDB.badge or not module.active then
		recapUp = false
		ns.Toast_Unpin(BADGE)
		return
	end
	if not (show or recapUp) then
		return
	end
	recapUp = true
	local names = {}
	for _, convo in ipairs(convos) do
		names[#names + 1] = ns.Inbox_ColoredName(convo)
	end
	if restricted.unread > 0 then
		names[#names + 1] = "in instance"
	end
	ns.Toast_Pin(BADGE, {
		owner = OWNER,
		label = "While you were away",
		accent = ns.Toast_ChatColor(WHISPER),
		title = total == 1 and "1 whisper" or (total .. " whispers"),
		text = "From " .. ns.Social_NameList(names, 3) .. ". Click to read, right-click to clear.",
		recentCount = total, -- Recent hears of it again only when this rises
		onClick = function()
			ns.Inbox_Toggle()
		end,
		onDismiss = function()
			ns.Whispers_MarkAllRead()
		end,
	})
end

local function Changed()
	UpdateBadge()
	ns.Inbox_Refresh()
end

function ns.Whispers_MarkRead(key)
	if key == RESTRICTED then
		restricted.unread = 0
	else
		ns.Social_MarkRead(Store(), key)
	end
	Changed()
end

function ns.Whispers_MarkAllRead()
	ns.Social_MarkAllRead(Store())
	restricted.unread = 0
	Changed()
end

-- This session's |K name for a Battle.net friend by BattleTag (saved conversations from earlier sessions).
local function FindBNetToken(battleTag)
	for i = 1, BNGetNumFriends() do
		local info = C_BattleNet.GetFriendAccountInfo(i)
		if info and info.battleTag == battleTag then
			return info.accountName
		end
	end
	return nil
end

-- Opens the chat box to answer this conversation.
function ns.Whispers_Reply(key)
	if key == RESTRICTED then
		-- Names are secret here: Blizzard keeps the last tell target itself.
		local ok = pcall(ChatFrameUtil.ReplyTell)
		if not ok then
			ns.Print("can't reply from here during instance chat restrictions; press R in chat instead.")
		end
		return
	end
	local convo = Store().convos[key]
	if not convo then
		return
	end
	if convo.bn then
		local token = bnTokens[key] or FindBNetToken(key:sub(4))
		if token then
			ChatFrameUtil.SendBNetTell(token)
		else
			ns.Print(convo.name .. " isn't online on Battle.net.")
		end
		return
	end
	ChatFrameUtil.SendTell(key)
end

-- This session's bnetAccountID for a BattleTag (what C_BattleNet.SendWhisper takes).
local function FindBNetAccountID(battleTag)
	for i = 1, BNGetNumFriends() do
		local info = C_BattleNet.GetFriendAccountInfo(i)
		if info and info.battleTag == battleTag then
			return info.bnetAccountID
		end
	end
	return nil
end

function ns.Whispers_CanSend(key)
	return key ~= nil and key ~= RESTRICTED and not (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
end

-- Sends from the inbox. Your whisper shows up in the conversation through the INFORM event.
-- Returns false when it couldn't go out here (the normal chat box is opened instead).
function ns.Whispers_Send(key, text)
	text = strtrim(text or "")
	if text == "" then
		return true
	end
	if not ns.Whispers_CanSend(key) then
		ns.Print("can't send from the inbox during instance chat restrictions; use the chat box.")
		ns.Whispers_Reply(key)
		return false
	end
	local convo = Store().convos[key]
	local ok, err
	if convo and convo.bn then
		local id = FindBNetAccountID(key:sub(4))
		if not id then
			ns.Print(convo.name .. " isn't online on Battle.net.")
			return false
		end
		local sent
		ok, sent = pcall(C_BattleNet.SendWhisper or BNSendWhisper, id, text)
		if not ok then
			err = sent
		elseif sent == false then
			ok, err = false, "Battle.net refused the whisper"
		end
	else
		ok, err = pcall(C_ChatInfo.SendChatMessage or SendChatMessage, text, "WHISPER", nil, key)
	end
	if not ok then
		ns.Print("couldn't send: " .. tostring(err))
	end
	ns.Whispers_MarkRead(key)
	return ok
end

-- The reply keybind: the newest unread conversation, else whoever whispered last.
function ns.Whispers_ReplyNewest()
	local _, convos = UnreadTotal()
	if restricted.unread > 0 then
		ns.Whispers_Reply(RESTRICTED)
	elseif convos[1] then
		ns.Whispers_MarkRead(convos[1].key)
		ns.Whispers_Reply(convos[1].key)
	else
		ChatFrameUtil.ReplyTell()
	end
end

local function PlayWhisperSound()
	ns.Social_PlaySound(ns.whispersDB.sound)
end

-- info = { key, name (display, may be secret), digestName, class, bn, gm, text (may be secret), secret }
local function Toast(info)
	if not ns.whispersDB.toasts then
		return
	end
	local accent = info.gm and GM_ACCENT or ns.Toast_ChatColor(info.bn and BN_WHISPER or WHISPER)
	local title = info.name
	local icon
	if not info.secret and info.class then
		local color = C_ClassColor.GetClassColor(info.class)
		if color then
			title = color:WrapTextInColorCode(info.name)
		end
		icon = GetClassAtlas(info.class:lower())
	end
	ns.Toast_Show({
		owner = OWNER,
		label = info.gm and "Game Master" or (info.bn and "Battle.net whisper" or "Whisper"),
		accent = accent,
		title = title,
		-- A Battle.net title is the |K account name: Recent saves the BattleTag's name instead.
		recentTitle = not info.secret and info.bn and info.digestName or nil,
		test = info.preview or nil,
		text = info.text,
		chat = true,
		secret = info.secret,
		iconAtlas = icon and C_Texture.GetAtlasInfo(icon) and icon or nil,
		mergeKey = not info.secret and info.key or nil,
		digestName = info.digestName,
		holdInCombat = ns.whispersDB.holdInCombat,
		onClick = function()
			if info.preview then
				return
			end
			ns.Whispers_MarkRead(info.key)
			ns.Whispers_Reply(info.key)
		end,
		onDismiss = function()
			if not info.preview then
				ns.Whispers_MarkRead(info.key)
			end
		end,
	})
end

local function Digest(held)
	local count, names = ns.Social_Digest(held)
	local secret = 0
	for _, spec in ipairs(held) do
		if not spec.digestName then
			secret = secret + 1
		end
	end
	if secret > 0 then
		names[#names + 1] = secret == 1 and "someone in the instance" or "others in the instance"
	end
	return {
		owner = OWNER,
		label = "While you were busy",
		accent = ns.Toast_ChatColor(WHISPER),
		title = count .. " whispers",
		text = "From " .. ns.Social_NameList(names, 4) .. ". Click to read.",
		onClick = function()
			ns.Inbox_Toggle()
		end,
	}
end

local function Incoming(info)
	local viewing = ns.Inbox_IsShowing(info.key)
	if info.secret then
		local messages = restricted.messages
		messages[#messages + 1] = { at = time(), text = info.text, sender = info.name }
		if #messages > MAX_RESTRICTED then
			table.remove(messages, 1)
		end
		restricted.last = time()
		if not viewing then
			restricted.unread = restricted.unread + 1
		end
	else
		ns.Social_AddMessage(Store(), info.key, { name = info.digestName, class = info.class, bn = info.bn },
			{ at = time(), text = info.text })
		if viewing then
			ns.Social_MarkRead(Store(), info.key)
		end
	end
	Changed()
	PlayWhisperSound()
	if not viewing then
		Toast(info)
	end
end

function events:CHAT_MSG_WHISPER(text, sender, _, _, _, flags, _, _, _, _, _, guid)
	if not Readable(text, sender) then
		-- Ambiguate on a secret sender isn't known to be allowed: fall back to the full name.
		local ok, short = pcall(Ambiguate, sender, "short")
		Incoming({ key = RESTRICTED, name = ok and short or sender, text = text, secret = true })
		return
	end
	local class
	if guid and Readable(guid) and guid ~= "" then
		local _, englishClass = GetPlayerInfoByGUID(guid)
		class = englishClass
	end
	local short = Ambiguate(sender, "short")
	Incoming({ key = FullName(sender), name = short, digestName = short, class = class, text = text,
		gm = Readable(flags) and (flags == "GM" or flags == "DEV") })
end

-- sender is the |K account name: shows the real name, but can't be read or saved. The BattleTag is the key.
function events:CHAT_MSG_BN_WHISPER(text, sender, _, _, _, _, _, _, _, _, _, _, bnSenderID)
	if not Readable(text, sender, bnSenderID) then
		Incoming({ key = RESTRICTED, name = sender, text = text, secret = true, bn = true })
		return
	end
	local info = bnSenderID and C_BattleNet.GetAccountInfoByID(bnSenderID)
	if not (info and info.battleTag) then
		return
	end
	local key = "bn:" .. info.battleTag
	bnTokens[key] = sender
	local game = info.gameAccountInfo
	Incoming({ key = key, name = sender, digestName = ns.Social_ShortTag(info.battleTag), bn = true, text = text,
		class = game and game.isOnline and game.classFilename or nil })
end

-- Your own whispers: kept in the conversation, which counts as answered.
local function Outgoing(key, text, info)
	ns.Social_AddMessage(Store(), key, info, { at = time(), text = text, out = true })
	Changed()
end

function events:CHAT_MSG_WHISPER_INFORM(text, target)
	if not Readable(text, target) then
		restricted.unread = 0 -- answered someone in the instance; we can't tell whom
		Changed()
		return
	end
	Outgoing(FullName(target), text, { name = Ambiguate(target, "short") })
end

function events:CHAT_MSG_BN_WHISPER_INFORM(text, target, _, _, _, _, _, _, _, _, _, _, bnSenderID)
	if not Readable(text, target, bnSenderID) then
		restricted.unread = 0
		Changed()
		return
	end
	local info = bnSenderID and C_BattleNet.GetAccountInfoByID(bnSenderID)
	if info and info.battleTag then
		local key = "bn:" .. info.battleTag
		bnTokens[key] = target
		Outgoing(key, text, { name = ns.Social_ShortTag(info.battleTag), bn = true })
	end
end

-- Back from AFK with unread whispers: one recap card instead of the toasts still up or held back.
function events:PLAYER_FLAGS_CHANGED(unit)
	local afk = UnitIsAFK("player")
	if not Readable(unit, afk) or unit ~= "player" then
		return
	end
	afk = afk and true or false
	if wasAFK and not afk and ns.whispersDB.badge and UnreadTotal() > 0 then
		ns.Toast_Clear(OWNER)
		UpdateBadge(true)
	end
	wasAFK = afk
end

local function Preview()
	if not module.active then
		ns.Print("Whispers is off.")
		return
	end
	for i, sample in ipairs(SAMPLES) do
		C_Timer.After((i - 1) * 1.2, function()
			Toast({ key = "preview:" .. sample.sender, name = sample.sender, digestName = sample.sender,
				class = sample.class, text = sample.text, preview = true })
			-- What a real whisper sounds like: Blizzard's own sound (effects channel) plus the extra one.
			PlaySound(SOUNDKIT.TELL_MESSAGE)
			PlayWhisperSound()
		end)
	end
end

local function Activate()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	ns.Toast_SetDigest(OWNER, Digest)
	local afk = UnitIsAFK("player")
	wasAFK = Readable(afk) and afk and true or false
end

local function Deactivate()
	events:UnregisterAllEvents()
	ns.Toast_Clear(OWNER)
	ns.Toast_Unpin(BADGE)
	recapUp = false
	ns.Inbox_Hide()
end

local function ClearHistory()
	wipe(Store().convos)
	wipe(restricted.messages)
	restricted.unread = 0
	Changed()
	ns.Print("whisper history cleared.")
end

-- Keybinds (Bindings.xml, Key Bindings > Tomte), through Core's Tomte_Binding.
ns.bindings.WHISPER_REPLY = function()
	if module and module.active then
		ns.Whispers_ReplyNewest()
	end
end
ns.bindings.WHISPER_INBOX = function()
	if module and module.active then
		ns.Inbox_Toggle()
	end
end
BINDING_NAME_TOMTE_WHISPER_REPLY = "Reply to newest unread whisper"
BINDING_NAME_TOMTE_WHISPER_INBOX = "Open whisper inbox"

local options = {
	{ type = "header", label = "Whispers" },
	{ type = "checkbox", key = "toasts", label = "Toasts",
		tooltip = "A toast for every whisper. Left-click replies, right-click dismisses. More whispers from the same person while the toast is up go into it." },
	{ type = "checkbox", key = "badge", label = "Unread recap after AFK", onChange = function()
		UpdateBadge()
	end,
		tooltip = "Back from AFK with unread whispers: one card with who wrote, in place of their toasts. It stays on top until you answer, open the inbox or right-click it." },
	{ type = "checkbox", key = "holdInCombat", label = "Hold toasts during combat",
		tooltip = "Whispers that arrive in combat show after it, as one card when there are several. Toasts always wait while a cinematic (AFK screen, flight, moment) hides the UI." },
	{ type = "dropdown", key = "sound", label = "Extra sound", onChange = ns.Social_PlaySound, choices = function()
		return ns.SOCIAL_SOUND_CHOICES
	end, tooltip = "Played on the Master channel, so you hear it with sound effects off. Blizzard's own whisper sound plays as well (on the effects channel). In the background only with 'Sound in Background' on." },
	{ type = "header", label = "Inbox" },
	{ type = "button", label = "Whisper inbox", text = "Open", onClick = function()
		ns.Inbox_Toggle()
	end, tooltip = "Your whisper conversations. Also /tomte whispers inbox, a click on the badge, or a keybind (Options > Keybindings > Tomte)." },
	{ type = "checkbox", key = "keepHistory", label = "Keep history between sessions",
		tooltip = "Off: the inbox starts empty at every login. Whispers in instances are never saved (the game hides them from addons)." },
	{ type = "slider", key = "historyDays", label = "Keep conversations for", min = 1, max = 30, step = 1,
		format = function(value)
			return value .. "d"
		end, tooltip = "Read conversations older than this are forgotten at login, unread ones after twice as long." },
	{ type = "button", label = "History", text = "Clear", onClick = ClearHistory,
		confirm = "Forget all whisper conversations?" },
	{ type = "header", label = "Preview" },
	{ type = "button", label = "Sample whispers", text = "Show", onClick = Preview,
		tooltip = "Three sample whisper toasts (two from the same person merge)." },
}
ns.Toast_Options(options)

module = ns.RegisterModule({
	key = "whispers",
	home = {
		{ kind = "quick", key = "inbox", order = 1, name = "Whisper inbox", open = function()
			ns.Inbox_Toggle()
		end, count = UnreadTotal },
	},
	name = "Whispers",
	category = "Social",
	description = "Whispers you can't miss: a toast for each one (click to reply), an unread recap when you're back from AFK, an inbox with your conversations, and one summary card for whispers that came in combat or during a cinematic.",
	enabledByDefault = true,
	defaults = {
		toasts = true,
		badge = true,
		holdInCombat = true,
		sound = "off",
		keepHistory = true,
		historyDays = 14,
		store = { convos = {} },
	},
	init = function(db)
		ns.whispersDB = db
		if db.keepHistory then
			ns.Social_PruneConvos(db.store, time(), db.historyDays * DAY)
		else
			wipe(db.store.convos)
		end
	end,
	toggle = function(active)
		if active then
			Activate()
		else
			Deactivate()
		end
	end,
	commands = {
		{ "inbox", "open the whisper inbox", function()
			ns.Inbox_Toggle()
		end },
		{ "preview", "show sample whisper toasts", Preview },
	},
	options = options,
})
