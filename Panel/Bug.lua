local addonName, ns = ...

-- /tomte bug: a report to copy (versions, character level/class/spec, modules, related addons, Tomte's last Lua
-- errors). Read here from the game; the text and the error rules are Core/BugReport.lua. Nothing is sent anywhere.
--
-- Error sources, the first that exists:
--   BugGrabber (BugSack): its read-only BugGrabber:GetDB() list, oldest first, kept across sessions.
--   Otherwise Blizzard's ScriptErrorsFrame.errorData (this session, kept even when the error window is off) plus
--   TomteDB.bugs, which this file fills at logout so a report the day after still has them.
-- Tomte never installs an error handler of its own: seterrorhandler would replace BugGrabber's or Blizzard's (and sit
-- in the path of Blizzard's secure code's errors), and AddLuaErrorHandler is for Blizzard's code only. The bug toast
-- listens where errors land instead (see Bug toast below).

local MAX_SCAN = 200
local GRABBED_SCAN = 10 -- BugGrabber's newest entries searched for the one it just reported
local LUA_ERROR = 0 -- ScriptErrorsFrame's message type for errors (1 is LUA_WARNING)
-- Listed in every report besides each module's uses/conflicts/replaces: the error catchers, TomTom and the TOC's OptionalDeps.
local WATCHED = { "BugSack", "!BugGrabber", "TomTom", "Baganator", "Syndicator", "Auctionator", "TradeSkillMaster",
	"MountJournalEnhanced", "AlmostCompletedAchievements", "WaypointUI", "DialogueUI" }

local function Loaded(name)
	return C_AddOns.IsAddOnLoaded(name) and true or false
end

local function Version(name)
	local v = ns.AddOnMetadata(name, "Version")
	if type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

-- The BugGrabber addon object when it's loaded and has GetDB, else nil.
local function BugGrabberAddon()
	local bg = BugGrabber
	if type(bg) == "table" and type(bg.GetDB) == "function" then
		return bg
	end
	return nil
end

