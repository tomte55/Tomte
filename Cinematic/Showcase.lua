local addonName, ns = ...

-- Character showcase on the left during cinematic flights: name and item level, the player model
-- (current transmog) in a frozen 3/4 pose standing on a soft ground shadow, and a gear strip framed by
-- thin gold lines underneath. A full-height gradient darkens the left side of the screen behind it.
-- The model doesn't spin. It's an actor in a ModelScene with our own camera, fitted with the game's own
-- projection (Project3DPointTo2D), which also tells where the feet are: the model frame is moved so the
-- feet stand on the shadow whatever the race or size.

local GEAR_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 } -- shirt/tabard left out
local PER_ROW = 8
local CENTER_X = 250 -- showcase center, from the left screen edge
local MODEL_W, MODEL_H = 300, 420
local MODEL_FACING = 0.45 -- radians: a 3/4 view, turned towards the middle of the screen
local ICON = 30
local GAP = 5
local GEAR_TOP = -40 -- gold line relative to the model frame bottom (negative = above it, just under the shadow)
local SHADOW_Y = 74 -- ground shadow center above the stand's bottom (where the feet stand)
local FIT_H = MODEL_H - SHADOW_Y - 10 -- feet to the top of the head
local FIT_W = MODEL_W * 0.9
local CAMERA_FOV = 0.5
local CAMERA_PITCH = 0.12 -- radians, a little above the model looking down
local FIT_PASSES = 3
local FIT_TIMEOUT = 1.5 -- seconds: a model that reports no size by then is fitted with a guessed one
local GUESS_BOX = { -0.5, -0.5, 0, 0.5, 0.5, 2 }
local GRADIENT_WIDTH = 620
local GOLD = { 1, 0.82, 0.45 }
local STAND_ANIM = 0

local panel
local icons = {}

local function Freeze(actor)
	actor:SetAnimation(STAND_ANIM, 0, 0, 0) -- speed 0: held on the first frame
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
		f:SetPoint("TOP", panel.stand, "BOTTOM", (col - (inRow - 1) / 2) * step, -GEAR_TOP - 10 - row * step)

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
	panel.gearBottom:SetPoint("TOPLEFT", panel.stand, "BOTTOM", -panel.stripWidth / 2, -GEAR_TOP - 20 - rows * step + GAP)
end

-- A point in the model's space on the model frame, in frame units from its bottom left (the projection
-- is in pixels). nil when it isn't on screen.
local function Project(x, y, z)
	local scene = panel.model
	local px, py = scene:Project3DPointTo2D(x, y, z)
	local scale = scene:GetEffectiveScale()
	if not (px and py) or scale <= 0 then
		return nil
	end
	return px / scale, py / scale
end

