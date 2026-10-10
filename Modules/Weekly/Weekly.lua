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

-- nil when this character isn't tracked (below its content's max level) or its snapshot is from an earlier
-- expansion: the old snapshot would show as if it were this week's.
function ns.Weekly_CurrentView()
	local snap = db and db.chars[UnitGUID("player")]
	if not (snap and ns.ContentAtMax() and ns.Weekly_SnapExpansion(snap) == ns.ContentExpansion()) then
		return nil
	end
	return ns.Weekly_View(snap, GetServerTime())
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
				ns.Panel_OpenPage("weekly")
				ns.WeeklyBoard_Refresh()
			end,
		})
	end
	local nextFull = ns.Weekly_NextConcFull(chars, now)
	if nextFull then
		toastTimer = C_Timer.NewTimer(math.min(nextFull - now + 5, MAX_TIMER), CheckToasts)
	end
end

-- Next up sources -----------------------------------------------------------------------------------------------

local function OpenBoard(view)
	return function()
		if view then
			ns.weeklyDB.view = view
		end
		ns.Panel_OpenPage("weekly")
		if ns.WeeklyBoard_Refresh then
			ns.WeeklyBoard_Refresh()
		end
	end
end

local function NextVaultReady()
	local v = ns.Weekly_CurrentView()
	if not (v and v.vaultReady) then
		return {}
	end
	return { { key = "weekly:vault", text = "Great Vault rewards waiting", why = "Pick your reward before you queue.",
		icon = "Interface\\Icons\\INV_Misc_Treasurechest02b", onClick = OpenBoard(), stay = true,
		hint = "Click for the Weekly board" } }
end

-- Full Concentration on any tracked character; the one you're playing first.
local function NextConcentration(now)
	local list = {}
	local me = UnitGUID("player")
	for guid, snap in pairs(Tracked()) do
		for skillLine, prof in pairs(snap.profs or {}) do
			local qty = ns.Weekly_ConcNow(prof.conc, now)
			if qty and prof.conc.max and qty >= prof.conc.max then
				local mine = guid == me
				list[#list + 1] = {
					key = ("weekly:conc:%s:%s"):format(guid, skillLine),
					text = mine and ("Use your %s Concentration"):format(prof.name or "profession")
						or ("%s: %s Concentration full"):format(snap.name or "?", prof.name or "profession"),
					why = "It's full, so it isn't recharging.", icon = prof.icon or CONC_ICON,
					bonus = mine and 9 or 0, onClick = OpenBoard("profs"), stay = true,
					hint = "Click for professions on the Weekly board",
				}
			end
		end
	end
	return list
end

-- What one more activity of a vault track is.
local VAULT_ACTIVITY = { raid = "Kill a raid boss", dungeons = "Run a Heroic or Mythic dungeon", world = "Do a delve or world activity" }

-- A vault track one activity from its next slot.
local function NextVaultSlot()
	local v = ns.Weekly_CurrentView()
	if not (v and v.vault) or v.vaultReady then
		return {}
	end
	local list = {}
	for _, track in ipairs(ns.WEEKLY_TRACKS) do
		local slots = v.vault[track.key] or {}
		local _, nextSlot = ns.Weekly_VaultGoal(slots)
		local s = nextSlot and slots[nextSlot]
		if s and s.threshold - s.progress == 1 then
			list[#list + 1] = {
				key = "weekly:vaultnext:" .. track.key, state = s.progress,
				text = ("%s for vault slot %d"):format(VAULT_ACTIVITY[track.key] or ("One more " .. track.label:lower()),
					nextSlot),
				right = ("%d/%d"):format(s.progress, s.threshold),
				icon = "Interface\\Icons\\INV_Misc_Treasurechest02b", onClick = OpenBoard(), stay = true,
				hint = "Click for the Weekly board",
			}
		end
	end
	return list
end

local function NextKnowledge()
	local v = ns.Weekly_CurrentView()
	if not v then
		return {}
	end
	local list = {}
	for _, k in ipairs(ns.Weekly_OpenKnowledge(v)) do
		list[#list + 1] = {
			key = ("weekly:know:%s:%s"):format(k.skillLine, k.label),
			text = ("%s %s"):format(k.name, k.label:lower()), why = k.tip, right = ns.Weekly_Pts(k.pts),
			icon = k.icon or CONC_ICON, bonus = math.min(k.pts, 9),
			onClick = function()
				ns.Weekly_SetWaypoint(k.loc)
			end, hint = "Click for a waypoint",
		}
	end
	return list
