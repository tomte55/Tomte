local addonName, ns = ...

-- Moment scene for the cinematic engine: top band = title card (spaced label, title, gold line,
-- subtitle), bottom band = the moment's icon and one line of detail. A creature model (new mount, tamed
-- pet) stands on the left on a darkened side, where the engine's character showcase goes for a level up.

local GOLD, GREY, WHITE = ns.SCENE_GOLD, ns.SCENE_GREY, ns.SCENE_WHITE
local CENTER_X = 250 -- model center from the left screen edge (same place as the showcase)
local MODEL_W, MODEL_H = 360, 420
local GRADIENT_WIDTH = 620
local TURN_SPEED = 0.25 -- radians per second
local ICON = 30
local Text, Place, SetText = ns.SceneText, ns.ScenePlace, ns.SceneSetText

local card, side
local facing = 0

local scene = {}
ns.MomentScene = scene

function scene.Create(parent, letterbox)
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

	-- Left side: creature model on a dark gradient.
	side = CreateFrame("Frame", nil, parent)
	side:SetAllPoints(letterbox)
	side:SetAlpha(0)
	local shade = side:CreateTexture(nil, "BACKGROUND", nil, -8)
	shade:SetColorTexture(1, 1, 1, 1)
	shade:SetPoint("TOPLEFT")
	shade:SetPoint("BOTTOMLEFT")
	shade:SetWidth(GRADIENT_WIDTH)
	shade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.7), CreateColor(0, 0, 0, 0))
	side.model = CreateFrame("PlayerModel", nil, side)
	side.model:SetSize(MODEL_W, MODEL_H)
	side.model:SetPoint("CENTER", side, "LEFT", CENTER_X, 30)
end

-- state.moment = { label, title, subtitle, detail, icon, displayID }
function scene.Begin(state)
	local m = state.moment
	local scale = UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale()
	card:SetScale(scale)
	side:SetScale(scale)
	ns.SceneSnap(card)
	card.label:SetText(ns.Spaced(m.label or ""))
	card.title:SetText(m.title or "")
	SetText(card.subtitle, m.subtitle)
	SetText(card.detail, m.detail)
	card.icon:SetShown(m.icon ~= nil)
	card.iconBorder:SetShown(m.icon ~= nil)
	if m.icon then
		card.icon:SetTexture(m.icon)
	end
	side:SetShown(m.displayID ~= nil)
	side.pending = m.displayID -- set on the first update: models set while hidden can stay blank
	side:SetAlpha(0)
	side.model:SetModelAlpha(0)
end

-- Called every frame while the letterbox is visible.
function scene.Update(alpha, dt)
	card:SetAlpha(alpha)
	if side:IsShown() then
		if side.pending then
			side.model:SetDisplayInfo(side.pending)
			side.model:SetPortraitZoom(0)
			side.pending = nil
			facing = 0.6
		end
		local a = math.max((alpha - 0.3) / 0.7, 0) -- the model a little after the text
		side:SetAlpha(a)
		side.model:SetModelAlpha(a) -- the 3D model ignores the frame alpha
		facing = (facing + dt * TURN_SPEED) % (2 * math.pi)
		side.model:SetFacing(facing)
	end
end
