-- Run from the AddOns folder: lua Tomte/tests/test_talents.lua
local ns = {}
assert(loadfile("Tomte/Core/CheckData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Talents/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local DELVE = 208
local A, B, C = 101, 102, 103 -- loadout config IDs
local PROT, HOLY = 66, 65
local VALID = { [A] = true, [B] = true, [C] = true }

local function dungeon(id)
	return ns.Talents_Place("party", 23, id or 2660, "Ara-Kara")
end

local function state(t)
	t.valid = t.valid or VALID
	t.count = t.count or 3
	return t
end

test("place kinds", function()
	eq(ns.Talents_PlaceKind("none", 0), "world")
	eq(ns.Talents_PlaceKind("party", 23), "dungeon")
	eq(ns.Talents_PlaceKind("raid", 16), "raid")
	eq(ns.Talents_PlaceKind("scenario", DELVE), "delve")
	eq(ns.Talents_PlaceKind("pvp", 0), "pvp")
	eq(ns.Talents_PlaceKind("arena", 0), "pvp")
	eq(ns.Talents_PlaceKind("scenario", 1), nil)
end)

test("only dungeons, raids and delves carry an instance", function()
	eq(dungeon().instanceID, 2660)
	eq(ns.Talents_Place("scenario", DELVE, 2664, "Fungal Folly").instanceID, 2664)
	eq(ns.Talents_Place("none", 0, 2552, "Khaz Algar").instanceID, nil)
	eq(ns.Talents_Place("arena", 0, 1505, "Nagrand Arena").instanceID, nil)
	eq(ns.Talents_Place("scenario", 1, 1, "x"), nil)
	eq(ns.Talents_PlaceKey(dungeon()), "dungeon:2660")
	eq(ns.Talents_PlaceKey(ns.Talents_Place("none", 0, 1)), "world:")
end)

test("an instance override wins over the kind", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.kinds.dungeon = A
	spec.instances[2660] = { config = B, name = "Ara-Kara" }
	local id, source = ns.Talents_Wanted(spec, dungeon(), VALID)
	eq(id, B)
	eq(source, "instance")
	id, source = ns.Talents_Wanted(spec, dungeon(9999), VALID)
	eq(id, A)
	eq(source, "kind")
end)

test("a deleted override falls back to the kind", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.kinds.dungeon = A
	spec.instances[2660] = { config = B }
	local id = ns.Talents_Wanted(spec, dungeon(), { [A] = true })
	eq(id, A)
	eq(ns.Talents_Wanted(spec, dungeon(), { [C] = true }), nil)
end)

test("decide: wrong loadout means switch", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.kinds.dungeon = B
	local d = ns.Talents_Decide(state({ place = dungeon(), spec = spec, active = A }))
	eq(d.action, "switch")
	eq(d.want, B)
	eq(d.source, "kind")
end)

test("decide: on the right one, nothing", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.kinds.dungeon = B
	eq(ns.Talents_Decide(state({ place = dungeon(), spec = spec, active = B })).action, "none")
end)

test("decide: Default loadout (no selection) is offered the switch", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.kinds.raid = C
	local d = ns.Talents_Decide(state({ place = ns.Talents_Place("raid", 16, 2657, "Nerub-ar Palace"), spec = spec }))
	eq(d.action, "switch")
	eq(d.want, C)
end)

test("decide: nothing saved learns, or stays quiet", function()
	local d = ns.Talents_Decide(state({ place = dungeon(), active = A, learn = true }))
	eq(d.action, "learn")
	eq(d.want, A)
	eq(ns.Talents_Decide(state({ place = dungeon(), active = A, learn = false })).action, "none")
	eq(ns.Talents_Decide(state({ place = dungeon(), active = nil, learn = true })).action, "none")
	eq(ns.Talents_Decide(state({ place = dungeon(), active = 999, learn = true })).action, "none", "unknown id")
end)

test("decide: starter build, key running, no loadouts, no place", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.kinds.dungeon = B
	eq(ns.Talents_Decide(state({ place = dungeon(), spec = spec, active = A, starter = true })).reason, "starter")
	eq(ns.Talents_Decide(state({ place = dungeon(), spec = spec, active = A, keyRunning = true })).reason,
		"keyRunning")
	eq(ns.Talents_Decide({ place = dungeon(), spec = spec, active = A, valid = {}, count = 0 }).reason, "noLoadouts")
	eq(ns.Talents_Decide(state({ spec = spec, active = A })).reason, "noPlace")
end)

test("decide: a saved loadout that was deleted doesn't nag", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.kinds.dungeon = 555
	local d = ns.Talents_Decide(state({ place = dungeon(), spec = spec, active = A, learn = false }))
	eq(d.action, "none")
end)

test("offer after a hand switch", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.kinds.dungeon = A
	local s = state({ place = dungeon(), spec = spec })
	local ok, before = ns.Talents_ShouldOffer(s, B, {})
	eq(ok, true)
	eq(before, A)
	eq(ns.Talents_ShouldOffer(s, A, {}), false, "already the saved one")
	eq(ns.Talents_ShouldOffer(s, 999, {}), false, "not a saved loadout")
	eq(ns.Talents_ShouldOffer(s, nil, {}), false, "Default loadout")
	eq(ns.Talents_ShouldOffer(s, B, { ["dungeon:2660#" .. B] = true }), false, "declined")
	s.starter = true
	eq(ns.Talents_ShouldOffer(s, B, {}), false, "starter")
	eq(ns.Talents_ShouldOffer(state({ spec = spec }), B, {}), false, "no place")
	eq(ns.Talents_ShouldOffer(state({ place = dungeon() }), B, {}), true, "nothing saved yet")
end)

test("remember for the kind drops this instance's override", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.instances[2660] = { config = A, name = "Ara-Kara" }
	ns.Talents_Remember(spec, dungeon(), B, "kind")
	eq(spec.kinds.dungeon, B)
	eq(spec.instances[2660], nil)
	ns.Talents_Remember(spec, dungeon(), C, "instance")
	eq(spec.instances[2660].config, C)
	eq(spec.instances[2660].name, "Ara-Kara")
	eq(spec.kinds.dungeon, B)
end)

test("remember for one instance where there are none falls back to the kind", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	ns.Talents_Remember(spec, ns.Talents_Place("none", 0), A, "instance")
	eq(spec.kinds.world, A)
end)

test("prune forgets deleted loadouts", function()
	local spec = ns.Talents_Spec({}, PROT, true)
	spec.kinds.dungeon, spec.kinds.raid = A, 555
	spec.instances[1] = { config = 556 }
	spec.instances[2] = { config = B }
	eq(ns.Talents_Prune(spec, VALID), 2)
	eq(spec.kinds.raid, nil)
	eq(spec.kinds.dungeon, A)
	eq(spec.instances[1], nil)
	eq(spec.instances[2].config, B)
end)

test("entries sort by spec order, kinds, then instances by name", function()
	local char = {}
	local prot = ns.Talents_Spec(char, PROT, true)
	local holy = ns.Talents_Spec(char, HOLY, true)
	prot.kinds.raid, prot.kinds.world = B, A
	prot.instances[2] = { config = C, name = "Zeta" }
	prot.instances[1] = { config = C, name = "Alpha" }
	holy.kinds.dungeon = A
	local list = ns.Talents_Entries(char, { PROT, HOLY })
	local out = {}
	for i, e in ipairs(list) do
		out[i] = e.specID .. ":" .. (e.kind or e.name)
	end
	eq(table.concat(out, " "), "66:world 66:raid 66:Alpha 66:Zeta 65:dungeon")
end)

test("forget removes one entry and empty specs", function()
	local char = {}
	local spec = ns.Talents_Spec(char, PROT, true)
	spec.kinds.dungeon = A
	spec.instances[5] = { config = B, name = "X" }
	ns.Talents_Forget(char, { specID = PROT, instanceID = 5 })
	eq(spec.instances[5], nil)
	eq(char.specs[PROT] ~= nil, true)
	ns.Talents_Forget(char, { specID = PROT, kind = "dungeon" })
	eq(char.specs[PROT], nil)
	ns.Talents_Forget(char, { specID = HOLY, kind = "raid" }) -- nothing saved: no error
end)

test("texts", function()
	eq(ns.Talents_WrongText("Raid", "Mythic+", "dungeons"), "You're on Raid; for dungeons you use Mythic+.")
	eq(ns.Talents_WrongText(nil, "Mythic+", "Ara-Kara"), "You're on no saved loadout; for Ara-Kara you use Mythic+.")
	eq(ns.Talents_OfferText("Delve", ns.Talents_Place("scenario", DELVE, 1, "x")), "Use Delve for delves from now on?")
	eq(ns.Talents_PlacePhrase(dungeon(), "instance"), "Ara-Kara")
	eq(ns.Talents_PlacePhrase(dungeon(), "kind"), "dungeons")
	eq(ns.Talents_EntryText({ kind = "pvp" }, "Holy", "Arena"), "Holy - PvP: Arena")
	eq(ns.Talents_EntryText({ instanceID = 7, name = "Ara-Kara" }, "Holy", "M+"), "Holy - Ara-Kara: M+")
	eq(ns.Talents_ReasonText("onIt"), "You're on the loadout saved for this place.")
end)

H.done()
