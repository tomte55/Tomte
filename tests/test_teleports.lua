-- Run from the AddOns folder: lua Tomte/tests/test_teleports.lua
local ns = {}
assert(loadfile("Tomte/Modules/Teleports/Data.lua"))("Tomte", ns)

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

test("destination from descriptions", function()
	eq(ns.Tp_Destination("Teleport to the entrance to The Stonevault."), "The Stonevault")
	eq(ns.Tp_Destination("Teleport to the entrance to Operation: Floodgate."), "Operation: Floodgate")
	eq(ns.Tp_Destination("Teleports the caster to Stormwind."), "Stormwind")
	eq(ns.Tp_Destination("Creates a portal, teleporting group members that use it to Orgrimmar."), "Orgrimmar")
	eq(ns.Tp_Destination("Teleports the caster to Dalaran. Some more text."), "Dalaran")
	eq(ns.Tp_Destination("Summons a mount."), nil)
	eq(ns.Tp_Destination(nil), nil)
end)

test("mentions: case-insensitive, skips short names", function()
	eq(ns.Tp_Mentions("Teleport to the entrance to The Stonevault.", { "Isle of Dorn", "the stonevault" }), true)
	eq(ns.Tp_Mentions("Teleports the caster to Stormwind.", { "Orgrimmar" }), false)
	eq(ns.Tp_Mentions("Teleports to Org.", { "Org" }), false, "short name")
	eq(ns.Tp_Mentions(nil, { "Dalaran" }), false)
	eq(ns.Tp_Mentions("Stormwind", { "Stormwind City" }), true, "destination is part of the map name")
	eq(ns.Tp_Mentions("Org", { "Orgrimmar" }), false, "short destination")
end)

local function entry(t)
	t.name = t.name or t.key
	return t
end

test("sections: order, favorites and here are copies", function()
	local out = ns.Tp_Sections({
		entry({ key = "a", section = "items", known = true }),
		entry({ key = "b", section = "hearth", known = true, favorite = true }),
		entry({ key = "c", section = "dungeon", known = true, here = true }),
	}, {})
	eq(#out, 5)
	eq(out[1].key, "favorites")
	eq(out[1].entries[1].key, "b")
	eq(out[2].key, "here")
	eq(out[2].entries[1].key, "c")
	eq(out[3].key, "hearth")
	eq(out[4].key, "dungeon")
	eq(out[5].key, "items")
end)

test("sections: unknown only for current-season dungeons with the option", function()
	local list = {
		entry({ key = "known", section = "dungeon", known = true }),
		entry({ key = "cur", section = "dungeon", current = true }),
		entry({ key = "old", section = "dungeon" }),
		entry({ key = "item", section = "items" }),
	}
	local out = ns.Tp_Sections(list, { showUnearned = true })
	eq(#out, 1)
	eq(#out[1].entries, 2)
	out = ns.Tp_Sections(list, { showUnearned = false })
	eq(#out[1].entries, 1)
end)

test("sections: dungeon order is current known, older known, unearned", function()
	local out = ns.Tp_Sections({
		entry({ key = "z-unearned", name = "A", section = "dungeon", current = true }),
		entry({ key = "old", name = "B", section = "dungeon", known = true }),
		entry({ key = "cur", name = "C", section = "dungeon", known = true, current = true }),
	}, { showUnearned = true })
	local e = out[1].entries
	eq(e[1].key, "cur")
	eq(e[2].key, "old")
	eq(e[3].key, "z-unearned")
end)

test("sections: unknown favorites don't show, hidden sections drop out", function()
	local out = ns.Tp_Sections({
		entry({ key = "a", section = "class", favorite = true }),
		entry({ key = "b", section = "class", known = true }),
	}, { hidden = { class = true } })
	eq(#out, 0)
end)

test("cooldown format", function()
	eq(ns.Tp_FormatCooldown(45), "45s")
	eq(ns.Tp_FormatCooldown(754), "12:34")
	eq(ns.Tp_FormatCooldown(5025), "1:23:45")
	eq(ns.Tp_FormatCooldown(59.2), "1:00")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
