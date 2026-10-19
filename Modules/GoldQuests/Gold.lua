local addonName, ns = ...

-- Gold world quests module: a gold world quest window modelled on GoldWQ (public domain; spec docs/superpowers/specs/2026-10-11-tomte-gold-world-quests-
-- design.md). The gold world quests of the player's expansion with totals, special assignments, weekly caches, a
-- route that tracks them one by one, and world quest gold per character. Pure logic in Data.lua, game reading in
-- Scan.lua, the window in Window.lua.

local OWNER = "wgq"
local LOGIN_DELAY = 6 -- seconds after login before the first scan
local LOGIN_RETRY = 5 -- seconds between scans while rewards load
local LOGIN_TRIES = 12 -- then the login line goes out with what loaded
local WINDOW_DELAY = 2 -- seconds after login before a window left open comes back
local DEBOUNCE = 1

local module, db
local events = ns.NewEvents()
local lastModel
local char
local viewExpansion -- the expansion picked in the window (this session); nil = the player's
local currentCount = 0 -- gold quests up in the player's expansion at the last scan of it (Home)
local currentGroup -- that scan's totals (minimap button tooltip)
local loggedIn = false
local refreshTimer
local wqSeen = {} -- [questID] = true: world quests the scans saw this session (turn-ins only say the ID)

-- Characters ------------------------------------------------------------------------------------------------------

local function Char()
	local guid = UnitGUID("player")
	local c = db.chars[guid]
	if not c then
		c = ns.Gold_NewChar()
		db.chars[guid] = c
	end
	ns.MergeDefaults(ns.Gold_NewChar(), c)
	char = c
	return c
end

local function UpdateChar()
	local c = Char()
	c.name = UnitName("player")
	c.realm = GetNormalizedRealmName()
	c.class = select(2, UnitClass("player"))
	local level = UnitLevel("player")
	if not ns.IsSecret(level) then
		c.level = level
	end
	c.expansion = ns.ContentExpansion()
	ns.Gold_RollWeek(c, GetServerTime(), C_DateAndTime.GetSecondsUntilWeeklyReset())
	c.firstReset = c.firstReset or c.nextReset -- the end of the week Tomte started tracking this character
	return c
end

function ns.Gold_TurnedIn()
	return char and char.turnedIn or {}
end

-- Tomte started tracking this character this week: caches done before that don't show as done.
function ns.Gold_TrackingFresh()
	return char ~= nil and char.firstReset ~= nil and GetServerTime() < char.firstReset
end

-- The Characters view: characters at their expansion's max level, or with world quest gold.
function ns.Gold_Characters(now)
	local shown = {}
	for guid, c in pairs(db.chars) do
		local maxLevel = ns.ContentMaxLevel(c.expansion)
		if (c.totalCopper or 0) > 0 or (c.level and maxLevel and c.level >= maxLevel) then
			shown[guid] = c
		end
	end
	return ns.Gold_SortChars(shown, UnitGUID("player"), now)
end

-- Scanning --------------------------------------------------------------------------------------------------------

-- The expansion the window shows: the one picked in its menu, else the player's.
function ns.Gold_ViewExpansion()
	return viewExpansion or ns.ContentExpansion()
end

-- nil goes back to the player's expansion.
function ns.Gold_SetViewExpansion(expansion)
	viewExpansion = expansion ~= ns.ContentExpansion() and expansion or nil
end

-- The menu's choices: the expansions with zones that the account owns, newest first.
function ns.Gold_ExpansionChoices()
	local owned = GetExpansionLevel()
	local list = {}
	for _, e in ipairs(ns.Content_Expansions()) do
		if ns.Content_Get(e, "goldZones") and e <= owned then
			table.insert(list, 1, { value = e, text = ns.ExpansionName(e) })
		end
	end
	return list
end

-- A fresh read of the game for the window's expansion (also rolls this character's week over when the reset passed).
function ns.Gold_Scan()
	local c = UpdateChar()
	local expansion = ns.Gold_ViewExpansion()
	lastModel = ns.Gold_Read(c, db.hiddenCaches, expansion, expansion == ns.ContentExpansion())
	for _, q in ipairs(lastModel and lastModel.quests or {}) do
		wqSeen[q.id] = true
	end
	if lastModel and expansion == ns.ContentExpansion() then
		currentCount = lastModel.group.count
		currentGroup = lastModel.group
	end
	return lastModel
end

function ns.Gold_LastModel()
	return lastModel
end

local function RefreshSoon()
	if refreshTimer or not ns.GoldWindow_IsShown() then
		return
	end
	refreshTimer = C_Timer.NewTimer(DEBOUNCE, function()
		refreshTimer = nil
		ns.GoldWindow_Refresh()
	end)
end

ns.WQRoute_Listen(function()
	ns.GoldWindow_Redraw()
end)

