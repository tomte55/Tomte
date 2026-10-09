-- Run from the AddOns folder: lua Tomte/tests/test_achievements.lua
local ns = {}
assert(loadfile("Tomte/Modules/Achievements/Data.lua"))("Tomte", ns)

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

local function crit(name, completed, quantity, required)
	return { name = name, completed = completed, quantity = quantity or 0, required = required or 0 }
end

-- Percent --------------------------------------------------------------------------------------------------

test("Percent counts completed criteria as 1 and partial ones by quantity", function()
	local percent, done, total, last = ns.Ach_Percent({
		crit("A", true), crit("B", false, 5, 10), crit("C", false, 0, 4), crit("D", true),
	})
	eq(percent, 62.5)
	eq(done, 2)
	eq(total, 4)
	eq(last, nil, "two left")
end)

test("Percent is nil without criteria", function()
	eq(ns.Ach_Percent({}), nil)
	eq(ns.Ach_Percent(nil), nil)
end)

test("Percent treats a zero required quantity as no progress", function()
	local percent = ns.Ach_Percent({ crit("A", false, 3, 0), crit("B", true) })
	eq(percent, 50)
end)

test("Percent names the last criterion when one is left", function()
	local percent, done, total, last = ns.Ach_Percent({ crit("A", true), crit("B", true), crit("Kill Bob", false) })
	eq(done, 2)
	eq(total, 3)
	eq(last, "Kill Bob")
end)

test("Percent caps a quantity above the requirement", function()
	eq(ns.Ach_Percent({ crit("A", false, 12, 10) }), 100)
end)

test("Percent shows a single counted criterion as its quantity", function()
	local percent, done, total, last, have, need = ns.Ach_Percent({ crit("", false, 198, 200) })
	eq(percent, 99)
	eq(done, 0)
	eq(total, 1)
	eq(last, nil, "unnamed criterion")
	eq(have, 198)
	eq(need, 200)
	eq(ns.Ach_ProgressText({ percent = percent, have = have, need = need }), "99%  -  198/200")
end)

test("Percent shows criteria counts when there are several", function()
	local _, _, _, _, have, need = ns.Ach_Percent({ crit("A", true), crit("B", false, 5, 10) })
	eq(have, 1)
	eq(need, 2)
end)

-- Milestones -----------------------------------------------------------------------------------------------

local function state(percent, done, total)
	return { percent = percent, done = done, total = total }
end

test("Milestone: crossing the threshold is almost", function()
	eq(ns.Ach_Milestone(state(70, 7, 10), state(80, 8, 10), 80, false, {}), "almost")
end)

test("Milestone: already above the threshold is nothing", function()
	eq(ns.Ach_Milestone(state(80, 8, 10), state(85, 8, 10), 80, false, {}), nil)
end)

test("Milestone: one step left beats almost", function()
	eq(ns.Ach_Milestone(state(60, 3, 5), state(80, 4, 5), 80, false, {}), "lastStep")
end)

test("Milestone: one step left needs two or more criteria", function()
	eq(ns.Ach_Milestone(state(50, 0, 1), state(60, 0, 1), 80, false, {}), nil)
end)

test("Milestone: pinned progress", function()
	eq(ns.Ach_Milestone(state(20, 2, 10), state(30, 3, 10), 80, true, {}), "pinned")
	eq(ns.Ach_Milestone(state(20, 2, 10), state(25, 2, 10), 80, true, {}), "pinned", "quantity only")
	eq(ns.Ach_Milestone(state(20, 2, 10), state(20, 2, 10), 80, true, {}), nil, "no change")
end)

test("Milestone: almost and last step fire once, pinned repeats", function()
	eq(ns.Ach_Milestone(state(70, 7, 10), state(80, 8, 10), 80, false, { almost = true }), nil)
	eq(ns.Ach_Milestone(state(60, 3, 5), state(80, 4, 5), 80, false, { lastStep = true }), "almost")
	eq(ns.Ach_Milestone(state(20, 2, 10), state(30, 3, 10), 80, true, { pinned = true }), "pinned")
end)

test("Milestone: nothing without a before state (first scan)", function()
	eq(ns.Ach_Milestone(nil, state(90, 9, 10), 80, true, {}), nil)
end)

-- Rewards and expansions -----------------------------------------------------------------------------------

test("RewardTypeFromText", function()
	eq(ns.Ach_RewardTypeFromText("Title Reward: the Patient"), "title")
	eq(ns.Ach_RewardTypeFromText("Title: Hand of A'dal"), "title")
	eq(ns.Ach_RewardTypeFromText("Reward: Reins of the Bronze Drake"), "other")
	eq(ns.Ach_RewardTypeFromText(""), nil)
	eq(ns.Ach_RewardTypeFromText(nil), nil)
end)

