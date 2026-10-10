local addonName, ns = ...

-- Toast stack shared by the social modules: small cards that slide in at one spot on the screen and stack
-- downwards. A card has a spaced label in its accent color, a title (a name), a few lines of text and an
-- accent bar on the left. Left-click runs the card's onClick, right-click dismisses it; hovering pauses its
-- timer. A card with a mergeKey that is still up takes the next one with the same key (text replaced,
-- count shown). Pinned cards (the unread whisper recap) sit on top of the stack and never time out.
-- While a cinematic hides the UI (and in combat, for cards with holdInCombat) cards are held back; when
-- they're let go, an owner with a digest builder gets one card for all of its held cards. When a Blizzard UI
-- panel (merchant, mail, character...) covers the stack, the stack slides beside it until the panel closes.
--
-- ns.Toast_Show(spec): spec = { owner, label, accent, title, text, chat, secret, icon, iconAtlas, mergeKey, hold,
--   holdInCombat, onClick(button), onDismiss(), digestName, count }. secret = title/text may be secret values.
--   accent = a theme color role, or an { r, g, b } that carries game meaning (ns.Toast_ChatColor, quality);
--   chat = text is something another player wrote (shown in the chat font).
--   For Recent (ns.Recent_Note): recentTitle = a saveable title when title isn't one (a |K account name),
--   test = a preview (not noted); a pin's recentCount = Recent hears of it again only when this rises.
-- ns.Toast_Pin(key, spec) / ns.Toast_Unpin(key), ns.Toast_Clear(owner), ns.Toast_SetDigest(owner, fn(held))

local WIDTH = 300
local PAD = 10
local GAP = 6
local ICON = 28
local MAX_SHOWN = 4
local SLIDE_IN = 0.45 -- seconds to slide in from the nearest screen edge
local FADE_IN, FADE_OUT = 0.15, 0.6
local PULSE = 0.5 -- a merged message: the card flashes in its accent color and bounces
local BOUNCE = 10 -- pixels, towards the middle of the screen
local MOVE_SPEED = 12 -- reflow easing
local HOLD_MIN, HOLD_PER_CHAR, HOLD_MAX = 7, 0.06, 18
local HELD_CHECK = 0.5
local SECRET_TITLE_H, SECRET_TEXT_H = 16, 45 -- one title line, three text lines (the most a card shows)
local DEFAULT_POINT = { "TOPLEFT", "LEFT", 40, 140 } -- on UIParent: left side, above the chat
local DODGE_CHECK = 0.2 -- seconds between looks at the open UI panels
local DODGE_GAP = 12 -- pixels between a panel and the stack beside it
local PANEL_KEYS = { "left", "center", "right", "doublewide" } -- fullscreen panels can't be dodged
local UI = ns.UI

local anchor, mover
local shown = {} -- cards on screen, top to bottom (pinned first)
local queue = {} -- specs waiting for room
local held = {} -- specs held back while busy
local pinned = {} -- [key] = card
local pinNoted = {} -- [key] = spec.recentCount when the pin was last noted for Recent
local digests = {} -- [owner] = fn(held) -> spec
local pool = {}
local heldCheck = 0
local dodgeX, dodgeTarget, dodgeCheck = 0, 0, DODGE_CHECK

local function Smooth(p)
	return p * p * (3 - 2 * p)
end

local function EaseOut(p)
	local q = 1 - p
	return 1 - q * q * q
end

-- x offset that puts a card just off the screen edge nearest to the toasts.
local function OffscreenOffset()
	local left, right = anchor:GetLeft(), anchor:GetRight()
	if not (left and right) then
		return -WIDTH
	end
	left, right = left + dodgeX, right + dodgeX
	local toRight = UIParent:GetWidth() - right
	if left <= toRight then
		return -(left + WIDTH)
	end
	return toRight + WIDTH
end

-- Being placed: the handle is up, or Blizzard's Edit Mode is open. Cards wait and the stack stays put.
local function Moving()
	return (mover and mover:IsShown()) or ns.EditMode_Active()
end

local function SavePoint()
	local point, _, relativePoint, x, y = anchor:GetPoint(1)
	ns.db.toast.point = { point, relativePoint, x, y }
end

local function PlaceAnchor()
	local p = ns.db.toast.point or DEFAULT_POINT
	anchor:ClearAllPoints()
	anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local OnUpdate

