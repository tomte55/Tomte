local addonName, ns = ...

-- Mail: pure logic (no WoW API calls; unit-tested in tests/test_mail.lua). Which letters Open all takes from and in
-- what order, Auction House letter kinds, the running tally of opened letters, the end-of-run summary, when the next
-- take may go out, and who the alt picker offers. Mail.lua reads the inbox and drives the mailbox.

-- A letter, as Mail.lua reads it: { index, sender, subject, money, cod, isGM, invoiceType, class, items = { { slot,
-- itemID, currency } } }. class comes from ns.Mail_Classify.

-- Auction House letter kinds, in the order the summary lists them. "pending" (a sale whose gold is still on its way)
-- holds nothing to take and isn't counted.
ns.MAIL_AH_KINDS = { "sold", "won", "expired", "cancelled", "outbid" }
local AH = {}
for _, kind in ipairs(ns.MAIL_AH_KINDS) do
	AH[kind] = true
end
local KIND_WORDS = { sold = "sold", won = "won", expired = "expired", cancelled = "cancelled", outbid = "outbid",
	other = "other" }
-- Subjects tried in this order: the kinds without an invoice first; sold and won only when the invoice is missing.
local SUBJECT_ORDER = { "expired", "cancelled", "outbid", "sold", "won", "pending" }
local INVOICE_KIND = { seller = "sold", buyer = "won", seller_temp_invoice = "pending" }

local MAGIC = "([%(%)%.%%%+%-%*%?%[%]%^%$])"

-- A Lua pattern for one of Blizzard's subject formats ("Auction expired: %s", also "%1$s" in some locales).
function ns.Mail_SubjectPattern(fmt)
	local marked = fmt:gsub("%%%d*%$?s", "\001")
	local escaped = marked:gsub(MAGIC, "%%%1")
	return "^" .. escaped:gsub("\001", ".+") .. "$"
end

