local addonName, ns = ...

-- Bags: the marks editor, a window for where each mark sits on an item and which wins a shared corner. On the right one
-- row per mark, in the order they win: its corner picked on a small square of four corners (the lit one again turns
-- it off), Up and Down to move it. On the left, sample items painted by Buttons.lua's own code (so they look exactly
-- like the bags) and a big slot listing what each corner holds. Saves db.corners and db.markOrder (Bags.lua's
-- defaults); the order rules are Data.lua's (Bags_MarkOrder, Bags_MoveMark, Bags_CornerStacks).

local WIDTH, HEIGHT = 680, 470
local PAD = 18
local TITLE_TOP = 16
local LEFT_W = 250 -- the preview column
local SAMPLE = 54 -- a sample item's size, pixels
local SAMPLE_GAP = 8
-- What each corner holds: a line per corner (more when its marks wrap), its name in a CORNER_NAME_W column.
local CORNER_NAME_W = 78
local CORNER_GAP = 8
local SLOT_PAD = 8
local ROW_H = 36
local PICK = 13 -- one corner square of a row's picker
local PICK_GAP = 3
local NAME_W = 150

local UI = ns.UI

-- The marks, in player wording. available(): whether this character can get the mark at all (else the row is dimmed
-- and says why).
local INFO = {
	upgrade = { name = "Upgrade arrow", tip = "Gear Check's arrows: green for an upgrade, yellow for maybe, in Tomte's color for another character.",
		available = function()
			return ns.Gear_BagArrow ~= nil
		end, missing = "Needs Gear Check" },
	marker = { name = "Item marker", tip = "What to do with it, from Gold & value: a coin to vendor it, a gavel to auction it, a purple gem to disenchant it, a green tick to keep it, a yellow ! to keep it for a quest, a red X when it's safe to delete. Grey items get the coin even with Gold & value off." },
	crafting = { name = "Crafting list", tip = "A small list icon (three lines) on items your crafting list (Alts) wants moved; the item's tooltip says how many.",
		available = function()
			return ns.AltsList_Marked ~= nil
		end, missing = "Needs Alts" },
	transmog = { name = "Transmog mark", tip = "A coat hanger on items whose appearance you haven't collected: in the accent color when this character can learn it, grey when this character can't use it." },
	set = { name = "Equipment set", tip = "A small blue square on items in one of your equipment sets." },
	petlevel = { name = "Battle pet level", tip = "The level of a caged battle pet.", available = ns.NotForever,
		missing = "Not on this client" },
	ilvl = { name = "Item level", tip = "The item level on weapons and armor. Its color is set in the Bags settings." },
}

local CORNER_NAMES = { TOPLEFT = "Top left", TOPRIGHT = "Top right", BOTTOMLEFT = "Bottom left",
	BOTTOMRIGHT = "Bottom right" }

-- Sample items for the preview (icons used elsewhere in Tomte, so known to exist). Between them they carry every mark.
local function Samples()
	local level = ns.FOREVER and 52 or 646
	return {
		{ icon = 135030, quality = 4, ilvl = level, upgrade = "upgrade", marker = { kind = "keep" }, look = "you",
			classID = 2 },
		{ icon = 132624, quality = 3, ilvl = level - 13, marker = { kind = "disenchant" }, set = { "Tank" },
			look = "other", classID = 4 },
		{ icon = 133071, quality = 1, count = 20, marker = { kind = "auction" }, crafting = 3 },
		{ icon = 237429, quality = 0, ilvl = 12, marker = { kind = "vendor" }, junk = true, classID = 4 },
	}
end

local db
local dialog

local function Order()
	return ns.Bags_MarkOrder(db.markOrder)
end

local function Available(mark)
	local info = INFO[mark]
	return not info.available or info.available()
end

local Refresh -- forward declaration

local function Changed()
	ns.BagsWindow_Relayout()
	Refresh()
end

local function SetCorner(mark, corner)
	db.corners[mark] = db.corners[mark] == corner and "off" or corner
	Changed()
end

local function Move(mark, delta)
	db.markOrder = ns.Bags_MoveMark(Order(), mark, delta)
	Changed()
end

-- Rows ---------------------------------------------------------------------------------------------------------------

