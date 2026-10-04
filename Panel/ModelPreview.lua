local addonName, ns = ...

-- A turning 3D model card next to GameTooltip: a creature (mount or pet) or an appearance tried on the player, with a
-- name and a line under it. Almost Done's reward preview and Collect here's rows use it.
--
-- ns.ModelPreview_Create(parent) -> p
-- ns.ModelPreview_Show(p, model): model = { sceneID, displayID } or { link } (an appearance), plus key (skips
--   reloading the same model), name, sub. Shown only while GameTooltip is; returns false when there's nothing to show.
-- ns.ModelPreview_Hide(p)

local UI = ns.UI
local GOLD, GREY = UI.GOLD, UI.GREY
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local PREVIEW_W, PREVIEW_H = 240, 260
local TURN_SPEED = 0.35 -- radians per second
local DRESS_UP_SCENE = 596 -- Blizzard's dress-up frame scene (DressUpFrames.lua)

local function ClearModel(p)
	p.modelKey, p.actor = nil, nil
	p.scene:Hide()
end

local function SetCreature(p, sceneID, displayID, key)
	if p.modelKey == key then
		return
	end
	p.modelKey = key
	p.actor = nil
	p.scene:Show()
	p.scene:TransitionToModelSceneID(sceneID, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
	local actor = p.scene:GetActorByTag("unwrapped") or p.scene:GetActorByTag("pet")
	if not actor then
		return
	end
	p.actor, p.baseYaw, p.turn = actor, actor:GetYaw(), 0
	actor:SetModelByCreatureDisplayID(displayID, true)
	if actor.SetAnimationBlendOperation and Enum.ModelBlendOperation then
		actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.Anim)
	end
	actor:SetAnimation(0)
end

local function SetAppearance(p, link, key)
	if p.modelKey == key then
		return
	end
	p.modelKey = key
	p.actor = nil
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
		ClearModel(p)
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
	local usable = model and ((model.sceneID and model.displayID) or model.link)
	if not (usable and GameTooltip:IsShown()) then
		ns.ModelPreview_Hide(p)
		return false
	end
	Place(p)
	p:Show()
	local ok = pcall(function()
		if model.link then
			SetAppearance(p, model.link, model.key or model.link)
		else
			SetCreature(p, model.sceneID, model.displayID, model.key or (model.sceneID .. ":" .. model.displayID))
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
	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], UI.BG[4])
	UI.Border(p, GOLD[1], GOLD[2], GOLD[3], 0.45)
	p.scene = CreateFrame("ModelScene", nil, p, "NoCameraControlModelSceneMixinTemplate")
	p.scene:SetPoint("TOPLEFT", 4, -4)
	p.scene:SetPoint("BOTTOMRIGHT", -4, 40)
	p.scene:HookScript("OnUpdate", function(_, dt)
		if p.actor then
			p.turn = (p.turn + dt * TURN_SPEED) % (2 * math.pi)
			p.actor:SetYaw(p.baseYaw + p.turn)
		end
	end)
	p.name = UI.Text(p, 14, GOLD, TITLE_FONT)
	p.name:SetPoint("BOTTOMLEFT", 8, 22)
	p.name:SetPoint("BOTTOMRIGHT", -8, 22)
	p.name:SetJustifyH("CENTER")
	p.name:SetWordWrap(false)
	p.kind = UI.Text(p, 11, GREY)
	p.kind:SetPoint("BOTTOMLEFT", 8, 8)
	p.kind:SetPoint("BOTTOMRIGHT", -8, 8)
	p.kind:SetJustifyH("CENTER")
	return p
end
