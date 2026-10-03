-- Run from the AddOns folder: lua Tomte/tests/test_minimap.lua
local ns = {}
assert(loadfile("Tomte/Modules/Minimap/Data.lua"))("Tomte", ns)

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
local function near(actual, expected, label)
	if math.abs(actual - expected) > 0.001 then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

test("Offset: round right", function()
	local x, y = ns.Minimap_Offset(0, 75, 75, nil)
	near(x, 75)
	near(y, 0)
end)

test("Offset: round 225", function()
	local x, y = ns.Minimap_Offset(225, 75, 75, "ROUND")
	near(x, -75 * math.sqrt(0.5))
	near(y, -75 * math.sqrt(0.5))
end)

test("Offset: square corner", function()
	-- On the diagonal, pulled 10 px in from the corner (as LibDBIcon does).
	local x, y = ns.Minimap_Offset(45, 75, 75, "SQUARE")
	local d = math.sqrt(0.5) * (math.sqrt(2 * 75 ^ 2) - 10)
	near(x, d)
	near(y, d)
end)

test("Offset: square edge middle", function()
	local x, y = ns.Minimap_Offset(90, 75, 75, "SQUARE")
	near(x, 0)
	near(y, 75)
end)

test("Offset: unknown shape counts as round", function()
	local x = ns.Minimap_Offset(0, 75, 75, "BLOB")
	near(x, 75)
end)

test("Angle wraps to 0-360", function()
	near(ns.Minimap_Angle(1, 0), 0)
	near(ns.Minimap_Angle(0, 1), 90)
	near(ns.Minimap_Angle(-1, -1), 225)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
