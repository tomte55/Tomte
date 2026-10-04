local addonName, ns = ...

-- Friends Online module: one card at login with who's online (friends in WoW, friends in other games,
-- guildmates), and a toast when a friend comes online later: every friend, or only the people on your
-- watch list (which may also hold guildmates). Click a toast to whisper them.
-- Character friends come from FRIENDLIST_UPDATE (the list before vs after), Battle.net friends from
-- BN_FRIEND_ACCOUNT_ONLINE and guildmates from the "has come online" system message (secret in chat
-- lockdown, so watched guildmates are missed inside instances).

local OWNER = "friends"
local ACCENT = { 0, 0.85, 1 } -- Battle.net blue
local GUILD_ACCENT = { 0.25, 1, 0.25 }
local SETTLE = 15 -- seconds after login in which "came online" is the login catch-up, not news
local SUMMARY_DELAY = 8 -- seconds after login: friend and guild lists have arrived
local BN_DELAY = 2 -- seconds: a Battle.net friend's game info fills in just after the online event
local REPEAT = 60 -- seconds: the same person isn't announced twice within this
local EVENTS = { "PLAYER_ENTERING_WORLD", "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE" }

local module
local settleUntil = 0
local friendsOnline -- [lower-case character name] = true, nil until the friend list was first read
local friendNames = {} -- [lower-case name] = true for every character friend
local announced = {} -- [lower-case name] = GetTime() of the last toast
local watch = {}
local onlinePattern

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Readable(...)
	return not canaccessallvalues or canaccessallvalues(...)
end

local function ClassColored(name, class)
	local color = class and C_ClassColor.GetClassColor(class)
	return color and color:WrapTextInColorCode(name) or name
end

local function ClassOf(guid)
	if guid and guid ~= "" then
		local _, englishClass = GetPlayerInfoByGUID(guid)
		return englishClass
	end
	return nil
end

-- Only signed in to the Battle.net launcher or the mobile app ("BSAp"): online, but not playing anything.
local function Idle(game)
	local client = game.clientProgram
	return client == BNET_CLIENT_APP or client == BNET_CLIENT_CLNT or client == "BSAp"
end

-- What a Battle.net friend is doing: "Thrall - Dornogal", "World of Warcraft Classic". nil in the launcher.
local function Activity(game)
	if not (game and game.isOnline) then
		return nil
	end
	if game.clientProgram == BNET_CLIENT_WOW then
		if game.wowProjectID == WOW_PROJECT_MAINLINE and game.characterName and game.characterName ~= "" then
			local area = game.areaName and game.areaName ~= "" and (" - " .. game.areaName) or ""
			return ClassColored(game.characterName, game.classFilename) .. area, true
		end
		return (game.richPresence and game.richPresence ~= "") and game.richPresence or "World of Warcraft"
	end
	if Idle(game) then
		return nil
	end
	return (game.richPresence and game.richPresence ~= "") and game.richPresence or "Another game"
end

