local addonName, ns = ...

-- Gathering sessions module: tracks gathering runs (mining, herbalism, skinning, fishing): nodes, items with their
-- ranks, value and gold per hour, rare finds, skill and knowledge, zones. A small tracker while a run is on, an
-- end-of-run toast and a Gathering page. Detection is Detect.lua, pure logic Data.lua. It only reads and counts.

local IDLE_DEFAULT = 600 -- seconds without a gather that end a run (the "End a run after" slider's default)
local MIN_NODES_DEFAULT = 5 -- automatic runs with fewer nodes aren't kept
local IDLE_CHECK = 15

local module, db
local ticker

local events = ns.Gather_Events

local Money = ns.Gold
ns.Gather_Money = Money

local function Duration(seconds)
	return ns.Recap_Duration and ns.Recap_Duration(seconds) or (math.floor(seconds / 60) .. "m")
end
ns.Gather_DurationText = Duration

function ns.Gather_Current()
	return module and module.active and db and db.run or nil
end

function ns.Gather_Open()
	ns.Panel_OpenPage("gather")
end

local function Refresh()
	if ns.GatherTracker_Refresh then
		ns.GatherTracker_Refresh()
	end
	if ns.GatherPage_Refresh then
		ns.GatherPage_Refresh()
	end
end

-- The play session the run belongs to, or nil once another one started (a later login).
local function RunSession(run)
	local session = ns.Session_Current and ns.Session_Current()
	if session and run and session.guid == run.guid and session.start == run.session then
		return session
	end
	return nil
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function StartTicker()
	if ticker then
		return
	end
	ticker = C_Timer.NewTicker(IDLE_CHECK, function()
		local run = db.run
		if not run then
			StopTicker()
		elseif ns.Gather_Idle(run, GetServerTime(), db.idle) then
			ns.Gather_End("idle")
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- Start and end

function ns.Gather_Start(manual)
	if not (module and module.active) then
		return nil
	end
	if db.run then
		if manual then
			db.run.manual = true
			ns.Print("a gathering run is already on; it's kept even when it stays short.")
		end
		return db.run
	end
	local _, class = UnitClass("player")
	local run = ns.Gather_NewRun(UnitGUID("player"), GetServerTime(), { name = UnitName("player"), class = class,
		manual = manual })
	local session = ns.Session_Current and ns.Session_Current()
	run.session = session and session.start
	db.run = run
	ns.GatherDetect_ReadProgress() -- skill and knowledge baselines
	StartTicker()
	Refresh()
	return run
end

local function EndText(n)
	local parts = { Duration(n.duration), ("%d %s"):format(n.nodes, n.nodes == 1 and "node" or "nodes") }
	if n.value then
		parts[#parts + 1] = ("%s (%s/h)"):format(Money(n.value), Money(n.valuePerHour))
	end
	return table.concat(parts, " · ")
end

-- reason: "idle" | "manual" | "switch" (another character, or a run left over from an earlier login).
function ns.Gather_End(reason)
	local run = db and db.run
	if not run then
		if reason == "manual" then
			ns.Print("no gathering run is on.")
		end
		return
	end
	db.run = nil
	StopTicker()
	local kept = ns.Gather_Keep(run, db.minNodes)
	if kept then
		ns.Gather_Archive(db.runs, ns.Gather_Compact(run), db.keepCount)
		local session = RunSession(run)
		if session then
			ns.Gather_SessionAdd(session, 0, 0, 1)
		end
		if db.toastEnd and reason ~= "switch" and ns.Toast_Show then
			local n = ns.Gather_Numbers(run)
			ns.Toast_Show({
				owner = "gather", label = "Run done", accent = "accent", title = ns.Gather_RunTitle(n.mainKind, n.kinds),
				text = EndText(n), icon = ns.Gather_RunIcon(n), hold = 8,
				onClick = ns.Gather_Open,
			})
		end
	elseif reason == "manual" then
		ns.Print(("run ended; it isn't kept (%d of %d nodes)."):format(run.nodes, db.minNodes))
	end
	Refresh()
end

local function Resume()
	local guid = UnitGUID("player")
	if not guid then
		return
	end
	local what = ns.Gather_Resume(db.run, guid, GetServerTime(), db.idle)
	if what == "finish" then
		-- Another character's run, or one that timed out while logged out: it ends at its last gather.
		local same = db.run.guid == guid and RunSession(db.run)
		ns.Gather_End(same and "idle" or "switch")
	elseif what == "continue" then
		-- A relog within the idle timeout starts a new play session: the rest of the run counts in that one.
		local session = ns.Session_Current and ns.Session_Current()
		if session and session.guid == guid then
			db.run.session = session.start
		end
		StartTicker()
		ns.GatherDetect_ReadProgress()
	end
	Refresh()
end

events:On("gather", "PLAYER_ENTERING_WORLD", function()
	Resume()
end)

---------------------------------------------------------------------------------------------------------------
-- What Detect.lua hands over

local function ItemName(link, itemID)
	local name = link and C_Item.GetItemInfo(link)
	return name or link or ("item " .. tostring(itemID))
end

local function ProfName(skillLine)
	for _, p in ipairs(ns.GatherDetect_Profs()) do
		if p.base == skillLine then
			return p.name, p.icon
		end
	end
	return nil
end

local function ToastFind(f)
	if not (db.toastFind and ns.Toast_Show) then
		return
	end
	if f.kind == "item" then
		ns.Toast_Show({
			owner = "gather", label = "Rare find", accent = "accent", title = ItemName(f.link, f.itemID),
			icon = f.itemID and C_Item.GetItemIconByID(f.itemID) or nil, hold = 6, onClick = ns.Gather_Open,
		})
	else
		local name, icon = ProfName(f.skillLine)
		ns.Toast_Show({
			owner = "gather", label = "Rare find", accent = "accent", title = "Knowledge drop",
			text = ("%s: %d of %d this week"):format(name or "Profession", f.done or 0, f.total or 0),
			icon = icon or ns.GATHER_KIND_ICONS.mining, hold = 6, onClick = ns.Gather_Open,
		})
	end
end

local function MapSize(mapID)
	return C_Map.GetMapWorldSize(mapID)
end

-- A mining or herbalism node's spot, with or without a run going.
local function RecordNode(g)
	if not (db.recordNodes and g.mapID and g.x) then
		return
	end
	local info = { name = g.nodeName, item = g.item }
	if ns.GatherNodes_Add(db, g.mapID, g.x, g.y, g.kind, g.objectID, MapSize, info) then
		ns.Share_Changed("nodes")
		ns.GatherPins_Refresh()
	end
end

local handlers = {
	gather = function(g)
		RecordNode(g)
		local run = db.run
		if not run then
			if not db.auto then
				return
			end
			run = ns.Gather_Start(false)
			if not run then
				return
			end
		end
		local before = run.nodes
		ns.Gather_AddGather(run, g)
		local session = RunSession(run)
		if session then
			ns.Gather_SessionAdd(session, run.nodes - before, 0)
		end
		StartTicker()
		Refresh()
	end,
	item = function(it)
		local run = db.run
		if not run then
			return
		end
		ns.Gather_AddItem(run, it)
		local session = RunSession(run)
		if session and it.unit then
			ns.Gather_SessionAdd(session, 0, it.unit * (it.count or 1))
		end
		Refresh()
	end,
	find = function(f)
		local run = db.run
		if not run then
			return
		end
		ns.Gather_AddFind(run, f)
		ToastFind(f)
		Refresh()
	end,
	skill = function(line, level)
		if db.run then
			ns.Gather_Skill(db.run, line, level)
		end
	end,
	knowledge = function(line, available)
		if db.run then
			ns.Gather_Knowledge(db.run, line, available)
		end
	end,
	running = function()
		return db.run ~= nil
	end,
}

-- The recap card's gathering line for a session (the Session recap calls this), nil when there's nothing.
function ns.Gather_SessionText(session)
	if not (module and module.active and session) then
		return nil
	end
	return ns.Gather_SessionLine(session.gather, Money)
end

---------------------------------------------------------------------------------------------------------------
-- Home and Next up

local function LastRunLine()
	local run = db.run
	if run then
		local n = ns.Gather_Numbers(run, GetServerTime(), true)
		return ("%s on: %d nodes, %s"):format(ns.Gather_RunTitle(n.mainKind, n.kinds), n.nodes, Duration(n.duration))
	end
	local last = db.runs[1]
	if not last then
		return "No runs yet"
	end
	local n = ns.Gather_Numbers(last)
	local kind = #n.kinds > 0 and ns.Gather_KindsText(n.kinds) or "Gathering"
	if n.valuePerHour then
		return ("Last run: %s, %s, %s/h"):format(kind, Duration(n.duration), Money(n.valuePerHour))
	end
	return ("Last run: %s, %s, %d nodes/h"):format(kind, Duration(n.duration), n.nodesPerHour)
end

local function NextDrops()
	if not ns.ContentAtMax() then
		return {}
	end
	local list = {}
	for _, p in ipairs(ns.GatherDetect_Profs()) do
		local done, total = ns.GatherDetect_Drops(p)
		if done and done < total then
			local left = total - done
			list[#list + 1] = {
				key = "gather:drops:" .. p.base, state = done,
				text = ("%s: %d knowledge %s left this week"):format(p.name or ns.GATHER_KIND_NAMES[p.kind], left,
					left == 1 and "drop" or "drops"),
				why = p.def and p.def.from and ("They drop while " .. p.def.from .. ".") or nil,
				icon = p.icon or ns.GATHER_KIND_ICONS[p.kind], bonus = math.min(left, 9),
				onClick = ns.Gather_Open, hint = "Click for the Gathering page",
			}
		end
	end
	return list
end

---------------------------------------------------------------------------------------------------------------
-- Module

local function Why()
	for _, line in ipairs(ns.GatherDetect_Why()) do
		ns.Print(line)
	end
end

local function CountText(counts)
	local parts = {}
	for _, kind in ipairs(ns.GATHER_KINDS) do
		if counts[kind] then
			parts[#parts + 1] = ("%s %s"):format(ns.Thousands(counts[kind]), ns.GATHER_KIND_NAMES[kind]:lower())
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function NodeCount()
	local _, all = ns.GatherNodes_Counts(db)
	local n = 0
	for _, count in pairs(all) do
		n = n + count
	end
	return n
end

local function Nodes()
	local mapID = C_Map.GetBestMapForUnit("player")
	local here, all = ns.GatherNodes_Counts(db, mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	ns.Print(("node spots in %s: %s."):format(info and info.name or "this zone", CountText(here)))
	ns.Print(("node spots everywhere: %s."):format(CountText(all)))
	if not db.recordNodes then
		ns.Print("Remember node spots is off in the Gathering settings.")
	end
end

local function PinsChanged()
	ns.GatherPins_Refresh()
end

module = ns.RegisterModule({
	key = "gather",
	name = "Gathering",
	category = "General",
	description = "Tracks your gathering runs (mining, herbalism, skinning and fishing): nodes per hour, items with their ranks, gold per hour, rare finds, skill and knowledge gained, and zones. A small tracker while you gather, a toast when a run ends and a Gathering page.",
	enabledByDefault = true,
	defaults = {
		auto = true,
		idle = IDLE_DEFAULT,
		minNodes = MIN_NODES_DEFAULT,
		fishing = true,
		tracker = { shown = true, collapsed = false },
		toastEnd = true,
		toastFind = true,
		keepCount = 50,
		runs = {}, -- history, newest first (a collection: "Reset settings" keeps it)
		spells = {}, -- learned spellID -> kind (a collection)
		recordNodes = true,
		mapPins = "mine", -- "mine" (your gathering professions), "all" or "off"
		mapPinsOn = "mine", -- what the map button's right-click turns the pins back on to
		mapButton = true, -- the round button on the world map (MapPins.lua)
		nodes = {}, -- [uiMapID] = { [x * 10000 + y] = objectID or "m"/"h" } (Nodes.lua; a collection)
		nodeTypes = {}, -- [objectID] = { kind, name, item } (a collection)
		pageScope = "all", pageRange = "all", pageKind = "all", pageView = "runs",
	},
	-- Page filters: not in settings strings (Core/Profile.lua). Collections (runs, nodes) never are.
	noShare = { "pageScope", "pageRange", "pageKind", "pageView" },
	init = function(saved)
		db = saved
		if ns.GatherTracker_Init then
			ns.GatherTracker_Init(db)
		end
		if ns.GatherPage_Init then
			ns.GatherPage_Init(db)
		end
		ns.GatherPins_Init(db, module)
		-- Friend sharing (Modules/Share) loads after this file, so it's looked up here, at init.
		ns.Share_Register({
			key = "nodes",
			label = "Gathering nodes",
			count = function(n, adjective)
				return ns.Thousands(n) .. (adjective and (" " .. adjective) or "") .. (n == 1 and " node spot" or " node spots")
			end,
			export = function()
				return ns.GatherNodes_Export(db)
			end,
			revision = function()
				return ns.GatherNodes_Revision(db)
			end,
			import = function(payload)
				local added, why = ns.GatherNodes_Import(db, payload, MapSize)
				if added and added > 0 then
					ns.GatherPins_Refresh()
				end
				return added, why
			end,
			active = function()
				return module.active and db.recordNodes
			end,
		})
	end,
	toggle = function(active)
		if active then
			ns.GatherDetect_Start(db, handlers)
			events:Watch("gather", "PLAYER_ENTERING_WORLD")
			if ns.inWorld then
				Resume()
			end
		else
			ns.GatherDetect_Stop()
			events:UnwatchAll("gather")
			StopTicker()
			ns.GatherPins_Clear()
		end
		ns.GatherPins_Refresh()
		ns.Share_Changed("nodes")
		Refresh()
	end,
	home = {
		{ kind = "page", key = "gather", order = 8, name = "Gathering", icon = ns.GATHER_KIND_ICONS.mining,
			page = ns.GatherPage, summary = LastRunLine },
		{ kind = "next", key = "nextgather", name = "Gathering knowledge drops", score = 35, candidates = NextDrops,
			description = "Weekly knowledge drops your gathering professions can still find." },
	},
	commands = {
		{ "", "open the Gathering page", ns.Gather_Open, hidden = true },
		{ "open", "open the Gathering page", ns.Gather_Open },
		{ "start", "start a gathering run now (kept even when short)", function()
			if ns.Gather_Start(true) then
				ns.Print("gathering run started.")
			end
		end },
		{ "end", "end the gathering run", function()
			ns.Gather_End("manual")
		end },
		{ "why", "what the last loot window counted as, and why", Why },
		{ "nodes", "how many node spots are remembered here and everywhere", Nodes },
	},
	options = {
		{ type = "header", label = "Runs" },
		{ type = "checkbox", key = "auto", label = "Start runs by themselves",
			tooltip = "The first node you gather starts a run. Off: only /tomte gather start does." },
		{ type = "checkbox", key = "fishing", label = "Count fishing",
			tooltip = "Fishing catches count as gathering (a run of only fishing is a Fishing run)." },
		{ type = "slider", key = "idle", label = "End a run after", min = 180, max = 1800, step = 60,
			format = function(v)
				return ("%d min"):format(math.floor(v / 60 + 0.5))
			end, tooltip = "Minutes without a gather. The run ends at its last gather, so the wait doesn't lower the per-hour numbers." },
		{ type = "slider", key = "minNodes", label = "Keep runs from", min = 1, max = 20, step = 1,
			format = function(v)
				return ("%d %s"):format(v, v == 1 and "node" or "nodes")
			end, tooltip = "Automatic runs with fewer nodes aren't kept (their loot still counts in the session). Runs started by hand always are." },
		{ type = "slider", key = "keepCount", label = "Runs kept per character", min = 10, max = 200, step = 10 },

		{ type = "header", label = "Tracker and toasts" },
		{ type = "checkbox", key = "tracker.shown", label = "Show the tracker", onChange = Refresh,
			tooltip = "A small window while a run is on: time, nodes, value, top items, finds, skill. Hidden in instances and pet battles. Move it in Blizzard's Edit Mode (\"Gathering run\")." },
		{ type = "button", label = "Tracker position", text = "Reset", onClick = function()
			ns.GatherTracker_ResetPosition()
		end },
		{ type = "checkbox", key = "toastEnd", label = "Toast when a run ends",
			tooltip = "Time, nodes, value and gold per hour of the run." },
		{ type = "checkbox", key = "toastFind", label = "Toast for rare finds",
			tooltip = "A rare or better item, or a weekly knowledge drop, while gathering." },

		{ type = "header", label = "Nodes" },
		{ type = "checkbox", key = "recordNodes", label = "Remember node spots", onChange = function()
			ns.Share_Changed("nodes")
		end, tooltip = "Where you mined and picked herbs, for the world map. With Friend sharing on, friends who run Tomte get your spots and you get theirs." },
		{ type = "dropdown", key = "mapPins", label = "Show nodes on the world map", onChange = PinsChanged,
			choices = function()
				return { { value = "mine", text = "For your professions" }, { value = "all", text = "All" },
					{ value = "off", text = "Off" } }
			end },
		{ type = "checkbox", key = "mapButton", label = "Button on the world map", onChange = PinsChanged,
			tooltip = "A round button in the world map's top-right corner. Left-click: which nodes to show and more. Right-click: show or hide them." },
		{ type = "button", label = function()
			return ("Node spots: %s"):format(ns.Thousands(db and NodeCount() or 0))
		end, text = "Forget", confirm = "Forget every node spot Tomte remembers (yours and what friends sent)?",
			onClick = function()
				wipe(db.nodes)
				ns.Share_Changed("nodes")
				ns.GatherPins_Refresh()
			end },

		{ type = "header", label = "Data" },
		{ type = "button", label = function()
			return ("Runs kept: %d"):format(db and #db.runs or 0)
		end, text = "Clear", confirm = "Forget every gathering run Tomte kept?", onClick = function()
			wipe(db.runs)
			Refresh()
		end },
	},
})
ns.gatherModule = module
