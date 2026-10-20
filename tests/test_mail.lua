-- Run from the AddOns folder: lua Tomte/tests/test_mail.lua
local ns = {}
assert(loadfile("Tomte/Modules/Mail/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

-- The enUS subjects (GlobalStrings).
local PATTERNS = ns.Mail_SubjectPatterns({
	expired = "Auction expired: %s",
	cancelled = "Auction canceled: %s",
	outbid = "Outbid on %s",
	sold = "Auction successful: %s",
	won = "Auction won: %s",
	pending = "Sale Pending: %s",
})

local function price(copper)
	return math.floor(copper / 10000) .. "g"
end

local function letter(t)
	t.items = t.items or {}
	t.money = t.money or 0
	t.cod = t.cod or 0
	t.class = t.class or ns.Mail_Classify(t, PATTERNS)
	return t
end

-- Subjects ----------------------------------------------------------------------------------------------------

test("subject pattern escapes magic characters", function()
	local p = ns.Mail_SubjectPattern("Outbid on %s (100%)")
	eq(("Outbid on Linen Cloth (100%)"):match(p) ~= nil, true)
	eq(("Outbid on Linen Cloth (100x)"):match(p) ~= nil, false)
end)

test("subject pattern takes positional %1$s", function()
	local p = ns.Mail_SubjectPattern("Auktion abgelaufen: %1$s")
	eq(("Auktion abgelaufen: Leinenstoff"):match(p) ~= nil, true)
end)

test("missing formats are left out", function()
	local list = ns.Mail_SubjectPatterns({ expired = "Auction expired: %s", outbid = "" })
	eq(#list, 1)
	eq(list[1].kind, "expired")
end)

-- Classify ----------------------------------------------------------------------------------------------------

test("invoice decides sold, won and pending", function()
	eq(ns.Mail_Classify({ subject = "whatever", invoiceType = "seller" }, PATTERNS), "sold")
	eq(ns.Mail_Classify({ subject = "whatever", invoiceType = "buyer" }, PATTERNS), "won")
	eq(ns.Mail_Classify({ subject = "Sale Pending: Ore", invoiceType = "seller_temp_invoice" }, PATTERNS), "pending")
end)

test("subject decides expired, cancelled, outbid", function()
	eq(ns.Mail_Classify({ subject = "Auction expired: Linen Cloth" }, PATTERNS), "expired")
	eq(ns.Mail_Classify({ subject = "Auction canceled: Linen Cloth" }, PATTERNS), "cancelled")
	eq(ns.Mail_Classify({ subject = "Outbid on Linen Cloth" }, PATTERNS), "outbid")
	eq(ns.Mail_Classify({ subject = "Auction successful: Ore" }, PATTERNS), "sold")
end)

test("a player's letter is other", function()
	eq(ns.Mail_Classify({ subject = "Auction expired? lol" }, PATTERNS), "other")
	eq(ns.Mail_Classify({}, PATTERNS), "other")
	eq(ns.Mail_IsAuction("other"), false)
	eq(ns.Mail_IsAuction("outbid"), true)
end)

-- Skip --------------------------------------------------------------------------------------------------------

test("cash on delivery and GM letters are never taken", function()
	eq(ns.Mail_Skip(letter({ cod = 500, items = { { slot = 1, itemID = 7 } } }), {}), "cod")
	eq(ns.Mail_Skip(letter({ isGM = true, money = 5 }), {}), "gm")
end)

test("gold only leaves item letters", function()
	local items = letter({ subject = "hi", items = { { slot = 1, itemID = 7 } } })
	eq(ns.Mail_Skip(items, { goldOnly = true }), "empty")
	eq(ns.Mail_Skip(items, {}), nil)
end)

test("auction only leaves players' letters", function()
	eq(ns.Mail_Skip(letter({ subject = "from Kesha", money = 100 }), { ahOnly = true }), "notAuction")
	eq(ns.Mail_Skip(letter({ subject = "Outbid on Ore", money = 100 }), { ahOnly = true }), nil)
end)

-- Next step ---------------------------------------------------------------------------------------------------

test("gold first, then items from the last slot down", function()
	local letters = { letter({ index = 1, subject = "a", money = 300,
		items = { { slot = 1, itemID = 10 }, { slot = 3, itemID = 30 } } }) }
	local step = ns.Mail_NextStep(letters, { freeSlots = 5 })
	eq(step.kind, "money")
	letters[1].money = 0
	step = ns.Mail_NextStep(letters, { freeSlots = 5 })
	eq(step.kind, "item")
	eq(step.slot, 3)
	eq(step.index, 1)
end)

test("skips COD letters and goes on to the next", function()
	local letters = {
		letter({ index = 1, subject = "cod", cod = 100, items = { { slot = 1, itemID = 1 } } }),
		letter({ index = 2, subject = "Auction won: Ore", invoiceType = "buyer", items = { { slot = 1, itemID = 2 } } }),
	}
	local step = ns.Mail_NextStep(letters, { freeSlots = 5 })
	eq(step.index, 2)
end)

test("bags full: items left, gold still taken, bagsFull reported", function()
	local letters = {
		letter({ index = 1, subject = "x", items = { { slot = 1, itemID = 1 } } }),
		letter({ index = 2, subject = "Auction successful: Ore", invoiceType = "seller", money = 900 }),
	}
	local step, full = ns.Mail_NextStep(letters, { freeSlots = 0 })
	eq(step.index, 2)
	eq(step.kind, "money")
	eq(full, true)
	letters[2].money = 0
	step, full = ns.Mail_NextStep(letters, { freeSlots = 0 })
	eq(step, nil)
	eq(full, true)
end)

test("bags full: currency attachments are still taken", function()
	local letters = { letter({ index = 1, subject = "x", items = { { slot = 3, itemID = 1 },
		{ slot = 1, itemID = 2, currency = true } } }) }
	local step, full = ns.Mail_NextStep(letters, { freeSlots = 0, failed = { [2] = true } })
	eq(step.slot, 1)
	eq(full, true)
end)

test("failed and stuck items are passed over", function()
	local letters = { letter({ index = 1, subject = "x", items = { { slot = 1, itemID = 1 }, { slot = 2, itemID = 2 } } }) }
	local step = ns.Mail_NextStep(letters, { freeSlots = 5, failed = { [2] = true } })
	eq(step.itemID, 1)
	local skip = { [step.key] = true }
	step = ns.Mail_NextStep(letters, { freeSlots = 5, failed = { [2] = true }, skip = skip })
	eq(step, nil)
end)

test("gold only never returns an item step", function()
	local letters = { letter({ index = 1, subject = "x", items = { { slot = 1, itemID = 1 } } }) }
	eq(ns.Mail_NextStep(letters, { freeSlots = 5, goldOnly = true }), nil)
end)

-- Tally -------------------------------------------------------------------------------------------------------

test("counts and tally follow emptied letters", function()
	local letters = {
		letter({ index = 1, subject = "Auction successful: Ore", invoiceType = "seller", money = 100 }),
		letter({ index = 2, subject = "Auction expired: Ore", items = { { slot = 1, itemID = 1 } } }),
		letter({ index = 3, subject = "hi", cod = 5, items = { { slot = 1, itemID = 1 } } }),
	}
	local before = ns.Mail_Counts(letters, {})
	eq(before.sold, 1)
	eq(before.expired, 1)
	eq(before.other, nil)
	table.remove(letters, 1) -- emptied and deleted
	letters[1].items = {}
	local opened = ns.Mail_Tally({}, before, ns.Mail_Counts(letters, {}))
	eq(opened.sold, 1)
	eq(opened.expired, 1)
end)

test("new mail arriving doesn't count as opened", function()
	local opened = ns.Mail_Tally({ sold = 2 }, { sold = 1 }, { sold = 3 })
	eq(opened.sold, 2)
end)

-- Decide ------------------------------------------------------------------------------------------------------

test("decide waits on the server and the pace", function()
	local step = { index = 1 }
	eq(ns.Mail_Decide({ pending = true, step = step, minDelay = 0.15 }), "wait")
	eq(ns.Mail_Decide({ sinceLast = 0.1, step = step, minDelay = 0.15 }), "wait")
	eq(ns.Mail_Decide({ sinceLast = 0.2, step = step, minDelay = 0.15 }), "take")
	eq(ns.Mail_Decide({ step = step, minDelay = 0.15 }), "take")
end)

test("decide waits for more mail, then stops", function()
	eq(ns.Mail_Decide({ minDelay = 0.15, more = true, waited = 10, maxWait = 70 }), "more")
	eq(ns.Mail_Decide({ minDelay = 0.15, more = true, waited = 71, maxWait = 70 }), "done")
	eq(ns.Mail_Decide({ minDelay = 0.15 }), "done")
end)

test("signature changes with any take", function()
	local letters = { letter({ index = 1, subject = "a", money = 300, items = { { slot = 1, itemID = 10 } } }),
		letter({ index = 2, subject = "a", money = 300 }) }
	local before = ns.Mail_Signature(letters)
	eq(before, "2:600:1")
	table.remove(letters, 2)
	eq(ns.Mail_Signature(letters) ~= before, true)
	eq(ns.Mail_Signature({}), "0:0:0")
end)

test("stuck after the limit", function()
	eq(ns.Mail_Stuck(4, 5), false)
	eq(ns.Mail_Stuck(5, 5), true)
end)

-- Summary -----------------------------------------------------------------------------------------------------

test("summary lists auction kinds in order, others last", function()
	local title, detail, note = ns.Mail_Summary({ money = 12340000,
		opened = { won = 2, sold = 5, other = 1, outbid = 1 } }, price)
	eq(title, "1234g from 9 letters")
	eq(detail, "5 sold, 2 won, 1 outbid, 1 other")
	eq(note, "")
end)

test("summary notes letters left and COD", function()
	local title, detail, note = ns.Mail_Summary({ money = 0, opened = { expired = 1 }, left = 4, bagsFull = true,
		cod = 2 }, price)
	eq(title, "Opened 1 letter")
	eq(detail, "1 expired")
	eq(note, "4 left: bags full, 2 cash on delivery")
end)

test("summary with nothing taken", function()
	local title = ns.Mail_Summary({ money = 0, opened = {} }, price)
	eq(title, "Nothing to take")
end)

-- Recipients --------------------------------------------------------------------------------------------------

test("recipients: own other characters on reachable realms, both factions", function()
	local chars = {
		me = { name = "Aldric", realm = "Silvermoon", faction = "Alliance", class = "PALADIN" },
		a = { name = "Mira", realm = "Silvermoon", faction = "Alliance", class = "MAGE" },
		b = { name = "Kesha", realm = "Ravencrest", faction = "Alliance", class = "ROGUE" },
		c = { name = "Tolvan", realm = "Silvermoon", faction = "Horde", class = "HUNTER" },
		d = { name = "Bram", realm = "Far", faction = "Alliance" },
		e = { name = "Pandy", realm = "Silvermoon", faction = "Neutral" },
	}
	local list = ns.Mail_Recipients(chars, { guid = "me" }, function(c)
		return c.realm ~= "Far"
	end, function(c)
		return c.realm == "Silvermoon" and c.name or (c.name .. "-" .. c.realm)
	end)
	eq(#list, 3)
	eq(list[1].name, "Kesha-Ravencrest")
	eq(list[2].name, "Mira")
	eq(list[2].class, "MAGE")
	eq(list[3].name, "Tolvan")
end)

test("remember: newest first, case-insensitive, capped", function()
	local recent = ns.Mail_Remember(nil, "Mira", 3)
	ns.Mail_Remember(recent, "Kesha", 3)
	ns.Mail_Remember(recent, " mira ", 3)
	eq(table.concat(recent, ","), "mira,Kesha")
	ns.Mail_Remember(recent, "A", 3)
	ns.Mail_Remember(recent, "B", 3)
	eq(table.concat(recent, ","), "B,A,mira")
	ns.Mail_Remember(recent, "", 3)
	ns.Mail_Remember(recent, nil, 3)
	eq(#recent, 3)
end)

H.done()
