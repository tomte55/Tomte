local addonName, ns = ...

-- Toast stack: what a card looks like and how a spec fills it, and the still cards drawn into settings previews
-- (ns.Toast_DrawSample). The stack itself is in Toast.lua.

local WIDTH = 300
local PAD = 10
local GAP = 6
local ICON = 28
local TIMER_H = 2 -- the countdown line along the bottom
local SAMPLE_TIME_LEFT = 0.65 -- a settings preview's card shows this much of its time left
local FOREVER_EDGE = 3 -- px the Forever theme's tooltip border takes
local HOLD_MIN, HOLD_PER_CHAR, HOLD_MAX = 7, 0.06, 18
local SECRET_TITLE_H, SECRET_TEXT_H = 18, 45 -- one title line, three text lines (the most a card shows)
local UI = ns.UI

ns.TOAST_WIDTH = WIDTH -- for Toast.lua
ns.TOAST_GAP = GAP

-- What a card looks like: panel, hover and flash layers, accent bar and line, icon, texts (filled by Fill). Shared by
-- the real cards (NewCard adds the clicks) and the still samples in settings previews (ns.Toast_DrawSample).
local function Dress(card)
	card:SetWidth(WIDTH)
	UI.Panel(card, { alpha = 0.92, subtle = true, toast = true })
	-- The Forever theme's tooltip frame has rounded corners: the card's own layers stay inside them.
	local inset = ns.Theme.panel == "forever" and FOREVER_EDGE or 0
	card.glow = card:CreateTexture(nil, "BORDER")
	card.glow:SetPoint("TOPLEFT", inset, -inset)
	card.glow:SetPoint("BOTTOMRIGHT", -inset, inset)
	card.glow:SetColorTexture(UI.Color("hover"))
	card.glow:Hide()
	card.flash = card:CreateTexture(nil, "BORDER", nil, 1)
	card.flash:SetPoint("TOPLEFT", inset, -inset)
	card.flash:SetPoint("BOTTOMRIGHT", -inset, inset)
	card.flash:SetColorTexture(1, 1, 1, 1)
	card.flash:SetAlpha(0)
	card.bar = card:CreateTexture(nil, "ARTWORK")
	card.bar:SetPoint("TOPLEFT", inset, -inset)
	card.bar:SetPoint("BOTTOMLEFT", inset, inset)
	card.bar:SetWidth(2)
	card.line = card:CreateTexture(nil, "ARTWORK")
	card.line:SetPoint("BOTTOMLEFT", 2 + inset, inset)
	card.line:SetPoint("BOTTOMRIGHT", -inset, inset)
	card.line:SetHeight(1)
	card.line:SetColorTexture(1, 1, 1, 1)
	-- How long the card stays: shrinks from full width to nothing over its life, stands still while hovered.
	card.timer = card:CreateTexture(nil, "ARTWORK", nil, 1)
	card.timer:SetPoint("BOTTOMLEFT", 2 + inset, inset)
	card.timer:SetHeight(TIMER_H)
	card.timerFull = WIDTH - 2 - 2 * inset

	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(ICON, ICON)
	card.icon:SetPoint("TOPLEFT", PAD + 2, -PAD)

	card.label = ns.SceneText(card, 10, "textMuted")
	card.label:SetJustifyH("LEFT")
	card.label:SetWordWrap(false) -- spaced letters would wrap mid-word, and the card's height counts one line
	card.count = ns.SceneText(card, 10, "textMuted", "number")
	card.count:SetJustifyH("RIGHT")
	card.count:SetPoint("TOPRIGHT", -PAD, -PAD)
	card.title = ns.SceneText(card, 15, "heading", "title") -- the name stands out from the text under it
	card.title:SetJustifyH("LEFT")
	card.title:SetWordWrap(false)
	card.text = ns.SceneText(card, 13, "text")
	card.text:SetJustifyH("LEFT")
	card.text:SetJustifyV("TOP")
	card.text:SetWordWrap(true)
	card.text:SetMaxLines(3)
end

-- A measurement of a region holding a secret may itself be secret.
local function Measured(value, fallback)
	if ns.IsSecret(value) then
		return fallback
	end
	return value
end

