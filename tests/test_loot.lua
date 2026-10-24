-- Run from the AddOns folder: lua Tomte/tests/test_loot.lua
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Loot/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function item(slot, quality, extra)
	local e = { slot = slot, kind = "item", name = "Item " .. slot, quality = quality, quantity = 1 }
	for k, v in pairs(extra or {}) do
		e[k] = v
	end
	return e
end

local function names(lines)
	local out = {}
	for i, line in ipairs(lines) do
		out[i] = line.junk and ("junk" .. #line.junk) or tostring(line.entry.slot)
	end
	return table.concat(out, " ")
end

local function texts(parts)
	local out = {}
	for i, p in ipairs(parts) do
		out[i] = p.text .. "/" .. p.role
	end
	return table.concat(out, ", ")
end

test("auto-loot: the event's word, else the setting flipped by the auto-loot key", function()
	eq(ns.Loot_ShouldAutoLoot(true, false, false), true, "event says auto")
	eq(ns.Loot_ShouldAutoLoot(false, true, false), false, "event says by hand")
	eq(ns.Loot_ShouldAutoLoot(nil, true, false), true, "no event word: setting on")
	eq(ns.Loot_ShouldAutoLoot(nil, true, true), false, "setting on, key held: by hand")
	eq(ns.Loot_ShouldAutoLoot(nil, false, false), false, "setting off")
	eq(ns.Loot_ShouldAutoLoot(nil, false, true), true, "setting off, key held: auto")
	eq(ns.Loot_ShouldAutoLoot(nil, nil, false), false, "nothing known: by hand")
end)

test("lines: coin first, quest items, then quality, then slot", function()
	local entries = {
		item(1, 2),
		{ slot = 2, kind = "money", name = "12 Gold" },
		item(3, 4),
		item(4, 1, { quest = "item" }),
		item(5, 2),
		{ slot = 6, kind = "none" },
		{ slot = 7, kind = "currency", name = "Valor", quality = 3 },
	}
	eq(names(ns.Loot_Lines(entries)), "2 7 4 3 1 5")
end)

test("junk folds into one line at the end, from two items up", function()
	local entries = { item(1, 0, { quantity = 3, sell = 10 }), item(2, 3), item(3, 0, { sell = 25, taken = true }) }
	local lines = ns.Loot_Lines(entries, { foldJunk = true })
	eq(names(lines), "2 junk2")
	local junk = lines[2]
	eq(junk.quantity, 4, "items in the fold")
	eq(junk.worth, 55, "worth")
	eq(junk.taken, false, "one is still there")
	eq(names(ns.Loot_Lines({ item(1, 0), item(2, 3) }, { foldJunk = true })), "2 1", "a single junk item stays")
	eq(names(ns.Loot_Lines(entries)), "2 1 3", "off: each its own line")
	eq(names(ns.Loot_Lines({ item(1, 0, { quest = "item" }), item(2, 0) }, { foldJunk = true })), "1 2",
		"grey quest items are not junk")
end)

test("lines leave out the Card's best item", function()
	local best = item(2, 4)
	eq(names(ns.Loot_Lines({ item(1, 2), best }, { skip = best })), "1")
end)

test("best item: upgrade, then worth, then quality; never junk or coin", function()
	local entries = {
		{ slot = 1, kind = "money" },
		item(2, 4, { value = 100 }),
		item(3, 3, { value = 5000 }),
		item(4, 0, { sell = 999999 }),
	}
	eq(ns.Loot_BestIndex(entries), 3, "most valuable")
	entries[5] = item(5, 2, { verdict = { maybe = true } })
	eq(ns.Loot_BestIndex(entries), 5, "a maybe upgrade beats worth")
	entries[6] = item(6, 2, { verdict = { upgrade = true } })
	eq(ns.Loot_BestIndex(entries), 6, "an upgrade beats a maybe")
	eq(ns.Loot_BestIndex({ item(1, 3), item(2, 4) }), 2, "no worth: quality")
	eq(ns.Loot_BestIndex({ { slot = 1, kind = "money" }, item(2, 0) }), nil, "nothing")
end)

test("worth: Gold & value's price, else the vendor price, for the stack", function()
	eq(ns.Loot_Worth(item(1, 1, { value = 300, sell = 10, quantity = 4 })), 1200)
	eq(ns.Loot_Worth(item(1, 1, { sell = 10, quantity = 4 })), 40)
	eq(ns.Loot_Worth(item(1, 1, { sell = 0 })), nil, "no worth")
	eq(ns.Loot_Worth(item(1, 1, { sell = 7, quantity = 0 })), 7, "a stack of 0 counts one")
	eq(ns.Loot_Worth(item(1, 1, { value = 0, sell = 10, quantity = 2 })), 20, "a price of 0: the vendor price")
	eq(ns.Loot_Worth(item(1, 1, { value = 0 })), nil, "a price of 0 and no vendor price")
end)

test("paging keeps the page in range", function()
	local lines = {}
	for i = 1, 14 do
		lines[i] = { entry = item(i, 1) }
	end
	local shown, page, pages = ns.Loot_Page(lines, 6, 1)
	eq(#shown, 6, "first page")
	eq(pages, 3, "pages")
	shown, page = ns.Loot_Page(lines, 6, 3)
	eq(#shown, 2, "last page")
	eq(page, 3)
	shown, page = ns.Loot_Page(lines, 6, 9)
	eq(page, 3, "past the end")
	shown, page = ns.Loot_Page(lines, 6, 0)
	eq(page, 1, "before the start")
	shown, page, pages = ns.Loot_Page({}, 6, 2)
	eq(#shown, 0, "empty")
	eq(pages, 1, "one empty page")
	eq(page, 1)
end)

test("takeable and remaining", function()
	local entries = {
		item(3, 1),
		item(1, 1, { taken = true }),
		item(2, 1, { locked = true }),
		{ slot = 4, kind = "none" },
		{ slot = 5, kind = "money" },
	}
	eq(table.concat(ns.Loot_Takeable(entries), " "), "3 5", "not taken, not locked, in slot order")
	eq(ns.Loot_Remaining(entries), 3, "locked counts as left")
end)

test("details: each extra only when on, locked and quest first", function()
	local e = item(1, 1, { quantity = 5, owned = 1234, value = 25, stale = true, newLook = true, classID = 7,
		verdict = { text = "Upgrade +4.2%: equip it", role = "success", upgrade = true } })
	eq(texts(ns.Loot_Details(e, {})), "", "all off")
	eq(texts(ns.Loot_Details(e, { owned = true, value = true, newLook = true, verdict = "tag" })),
		"New look/accent, Upgrade/success, 1,234 owned/textMuted, 1s?/textMuted")
	eq(texts(ns.Loot_Details(e, { verdict = "full" })), "Upgrade +4.2%: equip it/success", "full verdict")
	local locked = item(2, 1, { locked = true, quest = "starts" })
	eq(texts(ns.Loot_Details(locked, {})), "Can't loot/danger, Starts a quest/info")
	locked.taken = true
	eq(texts(ns.Loot_Details(locked, {})), "Starts a quest/info", "taken: no longer can't loot")
	eq(texts(ns.Loot_Details(item(6, 1, { locked = true, taken = true }), {})), "", "locked, taken: nothing")
	eq(texts(ns.Loot_Details(item(3, 2, { verdict = { maybe = true } }), { verdict = "tag" })),
		"Maybe upgrade/warning")
	eq(texts(ns.Loot_Details(item(4, 3, { classID = 4, owned = 2 }), { owned = true })), "", "no owned count on gear")
	eq(texts(ns.Loot_Details(item(5, 1, { sell = 150, stale = true }), { value = true })), "1s/textMuted",
		"a vendor price is never stale")
end)

test("junk name and details", function()
	eq(ns.Loot_JunkName(1), "1 junk item")
	eq(ns.Loot_JunkName(1200), "1,200 junk items")
	eq(texts(ns.Loot_JunkDetails({ worth = 12345 }, { value = true })), "1g/textMuted")
	eq(texts(ns.Loot_JunkDetails({ worth = 0 }, { value = true })), "")
	eq(texts(ns.Loot_JunkDetails({ worth = 50 }, {})), "")
end)

test("quantity text", function()
	eq(ns.Loot_QuantityText(1), "")
	eq(ns.Loot_QuantityText(nil), "")
	eq(ns.Loot_QuantityText(2500), "x2,500")
end)

test("source title", function()
	eq(ns.Loot_SourceTitle({ names = { "Gnoll Brute" }, sources = 1 }), "Gnoll Brute")
	eq(ns.Loot_SourceTitle({ names = { "Gnoll Brute" }, sources = 3 }), "Gnoll Brute +2")
	eq(ns.Loot_SourceTitle({ names = {}, sources = 3 }), "3 corpses")
	eq(ns.Loot_SourceTitle({ names = {}, sources = 1 }), "Loot")
	eq(ns.Loot_SourceTitle({ fishing = true, fishingName = "Angeln", names = { "x" }, sources = 1 }), "Angeln")
	eq(ns.Loot_SourceTitle({ fishing = true }), "Fishing")
end)

test("valuable boss loot", function()
	eq(ns.Loot_IsValuable({ classID = 15, subclassID = 5, quality = 4 }), true, "mount")
	eq(ns.Loot_IsValuable({ classID = 15, subclassID = 2, quality = 3 }), true, "pet")
	eq(ns.Loot_IsValuable({ classID = 17, subclassID = 0, quality = 3 }), true, "battle pet")
	eq(ns.Loot_IsValuable({ classID = 15, subclassID = 4, quality = 1, toy = true }), true, "toy")
	eq(ns.Loot_IsValuable({ classID = 15, subclassID = 0, quality = 4 }), true, "set token")
	eq(ns.Loot_IsValuable({ classID = 15, subclassID = 0, quality = 3 }), false, "blue junk")
	eq(ns.Loot_IsValuable({ classID = 4, subclassID = 2, quality = 5 }), true, "legendary")
	eq(ns.Loot_IsValuable({ classID = 4, subclassID = 2, quality = 4 }), false, "epic gear")
	eq(ns.Loot_IsValuable({}), false, "nothing known")
	eq(ns.Loot_IsValuable({ classID = 15, subclassID = 0 }), false, "misc junk, quality not loaded")
	eq(ns.Loot_IsValuable({ classID = 15, subclassID = 5 }), true, "a mount needs no quality")
	eq(ns.Loot_IsValuable({ classID = 15, subclassID = 0, quality = 4 }), true, "epic misc")
	eq(ns.Loot_IsValuable({ classID = 15, subclassID = 0, quality = 3 }), false, "rare misc")
	eq(ns.Loot_IsValuable({ classID = 4, subclassID = 2 }), false, "gear, quality not loaded")
end)

test("currency gains: real currencies only, not the game's hidden trackers", function()
	local function info(over)
		local t = { name = "Restored Coffer Key", discovered = true, iconFileID = 4622270,
			description = "Unlocks a Bountiful Coffer." }
		for k, v in pairs(over or {}) do
			t[k] = v
		end
		return t
	end
	eq(ns.Loot_IsShownCurrency(info()), true, "a real currency")
	eq(ns.Loot_IsShownCurrency(info({ name = "11.0 Delves - System - Seasonal Affix - Events Active",
		description = "" })), false, "no description: a tracker")
	eq(ns.Loot_IsShownCurrency(info({ description = "Tracks something (Hidden)" })), false, "marked hidden")
	eq(ns.Loot_IsShownCurrency(info({ description = "DNT tracker" })), false, "marked do not translate")
	eq(ns.Loot_IsShownCurrency(info({ iconFileID = 134400 })), false, "question mark icon")
	eq(ns.Loot_IsShownCurrency(info({ iconFileID = 0 })), false, "no icon")
	eq(ns.Loot_IsShownCurrency(info({ discovered = false })), false, "never earned")
	eq(ns.Loot_IsShownCurrency(info({ isHeader = true })), false, "a header")
	eq(ns.Loot_IsShownCurrency(nil), false, "no info")
end)

test("reputation lines from the game's strings", function()
	local patterns = ns.Loot_RepPatterns({
		"Reputation with %s increased by %d.",
		"Reputation with %s increased by %d. (+%.1f bonus)",
		nil,
		"Reputation with %s increased.",
		"Your Warband's reputation with %s increased by %d.",
	})
	local faction, amount = ns.Loot_ParseRep("Reputation with Council of Dornogal increased by 250.", patterns)
	eq(faction, "Council of Dornogal")
	eq(amount, 250)
	faction, amount = ns.Loot_ParseRep("Reputation with The Assembly increased by 75. (+18.8 bonus)", patterns)
	eq(faction, "The Assembly", "bonus variant")
	eq(amount, 75)
	faction, amount = ns.Loot_ParseRep("Your Warband's reputation with Hallowfall Arathi increased by 2,500.", patterns)
	eq(faction, nil, "the game prints %d without separators; anything else isn't its line")
	faction, amount = ns.Loot_ParseRep("Your Warband's reputation with Hallowfall Arathi increased by 2500.", patterns)
	eq(faction, "Hallowfall Arathi", "warband")
	eq(amount, 2500)
	faction, amount = ns.Loot_ParseRep("Reputation with Kesha's Friends increased.", patterns)
	eq(faction, "Kesha's Friends", "generic")
	eq(amount, nil)
	eq(ns.Loot_ParseRep("You receive loot: Linen Cloth.", patterns), nil, "not a reputation line")
end)

test("reputation lines: the generic string alone", function()
	local patterns = ns.Loot_RepPatterns({ "Reputation with %s increased." })
	local faction, amount = ns.Loot_ParseRep("Reputation with Mira's Crew increased.", patterns)
	eq(faction, "Mira's Crew")
	eq(amount, nil)
	eq(ns.Loot_ParseRep("Reputation with Mira's Crew increased by 10.", patterns), nil, "not the generic line")
end)

test("reputation lines: positional German string", function()
	local patterns = ns.Loot_RepPatterns({ "Euer Ruf bei der Fraktion '%1$s' hat sich um %2$d verbessert." })
	local faction, amount = ns.Loot_ParseRep("Euer Ruf bei der Fraktion 'Aldric' hat sich um 10 verbessert.", patterns)
	eq(faction, "Aldric")
	eq(amount, 10)
end)

test("recently shown", function()
	local recent = {}
	eq(ns.Loot_RecentHas(recent, "i:1", 10, 3), false, "never")
	ns.Loot_RecentNote(recent, "i:1", 10)
	eq(ns.Loot_RecentHas(recent, "i:1", 12, 3), true, "within the window")
	eq(ns.Loot_RecentHas(recent, "i:1", 14, 3), false, "after it")
	eq(ns.Loot_RecentHas(recent, "i:2", 12, 3), false, "another key")
end)

H.done()
