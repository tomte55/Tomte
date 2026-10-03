-- Run from the AddOns folder: lua Tomte/tests/test_afk.lua
local ns = {}
assert(loadfile("Tomte/Modules/AFK/Data.lua"))("Tomte", ns)

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

test("ClockText uses 24h or 12h", function()
	eq(ns.AFK_ClockText(21, 7, true), "21:07")
	eq(ns.AFK_ClockText(0, 5, true), "00:05")
	eq(ns.AFK_ClockText(21, 7, false), "9:07 PM")
	eq(ns.AFK_ClockText(0, 5, false), "12:05 AM")
	eq(ns.AFK_ClockText(12, 30, false), "12:30 PM")
end)

test("XPGain is nil without progress", function()
	eq(ns.AFK_XPGain(70, 0.5, 70, 0.5), nil)
	eq(ns.AFK_XPGain(70, 0.5, 70, 0.4), nil)
end)

test("XPGain shows part of a level as a percentage", function()
	eq(ns.AFK_XPGain(70, 0.25, 70, 0.62), "+37% of a level")
	eq(ns.AFK_XPGain(70, 0.9, 71, 0.1), "+20% of a level")
end)

test("XPGain shows whole levels with one decimal", function()
	eq(ns.AFK_XPGain(70, 0.5, 72, 0.0), "+1.5 levels")
	eq(ns.AFK_XPGain(70, 0.0, 71, 0.0), "+1.0 levels")
end)

test("AddWhisper keeps the newest entries up to the cap", function()
	local list = {}
	for i = 1, 5 do
		ns.AFK_AddWhisper(list, { text = "m" .. i }, 3)
	end
	eq(#list, 3)
	eq(list[1].text, "m3")
	eq(list[3].text, "m5")
	eq(list.dropped, 2)
end)

test("VisibleWhispers returns the newest n, oldest first, and how many are left out", function()
	local list = {}
	for i = 1, 5 do
		ns.AFK_AddWhisper(list, { text = "m" .. i }, 20)
	end
	local shown, more = ns.AFK_VisibleWhispers(list, 3)
	eq(#shown, 3)
	eq(shown[1].text, "m3")
	eq(shown[3].text, "m5")
	eq(more, 2)
	shown, more = ns.AFK_VisibleWhispers(list, 10)
	eq(#shown, 5)
	eq(more, 0)
end)

test("VisibleWhispers counts entries dropped by the cap as left out", function()
	local list = {}
	for i = 1, 5 do
		ns.AFK_AddWhisper(list, { text = "m" .. i }, 3)
	end
	local shown, more = ns.AFK_VisibleWhispers(list, 2)
	eq(#shown, 2)
	eq(shown[2].text, "m5")
	eq(more, 3) -- m1, m2 dropped by the cap + m3 not shown
end)

test("MoneyText shows only gold once there is any, with thousands separators", function()
	local icons = { gold = "%sg", silver = "%ss", copper = "%sc" }
	eq(ns.AFK_MoneyText(500002312, false, icons), "50,000g")
	eq(ns.AFK_MoneyText(12345678, false, icons), "1,234g")
	eq(ns.AFK_MoneyText(9990000, false, icons), "999g")
	eq(ns.AFK_MoneyText(5612, false, icons), "56s 12c")
	eq(ns.AFK_MoneyText(5600, false, icons), "56s")
	eq(ns.AFK_MoneyText(7, false, icons), "7c")
	eq(ns.AFK_MoneyText(0, false, icons), "0c")
end)

test("MoneyText keeps silver next to gold when detailed", function()
	local icons = { gold = "%sg", silver = "%ss", copper = "%sc" }
	eq(ns.AFK_MoneyText(12345678, true, icons), "1,234g 56s")
	eq(ns.AFK_MoneyText(12340078, true, icons), "1,234g")
	eq(ns.AFK_MoneyText(1234567890, true, icons), "123,456g 78s")
	eq(ns.AFK_MoneyText(5612, true, icons), "56s 12c")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
