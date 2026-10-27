local addonName, ns = ...

-- Bags: pure logic (no WoW API calls; unit-tested in tests/test_bags.lua): the default categories, which category
-- gets an item, and the order of items inside one. Rules are search texts (Search.lua). The item record (Read.lua):
-- the fields Search.lua lists, plus itemID, link, icon, bag, slot, locked, readable; an empty slot is
-- { empty = true, kind = "normal" | "reagent", bag, slot }.

-- The default layout: Tomte's own list, from the game's item classes. A node is
--   { kind = "category", key, name, rule = "<search>" | auto = "new" | "set" | "empty" | "other", priority,
--     ownLine (a row of its own: nothing shares its line), hidden (its items aren't shown), shows ([place] = false
--     for "bags" / "bank" / "warband" it stays out of), items ([itemID] = true: always in it, before any rule) }
--   { kind = "section", key, name, children = { nodes } }
--   { kind = "divider" }
-- An item goes to the matching category with the highest priority (default 0); on a tie, the one higher in the list.
ns.BAGS_LAYOUT = {
	{ kind = "category", key = "new", name = "New", auto = "new", priority = 10, ownLine = true },
	{ kind = "category", key = "upgrades", name = "Upgrades", rule = "is:upgrade", priority = 5, ownLine = true },
	{ kind = "category", key = "hearth", name = "Hearthstone", rule = "is:hearth" },
	{ kind = "category", key = "keystone", name = "Keystone", rule = "is:keystone" },
	{ kind = "category", key = "potion", name = "Potion", rule = "is:potion" },
	{ kind = "category", key = "food", name = "Food", rule = "is:food" },
	{ kind = "category", key = "consumable", name = "Consumable", rule = "is:consumable" },
	{ kind = "category", key = "quest", name = "Quest", rule = "is:quest" },
	{ kind = "section", key = "equipment", name = "Equipment", children = {
		{ kind = "category", key = "sets", name = "Equipment sets", auto = "set", priority = 1 },
		{ kind = "category", key = "weapon", name = "Weapon", rule = "is:weapon" },
		{ kind = "category", key = "armor", name = "Armor", rule = "is:armor" },
	} },
	{ kind = "section", key = "crafting", name = "Crafting", children = {
		{ kind = "category", key = "reagent", name = "Reagent", rule = "is:reagent or is:tradegoods" },
		{ kind = "category", key = "profession", name = "Profession equipment", rule = "is:profession" },
		{ kind = "category", key = "recipe", name = "Recipe", rule = "is:recipe" },
	} },
	{ kind = "category", key = "decor", name = "Decor", rule = "is:decor" },
	{ kind = "category", key = "gem", name = "Gem", rule = "is:gem" },
	{ kind = "category", key = "enhancement", name = "Item enhancement", rule = "is:enhancement" },
	{ kind = "category", key = "bag", name = "Bag", rule = "is:bag" },
	{ kind = "category", key = "key", name = "Key", rule = "is:key" },
	{ kind = "category", key = "toy", name = "Toy", rule = "is:toy", priority = 1 },
	{ kind = "category", key = "pet", name = "Pets and mounts", rule = "is:pet or is:mount", priority = 1 },
	{ kind = "category", key = "misc", name = "Miscellaneous", rule = "is:misc" },
	{ kind = "divider", key = "tail" },
	{ kind = "category", key = "other", name = "Other", auto = "other" },
	{ kind = "category", key = "junk", name = "Junk", rule = "is:junk", priority = 8 },
	{ kind = "category", key = "empty", name = "Empty", auto = "empty", priority = 20 },
}

-- Rule texts compiled once: [text] = matcher, or false when the text doesn't compile.
local compiled = {}

local function Matcher(rule)
	local m = compiled[rule]
	if m == nil then
		m = ns.BagsSearch_Compile(rule) or false
		compiled[rule] = m
	end
	return m
end

