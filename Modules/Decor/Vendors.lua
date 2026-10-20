local addonName, ns = ...

-- Housing decor: learned vendor spots. The catalog names a decor's vendor and zone but not where the vendor stands,
-- and Blizzard's tracking can't lead to many vendors. When you open a shop that sells decor, Tomte remembers the
-- vendor, where you stand (next to them) and which decor they sell; vendor rows then get a waypoint. Rules in
-- Data.lua (Decor_LearnVendor, Decor_VendorSpot), the merchant events are wired in Decor.lua.

local Readable = ns.Readable

local db

function ns.DecorVendors_Init(moduleDB)
	db = moduleDB
end

local function IsDecorItem(itemID)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	local housing = Enum.ItemClass.Housing
	local decor = Enum.ItemHousingSubclass and Enum.ItemHousingSubclass.Decor
	return housing ~= nil and classID == housing and (decor == nil or subclassID == decor)
end

-- The decor the open shop sells (item IDs), from Blizzard's own merchant calls (MerchantFrame.lua).
local function ShopDecor()
	local items = {}
	for i = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(i)
		if Readable(itemID) and type(itemID) == "number" and IsDecorItem(itemID) then
			items[#items + 1] = itemID
		end
	end
	return items
end

-- Where you stand on your map (0..1): next to the vendor while their shop is open. Nil in instances, where the
-- game gives no position (warcraft.wiki.gg API_C_Map.GetPlayerMapPosition).
local function Position()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not Readable(mapID) or not mapID then
		return nil
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then
		return nil
	end
	local x, y = pos:GetXY()
	if not (Readable(x) and Readable(y)) or (x == 0 and y == 0) then
		return nil
	end
	return mapID, x, y
end

-- MERCHANT_SHOW / MERCHANT_UPDATE: learn the vendor if the shop sells decor. Returns true when something changed.
function ns.DecorVendors_Learn()
	local guid = UnitGUID("npc")
	local npcID = Readable(guid) and ns.Decor_NpcID(guid)
	if not npcID then
		return false
	end
	local items = ShopDecor()
	if #items == 0 then
		return false
	end
	local mapID, x, y = Position()
	if not mapID then
		return false
	end
	local name = UnitName("npc")
	local new = ns.Decor_LearnVendor(db.vendors, npcID, { name = Readable(name) and name or nil, mapID = mapID,
		x = x, y = y, items = items, now = GetServerTime() })
	if new then
		ns.Print(("remembered where %s stands (%d decor): their decor now gets a waypoint on the Decor page.")
			:format(name or "this vendor", #items))
	end
	return true
end

-- Every learned vendor (Data.lua's shape), for the page's decor by vendor. Read only.
function ns.DecorVendors_Learned()
	return db.vendors
end

-- The learned vendor for a decor entry, or nil.
function ns.DecorVendors_Spot(e)
	local _, v = ns.Decor_VendorSpot(e, db.vendors)
	return v
end

-- [itemID] = true for decor sold by learned vendors on your map.
function ns.DecorVendors_HereItems()
	local mapID = C_Map.GetBestMapForUnit("player")
	return ns.Decor_LearnedItemsOn(db.vendors, Readable(mapID) and mapID or nil)
end

-- A waypoint to the learned vendor of a decor entry (Tomte's map pin, super-tracked). Returns true when there is
-- a spot.
function ns.DecorVendors_Waypoint(e)
	local v = ns.DecorVendors_Spot(e)
	if not v then
		return false
	end
	if not C_Map.CanSetUserWaypointOnMap(v.mapID) then
		ns.Print(("%s stands on a map that can't hold a waypoint."):format(v.name or e.vendor or "That vendor"))
		return true
	end
	local now = ns.TrackPin(v.mapID, v.x, v.y)
	local info = C_Map.GetMapInfo(v.mapID)
	ns.Print(("%swaypoint to %s (%s %.1f, %.1f)."):format(now and "" or "after combat: ",
		v.name or e.vendor or "the vendor", info and info.name or "map", v.x * 100, v.y * 100))
	return true
end

-- /tomte decor vendors: every learned vendor, by name.
function ns.DecorVendors_Print()
	local list = {}
	for npcID, v in pairs(db.vendors) do
		local n = 0
		for _ in pairs(v.items or {}) do
			n = n + 1
		end
		local info = C_Map.GetMapInfo(v.mapID)
		list[#list + 1] = ("%s (%s %.1f, %.1f): %d decor, npc %d"):format(v.name or "?", info and info.name or "map",
			(v.x or 0) * 100, (v.y or 0) * 100, n, npcID)
	end
	table.sort(list)
	if #list == 0 then
		ns.Print("no decor vendors learned yet: open a shop that sells decor and Tomte remembers where it is.")
		return
	end
	ns.Print(("%d decor vendors learned:"):format(#list))
	for _, line in ipairs(list) do
		print("  " .. line)
	end
end
