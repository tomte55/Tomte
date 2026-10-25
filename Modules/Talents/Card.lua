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

-- The card's looks on f: the real card's and the settings preview's (TalentsCard_DrawSample below).
local function Dress(f)
	f:SetSize(CARD_W, 90)
	UI.Panel(f, { alpha = 0.95 })
	f.title = UI.Text(f, 10, "textMuted", "label")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	f.title:SetText(ns.Spaced("Talent check"))
	-- Fixed widths, so the wrapped height is known right after SetText.
	f.text = UI.Text(f, 13, "heading")
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -TEXT_GAP)
	f.text:SetWidth(CARD_W - 2 * PAD)
	f.text:SetJustifyH("LEFT")
	f.text:SetWordWrap(true)
	f.detail = UI.Text(f, 11, "textMuted")
	f.detail:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -4)
	f.detail:SetWidth(CARD_W - 2 * PAD)
	f.detail:SetJustifyH("LEFT")
	f.detail:SetWordWrap(true)
	f.buttons = {}
	for i = 1, MAX_BUTTONS do
		local b = UI.Button(f, 80, "")
		b:SetHeight(BUTTON_H)
		f.buttons[i] = b
	end
end

local function Build()
	card = CreateFrame("Frame", nil, UIParent)
	card:SetFrameStrata("HIGH")
	card:SetClampedToScreen(true)
	card:SetMovable(true)
	card:Hide()
	Dress(card)
	for _, b in ipairs(card.buttons) do
		b:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			if self.onClick then
				self.onClick() -- a mouse click: a hardware event, as switching talents wants
			end
		end)
	end
end

local function Place()
	local p = db.card
	card:ClearAllPoints()
	card:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
end

-- spec = { text, detail (optional), buttons = { { text, onClick }, ... } (at most three, left to right) }. A click
-- hides the card before its onClick runs. f: the card (Dress) to draw on.
local function Draw(f, spec)
	f.text:SetText(spec.text)
	f.detail:SetText(spec.detail or "")
	f.detail:SetShown(spec.detail ~= nil)
	local textH = f.text:GetStringHeight() + (spec.detail and 4 + f.detail:GetStringHeight() or 0)
	local x = PAD
	for i, b in ipairs(f.buttons) do
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
	f:SetWidth(math.max(CARD_W, x - BUTTON_GAP + PAD)) -- long loadout or instance names widen the button row
	local titleH = f.title:GetStringHeight()
	f:SetHeight(PAD + titleH + TEXT_GAP + textH + 10 + BUTTON_H + PAD)
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
		Draw(card, PREVIEW)
		card:Show()
	elseif current then
		Draw(card, current)
		card:Show()
	else
		card:Hide()
	end
end

-- The settings preview (Panel/Preview.lua): the card with spec (TalentsCard_Show's shape, no onClicks), else Edit
-- Mode's sample question. Drawn by Dress and Draw like the real one.
function ns.TalentsCard_DrawSample(host, spec)
	local f = host.card
	if not f then
		f = CreateFrame("Frame", nil, host)
		f:SetPoint("TOPLEFT")
		Dress(f)
		host.card = f
	end
	Draw(f, spec or PREVIEW)
	return f:GetWidth(), f:GetHeight()
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