-- Fits the camera so the model is FIT_H tall (and at most FIT_W wide), then moves the model frame so the
-- feet (z = 0, the actor's origin) land on the shadow. Returns false while the model has no size yet.
local function FitCamera(guess)
	local bx, by, bz, tx, ty, tz
	if guess then
		bx, by, bz, tx, ty, tz = unpack(GUESS_BOX)
	else
		bx, by, bz, tx, ty, tz = panel.actor:GetActiveBoundingBox()
	end
	if not (bx and tz) or tz - bz <= 0 then
		return false
	end
	local halfW, halfD = (tx - bx) / 2, (ty - by) / 2
	local ring = math.sqrt(halfW * halfW + halfD * halfD)
	local halfHeight = (tz - bz) / 2
	local radius = math.sqrt(ring * ring + halfHeight * halfHeight)

	local scene = panel.model
	scene:SetCameraOrientationByYawPitchRoll(math.pi, CAMERA_PITCH, 0)
	local fx, fy, fz = scene:GetCameraForward()
	if fz > 0 then -- the pitch's sign differs from what we assumed: we want to look down
		scene:SetCameraOrientationByYawPitchRoll(math.pi, -CAMERA_PITCH, 0)
		fx, fy, fz = scene:GetCameraForward()
	end
	local function PlaceCamera(distance)
		scene:SetCameraPosition(-fx * distance, -fy * distance, halfHeight - fz * distance)
	end
	scene:SetLightVisible(true)
	scene:SetLightType(Enum.ModelLightType and Enum.ModelLightType.Directional or 0)
	scene:SetLightDirection(fx, fy, fz)
	scene:SetLightAmbientColor(0.7, 0.7, 0.7)
	scene:SetLightDiffuseColor(0.8, 0.8, 0.8)

	-- Sizes on screen shrink with the distance: a few passes settle it.
	local distance = radius / math.tan(CAMERA_FOV / 2)
	for _ = 1, FIT_PASSES do
		PlaceCamera(distance)
		local _, top = Project(0, 0, 2 * halfHeight)
		local _, feet = Project(0, 0, 0)
		local left = Project(0, -ring, halfHeight)
		local right = Project(0, ring, halfHeight)
		if not (top and feet and left and right) then
			break
		end
		local ratio = math.max((top - feet) / FIT_H, math.abs(right - left) / FIT_W)
		if ratio <= 0 then
			break
		end
		distance = distance * ratio
	end
	PlaceCamera(distance)

	local feetX, feetY = Project(0, 0, 0)
	if not feetX then
		feetX, feetY = MODEL_W / 2, SHADOW_Y
	end
	scene:ClearAllPoints()
	scene:SetPoint("BOTTOMLEFT", panel.stand, "BOTTOMLEFT", MODEL_W / 2 - feetX, SHADOW_Y - feetY)
	return true
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

	-- Fixed box the layout hangs on; the model frame moves around it to put the feet on the shadow.
	panel.stand = CreateFrame("Frame", nil, panel)
	panel.stand:SetSize(MODEL_W, MODEL_H)
	panel.stand:SetPoint("CENTER", letterbox, "LEFT", CENTER_X, 40)

	panel.model = CreateFrame("ModelScene", nil, panel)
	panel.model:SetSize(MODEL_W, MODEL_H)
	panel.model:SetPoint("CENTER", panel.stand)
	panel.model:SetCameraFieldOfView(CAMERA_FOV)
	panel.actor = panel.model:CreateActor()
	-- Feet at height 0, so the projection of (0, 0, 0) is where they stand.
	panel.actor:SetUseCenterForOrigin(true, true, false)

	-- Ground shadow under the feet.
	for _, layer in ipairs(SoftEllipse(220, 44, 0.16)) do
		layer:SetPoint("CENTER", panel.stand, "BOTTOM", 0, SHADOW_Y)
	end

	panel.name = panel:CreateFontString(nil, "OVERLAY")
	panel.name:SetFont("Fonts\\MORPHEUS.TTF", 24, "")
	panel.name:SetShadowOffset(1, -1)
	panel.name:SetPoint("BOTTOM", panel.stand, "TOP", 0, 14)
	panel.ilvl = panel:CreateFontString(nil, "OVERLAY")
	panel.ilvl:SetFont(STANDARD_TEXT_FONT, 13, "")
	panel.ilvl:SetTextColor(0.75, 0.75, 0.75)
	panel.ilvl:SetShadowOffset(1, -1)
	panel.ilvl:SetPoint("TOP", panel.name, "BOTTOM", 0, -4)

	-- Gear strip under the feet, between two thin gold lines.
	local stripWidth = PER_ROW * (ICON + 2 + GAP) + 40
	panel.stripWidth = stripWidth
	panel.gearTop = GoldLine(stripWidth)
	panel.gearTop:SetPoint("TOPLEFT", panel.stand, "BOTTOM", -stripWidth / 2, -GEAR_TOP)
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
	-- Set the unit after showing: some model frames stay blank if the unit is set while hidden. Hidden
	-- until it's loaded and fitted (Showcase_Update).
	local actor = panel.actor
	actor:SetAlpha(0)
	actor:SetModelByUnit("player")
	actor:SetYaw(MODEL_FACING)
	Freeze(actor)
	panel.fitted = false
	panel.shownAt = GetTime()
end

-- Called every frame while the letterbox is visible.
function ns.Showcase_Update(alpha)
	if panel:IsShown() then
		panel:SetAlpha(alpha)
		if not panel.fitted then
			local actor = panel.actor
			if (actor:IsLoaded() and FitCamera()) or (GetTime() - panel.shownAt > FIT_TIMEOUT and FitCamera(true)) then
				panel.fitted = true
				Freeze(actor) -- again once loaded: an animation set before that may not stick
			end
		end
		-- The 3D model ignores the frame alpha: without this it pops out at 0.
		panel.actor:SetAlpha(panel.fitted and alpha or 0)
	end
end
