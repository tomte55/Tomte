local addonName, ns = ...

-- World quests module: the viewed map's world quests grouped and sorted by reward, in a tab of the world map's side
-- panel (Tab.lua), plus a toast when you arrive in a zone with a world quest that rewards a missing mount, pet or toy
-- or a clean Gear Check upgrade. Pure logic in Data.lua, game reading in Scan.lua.

local OWNER = "wq"
local ACCENT = { 0.95, 0.75, 0.3 }
local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local DEBOUNCE = 0.5
local ZONE_DELAY = 3 -- seconds after arriving before the zone is read
local LOGIN_DELAY = 8
local RETRY_DELAY = 5 -- rewards may still be loading
local RETRIES = 2
local TOAST_REASONS = { collectible = true, upgrade = true }
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED", "QUEST_TURNED_IN",
	"WORLD_QUEST_COMPLETED_BY_SPELL", "SUPER_TRACKING_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
}

local module, db
local toasted = {} -- [questID] = true, this session
local refreshTimer
local zoneToken = 0 -- a newer zone check cancels pending retries
local loggedIn = false

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Options()
	return { show = db.show, worth = db.worth, collapsed = {}, maxLevel = ns.WQ_MaxLevel() }
end

-- Redraws an open tab, debounced (QUEST_LOG_UPDATE and item info come in bursts).
local function RefreshSoon()
	if refreshTimer or not ns.WQTab_IsShown() then
		return
	end
	refreshTimer = C_Timer.NewTimer(DEBOUNCE, function()
		refreshTimer = nil
		ns.WQTab_Refresh()
	end)
end

-- Toast ---------------------------------------------------------------------------------------------------------

local function ShowToast(zoneName, list, icon)
	local title, text = ns.WQ_ToastText(zoneName, list)
	ns.Toast_Show({
		owner = OWNER, label = "World quests", accent = ACCENT, title = title, text = text, icon = icon or ICON,
		mergeKey = "wq:zone", holdInCombat = true, hold = 10, onClick = ns.WQTab_Open,
	})
end

