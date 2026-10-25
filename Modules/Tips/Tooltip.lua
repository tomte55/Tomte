local addonName, ns = ...

-- Tooltip extras: the lines on item, currency and world object tooltips (reputation tokens, reagents of combine
-- items, token vendors, the key a chest needs) and Ctrl-click on a token in the bags to set a waypoint to its vendor.
-- Text from Data.lua, game reads in Read.lua; started and stopped from Tips.lua. Also the settings previews' example
-- tooltips (Panel/Preview.lua), drawn by the same post-call.

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

local ITEM_KINDS = { "rep", "reagents", "vendors" } -- the order the lines go on an item tooltip

-- One kind's lines for an item (nothing when it gets none). inBags: the tooltip is a bag item's (Ctrl-click hint).
local function AddItemKind(tooltip, itemID, kind, inBags)
	if kind == "rep" then
		local factions = ns.Tips_ItemFactions(itemID)
		if factions then
			AddRep(tooltip, factions)
		end
	elseif kind == "reagents" then
		local recipe = ns.Tips_ItemRecipe(itemID)
		if recipe then
			AddReagents(tooltip, recipe)
		end
	elseif kind == "vendors" then
		local places = ns.Tips_VendorPlaces(ns.Tips_Data("vendors")[itemID])
		if #places > 0 then
			AddVendor(tooltip, places, inBags)
		end
	end
end

local previews = setmetatable({}, { __mode = "k" }) -- [settings preview tooltip] = the one line kind it shows

local function OnItem(tooltip, data)
	if not (tooltip.AddLine and data and ValidID(data.id)) then
		return
	end
	local only = previews[tooltip]
	if only then
		-- A settings preview: its row's line whatever the module and switches say, drawn as in the bags.
		AddItemKind(tooltip, data.id, only, true)
		return
	end
	if not enabled then
		return
	end
	local info = tooltip.processingInfo
	local inBags = info and info.getterName == "GetBagItem"
	for _, kind in ipairs(ITEM_KINDS) do
		if db[kind] then
			AddItemKind(tooltip, data.id, kind, inBags)
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

-- Also from a settings preview while the module is off: harmless, every handler checks enabled (or previews).
local function Hook()
	if hooked then
		return
	end
	hooked = true -- post-calls and hooks can't be removed
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, OnCurrency)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObject)
	hooksecurefunc("DressUpItemLocation", OnDressUpItemLocation)
end

function ns.TipsTooltip_Start(moduleDB)
	db = moduleDB
	enabled = true
	KeysByName() -- asks for the chest names now, so the first hover finds them
	Hook()
end

function ns.TipsTooltip_Stop()
	enabled = false
end

-- Setting previews --------------------------------------------------------------------------------------------------

local loading = {} -- [itemID] = true while a preview waits for it

-- True when the item's data is here; else asks for it once and redraws module's preview card when it comes.
function ns.Tips_PreviewLoaded(itemID, module)
	if C_Item.IsItemDataCachedByID(itemID) then
		return true
	end
	-- An ID this client doesn't know never loads (and ContinueOnItemLoad errors on it).
	if not C_Item.DoesItemExistByID(itemID) then
		return false
	end
	if not loading[itemID] then
		Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
			loading[itemID] = nil
			ns.Preview_Refresh(module)
		end)
		loading[itemID] = not C_Item.IsItemDataCachedByID(itemID) or nil -- the callback may have run already
	end
	return false
end

-- The tips tables, the player's expansion first, then newest to oldest.
function ns.Tips_PreviewSources()
	local mine = ns.ContentExpansion()
	local sources = { ns.Content_Get(mine, "tips") }
	local all = ns.Content_Expansions()
	for i = #all, 1, -1 do
		if all[i] ~= mine then
			sources[#sources + 1] = ns.Content_Get(all[i], "tips")
		end
	end
	return sources
end

-- Whether itemID (loaded) gets kind's line for this character: "yes", "no" (try the next sample) or "wait" (data is
-- on its way; the card redraws when it comes).
local function Usable(kind, itemID, module)
	if kind == "keys" then
		local entry = ns.Tips_Data("keys")[itemID]
		if entry.item and not ns.Tips_PreviewLoaded(entry.item, module) then
			return "wait"
		end
		local name = entry.currency and ns.Tips_Currency(entry.currency) or (entry.item and true)
		return name and "yes" or "no"
	elseif kind == "rep" then
		for _, factionID in ipairs(ns.Tips_ItemFactions(itemID) or {}) do
			if ns.Tips_FactionRecord(factionID) then
				return "yes"
			end
		end
		return "no"
	elseif kind == "reagents" then
		local recipe = ns.Tips_ItemRecipe(itemID)
		if not recipe then
			return "no"
		end
		local ready = true
		for _, r in ipairs(recipe.reagents) do
			if r.itemID and not ns.Tips_PreviewLoaded(r.itemID, module) then
				ready = false
			end
		end
		return ready and "yes" or "wait"
	end
	return #ns.Tips_VendorPlaces(ns.Tips_Data("vendors")[itemID]) > 0 and "yes" or "no"
end

-- Draws an example tooltip with kind's line ("keys", "rep", "reagents", "vendors") into host, on a real item from the
-- data (the player's expansion first). Returns its size, or nil while nothing is ready.
function ns.TipsTooltip_Preview(host, kind, module)
	for _, itemID in ipairs(ns.Tips_PreviewItems(ns.Tips_PreviewSources(), kind)) do
		if C_Item.DoesItemExistByID(itemID) then
			if not ns.Tips_PreviewLoaded(itemID, module) then
				return nil
			end
			local usable = Usable(kind, itemID, module)
			if usable == "wait" then
				return nil
			elseif usable == "yes" then
				local tip = ns.Preview_Tooltip(host)
				if kind == "keys" then
					-- The key line sits on the chest's world object tooltip, which only shows its name above it.
					tip:SetText(C_Item.GetItemNameByID(itemID))
					AddKey(tip, ns.Tips_Data("keys")[itemID])
				else
					previews[tip] = kind
					Hook() -- the line comes from the post-call, so a tooltip refresh keeps it
					tip:SetItemByID(itemID)
				end
				return ns.Preview_TooltipSize(tip)
			end
		end
	end
	return nil
end
