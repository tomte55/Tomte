local addonName, ns = ...

-- Edit Mode snapping: pure logic (no WoW API calls; unit-tested in tests/test_editmode.lua). EditMode.lua reads the
-- rects (Blizzard's elements, Tomte's widgets, the screen, Blizzard's grid lines) and moves the widget.
--
-- The rules follow Blizzard's EditModeMagnetismManager: per axis, the closest line within range wins. A dragged
-- widget lines its sides or center up with the screen's sides and center and with the grid lines, and with the
-- sides and center of a neighbouring element (one it overlaps or nearly touches on the other axis), or butts up
-- against it.
--
-- Rects are { left, right, bottom, top } in one coordinate space (EditMode.lua uses UIParent's).

local LEFT, RIGHT, BOTTOM, TOP = 1, 2, 3, 4 -- indexes into a rect

local function Center(a, b)
	return (a + b) / 2
end

-- Keeps the closest (target - source) pair within range in best = { distance, offset, line }.
local function Consider(best, source, target, range)
	local distance = math.abs(target - source)
	if distance <= range and (not best.distance or distance < best.distance) then
		best.distance, best.offset, best.line = distance, target - source, target
	end
end

-- Whether [lo1, hi1] and [lo2, hi2] overlap or come within range of each other.
local function Near(lo1, hi1, lo2, hi2, range)
	return lo1 <= hi2 + range and lo2 <= hi1 + range
end

-- One axis: lo/hi are the box's sides on it (left/right or bottom/top); the other axis decides which elements are
-- neighbours. Returns the offset to move by (0 when nothing is in range) and the line it snaps to (nil then).
local function SnapAxis(box, screen, frames, lines, range, lo, hi, otherLo, otherHi)
	local best = {}
	local boxLo, boxHi = box[lo], box[hi]
	local boxMid = Center(boxLo, boxHi)

	local screenMid = Center(screen[lo], screen[hi])
	Consider(best, boxLo, screen[lo], range)
	Consider(best, boxHi, screen[hi], range)
	Consider(best, boxMid, screenMid, range)
	Consider(best, boxLo, screenMid, range)
	Consider(best, boxHi, screenMid, range)

	for _, line in ipairs(lines or {}) do
		Consider(best, boxLo, line, range)
		Consider(best, boxHi, line, range)
		Consider(best, boxMid, line, range)
	end

	for _, f in ipairs(frames or {}) do
		if Near(box[otherLo], box[otherHi], f[otherLo], f[otherHi], range) then
			Consider(best, boxLo, f[hi], range) -- butt up on its far side
			Consider(best, boxHi, f[lo], range) -- butt up on its near side
			Consider(best, boxLo, f[lo], range)
			Consider(best, boxHi, f[hi], range)
			Consider(best, boxMid, Center(f[lo], f[hi]), range)
		end
	end

	return best.offset or 0, best.line
end

-- box: the widget's rect; screen: the screen's rect; frames: rects of the elements it can snap to; gridX / gridY: x of
-- the vertical and y of the horizontal grid lines (nil when the grid is hidden); range: how close a line has to be.
-- Returns dx, dy to move the widget by, and the x of the vertical and y of the horizontal line it snapped to (nil
-- on an axis that didn't snap).
local function SnapOffset(box, screen, frames, gridX, gridY, range)
	local dx, lineX = SnapAxis(box, screen, frames, gridX, range, LEFT, RIGHT, BOTTOM, TOP)
	local dy, lineY = SnapAxis(box, screen, frames, gridY, range, BOTTOM, TOP, LEFT, RIGHT)
	return dx, dy, lineX, lineY
end
ns.EditMode_SnapOffset = SnapOffset

-- Keeps a move within [lo, hi]; a widget bigger than the screen keeps its low side on screen.
local function Clamp(move, lo, hi)
	if hi < lo then
		return lo
	end
	return math.max(lo, math.min(hi, move))
end

-- Where a dragged widget goes: start is its rect when the drag began, moveX / moveY how far the cursor has moved
-- since, targets = { snap, clamp, screen, frames, gridX, gridY, range } (snap: Edit Mode's Snap checkbox; clamp:
-- the widget is clamped to the screen). Returns the total dx, dy from the start and, as SnapOffset, the lines it
-- snapped to (a clamp that pushes it off a line drops that line).
function ns.EditMode_DragOffset(start, moveX, moveY, targets)
	local lineX, lineY
	if targets.snap then
		local box = { start[LEFT] + moveX, start[RIGHT] + moveX, start[BOTTOM] + moveY, start[TOP] + moveY }
		local dx, dy
		dx, dy, lineX, lineY = SnapOffset(box, targets.screen, targets.frames, targets.gridX, targets.gridY,
			targets.range)
		moveX, moveY = moveX + dx, moveY + dy
	end
	if targets.clamp then
		local screen = targets.screen
		local x = Clamp(moveX, screen[LEFT] - start[LEFT], screen[RIGHT] - start[RIGHT])
		local y = Clamp(moveY, screen[BOTTOM] - start[BOTTOM], screen[TOP] - start[TOP])
		if x ~= moveX then
			lineX = nil
		end
		if y ~= moveY then
			lineY = nil
		end
		moveX, moveY = x, y
	end
	return moveX, moveY, lineX, lineY
end
