local addonName, ns = ...

-- Dungeon journal: the page's pooled pieces, built again on every layout: text blocks, small headings and list rows
-- (the picked one marked). Shared through ns.DJKit (Read.lua); the page is Page.lua.

local PAD = 8
local TEXT_GAP = 6 -- between text blocks
local PICK_ALPHA = 0.16 -- the picked row's wash

local UI = ns.UI
local Kit = ns.HomeKit
local J = ns.DJKit

J.PAD, J.TEXT_GAP = PAD, TEXT_GAP

local listRows, detailRows, texts = {}, {}, {}
local usedList, usedDetail, usedTexts = 0, 0, 0

function J.BeginParts()
	usedList, usedDetail, usedTexts = 0, 0, 0
end

function J.HideUnusedParts()
	Kit.HideFrom(listRows, usedList + 1)
	Kit.HideFrom(detailRows, usedDetail + 1)
	for i = usedTexts + 1, #texts do
		texts[i]:Hide()
	end
end

-- A text block at y in parent; returns the y under it. font: a font role ("body" by default); x: from the left edge.
function J.Text(parent, y, width, text, role, size, font, x)
	usedTexts = usedTexts + 1
	local fs = texts[usedTexts]
	if not fs then
		fs = UI.Text(parent, 13, "text")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		texts[usedTexts] = fs
	end
	fs:SetParent(parent)
	UI.SetFont(fs, font or "body", size or 13)
	UI.SetTextRole(fs, role or "text")
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or PAD, -y)
	fs:SetWidth(width)
	fs:SetText(text)
	fs:Show()
	return y + fs:GetStringHeight() + TEXT_GAP
end

-- A small heading inside a list: a wing, a group of dungeons, a part of the details. meta: muted text beside it.
function J.Label(parent, y, width, text, meta)
	local top = y + (y > PAD and 6 or 0)
	local after = J.Text(parent, top, width, text, "heading", 14, "title")
	if meta then
		local fs = texts[usedTexts]
		local metaX = PAD + fs:GetUnboundedStringWidth() + 10
		J.Text(parent, top + 2, width - metaX + PAD, meta, "textMuted", 11, "body", metaX)
	end
	return after
end

-- The picked row: a faint accent wash and a bar on its left edge.
function J.Mark(row, on)
	if on and not row.pickWash then
		row.pickWash = row:CreateTexture(nil, "BACKGROUND", nil, -1)
		row.pickWash:SetAllPoints()
		row.pickEdge = row:CreateTexture(nil, "ARTWORK")
		row.pickEdge:SetPoint("TOPLEFT", -PAD, 0)
		row.pickEdge:SetPoint("BOTTOMLEFT", -PAD, 0)
		row.pickEdge:SetWidth(2)
	end
	if row.pickWash then
		if on then
			row.pickWash:SetColorTexture(UI.RGBA("accent", PICK_ALPHA))
			row.pickEdge:SetColorTexture(UI.RGBA("accent"))
		end
		row.pickWash:SetShown(on)
		row.pickEdge:SetShown(on)
	end
end

local function Row(pool, n, parent, y, width)
	local row = Kit.PoolRow(pool, n, parent)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -y)
	row:SetWidth(width)
	J.Mark(row, false)
	if row.levelTrack then
		J.LevelBar(row, nil)
	end
	if row.star then
		row.star:Hide()
	end
	return row
end

-- A row in the left list (or the dungeon list) and a row in the details.
function J.ListRow(y, width)
	usedList = usedList + 1
	return Row(listRows, usedList, J.page.left.content, y, width)
end

function J.DetailRow(y, width)
	usedDetail = usedDetail + 1
	return Row(detailRows, usedDetail, J.page.right.content, y, width)
end

-- A small star left of a row's right-hand text: the boss or dungeon drops an item you want.
function J.RowStar(row)
	if not row.star then
		row.star = row:CreateTexture(nil, "OVERLAY")
		row.star:SetSize(14, 14)
		row.star:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
		J.StarArt(row.star, true)
	end
	row.star:Show()
end
