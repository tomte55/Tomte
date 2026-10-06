local addonName, ns = ...

-- Minimap Button module: a round button on the minimap's edge that opens the panel (right-click: the Weekly
-- board's popup). Drag it around the edge.
-- Looks like LibDBIcon's retail buttons (same Blizzard textures and sizes), without the library.
-- Positioning maths is in Data.lua.

local DEFAULT_ANGLE = 225
local RADIUS = 5 -- how far outside the minimap's edge the button sits (LibDBIcon's default)

local module, button

local function Place()
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local x, y = ns.Minimap_Offset(module.db.angle, Minimap:GetWidth() / 2 + RADIUS, Minimap:GetHeight() / 2 + RADIUS, shape)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function FollowCursor()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	module.db.angle = ns.Minimap_Angle(px / scale - mx, py / scale - my)
	Place()
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Tomte", 1, 0.82, 0.45)
	GameTooltip:AddLine("Click to open Tomte", 1, 1, 1)
	if ns.Weekly_Active and ns.Weekly_Active() then
		GameTooltip:AddLine("Right-click for this week's open items", 1, 1, 1)
	end
	local nextUp = ns.NextUp_TooltipLines and ns.NextUp_TooltipLines()
	if nextUp and #nextUp > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Next up", 1, 0.82, 0.45)
		for _, line in ipairs(nextUp) do
			GameTooltip:AddLine(line, 1, 1, 1, true)
		end
		GameTooltip:AddLine(" ")
	end
	GameTooltip:AddLine("Drag to move", 0.62, 0.62, 0.62)
	GameTooltip:Show()
end

local function Create()
	button = CreateFrame("Button", nil, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFixedFrameStrata(true)
	button:SetFrameLevel(8)
	button:SetFixedFrameLevel(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
	background:SetSize(24, 24)
	background:SetPoint("CENTER")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.ICON)
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	local mask = button:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			if ns.Weekly_TogglePopup then -- Weekly board (it ignores the click while turned off)
				ns.Weekly_TogglePopup()
			end
		else
			ns.Panel_Toggle()
		end
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:LockHighlight()
		self:SetScript("OnUpdate", FollowCursor)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)
	-- Edit Mode can resize the minimap.
	Minimap:HookScript("OnSizeChanged", function()
		if button:IsShown() then
			Place()
		end
	end)
end

-- A small dot on the button (Recent: something you haven't seen).
local dotWanted = false
local function ApplyDot()
	if not button then
		return
	end
	if not button.dot then
		button.dot = button:CreateTexture(nil, "OVERLAY", nil, 2)
		button.dot:SetSize(10, 10)
		button.dot:SetPoint("TOPRIGHT", -4, -4)
		button.dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		button.dot:SetVertexColor(1, 0.82, 0.45)
	end
	button.dot:SetShown(dotWanted)
end

function ns.Minimap_SetDot(shown)
	dotWanted = shown and true or false
	ApplyDot()
end

local function ResetPosition()
	module.db.angle = DEFAULT_ANGLE
	if button then
		Place()
	end
end

module = ns.RegisterModule({
	key = "minimap",
	name = "Minimap Button",
	category = "General",
	description = "A button on the minimap's edge that opens this window. Drag it to move it around the minimap.",
	enabledByDefault = true,
	defaults = {
		angle = DEFAULT_ANGLE,
	},
	toggle = function(active)
		if active then
			if not button then
				Create()
			end
			Place()
			button:Show()
			ApplyDot()
		elseif button then
			button:Hide()
		end
	end,
	options = {
		{ type = "button", label = "Position", text = "Reset", onClick = ResetPosition,
			tooltip = "Put the button back at the bottom left of the minimap." },
	},
})
