-- Run from the AddOns folder: lua Tomte/tests/test_gear.lua
local ns = {}
assert(loadfile("Tomte/Modules/Gear/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Gear/Advice.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Gear/Scales.lua"))("Tomte", ns)

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
local function has(list, pattern)
	for _, s in ipairs(list) do
		if s:find(pattern) then
			return true
		end
	end
	error("no reason matching '" .. pattern .. "' in {" .. table.concat(list, " | ") .. "}", 2)
end

local nextID = 0
-- An item: primary amount + one secondary, at an item level. Fields override.
local function item(loc, agi, secondary, extra)
	nextID = nextID + 1
	local d = {
		link = "item:" .. nextID, itemID = nextID, equipLoc = loc, classID = 4, subclassID = 3, ilvl = 300,
		stats = { PRIMARY = agi and { AGI = agi } or nil, HASTE = secondary },
	}
	for k, v in pairs(extra or {}) do
		d[k] = v
	end
	return d
end

local CTX = { primary = "AGI", weights = ns.Gear_DefaultWeights("AGI"), armorSubclass = 3, specOK = true }

local function gearset()
	return {
		[1] = item("INVTYPE_HEAD", 100, 100),
		[5] = item("INVTYPE_CHEST", 100, 100),
		[11] = item("INVTYPE_FINGER", nil, 200),
		[12] = item("INVTYPE_FINGER", nil, 150),
		[13] = item("INVTYPE_TRINKET", 100, nil),
		[16] = item("INVTYPE_WEAPON", 100, 100, { classID = 2 }),
		[17] = item("INVTYPE_WEAPON", 100, 100, { classID = 2 }),
	}
end

-------------------------------------------------------------------------------------------------- weights / stats

test("ParsePawn: Raidbots string", function()
	local r = ns.Gear_ParsePawn('( Pawn: v1: "Raidbots-Bm": Class=Hunter, Spec=BeastMastery, Agility=1.00, '
		.. 'CritRating=0.61, HasteRating=0.72, MasteryRating=0.55, Versatility=0.50, Dps=2.1, Ap=0.9 )')
	eq(r.name, "Raidbots-Bm")
	eq(r.class, "HUNTER")
	eq(r.spec, 1)
	eq(r.weights.AGI, 1)
	eq(r.weights.HASTE, 0.72)
	eq(r.weights.DPS, 2.1)
	eq(r.weights.Ap, nil)
end)

test("ParsePawn: class names with two words, spec number", function()
	local r = ns.Gear_ParsePawn('( Pawn: v1: "x": Class=DeathKnight, Spec=2, Strength=1 )')
	eq(r.class, "DEATHKNIGHT")
	eq(r.spec, 2)
end)

test("ParsePawn: garbage and missing parts are rejected", function()
	local r, err = ns.Gear_ParsePawn("hello")
	eq(r, nil)
	assert(err:find("Pawn string"))
	r, err = ns.Gear_ParsePawn('( Pawn: v1: "x": Class=Hunter, Spec=BeastMastery )')
	eq(r, nil)
	assert(err:find("No stat weights"))
	r, err = ns.Gear_ParsePawn('( Pawn: v1: "x": Agility=1 )')
	eq(r, nil)
	assert(err:find("class and spec"))
	r, err = ns.Gear_ParsePawn('( Pawn: v1: "x": Class=Hunter, Spec=Tank, Agility=1 )')
	eq(r, nil)
	assert(err:find("Unknown spec"))
	eq((ns.Gear_ParsePawn(nil)), nil)
end)

test("NormalizeStats: keys, hybrids, unknowns", function()
	local s = ns.Gear_NormalizeStats({
		ITEM_MOD_AGILITY_SHORT = 10, ITEM_MOD_HASTE_RATING_SHORT = 5, ITEM_MOD_VERSATILITY = 3,
		ITEM_MOD_STRENGTH_AGILITY_INTELLECT_SHORT = 7, EMPTY_SOCKET_PRISMATIC = 1, RESISTANCE0_NAME = 50,
	})
	eq(s.PRIMARY.AGI, 17)
	eq(s.PRIMARY.STR, 7)
	eq(s.PRIMARY.INT, 7)
	eq(s.HASTE, 5)
	eq(s.VERS, 3)
	eq(s.ARMOR, 50)
	eq(s.EMPTY_SOCKET_PRISMATIC, nil)
end)

test("ParseStatText: gem lines", function()
	local s = ns.Gear_ParseStatText("+12 Haste and +5 Mastery")
	eq(s.HASTE, 12)
	eq(s.MASTERY, 5)
	s = ns.Gear_ParseStatText("+13 Critical Strike")
	eq(s.CRIT, 13)
	s = ns.Gear_ParseStatText("+20 Agility, +4 Versatility")
	eq(s.PRIMARY.AGI, 20)
	eq(s.VERS, 4)
	s = ns.Gear_ParseStatText("Your spells sometimes do things")
	eq(next(s), nil)
end)

test("Score: only the spec's primary, weights, gems, empty sockets", function()
	local w = { AGI = 1, STR = 1, HASTE = 0.5 }
	local d = { stats = { PRIMARY = { AGI = 100, STR = 100 }, HASTE = 40, CRIT = 40 } }
	eq(ns.Gear_Score(d, w, "AGI", 0), 120)
	d.gemStats = { HASTE = 10 }
	d.gems, d.sockets = 1, 2
	eq(ns.Gear_Score(d, w, "AGI", 6), 120 + 5 + 6)
end)

test("GemValue: average per gem over equipped", function()
	local w = { AGI = 1, HASTE = 0.5 }
	local eqd = { [1] = { gems = 1, gemStats = { HASTE = 20 } }, [2] = { gems = 2, gemStats = { HASTE = 40 } } }
	eq(ns.Gear_GemValue(eqd, w, "AGI"), 10)
	eq(ns.Gear_GemValue({}, w, "AGI"), 0)
end)

test("StripLink: enchant and gems cleared, bonus IDs kept", function()
	local link = "|cnIQ4:|Hitem:12345:7000:213:214::::::90:253::28:2:1:2|h[Thing]|h|r"
	eq(ns.Gear_StripLink(link), "|cnIQ4:|Hitem:12345:::::::::90:253::28:2:1:2|h[Thing]|h|r")
end)

test("LinkInfo: enchant and gem count", function()
	local enchanted, gems = ns.Gear_LinkInfo("|cnIQ4:|Hitem:12345:7000:213:0:214:::::90|h[x]|h|r")
	eq(enchanted, true)
	eq(gems, 2)
	enchanted, gems = ns.Gear_LinkInfo("|cnIQ4:|Hitem:12345::::::::90|h[x]|h|r")
	eq(enchanted, false)
	eq(gems, 0)
end)

test("ParseUnique", function()
	local u = ns.Gear_ParseUnique("Unique-Equipped: Embellished (2)")
	eq(u.category, "Embellished")
	eq(u.max, 2)
	eq(ns.Gear_ParseUnique("Unique-Equipped").max, 1)
	eq(ns.Gear_ParseUnique("Binds when picked up"), nil)
end)

