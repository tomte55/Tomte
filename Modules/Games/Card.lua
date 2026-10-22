local addonName, ns = ...

-- Games: one playing card on screen. The face is the theme's text color (light on every theme) with the rank and
-- suit in bg (spades, clubs) or danger (hearts, diamonds); the back is the Cashier's choice (CashierData.lua), by
-- default accentDeep with an accent rule and mark. Cards slide in when dealt and turn over when revealed. Card numbers
-- are CardData.lua's; used by Table.lua and Cashier.lua.

local CARD_W, CARD_H = 52, 74
local SUIT_MEDIA = "Interface\\AddOns\\Tomte\\Media\\Games\\"
local SUIT_FILE = { spade = "Spade", heart = "Heart", diamond = "Diamond", club = "Club" }
local BACK_MARK = "Interface\\AddOns\\Tomte\\Media\\Showcase\\Diamond"
local PATTERN_V = 182 / 256 -- a back pattern's share of its texture's height (tools/games_art.py)
local PATTERN_ALPHA = 0.55
local SLIDE_TIME = 0.28 -- seconds for a dealt card to slide into place (from the shoe, across the table)
local FLIP_TIME = 0.08 -- seconds for each half of a card turning over
local DEAL_SCALE = 0.8 -- a dealt card starts this size and grows to full as it lands
local SHADE_ALPHA = 0.4 -- darkness over a losing hand's cards
-- Cards overlap in a row, so each one's inner frames (face, back, the back's rule, the shade) sit between it and
-- the next card: callers space cards this many frame levels apart.
local LEVELS = 4

local UI = ns.UI

ns.GAMES_CARD_W, ns.GAMES_CARD_H, ns.GAMES_CARD_LEVELS = CARD_W, CARD_H, LEVELS

local function SuitRole(card)
	return ns.Cards_IsRed(card) and "danger" or "bg"
end

local function ShowFace(self, card)
	local role = SuitRole(card)
	local suit = SUIT_MEDIA .. SUIT_FILE[ns.Cards_Suit(card)]
	for _, fs in ipairs({ self.rank, self.rankLow }) do
		fs:SetText(ns.Cards_RankText(card))
		UI.SetTextRole(fs, role)
	end
	for _, t in ipairs({ self.pip, self.big }) do
		t:SetTexture(suit)
		t:SetVertexColor(UI.Color(role))
	end
	self.face:Show()
	self.back:Hide()
end

local function ShowBack(self)
	self.face:Hide()
	self.back:Show()
end

-- card: a card number, or nil for face down.
local function SetCard(self, card)
	self.card = card
	if card then
		ShowFace(self, card)
	else
		ShowBack(self)
	end
end

-- Slides in from (dx, dy) away after `delay` seconds, growing to full size; invisible until then. onShow() (the
-- deal sound) runs as it starts moving.
local function Deal(self, dx, dy, delay, onShow)
	self.token = (self.token or 0) + 1
	local token = self.token
	self.slide:Stop()
	self:SetAlpha(0)
	self.shade:Hide()
	self.from:SetOffset(dx, dy)
	self.to:SetOffset(-dx, -dy)
	C_Timer.After(delay, function()
		if self.token == token then
			self:SetAlpha(1)
			self.slide:Play()
			if onShow then
				onShow()
			end
		end
	end)
end

-- Turns face up to `card` after `delay` seconds (its own token: a card can still be sliding in when it turns).
-- onShow() (the flip sound) runs as it starts turning.
local function Flip(self, card, delay, onShow)
	self.flipToken = (self.flipToken or 0) + 1
	local token = self.flipToken
	C_Timer.After(delay, function()
		if self.flipToken == token then
			if onShow then
				onShow()
			end
			self.pending = card
			self.flipOut:Play()
		end
	end)
end

-- Shown at once, no animation (a redraw of cards already on the table).
local function Place(self)
	self.token = (self.token or 0) + 1
	self.flipToken = (self.flipToken or 0) + 1
	self.slide:Stop()
	self.flipOut:Stop()
	self.flipIn:Stop()
	self:SetAlpha(1)
	self.shade:Hide()
end

-- A losing hand: a dark shade over the card. Not alpha: the cards overlap, and the one beneath would show through.
local function SetDim(self, dim)
	self.shade:SetShown(dim)
end

local function SetLevel(self, level)
	self:SetFrameLevel(level)
	self.face:SetFrameLevel(level + 1)
	self.back:SetFrameLevel(level + 1)
	self.rule:SetFrameLevel(level + 2)
	self.top:SetFrameLevel(level + 3)
end

local function Fill(frame, role)
	local t = frame:CreateTexture(nil, "BACKGROUND")
	t:SetAllPoints()
	t:SetColorTexture(UI.Color(role))
	return t
end

-- Card backs --------------------------------------------------------------------------------------------------------

local cards = {} -- every card made, so a new back reaches them all
local back -- the back in use: an item of ns.CASHIER_BACKS (nil until Table.lua sets one: the classic look)

