local addonName, ns = ...

-- Talent check: the card that offers a loadout switch or asks whether to remember a hand switch. A title, one line,
-- an optional muted detail and up to three buttons; moved through Edit Mode. What it says and does comes from
-- Talents.lua (the main file), which also hides it in combat and when the module stops.

-- Sizes in pixels. The card grows wider than CARD_W only when the buttons need it.
local CARD_W = 340
local PAD = 12
local BUTTON_H = 22
local BUTTON_GAP = 8
local MAX_BUTTONS = 3
local TEXT_GAP = 6

local UI = ns.UI

local db, module
local card
local current -- the question on show (TalentsCard_Show's spec), so Edit Mode can put it back after its preview

local function Build()
	card = CreateFrame("Frame", nil, UIParent)
	card:SetSize(CARD_W, 90)
	card:SetFrameStrata("HIGH")
	card:SetClampedToScreen(true)
	card:SetMovable(true)
	card:Hide()
	UI.Panel(card, { alpha = 0.95 })
	card.title = UI.Text(card, 10, "textMuted", "label")
	card.title:SetPoint("TOPLEFT", PAD, -PAD)
	card.title:SetText(ns.Spaced("Talent check"))
	-- Fixed widths, so the wrapped height is known right after SetText.
	card.text = UI.Text(card, 13, "heading")
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -TEXT_GAP)
	card.text:SetWidth(CARD_W - 2 * PAD)
	card.text:SetJustifyH("LEFT")
	card.text:SetWordWrap(true)
	card.detail = UI.Text(card, 11, "textMuted")
	card.detail:SetPoint("TOPLEFT", card.text, "BOTTOMLEFT", 0, -4)
	card.detail:SetWidth(CARD_W - 2 * PAD)
	card.detail:SetJustifyH("LEFT")
	card.detail:SetWordWrap(true)
	card.buttons = {}
	for i = 1, MAX_BUTTONS do
		local b = UI.Button(card, 80, "")
		b:SetHeight(BUTTON_H)
		b:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			if self.onClick then
				self.onClick() -- a mouse click: a hardware event, as switching talents wants
			end
		end)
		card.buttons[i] = b
	end
end

local function Place()
	local p = db.card
	card:ClearAllPoints()
	card:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
end

-- spec = { text, detail (optional), buttons = { { text, onClick }, ... } (at most three, left to right) }. A click
-- hides the card before its onClick runs.
local function Draw(spec)
	card.text:SetText(spec.text)
	card.detail:SetText(spec.detail or "")
	card.detail:SetShown(spec.detail ~= nil)
	local textH = card.text:GetStringHeight() + (spec.detail and 4 + card.detail:GetStringHeight() or 0)
	local x = PAD
	for i, b in ipairs(card.buttons) do
		local info = spec.buttons and spec.buttons[i]
		if info then
			b.label:SetText(info.text)
			UI.FitButton(b, 70, 24)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", x, PAD)
			x = x + b:GetWidth() + BUTTON_GAP
			b.onClick = info.onClick and function() -- the Edit Mode preview's buttons do nothing
				current = nil
				card:Hide()
				info.onClick()
			end
			b:Show()
		else
			b.onClick = nil
			b:Hide()
		end
	end
	card:SetWidth(math.max(CARD_W, x - BUTTON_GAP + PAD)) -- long loadout or instance names widen the button row
	local titleH = card.title:GetStringHeight()
	card:SetHeight(PAD + titleH + TEXT_GAP + textH + 10 + BUTTON_H + PAD)
end

-- What Edit Mode shows while there's no question.
local PREVIEW = {
	text = "You're on Raid; for dungeons you use Mythic+.",
	buttons = { { text = "Switch to Mythic+" }, { text = "Not now" } },
}

local function Refresh()
	local preview = module and module.active and ns.EditMode_Active() and not current
	if preview and not card then
		Build()
		Place()
	end
	if not card then
		return
	end
	if preview then
		Draw(PREVIEW)
		card:Show()
	elseif current then
		Draw(current)
		card:Show()
	else
		card:Hide()
	end
end

function ns.TalentsCard_Init(moduleDB, owner)
	db, module = moduleDB, owner
end

function ns.TalentsCard_Show(spec)
	if not card then
		Build()
	end
	current = spec
	if not (card:IsShown() and ns.EditMode_Active()) then
		Place()
	end
	Refresh()
	card:Raise()
end

function ns.TalentsCard_Hide()
	current = nil
	Refresh()
end

function ns.TalentsCard_Shown()
	return current ~= nil and card ~= nil and card:IsShown()
end

-- Back where the defaults put it (the `card` default in Talents.lua).
function ns.TalentsCard_ResetPosition()
	local p = db.card
	p.point, p.relPoint, p.x, p.y = "TOP", "TOP", 0, -180
	if card then
		Place()
	end
end

ns.EditMode_Register({
	name = "Talent check",
	frame = function()
		return card
	end,
	refresh = Refresh,
	saved = function()
		local point, _, relPoint, x, y = card:GetPoint()
		local p = db.card
		p.point, p.relPoint, p.x, p.y = point, relPoint, x, y
	end,
	module = "talents",
	reset = function()
		ns.TalentsCard_ResetPosition()
	end,
})
