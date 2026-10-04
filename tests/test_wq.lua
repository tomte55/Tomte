-- Run from the AddOns folder: lua Tomte/tests/test_wq.lua
local ns = {}
assert(loadfile("Tomte/Modules/Gear/Data.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/WorldQuests/Data.lua"))("Tomte", ns)

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

local GOLD = 10000

local function Opts(over)
	local o = {
		show = { pvp = false, petbattle = false, otherProfessions = false },
		worth = { transmog = false, gold = false, goldAmount = 500 },
		collapsed = {},
		maxLevel = true,
	}
	for k, v in pairs(over or {}) do
		o[k] = v
	end
	return o
end

local nextID = 0
local function Q(fields)
	nextID = nextID + 1
	local q = { id = nextID, title = "Quest " .. nextID, seconds = 3600 * 5, loaded = true, money = 0, items = {},
		currencies = {}, reps = {} }
	for k, v in pairs(fields) do
		q[k] = v
	end
	return q
end

local function Gear(ilvl, verdict)
	return { name = "Cloak", icon = 1, count = 1, ilvl = ilvl, gear = true, verdict = verdict }
end

local function Titles(section)
	local list = {}
	for _, q in ipairs(section.quests) do
		list[#list + 1] = q.title
	end
	return table.concat(list, ",")
end

local function SectionKeys(sections)
	local list = {}
	for _, s in ipairs(sections) do
		list[#list + 1] = s.key
	end
	return table.concat(list, ",")
end

-- Formatting -----------------------------------------------------------------------------------------------------

test("gold format", function()
	eq(ns.WQ_FormatGold(1250 * GOLD + 55), "1,250g")
	eq(ns.WQ_FormatGold(12 * GOLD), "12g")
	eq(ns.WQ_FormatGold(1234567 * GOLD), "1,234,567g")
	eq(ns.WQ_FormatGold(50), "<1g")
end)

test("time text and tiers", function()
	local text, tier = ns.WQ_TimeText(45 * 60)
	eq(text, "45m")
	eq(tier, "low")
	text, tier = ns.WQ_TimeText(10 * 60)
	eq(text, "10m")
	eq(tier, "critical")
	text, tier = ns.WQ_TimeText(3 * 3600 + 20 * 60)
	eq(text, "3h 20m")
	eq(tier, "normal")
	eq((ns.WQ_TimeText(3 * 3600)), "3h")
	eq((ns.WQ_TimeText(86400 + 4 * 3600 + 59)), "1d 4h")
	eq(select(2, ns.WQ_TimeText(75 * 60)), "low", "75 minutes is low")
	eq(select(2, ns.WQ_TimeText(15 * 60)), "critical", "15 minutes is critical")
end)

test("time text edge cases", function()
	eq(ns.WQ_TimeText(nil), nil)
	eq(ns.WQ_TimeText(0), nil)
	eq((ns.WQ_TimeText(20)), "1m", "under a minute rounds up")
end)

-- Filtering ------------------------------------------------------------------------------------------------------

test("filter hides pvp, pet battles and unknown professions by default", function()
	local o = Opts()
	eq(ns.WQ_Filter(Q({ type = "pvp", money = GOLD }), o), false, "pvp")
	eq(ns.WQ_Filter(Q({ type = "petbattle", money = GOLD }), o), false, "pet battle")
	eq(ns.WQ_Filter(Q({ type = "profession", knownSkill = false, money = GOLD }), o), false, "unknown profession")
	eq(ns.WQ_Filter(Q({ type = "profession", knownSkill = true, money = GOLD }), o), true, "known profession")
	eq(ns.WQ_Filter(Q({ type = "dungeon", money = GOLD }), o), true, "dungeon")
	eq(ns.WQ_Filter(Q({ elite = true, money = GOLD }), o), true, "elite")
end)

test("filter options show hidden types", function()
	local o = Opts({ show = { pvp = true, petbattle = true, otherProfessions = true } })
	eq(ns.WQ_Filter(Q({ type = "pvp", money = GOLD }), o), true)
	eq(ns.WQ_Filter(Q({ type = "petbattle", money = GOLD }), o), true)
	eq(ns.WQ_Filter(Q({ type = "profession", knownSkill = false, money = GOLD }), o), true)
end)

test("xp-only skipped at max level, kept below", function()
	eq(ns.WQ_Filter(Q({ xp = 5000 }), Opts()), false, "max level")
	eq(ns.WQ_Filter(Q({ xp = 5000 }), Opts({ maxLevel = false })), true, "below max")
	eq(ns.WQ_Filter(Q({ xp = 5000, loaded = false }), Opts()), true, "still loading stays")
	eq(ns.WQ_Filter(Q({ xp = 5000, money = GOLD }), Opts()), true, "xp plus gold")
end)

-- Classification ----------------------------------------------------------------------------------------------

test("main reward picks the section", function()
	local o = Opts()
	eq(ns.WQ_Classify(Q({ items = { Gear(600) } }), o), "gear")
	eq(ns.WQ_Classify(Q({ items = { { name = "Ore", count = 5 } } }), o), "other")
	eq(ns.WQ_Classify(Q({ currencies = { { name = "Kej", amount = 100 } }, money = GOLD }), o), "currency")
	eq(ns.WQ_Classify(Q({ money = 300 * GOLD, reps = { { name = "Dornogal", amount = 50 } } }), o), "gold")
	eq(ns.WQ_Classify(Q({ reps = { { name = "Dornogal", amount = 50 } } }), o), "rep")
	eq(ns.WQ_Classify(Q({ xp = 100 }), Opts({ maxLevel = false })), "other")
	eq(ns.WQ_Classify(Q({}), o), "other")
end)

test("gear goes before other items", function()
	eq(ns.WQ_Classify(Q({ items = { { name = "Ore", count = 5 }, Gear(600) } }), Opts()), "gear")
end)

test("classify an unloaded quest", function()
	local q = Q({ loaded = false, money = 900 * GOLD })
	eq(ns.WQ_Classify(q, Opts({ worth = { gold = true, goldAmount = 500 } })), "other")
	eq((ns.WQ_RewardText(q)), "loading…")
end)

test("worth it: missing collectibles and clean upgrades", function()
	local o = Opts()
	local section, _, reason = ns.WQ_Classify(Q({ items = { { name = "Drake", collectible = "mount" } } }), o)
	eq(section, "worth")
	eq(reason, "collectible")
	section, _, reason = ns.WQ_Classify(Q({ items = { Gear(610, { kind = "upgrade", pct = 3.2 }) } }), o)
	eq(section, "worth")
	eq(reason, "upgrade")
	eq((ns.WQ_Classify(Q({ items = { Gear(610, { kind = "empty" }) } }), o)), "worth", "empty slot")
	eq((ns.WQ_Classify(Q({ items = { Gear(610, { kind = "upgradeBut", pct = 3 }) } }), o)), "gear", "upgrade with a but")
	eq((ns.WQ_Classify(Q({ items = { Gear(610, { kind = "sidegrade", pct = 0.5 }) } }), o)), "gear", "sidegrade")
end)

test("collectible beats upgrade", function()
	local q = Q({ items = { Gear(610, { kind = "upgrade", pct = 3 }), { name = "Pet", collectible = "pet" } } })
	local section, _, reason = ns.WQ_Classify(q, Opts())
	eq(section, "worth")
	eq(reason, "collectible")
end)

test("appearance and gold rules are off by default", function()
	local look = Q({ items = { Gear(500, { kind = "downgrade", pct = -20 }) } })
	look.items[1].appearance = true
	local rich = Q({ money = 2000 * GOLD })
	eq((ns.WQ_Classify(look, Opts())), "gear")
	eq((ns.WQ_Classify(rich, Opts())), "gold")
	local o = Opts({ worth = { transmog = true, gold = true, goldAmount = 500 } })
	local section, _, reason = ns.WQ_Classify(look, o)
	eq(section, "worth")
	eq(reason, "appearance")
	section, _, reason = ns.WQ_Classify(rich, o)
	eq(section, "worth")
	eq(reason, "gold")
end)

test("gold threshold inclusive", function()
	local o = Opts({ worth = { gold = true, goldAmount = 500 } })
	eq((ns.WQ_Classify(Q({ money = 500 * GOLD }), o)), "worth")
	eq((ns.WQ_Classify(Q({ money = 499 * GOLD }), o)), "gold")
end)

test("gear without verdict", function()
	local o = Opts()
	eq((ns.WQ_Classify(Q({ items = { Gear(650) } }), o)), "gear", "no verdict never worth it")
	local sections = ns.WQ_Sections({
		Q({ title = "low", items = { Gear(600) } }),
		Q({ title = "high", items = { Gear(640) } }),
		Q({ title = "judged", items = { Gear(590, { kind = "downgrade", pct = -4 }) } }),
	}, o)
	eq(SectionKeys(sections), "gear")
	eq(Titles(sections[1]), "judged,high,low", "verdicts first, then item level")
end)

-- Sections and sorting -----------------------------------------------------------------------------------------

test("sections come in order and empty ones are left out", function()
	local sections = ns.WQ_Sections({
		Q({ reps = { { name = "A", amount = 10 } } }),
		Q({ money = 10 * GOLD }),
		Q({ items = { { name = "Drake", collectible = "mount" } } }),
	}, Opts())
	eq(SectionKeys(sections), "worth,gold,rep")
	eq(sections[1].title, "Worth it")
end)

test("filtered quests are left out of sections", function()
	local sections = ns.WQ_Sections({ Q({ type = "pvp", money = GOLD }), Q({ money = GOLD }) }, Opts())
	eq(#sections[1].quests, 1)
end)

test("worth it sort: collectible, upgrade by pct, appearance, gold", function()
	local look = Q({ title = "look", items = { Gear(500) } })
	look.items[1].appearance = true
	local sections = ns.WQ_Sections({
		Q({ title = "gold", money = 900 * GOLD }),
		look,
		Q({ title = "up1", items = { Gear(610, { kind = "upgrade", pct = 1.5 }) } }),
		Q({ title = "up5", items = { Gear(610, { kind = "upgrade", pct = 5 }) } }),
		Q({ title = "mount", items = { { name = "Drake", collectible = "mount" } } }),
	}, Opts({ worth = { transmog = true, gold = true, goldAmount = 500 } }))
	eq(Titles(sections[1]), "mount,up5,up1,look,gold")
end)

test("ties go to what expires first, then title", function()
	local sections = ns.WQ_Sections({
		Q({ title = "b", money = 10 * GOLD, seconds = 7200 }),
		Q({ title = "c", money = 10 * GOLD, seconds = nil }),
		Q({ title = "a", money = 10 * GOLD, seconds = 7200 }),
		Q({ title = "d", money = 10 * GOLD, seconds = 600 }),
	}, Opts())
	eq(Titles(sections[1]), "d,a,b,c")
end)

test("gold and rep sort by amount", function()
	local sections = ns.WQ_Sections({
		Q({ title = "small", money = 10 * GOLD }),
		Q({ title = "big", money = 90 * GOLD }),
		Q({ title = "r1", reps = { { name = "A", amount = 50 } } }),
		Q({ title = "r2", reps = { { name = "A", amount = 250 } } }),
	}, Opts())
	eq(Titles(sections[1]), "big,small")
	eq(Titles(sections[2]), "r2,r1")
end)

test("currencies group by name, then amount, capped last", function()
	local sections = ns.WQ_Sections({
		Q({ title = "kej50", currencies = { { name = "Kej", amount = 50 } } }),
		Q({ title = "crys9", currencies = { { name = "Crystals", amount = 9 } } }),
		Q({ title = "kej90", currencies = { { name = "Kej", amount = 90 } } }),
		Q({ title = "capped", currencies = { { name = "Arcane", amount = 999, capped = true } } }),
	}, Opts())
	eq(Titles(sections[1]), "crys9,kej90,kej50,capped")
	eq(sections[1].quests[4].dim, true)
	eq(sections[1].quests[1].dim, false)
end)

test("max renown rep is dimmed and last", function()
	local sections = ns.WQ_Sections({
		Q({ title = "maxed", reps = { { name = "A", amount = 500, max = true } } }),
		Q({ title = "open", reps = { { name = "B", amount = 50 } } }),
	}, Opts())
	eq(Titles(sections[1]), "open,maxed")
	eq(sections[1].quests[2].dim, true)
end)

test("not-for-you gear is dimmed", function()
	local sections = ns.WQ_Sections({
		Q({ title = "nope", items = { Gear(650, { kind = "notForYou", why = "plate" }) } }),
		Q({ title = "side", items = { Gear(600, { kind = "sidegrade", pct = 0.2 }) } }),
	}, Opts())
	eq(Titles(sections[1]), "side,nope")
	eq(sections[1].quests[2].dim, true)
end)

test("collapsed state comes from opts", function()
	local sections = ns.WQ_Sections({ Q({ money = GOLD }) }, Opts({ collapsed = { gold = true } }))
	eq(sections[1].collapsed, true)
end)

-- Text -----------------------------------------------------------------------------------------------------------

test("reward text", function()
	eq((ns.WQ_RewardText(Q({ items = { { name = "Drake", collectible = "mount" } } }))), "Mount: Drake")
	eq((ns.WQ_RewardText(Q({ items = { { name = "Rocket", collectible = "toy" } } }))), "Toy: Rocket")
	eq((ns.WQ_RewardText(Q({ items = { Gear(619, { kind = "upgrade", pct = 3.24 }) } }))), "ilvl 619 · Upgrade +3.2%")
	eq((ns.WQ_RewardText(Q({ items = { Gear(619) } }))), "ilvl 619")
	eq((ns.WQ_RewardText(Q({ items = { Gear(619, { kind = "downgrade", pct = -2 }) } }))), "ilvl 619 · Downgrade -2.0%")
	eq((ns.WQ_RewardText(Q({ items = { Gear(619, { kind = "notForYou", why = "plate" }) } }))), "ilvl 619 · Not for you")
	eq((ns.WQ_RewardText(Q({ money = 1250 * GOLD }))), "1,250g")
	eq((ns.WQ_RewardText(Q({ currencies = { { name = "Resonance Crystals", amount = 450 } } }))), "450 Resonance Crystals")
	eq((ns.WQ_RewardText(Q({ currencies = { { name = "Kej", amount = 5, capped = true } } }))), "5 Kej (capped)")
	eq((ns.WQ_RewardText(Q({ reps = { { name = "Council of Dornogal", amount = 250 } } }))), "+250 Council of Dornogal")
	eq((ns.WQ_RewardText(Q({ reps = { { name = "X", amount = 250, max = true } } }))), "+250 X (max renown)")
	eq((ns.WQ_RewardText(Q({ items = { { name = "Ore", count = 3 } } }))), "3 Ore")
	eq((ns.WQ_RewardText(Q({ items = { { name = "Box", count = 1 } } }))), "Box")
	eq((ns.WQ_RewardText(Q({}))), "No reward")
end)

test("appearance reward text", function()
	local q = Q({ items = { Gear(500) } })
	q.items[1].appearance = true
	q.items[1].name = "Robe"
	ns.WQ_Classify(q, Opts({ worth = { transmog = true } }))
	eq((ns.WQ_RewardText(q)), "Appearance: Robe")
end)

test("secondary rewards", function()
	local q = Q({ items = { Gear(619) }, money = 120 * GOLD, reps = { { name = "Dornogal", amount = 75 } },
		currencies = { { name = "Kej", amount = 20 } } })
	local main, secondary = ns.WQ_RewardText(q)
	eq(main, "ilvl 619")
	eq(secondary, "20 Kej · 120g · +75 Dornogal")
	main, secondary = ns.WQ_RewardText(Q({ money = 50 * GOLD }))
	eq(secondary, nil)
end)

test("main item follows the reward text", function()
	local ore, cloak, drake = { name = "Ore", count = 3 }, Gear(600), { name = "Drake", collectible = "mount" }
	eq(ns.WQ_MainItem(Q({ items = { ore, cloak } })), cloak, "gear before other items")
	eq(ns.WQ_MainItem(Q({ items = { cloak, drake } })), drake, "collectible first")
	eq(ns.WQ_MainItem(Q({ items = { ore } })), ore)
	eq(ns.WQ_MainItem(Q({ money = GOLD })), nil, "no item")
	eq(ns.WQ_MainItem(Q({ loaded = false, items = { ore } })), nil, "not loaded")
end)

test("upgrade text names the clean upgrade, not the first gear item", function()
	local q = Q({ items = { Gear(600, { kind = "downgrade", pct = -3 }), Gear(640, { kind = "upgrade", pct = 4 }) } })
	ns.WQ_Classify(q, Opts())
	eq((ns.WQ_RewardText(q)), "ilvl 640 · Upgrade +4.0%")
	eq(ns.WQ_MainItem(q), q.items[2])
end)

test("main reward kinds", function()
	eq((ns.WQ_MainReward(Q({ reps = { { name = "A", amount = 5 } } }))), "rep")
	local capped, open = { name = "A", amount = 5, capped = true }, { name = "B", amount = 3 }
	local kind, reward = ns.WQ_MainReward(Q({ currencies = { capped, open } }))
	eq(kind, "currency")
	eq(reward, open, "first uncapped currency")
	eq((ns.WQ_MainReward(Q({ loaded = false }))), "loading")
end)

test("quests whose data never came", function()
	local q = Q({ loaded = false, failed = true })
	eq((ns.WQ_RewardText(q)), "rewards unknown")
	eq(ns.WQ_Classify(q, Opts()), "other")
end)

test("tags", function()
	eq(ns.WQ_Tags(Q({ elite = true, type = "dungeon" })), "Elite · Dungeon")
	eq(ns.WQ_Tags(Q({ type = "worldboss", quality = 2 })), "World boss · Epic")
	eq(ns.WQ_Tags(Q({ type = "profession", profession = "Mining" })), "Mining")
	eq(ns.WQ_Tags(Q({ type = "profession" })), "Profession")
	eq(ns.WQ_Tags(Q({ quality = 1 })), "Rare")
	eq(ns.WQ_Tags(Q({})), "")
end)

test("toast text", function()
	local title, text = ns.WQ_ToastText("Hallowfall", { { title = "Rats!", what = "Mount: Drake" } })
	eq(title, "Hallowfall")
	eq(text, "Rats! rewards Mount: Drake.\nClick for the list.")
	title, text = ns.WQ_ToastText("Hallowfall", { { title = "A", what = "x" }, { title = "B", what = "y" } })
	eq(text, "2 world quests worth doing, like A (x).\nClick for the list.")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
