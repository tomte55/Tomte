local addonName, ns = ...

-- Groups in chat (World of Warcraft: Forever only; tools/forever_list.lua): reads the chat channels you've joined for people
-- looking for a dungeon group and lists them on a page. It adds to the game's Looking For Group window, which only has what
-- people list there. Nothing is kept between sessions. Rules in Data.lua, the page in Page.lua, the dungeons in
-- Data/Forever/Dungeons.lua. See docs/superpowers/specs/2026-11-06-tomte-forever-rest-and-chat-groups.md.

local ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"
local MAX_AGE = 600 -- seconds a message stays on the list: an older group has filled or given up
local PRUNE_EVERY = 30 -- seconds, so ages and old messages move while the page is open
local TOAST_AGAIN = 300 -- seconds before the same person's same dungeon can toast again
local TOAST_HOLD = 8
local QUEST_TOAST_HOLD = 15 -- seconds: long enough to decide and click to whisper

local module, db, ticker
local list = {}
local dungeons, byKey
local toasted = {} -- ["sender:dungeon"] = time() of the last toast

local events = CreateFrame("Frame")

function ns.ChatGroups_DB()
	return db
end

function ns.ChatGroups_List()
	return list
end

-- [key] = dungeon.
function ns.ChatGroups_Dungeons()
	return byKey
end

local function Toast(entry)
	local key = entry.sender .. ":" .. entry.dungeon
	if time() - (toasted[key] or 0) < TOAST_AGAIN then
		return
	end
	toasted[key] = time()
	ns.Toast_Show({ owner = "chatgroups", label = "Groups in chat", title = byKey[entry.dungeon].name,
		text = ("%s: %s"):format(entry.name, ns.ChatGroups_RoleText(entry)), icon = ICON, hold = TOAST_HOLD })
end

-- The unfinished quests in your log, for ChatGroups_YourQuest. Read when a message links a quest, which isn't often.
local function MyQuests()
	local mine = { byID = {}, byName = {} }
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID
			and not (C_QuestLog.ReadyForTurnIn(info.questID) or C_QuestLog.IsComplete(info.questID)) then
			mine.byID[info.questID] = true
			if info.title then
				mine.byName[info.title:lower()] = true
			end
		end
	end
	return mine
end

-- Whether the sender is already in your party or raid: you don't need a toast to find them.
local function InMyGroup(guid)
	if not guid or guid == "" or not IsInGroup() then
		return false
	end
	local prefix = IsInRaid() and "raid" or "party"
	for i = 1, GetNumGroupMembers() do
		if UnitGUID(prefix .. i) == guid then
			return true
		end
	end
	return false
end

-- Someone in chat is grouping for a quest you still have to do: click to whisper them.
local function QuestToast(entry)
	local key = entry.sender .. ":quest:" .. (entry.questID or entry.quest)
	if time() - (toasted[key] or 0) < TOAST_AGAIN then
		return
	end
	toasted[key] = time()
	local sender = entry.sender
	ns.Toast_Show({ owner = "chatgroups", label = "Your quest in chat", title = entry.quest,
		text = ("%s: %s. Click to whisper."):format(entry.name, ns.ChatGroups_RoleText(entry)), icon = ICON,
		hold = QUEST_TOAST_HOLD, onClick = function()
			ns.Chat_SendTell(sender)
		end })
end

function events:CHAT_MSG_CHANNEL(text, sender, _, _, _, _, _, _, _, _, _, guid)
	if not ns.Readable(text, sender, guid) then
		return -- chat lockdown
	end
	if guid == UnitGUID("player") then
		return
	end
	local entry = ns.ChatGroups_Parse(text, dungeons)
	if not entry then
		return
	end
	entry.sender, entry.name, entry.text, entry.at = sender, Ambiguate(sender, "short"), text, time()
	if guid and guid ~= "" then
		local _, class = GetPlayerInfoByGUID(guid)
		entry.class = class
	end
	ns.ChatGroups_Add(list, entry)
	ns.ChatGroupsPage_Refresh()
	if InMyGroup(guid) then
		return
	end
	if db.questToast and entry.quest and not entry.dungeon and ns.ChatGroups_YourQuest(entry, MyQuests()) then
		QuestToast(entry)
	elseif db.toast and entry.kind == "group" and ns.ChatGroups_Near(byKey[entry.dungeon], UnitLevel("player")) then
		Toast(entry)
	end
end

events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

local function Tick()
	ns.ChatGroups_Prune(list, time(), MAX_AGE)
	ns.ChatGroupsPage_Refresh()
end

local function Why()
	if not ns.Module_RequireOn(module) then
		return
	end
	local groups, players = 0, 0
	for _, entry in ipairs(list) do
		if entry.kind == "group" then
			groups = groups + 1
		else
			players = players + 1
		end
	end
	ns.Print(("Groups in chat: %d groups and %d players from the last %d minutes."):format(groups, players, MAX_AGE / 60))
end

module = ns.RegisterModule({
	key = "chatgroups",
	name = "Groups in chat",
	category = "social",
	icon = ICON,
	summary = "A list of everyone looking for a group in the chat channels you've joined.",
	description = "Reads the chat channels you've joined for people looking for a group, for a dungeon, a quest or anything "
		.. "else, and lists them by dungeon and role, so you don't have to watch chat. Click someone to whisper them. It reads English messages and abbreviations. "
		.. "The game's own Looking For Group window lists groups too.",
	enabledByDefault = true,
	toasts = "Groups in chat",
	defaults = {
		kind = "all", -- the page's filter: "all", "group" or "player"
		near = true, -- the page's filter: only dungeons near your level
		toast = false,
		questToast = true, -- a toast when someone groups for a quest you still have to do
	},
	home = {
		{ kind = "page", key = "chatgroups", order = 7, name = "Groups in chat", icon = ICON, page = ns.ChatGroupsPage,
			summary = function()
				return #list > 0 and ("%d looking right now"):format(#list) or "Nobody looking right now"
			end },
	},
	init = function(moduleDB)
		db = moduleDB
		dungeons = ns.Content_Get(ns.CONTENT_FOREVER, "dungeons") or {}
		byKey = ns.ChatGroups_ByKey(dungeons)
	end,
	toggle = function(active)
		if active then
			events:RegisterEvent("CHAT_MSG_CHANNEL")
			ticker = C_Timer.NewTicker(PRUNE_EVERY, Tick)
		else
			events:UnregisterAllEvents()
			if ticker then
				ticker:Cancel()
				ticker = nil
			end
			wipe(list)
			ns.ChatGroupsPage_Refresh()
			ns.Toast_Clear("chatgroups")
		end
	end,
	commands = {
		{ "why", "how many people are on the list", Why },
	},
	options = {
		{ type = "header", label = "Groups in chat" },
		{ type = "checkbox", key = "toast", label = "Toast for groups near my level",
			tooltip = "A toast when a group in chat asks for people for a dungeon near your level." },
		{ type = "checkbox", key = "questToast", label = "Toast for my quests",
			tooltip = "A toast when someone in chat groups for a quest you still have to do. Click it to whisper them." },
	},
})