end

-- Rail pill: Great Vault rewards waiting here (1) plus every tracked character with a full Concentration.
local function Pill()
	local v = ns.Weekly_CurrentView()
	local n = v and v.vaultReady and 1 or 0
	local now = GetServerTime()
	for _, snap in pairs(Tracked()) do
		for _, prof in pairs(snap.profs or {}) do
			local qty = ns.Weekly_ConcNow(prof.conc, now)
			if qty and prof.conc.max and qty >= prof.conc.max then
				n = n + 1
				break
			end
		end
	end
	return n
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

-- The same forget as Alts (Alts.lua): the character goes from every module, not just the board.
local function Forget(name)
	ns.Alts_ForgetByName(name, "weekly")
end

-- Prints every hard-coded ID with what the game says about it, to check the third-party data in game.
local function PrintIDs()
	local expansion = ns.ContentExpansion()
	for _, set in ipairs(ns.Content_Get(expansion, "crests") or {}) do
		ns.Print(set.label .. ":")
		for _, id in ipairs(set.ids) do
			local info = C_CurrencyInfo.GetCurrencyInfo(id)
			if info and info.name and info.name ~= "" then
				print(("  %d  %s  qty %s, max %s, weekly max %s, season total %s, useTotal %s"):format(id, info.name,
					tostring(info.quantity), tostring(info.maxQuantity), tostring(info.maxWeeklyQuantity),
					tostring(info.totalEarned), tostring(info.useTotalEarnedForMaxQty)))
			else
				print(("  %d  |cffff6060unknown|r"):format(id))
			end
		end
	end
	ns.Print(("content expansion %s, profession data for %s"):format(ns.ExpansionName(expansion),
		ns.Content_Get(expansion, "profs") and ns.ExpansionName(expansion) or "none"))
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

-- /tomte data checks (Core/Content.lua): does this expansion's Weekly data resolve in game?
local function CurrencyName(id)
	local info = C_CurrencyInfo.GetCurrencyInfo(id)
	return info and info.name ~= nil and info.name ~= "" and info.name or nil, info
end

local function Missing(key, expansion)
	return { ("!no %s data for %s"):format(key, ns.ExpansionName(expansion)) }
end