local function FromBugGrabber()
	local bg = BugGrabberAddon()
	local list = {}
	local db = bg and bg:GetDB()
	if type(db) ~= "table" then
		return list
	end
	local session = bg.GetSessionId and bg:GetSessionId()
	for i = #db, math.max(#db - MAX_SCAN + 1, 1), -1 do
		local err = db[i]
		if type(err) == "table" then
			list[#list + 1] = ns.Bug_Normalize(err, session ~= nil and err.session == session)
		end
	end
	return list
end

local function FromBlizzard()
	local list = {}
	local frame = ScriptErrorsFrame
	local data = type(frame) == "table" and frame.errorData
	if type(data) ~= "table" then
		return list
	end
	for i = #data, math.max(#data - MAX_SCAN + 1, 1), -1 do
		if type(data[i]) == "table" then
			list[#list + 1] = ns.Bug_Normalize(data[i], true)
		end
	end
	return list
end

local function FromSaved()
	local list = {}
	for _, e in ipairs(type(ns.db.bugs) == "table" and ns.db.bugs or {}) do
		list[#list + 1] = ns.Bug_Normalize(e, false)
	end
	return list
end

-- Returns errors, total, catcher text (which error list was read).
local function Errors()
	local lists, catcher
	if BugGrabberAddon() then
		lists = { FromBugGrabber() }
		local version = Version("!BugGrabber") or "?"
		catcher = Loaded("BugSack") and ("BugSack (BugGrabber %s)"):format(version) or ("BugGrabber " .. version)
	else
		lists = { FromBlizzard(), FromSaved() }
		catcher = "Blizzard's error list (this session) + Tomte's saved list"
	end
	local errors, total = ns.Bug_Collect(lists, ns.BUG_FILES, ns.BUG_MAX_SHOWN)
	for _, e in ipairs(errors) do
		if not e.when and type(e.time) == "number" then
			e.when = date("%Y-%m-%d %H:%M", e.time)
		end
		if e.current and e.when then
			e.when = e.when .. ", this session"
		elseif e.current then
			e.when = "this session"
		end
	end
	return errors, total, catcher
end

-- fn() fills info; a failure becomes "(could not read: ...)" in the fields it names.
local function Part(info, fields, fn)
	local ok, err = pcall(fn)
	if not ok then
		for _, field in ipairs(fields) do
			info[field] = "(could not read: " .. tostring(err) .. ")"
		end
	end
end

local function Info(full)
	local info = { full = full }
	Part(info, {}, function()
		local version, build, _, interface = GetBuildInfo()
		info.version, info.build, info.interface = ns.VERSION, build and (version .. "." .. build) or version, interface
		info.locale = GetLocale()
		info.theme = ns.Theme.name
		info.preset = type(ns.db.setup) == "table" and ns.db.setup.preset or "none"
	end)
	Part(info, {}, function()
		local level = UnitLevel("player")
		if not ns.IsSecret(level) then
			info.level = level
		end
		info.class = UnitClass("player")
		info.spec, info.specID = ns.SpecName(), ns.SpecID()
		info.content = ns.ExpansionName(ns.ContentExpansion())
	end)
	Part(info, { "on", "off", "blocked" }, function()
		local on, off, blocked = {}, {}, {}
		for _, module in ipairs(ns.modules) do
			if not module.alwaysOn then
				local list = ns.ModuleEnabled(module) and on or off
				list[#list + 1] = module.key
				local reason = ns.ModuleBlockedReason(module)
				if reason then
					blocked[#blocked + 1] = { module.key, reason }
				end
			end
		end
		info.on, info.off, info.blocked = on, off, blocked
	end)
	local used = {}
	Part(info, { "uses" }, function()
		local names = {}
		local function add(name)
			if type(name) == "string" and not used[name] then
				used[name] = true
				names[#names + 1] = name
			end
		end
		for _, module in ipairs(ns.modules) do
			for _, dep in ipairs(module.uses or {}) do
				add(dep.addon)
			end
			for _, dep in ipairs(module.conflicts or {}) do
				add(dep.addon)
			end
			for _, dep in ipairs(module.replaces or {}) do
				add(dep.addon)
			end
			for _, dep in ipairs(module.alongside or {}) do
				add(dep.addon)
			end
		end
		for _, name in ipairs(WATCHED) do
			add(name)
		end
		table.sort(names, function(a, b)
			return a:lower() < b:lower()
		end)
		local uses = {}
		for _, name in ipairs(names) do
			uses[#uses + 1] = { name, Loaded(name) and (Version(name) or true) or false }
		end
		info.uses = uses
	end)
	Part(info, { "others" }, function()
		local others = {}
		for i = 1, C_AddOns.GetNumAddOns() do
			local name, _, _, _, _, security = C_AddOns.GetAddOnInfo(i)
			if name and name ~= addonName and not used[name] and security == "INSECURE" and C_AddOns.IsAddOnLoaded(i) then
				others[#others + 1] = name
			end
		end
		table.sort(others, function(a, b)
			return a:lower() < b:lower()
		end)
		info.others = others
	end)
	Part(info, { "errors" }, function()
		info.errors, info.total, info.catcher = Errors()
	end)
	if full then
		info.profile = ns.ShareUI_ExportText()
	end
	return info
end

function ns.BugUI_Show(mode)
	local full = mode == "full"
	local ok, text = pcall(function()
		return ns.Bug_ReportText(Info(full))
	end)
	if not ok then
		text = "Tomte bug report\nTomte " .. tostring(ns.VERSION) .. "\n(could not build the report: " .. tostring(text)
			.. ")"
	end
	ns.Dialog_Show({
		title = full and "Tomte bug report (full)" or "Tomte bug report",
		hint = "Ctrl+C, then paste it to Tomte's author or in a GitHub issue (github.com/tomte55/Tomte/issues). "
			.. (full and "This one has error details and your settings: read it before you post it. " or
				"Read it first: ")
			.. "it's sent nowhere by itself.",
		text = text,
		readOnly = true,
		width = 620,
		height = 440,
	})
end

function ns.BugUI_Clear()
	if type(ns.db.bugs) == "table" then
		for i = #ns.db.bugs, 1, -1 do
			ns.db.bugs[i] = nil
		end
	end
	ns.Print("saved errors cleared.")
	if BugGrabberAddon() then
		ns.Print("BugSack keeps its own list: /bugsack reset.")
	end
end

-- Hidden /tomte bug selftest: a real error from this file, to check that the report finds Tomte's errors.
function ns.BugUI_SelfTest()
	ns.Print("raising a test error now. /tomte bug should list it.")
	error("Tomte bug report self-test (not a real error)")
end

-- Bug toast ----------------------------------------------------------------------------------------------------------

-- A toast when one of Tomte's errors happens (the report's rules: Tomte's files in the message or stack, a blocked
-- action, or Blizzard code tainted by Tomte); a click opens the report. Heard from BugGrabber's BugGrabbed event, or
-- without BugGrabber from a hook on Blizzard's error window, which gets every error even while it's hidden. Both run
-- inside the failing call, so the check waits a frame. Throttle rules in Core/BugReport.lua.

local toastState = {}
local latest -- the newest error's message waiting for its toast
local due -- timer for a toast the gap held back
local watching, broken

local function ShowToast()
	due = nil
	local n = ns.Bug_ToastTake(toastState, GetTime())
	if n == 0 or not ns.Window_BugToast() then
		return
	end
	local title, text = ns.Bug_ToastText(n, latest)
	ns.Toast_Show({
		owner = "window", label = "Bug", accent = "danger", icon = ns.ICON, mergeKey = "tomte:bug", holdInCombat = true,
		title = title, text = text,
		onClick = function()
			ns.BugUI_Show()
		end,
	})
end

local function Check(message, stack)
	if not (ns.db and ns.Window_BugToast()) or not ns.Bug_IsTomte(message, stack, ns.BUG_FILES) then
		return
	end
	latest = message
	local what, wait = ns.Bug_ToastNote(toastState, message, GetTime(), ns.BUG_TOAST_GAP)
	if what == "show" then
		ShowToast()
	elseif what == "wait" and not due then
		due = C_Timer.NewTimer(wait, ShowToast)
	end
end

-- An error in the check itself would land here again: it stops the watching instead of looping.
local function Stop(err)
	broken = true
	return ns.errorHandler(err)
end

local function Heard(message, stack)
	if broken or type(message) ~= "string" or ns.IsSecret(message) then
		return -- a secret message can't be matched
	end
	if type(stack) ~= "string" or ns.IsSecret(stack) then
		stack = nil
	end
	C_Timer.After(0, function()
		xpcall(Check, Stop, message, stack)
	end)
end

local function OnGrabbed(_, tableID)
	local db = BugGrabber:GetDB()
	if type(db) ~= "table" then
		return
	end
	for i = #db, math.max(#db - GRABBED_SCAN + 1, 1), -1 do
		local err = db[i]
		if type(err) == "table" and tostring(err) == tableID then
			Heard(err.message, err.stack)
			return
		end
	end
end

local function OnBlizzardError(_, message, messageType, stack)
	if messageType == LUA_ERROR then
		Heard(message, stack)
	end
end

-- Once, at file load (BugGrabber, "!BugGrabber", loads before Tomte) or at login if the error window wasn't there yet.
local function Watch()
	if watching then
		return
	end
	if BugGrabberAddon() then
		EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", OnGrabbed, toastState)
		watching = true
	elseif type(ScriptErrorsFrame) == "table" and type(ScriptErrorsFrame.DisplayMessageInternal) == "function" then
		hooksecurefunc(ScriptErrorsFrame, "DisplayMessageInternal", OnBlizzardError)
		watching = true
	end
end

Watch()

-- Taint watch --------------------------------------------------------------------------------------------------------

-- Hidden /tomte bug taint: watches Blizzard fields that, once written from a path Tomte's code tainted, get Blizzard's
-- own code blocked later (the map's zone: Button:SetPassThroughButtons when its quest pins refresh in combat). Right
-- after Blizzard writes one, a hook asks issecurevariable; the first time per session that it's tainted, the call path
-- that wrote it is kept, so the cause can be read instead of guessed. Off until turned on; saved on, so it also
-- catches what happens right after a reload. Hooks run after Blizzard's call and only read.
local TAINT_KEEP = 5 -- catches kept, newest first
local TAINT_STACK = 60 -- lines of call path per catch

local TAINT_WATCHES = {
	{
		name = "WorldMapFrame.mapID",
		owner = function()
			return WorldMapFrame
		end,
		field = "mapID",
		hook = function(fn)
			if WorldMapFrame and WorldMapFrame.SetMapID then
				hooksecurefunc(WorldMapFrame, "SetMapID", fn)
				return true
			end
		end,
	},
	{
		name = "QuestMapFrame.DetailsFrame.questID",
		owner = function()
			return QuestMapFrame and QuestMapFrame.DetailsFrame
		end,
		field = "questID",
		hook = function(fn)
			if QuestMapFrame_ShowQuestDetails then
				hooksecurefunc("QuestMapFrame_ShowQuestDetails", fn)
				return true
			end
		end,
	},
}

local taintHooked = {} -- [watch name] = true once its hook is in
local taintCaught = {} -- [watch name] = true once caught this session

local function TaintDB()
	if type(ns.db.taintWatch) ~= "table" then
		ns.db.taintWatch = {}
	end
	local t = ns.db.taintWatch
	if type(t.seen) ~= "table" then
		t.seen = {}
	end
	return t
end

local function TaintCheck(watch)
	local t = TaintDB()
	if not t.on or taintCaught[watch.name] then
		return
	end
	local owner = watch.owner()
	if not owner then
		return
	end
	local secure, by = issecurevariable(owner, watch.field)
	if secure then
		return
	end
	taintCaught[watch.name] = true
	-- 3: past this function and the hook's closure, so the path starts at Blizzard's call.
	table.insert(t.seen, 1, { at = time(), what = watch.name, by = tostring(by), stack = debugstack(3, TAINT_STACK, 0) })
	for i = #t.seen, TAINT_KEEP + 1, -1 do
		t.seen[i] = nil
	end
	ns.Print(("%s just became tainted (by %s). /tomte bug taint show has the call path to copy."):format(watch.name,
		tostring(by)))
end

local function TaintHook()
	for _, watch in ipairs(TAINT_WATCHES) do
		if not taintHooked[watch.name] and watch.hook(function()
			TaintCheck(watch)
		end) then
			taintHooked[watch.name] = true
		end
	end
end

local function TaintState()
	local parts = {}
	for _, watch in ipairs(TAINT_WATCHES) do
		local owner = watch.owner()
		local secure, by = true, nil
		if owner then
			secure, by = issecurevariable(owner, watch.field)
		end
		parts[#parts + 1] = ("%s %s"):format(watch.name, secure and "clean" or ("tainted by " .. tostring(by)))
	end
	return table.concat(parts, ", ")
end

-- arg: nil toggles the watch, "show" opens the catches to copy, "clear" forgets them.
function ns.BugUI_Taint(arg)
	local t = TaintDB()
	if arg == "show" then
		if #t.seen == 0 then
			ns.Print("the taint watch hasn't caught anything yet.")
			return
		end
		local lines = {}
		for _, s in ipairs(t.seen) do
			lines[#lines + 1] = ("%s  %s tainted by %s\n%s"):format(date("%Y-%m-%d %H:%M:%S", s.at), s.what, s.by,
				s.stack)
		end
		ns.Dialog_Show({
			title = "Tomte taint watch",
			hint = "Ctrl+C, then paste it to Tomte's author.",
			text = table.concat(lines, "\n"),
			readOnly = true,
			width = 620,
			height = 440,
		})
	elseif arg == "clear" then
		t.seen = {}
		ns.Print("taint watch catches cleared.")
	else
		t.on = not t.on
		if t.on then
			TaintHook()
		end
		ns.Print(("taint watch %s. Now: %s."):format(t.on and "on (stays on across reloads)" or "off", TaintState()))
	end
end

-- Logout (also /reload): without BugGrabber, keep Tomte's errors of this session for a report later.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_LOGIN")

function events:PLAYER_LOGIN()
	Watch()
	if ns.db and type(ns.db.taintWatch) == "table" and ns.db.taintWatch.on then
		TaintHook()
	end
end

function events:PLAYER_LOGOUT()
	if not ns.db or BugGrabberAddon() then
		return
	end
	pcall(function()
		local mine = {}
		for _, e in ipairs(FromBlizzard()) do
			if ns.Bug_IsTomte(e.message, e.stack, ns.BUG_FILES) then
				mine[#mine + 1] = e
			end
		end
		if #mine > 0 then
			if type(ns.db.bugs) ~= "table" then
				ns.db.bugs = {}
			end
			ns.Bug_Remember(ns.db.bugs, mine, ns.VERSION, time(), ns.BUG_MAX_SAVED)
		end
	end)
end