-- Online Battle.net friends: { info, activity, inWoW, idle }.
local function OnlineBNet()
	local list = {}
	local total = BNGetNumFriends() or 0
	for i = 1, total do
		local info = C_BattleNet.GetFriendAccountInfo(i)
		local game = info and info.gameAccountInfo
		if game and game.isOnline then
			local activity, inWoW = Activity(game)
			list[#list + 1] = { info = info, activity = activity, inWoW = inWoW, idle = Idle(game) }
		end
	end
	return list
end

-- Online character friends: [lower-case name] = FriendInfo. Also every friend's name, online or not
-- (lower case, full and short) into friendNames.
local function OnlineCharacters()
	local list = {}
	wipe(friendNames)
	for i = 1, C_FriendList.GetNumFriends() or 0 do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.name then
			friendNames[info.name:lower()] = true
			friendNames[Ambiguate(info.name, "short"):lower()] = true
			if info.connected then
				list[info.name:lower()] = info
			end
		end
	end
	return list
end

local function Settled()
	return GetTime() >= settleUntil
end

-- entry = { name (shown), names (for the watch list and repeats), class, text, guild, bnToken, tell }
local function Announce(entry)
	local db = ns.friendsDB
	if db.notify == "off" or not Settled() then
		return
	end
	local watched = ns.Social_IsWatched(watch, unpack(entry.names))
	if not watched and (db.notify ~= "all" or entry.guild) then
		return
	end
	local key = (entry.names[1] or ""):lower()
	if announced[key] and GetTime() - announced[key] < REPEAT then
		return
	end
	announced[key] = GetTime()
	ns.Toast_Show({
		owner = OWNER,
		label = entry.guild and "Guildmate online" or "Friend online",
		accent = entry.guild and GUILD_ACCENT or ACCENT,
		title = ClassColored(entry.name, entry.class),
		text = entry.text,
		hold = 8,
		digestName = entry.names[1],
		onClick = function()
			if entry.bnToken then
				ChatFrameUtil.SendBNetTell(entry.bnToken)
			elseif entry.tell then
				ChatFrameUtil.SendTell(entry.tell)
			end
		end,
	})
	ns.Social_PlaySound(db.sound)
	if db.flash and watched then
		FlashClientIcon()
	end
end

-- "3 friends online" with the number in the accent color, so it stands out from the words.
local COUNT_COLOR = CreateColor(ACCENT[1], ACCENT[2], ACCENT[3])
local function Count(n, one, many)
	return COUNT_COLOR:WrapTextInColorCode(tostring(n)) .. " " .. (n == 1 and one or many)
end

local function Summary(preview)
	local wow, other, idle, seen = {}, 0, 0, {}
	for _, friend in ipairs(OnlineBNet()) do
		if friend.inWoW then
			local game = friend.info.gameAccountInfo
			seen[game.characterName:lower()] = true
			wow[#wow + 1] = ("%s (%s)"):format(friend.info.accountName, ClassColored(game.characterName, game.classFilename))
		elseif friend.idle then
			idle = idle + 1
		else
			other = other + 1
		end
	end
	for _, info in pairs(OnlineCharacters()) do
		local short = Ambiguate(info.name, "short")
		if not seen[short:lower()] then
			wow[#wow + 1] = ClassColored(short, ClassOf(info.guid))
		end
	end
	local guild = 0
	if IsInGuild() then
		local _, online = GetNumGuildMembers()
		guild = math.max((online or 0) - 1, 0) -- you're online too
	end
	if #wow == 0 and other == 0 and idle == 0 and guild == 0 and not preview then
		return
	end
	-- "3 friends online" on top; below, friends in game with their names, then other games and guildmates.
	-- Friends only in the launcher count as online and get no line of their own.
	local lines, extra = {}, {}
	if #wow > 0 then
		lines[1] = Count(#wow, "friend", "friends") .. " in game: " .. ns.Social_NameList(wow, 3)
	end
	if other > 0 then
		extra[#extra + 1] = Count(other, "in another game", "in other games")
	end
	if guild > 0 then
		extra[#extra + 1] = Count(guild, "guildmate", "guildmates")
	end
	if #extra > 0 then
		lines[#lines + 1] = table.concat(extra, "  -  ")
	end
	local friends = #wow + other + idle
	ns.Toast_Show({
		owner = OWNER,
		label = "Online now",
		accent = ACCENT,
		title = Count(friends, "friend online", "friends online"),
		text = #lines > 0 and table.concat(lines, "\n") or (friends == 0 and "Nobody's online right now." or nil),
		hold = 12,
		onClick = function()
			ToggleFriendsFrame(FRIEND_TAB_FRIENDS)
		end,
	})
end

local function RebuildWatch()
	watch = ns.Social_ParseWords(ns.friendsDB.watch)
	-- Guildmates only come from the system message: listen only when someone could be on the list.
	if module.active and #watch > 0 then
		events:RegisterEvent("CHAT_MSG_SYSTEM")
	else
		events:UnregisterEvent("CHAT_MSG_SYSTEM")
	end
end

function events:PLAYER_ENTERING_WORLD(isInitialLogin, isReload)
	if not (isInitialLogin or isReload) then
		return -- a loading screen: nothing new
	end
	settleUntil = GetTime() + SETTLE
	C_FriendList.ShowFriends()
	if IsInGuild() then
		C_GuildInfo.GuildRoster()
	end
	if isInitialLogin and ns.friendsDB.summary then
		C_Timer.After(SUMMARY_DELAY, function()
			if module.active then
				Summary()
			end
		end)
	end
end

function events:FRIENDLIST_UPDATE()
	local now = OnlineCharacters()
	local set = {}
	for key in pairs(now) do
		set[key] = true
	end
	for _, key in ipairs(ns.Social_NewlyOnline(friendsOnline, set)) do
		local info = now[key]
		local short = Ambiguate(info.name, "short")
		local where = info.area and info.area ~= "" and info.area or nil
		Announce({
			name = short,
			names = { short, info.name },
			class = ClassOf(info.guid),
			text = where and (("Level %d - %s"):format(info.level or 0, where)) or nil,
			tell = info.name,
		})
	end
	friendsOnline = set
end

function events:BN_FRIEND_ACCOUNT_ONLINE(bnetAccountID, isCompanionApp)
	if isCompanionApp or not Settled() then
		return
	end
	C_Timer.After(BN_DELAY, function()
		if not module.active then
			return
		end
		local info = C_BattleNet.GetAccountInfoByID(bnetAccountID)
		if not (info and info.battleTag) then
			return
		end
		local game = info.gameAccountInfo
		if game and game.characterName and friendNames[game.characterName:lower()] then
			return -- also a character friend: announced from the friend list
		end
		local activity = Activity(game)
		Announce({
			name = info.accountName,
			names = { ns.Social_ShortTag(info.battleTag), info.battleTag, game and game.characterName },
			text = activity and ("Playing " .. activity) or nil,
			bnToken = info.accountName,
		})
	end)
end

-- "|Hplayer:Name-Realm|h[Name]|h has come online." Character friends are announced from the friend list.
function events:CHAT_MSG_SYSTEM(text)
	if not Readable(text) then
		return
	end
	if not onlinePattern then
		onlinePattern = ns.Moments_FormatToPattern(ERR_FRIEND_ONLINE_SS)
	end
	local full = text:match(onlinePattern)
	if not full then
		return
	end
	local short = Ambiguate(full, "short")
	if friendNames[full:lower()] or friendNames[short:lower()] then
		return -- a character friend: announced from the friend list
	end
	Announce({ name = short, names = { short, full }, guild = true, text = "Your guild", tell = full })
end

local function Preview()
	if not module.active then
		ns.Print("Friends Online is off.")
		return
	end
	Summary(true)
	ns.Toast_Show({ owner = OWNER, label = "Friend online", accent = ACCENT, title = ClassColored("Jaina", "MAGE"),
		text = "Level 90 - Silvermoon City", hold = 8 })
end

local function Activate()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	RebuildWatch()
	if ns.inWorld then
		friendsOnline = nil
		C_FriendList.ShowFriends() -- baseline for "came online"
	end
end

local function Deactivate()
	events:UnregisterAllEvents()
	friendsOnline = nil
	ns.Toast_Clear(OWNER)
end

local NOTIFY_CHOICES = {
	{ value = "off", text = "Off" },
	{ value = "watched", text = "Watch list only" },
	{ value = "all", text = "All friends" },
}

local options = {
	{ type = "header", label = "At login" },
	{ type = "checkbox", key = "summary", label = "Who's online",
		tooltip = "A card a few seconds after login: how many friends are online, who's in WoW (with their character), friends in other games and how many guildmates are on. Click it for the friends list." },
	{ type = "header", label = "Coming online" },
	{ type = "dropdown", key = "notify", label = "Toast when", choices = function()
		return NOTIFY_CHOICES
	end, tooltip = "All friends: every character and Battle.net friend. Watch list only: just the people below. Guildmates only ever come from the watch list." },
	{ type = "input", key = "watch", label = "Watch list", placeholder = "Anna, Thrall, Bjorn#2345", onChange = RebuildWatch,
		tooltip = "Character names, guildmates or BattleTags (the number is optional), separated by commas. Watched people also flash the taskbar icon." },
	{ type = "checkbox", key = "flash", label = "Flash for watched people",
		tooltip = "Flash the taskbar icon when someone on the watch list comes online." },
	{ type = "dropdown", key = "sound", label = "Sound", onChange = ns.Social_PlaySound, choices = function()
		return ns.SOCIAL_SOUND_CHOICES
	end, tooltip = "Played on the Master channel. Blizzard's own Battle.net toast has its own sound." },
	{ type = "button", label = "Sample", text = "Show", onClick = Preview,
		tooltip = "The login card with who's online now, and a sample friend toast." },
}
ns.Toast_Options(options)

module = ns.RegisterModule({
	key = "friends",
	name = "Friends Online",
	category = "Social",
	description = "Who's online when you log in, and a toast when friends (or just the people you watch, guildmates too) come online. Click a toast to whisper them.",
	enabledByDefault = true,
	defaults = {
		summary = true,
		notify = "watched",
		watch = "",
		flash = true,
		sound = "off",
	},
	init = function(db)
		ns.friendsDB = db
	end,
	toggle = function(active)
		if active then
			Activate()
		else
			Deactivate()
		end
	end,
	commands = {
		{ "preview", "show who's online now and a sample toast", Preview },
	},
	options = options,
})
