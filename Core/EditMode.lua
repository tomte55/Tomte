local addonName, ns = ...

-- Blizzard's Edit Mode moves Tomte's widgets too. Addons can't add systems to Edit Mode, so this only listens to
-- its open/close callbacks (EventRegistry "EditMode.Enter"/"EditMode.Exit") and never touches Blizzard's frames:
-- while it's open every registered widget shows (a preview when it has nothing to show) under a blue box with its
-- name that drags it. Positions stay in Tomte's own settings (one per widget, not per Edit Mode layout), and the
-- Lock checkboxes and unlock commands keep working on their own. /tomte unlock shows the same boxes without Edit
-- Mode (World of Warcraft: Forever has none).
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

-- Blizzard's selection look where the client has Edit Mode's atlases; elsewhere (Forever) a theme border.
local function Look(box, hover)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(KIT .. "-NineSlice-Corner") then
		NineSliceUtil.ApplyLayout(box, LAYOUT, hover and HOVER_KIT or KIT)
	elseif box.borderEdges then
		ns.UI.SetBorderColor(box, hover and "heading" or "accent")
	else
		ns.UI.Border(box, hover and "heading" or "accent")
	end
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
	Look(box, false)
	box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	box.label:SetPoint("CENTER")
	box.label:SetText(spec.name)
	box:SetScript("OnDragStart", function()
		spec.dragging = true
		frame:StartMoving()
	end)
	box:SetScript("OnDragStop", function()
		if not spec.dragging then -- already ended when combat started
			return
		end
		spec.dragging = nil
		frame:StopMovingOrSizing()
		spec.saved()
	end)
	box:SetScript("OnEnter", function(self)
		Look(self, true)
	end)
	box:SetScript("OnLeave", function(self)
		Look(self, false)
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

-- The boxes show while Blizzard's Edit Mode is open or the player unlocked them with /tomte unlock.
local editMode, unlocked = false, false

local function Refresh()
	active = editMode or unlocked
	for _, spec in ipairs(widgets) do
		local ok, err = pcall(Apply, spec)
		if not ok then
			ns.errorHandler(err)
		end
	end
end

EventRegistry:RegisterCallback("EditMode.Enter", function()
	editMode = true
	Refresh()
end, ns)
EventRegistry:RegisterCallback("EditMode.Exit", function()
	editMode = false
	Refresh()
end, ns)

function ns.EditMode_Unlocked()
	return unlocked
end

-- Unlock: some widgets are secure buttons (Fishing key, Drawers), which can't move in combat, so unlocking waits
-- for the end of combat and entering combat locks them again.
local combatFrame
function ns.EditMode_Unlock(on)
	if on == unlocked then
		return
	end
	if on and InCombatLockdown() then
		ns.Print("can't unlock in combat.")
		return
	end
	if not combatFrame then
		combatFrame = CreateFrame("Frame")
		combatFrame:SetScript("OnEvent", function()
			-- A drag still going when combat starts: drop it here and keep where it got to (the box hides, so its
			-- OnDragStop would never come, and a secure widget can't move in combat).
			for _, spec in ipairs(widgets) do
				local frame = spec.frame()
				if frame and spec.dragging then
					spec.dragging = nil
					frame:StopMovingOrSizing()
					spec.saved()
				end
			end
			ns.EditMode_Unlock(false)
			ns.Print("widgets locked for combat.")
		end)
	end
	unlocked = on
	if on then
		combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
		ns.Print("drag Tomte's widgets to move them; /tomte lock when done.")
	else
		combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
	end
	Refresh()
	if ns.Panel_Refresh then
		ns.Panel_Refresh()
	end
end
