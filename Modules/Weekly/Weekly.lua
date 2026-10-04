local addonName, ns = ...

-- Weekly board module: what you haven't done this week (Great Vault, crests, weekly quests, professions, renown,
-- lockouts) for this character and every other tracked one, aware of the weekly reset without logging them in.
-- Data.lua holds the logic, Collect.lua reads the game, BoardPage.lua and Popup.lua draw. This file wires them up,
-- owns the options and commands, and toasts when a character's Concentration fills up.

local ACCENT = { 0.4, 0.8, 1 }
local CONC_ICON = "Interface\\Icons\\INV_Misc_Gear_01" -- when the profession's own icon isn't known
local MAX_TIMER = 86400

local module, db
local toastTimer

local function Tracked()
	local chars = {}
	for guid, snap in pairs(db.chars) do
		if not db.hidden[guid] then
			chars[guid] = snap
		end
	end
	return chars
end

-- Views of every tracked character, the current one first.
function ns.Weekly_Views()
	local now, views = GetServerTime(), {}
	for _, guid in ipairs(ns.Weekly_CharOrder(db.chars, UnitGUID("player"), db.hidden)) do
		views[#views + 1] = ns.Weekly_View(db.chars[guid], now)
	end
	return views
end

function ns.Weekly_CurrentView()
	local snap = db and db.chars[UnitGUID("player")]
	return snap and ns.Weekly_View(snap, GetServerTime()) or nil
end

local function CheckToasts()
	if toastTimer then
		toastTimer:Cancel()
		toastTimer = nil
	end
	if not (module.active and db.toast) then
		return
	end
	local now = GetServerTime()
	local chars = Tracked()
	for _, due in ipairs(ns.Weekly_DueConc(chars, now)) do
		local snap = db.chars[due.guid]
		local prof = snap.profs[due.skillLine]
		prof.conc.notified = true
		ns.Toast_Show({
			owner = "weekly", label = "Concentration", accent = ACCENT, title = snap.name or "?",
			text = (prof.name or "Profession") .. " Concentration is full. Craft before it goes to waste.",
			icon = prof.icon or CONC_ICON, hold = 10, holdInCombat = true,
			onClick = function()
				ns.weeklyDB.view = "profs"
				ns.Panel_OpenModule("weekly", "page")
				ns.WeeklyBoard_Refresh()
			end,
		})
	end
	local nextFull = ns.Weekly_NextConcFull(chars, now)
	if nextFull then
		toastTimer = C_Timer.NewTimer(math.min(nextFull - now + 5, MAX_TIMER), CheckToasts)
	end
end

local BASE_OPTIONS = {
	{ type = "checkbox", key = "toast", label = "Concentration full toast", onChange = function()
		CheckToasts()
	end, tooltip = "A toast when any tracked character's Concentration is predicted full (once per fill)." },
	{ type = "checkbox", key = "learned", label = "Show learned weekly quests", onChange = function()
		ns.WeeklyBoard_Refresh()
		ns.WeeklyPopup_Refresh()
	end, tooltip = "Weekly quests seen in your quest log (delves, world events, ...) on the board and in the popup, while they're in the log or done this week." },
	{ type = "button", label = "Popup position", text = "Reset", onClick = function()
		ns.WeeklyPopup_ResetPosition()
	end, tooltip = "Put the popup back under the minimap." },
}

-- Options: the fixed ones, then a "Hide" checkbox per tracked character.
local function BuildOptions()
	local options = module.options
	for i = #options, 1, -1 do
		options[i] = nil
	end
	for _, spec in ipairs(BASE_OPTIONS) do
		options[#options + 1] = spec
	end
	local guids = ns.Weekly_CharOrder(db.chars, UnitGUID("player"), {}, true)
	if #guids > 0 then
		options[#options + 1] = { type = "header", label = "Characters" }
	end
	for _, guid in ipairs(guids) do
		local snap = db.chars[guid]
		options[#options + 1] = {
			type = "checkbox", key = "hidden." .. guid,
			label = ("Hide %s (%s)"):format(snap.name or "?", snap.realm or "?"),
			onChange = function()
				ns.WeeklyBoard_Refresh()
				CheckToasts()
			end,
			tooltip = "Leave this character out of the Characters and Professions views and the Concentration toast.",
		}
	end
end

local knownChars = 0

-- After every refresh (Collect.lua).
function ns.Weekly_Changed()
	local n = 0
	for _ in pairs(db.chars) do
		n = n + 1
	end
	if n ~= knownChars then
		knownChars = n
		BuildOptions()
	end
	ns.WeeklyBoard_Refresh()
	ns.WeeklyPopup_Refresh()
	CheckToasts()
end

local function ListQuests()
	local list = {}
	for id, q in pairs(db.quests) do
		list[#list + 1] = { id = id, title = q.title or "?" }
	end
	table.sort(list, function(a, b)
		return a.title < b.title
	end)
	if #list == 0 then
		ns.Print("no weekly quests learned yet. They're learned when one is in your quest log.")
		return
	end
	ns.Print(#list .. " learned weekly quests:")
	for _, q in ipairs(list) do
		local done = C_QuestLog.IsQuestFlaggedCompleted(q.id)
		print(("  %d  %s  %s"):format(q.id, q.title, done and "|cff73d973done|r" or "|cffaaaaaaopen|r"))
	end
end

local function Forget(name)
	if name == "" then
		ns.Print("usage: /tomte weekly forget <name>")
		return
	end
	local forgotten = 0
	for guid, snap in pairs(db.chars) do
		if (snap.name or ""):lower() == name then
			db.chars[guid] = nil
			db.hidden[guid] = nil
			forgotten = forgotten + 1
		end
	end
	ns.Print(forgotten > 0 and ("forgot %d character(s) named %s."):format(forgotten, name)
		or ("no tracked character named %s."):format(name))
	ns.Weekly_Changed()
end

-- Prints every hard-coded ID with what the game says about it, to check the third-party data in game.
local function PrintIDs()
	ns.Print("crests:")
	for _, id in ipairs(ns.WEEKLY_CRESTS) do
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if info and info.name and info.name ~= "" then
			print(("  %d  %s  qty %s, max %s, weekly max %s, season total %s, useTotal %s"):format(id, info.name,
				tostring(info.quantity), tostring(info.maxQuantity), tostring(info.maxWeeklyQuantity),
				tostring(info.totalEarned), tostring(info.useTotalEarnedForMaxQty)))
		else
			print(("  %d  |cffff6060unknown|r"):format(id))
		end
	end
	local expansion = ns.Weekly_Expansion(GetExpansionLevel())
	ns.Print(("expansion level %s, profession data for %s"):format(tostring(GetExpansionLevel()), tostring(expansion)))
	local first, second = GetProfessions()
	for _, index in pairs({ first, second }) do
		local name, _, _, _, _, _, base = GetProfessionInfo(index)
		local def = ns.Weekly_ProfDef(expansion, base)
		ns.Print(("%s (skill line %s):"):format(name or "?", tostring(base)))
		if def then
			local currency = C_TradeSkillUI.GetConcentrationCurrencyID(def.child)
			local info = currency and currency > 0 and C_CurrencyInfo.GetCurrencyInfo(currency)
			print(("  Concentration: currency %s %s"):format(tostring(currency), info and ("%s/%s, cycle %sms +%s"):format(
				tostring(info.quantity), tostring(info.maxQuantity), tostring(info.rechargingCycleDurationMS),
				tostring(info.rechargingAmountPerCycle)) or "none"))
			for _, k in ipairs(ns.Weekly_ProfQuestIDs(def)) do
				local title = C_QuestLog.GetTitleForQuestID(k)
				print(("  %d  %s  %s"):format(k, title or "|cffaaaaaa(no title)|r",
					C_QuestLog.IsQuestFlaggedCompleted(k) and "|cff73d973done|r" or "open"))
			end
		else
			print("  not in the table")
		end
	end
end

module = ns.RegisterModule({
	key = "weekly",
	name = "Weekly board",
	category = "General",
	description = "What you haven't done this week: Great Vault, crests, weekly quests, profession knowledge and Concentration, renown and lockouts, for every max-level character (alts roll over at the weekly reset without logging in). Right-click the minimap button for a quick list.",
	enabledByDefault = true,
	defaults = {
		chars = {}, -- [guid] = snapshot (Collect.lua)
		quests = {}, -- [questID] = { title, firstSeen }, learned weekly quests
		hidden = {}, -- [guid] = true
		view = "week",
		popup = {},
		toast = true,
		learned = true,
	},
	init = function(moduleDB)
		db = moduleDB
		ns.weeklyDB = db
		BuildOptions()
	end,
	toggle = function(active)
		if active then
			ns.WeeklyCollect_Start(db) -- the first refresh checks the toasts
		else
			ns.WeeklyCollect_Stop()
			if toastTimer then
				toastTimer:Cancel()
				toastTimer = nil
			end
			ns.Toast_Clear("weekly")
			ns.WeeklyPopup_Hide()
		end
	end,
	page = ns.WeeklyBoardPage,
	options = {},
	commands = {
		{ "popup", "toggle the weekly popup", ns.WeeklyPopup_Toggle },
		{ "board", "open the weekly board", function()
			ns.Panel_OpenModule("weekly", "page")
		end },
		{ "quests", "list the learned weekly quests", ListQuests },
		{ "forget", "forget a character: /tomte weekly forget <name>", Forget },
		{ "ids", "check the crest and knowledge quest IDs in game", PrintIDs },
	},
})

-- Map pin + super-track, which the Waypoints module (and Blizzard's own arrow) then shows. loc.x/y are percent.
function ns.Weekly_SetWaypoint(loc)
	if not C_Map.CanSetUserWaypointOnMap(loc.map) then
		ns.Print("can't place a map pin on that map.")
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(loc.map, loc.x / 100, loc.y / 100))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	local info = C_Map.GetMapInfo(loc.map)
	ns.Print(("waypoint: %s, %s %.1f %.1f"):format(loc.text or "?", info and info.name or "?", loc.x, loc.y))
end

-- Right-click on the minimap button (Minimap.lua).
function ns.Weekly_TogglePopup()
	if module.active then
		ns.WeeklyPopup_Toggle()
	end
end

function ns.Weekly_Active()
	return module.active
end
