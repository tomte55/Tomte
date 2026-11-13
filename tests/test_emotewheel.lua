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

test("buff thanks: a refresh is an update with the full duration left", function()
	eq(ns.EmoteWheel_JustRefreshed(3600, 3700, 100), true, "recast just now")
	eq(ns.EmoteWheel_JustRefreshed(3600, 3699, 100), true, "event a second late")
	eq(ns.EmoteWheel_JustRefreshed(3600, 3000, 100), false, "running down")
	eq(ns.EmoteWheel_JustRefreshed(0, 0, 100), false, "no duration")
	eq(ns.EmoteWheel_JustRefreshed(nil, nil, 100), false, "missing")
end)

test("store fills every slot, empty ones after the list", function()
	local slots = ns.EmoteWheel_Store({ { name = "Bow", text = "/bow" }, { name = "", text = "" } })
	eq(slots.s1.text, "/bow")
	eq(slots.s2.text, "", "a slice still being made")
	eq(slots["s" .. ns.EMOTEWHEEL_MAX].name, "", "last slot")
	eq(#ns.EmoteWheel_Slices(slots), 1, "the wheel skips the empty one")
end)

test("move shifts the slices between", function()
	local function names(list)
		local out = {}
		for i, s in ipairs(list) do
			out[i] = s.name
		end
		return table.concat(out, " ")
	end
	local list = { { name = "a" }, { name = "b" }, { name = "c" }, { name = "d" } }
	eq(names(ns.EmoteWheel_Move(list, 1, 3)), "b c a d", "forward")
	eq(names(ns.EmoteWheel_Move(list, 4, 1)), "d b c a", "back")
	eq(names(ns.EmoteWheel_Move(list, 2, 9)), "d b c a", "out of range")
end)

local MORE = {
	chat = { ["/S"] = "SAY", ["/W"] = "WHISPER", ["/P"] = "PARTY", ["/G"] = "GUILD", ["/Y"] = "YELL",
		["/O"] = "OFFICER" },
	emotes = LOOKUPS.emotes, secure = LOOKUPS.secure, slash = LOOKUPS.slash,
}

local function Kind(text)
	return table.concat({ ns.EmoteWheel_Kind(text, MORE) }, "|")
end

test("kind tells emotes, chat lines and commands apart", function()
	eq(select("#", ns.EmoteWheel_Kind("", MORE)), 2)
	eq(ns.EmoteWheel_Kind("", MORE), "emote", "empty: no emote picked yet")
	eq(Kind("/ty"), "emote|THANK")
	eq(Kind("/bow Kesha"), "command", "emote at someone by name")
	eq(Kind("Good luck"), "line|SAY|Good luck")
	eq(Kind("/p Ready"), "line|PARTY|Ready")
	eq(Kind("/g"), "line|GUILD|", "no message yet")
	eq(Kind("/w %t Thanks!"), "line|WHISPER|Thanks!")
	eq(Kind("/w %t"), "line|WHISPER|")
	eq(Kind("/w Kesha hi"), "command", "whisper by name")
	eq(Kind("/o hi"), "command", "a channel the editor doesn't build")
	eq(Kind("/dance"), "command")
end)

test("line builds the text back", function()
	local commands = { SAY = "/s", PARTY = "/p", WHISPER = "/w" }
	eq(ns.EmoteWheel_Line("SAY", " Hello ", commands), "Hello", "plain text is said")
	eq(ns.EmoteWheel_Line("SAY", "", commands), "/s", "nothing yet")
	eq(ns.EmoteWheel_Line("SAY", "/odd", commands), "/s /odd")
	eq(ns.EmoteWheel_Line("PARTY", "Ready", commands), "/p Ready")
	eq(ns.EmoteWheel_Line("WHISPER", "Thanks!", commands), "/w %t Thanks!")
	eq(ns.EmoteWheel_Line("WHISPER", "", commands), "/w %t")
	for _, chatType in ipairs({ "SAY", "PARTY", "WHISPER" }) do
		local text = ns.EmoteWheel_Line(chatType, "Hi %t", commands)
		eq(Kind(text), "line|" .. chatType .. "|Hi %t", "round trip " .. chatType)
	end
end)

test("describe says what a slice does", function()
	eq(ns.EmoteWheel_Describe("/ty", MORE), "Does /ty, at your target if you have one.")
	eq(ns.EmoteWheel_Describe("/bow %t", MORE), "Does /bow at [target].")
	eq(ns.EmoteWheel_Describe("Hello %t", MORE), "Says \"Hello [target]\".")
	eq(ns.EmoteWheel_Describe("/w %t Thanks!", MORE), "Whispers \"Thanks!\" to your target.")
	eq(ns.EmoteWheel_Describe("/g", MORE), "Sends nothing yet: add a message.")
	eq(ns.EmoteWheel_Describe("/cast Heal", MORE), "The wheel can't run /cast: only the game's own buttons and macros can.")
	eq(ns.EmoteWheel_Describe("/nope", MORE), "/nope isn't a command the game knows.")
	eq(ns.EmoteWheel_Describe("", MORE), "Pick an emote, or write a line to say.")
end)

test("several lines: run in turn, like a macro", function()
	local lines = ns.EmoteWheel_Lines(" Thanks! \r\n\n  /ty  \n")
	eq(#lines, 2, "empty lines left out")
	eq(lines[1], "Thanks!", "trimmed")
	eq(lines[2], "/ty")
	eq(#ns.EmoteWheel_Lines(""), 0)
	eq(ns.EmoteWheel_OneLine("Thanks!\n/ty"), "Thanks!; /ty")
	eq(ns.EmoteWheel_OneLine("/bow"), "/bow")
	eq(ns.EmoteWheel_Label({ name = "", text = "/ty\nThanks!" }), "Ty", "label from the first line")
	eq(ns.EmoteWheel_Label({ name = "", text = "Thanks!\n/ty" }), "Thanks!")
	eq(Kind("Thanks!\n/ty"), "command", "the editor shows several lines as a command")
	eq(Kind("/ty\n"), "emote|THANK", "a trailing empty line is still one line")
	eq(ns.EmoteWheel_Describe("Thanks!\n/ty", MORE),
		"Says \"Thanks!\". Then does /ty, at your target if you have one.")
	-- A lone / (typing the next line) used to error in Parse and Kind.
	eq(ns.EmoteWheel_Parse("/", MORE), nil, "a / alone does nothing")
	eq(Kind("/"), "command")
	eq(ns.EmoteWheel_Describe("Thanks!\n/", MORE), "Says \"Thanks!\". Then sends nothing yet: add a message.")
	local list = ns.EmoteWheel_Slices({ s1 = { name = "", text = "Thanks!\n/ty\n" } })
	eq(list[1].text, "Thanks!\n/ty", "a slice keeps its lines")
end)

test("extras: acts out, voice line for this race and sex", function()
	local saved = { ns.EMOTEWHEEL_ACTS, ns.EMOTEWHEEL_VOICE }
	ns.EMOTEWHEEL_ACTS = { WAVE = true, CHEER = true }
	ns.EMOTEWHEEL_VOICE = { CHEER = true, BEG = { ["2-0"] = true, ["10-1-12"] = true } }
	local function extras(...)
		local acts, voice = ns.EmoteWheel_Extras(...)
		return tostring(acts) .. " " .. tostring(voice)
	end
	eq(extras("WAVE", 2, 2, 1), "true false", "acts, no voice")
	eq(extras("CHEER", 2, 3, 1), "true true", "every race")
	eq(extras("BEG", 2, 2, 1), "false true", "this race, male")
	eq(extras("BEG", 2, 3, 1), "false false", "this race, female")
	eq(extras("BEG", 10, 3, 12), "false true", "a class's own line")
	eq(extras("BEG", 10, 3, 2), "false false", "not that class")
	eq(extras("NOPE", 2, 2, 1), "false false", "unknown emote")
	eq(extras(nil, 2, 2, 1), "false false", "no emote")
	ns.EMOTEWHEEL_ACTS, ns.EMOTEWHEEL_VOICE = saved[1], saved[2]
	eq(ns.EmoteWheel_ExtrasText(true, true), "Your character acts it out and says it out loud.")
	eq(ns.EmoteWheel_ExtrasText(false, true), "Your character says it out loud.")
	eq(ns.EmoteWheel_ExtrasText(false, false), nil)
end)

test("generated emote data", function()
	assert(loadfile("Tomte/Modules/EmoteWheel/Generated.lua"))("Tomte", ns)
	local acts, voice = ns.EmoteWheel_Extras("CHEER", 1, 2, 1)
	eq(acts and voice, true, "cheer acts out and has a voice line")
	acts, voice = ns.EmoteWheel_Extras("BOW", 1, 2, 1)
	eq(tostring(acts) .. " " .. tostring(voice), "true false", "bow is silent")
	eq(ns.EmoteWheel_Extras("AGREE", 1, 2, 1), false, "agree is text only")
end)

test("label place: short labels stay put, a wide one on a slanted slice finds room", function()
	local step = 2 * math.pi / 8
	local function place(i, nameW, cmdW)
		local boxes = { { nameW, 15, 6.5 }, { cmdW, 11, -8.5 } }
		return ns.EmoteWheel_LabelPlace(ns.EmoteWheel_Angle(i, 8), step, boxes, 106, 60, 150, 8, 30)
	end
	local x, y = place(1, 40, 20)
	H.near(x, 0, "Thank: on the middle")
	H.near(y, 106, "Thank: the usual radius")
	x, y = place(3, 40, 30)
	H.near(x, 106, "Wave: the usual radius")
	local wx, wy = place(2, 70, 55)
	local mx, my = place(8, 70, 55)
	H.near(mx, -wx, "No Mana mirrors Welcome")
	H.near(my, wy, "No Mana mirrors Welcome")
	local r = math.sqrt(wx * wx + wy * wy)
	assert(r > 60 and r < 150, "Welcome stays on the ring: " .. r)
	assert(math.atan(wx / wy) > math.pi / 4, "and away from Thank, its wide line's near side")
end)

test("filter emotes by name or command", function()
	local emotes = { { name = "Wave", commands = { "/wave" } }, { name = "Thank", commands = { "/thank", "/ty" } } }
	eq(#ns.EmoteWheel_FilterEmotes(emotes, ""), 2)
	eq(ns.EmoteWheel_FilterEmotes(emotes, "/TY")[1].name, "Thank", "by an alias")
	eq(ns.EmoteWheel_FilterEmotes(emotes, "av")[1].name, "Wave")
	eq(#ns.EmoteWheel_FilterEmotes(emotes, "zzz"), 0)
end)

H.done()