test("ExpansionFromChain finds the first expansion name", function()
	eq(ns.Ach_ExpansionFromChain({ "Midnight Dungeon", "Dungeons & Raids" }), "Midnight")
	eq(ns.Ach_ExpansionFromChain({ "Zones", "The War Within", "Exploration" }), "The War Within")
	eq(ns.Ach_ExpansionFromChain({ "Battle for Azeroth" }), "Battle for Azeroth")
	eq(ns.Ach_ExpansionFromChain({ "Eastern Kingdoms", "Classic" }), "Classic")
	eq(ns.Ach_ExpansionFromChain({ "Wrath of the Lich King Raid" }), "Wrath of the Lich King")
	eq(ns.Ach_ExpansionFromChain({ "Pet Battles" }), nil)
	eq(ns.Ach_ExpansionFromChain({}), nil)
end)

test("ExpansionFromChain by category ID, in any client language", function()
	-- Dungeons & Raids (168) > Midnight (15542) > Midnight Dungeon (15541), as a German client names them
	eq(ns.Ach_ExpansionFromChain({ "Dungeons von Mitternacht", "Mitternacht", "Dungeons & Schlachtzüge" },
		{ 15541, 15542, 168 }), "Midnight")
	eq(ns.Ach_ExpansionFromChain({ "Ruf", "Klassisch" }, { 14864, 201 }), "Classic", "nearest first")
	eq(ns.Ach_ExpansionFromChain({ "Haustierkämpfe" }, { 15117 }), nil)
	eq(ns.Ach_ExpansionFromChain({ "Legion Remix" }, { 999999 }), "Legion", "unknown ID: English name")
	-- the ID and the English name agree on an English client
	eq(ns.Ach_ExpansionFromChain({ "Cataclysm Raid", "Dungeons & Raids" }, { 15068, 168 }), "Cataclysm")
end)

test("RewardTypeFromText in the client's language", function()
	_G.HONOR_REWARD_TITLE_TOOLTIP = "Titel"
	local de = {}
	assert(loadfile("Tomte/Modules/Achievements/Data.lua"))("Tomte", de)
	_G.HONOR_REWARD_TITLE_TOOLTIP = nil
	eq(de.Ach_RewardTypeFromText("Titel: Der/Die Geduldige"), "title")
	eq(de.Ach_RewardTypeFromText("Title: Dämonentöter(in)"), "title", "some German texts keep the English word")
	eq(de.Ach_RewardTypeFromText("Belohnung: Zügel des Bronzedrachen"), "other")
end)

-- Filters --------------------------------------------------------------------------------------------------

local function settings(extra)
	local s = {
		threshold = 80, reward = "any", showIgnored = false, categories = {}, expansions = {},
		professions = "mine", events = "running",
	}
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

local function record(extra)
	local r = { id = 1, name = "Glory of the Delver", percent = 90, done = 9, total = 10, top = "Delves",
		catName = "Delves", reward = "" }
	for k, v in pairs(extra or {}) do
		r[k] = v
	end
	return r
end

local function ctx(extra)
	local c = { pinned = {}, ignored = {}, professions = {}, holidays = {}, searchText = "",
		rewardInfo = function()
			return nil
		end }
	for k, v in pairs(extra or {}) do
		c[k] = v
	end
	return c
end

test("Passes: threshold", function()
	eq(ns.Ach_Passes(record(), settings(), ctx()), true)
	eq(ns.Ach_Passes(record({ percent = 79.9 }), settings(), ctx()), false)
end)

test("Passes: ignored, unless shown", function()
	local c = ctx({ ignored = { [1] = true } })
	eq(ns.Ach_Passes(record(), settings(), c), false)
	eq(ns.Ach_Passes(record(), settings({ showIgnored = true }), c), true)
end)

test("Passes: category and expansion switched off", function()
	eq(ns.Ach_Passes(record(), settings({ categories = { Delves = false } }), ctx()), false)
	eq(ns.Ach_Passes(record({ expansion = "Midnight" }), settings({ expansions = { Midnight = false } }), ctx()), false)
	eq(ns.Ach_Passes(record(), settings({ expansions = { Other = false } }), ctx()), false, "no expansion = Other")
	eq(ns.Ach_Passes(record({ expansion = "Legion" }), settings({ expansions = { Midnight = false } }), ctx()), true)
end)

test("Passes: professions mode", function()
	local r = record({ top = "Professions", topID = 169, catName = "Cooking", name = "Kickin' Kitchen" })
	eq(ns.Ach_Passes(r, settings(), ctx({ professions = { "Cooking" } })), true)
	eq(ns.Ach_Passes(r, settings(), ctx({ professions = { "Mining" } })), false)
	eq(ns.Ach_Passes(r, settings({ professions = "all" }), ctx()), true)
	eq(ns.Ach_Passes(r, settings({ professions = "none" }), ctx({ professions = { "Cooking" } })), false)
	local byCrit = record({ top = "Professions", topID = 169, catName = "Professions", critNames = { "Midnight Mining" } })
	eq(ns.Ach_Passes(byCrit, settings(), ctx({ professions = { "Mining" } })), true, "criterion name")
	-- By category ID, not name: a German client's "Berufe" still counts, a "Professions" name with another ID doesn't.
	local de = record({ top = "Berufe", topID = 169, catName = "Kochkunst" })
	eq(ns.Ach_Passes(de, settings(), ctx({ professions = { "Bergbau" } })), false, "localized top")
	eq(ns.Ach_Passes(record({ top = "Professions", topID = 15522 }), settings({ professions = "none" }), ctx()), true)
end)

