local addonName, ns = ...

-- Gold & value: pure logic (unit-tested with plain Lua). Value.lua reads prices from Auctionator or TSM and the
-- game; this file decides which price counts and adds things up, and what the backpack item tracker shows.

local TRADEGOODS, REAGENT, GEM = 7, 5, 3
local WEAPON, ARMOR = 2, 4

-- "gathered" (trade goods and reagents), "gear" (weapons and armor) or "other".
function ns.Value_Category(classID)
	if classID == TRADEGOODS or classID == REAGENT or classID == GEM then
		return "gathered"
	elseif classID == WEAPON or classID == ARMOR then
		return "gear"
	end
	return "other"
end

-- Which source a price comes from. setting: "auto" | "auctionator" | "tsm" | "vendor"; has = { auctionator, tsm }.
function ns.Value_Source(setting, has)
	if setting == "vendor" then
		return "vendor"
	elseif setting == "tsm" then
		return has.tsm and "tsm" or (has.auctionator and "auctionator" or "vendor")
	elseif setting == "auctionator" then
		return has.auctionator and "auctionator" or (has.tsm and "tsm" or "vendor")
	end
	return has.tsm and "tsm" or (has.auctionator and "auctionator" or "vendor")
end

-- The price that counts for one item. info = { category, bound, auction, vendor }, gear = "auction" | "vendor" |
-- "none". Bound items can't be sold on the auction house, so they're worth their vendor price. Returns copper or nil
-- (nil: leave it out), and "auction" | "vendor".
function ns.Value_Pick(info, gear)
	if info.category == "gear" then
		if gear == "none" then
			return nil
		elseif gear == "vendor" then
			return info.vendor, "vendor"
		end
	end
	if info.bound then
		return info.vendor, "vendor"
	end
	if info.auction and info.auction > 0 then
		return info.auction, "auction"
	end
	return info.vendor, "vendor"
end

-- Session loot: loot[key] = { n, v (value when looted, copper), c (category), link }. key is the item ID, but the
-- link for gear: copies of one item at different item levels are priced apart.
function ns.Value_LootAdd(loot, itemID, link, count, unit, category)
	local key = category == "gear" and link or itemID
	local e = loot[key]
	if not e then
		e = { n = 0, v = 0, c = category, link = link }
		loot[key] = e
	end
	e.n = e.n + (count or 1)
	e.v = e.v + (unit or 0) * (count or 1)
	return e
end

-- Total value and by category. priceNow(key, entry) -> copper | nil, or nil to use the value when looted (key: an
-- item ID, or a link for gear).
-- skip = { [category] = true } leaves categories out (gear when "Gear and BoEs" is "Leave out").
function ns.Value_LootTotals(loot, priceNow, skip)
	local total, by = 0, { gathered = 0, gear = 0, other = 0 }
	for itemID, e in pairs(loot or {}) do
		if not (skip and skip[e.c]) then
			local v
			if priceNow then
				local unit = priceNow(itemID, e)
				v = unit and unit * e.n or e.v
			else
				v = e.v
			end
			total = total + v
			by[e.c or "other"] = (by[e.c or "other"] or 0) + v
		end
	end
	return total, by
end

-- Carried value from item stacks: { { price, count } }. Missing prices count as 0.
function ns.Value_Sum(stacks)
	local total = 0
	for _, s in ipairs(stacks) do
		total = total + (s.price or 0) * (s.count or 1)
	end
	return total
end

-- Craft cost: materials = { { need, have, unit } }. owned = "market" | "free" (what you already have costs nothing).
-- Returns cost and whether every material had a price.
function ns.Value_CraftCost(materials, owned)
	local cost, complete = 0, true
	for _, m in ipairs(materials) do
		local buy = m.need
		if owned == "free" then
			buy = math.max(m.need - (m.have or 0), 0)
		end
		if buy > 0 then
			if m.unit then
				cost = cost + m.unit * buy
			else
				complete = false
			end
		end
	end
	return cost, complete
