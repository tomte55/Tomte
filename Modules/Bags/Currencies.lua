local addonName, ns = ...

-- Bags: the currencies panel, opened from the button at the bag window's bottom left. The game's currency list with
-- its headers (folding a header folds it in the game's currency tab too: it's the same list), a search, and on top
-- the currencies shown on the bag ("Tracked"). Shift-click shows or hides a currency on the bag; while typing in chat
-- it links it instead (the chat link modifier is Shift too). Rows from Data.lua's Bags_CurrencyRows; the window is in Window.lua.

local WIDTH = 260
local PAD = 8
local BAND_H = 34 -- the header band, as the bag window's
local ROW_H = 20
local ICON = 14
local INDENT = 12 -- per level of the list's depth
local MAX_LIST = 400 -- a bound for reading the game's currency list
-- Seconds after a search folded the list back in which the game's CURRENCY_DISPLAY_UPDATE doesn't redraw.
local QUIET_SECONDS = 0.5

local UI = ns.UI

local panel, scroll, search
local rows = {}
local anchor -- the bag window the panel sits beside
local quietUntil = 0

-- The game's currency list, each entry with its index.
local function List()
	local list = {}
	for i = 1, math.min(C_CurrencyInfo.GetCurrencyListSize(), MAX_LIST) do
		local info = C_CurrencyInfo.GetCurrencyListInfo(i)
		if info then
			info.index = i
			list[#list + 1] = info
		end
	end
	return list
end

-- The whole currency list for a search: the game only lists what's under unfolded headers, so the folded ones are
-- unfolded for the read and folded again after (a parent can hide folded children: a few passes). The game's
-- currency tab shares the folds, so they're put back exactly.
local function HeaderKey(info)
	return (info.currencyListDepth or 0) .. ":" .. (info.name or "")
end

local function FullList()
	local unfolded = {} -- [depth:name] = true for the headers opened here
	-- Unfolding may send CURRENCY_DISPLAY_UPDATE at once: no redraw (and no second unfold) while this reads.
	quietUntil = GetTime() + QUIET_SECONDS
	for _ = 1, 4 do
		local opened = false
		for i = math.min(C_CurrencyInfo.GetCurrencyListSize(), MAX_LIST), 1, -1 do
			local info = C_CurrencyInfo.GetCurrencyListInfo(i)
			if info and info.isHeader and not info.isHeaderExpanded then
				unfolded[HeaderKey(info)] = true
				C_CurrencyInfo.ExpandCurrencyList(i, true)
				opened = true
			end
		end
		if not opened then
			break
		end
	end
	local list = List()
	if next(unfolded) then
		for i = math.min(C_CurrencyInfo.GetCurrencyListSize(), MAX_LIST), 1, -1 do
			local info = C_CurrencyInfo.GetCurrencyListInfo(i)
			if info and info.isHeader and info.isHeaderExpanded and unfolded[HeaderKey(info)] then
				C_CurrencyInfo.ExpandCurrencyList(i, false)
			end
		end
		-- Folding sends CURRENCY_DISPLAY_UPDATE, which would redraw and unfold again.
		quietUntil = GetTime() + QUIET_SECONDS
	end
	return list
end

-- The currencies shown on the bag, whatever is folded in the list.
local function Tracked()
	local tracked = {}
	for i = 1, MAX_LIST do
		local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
		if not info then
			break
		end
		tracked[#tracked + 1] = { currencyID = info.currencyTypesID, name = info.name, quantity = info.quantity,
			iconFileID = info.iconFileID }
	end
	return tracked
end

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, scroll.content)
	row:SetHeight(ROW_H)
	row:RegisterForClicks("LeftButtonUp")
	UI.HoverWash(row)
	row.name = UI.Text(row, 12, "text")
	row.name:SetWordWrap(false)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("RIGHT", -4, 0)
	row.count = UI.Text(row, 12, "text", "number")
	row.count:SetPoint("RIGHT", row.icon, "LEFT", -4, 0)
	row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row:SetScript("OnEnter", function(self)
		UI.WashTo(self.hoverWash, true)
		local data = self.data
		if data and data.kind == "currency" and data.info.currencyID then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetCurrencyByID(data.info.currencyID)
			UI.TipLine(data.info.isShowInBackpack and "Shift-click: stop showing it on the bag"
				or "Shift-click: show it on the bag", "textMuted")
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		UI.WashTo(self.hoverWash, false)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		local data = self.data
		if not data then
			return
		end
		if data.kind == "header" then
			if data.index then
				C_CurrencyInfo.ExpandCurrencyList(data.index, not data.expanded)
				ns.BagsCurrencies_Refresh()
			end
		elseif data.kind ~= "currency" then
			return
		elseif IsModifiedClick("CHATLINK") and ChatFrameUtil.GetActiveWindow() then
			UI.InsertLink(C_CurrencyInfo.GetCurrencyLink(data.info.currencyID))
		elseif IsShiftKeyDown() and data.info.currencyID then
			C_CurrencyInfo.SetCurrencyBackpackByID(data.info.currencyID, not data.info.isShowInBackpack)
			quietUntil = 0 -- a change from the panel always redraws
			ns.BagsCurrencies_Refresh()
			ns.BagsWindow_RefreshFooter()
		end
	end)
	rows[i] = row
	return row
