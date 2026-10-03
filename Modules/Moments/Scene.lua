local addonName, ns = ...

-- Moment scene for the cinematic engine: top band = title card (spaced label, title, gold line,
-- subtitle), bottom band = the moment's icon and one line of detail. A creature (new mount, battle pet,
-- tamed pet) gets a reveal in the middle of the screen: the world dims, a flash, and the model pops in on
-- a glow. Its tier (ns.MOMENT_TIER_FX) adds rays, a spin-in, sparkles, a build-up and sounds.

local GOLD, GREY, WHITE = ns.SCENE_GOLD, ns.SCENE_GREY, ns.SCENE_WHITE
local TURN_SPEED = 0.25 -- radians per second, once the model has settled
local SPIN_SPEED = 14 -- extra radians per second at the reveal (rare and up), decays quickly
local SPIN_DECAY = 3
local ICON = 30
local GLOW_TEXTURE = 132039 -- Interface\GLUES\MODELS\UI_Tauren\gradientCircle
local STARGLOW_ATLAS = "LegendaryToast-OrangeStarglow"
local DIM_ALPHA = 0.6
local DIM_IN = 0.4 -- seconds the world takes to dim before the reveal
local POP_TIME = 0.6 -- model scale-in
local BURST_TIME = 0.7
local RAY_COUNT = 18
local RAY_SPEED = 0.08 -- radians per second
local RAY_FADE = 1.2
local SPARK_COUNT = 32
local SPARK_RATE = 14 -- per second
local SOUND_STOP_FADE = 500 -- ms, when the moment is dismissed early
-- Our own camera on the model scene (radians), a little above the model looking down. It's fitted with the
-- game's own projection (Project3DPointTo2D), which also tells where the feet are on screen.
local CAMERA_FOV = 0.5
local CAMERA_PITCH = 0.3
local CAMERA_FIT = 0.85 -- the model's farthest point from the center, as a share of the frame's half size
local FIT_PASSES = 3
local PEDESTAL_SCALE = 1.5 -- of the ring the model's feet turn on
local PEDESTAL_MIN_FLAT = 0.18 -- height/width at least, so it stays visible
local FIT_TIMEOUT = 1.5 -- seconds: a model that reports no size by then is shown with a guessed one
local GUESS_BOX = { -1, -1, 0, 1, 1, 2 }

local Text, Place, SetText = ns.SceneText, ns.ScenePlace, ns.SceneSetText
local TWO_PI = 2 * math.pi

local card, stage
local reveal -- per-moment reveal state, nil without a model

local scene = {}
ns.MomentScene = scene

local function Additive(parent, layer, sub)
	local tex = parent:CreateTexture(nil, layer, nil, sub)
	tex:SetBlendMode("ADD")
	return tex
end

local function Glow(parent, layer, sub)
	local tex = Additive(parent, layer, sub)
	tex:SetTexture(GLOW_TEXTURE)
	return tex
end

-- Thin beams around the center. Gradient textures ignore their own alpha: a layer fades as a frame.
local function CreateRays(parent)
	local layer = CreateFrame("Frame", nil, parent)
	layer:SetAllPoints(parent)
	layer.rays = {}
	for i = 1, RAY_COUNT do
		local ray = Additive(layer, "BACKGROUND", 2)
		ray:SetColorTexture(1, 1, 1, 1)
		layer.rays[i] = ray
	end
	return layer
end

local function ColorRays(layer, color, strength)
	for i, ray in ipairs(layer.rays) do
		local a = (i % 3 == 0) and strength or strength * 0.55
		ray:SetGradient("VERTICAL", CreateColor(color[1], color[2], color[3], a), CreateColor(color[1], color[2], color[3], 0))
	end
end

local function SizeRays(layer, inner, length)
	layer.inner, layer.length = inner, length
	for i, ray in ipairs(layer.rays) do
		local long = (i % 2 == 0) and 1 or 0.7
		ray:SetSize((i % 3 == 0) and 7 or 3, length * long)
		ray.long = long
	end
end

-- Each ray starts at `inner` from the center and points outward; the texture's top is its outer end.
local function PlaceRays(layer, angle)
	for i, ray in ipairs(layer.rays) do
		local theta = angle + (i - 1) * TWO_PI / RAY_COUNT
		local d = layer.inner + layer.length * ray.long / 2
		ray:SetPoint("CENTER", stage, "CENTER", math.cos(theta) * d, math.sin(theta) * d)
		ray:SetRotation(theta - math.pi / 2)
	end
