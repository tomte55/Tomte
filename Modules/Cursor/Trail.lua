local addonName, ns = ...

-- Cursor highlight: the trail behind the cursor. Flat shapes are pooled textures (or pooled lines for the ribbon) at
-- the trail's points; a spell effect is one Blizzard model at the cursor whose particles stay behind as it moves.
-- Driven by Cursor.lua's OnUpdate (registered there); pure rules (points, sizes, when it shows, colors, the shape
-- and effect lists) in Data.lua. The settings preview's still trail is drawn here too (Cursor_TrailSample).

local ART = ns.Theme.MEDIA .. "Cursor\\"
local MAX_POINTS = 48 -- pool size; a point's life usually ends the trail long before the mouse lays this many
local STILL = 0.5 -- UI units: a smaller step between two looks counts as a still mouse
local RIBBON_WIDTH = 0.5 -- the ribbon's thickness, times the head size
local HEAD_REFERENCE = 14 -- the head size (the default) the spell effects' scales in Data.lua are meant for
-- Both holders draw in the TOOLTIP strata, above every window; the ring's holder sits a level above the trail's.
local TRAIL_LEVEL = 5

-- The settings preview's still trail (Cursor_TrailSample): the cursor sweeps an arc of SAMPLE_RADIUS at SAMPLE_SPEED
-- for SAMPLE_SECONDS (longer than the longest Length), looked at SAMPLE_RATE times a second as the driver would.
local SAMPLE_SPEED = 300 -- UI units per second: an easy sweep of the hand
local SAMPLE_RADIUS = 170
local SAMPLE_SECONDS = 1.3
local SAMPLE_RATE = 120

local holder, model
-- The flat trail's drawing target: frame (what points are placed on: the screen holder, made on first need, or a
-- preview's frame), sprites and lines (pooled textures and ribbon lines by slot; see Slot), art (the art the pooled
-- textures show now).
local live = { sprites = {}, lines = {} }
local points, fade = {}, {}
local lastX, lastY, lastMove
local modelFile -- the model file shown, nil while the model is hidden and cleared
local translation, rotation -- reused vectors for SetTransform

-- Flat shapes --------------------------------------------------------------------------------------------------

local function Holder()
	if not holder then
		-- Covers the screen so points can be placed by cursor position; never takes the mouse.
		holder = CreateFrame("Frame", nil, UIParent)
		holder:SetAllPoints(UIParent)
		holder:SetFrameStrata("TOOLTIP")
		holder:SetFrameLevel(TRAIL_LEVEL)
		holder:EnableMouse(false)
		live.frame = holder
	end
	return holder
end

local function Sprite(target, i)
	local s = target.sprites[i]
	if not s then
		s = target.frame:CreateTexture(nil, "ARTWORK")
		s:SetTexture(ART .. target.art)
		s:SetBlendMode("ADD")
		target.sprites[i] = s
	end
	return s
end

local function Line(target, i)
	local l = target.lines[i]
	if not l then
		l = target.frame:CreateLine(nil, "ARTWORK")
		l:SetColorTexture(1, 1, 1, 1) -- white, tinted per segment with SetVertexColor
		target.lines[i] = l
	end
	return l
end

-- Each point keeps one pool entry for its whole life: the slot from its serial number. Points alive at once have
-- consecutive serials and are never more than MAX_POINTS, so they never share a slot. An entry is placed and colored
-- once (entry.n: the point it shows, nil while hidden); after that only its size and opacity change per frame.
local function Slot(p)
	return p.n % MAX_POINTS + 1
end

-- Hides the entries not showing a point from serial `first` to `last` (1, 0 hides all).
local function HideStale(pool, first, last)
	for k = 1, MAX_POINTS do
		local e = pool[k]
		if e and e.n and (e.n < first or e.n > last) then
			e:Hide()
			e.n, e.endN, e.size = nil, nil, nil
		end
	end
end

