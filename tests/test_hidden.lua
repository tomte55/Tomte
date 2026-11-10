-- Run from the AddOns folder: lua Tomte/tests/test_hidden.lua
local ns = {}
assert(loadfile("Tomte/Modules/Hidden/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function State(set, saved, applied)
	return { set = set or {}, saved = saved or {}, applied = applied or {} }
end

test("Same compares numbers in the game's format", function()
	eq(ns.Hidden_Same("1.000000", "1"), true)
	eq(ns.Hidden_Same("2.6", "2.600000"), true)
	eq(ns.Hidden_Same("0", "1"), false)
	eq(ns.Hidden_Same("png", "png"), true)
	eq(ns.Hidden_Same(nil, "1"), false)
end)

test("every setting has a label, a kind and a known client", function()
	local seen = {}
	for _, e in ipairs(ns.HIDDEN_SETTINGS) do
		if not e.group then
			assert(e.label and (e.kind == "switch" or e.kind == "slider"), e.cvar)
			assert(e.client == nil or e.client == "retail" or e.client == "forever", e.cvar)
			assert(not seen[e.cvar], "listed twice: " .. e.cvar)
			seen[e.cvar] = true
			if e.kind == "slider" then
				assert(e.min and e.max and e.step and e.min < e.max, e.cvar)
			end
		end
	end
end)

test("Available follows the client and whether the CVar exists", function()
	local yes = function()
		return true
	end
	local no = function()
		return false
	end
	eq(ns.Hidden_Available({ cvar = "a" }, false, yes), true)
	eq(ns.Hidden_Available({ cvar = "a" }, true, no), false)
	eq(ns.Hidden_Available({ cvar = "a", client = "forever" }, false, yes), false)
	eq(ns.Hidden_Available({ cvar = "a", client = "forever" }, true, yes), true)
	eq(ns.Hidden_Available({ group = "Map" }, false, yes), false)
end)

test("switch values, inverted too", function()
	eq(ns.Hidden_SwitchValue({}, true), "1")
	eq(ns.Hidden_SwitchValue({ invert = true }, true), "0")
	eq(ns.Hidden_SwitchOn({}, "1"), true)
	eq(ns.Hidden_SwitchOn({}, "0.000000"), false)
	eq(ns.Hidden_SwitchOn({ invert = true }, "0"), true)
end)

test("slider values snap to the step and the range", function()
	local zoom = { min = 1, max = 2.6, step = 0.1 }
	eq(ns.Hidden_SliderValue(zoom, 2.6000001), "2.6")
	eq(ns.Hidden_SliderValue(zoom, 3), "2.6")
	eq(ns.Hidden_SliderValue(zoom, 1), "1")
	eq(ns.Hidden_SliderValue({ min = 0, max = 400, step = 10 }, 123), "120")
end)

test("Choose saves the old value once and forgets a choice put back", function()
	local s = State()
	eq(ns.Hidden_Choose(s, "x", "1", "1"), false) -- already that
	eq(s.saved.x, nil)
	eq(ns.Hidden_Choose(s, "x", "0", "1"), true)
	eq(s.saved.x, "1")
	eq(s.set.x, "0")
	eq(ns.Hidden_Choose(s, "x", "2", "0"), true)
	eq(s.saved.x, "1") -- still the value from before Tomte
	eq(ns.Hidden_Choose(s, "x", "1.000000", "2"), true)
	eq(s.set.x, nil)
	eq(s.saved.x, nil)
end)

test("StartPlan writes choices the game doesn't have yet", function()
	local s = State({ zoom = "2.6", ok = "1" }, { ok = "0" }, { ok = "1" })
	local writes, adopted = ns.Hidden_StartPlan(s, { zoom = "1.000000", ok = "1" })
	eq(#writes, 1)
	eq(writes[1].cvar, "zoom")
	eq(s.saved.zoom, "1.000000")
	eq(#adopted, 0)
end)

test("StartPlan lets a change made elsewhere win", function()
	local s = State({ zoom = "2.6" }, { zoom = "1" }, { zoom = "2.600000" })
	local writes, adopted = ns.Hidden_StartPlan(s, { zoom = "2.0" })
	eq(#writes, 0)
	eq(adopted[1], "zoom")
	eq(s.set.zoom, nil)
	eq(s.saved.zoom, nil)
end)

test("StartPlan keeps a choice for a CVar this client lacks", function()
	local s = State({ showKeyring = "1" })
	local writes = ns.Hidden_StartPlan(s, {})
	eq(#writes, 0)
	eq(s.set.showKeyring, "1")
end)

test("StopPlan puts back only what is still Tomte's", function()
	local s = State({ a = "1", b = "1" }, { a = "0", b = "0" }, { a = "1", b = "1" })
	local writes = ns.Hidden_StopPlan(s, { a = "1", b = "5" })
	eq(#writes, 1)
	eq(writes[1].cvar, "a")
	eq(writes[1].value, "0")
	eq(s.saved.a, nil)
	eq(s.saved.b, nil)
	eq(s.set.a, "1") -- kept for the next start
end)

test("DiffText lists what differs, grouped and sorted", function()
	local rows = {
		{ name = "zeta", value = "1", default = "0", category = 4 },
		{ name = "alpha", value = "1.000000", default = "1", category = 4 },
		{ name = "Beta", value = "", default = "x", category = 1 },
	}
	local text, count = ns.Hidden_DiffText(rows, function(c)
		return c == 1 and "Graphics" or "Game"
	end)
	eq(count, 2)
	eq(text, '-- Game\nzeta: now 1, game default 0\n\n-- Graphics\nBeta: now "", game default x')
end)

H.done()