end

local function Draw()
	if not (panel and panel:IsShown()) then
		return
	end
	local text = search:GetText()
	local searching = text ~= ""
	local list = ns.Bags_CurrencyRows(searching and FullList() or List(), searching and text:lower() or nil, Tracked())
	local y = 0
	local width = scroll:GetWidth()
	for i, data in ipairs(list) do
		local row = Row(i)
		if searching and data.kind == "header" then
			data.index, data.expanded = nil, true -- read unfolded and folded back: its index is stale
		end
		row.data = data
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", 2 + (data.depth or 0) * INDENT, 0)
		if data.kind == "header" then
			UI.SetFont(row.name, "title", 13)
			UI.SetTextRole(row.name, "heading")
			row.name:SetText((data.expanded and "- " or "+ ") .. data.name)
			row.count:SetText("")
			row.icon:Hide()
		elseif data.kind == "hint" then
			row.name:SetPoint("LEFT", 2 + INDENT, 0)
			UI.SetFont(row.name, "body", 11)
			UI.SetTextRole(row.name, "textMuted")
			row.name:SetText("Shift-click a currency to show it on the bag")
			row.count:SetText("")
			row.icon:Hide()
		else
			UI.SetFont(row.name, "body", 12)
			UI.SetTextRole(row.name, "text")
			row.name:SetText(data.name)
			row.count:SetText(ns.Thousands(data.info.quantity or 0))
			row.icon:SetTexture(data.info.iconFileID)
			row.icon:Show()
		end
		row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
		row:Show()
		y = y + ROW_H
	end
	for i = #list + 1, #rows do
		rows[i]:Hide()
		rows[i].data = nil
	end
	scroll:SetContentHeight(y)
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
	title:SetText("Currencies")
	local close = ns.BagsKit_Cluster(band, { { glyph = "Close", tip = "Close", onClick = function()
		panel:Hide()
	end } })
	close:SetPoint("RIGHT", -PAD, 0)
	local tray = ns.BagsKit_Tray(panel)
	tray:SetPoint("TOPLEFT", band, "BOTTOMLEFT", PAD - 1, -PAD)
	tray:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	search = ns.BagsKit_Search(band, "Search currencies", Draw)
	search:SetPoint("LEFT", title, "RIGHT", 10, 0)
	search:SetPoint("RIGHT", close, "LEFT", -8, 0)
	search.help:Hide()
	search:SetTextInsets(8, 8, 0, 0)

	scroll = UI.Scroll(tray)
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -12, 6)
	panel:SetScript("OnShow", Draw)
	panel:SetScript("OnHide", function()
		search:ClearFocus()
	end)
	panel:Hide()
end

-- The button for the bag window's footer (a one-button cluster): opens and closes the panel docked to window's
-- left edge. One side panel at a time: Find on all characters closes.
function ns.BagsCurrencies_Button(parent, window)
	anchor = window
	return ns.BagsKit_Cluster(parent, { { glyph = "Coin", tip = "Currencies", onClick = function()
		if not panel then
			Build()
		end
		panel:ClearAllPoints()
		panel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 1, 0)
		panel:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", 1, 0)
		if panel:IsShown() then
			panel:Hide()
		else
			ns.BagsFind_Hide()
			panel:Show()
		end
	end } })
end

function ns.BagsCurrencies_Hide()
	if panel then
		panel:Hide()
	end
end

-- CURRENCY_DISPLAY_UPDATE and after a change from the panel itself.
function ns.BagsCurrencies_Refresh()
	if GetTime() < quietUntil then
		return
	end
	Draw()
end
