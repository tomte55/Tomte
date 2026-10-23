local addonName, ns = ...

-- Housing decor: pure logic for the house editor extras and the house list (no WoW API calls; unit-tested in
-- tests/test_decor_editor.lua). Copying dyes from one placed decor to another, which stored stack Alt places another
-- of, the hover lines, the editor clock, the preview's size in bananas, the house list order and what the Teleport
-- home binding does. The UI is in Editor.lua, Houses.lua and Alert.lua.

local BANANA_DECIMALS = 1 -- "1.5 x 0.5 x 2 bananas"

-- Dyes --------------------------------------------------------------------------------------------------------------

-- A copy of the dye slots (HousingDecorDyeSlot: { ID, orderIndex, dyeColorID }) in display order.
local function Ordered(slots)
	local out = {}
	for i, slot in ipairs(slots or {}) do
		out[i] = slot
	end
	table.sort(out, function(a, b)
		if (a.orderIndex or 0) ~= (b.orderIndex or 0) then
			return (a.orderIndex or 0) < (b.orderIndex or 0)
		end
		return (a.ID or 0) < (b.ID or 0)
	end)
	return out
end

-- The colors on a decor's dye slots in display order: { dyeColorID or 0 (no dye) }. nil when it has no dye slots.
function ns.DecorEditor_DyeColors(slots)
	local ordered = Ordered(slots)
	if #ordered == 0 then
		return nil
	end
	local colors = {}
	for i, slot in ipairs(ordered) do
		colors[i] = slot.dyeColorID or 0
	end
	return colors
end

-- True when the decor's slots already wear the copied colors (slot by slot, in display order).
function ns.DecorEditor_DyesMatch(colors, slots)
	if not colors then
		return false
	end
	for i, slot in ipairs(Ordered(slots)) do
		if (slot.dyeColorID or 0) ~= (colors[i] or 0) then
			return false
		end
	end
	return true
end

