local addonName, ns = ...

-- Blizzard's Edit Mode moves Tomte's widgets too. Addons can't add systems to Edit Mode, so this only listens to
-- its open/close callbacks (EventRegistry "EditMode.Enter"/"EditMode.Exit") and never touches Blizzard's frames:
-- while it's open every registered widget shows (a preview when it has nothing to show) under a blue box with its
-- name that drags it. Positions stay in Tomte's own settings (one per widget, not per Edit Mode layout), and the
-- Lock checkboxes and unlock commands keep working on their own.
--
--
-- With Edit Mode's Snap checkbox on, a dragged widget snaps live like Blizzard's elements do (rules in EditModeData.lua):
-- to the screen, Blizzard's grid lines, Blizzard's elements and the other Tomte widgets. It only reads
-- EditModeMagnetismManager; adding our frames to it would put addon values into the tables that place the action
-- bars and taint them. So Blizzard's elements don't snap to Tomte's.
--
-- ns.EditMode_Register(spec): spec = { name, frame() -> the moving frame or nil, refresh() to show or hide it
--   (it asks ns.EditMode_Active()), saved() after a drag, place(box, frame) to size the box (default: the frame) }

local DEFAULT_SNAP_RANGE = 8 -- screen pixels, Blizzard's EditModeMagnetismManager.magnetismRange
local SNAP_LINE_WIDTH = 1.5 -- screen pixels, Blizzard's magnetismPreviewLinePixelWidth

local IsSecret = ns.IsSecret

local widgets = {}
local active = false

