-- Run from the AddOns folder: lua Tomte/tests/test_editmode.lua
local ns = {}
assert(loadfile("Tomte/Core/EditModeData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local Snap = ns.EditMode_SnapOffset
local SCREEN = { 0, 1000, 0, 600 }
local RANGE = 8

test("nothing in range leaves the widget where it is", function()
	local dx, dy = Snap({ 200, 300, 200, 250 }, SCREEN, {}, nil, nil, RANGE)
	eq(dx, 0, "dx")
	eq(dy, 0, "dy")
end)

test("snaps to the screen's sides and center", function()
	local dx, dy = Snap({ 5, 105, 543, 595 }, SCREEN, {}, nil, nil, RANGE)
	eq(dx, -5, "left side")
	eq(dy, 5, "top side")
	dx, dy = Snap({ 446, 546, 270, 320 }, SCREEN, {}, nil, nil, RANGE)
	eq(dx, 4, "center x")
	eq(dy, 5, "center y")
end)

test("snaps to grid lines only when given", function()
	local box = { 203, 253, 103, 153 }
	local dx, dy = Snap(box, SCREEN, {}, nil, nil, RANGE)
	eq(dx, 0, "no grid")
	dx, dy = Snap(box, SCREEN, {}, { 100, 200, 300 }, { 100, 200 }, RANGE)
	eq(dx, -3, "grid x")
	eq(dy, -3, "grid y")
end)

test("butts up against a neighbour and lines up with its top", function()
	local bar = { 300, 600, 100, 140 }
	-- Dropped just right of the bar, a little lower than its top.
	local dx, dy = Snap({ 604, 704, 92, 137 }, SCREEN, { bar }, nil, nil, RANGE)
	eq(dx, -4, "left side onto the bar's right side")
	eq(dy, 3, "top onto the bar's top")
end)

test("ignores elements that aren't neighbours on the other axis", function()
	local far = { 300, 600, 400, 440 }
	local dx = Snap({ 604, 704, 92, 137 }, SCREEN, { far }, nil, nil, RANGE)
	eq(dx, 0, "far above, no snap to its side")
end)

test("the closest line wins", function()
	local dx = Snap({ 203, 253, 300, 350 }, SCREEN, {}, { 200, 205 }, nil, RANGE)
	eq(dx, 2, "205 is closer than 200")
end)

local Drag = ns.EditMode_DragOffset
local function Targets(snap, clamp, frames)
	return { snap = snap, clamp = clamp, screen = SCREEN, frames = frames or {}, range = RANGE }
end

test("a drag follows the cursor when nothing is in range", function()
	local dx, dy = Drag({ 200, 300, 200, 250 }, 40, -30, Targets(true, false))
	eq(dx, 40, "dx")
	eq(dy, -30, "dy")
end)

test("a drag sticks to a line while within range and lets go past it", function()
	local bar = { 300, 600, 100, 140 }
	local start = { 650, 750, 100, 140 }
	local dx = Drag(start, -44, 0, Targets(true, false, { bar }))
	eq(dx, -50, "pulled flush 6 short of the bar")
	dx = Drag(start, -40, 0, Targets(true, false, { bar }))
	eq(dx, -40, "10 away: free")
end)

test("a drag reports the lines it snapped to", function()
	local bar = { 300, 600, 100, 140 }
	local _, _, lineX, lineY = Drag({ 650, 750, 103, 143 }, -44, 0, Targets(true, false, { bar }))
	eq(lineX, 600, "the bar's right side")
	eq(lineY, 100, "the bar's bottom")
	_, _, lineX, lineY = Drag({ 650, 750, 200, 240 }, -40, 0, Targets(true, false, { bar }))
	eq(lineX, nil, "free on x")
	eq(lineY, nil, "free on y")
end)

test("a clamp that pushes a widget off its line drops the line", function()
	local _, _, lineX = Drag({ 900, 980, 200, 240 }, 120, 0, Targets(true, true, { { 1000, 1100, 200, 240 } }))
	eq(lineX, nil, "snapped past the screen edge, clamped back")
end)

test("a drag doesn't snap with Snap off", function()
	local dx = Drag({ 650, 750, 100, 140 }, -44, 0, Targets(false, false, { { 300, 600, 100, 140 } }))
	eq(dx, -44, "dx")
end)

test("a clamped widget stays on screen", function()
	local dx, dy = Drag({ 900, 980, 500, 580 }, 100, 100, Targets(false, true))
	eq(dx, 20, "stops at the right side")
	eq(dy, 20, "stops at the top")
	dx = Drag({ 900, 980, 500, 580 }, 100, 0, Targets(false, false))
	eq(dx, 100, "unclamped goes off screen")
end)

H.done()
