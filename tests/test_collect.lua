-- Run from the AddOns folder: lua Tomte/tests/test_collect.lua
local ns = {}
assert(loadfile("Tomte/Modules/Collect/Data.lua"))("Tomte", ns)

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
local function has(list, value, label)
	for _, v in ipairs(list) do
		if v == value then
			return
		end
	end
	error((label or "list") .. ": missing " .. tostring(value) .. " in {" .. table.concat(list, "; ") .. "}", 2)
end

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"

test("clean strips colors and textures", function()
	eq(ns.Collect_Clean("|cFFFFD200Drop: |rDoomwalker"), "Drop: Doomwalker")
	eq(ns.Collect_Clean("777" .. GOLD), "777")
	eq(ns.Collect_Clean("  x  "), "x")
	eq(ns.Collect_Clean(nil), "")
end)

test("parse a drop with a zone", function()
	local s = ns.Collect_ParseSource("|cFFFFD200Drop: |rDoomwalker|n|cFFFFD200Zone: |rTanaris")
	eq(#s.lines, 2)
	eq(s.lines[1].label, "drop")
	eq(s.lines[1].value, "Doomwalker")
	has(s.zones, "tanaris")
	eq(s.drop, "Doomwalker")
	eq(s.line, "Drop: Doomwalker")
end)

test("parse a vendor with a cost, label space after |r", function()
	local raw = "|cFFFFD200Vendor:|r Ando the Gat|n|cFFFFD200Zone: |rLiberation of Undermine|n|cFFFFD200Cost:|r 777" .. GOLD
	local s = ns.Collect_ParseSource(raw)
	has(s.zones, "liberation of undermine")
	eq(s.line, "Vendor: Ando the Gat · 777" .. GOLD)
	eq(s.drop, nil)
end)

test("comma in an instance name with a qualifier", function()
	local s = ns.Collect_ParseSource("|cFFFFD200Drop: |rFyrakk|n|cFFFFD200Zone: |rAmirdrassil, the Dream's Hope (Mythic)")
	eq(ns.Collect_MatchZones(s.zones, { ["amirdrassil, the dream's hope"] = "Amirdrassil, the Dream's Hope" }),
		"Amirdrassil, the Dream's Hope")
	eq(s.line, "Drop: Fyrakk (Mythic)")
	eq(s.drop, "Fyrakk")
end)

test("pet battle list with qualifiers", function()
	local s = ns.Collect_ParseSource("|cFFFFD200Pet Battle: |rAzshara, Eversong Woods (Burning Crusade), Nagrand")
	has(s.zones, "eversong woods")
	has(s.zones, "nagrand")
	has(s.zones, "azshara")
	eq(s.line, "Wild pet battle")
	eq(ns.Collect_MatchZones(s.zones, { ["nagrand"] = "Nagrand" }), "Nagrand")
end)

test("no zone line: nothing to match", function()
	local s = ns.Collect_ParseSource("|cFFFFD200Promotion:|r Blizzard Store")
	eq(#s.zones, 0)
	eq(s.line, "Promotion: Blizzard Store")
	eq(ns.Collect_MatchZones(s.zones, { ["tanaris"] = "Tanaris" }), nil)
end)

test("location label counts as a zone", function()
	local s = ns.Collect_ParseSource("|cFFFFD200Treasure:|r Hidden Chest|n|cFFFFD200Location:|r Hallowfall")
	has(s.zones, "hallowfall")
	eq(s.line, "Treasure: Hidden Chest")
end)

test("alias: capital cities", function()
	local s = ns.Collect_ParseSource("|cFFFFD200Vendor:|r Someone|n|cFFFFD200Zone: |rCapital Cities")
	eq(ns.Collect_MatchZones(s.zones, { ["orgrimmar"] = "Orgrimmar" }), "Orgrimmar")
	local s2 = ns.Collect_ParseSource("|cFFFFD200Zone: |rStormwind")
	eq(ns.Collect_MatchZones(s2.zones, { ["stormwind city"] = "Stormwind City" }), "Stormwind City")
end)

test("world drop is no drop name", function()
	local s = ns.Collect_ParseSource("|cFFFFD200Drop: |rWorld Drop|n|cFFFFD200Zone: |rThe Waking Shores")
	eq(s.drop, nil)
	eq(s.line, "Drop: World Drop")
end)

test("empty and nil sources", function()
	local s = ns.Collect_ParseSource(nil)
	eq(#s.lines, 0)
	eq(#s.zones, 0)
	eq(s.line, nil)
	eq(#ns.Collect_ParseSource("").zones, 0)
end)

test("candidates: pieces and joined pairs", function()
	local c = ns.Collect_Candidates("A Place, B Place (Heroic), C Place")
	has(c, "a place")
	has(c, "b place")
	has(c, "c place")
	has(c, "a place, b place")
	has(c, "b place, c place")
end)

test("text mentions: whole words only", function()
	eq(ns.Collect_TextMentions("explore hallowfall", { "Hallowfall" }), true)
	eq(ns.Collect_TextMentions("treasures of hallowfallen", { "Hallowfall" }), false)
	eq(ns.Collect_TextMentions("go to org now", { "Org" }), false, "short name")
	eq(ns.Collect_TextMentions("the ringing deeps loremaster", { "Isle of Dorn", "The Ringing Deeps" }), true)
	eq(ns.Collect_TextMentions("hallowfall.", { "Hallowfall" }), true, "punctuation is a boundary")
	eq(ns.Collect_TextMentions("dalaran's sewers", { "Dalaran" }), true, "apostrophe after is a boundary")
	eq(ns.Collect_TextMentions(nil, { "Dalaran" }), false)
	eq(ns.Collect_TextMentions("a (b) c", { "(b)x" }), false, "magic characters are plain")
end)

test("real line breaks separate lines too", function()
	local s = ns.Collect_ParseSource("|cFFFFD200Quest:|r She's in a Happier Place\n|cFFFFD200Zone:|r Tanaris")
	has(s.zones, "tanaris")
	eq(s.line, "Quest: She's in a Happier Place")
	local s2 = ns.Collect_ParseSource("|cFFFFD200Drop:|r X\r\n|cFFFFD200Zone:|r Tanaris")
	has(s2.zones, "tanaris")
end)

test("lower-case mentions: same rules, no lowering", function()
	eq(ns.Collect_LowerMentions("explore hallowfall", { "hallowfall" }), true)
	eq(ns.Collect_LowerMentions("treasures of hallowfallen", { "hallowfall" }), false)
	eq(ns.Collect_LowerMentions("go to org now", { "org" }), false, "short name")
	eq(ns.Collect_LowerMentions(nil, { "dalaran" }), false)
end)

test("sections: order, up-now first, sorting", function()
	local out = ns.Collect_Sections({
		{ kind = "ach", name = "B", percent = 10 },
		{ kind = "pet", name = "Zeta" },
		{ kind = "mount", name = "Beta" },
		{ kind = "mount", name = "Alpha" },
		{ kind = "mount", name = "Gamma", upNow = { x = 0.1, y = 0.2 } },
		{ kind = "ach", name = "A", percent = 50 },
		{ kind = "ach", name = "C", percent = 50 },
	}, { show = { mounts = true, pets = true, achievements = true }, collapsed = {} })
	eq(#out, 3)
	eq(out[1].key, "mounts")
	eq(out[1].entries[1].name, "Gamma")
	eq(out[1].entries[2].name, "Alpha")
	eq(out[1].entries[3].name, "Beta")
	eq(out[2].key, "pets")
	eq(out[3].key, "achievements")
	eq(out[3].entries[1].name, "A")
	eq(out[3].entries[2].name, "C")
	eq(out[3].entries[3].name, "B")
end)

test("sections: hidden kinds, collapsed and empty", function()
	local out = ns.Collect_Sections({
		{ kind = "mount", name = "A" },
		{ kind = "pet", name = "B" },
	}, { show = { mounts = true, pets = false, achievements = true }, collapsed = { mounts = true } })
	eq(#out, 1)
	eq(out[1].key, "mounts")
	eq(out[1].collapsed, true)
	eq(#out[1].entries, 1)
end)

test("zone toast text", function()
	eq(ns.Collect_ZoneToastText({ mounts = 2, pets = 1, achievements = 18 }), "2 mounts, 1 pet, 18 achievements left")
	eq(ns.Collect_ZoneToastText({ mounts = 0, pets = 3, achievements = 0 }), "3 pets left")
	eq(ns.Collect_ZoneToastText({ mounts = 1, pets = 0, achievements = 1 }), "1 mount, 1 achievement left")
	eq(ns.Collect_ZoneToastText({ mounts = 0, pets = 0, achievements = 0 }), nil)
end)

test("counts by kind", function()
	local c = ns.Collect_Counts({ { kind = "mount" }, { kind = "mount" }, { kind = "ach" } })
	eq(c.mounts, 2)
	eq(c.pets, 0)
	eq(c.achievements, 1)
end)

-- A non-English client: the labels come from Blizzard's globals (fake esES and zhCN texts here).
local function LoadWith(globals)
	for k, v in pairs(globals) do
		_G[k] = v
	end
	local loc = {}
	assert(loadfile("Tomte/Modules/Collect/Data.lua"))("Tomte", loc)
	for k in pairs(globals) do
		_G[k] = nil
	end
	return loc
end

test("localized labels map to the same keys", function()
	local es = LoadWith({ ZONE_COLON = "Zona:", BATTLE_PET_SOURCE_1 = "Botín", BATTLE_PET_SOURCE_5 = "Duelo de mascotas",
		COSTS_LABEL = "Coste:", PLAYER_DIFFICULTY2 = "Heroico", TRANSMOG_SOURCE_4 = "Botín mundial" })
	local s = es.Collect_ParseSource("|cFFFFD200Botín: |rKazzak|n|cFFFFD200Zona: |rRuinas de Lordaeron (Heroico)"
		.. "|n|cFFFFD200Coste:|r 5" .. GOLD)
	eq(s.lines[1].label, "drop")
	eq(s.lines[2].label, "zone")
	has(s.zones, "ruinas de lordaeron")
	eq(s.drop, "Kazzak")
	eq(s.line, "Botín: Kazzak (Heroico) · 5" .. GOLD)
	local p = es.Collect_ParseSource("|cFFFFD200Duelo de mascotas: |rNagrand, Tanaris")
	has(p.zones, "nagrand")
	eq(p.line, "Wild pet battle")
	eq(es.Collect_ParseSource("|cFFFFD200Botín: |rBotín mundial|n|cFFFFD200Zona: |rX").drop, nil, "world drop")
	eq(es.Collect_ParseSource("|cFFFFD200Drop: |rDoomwalker|n|cFFFFD200Zone: |rTanaris").zones[1], "tanaris",
		"English labels still work")
	local zh = LoadWith({ ZONE_COLON = "区域：" })
	has(zh.Collect_ParseSource("|cFFFFD200区域：|r塔纳利斯").zones, "塔纳利斯", "full-width colon")
end)

print(failures == 0 and "all passed" or (failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
