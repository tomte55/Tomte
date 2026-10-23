local addonName, ns = ...

-- Tooltip extras: the lines on item, currency and world object tooltips (reputation tokens, reagents of combine
-- items, token vendors, the key a chest needs) and Ctrl-click on a token in the bags to set a waypoint to its vendor.
-- Text from Data.lua, game reads in Read.lua; started and stopped from Tips.lua.

local UI = ns.UI
local IsSecret = ns.IsSecret
local Icon = ns.Tips_Icon

local db
local enabled = false
local hooked = false
local keysByName -- [localized chest name] = keys entry; rebuilt while a name isn't loaded yet

-- A colored line on this tooltip (UI.TipLine always writes to GameTooltip; post-calls also run on ItemRefTooltip
-- and the comparison tooltips).
local function AddRoleLine(tooltip, text, role)
	local r, g, b = UI.RGB(role)
	tooltip:AddLine(text, r, g, b, true)
end

local function SetRefresh(tooltip)
	if tooltip.RefreshDataNextUpdate then
		tooltip:RefreshDataNextUpdate()
	end
end

-- Reputation ------------------------------------------------------------------------------------------------------

local function AddRep(tooltip, factionIDs)
	local first = true
	for _, factionID in ipairs(factionIDs) do
		local rec = ns.Tips_FactionRecord(factionID)
		if rec then
			if first then
				tooltip:AddLine(" ")
				first = false
			end
			local status, role = ns.Tips_RepStatus(rec)
			tooltip:AddLine(UI.Wrap(rec.name or "?", "heading") .. "  " .. UI.Wrap(status, role), 1, 1, 1, true)
		end
	end
end

-- Reagents ----------------------------------------------------------------------------------------------------------

local function AddReagents(tooltip, recipe)
	local list, missing = ns.Tips_ReadReagents(recipe)
	local rows, crafts = ns.Tips_ReagentRows(list)
	tooltip:AddLine(" ")
	tooltip:AddLine(UI.Wrap("Reagents", "textMuted"))
	for i, row in ipairs(rows) do
		local r, g, b = UI.RGB(row.role)
		tooltip:AddDoubleLine(Icon(list[i].icon) .. row.left, row.right, r, g, b, r, g, b)
	end
	local text, role = ns.Tips_CraftsText(crafts)
	if text then
		AddRoleLine(tooltip, text, role)
	end
	if missing then
		SetRefresh(tooltip)
	end
end

-- Vendors -----------------------------------------------------------------------------------------------------------