-- Route (Modules/WorldQuests/Route.lua) ---------------------------------------------------------------------------

-- The gold quests up in an expansion's zones, read without touching the window's model. A quest whose reward isn't
-- loaded (again) is still up: the route keeps it.
local function GoldUp(expansion)
	local list = {}
	local quests = ns.WQ_ForZones(ns.Content_Get(expansion, "goldZones") or {})
	for _, q in ipairs(quests) do
		if not q.loaded or q.money > 0 then
			list[#list + 1] = q
		end
	end
	return list
end

function ns.Gold_StartRoute()
	local model = ns.Gold_Scan()
	if not model or model.group.count == 0 then
		ns.Print("no gold world quests to route" .. (model and model.pending > 0 and " yet: rewards are still loading."
			or "."))
		return
	end
	local expansion = model.expansion
	local quests = {}
	for _, zone in ipairs(model.group.zones) do
		for _, q in ipairs(zone.quests) do
			quests[#quests + 1] = q
		end
	end
	local label = ("%s gold world quests (%s)"):format(ns.ExpansionName(expansion), ns.Gold(model.group.total))
	ns.WQRoute_Start(quests, function()
		return GoldUp(expansion)
	end, OWNER, label)
end

-- Events ----------------------------------------------------------------------------------------------------------

local function LoginScan(tries)
	if not module.active then
		return
	end
	local model = ns.Gold_Scan()
	if model and model.pending > 0 and tries < LOGIN_TRIES then
		C_Timer.After(LOGIN_RETRY, function()
			LoginScan(tries + 1)
		end)
		return
	end
	if model and model.expansion == ns.ContentExpansion() and db.announce and ns.ContentAtMax() then
		ns.Print(ns.Gold_LoginLine(model.group))
	end
	ns.GoldWindow_Redraw()
end

local function OnLogin()
	if loggedIn then
		return
	end
	loggedIn = true
	UpdateChar()
	C_Timer.After(LOGIN_DELAY, function()
		LoginScan(0)
	end)
	if db.window.shown then
		C_Timer.After(WINDOW_DELAY, function()
			if module.active and db.window.shown then
				ns.GoldWindow_Show()
			end
		end)
	end
end

events:On(OWNER, "PLAYER_ENTERING_WORLD", function()
	OnLogin()
end)

events:On(OWNER, "QUEST_LOG_UPDATE", RefreshSoon)
events:On(OWNER, "GET_ITEM_INFO_RECEIVED", RefreshSoon)
events:On(OWNER, "SUPER_TRACKING_CHANGED", function()
	ns.GoldWindow_Redraw()
end)

events:On(OWNER, "QUEST_TURNED_IN", function(_, questID, _, money)
	local c = UpdateChar()
	c.turnedIn[questID] = true
	local isWQ = wqSeen[questID] or C_QuestLog.IsWorldQuest(questID)
	if isWQ and ns.Gold_AddEarned(c, questID, money) and db.earnedLine then
		ns.Print(("+%s from world quests (this week: %s)."):format(ns.WQ_FormatGold(money), ns.Gold(c.weekCopper)))
	end
	ns.WQ_Forget(questID)
	RefreshSoon()
end)

local EVENTS = { "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED", "SUPER_TRACKING_CHANGED",
	"QUEST_TURNED_IN" }

-- Commands --------------------------------------------------------------------------------------------------------

local function Toggle()
	if ns.Module_RequireOn(module) then
		ns.GoldWindow_Toggle()
	end
end

local function Open()
	if ns.Module_RequireOn(module) then
		ns.GoldWindow_Show()
	end
end

local function List()
	if not ns.Module_RequireOn(module) then
		return
	end
	local model = ns.Gold_Scan()
	if not model then
		ns.Print("no gold world quest data for " .. ns.ExpansionName(ns.ContentExpansion()) .. ".")
		return
	end
	ns.Print(ns.Gold_Summary(model.group) .. (model.pending > 0 and (" (%d still loading)"):format(model.pending) or ""))
	for _, zone in ipairs(model.group.zones) do
		print(("  %s: %d, %s"):format(zone.name, #zone.quests, ns.Gold(zone.total)))
		for _, q in ipairs(zone.quests) do
			print(("    %s  %s  %s"):format(ns.WQ_FormatGold(q.money), q.title, ns.WQ_TimeText(q.seconds) or ""))
		end
	end
end

local function Report()
	if not ns.Module_RequireOn(module) then
		return
	end
	UpdateChar()
	local now = GetServerTime()
	ns.Print("world quest gold this week (and in all):")
	for _, entry in ipairs(ns.Gold_Characters(now)) do
		local c = entry.char
		local week, caches = ns.Gold_CharWeek(c, now)
		local list = ns.Content_Get(c.expansion, "caches") or {}
		local done = 0
		for _, cache in ipairs(list) do
			if caches[cache.key] then
				done = done + 1
			end
		end
		print(("  %s-%s: %s (%s), caches %d/%d"):format(c.name or "?", c.realm or "?", ns.Gold(week),
			ns.Gold(c.totalCopper or 0), done, #list))
	end
end

local function Route()
	if ns.Module_RequireOn(module) then
		ns.Gold_StartRoute()
	end
end

local function Stop()
	ns.WQRoute_Stop()
end

local function ResetPlace()
	ns.GoldWindow_ResetPlace()
end

-- Key bindings (Bindings.xml, Key Bindings > Tomte), through ns.Binding_Add.
ns.Binding_Add("GOLD", "wgq", function()
	ns.GoldWindow_Toggle()
end)
BINDING_NAME_TOMTE_GOLD = "Gold world quests window"

module = ns.RegisterModule({
	key = "wgq",
	name = "Gold world quests",
	category = "week",
	icon = 901746, -- inv_misc_coinbag_special
	summary = "Every gold world quest and weekly cache, with a route.",
	description = "A window with every world quest that gives gold in your expansion's zones, by zone with totals, "
		.. "plus the special assignments (done, up, or how many world quests until it unlocks) and the weekly caches "
		.. "you haven't done. Route tracks the gold quests one by one, nearest first. Characters shows each "
		.. "character's world quest gold this week and in all, and its caches. A line in chat at login with what's "
		.. "up. Open it with /tomte wgq, a key binding or Home.",
	enabledByDefault = true,
	replaces = { { addon = "GoldWQ", why = "the gold world quest window with totals, assignments and caches" } },
	minimapButton = {
		name = "Gold world quests",
		icon = "Interface\\Icons\\INV_Misc_Coin_01",
		onClick = function()
			ns.GoldWindow_Toggle()
		end,
		tooltip = function(tooltip)
			tooltip:AddLine(currentGroup and ns.Gold_Summary(currentGroup) or "Not scanned yet", 1, 1, 1)
			tooltip:AddLine("Click to open or close the window", 1, 1, 1)
		end,
	},
	home = {
		{ kind = "quick", key = "goldquick", order = 4, name = "Gold world quests",
			count = function()
				return currentCount
			end,
			open = function()
				ns.GoldWindow_Show()
			end },
	},
	defaults = {
		window = { shown = false, collapsed = false },
		view = "gold",
		scale = 1,
		opacity = 0.55,
		announce = true,
		earnedLine = true,
		collapsed = { quests = false, assignments = false, caches = false },
		hiddenCaches = {}, -- [cache key] = true
		chars = {}, -- [guid] = character record (Data.lua)
	},
	init = function(saved)
		db = saved
		ns.GoldWindow_Init(db)
	end,
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:Watch(OWNER, event)
			end
			if ns.inWorld then
				OnLogin()
			end
		else
			events:UnwatchAll(OWNER)
			if refreshTimer then
				refreshTimer:Cancel()
				refreshTimer = nil
			end
			ns.WQRoute_Stop(OWNER, true)
			viewExpansion = nil
			loggedIn = false
			ns.GoldWindow_Close()
		end
	end,
	commands = {
		{ "", "open or close the window", Toggle, hidden = true },
		{ "open", "open the Gold world quests window", Open },
		{ "list", "the gold world quests by zone, in chat", List },
		{ "route", "track the gold world quests one by one, nearest first", Route },
		{ "stop", "stop the route (also one started in the World quests map tab)", Stop },
		{ "report", "world quest gold and caches per character, in chat", Report },
		{ "reset", "put the window back in the middle at its first size", ResetPlace, whileOff = true },
	},
	options = {
		{ type = "header", label = "Window" },
		{ type = "button", label = "Gold world quests window", text = "Open", onClick = Open },
		{ type = "slider", key = "scale", label = "Scale", min = 0.6, max = 1.5, step = 0.05,
			onChange = ns.GoldWindow_ApplyLook, format = function(v)
				return ("%d%%"):format(math.floor(v * 100 + 0.5))
			end },
		{ type = "slider", key = "opacity", label = "Background opacity", min = 0.2, max = 1, step = 0.05,
			onChange = ns.GoldWindow_ApplyLook, format = function(v)
				return ("%d%%"):format(math.floor(v * 100 + 0.5))
			end },
		{ type = "button", label = "Window position and size", text = "Reset", onClick = ResetPlace },
		{ type = "header", label = "Chat" },
		{ type = "checkbox", key = "announce", label = "Gold world quests up, at login",
			tooltip = "One line once the rewards have loaded: how many gold world quests are up and their total." },
		{ type = "checkbox", key = "earnedLine", label = "Gold from each world quest you hand in" },
		{ type = "header", label = "Weekly caches" },
		{ type = "button", label = "Rows you hid with a right-click", text = "Show again", onClick = function()
			wipe(db.hiddenCaches)
			ns.GoldWindow_Refresh()
		end },
	},
})
