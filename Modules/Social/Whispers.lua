local addonName, ns = ...

-- Whispers module: every whisper (character or Battle.net) gets a toast (left-click replies, right-click
-- dismisses), back from AFK an unread recap stays on top of the toasts until you've answered or looked, and
-- an inbox window keeps the conversations. Toasts wait while a cinematic hides the UI (and, by default, during
-- combat) and come back as one "while you were busy" card. Optional extra sound on the Master channel.
-- Conversations with characters are per character of yours; the unread counts and the recap only count the one you're
-- on.
-- Blizzard already flashes the taskbar icon for whispers.
-- In chat lockdown (instances, encounters, M+, PvP) the text and sender are secret: such whispers are shown
-- as they are (SetText takes secrets) but can't be compared or saved, so they live in a session-only
-- "In instance" conversation and reply goes to Blizzard's last tell target.

local OWNER = "whispers"
local RECAP = "whispers" -- Toast_Pin key of the unread recap card
local RESTRICTED = "restricted" -- key of the session-only conversation with secret whispers
local DAY = 86400
-- Cards in the player's chat colors (ns.Toast_ChatColor): whisper pink, Battle.net whisper blue.
local WHISPER, BN_WHISPER = "WHISPER", "BN_WHISPER"
local GM_ACCENT = { 0.25, 0.75, 1 } -- theme: game meaning (GM); Blizzard has no GM chat color to read
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
local sample -- the preview's made-up conversations (ns.Social_SampleConvos) while its inbox is open, else nil
local bnTokens = {} -- [conversation key] = this session's |K account name, for replies
local recapUp = false -- the unread card is showing
local wasAFK = false
local awaySince -- time() when you went AFK, nil while you're not
local recapSince -- the recap counts only whispers from this time() on (when you went AFK)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

local Readable = ns.Readable

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

-- Who you are now: character conversations are tagged with it.
local function Me()
	return UnitGUID("player"), UnitName("player")
end

-- Whether convo can be answered from this character (its own, untagged, Battle.net or the instance one).
function ns.Whispers_IsMine(convo)
	return convo ~= nil and ns.Social_IsMine(convo, (Me()))
end

local function SampleConvo(key)
	for _, convo in ipairs(sample) do
		if convo.key == key then
			return convo
		end
	end
	return nil
end

-- Conversations for the inbox: the saved ones plus this session's secret ones. During the preview only the
-- made-up ones, so a screenshot of it shows nobody's real whispers.
function ns.Whispers_Convos()
	if sample then
		return { unpack(sample) }
	end
	local list = ns.Social_SortedConvos(Store())
	if #restricted.messages > 0 then
		table.insert(list, 1, restricted)
	end
	return list
end

function ns.Whispers_Get(key)
	if sample then
		return SampleConvo(key)
	elseif key == RESTRICTED then
		return #restricted.messages > 0 and restricted or nil
	end
	return Store().convos[key]
end

-- since (optional): only whispers that came in at or after this time().
local function UnreadTotal(since)
	local total, convos = ns.Social_Unread(Store(), (Me()), since)
	local restrictedCount = ns.Social_UnreadSince(restricted, since)
	return total + restrictedCount, convos, restrictedCount
end

-- The unread recap card: total whispers from names (colored, as shown).
local function RecapSpec(total, names)
	return {
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
	}
end

