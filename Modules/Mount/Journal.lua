local addonName, ns = ...

-- Smart Mount's zone favorite star in the Mount Journal, top right of the mount display. It's lit when the selected
-- mount is a favorite for the zone or continent you're standing in; clicking it opens a menu to add or remove it
-- for either. The journal is load-on-demand, so the star is built when Blizzard_Collections loads.

local star, waiter

-- The zone and continent you stand in: { { mapID, name, kind } }.
local function Levels()
	local chain, infos = ns.Mount_Chain()
	local levels, haveZone, haveContinent = {}, false, false
	for i, mapID in ipairs(chain) do
		local mapType = infos[i].mapType
		if mapType == Enum.UIMapType.Zone and not haveZone then
			haveZone = true
			levels[#levels + 1] = { mapID = mapID, name = infos[i].name, kind = "zone" }
		elseif mapType == Enum.UIMapType.Continent and not haveContinent then
			haveContinent = true
			levels[#levels + 1] = { mapID = mapID, name = infos[i].name, kind = "continent" }
		end
	end
	return levels
end

local function SelectedMount()
	local mountID = MountJournal and MountJournal.selectedMountID
	if not mountID then
		return nil
	end
	local name, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
	return isCollected and mountID or nil, name
end

local function Starred(mountID)
	for _, level in ipairs(Levels()) do
		if ns.Mount_InZone(ns.mountDB.zones, level.mapID, mountID) then
			return true
		end
	end
	return false
end

function ns.MountJournal_Refresh()
	if not star then
		return
	end
	local mountID = SelectedMount()
	local show = ns.mountModule and ns.mountModule.active and mountID ~= nil
	star:SetShown(show)
	if show then
		local on = Starred(mountID)
		star.icon:SetDesaturated(not on)
		star.icon:SetAlpha(on and 1 or 0.6)
	end
end

local function Toggle(mapID, mountID)
	ns.Mount_ToggleZone(ns.mountDB.zones, mapID, mountID)
	ns.MountJournal_Refresh()
	ns.MountZonesPage_Refresh()
end

local function OpenMenu(owner)
	local mountID, name = SelectedMount()
	if not mountID then
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Smart Mount: " .. name)
		local levels = Levels()
		if #levels == 0 then
			root:CreateButton("No zone here", function() end)
		end
		for _, level in ipairs(levels) do
			root:CreateCheckbox(("Favorite in %s (%s)"):format(level.name, level.kind), function()
				return ns.Mount_InZone(ns.mountDB.zones, level.mapID, mountID)
			end, function()
				Toggle(level.mapID, mountID)
			end)
		end
	end)
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Smart Mount zone favorite")
	GameTooltip:AddLine("Click to add this mount to the favorites for the zone or continent you're in. Smart Mount picks from those first there.", 1, 1, 1, true)
	local mountID = SelectedMount()
	for _, level in ipairs(Levels()) do
		local on = mountID and ns.Mount_InZone(ns.mountDB.zones, level.mapID, mountID)
		GameTooltip:AddDoubleLine(level.name, on and "favorite" or "-", 0.8, 0.8, 0.8, on and 1 or 0.5, on and 0.82 or 0.5,
			on and 0 or 0.5)
	end
	GameTooltip:Show()
end

local function Build()
	local display = MountJournal.MountDisplay
	star = CreateFrame("Button", nil, display)
	star:SetSize(30, 30)
	star:SetPoint("TOPRIGHT", -10, -10)
	star:SetFrameLevel(display:GetFrameLevel() + 10)
	star.icon = star:CreateTexture(nil, "ARTWORK")
	star.icon:SetAllPoints()
	star.icon:SetAtlas("PetJournal-FavoritesIcon")
	star:SetHighlightAtlas("PetJournal-FavoritesIcon", "ADD")
	star:SetScript("OnClick", OpenMenu)
	star:SetScript("OnEnter", OnEnter)
	star:SetScript("OnLeave", GameTooltip_Hide)
	hooksecurefunc("MountJournal_UpdateMountDisplay", ns.MountJournal_Refresh)
	ns.MountJournal_Refresh()
end

-- Called from Mount.lua's init: build when the journal loads (or now, if it already has).
function ns.MountJournal_Init()
	if C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
		Build()
		return
	end
	if waiter then
		return
	end
	waiter = CreateFrame("Frame")
	waiter:RegisterEvent("ADDON_LOADED")
	waiter:SetScript("OnEvent", function(self, _, name)
		if name == "Blizzard_Collections" then
			self:UnregisterAllEvents()
			Build()
		end
	end)
end
