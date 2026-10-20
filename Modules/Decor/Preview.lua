local addonName, ns = ...

-- Housing decor: a turning 3D model of a decor next to GameTooltip, the way the housing catalog previews it (the
-- entry's model file in its catalog model scene, Blizzard_HousingModelPreview). Panel/ModelPreview.lua shows creatures
-- and appearances only; decor models are files, so the Decor page has this card. Shown only while GameTooltip is.

local PREVIEW_W, PREVIEW_H = 220, 240
local TURN_SPEED = 0.6 -- radians per second
local ACTOR_TAG = "decor" -- the actor the catalog's decor model scenes hold
local DEFAULT_SCENE = 1317 -- Constants.HousingCatalogConsts.HOUSING_CATALOG_DECOR_MODELSCENEID_DEFAULT, when missing
local UI = ns.UI

local function DefaultScene()
	local consts = Constants and Constants.HousingCatalogConsts
	return consts and consts.HOUSING_CATALOG_DECOR_MODELSCENEID_DEFAULT or DEFAULT_SCENE
end

-- Under the tooltip, or above it when there's no room below.
local function Place(p)
	p:ClearAllPoints()
	local bottom = GameTooltip:GetBottom()
	local needed = (PREVIEW_H + 4) * p:GetEffectiveScale() / GameTooltip:GetEffectiveScale()
	if bottom and bottom - needed >= 0 then
		p:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -4)
	else
		p:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, 4)
	end
end

function ns.DecorPreview_Hide(p)
	if p then
		p:Hide()
	end
end

-- Loads the entry's model; false when it has none or the scene has no decor actor.
local function SetModel(p, e)
	local sceneID = e.sceneID or DefaultScene()
	local ok = pcall(p.scene.TransitionToModelSceneID, p.scene, sceneID, CAMERA_TRANSITION_TYPE_IMMEDIATE,
		CAMERA_MODIFICATION_TYPE_DISCARD, true)
	local actor = ok and p.scene:GetActorByTag(ACTOR_TAG)
	if not actor then
		return false
	end
	if actor.SetPreferModelCollisionBounds then
		actor:SetPreferModelCollisionBounds(true)
	end
	if not pcall(actor.SetModelByFileID, actor, e.asset) then
		return false
	end
	p.actor, p.baseYaw, p.turn = actor, actor:GetYaw() or 0, 0
	return true
end

-- e: a catalog entry (Catalog.lua) with asset and sceneID. Returns false (and hides) when there's nothing to show.
function ns.DecorPreview_Show(p, e)
	if not (e and e.asset and GameTooltip:IsShown()) then
		ns.DecorPreview_Hide(p)
		return false
	end
	if p.id ~= e.id then
		p.actor = nil
		if not SetModel(p, e) then
			p.id = nil
			ns.DecorPreview_Hide(p)
			return false
		end
		p.id = e.id
	end
	p.name:SetText(e.name or "")
	p.sub:SetText(e.line or ns.Decor_SourceWord(e.source))
	Place(p)
	p:Show()
	return true
end

function ns.DecorPreview_Create(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(PREVIEW_W, PREVIEW_H)
	p:SetFrameStrata("TOOLTIP")
	p:SetClampedToScreen(true)
	p:Hide()
	UI.Panel(p, { size = "medium" })
	p.scene = CreateFrame("ModelScene", nil, p, "NoCameraControlModelSceneMixinTemplate")
	p.scene:SetPoint("TOPLEFT", 4, -4)
	p.scene:SetPoint("BOTTOMRIGHT", -4, 40)
	-- OnUpdate runs only while the card is shown: it turns the model.
	p:SetScript("OnUpdate", function(_, dt)
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
	p.sub = UI.Text(p, 11, "textMuted")
	p.sub:SetPoint("BOTTOMLEFT", 8, 8)
	p.sub:SetPoint("BOTTOMRIGHT", -8, 8)
	p.sub:SetJustifyH("CENTER")
	p.sub:SetWordWrap(false)
	return p
end