ns.Content_AddCheck("crests", function(expansion)
	local sets = ns.Content_Get(expansion, "crests")
	if not sets then
		return Missing("crest", expansion)
	end
	local picked, lines = ns.WeeklyCollect_CrestSet(expansion), {}
	for _, set in ipairs(sets) do
		local names, bad = {}, false
		for _, id in ipairs(set.ids) do
			local name, info = CurrencyName(id)
			names[#names + 1] = name and ("%s %d"):format(name, info.quantity or 0) or (id .. " unknown")
			bad = bad or not name
		end
		lines[#lines + 1] = ("%s%s%s: %s"):format(bad and "!" or "", set.label, set == picked and " (shown)" or "",
			table.concat(names, ", "))
	end
	return lines
end)

ns.Content_AddCheck("resources", function(expansion)
	local ids = ns.Content_Get(expansion, "resources")
	if not ids then
		return Missing("resources", expansion)
	end
	local n, bad = 0, {}
	for _, id in ipairs(ids) do
		if CurrencyName(id) then
			n = n + 1
		else
			bad[#bad + 1] = tostring(id)
		end
	end
	local lines = { ("%d of %d currencies known"):format(n, #ids) }
	if #bad > 0 then
		lines[2] = "!unknown: " .. table.concat(bad, ", ")
	end
	return lines
end)

ns.Content_AddCheck("raids", function(expansion)
	local list, source = ns.WeeklyRaids_Read(expansion)
	if #list == 0 then
		return { ("!none (from the %s)"):format(source == "journal" and "journal" or "table") }
	end
	local names = {}
	for _, raid in ipairs(list) do
		names[#names + 1] = ("%s (%d bosses)"):format(raid.name, #raid.bosses)
	end
	return { ("from the %s: %s"):format(source == "journal" and "Encounter Journal" or "hand-kept table",
		table.concat(names, ", ")) }
end)

ns.Content_AddCheck("activities", function(expansion)
	local groups = ns.Content_Get(expansion, "activities")
	if not groups then
		return Missing("activities", expansion)
	end
	local quests, lines, untitled = 0, 0, {}
	for _, g in ipairs(groups) do
		for _, e in ipairs(g.entries) do
			if e.questLine then
				lines = lines + 1
			end
			for _, id in ipairs(e.flags or { e.quest }) do
				quests = quests + 1
				if e.quest and not C_QuestLog.GetTitleForQuestID(id) then
					untitled[#untitled + 1] = tostring(id)
				end
			end
		end
	end
	local out = { ("%d groups, %d quest IDs, %d quest lines"):format(#groups, quests, lines) }
	if #untitled > 0 then
		out[2] = "no title cached (fine if never seen): " .. table.concat(untitled, ", ")
	end
	return out
end)

ns.Content_AddCheck("factions", function(expansion)
	local renown = C_MajorFactions.GetMajorFactionIDs(expansion) or {}
	local subs, n, bad = ns.Content_Get(expansion, "subfactions") or {}, 0, {}
	for _, list in pairs(subs) do
		for _, sub in ipairs(list) do
			local data = C_Reputation.GetFactionDataByID(sub.id)
			if data and data.name and data.name ~= "" then
				n = n + 1
			else
				bad[#bad + 1] = tostring(sub.id)
			end
		end
	end
	local lines = { ("%d renown factions, %d sub-factions known"):format(#renown, n) }
	if #bad > 0 then
		lines[2] = "!unknown sub-factions: " .. table.concat(bad, ", ")
	end
	return lines
end)

ns.Content_AddCheck("profs", function(expansion)
	if not ns.Content_Get(expansion, "profs") then
		return Missing("profession", expansion)
	end
	local lines = {}
	local first, second = GetProfessions()
	for _, index in pairs({ first, second }) do
		local name, _, _, _, _, _, base = GetProfessionInfo(index)
		local def = base and ns.Weekly_ProfDef(expansion, base)
		lines[#lines + 1] = def and ("%s: skill line %d, %d knowledge quests"):format(name or "?", def.child,
			#ns.Weekly_ProfQuestIDs(def)) or ("!%s: not in the table"):format(name or "?")
	end
	if #lines == 0 then
		lines[1] = "no professions"
	end
	return lines
end)

module = ns.RegisterModule({
	key = "weekly",
	name = "Weekly board",
	category = "General",
	description = "What you haven't done this week and where the expansion stands: Great Vault, crests, weekly quests, profession knowledge and Concentration, lockouts, renown factions with their reward tracks, weekly activities and raid kills, for every max-level character (alts roll over at the weekly reset without logging in). Right-click the minimap button for a quick list.",
	enabledByDefault = true,
	defaults = {
		chars = {}, -- [guid] = snapshot (Collect.lua)
		quests = {}, -- [questID] = { title, firstSeen }, learned weekly quests
		hidden = {}, -- [guid] = true
		view = "week",
		popup = {},
		toast = true,
		learned = true,
		hideCompleted = true, -- Activities tab
		raidCollapsed = {}, -- Raids tab: [journalInstanceID] = true
		-- faction: the Factions tab's selected faction ID (nil = the first one)
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
	home = {
		ns.WeeklyHomeSection,
		{ kind = "next", key = "nextvault", name = "Great Vault rewards waiting", score = 100, candidates = NextVaultReady,
			description = "Your Great Vault has rewards to pick." },
		{ kind = "next", key = "nextconc", name = "Concentration full", score = 85, candidates = NextConcentration,
			description = "A tracked character's Concentration is full (yours first)." },
		{ kind = "next", key = "nextvaultslot", name = "Vault slot one activity away", score = 70, candidates = NextVaultSlot,
			description = "One more raid boss, dungeon or world activity unlocks the next vault slot." },
		{ kind = "next", key = "nextknowledge", name = "Knowledge sources", score = 50, candidates = NextKnowledge,
			description = "Profession knowledge sources still open this week that have a place to go (click for a waypoint)." },
		{ kind = "page", key = "weekly", order = 2, name = "Weekly board", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
			page = ns.WeeklyBoardPage,
			summary = function()
				local v = ns.Weekly_CurrentView()
				return v and ns.Weekly_HomeSummary(v) or "Max-level characters only"
			end,
			pill = Pill,
			pillTip = "Great Vault rewards waiting and characters with full Concentration" },
	},
	options = {},
	commands = {
		{ "popup", "toggle the weekly popup", ns.WeeklyPopup_Toggle },
		{ "board", "open the weekly board", function()
			ns.Panel_OpenPage("weekly")
		end },
		{ "quests", "list the learned weekly quests", ListQuests },
		{ "forget", "forget a character everywhere: /tomte weekly forget <name>[-<realm>]", Forget },
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