-- item: base fills the back (times dim), ink draws the pattern and the rule; no pattern shows the classic mark.
local function PaintBack(f, item)
	local base, ink, dim = "accentDeep", "accent", 1
	if item then
		base, ink, dim = item.base, item.ink, item.dim or 1
	end
	local r, g, b = UI.Color(base)
	f.backFill:SetColorTexture(r * dim, g * dim, b * dim)
	UI.SetBorderColor(f.rule, ink, 0.7)
	local pattern = item and item.pattern
	if pattern then
		f.pattern:SetTexture(SUIT_MEDIA .. pattern)
		f.pattern:SetTexCoord(0, 1, 0, PATTERN_V)
		f.pattern:SetVertexColor(UI.Color(ink))
		f.pattern:SetAlpha(PATTERN_ALPHA)
	end
	f.pattern:SetShown(pattern ~= nil)
	f.mark:SetVertexColor(UI.Color(ink))
	f.mark:SetShown(pattern == nil)
end

function ns.GamesCard_SetBack(item)
	back = item
	for _, f in ipairs(cards) do
		if not f.swatch then
			PaintBack(f, item)
		end
	end
end

-- A back on any frame of card size (the Cashier's swatches): a card that only ever shows its back.
function ns.GamesCard_Swatch(parent, item)
	local f = ns.GamesCard_Create(parent)
	PaintBack(f, item)
	f.swatch = item
	f:SetCard(nil)
	f:Show()
	return f
end

function ns.GamesCard_Create(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(CARD_W, CARD_H)

	f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	f.shadow:SetPoint("TOPLEFT", 2, -2)
	f.shadow:SetPoint("BOTTOMRIGHT", 2, -2)
	f.shadow:SetColorTexture(0, 0, 0, 0.35)

	f.face = CreateFrame("Frame", nil, f)
	f.face:SetAllPoints()
	Fill(f.face, "text")
	UI.Border(f.face, "frameDark", 0.6)
	f.rank = UI.Text(f.face, 15, "bg", "title") -- the title font: a number font may have no A, J, Q, K
	f.rank:SetPoint("TOPLEFT", 5, -4)
	f.rank:SetShadowOffset(0, 0)
	f.pip = f.face:CreateTexture(nil, "ARTWORK")
	f.pip:SetSize(11, 11)
	f.pip:SetPoint("TOP", f.rank, "BOTTOM", 0, -1)
	f.big = f.face:CreateTexture(nil, "ARTWORK")
	f.big:SetSize(28, 28)
	f.big:SetPoint("CENTER", 3, -4)
	f.rankLow = UI.Text(f.face, 11, "bg", "title")
	f.rankLow:SetPoint("BOTTOMRIGHT", -5, 4)
	f.rankLow:SetShadowOffset(0, 0)

	f.back = CreateFrame("Frame", nil, f)
	f.back:SetAllPoints()
	f.backFill = Fill(f.back, "accentDeep")
	UI.Border(f.back, "frameDark", 0.8)
	f.pattern = f.back:CreateTexture(nil, "ARTWORK")
	f.pattern:SetPoint("TOPLEFT", 4, -4)
	f.pattern:SetPoint("BOTTOMRIGHT", -4, 4)
	f.rule = CreateFrame("Frame", nil, f.back)
	f.rule:SetPoint("TOPLEFT", 4, -4)
	f.rule:SetPoint("BOTTOMRIGHT", -4, 4)
	UI.Border(f.rule, "accent", 0.7)
	f.mark = f.back:CreateTexture(nil, "ARTWORK", nil, 1)
	f.mark:SetTexture(BACK_MARK)
	f.mark:SetSize(22, 22)
	f.mark:SetPoint("CENTER")
	f.mark:SetAlpha(0.6)
	cards[#cards + 1] = f
	PaintBack(f, back)

	f.slide = f:CreateAnimationGroup()
	f.from = f.slide:CreateAnimation("Translation")
	f.from:SetDuration(0.001)
	f.from:SetOrder(1)
	f.to = f.slide:CreateAnimation("Translation")
	f.to:SetDuration(SLIDE_TIME)
	f.to:SetSmoothing("OUT")
	f.to:SetOrder(2)
	local grow = f.slide:CreateAnimation("Scale")
	grow:SetScaleFrom(DEAL_SCALE, DEAL_SCALE)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(SLIDE_TIME)
	grow:SetSmoothing("OUT")
	grow:SetOrder(2)

	-- Turning over: squeeze to a sliver, change the face, open back up.
	f.flipOut = f:CreateAnimationGroup()
	local squeeze = f.flipOut:CreateAnimation("Scale")
	squeeze:SetScaleFrom(1, 1)
	squeeze:SetScaleTo(0.05, 1)
	squeeze:SetDuration(FLIP_TIME)
	f.flipIn = f:CreateAnimationGroup()
	local open = f.flipIn:CreateAnimation("Scale")
	open:SetScaleFrom(0.05, 1)
	open:SetScaleTo(1, 1)
	open:SetDuration(FLIP_TIME)
	f.flipOut:SetScript("OnFinished", function()
		SetCard(f, f.pending)
		f.flipIn:Play()
	end)

	-- Over the face and the back, on a frame of its own above both.
	f.top = CreateFrame("Frame", nil, f)
	f.top:SetAllPoints()
	f.shade = f.top:CreateTexture(nil, "OVERLAY")
	f.shade:SetAllPoints()
	f.shade:SetColorTexture(0, 0, 0, SHADE_ALPHA)
	f.shade:Hide()

	f.SetCard, f.Deal, f.Flip, f.Place, f.SetLevel, f.SetDim = SetCard, Deal, Flip, Place, SetLevel, SetDim
	f:Hide()
	return f
end
