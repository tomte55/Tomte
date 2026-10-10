local addonName, ns = ...

-- A 3D model card next to GameTooltip: a creature (mount or pet) standing as in its journal, or an appearance tried
-- on the player and turning, with a name and a line under it. Almost Done's reward preview, Collect here's and World
-- quests' rows use it.
--
-- ns.ModelPreview_Create(parent) -> p
-- ns.ModelPreview_Show(p, model): model = { displayID, sceneID, selfMount } (a mount or pet; sceneID is its journal
--   scene) or { link } (an appearance), plus key (skips reloading the same model), name, sub. Shown only while
--   GameTooltip is; returns false when there's nothing to show.
-- ns.ModelPreview_Hide(p)

local UI = ns.UI
local PREVIEW_W, PREVIEW_H = 240, 260
local TURN_SPEED = 0.35 -- radians per second
local DRESS_UP_SCENE = 596 -- Blizzard's dress-up frame scene (DressUpFrames.lua)
-- Creatures stand still at their journal's angle: the camera and actor angles of the mount's or pet's own scene. They
-- are shown in a plain scene with our own camera at those angles (as Moments' reveal), because the journals' scenes
-- are framed for their bigger windows and cut big mounts off. The camera backs off until the model's box (what
-- Blizzard's actors normalize their scale by) fills CAMERA_FIT of the frame, measured with the game's own projection.
local CAMERA_FOV = 0.5
local CAMERA_FIT = 0.95 -- the box's widest point on screen, as a share of the frame's half size
local FIT_PASSES = 6
local FIT_TIMEOUT = 1.5 -- seconds: a model that reports no size by then is shown with a guessed one
local GUESS_BOX = { -1, -1, 0, 1, 1, 2 }
-- Without a journal scene: a little above the model looking down, the model three-quarters on.
local DEFAULT_ANGLES = { camYaw = math.pi, camPitch = 0.3, camRoll = 0, yaw = 0.9, pitch = 0, roll = 0 }
local ACTOR_TAGS = { "unwrapped", "pet" } -- the creature's actor in a mount or pet scene
local SELF_MOUNT_IDLE = 618 -- the Mount Journal's animation for a mount you become (MountSelfIdle)
local RESUME = 0.5 -- seconds a hidden preview keeps its model, so a redraw's hide and re-show doesn't reload it

local function ClearModel(p)
	p.modelKey, p.actor, p.fitting = nil, nil, nil
	p.scene:Hide()
	p.creature:Hide()
	p.creatureActor:ClearModel()
end

-- The journal's angles for a mount or pet scene, or nil. The camera's zoomed offsets apply in full at its closest
-- zoom and not at all at its farthest (OrbitCameraMixin), so in part at its default zoom.
local function JournalAngles(sceneID)
	if not sceneID then
		return nil
	end
	local _, cameraIDs, actorIDs = C_ModelInfo.GetModelSceneInfoByID(sceneID)
	local camera = cameraIDs and cameraIDs[1] and C_ModelInfo.GetModelSceneCameraInfoByID(cameraIDs[1])
	if not camera then
		return nil
	end
	local actor
	for _, tag in ipairs(ACTOR_TAGS) do
		for _, id in ipairs(actorIDs or {}) do
			local info = C_ModelInfo.GetModelSceneActorInfoByID(id)
			if info and info.scriptTag == tag then
				actor = info
				break
			end
		end
		if actor then
			break
		end
	end
	local zoomIn = 0
	local near, far = camera.minZoomDistance, camera.maxZoomDistance
	if near and far and far > near and camera.zoomDistance then
		zoomIn = 1 - math.min(math.max((camera.zoomDistance - near) / (far - near), 0), 1)
	end
	return {
		camYaw = (camera.yaw or 0) + (camera.zoomedYawOffset or 0) * zoomIn,
		camPitch = (camera.pitch or 0) + (camera.zoomedPitchOffset or 0) * zoomIn,
		camRoll = (camera.roll or 0) + (camera.zoomedRollOffset or 0) * zoomIn,
		yaw = actor and actor.yaw or 0,
		pitch = actor and actor.pitch or 0,
		roll = actor and actor.roll or 0,
	}
end

-- A point in the model's space on the creature scene, as fractions of its half size from the center (x right,
-- y up). The projection is in pixels from the frame's bottom left.
local function Project(scene, x, y, z)
	local px, py = scene:Project3DPointTo2D(x, y, z)
	local s = scene:GetEffectiveScale()
	local halfW, halfH = scene:GetWidth() * s / 2, scene:GetHeight() * s / 2
	if not (px and py) or halfW <= 0 or halfH <= 0 then
		return nil
	end
	return (px - halfW) / halfW, (py - halfH) / halfH
end

