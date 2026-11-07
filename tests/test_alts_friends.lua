-- Run from the AddOns folder: lua Tomte/tests/test_alts_friends.lua
local ns = {}
assert(loadfile("Tomte/Modules/Alts/SendData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Alts/FriendsData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local BAG, LEATHER, HIDE = 5573, 2318, 783 -- made-up recipe ID, real item IDs
local HOME = ns.Alts_RealmSet({}, "Argent Dawn")
local AWAY = ns.Alts_RealmSet({}, "Silvermoon")

local function Mine()
	local chars = {
		["Player-1-AA"] = { name = "Mira", realm = "Argent Dawn", faction = "Horde", class = "HUNTER", level = 14,
			profs = { [165] = { base = 165, skill = 38, max = 75, known = { [BAG] = true, [9] = true } } } },
		["Player-1-BB"] = { name = "Aldric", realm = "Argent Dawn", faction = "Horde", class = "WARRIOR", level = 3 },
	}
	local recipes = {
		[BAG] = { name = "Light Leather Reagent Bag", base = 165, item = 70001,
			reagents = { { items = { LEATHER }, qty = 8 }, { items = { HIDE, 99 }, qty = 1 } } },
		[9] = { name = "Light Armor Kit", base = 165, item = 2304, reagents = { { items = { LEATHER }, qty = 1 } } },
	}
	return chars, recipes
end

test("Export and Import: characters, professions and recipes round trip", function()
	local chars, recipes = Mine()
	local data = assert(ns.AltsFriends_Import(ns.AltsFriends_Export(chars, recipes)))
	eq(#data.chars, 1, "a character without professions isn't sent")
	local c = data.chars[1]
	eq(c.name, "Mira")
	eq(c.realm, "Argent Dawn")
	eq(c.faction, "H")
	eq(c.class, "HUNTER")
	eq(c.level, 14)
	eq(c.profs[165].skill, 38)
	eq(c.profs[165].max, 75)
	eq(c.profs[165].known[BAG], true)
	eq(c.profs[165].known[9], true)
	local r = data.recipes[BAG]
	eq(r.name, "Light Leather Reagent Bag")
	eq(r.item, 70001)
	eq(r.base, 165)
	eq(r.reagents[1].items[1], LEATHER)
	eq(r.reagents[1].qty, 8)
	eq(r.reagents[2].items[1], HIDE, "the first item of a reagent slot")
end)

test("Export: separators in names can't break the records", function()
	local chars, recipes = Mine()
	recipes[BAG].name = "Bolt; of, Cloth:=|^."
	local data = assert(ns.AltsFriends_Import(ns.AltsFriends_Export(chars, recipes)))
	eq(data.recipes[BAG].name:find("[;,:=|%^%.]"), nil)
	eq(data.recipes[BAG].name:find("Bolt") ~= nil, true)
	eq(data.recipes[9].name, "Light Armor Kit", "the next record still reads")
end)

test("Revision: the same payload, the same number; a change, another", function()
	local chars, recipes = Mine()
	local a = ns.AltsFriends_Revision(ns.AltsFriends_Export(chars, recipes))
	eq(type(a), "number")
	eq(a == math.floor(a), true, "a whole number (the hello carries digits only)")
	eq(ns.AltsFriends_Revision(ns.AltsFriends_Export(chars, recipes)), a)
	chars["Player-1-AA"].profs[165].skill = 39
	eq(ns.AltsFriends_Revision(ns.AltsFriends_Export(chars, recipes)) ~= a, true)
end)

test("Import: garbage is rejected", function()
	eq((ns.AltsFriends_Import("hello there")), nil)
	eq((ns.AltsFriends_Import("p165,1,2=5;")), nil, "a profession before any character")
	local data = ns.AltsFriends_Import("")
	eq(#data.chars, 0, "nothing shared yet is fine")
end)

local function FriendData()
	local chars, recipes = Mine()
	return assert(ns.AltsFriends_Import(ns.AltsFriends_Export(chars, recipes)))
end

test("Merge: a friend's reachable characters and their recipes join, yours stay as they were", function()
	local chars, recipes = Mine()
	local kesha = FriendData()
	kesha.recipes[777] = { name = "Kesha's Secret", base = 165, item = 70002, reagents = {} }
	kesha.chars[1].profs[165].known[777] = true
	local friends = { ["Kesha#1234"] = { at = 100, data = kesha } }
	local c2, r2 = ns.AltsFriends_Merge(chars, recipes, friends,
		{ faction = "Horde", realms = HOME, online = { ["Kesha#1234"] = true } })
	local key = "friend:Kesha#1234:Mira-Argent Dawn"
	eq(c2[key] ~= nil, true)
	eq(c2[key].friend.tag, "Kesha#1234")
	eq(c2[key].friend.online, true)
	eq(c2[key].friend.seen, 100)
	eq(c2[key].profs[165].known[777], true)
	eq(r2[777].friend, true, "a recipe only the friend knows")
	eq(r2[BAG], recipes[BAG], "yours is kept, not replaced")
	eq(c2["Player-1-AA"], chars["Player-1-AA"])
	eq(chars[key], nil, "your table isn't changed")
	eq(recipes[777], nil)
end)

test("Merge: characters mail can't reach are left out", function()
	local chars, recipes = Mine()
	local friends = { ["Kesha#1234"] = { at = 1, data = FriendData() } }
	local c2 = ns.AltsFriends_Merge(chars, recipes, friends, { faction = "Alliance", realms = HOME })
	eq(c2["friend:Kesha#1234:Mira-Argent Dawn"], nil, "other faction")
	c2 = ns.AltsFriends_Merge(chars, recipes, friends, { faction = "Horde", realms = AWAY })
	eq(c2["friend:Kesha#1234:Mira-Argent Dawn"], nil, "another realm")
	c2 = ns.AltsFriends_Merge(chars, recipes, friends, { faction = "Horde", realms = HOME })
	eq(c2["friend:Kesha#1234:Mira-Argent Dawn"].friend.online, false, "offline")
end)

test("Merge: a friend's recipes only come with a character of theirs that's shown", function()
	local chars = {}
	local friends = { ["Kesha#1234"] = { at = 1, data = FriendData() } }
	local _, r2 = ns.AltsFriends_Merge(chars, {}, friends, { faction = "Alliance", realms = HOME })
	eq(r2[BAG], nil, "nobody you can reach knows it: not listed with 'no one'")
	_, r2 = ns.AltsFriends_Merge(chars, {}, friends, { faction = "Horde", realms = HOME })
	eq(r2[BAG] ~= nil, true)
end)

test("Forever realms: the server number doesn't count, the ruleset does", function()
	local key = ns.AltsFriends_ForeverRealm
	eq(key("CAMWOWEU4Realm5PvE"), key("CAMWOWEU4Realm3PvE"), "two PvE servers, one world")
	eq(key("CAMWOWEU4Realm5PvE") ~= key("CAMWOWEU4Realm2PvP"), true, "another ruleset")
	local realms = { [key("CAMWOWEU4Realm5PvE")] = true }
	local friend = { name = "Mira", realm = "CAMWOWEU4Realm3PvE", faction = "H", profs = {} }
	eq(ns.AltsFriends_Reachable(friend, "Horde", realms, key), true)
	friend.realm = "CAMWOWEU4Realm2PvP"
	eq(ns.AltsFriends_Reachable(friend, "Horde", realms, key), false)
	local chars, recipes = Mine()
	local data = FriendData()
	data.chars[1].realm = "CAMWOWEU4Realm3PvE"
	local c2 = ns.AltsFriends_Merge(chars, recipes, { ["Kesha#1234"] = { at = 1, data = data } },
		{ faction = "Horde", realms = realms, realmKey = key })
	eq(c2["friend:Kesha#1234:Mira-CAMWOWEU4Realm3PvE"] ~= nil, true, "the merge uses the key too")
end)

test("Reachable: unknown faction counts as reachable", function()
	eq(ns.AltsFriends_Reachable({ realm = "Argent Dawn", faction = "" }, "Horde", HOME), true)
	eq(ns.AltsFriends_Reachable({ realm = "Argent Dawn", faction = "A" }, "Horde", HOME), false)
	eq(ns.AltsFriends_Reachable({ realm = "Argent Dawn", faction = "H" }, "Horde", nil), true, "realms unknown")
end)

test("Apply: a request goes waiting, sent, delivered, accepted, made, done", function()
	local req = ns.AltsFriends_NewRequest({ id = "k1", recipeID = BAG, amount = 1 })
	eq(req.state, "waiting")
	for _, step in ipairs({ { "sent", "sent" }, { "got", "delivered" }, { "accepted", "accepted" }, { "made", "made" },
		{ "done", "done" } }) do
		eq(ns.AltsFriends_Apply(req, step[1]), true, step[1])
		eq(req.state, step[2])
	end
	eq(ns.AltsFriends_Apply(req, "accepted"), false, "nothing after done")
	eq(ns.AltsFriends_Apply(req, "cancel"), false)
	eq(req.state, "done")
end)

test("Apply: cancel and decline from open states, an answer can overtake its got", function()
	local req = ns.AltsFriends_NewRequest({ id = "k1" })
	eq(ns.AltsFriends_Apply(req, "cancel"), true)
	eq(req.state, "cancelled")
	req = ns.AltsFriends_NewRequest({ id = "k2" })
	eq(ns.AltsFriends_Apply(req, "accepted"), true, "accepted before the got arrived")
	eq(ns.AltsFriends_Apply(req, "got"), false, "a late got changes nothing")
	eq(req.state, "accepted")
	eq(ns.AltsFriends_Apply(req, "cancel"), true)
	req = ns.AltsFriends_NewRequest({ id = "k3", state = "delivered" })
	eq(ns.AltsFriends_Apply(req, "declined"), true)
	eq(req.state, "declined")
	eq(ns.AltsFriends_Apply(req, "bogus"), false)
end)

test("Encode and Decode: an ask and an answer round trip", function()
	local req = ns.AltsFriends_NewRequest({ id = "1700000000-1234", recipeID = BAG, itemID = 70001, amount = 2,
		mats = true, crafter = "Mira", asker = "Aldric", askerRealm = "Argent Dawn" })
	local msg = ns.AltsFriends_Decode(ns.AltsFriends_EncodeAsk(req))
	eq(msg.id, "1700000000-1234")
	eq(msg.kind, "ask")
	eq(msg.recipeID, BAG)
	eq(msg.itemID, 70001)
	eq(msg.amount, 2)
	eq(msg.mats, true)
	eq(msg.crafter, "Mira")
	eq(msg.asker, "Aldric")
	eq(msg.askerRealm, "Argent Dawn")
	msg = ns.AltsFriends_Decode(ns.AltsFriends_EncodeAnswer("k1", "accepted"))
	eq(msg.id, "k1")
	eq(msg.kind, "accepted")
	eq(ns.AltsFriends_Decode("k1;bogus"), nil)
	eq(ns.AltsFriends_Decode("k1;ask;x"), nil, "a broken ask")
	eq(ns.AltsFriends_Decode(""), nil)
end)

test("TakeAsk: a new ask becomes their request once, a repeat changes nothing", function()
	local requests = {}
	local msg = ns.AltsFriends_Decode("k1;ask;5573;70001;1;0;Mira;Aldric;Argent Dawn")
	local req, new = ns.AltsFriends_TakeAsk(requests, msg, "Aldric#1111", 50)
	eq(new, true)
	eq(req.mine, false)
	eq(req.friend, "Aldric#1111")
	eq(req.state, "delivered")
	eq(req.at, 50)
	eq(req.mats, false)
	eq(requests.k1, req)
	req.state = "accepted"
	local again, new2 = ns.AltsFriends_TakeAsk(requests, msg, "Aldric#1111", 60)
	eq(new2, false)
	eq(again.state, "accepted", "the repeat didn't reset it")
	eq(again.at, 50)
end)

test("MailGroups: your materials until mailed, their made crafts until done", function()
	local _, recipes = Mine()
	local requests = {
		a = { id = "a", mine = true, mats = true, state = "accepted", recipeID = BAG, amount = 2, crafter = "Mira",
			crafterRealm = "Argent Dawn", friend = "Kesha#1234", at = 2 },
		b = { id = "b", mine = true, mats = true, state = "waiting", recipeID = 9, amount = 1, crafter = "Mira",
			crafterRealm = "Argent Dawn", friend = "Kesha#1234", at = 1 },
		c = { id = "c", mine = true, mats = false, state = "accepted", recipeID = BAG, amount = 1, friend = "K#1" },
		d = { id = "d", mine = true, mats = true, matsSent = true, state = "accepted", recipeID = BAG, amount = 1,
			friend = "K#1" },
		e = { id = "e", mine = false, state = "made", recipeID = BAG, itemID = 70001, amount = 3, asker = "Aldric",
			askerRealm = "Argent Dawn", friend = "Aldric#1111", at = 3 },
		f = { id = "f", mine = false, state = "accepted", recipeID = BAG, itemID = 70001, amount = 1, friend = "A#1" },
		g = { id = "g", mine = true, mats = true, state = "cancelled", recipeID = BAG, amount = 1, friend = "K#1" },
	}
	local groups = ns.AltsFriends_MailGroups(requests, recipes)
	eq(#groups, 3)
	eq(groups[1].req.id, "e", "newest first")
	eq(groups[1].kind, "item")
	eq(groups[1].to.name, "Aldric")
	eq(groups[1].to.realm, "Argent Dawn")
	eq(groups[1].wants[1].itemID, 70001)
	eq(groups[1].wants[1].n, 3)
	eq(groups[2].req.id, "a")
	eq(groups[2].kind, "mats")
	eq(groups[2].to.name, "Mira")
	eq(groups[2].wants[1].itemID, LEATHER)
	eq(groups[2].wants[1].n, 16)
	eq(groups[3].req.id, "b", "a waiting request's materials can go already")
end)

test("Apply: a later state overtakes the ones before it (answers lost while offline)", function()
	local req = ns.AltsFriends_NewRequest({ id = "k1", state = "sent" })
	eq(ns.AltsFriends_Apply(req, "done"), true, "done overtakes accepted and made")
	eq(req.state, "done")
	req = ns.AltsFriends_NewRequest({ id = "k2", state = "delivered" })
	eq(ns.AltsFriends_Apply(req, "made"), true)
	eq(ns.AltsFriends_Apply(req, "accepted"), false, "never backwards")
	eq(req.state, "made")
	eq(ns.AltsFriends_Apply(req, "declined"), true, "the crafter can still decline a made craft")
	eq(req.state, "declined")
end)

test("Ask carries the asker's faction; one without it still decodes", function()
	local req = ns.AltsFriends_NewRequest({ id = "k1", recipeID = BAG, itemID = 70001, amount = 1, mats = false,
		crafter = "Mira", asker = "Aldric", askerRealm = "Argent Dawn", askerFaction = "Horde" })
	eq(ns.AltsFriends_Decode(ns.AltsFriends_EncodeAsk(req)).askerFaction, "H")
	local old = ns.AltsFriends_Decode("k1;ask;5573;70001;1;0;Mira;Aldric;Argent Dawn")
	eq(old.askerFaction, "")
	eq(old.askerRealm, "Argent Dawn")
end)

test("Merge keeps a friend's character's faction", function()
	local chars, recipes = Mine()
	local c2 = ns.AltsFriends_Merge(chars, recipes, { ["Kesha#1234"] = { at = 1, data = FriendData() } },
		{ faction = "Horde", realms = HOME })
	eq(c2["friend:Kesha#1234:Mira-Argent Dawn"].faction, "H")
end)

test("MailGroups: only recipients your mail reaches; a made craft counts what each craft makes", function()
	local _, recipes = Mine()
	recipes[BAG].qMin = 5 -- five per craft
	local requests = {
		e = { id = "e", mine = false, state = "made", recipeID = BAG, itemID = 70001, amount = 2, asker = "Aldric",
			askerRealm = "Argent Dawn", askerFaction = "H", friend = "Aldric#1111", at = 3 },
		a = { id = "a", mine = true, mats = true, state = "accepted", recipeID = BAG, amount = 1, crafter = "Mira",
			crafterRealm = "Argent Dawn", crafterFaction = "H", friend = "Kesha#1234", at = 2 },
	}
	local groups = ns.AltsFriends_MailGroups(requests, recipes, { faction = "Horde", realms = HOME })
	eq(#groups, 2)
	eq(groups[1].wants[1].n, 10, "2 crafts x 5")
	eq(#ns.AltsFriends_MailGroups(requests, recipes, { faction = "Alliance", realms = HOME }), 0, "other faction")
	eq(#ns.AltsFriends_MailGroups(requests, recipes, { faction = "Horde", realms = AWAY }), 0, "another realm")
	eq(ns.AltsFriends_ItemCount(requests.e, recipes[BAG]), 10)
	eq(ns.AltsFriends_ItemCount(requests.e, nil), 2, "unknown recipe: one per craft")
end)

test("Todos: a made craft and materials to send become tracker blocks with mail steps", function()
	local groups = {
		{ req = { id = "e", recipeID = BAG }, kind = "item", to = { name = "Dead" }, wants = { { itemID = 70001, n = 1 } } },
		{ req = { id = "a", recipeID = BAG }, kind = "mats", to = { name = "Mira" },
			wants = { { itemID = LEATHER, n = 8 }, { itemID = HIDE, n = 1 } } },
	}
	local todos = ns.AltsFriends_Todos(groups, {
		me = "Player-1-AA",
		itemName = function(id)
			return "item" .. id
		end,
		recipeName = function(req)
			return "Camp Tent"
		end,
	})
	eq(#todos, 2)
	local t = todos[1]
	eq(t.friend, true)
	eq(t.entry, "friend:item:e", "a key the tracker follows across redraws")
	eq(t.title, "For Dead: Camp Tent")
	eq(t.crafter, "Player-1-AA", "yours to do")
	eq(#t.lines, 1)
	eq(t.lines[1].kind, "mail")
	eq(t.lines[1].mine, true)
	eq(t.lines[1].text, "Mail 1 item70001 to Dead")
	eq(todos[2].title, "Materials for Mira: Camp Tent")
	eq(todos[2].lines[2].text, "Mail 1 item783 to Mira")
	eq(t.needed, 1, "the tracker's progress bar starts empty (Alts_CraftProgress)")
	eq(t.inPlace, 0)
end)

test("Awaiting: a friend's asks you haven't answered, newest first", function()
	local requests = {
		a = { id = "a", mine = false, state = "delivered", at = 1 },
		b = { id = "b", mine = false, state = "delivered", at = 5 },
		c = { id = "c", mine = false, state = "accepted", at = 9 }, -- answered
		d = { id = "d", mine = true, state = "delivered", at = 7 }, -- yours, waiting on them
		e = { id = "e", mine = false, state = "delivered", at = 3, hidden = true },
	}
	local list = ns.AltsFriends_Awaiting(requests)
	eq(#list, 2)
	eq(list[1].id, "b")
	eq(list[2].id, "a")
	eq(#ns.AltsFriends_Awaiting({}), 0)
end)

test("Materials: each reagent's first item times the amount", function()
	local _, recipes = Mine()
	local mats = ns.AltsFriends_Materials(recipes[BAG], 2)
	eq(#mats, 2)
	eq(mats[1].itemID, LEATHER)
	eq(mats[1].count, 16)
	eq(mats[2].itemID, HIDE)
	eq(mats[2].count, 2)
	eq(#ns.AltsFriends_Materials({}, 3), 0, "no reagents known")
end)

H.done()
