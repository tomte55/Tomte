local addonName, ns = ...

-- Whisper inbox: who a conversation is with, read from the friend list, Battle.net friends and the guild roster,
-- for the header's status line (ns.Inbox_StatusText in Data.lua), the online dots and the Invite / Add friend
-- actions. Called by Inbox.lua; reads only, no events of its own (the inbox re-reads on a ticker while it's open).

local ROSTER_SECONDS = 30 -- the guild roster is asked for again at most this often

local guild = {} -- [Name-Realm] = { online, level, className, classFile, area } (from the last roster read)
local guildAt = 0
local Readable = ns.Readable

-- The guild roster as a map, re-read when older than ROSTER_SECONDS (C_GuildInfo.GuildRoster asks the server for
-- fresh data; GetGuildRosterInfo reads what's here).
local function Guild()
	if not IsInGuild() then
		return guild
	end
	local now = GetTime()
	if now - guildAt < ROSTER_SECONDS then
		return guild
	end
	guildAt = now
	C_GuildInfo.GuildRoster()
	wipe(guild)
	for i = 1, GetNumGuildMembers() do
		local name, _, _, level, className, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
		if name and Readable(name) then
			guild[name] = { online = online and true or false, level = level, className = className,
				classFile = classFile, area = zone }
		end
	end
	return guild
end

local function MyRealm()
	return GetNormalizedRealmName() or GetRealmName()
end

-- The friend list keeps friends from your own realm without the realm. Each entry is matched as ns.Social_IsCharacter
-- does (a whisperer from another realm with the same name isn't your friend; on Forever the server number doesn't
-- count, friends there play from differently numbered servers).
local function CharacterFriend(key)
	local info = C_FriendList.GetFriendInfo(key)
	if not info and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
		local myRealm = MyRealm()
		for i = 1, C_FriendList.GetNumFriends() or 0 do
			local f = C_FriendList.GetFriendInfoByIndex(i)
			local fName = f and f.name
			if fName and Readable(fName) then
				local name, realm = fName:match("^(.-)%-(.+)$")
				if ns.Social_IsCharacter(key, name or fName, realm, myRealm, ns.FOREVER) then
					info = f
					break
				end
			end
		end
	end
	if not info then
		return nil
	end
	local who = { online = info.connected and true or false, friend = true }
	if who.online then
		who.level = info.level ~= 0 and info.level or nil
		who.className = info.className
		who.area = info.area
		who.inviteName = key
	end
	return who
end

local function BNetFriend(key)
	local info = ns.Whispers_BNetFriend and ns.Whispers_BNetFriend(key:sub(4))
	if not info then
		return nil
	end
	local game = info.gameAccountInfo
	local who = { online = game ~= nil and game.isOnline and true or false, friend = true }
	if not who.online then
		return who
	end
	if game.clientProgram == BNET_CLIENT_WOW then
		if game.wowProjectID == WOW_PROJECT_ID and game.isInCurrentRegion then
			who.level = game.characterLevel
			who.className = game.className
			who.classFile = game.classFilename
			who.area = game.areaName
			who.gameAccountID = game.gameAccountID
		else
			who.game = game.richPresence ~= "" and game.richPresence or true -- Classic, another region
		end
	elseif game.clientProgram == BNET_CLIENT_APP or game.clientProgram == "BSAp" then
		who.game = "app"
	else
		who.game = true
	end
	return who
end

-- A character whisper from someone on your Battle.net friend list: the friend whose WoW game account is on that
-- character (online only: Battle.net doesn't say which characters an offline friend has).
local function BNetCharacter(key)
	if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts) then
		return nil
	end
	local myRealm = MyRealm()
	for i = 1, BNGetNumFriends() or 0 do
		for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
			local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
			if game and game.isOnline and game.clientProgram == BNET_CLIENT_WOW
				and (game.wowProjectID == nil or game.wowProjectID == WOW_PROJECT_ID)
				and Readable(game.characterName)
				and ns.Social_IsCharacter(key, game.characterName, game.realmName, myRealm, ns.FOREVER) then
				return { online = true, friend = true, level = game.characterLevel, className = game.className,
					classFile = game.classFilename, area = game.areaName, inviteName = key }
			end
		end
	end
	return nil
end

-- who for a conversation, or nil when they're not a friend, Battle.net friend or guildmate (or it's the session's
-- secret "In instance" conversation). See ns.Inbox_StatusText for the fields.
function ns.InboxWho_Get(convo)
	if convo and convo.sample then
		return convo.who
	elseif not convo or convo.restricted then
		return nil
	end
	local with = ns.Social_With(convo)
	if convo.bn then
		return BNetFriend(with)
	end
	local who = CharacterFriend(with) or BNetCharacter(with)
	local member = Guild()[with]
	-- The friend list is live; the roster can be up to ROSTER_SECONDS old, so it only speaks for guildmates who
	-- aren't friends.
	if member and who then
		who.classFile = member.classFile
		who.guild = true
	elseif member then
		who = { online = member.online, classFile = member.classFile, guild = true }
		if member.online then
			who.level, who.className, who.area = member.level, member.className, member.area
			who.inviteName = with
		end
	end
	return who
end

-- /tomte whispers who: the conversation's name and every friend entry as the game gives them, and the match.
function ns.InboxWho_Why(convo)
	if not convo then
		ns.Print("no conversations.")
		return
	end
	local with = ns.Social_With(convo)
	ns.Print(("conversation: %q (Battle.net: %s), your realm %q"):format(with, convo.bn and "yes" or "no", MyRealm()))
	for i = 1, (C_FriendList.GetNumFriends and C_FriendList.GetNumFriends()) or 0 do
		local f = C_FriendList.GetFriendInfoByIndex(i)
		ns.Print(("  friend %d: %q online %s"):format(i, tostring(f and f.name), tostring(f and f.connected)))
	end
	for i = 1, (BNGetNumFriends and BNGetNumFriends()) or 0 do
		for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
			local g = C_BattleNet.GetFriendGameAccountInfo(i, j)
			if g and g.isOnline then
				ns.Print(("  Battle.net %d.%d: %q realm %q program %s project %s"):format(i, j,
					tostring(g.characterName), tostring(g.realmName), tostring(g.clientProgram),
					tostring(g.wowProjectID)))
			end
		end
	end
	local who = ns.InboxWho_Get(convo)
	ns.Print("match: " .. (who and ns.Inbox_StatusText(who) or "none"))
end

-- Whether adding them as a character friend makes sense: not already one, and the client still has that list.
function ns.InboxWho_CanAddFriend(convo, who)
	if not convo or convo.bn or convo.restricted or (who and who.friend) then
		return false
	end
	return not C_FriendList.IsLegacyFriendSystemEnabled or C_FriendList.IsLegacyFriendSystemEnabled()
end

function ns.InboxWho_CanInvite(who)
	return who ~= nil and who.online and (who.inviteName ~= nil or who.gameAccountID ~= nil)
end

function ns.InboxWho_Invite(who)
	if who.gameAccountID then
		C_BattleNet.InviteFriend(who.gameAccountID)
	elseif who.inviteName then
		C_PartyInfo.InviteUnit(who.inviteName)
	end
end

function ns.InboxWho_AddFriend(convo)
	C_FriendList.AddFriend(ns.Social_With(convo))
end
