-- Run from the AddOns folder: lua Tomte/tests/test_content.lua
local ns = {}
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)

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

test("Resolve follows the level band, capped at what the account owns", function()
	eq(ns.Content_Resolve(10, 11), 10, "owner at 80")
	eq(ns.Content_Resolve(11, 11), 11, "owner at 85")
	eq(ns.Content_Resolve(11, 10), 10, "non-owner can't go past what it owns")
	eq(ns.Content_Resolve(nil, 10), 10, "no answer for the level: what it owns")
	eq(ns.Content_Resolve(9, nil), 9, "no owned level: the band")
end)

test("ContentExpansion and ContentAtMax use the game's level rule", function()
	_G.UnitLevel = function()
		return 80
	end
	_G.GetExpansionForLevel = function(level)
		return level <= 80 and 10 or 11
	end
	_G.GetExpansionLevel = function()
		return 11
	end
	_G.GetMaxLevelForExpansionLevel = function(e)
		return ({ [10] = 80, [11] = 90 })[e]
	end
	eq(ns.ContentExpansion(), 10, "owner's alt at 80")
	eq(ns.ContentAtMax(), true, "80 is War Within's max")
	eq(ns.ContentExpansion(85), 11, "85")
	eq(ns.ContentAtMax(85), false, "85 isn't Midnight's max")
	eq(ns.ContentAtMax(90), true, "90")
	_G.GetExpansionLevel = function()
		return 10
	end
	eq(ns.ContentExpansion(90), 10, "non-owner")
	eq(ns.ContentAtMax(80), true, "non-owner at 80")
end)

test("Register and Get per expansion", function()
	ns.Content_Register(10, "raids", { 1 })
	ns.Content_Register(11, "crests", { 2 })
	eq(ns.Content_Get(10, "raids")[1], 1, "raids")
	eq(ns.Content_Get(11, "raids"), nil, "missing key")
	eq(ns.Content_Get(12, "raids"), nil, "missing expansion")
	eq(ns.Content_Get(nil, "raids"), nil, "no expansion")
	eq(#ns.Content_Expansions(), 2, "expansions")
	eq(ns.ExpansionName(11), "Midnight", "name")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