-------------------------------------------------------------------------------------------------- targets

test("Compare: rings against the weaker ring", function()
	local e = gearset()
	local t = ns.Gear_Target(item("INVTYPE_FINGER", nil, 170), e)
	eq(t.mode, "weaker")
	local v = ns.Gear_Evaluate(item("INVTYPE_FINGER", nil, 170, { ilvl = 310 }), e, CTX)
	eq(v.kind, "upgrade") -- 85 vs 75 (the 150 ring)
end)

test("Compare: 2H vs MH+OH", function()
	local e = gearset()
	local t = ns.Gear_Target(item("INVTYPE_2HWEAPON", 200, 200), e)
	eq(t.mode, "sum")
	local v = ns.Gear_Evaluate(item("INVTYPE_2HWEAPON", 250, 250, { classID = 2, ilvl = 320 }), e, CTX)
	eq(v.kind, "upgrade") -- 375 vs 300
end)

test("Compare: 1H with 2H worn", function()
	local e = { [16] = item("INVTYPE_2HWEAPON", 200, 200) }
	local v = ns.Gear_Evaluate(item("INVTYPE_WEAPON", 100, 100), e, CTX)
	eq(v.kind, "pair")
	eq(ns.Gear_IsCleanUpgrade(v), false)
end)

test("Compare: Titan's Grip", function()
	local e = { [16] = item("INVTYPE_2HWEAPON", 200, 200), [17] = item("INVTYPE_2HWEAPON", 150, 150) }
	local t = ns.Gear_Target(item("INVTYPE_2HWEAPON", 200, 200), e)
	eq(t.mode, "weaker")
	local v = ns.Gear_Evaluate(item("INVTYPE_2HWEAPON", 190, 190, { ilvl = 320 }), e, CTX)
	eq(v.kind, "upgrade") -- vs the 150 one
end)

test("Compare: 1H while dual wielding uses the weaker hand; off-hand slot empty", function()
	local e = gearset()
	eq(ns.Gear_Target(item("INVTYPE_WEAPON", 1, 1), e).mode, "weaker")
	e[17] = nil
	eq(ns.Gear_Target(item("INVTYPE_HOLDABLE", 1, 1), e).mode, "empty")
	eq(ns.Gear_Target(item("INVTYPE_WEAPON", 1, 1), e).slots[1], 16)
end)

test("Empty slot: upgrade, not a huge %", function()
	local v = ns.Gear_Evaluate(item("INVTYPE_CLOAK", 50, 50), gearset(), CTX)
	eq(v.kind, "empty")
	eq(v.pct, nil)
	eq(ns.Gear_IsCleanUpgrade(v), true)
end)

test("Worn item with no stats: never \"slot empty\"", function()
	local e = gearset()
	e[8] = item("INVTYPE_FEET", nil, nil, { ilvl = 105 })
	local statless = item("INVTYPE_FEET", nil, nil, { ilvl = 71 })
	local v = ns.Gear_Evaluate(statless, e, CTX)
	eq(v.kind, "ilvl")
	eq(v.ilvlDiff, -34)
	eq(ns.Gear_IsCleanUpgrade(v), false)
	local text, color = ns.Gear_Headline(v)
	assert(text:find("keep yours"), text)
	eq(color, "red")
	v = ns.Gear_Evaluate(item("INVTYPE_FEET", 50, 50), e, CTX)
	eq(v.kind, "noStats")
	eq(v.pct, nil)
	eq(ns.Gear_IsCleanUpgrade(v), true)
	eq(#ns.Gear_PickReveals({ { verdict = v } }, 2), 1)
	-- a real item worn: a statless candidate is a plain downgrade
	e[8] = item("INVTYPE_FEET", 17, 24, { ilvl = 105 })
	eq(ns.Gear_Evaluate(statless, e, CTX).kind, "downgrade")
end)

test("Hovering an equipped item: no verdict", function()
	local e = gearset()
	eq(ns.Gear_Evaluate(e[1], e, CTX), nil)
end)

test("Not equippable: no verdict", function()
	eq(ns.Gear_Evaluate(item("INVTYPE_BODY", 1, 1), gearset(), CTX), nil)
end)

-------------------------------------------------------------------------------------------------- verdicts

test("Upgrade, downgrade, sidegrade", function()
	local e = gearset()
	eq(ns.Gear_Evaluate(item("INVTYPE_HEAD", 120, 120, { ilvl = 310 }), e, CTX).kind, "upgrade")
	eq(ns.Gear_Evaluate(item("INVTYPE_HEAD", 80, 80, { ilvl = 290 }), e, CTX).kind, "downgrade")
	eq(ns.Gear_Evaluate(item("INVTYPE_HEAD", 100, 101, { ilvl = 310 }), e, CTX).kind, "sidegrade")
end)

test("Stat mix: same level, small difference is a sidegrade with a sim hint", function()
	local e = gearset()
	local ctx = { primary = "AGI", weights = { AGI = 1, HASTE = 0.3, CRIT = 0.8 }, armorSubclass = 3, specOK = true }
	-- old head: 100 + 30 = 130; new: 100 AGI + 33 CRIT = 126.4 -> -2.8%, same ilvl
	local cand = item("INVTYPE_HEAD", 100, nil, { stats = { PRIMARY = { AGI = 100 }, CRIT = 33 } })
	local v = ns.Gear_Evaluate(cand, e, ctx)
	eq(v.kind, "sidegrade")
	eq(v.statMix, true)
	has(v.reasons, "sim to be sure")
	-- the same item two ranks higher is judged normally
	cand.ilvl = 308
	eq(ns.Gear_Evaluate(cand, e, ctx).statMix, nil)
end)

test("Not for you: armor type (cloak exempt), main stat, spec, red tooltip line", function()
	local e = gearset()
	local v = ns.Gear_Evaluate(item("INVTYPE_CHEST", 200, 200, { subclassID = 4 }), e, CTX)
	eq(v.kind, "notForYou")
	assert(v.why:find("Plate"))
	eq(ns.Gear_Evaluate(item("INVTYPE_CLOAK", 200, 200, { subclassID = 1 }), e, CTX).kind, "empty")
	local int = item("INVTYPE_HEAD", nil, 200, { stats = { PRIMARY = { INT = 200 } } })
	eq(ns.Gear_Evaluate(int, e, CTX).why, "wrong main stat")
	local ctx = { primary = "AGI", weights = CTX.weights, armorSubclass = 3, specOK = false }
	eq(ns.Gear_Evaluate(item("INVTYPE_HEAD", 200, 200), e, ctx).why, "not for your spec")
	eq(ns.Gear_Evaluate(item("INVTYPE_HEAD", 200, 200, { redText = "Requires Level 90" }), e, CTX).why,
		"Requires Level 90")
end)

test("Trinket and effect items: can't judge", function()
	local e = gearset()
	local v = ns.Gear_Evaluate(item("INVTYPE_TRINKET", 300, nil), e, CTX)
	eq(v.kind, "simIt")
	has(v.reasons, "/tomte gear sim")
	eq(ns.Gear_IsCleanUpgrade(v), false)
	v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 300, 300, { effect = "Use: things" }), e, CTX)
	eq(v.kind, "simIt")