end

-- Whether a price is too old to trust. age in days (nil = unknown, trusted).
function ns.Value_Stale(age, maxDays)
	return age ~= nil and age > maxDays
end

-- Backpack item tracker (Backpack.lua) --------------------------------------------------------------------------

-- A holiday's token, shown on the bag's currency bar while the holiday is on. Keys are the Holidays module's
-- (Modules/Holidays/Table.lua). Item and currency IDs checked on warcraft.wiki.gg.
ns.VALUE_HOLIDAY_TOKENS = {
	lunar = { kind = "item", id = 21100 }, -- Coin of Ancestry
	love = { kind = "item", id = 49927 }, -- Love Token
	noblegarden = { kind = "item", id = 44791 }, -- Noblegarden Chocolate
	midsummer = { kind = "item", id = 23247 }, -- Burning Blossom
	brewfest = { kind = "item", id = 37829 }, -- Brewfest Prize Token
	hallows = { kind = "item", id = 33226 }, -- Tricky Treats
	darkmoon = { kind = "currency", id = 515 }, -- Darkmoon Prize Ticket
	timewalking = { kind = "currency", id = 1166 }, -- Timewalking Badge
}
-- The order holiday tokens are listed in when two holidays overlap.
local HOLIDAY_ORDER = { "darkmoon", "timewalking", "lunar", "love", "noblegarden", "midsummer", "brewfest", "hallows" }

-- The item IDs in the settings list ("224025, 210796"; item links work too), each once, in order.
function ns.Value_ParseItems(text)
	local list, seen = {}, {}
	-- Color codes carry digits ("|cff0070dd", "|cnIQ4:"): out first. A link counts as its item ID; other links go.
	text = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", " "):gsub("|cn[^:]*:", " "):gsub("|r", " ")
	text = text:gsub("|Hitem:(%d+)[^|]*|h.-|h", " %1 "):gsub("|H.-|h.-|h", " ")
	for id in text:gmatch("%d+") do
		id = tonumber(id)
		if id and id > 0 and not seen[id] then
			seen[id] = true
			list[#list + 1] = id
		end
	end
	return list
end

-- The settings list with itemID added at the end or, when it's there, taken out. Returns the new text and true when
-- it was added.
function ns.Value_ToggleItem(text, itemID)
	local list, kept, found = ns.Value_ParseItems(text), {}, false
	for _, id in ipairs(list) do
		if id == itemID then
			found = true
		else
			kept[#kept + 1] = id
		end
	end
	if not found then
		kept[#kept + 1] = itemID
	end
	return table.concat(kept, ", "), not found
end

-- What the backpack tracker shows, in order: tokens of the holidays on now, the upgrade crests (highest tier first),
-- then the tracked items. Each { kind = "item" | "currency", id, count }. Left out: anything with no count, and a
-- currency Blizzard's own tracker shows already. opts = { items = { itemID, ... }, holidays = { [key] = true },
-- crests = { currencyID, ... } (lowest tier first), watched = { [currencyID] = true }, count = fn(kind, id) -> n }.
function ns.Value_BackpackEntries(opts)
	local entries, seen = {}, {}
	local watched = opts.watched or {}
	local function add(kind, id)
		local key = kind .. ":" .. id
		if seen[key] or (kind == "currency" and watched[id]) then
			return
		end
		seen[key] = true
		local count = opts.count(kind, id)
		if count and count > 0 then
			entries[#entries + 1] = { kind = kind, id = id, count = count }
		end
	end
	for _, key in ipairs(HOLIDAY_ORDER) do
		local token = ns.VALUE_HOLIDAY_TOKENS[key]
		if opts.holidays and opts.holidays[key] and token then
			add(token.kind, token.id)
		end
	end
	local crests = opts.crests or {}
	for i = #crests, 1, -1 do
		add("currency", crests[i])
	end
	for _, id in ipairs(opts.items or {}) do
		add("item", id)
	end
	return entries
end