local function MapName(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and info.name
end

local function AreaName(areaID)
	local name = C_Map.GetAreaInfo(areaID)
	return name ~= "" and name or nil
end

local function PlaceText(place)
	local mapName = MapName(place.map)
	local who
	if place.npc then
		who = ns.Tips_NpcName(place.npc, place.name)
		mapName = place.area and AreaName(place.area) or mapName
	elseif place.area then
		who = AreaName(place.area) or place.name
	else
		who = place.name
	end
	return ns.Tips_VendorText(place, who, mapName)
end

local function AddVendor(tooltip, places, inBags)
	local spacer = inBags
	for _, place in ipairs(places) do
		spacer = spacer or not place.named
	end
	if not spacer then
		return -- the item's own text names its vendors, and outside the bags there's no Ctrl-click hint
	end
	tooltip:AddLine(" ")
	for _, place in ipairs(places) do
		if not place.named then
			tooltip:AddLine(UI.Wrap("Spend at ", "textMuted") .. UI.Wrap(PlaceText(place), "heading"), 1, 1, 1, true)
		end
	end
	if inBags then
		AddRoleLine(tooltip, #places > 1 and "Ctrl-click: waypoint to the nearest one" or "Ctrl-click: waypoint",
			"success")
	end
end

local function SetWaypoint(place)
	local title = PlaceText(place)
	local setPoint = ns.Way_SetPoint -- Waypoints (Modules/Travel), looked up now: it may be off or missing
	local placed
	if setPoint then
		placed = setPoint(place.map, place.x, place.y, title) ~= nil -- nil: that map takes no pins
	elseif C_Map.CanSetUserWaypointOnMap(place.map) then
		ns.TrackPin(place.map, place.x, place.y)
		placed = true
	end
	ns.Print(placed and ("waypoint set: " .. title .. ".") or "can't set a waypoint on that map.")
end

-- HandleModifiedItemClick (Ctrl-click on a bag item) calls DressUpItemLocation first.
local function OnDressUpItemLocation(itemLocation)
	if not (enabled and db.vendors and itemLocation and itemLocation:IsValid()) then
		return
	end
	local itemID = C_Item.GetItemID(itemLocation)
	if not itemID or IsSecret(itemID) then
		return
	end
	local places = ns.Tips_VendorPlaces(ns.Tips_Data("vendors")[itemID])
	if #places == 0 then
		return
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y
	if pos then
		x, y = pos:GetXY()
	end
	if IsSecret(x) or IsSecret(y) then
		x, y = nil, nil
	end
	SetWaypoint(places[ns.Tips_PickVendor(places, mapID, x, y)])
end

-- Keys --------------------------------------------------------------------------------------------------------------

local function KeysByName()
	if keysByName then
		return keysByName
	end
	local map, complete = {}, true
	for itemID, entry in pairs(ns.Tips_Data("keys")) do
		local name = C_Item.GetItemNameByID(itemID)
		if name then
			map[name] = entry
		else
			complete = false
			C_Item.RequestLoadItemDataByID(itemID)
		end
	end
	if complete then
		keysByName = map
	end
	return map
end

local function AddKey(tooltip, entry)
	local name, have, icon
	if entry.currency then
		name, have, icon = ns.Tips_Currency(entry.currency)
	else
		name, have, icon = ns.Tips_Entry("item", entry.item)
	end
	if not name then
		SetRefresh(tooltip)
		return
	end
	local left, right, role = ns.Tips_KeyLine(name, have, entry.count)
	local r, g, b = UI.RGB(role)
	tooltip:AddDoubleLine(left, right .. " " .. Icon(icon), r, g, b, r, g, b)
end

-- Post-calls ------------------------------------------------------------------------------------------------------

local function ValidID(id)
	return id and not IsSecret(id) and type(id) == "number"
end

local function OnItem(tooltip, data)
	if not (enabled and tooltip.AddLine and data and ValidID(data.id)) then
		return
	end
	local itemID = data.id
	if db.rep then
		local factions = ns.Tips_ItemFactions(itemID)
		if factions then
			AddRep(tooltip, factions)
		end
	end
	if db.reagents then
		local recipe = ns.Tips_ItemRecipe(itemID)
		if recipe then
			AddReagents(tooltip, recipe)
		end
	end
	if db.vendors then
		local places = ns.Tips_VendorPlaces(ns.Tips_Data("vendors")[itemID])
		if #places > 0 then
			local info = tooltip.processingInfo
			AddVendor(tooltip, places, info and info.getterName == "GetBagItem")
		end
	end
end

local function OnCurrency(tooltip, data)
	if not (enabled and db.rep and tooltip.AddLine and data and ValidID(data.id)) then
		return
	end
	local factionID = C_CurrencyInfo.GetFactionGrantedByCurrency(data.id)
	if factionID and not IsSecret(factionID) then
		AddRep(tooltip, { factionID })
	end
end

local function OnObject(tooltip, data)
	if not (enabled and db.keys and tooltip.AddLine and data and data.lines and data.lines[1]) then
		return
	end
	local name = data.lines[1].leftText
	if not name or IsSecret(name) then
		return
	end
	local entry = KeysByName()[name]
	if entry then
		AddKey(tooltip, entry)
	end
end

-- Start and stop --------------------------------------------------------------------------------------------------

function ns.TipsTooltip_Start(moduleDB)
	db = moduleDB
	enabled = true
	KeysByName() -- asks for the chest names now, so the first hover finds them
	if not hooked then
		hooked = true -- post-calls and hooks can't be removed; each handler checks enabled
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, OnCurrency)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObject)
		hooksecurefunc("DressUpItemLocation", OnDressUpItemLocation)
	end
end

function ns.TipsTooltip_Stop()
	enabled = false
end
