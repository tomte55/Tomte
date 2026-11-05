-- Run from the AddOns folder: lua Tomte/tests/test_tips.lua
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Tips/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

-- The data files load with a stub registry: they must parse and keep their shape.
local registered = {}
ns.Content_Register = function(expansion, key, value)
	registered[expansion] = registered[expansion] or {}
	registered[expansion][key] = value
end
for _, file in ipairs({ "Data/Older/Tips.lua", "Data/WarWithin/Tips.lua", "Data/Midnight/Tips.lua" }) do
	assert(loadfile("Tomte/" .. file))("Tomte", ns)
end

test("data files register a tips table per expansion", function()
	eq(type(registered[9].tips), "table", "older")
	eq(type(registered[10].tips), "table", "war within")
	eq(type(registered[11].tips), "table", "midnight")
end)

test("data shapes: rep spells map to faction IDs, vendors have a map and position", function()
	for expansion, data in pairs(registered) do
		for spellID, value in pairs(data.tips.repSpells or {}) do
			for _, factionID in ipairs(ns.Tips_FactionList(value)) do
				assert(type(factionID) == "number" and factionID > 0, "rep " .. expansion .. ":" .. spellID)
			end
		end
		for itemID, value in pairs(data.tips.vendors or {}) do
			for _, place in ipairs(ns.Tips_VendorPlaces(value)) do
				assert(type(place.map) == "number", "vendor map " .. itemID)
				assert(place.x > 0 and place.x < 1 and place.y > 0 and place.y < 1, "vendor position " .. itemID)
				assert(place.npc or place.area or place.name, "vendor who " .. itemID)
			end
		end
		for itemID, key in pairs(data.tips.keys or {}) do
			assert(key.currency or key.item, "key " .. itemID)
		end
		for choiceID, token in pairs(data.tips.choices or {}) do
			assert(token.currency or token.item, "choice " .. choiceID)
		end
	end
end)

test("Merge combines expansions, a later one wins", function()
	local merged = ns.Tips_Merge({ { vendors = { [1] = "a", [2] = "b" } }, { vendors = { [2] = "c" } }, {} }, "vendors")
	eq(merged[1], "a")
	eq(merged[2], "c")
	eq(next(ns.Tips_Merge({ {} }, "keys")), nil, "empty")
end)

