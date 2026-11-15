local addonName, ns = ...

-- Gathering nodes on the minimap: pure logic (no WoW API calls; unit-tested in tests/test_gather_minimap.lua). Where a
-- map spot lands on the minimap relative to the player (yards east and north, turned with a rotating minimap), whether
-- it's inside a round or square minimap, the edge point toward it, and a route leg clipped to the minimap.
-- Drawn by MinimapPins.lua.

-- Offset of a spot from the player in yards: east, north. Map coordinates grow east (x) and south (y). facing
-- (radians counterclockwise from north, GetPlayerFacing) turns the result so the player faces up; nil for a minimap
-- that doesn't rotate.
function ns.GatherMini_Offset(sx, sy, px, py, w, h, facing)
	local east, north = (sx - px) * w, (py - sy) * h
	if not facing then
		return east, north
	end
	local c, s = math.cos(facing), math.sin(facing)
	return east * c + north * s, north * c - east * s
end

-- True when x, y (any unit, minimap center at 0, 0) is within radius r: a circle, or a square for any other shape.
function ns.GatherMini_Inside(x, y, r, round)
	if round then
		return x * x + y * y <= r * r
	end
	return math.abs(x) <= r and math.abs(y) <= r
end

-- The point on the edge (radius r) in the direction of x, y.
function ns.GatherMini_Clamp(x, y, r, round)
	if round then
		local d = math.sqrt(x * x + y * y)
		if d == 0 then
			return 0, 0
		end
		return x / d * r, y / d * r
	end
	local m = math.max(math.abs(x), math.abs(y))
	if m == 0 then
		return 0, 0
	end
	return x / m * r, y / m * r
end

-- The part of the leg x1, y1 -> x2, y2 inside the minimap (radius r): four numbers, or nil when none of it is.
function ns.GatherMini_Clip(x1, y1, x2, y2, r, round)
	local dx, dy = x2 - x1, y2 - y1
	local t0, t1 = 0, 1
	if round then
		-- |p + t d|^2 = r^2: a t^2 + b t + c = 0
		local a = dx * dx + dy * dy
		local b = 2 * (x1 * dx + y1 * dy)
		local c = x1 * x1 + y1 * y1 - r * r
		if a == 0 then
			if c > 0 then
				return nil
			end
			return x1, y1, x2, y2
		end
		local disc = b * b - 4 * a * c
		if disc <= 0 then
			return nil
		end
		local root = math.sqrt(disc)
		t0 = math.max(0, (-b - root) / (2 * a))
		t1 = math.min(1, (-b + root) / (2 * a))
	else
		-- Liang-Barsky against -r..r on both axes.
		local p = { -dx, dx, -dy, dy }
		local q = { x1 + r, r - x1, y1 + r, r - y1 }
		for i = 1, 4 do
			if p[i] == 0 then
				if q[i] < 0 then
					return nil
				end
			else
				local t = q[i] / p[i]
				if p[i] < 0 then
					t0 = math.max(t0, t)
				else
					t1 = math.min(t1, t)
				end
			end
		end
	end
	if t0 >= t1 then
		return nil
	end
	return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end
