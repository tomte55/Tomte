local addonName, ns = ...

-- Quest pins in the game's own look (Blizzard_POIButton: POIButton.lua, POIButton.xml), shared by the Tomte map's pins
-- (Modules/Map/Pins.lua) and the Quest list's minimap markers (Modules/QuestList/Minimap.lua): a round button, the
-- active quest's one lit and glowing, an icon on it. The button art is 32 pixels on a 20-pixel button, the glow 50.

local ATLAS = {
	button = "UI-QuestPoi-QuestNumber", activeButton = "UI-QuestPoi-QuestNumber-SuperTracked",
	glow = "UI-QuestPoi-OuterGlow", highlight = "UI-QuestPoi-InnerGlow",
	progress = "Quest-In-Progress-Icon-yellow", activeProgress = "Quest-In-Progress-Icon-Brown",
	ready = "UI-QuestIcon-TurnIn-Normal",
}
-- Sizes as shares of the pin: the button art and its icon are both 32 pixels on a 20-pixel button (POIButton.xml; a
-- smaller icon left the in-progress dots too small to see), the glow 50.
local ART, GLOW, ICON = 32 / 20, 50 / 20, 32 / 20

local known -- nil: not asked yet

-- Whether this client has the art (false: callers draw their own).
function ns.QuestPin_Has()
	if known == nil then
		known = C_Texture.GetAtlasInfo(ATLAS.button) ~= nil
	end
	return known
end

-- Dresses frame (a pin of `size` pixels) as a quest: active lit and glowing, ready with the turn-in mark. Its textures
-- are made once (frame.questPin) and set again only when something changed. Returns false without the art.
function ns.QuestPin_Look(frame, size, active, ready)
	if not ns.QuestPin_Has() then
		return false
	end
	local t = frame.questPin
	if not t then
		t = {}
		t.glow = frame:CreateTexture(nil, "BACKGROUND")
		t.glow:SetPoint("CENTER")
		t.glow:SetAtlas(ATLAS.glow)
		t.glow:SetBlendMode("ADD")
		t.button = frame:CreateTexture(nil, "BORDER")
		t.button:SetPoint("CENTER")
		t.mark = frame:CreateTexture(nil, "ARTWORK", nil, 1)
		t.mark:SetPoint("CENTER")
		t.lit = frame:CreateTexture(nil, "HIGHLIGHT")
		t.lit:SetPoint("CENTER")
		t.lit:SetAtlas(ATLAS.highlight)
		t.lit:SetBlendMode("ADD")
		frame.questPin = t
	end
	local key = (active and "a" or "") .. (ready and "r" or "") .. size
	if t.key ~= key then
		t.key = key
		t.glow:SetSize(size * GLOW, size * GLOW)
		t.glow:SetShown(active and true or false)
		t.button:SetSize(size * ART, size * ART)
		t.button:SetAtlas(active and ATLAS.activeButton or ATLAS.button)
		t.lit:SetSize(size * ART, size * ART)
		t.mark:SetSize(size * ICON, size * ICON)
		t.mark:SetAtlas(ready and ATLAS.ready or active and ATLAS.activeProgress or ATLAS.progress)
	end
	ns.QuestPin_Show(frame, true)
	return true
end

-- Shows or hides the quest look on a frame that has it (a minimap marker turned into an edge arrow hides it).
function ns.QuestPin_Show(frame, shown)
	local t = frame.questPin
	if t then
		t.button:SetShown(shown)
		t.mark:SetShown(shown)
		t.lit:SetShown(shown)
		t.glow:SetShown(shown and t.key:sub(1, 1) == "a")
	end
end
