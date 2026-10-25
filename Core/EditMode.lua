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
--
-- The widgets' shared motion is at the end (ns.EditMode_Fold*, ns.EditMode_Reflow): folding to the title eases, and
-- rows that arrive or move while a widget shows fade and glide.

local DEFAULT_SNAP_RANGE = 8 -- screen pixels, Blizzard's EditModeMagnetismManager.magnetismRange
local NUDGE, NUDGE_SHIFT = 1, 10 -- UIParent units per arrow key press, as Blizzard's ProcessMovementKey
local NUDGE_KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local SNAP_LINE_WIDTH = 1.5 -- screen pixels, Blizzard's magnetismPreviewLinePixelWidth
local SETTLE_SECONDS = 0.45 -- a dropped widget's outline easing from the accent color back to Edit Mode's
local FOLD_SECONDS = 0.22 -- a widget's height easing to its folded or unfolded size
local FOLD_FADE = 0.1 -- what a fold hides fading out before the widget shrinks
local FOLD_STAGGER = 0.03 -- seconds between two regions fading in, top down
local GLIDE_SECONDS = 0.25 -- a row gliding from where it was drawn to its new place
local INSTANT = 0.001 -- an animation's shortest duration

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

-- A dropped widget settles: its box's outline flashes the accent color and eases back. Made on the first drop, on
-- top of the box's own outline (the selected kit, desaturated so the accent tints it true).
local function Settle(box)
	local UI = ns.UI
	local flash = box.settle
	if not flash then
		flash = CreateFrame("Frame", nil, box)
		flash:SetAllPoints()
		NineSliceUtil.ApplyLayout(flash, LAYOUT, SELECTED_KIT)
		if flash.Center then
			flash.Center:Hide() -- the outline only, not a wash over the widget
		end
		for _, region in ipairs({ flash:GetRegions() }) do
			region:SetDesaturated(true)
			region:SetBlendMode("ADD")
		end
		flash:Hide()
		box.settle = flash
	end
	local r, g, b = UI.Color("accent")
	for _, region in ipairs({ flash:GetRegions() }) do
		region:SetVertexColor(r, g, b)
	end
	flash:SetAlpha(1)
	flash:Show()
	UI.AlphaTo(flash, 0, SETTLE_SECONDS, function()
		flash:Hide()
	end)
end

-- Also runs when Edit Mode closes mid-drag (the box hides), so the position is saved either way; dropped: the player
-- let go (the box settles with a sound), not the box hiding.
local function StopDrag(spec, frame, dropped)
	local box = spec.box
	if not box.drag then
		return
	end
	DragUpdate(box, frame)
	ShowSnapLines(nil, nil)
	box:SetScript("OnUpdate", nil)
	box.drag = nil
	spec.saved()
	if dropped then
		Settle(box)
		ns.UI.Sound("drop")
	end
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
		ns.UI.Sound("tick")
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
		StopDrag(spec, frame, true)
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

-- Widget motion -----------------------------------------------------------------------------------------------------
-- For the widgets above (Almost Done, Crafting list, Gathering run, Pet battle helper): the minus in their corner
-- eases the height instead of snapping, and rows that arrive or move while a widget shows fade and glide. Widgets are
-- anchored by their top, so only the bottom edge moves and saved positions stay put. Tweens follow the Tomte window's
-- Motion setting on their own ("off": everything lands at once).

-- What a redraw of f is compared with: the height f is drawn at and which of regions show. Take it just before.
function ns.EditMode_FoldStart(f, regions)
	local shown = {}
	for _, r in ipairs(regions) do
		shown[r] = r:IsShown()
	end
	return { height = f:GetHeight(), shown = shown, visible = f:IsVisible() }
end

-- Call after every redraw that sets f's height: while a fold runs, that height becomes where it eases to and f stays
-- at the fold's height meanwhile (no one-frame jump).
function ns.EditMode_FoldKeep(f)
	if f.foldHeight then
		f.foldTarget = f:GetHeight()
		f:SetHeight(f.foldHeight)
	end
end

local function FoldLand(f, height)
	ns.UI.TweenStop(f, "fold")
	f.foldHeight, f.foldTarget = nil, nil
	f:SetHeight(height)
	f:SetClipsChildren(false)
end

