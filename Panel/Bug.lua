local addonName, ns = ...

-- /tomte bug: a report to copy (versions, character level/class/spec, modules, related addons, Tomte's last Lua
-- errors). Read here from the game; the text and the error rules are Core/BugReport.lua. Nothing is sent anywhere.
--
-- Error sources, the first that exists:
--   BugGrabber (BugSack): its read-only BugGrabber:GetDB() list, oldest first, kept across sessions.
--   Otherwise Blizzard's ScriptErrorsFrame.errorData (this session, kept even when the error window is off) plus
--   TomteDB.bugs, which this file fills at logout so a report the day after still has them.
-- Tomte never installs an error handler of its own (it would sit in the path of Blizzard's secure code's errors).

local MAX_SCAN = 200
-- Listed in every report besides each module's uses/conflicts: the error catchers, TomTom and the TOC's OptionalDeps.
local WATCHED = { "BugSack", "!BugGrabber", "TomTom", "Baganator", "Syndicator", "Auctionator", "TradeSkillMaster",
	"MountJournalEnhanced", "AlmostCompletedAchievements", "WaypointUI", "DialogueUI" }

local function Loaded(name)
	return C_AddOns.IsAddOnLoaded(name) and true or false
end

local function Version(name)
	local v = C_AddOns.GetAddOnMetadata(name, "Version")
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
		if not (issecretvalue and issecretvalue(level)) then
			info.level = level
		end
		info.class = UnitClass("player")
		local index = C_SpecializationInfo.GetSpecialization()
		if index then
			local specID, name = C_SpecializationInfo.GetSpecializationInfo(index)
			info.spec, info.specID = name, specID
		end
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

-- Logout (also /reload): without BugGrabber, keep Tomte's errors of this session for a report later.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
events:RegisterEvent("PLAYER_LOGOUT")

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
