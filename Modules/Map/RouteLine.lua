local addonName, ns = ...

-- Tomte map: a Waypoints route (Modules/Travel/ForeverRouter.lua, ns.WayRouter_Path) as a line: flights, zeppelins and
-- boats solid, the walks between them fainter. Laid out with the flight pins (Flights.lua calls it on every layout,
-- with the view's transform for points anywhere, so a line still runs to a place off the view's edge).

local TRAVEL_PX, WALK_PX = 3, 2 -- line thickness, pixels
local TRAVEL_ALPHA, WALK_ALPHA = 0.9, 0.45

local UI = ns.UI

local layer
local lines = {}
local used = 0

local function Line(i)
	local line = lines[i]
	if not line then
		line = layer:CreateLine(nil, "OVERLAY")
		lines[i] = line
	end
	return line
end

local function HideLines()
	for i = 1, used do
		lines[i]:Hide()
	end
	used = 0
end

function ns.MapRoute_Init(pinLayer)
	layer = pinLayer or layer
end

-- toViewAll(cx, cy) -> x, y: pixels from the layer's centre (x right, y down), for any canvas point.
function ns.MapRoute_Layout(toViewAll)
	HideLines()
	local path = layer and toViewAll and ns.WayRouter_Path and ns.WayRouter_Path()
	if not path then
		return
	end
	local px, py
	for _, p in ipairs(path) do
		local cx, cy = ns.MapArt_ToCanvas(p[1], p[2], p[3])
		local x, y
		if cx then
			x, y = toViewAll(cx, cy)
		end
		if x and px then
			local walk = p[4] == "walk"
			used = used + 1
			local line = Line(used)
			line:SetThickness(walk and WALK_PX or TRAVEL_PX)
			line:SetColorTexture(UI.Color("accent"))
			line:SetAlpha(walk and WALK_ALPHA or TRAVEL_ALPHA)
			line:SetStartPoint("CENTER", layer, px, -py)
			line:SetEndPoint("CENTER", layer, x, -y)
			line:Show()
		end
		px, py = x, y
	end
end
