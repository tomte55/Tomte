-- Run from the AddOns folder: lua Tomte/tests/test_quests.lua
local ns = {}
assert(loadfile("Tomte/Modules/Quests/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local RULES = { skipRepeatable = true, skipTrivial = false, skipDoneElsewhere = false, skipCosts = true }
local ALL_OFF = { skipRepeatable = false, skipTrivial = false, skipDoneElsewhere = false, skipCosts = false }

test("skip key follows the setting", function()
	eq(ns.Quests_SkipKeyDown("shift", true, false, false), true)
	eq(ns.Quests_SkipKeyDown("shift", false, true, true), false)
	eq(ns.Quests_SkipKeyDown("ctrl", false, true, false), true)
	eq(ns.Quests_SkipKeyDown("ctrl", true, false, false), false)
	eq(ns.Quests_SkipKeyDown("alt", nil, nil, true), true)
	eq(ns.Quests_SkipKeyDown("alt", true, true, nil), false)
	eq(ns.Quests_SkipKeyDown(nil, true), true, "unknown setting: Shift")
end)

test("NPC ID from a GUID", function()
	eq(ns.Quests_NpcID("Creature-0-3767-2552-28-214296-00006A1B2C"), 214296)
	eq(ns.Quests_NpcID("GameObject-0-3767-2552-28-123456-00006A1B2C"), 123456)
	eq(ns.Quests_NpcID("Vehicle-0-3767-2552-28-204450-00006A1B2C"), 204450)
	eq(ns.Quests_NpcID("Player-1234-0ABCDEF0"), nil)
	eq(ns.Quests_NpcID(nil), nil)
end)

test("accept: daily, weekly and repeatable are skipped by default", function()
	local ok, why = ns.Quests_ShouldAccept({ frequency = 1 }, RULES)
	eq(ok, false)
	eq(why, "a daily quest")
	ok, why = ns.Quests_ShouldAccept({ frequency = 2 }, RULES)
	eq(why, "a weekly quest")
	ok, why = ns.Quests_ShouldAccept({ frequency = 0, repeatable = true }, RULES)
	eq(why, "a repeatable quest")
	eq((ns.Quests_ShouldAccept({ frequency = 1 }, ALL_OFF)), true)
	eq((ns.Quests_ShouldAccept({ frequency = 0 }, RULES)), true)
end)

test("accept: trivial and done elsewhere follow their switches", function()
	eq((ns.Quests_ShouldAccept({ trivial = true }, RULES)), true)
	eq((ns.Quests_ShouldAccept({ trivial = true }, { skipTrivial = true })), false)
	eq((ns.Quests_ShouldAccept({ doneElsewhere = true }, RULES)), true)
	local ok, why = ns.Quests_ShouldAccept({ doneElsewhere = true }, { skipDoneElsewhere = true })
	eq(ok, false)
	eq(why, "already done on another character")
end)

test("accept: PvP and item-offered quests are never accepted", function()
	eq((ns.Quests_ShouldAccept({ pvp = true }, ALL_OFF)), false)
	eq((ns.Quests_ShouldAccept({ fromItem = true }, ALL_OFF)), false)
end)

test("turn in: costs and repeatables", function()
	eq((ns.Quests_ShouldTurnIn({ completable = true }, RULES)), true)
	eq((ns.Quests_ShouldTurnIn({ completable = false }, ALL_OFF)), false)
	eq((ns.Quests_ShouldTurnIn({}, RULES)), true, "reward step: completable unknown")
	local ok, why = ns.Quests_ShouldTurnIn({ completable = true, money = 5000 }, RULES)
	eq(ok, false)
	eq(why, "the turn-in costs gold")
	ok, why = ns.Quests_ShouldTurnIn({ completable = true, currencies = 1 }, RULES)
	eq(why, "the turn-in costs a currency")
	eq((ns.Quests_ShouldTurnIn({ completable = true, money = 5000 }, ALL_OFF)), true)
	eq((ns.Quests_ShouldTurnIn({ completable = true, frequency = 1 }, RULES)), false)
end)

test("reward choice", function()
	eq(ns.Quests_RewardChoice(0, nil, false), 0)
	eq(ns.Quests_RewardChoice(nil, nil, true), 0)
	eq(ns.Quests_RewardChoice(1, nil, false), 1)
	eq(ns.Quests_RewardChoice(3, 2, false), nil, "not asked to pick")
	eq(ns.Quests_RewardChoice(3, nil, true), nil, "Gear Check not sure")
	eq(ns.Quests_RewardChoice(3, 2, true), 2)
	eq(ns.Quests_RewardChoice(3, 4, true), nil, "out of range")
end)

test("pick quest: finished first, then one to accept, tried ones skipped", function()
	local active = { { questID = 1, title = "Open", complete = false },
		{ questID = 2, title = "Done", complete = true } }
	local available = { { questID = 3, title = "Daily", frequency = 1 }, { questID = 4, title = "New" } }
	local kind, q = ns.Quests_PickQuest(active, available, {}, RULES)
	eq(kind, "active")
	eq(q.questID, 2)
	local passed
	kind, q, passed = ns.Quests_PickQuest(active, available, { [2] = true }, RULES)
	eq(kind, "available")
	eq(q.questID, 4)
	eq(passed[1], "Daily: a daily quest")
	kind = ns.Quests_PickQuest(active, available, { [2] = true, [4] = true }, RULES)
	eq(kind, nil)
end)

test("pick quest: a finished daily isn't handed in while dailies are skipped", function()
	local active = { { questID = 5, title = "Bones", complete = true, frequency = 1 } }
	local kind, _, passed = ns.Quests_PickQuest(active, {}, {}, RULES)
	eq(kind, nil)
	eq(passed[1], "Bones: a daily quest")
end)

local function option(id, flags, extra)
	local o = { gossipOptionID = id, flags = flags or 0, status = 0, icon = 132053 }
	for k, v in pairs(extra or {}) do
		o[k] = v
	end
	return o
end

test("gossip: the one quest-step option", function()
	local options = { option(10), option(11, 1), option(12) }
	local i, why = ns.Quests_GossipPick(options, {}, {})
	eq(i, 2)
	eq(why, "the quest step")
	eq((ns.Quests_GossipPick({ option(10, 1), option(11, 1) }, {}, {})), nil, "two quest steps: the player picks")
	eq((ns.Quests_GossipPick({ option(10, 5) }, {}, {}, { questStep = true })), 1, "flags with more bits set")
end)

test("gossip: the only option, once per conversation", function()
	eq((ns.Quests_GossipPick({ option(20) }, {}, {})), 1)
	eq((ns.Quests_GossipPick({ option(20) }, {}, { [20] = true })), nil)
	eq((ns.Quests_GossipPick({ option(20) }, {}, {}, { only = true, hasQuests = true })), nil, "quests come first")
	eq((ns.Quests_GossipPick({ option(20) }, {}, {}, { only = false })), nil)
	local i, why = ns.Quests_GossipPick({ option(20, 0, { selectOptionWhenOnlyOption = true }) }, {}, {})
	eq(i, nil)
	eq(why, "the game picks this one itself")
	i, why = ns.Quests_GossipPick({ option(21) }, {}, {}, { only = true, onlyPicked = true })
	eq(i, nil, "once per conversation, even for a new option on the next page")
	eq(why, "an only option was already picked in this conversation")
	local _, _, rule = ns.Quests_GossipPick({ option(21) }, {}, {}, { only = true })
	eq(rule, "only")
end)

test("gossip: the only option must be plain talk, outside instances, not forced", function()
	local ONLY = { only = true }
	eq((ns.Quests_GossipPick({ option(40, 0, { icon = 1019848 }) }, {}, {}, ONLY)), 1, "chat bubble icon")
	eq((ns.Quests_GossipPick({ option(40, 0, { icon = 132060 }) }, {}, {}, ONLY)), nil, "vendor icon")
	eq((ns.Quests_GossipPick({ option(40, 0, { icon = 132060, overrideIconID = 132053 }) }, {}, {}, ONLY)), 1,
		"override icon wins")
	eq((ns.Quests_GossipPick({ option(40, 0, { overrideIconID = 136458 }) }, {}, {}, ONLY)), nil,
		"override to a service icon")
	eq((ns.Quests_GossipPick({ option(40, 0, { spellID = 1234 }) }, {}, {}, ONLY)), nil, "casts a spell")
	eq((ns.Quests_GossipPick({ option(40, 4) }, {}, {}, ONLY)), nil, "plays a movie")
	eq((ns.Quests_GossipPick({ option(40) }, {}, {}, { only = true, forceGossip = true })), nil, "forced gossip")
	local i, why = ns.Quests_GossipPick({ option(40) }, {}, {}, { only = true, inInstance = true })
	eq(i, nil)
	eq(why, "only options aren't picked in instances")
end)

test("gossip: quest steps and event sign-ups keep working in instances and with any icon", function()
	local rules = { questStep = true, events = true, only = true, inInstance = true, forceGossip = true }
	eq((ns.Quests_GossipPick({ option(50, 1, { icon = 132060 }) }, {}, {}, rules)), 1, "quest step")
	local i, _, rule = ns.Quests_GossipPick({ option(120733, 0, { icon = 132060 }) }, { [120733] = "x" }, {}, rules)
	eq(i, 1)
	eq(rule, "event")
end)

test("repeat kind", function()
	eq(ns.Quests_RepeatKind({ frequency = 3 }), "repeatable", "resets by schedule")
	eq(ns.Quests_RepeatKind({ frequency = 0 }), nil)
	eq(ns.Quests_RepeatKind({}), nil)
end)

test("gossip: event sign-ups win, unavailable and ID-less options never", function()
	local options = { option(30), option(120733), option(31, 1) }
	local i, why = ns.Quests_GossipPick(options, { [120733] = "Theater Troupe" }, {})
	eq(i, 2)
	eq(why, "event: Theater Troupe")
	eq((ns.Quests_GossipPick({ option(120733, 0, { status = 1 }) }, { [120733] = "x" }, {})), nil)
	eq((ns.Quests_GossipPick({ { flags = 0, status = 0 } }, {}, {})), nil, "no ID")
	eq((ns.Quests_GossipPick(options, { [120733] = "x" }, {}, { events = false, questStep = true })), 3)
end)

test("cinematic policy", function()
	local seen = { [960] = true }
	eq(ns.Quests_SkipCinematic("off", "movie", 960, seen, true), false)
	eq(ns.Quests_SkipCinematic("all", "movie", 961, seen, false), true)
	eq(ns.Quests_SkipCinematic("all", "cinematic", nil, seen, false), true)
	eq(ns.Quests_SkipCinematic("seen", "movie", 960, seen, false), true)
	eq(ns.Quests_SkipCinematic("seen", "movie", 961, seen, false), false)
	eq(ns.Quests_SkipCinematic("seen", "cinematic", nil, seen, false), false)
	eq(ns.Quests_SkipCinematic("seen", "cinematic", nil, seen, true), true)
end)

test("talking head action", function()
	local rules = { hideInInstance = true, hideWorldQuest = false }
	eq(ns.Quests_TalkingHeadAction("off", {}, rules), "blizzard")
	eq(ns.Quests_TalkingHeadAction("hide", {}, rules), "hide")
	eq(ns.Quests_TalkingHeadAction("text", {}, rules), "text")
	eq(ns.Quests_TalkingHeadAction("text", { inInstance = true }, rules), "hide")
	eq(ns.Quests_TalkingHeadAction("text", { worldQuest = true }, rules), "text")
	eq(ns.Quests_TalkingHeadAction("text", { worldQuest = true }, { hideWorldQuest = true }), "hide")
end)

test("quest item state", function()
	eq((ns.Quests_ItemQuestState({ onQuest = true, ready = true })), "In your quest log, ready to hand in")
	eq((ns.Quests_ItemQuestState({ onQuest = true })), "In your quest log")
	eq((ns.Quests_ItemQuestState({ done = true, doneOnAccount = true })), "Already done")
	eq((ns.Quests_ItemQuestState({ doneOnAccount = true })), "Not done here, done on another character")
	local text, role = ns.Quests_ItemQuestState({})
	eq(text, "Not started")
	eq(role, "warning")
end)

test("race medals from the aura text", function()
	local lines = {
		"Your best times:",
		"|cffffd100Course|r",
		"|A:challenges-medal-small-gold:12:12|a 52.1",
		"|CFFFFD100Advanced Course|r",
		"No attempts",
		"Gold time: 60.0",
		"|cffffd100Reverse Course|r",
		"|A:challenges-medal-small-bronze:12:12|a 70.3",
	}
	local medals, titles = ns.Quests_RaceMedals(lines)
	eq(#medals, 3)
	eq(medals[1], "challenges-medal-small-gold")
	eq(medals[2], false)
	eq(medals[3], "challenges-medal-small-bronze")
	eq(titles[1], "Course")
	eq(titles[2], "Advanced Course")
	eq(#ns.Quests_RaceMedals({ "nothing here" }), 0)
end)

test("race medals: a title with no record line after it", function()
	local medals, titles = ns.Quests_RaceMedals({ "|cffffd100Course|r", "|A:x-medal-small-silver|a 1",
		"|cffffd100Last Course|r" })
	eq(#medals, 2)
	eq(medals[1], "x-medal-small-silver")
	eq(medals[2], false)
	eq(titles[2], "Last Course")
end)

test("race medals go on course options only", function()
	local medals = { "gold", false, "bronze" }
	local titles = { "Course", "Advanced Course", "Reverse Course" }
	local options = { { name = "Tell me about the races" }, { name = "Reverse Course" }, { name = "Course" },
		{ name = "Advanced Course" } }
	local marks = ns.Quests_RaceMedalOptions(medals, titles, options)
	eq(marks[1], nil, "not a course")
	eq(marks[3], "gold")
	eq(marks[4], nil, "no medal on the advanced course")
	eq(marks[2], "bronze")
	-- Names that don't match: by order only when every option is a course.
	marks = ns.Quests_RaceMedalOptions(medals, titles, { { name = "Zap" }, { name = "Zip" }, { name = "Zop" } })
	eq(marks[1], "gold")
	eq(marks[3], "bronze")
	marks = ns.Quests_RaceMedalOptions(medals, titles, { { name = "Zap" }, { name = "Zip" }, { name = "Zop" },
		{ name = "Zup" } })
	eq(next(marks), nil, "an extra option: no guessing")
end)

H.done()