test("Merge over the real data finds tokens from every expansion", function()
	local sources = { registered[9].tips, registered[10].tips, registered[11].tips }
	local rep = ns.Tips_Merge(sources, "repSpells")
	eq(rep[17047], 529, "Argent Dawn Valor Token")
	eq(rep[1228437], 2640, "Big Wheel of Cheese")
	eq(rep[1277957], 2744, "Valeera companion experience")
	eq(#ns.Tips_FactionList(rep[1257179]), 9, "Insignia of the Broken Isles")
end)

test("FactionList wraps one ID and passes a list", function()
	eq(#ns.Tips_FactionList(529), 1)
	eq(ns.Tips_FactionList(529)[1], 529)
	eq(#ns.Tips_FactionList({ 1, 2 }), 2)
	eq(#ns.Tips_FactionList(nil), 0)
end)

test("RepStatus: renown in progress", function()
	local text, role = ns.Tips_RepStatus({ kind = "renown", level = 12, earned = 1500, threshold = 2500 })
	eq(text, "Renown 12  1,500 / 2,500")
	eq(role, "text")
end)

test("RepStatus: friendship rank", function()
	local text = ns.Tips_RepStatus({ kind = "friend", standing = "Buddy", level = 3, maxLevel = 8, earned = 10,
		threshold = 100 })
	eq(text, "Buddy (rank 3 of 8)  10 / 100")
end)

test("RepStatus: maxed without paragon warns", function()
	local text, role = ns.Tips_RepStatus({ kind = "plain", standing = "Exalted", maxed = true, threshold = 0 })
	eq(text, "Exalted, maxed: this gives you nothing more")
	eq(role, "warning")
end)

test("RepStatus: paragon shows progress in the current cycle", function()
	local text, role = ns.Tips_RepStatus({ kind = "renown", level = 25, maxed = true,
		paragon = { value = 23000, threshold = 10000 } })
	eq(text, "Paragon 3,000 / 10,000")
	eq(role, "accent")
end)

test("RepStatus: paragon reward waiting", function()
	local _, role = ns.Tips_RepStatus({ kind = "renown", maxed = true,
		paragon = { value = 10000, threshold = 10000, pending = true } })
	eq(role, "success")
end)

test("RepStatus: paragon not yet reached is plain progress", function()
	local text = ns.Tips_RepStatus({ kind = "plain", standing = "Revered", earned = 5, threshold = 21000,
		paragon = { value = 0, threshold = 10000 } })
	eq(text, "Revered  5 / 21,000")
end)

test("IsCombine: an item that only uses itself up isn't a combine", function()
	eq(ns.Tips_IsCombine(100, {}), false)
	eq(ns.Tips_IsCombine(100, { { itemID = 100, need = 1 } }), false)
	eq(ns.Tips_IsCombine(100, { { itemID = 100 } }), false)
	eq(ns.Tips_IsCombine(100, { { itemID = 100, need = 2 } }), true)
	eq(ns.Tips_IsCombine(100, { { itemID = 200, need = 1 } }), true)
	eq(ns.Tips_IsCombine(100, { { itemID = 100, need = 1 }, { currencyID = 3 } }), true)
end)

test("ReagentRows: counts, short reagents and how many you can make", function()
	local rows, crafts = ns.Tips_ReagentRows({
		{ name = "Shard", have = 25, need = 10 },
		{ name = "Dust", have = 1200, need = 100 },
	})
	eq(#rows, 2)
	eq(rows[1].right, "25 / 10")
	eq(rows[2].right, "1,200 / 100")
	eq(rows[1].role, "text")
	eq(crafts, 2)
end)

test("ReagentRows: one short reagent makes it zero and red", function()
	local rows, crafts = ns.Tips_ReagentRows({ { name = "Shard", have = 3, need = 10 }, { name = "Dust", have = 500,
		need = 1 } })
	eq(rows[1].role, "danger")
	eq(crafts, 0)
	eq(ns.Tips_CraftsText(crafts), nil)
end)

test("ReagentRows: missing name and need fall back", function()
	local rows, crafts = ns.Tips_ReagentRows({ { have = 2 } })
	eq(rows[1].left, "?")
	eq(rows[1].right, "2 / 1")
	eq(crafts, 2)
end)

test("CraftsText", function()
	eq(ns.Tips_CraftsText(1), "You have enough for one.")
	eq(ns.Tips_CraftsText(1500), "You have enough for 1,500.")
end)

test("KeyLine colors by whether you have enough", function()
	local left, right, role = ns.Tips_KeyLine("Restored Coffer Key", 0, 1)
	eq(left, "Opens with Restored Coffer Key")
	eq(right, "0 / 1")
	eq(role, "danger")
	local _, _, ok = ns.Tips_KeyLine("Restored Coffer Key", 3)
	eq(ok, "success")
end)

test("VendorPlaces: one place or a list", function()
	eq(#ns.Tips_VendorPlaces(nil), 0)
	eq(#ns.Tips_VendorPlaces({ map = 1, x = 0.5, y = 0.5 }), 1)
	eq(#ns.Tips_VendorPlaces({ places = { {}, {} } }), 2)
end)

test("PickVendor: nearest on your map, else the first", function()
	local places = {
		{ map = 2346, x = 0.432, y = 0.828 },
		{ map = 2346, x = 0.354, y = 0.412 },
		{ map = 2248, x = 0.5, y = 0.5 },
	}
	eq(ns.Tips_PickVendor(places, 2346, 0.35, 0.40), 2)
	eq(ns.Tips_PickVendor(places, 2346, 0.45, 0.80), 1)
	eq(ns.Tips_PickVendor(places, 2248, 0.1, 0.1), 3)
	eq(ns.Tips_PickVendor(places, 999, 0.1, 0.1), 1, "other map")
	eq(ns.Tips_PickVendor(places, nil, nil, nil), 1, "no position")
end)

test("VendorText: who, where, note and label", function()
	eq(ns.Tips_VendorText({}, "Cendvin", "The Ringing Deeps"), "Cendvin, The Ringing Deeps")
	eq(ns.Tips_VendorText({ note = "upper floor" }, "Kari", "Incontinental Hotel"),
		"Kari, Incontinental Hotel (upper floor)")
	eq(ns.Tips_VendorText({ label = "Mounts" }, "Skedgit", "Undermine"), "Mounts: Skedgit, Undermine")
	eq(ns.Tips_VendorText({}, nil, "Undermine"), "Undermine")
	eq(ns.Tips_VendorText({}, "Ponzo", nil), "Ponzo")
end)

test("ChoiceEntries: token first, rewards once each, limited", function()
	local options = {
		{ rewardInfo = { itemRewards = { { itemId = 10 }, { itemId = 11 } },
			currencyRewards = { { currencyId = 5 } } } },
		{ rewardInfo = { itemRewards = { { itemId = 10 } }, currencyRewards = {} } },
		{},
	}
	local list = ns.Tips_ChoiceEntries(options, { item = 99 })
	eq(#list, 4)
	eq(list[1].id, 99)
	eq(list[1].kind, "item")
	eq(list[2].id, 10)
	eq(list[3].id, 11)
	eq(list[4].kind, "currency")
	eq(#ns.Tips_ChoiceEntries(options, nil, 2), 2, "limit")
	eq(ns.Tips_ChoiceEntries(options, { currency = 3090 })[1].kind, "currency")
	eq(#ns.Tips_ChoiceEntries(nil, nil), 0)
end)

test("ChoiceEntries: an item and a currency with the same ID are both kept", function()
	local list = ns.Tips_ChoiceEntries({ { rewardInfo = { itemRewards = { { itemId = 7 } },
		currencyRewards = { { currencyId = 7 } } } } })
	eq(#list, 2)
end)

test("CountText", function()
	eq(ns.Tips_CountText("Radiant Echo", 1234), "Radiant Echo: 1,234")
	eq(ns.Tips_CountText(nil, nil), "?: 0")
end)
test("PreviewItems picks samples per line kind, the first source first, each once", function()
	local mine = {
		keys = { [30] = true, [10] = true },
		samples = { rep = 500 },
		reagentQuantity = { [2] = { [41] = 1, [40] = 2 }, [1] = { [42] = 1 } },
		vendors = { [60] = { named = true, map = 1 }, [61] = { map = 1 } },
		choices = { [7] = { currency = 3000 }, [8] = { item = 70 } },
	}
	local older = {
		keys = { [10] = true, [5] = true },
		samples = { rep = 501 },
		vendors = { [62] = { places = { { map = 2 }, { named = true, map = 3 } } } },
		choices = { [9] = { currency = 3000 } },
	}
	local sources = { mine, older }
	eq(table.concat(ns.Tips_PreviewItems(sources, "keys"), ","), "10,30,5", "sorted, a repeat once")
	eq(table.concat(ns.Tips_PreviewItems(sources, "rep"), ","), "500,501")
	eq(table.concat(ns.Tips_PreviewItems(sources, "reagents"), ","), "42,40,41", "by recipe, then item")
	eq(table.concat(ns.Tips_PreviewItems(sources, "vendors"), ","), "61,60,62",
		"a vendor not in the item's text first, per source")
	local choice = ns.Tips_PreviewItems(sources, "choice")
	eq(#choice, 2, "the same currency once")
	eq(choice[1].kind, "currency")
	eq(choice[1].id, 3000)
	eq(choice[2].kind, "item")
	eq(ns.Tips_PreviewItems({ {} }, "rep")[1], nil, "a source without samples")
end)

-- A book with nothing else to it, checked against every achievement; tests change one fact.
local function Book(changes)
	local facts = { scanned = true, readable = true, bound = true }
	for k, v in pairs(changes or {}) do
		facts[k] = v
	end
	return facts
end

test("use: a plain book is lore, safe to delete or sell", function()
	local text, role = ns.Tips_UseVerdict(Book())
	eq(text, "Lore: read it, then safe to delete")
	eq(role, "success")
	eq(ns.Tips_UseVerdict(Book({ sells = true })), "Lore: read it, then sell it")
end)

test("use: an achievement that needs it wins over everything", function()
	local text, role = ns.Tips_UseVerdict(Book({ achievement = "Lorewalking", known = true }))
	eq(text, "Needed for Lorewalking")
	eq(role, "warning")
	eq(ns.Tips_UseVerdict({ achievement = "Lorewalking" }), "Needed for Lorewalking", "even outside the bags")
end)

test("use: no line before the achievement check is done", function()
	eq(ns.Tips_UseVerdict(Book({ scanned = false })), nil)
	eq(ns.Tips_UseVerdict(Book({ scanned = false, known = true })), nil)
end)

test("use: no line on a book with a use, a quest or a token", function()
	eq(ns.Tips_UseVerdict(Book({ hasUse = true })), nil, "use effect")
	eq(ns.Tips_UseVerdict(Book({ quest = true })), nil, "quest")
	eq(ns.Tips_UseVerdict(Book({ token = true })), nil, "token")
	eq(ns.Tips_UseVerdict(Book({ reagent = true })), nil, "reagent")
end)

test("use: no line on anything that isn't a book and isn't learned", function()
	local text, _, reason = ns.Tips_UseVerdict(Book({ readable = false }))
	eq(text, nil)
	eq(type(reason), "string")
end)

test("use: already learned says delete, sell, or sell or trade", function()
	eq(ns.Tips_UseVerdict({ scanned = true, known = true, bound = true }), "Already learned: safe to delete")
	eq(ns.Tips_UseVerdict({ scanned = true, known = true, bound = true, sells = true }), "Already learned: sell it")
	eq(ns.Tips_UseVerdict({ scanned = true, known = true, bound = false }), "Already learned: sell or trade it")
	eq(ns.Tips_UseVerdict({ scanned = true, known = true, quest = true }), nil, "a quest still needs it")
end)

H.done()
