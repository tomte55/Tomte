local addonName, ns = ...

-- Housing decor: pure logic for the house editor extras and the house list (no WoW API calls; unit-tested in
-- tests/test_decor_editor.lua). Copying dyes from one placed decor to another, which stored stack Alt places another
-- of, the hover lines, the editor clock, the preview's size next to a person, the house list order, what the Teleport
-- home binding does and the View Houses cards' art crop. The UI is in Editor.lua, Houses.lua, HouseList.lua and
-- Alert.lua.

local SIZE_DECIMALS = 1 -- "about 1.5 people tall"

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

-- Size next to a person -------------------------------------------------------------------------------------------

local function Round(n)
	local mult = 10 ^ SIZE_DECIMALS
	local r = math.floor(n * mult + 0.5) / mult
	if r == math.floor(r) then
		return ("%d"):format(r)
	end
	return ("%." .. SIZE_DECIMALS .. "f"):format(r)
end

-- How tall a model is next to a person: "about 1.5 people tall". nil when a height is unknown.
function ns.DecorEditor_PeopleText(height, person)
	if not (height and person and person > 0) then
		return nil
	end
	local n = height / person
	return ("about %s %s tall"):format(Round(n), Round(n) == "1" and "person" or "people")
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

-- View Houses window ------------------------------------------------------------------------------------------------

-- Neighborhood pictures by C_Housing.GetNeighborhoodTextureSuffix: Blizzard's housing loading screens
-- (Interface/Glues/LoadingScreens/Expansion10/Main), sharp where the dashboard's own neighborhood art is blurred.
-- top/bottom: the painted part (0-1), the rest is grey bars; focusY: which band shows on a wide card (0 = top).
local NEIGHBORHOOD_ART = {
	elwynn = { file = 7377860, width = 2992, height = 1684, top = 0, bottom = 1, focusY = 0.55 }, -- Founder's Point
	durotar = { file = 7490877, width = 2992, height = 1684, top = 0.165, bottom = 0.835, focusY = 0.5 }, -- Razorwind
}
NEIGHBORHOOD_ART.duratar = NEIGHBORHOOD_ART.durotar -- the dashboard atlas spells it this way too

-- The picture for a neighborhood texture suffix, shaped like an AtlasInfo (file, width, height and tex coords of the
-- painted part) plus focusY, for DecorEditor_ArtCrop. nil for a neighborhood without one here.
function ns.DecorEditor_NeighborhoodArt(suffix)
	local art = NEIGHBORHOOD_ART[suffix or ""]
	if not art then
		return nil
	end
	return { file = art.file, width = art.width, height = art.height * (art.bottom - art.top), leftTexCoord = 0,
		rightTexCoord = 1, topTexCoord = art.top, bottomTexCoord = art.bottom, focusY = art.focusY }
end

-- Texture coordinates that show an atlas region (AtlasInfo: leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord,
-- width, height) at `aspect` (width / height) without stretching: the full width and a band at focusY (0 = top,
-- 1 = bottom) when the art is taller, the full height and the middle when it's wider. nil for a missing or empty
-- region.
function ns.DecorEditor_ArtCrop(info, aspect, focusY)
	if not (info and info.width and info.height and info.width > 0 and info.height > 0 and aspect and aspect > 0) then
		return nil
	end
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local artAspect = info.width / info.height
	if artAspect > aspect then
		local keep = aspect / artAspect
		local cut = (r - l) * (1 - keep) / 2
		return l + cut, r - cut, t, b
	end
	local keep = artAspect / aspect
	local spare = (b - t) * (1 - keep)
	local top = t + spare * math.min(math.max(focusY or 0.5, 0), 1)
	return l, r, top, top + (b - t) * keep
end

-- Whether a house card needs its own neighborhood line: not when the house name already says it ("1 Hot Gravel
-- Settlement" in Hot Gravel Settlement).
function ns.DecorEditor_ShowNeighborhood(houseName, neighborhoodName)
	if type(neighborhoodName) ~= "string" or neighborhoodName == "" then
		return false
	end
	return not (type(houseName) == "string" and houseName:lower():find(neighborhoodName:lower(), 1, true))
end

-- How many house cards the View Houses window shows before it scrolls: all of them up to `max`, and room for one
-- (the "no houses" text) when there are none.
function ns.DecorEditor_CardsShown(count, max)
	return math.min(math.max(count or 0, 1), max)
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
