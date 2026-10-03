local addonName, ns = ...

-- Character showcase on the left during cinematic flights: name and item level, the player model
-- (current transmog) in a frozen 3/4 pose standing on a soft ground shadow, and a gear strip framed by
-- thin gold lines underneath. A full-height gradient darkens the left side of the screen behind it.
-- The model doesn't spin: turning a model rotates it around its center, which makes the feet slide.

local GEAR_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 } -- shirt/tabard left out
local PER_ROW = 8
local CENTER_X = 250 -- showcase center, from the left screen edge
local MODEL_W, MODEL_H = 300, 420
local MODEL_FACING = 0.45 -- radians: a 3/4 view, turned towards the middle of the screen
local ICON = 30
local GAP = 5
local GEAR_TOP = -40 -- gold line relative to the model frame bottom (negative = above it, just under the shadow)
local SHADOW_Y = 74 -- ground shadow center above the model frame's bottom (where the feet stand)
local GRADIENT_WIDTH = 620
local GOLD = { 1, 0.82, 0.45 }
local STAND_ANIM = 0

local panel
local icons = {}

local function Freeze(model)
	model:FreezeAnimation(STAND_ANIM, 0, 0)
end

local function GoldLine(width)
	local half = width / 2
	local left = panel:CreateTexture(nil, "OVERLAY")
	left:SetColorTexture(1, 1, 1, 1)
	left:SetSize(half, 1)
	left:SetGradient("HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.7))
	local right = panel:CreateTexture(nil, "OVERLAY")
	right:SetColorTexture(1, 1, 1, 1)
	right:SetSize(half, 1)
	right:SetGradient("HORIZONTAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.7), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0))
	right:SetPoint("LEFT", left, "RIGHT")
	left.right = right
	return left
end

local function ShowLine(line, shown)
	line:SetShown(shown)
	line.right:SetShown(shown)
end

-- Soft ellipse from stacked translucent circles (no soft radial texture to rely on).
local function SoftEllipse(width, height, alpha)
	local layers = {}
	for i = 1, 5 do
		local f = 1 - (i - 1) * 0.17
		local tex = panel:CreateTexture(nil, "BACKGROUND", nil, i - 1)
		tex:SetColorTexture(0, 0, 0, alpha)
		tex:SetSize(width * f, height * f)
		local mask = panel:CreateMaskTexture()
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(tex)
		tex:AddMaskTexture(mask)
		layers[i] = tex
	end
	return layers
end

local function CreateIcon()
	local f = CreateFrame("Frame", nil, panel)
	f:SetSize(ICON + 2, ICON + 2)
	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetAllPoints()
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", 1, -1)
	f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.level = f:CreateFontString(nil, "OVERLAY")
	f.level:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	f.level:SetPoint("BOTTOMRIGHT", -1, 2)
	icons[#icons + 1] = f
	return f
end

-- Fill the strip with equipped items only (no empty placeholders), centered row by row.
local function LayoutGear()
	local equipped = {}
	for _, slot in ipairs(GEAR_SLOTS) do
		local location = ItemLocation:CreateFromEquipmentSlot(slot)
		if C_Item.DoesItemExist(location) then
			equipped[#equipped + 1] = location
		end
	end
	local step = ICON + 2 + GAP
	for i, f in ipairs(icons) do
		f:Hide()
	end
	for i, location in ipairs(equipped) do
		local f = icons[i] or CreateIcon()
		local row = math.floor((i - 1) / PER_ROW)
		local inRow = math.min(PER_ROW, #equipped - row * PER_ROW)
		local col = (i - 1) % PER_ROW
		f:ClearAllPoints()
		f:SetPoint("TOP", panel.model, "BOTTOM", (col - (inRow - 1) / 2) * step, -GEAR_TOP - 10 - row * step)

		f.icon:SetTexture(C_Item.GetItemIcon(location))
		local quality = C_Item.GetItemQuality(location)
		local r, g, b = 0.6, 0.6, 0.6
		if quality then
			r, g, b = C_Item.GetItemQualityColor(quality)
		end
		f.border:SetColorTexture(r, g, b, 1)
		local level = C_Item.GetCurrentItemLevel(location)
		f.level:SetText((level and level > 1) and level or "")
		f:Show()
	end
	local rows = math.ceil(#equipped / PER_ROW)
	ShowLine(panel.gearTop, rows > 0)
	ShowLine(panel.gearBottom, rows > 0)
	-- Same 10 unit gap above the first row and below the last one.
	panel.gearBottom:ClearAllPoints()
	panel.gearBottom:SetPoint("TOPLEFT", panel.model, "BOTTOM", -panel.stripWidth / 2, -GEAR_TOP - 20 - rows * step + GAP)
end

function ns.Showcase_Create(letterbox)
	panel = CreateFrame("Frame", nil, letterbox)
	panel:SetAllPoints(letterbox)
	panel:SetAlpha(0)
	panel:Hide()

	-- Full-height gradient, so it has no visible top or bottom edge.
	local shade = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
	shade:SetColorTexture(1, 1, 1, 1)
	shade:SetPoint("TOPLEFT", letterbox, "TOPLEFT")
	shade:SetPoint("BOTTOMLEFT", letterbox, "BOTTOMLEFT")
	shade:SetWidth(GRADIENT_WIDTH)
	shade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.75), CreateColor(0, 0, 0, 0))

	panel.model = CreateFrame("PlayerModel", nil, panel)
	panel.model:SetSize(MODEL_W, MODEL_H)
	panel.model:SetPoint("CENTER", letterbox, "LEFT", CENTER_X, 40)
	panel.model:SetScript("OnModelLoaded", Freeze)

	-- Ground shadow under the feet.
	for _, layer in ipairs(SoftEllipse(220, 44, 0.16)) do
		layer:SetPoint("CENTER", panel.model, "BOTTOM", 0, SHADOW_Y)
	end

	panel.name = panel:CreateFontString(nil, "OVERLAY")
	panel.name:SetFont("Fonts\\MORPHEUS.TTF", 24, "")
	panel.name:SetShadowOffset(1, -1)
	panel.name:SetPoint("BOTTOM", panel.model, "TOP", 0, 14)
	panel.ilvl = panel:CreateFontString(nil, "OVERLAY")
	panel.ilvl:SetFont(STANDARD_TEXT_FONT, 13, "")
	panel.ilvl:SetTextColor(0.75, 0.75, 0.75)
	panel.ilvl:SetShadowOffset(1, -1)
	panel.ilvl:SetPoint("TOP", panel.name, "BOTTOM", 0, -4)

	-- Gear strip under the feet, between two thin gold lines.
	local stripWidth = PER_ROW * (ICON + 2 + GAP) + 40
	panel.stripWidth = stripWidth
	panel.gearTop = GoldLine(stripWidth)
	panel.gearTop:SetPoint("TOPLEFT", panel.model, "BOTTOM", -stripWidth / 2, -GEAR_TOP)
	panel.gearBottom = GoldLine(stripWidth)
end

-- Called when a cinematic starts. enabled = the showcase setting.
function ns.Showcase_Show(enabled)
	if not enabled then
		panel:Hide()
		return
	end
	panel:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())

	local _, classFile = UnitClass("player")
	local color = C_ClassColor.GetClassColor(classFile)
	if color then
		panel.name:SetTextColor(color:GetRGB())
	else
		panel.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end
	panel.name:SetText(UnitPVPName("player") or UnitName("player"))
	local _, equipped = GetAverageItemLevel()
	panel.ilvl:SetText(("-  item level %d  -"):format(math.floor(equipped or 0)))
	LayoutGear()

	panel:Show()
	-- Set the unit after showing: some model frames stay blank if the unit is set while hidden.
	local model = panel.model
	model:SetUnit("player")
	model:SetRotation(MODEL_FACING)
	Freeze(model)
	-- OnModelLoaded may not fire for a model that's already loaded; freeze again once it has settled.
	C_Timer.After(0.3, function()
		Freeze(model)
	end)
end

-- Called every frame while the letterbox is visible.
function ns.Showcase_Update(alpha)
	if panel:IsShown() then
		panel:SetAlpha(alpha)
	end
end
