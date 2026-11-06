local addonName, ns = ...

-- Where to get it: the page in the Tomte window. Type a name, pick an item, and it lists where to buy it, gather it and farm it, the
-- best for your level first. Clicking a place puts a pin on the map. Rules in Data.lua; registered in Sources.lua.

local PAD = 8
local TOP_H = 34 -- the search row
local SEARCH_W = 260
local FOOT = "From Classic's data, so Forever may differ. Crafted items and quest rewards aren't covered yet."

local UI = ns.UI
local Kit = ns.HomeKit

local page, c, search
local selected -- the item shown, nil: the search results
local rows, heads = {}, {}
local used, usedHeads = 0, 0

local function Heading(y, width, title, meta)
	usedHeads = usedHeads + 1
	heads[usedHeads] = heads[usedHeads] or Kit.Heading(c)
	local h = heads[usedHeads]
	h:Show()
	h:Set(title, meta)
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
	h:SetWidth(width)
	return y + h:GetHeight() + 2
end

local function Row(y, width)
	used = used + 1
	local row = Kit.PoolRow(rows, used, c)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
	row:SetWidth(width)
	return row
end

local function ItemTooltip(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(row.itemID)
	GameTooltip:Show()
end

local Layout

local function PickItem(row)
	selected = row.itemID
	Layout()
end

local function PinTooltip(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(row.source.name)
	UI.TipLine(row.source.spawns > 1 and ("%d spawns around here"):format(row.source.spawns) or "One spawn", "textMuted")
	UI.TipLine("Click to put a pin on the map.", "textMuted")
	GameTooltip:Show()
end

local function PinClick(row)
	ns.Sources_Pin(row.source)
end

local function Places(list, title, meta, y, width, right)
	if #list == 0 then
		return y
	end
	y = Heading(y, width, title, meta)
	for _, source in ipairs(list) do
		local row = Row(y, width)
		row.source = source
		row.onClick, row.onEnter = PinClick, PinTooltip
		row:Set(nil, source.name, "text", right(source), nil, ns.Sources_SubText(source))
		y = y + Kit.ROW2_H
	end
	return y + PAD
end

local function DrawItem(width)
	local y = PAD
	local name = ns.Sources_Name(ns.SOURCES_ITEMS, selected)
	local header = Row(y, width)
	header.itemID = selected
	header.onClick, header.onEnter = function()
		selected = nil
		Layout()
	end, ItemTooltip
	header:Set(C_Item.GetItemIconByID(selected), name, "heading", "Back to the search", "accent", "")
	y = y + Kit.ROW2_H + PAD
	local sorted = ns.Sources_ForMe(selected)
	y = Places(sorted.buy, "Buy it", nil, y, width, function()
		return nil
	end)
	y = Places(sorted.gather, "Gather or find it", nil, y, width, function(source)
		return ns.Sources_ChanceText(source.chance)
	end)
	y = Places(sorted.drops, "Drops from", "Best for your level first", y, width, function(source)
		return ns.Sources_ChanceText(source.chance)
	end)
	if #sorted.buy + #sorted.gather + #sorted.drops == 0 then
		y = Heading(y, width, "Nothing for your side", "Vendors of the other faction, or mobs of your own")
	end
	return y
end

local function DrawResults(width)
	local y = PAD
	local found = ns.Sources_Search(ns.SOURCES_ITEMS, search:GetText())
	for _, item in ipairs(found) do
		local row = Row(y, width)
		row.itemID = item.itemID
		row.onClick, row.onEnter = PickItem, ItemTooltip
		row:Set(C_Item.GetItemIconByID(item.itemID), item.name, "text")
		y = y + Kit.ROW_H
	end
	return y, #found
end

Layout = function()
	if not page then
		return
	end
	used, usedHeads = 0, 0
	local width = c:GetWidth() - 2 * PAD
	local y, count
	if selected then
		y = DrawItem(width)
	else
		y, count = DrawResults(width)
	end
	Kit.HideFrom(rows, used + 1)
	for i = usedHeads + 1, #heads do
		heads[i]:Hide()
	end
	local typed = search:GetText():gsub("%s", "") ~= ""
	page.empty:SetShown(not selected and count == 0)
	page.empty:SetText(typed and "No item by that name that Tomte knows where to get." or "Type an item's name, for example Linen Cloth.")
	page.foot:SetShown(selected ~= nil)
	page.list:SetContentHeight(y + PAD)
end

local function Create(frame)
	page = frame
	search = ns.BagsKit_Search(page, "Item name, for example Linen Cloth", function()
		selected = nil
		Layout()
	end)
	search.help:Hide()
	search:SetPoint("TOPLEFT", PAD, -PAD)
	search:SetWidth(SEARCH_W)

	page.foot = UI.Text(page, 11, "textFaint")
	page.foot:SetPoint("LEFT", search, "RIGHT", 12, 0)
	page.foot:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
	page.foot:SetJustifyH("LEFT")
	page.foot:SetWordWrap(true)
	page.foot:SetText(FOOT)

	page.list = UI.Scroll(page)
	page.list:SetPoint("TOPLEFT", 0, -(PAD + TOP_H))
	page.list:SetPoint("BOTTOMRIGHT", -12, 0)
	c = page.list.content
	page.list.onWidthChanged = Layout

	page.empty = UI.Text(page, 13, "textMuted")
	page.empty:SetPoint("TOPLEFT", page.list, "TOPLEFT", PAD, -PAD)
	page.empty:SetPoint("RIGHT", page.list, "RIGHT", -PAD, 0)
	page.empty:SetJustifyH("LEFT")
	page.empty:SetWordWrap(true)
end

-- Shows an item, or a search for text. Before the page was first opened, this waits: Create hasn't run.
local pendingItem, pendingText

local function ApplyPending()
	if not page then
		return
	end
	if pendingText then
		search:SetText(pendingText)
		search:SetCursorPosition(0)
	end
	if pendingItem then
		selected = pendingItem
	elseif pendingText then
		selected = nil
	end
	pendingItem, pendingText = nil, nil
	Layout()
end

function ns.SourcesPage_ShowItem(itemID)
	pendingItem, pendingText = itemID, ns.Sources_Name(ns.SOURCES_ITEMS, itemID)
	ApplyPending()
end

function ns.SourcesPage_ShowSearch(text)
	pendingItem, pendingText = nil, text
	ApplyPending()
end

ns.SourcesPage = {
	title = "Where to get it",
	Create = Create,
	Refresh = function()
		ApplyPending()
		Layout()
	end,
}
