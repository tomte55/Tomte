-- Run from the AddOns folder: lua Tomte/tests/test_emotewheel.lua
local ns = {}
assert(loadfile("Tomte/Modules/EmoteWheel/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local LOOKUPS = {
	chat = { ["/S"] = "SAY", ["/SAY"] = "SAY", ["/W"] = "WHISPER", ["/P"] = "PARTY", ["/E"] = "EMOTE" },
	emotes = { ["/BOW"] = "BOW", ["/TY"] = "THANK", ["/THANK"] = "THANK" },
	secure = { ["/CAST"] = true },
	slash = { ["/DANCE"] = "DANCE", ["/RANDOM"] = "RANDOM" },
}

test("slices skip empty slots and keep the slot number", function()
	local list = ns.EmoteWheel_Slices({ s1 = { name = "Bow", text = "/bow" }, s2 = { name = "", text = "  " },
		s3 = { name = "", text = " /wave " } })
	eq(#list, 2, "count")
	eq(list[2].text, "/wave", "trimmed")
	eq(list[2].slot, 3, "slot")
end)

test("label: own name, else from the command, else the text", function()
	eq(ns.EmoteWheel_Label({ name = "Thanks!", text = "/ty" }), "Thanks!")
	eq(ns.EmoteWheel_Label({ name = "", text = "/cheer" }), "Cheer")
	eq(ns.EmoteWheel_Label({ name = " ", text = "Good luck everyone" }), "Good luck e...")
end)

test("short counts characters, not bytes", function()
	eq(ns.EmoteWheel_Short("Ñandú es rápido", 6), "Ñandú...")
	eq(ns.EmoteWheel_Short("abc", 3), "abc")
end)

test("full name carries another realm only", function()
	eq(ns.EmoteWheel_FullName("Kesha", "Silvermoon"), "Kesha-Silvermoon")
	eq(ns.EmoteWheel_FullName("Kesha", ""), "Kesha")
	eq(ns.EmoteWheel_FullName("Kesha", nil), "Kesha")
end)

test("%t is the target, nil without one", function()
	eq(ns.EmoteWheel_Fill("/w %t Thanks!", "Aldric"), "/w Aldric Thanks!")
	eq(ns.EmoteWheel_Fill("/w %t Thanks!", nil), nil)
	eq(ns.EmoteWheel_Fill("/bow", nil), "/bow")
	eq(ns.EmoteWheel_Fill("%t, %t!", "Mi%ra"), "Mi%ra, Mi%ra!", "a % in the name is kept")
end)

test("parse: chat types, whispers, emotes, slash and secure commands", function()
	local a = ns.EmoteWheel_Parse("Hello there", LOOKUPS)
	eq(a.kind, "chat")
	eq(a.chatType, "SAY")
	a = ns.EmoteWheel_Parse("/p Ready!", LOOKUPS)
	eq(a.chatType, "PARTY")
	eq(a.text, "Ready!")
	a = ns.EmoteWheel_Parse("/w Kesha-Realm Thanks for the help", LOOKUPS)
	eq(a.target, "Kesha-Realm")
	eq(a.text, "Thanks for the help")
	eq(ns.EmoteWheel_Parse("/w Kesha", LOOKUPS), nil, "whisper without a message")
	eq(ns.EmoteWheel_Parse("/s", LOOKUPS), nil, "say without text")
	a = ns.EmoteWheel_Parse("/Bow", LOOKUPS)
	eq(a.kind, "emote")
	eq(a.token, "BOW")
	eq(a.target, nil)
	eq(ns.EmoteWheel_Parse("/ty Mira", LOOKUPS).target, "Mira")
	eq(ns.EmoteWheel_Parse("/cast Fireball", LOOKUPS).kind, "secure")
	a = ns.EmoteWheel_Parse("/random 100", LOOKUPS)
	eq(a.kind, "slash")
	eq(a.key, "RANDOM")
	eq(a.msg, "100")
	eq(ns.EmoteWheel_Parse("/nothing", LOOKUPS).kind, "unknown")
	eq(ns.EmoteWheel_Parse("   ", LOOKUPS), nil)
end)

test("slice under the cursor, slice 1 at the top, clockwise", function()
	eq(ns.EmoteWheel_SliceAt(0, 100, 8, 40), 1, "up")
	eq(ns.EmoteWheel_SliceAt(100, 0, 8, 40), 3, "right")
	eq(ns.EmoteWheel_SliceAt(0, -100, 8, 40), 5, "down")
	eq(ns.EmoteWheel_SliceAt(-100, 0, 8, 40), 7, "left")
	eq(ns.EmoteWheel_SliceAt(-10, 100, 8, 40), 1, "just left of up is still slice 1")
	eq(ns.EmoteWheel_SliceAt(-100, 95, 8, 40), 8, "up-left")
	eq(ns.EmoteWheel_SliceAt(10, 10, 8, 40), nil, "center")
	eq(ns.EmoteWheel_SliceAt(100, 100, 4, 40), 2, "45 degrees with 4 slices is on the edge: the next slice")
end)

test("angle and point agree with SliceAt", function()
	for count = 4, 12 do
		for i = 1, count do
			local x, y = ns.EmoteWheel_Point(ns.EmoteWheel_Angle(i, count), 100)
			eq(ns.EmoteWheel_SliceAt(x, y, count, 40), i, count .. " slices, slice " .. i)
		end
	end
end)

test("buff thanks: long buffs from other players, out of combat, once a while", function()
	local buff = { fromPlayer = true, duration = 3600, inCombat = false, inInstance = false }
	local rules = { instances = false }
	eq(ns.EmoteWheel_ShouldThank(buff, rules, nil, 100), true)
	eq(ns.EmoteWheel_ShouldThank(buff, rules, 50, 100), false, "just thanked")
	eq(ns.EmoteWheel_ShouldThank(buff, rules, 100 - ns.EMOTEWHEEL_THANK_AGAIN, 100), true, "long ago")
	buff.duration = 30
	eq(ns.EmoteWheel_ShouldThank(buff, rules, nil, 100), false, "short buff")
	buff.duration = 3600
	buff.inCombat = true
	eq(ns.EmoteWheel_ShouldThank(buff, rules, nil, 100), false, "combat")
	buff.inCombat = false
	buff.inInstance = true
	eq(ns.EmoteWheel_ShouldThank(buff, rules, nil, 100), false, "instance")
	rules.instances = true
	eq(ns.EmoteWheel_ShouldThank(buff, rules, nil, 100), true, "instances allowed")
	buff.fromPlayer = false
	eq(ns.EmoteWheel_ShouldThank(buff, rules, nil, 100), false, "own buff")
end)

H.done()