local function Picker(row)
	local picker = CreateFrame("Frame", nil, row)
	picker:SetSize(PICK * 2 + PICK_GAP, PICK * 2 + PICK_GAP)
	picker.squares = {}
	for i, corner in ipairs(ns.BAGS_CORNERS) do
		local b = CreateFrame("Button", nil, picker)
		b:SetSize(PICK, PICK)
		local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
		b:SetPoint("TOPLEFT", col * (PICK + PICK_GAP), -line * (PICK + PICK_GAP))
		b.fill = b:CreateTexture(nil, "ARTWORK")
		b.fill:SetAllPoints()
		UI.Border(b, "frame", 0.6)
		b:SetScript("OnClick", function()
			SetCorner(row.mark, corner)
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(CORNER_NAMES[corner])
			if db.corners[row.mark] == corner then
				UI.TipLine("Click again to turn it off.", "textMuted")
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		picker.squares[corner] = b
	end
	return picker
end

local function Row(i)
	local row = dialog.rows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, dialog)
	row:SetSize(WIDTH - LEFT_W - PAD * 3, ROW_H)
	row.name = UI.Text(row, 13, "text", "label")
	row.name:SetPoint("LEFT", 0, 4)
	row.name:SetWidth(NAME_W)
	row.name:SetJustifyH("LEFT")
	row.where = UI.Text(row, 10, "textMuted")
	row.where:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.where:SetWidth(NAME_W)
	row.where:SetJustifyH("LEFT")
	row.hover = CreateFrame("Frame", nil, row)
	row.hover:SetPoint("TOPLEFT")
	row.hover:SetSize(NAME_W, ROW_H)
	row.hover:SetScript("OnEnter", function(self)
		local info = INFO[row.mark]
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(info.name)
		UI.TipLine(info.tip, "text", true)
		GameTooltip:Show()
	end)
	row.hover:SetScript("OnLeave", GameTooltip_Hide)
	row.picker = Picker(row)
	row.picker:SetPoint("LEFT", NAME_W + 8, 0)
	row.up = UI.Button(row, 40, "Up")
	row.up:SetPoint("LEFT", row.picker, "RIGHT", 14, 0)
	row.up:SetScript("OnClick", function()
		Move(row.mark, -1)
	end)
	row.down = UI.Button(row, 48, "Down")
	row.down:SetPoint("LEFT", row.up, "RIGHT", 4, 0)
	row.down:SetScript("OnClick", function()
		Move(row.mark, 1)
	end)
	row.rule = UI.Hairline(row, 1, 0.4) -- its width comes from the two points
	row.rule:SetPoint("BOTTOMLEFT")
	row.rule:SetPoint("BOTTOMRIGHT")
	dialog.rows[i] = row
	return row
end

local function FillRow(row, mark, i, count)
	row.mark = mark
	local info = INFO[mark]
	local corner = db.corners[mark] or "off"
	local available = Available(mark)
	row.name:SetText(("%d. %s"):format(i, info.name))
	if not available then
		row.where:SetText(info.missing)
	else
		row.where:SetText(CORNER_NAMES[corner] or "Off")
	end
	row:SetAlpha(available and 1 or 0.5)
	for c, b in pairs(row.picker.squares) do
		local lit = c == corner
		b.fill:SetColorTexture(UI.Color(lit and "accent" or "surface"))
		UI.SetBorderColor(b, lit and "accent" or "frame", lit and 1 or 0.6)
	end
	row.up:SetEnabled(i > 1)
	row.down:SetEnabled(i < count)
end

-- Preview -----------------------------------------------------------------------------------------------------------

local function PaintSamples()
	local opts = ns.BagsWindow_PaintOptions()
	opts.markOrder = Order()
	for i, item in ipairs(Samples()) do
		local button = ns.BagsButtons_GetView(dialog.samples, i)
		ns.BagsButtons_Place(button, dialog.samples, (i - 1) * (SAMPLE + SAMPLE_GAP), 0, SAMPLE)
		ns.BagsButtons_Paint(button, item, opts)
	end
end