local function BuildAnchor()
	anchor = CreateFrame("Frame", nil, UIParent)
	anchor:SetSize(WIDTH, 1)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetFrameLevel(50)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	PlaceAnchor()
	anchor:SetScript("OnUpdate", function(self, dt)
		OnUpdate(dt)
	end)
end

local function Busy(spec)
	return ns.Cinematic.IsActive() or not UIParent:IsShown() or (spec.holdInCombat and InCombatLockdown())
end

local function HideCard(card)
	card:Hide()
	card.spec = nil
	pool[#pool + 1] = card
end

local function Remove(card)
	for i, c in ipairs(shown) do
		if c == card then
			table.remove(shown, i)
			break
		end
	end
	if card.pinKey then
		pinned[card.pinKey] = nil
		card.pinKey = nil
	end
	HideCard(card)
end

-- Start fading out (right-click, or the owner says it's done).
local function Dismiss(card)
	if not card.leaving then
		card.leaving = 0
	end
end

local function OnCardClick(card, button)
	local spec = card.spec
	if not spec then
		return
	end
	if button == "RightButton" then
		if spec.onDismiss then
			spec.onDismiss()
		end
		Dismiss(card)
		return
	end
	if spec.onClick then
		spec.onClick(button)
	end
	if not card.pinKey then
		Dismiss(card)
	end
end

local function NewCard()
	local card = CreateFrame("Button", nil, anchor)
	card:SetWidth(WIDTH)
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card:SetScript("OnClick", OnCardClick)
	card:SetScript("OnEnter", function(self)
		self.hovered = true
		self.glow:Show()
	end)
	card:SetScript("OnLeave", function(self)
		self.hovered = false
		self.glow:Hide()
	end)

	UI.Panel(card, { alpha = 0.92, subtle = true })
	card.glow = card:CreateTexture(nil, "BORDER")
	card.glow:SetAllPoints()
	card.glow:SetColorTexture(UI.Color("hover"))
	card.glow:Hide()
	card.flash = card:CreateTexture(nil, "BORDER", nil, 1)
	card.flash:SetAllPoints()
	card.flash:SetColorTexture(1, 1, 1, 1)
	card.flash:SetAlpha(0)
	card.bar = card:CreateTexture(nil, "ARTWORK")
	card.bar:SetPoint("TOPLEFT")
	card.bar:SetPoint("BOTTOMLEFT")
	card.bar:SetWidth(2)
	card.line = card:CreateTexture(nil, "ARTWORK")
	card.line:SetPoint("BOTTOMLEFT", 2, 0)
	card.line:SetPoint("BOTTOMRIGHT")
	card.line:SetHeight(1)
	card.line:SetColorTexture(1, 1, 1, 1)

	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(ICON, ICON)
	card.icon:SetPoint("TOPLEFT", PAD + 2, -PAD)

	card.label = ns.SceneText(card, 10, "textMuted")
	card.label:SetJustifyH("LEFT")
	card.count = ns.SceneText(card, 10, "textMuted", "number")
	card.count:SetJustifyH("RIGHT")
	card.count:SetPoint("TOPRIGHT", -PAD, -PAD)
	card.title = ns.SceneText(card, 14, "text")
	card.title:SetJustifyH("LEFT")
	card.title:SetWordWrap(false)
	card.text = ns.SceneText(card, 13, "text")
	card.text:SetJustifyH("LEFT")
	card.text:SetJustifyV("TOP")
	card.text:SetWordWrap(true)
	card.text:SetMaxLines(3)
	return card
end

-- A measurement of a region holding a secret may itself be secret.
local function Measured(value, fallback)
	if issecretvalue and issecretvalue(value) then
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
	card.label:SetTextColor(r, g, b)
	card.label:SetText(ns.Spaced(spec.label or ""))
	card.count:SetText((spec.count or 1) > 1 and ("x" .. spec.count) or "")

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
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
	card.text:SetWidth(WIDTH - left - PAD)
	UI.SetFont(card.text, spec.chat and "chat" or "body", 13)
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

local function Acquire()
	local card = table.remove(pool) or NewCard()
	card.leaving, card.hovered, card.pinKey = nil, false, nil
	card.glow:Hide()
	card.flash:SetAlpha(0)
	return card
end

-- New card at the bottom of the stack (pinned cards go to the top).
local function Place(spec, pinKey)
	local card = Acquire()
	Fill(card, spec)
	card.pinKey = pinKey
	anchor:Show()
	card.enter, card.pulse = 0, nil
	dodgeCheck = DODGE_CHECK -- a new card changes the stack height: look at the panels right away
	card.from = OffscreenOffset()
	card.y, card.drawnX, card.drawnY = nil, nil, nil
	card:SetAlpha(0)
	card:Show()
	if pinKey then
		pinned[pinKey] = card
		table.insert(shown, 1, card)
	else
		shown[#shown + 1] = card
	end
	anchor:Show()
end

local function Unpinned()
	local n = 0
	for _, card in ipairs(shown) do
		if not card.pinKey then
			n = n + 1
		end
	end
	return n
end

-- A card still up with this owner and merge key.
local function FindMerge(spec)
	if not spec.mergeKey then
		return nil
	end
	for _, card in ipairs(shown) do
		local s = card.spec
		if s and not card.leaving and not card.pinKey and s.owner == spec.owner and s.mergeKey == spec.mergeKey then
			return card
		end
	end
	return nil
end

local function Display(spec)
	local card = FindMerge(spec)
	if card then
		spec.count = (card.spec.count or 1) + (spec.count or 1)
		Fill(card, spec)
		card.pulse = 0
		return
	end
	for _, q in ipairs(queue) do
		if spec.mergeKey and q.owner == spec.owner and q.mergeKey == spec.mergeKey then
			spec.count = (q.count or 1) + (spec.count or 1)
			for k, v in pairs(spec) do
				q[k] = v
			end
			return
		end
	end
	if Unpinned() >= MAX_SHOWN then
		queue[#queue + 1] = spec
		return
	end
	Place(spec)
end

-- Held cards whose reason is gone: one digest card per owner that has a builder, else each card.
local function ReleaseHeld()
	local ready, byOwner, order = {}, {}, {}
	for i = #held, 1, -1 do
		if not Busy(held[i]) then
			table.insert(ready, 1, table.remove(held, i))
		end
	end
	for _, spec in ipairs(ready) do
		local owner = spec.owner or ""
		if not byOwner[owner] then
			byOwner[owner] = {}
			order[#order + 1] = owner
		end
		local list = byOwner[owner]
		list[#list + 1] = spec
	end
	for _, owner in ipairs(order) do
		local list = byOwner[owner]
		local build = digests[owner]
		if #list > 1 and build then
			local digest = build(list)
			if digest then
				Display(digest)
			end
		else
			for _, spec in ipairs(list) do
				Display(spec)
			end
		end
	end
end

-- Open UI panels as { left, right, top, bottom } in the anchor's coordinates.
local function PanelRects()
	local rects = {}
	local scale = anchor:GetEffectiveScale()
	for _, key in ipairs(PANEL_KEYS) do
		local panel = GetUIPanel(key)
		if panel and panel:IsVisible() then
			local left, bottom, width, height = panel:GetRect()
			if left then
				local k = panel:GetEffectiveScale() / scale
				rects[#rects + 1] = { left * k, (left + width) * k, (bottom + height) * k, bottom * k }
			end
		end
	end
	return rects
end

-- x offset that moves the stack beside any panel covering it: away from the screen edge the stack sits at.
local function DodgeOffset()
	if #shown == 0 or Moving() then
		return 0
	end
	local left, top = anchor:GetLeft(), anchor:GetTop()
	if not (left and top) then
		return 0
	end
	local rects = PanelRects()
	if #rects == 0 then
		return 0
	end
	local height = 0
	for _, card in ipairs(shown) do
		height = height + card:GetHeight() + GAP
	end
	local bottom = top - height
	local screen = UIParent:GetWidth()
	local towardRight = left + WIDTH / 2 < screen / 2
	local x = left
	for _ = 1, #rects do
		local hit
		for _, r in ipairs(rects) do
			if x < r[2] and x + WIDTH > r[1] and top > r[4] and bottom < r[3] then
				hit = r
				break
			end
		end
		if not hit then
			break
		end
		x = towardRight and hit[2] + DODGE_GAP or hit[1] - DODGE_GAP - WIDTH
	end
	x = math.max(0, math.min(x, screen - WIDTH))
	return x - left
end

local function Layout(dt)
	dodgeCheck = dodgeCheck + dt
	if dodgeCheck >= DODGE_CHECK then
		dodgeCheck = 0
		dodgeTarget = DodgeOffset()
	end
	if dodgeX ~= dodgeTarget then
		dodgeX = dodgeX + (dodgeTarget - dodgeX) * math.min(dt * MOVE_SPEED, 1)
		if math.abs(dodgeTarget - dodgeX) < 0.5 then
			dodgeX = dodgeTarget
		end
	end
	local dx = math.floor(dodgeX + 0.5)
	local y = 0
	for _, card in ipairs(shown) do
		local target = -y
		if not card.y then
			card.y = target
		else
			card.y = card.y + (target - card.y) * math.min(dt * MOVE_SPEED, 1)
		end
		local slide = 0
		if card.enter < SLIDE_IN then
			slide = math.floor(card.from * (1 - EaseOut(card.enter / SLIDE_IN)) + 0.5)
		elseif card.pulse then
			-- One hop away from the screen edge, then a smaller one back: a damped bounce.
			local p = card.pulse / PULSE
			local away = card.from < 0 and 1 or -1
			slide = math.floor(away * BOUNCE * math.sin(p * math.pi * 2) * (1 - p) + 0.5)
		end
		local x, cy = slide + dx, math.floor(card.y + 0.5)
		if card.drawnX ~= x or card.drawnY ~= cy then
			card.drawnX, card.drawnY = x, cy
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, cy)
		end
		y = y + card:GetHeight() + GAP
	end
end

function OnUpdate(dt)
	heldCheck = heldCheck + dt
	if heldCheck >= HELD_CHECK and #held > 0 then
		heldCheck = 0
		ReleaseHeld()
	end
	for i = #shown, 1, -1 do
		local card = shown[i]
		if card.enter < SLIDE_IN then
			card.enter = card.enter + dt
			if not card.leaving then
				card:SetAlpha(Smooth(math.min(card.enter / FADE_IN, 1)))
			end
		end
		if card.pulse then
			card.pulse = card.pulse + dt
			card.flash:SetAlpha(0.3 * (1 - Smooth(math.min(card.pulse / PULSE, 1))))
			if card.pulse >= PULSE then
				card.pulse = nil
				card.flash:SetAlpha(0)
			end
		end
		if card.leaving then
			card.leaving = card.leaving + dt
			card:SetAlpha(1 - Smooth(math.min(card.leaving / FADE_OUT, 1)))
			if card.leaving >= FADE_OUT then
				Remove(card)
			end
		elseif not card.pinKey and not card.hovered and not Moving() then
			card.age = card.age + dt
			if card.age >= card.life then
				Dismiss(card)
			end
		end
	end
	while #queue > 0 and Unpinned() < MAX_SHOWN do
		Place(table.remove(queue, 1))
	end
	Layout(dt)
	if #shown == 0 and #held == 0 and #queue == 0 and not Moving() then
		anchor:Hide()
	end
end

local function BuildMover()
	mover = CreateFrame("Frame", nil, anchor)
	mover:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
	mover:SetSize(WIDTH, 22)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	local bg = mover:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.RGBA("accent", 0.25))
	local text = ns.SceneText(mover, 11, "accent")
	text:SetPoint("CENTER")
	text:SetText("Drag to move toasts - right-click to lock")
	mover:SetScript("OnDragStart", function()
		anchor:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		anchor:StopMovingOrSizing()
		SavePoint()
	end)
	mover:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			ns.Toast_Unlock(false)
		end
	end)
	mover:Hide()
end

local function Ensure()
	if not anchor then
		BuildAnchor()
		BuildMover()
	end
end

-- A chat type's color as { r, g, b }, as the player has it set in chat (whisper pink, guild green), for cards about
-- chat. Called when the card is made: ChatTypeInfo gets its colors after login.
function ns.Toast_ChatColor(chatType)
	local info = ChatTypeInfo and ChatTypeInfo[chatType]
	if info and info.r then
		return { info.r, info.g, info.b }
	end
	return { UI.Color("accent") }
end

function ns.Toast_Show(spec)
	if ns.Recent_Note then
		ns.Recent_Note(spec)
	end
	Ensure()
	anchor:Show()
	if Busy(spec) then
		held[#held + 1] = spec
		return
	end
	Display(spec)
end

-- A card that stays on top until unpinned. Showing it again with the same key updates it in place.
-- Recent hears of it when it's first pinned, and again only when spec.recentCount rises (an update while
-- you read isn't news).
function ns.Toast_Pin(key, spec)
	local card = pinned[key]
	local count = spec.recentCount or 0
	if ns.Recent_Note and (not card or card.leaving or count > (pinNoted[key] or 0)) then
		local copy = {} -- every field, recentTitle and test included
		for k, v in pairs(spec) do
			copy[k] = v
		end
		copy.mergeKey = "pin:" .. key
		ns.Recent_Note(copy)
	end
	pinNoted[key] = count
	Ensure()
	if card then
		Fill(card, spec)
		card.leaving = nil
		card:SetAlpha(1)
		return
	end
	Place(spec, key)
end

function ns.Toast_Unpin(key)
	pinNoted[key] = nil
	local card = pinned[key]
	if card then
		Dismiss(card)
	end
end

-- Drop every card from this owner (module turned off): on screen, waiting and held.
function ns.Toast_Clear(owner)
	for i = #queue, 1, -1 do
		if queue[i].owner == owner then
			table.remove(queue, i)
		end
	end
	for i = #held, 1, -1 do
		if held[i].owner == owner then
			table.remove(held, i)
		end
	end
	for i = #shown, 1, -1 do
		local card = shown[i]
		if card.spec and card.spec.owner == owner then
			Remove(card)
		end
	end
end

-- Cards from this owner that were held back come out as one card: fn(heldSpecs) returns its spec.
function ns.Toast_SetDigest(owner, fn)
	digests[owner] = fn
end

function ns.Toast_Unlock(unlock)
	Ensure()
	if unlock == nil then
		unlock = not mover:IsShown()
	end
	mover:SetShown(unlock)
	if unlock then
		anchor:Show()
		if Unpinned() == 0 then
			ns.Toast_Show({ owner = "toast", label = "Toast", title = "Sample", text = "Toasts show up here.", hold = 30,
				test = true })
		end
	end
end

-- A sample card while Edit Mode is open (straight to the screen: not a toast for Recent).
ns.EditMode_Register({
	name = "Toasts",
	frame = function()
		return anchor
	end,
	refresh = function()
		if ns.EditMode_Active() then
			Ensure()
			anchor:Show()
			if Unpinned() == 0 then
				Display({ owner = "editmode", label = "Toast", title = "Sample", text = "Toasts show up here." })
			end
		elseif anchor then
			ns.Toast_Clear("editmode")
		end
	end,
	saved = SavePoint,
	place = function(box, frame)
		box:SetPoint("TOPLEFT", frame, "TOPLEFT")
		box:SetSize(WIDTH, 70)
	end,
})

function ns.Toast_ResetPosition()
	ns.db.toast.point = nil
	if anchor then
		PlaceAnchor()
	end
end

-- Sound choices (ns.SOCIAL_SOUND_CHOICES) on the Master channel: heard with sound effects off.
local SOUNDS = {
	whisper = "TELL_MESSAGE",
	chime = "UI_BNET_TOAST",
	bell = "READY_CHECK",
	alarm = "RAID_WARNING",
	invite = "IG_PLAYER_INVITE",
}

function ns.Social_PlaySound(choice)
	local kit = SOUNDS[choice] and SOUNDKIT[SOUNDS[choice]]
	if kit then
		PlaySound(kit, "Master")
	end
end

-- The same two rows in every social module's options.
function ns.Toast_Options(options)
	options[#options + 1] = { type = "header", label = "Toast position" }
	options[#options + 1] = { type = "button", label = "Move toasts", text = "Unlock", onClick = function()
		ns.Toast_Unlock()
	end, tooltip = "Show a handle above the toasts: drag it to move them, right-click it (or click this again) to lock. Shared by all social modules. Blizzard's Edit Mode moves them too." }
	options[#options + 1] = { type = "button", label = "Reset position", text = "Reset", onClick = ns.Toast_ResetPosition,
		tooltip = "Put the toasts back on the left side of the screen, above the chat." }
	return options
end
