-- Run from the AddOns folder: lua Tomte/tests/test_delves.lua
local ns = {}
assert(loadfile("Tomte/Core/Content.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/WarWithin/Delves.lua"))("Tomte", ns)
assert(loadfile("Tomte/Data/Midnight/Delves.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Delves/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("delves data for both expansions", function()
	for _, e in ipairs({ 10, 11 }) do
		local d = ns.Content_Get(e, "delves")
		assert(d, "expansion " .. e)
		assert(#d.zones >= 4, "zones " .. e)
		eq(d.keyCurrency, 3028, "key currency " .. e)
		eq(d.shardsPerKey, 100, "shards per key " .. e)
		assert(d.shards.items or d.shards.currency, "shards " .. e)
		assert(d.companionFaction, "companion " .. e)
		eq(d.vaultTopTier, 8, "top tier " .. e)
	end
	eq(ns.Content_Get(10, "delves").companionFaction, 2640)
	eq(ns.Content_Get(11, "delves").companionFaction, 2744)
	eq(ns.Content_Get(11, "delves").shards.currency, 3310)
	assert(ns.Content_Get(10, "delves").bountifulPOIs[7783], "The Sinkhole bountiful")
end)

test("bountiful by atlas, by ID, neither", function()
	eq(ns.Delves_IsBountiful({ poi = 1, atlas = "delves-bountiful" }, nil), true, "atlas")
	eq(ns.Delves_IsBountiful({ poi = 7783, atlas = "delves-regular" }, { [7783] = true }), true, "id")
	eq(ns.Delves_IsBountiful({ poi = 7870, atlas = "delves-regular" }, { [7783] = true }), false, "neither")
	eq(ns.Delves_IsBountiful({ poi = 7870 }, nil), false, "no atlas, no list")
end)

test("sort: bountiful, then my zone, then name", function()
	local list = {
		{ poi = 1, map = 2, name = "B" },
		{ poi = 2, map = 1, name = "C" },
		{ poi = 3, map = 2, name = "A", bountiful = true },
		{ poi = 4, map = 1, name = "D", bountiful = true },
		{ poi = 5, map = 1, name = "A" },
	}
	ns.Delves_Sort(list, 1)
	eq(list[1].poi, 4, "bountiful in my zone")
	eq(list[2].poi, 3, "bountiful elsewhere")
	eq(list[3].poi, 5, "my zone A")
	eq(list[4].poi, 2, "my zone C")
	eq(list[5].poi, 1, "elsewhere")
	eq(#ns.Delves_Sort({}, 1), 0, "empty")
end)

test("earned keys from Weekly's curated list", function()
	local curated = { { group = "Delves", entries = {
		{ label = "The Key to Success", state = "done" },
		{ label = "Restored Coffer Keys", kind = "keys", n = 3, of = 4 },
		{ label = "Coffer Key Shards", kind = "shards", n = 1, of = 4 },
	} } }
	local k = ns.Delves_Earned(curated, "keys")
	eq(k.n, 3)
	eq(k.of, 4)
	eq(ns.Delves_Earned(curated, "missing"), nil, "unknown kind")
	eq(ns.Delves_Earned(nil, "keys"), nil, "no list")
end)

test("key line", function()
	local text, combine = ns.Delves_KeyLine({ keys = 2, shards = 140, perKey = 100, earned = { n = 3, of = 4 } })
	eq(text, "2 keys · 140 shards (1 more key) · keys this week 3/4")
	eq(combine, true)
	text, combine = ns.Delves_KeyLine({ keys = 1, shards = 40, perKey = 100, shardWeek = { n = 200, of = 600 } })
	eq(text, "1 key · 40 shards, 200/600 this week")
	eq(combine, false)
	text = ns.Delves_KeyLine({ keys = 0 })
	eq(text, "0 keys")
end)

test("vault plan: mixed tiers", function()
	local slots = { { threshold = 2, progress = 5 }, { threshold = 4, progress = 5 }, { threshold = 8, progress = 5 } }
	local runs = { { difficulty = 8, numPoints = 2 }, { difficulty = 5, numPoints = 3 } }
	local plan = ns.Delves_VaultPlan(slots, runs, 8)
	eq(plan.rows[1].tier, 8, "slot 1 tier")
	eq(plan.rows[1].maxed, true, "slot 1 maxed")
	eq(plan.rows[2].tier, 5, "slot 2 tier")
	eq(plan.rows[2].maxed, false, "slot 2 maxed")
	eq(plan.rows[2].need, 2, "slot 2 needs 2 more at the top")
	eq(plan.rows[3].unlocked, false, "slot 3 locked")
	eq(plan.rows[3].tier, nil, "slot 3 tier")
	eq(plan.advice.index, 2, "advice slot")
	eq(plan.text, "Tier 8 or higher: 2 more runs max vault slot 2 (now Tier 5)")
end)

test("vault plan: thresholds 1/4/8, one run short", function()
	local slots = { { threshold = 1, progress = 7 }, { threshold = 4, progress = 7 }, { threshold = 8, progress = 7 } }
	local runs = { { difficulty = 11, numPoints = 4 }, { difficulty = 3, numPoints = 3 } }
	local plan = ns.Delves_VaultPlan(slots, runs, 8)
	eq(plan.rows[2].maxed, true, "4 runs at 11")
	eq(plan.advice.index, 3, "slot 3")
	eq(plan.rows[3].need, 4, "8 - 4")
	eq(plan.text, "Tier 8 or higher: 4 more runs unlock vault slot 3 at the top")
end)

test("vault plan: world activities only", function()
	local slots = { { threshold = 2, progress = 3 }, { threshold = 4, progress = 3 } }
	local plan = ns.Delves_VaultPlan(slots, { { difficulty = 1, numPoints = 3 } }, 8)
	eq(plan.rows[1].unlocked, true)
	eq(plan.rows[1].tier, 1)
	eq(plan.rows[1].maxed, false)
	eq(plan.text, "Tier 8 or higher: 2 more runs max vault slot 1 (now Tier 1)")
end)

test("vault plan: no runs, all maxed, empty inputs", function()
	local plan = ns.Delves_VaultPlan({ { threshold = 2, progress = 0 } }, {}, 8)
	eq(plan.rows[1].unlocked, false)
	eq(plan.text, "Tier 8 or higher: 2 more runs unlock vault slot 1 at the top")
	plan = ns.Delves_VaultPlan({ { threshold = 1, progress = 1 } }, { { difficulty = 9, numPoints = 1 } }, 8)
	eq(plan.advice, nil)
	eq(plan.text, "Every World slot is maxed")
	plan = ns.Delves_VaultPlan({}, {}, 8)
	eq(plan.text, nil, "no slots")
	eq(#plan.rows, 0)
end)

test("vault plan: one run left uses the singular", function()
	local plan = ns.Delves_VaultPlan({ { threshold = 2, progress = 2 } },
		{ { difficulty = 8, numPoints = 1 }, { difficulty = 4, numPoints = 1 } }, 8)
	eq(plan.text, "Tier 8 or higher: 1 more run maxes vault slot 1 (now Tier 4)")
end)

test("ladder: follows the steps to the top", function()
	local steps = { [1] = { 11, 2, 610 }, [2] = { 12, 4, 623 }, [4] = { 13, 8, 649 } }
	local calls = {}
	local ladder, top = ns.Delves_Ladder(function(tierID, level)
		calls[#calls + 1] = tierID
		local s = steps[level]
		if s then
			return true, s[1], s[2], s[3]
		end
		return true, nil, nil, nil
	end, 1, 10)
	eq(top, 8)
	eq(#ladder, 3)
	eq(ladder[3].tier, 8)
	eq(ladder[3].ilvl, 649)
	eq(calls[1], 10, "starts with the given tier ID")
	eq(calls[2], 11, "then the returned one")
	eq(ns.Delves_LadderText(ladder), "Tier 2: 610 · Tier 4: 623 · Tier 8: 649")
end)

test("ladder: no data, stuck", function()
	local ladder, top = ns.Delves_Ladder(function()
		return false
	end, 1, 10)
	eq(ladder, nil, "no season data")
	eq(top, nil)
	local n = 0
	ladder, top = ns.Delves_Ladder(function(_, level)
		n = n + 1
		return true, 10, level, 600 -- never rises
	end, 1, 10)
	eq(#ladder, 0)
	eq(top, 1)
	eq(n, 1, "stops at once")
	eq(ns.Delves_LadderText({}), nil)
end)

test("suggest tier", function()
	local tiers = {
		{ tier = 1, suggestedILvl = 560, unlocked = true },
		{ tier = 7, suggestedILvl = 640, unlocked = true },
		{ tier = 8, suggestedILvl = 650, unlocked = true },
		{ tier = 9, suggestedILvl = 655, unlocked = false },
	}
	eq(ns.Delves_SuggestTier(tiers, 652).tier, 8)
	eq(ns.Delves_SuggestTier(tiers, 660).tier, 8, "locked tier skipped")
	eq(ns.Delves_SuggestTier(tiers, 500), nil, "below every tier")
	eq(ns.Delves_SuggestTier({}, 600), nil)
end)

test("role hint", function()
	local names = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
	eq(ns.Delves_RoleHint("TANK", "TANK", "Brann", names), "Brann is set to Tank: Healer suits a tank")
	eq(ns.Delves_RoleHint("HEALER", "HEALER", "Brann", names), "Brann is set to Healer: Damage suits a healer")
	eq(ns.Delves_RoleHint("DAMAGER", "DAMAGER", "Brann", names), nil, "damage + damage is fine")
	eq(ns.Delves_RoleHint("TANK", "HEALER", "Brann", names), nil)
	eq(ns.Delves_RoleHint(nil, "TANK", "Brann", names), nil)
	eq(ns.Delves_RoleHint("TANK", "TANK", nil, {}), "Your companion is set to tank: healer suits a tank")
end)

test("season companion for another expansion", function()
	eq(ns.Delves_PickCompanionSource({ expansionID = 10, playerCompanionID = 1 }, 10), "season")
	eq(ns.Delves_PickCompanionSource({ expansionID = 11, playerCompanionID = 2 }, 10), "fallback")
	eq(ns.Delves_PickCompanionSource({ expansionID = 10 }, 10), "fallback", "no companion ID")
	eq(ns.Delves_PickCompanionSource(nil, 10), "fallback")
end)

test("track mode", function()
	eq(ns.Delves_TrackMode(2274, 2274), "poi")
	eq(ns.Delves_TrackMode(2274, 2371), "pin")
	eq(ns.Delves_TrackMode(nil, 2274), "pin", "unknown continent")
end)

test("dedupe: a bountiful entrance replaces the same delve's normal one", function()
	local list = ns.Delves_Dedupe({
		{ poi = 7870, map = 2215, name = "The Sinkhole" },
		{ poi = 7783, map = 2215, name = "The Sinkhole", bountiful = true },
		{ poi = 7871, map = 2215, name = "Skittering Breach" },
		{ poi = 9, map = 2214, name = "The Sinkhole" },
	})
	eq(#list, 3)
	eq(list[1].poi, 7783, "bountiful kept in the normal one's place")
	eq(list[2].poi, 7871)
	eq(list[3].poi, 9, "same name on another map stays")
	eq(#ns.Delves_Dedupe({}), 0)
end)

test("bountiful in Next up: with a key or always", function()
	eq(ns.Delves_SuggestBountiful(0, "key"), false)
	eq(ns.Delves_SuggestBountiful(1, "key"), true)
	eq(ns.Delves_SuggestBountiful(0, "always"), true)
	eq(ns.Delves_SuggestBountiful(nil, "key"), false, "keys unread")
end)

test("empty inputs", function()
	eq(#ns.Delves_Sort({}, nil), 0)
	eq(ns.Delves_KeyLine({}), "0 keys")
	eq(ns.Delves_VaultPlan(nil, nil, 8).text, nil)
	eq(ns.Delves_SuggestTier(nil, 600), nil)
	eq(ns.Delves_Earned({}, "keys"), nil)
end)

test("stash data for both expansions", function()
	for _, e in ipairs({ 10, 11 }) do
		local s = ns.Content_Get(e, "delves").stash
		eq(s.spell, 1216211, "stash spell " .. e)
		assert(#s.widgets >= 1, "stash widgets " .. e)
	end
	local cap = ns.Content_Get(10, "delves").capItems
	assert(#cap.keys > 0 and #cap.shards > 0, "cap items")
end)

test("stash count from the widget text", function()
	local n, of = ns.Delves_StashParse("Gilded Stash\nLooted this week: 2/4")
	eq(n, 2, "n")
	eq(of, 4, "of")
	n, of = ns.Delves_StashParse("Diese Woche geplündert: 0 / 3")
	eq(n, 0, "spaced n")
	eq(of, 3, "spaced of")
	eq(ns.Delves_StashParse("no count here"), nil, "no count")
	eq(ns.Delves_StashParse("1/0"), nil, "zero of")
	eq(ns.Delves_StashParse(nil), nil, "nil")
end)

test("stash pick: live, saved this week, stale", function()
	local week = 1000000
	local s = ns.Delves_StashPick({ n = 1, of = 4, accurate = true }, { n = 3, of = 4, week = week }, week)
	eq(s.n, 1, "live accurate wins")
	eq(s.old, nil, "live not old")
	s = ns.Delves_StashPick({ n = 0, of = 4, accurate = false }, { n = 3, of = 4, week = week + 2 }, week)
	eq(s.n, 3, "saved this week (drifted a second or two)")
	eq(s.old, true, "saved is old")
	s = ns.Delves_StashPick(nil, { n = 3, of = 4, week = week - 7 * 86400 }, week)
	eq(s, nil, "last week's saved is dropped")
	s = ns.Delves_StashPick({ n = 2, of = 4, accurate = false }, nil, week)
	eq(s.n, 2, "inaccurate live as fallback")
	eq(s.old, true, "inaccurate is old")
	eq(ns.Delves_StashPick(nil, nil, nil), nil, "nothing")
end)

test("stash text", function()
	eq(ns.Delves_StashText({ n = 1, of = 4 }, "Gilded Stash"), "Gilded Stash: 1/4 this week")
	eq(ns.Delves_StashText({ n = 4, of = 4 }, nil), "Gilded Stash: 4/4 this week (all found)")
	eq(ns.Delves_StashText(nil, "x"), nil)
end)

test("journey fraction", function()
	local near = H.near
	near(ns.Delves_JourneyFraction({ level = 3, earned = 250, threshold = 1000, max = 10 }), 0.25, "quarter")
	near(ns.Delves_JourneyFraction({ level = 10, earned = 0, threshold = 0, max = 10 }), 1, "max")
	near(ns.Delves_JourneyFraction({ level = 3, earned = 50, threshold = 0 }), 0, "no threshold")
	near(ns.Delves_JourneyFraction({ level = 3, earned = 1200, threshold = 1000 }), 1, "clamped")
	near(ns.Delves_JourneyFraction(nil), 0, "nil")
end)

test("cap lines for the key tooltip", function()
	local lines = ns.Delves_CapLines({ keys = 2, perKey = 100, shards = 250, earned = { n = 4, of = 4 },
		shardEarned = { n = 1, of = 4 } }, "keys")
	eq(#lines, 3, "count")
	eq(lines[1].left, "Keys this week")
	eq(lines[1].right, "4/4 (cap reached)")
	eq(lines[1].role, "textMuted")
	eq(lines[2].right, "1/4")
	eq(lines[3].right, "250 (2 more keys)")
	eq(lines[3].role, "success")
	lines = ns.Delves_CapLines({ keys = 0, keyWeek = { n = 1, of = 3 }, earned = { n = 0, of = 4 } }, "keys")
	eq(lines[1].right, "1/3", "the currency's own cap first")
	eq(#lines, 1, "no shards")
end)

test("cap lines for the shard tooltip", function()
	local lines = ns.Delves_CapLines({ perKey = 100, shards = 130, shardWeek = { n = 200, of = 600 } }, "shards")
	eq(lines[1].left, "Shards this week")
	eq(lines[1].right, "200/600")
	eq(lines[2].left, "Next key")
	eq(lines[2].right, "30/100")
	eq(#lines, 2)
	eq(#ns.Delves_CapLines(nil, "keys"), 0, "no keys read yet")
	eq(#ns.Delves_CapLines({ shardWeek = { n = 0, of = 0 } }, "shards"), 0, "no cap")
end)

local function Power(spellID, header, extra)
	local o = { spellID = spellID, header = header, buttons = { { id = spellID * 10 } } }
	for k, v in pairs(extra or {}) do
		o[k] = v
	end
	return o
end

test("preferred powers parse", function()
	local p = ns.Delves_ParsePowers(" Sticky Fingers, 12345 ;Battle Ready ,, ")
	eq(#p, 3, "count")
	eq(p[1].name, "sticky fingers")
	eq(p[2].id, 12345)
	eq(p[3].name, "battle ready")
	eq(#ns.Delves_ParsePowers(nil), 0, "nil")
	eq(#ns.Delves_ParsePowers(""), 0, "empty")
end)

test("power pick: only option, preferred, none", function()
	local o, why = ns.Delves_PickPower({ Power(1, "Alpha") }, {})
	eq(o.spellID, 1, "only")
	eq(why, "only")
	local opts = { Power(1, "Alpha"), Power(2, "Beta"), Power(3, "Gamma") }
	o, why = ns.Delves_PickPower(opts, ns.Delves_ParsePowers("gamma, 2"))
	eq(o.spellID, 3, "first preference wins")
	eq(why, "preferred")
	o = ns.Delves_PickPower(opts, ns.Delves_ParsePowers("delta, 2"))
	eq(o.spellID, 2, "by spell ID")
	o, why = ns.Delves_PickPower(opts, ns.Delves_ParsePowers("delta"))
	eq(o, nil, "no match")
	eq(why, "nomatch")
	o, why = ns.Delves_PickPower({}, {})
	eq(why, "none")
end)

test("power pick: not a power choice", function()
	local _, why = ns.Delves_PickPower({ Power(1, "Alpha"), { header = "Talk", buttons = { { id = 5 } } } },
		ns.Delves_ParsePowers("alpha"))
	eq(why, "notpowers", "an option without a spell")
	_, why = ns.Delves_PickPower({ Power(1, "Alpha", { buttons = { { id = 1 }, { id = 2 } } }) }, {})
	eq(why, "notpowers", "two buttons")
	_, why = ns.Delves_PickPower({ Power(1, "Alpha", { buttons = { { id = 1, confirmation = "Sure?" } } }) }, {})
	eq(why, "notpowers", "asks to confirm")
	_, why = ns.Delves_PickPower({ Power(1, "Alpha", { disabledOption = true }) }, {})
	eq(why, "notpowers", "disabled")
end)

H.done()