-- formats = { expired = AUCTION_EXPIRED_MAIL_SUBJECT, cancelled = AUCTION_REMOVED_MAIL_SUBJECT, ... } (missing ones
-- are left out) -> { { kind, pattern } } in SUBJECT_ORDER.
function ns.Mail_SubjectPatterns(formats)
	local list = {}
	for _, kind in ipairs(SUBJECT_ORDER) do
		local fmt = formats[kind]
		if type(fmt) == "string" and fmt ~= "" then
			list[#list + 1] = { kind = kind, pattern = ns.Mail_SubjectPattern(fmt) }
		end
	end
	return list
end

-- "sold", "won", "expired", "cancelled", "outbid", "pending" or "other". The invoice decides when there is one
-- (GetInboxInvoiceInfo only answers for sales and purchases); otherwise the subject.
function ns.Mail_Classify(letter, patterns)
	local kind = INVOICE_KIND[letter.invoiceType or ""]
	if kind then
		return kind
	end
	local subject = letter.subject or ""
	for _, p in ipairs(patterns or {}) do
		if subject:match(p.pattern) then
			return p.kind
		end
	end
	return "other"
end

function ns.Mail_IsAuction(kind)
	return AH[kind] == true
end

-- Why Open all leaves a letter alone, or nil when there's something to take. opts = { goldOnly, ahOnly }.
-- "cod" (cash on delivery: paying is your call), "gm" (Blizzard wants those opened by hand), "notAuction",
-- "empty" (nothing to take, or only items while taking gold only).
function ns.Mail_Skip(letter, opts)
	if (letter.cod or 0) > 0 then
		return "cod"
	elseif letter.isGM then
		return "gm"
	elseif opts.ahOnly and not AH[letter.class] then
		return "notAuction"
	elseif (letter.money or 0) > 0 then
		return nil
	elseif not opts.goldOnly and #(letter.items or {}) > 0 then
		return nil
	end
	return "empty"
end

local function StepKey(letter, kind, slot, itemID)
	return table.concat({ letter.sender or "", letter.subject or "", kind, slot or 0, itemID or letter.money or 0 },
		"|")
end

-- The next thing to take: { index, kind = "money" | "item", slot, itemID, key }, or nil. Gold first on each letter,
-- then its items from the last slot down. opts = { goldOnly, ahOnly, freeSlots, failed = { [itemID] = true } (the
-- server refused them: unique, bags), skip = { [key] = true } (stuck) }. Currency attachments need no bag slot and
-- never count as failed items (their ID is a currency ID, as in Blizzard's Open All). Second return: true when an
-- item was left because the bags are full.
function ns.Mail_NextStep(letters, opts)
	local bagsFull = false
	for _, letter in ipairs(letters) do
		if not ns.Mail_Skip(letter, opts) then
			if (letter.money or 0) > 0 then
				local key = StepKey(letter, "money")
				if not (opts.skip and opts.skip[key]) then
					return { index = letter.index, kind = "money", key = key }, bagsFull
				end
			end
			if not opts.goldOnly then
				local items = {}
				for i, item in ipairs(letter.items or {}) do
					items[i] = item
				end
				table.sort(items, function(a, b)
					return a.slot > b.slot
				end)
				for _, item in ipairs(items) do
					local key = StepKey(letter, "item", item.slot, item.itemID)
					local failed = not item.currency and opts.failed and opts.failed[item.itemID]
					if not failed and not (opts.skip and opts.skip[key]) then
						if not item.currency and (opts.freeSlots or 0) <= 0 then
							bagsFull = true
						else
							return { index = letter.index, kind = "item", slot = item.slot, itemID = item.itemID,
								key = key }, bagsFull
						end
					end
				end
			end
		end
	end
	return nil, bagsFull
end

-- Letters with something left to take, by kind: { [kind] = n }.
function ns.Mail_Counts(letters, opts)
	local counts = {}
	for _, letter in ipairs(letters) do
		if not ns.Mail_Skip(letter, opts) then
			local kind = letter.class or "other"
			counts[kind] = (counts[kind] or 0) + 1
		end
	end
	return counts
end

-- Adds the letters that were emptied between two counts to opened (in place) and returns it. New mail arriving in
-- between raises a count, which isn't an opened letter: only drops count.
function ns.Mail_Tally(opened, before, after)
	for kind, n in pairs(before) do
		local drop = n - (after[kind] or 0)
		if drop > 0 then
			opened[kind] = (opened[kind] or 0) + drop
		end
	end
	return opened
end

-- What to do on a tick. s = { pending (a mail command is still on its way), sinceLast (seconds since the last take,
-- nil before the first), minDelay, step (ns.Mail_NextStep's), more (more letters wait on the server than the inbox
-- shows), waited (seconds spent waiting for them), maxWait }.
-- "wait" (too soon, or the server is busy), "take", "more" (nothing left here, more mail on its way) or "done".
function ns.Mail_Decide(s)
	if s.pending or (s.sinceLast and s.sinceLast < s.minDelay) then
		return "wait"
	elseif s.step then
		return "take"
	elseif s.more and (s.waited or 0) < s.maxWait then
		return "more"
	end
	return "done"
end

-- The inbox in one string (letters, gold, items): a take that worked changes it. Two letters alike (the same sale
-- twice) give the same step key, so a repeated key alone doesn't mean a take failed; an unchanged inbox does.
function ns.Mail_Signature(letters)
	local money, items = 0, 0
	for _, letter in ipairs(letters) do
		money = money + (letter.money or 0)
		items = items + #(letter.items or {})
	end
	return #letters .. ":" .. money .. ":" .. items
end

-- The same take was sent tries times without the inbox changing: give up on it.
function ns.Mail_Stuck(tries, limit)
	return tries >= limit
end

-- The summary of a run. s = { money (copper), opened = { [kind] = n }, left (letters still holding something),
-- cod (cash-on-delivery letters left), bagsFull, goldOnly }. price(copper) formats money (ns.Price).
-- Returns title ("1,234g from 18 letters"), detail ("5 sold, 2 won, 1 other") and note ("4 left: bags full"; may
-- be ""). Nothing taken: title "Nothing to take".
function ns.Mail_Summary(s, price)
	local total = 0
	for _, n in pairs(s.opened or {}) do
		total = total + n
	end
	local money = s.money or 0
	local title
	if total == 0 and money <= 0 then
		title = "Nothing to take"
	else
		local letters = total == 1 and "1 letter" or (total .. " letters")
		title = money > 0 and (price(money) .. " from " .. letters) or ("Opened " .. letters)
	end
	local parts = {}
	for _, kind in ipairs(ns.MAIL_AH_KINDS) do
		local n = s.opened and s.opened[kind] or 0
		if n > 0 then
			parts[#parts + 1] = n .. " " .. KIND_WORDS[kind]
		end
	end
	local others = 0
	for kind, n in pairs(s.opened or {}) do
		if not AH[kind] then
			others = others + n
		end
	end
	if others > 0 then
		parts[#parts + 1] = others .. " " .. KIND_WORDS.other
	end
	local notes = {}
	if (s.left or 0) > 0 then
		local why = s.bagsFull and ": bags full" or (s.goldOnly and ": items, gold only" or "")
		notes[#notes + 1] = s.left .. " left" .. why
	end
	if (s.cod or 0) > 0 then
		notes[#notes + 1] = s.cod .. " cash on delivery"
	end
	return title, table.concat(parts, ", "), table.concat(notes, ", ")
end

-- Characters the picker offers. chars = { [guid] = { name, realm, faction, class } }, me = { guid },
-- reachable(c) -> bool (mail reaches that realm), mailName(c) -> "Name" or "Name-Realm".
-- Returns { { name = mail name, short = c.name, class } } sorted by name; yourself and unreachable realms left out.
-- Both factions: your own characters on the same or a connected realm can mail each other across factions. A
-- Pandaren that hasn't picked a faction yet ("Neutral") is left out.
function ns.Mail_Recipients(chars, me, reachable, mailName)
	local list = {}
	for guid, c in pairs(chars) do
		if guid ~= me.guid and c.name and c.faction ~= "Neutral" and reachable(c) then
			list[#list + 1] = { name = mailName(c), short = c.name, class = c.class }
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- Remembers a recipient at the front of recent (in place, case-insensitive, at most max) and returns it.
function ns.Mail_Remember(recent, name, max)
	recent = recent or {}
	if type(name) ~= "string" then
		return recent
	end
	name = name:match("^%s*(.-)%s*$")
	if name == "" then
		return recent
	end
	local lower = name:lower()
	for i = #recent, 1, -1 do
		if recent[i]:lower() == lower then
			table.remove(recent, i)
		end
	end
	table.insert(recent, 1, name)
	while #recent > max do
		table.remove(recent)
	end
	return recent
end
