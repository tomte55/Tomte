local addonName, ns = ...

-- Gold & value, item markers: the drawn markers (rules in MarkerData.lua). One widget per item button, in Tomte's bags
-- (Modules/Bags/Buttons.lua), Baganator's and the game's (MarkerBags.lua). Drawn from plain textures in the look of
-- Tomte's other bag marks: the glyph in its color over a black copy of itself, so it reads on bright icons. Only the
-- vendor coin is the game's own art (the junk coin of its bags).

local SIZE = 14 -- the widget's side on a 37 px item button
local SHADOW_X, SHADOW_Y, SHADOW_ALPHA = 1.5, -1.5, 0.9 -- as Buttons.lua's marks
local BAR = 2.5 -- stroke width
local COIN_ATLAS = "bags-junkcoin" -- ContainerFrameItemButtonTemplate's JunkIcon
local EPIC = 4 -- Enum.ItemQuality.Epic: the disenchant marker's color
local DIAGONAL = math.pi / 4

local UI = ns.UI

-- A bar of w x h at x, y from the center, turned by angle.
local function Bar(holder, sub, w, h, x, y, angle)
	local t = holder:CreateTexture(nil, "ARTWORK", nil, sub)
	t:SetSize(w, h)
	t:SetPoint("CENTER", x, y)
	if angle then
		t:SetRotation(angle)
	end
	return t
end

-- Each kind: draw(holder, sub) -> textures. Shapes on a SIZE square around its center.
local SHAPES = {
	-- A gavel: the handle along the rising diagonal, the head across its top end.
	auction = function(holder, sub)
		return {
			Bar(holder, sub, BAR, 10, -2, -2, -DIAGONAL),
			Bar(holder, sub, 10, 5, 2.5, 2.5, -DIAGONAL),
		}
	end,
	-- A diamond with a spark beside it.
	disenchant = function(holder, sub)
		return {
			Bar(holder, sub, 8, 8, -1, -1, DIAGONAL),
			Bar(holder, sub, 3, 3, 5, 5),
		}
	end,
	-- A check mark: a short stroke down to the bottom point, a long one up to the right.
	keep = function(holder, sub)
		return {
			Bar(holder, sub, BAR, 6, -3.6, -1.9, DIAGONAL),
			Bar(holder, sub, BAR, 12, 2.7, 0.2, -DIAGONAL),
		}
	end,
	-- An exclamation mark.
	quest = function(holder, sub)
		return {
			Bar(holder, sub, 3, 8, 0, 2),
			Bar(holder, sub, 3, 3, 0, -5),
		}
	end,
	-- An X.
	delete = function(holder, sub)
		return {
			Bar(holder, sub, BAR, 13, 0, 0, DIAGONAL),
			Bar(holder, sub, BAR, 13, 0, 0, -DIAGONAL),
		}
	end,
}

-- The glyph's color for kind: a theme role, or the game's own colors where those say it better.
local function Color(kind)
	if kind == "disenchant" then
		local r, g, b = C_Item.GetItemQualityColor(EPIC) -- its 4th return is a hex string, not alpha
		return r, g, b, 1
	elseif kind == "quest" then
		return YELLOW_FONT_COLOR:GetRGBA()
	elseif kind == "keep" then
		return UI.Color("success")
	elseif kind == "delete" then
		return UI.Color("danger")
	end
	return UI.Color("warning")
end

-- The coin: the game's junk coin when this client has it, else a drawn gold disc.
local function Coin(widget)
	local holder = CreateFrame("Frame", nil, widget)
	holder:SetAllPoints()
	local hasAtlas = C_Texture.GetAtlasInfo(COIN_ATLAS) ~= nil
	local shadow = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	shadow:SetPoint("TOPLEFT", SHADOW_X, SHADOW_Y)
	shadow:SetPoint("BOTTOMRIGHT", SHADOW_X, SHADOW_Y)
	local coin = holder:CreateTexture(nil, "ARTWORK", nil, 2)
	coin:SetAllPoints()
	if hasAtlas then
		shadow:SetAtlas(COIN_ATLAS)
		shadow:SetVertexColor(0, 0, 0, SHADOW_ALPHA)
		coin:SetAtlas(COIN_ATLAS)
	else
		shadow:SetColorTexture(0, 0, 0, SHADOW_ALPHA)
		UI.CircleMask(shadow, holder)
		coin:SetColorTexture(UI.Color("warning"))
		UI.CircleMask(coin, holder)
	end
	holder.Recolor = function() end
	return holder
end

-- One kind's glyph and shadow, in a holder of their own.
local function Glyph(widget, kind)
	if kind == "vendor" then
		return Coin(widget)
	end
	local holder = CreateFrame("Frame", nil, widget)
	holder:SetAllPoints()
	local glyphs = {}
	for _, shadow in ipairs({ true, false }) do
		local layer = CreateFrame("Frame", nil, holder)
		layer:SetSize(SIZE, SIZE)
		layer:SetPoint("CENTER", shadow and SHADOW_X or 0, shadow and SHADOW_Y or 0)
		for _, t in ipairs(SHAPES[kind](layer, shadow and 1 or 2)) do
			if shadow then
				t:SetColorTexture(0, 0, 0, SHADOW_ALPHA)
			else
				glyphs[#glyphs + 1] = t
			end
		end
	end
	holder.Recolor = function()
		for _, t in ipairs(glyphs) do
			t:SetColorTexture(Color(kind))
		end
	end
	return holder
end

-- A marker widget on parent (an item button), hidden until SetKind. widget:SetKind(kind) shows that marker (a
-- VALUE_MARKERS key; nil hides it); colors are read on each SetKind, so a theme switch reaches them.
function ns.Value_MarkerWidget(parent)
	local widget = CreateFrame("Frame", nil, parent)
	widget:SetSize(SIZE, SIZE)
	widget:SetFrameLevel(parent:GetFrameLevel() + 3)
	widget:Hide()
	local glyphs = {}
	function widget:SetKind(kind)
		for k, g in pairs(glyphs) do
			g:SetShown(k == kind)
		end
		self.kind = kind
		if not kind then
			self:Hide()
			return
		end
		local g = glyphs[kind]
		if not g then
			g = Glyph(self, kind)
			glyphs[kind] = g
		end
		g:Recolor()
		g:Show()
		self:Show()
	end
	return widget
end
