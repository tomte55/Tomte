local addonName, ns = ...

-- Dungeon journal: the lit band over the details (the boss or quest giver as a still model you can drag to turn, a
-- glow behind it, the name beside it, a shadow cast on the loot below) and the recessed well behind the left list.
-- Shared through ns.DJKit (Read.lua); laid out by Page.lua.

local STAGE_H = 150
local MODEL_W = 150 -- the model's box, standing on the band's bottom edge
local MODEL_ZOOM = 0.45 -- PlayerModel portrait zoom: 1 is the face, 0 the whole body; this is about waist up
local MODEL_TRIES = 6 -- a creature the client hasn't seen loads late: ask again this many times
local MODEL_RETRY = 0.4 -- seconds between asks
local TURN_SPEED = 0.02 -- radians per pixel dragged
local GLOW_W = 0.6 -- the glow's width, as a share of the band's
local GLOW_ALPHA = 0.22
local FILL_ALPHA = 0.45 -- the band's darker fill
local SHADOW_H = 10 -- the shadow it casts on what's below
local SHADOW_ALPHA = 0.5
local WELL_ALPHA = 0.35 -- the left list's well when the theme has no well art
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" -- a creature with no model

local UI = ns.UI
local J = ns.DJKit

J.STAGE_H = STAGE_H

-- The model ------------------------------------------------------------------------------------------------------------

local function Still(model)
	model:SetPortraitZoom(MODEL_ZOOM)
	model:FreezeAnimation(0, 0, 0)
end

local function TryModel(holder, npc, tries)
	if holder.npc ~= npc then
		return
	end
	local model = holder.model
	model:SetCreature(npc)
	-- A creature the client already has is loaded right away: freeze it now so its idle never plays.
	if model:GetModelFileID() then
		Still(model)
	end
	C_Timer.After(MODEL_RETRY, function()
		if holder.npc ~= npc or not holder:IsVisible() then
			return
		end
		if model:GetModelFileID() then
			holder.skull:Hide()
			Still(model)
		elseif tries < MODEL_TRIES then
			TryModel(holder, npc, tries + 1)
		else
			holder.skull:Show()
		end
	end)
end

local function ShowModel(holder, npc)
	holder:SetShown(npc ~= nil)
	if not npc or holder.npc == npc then
		return
	end
	holder.npc = npc
	holder.skull:Hide()
	holder.model:ClearModel()
	holder.model:SetFacing(0)
	TryModel(holder, npc, 1)
end

-- Drag left or right to turn it; only while the button is down does anything run each frame.
local function Turn(self)
	local x = GetCursorPosition()
	self:SetFacing(self:GetFacing() + (x - self.dragX) * TURN_SPEED / self:GetEffectiveScale())
	self.dragX = x
end

local function CreateModel(stage)
	local holder = CreateFrame("Frame", nil, stage)
	holder:SetSize(MODEL_W, STAGE_H - 6)
	holder:SetPoint("BOTTOMLEFT", 12, 0)
	holder.model = CreateFrame("PlayerModel", nil, holder)
	holder.model:SetAllPoints()
	if holder.model:HasScript("OnModelLoaded") then
		holder.model:SetScript("OnModelLoaded", Still)
	end
	holder.model:EnableMouse(true)
	holder.model:SetScript("OnMouseDown", function(self)
		self.dragX = GetCursorPosition()
		self:SetScript("OnUpdate", Turn)
	end)
	holder.model:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	holder.model:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", -20, -20)
		GameTooltip:SetText("Drag to turn", UI.RGB("textMuted"))
		GameTooltip:Show()
	end)
	holder.model:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	-- A model set while hidden can stay blank: set it again when the band shows next.
	holder:SetScript("OnHide", function(self)
		self.npc = nil
		self.model:SetScript("OnUpdate", nil)
	end)
	holder.skull = holder:CreateTexture(nil, "ARTWORK")
	holder.skull:SetSize(40, 40)
	holder.skull:SetPoint("CENTER", 0, -10)
	holder.skull:SetTexture(SKULL)
	holder.skull:Hide()
	holder:Hide()
	return holder
end

