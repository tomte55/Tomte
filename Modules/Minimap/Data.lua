local addonName, ns = ...

-- Minimap button positioning. Pure logic (unit-tested with plain Lua). Same rules as LibDBIcon: each quadrant of
-- the minimap is round or square depending on GetMinimapShape(); round quadrants put the button on the ellipse,
-- square ones on the diagonal, clamped to the edge.
-- The quadrant table and the placement maths are adapted from LibDBIcon-1.0 (by Rabbit and funkehdude,
-- https://www.wowace.com/projects/libdbicon-1-0), used under its Ace3-style BSD license.

local QUADRANTS = { -- [shape] = round? for quadrants 1 (bottom right), 2 (bottom left), 3 (top right), 4 (top left)
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- angle in degrees (0 = right, counter-clockwise); halfW/halfH = half the minimap size plus the button radius.
-- Returns the button's offset from the minimap's center.
function ns.Minimap_Offset(angle, halfW, halfH, shape)
	local rad = math.rad(angle)
	local x, y = math.cos(rad), math.sin(rad)
	-- Quadrant numbering as in the table above.
	local q = 1
	if x < 0 then
		q = q + 1
	end
	if y > 0 then
		q = q + 2
	end
	local round = (QUADRANTS[shape] or QUADRANTS.ROUND)[q]
	if round then
		return x * halfW, y * halfH
	end
	local diagW = math.sqrt(2 * halfW ^ 2) - 10
	local diagH = math.sqrt(2 * halfH ^ 2) - 10
	return math.max(-halfW, math.min(x * diagW, halfW)), math.max(-halfH, math.min(y * diagH, halfH))
end

-- Offset from the minimap's center -> angle in degrees, 0-360.
local atan2 = math.atan2 or math.atan -- WoW (Lua 5.1) has atan2; plain Lua 5.4 takes two args in atan
function ns.Minimap_Angle(dx, dy)
	return math.deg(atan2(dy, dx)) % 360
end

-- How far apart two angles are around the circle, 0-180.
local function Apart(a, b)
	return math.abs((a - b + 180) % 360 - 180)
end

-- An angle for a newly shown button: the first of start, start + step, start + 2 * step, ... at least gap degrees
-- from every taken angle; start when the whole edge is taken.
function ns.Minimap_FreeAngle(taken, start, step, gap)
	for i = 0, math.floor(360 / math.abs(step)) - 1 do
		local angle = (start + i * step) % 360
		local free = true
		for _, other in ipairs(taken) do
			if Apart(angle, other) < gap then
				free = false
				break
			end
		end
		if free then
			return angle
		end
	end
	return start % 360
end

-- count angles one step apart from start, for Reset.
function ns.Minimap_Spread(count, start, step)
	local list = {}
	for i = 1, count do
		list[i] = (start + (i - 1) * step) % 360
	end
	return list
end