end)

test("Losing an effect: can't judge, sim both", function()
	local e = gearset()
	e[1].effect = "Equip: your attacks sometimes explode"
	local v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { ilvl = 320 }), e, CTX)
	eq(v.kind, "simIt")
	eq(v.reasons[1], "Your current gear has an Equip effect that stats can't value")
	eq(v.reasons[2], "Sim both to know: /tomte gear sim")
	eq(ns.Gear_IsCleanUpgrade(v), false)
	eq((ns.Gear_Headline(v)), "Can't judge (stats alone +50.0%)")
	for _, r in ipairs(v.reasons) do
		assert(not r:find("Loses:"), "no pasted effect text")
	end
end)

test("Losing a Use effect", function()
	local e = gearset()
	e[1].effect = "Use: open the device"
	local v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { ilvl = 320 }), e, CTX)
	eq(v.reasons[1], "Your current gear has a Use effect that stats can't value")
end)

test("Losing an effect while gaining one: one sim line", function()
	local e = gearset()
	e[1].effect = "Equip: old"
	local v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { effect = "Equip: new" }), e, CTX)
	eq(v.kind, "simIt")
	local sims = 0
	for _, r in ipairs(v.reasons) do
		if r:find("/tomte gear sim") then
			sims = sims + 1
		end
	end
	eq(sims, 1)
	has(v.reasons, "has an Equip effect that stats can't value")
end)

test("Losing a socket names the gem", function()
	local e = gearset()
	e[1].sockets = 1
	e[1].gemText = "+10 Critical Strike and +3 Haste"
	local v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { ilvl = 320 }), e, CTX)
	has(v.reasons, "^Loses a socket %(your gem: %+10 Critical Strike and %+3 Haste%)$")
	e[1].sockets, e[1].gemText = 2, nil
	v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { ilvl = 320 }), e, CTX)
	has(v.reasons, "^Loses 2 sockets$")
	v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { ilvl = 320, sockets = 2 }), e, CTX)
	for _, r in ipairs(v.reasons) do
		assert(not r:find("Loses"), "same sockets: nothing lost")
	end
end)

test("Unique: same ring is compared against itself", function()
	local e = gearset()
	e[11].unique = { max = 1 } -- the better ring (200)
	local cand = item("INVTYPE_FINGER", nil, 210, { itemID = e[11].itemID, unique = { max = 1 }, ilvl = 320 })
	local t = ns.Gear_Target(cand, e)
	eq(t.mode, "single")
	eq(t.slots[1], 11)
	eq(ns.Gear_Evaluate(cand, e, CTX).kind, "upgrade") -- +5% over the same ring, not over the weaker one
end)

test("Unique: embellishment limit", function()
	local e = gearset()
	e[1].unique = { category = "Embellished", max = 2 }
	e[5].unique = { category = "Embellished", max = 2 }
	local cand = item("INVTYPE_FINGER", nil, 400, { unique = { category = "Embellished", max = 2 } })
	local v = ns.Gear_Evaluate(cand, e, CTX)
	eq(v.kind, "notForYou")
	assert(v.why:find("Embellished %(2%)"))
	-- replacing one of the two embellished items is fine
	local head = item("INVTYPE_HEAD", 120, 120, { unique = { category = "Embellished", max = 2 }, effect = "Equip: x" })
	eq(ns.Gear_Evaluate(head, e, CTX).kind, "simIt")
end)

test("Loses an embellishment", function()
	local e = gearset()
	e[1].unique = { category = "Embellished", max = 2 }
	e[1].effect = "Equip: x"
	local v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 200, 200, { ilvl = 330 }), e, CTX)
	eq(v.kind, "upgradeBut")
	has(v.reasons, "Loses an embellishment")
end)

local function tierSet(n)
	local e = gearset()
	local slots = { 1, 3, 5, 7, 10 }
	local locs = { "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_LEGS", "INVTYPE_HAND" }
	for i = 1, 5 do
		e[slots[i]] = item(locs[i], 100, 100, { setID = i <= n and 77 or nil })
	end
	return e
end

test("Breaks 4-set", function()
	local v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { ilvl = 330 }), tierSet(4), CTX)
	eq(v.kind, "upgradeBut")
	has(v.reasons, "Breaks your 4%-set %(4 > 3%)")
end)

test("Completes 4-set: lifts a small downgrade", function()
	local v = ns.Gear_Evaluate(item("INVTYPE_LEGS", 97, 97, { setID = 77, ilvl = 290 }), tierSet(3), CTX)
	eq(v.kind, "upgradeBut")
	has(v.reasons, "Completes your 4%-set")
	local h = ns.Gear_Headline(v)
	assert(h:find("set bonus"))
	-- a big downgrade isn't lifted
	eq(ns.Gear_Evaluate(item("INVTYPE_LEGS", 50, 50, { setID = 77 }), tierSet(3), CTX).kind, "downgrade")
end)

test("Catalyst note on a non-set tier-slot item with an upgrade track", function()
	local cand = item("INVTYPE_LEGS", 150, 150, { ilvl = 330, upgrade = { cur = 2, max = 6, maxIlvl = 308, track = "Champion" } })
	local v = ns.Gear_Evaluate(cand, tierSet(3), CTX)
	has(v.reasons, "catalysed into tier %(completes 4%-set%)")
	has(v.reasons, "Champion 2/6, upgrades to 308")
	-- no set worn: plain note
	v = ns.Gear_Evaluate(cand, gearset(), CTX)
	has(v.reasons, "^Can be catalysed into tier$")
	-- below Veteran (Explorer, Adventurer, leveling gear without a track): the Catalyst won't take it
	for _, track in ipairs({ "Explorer", "Adventurer", false }) do
		cand.upgrade.track = track or nil
		v = ns.Gear_Evaluate(cand, gearset(), CTX)
		for _, r in ipairs(v.reasons) do
			assert(not r:find("catalysed"), tostring(track) .. ": " .. r)
		end
	end
end)

test("Enchant and socket reasons", function()
	local e = gearset()
	e[1].enchanted = true
	local v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { ilvl = 330, sockets = 1 }), e, CTX)
	eq(v.kind, "upgrade") -- enchant is information, not a warning
	has(v.reasons, "re%-enchant")
	has(v.reasons, "%+1 socket")
end)

test("Headlines say what to do", function()
	eq((ns.Gear_Headline({ kind = "upgrade", pct = 2.44 })), "Upgrade +2.4%: equip it")
	eq((ns.Gear_Headline({ kind = "downgrade", pct = -3.2 })), "Downgrade -3.2%: keep yours")
	eq((ns.Gear_Headline({ kind = "notForYou", why = "wrong main stat" })), "Not for you: wrong main stat")
	local _, color = ns.Gear_Headline({ kind = "simIt", pct = -1.5 })
	eq(color, "orange")
end)

