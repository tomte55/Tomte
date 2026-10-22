local addonName, ns = ...

-- Blackjack: the classic table surface in the table window. A half-moon felt (tinted by the chosen felt), the padded
-- rail along its curve, the rules printed on arcs, the shoe and discard tray, betting circles with chip stacks, and the
-- chip buttons. All art is Media/Games/*.tga from tools/games_art.py, white or grey, tinted here by theme role; the
-- felt geometry below repeats that tool's numbers. Felts are chosen in CashierData.lua; used by Table.lua.

local MEDIA = "Interface\\AddOns\\Tomte\\Media\\Games\\"
local FELT_X, FELT_Y = 10, 44 -- the felt's top left in the window (below the title bar)
local FELT_W, FELT_H = 540, 384 -- as FELT_W, FELT_H in tools/games_art.py
local FELT_V = 384 / 540 -- the felt's share of its square 512 texture's height
local PRINT_TOP, PRINT_H = 80, 135 -- felt rows the print textures cover (PRINT_TOP, PRINT_H in the tool)
local FELT_DIM = 0.5 -- a felt's role color times this: felt is dark, and the grey art is near white
local RING_SIZE = 46
local CHIP_SIZE = 26
local CHIP_RISE = 3 -- pixels each chip in a stack sits above the one under it
local MAX_STACK = 6
local CHIP_BUTTON = 38
local SHOE_SIZE, TRAY_SIZE = 64, 60

-- Chip colors by value, as in a casino: blue, red, green, black.
local CHIP_ROLES = { [10] = "info", [50] = "danger", [100] = "success", [500] = "frameDark" }

local UI = ns.UI

ns.BLACKJACK_FELT_DIM = FELT_DIM
-- The shoe's middle, from the window's top left: dealt cards come from here.
ns.BLACKJACK_SHOE_X, ns.BLACKJACK_SHOE_Y = FELT_X + FELT_W - 8 - SHOE_SIZE / 2, -(FELT_Y + 6 + SHOE_SIZE / 2)

local function Tex(parent, file, layer, sublevel)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
	t:SetTexture(MEDIA .. file)
	return t
end

local function Tint(t, role, alpha, dim)
	local r, g, b = UI.Color(role)
	dim = dim or 1
	t:SetVertexColor(r * dim, g * dim, b * dim, alpha or 1)
end

-- One chip: the body in its value's color, the edge inserts over it.
local function NewChip(parent, size)
	local chip = { body = Tex(parent, "Chip", "ARTWORK", 1), marks = Tex(parent, "ChipMarks", "ARTWORK", 2) }
	chip.body:SetSize(size, size)
	chip.marks:SetAllPoints(chip.body)
	Tint(chip.marks, "text", 0.9)
	return chip
end

local function SetChipValue(chip, value)
	Tint(chip.body, CHIP_ROLES[value] or "accent")
end

local function ShowChip(chip, shown)
	chip.body:SetShown(shown)
	chip.marks:SetShown(shown)
end

-- A betting circle with a stack of chips in it.
local function NewSpot(parent)
	local spot = { chips = {} }
	spot.ring = Tex(parent, "Ring", "ARTWORK", 0)
	spot.ring:SetSize(RING_SIZE, RING_SIZE)
	Tint(spot.ring, "accent", 0.55)
	for i = 1, MAX_STACK do
		spot.chips[i] = NewChip(parent, CHIP_SIZE)
	end
	return spot
end

-- Builds the felt on a frame of its own just above the window's background (the window's panel art would cover
-- textures of the window itself). Returns that frame: Table.lua puts its text on it, and its cards above it.
function ns.BlackjackFelt_Create(window)
	local f = CreateFrame("Frame", nil, window)
	f:SetAllPoints()
	f:SetFrameLevel(window:GetFrameLevel() + 1)

	f.felt = Tex(f, "Felt", "BACKGROUND")
	f.felt:SetPoint("TOPLEFT", FELT_X, -FELT_Y)
	f.felt:SetSize(FELT_W, FELT_H)
	f.felt:SetTexCoord(0, 1, 0, FELT_V)

	f.rail = Tex(f, "Rail", "BORDER")
	f.rail:SetAllPoints(f.felt)
	f.rail:SetTexCoord(0, 1, 0, FELT_V)
	Tint(f.rail, "frame")

	f.printMain = Tex(f, "PrintMain", "BORDER", 1)
	f.printMain:SetPoint("TOPLEFT", FELT_X, -(FELT_Y + PRINT_TOP))
	f.printMain:SetSize(FELT_W, PRINT_H)
	f.printRule = Tex(f, "PrintRule", "BORDER", 1)
	f.printRule:SetAllPoints(f.printMain)
	Tint(f.printRule, "text", 0.45)

	f.shoe = Tex(f, "Shoe", "BORDER", 2)
	f.shoe:SetSize(SHOE_SIZE, SHOE_SIZE)
	f.shoe:SetPoint("CENTER", f, "TOPLEFT", ns.BLACKJACK_SHOE_X, ns.BLACKJACK_SHOE_Y)
	Tint(f.shoe, "frame")
	f.tray = Tex(f, "Tray", "BORDER", 2)
	f.tray:SetSize(TRAY_SIZE, TRAY_SIZE)
	f.tray:SetPoint("TOPLEFT", FELT_X + 8, -(FELT_Y + 8))
	Tint(f.tray, "frame")

	f.spots = { NewSpot(f), NewSpot(f) }
	return f
end

-- item: a felt from ns.CASHIER_FELTS.
function ns.BlackjackFelt_SetFelt(f, item)
	Tint(f.felt, item.role, 1, item.dim or FELT_DIM)
	Tint(f.printMain, "accent", 0.85)
end

-- Betting circle i (1 or 2) centered on (x, y) from the window's top, holding `amount` in chips; amount nil or 0
-- hides the chips, shown false hides the circle too.
function ns.BlackjackFelt_Spot(f, i, shown, x, y, amount)
	local spot = f.spots[i]
	spot.ring:SetShown(shown)
	spot.ring:ClearAllPoints()
	spot.ring:SetPoint("CENTER", f, "TOP", x, y)
	local stack = shown and amount and ns.Chips_Stack(amount, ns.BLACKJACK_CHIPS, MAX_STACK) or {}
	for n, chip in ipairs(spot.chips) do
		local value = stack[n]
		if value then
			SetChipValue(chip, value)
			chip.body:ClearAllPoints()
			chip.body:SetPoint("CENTER", spot.ring, "CENTER", 0, (n - 1) * CHIP_RISE - (#stack - 1) * CHIP_RISE / 2)
		end
		ShowChip(chip, value ~= nil)
	end
	return spot.ring
end

-- A round chip button showing its value: the bet controls under the felt.
function ns.BlackjackFelt_ChipButton(parent, value, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(CHIP_BUTTON, CHIP_BUTTON)
	local chip = NewChip(b, CHIP_BUTTON)
	chip.body:SetPoint("CENTER")
	SetChipValue(chip, value)
	b.chip = chip
	b.label = UI.Text(b, 11, "text", "number")
	b.label:SetPoint("CENTER", 0, 0)
	b.label:SetText(ns.Thousands(value))
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetTexture(ns.Theme.media.glow)
	b.glow:SetPoint("CENTER")
	b.glow:SetSize(CHIP_BUTTON * 1.9, CHIP_BUTTON * 1.9)
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(UI.Color("accent"))
	b.glow:SetAlpha(0)
	b:SetScript("OnEnter", function(self)
		self.glow:SetAlpha(0.5)
	end)
	b:SetScript("OnLeave", function(self)
		self.glow:SetAlpha(0)
	end)
	b:SetScript("OnMouseDown", function(self)
		self.chip.body:SetPoint("CENTER", 1, -1)
	end)
	b:SetScript("OnMouseUp", function(self)
		self.chip.body:SetPoint("CENTER")
	end)
	b:SetScript("OnClick", onClick)
	return b
end
