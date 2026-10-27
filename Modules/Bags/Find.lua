local addonName, ns = ...

-- Bags: "Find on all characters": a panel beside the bag window listing every item any of your characters has (Item
-- counts' record) that matches the search, with who has how many. Opened from the saved searches menu (Window.lua).
-- The search language is Search.lua's; tooltip words aren't searched here (other characters' items aren't in reach).

local WIDTH = 300
local PAD = 8
local BAND_H = 34 -- the header band, as the bag window's
local ROW_H = 34
local ICON = 26
local MAX_ROWS = 200 -- matches listed at most

local UI = ns.UI

local panel, scroll, note
local rows = {}
local anchor -- the bag window

-- A light record for the search language from an item ID (no bag slot behind it).
local function Record(id)
	local _, typeName, subTypeName, equipLoc, icon, classID, subclassID = C_Item.GetItemInfoInstant(id)
	if not icon then
		return nil
	end
	return {
		itemID = id, icon = icon, name = C_Item.GetItemNameByID(id), typeName = typeName, subTypeName = subTypeName,
		equipLoc = equipLoc, classID = classID, subclassID = subclassID, quality = C_Item.GetItemQualityByID(id),
		readable = true,
	}
end

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, scroll.content)
	row:SetHeight(ROW_H)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 2, 0)
	row.name = UI.Text(row, 12, "text")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
	row.name:SetPoint("RIGHT", -4, 0)
	row.name:SetWordWrap(false)
	row.where = UI.Text(row, 11, "textMuted")
	row.where:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
	row.where:SetPoint("RIGHT", -4, 0)
	row.where:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetItemByID(self.itemID)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	rows[i] = row
	return row
end

-- "Aldric 12 · Kesha 3 · Warband 5" for one item.
local function WhereText(id)
	local record = ns.Counts_Record and ns.Counts_Record()
	local rowsOf = ns.Counts_Rows(ns.Counts_Entry(id), record or {}, UnitGUID("player"))
	local parts = {}
	for _, r in ipairs(rowsOf) do
		if r.kind == "char" then
			parts[#parts + 1] = ("%s %d"):format(UI.ClassColored(r.name, r.class), r.total)
		elseif r.kind == "warband" then
			parts[#parts + 1] = ("Warband %d"):format(r.total)
		else
			parts[#parts + 1] = ("%s %d"):format(r.name, r.total)
		end
	end
	return table.concat(parts, "  ")
end

local function Draw(text)
	local matcher = ns.BagsSearch_Compile(text)
	local found = {}
	if matcher then
		for _, id in ipairs(ns.Counts_ItemIDs and ns.Counts_ItemIDs() or {}) do
			local record = Record(id)
			if record and matcher(record) then
				found[#found + 1] = record
			end
		end
	end
	table.sort(found, function(a, b)
		return (a.name or "") < (b.name or "")
	end)
	local y, shown = 0, math.min(#found, MAX_ROWS)
	local width = scroll:GetWidth()
	for i = 1, shown do
		local record, row = found[i], Row(i)
		row.itemID = record.itemID
		row.icon:SetTexture(record.icon)
		row.name:SetText(record.name or ("item " .. record.itemID))
		row.where:SetText(WhereText(record.itemID))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row:Show()
		y = y + ROW_H
	end
	for i = shown + 1, #rows do
		rows[i]:Hide()
	end
	scroll:SetContentHeight(y)
	if not (ns.Counts_Active and ns.Counts_Active()) then
		note:SetText("Turn on Item counts to search every character.")
	elseif #found == 0 then
		note:SetText(("Nothing on any character matches \"%s\"."):format(text))
	else
		note:SetText(("%d items match \"%s\"."):format(#found, text))
	end
end

local function Build()
	panel = CreateFrame("Frame", nil, anchor)
	panel:SetWidth(WIDTH)
	panel:EnableMouse(true)
	UI.Panel(panel)
	-- Header band: the title and a close button; the list below in a tray. Docked flush to the bag window's left edge.
	local band = ns.BagsKit_Band(panel)
	band:SetPoint("TOPLEFT", 1, -1)
	band:SetPoint("TOPRIGHT", -1, -1)
	band:SetHeight(BAND_H)
	local title = UI.Text(band, 14, "heading", "title")
	title:SetPoint("LEFT", PAD, 0)
	title:SetText("On all characters")
	local close = ns.BagsKit_Cluster(band, { { glyph = "Close", tip = "Close", onClick = function()
		panel:Hide()
	end } })
	close:SetPoint("RIGHT", -PAD, 0)
	local tray = ns.BagsKit_Tray(panel)
	tray:SetPoint("TOPLEFT", band, "BOTTOMLEFT", PAD - 1, -PAD)
	tray:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	note = UI.Text(tray, 11, "textMuted")
	note:SetPoint("TOPLEFT", 8, -7)
	note:SetPoint("RIGHT", -8, 0)
	scroll = UI.Scroll(tray)
	scroll:SetPoint("TOPLEFT", 6, -24)
	scroll:SetPoint("BOTTOMRIGHT", -12, 6)
	panel:Hide()
end

-- Opens the panel beside window for a search text.
function ns.BagsFind_Show(window, text)
	anchor = window
	if not panel then
		Build()
	end
	panel:ClearAllPoints()
	panel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 1, 0)
	panel:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", 1, 0)
	ns.BagsCurrencies_Hide() -- one side panel at a time
	panel:Show()
	Draw(text)
end

function ns.BagsFind_Hide()
	if panel then
		panel:Hide()
	end
end