-- The flat trail of points (with their strengths in fade) on target; the shape pieces, or the ribbon.
local function DrawSprites(target, points, fade, db, palette, shape, now, gate)
	local sprites = target.sprites
	if target.art ~= shape.art then
		target.art = shape.art
		HideStale(sprites, 1, 0) -- placed again with the new shape's turn
		for _, s in pairs(sprites) do
			s:SetTexture(ART .. target.art)
		end
	end
	local anchor = target.frame
	for i, p in ipairs(points) do
		local s = Sprite(target, Slot(p))
		if s.n ~= p.n then
			s.n, s.size = p.n, nil
			s:SetPoint("CENTER", anchor, "BOTTOMLEFT", p.x, p.y)
			s:SetVertexColor(ns.Cursor_Color(db.color, palette, p.t)) -- the rainbow takes the time it was placed
			s:SetRotation(0)
			s:Show()
		end
		local age = now - p.t
		local size, alpha = ns.Cursor_TrailLook(fade[i], db.trailSize, db.trailTaper, db.trailOpacity)
		if shape.twinkle then
			local k = ns.Cursor_Twinkle(p.n, age)
			size, alpha = size * k, alpha * k
		end
		if shape.spin then
			s:SetRotation(ns.Cursor_Spin(p.n, age))
		end
		if s.size ~= size then
			s.size = size
			s:SetSize(size, size)
		end
		s:SetAlpha(alpha * gate)
	end
	HideStale(sprites, points[1].n, points[#points].n)
	HideStale(target.lines, 1, 0)
end

-- A line from each point to the next and from the newest point to the cursor, as thick as the newer end's size.
local function DrawRibbon(target, points, fade, db, palette, now, x, y, gate)
	local anchor = target.frame
	for i = 1, #points do
		local p, q = points[i], points[i + 1]
		local l = Line(target, Slot(p))
		if l.n ~= p.n then
			l.n, l.endN = p.n, nil
			l:SetStartPoint("BOTTOMLEFT", anchor, p.x, p.y)
			l:Show()
		end
		if q then
			if l.endN ~= q.n then
				l.endN = q.n
				l:SetEndPoint("BOTTOMLEFT", anchor, q.x, q.y)
				l:SetVertexColor(ns.Cursor_Color(db.color, palette, q.t))
			end
		else
			-- The head segment follows the cursor.
			l.endN = nil
			l:SetEndPoint("BOTTOMLEFT", anchor, x, y)
			l:SetVertexColor(ns.Cursor_Color(db.color, palette, now))
		end
		local f = q and fade[i + 1] or fade[i] -- the head segment fades with the newest point once the mouse rests
		local size, alpha = ns.Cursor_TrailLook(f, db.trailSize, db.trailTaper, db.trailOpacity)
		l:SetThickness(math.max(1, size * RIBBON_WIDTH))
		l:SetAlpha(alpha * gate)
	end
	HideStale(target.lines, points[1].n, points[#points].n)
	HideStale(target.sprites, 1, 0)
end

local function Hide2D()
	HideStale(live.sprites, 1, 0)
	HideStale(live.lines, 1, 0)
end

-- Draws the flat trail; returns whether anything is left to draw (false: the trail has faded out).
local function Update2D(db, palette, now, x, y, gate, moved)
	if moved then
		ns.Cursor_TrailAdd(points, now, x, y, db.trailGap, MAX_POINTS)
	end
	ns.Cursor_TrailFade(points, now, db.trailLife, fade)
	if not points[1] then
		Hide2D()
		return false
	end
	local shape = ns.Cursor_Find(ns.CURSOR_TRAIL_SHAPES, db.trailShape)
	Holder()
	if shape.art then
		DrawSprites(live, points, fade, db, palette, shape, now, gate)
	else
		DrawRibbon(live, points, fade, db, palette, now, x, y, gate)
	end
	return true
end

-- A still flat trail for a settings preview (Panel/Preview.lua): the points the trail would hold right after the
-- cursor swept an arc, drawn into host by the same code as the real trail. s: the trail settings (color,
-- trailShape, trailSize, trailOpacity, trailLife, trailGap, trailTaper); palette as for Cursor_TrailUpdate.
-- Returns the width and height drawn.
function ns.Cursor_TrailSample(host, s, palette)
	local target = host.trailSample
	if not target then
		target = { frame = CreateFrame("Frame", nil, host), sprites = {}, lines = {} }
		target.frame:SetSize(1, 1)
		host.trailSample = target
	end
	-- A new set of points numbered from 1 again, maybe in other settings: everything is placed anew.
	HideStale(target.sprites, 1, 0)
	HideStale(target.lines, 1, 0)
	local pts, strengths = {}, {}
	local now, x, y = 0, 0, 0
	for step = 0, SAMPLE_SECONDS * SAMPLE_RATE do
		now = step / SAMPLE_RATE
		local turn = SAMPLE_SPEED * now / SAMPLE_RADIUS
		x, y = SAMPLE_RADIUS * math.sin(turn), SAMPLE_RADIUS * (1 - math.cos(turn))
		ns.Cursor_TrailAdd(pts, now, x, y, s.trailGap, MAX_POINTS)
	end
	ns.Cursor_TrailFade(pts, now, s.trailLife, strengths)
	-- The box around what shows (the points and the cursor), with room for a fresh point's half size.
	local minX, maxX, minY, maxY = x, x, y, y
	for _, p in ipairs(pts) do
		minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
		minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
	end
	local margin = s.trailSize / 2 + 2
	local w, h = maxX - minX + 2 * margin, maxY - minY + 2 * margin
	-- Points are placed from the frame's bottom-left: put (minX, minY) margin in from host's bottom-left corner.
	target.frame:ClearAllPoints()
	target.frame:SetPoint("BOTTOMLEFT", host, "TOPLEFT", margin - minX, margin - h - minY)
	local shape = ns.Cursor_Find(ns.CURSOR_TRAIL_SHAPES, s.trailShape)
	if shape.art then
		DrawSprites(target, pts, strengths, s, palette, shape, now, 1)
	else
		DrawRibbon(target, pts, strengths, s, palette, now, x, y, 1)
	end
	return w, h
end

-- Spell effect -------------------------------------------------------------------------------------------------

-- Hidden and cleared, so a model that isn't shown costs nothing.
local function HideModel()
	if modelFile then
		model:ClearModel()
		model:Hide()
		modelFile = nil
	end
end

-- Placement as measured by the CursorTrail addon (see CURSOR_EFFECTS in Data.lua): a PlayerModel covering the
-- screen with custom camera 1 and the model's center as its origin takes SetTransform positions from the screen's
-- bottom-left corner in fractions of the screen's diagonal, the same on any screen size and UI scale.
local function ShowModel(effect)
	if not model then
		model = CreateFrame("PlayerModel", nil, UIParent)
		model:SetAllPoints(UIParent)
		model:SetFrameStrata("TOOLTIP")
		model:SetFrameLevel(TRAIL_LEVEL)
		model:EnableMouse(false)
		translation, rotation = CreateVector3D(0, 0, 0), CreateVector3D(0, 0, 0)
	end
	model:Show()
	model:SetModel(effect.file)
	model:SetCustomCamera(1)
	model:UseModelCenterToTransform(true)
	modelFile = effect.file
end

-- Keeps the effect at the cursor; returns whether it's shown. It fades out once the mouse rests.
local function UpdateModel(db, now, x, y, gate)
	local visible = lastMove and ns.Cursor_IdleFade(now - lastMove) or 0
	if visible <= 0 then
		HideModel()
		return false
	end
	local effect = ns.Cursor_Find(ns.CURSOR_EFFECTS, db.trailEffect)
	if modelFile ~= effect.file then
		ShowModel(effect)
	end
	local w, h = UIParent:GetSize()
	local diagonal = math.sqrt(w * w + h * h) -- x and y are UI units too, so UIParent's scale cancels out
	translation:SetXYZ(x / diagonal, y / diagonal, 0)
	local turn = effect.turn
	rotation:SetXYZ(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
	model:SetTransform(translation, rotation, effect.scale * db.trailSize / HEAD_REFERENCE)
	model:SetAlpha(gate * visible * db.trailOpacity)
	return true
end

-- Driver -------------------------------------------------------------------------------------------------------

-- Hides and forgets everything (the trail turned off or stopped showing, a setting changed, the module stopped).
function ns.Cursor_TrailClear()
	wipe(points)
	wipe(fade)
	Hide2D()
	HideModel()
	lastMove = nil
end

-- One look at the cursor (x, y in UI units) at `now`. gate: how strongly the trail shows (ns.Cursor_TrailGate;
-- 0 clears it). palette: the colors for ns.Cursor_Color. Returns whether the trail still draws something, so the
-- driver keeps calling every frame; false once it has faded out and the mouse is still.
function ns.Cursor_TrailUpdate(db, palette, now, x, y, gate)
	-- The last position is followed while the trail is gated off too, so a trail that starts showing under a still
	-- mouse (the ring popping up, combat starting) stays empty.
	local moved = not lastX or math.abs(x - lastX) > STILL or math.abs(y - lastY) > STILL
	lastX, lastY = x, y
	if gate <= 0 then
		if lastMove or points[1] or modelFile then
			ns.Cursor_TrailClear()
		end
		return false
	end
	if moved then
		lastMove = now
	end
	if db.trailStyle == "effect" then
		if points[1] then
			wipe(points)
			Hide2D()
		end
		return UpdateModel(db, now, x, y, gate)
	end
	HideModel()
	return Update2D(db, palette, now, x, y, gate, moved)
end
