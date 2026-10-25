local addonName, ns = ...

-- Blizzard's Edit Mode moves Tomte's widgets too. Addons can't add systems to Edit Mode, so this only listens to
-- its open/close callbacks (EventRegistry "EditMode.Enter"/"EditMode.Exit") and never touches Blizzard's frames:
-- while it's open every registered widget shows (a preview when it has nothing to show) under a blue box with its
-- name that drags it. Positions stay in Tomte's own settings (one per widget, not per Edit Mode layout), and the
-- Lock checkboxes and unlock commands keep working on their own.
--
-- With Edit Mode's Snap checkbox on, a dragged widget snaps live like Blizzard's elements do (rules in
-- EditModeData.lua): to the screen, Blizzard's grid lines, Blizzard's elements and the other Tomte widgets. It only
-- reads EditModeMagnetismManager; adding our frames to it would put addon values into the tables that place the
-- action bars and taint them. So Blizzard's elements don't snap to Tomte's.
--
-- Like Blizzard's, a press on a box selects it (yellow) and only the selected one drags (the same press can go on
-- into the drag), and the arrow keys nudge it. The selected widget gets a settings dialog
-- (Panel/EditModeDialog.lua). Selecting one of Blizzard's elements deselects ours; selecting ours deselects
-- Blizzard's through EditModeManagerFrame:ClearSelectedSystem, which Blizzard runs through a secure delegate so addon
-- calls don't taint it.
--
-- ns.EditMode_Register(spec): spec = { name, frame() -> the moving frame or nil, refresh() to show or hide it
--   (it asks ns.EditMode_Active()), saved() after a drag, place(box, frame) to size the box (default: the frame),
--   and for the settings dialog: module = "<module key>", options = { "<options key>", ... } (rows of that module's
--   options schema), reset() to put it back in its default place }

local DEFAULT_SNAP_RANGE = 8 -- screen pixels, Blizzard's EditModeMagnetismManager.magnetismRange
local NUDGE, NUDGE_SHIFT = 1, 10 -- UIParent units per arrow key press, as Blizzard's ProcessMovementKey
local NUDGE_KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
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
local KIT, SELECTED_KIT = "editmode-actionbar-highlight", "editmode-actionbar-selected"

local selected -- the selected widget's spec

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

-- Selecting -------------------------------------------------------------------------------------------------------

-- The selected box's look, and the arrow keys while it's selected (keyboard can't be claimed in combat).
local function SetKit(spec)
	local box = spec.box
	if not box then
		return
	end
	NineSliceUtil.ApplyLayout(box, LAYOUT, spec == selected and SELECTED_KIT or KIT)
	if not InCombatLockdown() then
		box:EnableKeyboard(spec == selected)
	end
end

-- Moves the widget by dx, dy UIParent units, keeping its anchor points (as a drag does); no snapping, like Blizzard.
local function Nudge(spec, frame, dx, dy)
	local toFrame = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local points = {}
	for i = 1, frame:GetNumPoints() do
		points[i] = { frame:GetPoint(i) }
	end
	for _, p in ipairs(points) do
		frame:SetPoint(p[1], p[2], p[3], p[4] + dx * toFrame, p[5] + dy * toFrame)
	end
	spec.saved()
end

-- Arrow keys nudge the selected widget (Shift: further); every other key goes on to the game.
local function OnKeyDown(spec, frame, box, key)
	local dir = NUDGE_KEYS[key]
	if InCombatLockdown() then
		return
	end
	box:SetPropagateKeyboardInput(not dir)
	if dir then
		local step = IsShiftKeyDown() and NUDGE_SHIFT or NUDGE
		Nudge(spec, frame, dir[1] * step, dir[2] * step)
	end
end

function ns.EditMode_Selected()
	return selected
end

function ns.EditMode_Deselect()
	local old = selected
	if not old then
		return
	end
	selected = nil
	SetKit(old)
	ns.EditModeDialog_Hide()
end

local function Select(spec)
	if selected == spec then
		return
	end
	local old = selected
	selected = spec
	if old then
		SetKit(old)
	end
	SetKit(spec)
	if not InCombatLockdown() then
		EditModeManagerFrame:ClearSelectedSystem()
	end
	ns.EditModeDialog_Show(spec)
end

-- On the first Edit Mode open, when EditModeManagerFrame surely exists.
local hooked = false
local function HookBlizzardSelect()
	if hooked then
		return
	end
	hooked = true
	hooksecurefunc(EditModeManagerFrame, "SelectSystem", function()
		ns.EditMode_Deselect()
	end)
end

-- Hides a widget and its box until Edit Mode closes, to see what's under it (Blizzard's list has checkboxes for this).
-- By alpha: whether the widget shows is its own module's call.
function ns.EditMode_HideWidget(spec)
	local frame = spec.frame()
	if selected == spec then
		ns.EditMode_Deselect()
	end
	if frame and not spec.hiddenFrame then
		spec.hiddenFrame, spec.hiddenAlpha = frame, frame:GetAlpha()
		frame:SetAlpha(0)
	end
	if spec.box then
		spec.box:Hide()
	end
end

local function Unhide(spec)
	if spec.hiddenFrame then
		spec.hiddenFrame:SetAlpha(spec.hiddenAlpha)
		spec.hiddenFrame, spec.hiddenAlpha = nil, nil
	end
end

-- Boxes -----------------------------------------------------------------------------------------------------------

-- Blizzard's hover: the box's own kit again on top, added (EditModeSystemSelectionBaseMixin's MouseOverHighlight).
local function HoverGlow(box)
	local glow = CreateFrame("Frame", nil, box)
	glow:SetAllPoints()
	NineSliceUtil.ApplyLayout(glow, LAYOUT, KIT)
	for _, region in ipairs({ glow:GetRegions() }) do
		region:SetBlendMode("ADD")
	end
	glow:Hide()
	return glow
end

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
	box:SetPropagateKeyboardInput(true)
	box:SetScript("OnKeyDown", function(self, key)
		OnKeyDown(spec, frame, self, key)
	end)
	spec.box = box
	SetKit(spec)
	box.glow = HoverGlow(box)
	box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	box.label:SetPoint("CENTER")
	box.label:SetText(spec.name)
	box:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			Select(spec)
		end
	end)
	box:SetScript("OnDragStart", function()
		if selected == spec then
			StartDrag(spec, frame)
		end
	end)
	box:SetScript("OnDragStop", function()
		StopDrag(spec, frame)
	end)
	box:SetScript("OnHide", function()
		StopDrag(spec, frame)
		if selected == spec then
			ns.EditMode_Deselect()
		end
	end)
	box:SetScript("OnEnter", function(self)
		self.glow:Show()
	end)
	box:SetScript("OnLeave", function(self)
		self.glow:Hide()
	end)
	if spec.place then
		spec.place(box, frame)
	else
		box:SetAllPoints()
	end
	return box
end

local function Apply(spec)
	spec.refresh()
	local frame = spec.frame()
	if active and frame and not spec.hiddenFrame then
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
	if on then
		HookBlizzardSelect()
	end
	for _, spec in ipairs(widgets) do
		if not on then
			Unhide(spec)
		end
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