-- The unread card only comes up when you're back from AFK, for whispers that came in while you were away; after
-- that it follows their unread count until they're read (answered, opened in the inbox, or right-clicked).
local function UpdateRecap(show)
	local total, convos, restrictedCount = UnreadTotal(recapSince)
	if total == 0 or not ns.whispersDB.badge or not module.active then
		recapUp = false
		ns.Toast_Unpin(RECAP)
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
	if restrictedCount > 0 then
		names[#names + 1] = "in instance"
	end
	ns.Toast_Pin(RECAP, RecapSpec(total, names))
end

local function Changed()
	UpdateRecap()
	ns.Inbox_Refresh()
end

function ns.Whispers_MarkRead(key)
	local convo = sample and SampleConvo(key)
	if convo then
		convo.unread = 0
	elseif key == RESTRICTED then
		restricted.unread = 0
	else
		ns.Social_MarkRead(Store(), key)
	end
	Changed()
end

function ns.Whispers_MarkAllRead()
	if sample then
		for _, convo in ipairs(sample) do
			convo.unread = 0
		end
		ns.Inbox_Refresh()
		return
	end
	ns.Social_MarkAllRead(Store(), (Me()))
	restricted.unread = 0
	Changed()
end

-- The inbox closed: the preview's conversations go, the real ones come back.
function ns.Whispers_EndSample()
	sample = nil
end

-- Pinned conversations sit at the top of the inbox and are never trimmed or pruned.
function ns.Whispers_SetPinned(key, on)
	local convo = Store().convos[key]
	if convo then
		convo.pinned = on or nil
		Changed()
	end
end

function ns.Whispers_Delete(key)
	if key == RESTRICTED then
		return
	end
	Store().convos[key] = nil
	bnTokens[key] = nil
	Changed()
end

-- This session's account info for a Battle.net friend by BattleTag, nil when not on the friend list. Its accountName
-- is the |K name replies need (saved conversations from earlier sessions), its bnetAccountID what
-- C_BattleNet.SendWhisper takes.
local function FindBNetFriend(battleTag)
	for i = 1, BNGetNumFriends() do
		local info = C_BattleNet.GetFriendAccountInfo(i)
		if info and info.battleTag == battleTag then
			return info
		end
	end
	return nil
end
ns.Whispers_BNetFriend = FindBNetFriend -- the inbox header reads who they are from it (InboxWho.lua)

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
	if not ns.Whispers_IsMine(convo) then
		ns.Print(("that conversation is on %s: log in there to answer."):format(convo.charName or "another character"))
		return
	end
	local target = ns.Social_With(convo)
	if convo.bn then
		local token = bnTokens[key]
		if not token then
			local friend = FindBNetFriend(target:sub(4))
			token = friend and friend.accountName
		end
		if token then
			ChatFrameUtil.SendBNetTell(token)
		else
			ns.Print(convo.name .. " isn't online on Battle.net.")
		end
		return
	end
	ChatFrameUtil.SendTell(target)
end

local function CanSend(key)
	return key ~= nil and key ~= RESTRICTED and not (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
end

-- Sends from the inbox. Your whisper shows up in the conversation through the INFORM event.
-- Returns false when it couldn't go out here (the normal chat box is opened instead).
function ns.Whispers_Send(key, text)
	text = strtrim(text or "")
	if text == "" then
		return true
	end
	if sample then
		ns.Print("that's a sample conversation: nothing was sent.")
		return true
	end
	if not CanSend(key) then
		ns.Print("can't send from the inbox during instance chat restrictions; use the chat box.")
		ns.Whispers_Reply(key)
		return false
	end
	local convo = Store().convos[key]
	if convo and not ns.Whispers_IsMine(convo) then
		ns.Print(("that conversation is on %s: log in there to answer."):format(convo.charName or "another character"))
		return false
	end
	local target = convo and ns.Social_With(convo) or key
	local ok, err
	if convo and convo.bn then
		local friend = FindBNetFriend(target:sub(4))
		local id = friend and friend.bnetAccountID
		if not id then
			ns.Print(convo.name .. " isn't online on Battle.net.")
			return false
		end
		local sent
		ok, sent = pcall(C_BattleNet.SendWhisper, id, text)
		if not ok then
			err = sent
		elseif sent == false then
			ok, err = false, "Battle.net refused the whisper"
		end
	else
		ok, err = pcall(C_ChatInfo.SendChatMessage, text, "WHISPER", nil, target)
	end
	if not ok then
		ns.Print("couldn't send: " .. tostring(err))
	end
	ns.Whispers_MarkRead(key)
	return ok
end

-- The reply keybind: the newest unread conversation, else whoever whispered last.
local function ReplyNewest()
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

-- info = { key, name (display, may be secret), digestName, class, bn, gm, text (may be secret), secret, entry (the
-- saved message; none for a preview), preview, count (for a still sample: how many it stands for) }
local function ToastSpec(info)
	local accent = info.gm and GM_ACCENT or ns.Toast_ChatColor(info.bn and BN_WHISPER or WHISPER)
	local title = info.name
	local icon
	if not info.secret and info.class then
		title = ns.UI.ClassColored(info.name, info.class)
		icon = GetClassAtlas(info.class:lower())
	end
	return {
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
		count = info.count,
		digestName = info.digestName,
		holdInCombat = ns.whispersDB.holdInCombat,
		-- Answered (from anywhere) or read in the inbox while the toast was held back: not news anymore.
		stale = info.entry and function()
			return not ns.Social_IsUnread(ns.Whispers_Get(info.key), info.entry)
		end,
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
	}
end

local function Toast(info)
	if ns.whispersDB.toasts then
		ns.Toast_Show(ToastSpec(info))
	end
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
	local viewing
	if info.secret then
		viewing = ns.Inbox_IsShowing(info.key)
		local messages = restricted.messages
		info.entry = { at = time(), text = info.text, sender = info.name }
		messages[#messages + 1] = info.entry
		if #messages > MAX_RESTRICTED then
			table.remove(messages, 1)
		end
		restricted.last = time()
		if not viewing then
			restricted.unread = restricted.unread + 1
		end
	else
		info.entry = { at = time(), text = info.text }
		local convo, claimed = ns.Social_AddMessage(Store(), info.key, { name = info.digestName, class = info.class,
			bn = info.bn, with = info.with, char = info.char, charName = info.charName }, info.entry)
		if claimed then
			ns.Inbox_Rekey(claimed, convo.key)
		end
		viewing = ns.Inbox_IsShowing(info.key)
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
	local with = FullName(sender)
	local me, myName = Me()
	Incoming({ key = ns.Social_ConvoKey(with, me), with = with, char = me, charName = myName, name = short,
		digestName = short, class = class, text = text, gm = Readable(flags) and (flags == "GM" or flags == "DEV") })
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
	Incoming({ key = key, with = key, name = sender, digestName = ns.Social_ShortTag(info.battleTag), bn = true, text = text,
		class = game and game.isOnline and game.classFilename or nil })
end

-- Your own whispers: kept in the conversation, which counts as answered.
local function Outgoing(key, text, info)
	local convo, claimed = ns.Social_AddMessage(Store(), key, info, { at = time(), text = text, out = true })
	if claimed then
		ns.Inbox_Rekey(claimed, convo.key)
	end
	Changed()
end

function events:CHAT_MSG_WHISPER_INFORM(text, target)
	if not Readable(text, target) then
		restricted.unread = 0 -- answered someone in the instance; we can't tell whom
		Changed()
		return
	end
	local with = FullName(target)
	local me, myName = Me()
	Outgoing(ns.Social_ConvoKey(with, me), text, { name = Ambiguate(target, "short"), with = with, char = me,
		charName = myName })
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
		Outgoing(key, text, { name = ns.Social_ShortTag(info.battleTag), bn = true, with = key })
	end
end

-- Back from AFK with unread whispers from while you were away: one recap card instead of the toasts still up or
-- held back. Whispers left unread from before (or from an earlier session) don't count.
function events:PLAYER_FLAGS_CHANGED(unit)
	local afk = UnitIsAFK("player")
	-- The unit token and the AFK flag can come in as secret values under addon restrictions: compare them only
	-- when readable.
	if not Readable(unit, afk) or unit ~= "player" then
		return
	end
	afk = afk and true or false
	if afk and not wasAFK then
		awaySince = time()
	elseif wasAFK and not afk then
		if ns.whispersDB.badge and awaySince and UnreadTotal(awaySince) > 0 then
			ns.Toast_Clear(OWNER)
			recapSince = awaySince
			UpdateRecap(true)
		end
		awaySince = nil
	end
	wasAFK = afk
end

local function Preview()
	if not ns.Module_RequireOn(module) then
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
	-- And the inbox with made-up conversations, until it's closed.
	local classNames = {}
	for id = 1, GetNumClasses() do
		local info = C_CreatureInfo.GetClassInfo(id)
		if info then
			classNames[info.classFile] = info.className
		end
	end
	sample = ns.Social_SampleConvos(time())
	for _, convo in ipairs(sample) do
		convo.who.className = classNames[convo.class]
	end
	ns.Inbox_Toggle(sample[1].key)
end

local function Activate()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	ns.Toast_SetDigest(OWNER, Digest)
	local afk = UnitIsAFK("player")
	wasAFK = Readable(afk) and afk and true or false
	-- Already AFK (a /reload while away): the best guess for when is now.
	awaySince = wasAFK and time() or nil
end

local function Deactivate()
	events:UnregisterAllEvents()
	ns.Toast_Clear(OWNER)
	ns.Toast_Unpin(RECAP)
	recapUp = false
	ns.Inbox_Hide()
	sample = nil
end

local function ClearHistory()
	wipe(Store().convos)
	wipe(restricted.messages)
	restricted.unread = 0
	Changed()
	ns.Print("whisper history cleared.")
end

-- Key bindings (Bindings.xml, Key Bindings > Tomte), through ns.Binding_Add.
ns.Binding_Add("WHISPER_REPLY", "whispers", function()
	ReplyNewest()
end)
ns.Binding_Add("WHISPER_INBOX", "whispers", function()
	ns.Inbox_Toggle()
end)
BINDING_NAME_TOMTE_WHISPER_REPLY = "Reply to newest unread whisper"
BINDING_NAME_TOMTE_WHISPER_INBOX = "Open whisper inbox"

-- Settings previews (Panel/Preview.lua): still cards from the made-up conversations (ns.Social_SampleConvos), built by
-- the same spec code as the real ones. The preview's own copy: the inbox's sample and the saved store aren't touched.
local function UnreadSamples()
	local list = {}
	for _, convo in ipairs(ns.Social_SampleConvos(time())) do
		if convo.unread > 0 then
			list[#list + 1] = convo
		end
	end
	return list
end

local function ToastPreview(host)
	local w, h
	for i, convo in ipairs(UnreadSamples()) do
		local last = convo.messages[#convo.messages]
		w, h = ns.Toast_DrawSample(host, ToastSpec({ key = "preview:" .. convo.name, name = convo.name,
			digestName = convo.name, class = convo.class, text = last.text, preview = true, count = convo.unread }), i)
	end
	return w, h
end

local function RecapPreview(host)
	local total, names = 0, {}
	for _, convo in ipairs(UnreadSamples()) do
		total = total + convo.unread
		names[#names + 1] = ns.Inbox_ColoredName(convo)
	end
	local spec = RecapSpec(total, names)
	spec.test = true
	return ns.Toast_DrawSample(host, spec, 1)
end

local options = {
	{ type = "header", label = "Whispers" },
	{ type = "checkbox", key = "toasts", label = "Toasts", preview = ns.Preview_When("toasts", ToastPreview),
		tooltip = "A toast for every whisper. Left-click replies, right-click dismisses. More whispers from the same person while the toast is up go into it." },
	{ type = "checkbox", key = "holdInCombat", label = "Hold toasts during combat", parent = "toasts",
		tooltip = "Whispers that arrive in combat show after it, as one card when there are several. Toasts always wait while a cinematic (AFK screen, flight, moment) hides the UI." },
	{ type = "checkbox", key = "badge", label = "Unread recap after AFK",
		preview = ns.Preview_When("badge", RecapPreview), onChange = function()
		UpdateRecap()
	end,
		tooltip = "Back from AFK with unread whispers: one card with who wrote, in place of their toasts. It stays on top until you answer, open the inbox or right-click it." },
	{ type = "dropdown", key = "sound", label = "Extra sound", onChange = ns.Social_PlaySound, choices = function()
		return ns.SOCIAL_SOUND_CHOICES
	end, tooltip = "Played on the Master channel, so you hear it with sound effects off. Blizzard's own whisper sound plays as well (on the effects channel). In the background only with 'Sound in Background' on." },
	{ type = "header", label = "Inbox" },
	{ type = "button", label = "Whisper inbox", text = "Open", onClick = function()
		ns.Inbox_Toggle()
	end, tooltip = "Your whisper conversations. Also /tomte whispers inbox, a click on the unread recap, or a keybind (Options > Keybindings > Tomte)." },
	{ type = "checkbox", key = "keepHistory", label = "Keep history between sessions",
		tooltip = "Off: the inbox starts empty at every login. Whispers in instances are never saved (the game hides them from addons)." },
	{ type = "slider", key = "historyDays", label = "Keep conversations for", min = 1, max = 30, step = 1,
		parent = "keepHistory", format = function(value)
			return value .. "d"
		end, tooltip = "Read conversations older than this are forgotten at login, unread ones after twice as long." },
	{ type = "button", label = "History", text = "Clear", onClick = ClearHistory,
		confirm = "Forget all whisper conversations, on every character?" },
	{ type = "header", label = "Preview" },
	{ type = "button", label = "Sample whispers", text = "Show", onClick = Preview,
		tooltip = "Three sample whisper toasts (two from the same person merge) and the inbox with made-up "
			.. "conversations. Your real whispers come back when you close it." },
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
	category = "social",
	icon = 136209, -- spell_shadow_soothingkiss
	summary = "A toast for every whisper, an AFK recap and an inbox of your chats.",
	description = "Whispers you can't miss: a toast for each one (click to reply), an unread recap when you're back from AFK, an inbox with your conversations, and one summary card for whispers that came in combat or during a cinematic.",
	enabledByDefault = true,
	toasts = true,
	defaults = {
		toasts = true,
		badge = true,
		holdInCombat = true,
		sound = "off",
		keepHistory = true,
		historyDays = 14,
		-- convos[key] = { key, with, char, charName, name, class, bn, last, unread, pinned, messages } (Data.lua);
		-- char = which of your characters (GUID), none for Battle.net and conversations from before 1.16
		store = { convos = {} },
		inbox = {}, -- the inbox window: point = { point, relPoint, x, y }, w, h
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
		{ "preview", "show sample whisper toasts and an inbox with made-up conversations", Preview },
	},
	options = options,
})
