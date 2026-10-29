local addonName, ns = ...

-- Performance module: is Tomte fast? Turns Tomte's own measuring on (Core/Perf.lua: every module's events and
-- scripts, timed per file and event), a page with that next to the game's addon profiler, a chat line when one
-- Tomte call makes the game hitch, an on-screen readout and a copy-paste report. Rules in Data.lua, the game's
-- numbers in Read.lua, the page in Page.lua, the readout in Overlay.lua.

local ICON = 134377 -- inv_misc_pocketwatch_02 (Weekly has _01)
local WARN_GAP = 60 -- seconds between two warnings about the same module and event
local REPORT_PARTS = 5 -- files and events per module in the report

local module, db
local warned = {} -- [group .. sub .. what] = GetTime() of the last warning

function ns.Perf_SortKey()
	return db.sort
end

function ns.Perf_SetSortKey(value)
	db.sort = value
end

local function OnHitch(group, sub, what, ms)
	if not db.warn or ms < db.warnMs then
		return
	end
	if ns.Perf_ShouldWarn(warned, group .. "\0" .. tostring(sub) .. "\0" .. tostring(what), GetTime(), WARN_GAP) then
		ns.Print(ns.Perf_WarnText(group, sub, what, ms))
	end
end

local function Names()
	local names = {}
	for _, m in ipairs(ns.modules) do
		names[m.key] = m.name or m.key
	end
	return names
end

local function Report()
	local game = ns.PerfRead_Game(true, true)
	local stats = ns.Perf_Stats()
	local since, fromLoad, loadedAt = ns.Perf_Since()
	local now = GetTime()
	local rows = ns.Perf_ModuleRows(stats, ns.PerfPage_Rates(), "total")
	local parts = {}
	for _, row in ipairs(rows) do
		parts[row.group] = ns.Perf_TopParts(stats[row.group], REPORT_PARTS)
	end
	local startup, startupTotal = ns.Perf_StartupRows(ns.Perf_StartupTimes())
	local login, loginTotal = ns.Perf_LoginRows(stats)
	local t = game.tomte
	return ns.Perf_Report({
		version = C_AddOns.GetAddOnMetadata(addonName, "Version"),
		elapsed = now - loadedAt,
		now = now,
		fps = game.fps,
		home = game.home,
		world = game.world,
		tomte = {
			recent = ns.Perf_Percent(game.app.recent, game.overall.recent, t.recent),
			session = ns.Perf_Percent(game.app.session, game.overall.session, t.session),
			peak = t.peak,
			mem = t.mem,
			over = t.over,
		},
		coverage = since and fromLoad and ns.Perf_Coverage(ns.Perf_MeasuredTotal(stats), t.session, game.app.session,
			(now - loadedAt) * 1000) or nil,
		rows = rows,
		parts = parts,
		hitches = ns.Perf_Hitches(),
		startup = startup,
		startupTotal = startupTotal,
		login = login,
		loginTotal = loginTotal,
		loginSeconds = ns.PERF_LOGIN_SECONDS,
		addons = ns.Perf_AddonRows(game, game.addons),
		names = Names(),
	})
end

function ns.Perf_ShowReport()
	ns.Dialog_Show({
		title = "Performance report",
		hint = "Ctrl+C to copy, for a bug report.",
		text = Report(),
		readOnly = true,
		width = 560,
		height = 420,
	})
end