test("Passes: world events mode", function()
	local r = record({ top = "World Events", topID = 155, catName = "Hallow's End" })
	eq(ns.Ach_Passes(r, settings(), ctx({ holidays = { "hallow's end" } })), true)
	eq(ns.Ach_Passes(r, settings(), ctx({ holidays = { "brewfest" } })), false)
	eq(ns.Ach_Passes(r, settings({ events = "all" }), ctx()), true)
	eq(ns.Ach_Passes(r, settings({ events = "none" }), ctx({ holidays = { "hallow's end" } })), false)
	local fr = record({ top = "Évènements mondiaux", topID = 155, catName = "Sanssaint" })
	eq(ns.Ach_Passes(fr, settings({ events = "none" }), ctx()), false, "localized top")
end)

test("Passes: reward filters", function()
	local mount = record({ reward = "Reward: Reins" })
	local function info(type, owned)
		return function()
			return { type = type, owned = owned }
		end
	end
	eq(ns.Ach_Passes(record(), settings({ reward = "reward" }), ctx()), false, "no reward")
	eq(ns.Ach_Passes(mount, settings({ reward = "reward" }), ctx({ rewardInfo = info("mount", true) })), true)
	eq(ns.Ach_Passes(mount, settings({ reward = "new" }), ctx({ rewardInfo = info("mount", true) })), false, "owned")
	eq(ns.Ach_Passes(mount, settings({ reward = "new" }), ctx({ rewardInfo = info("mount", false) })), true)
	eq(ns.Ach_Passes(mount, settings({ reward = "mount" }), ctx({ rewardInfo = info("mount", false) })), true)
	eq(ns.Ach_Passes(mount, settings({ reward = "pet" }), ctx({ rewardInfo = info("mount", false) })), false)
	eq(ns.Ach_Passes(mount, settings({ reward = "title" }), ctx({ rewardInfo = info("title", false) })), true)
end)

test("Passes: search is plain text over name, reward and criteria", function()
	eq(ns.Ach_Passes(record(), settings(), ctx({ searchText = "delver" })), true)
	eq(ns.Ach_Passes(record(), settings(), ctx({ searchText = "raider" })), false)
	eq(ns.Ach_Passes(record({ reward = "Title Reward: 100%" }), settings(), ctx({ searchText = "100%" })), true)
	eq(ns.Ach_Passes(record(), settings(), ctx({ searchText = "[%" })), false, "pattern characters")
	eq(ns.Ach_Passes(record({ critNames = { "Zekvir" } }), settings(), ctx({ searchText = "zek" })), true)
end)

test("Passes: pins skip the threshold and filters, not search", function()
	local c = ctx({ pinned = { [1] = true } })
	eq(ns.Ach_Passes(record({ percent = 5 }), settings({ categories = { Delves = false } }), c), true)
	c.searchText = "raider"
	eq(ns.Ach_Passes(record({ percent = 5 }), settings(), c), false)
end)

-- Sort and Top N -------------------------------------------------------------------------------------------

local function names(list)
	local out = {}
	for i, r in ipairs(list) do
		out[i] = r.name
	end
	return table.concat(out, ",")
end

local SORT_SET = {
	{ id = 1, name = "b", percent = 90, points = 10, done = 9, total = 10 },
	{ id = 2, name = "a", percent = 90, points = 5, done = 1, total = 2 },
	{ id = 3, name = "c", percent = 95, points = 25, done = 18, total = 20 },
}

local function copy(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

test("Sort modes", function()
	local list = copy(SORT_SET)
	ns.Ach_Sort(list, "percent")
	eq(names(list), "c,a,b")
	ns.Ach_Sort(list, "points")
	eq(names(list), "c,b,a")
	ns.Ach_Sort(list, "name")
	eq(names(list), "a,b,c")
	ns.Ach_Sort(list, "steps")
	eq(names(list), "a,b,c", "fewest left, then percent, then name")
end)

test("TopN: pins first in pin order, then the list", function()
	local byID = { [1] = SORT_SET[1], [2] = SORT_SET[2], [3] = SORT_SET[3], [4] = { id = 4, name = "d", percent = 10 } }
	local list = copy(SORT_SET)
	ns.Ach_Sort(list, "percent")
	local top = ns.Ach_TopN(list, { 4, 99, 2 }, byID, 3)
	eq(names(top), "d,a,c")
	eq(top[1].pinned, true)
	eq(top[3].pinned, nil)
end)

test("TopN: fewer than n", function()
	eq(#ns.Ach_TopN({}, {}, {}, 5), 0)
end)

test("MetaPercent", function()
	local percent, done, total = ns.Ach_MetaPercent({
		{ completed = true }, { completed = false, percent = 50 }, { completed = false },
		{ completed = true },
	})
	eq(percent, 62.5)
	eq(done, 2)
	eq(total, 4)
	eq((ns.Ach_MetaPercent({})), 0)
end)

print(failures == 0 and "all passed" or (failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
