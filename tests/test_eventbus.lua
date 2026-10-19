-- Run from the AddOns folder: lua Tomte/tests/test_eventbus.lua
local registered = {}
local frames = {}
_G.CreateFrame = function()
	local f = { scripts = {} }
	function f:SetScript(name, fn) self.scripts[name] = fn end
	function f:RegisterEvent(e) registered[e] = "all" end
	function f:RegisterUnitEvent(e, u1, u2) registered[e] = u1 .. (u2 and ("," .. u2) or "") end
	function f:UnregisterEvent(e) registered[e] = nil end
	frames[#frames + 1] = f
	return f
end
local reported = {}
local ns = {
	errorHandler = function(err)
		reported[#reported + 1] = tostring(err)
	end,
}
assert(loadfile("Tomte/Core/Events.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
-- Each test starts with nothing registered on the fake frame API.
local function test(name, fn)
	for k in pairs(registered) do registered[k] = nil end
	H.test(name, fn)
end
local eq = H.eq
local function Fire(bus, event, ...)
	bus.frame.scripts.OnEvent(bus.frame, event, ...)
end

test("handlers run in attach order, only for watching owners", function()
	local bus, calls = ns.NewEvents(), {}
	bus:On("a", "E", function(self, x) calls[#calls + 1] = "a" .. x end)
	bus:On("b", "E", function(self, x) calls[#calls + 1] = "b" .. x end)
	bus:Watch("a", "E")
	Fire(bus, "E", 1)
	eq(table.concat(calls, " "), "a1")
	bus:Watch("b", "E")
	Fire(bus, "E", 2)
	eq(table.concat(calls, " "), "a1 a2 b2")
end)
test("one owner's unwatch keeps the event for another", function()
	local bus = ns.NewEvents()
	bus:On("a", "E", function() end)
	bus:On("b", "E", function() end)
	bus:Watch("a", "E")
	bus:Watch("b", "E")
	bus:Unwatch("a", "E")
	eq(registered.E, "all")
	bus:Unwatch("b", "E")
	eq(registered.E, nil)
end)
test("UnwatchAll only drops that owner", function()
	local bus = ns.NewEvents()
	bus:Watch("a", "E")
	bus:Watch("a", "F")
	bus:Watch("b", "F")
	bus:UnwatchAll("a")
	eq(registered.E, nil)
	eq(registered.F, "all")
	eq(bus:Watching("a", "F"), false)
	eq(bus:Watching("b", "F"), true)
end)
test("unit events", function()
	local bus = ns.NewEvents()
	bus:Watch("a", "UNIT_AURA", "player")
	eq(registered.UNIT_AURA, "player")
end)
test("handlers get the bus as self", function()
	local bus, seen = ns.NewEvents(), nil
	bus:On("a", "E", function(self) seen = self end)
	bus:Watch("a", "E")
	Fire(bus, "E")
	eq(seen, bus)
end)
test("an owner unwatching itself inside its handler is fine", function()
	local bus, n = ns.NewEvents(), 0
	bus:On("a", "E", function(self) n = n + 1; self:Unwatch("a", "E") end)
	bus:Watch("a", "E")
	Fire(bus, "E")
	Fire(bus, "E")
	eq(n, 1)
end)
test("TryWatch survives an unknown event", function()
	local bus = ns.NewEvents()
	bus.frame.RegisterEvent = function() error("unknown event") end
	eq(bus:TryWatch("a", "NOPE"), false)
	eq(bus:Watching("a", "NOPE"), false)
end)
test("a handler that errors doesn't stop the next one", function()
	local bus, calls = ns.NewEvents(), {}
	for i = #reported, 1, -1 do
		reported[i] = nil
	end
	bus:On("a", "E", function()
		error("boom")
	end)
	bus:On("b", "E", function(self, x)
		calls[#calls + 1] = "b" .. x
	end)
	bus:Watch("a", "E")
	bus:Watch("b", "E")
	Fire(bus, "E", 1)
	eq(table.concat(calls, " "), "b1", "b still ran")
	eq(#reported, 1, "the error went to ns.errorHandler")
	assert(reported[1]:find("boom"), reported[1])
end)
test("handlers get their arguments through xpcall", function()
	local bus, got = ns.NewEvents(), {}
	bus:On("a", "E", function(self, x, y, z)
		got.self, got.x, got.y, got.z = self, x, y, z
	end)
	bus:Watch("a", "E")
	Fire(bus, "E", "one", nil, 3)
	eq(got.self, bus, "the bus first")
	eq(got.x, "one")
	eq(got.y, nil, "a nil in the middle survives")
	eq(got.z, 3)
end)

H.done()