-------------------------------------------------------------------------------------------------- advice

test("ResolveWeights: imported > built-in > fallback", function()
	local builtin = { weights = { AGI = 1, HASTE = 0.8 }, label = "guide" }
	local saved = { name = "Raidbots", weights = { AGI = 1, CRIT = 0.9 } }
	local w, source, label = ns.Gear_ResolveWeights(saved, builtin, "AGI")
	eq(source, "imported")
	eq(label, "Raidbots")
	eq(w.CRIT, 0.9)
	w, source = ns.Gear_ResolveWeights(nil, builtin, "AGI")
	eq(source, "builtin")
	eq(w.HASTE, 0.8)
	w, source = ns.Gear_ResolveWeights(nil, nil, "STR")
	eq(source, "none")
	eq(w.STR, 1)
	eq(w.HASTE, 0.5)
end)

test("WeightsHint: only at max level, once per spec, again when the season moves on", function()
	local b = { season = 1 }
	-- Below max level (or level unknown): nothing, built-in is fine while leveling.
	eq(ns.Gear_WeightsHint("builtin", b, nil, 1, 79, 80), nil)
	eq(ns.Gear_WeightsHint("builtin", b, nil, 1, nil, 80), nil)
	eq(ns.Gear_WeightsHint("builtin", b, nil, 1, 80, nil), nil)
	local kind, seen = ns.Gear_WeightsHint("builtin", b, nil, 1, 80, 80)
	eq(kind, "max")
	eq(seen, "max")
	eq(ns.Gear_WeightsHint("builtin", b, seen, 1, 80, 80), nil)
	-- The old any-level hint doesn't count as told.
	eq(select(1, ns.Gear_WeightsHint("builtin", b, "builtin", 1, 80, 80)), "max")
	kind, seen = ns.Gear_WeightsHint("builtin", b, seen, 2, 80, 80)
	eq(kind, "stale")
	eq(seen, "stale:2")
	eq(ns.Gear_WeightsHint("builtin", b, seen, 2, 80, 80), nil)
	eq(select(1, ns.Gear_WeightsHint("builtin", b, seen, 3, 80, 80)), "stale")
	eq(ns.Gear_WeightsHint("builtin", b, nil, 2, 70, 80), nil, "no stale hint below max level")
	-- Unknown season: only the first-time hint.
	eq(ns.Gear_WeightsHint("builtin", b, nil, nil, 80, 80), "max")
	eq(ns.Gear_WeightsHint("builtin", b, "max", nil, 80, 80), nil)
	-- Imported or no weights: never.
	eq(ns.Gear_WeightsHint("imported", b, nil, 2, 80, 80), nil)
	eq(ns.Gear_WeightsHint("none", nil, nil, 2, 80, 80), nil)
end)

test("SimSuggested: built-in at max level only", function()
	eq(ns.Gear_SimSuggested("builtin", 80, 80), true)
	eq(ns.Gear_SimSuggested("builtin", 79, 80), false)
	eq(ns.Gear_SimSuggested("imported", 80, 80), false)
	eq(ns.Gear_SimSuggested("none", 80, 80), false)
	eq(ns.Gear_SimSuggested("builtin", 80, nil), false)
end)

test("MigrateHinted: old per-spec keys of this class move to the character", function()
	local hinted = { [66] = "builtin", [253] = "stale:37", ["Player-1"] = { [70] = "max" } }
	local mine = ns.Gear_MigrateHinted(hinted, "Player-2", { [65] = true, [66] = true, [70] = true })
	eq(mine[66], "builtin")
	eq(hinted["Player-2"], mine)
	eq(hinted[66], nil)
	eq(hinted[253], "stale:37", "another class's key waits")
	eq(hinted["Player-1"][70], "max", "other characters untouched")
	-- A value already on the character wins.
	hinted = { [66] = "builtin", ["Player-2"] = { [66] = "max" } }
	eq(ns.Gear_MigrateHinted(hinted, "Player-2", { [66] = true })[66], "max")
	eq(hinted[66], nil)
end)

test("WeightsFor: this or another character's imported weights, else built-in", function()
	local scales = { specs = { [65] = { label = "guide priority, S2", weights = { INT = 1, MASTERY = 0.7 } } } }
	local saved = { ["Player-1"] = { [65] = { name = "Mine", weights = { INT = 1, HASTE = 0.9 } } } }
	local w, source, label = ns.Gear_WeightsFor(saved, "Player-1", 65, "INT", scales)
	eq(source, "imported")
	eq(label, "Mine")
	eq(w.HASTE, 0.9)
	w, source, label = ns.Gear_WeightsFor(saved, "Player-2", 65, "INT", scales)
	eq(source, "builtin")
	eq(label, "guide priority, S2")
	w, source = ns.Gear_WeightsFor(saved, "Player-2", 999, "AGI", scales)
	eq(source, "none")
	eq(w.AGI, 1)
end)

test("SourceText: guide weights ask for a sim", function()
	eq(ns.Gear_SourceText("builtin", "guide priority, Midnight S2"),
		"built-in, guide priority, Midnight S2: import a sim for better")
	eq(ns.Gear_SourceText("builtin", "sims, Midnight S2"), "built-in, sims, Midnight S2")
	eq(ns.Gear_SourceText("imported", "Raidbots"), 'imported "Raidbots"')
	eq(ns.Gear_SourceText("none", nil), nil)
	eq(ns.Gear_IsGuideLabel("sims, guide priority"), false)
end)

local GEMS = {
	{ itemID = 1, name = "Crit Gem", stats = { CRIT = 10, VERS = 5 } },
	{ itemID = 2, name = "Haste Gem", stats = { HASTE = 10, MASTERY = 5 } },
	{ itemID = 3, name = "Agi Gem", stats = { PRIMARY = { AGI = 6 } } },
}

test("BestGem: highest value under the weights", function()
	local best, value = ns.Gear_BestGem(GEMS, { AGI = 1, HASTE = 0.9, MASTERY = 0.6, CRIT = 0.5, VERS = 0.4 }, "AGI")
	eq(best.name, "Haste Gem")
	eq(value, 12)
	best = ns.Gear_BestGem(GEMS, { AGI = 1, CRIT = 1, VERS = 1 }, "AGI")
	eq(best.name, "Crit Gem")
	best = ns.Gear_BestGem(GEMS, { STR = 3 }, "STR") -- nothing scores: no advice
	eq(best, nil)
	eq(ns.Gear_BestGem({}, { AGI = 1 }, "AGI"), nil)
end)

test("StatLabel: largest first", function()
	eq(ns.Gear_StatLabel({ MASTERY = 5, HASTE = 10 }), "Haste, Mastery")
	eq(ns.Gear_StatLabel({ PRIMARY = { AGI = 6 } }), "Agility")
end)

