local addonName, ns = ...

-- Bags: "Find on all characters": a panel beside the bag window listing every item any of your characters has (Item
-- counts' record) that matches the search, with who has how many. Opened from the saved searches menu (Window.lua).
-- The search language is Search.lua's. Words also look in the tooltip ("Use:"), read from the item's saved link
-- (Item counts keeps one) a batch per frame and kept for the session. Items the game hasn't loaded have no name or
-- tooltip yet: they're asked for, and the search runs again as they arrive.

local WIDTH = 300
local PAD = 8
local BAND_H = 34 -- the header band, as the bag window's
local ROW_H = 34
local ICON = 26
local MAX_ROWS = 200 -- matches listed at most
local LOAD_DELAY = 0.3 -- seconds of arriving item data gathered into one new search
local TEXT_BATCH = 150 -- tooltips read per frame: a first search over every character doesn't stall the game

local UI = ns.UI

local panel, scroll, note
local rows = {}
local anchor -- the bag window
local lastText -- the search shown, run again as item data arrives
local loader -- watches GET_ITEM_INFO_RECEIVED while items are still loading and the panel is shown
local texts = {} -- [link] = the tooltip's lines in lower case, this session
local batchQueued = false

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

local Draw

local redraw = UI.Debounce(LOAD_DELAY, function()
	if panel and panel:IsShown() and lastText then
		Draw(lastText)
	end
end)

-- Watches for item data only while some is still on its way.
local function WatchLoading(on)
	if on and not loader then
		loader = CreateFrame("Frame")
		loader:SetScript("OnEvent", redraw)
	end
	if loader then
		if on then
			loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		else
			loader:UnregisterAllEvents()
		end
	end
end

-- The tooltip's lines in lower case (Search.lua's item.text), or nil while the item hasn't loaded. Secret lines are
-- skipped.
local function ReadText(link)
	local data = C_TooltipInfo.GetHyperlink(link)
	local lines = data and data.lines
	if not (lines and #lines > 0) then
		return nil
	end
	local parts = {}
	for _, line in ipairs(lines) do
		for _, part in ipairs({ line.leftText, line.rightText }) do
			if part and part ~= "" and not ns.IsSecret(part) then
				parts[#parts + 1] = part:lower()
			end
		end
	end
	return table.concat(parts, "\n")
end

-- The next batch of tooltips, a frame from now.
local function QueueBatch()
	if batchQueued then
		return
	end
	batchQueued = true
	C_Timer.After(0, function()
		batchQueued = false
		if panel and panel:IsShown() and lastText then
			Draw(lastText)
		end
	end)
end

function Draw(text)
	lastText = text
	local matcher, _, usesText = ns.BagsSearch_Compile(text)
	local found, loading, budget = {}, 0, TEXT_BATCH
	local links = usesText and ns.Counts_ItemLinks and ns.Counts_ItemLinks() or {}
	local waiting = false -- tooltips left for the next frame
	if matcher then
		for _, id in ipairs(ns.Counts_ItemIDs and ns.Counts_ItemIDs() or {}) do
			local record = Record(id)
			if record and not record.name then
				loading = loading + 1
				C_Item.RequestLoadItemDataByID(id)
			elseif record then
				if usesText then
					local link = links[id] or ("item:" .. id)
					if texts[link] == nil and budget > 0 then
						budget = budget - 1
						texts[link] = ReadText(link) or false
					end
					if texts[link] == nil then
						waiting = true
					elseif texts[link] == false then
						texts[link] = nil -- not loaded: asked for, read again next time
						loading = loading + 1
						C_Item.RequestLoadItemDataByID(id)
					else
						record.text = texts[link]
					end
				end
				if matcher(record) then
					found[#found + 1] = record
				end
			end
		end
	end
	if waiting then
		QueueBatch()
	end
	loading = loading + (waiting and 1 or 0)
	WatchLoading(loading > 0)
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
	elseif loading > 0 then
		note:SetText(("%d items match \"%s\" so far (still reading)..."):format(#found, text))
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
	panel:SetScript("OnHide", function()
		WatchLoading(false)
	end)
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
