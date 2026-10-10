-- Run from the AddOns folder: lua Tomte/tests/test_send.lua
local ns = {}
assert(loadfile("Tomte/Modules/Alts/SendData.lua"))("Tomte", ns)

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

local HERB, ORE, CLOTH, MINE = 100, 200, 300, 400
local recipes = {
	[1] = { reagents = { { items = { HERB, HERB + 1 }, qty = 5 } } }, -- potion
	[2] = { reagents = { { items = { HERB } }, { items = { ORE } } } }, -- flask
	[3] = { reagents = { { items = { ORE } } } }, -- ingot
	[4] = { reagents = { { items = { MINE } } } }, -- something Main knows
}
local chars = {
	Main = { guid = "Main", name = "Main", realm = "Silvermoon", seen = 50, profs = { [1] = { known = { [4] = true } } } },
	Alch = { guid = "Alch", name = "Mira", realm = "Silvermoon", seen = 10, profs = { [2] = { known = { [1] = true, [2] = true } } } },
	Smith = { guid = "Smith", name = "Tolvan", realm = "Argent Dawn", seen = 20, profs = { [3] = { known = { [3] = true } } } },
	Alch2 = { guid = "Alch2", name = "Bea", realm = "Silvermoon", seen = 30, profs = { [2] = { known = { [2] = true } } } },
}

local function Ctx(over)
	local ctx = { me = "Main", chars = chars, users = ns.Alts_ReagentUsers(chars, recipes), rules = {} }
	for k, v in pairs(over or {}) do
		ctx[k] = v
	end
	return ctx
end

test("users count known recipes per character", function()
	local users = ns.Alts_ReagentUsers(chars, recipes)
	eq(users[HERB].Alch, 2)
	eq(users[HERB].Alch2, 1)
	eq(users[HERB + 1].Alch, 1)
	eq(users[ORE].Smith, 1)
	eq(users[MINE].Main, 1)
end)

test("recipient: most recipes, ties by last played, never what I use", function()
	eq(ns.Alts_Recipient(HERB, "herb", Ctx()), "Alch")
	eq(ns.Alts_Recipient(ORE, "ore", Ctx()), "Alch2", "Smith 1 vs Bea (Alch2) 1: Bea played later")
	eq(ns.Alts_Recipient(MINE, "mine", Ctx()), nil, "Main uses it")
	eq(ns.Alts_Recipient(CLOTH, "cloth", Ctx()), nil, "nobody uses it")
end)