-- What each corner holds: its marks in order, the first (the one that shows) bright, the ones behind it faint. Bottom
-- right also has the game's stack count.
local function PaintSlot()
	local stacks = ns.Bags_CornerStacks(db.corners, Order())
	local slot, y = dialog.slot, SLOT_PAD
	for _, corner in ipairs(ns.BAGS_CORNERS) do
		local text = slot.corners[corner]
		local parts = {}
		for i, mark in ipairs(stacks[corner]) do
			parts[#parts + 1] = UI.Wrap(INFO[mark].name, i == 1 and "text" or "textFaint")
		end
		if corner == "BOTTOMRIGHT" then
			parts[#parts + 1] = UI.Wrap("stack count", "textFaint")
		end
		text:SetText(#parts > 0 and table.concat(parts, UI.Wrap(", ", "textFaint")) or UI.Wrap("nothing", "textFaint"))
		slot.names[corner]:SetPoint("TOPLEFT", SLOT_PAD, -y)
		text:SetPoint("TOPLEFT", SLOT_PAD + CORNER_NAME_W, -y)
		y = y + math.max(text:GetStringHeight(), slot.names[corner]:GetStringHeight()) + CORNER_GAP
	end
	slot:SetHeight(y - CORNER_GAP + SLOT_PAD)
end

function Refresh()
	if not (dialog and dialog:IsShown()) then
		return
	end
	local order = Order()
	local y = dialog.listTop
	for i, mark in ipairs(order) do
		local row = Row(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", LEFT_W + PAD * 2, -y)
		FillRow(row, mark, i, #order)
		row:Show()
		y = y + ROW_H
	end
	for i = #order + 1, #dialog.rows do
		dialog.rows[i]:Hide()
	end
	PaintSamples()
	PaintSlot()
end

-- Window -------------------------------------------------------------------------------------------------------------

local function Heading(text, x, y)
	local fs = UI.Text(dialog, 12, "heading", "label")
	fs:SetPoint("TOPLEFT", x, -y)
	fs:SetText(text)
	return fs
end

local function Build()
	dialog = UI.Dialog("TomteBagsMarks", WIDTH, HEIGHT) -- Escape closes it
	dialog.title = UI.Text(dialog, 16, "heading", "title")
	dialog.title:SetPoint("TOPLEFT", PAD, -TITLE_TOP)
	dialog.title:SetText("Marks on items")
	local top = TITLE_TOP + 34
	Heading("Preview", PAD, top)
	dialog.samples = CreateFrame("Frame", nil, dialog)
	dialog.samples:SetPoint("TOPLEFT", PAD, -(top + 20))
	dialog.samples:SetSize(LEFT_W, SAMPLE)
	Heading("What each corner holds", PAD, top + 20 + SAMPLE + 18)
	-- One line per corner across the whole column: the corner's name, then its marks in order.
	local slot = CreateFrame("Frame", nil, dialog)
	slot:SetPoint("TOPLEFT", PAD, -(top + 20 + SAMPLE + 38))
	slot:SetWidth(LEFT_W)
	UI.Surface(slot, 0.6)
	slot.corners, slot.names = {}, {}
	for _, corner in ipairs(ns.BAGS_CORNERS) do
		local name = UI.Text(slot, 11, "textMuted", "label")
		name:SetText(CORNER_NAMES[corner])
		local text = UI.Text(slot, 11, "text")
		text:SetWidth(LEFT_W - SLOT_PAD * 2 - CORNER_NAME_W)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(true)
		slot.corners[corner], slot.names[corner] = text, name
	end
	dialog.slot = slot
	Heading("Mark", LEFT_W + PAD * 2, top)
	Heading("Corner", LEFT_W + PAD * 2 + NAME_W + 8, top)
	Heading("Order", LEFT_W + PAD * 2 + NAME_W + 8 + PICK * 2 + PICK_GAP + 14, top)
	dialog.listTop = top + 22
	dialog.rows = {}
	local hint = UI.Text(dialog, 11, "textMuted")
	hint:SetPoint("BOTTOMLEFT", PAD, 46)
	hint:SetPoint("RIGHT", -PAD, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Click a corner to put a mark there; click it again to turn the mark off. When marks share a corner, "
		.. "the one higher in the list shows. The game's stack count always sits bottom right.")
	dialog.close = UI.Button(dialog, 80, "Close")
	dialog.close:SetPoint("BOTTOMRIGHT", -PAD, 14)
	dialog.close:SetScript("OnClick", function()
		dialog:Hide()
	end)
	dialog.reset = UI.Button(dialog, 120, "Back to defaults")
	dialog.reset:SetPoint("RIGHT", dialog.close, "LEFT", -8, 0)
	dialog.reset:SetScript("OnClick", function()
		ns.Confirm_Show("Put every mark back in its default corner and order?", function()
			ns.Bags_ResetMarks()
			Changed()
		end)
	end)
	dialog:HookScript("OnShow", Refresh)
end

function ns.BagsMarks_Init(saved)
	db = saved
end

function ns.BagsMarks_Show()
	if not dialog then
		Build()
	end
	UI.PlaceDialog(dialog)
	dialog:Show() -- OnShow fills it
end