-- The look of Blizzard's selection boxes (the atlases of EditModeSystemSelectionLayout in Blizzard_EditMode).
local LAYOUT = {
	TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
	BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
	LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
	RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
	Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local KIT, HOVER_KIT = "editmode-actionbar-highlight", "editmode-actionbar-selected"

function ns.EditMode_Active()
	return active
end

-- Snapping --------------------------------------------------------------------------------------------------------

-- A region's { left, right, bottom, top } in UIParent's coordinates, or nil when it has no rect yet.
local function UIRect(region)
	local left, bottom, width, height = region:GetRect()
	if not left or IsSecret(left, bottom, width, height) then
		return nil
	end
	local scale = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return { left * scale, (left + width) * scale, bottom * scale, (bottom + height) * scale }
end

local function Values(map)
	local list = {}
	for _, value in pairs(map) do
		list[#list + 1] = value
	end
	return list
end

-- What a drag can snap to, read once when it starts (nothing else moves during it).
local function SnapTargets(spec, frame)
	local magnet = EditModeMagnetismManager
	local frames = {}
	-- Blizzard's shown elements, minus the one selected in Edit Mode; their Selection is the blue box around them.
	for system in pairs(magnet and magnet.magneticFrames or {}) do
		frames[#frames + 1] = UIRect(system.Selection or system)
	end
	for _, other in ipairs(widgets) do
		if other ~= spec and other.box and other.box:IsVisible() then
			frames[#frames + 1] = UIRect(other.box)
		end
	end
	-- Blizzard's grid lines while the grid is shown (nil otherwise), already in UIParent's coordinates.
	local grid = magnet and magnet.magneticGridLines
	return {
		snap = EditModeManagerFrame and EditModeManagerFrame:IsSnapEnabled(),
		clamp = frame:IsClampedToScreen(),
		screen = UIRect(UIParent),
		frames = frames,
		gridX = grid and Values(grid.vertical),
		gridY = grid and Values(grid.horizontal),
		range = (magnet and magnet.magnetismRange or DEFAULT_SNAP_RANGE) / UIParent:GetEffectiveScale(),
	}
end

-- The lines a drag is snapped to, drawn across the screen like Blizzard's (its red line template, at the strata of
-- its MagnetismPreviewLinesContainer). Made on the first drag, when Blizzard_EditMode is surely loaded.
local snapLines

local function SnapLine(container)
	local line = container:CreateLine(nil, "OVERLAY", "MagnetismPreviewLineTemplate")
	line:SetThickness(PixelUtil.GetNearestPixelSize(SNAP_LINE_WIDTH, line:GetEffectiveScale(), SNAP_LINE_WIDTH))
	line:Hide()
	return line
end

local function ShowSnapLines(lineX, lineY)
	if not snapLines then
		local container = CreateFrame("Frame", nil, UIParent)
		container:SetAllPoints()
		container:SetFrameStrata("HIGH")
		snapLines = { x = SnapLine(container), y = SnapLine(container) }
	end
	local x, y = snapLines.x, snapLines.y
	if lineX then
		x:SetStartPoint("BOTTOMLEFT", UIParent, lineX, 0)
		x:SetEndPoint("TOPLEFT", UIParent, lineX, 0)
	end
	if lineY then
		y:SetStartPoint("BOTTOMLEFT", UIParent, 0, lineY)
		y:SetEndPoint("BOTTOMRIGHT", UIParent, 0, lineY)
	end
	x:SetShown(lineX ~= nil)
	y:SetShown(lineY ~= nil)
end

-- Dragging --------------------------------------------------------------------------------------------------------
-- The box moves the widget itself instead of StartMoving, which can't be offset mid-drag: each frame the widget
-- follows the cursor, then snaps. Its anchor points keep their own points and only shift, so a widget keeps the
-- side it grows from.

local function CursorUI()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	return x / scale, y / scale
end

local function DragUpdate(box, frame)
	local drag = box.drag
	local x, y = CursorUI()
	local dx, dy, lineX, lineY = ns.EditMode_DragOffset(drag.rect, x - drag.x, y - drag.y, drag.targets)
	for _, p in ipairs(drag.points) do
		frame:SetPoint(p[1], p[2], p[3], p[4] + dx * drag.toFrame, p[5] + dy * drag.toFrame)
	end
	ShowSnapLines(lineX, lineY)
end

local function StartDrag(spec, frame)
	local box = spec.box
	local rect = UIRect(box)
	if not rect or frame:GetNumPoints() == 0 then
		return
	end
	local points = {}
	for i = 1, frame:GetNumPoints() do
		points[i] = { frame:GetPoint(i) }
	end
	local x, y = CursorUI()
	box.drag = {
		rect = rect,
		x = x,
		y = y,
		points = points,
		targets = SnapTargets(spec, frame),
		toFrame = UIParent:GetEffectiveScale() / frame:GetEffectiveScale(), -- UIParent units -> the frame's offsets
	}
	box:SetScript("OnUpdate", function()
		DragUpdate(box, frame)
	end)
end

-- Also runs when Edit Mode closes mid-drag (the box hides), so the position is saved either way.
local function StopDrag(spec, frame)
	local box = spec.box
	if not box.drag then
		return
	end
	DragUpdate(box, frame)
	ShowSnapLines(nil, nil)
	box:SetScript("OnUpdate", nil)
	box.drag = nil
	spec.saved()
end

-- Boxes -----------------------------------------------------------------------------------------------------------

local function Box(spec, frame)
	local box = spec.box
	if box and box:GetParent() == frame then
		return box
	end
	box = CreateFrame("Frame", nil, frame)
	-- Well above the widget's own children (rows, icons, buttons), so the box draws over them and takes the drag.
	box:SetFrameLevel(frame:GetFrameLevel() + 100)
	box:SetIgnoreParentAlpha(true)
	box:EnableMouse(true)
	box:RegisterForDrag("LeftButton")
	NineSliceUtil.ApplyLayout(box, LAYOUT, KIT)
	box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	box.label:SetPoint("CENTER")
	box.label:SetText(spec.name)
	box:SetScript("OnDragStart", function()
		StartDrag(spec, frame)
	end)
	box:SetScript("OnDragStop", function()
		StopDrag(spec, frame)
	end)
	box:SetScript("OnHide", function()
		StopDrag(spec, frame)
	end)
	box:SetScript("OnEnter", function(self)
		NineSliceUtil.ApplyLayout(self, LAYOUT, HOVER_KIT)
	end)
	box:SetScript("OnLeave", function(self)
		NineSliceUtil.ApplyLayout(self, LAYOUT, KIT)
	end)
	if spec.place then
		spec.place(box, frame)
	else
		box:SetAllPoints()
	end
	spec.box = box
	return box
end

local function Apply(spec)
	spec.refresh()
	local frame = spec.frame()
	if active and frame then
		Box(spec, frame):Show()
	elseif spec.box then
		spec.box:Hide()
	end
end

function ns.EditMode_Register(spec)
	widgets[#widgets + 1] = spec
	if active then
		Apply(spec)
	end
end

local function SetActive(on)
	active = on
	for _, spec in ipairs(widgets) do
		local ok, err = pcall(Apply, spec)
		if not ok then
			ns.errorHandler(err)
		end
	end
end

EventRegistry:RegisterCallback("EditMode.Enter", function()
	SetActive(true)
end, ns)
EventRegistry:RegisterCallback("EditMode.Exit", function()
	SetActive(false)
end, ns)