test("plan and rules come first", function()
	eq(ns.Alts_Recipient(ORE, "ore", Ctx({ plan = { [ORE] = "Smith" } })), "Smith")
	local rules = ns.Alts_ParseRules("200 = Tolvan, Linen Cloth=mira")
	eq(#rules, 2)
	eq(rules[1].match, 200)
	eq(rules[2].match, "linen cloth")
	eq(ns.Alts_Recipient(ORE, "ore", Ctx({ rules = rules })), "Smith")
	eq(ns.Alts_Recipient(CLOTH, "Linen Cloth", Ctx({ rules = rules })), "Alch")
	eq(ns.Alts_Recipient(MINE, "mine", Ctx({ rules = ns.Alts_ParseRules("400=nobody") })), nil, "unknown name")
end)

test("groups by recipient with a filter", function()
	local stacks = {
		{ itemID = HERB, count = 20 }, { itemID = HERB, count = 20, bound = true }, { itemID = ORE, count = 5 },
		{ itemID = CLOTH, count = 3 },
	}
	local groups = ns.Alts_SendGroups(stacks, Ctx(), function(s)
		return not s.bound
	end)
	eq(#groups, 2)
	eq(groups[1].guid, "Alch2", "one stack each: by name, Bea first")
	eq(groups[2].guid, "Alch")
	eq(#groups[2].stacks, 1, "the bound stack is filtered out")
	eq(groups[2].count, 20)
end)

test("next mail takes 12", function()
	local g = { stacks = {} }
	for i = 1, 15 do
		g.stacks[i] = { i = i }
	end
	eq(#ns.Alts_NextMail(g, 12), 12)
end)

test("plan assignments", function()
	local plan = { steps = { { recipeID = 2, crafters = { chars.Alch2 } }, { recipeID = 3, crafters = {} } } }
	local out = ns.Alts_PlanAssignments(plan, recipes)
	eq(out[HERB], "Alch2")
	eq(out[ORE], "Alch2")
end)

test("top up and mail names", function()
	eq(ns.Alts_TopUp(100, 500, 10000, 500), 400)
	eq(ns.Alts_TopUp(600, 500, 10000, 500), nil)
	eq(ns.Alts_TopUp(100, 500, 600, 500), 100, "only what I can spare")
	eq(ns.Alts_TopUp(100, 500, 400, 500), nil)
	eq(ns.Alts_MailName(chars.Alch, "Silvermoon"), "Mira")
	eq(ns.Alts_MailName(chars.Smith, "Silvermoon"), "Tolvan-ArgentDawn")
end)

test("stacks a tracked craft claims aren't offered again", function()
	local stacks = {
		{ itemID = 1, count = 128, slot = 1 }, -- the craft wants 128: all of it
		{ itemID = 2, count = 20, slot = 2 }, -- wants 5: this stack is drawn on, so it's left out whole
		{ itemID = 2, count = 20, slot = 3 }, -- not needed: stays
		{ itemID = 3, count = 7, slot = 4 }, -- not claimed
	}
	local left = ns.Alts_Unclaimed(stacks, { [1] = 128, [2] = 5 })
	eq(#left, 2)
	eq(left[1].slot, 3)
	eq(left[2].slot, 4)
	eq(#ns.Alts_Unclaimed(stacks, {}), 4, "no claims")
end)

test("GearGroups: by who gets it, one route only, sorted by name", function()
	local stacks = {
		{ bag = 0, slot = 1, to = "Smith", route = "mail" },
		{ bag = 0, slot = 2, to = "Alch", route = "mail" },
		{ bag = 0, slot = 3, to = "Alch", route = "warband" },
		{ bag = 0, slot = 4, to = "Alch", route = "mail", count = 1 },
		{ bag = 0, slot = 5, route = "mail" },
		{ bag = 0, slot = 6, to = "Gone", route = "mail" },
	}
	local groups = ns.Alts_GearGroups(stacks, "mail", chars)
	eq(#groups, 2)
	eq(groups[1].guid, "Alch", "Mira before Tolvan")
	eq(#groups[1].stacks, 2)
	eq(groups[1].gear, true)
	eq(groups[2].guid, "Smith")
	groups = ns.Alts_GearGroups(stacks, "warband", chars)
	eq(#groups, 1)
	eq(groups[1].stacks[1].slot, 3)
	eq(#ns.Alts_GearGroups({}, "mail", chars), 0)
end)

test("realms: connected set, own realm, normalized names", function()
	local realms = ns.Alts_RealmSet({ "ArgentDawn", "The Sha'tar" }, "Silver-moon")
	eq(realms.ArgentDawn, true)
	eq(realms["TheSha'tar"], true)
	eq(realms.Silvermoon, true, "own realm, normalized")
	eq(ns.Alts_Reachable(chars.Smith, realms), true, "Argent Dawn with a space")
	eq(ns.Alts_Reachable({ realm = "Draenor" }, realms), false)
	eq(ns.Alts_Reachable({ realm = "Draenor" }, nil), true, "unknown realms: everyone")
	eq(ns.Alts_Reachable({}, realms), true, "no stored realm")
	local alone = ns.Alts_RealmSet({}, "Silvermoon")
	eq(ns.Alts_Reachable(chars.Smith, alone), false, "an unconnected realm reaches only itself")
end)

test("recipient: characters mail can't reach are skipped", function()
	local realms = ns.Alts_RealmSet({}, "Silvermoon")
	eq(ns.Alts_Recipient(ORE, "ore", Ctx({ realms = realms })), "Alch2", "Tolvan (Argent Dawn) is out anyway")
	eq(ns.Alts_Recipient(ORE, "ore", Ctx({ realms = realms, plan = { [ORE] = "Smith" } })), "Alch2", "plan to Tolvan: skipped")
	eq(ns.Alts_Recipient(ORE, "ore", Ctx({ realms = realms, rules = ns.Alts_ParseRules("200=Tolvan") })), nil,
		"a rule to someone out of reach: nobody")
	local onlySmith = { [ORE] = { Smith = 3 } }
	eq(ns.Alts_Recipient(ORE, "ore", Ctx({ realms = realms, users = onlySmith })), nil)
	eq(ns.Alts_Recipient(ORE, "ore", Ctx({ users = onlySmith })), "Smith", "no realm filter")
	local stacks = { { bag = 0, slot = 1, to = "Smith", route = "mail" }, { bag = 0, slot = 2, to = "Alch", route = "mail" } }
	local groups = ns.Alts_GearGroups(stacks, "mail", chars, realms)
	eq(#groups, 1)
	eq(groups[1].guid, "Alch")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