-- After the redraw (before = what EditMode_FoldStart took): f's height eases from what it was to what the redraw set.
-- Regions the redraw hid fade out first and f shrinks after them; regions it showed fade in top down (regions are in
-- top-down order) while f grows, clipped to it. A widget that wasn't showing lands at once.
function ns.EditMode_Fold(f, before, regions)
	local UI = ns.UI
	local to = f.foldHeight and f.foldTarget or f:GetHeight()
	-- A fold cut short: what it was fading out stays as the redraw left it.
	for _, r in ipairs(f.foldLeaving or {}) do
		UI.TweenStop(r, "alpha")
		r:SetAlpha(1)
	end
	f.foldLeaving = nil
	if not (before.visible and f:IsVisible()) or UI.MotionLevel() == "off" then
		for _, r in ipairs(regions) do
			UI.TweenStop(r, "alpha")
			r:SetAlpha(1)
		end
		FoldLand(f, to)
		return
	end
	local leaving, arriving = {}, {}
	for _, r in ipairs(regions) do
		local now = r:IsShown()
		if before.shown[r] and not now then
			leaving[#leaving + 1] = r
		elseif now and not before.shown[r] then
			arriving[#arriving + 1] = r
		end
	end
	for _, r in ipairs(leaving) do
		r:Show()
		UI.AlphaTo(r, 0, FOLD_FADE, function()
			r:Hide()
			r:SetAlpha(1)
		end)
	end
	f.foldLeaving = #leaving > 0 and leaving or nil
	local step = #arriving > 0 and math.min(FOLD_STAGGER, FOLD_SECONDS / #arriving) or 0
	for i, r in ipairs(arriving) do
		r:SetAlpha(0)
		UI.Tween(r, "alpha", FOLD_SECONDS, function(t)
			r:SetAlpha(t)
		end, nil, nil, (i - 1) * step)
	end
	local from = before.height
	if math.abs(to - from) < 0.5 then
		FoldLand(f, to)
		return
	end
	f.foldHeight, f.foldTarget = from, to
	f:SetHeight(from)
	f:SetClipsChildren(true) -- what the growing widget doesn't reach yet stays out of sight
	UI.Tween(f, "fold", FOLD_SECONDS, function(t)
		f.foldHeight = UI.Lerp(from, f.foldTarget, t)
		f:SetHeight(f.foldHeight)
	end, function()
		FoldLand(f, f.foldTarget)
	end, nil, #leaving > 0 and FOLD_FADE or nil)
end

-- Draws row dy higher (negative: lower) than its place and glides it there. Moves only how it's drawn: its anchors are
-- already final.
local function Glide(row, dy)
	local group = row.glide
	if not group then
		group = row:CreateAnimationGroup()
		-- Within a group, a finished translation stays applied until the group ends: there at once, then back.
		group.jump = group:CreateAnimation("Translation")
		group.jump:SetOrder(1)
		group.jump:SetDuration(INSTANT)
		group.back = group:CreateAnimation("Translation")
		group.back:SetOrder(2)
		group.back:SetDuration(GLIDE_SECONDS)
		group.back:SetSmoothing("IN_OUT")
		row.glide = group
	end
	group:Stop()
	group.jump:SetOffset(0, dy)
	group.back:SetOffset(0, -dy)
	group:Play()
end

-- For a list redrawn while it shows: rows[1..n] carry .key (nil: not followed) and .y (their top, in units down from
-- their parent's top). spots is what this returned for the list's last draw (nil, a first draw or a list that wasn't
-- showing: nothing moves). Rows with a new key fade in; rows drawn elsewhere last time glide from there, so the rows
-- below one that arrived or left open or close up instead of jumping. Returns the spots for the next draw.
function ns.EditMode_Reflow(rows, n, spots)
	local UI = ns.UI
	local glide = UI.MotionLevel() ~= "off"
	local now, arrived = {}, {}
	for i = 1, n do
		local row = rows[i]
		local key = row.key
		if key ~= nil then
			now[key] = row.y
			local was = spots and spots[key]
			if spots and was == nil then
				arrived[#arrived + 1] = row
			elseif was and was ~= row.y and glide then
				Glide(row, row.y - was)
			end
		end
	end
	UI.FadeInRows(arrived, 1, #arrived, GLIDE_SECONDS)
	return now
end

EventRegistry:RegisterCallback("EditMode.Enter", function()
	SetActive(true)
end, ns)
EventRegistry:RegisterCallback("EditMode.Exit", function()
	SetActive(false)
end, ns)
