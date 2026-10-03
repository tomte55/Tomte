local addonName, ns = ...

-- Zones tab of Smart Mount in the panel: every zone or continent with favorites, its mounts under it. Click the x on
-- a mount to remove it, or Clear to drop a whole list. Adding happens with the star in the Mount Journal.

local UI = ns.UI
local GOLD, WHITE, GREY = UI.GOLD, UI.WHITE, UI.GREY
local HEADER_H, ROW_H, ICON = 26, 22, 18

local page
local rows, used = {}, 0

local function NewRow()
	local row = CreateFrame("Frame", nil, page.scroll.content)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.name = UI.Text(row, 12, WHITE)
	row.name:SetWordWrap(false)
	row.button = UI.Button(row, 60, "")
	row.button:SetPoint("RIGHT", -6, 0)
	row.button:SetScript("OnClick", function(self)
		self.onClick()
	end)
	row.name:SetPoint("RIGHT", row.button, "LEFT", -8, 0)
	return row
end

local function Row()
	used = used + 1
	local row = rows[used] or NewRow()
	rows[used] = row
	row:Show()
	return row
end

local function MapName(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and info.name or ("map " .. mapID)
end

local function Layout()
	for i = 1, used do
		rows[i]:Hide()
	end
	used = 0
	local zones = ns.mountDB.zones
	local mapIDs = {}
	for mapID in pairs(zones) do
		mapIDs[#mapIDs + 1] = mapID
	end
	table.sort(mapIDs, function(a, b)
		return MapName(a) < MapName(b)
	end)
	page.none:SetShown(#mapIDs == 0)

	local y = 0
	for _, mapID in ipairs(mapIDs) do
		local header = Row()
		header:SetHeight(HEADER_H)
		header:SetPoint("TOPLEFT", 0, -y)
		header:SetPoint("RIGHT")
		header.icon:Hide()
		header.name:ClearAllPoints()
		header.name:SetPoint("LEFT", 8, 0)
		header.name:SetPoint("RIGHT", header.button, "LEFT", -8, 0)
		header.name:SetText(MapName(mapID))
		header.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		header.button.label:SetText("Clear")
		header.button.onClick = function()
			zones[mapID] = nil
			Layout()
			ns.MountJournal_Refresh()
		end
		y = y + HEADER_H
		for _, mountID in ipairs(zones[mapID]) do
			local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
			local row = Row()
			row:SetHeight(ROW_H)
			row:SetPoint("TOPLEFT", 0, -y)
			row:SetPoint("RIGHT")
			row.icon:Show()
			row.icon:SetTexture(icon)
			row.icon:SetPoint("LEFT", 20, 0)
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			row.name:SetPoint("RIGHT", row.button, "LEFT", -8, 0)
			row.name:SetText(name or ("mount " .. mountID))
			row.name:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
			row.button.label:SetText("Remove")
			row.button.onClick = function()
				ns.Mount_ToggleZone(zones, mapID, mountID)
				Layout()
				ns.MountJournal_Refresh()
			end
			y = y + ROW_H
		end
		y = y + 6
	end
	page.scroll:SetContentHeight(y)
end

function ns.MountZonesPage_Refresh()
	if page and page:IsVisible() then
		Layout()
	end
end

ns.MountZonesPage = {
	title = "Zones",
	Create = function(frame)
		page = frame
		page.scroll = UI.Scroll(page)
		page.scroll:SetPoint("TOPLEFT", 8, 0)
		page.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
		page.none = UI.Text(page, 12, GREY)
		page.none:SetPoint("TOPLEFT", 8, -4)
		page.none:SetPoint("RIGHT", -8, 0)
		page.none:SetText("No zone favorites yet. Open the Mount Journal, select a mount and click the star at the top right of its picture to make it a favorite for the zone or continent you're in.")
	end,
	Refresh = Layout,
}