-- The dye changes that put the copied colors on a decor: { { slotID, colorID } } for the slots that differ, colorID
-- nil to clear a slot. A decor with more slots than the copy gets the extra ones cleared.
function ns.DecorEditor_DyePlan(colors, slots)
	local plan = {}
	if not colors then
		return plan
	end
	for i, slot in ipairs(Ordered(slots)) do
		local want = colors[i] or 0
		if (slot.dyeColorID or 0) ~= want then
			plan[#plan + 1] = { slotID = slot.ID, colorID = want ~= 0 and want or nil }
		end
	end
	return plan
end

-- Placing another ----------------------------------------------------------------------------------------------------

-- variants: HousingCatalogEntryVariantInfo list ({ entryVariantID, numStored, dyeSlots }). hoveredSlots: the hovered
-- decor's dye slots. The stack Alt places: one in storage with the hovered decor's dyes, else any stack in storage.
-- redeemable: the decor has unredeemed copies, which aren't a stored stack; then the first variant stands in.
-- Returns the entryVariantID or nil.
function ns.DecorEditor_PickVariant(variants, hoveredSlots, redeemable)
	local colors = ns.DecorEditor_DyeColors(hoveredSlots)
	local anyStored
	for _, v in ipairs(variants or {}) do
		if (v.numStored or 0) > 0 and v.entryVariantID then
			if colors == nil and ns.DecorEditor_DyeColors(v.dyeSlots) == nil
				or ns.DecorEditor_DyesMatch(colors, v.dyeSlots) then
				return v.entryVariantID
			end
			anyStored = anyStored or v.entryVariantID
		end
	end
	if anyStored then
		return anyStored
	end
	if redeemable then
		local first = (variants or {})[1]
		return first and first.entryVariantID
	end
	return nil
end

-- Room in the house's decor budget for one more: hasMax false means there's no budget here.
function ns.DecorEditor_BudgetAllows(spent, max, hasMax, cost)
	if not hasMax then
		return true
	end
	return (spent or 0) + (cost or 0) <= (max or 0)
end

-- How many you have to place: stored plus unredeemed (HousingCatalogEntryInfo).
function ns.DecorEditor_Stored(info)
	if type(info) ~= "table" then
		return 0
	end
	local stored, redeem = info.totalNumStored, info.remainingRedeemable
	return (type(stored) == "number" and stored > 0 and stored or 0)
		+ (type(redeem) == "number" and redeem > 0 and redeem or 0)
end

-- The hover tooltip lines for a placed decor (info: its HousingCatalogEntryInfo, or nil): { { text, role } }.
-- dupe: Alt places another (the line only shows while there's one to place).
function ns.DecorEditor_HoverLines(info, dupe)
	local lines = {}
	if type(info) ~= "table" then
		return lines
	end
	local stored = ns.DecorEditor_Stored(info)
	lines[#lines + 1] = { ("In storage: %d"):format(stored), stored > 0 and "text" or "textMuted" }
	if type(info.totalNumPlaced) == "number" and info.totalNumPlaced > 0 then
		lines[#lines + 1] = { ("Placed in your houses: %d"):format(info.totalNumPlaced), "textMuted" }
	end
	if type(info.placementCost) == "number" then
		lines[#lines + 1] = { ("Decor budget cost: %d"):format(info.placementCost), "textMuted" }
	end
	if dupe and stored > 0 then
		lines[#lines + 1] = { "Alt: place another", "accent" }
	end
	return lines
end

-- Clock ---------------------------------------------------------------------------------------------------------------

-- "14:05", or "2:05 PM" when military is false (am/pm: the client's words, default "AM"/"PM").
function ns.DecorEditor_ClockText(hour, minute, military, am, pm)
	if military then
		return ("%02d:%02d"):format(hour, minute)
	end
	local h = hour % 12
	if h == 0 then
		h = 12
	end
	return ("%d:%02d %s"):format(h, minute, hour < 12 and (am or "AM") or (pm or "PM"))
end

-- Banana for scale ------------------------------------------------------------------------------------------------

local function Round(n)
	local mult = 10 ^ BANANA_DECIMALS
	local r = math.floor(n * mult + 0.5) / mult
	if r == math.floor(r) then
		return ("%d"):format(r)
	end
	return ("%." .. BANANA_DECIMALS .. "f"):format(r)
end

-- A model's bounding box size in bananas: "1.5 x 0.5 x 2 bananas" (width x depth x height). banana: one banana's
-- length in the same units. nil when either size is unknown.
function ns.DecorEditor_SizeText(width, depth, height, banana)
	if not (width and depth and height and banana and banana > 0) then
		return nil
	end
	return ("%s x %s x %s bananas"):format(Round(width / banana), Round(depth / banana), Round(height / banana))
end

-- Houses ----------------------------------------------------------------------------------------------------------

-- houses: HouseInfo list from PLAYER_HOUSE_LIST_UPDATED; matches: [houseGUID] = true for houses in your faction's
-- neighborhoods. The houses that can be teleported to (all three IDs there), your faction's first, then by
-- neighborhood and house name: { name, where, house, ownFaction }.
function ns.DecorEditor_HouseRows(houses, matches)
	local rows = {}
	for _, h in ipairs(houses or {}) do
		if h.neighborhoodGUID and h.houseGUID and h.plotID then
			rows[#rows + 1] = { name = h.houseName or "Your house", where = h.neighborhoodName, house = h,
				ownFaction = (matches or {})[h.houseGUID] == true }
		end
	end
	table.sort(rows, function(a, b)
		if a.ownFaction ~= b.ownFaction then
			return a.ownFaction
		end
		if (a.where or "") ~= (b.where or "") then
			return (a.where or "") < (b.where or "")
		end
		return a.name < b.name
	end)
	return rows
end

-- What the Teleport home binding does: "return" (back to where you were, while visiting a house and the game offers
-- the way back), "teleport" with the house (the first of HouseRows), or "none".
function ns.DecorEditor_HomeAction(rows, canReturn)
	if canReturn then
		return "return"
	end
	local first = rows and rows[1]
	if first then
		return "teleport", first.house
	end
	return "none"
end

-- Acquired alert ----------------------------------------------------------------------------------------------------

-- The decor ID for a name on the "decor acquired" alert: a recently added decor of that name (recent: [name] =
-- decorID), else the catalog entry of that name (entries: { id, name }). nil when neither knows it.
function ns.DecorEditor_FindByName(name, recent, entries)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if recent and recent[name] then
		return recent[name]
	end
	for _, e in ipairs(entries or {}) do
		if e.name == name then
			return e.id
		end
	end
	return nil
end