-- The quests in your zone worth a toast that haven't had one: { { title, what, id, icon } }, plus how many still load.
local function WorthToasting()
	local quests, name, kind, _, pending = ns.WQ_ForMap(C_Map.GetBestMapForUnit("player"))
	if not quests or kind ~= "zone" then
		return nil
	end
	local list = {}
	for _, section in ipairs(ns.WQ_Sections(quests, Options())) do
		if section.key == "worth" then
			for _, q in ipairs(section.quests) do
				if TOAST_REASONS[q.reason] and not toasted[q.id] then
					local item = ns.WQ_MainItem(q)
					list[#list + 1] = { id = q.id, title = q.title, what = (ns.WQ_RewardText(q)), icon = item and item.icon }
				end
			end
		end
	end
	return list, name, pending
end

local function ZoneCheck(token, attempt)
	if token ~= zoneToken or not (module.active and db.toast) then
		return
	end
	if InCombatLockdown() then
		C_Timer.After(RETRY_DELAY, function()
			ZoneCheck(token, attempt)
		end)
		return
	end
	local list, name, pending = WorthToasting()
	if not list then
		return
	end
	if pending > 0 and attempt < RETRIES then
		C_Timer.After(RETRY_DELAY, function()
			ZoneCheck(token, attempt + 1)
		end)
		return
	end
	if #list == 0 then
		return
	end
	for _, entry in ipairs(list) do
		toasted[entry.id] = true
	end
	ShowToast(name, list, list[1].icon)
end

local function ScheduleZoneCheck(delay)
	zoneToken = zoneToken + 1
	local token = zoneToken
	C_Timer.After(delay, function()
		ZoneCheck(token, 0)
	end)
end

-- Events --------------------------------------------------------------------------------------------------------

function events:PLAYER_ENTERING_WORLD()
	if not loggedIn then
		loggedIn = true
		ScheduleZoneCheck(LOGIN_DELAY)
	end
end

function events:ZONE_CHANGED_NEW_AREA()
	ScheduleZoneCheck(ZONE_DELAY)
end

events.QUEST_LOG_UPDATE = RefreshSoon
events.GET_ITEM_INFO_RECEIVED = RefreshSoon
events.SUPER_TRACKING_CHANGED = RefreshSoon
events.PLAYER_EQUIPMENT_CHANGED = RefreshSoon

function events:QUEST_TURNED_IN(questID)
	ns.WQ_Forget(questID)
	RefreshSoon()
end

function events:WORLD_QUEST_COMPLETED_BY_SPELL(questID)
	ns.WQ_Forget(questID)
	RefreshSoon()
end

-- Commands ------------------------------------------------------------------------------------------------------

local function RequireActive()
	if not module.active then
		ns.Print("World quests is off.")
		return false
	end
	return true
end

local function Here()
	if not RequireActive() then
		return
	end
	local quests, name, kind, _, pending = ns.WQ_ForMap(C_Map.GetBestMapForUnit("player"))
	if not quests then
		ns.Print("no zone here.")
		return
	end
	local opts = Options()
	local shown = 0
	local sections = ns.WQ_Sections(quests, opts)
	for _, s in ipairs(sections) do
		shown = shown + #s.quests
	end
	ns.Print(("%s (%s): %d world quests, %d listed, %d still loading."):format(name, kind, #quests, shown, pending))
	for _, s in ipairs(sections) do
		print("  " .. s.title .. ":")
		for _, q in ipairs(s.quests) do
			local main, secondary = ns.WQ_RewardText(q)
			local time = ns.WQ_TimeText(q.seconds) or "?"
			print(("    %s [%d] %s: %s%s%s"):format(q.title, q.id, time, main, secondary and (" · " .. secondary) or "",
				q.reason and (" (" .. q.reason .. ")") or ""))
		end
	end
end

local function Test()
	if not RequireActive() then
		return
	end
	ShowToast("Hallowfall", { { title = "Sample Quest", what = "Mount: Sample Drake" },
		{ title = "Another Quest", what = "ilvl 619 · Upgrade +3.2%" } })
end

local function Changed()
	ns.WQTab_Refresh()
end

-- Home reads the quests for its title and its rows in the same refresh: one read serves both.
local homeQuests, homeQuestsAt
local function HomeQuests()
	if homeQuestsAt ~= GetTime() then
		homeQuests, homeQuestsAt = ns.WQ_ForMap(C_Map.GetBestMapForUnit("player")), GetTime()
	end
	return homeQuests
end

module = ns.RegisterModule({
	key = "wq",
	name = "World quests",
	category = "World",
	description = "A tab in the world map's side panel with the world quests on the map you're looking at, grouped "
		.. "by reward and sorted by what they're worth: missing mounts, pets and toys and real gear upgrades (from "
		.. "Gear Check) on top, then gear, gold, currencies and reputation, with time left. Click to track one. A "
		.. "toast when you arrive in a zone with one worth doing.",
	enabledByDefault = true,
	home = {
		{ kind = "map", key = "worldquests", order = 3, name = "World quests", icon = "Interface\\Icons\\INV_Misc_Map_01",
			open = function()
				ns.WQTab_Open()
			end,
			summary = function()
				local zoneID = ns.MapTabs_ResolveMap(C_Map.GetBestMapForUnit("player"))
				if not zoneID then
					return nil
				end
				local n = 0
				for _, info in ipairs(C_TaskQuest.GetQuestsOnMap(zoneID) or {}) do
					if info.questID and C_QuestLog.IsWorldQuest(info.questID)
						and not C_QuestLog.IsQuestFlaggedCompleted(info.questID) then
						n = n + 1
					end
				end
				return n == 1 and "1 world quest around here" or (n .. " world quests around here")
			end },
		{ kind = "next", key = "nextwq", name = "World quests worth doing", score = 80,
			description = "A world quest around you rewards a mount, pet or toy you're missing, or a clean gear upgrade "
				.. "(click to track it).",
			candidates = function()
				local quests = HomeQuests()
				local list = {}
				for _, section in ipairs(quests and ns.WQ_Sections(quests, ns.WQ_Options()) or {}) do
					if section.key == "worth" then
						for _, q in ipairs(section.quests) do
							if TOAST_REASONS[q.reason] then
								local main = ns.WQ_RewardText(q)
								list[#list + 1] = {
									key = "wq:" .. q.id, text = main,
									why = q.title .. (q.zone and (", " .. q.zone) or ""),
									right = (ns.WQ_TimeText(q.seconds)), icon = ns.WQ_RowIcon(q),
									bonus = q.reason == "collectible" and 9 or 5,
									onClick = function()
										ns.WQ_Track(q)
									end, hint = "Click to track it",
								}
							end
						end
					end
				end
				return list
			end },
		{ kind = "around", key = "wqaround", order = 2, name = "World quests",
			icon = "Interface\\Icons\\INV_Misc_Map_01",
			open = function()
				ns.WQTab_Open()
			end,
			title = function()
				local quests = HomeQuests()
				if not quests then
					return "World quests: none on this map"
				end
				local n = 0
				for _, s in ipairs(ns.WQ_Sections(quests, ns.WQ_Options())) do
					n = n + #s.quests
				end
				return ("World quests: %d here"):format(n)
			end,
			-- The tab's own order: worth-it rewards first.
			items = function(limit)
				local quests = HomeQuests()
				local rows = {}
				for _, s in ipairs(quests and ns.WQ_Sections(quests, ns.WQ_Options()) or {}) do
					for _, q in ipairs(s.quests) do
						if #rows >= limit then
							return rows
						end
						local main = ns.WQ_RewardText(q)
						rows[#rows + 1] = {
							icon = ns.WQ_RowIcon(q), text = main, right = ns.WQ_TimeText(q.seconds),
							color = s.key == "worth" and { 1, 0.82, 0.45 } or nil,
							onEnter = function(row)
								GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
								GameTooltip:SetText(q.title, 1, 1, 1)
								GameTooltip:AddLine(main, 0.8, 0.8, 0.8)
								GameTooltip:Show()
							end,
						}
					end
				end
				return rows
			end },
	},
	defaults = {
		show = { pvp = false, petbattle = false, otherProfessions = false },
		worth = { transmog = false, gold = false, goldAmount = 500 },
		collapsed = { worth = false, gear = false, gold = false, currency = false, rep = false, other = true },
		toast = true,
		preview = true,
	},
	init = function(saved)
		db = saved
		ns.WQTab_Init(db)
	end,
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			ns.WQTab_SetEnabled(true)
			if ns.inWorld and not loggedIn then
				loggedIn = true
				ScheduleZoneCheck(ZONE_DELAY)
			end
		else
			events:UnregisterAllEvents()
			zoneToken = zoneToken + 1
			if refreshTimer then
				refreshTimer:Cancel()
				refreshTimer = nil
			end
			ns.WQTab_SetEnabled(false)
			ns.WQ_ClearCache()
			ns.Toast_Clear(OWNER)
		end
	end,
	commands = {
		{ "open", "open the map on the World quests tab", ns.WQTab_Open },
		{ "here", "your zone's world quests by section, in chat", Here },
		{ "test", "show a sample toast", Test },
	},
	options = {
		{ type = "header", label = "List" },
		{ type = "checkbox", key = "show.pvp", label = "PvP quests", onChange = Changed },
		{ type = "checkbox", key = "show.petbattle", label = "Pet battle quests", onChange = Changed },
		{ type = "checkbox", key = "show.otherProfessions", label = "Profession quests you can't do", onChange = Changed,
			tooltip = "Quests for professions this character doesn't have. Your own professions' quests always show." },
		{ type = "checkbox", key = "preview", label = "Model preview",
			tooltip = "Hovering a quest that rewards a mount, pet or appearance shows it, turning, next to the tooltip." },
		{ type = "header", label = "Worth it" },
		{ type = "checkbox", key = "worth.transmog", label = "Appearances you don't have", onChange = Changed,
			tooltip = "Gear whose look this character can collect and the account doesn't have yet." },
		{ type = "checkbox", key = "worth.gold", label = "Big gold rewards", onChange = Changed },
		{ type = "slider", key = "worth.goldAmount", label = "Big gold is at least", min = 100, max = 5000, step = 100,
			onChange = Changed, format = function(v)
				return ("%dg"):format(v)
			end },
		{ type = "header", label = "Toast" },
		{ type = "checkbox", key = "toast", label = "Arriving in a zone with a quest worth doing",
			tooltip = "A missing mount, pet or toy, or a clean Gear Check upgrade. Once per quest per session." },
		{ type = "button", label = "Sample toast", text = "Show", onClick = Test },
	},
})