local function Fill(card, spec)
	card.spec = spec
	local r, g, b = UI.RGBA(spec.accent or "accent")
	card.bar:SetColorTexture(r, g, b, 1)
	card.flash:SetColorTexture(r, g, b, 1)
	card.line:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.5), CreateColor(r, g, b, 0))
	card.timer:SetColorTexture(r, g, b, 0.85)
	card.timer:SetWidth(card.timerFull)
	card.label:SetTextColor(r, g, b)
	card.label:SetText(ns.Spaced(spec.label or ""))
	local corner = (spec.count or 1) > 1 and ("x" .. spec.count) or nil
	local ago = spec.heldAt and ns.Toast_HeldText(GetTime() - spec.heldAt)
	if ago then
		corner = corner and (ago .. " - " .. corner) or ago
	end
	card.count:SetText(corner or "")

	local hasIcon = spec.icon ~= nil or spec.iconAtlas ~= nil
	card.icon:SetShown(hasIcon)
	if spec.iconAtlas then
		card.icon:SetAtlas(spec.iconAtlas)
	elseif spec.icon then
		card.icon:SetTexture(spec.icon)
	end
	local left = PAD + 2 + (hasIcon and (ICON + 8) or 0)
	card.label:ClearAllPoints()
	card.label:SetPoint("TOPLEFT", left, -PAD)
	card.label:SetPoint("RIGHT", card.count, "LEFT", -6, 0)
	card.title:ClearAllPoints()
	card.title:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -4)
	card.title:SetPoint("RIGHT", -PAD, 0)
	card.title:SetText(spec.title or "")
	card.text:ClearAllPoints()
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
	card.text:SetWidth(WIDTH - left - PAD)
	-- A chat line is the message itself and stays bright; any other text is detail under the name.
	UI.SetFont(card.text, spec.chat and "chat" or "body", spec.chat and 13 or 12)
	UI.SetTextRole(card.text, spec.chat and "text" or "textMuted")
	card.text:SetText(spec.text or "")

	-- Secret text (chat lockdown) can be shown but not measured or compared: assume the longest card.
	local textH
	if spec.secret then
		textH = Measured(card.text:GetStringHeight(), SECRET_TEXT_H) + 3
	else
		-- Measured here too: a pooled card that once held secret text may still measure as secret.
		textH = (spec.text and spec.text ~= "") and (math.min(Measured(card.text:GetStringHeight(), SECRET_TEXT_H), SECRET_TEXT_H) + 3) or 0
	end
	local titleH = Measured(card.title:GetStringHeight(), SECRET_TITLE_H)
	local h = PAD + Measured(card.label:GetStringHeight(), 10) + 4 + titleH + textH + PAD
	if hasIcon then
		h = math.max(h, ICON + 2 * PAD)
	end
	card:SetHeight(math.floor(h + 0.5))
	card.life = spec.hold or (spec.secret and HOLD_MAX)
		or ns.Social_HoldTime(spec.text, HOLD_MIN, HOLD_PER_CHAR, HOLD_MAX)
	card.age = 0
end

-- A still card for a settings preview (Panel/Preview.lua): a plain frame dressed and filled like a real card, the
-- i-th from the top of host (cards below i are hidden, so drawing 1 then 2 stacks two). Nothing on it moves or times
-- out: Fill's life and age are never counted. Returns the stack's width and height so far.
function ns.Toast_DrawSample(host, spec, i)
	i = i or 1
	host.toastSamples = host.toastSamples or {}
	local cards = host.toastSamples
	for n = 1, i do
		if not cards[n] then
			local card = CreateFrame("Frame", nil, host)
			Dress(card)
			card.glow:Hide()
			card.flash:SetAlpha(0)
			cards[n] = card
		end
	end
	for n = i + 1, #cards do
		cards[n]:Hide()
	end
	local card = cards[i]
	Fill(card, spec)
	card.timer:SetWidth(card.timerFull * SAMPLE_TIME_LEFT)
	card:ClearAllPoints()
	if i == 1 then
		card:SetPoint("TOPLEFT", host, "TOPLEFT")
	else
		card:SetPoint("TOPLEFT", cards[i - 1], "BOTTOMLEFT", 0, -GAP)
	end
	card:Show()
	local h = 0
	for n = 1, i do
		h = h + cards[n]:GetHeight() + (n > 1 and GAP or 0)
	end
	return WIDTH, h
end

-- For Toast.lua.
ns.ToastCard_Dress = Dress
ns.ToastCard_Fill = Fill