-- /tomte perf show: the top modules and the last hitches in chat.
local function Show()
	local game = ns.PerfRead_Game(false)
	local t = game.tomte
	ns.Print(("now %s of the frame, session %s, longest frame %s."):format(
		ns.Perf_PercentText(ns.Perf_Percent(game.app.recent, game.overall.recent, t.recent)),
		ns.Perf_PercentText(ns.Perf_Percent(game.app.session, game.overall.session, t.session)),
		ns.Perf_MsText(t.peak)))
	local rows = ns.Perf_ModuleRows(ns.Perf_Stats(), nil, "total")
	for i = 1, math.min(#rows, 5) do
		local row = rows[i]
		print(("  %s: %s in %s calls, longest %s%s"):format(row.name, ns.Perf_MsText(row.total),
			ns.Thousands(row.calls), ns.Perf_MsText(row.peak), row.peakWhat
				and (" (" .. ns.Perf_PartText(row.group, row.peakSub, row.peakWhat) .. ")") or ""))
	end
	local hitches = ns.Perf_Hitches()
	local now = GetTime()
	for i = 1, math.min(#hitches, 3) do
		local h = hitches[i]
		print(("  hitch %s ago: %s · %s, %s"):format(ns.Perf_DurationText(now - h.at), ns.Perf_GroupName(h.group),
			ns.Perf_PartText(h.group, h.sub, h.what), ns.Perf_MsText(h.ms)))
	end
	print("  /tomte perf open for the page, /tomte perf report to copy it all.")
end

local function Reset()
	ns.Perf_Reset()
	wipe(warned)
	ns.PerfPage_StartOver()
end
ns.Perf_StartOver = Reset

local function ApplyReadout()
	ns.PerfReadout_Set(db, module.active and db.readout.shown == true)
end

module = ns.RegisterModule({
	key = "perf",
	name = "Performance",
	category = "tomte",
	icon = ICON,
	summary = "How much of the frame Tomte takes, which module and which event, and every addon next to it.",
	description = "Times Tomte's own code per module, file and event, next to the game's addon profiler. The "
		.. "Performance page shows how much of each frame Tomte takes, its busiest modules (hover one to see where "
		.. "the time goes), the calls that made the game hitch, what each module costs while logging in, and every "
		.. "loaded addon's CPU and memory. Copy report gives it all as text for a bug report. Measuring costs "
		.. "almost nothing, but it's off until you turn this on.",
	enabledByDefault = false,
	defaults = {
		sort = "total", -- the module table's order: "now", "total" or "peak"
		warn = false,
		warnMs = 50,
		readout = { shown = false, point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -220, y = -8 },
	},
	init = function(moduleDB)
		db = moduleDB
		db.sort = ns.ChoiceOrDefault(db.sort, ns.PERF_SORTS, "total")
		ns.Perf_SetHitchHook(OnHitch)
	end,
	toggle = function(active)
		ns.Perf_SetOn(active)
		if not active then
			wipe(warned)
		end
		ApplyReadout()
	end,
	home = {
		{ kind = "page", key = "performance", order = 95, name = "Performance", icon = ICON, page = ns.PerfPage,
			summary = function()
				local game = ns.PerfRead_Game(false)
				return ("Tomte takes %s of the frame."):format(ns.Perf_PercentText(ns.Perf_Percent(game.app.recent,
					game.overall.recent, game.tomte.recent)))
			end },
	},
	options = {
		{ type = "header", label = "Performance" },
		{ type = "button", label = "Page", text = "Open", onClick = function()
			ns.Panel_OpenPage("performance")
		end, tooltip = "Tomte's modules, hitches, startup and every addon." },
		{ type = "button", label = "Numbers", text = "Start over", onClick = Reset,
			tooltip = "Clears Tomte's numbers and measures from now, to see what one thing costs." },
		{ type = "header", label = "Warnings" },
		{ type = "checkbox", key = "warn", label = "Tell me when Tomte makes the game hitch",
			tooltip = "A line in chat when one Tomte call runs longer than the time below, naming the module and event. At most once a minute for the same one." },
		{ type = "slider", key = "warnMs", label = "Longer than", min = 20, max = 200, step = 10, parent = "warn",
			format = function(v)
				return ("%d ms"):format(v)
			end },
		{ type = "header", label = "Readout" },
		{ type = "checkbox", key = "readout.shown", label = "Show a readout on screen", onChange = ApplyReadout,
			tooltip = "Frame rate, latency and Tomte's share of the frame in a small line. Move it in Edit Mode." },
		{ type = "button", label = "Position", text = "Reset", onClick = ns.PerfReadout_Reset, parent = "readout.shown" },
	},
	commands = {
		{ "show", "Tomte's busiest modules and last hitches", Show },
		{ "report", "a text report to copy", function()
			ns.Perf_ShowReport()
		end },
		{ "reset", "start measuring over from now", Reset },
		{ "open", "open the Performance page", function()
			ns.Panel_OpenPage("performance")
		end },
	},
})
