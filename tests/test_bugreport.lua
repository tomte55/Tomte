-- Run from the AddOns folder: lua Tomte/tests/test_bugreport.lua
local ns = {}
local SECRET = "<<secret>>"
issecretvalue = function(v)
	return v == SECRET
end
assert(loadfile("Tomte/Core/BugFiles.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/BugReport.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

test("BugFiles matches the TOC", function()
	local toc = {}
	for line in io.lines("Tomte/Tomte.toc") do
		local f = line:match("^([%w_/\\]+%.lua)%s*$")
		if f then
			toc[#toc + 1] = f:gsub("\\", "/")
		end
	end
	local hint = " (run: lua Tomte/tools/bugfiles.lua)"
	eq(#ns.BUG_FILES, #toc, "count" .. hint)
	for i, f in ipairs(toc) do
		eq(ns.BUG_FILES[i], f, "file " .. i .. hint)
	end
end)

test("IsTomte: full paths, backslashes and blocked calls", function()
	local F = ns.BUG_FILES
	eq(ns.Bug_IsTomte("Interface/AddOns/Tomte/Core/Core.lua:12: boom", nil, F), true, "full")
	eq(ns.Bug_IsTomte("Interface\\AddOns\\Tomte\\Core\\Core.lua:12: boom", nil, F), true, "backslash")
	eq(ns.Bug_IsTomte("[ADDON_ACTION_BLOCKED] AddOn 'Tomte' tried to call the protected function 'X'.", nil, F),
		true, "blocked")
	eq(ns.Bug_IsTomte("AddOn 'TomteFoo' tried to call", nil, F), false, "blocked, other addon")
end)

test("IsTomte: shortened paths", function()
	local F = ns.BUG_FILES
	eq(ns.Bug_IsTomte("...ules/Achievements/Achievements.lua:12: boom", nil, F), true, "tail of a Tomte file")
	eq(ns.Bug_IsTomte("...ules/SomethingElse/Other.lua:12: boom", nil, F), false, "tail of another file")
	eq(ns.Bug_IsTomte("...ts.lua:1: x", nil, F), false, "tail too short to tell")
	local ok, stackOnly = ns.Bug_IsTomte("x", "[string \"...ules/Achievements/Achievements.lua\"]:5: in function", F)
	eq(ok, true, "shortened in the stack")
	eq(stackOnly, true, "stack only")
end)

test("IsTomte: other addons and look-alike names", function()
	local F = ns.BUG_FILES
	eq(ns.Bug_IsTomte("Interface/AddOns/TomteFoo/a.lua:1: x", nil, F), false, "TomteFoo")
	eq(ns.Bug_IsTomte("Interface/AddOns/DBM-Core/DBM-Core.lua:1: x", nil, F), false, "DBM")
	eq(ns.Bug_IsTomte(nil, nil, F), false, "nothing")
	local ok, stackOnly = ns.Bug_IsTomte("Interface/AddOns/Baganator/x.lua:5: y",
		"[Interface/AddOns/Baganator/x.lua]:5: in function\n[Interface/AddOns/Tomte/Modules/Gear/Gear.lua]:40: in function", F)
	eq(ok, true, "Tomte in the stack")
	eq(stackOnly, true, "stack only")
	ok, stackOnly = ns.Bug_IsTomte("Interface/AddOns/Tomte/Core/Core.lua:1: x", nil, F)
	eq(stackOnly, false, "in the message")
end)

test("normalize survives odd messages", function()
	eq(ns.Bug_Normalize({ message = { "x" } }, true).message, "(unreadable)", "table")
	eq(ns.Bug_Normalize({}, true).message, "(unreadable)", "nil")
	eq(ns.Bug_Normalize("x", true).message, "(unreadable)", "not a table")
	eq(ns.Bug_Normalize({ message = SECRET, stack = SECRET }, true).message,
		"(hidden by the game: secret value)", "secret")
	eq(ns.Bug_Normalize({ message = SECRET, stack = SECRET }, true).stack, nil, "secret stack")
	eq(ns.Bug_Normalize({ message = "m", locals = SECRET }, true).locals, nil, "secret locals")
	eq(ns.Bug_Normalize({ message = "m", stack = 5 }, true).stack, nil, "odd stack")
	local bg = ns.Bug_Normalize({ message = "m", counter = 3, time = 100 }, false)
	eq(bg.count, 3, "BugGrabber counter")
	eq(bg.time, 100, "numeric time")
	eq(bg.current, false, "current")
	local blz = ns.Bug_Normalize({ message = "m", count = 2, time = "Sat Oct 10 21:14:00 2026" }, true)
	eq(blz.when, "Sat Oct 10 21:14:00 2026", "string time kept as text")
	eq(ns.Bug_Normalize({ message = "m", count = "x" }, true).count, 1, "odd count")
end)

test("collect filters, dedupes and caps", function()
	local function E(msg, count)
		return ns.Bug_Normalize({ message = msg, count = count or 1 }, true)
	end
	local list = ns.Bug_Collect({
		{ E("Interface/AddOns/Tomte/Core/Core.lua:1: a", 2), E("Interface/AddOns/DBM-Core/x.lua:1: b") },
		{ E("Interface/AddOns/Tomte/Core/Core.lua:1: a", 1), E("Interface/AddOns/Tomte/Core/Core.lua:2: c"),
			E("Interface/AddOns/Tomte/Core/Core.lua:3: d"), E("Interface/AddOns/Tomte/Core/Core.lua:4: e") },
	}, ns.BUG_FILES, 3)
	eq(#list, 3, "capped")
	eq(list[1].count, 3, "counts added")
	eq(list[2].message, "Interface/AddOns/Tomte/Core/Core.lua:2: c", "order kept")
	local total
	list, total = ns.Bug_Collect({ { E("Interface/AddOns/Tomte/Core/Core.lua:1: a") }, {} }, ns.BUG_FILES, 3)
	eq(total, 1, "total")
end)

test("collect counts every Tomte error, shown or not", function()
	local errs = {}
	for i = 1, 5 do
		errs[i] = ns.Bug_Normalize({ message = "Interface/AddOns/Tomte/Core/Core.lua:" .. i .. ": x" }, true)
	end
	local list, total = ns.Bug_Collect({ errs }, ns.BUG_FILES, 3)
	eq(#list, 3, "shown")
	eq(total, 5, "total")
end)

test("stack head", function()
	eq(ns.Bug_StackHead("a\nb\nc\nd", 2), "a\nb", "two lines")
	eq(ns.Bug_StackHead("a\nb", 5), "a\nb", "fewer lines")
	eq(ns.Bug_StackHead(nil, 5), nil, "nil")
end)

test("remember keeps a small newest-first ring", function()
	local buffer = {}
	local errs = {}
	for i = 1, 7 do
		errs[i] = ns.Bug_Normalize({ message = "m" .. i, stack = ("line\n"):rep(30), locals = "x", count = 1 }, true)
	end
	ns.Bug_Remember(buffer, errs, "1.5.0", 1000, 5)
	eq(#buffer, 5, "capped")
	eq(buffer[1].message, "m1", "newest first")
	eq(buffer[1].version, "1.5.0", "version")
	ns.Bug_Remember(buffer, { ns.Bug_Normalize({ message = "m3", count = 2 }, true) }, "1.5.0", 2000, 5)
	eq(buffer[1].message, "m3", "moved to the front")
	eq(buffer[1].count, 3, "count added")
	eq(buffer[1].time, 2000, "time")
	eq(#buffer, 5, "still capped")
	local _, lines = buffer[2].stack:gsub("\n", "")
	eq(lines < ns.BUG_STACK_LINES, true, "stack cut")
	eq(buffer[2].locals, nil, "no locals")
	ns.Bug_Remember(buffer, { ns.Bug_Normalize({ message = ("y"):rep(900) }, true) }, "1.5.0", 3000, 5)
	eq(#buffer[1].message, ns.BUG_MAX_MESSAGE, "message cut")
end)

test("remember survives odd saved entries", function()
	local buffer = { "junk", { message = 5 } }
	ns.Bug_Remember(buffer, { ns.Bug_Normalize({ message = "m" }, true) }, "1.5.0", 10, 5)
	eq(buffer[1].message, "m", "added")
end)

test("report text has the key lines and no locals unless full", function()
	local info = { version = "1.5.0", build = "12.1.0.69933", interface = 120100, locale = "enUS",
		theme = "cartographer", level = 80, class = "Hunter", spec = "Marksmanship", specID = 254,
		content = "The War Within", preset = "collector", on = { "pets", "minimap" }, off = { "afk" },
		blocked = { { "rogue", "not a Rogue" } }, uses = { { "Baganator", "1.2.3" }, { "Auctionator", false } },
		catcher = "BugSack (BugGrabber v12.1.0)", others = { "DBM-Core" }, total = 1,
		errors = { ns.Bug_Normalize({ message = "Interface/AddOns/Tomte/Core/Core.lua:1: a", locals = "x = 1",
			count = 2, time = "now" }, true) } }
	local text = ns.Bug_ReportText(info)
	local function has(s)
		eq(text:find(s, 1, true) ~= nil, true, s)
	end
	has("Tomte bug report")
	has("Tomte 1.5.0 | WoW 12.1.0.69933 (120100) | enUS | theme cartographer")
	has("Character: level 80 Hunter (Marksmanship, spec 254) | content The War Within")
	has("Setup: preset collector")
	has("Modules on (2): pets, minimap")
	has("Modules off (1): afk")
	has("Blocked (1): rogue (not a Rogue)")
	has("Uses: Baganator 1.2.3, Auctionator not loaded")
	has("Error catcher: BugSack (BugGrabber v12.1.0)")
	has("Other addons (1): DBM-Core")
	has("Errors from Tomte (newest first, 1 of 1):")
	has("1) x2")
	eq(text:find("x = 1", 1, true), nil, "no locals")
	info.full = true
	info.profile = "Tomte1:QUJD"
	text = ns.Bug_ReportText(info)
	has("x = 1")
	has("Tomte1:QUJD")
end)

test("report text without errors says where to get them", function()
	local text = ns.Bug_ReportText({ version = "1", on = {}, off = {}, blocked = {}, uses = {}, others = {},
		errors = {}, total = 0, catcher = nil })
	eq(text:find("No error list available. Install BugSack to catch errors.", 1, true) ~= nil, true, "hint")
	text = ns.Bug_ReportText({ version = "1", errors = {}, total = 0, catcher = "BugGrabber 1" })
	eq(text:find("No Tomte errors", 1, true) ~= nil, true, "none caught")
end)

test("report text survives missing fields and failed parts", function()
	local text = ns.Bug_ReportText({})
	eq(text:find("Tomte ? | WoW ?", 1, true) ~= nil, true, "question marks")
	text = ns.Bug_ReportText({ on = "(could not read: boom)" })
	eq(text:find("Modules on: (could not read: boom)", 1, true) ~= nil, true, "a failed part")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
