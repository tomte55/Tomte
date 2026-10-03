-- Run from the AddOns folder: lua Tomte/tests/test_gear.lua
local ns = {}
assert(loadfile("Tomte/Modules/Gear/Data.lua"))("Tomte", ns)

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

test("Losing an effect: upgrade, but", function()
	local e = gearset()
	e[1].effect = "Equip: your attacks sometimes explode"
	local v = ns.Gear_Evaluate(item("INVTYPE_HEAD", 150, 150, { ilvl = 320 }), e, CTX)
	eq(v.kind, "upgradeBut")
	has(v.reasons, "Loses: Equip")
	eq(ns.Gear_IsCleanUpgrade(v), false)
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

print(failures == 0 and "all passed" or (failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