-- The band --------------------------------------------------------------------------------------------------------------

-- parent: the page; returns the band, which the caller anchors (its width follows the right side).
function J.CreateStage(parent)
	local stage = CreateFrame("Frame", nil, parent)
	stage:SetHeight(STAGE_H)
	stage.fill = stage:CreateTexture(nil, "BACKGROUND")
	stage.fill:SetAllPoints()
	stage.glow = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
	stage.glow:SetPoint("TOPLEFT")
	stage.glow:SetPoint("BOTTOMLEFT")
	stage.glow:SetColorTexture(1, 1, 1)
	stage.floor = UI.Hairline(stage, 10, 0.8, "rule")
	stage.floor:SetPoint("BOTTOMLEFT")
	stage.floor:SetPoint("BOTTOMRIGHT")
	stage.shadow = stage:CreateTexture(nil, "OVERLAY")
	stage.shadow:SetPoint("TOPLEFT", stage, "BOTTOMLEFT")
	stage.shadow:SetPoint("TOPRIGHT", stage, "BOTTOMRIGHT")
	stage.shadow:SetHeight(SHADOW_H)
	stage.shadow:SetColorTexture(1, 1, 1)
	stage:SetScript("OnSizeChanged", function(self, w)
		self.glow:SetWidth(math.max(w * GLOW_W, 1))
	end)

	stage.holder = CreateModel(stage)
	stage.title = UI.Text(stage, 28, "heading", "title")
	stage.title:SetJustifyH("LEFT")
	stage.title:SetWordWrap(false)
	stage.sub = UI.Text(stage, 13, "textMuted")
	stage.sub:SetJustifyH("LEFT")
	stage.sub:SetPoint("TOPLEFT", stage.title, "BOTTOMLEFT", 0, -4)
	stage.note = UI.Text(stage, 13, "textMuted")
	stage.note:SetJustifyH("LEFT")
	stage.note:SetPoint("TOPLEFT", stage.sub, "BOTTOMLEFT", 0, -4)
	stage:Hide()
	return stage
end

-- Colors are set each time it's drawn, so a theme switch reaches them.
local function Paint(stage)
	stage.fill:SetColorTexture(UI.RGBA("frameDark", FILL_ALPHA))
	stage.glow:SetGradient("HORIZONTAL", UI.ColorObject("accent", GLOW_ALPHA), UI.ColorObject("accent", 0))
	stage.shadow:SetGradient("VERTICAL", UI.ColorObject("frameDark", 0), UI.ColorObject("frameDark", SHADOW_ALPHA))
end

-- Fills the band: title, sub (muted), note (in a color role); npc: the creature to stand in it (nil: none, the text
-- moves left). rightW: room kept free at the right (a switch there).
function J.Stage(stage, title, sub, note, noteRole, npc, rightW)
	Paint(stage)
	ShowModel(stage.holder, npc)
	local x = npc and (12 + MODEL_W + 16) or 22
	stage.title:ClearAllPoints()
	stage.title:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", x, 58)
	stage.title:SetPoint("RIGHT", stage, "RIGHT", -(rightW or 0) - 16, 0)
	stage.title:SetText(title or "")
	stage.sub:SetPoint("RIGHT", stage, "RIGHT", -(rightW or 0) - 16, 0)
	stage.sub:SetText(sub or "")
	stage.note:SetText(note or "")
	UI.SetTextRole(stage.note, noteRole or "textMuted")
	stage:Show()
end

-- The well behind the left list: the game's sunken panel on the Forever theme, else a darker fill.
function J.CreateWell(parent)
	if ns.Theme.panel == "forever" and UI.Forever_Well then
		return UI.Forever_Well(parent)
	end
	local well = CreateFrame("Frame", nil, parent)
	well:SetFrameLevel(parent:GetFrameLevel())
	well.fill = well:CreateTexture(nil, "BACKGROUND")
	well.fill:SetAllPoints()
	local function Paint(self)
		self.fill:SetColorTexture(UI.RGBA("frameDark", WELL_ALPHA))
	end
	well:SetScript("OnShow", Paint)
	Paint(well)
	UI.Border(well, "rule", 0.6)
	return well
end
