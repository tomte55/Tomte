-- Run from the AddOns folder: lua Tomte/tests/test_setup.lua
local ns = {
	errorHandler = function(err)
		error(err)
	end,
}
assert(loadfile("Tomte/Core/Modules.lua"))("Tomte", ns)
assert(loadfile("Tomte/Core/Setup.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

-- The real module keys, read from the source so a renamed module breaks this test.
local function RealKeys()
	local keys = {}
	for line in io.lines("Tomte/Tomte.toc") do
		local file = line:match("^([%w_/\\]+%.lua)%s*$")
		if file then
			local f = assert(io.open("Tomte/" .. file:gsub("\\", "/")))
			local text = f:read("*a")
			f:close()
			for key in text:gmatch("RegisterModule%(%{%s*key%s*=%s*\"([%w_]+)\"") do
				keys[key] = true
			end
		end
	end
	return keys
end

local function Register()
	ns.modules, ns.modulesByKey, ns.homeByKey = {}, {}, {}
	ns.RegisterModule({ key = "window", name = "Tomte window", category = "General", alwaysOn = true })
	local keys = {}
	for key in pairs(RealKeys()) do
		if key ~= "window" then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		ns.RegisterModule({ key = key, name = "N-" .. key, category = "X", enabledByDefault = true,
			toggle = function() end })
	end
	ns.db = { enabled = {} }
	for _, m in ipairs(ns.modules) do
		ns.RefreshModule(m)
	end
end

test("every preset and base key is a registered module key", function()
	local real = RealKeys()
	eq(real.window, true, "source scan finds modules")
	eq(real.fishing, true, "source scan finds the newest modules")
	for _, key in ipairs(ns.SETUP_BASE) do
		eq(real[key], true, "base " .. key)
	end
	for _, preset in ipairs(ns.SETUP_PRESETS) do
		for _, key in ipairs(preset.on or {}) do
			eq(real[key], true, preset.key .. " " .. key)
		end
	end
end)

test("presets come in the picker's order", function()
	eq(ns.SETUP_PRESETS[1].key, "minimal", "1")
	eq(ns.SETUP_PRESETS[2].key, "collector", "2")
	eq(ns.SETUP_PRESETS[3].key, "crafter", "3")
	eq(ns.SETUP_PRESETS[4].key, "social", "4")
	eq(ns.SETUP_PRESETS[5].key, "everything", "5")
	eq(ns.Setup_Preset("crafter").name, "Crafter", "lookup")
	eq(ns.Setup_Preset("nope"), nil, "unknown")
end)

test("crafter plan turns its modules and the base on, the rest off, never touches window", function()
	Register()
	local plan = ns.Setup_Plan("crafter", ns.modules)
	eq(plan.enabled.alts, true, "alts")
	eq(plan.enabled.value, true, "value")
	eq(plan.enabled.gather, true, "gather")
	eq(plan.enabled.fishing, true, "fishing")
	eq(plan.enabled.hunter, true, "class modules are base")
	eq(plan.enabled.afk, false, "afk")
	eq(plan.enabled.recap, false, "recap")
	eq(plan.enabled.moments, false, "moments")
	eq(plan.enabled.whispers, nil, "whispers left alone")
	eq(plan.enabled.tradefilter, true, "trade filter")
	eq(plan.enabled.chattabs, true, "chat tabs")
	eq(plan.enabled.events, false, "events")
	eq(plan.enabled.window, nil, "window is always on")
end)

test("collector has the collecting modules, minimal none of the new ones", function()
	Register()
	local plan = ns.Setup_Plan("collector", ns.modules)
	eq(plan.enabled.events, true, "events")
	eq(plan.enabled.delves, true, "delves")
	eq(plan.enabled.pets, true, "pets")
	eq(plan.enabled.gather, false, "gather")
	plan = ns.Setup_Plan("minimal", ns.modules)
	for _, key in ipairs({ "events", "delves", "gather", "fishing", "moments", "afk", "recap" }) do
		eq(plan.enabled[key], false, "minimal " .. key)
	end
end)

test("class modules are in every preset", function()
	Register()
	for _, preset in ipairs(ns.SETUP_PRESETS) do
		local plan = ns.Setup_Plan(preset.key, ns.modules)
		if not plan.clear then
			eq(plan.enabled.hunter and plan.enabled.pet and plan.enabled.rogue, true, preset.key)
		end
	end
end)

test("everything clears the choices", function()
	Register()
	ns.db.enabled.afk = false
	local plan = ns.Setup_Plan("everything", ns.modules)
	eq(plan.clear, true, "clear")
	ns.Setup_Apply(ns.db, plan, ns.modules)
	eq(next(ns.db.enabled), nil, "enabled emptied")
end)

test("apply writes choices, refreshes modules and keeps the enabled table", function()
	Register()
	local before = ns.db.enabled
	ns.Setup_Apply(ns.db, ns.Setup_Plan("minimal", ns.modules), ns.modules)
	eq(ns.db.enabled, before, "same table")
	eq(ns.db.enabled.recap, false, "recap off")
	eq(ns.modulesByKey.recap.active, false, "recap stopped")
	eq(ns.modulesByKey.gear.active, true, "gear running")
end)

test("matches is true right after applying and false after a change", function()
	Register()
	eq(ns.Setup_Matches("everything", ns.modules), true, "defaults are Everything")
	ns.Setup_Apply(ns.db, ns.Setup_Plan("collector", ns.modules), ns.modules)
	eq(ns.Setup_Matches("collector", ns.modules), true, "matches")
	eq(ns.Setup_Matches("crafter", ns.modules), false, "other preset")
	ns.SetModuleEnabled("ach", false)
	eq(ns.Setup_Matches("collector", ns.modules), false, "after a change")
	eq(ns.Setup_Matches("nope", ns.modules), false, "unknown")
end)

test("unknown preset is an error, not a crash", function()
	Register()
	local plan, err = ns.Setup_Plan("nope", ns.modules)
	eq(plan, nil, "plan")
	eq(err, "unknown preset", "err")
end)

test("OnNames lists module names in registration order", function()
	Register()
	local names = ns.Setup_OnNames("minimal", ns.modules)
	eq(#names, #ns.SETUP_BASE + 4, "count")
	for i = 2, #names do
		eq(names[i - 1] < names[i], true, "order " .. i)
	end
	eq(#ns.Setup_OnNames("everything", ns.modules), #ns.modules - 1 - #ns.SETUP_UNTOUCHED,
		"everything: every default-on module it touches")
	eq(#ns.Setup_OnNames("nope", ns.modules), 0, "unknown")
end)

test("presets leave Whispers, Mentions, Friends Online and Group Alerts alone", function()
	Register()
	for _, key in ipairs({ "minimal", "collector", "crafter" }) do
		local plan = ns.Setup_Plan(key, ns.modules)
		for _, k in ipairs(ns.SETUP_UNTOUCHED) do
			eq(plan.enabled[k], nil, key .. " " .. k)
		end
	end
end)

test("Social turns the chat and social modules on", function()
	Register()
	local plan = ns.Setup_Plan("social", ns.modules)
	for _, k in ipairs({ "whispers", "mentions", "friends", "alerts", "share", "tradefilter", "chattabs", "chattags",
		"chatcopy", "recent", "way" }) do
		eq(plan.enabled[k], true, k)
	end
	eq(plan.enabled.gather, false, "gather")
	eq(plan.enabled.hunter, true, "class modules are base")
end)

test("a preset keeps the player's choice for the modules it leaves alone", function()
	Register()
	ns.SetModuleEnabled("whispers", false)
	ns.Setup_Apply(ns.db, ns.Setup_Plan("minimal", ns.modules), ns.modules)
	eq(ns.db.enabled.whispers, false, "minimal keeps it")
	eq(ns.Setup_Matches("minimal", ns.modules), true, "matches ignores it")
	ns.Setup_Apply(ns.db, ns.Setup_Plan("everything", ns.modules), ns.modules)
	eq(ns.db.enabled.whispers, false, "everything keeps it too")
	eq(ns.db.enabled.recap, nil, "everything clears the rest")
	eq(ns.Setup_Matches("everything", ns.modules), true, "matches")
	ns.Setup_Apply(ns.db, ns.Setup_Plan("social", ns.modules), ns.modules)
	eq(ns.db.enabled.whispers, true, "a preset that names it turns it on")
end)

test("existing user is marked done, with no note", function()
	local db = { schema = 1, enabled = { afk = false } }
	ns.Setup_Migrate(db)
	eq(db.setup.state, "done", "state")
	eq(db.setup.note, nil, "no note")
end)

test("fresh install stays pending through the migration", function()
	local db = {}
	ns.Setup_MarkFresh(db)
	ns.Setup_Migrate(db)
	eq(db.setup.state, "pending", "state")
end)

H.done()
