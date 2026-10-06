-- Run from the AddOns folder: lua Tomte/tests/test_recent.lua
local ns = {}
assert(loadfile("Tomte/Modules/Recent/Data.lua"))("Tomte", ns)

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

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local function isSecret(v)
	return v == SECRET
end
local ME = { guid = "Player-1", char = "Main", class = "HUNTER" }
local ALT = { guid = "Player-2", char = "Alt", class = "MAGE" }

test("entry from a toast keeps plain fields and no functions", function()
	local e = ns.Recent_FromSpec({ owner = "wq", label = "World quests", title = "Hallowfall", text = "A mount",
		accent = { 1, 0.5, 0 }, icon = 123, mergeKey = "wq:zone", onClick = function() end }, ME, 100, isSecret)
	eq(e.title, "Hallowfall")
	eq(e.text, "A mount")
	eq(e.accent[2], 0.5)
	eq(e.mergeKey, "wq:zone")
	eq(e.guid, "Player-1")
	for _, v in pairs(e) do
		assert(type(v) ~= "function", "no functions")
	end
end)

test("secret title or text is replaced, and doesn't merge", function()
	local e = ns.Recent_FromSpec({ owner = "whispers", label = "Whisper", title = SECRET, text = SECRET, secret = true,
		mergeKey = "x" }, ME, 100, isSecret)
	eq(e.title, "Whisper")
	assert(e.text:find("hidden"), "hidden text")
	eq(e.mergeKey, nil)
end)

test("banner uses its subtitle as text", function()
	local e = ns.Recent_FromSpec({ owner = "moments", label = "Level up", title = "Level 80", subtitle = "Well done" },
		ME, 100, isSecret, true)
	eq(e.text, "Well done")
	eq(e.banner, true)
end)

test("add puts newest first and caps", function()
	local list = {}
	for i = 1, 5 do
		ns.Recent_Add(list, { at = i, guid = "g", title = "t" .. i }, 3)
	end
	eq(#list, 3)
	eq(list[1].title, "t5")
	eq(list[3].title, "t3")
end)

test("merge replaces the same key and character, counts up", function()
	local list = {}
	ns.Recent_Add(list, { at = 1, guid = "g", mergeKey = "k", text = "a", count = 1 }, 10)
	ns.Recent_Add(list, { at = 2, guid = "g", text = "other", count = 1 }, 10)
	ns.Recent_Add(list, { at = 3, guid = "g", mergeKey = "k", text = "b", count = 1 }, 10)
	eq(#list, 2)
	eq(list[1].text, "b")
	eq(list[1].count, 2)
	ns.Recent_Add(list, { at = 4, guid = "h", mergeKey = "k", text = "c", count = 1 }, 10)
	eq(#list, 3, "another character doesn't merge")
end)

test("visible filters scope, owners and banners", function()
	local list = {
		{ at = 3, guid = ME.guid, owner = "wq" },
		{ at = 2, guid = ALT.guid, owner = "whispers" },
		{ at = 1, guid = ME.guid, owner = "moments", banner = true },
	}
	eq(#ns.Recent_Visible(list, "account", ME.guid, {}), 3)
	eq(#ns.Recent_Visible(list, "char", ME.guid, {}), 2)
	eq(#ns.Recent_Visible(list, "account", ME.guid, { whispers = false }), 2)
	eq(#ns.Recent_Visible(list, "account", ME.guid, { banners = false }), 2)
	eq(ns.Recent_Unseen(list, 1), 2)
end)

test("ago", function()
	eq(ns.Recent_Ago(10), "now")
	eq(ns.Recent_Ago(300), "5m")
	eq(ns.Recent_Ago(7200), "2h")
	eq(ns.Recent_Ago(200000), "2d")
end)

test("group by day", function()
	local function day(t)
		return math.floor(t / 86400)
	end
	eq(ns.Recent_Group(86400 * 5 + 10, 86400 * 5 + 500, day), "Today")
	eq(ns.Recent_Group(86400 * 4, 86400 * 5 + 500, day), "Earlier")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