-- The model's box corners, turned to its yaw. The actor centers the model's width and depth on its position; its
-- height stays as the model has it (feet near 0).
local function Corners(bx, by, bz, tx, ty, tz, yaw)
	local halfW, halfD = (tx - bx) / 2, (ty - by) / 2
	local c, s = math.cos(yaw), math.sin(yaw)
	local corners = {}
	for _, x in ipairs({ -halfW, halfW }) do
		for _, y in ipairs({ -halfD, halfD }) do
			local rx, ry = x * c - y * s, x * s + y * c
			corners[#corners + 1] = { rx, ry, bz }
			corners[#corners + 1] = { rx, ry, tz }
		end
	end
	return corners
end

-- Where the corners land on screen, as fractions of the half size; nil when one is behind the camera.
local function ScreenBounds(scene, corners)
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs(corners) do
		local x, y = Project(scene, c[1], c[2], c[3])
		if not (x and y) then
			return nil
		end
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minY, maxY = math.min(minY, y), math.max(maxY, y)
	end
	return minX, maxX, minY, maxY
end

-- Returns false while the model has no size yet. guess = use GUESS_BOX instead.
local function FitCamera(p, guess)
	local bx, by, bz, tx, ty, tz
	if guess then
		bx, by, bz, tx, ty, tz = unpack(GUESS_BOX)
	else
		bx, by, bz, tx, ty, tz = p.creatureActor:GetActiveBoundingBox()
	end
	if not (bx and tz) or tx - bx <= 0 or ty - by <= 0 or tz - bz <= 0 then
		return false
	end
	local angles = p.angles
	local corners = Corners(bx, by, bz, tx, ty, tz, angles.yaw)

	local scene = p.creature
	scene:SetCameraOrientationByYawPitchRoll(angles.camYaw, angles.camPitch, angles.camRoll)
	local fx, fy, fz = scene:GetCameraForward()
	if angles == DEFAULT_ANGLES and fz > 0 then -- the pitch's sign differs from what we assumed: we want to look down
		scene:SetCameraOrientationByYawPitchRoll(angles.camYaw, -angles.camPitch, angles.camRoll)
		fx, fy, fz = scene:GetCameraForward()
	end
	scene:SetLightVisible(true)
	scene:SetLightType(Enum.ModelLightType and Enum.ModelLightType.Directional or 0)
	scene:SetLightDirection(fx, fy, fz)
	scene:SetLightAmbientColor(0.7, 0.7, 0.7)
	scene:SetLightDiffuseColor(0.8, 0.8, 0.8)

	-- The camera looks at (lookX, lookY, lookZ) from `distance` away. Each pass centers the box on screen (how far a
	-- step of the look point moves things on screen is measured) and scales the distance by how far the box reaches
	-- (sizes on screen shrink with the distance, so a few passes settle it).
	local halfW, halfD, halfH = (tx - bx) / 2, (ty - by) / 2, (tz - bz) / 2
	local lookX, lookY, lookZ = 0, 0, (bz + tz) / 2
	local rightX, rightY = fy, -fx -- level and square to the view
	local flat = math.sqrt(rightX * rightX + rightY * rightY)
	if flat > 0 then
		rightX, rightY = rightX / flat, rightY / flat
	end
	local distance = 2 * math.sqrt(halfW * halfW + halfD * halfD + halfH * halfH) / math.tan(CAMERA_FOV / 2)
	local function PlaceCamera()
		scene:SetCameraPosition(lookX - fx * distance, lookY - fy * distance, lookZ - fz * distance)
	end
	for _ = 1, FIT_PASSES do
		PlaceCamera()
		local minX, maxX, minY, maxY = ScreenBounds(scene, corners)
		if not minX then
			distance = distance * 2 -- part of it is behind the camera
		else
			local x0, y0 = Project(scene, lookX, lookY, lookZ)
			local _, y1 = Project(scene, lookX, lookY, lookZ + 1)
			local x1 = Project(scene, lookX + rightX, lookY + rightY, lookZ)
			if x0 and x1 and x1 ~= x0 and flat > 0 then
				local step = ((minX + maxX) / 2 - x0) / (x1 - x0)
				lookX, lookY = lookX + rightX * step, lookY + rightY * step
			end
			if y0 and y1 and y1 ~= y0 then
				lookZ = lookZ + ((minY + maxY) / 2 - y0) / (y1 - y0)
			end
			local reach = math.max((maxX - minX) / 2, (maxY - minY) / 2)
			if reach <= 0 then
				break
			end
			distance = distance * reach / CAMERA_FIT
		end
	end
	PlaceCamera()
	return true
end

local function SetCreature(p, model, key)
	if p.modelKey == key then
		return
	end
	p.modelKey = key
	p.actor = nil -- stands still
	p.scene:Hide()
	p.creature:Show()
	p.angles = JournalAngles(model.sceneID) or DEFAULT_ANGLES
	local actor = p.creatureActor
	-- Invisible until it's measured and the camera fitted (the 3D model ignores the frame alpha).
	actor:SetAlpha(0)
	actor:SetModelByCreatureDisplayID(model.displayID) -- set while shown: one set while hidden can stay blank
	actor:SetYaw(p.angles.yaw)
	actor:SetPitch(p.angles.pitch)
	actor:SetRoll(p.angles.roll)
	-- As the Mount Journal: a mount you become idles as one.
	if actor.SetAnimationBlendOperation and Enum.ModelBlendOperation then
		actor:SetAnimationBlendOperation(model.selfMount and Enum.ModelBlendOperation.None or Enum.ModelBlendOperation.Anim)
	end
	actor:SetAnimation(model.selfMount and SELF_MOUNT_IDLE or 0)
	p.fitting = GetTime()
end

local function SetAppearance(p, link, key)
	if p.modelKey == key then
		return
	end
	p.modelKey = key
	p.actor, p.fitting = nil, nil
	p.creature:Hide()
	p.scene:Show()
	p.scene:TransitionToModelSceneID(DRESS_UP_SCENE, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
	SetupPlayerForModelScene(p.scene, nil, nil, true, true)
	local actor = p.scene:GetPlayerActor()
	if actor then
		actor:TryOn(link)
		p.actor, p.baseYaw, p.turn = actor, actor:GetYaw(), 0
	end
end

function ns.ModelPreview_Hide(p)
	if p:IsShown() then
		p:Hide()
		p.hiddenAt = GetTime()
	end
end

-- Under the tooltip, or above it when there's no room below, or right of it when there's none above either.
local function Place(p)
	p:ClearAllPoints()
	-- In screen pixels: the tooltip, the preview and UIParent can each have their own scale.
	local tipScale = GameTooltip:GetEffectiveScale()
	local bottom, top = GameTooltip:GetBottom(), GameTooltip:GetTop()
	local screenH = UIParent:GetHeight() * UIParent:GetEffectiveScale()
	local needed = (PREVIEW_H + 4) * p:GetEffectiveScale()
	if bottom and bottom * tipScale - needed >= 0 then
		p:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -4)
	elseif top and top * tipScale + needed <= screenH then
		p:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, 4)
	else
		p:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 4, 0)
	end
