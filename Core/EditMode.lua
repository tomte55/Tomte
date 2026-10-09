local addonName, ns = ...

-- Blizzard's Edit Mode moves Tomte's widgets too. Addons can't add systems to Edit Mode, so this only listens to
-- its open/close callbacks (EventRegistry "EditMode.Enter"/"EditMode.Exit") and never touches Blizzard's frames:
-- while it's open every registered widget shows (a preview when it has nothing to show) under a blue box with its
-- name that drags it. Positions stay in Tomte's own settings (one per widget, not per Edit Mode layout), and the
-- Lock checkboxes and unlock commands keep working on their own.
--
-- ns.EditMode_Register(spec): spec = { name, frame() -> the moving frame or nil, refresh() to show or hide it
--   (it asks ns.EditMode_Active()), saved() after a drag, place(box, frame) to size the box (default: the frame) }

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

local function Box(spec, frame)
	local box = spec.box
	if box and box:GetParent() == frame then
		return box
	end
	box = CreateFrame("Frame", nil, frame)
	box:SetFrameLevel(frame:GetFrameLevel() + 100)
	box:SetIgnoreParentAlpha(true)
	box:EnableMouse(true)
	box:RegisterForDrag("LeftButton")
	NineSliceUtil.ApplyLayout(box, LAYOUT, KIT)
	box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	box.label:SetPoint("CENTER")
	box.label:SetText(spec.name)
	box:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	box:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		spec.saved()
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
