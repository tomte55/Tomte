-- Run from the AddOns folder: lua Tomte/tests/test_afk.lua
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/AFK/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

test("ClockText uses 24h or 12h", function()
	eq(ns.AFK_ClockText(21, 7, true), "21:07")
	eq(ns.AFK_ClockText(0, 5, true), "00:05")
	eq(ns.AFK_ClockText(21, 7, false), "9:07 PM")
	eq(ns.AFK_ClockText(0, 5, false), "12:05 AM")
	eq(ns.AFK_ClockText(12, 30, false), "12:30 PM")
end)

test("AwaySince counts the idle time before the game's automatic AFK flag", function()
	eq(ns.AFK_AwaySince(1000, nil), 700)
	eq(ns.AFK_AwaySince(1000, 400), 700) -- an old /afk doesn't count
	eq(ns.AFK_AwaySince(1000, 1010), 700) -- nor one typed after the flag appeared
end)

test("AwaySince starts at the flag right after a typed /afk", function()
	eq(ns.AFK_AwaySince(1000, 1000), 1000)
	eq(ns.AFK_AwaySince(1000, 996), 1000)
end)

test("XPGain is nil without progress", function()
	eq(ns.AFK_XPGain(70, 0.5, 70, 0.5), nil)
	eq(ns.AFK_XPGain(70, 0.5, 70, 0.4), nil)
end)

test("XPGain shows part of a level as a percentage", function()
	eq(ns.AFK_XPGain(70, 0.25, 70, 0.62), "+37% of a level")
	eq(ns.AFK_XPGain(70, 0.9, 71, 0.1), "+20% of a level")
end)

test("XPGain shows whole levels with one decimal", function()
	eq(ns.AFK_XPGain(70, 0.5, 72, 0.0), "+1.5 levels")
	eq(ns.AFK_XPGain(70, 0.0, 71, 0.0), "+1.0 levels")
end)

test("AddWhisper keeps the newest entries up to the cap", function()
	local list = {}
	for i = 1, 5 do
		ns.AFK_AddWhisper(list, { text = "m" .. i }, 3)
	end
	eq(#list, 3)
	eq(list[1].text, "m3")
	eq(list[3].text, "m5")
	eq(list.dropped, 2)
end)

test("VisibleWhispers returns the newest n, oldest first, and how many are left out", function()
	local list = {}
	for i = 1, 5 do
		ns.AFK_AddWhisper(list, { text = "m" .. i }, 20)
	end
	local shown, more = ns.AFK_VisibleWhispers(list, 3)
	eq(#shown, 3)
	eq(shown[1].text, "m3")
	eq(shown[3].text, "m5")
	eq(more, 2)
	shown, more = ns.AFK_VisibleWhispers(list, 10)
	eq(#shown, 5)
	eq(more, 0)
end)

test("VisibleWhispers counts entries dropped by the cap as left out", function()
	local list = {}
	for i = 1, 5 do
		ns.AFK_AddWhisper(list, { text = "m" .. i }, 3)
	end
	local shown, more = ns.AFK_VisibleWhispers(list, 2)
	eq(#shown, 2)
	eq(shown[2].text, "m5")
	eq(more, 3) -- m1, m2 dropped by the cap + m3 not shown
end)

test("MoneyText shows only gold once there is any, with thousands separators", function()
	local icons = { gold = "%sg", silver = "%ss", copper = "%sc" }
	eq(ns.AFK_MoneyText(500002312, false, icons), "50,000g")
	eq(ns.AFK_MoneyText(12345678, false, icons), "1,234g")
	eq(ns.AFK_MoneyText(9990000, false, icons), "999g")
	eq(ns.AFK_MoneyText(5612, false, icons), "56s 12c")
	eq(ns.AFK_MoneyText(5600, false, icons), "56s")
	eq(ns.AFK_MoneyText(7, false, icons), "7c")
	eq(ns.AFK_MoneyText(0, false, icons), "0c")
end)

test("MoneyText keeps silver next to gold when detailed", function()
	local icons = { gold = "%sg", silver = "%ss", copper = "%sc" }
	eq(ns.AFK_MoneyText(12345678, true, icons), "1,234g 56s")
	eq(ns.AFK_MoneyText(12340078, true, icons), "1,234g")
	eq(ns.AFK_MoneyText(1234567890, true, icons), "123,456g 78s")
	eq(ns.AFK_MoneyText(5612, true, icons), "56s 12c")
end)

test("interrupts: every entry is an event name with a rule", function()
	for event, rule in pairs(ns.AFK_INTERRUPTS) do
		eq(event:match("^[A-Z_]+$") ~= nil, true, "name " .. event)
		eq(rule == true or (type(rule) == "table" and type(rule.arg) == "number" and rule.value ~= nil), true,
			"rule " .. event)
	end
end)

test("interrupts: popups close the screen", function()
	for _, event in ipairs({ "LFG_PROPOSAL_SHOW", "READY_CHECK", "PARTY_INVITE_REQUEST", "CONFIRM_SUMMON",
		"LFG_ROLE_CHECK_SHOW", "LFG_READY_CHECK_SHOW", "PET_BATTLE_QUEUE_PROPOSE_MATCH", "DUEL_REQUESTED",
		"TRADE_REQUEST", "TRADE_SHOW", "RESURRECT_REQUEST", "GUILD_INVITE_REQUEST", "GROUP_INVITE_CONFIRMATION" }) do
		eq(ns.AFK_Interrupts(event), true, event)
	end
end)

test("interrupts: a premade group application only when invited", function()
	local event = "LFG_LIST_APPLICATION_STATUS_UPDATED" -- searchResultID, newStatus, oldStatus, groupName
	eq(ns.AFK_Interrupts(event, 12, "invited", "applied", "Mira's keys"), true)
	eq(ns.AFK_Interrupts(event, 12, "applied", "none", "Mira's keys"), false)
	eq(ns.AFK_Interrupts(event, 12, "declined", "applied", "Mira's keys"), false)
	eq(ns.AFK_Interrupts(event, 12, "inviteaccepted", "invited", "Mira's keys"), false)
	eq(ns.AFK_Interrupts(event), false, "no payload")
end)

test("interrupts: anything else doesn't", function()
	eq(ns.AFK_Interrupts("CHAT_MSG_WHISPER", "hi", "Aldric"), false)
	eq(ns.AFK_Interrupts("UPDATE_BATTLEFIELD_STATUS", 1), false, "AFK.lua checks the status itself")
end)

H.done()