end

function ns.ModelPreview_Show(p, model)
	local usable = model and (model.displayID or model.link)
	if not (usable and GameTooltip:IsShown()) then
		ns.ModelPreview_Hide(p)
		return false
	end
	if p.hiddenAt and GetTime() - p.hiddenAt > RESUME then
		ClearModel(p)
	end
	p.hiddenAt = nil
	Place(p)
	p:Show()
	local ok = pcall(function()
		if model.link then
			SetAppearance(p, model.link, model.key or model.link)
		else
			SetCreature(p, model, model.key or model.displayID)
		end
	end)
	if not ok then
		ClearModel(p)
	end
	p.name:SetText(model.name or "")
	p.kind:SetText(model.sub or "")
	return true
end

function ns.ModelPreview_Create(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(PREVIEW_W, PREVIEW_H)
	p:SetFrameStrata("TOOLTIP")
	p:SetClampedToScreen(true)
	p:Hide()
	UI.Panel(p, { size = "medium" })
	p.scene = CreateFrame("ModelScene", nil, p, "NoCameraControlModelSceneMixinTemplate")
	p.scene:SetPoint("TOPLEFT", 4, -4)
	p.scene:SetPoint("BOTTOMRIGHT", -4, 40)
	p.creature = CreateFrame("ModelScene", nil, p)
	p.creature:SetPoint("TOPLEFT", 4, -4)
	p.creature:SetPoint("BOTTOMRIGHT", -4, 40)
	p.creature:SetCameraFieldOfView(CAMERA_FOV)
	p.creature:Hide()
	p.creatureActor = p.creature:CreateActor()
	-- Its width and depth centered on its position, feet at height 0 (the default can be the model's center).
	p.creatureActor:SetUseCenterForOrigin(true, true, false)
	p:SetScript("OnUpdate", function(_, dt)
		-- The creature shows once it's loaded and measured (usually right away).
		if p.fitting then
			local actor = p.creatureActor
			if (actor:IsLoaded() and FitCamera(p)) or (GetTime() - p.fitting > FIT_TIMEOUT and FitCamera(p, true)) then
				p.fitting = nil
				actor:SetAlpha(1)
			end
		end
		-- An appearance turns.
		if p.actor then
			p.turn = (p.turn + dt * TURN_SPEED) % (2 * math.pi)
			p.actor:SetYaw(p.baseYaw + p.turn)
		end
	end)
	p.name = UI.Text(p, 13, "heading", "title")
	p.name:SetPoint("BOTTOMLEFT", 8, 22)
	p.name:SetPoint("BOTTOMRIGHT", -8, 22)
	p.name:SetJustifyH("CENTER")
	p.name:SetWordWrap(false)
	p.kind = UI.Text(p, 11, "textMuted")
	p.kind:SetPoint("BOTTOMLEFT", 8, 8)
	p.kind:SetPoint("BOTTOMRIGHT", -8, 8)
	p.kind:SetJustifyH("CENTER")
	return p
end
