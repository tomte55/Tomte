local addonName, ns = ...

-- Cursor highlight: the trail behind the cursor. Flat shapes are pooled textures (or pooled lines for the ribbon) at
-- the trail's points; a spell effect is one Blizzard model at the cursor whose particles stay behind as it moves.
-- Driven by Cursor.lua's OnUpdate (registered there); pure rules (points, sizes, when it shows, colors, the shape
-- and effect lists) in Data.lua.

local ART = ns.Theme.MEDIA .. "Cursor\\"
local MAX_POINTS = 48 -- pool size; a point's life usually ends the trail long before the mouse lays this many
local STILL = 0.5 -- UI units: a smaller step between two looks counts as a still mouse
local RIBBON_WIDTH = 0.5 -- the ribbon's thickness, times the head size
local HEAD_REFERENCE = 14 -- the head size (the default) the spell effects' scales in Data.lua are meant for
-- Both holders draw in the TOOLTIP strata, above every window; the ring's holder sits a level above the trail's.
local TRAIL_LEVEL = 5

local holder, model
local sprites, lines = { shown = 0 }, { shown = 0 } -- pooled textures and ribbon lines; shown: see HideFrom
local spriteArt -- the art the pooled textures show now
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
	end
	return holder
end

local function Sprite(i)
	local s = sprites[i]
	if not s then
		s = Holder():CreateTexture(nil, "ARTWORK")
		s:SetTexture(ART .. spriteArt)
		s:SetBlendMode("ADD")
		sprites[i] = s
	end
	return s
end

local function Line(i)
	local l = lines[i]
	if not l then
		l = Holder():CreateLine(nil, "ARTWORK")
		l:SetColorTexture(1, 1, 1, 1) -- white, tinted per segment with SetVertexColor
		lines[i] = l
	end
	return l
end

-- Hides pool entries from `first` on. pool.shown is how many may be shown, so a trail that has faded out costs no
-- calls on later looks.
local function HideFrom(pool, first)
	for i = first, pool.shown do
		pool[i]:Hide()
	end
	if pool.shown >= first then
		pool.shown = first - 1
	end
end

local function DrawSprites(db, palette, shape, now, gate)
	if spriteArt ~= shape.art then
		spriteArt = shape.art
		for _, s in ipairs(sprites) do
			s:SetTexture(ART .. spriteArt)
		end
	end
	local anchor = Holder()
	for i, p in ipairs(points) do
		local age = now - p.t
		local size, alpha = ns.Cursor_TrailLook(fade[i], db.trailSize, db.trailTaper, db.trailOpacity)
		if shape.twinkle then
			local k = ns.Cursor_Twinkle(p.n, age)
			size, alpha = size * k, alpha * k
		end
		local s = Sprite(i)
		s:SetRotation(shape.spin and ns.Cursor_Spin(p.n, age) or 0)
		s:SetVertexColor(ns.Cursor_Color(db.color, palette, p.t))
		s:SetSize(size, size)
		s:SetPoint("CENTER", anchor, "BOTTOMLEFT", p.x, p.y)
		s:SetAlpha(alpha * gate)
		s:Show()
	end
	HideFrom(sprites, #points + 1)
	sprites.shown = #points
	HideFrom(lines, 1)
end

-- A line from each point to the next and from the newest point to the cursor, as thick as the newer end's size.
local function DrawRibbon(db, palette, now, x, y, gate)
	local anchor = Holder()
	local n = #points
	for i = 1, n do
		local p, q = points[i], points[i + 1]
		local f = q and fade[i + 1] or fade[i] -- the head segment fades with the newest point once the mouse rests
		local qx, qy = q and q.x or x, q and q.y or y
		local size, alpha = ns.Cursor_TrailLook(f, db.trailSize, db.trailTaper, db.trailOpacity)
		local l = Line(i)
		l:SetStartPoint("BOTTOMLEFT", anchor, p.x, p.y)
		l:SetEndPoint("BOTTOMLEFT", anchor, qx, qy)
		l:SetThickness(math.max(1, size * RIBBON_WIDTH))
		l:SetVertexColor(ns.Cursor_Color(db.color, palette, q and q.t or now))
		l:SetAlpha(alpha * gate)
		l:Show()
	end
	HideFrom(lines, n + 1)
	lines.shown = n
	HideFrom(sprites, 1)
end

local function Hide2D()
	HideFrom(sprites, 1)
	HideFrom(lines, 1)
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
	if shape.art then
		DrawSprites(db, palette, shape, now, gate)
	else
		DrawRibbon(db, palette, now, x, y, gate)
	end
	return true
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
