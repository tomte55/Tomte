local addonName, ns = ...

-- Sending settings to a player: both ends of one transfer. The sender offers, the receiver is asked, and only on Yes
-- does the settings string come over; the receiver then sees the import preview (Panel/Share.lua) before anything
-- changes. Two routes: an addon whisper to a character (same or connected realms, works in every Tomte) and Friend
-- sharing to a Battle.net friend (a message-only set, Modules/Share/Share.lua). Messages and reassembly in
-- Core/ProfileWire.lua. Always on, not a module: the new player who'd receive settings hasn't turned anything on yet.
-- See docs/superpowers/specs/2026-11-14-tomte-send-settings-design.md.

local PREFIX = ns.PROFILEWIRE_PREFIX
local SET = "profile" -- Friend sharing set key (lower-case letters only: Share's message format)
local SEND_GAP = 0.1 -- seconds between addon whispers (not throttled outside instances, still paced)
local THROTTLED = 2 -- seconds to wait after the game throttled a message
local LOCKDOWN = 10 -- seconds to wait while addon messages are locked down
local ANSWER_WAIT = 120 -- seconds the sender waits for Yes or No (the receiver may be busy for a moment)
local RESULT_WAIT = 60 -- seconds the sender waits, after Yes, to hear the settings arrived
local TID_LENGTH = 6
local TID_CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"
local MENUS = { "PLAYER", "PARTY", "RAID_PLAYER", "FRIEND", "GUILD", "CHAT_ROSTER", "COMMUNITIES_WOW_MEMBER",
	"COMMUNITIES_GUILD_MEMBER", "BN_FRIEND" } -- right-click menus that get the entry (wow-ui-source UnitPopupShared)

local NO_ANSWER = "no answer from %s: they may be offline, not run Tomte, or run an older Tomte."
local NO_LINES = {
	declined = "%s said no thanks.",
	busy = "%s is looking at another offer. Try again in a moment.",
	off = "%s doesn't take settings from players.",
}
local RESULT_LINES = {
	shown = "%s got your settings and is looking at what changes.",
	same = "%s already has these settings.",
	bad = "%s's Tomte couldn't read your settings. One of you may need to update Tomte.",
	cancelled = "%s closed your settings without importing them.",
}

local outgoing -- { route = "whisper" | "bnet", to, name, tid, text, timer }
local incoming -- { route, from, name, tid, state = "held" | "asking" | "receiving", timer }
local shownTo = {} -- [tid] = name: a send whose preview is open on their side (they may still cancel)
local asked = {} -- [route .. from] = GetTime() of the last question we put to the player for that sender
local inbox = ns.ProfileWire_NewInbox()
local queue, pumping = {}, false -- addon whispers waiting to go: { to, text }
local events = CreateFrame("Frame")

local function NewTid()
	local parts = {}
	for i = 1, TID_LENGTH do
		local n = math.random(#TID_CHARS)
		parts[i] = TID_CHARS:sub(n, n)
	end
	return table.concat(parts)
end

-- "Name-Realm" for a typed or given name; the realm is ours when none is given. Forever keeps the name as it is:
-- "Name Surname" is unique in the region and a realm only stops the whisper from arriving.
local function FullName(name)
	if ns.FOREVER or name:find("-", 1, true) then
		return name
	end
	local realm = ns.RealmName()
	return realm and (name .. "-" .. realm) or name
end

-- A unit's name as whispers address it: on Forever the first name and surname ("Aldric Stonebrook"; names are
-- unique in the region, the first name alone reaches no one), on retail the plain name. nil when unreadable.
local function UnitAddress(unit)
	local name, surname = UnitNameUnmodified(unit)
	if not name or ns.IsSecret(name, surname) then
		return nil
	end
	if ns.FOREVER and NameUtil and NameUtil.GetUnmodifiedUnitFullName then
		return NameUtil.GetUnmodifiedUnitFullName(unit)
	end
	return name
end

local function IsSelf(full)
	local me = UnitAddress("player")
	return me ~= nil and FullName(me):lower() == full:lower()
end

-- Forever: a first name alone finds the full name of your target or a group member who has it, else nil.
local function ForeverFullName(first)
	local units = { "target" }
	for i = 1, GetNumGroupMembers() do
		units[#units + 1] = IsInRaid() and ("raid" .. i) or ("party" .. i)
	end
	first = first:lower()
	for _, unit in ipairs(units) do
		if UnitIsPlayer(unit) then
			local name = UnitNameUnmodified(unit)
			if name and not ns.IsSecret(name) and name:lower() == first then
				return UnitAddress(unit)
			end
		end
	end
	return nil
end

-- Sending ----------------------------------------------------------------------------------------------------------

local function DropQueued(to)
	for i = #queue, 1, -1 do
		if queue[i].to == to then
			table.remove(queue, i)
		end
	end
end

local Finish

local function Pump()
	local item = table.remove(queue, 1)
	if not item then
		pumping = false
		return
	end
	-- Without our own realm: Forever answers a whisper to "Name-OurRealm" with "No player named ...", while the
	-- plain name reaches them (retail takes either).
	local result = C_ChatInfo.SendAddonMessage(PREFIX, item.text, "WHISPER", Ambiguate(item.to, "none"))
	local wait = SEND_GAP
	local R = Enum.SendAddonMessageResult
	if R and (result == R.AddonMessageThrottle or result == R.ChannelThrottle) then
		table.insert(queue, 1, item)
		wait = THROTTLED
	elseif R and result == R.AddOnMessageLockdown then
		table.insert(queue, 1, item)
		wait = LOCKDOWN
	elseif R and result == R.TargetOffline then
		DropQueued(item.to)
		if outgoing and outgoing.route == "whisper" and outgoing.to == item.to then
			Finish("%s is offline.")
		end
	end
	C_Timer.After(wait, Pump)
end

-- One message to a player over a route. False when Friend sharing can't reach them right now.
local function Send(route, to, tid, wire)
	if route == "bnet" then
		return ns.Share_Send ~= nil and ns.Share_Send(to, SET, tid .. ";" .. wire)
	end
	queue[#queue + 1] = { to = to, text = wire }
	if not pumping then
		pumping = true
		Pump()
	end
	return true
end

-- Ends our send, with a chat line about how it went (%s: their name).
function Finish(line)
	if not outgoing then
		return
	end
	if outgoing.timer then
		outgoing.timer:Cancel()
	end
	local name = outgoing.name
	if outgoing.route == "whisper" then
		DropQueued(outgoing.to)
	end
	outgoing = nil
	if line then
		ns.Print(line:format(name))
	end
end

local function WaitFor(seconds)
	local sending = outgoing
	if sending.timer then
		sending.timer:Cancel()
	end
	sending.timer = C_Timer.NewTimer(seconds, function()
		if outgoing == sending then
			sending.timer = nil
			Finish(NO_ANSWER)
		end
	end)
end

local function Start(route, to, name)
	if not ns.ShareUI_Available() then
		ns.Print("sharing settings isn't available in this game.")
		return
	end
	if outgoing then
		ns.Print(("already sending your settings to %s."):format(outgoing.name))
		return
	end
	local text, err = ns.ShareUI_ExportText()
	if not text then
		ns.Print("couldn't build the string: " .. tostring(err))
		return
	end
	outgoing = { route = route, to = to, name = name, tid = NewTid(), text = text }
	if not Send(route, to, outgoing.tid, ns.ProfileWire_Offer(outgoing.tid, #text)) then
		Finish("%s can't be reached through Friend sharing right now.")
		return
	end
	ns.Print(("asking %s if they'd like your settings..."):format(name))
	WaitFor(ANSWER_WAIT)
end

-- An answer to our send: Yes sends the settings, No and results end it.
local function OnAnswer(route, msg)
	if msg.kind == "R" and msg.outcome == "cancelled" then
		local name = shownTo[msg.tid]
		shownTo[msg.tid] = nil
		if name then
			ns.Print(RESULT_LINES.cancelled:format(name))
		end
		return
	end
	if not (outgoing and outgoing.tid == msg.tid and outgoing.route == route) then
		return
	end
	if msg.kind == "A" then
		local size = route == "bnet" and ns.PROFILEWIRE_BNET or ns.PROFILEWIRE_WHISPER
		for _, wire in ipairs(ns.ProfileWire_Data(msg.tid, outgoing.text, size)) do
			if not Send(route, outgoing.to, msg.tid, wire) then
				Finish("%s can't be reached through Friend sharing right now.")
				return
			end
		end
		ns.Print(("sending your settings to %s..."):format(outgoing.name))
		WaitFor(RESULT_WAIT)
	elseif msg.kind == "N" then
		Finish(NO_LINES[msg.reason] or NO_LINES.declined)
	elseif msg.kind == "R" then
		if msg.outcome == "shown" then
			shownTo[msg.tid] = outgoing.name
		end
		Finish(RESULT_LINES[msg.outcome] or RESULT_LINES.bad)
	end
end

-- Receiving --------------------------------------------------------------------------------------------------------

local function Reply(receiving, wire)
	Send(receiving.route, receiving.from, receiving.tid, wire)
end

local function Drop(receiving)
	if incoming == receiving then
		if receiving.timer then
			receiving.timer:Cancel()
		end
		incoming = nil
	end
end

-- Forgets the offer if nothing more happens in time (Esc on the question answers nothing).
local function Expire(receiving, seconds)
	if receiving.timer then
		receiving.timer:Cancel()
	end
	receiving.timer = C_Timer.NewTimer(seconds, function()
		receiving.timer = nil
		Drop(receiving)
	end)
end

local function Ask(receiving)
	receiving.state = "asking"
	asked[receiving.route .. receiving.from] = GetTime()
	Expire(receiving, ANSWER_WAIT)
	ns.Confirm_Show(("%s wants to send you their Tomte settings.\n\nYou'll see what changes before anything is "
		.. "imported."):format(receiving.name), function()
		if incoming ~= receiving then
			return
		end
		receiving.state = "receiving"
		Expire(receiving, ns.PROFILEWIRE_STALE)
		Reply(receiving, ns.ProfileWire_Accept(receiving.tid))
	end, { yes = "See changes", no = "No thanks", noEnter = true, onNo = function()
		if incoming == receiving then
			Reply(receiving, ns.ProfileWire_No(receiving.tid, "declined"))
			Drop(receiving)
		end
	end })
end

local function OnOffer(route, from, name, msg)
	local receiving = { route = route, from = from, name = name, tid = msg.tid }
	local window = ns.db and ns.db.window
	if not (ns.ShareUI_Available() and window and window.receiveSettings) then
		Reply(receiving, ns.ProfileWire_No(msg.tid, "off"))
	elseif incoming or ns.ShareUI_PreviewShown() then
		Reply(receiving, ns.ProfileWire_No(msg.tid, "busy"))
	elseif not ns.ProfileWire_MayAsk(asked[route .. from], GetTime()) or msg.size > ns.PROFILE_MAX_TEXT then
		Reply(receiving, ns.ProfileWire_No(msg.tid, "declined"))
	else
		incoming = receiving
		if InCombatLockdown() then
			receiving.state = "held" -- asked on PLAYER_REGEN_ENABLED
		else
			Ask(receiving)
		end
	end
end

local function OnData(route, from, msg)
	local receiving = incoming
	if not (receiving and receiving.state == "receiving" and receiving.route == route and receiving.from == from
		and receiving.tid == msg.tid) then
		return
	end
	local text, err = ns.ProfileWire_Add(inbox, from .. ":" .. msg.tid, msg, GetTime())
	if err then
		Reply(receiving, ns.ProfileWire_Result(msg.tid, "bad"))
		Drop(receiving)
		return
	end
	if not text then
		Expire(receiving, ns.PROFILEWIRE_STALE)
		return
	end
	Drop(receiving)
	local ok, why, same = ns.ShareUI_PreviewText(text, ("%s's settings"):format(receiving.name), function(imported)
		if not imported then
			Reply(receiving, ns.ProfileWire_Result(receiving.tid, "cancelled"))
		end
	end)
	if ok then
		Reply(receiving, ns.ProfileWire_Result(msg.tid, "shown"))
	else
		Reply(receiving, ns.ProfileWire_Result(msg.tid, same and "same" or "bad"))
		ns.Print(("%s sent you their settings. %s"):format(receiving.name, why))
	end
end

-- Any message of ours from a player, over either route. from: their Name-Realm or BattleTag; name: shown to you.
local function OnMessage(route, from, name, text)
	local msg = ns.ProfileWire_Parse(text)
	if not msg then
		return
	end
	if msg.kind == "O" then
		OnOffer(route, from, name, msg)
	elseif msg.kind == "D" then
		OnData(route, from, msg)
	else
		OnAnswer(route, msg)
	end
end

-- Friend sharing route: the set's message and refusal (an older Tomte, or one that doesn't take settings).
local function OnFriendMessage(tag, text)
	local body = text:match("^[^;]+;(.*)$")
	if body then
		OnMessage("bnet", tag, tag:match("^[^#]+") or tag, body)
	end
end

local function OnFriendRefused(tag)
	if outgoing and outgoing.route == "bnet" and outgoing.to == tag then
		Finish("%s's Tomte doesn't take settings yet: they need to update Tomte.")
	end
end

-- Who to send to ---------------------------------------------------------------------------------------------------

function ns.ShareSend_ToPlayer(name)
	name = strtrim(name or "")
	if name == "" then
		ns.Print("whose settings? /tomte profile send <name>")
		return
	end
	if ns.FOREVER and not name:find("[%s%-]") then
		local found = ForeverFullName(name)
		if not found then
			ns.Print(("type %s's full name, first name and surname (or target them first)."):format(name))
			return
		end
		name = found
	end
	local full = FullName(name)
	if IsSelf(full) then
		ns.Print("those are already your settings.")
		return
	end
	Start("whisper", full, Ambiguate(full, "none"))
end

function ns.ShareSend_ToFriend(tag)
	Start("bnet", tag, tag:match("^[^#]+") or tag)
end

-- Your target's Name-Realm when it's another player, for the name box.
local function TargetName()
	if not UnitIsPlayer("target") or UnitIsUnit("target", "player") then
		return ""
	end
	if ns.FOREVER then
		return UnitAddress("target") or "" -- the second return is the surname there, not a realm
	end
	local name, realm = UnitNameUnmodified("target")
	if not name or ns.IsSecret(name) or ns.IsSecret(realm) then
		return ""
	end
	return (realm and realm ~= "") and (name .. "-" .. realm) or name
end

function ns.ShareSend_Ask()
	if not ns.ShareUI_Available() then
		ns.Print("sharing settings isn't available in this game.")
		return
	end
	ns.Dialog_Show({
		title = "Send your settings to a player",
		hint = (ns.FOREVER and "Their character's full name, first name and surname." or "Their character's name "
			.. "(Name, or Name-Realm from another realm).") .. " They're asked first, and see what changes before "
			.. "anything is imported.",
		text = TargetName(),
		saveText = "Send",
		height = 150,
		onSave = function(text)
			local name = strtrim(text or "")
			if name == "" then
				return "Type a player's name."
			end
			ns.ShareSend_ToPlayer(name)
			return nil
		end,
	})
end

-- Right-click menus: route and who for the clicked player, or nil when there's no one to send to.
local function MenuTarget(context)
	local account = context.accountInfo
	if context.which == "BN_FRIEND" then
		local tag = account and account.battleTag
		if tag and ns.Share_Online and ns.Share_Online(tag) then
			return "bnet", tag
		end
		local game = account and account.gameAccountInfo
		if not (game and game.clientProgram == BNET_CLIENT_WOW and game.wowProjectID == WOW_PROJECT_ID
			and game.characterName) then
			return nil
		end
		-- Forever leaves realmName empty (1.60.1 hotfix); a name there is unique in the region and whispers by itself.
		local realm = (game.realmName or ""):gsub("[%s%-]", "")
		return "whisper", realm ~= "" and (game.characterName .. "-" .. realm) or game.characterName
	end
	local name = context.name
	if type(name) ~= "string" or name == "" or ns.IsSecret(name) then
		return nil
	end
	if ns.FOREVER then
		-- The name Blizzard's own Whisper entry uses: "Name Surname" there (context.surname is no realm).
		local ok, full = pcall(UnitPopupSharedUtil.GetFullPlayerName, context)
		if ok and type(full) == "string" and full ~= "" and not ns.IsSecret(full) then
			return "whisper", full
		end
		return nil
	end
	local server = context.server
	if type(server) == "string" and server ~= "" and not ns.IsSecret(server) then
		name = name .. "-" .. server
	end
	return "whisper", name
end

local function AddMenuEntry(_, root, context)
	if not (context and ns.ShareUI_Available()) then
		return
	end
	local route, to = MenuTarget(context)
	if route == "whisper" and IsSelf(FullName(to)) then
		return
	end
	if not route then
		return
	end
	root:CreateDivider()
	root:CreateButton("Send my Tomte settings", function()
		if route == "bnet" then
			ns.ShareSend_ToFriend(to)
		else
			ns.ShareSend_ToPlayer(to)
		end
	end)
end

-- Events -----------------------------------------------------------------------------------------------------------

function events:CHAT_MSG_ADDON(prefix, text, channel, sender)
	if ns.IsSecret(prefix, text, channel, sender) or prefix ~= PREFIX or channel ~= "WHISPER"
		or type(sender) ~= "string" then
		return
	end
	local from = FullName(sender)
	OnMessage("whisper", from, Ambiguate(from, "none"), text)
end

function events:PLAYER_REGEN_ENABLED()
	if incoming and incoming.state == "held" then
		Ask(incoming)
	end
end

-- Every file is loaded by now: Friend sharing (a module, after Panel/) takes the set, and the menus can be extended.
function events:PLAYER_LOGIN()
	if ns.Share_Register then
		ns.Share_Register({ key = SET, messageOnly = true, message = OnFriendMessage, refused = OnFriendRefused,
			active = ns.ShareUI_Available })
	end
	if Menu and Menu.ModifyMenu then -- Forever may have the older dropdown menus
		for _, which in ipairs(MENUS) do
			Menu.ModifyMenu("MENU_UNIT_" .. which, AddMenuEntry)
		end
	end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	events:RegisterEvent("CHAT_MSG_ADDON")
end
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))
