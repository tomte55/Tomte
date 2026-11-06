local addonName, ns = ...

-- Gear Check's upgrade arrow, drawn in Baganator's bags (Baganator.lua) and Tomte's own (Modules/Bags/Buttons.lua), on
-- retail and on Forever.

local UI = ns.UI

-- The tint of each ns.Gear_BagArrow kind (nil: the arrow's own green).
ns.GEAR_ARROW_ROLES = {
	maybe = "warning", -- the tooltip's "Can't judge" color
	alt = "accent", -- the color of Tomte's map markers, so it can't pass for your own arrow
}

-- Bigger than Blizzard's bag arrow, with a dark copy behind it so it reads on bright icons. role: theme color to
-- tint with (the arrow is desaturated first so the tint is the color), nil for the atlas's own.
function ns.Gear_Arrow(itemButton, role)
	local widget = CreateFrame("Frame", nil, itemButton)
	widget:SetSize(22, 24)
	widget.padding = 0.5
	local shadow = widget:CreateTexture(nil, "ARTWORK")
	shadow:SetAtlas("bags-greenarrow")
	shadow:SetVertexColor(0, 0, 0, 0.9)
	shadow:SetPoint("TOPLEFT", 1.5, -1.5)
	shadow:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
	local arrow = widget:CreateTexture(nil, "OVERLAY")
	arrow:SetAtlas("bags-greenarrow")
	arrow:SetAllPoints()
	if role then
		arrow:SetDesaturated(true)
		arrow:SetVertexColor(UI.Color(role))
	end
	return widget
end