end

local function CreateStage(parent, letterbox)
	stage = CreateFrame("Frame", nil, parent)
	stage:SetAllPoints(letterbox)
	stage:SetAlpha(0)

	stage.dim = stage:CreateTexture(nil, "BACKGROUND", nil, -8)
	stage.dim:SetColorTexture(0, 0, 0, 1)
	stage.dim:SetAllPoints(stage)

	stage.starglow = Additive(stage, "BACKGROUND", 0)
	stage.starglow:SetPoint("CENTER")
	stage.hasStarglow = C_Texture.GetAtlasInfo(STARGLOW_ATLAS) ~= nil
	if stage.hasStarglow then
		stage.starglow:SetAtlas(STARGLOW_ATLAS)
		stage.starglow:SetDesaturated(true)
	end
	stage.glow = Glow(stage, "BACKGROUND", 1)
	stage.glow:SetPoint("CENTER")
	stage.raysA = CreateRays(stage)
	stage.raysB = CreateRays(stage)

	stage.model = CreateFrame("ModelScene", nil, stage)
	stage.model:SetPoint("CENTER")
	stage.model:SetFrameLevel(stage:GetFrameLevel() + 3)
	stage.model:SetCameraFieldOfView(CAMERA_FOV)
	stage.actor = stage.model:CreateActor()
	-- Turns around its middle, feet at height 0 (the default can be the model's center).
	stage.actor:SetUseCenterForOrigin(true, true, false)
	-- Behind the model (the feet stand on it), placed once the model is measured.
	stage.pedestal = Glow(stage, "BACKGROUND", 3)

	-- Above the model: flash and burst cover it.
	local front = CreateFrame("Frame", nil, stage)
	front:SetAllPoints(stage)
	front:SetFrameLevel(stage:GetFrameLevel() + 5)
	stage.burst = Glow(front, "OVERLAY", 0)
	stage.burst:SetPoint("CENTER")
	stage.flash = Additive(front, "OVERLAY", 1)
	stage.flash:SetColorTexture(1, 1, 1, 1)
	stage.flash:SetAllPoints(stage)
	stage.sparks = {}
	for i = 1, SPARK_COUNT do
		local spark = Glow(front, "ARTWORK", 1)
		spark:Hide()
		stage.sparks[i] = spark
	end
end

function scene.Create(parent, letterbox)
	CreateStage(parent, letterbox)

	card = CreateFrame("Frame", nil, parent)
	card:SetAllPoints(letterbox)
	card:SetFrameLevel(letterbox:GetFrameLevel() + 10)
	card:SetAlpha(0)

	card.title = Text(card, 36, GOLD, ns.SCENE_TITLE_FONT)
	Place(card, card.title, "TOP", letterbox.top, "CENTER", 0, 22)
	card.label = Text(card, 12, GREY)
	Place(card, card.label, "TOP", letterbox.top, "CENTER", 0, 40)
	card.line = ns.SceneGoldLine(card, 300)
	Place(card, card.line, "TOPRIGHT", letterbox.top, "CENTER", 0, -19)
	card.subtitle = Text(card, 14, GREY)
	Place(card, card.subtitle, "TOP", letterbox.top, "CENTER", 0, -26)

	card.icon = card:CreateTexture(nil, "OVERLAY")
	card.icon:SetSize(ICON, ICON)
	card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	Place(card, card.icon, "TOP", letterbox.bottom, "CENTER", 0, 30)
	card.iconBorder = card:CreateTexture(nil, "ARTWORK")
	card.iconBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
	card.iconBorder:SetPoint("TOPLEFT", card.icon, -1, 1)
	card.iconBorder:SetPoint("BOTTOMRIGHT", card.icon, 1, -1)
	card.detail = Text(card, 13, WHITE)
	card.detail:SetWidth(700)
	Place(card, card.detail, "TOP", letterbox.bottom, "CENTER", 0, -8)
end

-- h = screen height in the stage's units (the stage may not be laid out yet on its first use).
local function SetupStage(fx, h)
	local glow = fx.glow
	reveal.size = math.floor(h * 0.62)
	stage.glow:SetSize(h * 0.75, h * 0.75)
	stage.glow:SetVertexColor(glow[1], glow[2], glow[3])
	stage.starglow:SetSize(h * 1.1, h * 1.1)
	stage.starglow:SetVertexColor(glow[1], glow[2], glow[3])
	stage.starglow:SetShown(stage.hasStarglow and fx.rays or false)
	stage.pedestal:SetVertexColor(glow[1], glow[2], glow[3])
	stage.burst:SetVertexColor(1, 1, 1)
	SizeRays(stage.raysA, h * 0.08, h * 0.5)
	SizeRays(stage.raysB, h * 0.12, h * 0.42)
	ColorRays(stage.raysA, glow, 0.7)
	ColorRays(stage.raysB, { 1, 1, 1 }, 0.45)
	stage.raysA:SetShown(fx.rays or false)
	stage.raysB:SetShown(fx.doubleRays or false)
	stage.raysA:SetAlpha(0)
	stage.raysB:SetAlpha(0)
	for _, spark in ipairs(stage.sparks) do
		spark:Hide()
		spark.age = nil
	end
	stage.flash:SetAlpha(0)
	stage.burst:SetAlpha(0)
	-- Hidden and empty until the reveal: a model frame shown again draws its last model for a frame.
	stage.actor:SetAlpha(0)
	stage.actor:ClearModel()
	stage.model:Hide()
	stage.pedestal:SetAlpha(0)
end

-- A point in the model's space on the model frame, as fractions of the frame's half size from its
-- center (x right, y up). nil when it isn't on screen. The projection is in pixels from the frame's
-- bottom left.
local function Project(x, y, z)
	local scene = stage.model
	local px, py = scene:Project3DPointTo2D(x, y, z)
	local half = scene:GetWidth() * scene:GetEffectiveScale() / 2
	if not (px and py) or half <= 0 then
		return nil
	end
	return (px - half) / half, (py - half) / half
end

-- Fits the camera to the loaded model and works out where its feet are. The model turns around its
-- middle with its feet at z = 0, so only the box's size counts: the camera looks at its middle and backs
-- off until the top, feet and the circle its corners turn on (`ring`) fill CAMERA_FIT of the frame.
-- Returns false while the model has no size yet. guess = use GUESS_BOX instead (no pedestal).
local function FitCamera(guess)
	local bx, by, bz, tx, ty, tz
	if guess then
		bx, by, bz, tx, ty, tz = unpack(GUESS_BOX)
	else
		bx, by, bz, tx, ty, tz = stage.actor:GetActiveBoundingBox()
	end
	if not (bx and tz) or tz - bz <= 0 then
		return false
	end
	local halfW, halfD = (tx - bx) / 2, (ty - by) / 2
	local ring = math.sqrt(halfW * halfW + halfD * halfD)
	local halfHeight = (tz - bz) / 2
	local radius = math.sqrt(ring * ring + halfHeight * halfHeight)

	local scene = stage.model
	scene:SetCameraOrientationByYawPitchRoll(math.pi, CAMERA_PITCH, 0)
	local fx, fy, fz = scene:GetCameraForward()
	if fz > 0 then -- the pitch's sign differs from what we assumed: we want to look down
		scene:SetCameraOrientationByYawPitchRoll(math.pi, -CAMERA_PITCH, 0)
		fx, fy, fz = scene:GetCameraForward()
	end
	local function PlaceCamera(distance)
		scene:SetCameraPosition(-fx * distance, -fy * distance, halfHeight - fz * distance)
	end
	scene:SetLightVisible(true)
	scene:SetLightType(Enum.ModelLightType and Enum.ModelLightType.Directional or 0)
	scene:SetLightDirection(fx, fy, fz)
	scene:SetLightAmbientColor(0.7, 0.7, 0.7)
	scene:SetLightDiffuseColor(0.8, 0.8, 0.8)

	-- Sizes on screen shrink with the distance: a few passes settle it.
	local distance = radius / math.tan(CAMERA_FOV / 2)
	for _ = 1, FIT_PASSES do
		PlaceCamera(distance)
		local _, top = Project(0, 0, 2 * halfHeight)
		local _, feet = Project(0, 0, 0)
		local left = Project(0, -ring, halfHeight)
		local right = Project(0, ring, halfHeight)
		if not (top and feet and left and right) then
			break
		end
		local reach = math.max(math.abs(top), math.abs(feet), math.abs(left), math.abs(right))
		if reach <= 0 then
			break
		end
		distance = distance * reach / CAMERA_FIT
	end
	PlaceCamera(distance)

	-- The pedestal: the ring the feet turn on, seen in perspective.
	local leftX = Project(0, -ring, 0)
	local rightX = Project(0, ring, 0)
	local _, nearY = Project(ring, 0, 0)
	local _, farY = Project(-ring, 0, 0)
	reveal.guessed = guess or not (leftX and rightX and nearY and farY)
	if not reveal.guessed then
		local w = math.abs(rightX - leftX)
		reveal.pedestalW = w
		reveal.pedestalH = math.max(math.abs(nearY - farY), w * PEDESTAL_MIN_FLAT)
		reveal.pedestalY = (nearY + farY) / 2
	end
	return true
end

-- state.moment = { label, title, subtitle, detail, icon, displayID, tier }; state.sound = play the sounds.
function scene.Begin(state)
	local m = state.moment
	local scale = UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale()
	card:SetScale(scale)
	stage:SetScale(scale)
	ns.SceneSnap(card)
	local fx = ns.MOMENT_TIER_FX[m.tier]
	card.label:SetText(ns.Spaced(m.label or ""))
	local labelColor = (fx and m.tier ~= "common") and fx.glow or GREY
	card.label:SetTextColor(labelColor[1], labelColor[2], labelColor[3])
	card.title:SetText(m.title or "")
	SetText(card.subtitle, m.subtitle)
	SetText(card.detail, m.detail)
	card.icon:SetShown(m.icon ~= nil)
	card.iconBorder:SetShown(m.icon ~= nil)
	if m.icon then
		card.icon:SetTexture(m.icon)
	end
	reveal = nil
	stage:SetShown(m.displayID ~= nil)
	stage:SetAlpha(0)
	if m.displayID then
		fx = fx or ns.MOMENT_TIER_FX.common
		reveal = { fx = fx, displayID = m.displayID, sound = state.sound, sounds = {}, h = WorldFrame:GetHeight() / scale }
		SetupStage(fx, reveal.h)
	end
end

local function PlaySounds()
	if not reveal.sound then
		return
	end
	for _, key in ipairs(reveal.fx.sounds) do
		local kit = SOUNDKIT[key]
		if kit then
			local _, handle = PlaySound(kit, "SFX")
			reveal.sounds[#reveal.sounds + 1] = handle
		end
	end
end

local function EaseOutBack(p)
	local c = 1.7
	p = p - 1
	return 1 + (c + 1) * p * p * p + c * p * p
end

local function UpdateSparks(dt, h)
	reveal.sparkDue = (reveal.sparkDue or 0) + dt * SPARK_RATE
	local glow = reveal.fx.glow
	for _, spark in ipairs(stage.sparks) do
		if spark.age then
			spark.age = spark.age + dt
			if spark.age >= spark.life then
				spark.age = nil
				spark:Hide()
			else
				spark.y = spark.y + spark.vy * dt
				spark.x = spark.x + math.sin(spark.age * 2 + spark.phase) * 8 * dt
				spark:SetPoint("CENTER", stage, "CENTER", spark.x, spark.y)
				spark:SetAlpha(math.sin(math.pi * spark.age / spark.life) * 0.9)
			end
		elseif reveal.sparkDue >= 1 then
			reveal.sparkDue = reveal.sparkDue - 1
			spark.age, spark.life, spark.phase = 0, 1.8 + math.random() * 1.4, math.random() * TWO_PI
			spark.x = (math.random() - 0.5) * h * 0.55
			spark.y = -h * 0.28 + math.random() * h * 0.2
			spark.vy = h * (0.06 + math.random() * 0.08)
			local size = 6 + math.random() * 12
			spark:SetSize(size, size)
			local white = math.random() * 0.6
			spark:SetVertexColor(glow[1] + (1 - glow[1]) * white, glow[2] + (1 - glow[2]) * white, glow[3] + (1 - glow[3]) * white)
			spark:SetAlpha(0)
			spark:Show()
		end
	end
end

-- t = seconds since the scene became visible. Before revealAt the world dims (and a legendary charges up);
-- at revealAt: flash, burst, sound, and the model pops in.
local function UpdateReveal(dt)
	local fx, h = reveal.fx, reveal.h
	reveal.t = reveal.t + dt
	local t = reveal.t
	local revealAt = DIM_IN + fx.charge
	stage.dim:SetAlpha(DIM_ALPHA * math.min(t / DIM_IN, 1))

	-- Glow: grows during the charge, then breathes.
	local glowScale, glowAlpha
	if t < revealAt then
		local p = t / revealAt
		glowScale, glowAlpha = 0.3 + 0.5 * p, 0.25 + 0.5 * p
	else
		local since = t - revealAt
		glowScale = 1 + 0.04 * math.sin(since * 1.6)
		glowAlpha = 0.75 + 0.1 * math.sin(since * 1.6)
	end
	local g = h * 0.75 * glowScale
	stage.glow:SetSize(g, g)
	stage.glow:SetAlpha(glowAlpha)

	if stage.starglow:IsShown() then
		local a = t < revealAt and 0.25 * t / revealAt or math.min(0.25 + (t - revealAt) / RAY_FADE * 0.45, 0.7)
		stage.starglow:SetAlpha(a)
		stage.starglow:SetRotation(-t * RAY_SPEED * 0.6)
	end

	if t < revealAt then
		return
	end
	local since = t - revealAt
	if not reveal.revealed then
		reveal.revealed = true
		stage.model:SetSize(reveal.size, reveal.size)
		stage.model:Show()
		stage.actor:SetAlpha(0)
		stage.actor:SetModelByCreatureDisplayID(reveal.displayID) -- set while shown: one set while hidden can stay blank
		reveal.facing = fx.spin and 0 or 0.6
		PlaySounds()
	end
	-- The model pops in once it's loaded and measured (usually right away).
	if not reveal.fitAt and ((stage.actor:IsLoaded() and FitCamera()) or (since > FIT_TIMEOUT and FitCamera(true))) then
		reveal.fitAt = t
	end

	-- Flash and burst.
	local flashTime = fx.bigFlash and 0.8 or 0.5
	stage.flash:SetAlpha(fx.flash * math.max(1 - since / flashTime, 0) ^ 2)
	if since < BURST_TIME then
		local p = since / BURST_TIME
		local size = h * (0.2 + (fx.bigFlash and 2.2 or 1.4) * p)
		stage.burst:SetSize(size, size)
		stage.burst:SetAlpha(0.9 * (1 - p))
	else
		stage.burst:SetAlpha(0)
	end

	-- Model: pops in (scale with a little overshoot), spins in for rare and up, then turns slowly. The
	-- pedestal glow lies on the ring the feet turn on.
	if reveal.fitAt then
		local shown = t - reveal.fitAt
		local p = math.min(shown / POP_TIME, 1)
		local size = math.max(math.floor(reveal.size * (0.3 + 0.7 * EaseOutBack(p))), 1)
		if size ~= reveal.modelSize then
			reveal.modelSize = size
			stage.model:SetSize(size, size)
			local half = size / 2
			if not reveal.guessed then
				stage.pedestal:SetSize(half * reveal.pedestalW * PEDESTAL_SCALE, half * reveal.pedestalH * PEDESTAL_SCALE)
				stage.pedestal:SetPoint("CENTER", stage, "CENTER", 0, half * reveal.pedestalY)
			end
		end
		reveal.modelAlpha = math.min(shown / 0.3, 1)
		stage.pedestal:SetAlpha(reveal.guessed and 0 or math.min(shown / 0.5, 1) * 0.6)
		local speed = TURN_SPEED + (fx.spin and SPIN_SPEED * math.exp(-SPIN_DECAY * shown) or 0)
		reveal.facing = (reveal.facing + dt * speed) % TWO_PI
		stage.actor:SetYaw(reveal.facing)
	end

	if fx.rays then
		local a = math.min(since / RAY_FADE, 1)
		stage.raysA:SetAlpha(a)
		PlaceRays(stage.raysA, t * RAY_SPEED)
		if fx.doubleRays then
			stage.raysB:SetAlpha(a)
			PlaceRays(stage.raysB, -t * RAY_SPEED * 1.4)
		end
	end
	if fx.sparkles then
		UpdateSparks(dt, h)
	end
end

-- Called every frame while the letterbox is visible.
function scene.Update(alpha, dt)
	card:SetAlpha(alpha)
	if not reveal then
		return
	end
	stage:SetAlpha(alpha)
	if alpha <= 0 and not reveal.t then
		return -- the reveal starts with the scene's fade-in
	end
	reveal.t = reveal.t or 0
	if alpha > 0 then
		UpdateReveal(dt)
	end
	stage.actor:SetAlpha((reveal.modelAlpha or 0) * alpha) -- the 3D model ignores the frame alpha
end

function scene.End()
	if reveal then
		for _, handle in ipairs(reveal.sounds) do
			StopSound(handle, SOUND_STOP_FADE)
		end
		wipe(reveal.sounds)
	end
end
