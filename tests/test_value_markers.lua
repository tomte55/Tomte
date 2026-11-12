-- Run from the AddOns folder: lua Tomte/tests/test_value_markers.lua
local ns = {}
assert(loadfile("Tomte/Modules/Value/Data.lua"))("Tomte", ns) -- Value_SellVerdict, for real numbers
assert(loadfile("Tomte/Modules/Value/MarkerData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function Kind(f)
	return ns.Value_Marker(f).kind
end

local function Rule(f)
	return ns.VALUE_MARKER_RULES[ns.Value_Marker(f).rule].title
end

-- A tradeable white trade good that a vendor buys for 10 copper each.
local function Goods(extra)
	local f = { quality = 1, classID = 7, vendor = 10, count = 5, minGain = 100 }
	for k, v in pairs(extra or {}) do
		f[k] = v
	end
	return f
end

test("every rule has a title and text, and every marker kind a name", function()
	for i, rule in ipairs(ns.VALUE_MARKER_RULES) do
		assert(rule.title and rule.text, "rule " .. i)
		if rule.kind then
			assert(ns.Value_MarkerName(rule.kind), rule.kind)
		end
	end
end)

test("ignored and skipped items get no marker", function()
	eq(Kind(Goods({ ignored = true, questFor = "A quest" })), nil)
	eq(Kind(Goods({ skip = "bag" })), nil)
	eq(Rule(Goods({ skip = "hearth" })), "No marker: left alone")
end)

test("quests: wanted or starting one is kept, a done one with no vendor is deleted", function()
	eq(Kind(Goods({ questFor = "Gnoll Trouble", classID = 12, vendor = 0, noValue = true })), "quest")
	eq(ns.Value_Marker(Goods({ questFor = "Gnoll Trouble" })).why, "For Gnoll Trouble.")
	eq(Kind(Goods({ startsQuest = true, vendor = 0, noValue = true })), "quest")
	eq(Kind(Goods({ startsQuest = true, questDone = true, vendor = 0, noValue = true })), "delete")
	eq(Kind(Goods({ startsQuest = true, questDone = true, bound = true })), "vendor", "a vendor still buys it")
end)

test("a quest starter whose quest is taken: kept only when an objective names it, without naming the quest", function()
	local head = { classID = 12, quality = 1, vendor = 0, noValue = true, bound = true, startsQuest = true,
		questActive = true }
	eq(Kind(head), nil, "taken, no objective names it")
	eq(Rule(head), "No marker: an unknown quest item")
	head.questFor = "Unending Torment"
	eq(Kind(head), "quest")
	eq(ns.Value_Marker(head).why, "Its quest needs it handed in.", "the game's Starts: line names it already")
end)

test("something to open is kept", function()
	eq(Kind({ classID = 12, quality = 1, vendor = 0, noValue = true, questItem = true, openable = true }), "keep")
	eq(ns.Value_Marker(Goods({ openable = true, bound = true })).why, "Right-click to open it.")
end)

test("a quest item no quest names gets no marker", function()
	eq(Kind({ classID = 12, quality = 1, vendor = 0, noValue = true, questItem = true }), nil)
	eq(Rule({ classID = 12, quality = 1, vendor = 0, noValue = true }), "No marker: an unknown quest item")
end)

test("soulbound gear you can't use and can't sell is deleted, unless its look is new", function()
	local f = { classID = 4, quality = 2, bound = true, unusable = true, vendor = 0, noValue = true }
	eq(Kind(f), "delete")
	f.newLook = true
	eq(Kind(f), "keep")
	f.newLook, f.unusable = nil, false
	eq(Kind(f), "keep", "usable: can't be sold, kept")
end)

test("gear: upgrades, sets and new looks are kept", function()
	local gear = { classID = 4, quality = 3, bound = true, vendor = 500 }
	eq(Kind(gear), "vendor")
	gear.upgrade = "maybe"
	eq(Kind(gear), "keep")
	gear.upgrade = "alt"
	eq(ns.Value_Marker(gear).why, "An upgrade for another character.")
	gear.upgrade, gear.inSet = nil, true
	eq(Kind(gear), "keep")
	gear.inSet, gear.newLook = nil, true
	eq(Kind(gear), "keep")
end)

test("disenchant: worth more than vendor plus the limit and than the auction house", function()
	local gear = { classID = 2, quality = 3, vendor = 100, count = 1, minGain = 100, destroy = 250,
		sell = { kind = "vendor", expected = 120 } }
	eq(Kind(gear), "disenchant")
	gear.destroy = 150
	eq(Kind(gear), "vendor", "not past the limit")
	gear.destroy, gear.sell = 400, { kind = "ah", expected = 500 }
	eq(Kind(gear), "auction", "the auction house pays more")
	gear.sell, gear.bound = nil, true
	eq(Kind(gear), "vendor", "soulbound without Disenchant")
	gear.canDisenchant = true
	eq(Kind(gear), "disenchant")
	gear.quality = 5
	eq(Kind(gear), "vendor", "legendaries can't be disenchanted")
end)

test("collectibles and crafting materials are kept unless they sell well", function()
	eq(Kind(Goods({ collectible = true })), "keep")
	eq(Kind(Goods({ crafting = true, sell = { kind = "vendor", expected = 10 } })), "keep")
	eq(Kind(Goods({ crafting = true, sell = { kind = "ah", expected = 90 } })), "auction")
end)

test("can't be sold: kept", function()
	eq(Kind(Goods({ vendor = 0, noValue = true })), "keep")
	eq(Kind(Goods({ vendor = 0, sell = { kind = "ah", expected = 900 } })), "auction", "the auction house buys it")
end)

test("soulbound: vendored, or kept when you use it up", function()
	eq(Kind(Goods({ bound = true })), "vendor")
	eq(Kind(Goods({ bound = true, consumable = true })), "keep")
end)

test("grey junk is vendored unless it sells well", function()
	eq(Kind(Goods({ quality = 0 })), "vendor")
	eq(Kind(Goods({ quality = 0, sell = { kind = "ah", expected = 900 } })), "auction")
end)

test("tradeable with a price: auction, keep a consumable, else vendor", function()
	eq(Kind(Goods({ sell = { kind = "ah", expected = 90 } })), "auction")
	eq(Kind(Goods({ consumable = true, sell = { kind = "ah", expected = 90 } })), "keep")
	eq(Kind(Goods({ sell = { kind = "small", expected = 20 } })), "vendor")
	eq(ns.Value_Marker(Goods({ sell = { kind = "slow", expected = 20 } })).why, "Rarely sells at the auction house.")
	eq(Kind(Goods()), nil, "no price: nothing to go on")
end)

test("quest objectives name the item in either order, any case", function()
	local quests = {
		{ title = "Wolves", objectives = { "Wolf Meat: 3/8" } },
		{ title = "Gnolls", objectives = { "Slay 10 gnolls", "3/8 gnoll paw" } },
	}
	eq(ns.Value_QuestFor("Gnoll Paw", quests), "Gnolls")
	eq(ns.Value_QuestFor("Wolf Meat", quests), "Wolves")
	eq(ns.Value_QuestFor("Bear Meat", quests), nil)
	eq(ns.Value_ObjectiveNames("Ax: 1/1", "Ax"), false, "too short to trust")
end)

test("recipes: kept while you or an alt can learn it, now or later", function()
	local pattern = Goods({ classID = 9, quality = 2, vendor = 658, sell = { kind = "vendor", expected = 600 } })
	pattern.recipe = ns.Value_RecipeFact({ known = {}, ready = {}, low = { { c = { name = "Aldric" }, skill = 50 } },
		need = 90, profName = "Leatherworking" })
	eq(Kind(pattern), "keep")
	eq(ns.Value_Marker(pattern).why, "Aldric can learn it later (Leatherworking 50/90).")
	pattern.recipe = ns.Value_RecipeFact({ known = {}, ready = { { c = { name = "Mira" }, skill = 95 } }, low = {},
		need = 90, profName = "Leatherworking" })
	eq(ns.Value_Marker(pattern).why, "Mira can learn it (Leatherworking 95).")
	pattern.recipe = ns.Value_RecipeFact({ known = { { c = { name = "Kesha" } } }, ready = {}, low = {} })
	eq(Kind(pattern), "vendor", "already known: the selling rules decide")
	pattern.recipe = ns.Value_RecipeFact({ known = {}, ready = {}, low = {} })
	eq(pattern.recipe, nil, "nobody has the profession")
	eq(Kind(pattern), "vendor")
end)

-- Pattern: Deviate Scale Belt on Forever: vendor 6s 58c, a 42% sale rate, limit 1s.
test("the reason matches the numbers: a vendor paying more says so", function()
	local function Pattern(market)
		local sell = ns.Value_SellVerdict({ market = market, vendor = 658, saleRate = 0.42, count = 1, minGain = 100 })
		return Goods({ classID = 9, quality = 2, vendor = 658, count = 1, sell = sell })
	end
	local cheap = Pattern(612) -- TSM's market value: 6s 12c
	eq(cheap.sell.kind, "vendor")
	eq(Kind(cheap), "vendor")
	eq(ns.Value_Marker(cheap).why, "A vendor pays more than the auction house would.")
	local dear = Pattern(12208) -- 1g 22s 8c
	eq(dear.sell.kind, "ah")
	eq(Kind(dear), "auction", "at that price the marker and the tooltip's Auction House line agree")
	eq(ns.Value_Marker(Goods({ sell = { kind = "small", expected = 20 } })).why,
		"The auction house makes less than your limit more.")
end)

test("summary counts in marker order", function()
	eq(ns.Value_MarkerSummary({ keep = 3, vendor = 2 }), "2 to vendor, 3 to keep")
	eq(ns.Value_MarkerSummary({}), nil)
end)

H.done()