test("GemLines: empty sockets and worse gems on worn items", function()
	local w = { AGI = 1, HASTE = 1, MASTERY = 0.5, CRIT = 0.2, VERS = 0.2 }
	local best, value = ns.Gear_BestGem(GEMS, w, "AGI")
	local stats = function(id)
		for _, g in ipairs(GEMS) do
			if g.itemID == id then
				return g.stats
			end
		end
	end
	local lines = ns.Gear_GemLines({ sockets = 2, gems = 1, gemIDs = { 1 } }, best, value, true, stats, w, "AGI")
	eq(#lines, 2)
	eq(lines[1], "Empty socket: best gem Haste Gem (Haste, Mastery)")
	eq(lines[2], "Gem: Haste Gem is better for your spec")
	-- Not worn: no gem nagging. Best gem socketed: nothing.
	lines = ns.Gear_GemLines({ sockets = 1, gems = 1, gemIDs = { 1 } }, best, value, false, stats, w, "AGI")
	eq(#lines, 0)
	lines = ns.Gear_GemLines({ sockets = 2, gems = 2, gemIDs = { 2, 2 } }, best, value, true, stats, w, "AGI")
	eq(#lines, 0)
	lines = ns.Gear_GemLines({ sockets = 2, gems = 0, gemIDs = {} }, best, value, false, stats, w, "AGI")
	eq(lines[1], "2 empty sockets: best gem Haste Gem (Haste, Mastery)")
	-- Unloaded gem: no claim. Within the slack: fine.
	lines = ns.Gear_GemLines({ sockets = 1, gems = 1, gemIDs = { 99 } }, best, value, true, stats, w, "AGI")
	eq(#lines, 0)
	local close = { HASTE = 9.8, MASTERY = 5 }
	lines = ns.Gear_GemLines({ sockets = 1, gems = 1, gemIDs = { 7 } }, best, value, true, function()
		return close
	end, w, "AGI")
	eq(#lines, 0)
	eq(#ns.Gear_GemLines({ sockets = 1, gems = 0 }, nil, 0, true, stats, w, "AGI"), 0)
	lines = ns.Gear_GemLines({ sockets = 1, gems = 0 }, best, value, false, stats, w, "AGI", "Eversong Diamond")
	eq(lines[2], "Or your one Eversong Diamond (sim which)")
end)

test("WearsGem", function()
	local e = { [1] = { gemIDs = { 5 } }, [2] = {} }
	eq(ns.Gear_WearsGem(e, { [5] = true }), true)
	eq(ns.Gear_WearsGem(e, { [6] = true }), false)
end)

test("LinkGemIDs: socketed gems in order", function()
	local ids = ns.Gear_LinkGemIDs("|cnIQ4:|Hitem:12345:7000:213:0:214:::::90|h[x]|h|r")
	eq(#ids, 2)
	eq(ids[1], 213)
	eq(ids[2], 214)
	eq(#ns.Gear_LinkGemIDs("|cnIQ4:|Hitem:12345::::::::90|h[x]|h|r"), 0)
end)

test("Enchant slots: off-hand only when it's a weapon", function()
	eq(ns.Gear_EnchantSlot(1, "INVTYPE_HEAD"), true)
	eq(ns.Gear_EnchantSlot(9, "INVTYPE_WRIST"), false)
	eq(ns.Gear_EnchantSlot(17, "INVTYPE_WEAPON"), true)
	eq(ns.Gear_EnchantSlot(17, "INVTYPE_SHIELD"), false)
	eq(ns.Gear_EnchantSlot(17, "INVTYPE_HOLDABLE"), false)
end)

test("Audit: missing enchants and empty sockets", function()
	local e = {
		[1] = { equipLoc = "INVTYPE_HEAD", enchanted = false, sockets = 1, gems = 0 },
		[3] = { equipLoc = "INVTYPE_SHOULDER", enchanted = true },
		[9] = { equipLoc = "INVTYPE_WRIST", enchanted = false, sockets = 1, gems = 1 },
		[11] = { equipLoc = "INVTYPE_FINGER", enchanted = false, sockets = 2, gems = 0 },
		[17] = { equipLoc = "INVTYPE_SHIELD", enchanted = false },
	}
	local a = ns.Gear_Audit(e)
	eq(a.enchants, 2)
	eq(a.sockets, 3)
	eq(ns.Gear_AuditText(a), "2 missing enchants, 3 empty sockets")
	eq(ns.Gear_AuditText({ enchants = 1, sockets = 0 }), "1 missing enchant")
	eq(ns.Gear_AuditText({ enchants = 0, sockets = 0 }), nil)
	eq(ns.Gear_WornSlot("b", { [1] = { link = "a" }, [5] = { link = "b" } }), 5)
	eq(ns.Gear_WornSlot("c", { [1] = { link = "a" } }), nil)
end)

test("AuditList: one entry per slot with a problem, in slot order", function()
	local e = {
		[11] = { equipLoc = "INVTYPE_FINGER", enchanted = false, sockets = 2, gems = 0, link = "ring" },
		[2] = { equipLoc = "INVTYPE_NECK", enchanted = false, sockets = 1, gems = 0, link = "neck" },
		[3] = { equipLoc = "INVTYPE_SHOULDER", enchanted = true, link = "shoulder" },
		[9] = { equipLoc = "INVTYPE_WRIST", enchanted = true, sockets = 1, gems = 1, link = "wrist" },
	}
	local list = ns.Gear_AuditList(e)
	eq(#list, 2)
	eq(list[1].slot, 2)
	eq(list[1].enchant, false, "neck takes no enchant")
	eq(list[1].empty, 1)
	eq(list[1].link, "neck")
	eq(list[2].slot, 11)
	eq(list[2].enchant, true)
	eq(list[2].empty, 2)
	eq(ns.Gear_AuditEntryText(list[2]), "Not enchanted, 2 empty sockets")
	eq(ns.Gear_AuditEntryText({ enchant = true, empty = 0 }), "Not enchanted")
	eq(ns.Gear_AuditEntryText({ enchant = false, empty = 1 }), "1 empty socket")
	eq(#ns.Gear_AuditList({}), 0)
end)

-- Every spec's main stat (warcraft.wiki.gg SpecializationID, standard retail roles), to check Scales.lua against.
local SPEC_MAIN = {
	[71] = "STR", [72] = "STR", [73] = "STR", -- Warrior
	[65] = "INT", [66] = "STR", [70] = "STR", -- Paladin
	[253] = "AGI", [254] = "AGI", [255] = "AGI", -- Hunter
	[259] = "AGI", [260] = "AGI", [261] = "AGI", -- Rogue
	[256] = "INT", [257] = "INT", [258] = "INT", -- Priest
	[250] = "STR", [251] = "STR", [252] = "STR", -- Death Knight
	[262] = "INT", [263] = "AGI", [264] = "INT", -- Shaman
	[62] = "INT", [63] = "INT", [64] = "INT", -- Mage
	[265] = "INT", [266] = "INT", [267] = "INT", -- Warlock
	[268] = "AGI", [269] = "AGI", [270] = "INT", -- Monk
	[102] = "INT", [103] = "AGI", [104] = "AGI", [105] = "INT", -- Druid
	[577] = "AGI", [581] = "AGI", [1480] = "INT", -- Demon Hunter
	[1467] = "INT", [1468] = "INT", [1473] = "INT", -- Evoker
}
local HEALERS = { [65] = true, [256] = true, [257] = true, [264] = true, [270] = true, [105] = true, [1468] = true }

test("Scales: every spec, main stat 1 and right, four secondaries in (0, 1]", function()
	local count = 0
	for id, main in pairs(SPEC_MAIN) do
		count = count + 1
		local scale = ns.Gear_Scales.specs[id]
		assert(scale and type(scale.label) == "string", "no scale for " .. id)
		local n = 0
		for key, value in pairs(scale.weights) do
			n = n + 1
			if key == "AGI" or key == "STR" or key == "INT" then
				eq(key, main, "main stat of " .. id)
				eq(value, 1, "main stat weight of " .. id)
			else
				assert(key == "CRIT" or key == "HASTE" or key == "MASTERY" or key == "VERS", "odd key " .. key .. " in " .. id)
				assert(value > 0 and value <= 1, ("%s %s out of range in %d"):format(key, tostring(value), id))
			end
		end
		eq(n, 5, "main + four secondaries in " .. id)
		eq(scale.weights[main], 1, "main stat present in " .. id)
		if HEALERS[id] then
			assert(ns.Gear_IsGuideLabel(scale.label), "healer " .. id .. " should be labeled guide priority")
		end
	end
	eq(count, 40)
	for id in pairs(ns.Gear_Scales.specs) do
		assert(SPEC_MAIN[id], "unknown spec " .. id .. " in Scales")
	end
	eq(#ns.Gear_Scales.gems, 16)
	eq(#ns.Gear_Scales.diamonds, 8)
end)

test("OffspecLine: only plain upgrades", function()
	eq(ns.Gear_OffspecLine("Marksmanship", { kind = "upgrade", pct = 4 }), "Also an upgrade for Marksmanship +4.0%")
	eq(ns.Gear_OffspecLine("Marksmanship", { kind = "empty" }), nil)
	eq(ns.Gear_OffspecLine("Marksmanship", { kind = "upgradeBut", pct = 4 }), nil)
	eq(ns.Gear_OffspecLine("Marksmanship", nil), nil)
end)

test("Evaluate: best-gem value for empty sockets when given", function()
	local e = gearset()
	local cand = item("INVTYPE_HEAD", 100, 100, { sockets = 1 })
	local ctx = {}
	for k, v in pairs(CTX) do
		ctx[k] = v
	end
	ctx.gemValue = 20
	local v = ns.Gear_Evaluate(cand, e, ctx)
	eq(v.kind, "upgrade") -- 150 + 20 vs 150
end)

test("Rank: rings best / second best / bag has better", function()
	local ctx = { primary = "AGI", armorSubclass = 3, specID = 253 }
	local score = function(d)
		return ns.Gear_Score(d, CTX.weights, "AGI", 0)
	end
	local r1 = item("INVTYPE_FINGER", nil, 200)
	local r2 = item("INVTYPE_FINGER", nil, 150)
	local rank = ns.Gear_Rank(r1, 11, { r2 }, {}, ctx, score)
	eq(rank, 1)
	rank = ns.Gear_Rank(r2, 12, { r1 }, {}, ctx, score)
	eq(rank, 2)
	local bagRing = item("INVTYPE_FINGER", nil, 180)
	local better
	rank, better = ns.Gear_Rank(r2, 12, { r1 }, { bagRing, item("INVTYPE_HEAD", 100, 999) }, ctx, score)
	eq(rank, 3)
	eq(better, bagRing)
	-- Effect items, trinkets and things the spec can't use don't count.
	local fx = item("INVTYPE_FINGER", nil, 900, { effect = "Equip: stuff" })
	local cloth = item("INVTYPE_HEAD", 100, 999, { subclassID = 1 })
	local str = item("INVTYPE_FINGER", nil, 900, { specs = { [71] = true } })
	rank = ns.Gear_Rank(r1, 11, { r2 }, { fx, str }, ctx, score)
	eq(rank, 1)
	local head = item("INVTYPE_HEAD", 100, 100)
	eq(ns.Gear_Rank(head, 1, {}, { cloth }, ctx, score), 1)
	eq(ns.Gear_Rankable(item("INVTYPE_TRINKET", 100)), false)
end)

test("Rank: weapons only against the same kind", function()
	local ctx = { primary = "AGI", armorSubclass = 3 }
	local score = function(d)
		return ns.Gear_Score(d, CTX.weights, "AGI", 0)
	end
	local bow = item("INVTYPE_RANGED", 100, 100, { classID = 2 })
	local bigger2h = item("INVTYPE_2HWEAPON", 300, 300, { classID = 2 })
	local betterBow = item("INVTYPE_RANGED", 120, 100, { classID = 2 })
	eq(ns.Gear_Rank(bow, 16, {}, { bigger2h }, ctx, score), 1)
	eq(ns.Gear_Rank(bow, 16, {}, { betterBow }, ctx, score), 2)
end)

test("RankLine", function()
	eq(ns.Gear_RankLine("Beast Mastery", 1, 2), "Beast Mastery: your best")
	eq(ns.Gear_RankLine("Beast Mastery", 2, 2), "Beast Mastery: your second best")
	eq(ns.Gear_RankLine("Beast Mastery", 2, 1, "Bow"), "Beast Mastery: bag has better (Bow)")
	eq(select(2, ns.Gear_RankLine("Beast Mastery", 3, 2, "Ring")), "orange")
	eq(ns.Gear_RankLine("Beast Mastery", 2, 1, nil), nil)
end)

test("Unusable: armor, main stat, spec", function()
	local ctx = { primary = "AGI", armorSubclass = 3, specID = 253 }
	eq(ns.Gear_Unusable(item("INVTYPE_HEAD", 100, 1), ctx), nil)
	eq(ns.Gear_Unusable(item("INVTYPE_HEAD", 100, 1, { subclassID = 4 }), ctx), "wrong armor type (Plate)")
	eq(ns.Gear_Unusable(item("INVTYPE_FINGER", nil, 1, { specs = { [254] = true } }), ctx), "not for your spec")
	eq(ns.Gear_Unusable(item("INVTYPE_FINGER", nil, 1, { redText = "Requires level 90" }), ctx), "Requires level 90")
end)

-------------------------------------------------------------------------------------------------- reveal

test("Evaluate: verdict.slot is where the item goes (the weaker ring)", function()
	local e = gearset()
	local v = ns.Gear_Evaluate(item("INVTYPE_FINGER", nil, 170, { ilvl = 310 }), e, CTX)
	local weaker = ns.Gear_Score(e[11], CTX.weights, CTX.primary, 0) <= ns.Gear_Score(e[12], CTX.weights, CTX.primary, 0) and 11 or 12
	eq(v.slot, weaker)
end)

test("RevealTier: by item quality", function()
	eq(ns.Gear_RevealTier(nil), "common")
	eq(ns.Gear_RevealTier(2), "common")
	eq(ns.Gear_RevealTier(3), "rare")
	eq(ns.Gear_RevealTier(4), "epic")
	eq(ns.Gear_RevealTier(5), "legendary")
end)

test("PickReveals: clean upgrades over the minimum, best per slot, biggest first", function()
	local function it(kind, pct, slot)
		return { verdict = { kind = kind, pct = pct, slot = slot } }
	end
	local small = it("upgrade", 1.5, 1)
	local ring = it("upgrade", 4, 11)
	local betterRing = it("upgrade", 9, 11)
	local empty = it("empty", nil, 15)
	local list = ns.Gear_PickReveals({ small, ring, it("upgradeBut", 20, 5), it("simIt", 30, 13), betterRing,
		it("sidegrade", 0.5, 7), empty }, 2)
	eq(#list, 2)
	eq(list[1], empty)
	eq(list[2], betterRing)
	eq(#ns.Gear_PickReveals({ small }, 1), 1)
	eq(#ns.Gear_PickReveals({}, 0), 0)
end)

test("RevealLabel and RevealLine", function()
	eq(ns.Gear_RevealLabel({ kind = "upgrade", pct = 4.21 }), "Upgrade +4.2%")
	eq(ns.Gear_RevealLabel({ kind = "empty" }), "Upgrade for an empty slot")
	eq(ns.Gear_RevealLine(684, "Old Helm", 671), "Item level 684, replaces Old Helm (671)")
	eq(ns.Gear_RevealLine(684, nil, nil), "Item level 684")
	eq(ns.Gear_RevealLine(nil, nil, nil), nil)
end)

-------------------------------------------------------------------------------------------------- upgrades for alts

local SCALES = ns.Gear_Scales
local GEMS = { { itemID = 1, name = "Quick Gem", stats = { HASTE = 10 } } }

test("CharSpec and BuildContext: armor type, main stat and weight source per alt", function()
	eq(ns.Gear_CharSpec({ specID = 66 }), nil, "no main stat yet")
	eq(ns.Gear_CharSpec(nil), nil)
	local plate = { guid = "P", class = "PALADIN", specID = 66, spec = "Protection", primary = "STR" }
	local cloth = { guid = "C", class = "PRIEST", specID = 257, spec = "Holy", primary = "INT" }
	local leather = { guid = "L", class = "DRUID", specID = 105, spec = "Restoration", primary = "INT" }
	local saved = { L = { [105] = { name = "Resto sim", weights = { INT = 1, HASTE = 0.8 } } },
		C = { [999] = { name = "other spec", weights = { INT = 1 } } } }
	local ctx = ns.Gear_BuildContext(ns.Gear_CharSpec(plate), plate.guid, plate.class, saved, SCALES, GEMS)
	eq(ctx.armorSubclass, 4, "plate")
	eq(ctx.primary, "STR")
	eq(ctx.source, "builtin")
	eq(ctx.spec.name, "Protection")
	eq(ctx.best.name, "Quick Gem")
	ctx = ns.Gear_BuildContext(ns.Gear_CharSpec(cloth), cloth.guid, cloth.class, saved, SCALES, GEMS)
	eq(ctx.armorSubclass, 1, "cloth")
	eq(ctx.primary, "INT")
	eq(ctx.source, "builtin", "another spec's import doesn't count")
	ctx = ns.Gear_BuildContext(ns.Gear_CharSpec(leather), leather.guid, leather.class, saved, SCALES, {})
	eq(ctx.armorSubclass, 2, "leather")
	eq(ctx.source, "imported", "their own import")
	eq(ctx.label, "Resto sim")
	eq(ctx.best, nil, "no gems loaded")
	eq(ctx.gemValue, nil)
	ctx = ns.Gear_BuildContext({ id = 4242, name = "New", primary = "AGI" }, "X", "ROGUE", saved, SCALES, GEMS)
	eq(ctx.source, "none")
	eq(ctx.noWeights, true)
	eq(ns.Gear_BuildContext({ id = 1 }, "X", "ROGUE", saved, SCALES, GEMS), nil)
end)

test("BindState: from bind type, bound and warbound until equipped", function()
	eq(ns.Gear_BindState(2, nil, nil), "boe", "BoE link")
	eq(ns.Gear_BindState(2, false, false), "boe", "BoE in the bags")
	eq(ns.Gear_BindState(2, true, false), "soulbound", "BoE once worn")
	eq(ns.Gear_BindState(3, false, false), "boe", "bind on use")
	eq(ns.Gear_BindState(0, nil, nil), "boe", "never binds")
	eq(ns.Gear_BindState(1, nil, nil), "soulbound", "bind on pickup")
	eq(ns.Gear_BindState(1, true, false), "soulbound")
	eq(ns.Gear_BindState(4, nil, nil), "soulbound", "quest")
	eq(ns.Gear_BindState(8, true, false), "warbound")
	eq(ns.Gear_BindState(8, nil, nil), "warbound", "warbound link")
	eq(ns.Gear_BindState(7, true, false), "warbound", "account bound (heirloom kind)")
	eq(ns.Gear_BindState(9, false, true), "warboundUntilEquip")
	eq(ns.Gear_BindState(9, nil, nil), "warboundUntilEquip", "link")
	eq(ns.Gear_BindState(9, true, false), "soulbound", "warbound until equipped, and worn")
	eq(ns.Gear_BindState(nil, true, false), nil, "not loaded")
	eq(ns.Gear_BindState(nil, false, true), "warboundUntilEquip", "the location says so before the item loads")
end)

test("BindStateFromLines: the tooltip's own bind line", function()
	local known = { Soulbound = "soulbound", ["Binds when equipped"] = "boe", Warbound = "warbound",
		["Warbound until equipped"] = "warboundUntilEquip" }
	eq(ns.Gear_BindStateFromLines({ "Helm", "Soulbound", "Plate" }, known), "soulbound")
	eq(ns.Gear_BindStateFromLines({ "Helm", "Binds when equipped" }, known), "boe")
	eq(ns.Gear_BindStateFromLines({ "Helm", "Warbound until equipped" }, known), "warboundUntilEquip")
	eq(ns.Gear_BindStateFromLines({ "Helm", "Plate" }, known), nil)
end)

test("TransferRoute: warbound and BoE yes, soulbound no", function()
	eq(ns.Gear_TransferRoute("boe"), "mail")
	eq(ns.Gear_TransferRoute("warbound"), "warband")
	eq(ns.Gear_TransferRoute("warboundUntilEquip"), "warband")
	eq(ns.Gear_TransferRoute("soulbound"), nil)
	eq(ns.Gear_TransferRoute(nil), nil)
end)

test("AltsToJudge: not me, spec and gear stored, seen in 60 days, max level mode", function()
	local DAY, now = 86400, 1000 * 86400
	local function char(guid, name, level, seenDaysAgo, extra)
		local c = { guid = guid, name = name, level = level, seen = now - seenDaysAgo * DAY, gear = {}, specID = 1,
			primary = "INT" }
		for k, v in pairs(extra or {}) do
			c[k] = v
		end
		return c
	end
	local chars = {
		Me = char("Me", "Tomten", 80, 0),
		Mira = char("Mira", "Mira", 80, 10),
		Bea = char("Bea", "Bea", 42, 59),
		Old = char("Old", "Old", 80, 61),
		NoGear = char("NoGear", "Nogear", 80, 1, { gear = false }),
		NoSpec = char("NoSpec", "Nospec", 80, 1, { primary = false }),
		NoSeen = char("NoSeen", "Noseen", 80, 1, { seen = false }),
	}
	local list = ns.Gear_AltsToJudge(chars, "Me", now, "all", 80)
	eq(#list, 2)
	eq(list[1].name, "Bea", "by name")
	eq(list[2].name, "Mira")
	list = ns.Gear_AltsToJudge(chars, "Me", now, "max", 80)
	eq(#list, 1)
	eq(list[1].name, "Mira")
	eq(#ns.Gear_AltsToJudge(chars, "Me", now, "max", nil), 0, "max level unknown")
	eq(#ns.Gear_AltsToJudge(chars, "Me", now, "off", 80), 0)
end)

test("AltVerdict: the alt's level and worn items, not your red text", function()
	local ctx = { primary = "INT", weights = ns.Gear_DefaultWeights("INT"), armorSubclass = 1, specID = 257 }
	local function cloth(loc, int, haste, extra)
		local d = item(loc, nil, haste, extra)
		d.subclassID = 1
		d.stats.PRIMARY = { INT = int }
		return d
	end
	local worn = { [1] = cloth("INVTYPE_HEAD", 100, 100) }
	-- Red on your tooltip (another class, or too low): doesn't count for them.
	local cand = cloth("INVTYPE_HEAD", 120, 120, { redText = "Requires level 80", minLevel = 80 })
	local v = ns.Gear_AltVerdict(cand, worn, ctx, 80)
	eq(v.kind, "upgrade")
	eq(cand.redText, "Requires level 80", "the shared descriptor isn't changed")
	v = ns.Gear_AltVerdict(cand, worn, ctx, 70)
	eq(v.kind, "notForYou", "below the required level")
	has({ v.why }, "requires level 80")
	-- Their worn item is better: a downgrade for them.
	v = ns.Gear_AltVerdict(cand, { [1] = cloth("INVTYPE_HEAD", 200, 200) }, ctx, 80)
	eq(v.kind, "downgrade")
	-- Nothing worn there.
	v = ns.Gear_AltVerdict(cand, {}, ctx, 80)
	eq(v.kind, "empty")
	-- Their armor type and spec.
	local plate = item("INVTYPE_HEAD", nil, 120, { subclassID = 4 })
	plate.stats.PRIMARY = { INT = 120 }
	eq(ns.Gear_AltVerdict(plate, worn, ctx, 80).kind, "notForYou", "plate for a cloth alt")
	local other = cloth("INVTYPE_HEAD", 120, 120, { specs = { [256] = true } })
	eq(ns.Gear_AltVerdict(other, worn, ctx, 80).kind, "notForYou", "another spec's item")
	eq(ctx.specOK, false)
	local theirs = cloth("INVTYPE_HEAD", 120, 120, { specs = { [257] = true } })
	eq(ns.Gear_AltVerdict(theirs, worn, ctx, 80).kind, "upgrade")
	-- Already worn by them.
	eq(ns.Gear_AltVerdict(worn[1], worn, ctx, 80), nil)
end)

test("AltLines: best first, two lines, then +n more", function()
	local results = ns.Gear_SortAltUpgrades({
		{ name = "Bea", spec = "Fire", verdict = { kind = "upgrade", pct = 3.04 } },
		{ name = "Mira", spec = "Holy", verdict = { kind = "upgrade", pct = 8.21 } },
		{ name = "Tolvan", spec = "Arms", verdict = { kind = "empty" } },
		{ name = "Ada", spec = "Frost", verdict = { kind = "upgrade", pct = 3.04 } },
	})
	eq(results[1].name, "Tolvan", "an empty slot first")
	eq(results[2].name, "Mira")
	eq(results[3].name, "Ada", "ties by name")
	local lines, more = ns.Gear_AltLines(results, 2)
	eq(#lines, 2)
	eq(lines[1], "Upgrade for Tolvan (Arms): empty slot")
	eq(lines[2], "Upgrade for Mira (Holy): +8.2%")
	eq(more, "+2 more")
	lines, more = ns.Gear_AltLines({ results[2] }, 2)
	eq(#lines, 1)
	eq(more, nil)
	lines = ns.Gear_AltLines({}, 2)
	eq(#lines, 0)
	eq(ns.Gear_AltGain({ kind = "noStats" }), "theirs has no stats")
end)

test("Maybe an upgrade: unsure, but stats say upgrade", function()
	local e = gearset()
	-- effect item with better stats: maybe; with worse stats: no
	local v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { ilvl = 320, effect = "Use: things" }), e, CTX)
	eq(v.kind, "simIt")
	eq(ns.Gear_IsMaybeUpgrade(v), true)
	eq(ns.Gear_IsCleanUpgrade(v), false)
	v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 50, 50, { ilvl = 290, effect = "Use: things" }), e, CTX)
	eq(ns.Gear_IsMaybeUpgrade(v), false)
	-- trinket for an empty slot: no percentage, no arrow
	eq(ns.Gear_IsMaybeUpgrade(ns.Gear_Evaluate(item("INVTYPE_TRINKET", 300, nil), e, CTX)), false)
	-- clean upgrades and downgrades aren't maybes
	eq(ns.Gear_IsMaybeUpgrade(ns.Gear_Evaluate(item("INVTYPE_HEAD", 120, 120, { ilvl = 310 }), e, CTX)), false)
	eq(ns.Gear_IsMaybeUpgrade(ns.Gear_Evaluate(item("INVTYPE_HEAD", 80, 80, { ilvl = 290 }), e, CTX)), false)
	-- stat mix and upgrade-with-warning, by verdict
	eq(ns.Gear_IsMaybeUpgrade({ kind = "sidegrade", statMix = true, pct = 2.5 }), true)
	eq(ns.Gear_IsMaybeUpgrade({ kind = "sidegrade", statMix = true, pct = -2.5 }), false)
	eq(ns.Gear_IsMaybeUpgrade({ kind = "sidegrade", pct = 0.5 }), false)
	eq(ns.Gear_IsMaybeUpgrade({ kind = "upgradeBut", pct = 4 }), true)
	eq(ns.Gear_IsMaybeUpgrade({ kind = "upgradeBut", pct = 0.2 }), false) -- set bonus, stats flat
	eq(ns.Gear_IsMaybeUpgrade(nil), false)
end)

print(failures == 0 and "all passed" or (failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