-- The layout's categories in order: each node gets .order (its place) and .section (its section's key).
function ns.Bags_Flatten(layout)
	local list = {}
	local function Walk(nodes, section)
		for _, node in ipairs(nodes) do
			if node.kind == "category" then
				node.order = #list + 1
				node.section = section
				list[#list + 1] = node
			elseif node.kind == "section" then
				Walk(node.children or {}, node.key)
			end
		end
	end
	Walk(layout, nil)
	return list
end

-- Whether a category takes an item, ignoring the other categories ("other" takes anything here).
local function Takes(category, item)
	if item.empty then
		return category.auto == "empty"
	end
	local auto = category.auto
	if auto == "new" then
		return item.new == true
	elseif auto == "set" then
		return item.set ~= nil
	elseif auto == "empty" then
		return false
	elseif auto == "other" then
		return false
	end
	local m = category.rule and Matcher(category.rule)
	return m and m(item) == true or false
end

-- True when a beats b in the contest for an item.
local function Beats(a, b)
	local pa, pb = a.priority or 0, b.priority or 0
	if pa ~= pb then
		return pa > pb
	end
	return a.order < b.order
end

-- Whether a category takes part where the items are: place is "bags", "bank" or "warband"; category.shows
-- ([place] = false to leave a place out) nil means everywhere.
local function ShowsIn(category, place)
	return not (category.shows and place and category.shows[place] == false)
end

local function Winner(item, categories, place)
	-- An item the player put in a category by hand goes there, whatever the rules say (the first such category).
	if not item.empty and item.itemID then
		for _, category in ipairs(categories) do
			if category.items and category.items[item.itemID] and ShowsIn(category, place) then
				return category
			end
		end
	end
	local best
	for _, category in ipairs(categories) do
		if ShowsIn(category, place) and Takes(category, item) and (not best or Beats(category, best)) then
			best = category
		end
	end
	if best then
		return best
	end
	for _, category in ipairs(categories) do
		if category.auto == "other" then
			return category
		end
	end
	return nil
end

-- Items to their categories: byKey[category key] = { items }. Every item lands in exactly one category (none when
-- the layout has no "other"). place: "bags" (default), "bank" or "warband", for categories shown only in some.
function ns.Bags_Assign(items, categories, place)
	local byKey = {}
	place = place or "bags"
	for _, item in ipairs(items) do
		local category = Winner(item, categories, place)
		if category then
			local list = byKey[category.key]
			if not list then
				list = {}
				byKey[category.key] = list
			end
			list[#list + 1] = item
		end
	end
	return byKey
end

-- Sort keys, each nil when a and b tie on it. Numbers higher first unless said otherwise.
local function Quality(a, b)
	if (a.quality or 0) ~= (b.quality or 0) then
		return (a.quality or 0) > (b.quality or 0)
	end
end

local function Level(a, b)
	if (a.ilvl or 0) ~= (b.ilvl or 0) then
		return (a.ilvl or 0) > (b.ilvl or 0)
	end
end

local function Name(a, b)
	if (a.name or "") ~= (b.name or "") then
		return (a.name or "") < (b.name or "")
	end
end

local function Kind(a, b)
	if (a.classID or 99) ~= (b.classID or 99) then
		return (a.classID or 99) < (b.classID or 99)
	end
	if (a.subclassID or 99) ~= (b.subclassID or 99) then
		return (a.subclassID or 99) < (b.subclassID or 99)
	end
end

-- The same item last: item ID, bigger stack first, then bag and slot, so the order never depends on table.sort.
local function Last(a, b)
	if (a.itemID or 0) ~= (b.itemID or 0) then
		return (a.itemID or 0) < (b.itemID or 0)
	end
	if (a.count or 0) ~= (b.count or 0) then
		return (a.count or 0) > (b.count or 0)
	end
	if (a.bag or 0) ~= (b.bag or 0) then
		return (a.bag or 0) < (b.bag or 0)
	end
	return (a.slot or 0) < (b.slot or 0)
end

-- The sort setting's methods: the keys tried in order.
local SORTS = {
	quality = { Quality, Level, Name },
	type = { Kind, Quality, Level, Name },
	name = { Name, Quality, Level },
	ilvl = { Level, Quality, Name },
}
ns.BAGS_SORTS = { "quality", "type", "name", "ilvl" }

-- Items inside a category, in place. method: a SORTS key (default quality: best quality first, then higher item
-- level, then name); reverse turns the whole order around.
function ns.Bags_SortItems(list, method, reverse)
	local keys = SORTS[method] or SORTS.quality
	table.sort(list, function(a, b)
		if reverse then
			a, b = b, a
		end
		for _, key in ipairs(keys) do
			local before = key(a, b)
			if before ~= nil then
				return before
			end
		end
		return Last(a, b)
	end)
	return list
end

-- The marks an item can carry, in the order they win a shared corner: junk coin, Gear Check's arrow, the crafting
-- list's count, the transmog diamond, the equipment set mark, a battle pet's level, the item level.
ns.BAGS_MARKS = { "junk", "upgrade", "crafting", "transmog", "set", "petlevel", "ilvl" }

-- Which mark each corner shows: has[mark] is true (or a value) when the item carries it, corners[mark] is the corner
-- picked for it ("TOPLEFT", ... or "off"). Returns [corner] = mark: the first carried mark of that corner in
-- BAGS_MARKS order, so marks sharing a corner never overlap.
function ns.Bags_CornerMarks(has, corners)
	local shown = {}
	for _, mark in ipairs(ns.BAGS_MARKS) do
		local corner = corners[mark]
		if has[mark] and corner and corner ~= "off" and not shown[corner] then
			shown[corner] = mark
		end
	end
	return shown
end

-- Whether an item can go where the open window wants it (the windows Blizzard's item context matching doesn't
-- cover): "merchant" (it sells for something), "mail" (not soulbound), "trade" and "auction" (not bound at all,
-- and not a quest item). Anything else, or no window: true.
function ns.Bags_Fits(item, situation)
	if item.empty or not situation then
		return true
	end
	if situation == "merchant" then
		return not item.noValue
	elseif situation == "mail" then
		return item.bind ~= "soulbound"
	elseif situation == "trade" or situation == "auction" then
		return (item.bind == nil or item.bind == "boe") and not item.quest
	elseif situation == "warband" then
		return item.warbandOK ~= false -- the game's answer, read by the window (C_Bank.IsItemAllowedInBankType)
	end
	return true
end

-- Junk: grey, sells for something, and not soulbound (a soulbound grey is a keepsake like a rolled message or a
-- quest leftover, not vendor trash). quality: Enum.ItemQuality (0 = Poor).
function ns.Bags_IsJunk(quality, noValue, bind)
	return quality == 0 and not noValue and bind ~= "soulbound"
end

-- Keeping places while a window that takes items is open (selling, mailing): items don't move, a slot that emptied
-- stays where its item was. A slot key is bag * 1000 + slot.
local function SlotKey(record)
	return record.bag * 1000 + record.slot
end

-- The places to keep: [category key] = { slot keys in order }, from what's on screen now. Empty is left out (its
-- buttons stand for every free slot of a kind).
function ns.Bags_Snapshot(contents)
	local snapshot = {}
	for key, list in pairs(contents) do
		if key ~= "empty" then
			local slots = {}
			for i, record in ipairs(list) do
				slots[i] = SlotKey(record)
			end
			snapshot[key] = slots
		end
	end
	return snapshot
end

-- contents laid out by snapshot: each category keeps its slots in order, showing whatever is in each slot now (an
-- item, or the empty slot), then the items that weren't on screen yet in the category they belong to now.
-- bySlot: [slot key] = the record in that slot now (items and empty slots).
function ns.Bags_KeepPlaces(snapshot, contents, bySlot)
	local out, kept = {}, {}
	for key, slots in pairs(snapshot) do
		local list = {}
		for _, slotKey in ipairs(slots) do
			local record = bySlot[slotKey]
			if record then
				list[#list + 1] = record
				kept[slotKey] = true
			end
		end
		out[key] = list
	end
	for key, list in pairs(contents) do
		if key == "empty" then
			-- Empty's button for a kind can't be a slot kept elsewhere (one button, one place): another free slot of
			-- that kind stands in, with the same count; none left means none shown.
			local empties = {}
			for _, record in ipairs(list) do
				local stand = record
				if kept[SlotKey(record)] then
					stand = nil
					for slotKey, other in pairs(bySlot) do
						if other.empty and other.kind == record.kind and not kept[slotKey] then
							stand = setmetatable({ free = record.free }, { __index = other })
							break
						end
					end
				end
				empties[#empties + 1] = stand
			end
			out[key] = empties
		else
			local target = out[key] or {}
			for _, record in ipairs(list) do
				if not kept[SlotKey(record)] then
					target[#target + 1] = record
				end
			end
			out[key] = target
		end
	end
	return out
end

-- The currencies panel's rows from the game's currency list (C_CurrencyInfo.GetCurrencyListInfo entries plus
-- index) and the ones shown on the bag (tracked: { currencyID, name, quantity, iconFileID }, read apart from the
-- list, which leaves out what's under a folded header): first "Tracked", then the list with its headers. search (lower case) keeps the
-- currencies whose name has it, each under its header. Rows: { kind = "header", name, index, expanded, depth },
-- { kind = "currency", name, index, info, depth } or { kind = "hint" } (nothing tracked yet); the tracked group's
-- header has index nil. depth: how far in to indent (the game's currencyListDepth for headers, one more than its
-- header for a currency).
function ns.Bags_CurrencyRows(list, search, tracked)
	tracked = tracked or {}
	local rows = {}
	local function Matches(entry)
		return not search or search == "" or (entry.name or ""):lower():find(search, 1, true) ~= nil
	end
	rows[1] = { kind = "header", name = "Tracked", expanded = true, depth = 0 }
	for _, entry in ipairs(tracked) do
		if Matches(entry) then
			local info = setmetatable({ isShowInBackpack = true }, { __index = entry })
			rows[#rows + 1] = { kind = "currency", name = entry.name, info = info, depth = 1 }
		end
	end
	if #tracked == 0 and (not search or search == "") then
		rows[#rows + 1] = { kind = "hint" }
	end
	local header, headerShown
	for _, entry in ipairs(list) do
		if entry.isHeader then
			header, headerShown = { kind = "header", name = entry.name, index = entry.index,
				expanded = entry.isHeaderExpanded, depth = entry.currencyListDepth or 0 }, false
			if not search or search == "" then
				rows[#rows + 1] = header
				headerShown = true
			end
		elseif Matches(entry) then
			if header and not headerShown then
				rows[#rows + 1] = header
				headerShown = true
			end
			rows[#rows + 1] = { kind = "currency", name = entry.name, index = entry.index, info = entry,
				depth = (header and header.depth or 0) + 1 }
		end
	end
	return rows
end

-- A caged battle pet's level from its link ("battlepet:speciesID:level:..."), nil for anything else.
function ns.Bags_PetLevel(link)
	local level = link and link:match("|Hbattlepet:%d+:(%d+)")
	return level and tonumber(level)
end

-- Stacks of the same item (same link) merged into one record per item for "group identical items": the first
-- stack's record (its bag and slot, so clicks act on it) with count = the total and stacks = how many were merged.
-- Empty slots and unreadable items stay as they are.
function ns.Bags_Group(items)
	local out, byLink = {}, {}
	for _, item in ipairs(items) do
		local link = not item.empty and item.readable ~= false and item.link
		local first = link and byLink[link]
		if first then
			first.count = first.count + (item.count or 1)
			first.stacks = first.stacks + 1
		else
			local copy = item
			if link then
				copy = setmetatable({ count = item.count or 1, stacks = 1 }, { __index = item })
				byLink[link] = copy
			end
			out[#out + 1] = copy
		end
	end
	return out
end

-- Enum.ItemBind values (warcraft.wiki.gg/wiki/Enum.ItemBind).
local BIND_ON_EQUIP, BIND_ON_USE = 2, 3
local BIND_TO_ACCOUNT, BIND_TO_BNET, BIND_TO_BNET_UNTIL_EQUIPPED = 7, 8, 9

-- An item's bind state for the search: "soulbound", "warbound", "boe" (not bound yet, binds on equip or use) or nil.
-- bindType: the item's Enum.ItemBind; isBound: the container's isBound for this copy.
function ns.Bags_BindState(bindType, isBound)
	if isBound then
		if bindType == BIND_TO_ACCOUNT or bindType == BIND_TO_BNET then
			return "warbound"
		end
		return "soulbound"
	end
	if bindType == BIND_TO_ACCOUNT or bindType == BIND_TO_BNET or bindType == BIND_TO_BNET_UNTIL_EQUIPPED then
		return "warbound"
	elseif bindType == BIND_ON_EQUIP or bindType == BIND_ON_USE then
		return "boe"
	end
	return nil
end

-- For /tomte bags why: the categories that take the item, the winner first, as lines. place as for Bags_Assign.
function ns.Bags_Why(item, categories, place)
	local winner = Winner(item, categories, place or "bags")
	if winner and winner.items and item.itemID and winner.items[item.itemID] then
		return { ("%s (you put this item in it)"):format(winner.name) }
	end
	local taking = {}
	for _, category in ipairs(categories) do
		if ShowsIn(category, place or "bags") and Takes(category, item) then
			taking[#taking + 1] = category
		end
	end
	table.sort(taking, Beats)
	local lines = {}
	for i, category in ipairs(taking) do
		local how = category.rule and ("rule " .. category.rule) or ("automatic: " .. category.auto)
		lines[i] = ("%s%s (priority %d, %s)"):format(i == 1 and "" or "also ", category.name,
			category.priority or 0, how)
	end
	if #lines == 0 then
		lines[1] = "No category takes it, so it's in Other."
	end
	return lines
end
