local addonName, ns = ...

-- Blackjack: the table window (a movable UI.Dialog; Esc closes it). Dealer row on top, your hand or hands below, a
-- message line between, the bet controls or the play buttons at the bottom, chips top right (stats on hover).
-- Rules and the saved game in BlackjackRules.lua; cards in Card.lua; registered in Blackjack.lua. Plain frames:
-- nothing here is protected.

local WIDTH, HEIGHT = 500, 372
local CARD_STEP = 30 -- pixels between overlapping cards in a hand
local HAND_GAP = 60 -- pixels between two split hands
local MAX_CARDS = 11 -- the most cards a hand can hold without busting (four aces, four twos, three threes)
local DEAL_STAGGER = 0.15 -- seconds between the first four cards
local DEALER_PACE = 0.55 -- seconds between the dealer's cards once you stand
local SLIDE_FROM_X, SLIDE_FROM_Y = 120, 60 -- where dealt cards come from (up and to the right: the shoe)
local DEALER_Y, PLAYER_Y = -78, -216 -- card rows' tops, from the window's top
local RESULT_ROLES = { blackjack = "success", win = "success", push = "textMuted", lose = "danger", bust = "danger" }
local BIG_WIN = 500 -- chips won in one round that count as a big win (a bigger sound)
local SHUFFLE_TIME = 0.4 -- seconds of shuffling sounds before the first card of a fresh shoe
local CHIP_ROLL = 0.8 -- seconds for the chip count to roll to a round's payout
local GLOW_REST = 0.35 -- a winning hand's glow once it has flashed
local CHIP_FLOAT_DRIFT = -22 -- pixels the +/- under the chip count drifts (down, away from the count)
local MESSAGE_SIZE, BANNER_SIZE = 14, 30 -- font sizes of the message line and the "Blackjack!" banner

local UI = ns.UI

local db, frame
local Draw
-- What the window shows of the round, so only new cards animate: the round table, cards shown per hand and for
-- the dealer, whether the hole card is face up, and which round's result has had its sounds and effects.
local shown = { round = nil, hands = {}, dealer = 0, hole = false, handCount = 1 }
local revealTimer
local shownChips -- the number on the chip count (it rolls to new values)
local bustShown = {} -- [hand] = true: already shook and sounded when it busted

local function Game()
	return db.game
end

local function Random(n)
	return math.random(n)
end

local function Sound(name)
	if db.sounds then
		ns.GamesFx_Sound(name)
	end
end

local function DealSound()
	Sound("deal")
end

local function FlipSound()
	Sound("flip")
end

local function ChipsText(chips)
	return ns.Thousands(chips) .. " chips"
end

-- The chip count, rolled to its new value (roll) or set at once. role: its color while rolling.
local function SetChips(value, roll, role)
	if value == shownChips then
		return -- unchanged: a roll on its way there keeps going
	end
	if roll and shownChips then
		ns.GamesFx_CountTo(frame.chips, shownChips, value, roll, ChipsText, "accent", role)
	else
		ns.GamesFx_CountTo(frame.chips, value, value, 0, ChipsText, "accent")
	end
	shownChips = value
end

-- Actions -------------------------------------------------------------------------------------------------------

local function HandRow(hand)
	for i, h in ipairs(Game().round.hands) do
		if h == hand then
			return frame.hands[i]
		end
	end
end

local function ShakeRow(row)
	for _, card in ipairs(row.cards) do
		if card:IsShown() then
			ns.GamesFx_Shake(card)
		end
	end
end

local function Act(fn)
	if revealTimer then
		return
	end
	local game = Game()
	local hand = ns.Blackjack_ActiveHand(game)
	fn(game, Random)
	Draw(true)
	-- A hand that just went bust shakes as its last card lands.
	if hand and ns.Blackjack_Value(hand.cards) > 21 and not bustShown[hand] then
		bustShown[hand] = true
		local row = HandRow(hand)
		C_Timer.After(0.25, function()
			if frame:IsShown() and row then
				Sound("lose")
				ShakeRow(row)
			end
		end)
	end
end

local function Deal()
	Act(ns.Blackjack_Deal)
end

local function AddChip(amount)
	if revealTimer then
		return
	end
	local game = Game()
	if game.round and game.round.phase == "done" and not shown.betChanged then
		game.bet = 0 -- the first chip after a round starts a new bet; Deal alone repeats the last one
	end
	shown.betChanged = true
	local before = game.bet
	ns.Blackjack_AddBet(game, amount)
	Draw(false)
	if game.bet > before then
		Sound("chip")
		ns.GamesFx_PopText(frame.betText, "number", 13, 1.35, 0.2)
		ns.GamesFx_Float(frame.fx, "+" .. ns.Thousands(game.bet - before), "accent", frame.betText, "TOP", 0, 6,
			{ size = 13 })
	end
end

local function ClearBet()
	if revealTimer then
		return
	end
	ns.Blackjack_ClearBet(Game())
	shown.betChanged = true
	Sound("clear")
	Draw(false)
end

local function Refill()
	if ns.Blackjack_Refill(Game()) then
		Sound("refill")
		ns.Print(("the house gives you %s chips."):format(ns.Thousands(ns.BLACKJACK_START_CHIPS)))
		SetChips(Game().chips, CHIP_ROLL, "success")
		ns.GamesFx_Float(frame.fx, "+" .. ns.Thousands(ns.BLACKJACK_START_CHIPS), "success", frame.chips, "BOTTOM", 0,
			-10, { rise = CHIP_FLOAT_DRIFT })
	end
	Draw(false)
end

-- Tooltips ------------------------------------------------------------------------------------------------------

local Line = UI.TipLine

local function StatsTooltip(owner)
	local s = Game().stats
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
	GameTooltip:SetText("Blackjack", UI.Color("heading"))
	Line("Play chips only, kept between sessions.", "textMuted", true)
	Line(" ")
	GameTooltip:AddDoubleLine("Hands played", ns.Thousands(s.hands), UI.Color("textMuted"))
	GameTooltip:AddDoubleLine("Won / lost / pushed", ("%s / %s / %s"):format(ns.Thousands(s.wins),
		ns.Thousands(s.losses), ns.Thousands(s.pushes)), UI.Color("textMuted"))
	GameTooltip:AddDoubleLine("Blackjacks", ns.Thousands(s.blackjacks), UI.Color("textMuted"))
	GameTooltip:AddDoubleLine("Biggest win", ns.Thousands(s.biggestWin), UI.Color("textMuted"))
	GameTooltip:AddDoubleLine("Best win streak", ns.Thousands(s.bestStreak), UI.Color("textMuted"))
	GameTooltip:AddDoubleLine("Most chips held", ns.Thousands(s.peak), UI.Color("textMuted"))
	if s.refills > 0 then
		GameTooltip:AddDoubleLine("House chips taken", ns.Thousands(s.refills), UI.Color("textMuted"))
	end
	Line(" ")
	Line(("%d cards left in the shoe"):format(ns.Blackjack_Left(Game())), "textFaint")
	GameTooltip:Show()
end

local function ButtonTip(button, text)
	button:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		Line(text, "text", true)
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", GameTooltip_Hide)
end

-- Building ------------------------------------------------------------------------------------------------------

local function Button(parent, width, text, onClick, tip)
	local b = UI.Button(parent, width, text)
	b:SetHeight(24)
	b:SetScript("OnClick", onClick)
	if tip then
		ButtonTip(b, tip)
	end
	return b
end

local function SetUsable(button, usable)
	button:SetEnabled(usable)
	button:SetAlpha(usable and 1 or 0.35)
end

local function SavePlace()
	local point, _, relPoint, x, y = frame:GetPoint()
	db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = point, relPoint, x, y
end

local function ApplyPlace()
	frame:ClearAllPoints()
	frame:SetPoint(db.frame.point, UIParent, db.frame.relPoint, db.frame.x, db.frame.y)
end

local function NewHandRow(parent)
	local row = { cards = {} }
	for i = 1, MAX_CARDS do
		row.cards[i] = ns.GamesCard_Create(parent)
	end
	row.value = UI.Text(parent, 13, "heading", "number")
	row.value:SetJustifyH("CENTER")
	row.bet = UI.Text(parent, 11, "textMuted")
	row.bet:SetJustifyH("CENTER")
	row.mark = UI.Hairline(parent, 90, 1, "accent")
	-- Behind a winning hand: the cards are child frames, so any texture of the window is under them.
	row.glow = parent:CreateTexture(nil, "ARTWORK")
	row.glow:SetTexture(ns.Theme.media.glow)
	row.glow:SetBlendMode("ADD")
	row.glow:SetVertexColor(UI.Color("success"))
	row.glow:Hide()
	return row
end

local function Create()
	frame = UI.Dialog("TomteBlackjack", WIDTH, HEIGHT)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePlace()
	end)
	ApplyPlace()

	local title = UI.Text(frame, 16, "heading", "title")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Blackjack")

	local close = UI.Button(frame, 20, "x")
	close:SetPoint("TOPRIGHT", -10, -10)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local chips = CreateFrame("Frame", nil, frame)
	chips:SetSize(150, 20)
	chips:SetPoint("TOPRIGHT", close, "TOPLEFT", -10, 0)
	chips:EnableMouse(true)
	chips:SetScript("OnEnter", StatsTooltip)
	chips:SetScript("OnLeave", GameTooltip_Hide)
	frame.chips = UI.Text(chips, 15, "accent", "number")
	frame.chips:SetPoint("RIGHT")
	frame.chips:SetJustifyH("RIGHT")

	local rule = UI.Hairline(frame, WIDTH - 40, 0.5)
	rule:SetPoint("TOP", 0, -42)

	frame.dealerLabel = UI.Text(frame, 12, "textMuted", "label")
	frame.dealerLabel:SetPoint("TOP", 0, -54)
	frame.dealer = NewHandRow(frame)
	frame.dealer.bet:Hide()
	frame.dealer.mark:Hide()

	frame.message = UI.Text(frame, MESSAGE_SIZE, "text")
	frame.message:SetPoint("CENTER", frame, "TOP", 0, DEALER_Y - ns.GAMES_CARD_H - 26)
	frame.message:SetWidth(WIDTH - 40)
	frame.message:SetJustifyH("CENTER")

	frame.hands = { NewHandRow(frame), NewHandRow(frame) }

	-- "Blackjack!" over your hand: pops in big, then fades.
	-- Above the cards: the banner and floating numbers.
	frame.fx = CreateFrame("Frame", nil, frame)
	frame.fx:SetAllPoints()
	frame.fx:SetFrameLevel(frame:GetFrameLevel() + (MAX_CARDS + 2) * ns.GAMES_CARD_LEVELS)
	frame.banner = UI.Text(frame.fx, BANNER_SIZE, "warning", "title")
	frame.banner:SetPoint("CENTER", frame, "TOP", 0, PLAYER_Y - ns.GAMES_CARD_H / 2)
	frame.banner:Hide()
	frame.bannerFade = frame.banner:CreateAnimationGroup()
	local bannerOut = frame.bannerFade:CreateAnimation("Alpha")
	bannerOut:SetFromAlpha(1)
	bannerOut:SetToAlpha(0)
	bannerOut:SetStartDelay(1.4)
	bannerOut:SetDuration(0.6)
	frame.bannerFade:SetScript("OnFinished", function()
		frame.banner:Hide()
	end)

	-- Bottom row: chips and Deal between rounds, the play buttons during one.
	local bottom = CreateFrame("Frame", nil, frame)
	bottom:SetSize(WIDTH - 32, 24)
	bottom:SetPoint("BOTTOM", 0, 14)
	frame.bottom = bottom

	frame.betting = CreateFrame("Frame", nil, bottom)
	frame.betting:SetAllPoints()
	local prev
	for _, amount in ipairs(ns.BLACKJACK_CHIPS) do
		local b = Button(frame.betting, 46, ns.Thousands(amount), function()
			AddChip(amount)
		end)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
		else
			b:SetPoint("LEFT")
		end
		prev = b
	end
	frame.clear = Button(frame.betting, 56, "Clear", ClearBet)
	frame.clear:SetPoint("LEFT", prev, "RIGHT", 6, 0)
	frame.deal = Button(frame.betting, 90, "Deal", Deal)
	frame.deal:SetPoint("RIGHT")
	frame.betText = UI.Text(frame.betting, 13, "heading", "number")
	frame.betText:SetPoint("RIGHT", frame.deal, "LEFT", -12, 0)
	frame.betText:SetJustifyH("RIGHT")

	frame.playing = CreateFrame("Frame", nil, bottom)
	frame.playing:SetAllPoints()
	frame.hit = Button(frame.playing, 96, "Hit", function()
		Act(ns.Blackjack_Hit)
	end, "Take another card.")
	frame.stand = Button(frame.playing, 96, "Stand", function()
		Act(ns.Blackjack_Stand)
	end, "Keep this hand; the dealer plays.")
	frame.double = Button(frame.playing, 96, "Double", function()
		Act(ns.Blackjack_Double)
	end, "Double your bet for exactly one more card.")
	frame.split = Button(frame.playing, 96, "Split", function()
		Act(ns.Blackjack_Split)
	end, "Split the pair into two hands, each with its own bet.")
	local x = -((96 * 4 + 8 * 3) / 2) + 48
	for _, b in ipairs({ frame.hit, frame.stand, frame.double, frame.split }) do
		b:SetPoint("CENTER", bottom, "CENTER", x, 0)
		x = x + 104
	end

	frame.refill = Button(bottom, 140, "House chips", Refill,
		("Out of chips: the house gives you %s to play on."):format(ns.Thousands(ns.BLACKJACK_START_CHIPS)))
	frame.refill:SetPoint("CENTER")

	frame:HookScript("OnHide", function(self)
		if not self:IsShown() then -- closed, not just hidden with UIParent (Alt+Z, a cinematic)
			Sound("close")
		end
		GameTooltip_Hide()
		if revealTimer then
			revealTimer:Cancel()
			revealTimer = nil
		end
		shown.round = nil -- shown again later: draw the table as it is, without replaying the deal
	end)
end

-- Drawing -------------------------------------------------------------------------------------------------------

-- Puts a row of cards with its left edge at x, top at y; one card frame shown per entry of cards.
local function LayoutRow(row, cards, x, y)
	for i, card in ipairs(row.cards) do
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", frame, "TOP", x + (i - 1) * CARD_STEP, y)
		card:SetLevel(frame:GetFrameLevel() + i * ns.GAMES_CARD_LEVELS)
		card:SetShown(cards[i] ~= nil)
	end
end

local function RowWidth(n)
	return ns.GAMES_CARD_W + math.max(n - 1, 0) * CARD_STEP
end

-- Deals the cards past `from` in row (with `cards`) with a slide, the first after `delay`, `step` apart.
-- Returns the delay after the last.
local function DealNew(row, cards, from, delay, step)
	for i = from + 1, #cards do
		local card = row.cards[i]
		card:SetCard(cards[i])
		card:Deal(SLIDE_FROM_X, SLIDE_FROM_Y, delay, DealSound)
		delay = delay + step
	end
	return delay
end

local function PlaceAll(row, cards, faceDownAt)
	for i, c in ipairs(cards) do
		row.cards[i]:SetCard(i ~= faceDownAt and c or nil)
		row.cards[i]:Place()
	end
end

-- The hand rows' labels: value (and result once the round is settled and shown) and bet.
local function HandLabels(row, hand, settled, active)
	local text = ns.Blackjack_ValueText(hand.cards)
	if ns.Blackjack_IsNatural(hand) and not settled then
		text = "Blackjack"
	end
	if settled and hand.result then
		text = text .. "  ·  " .. UI.Wrap(ns.Blackjack_ResultText(hand.result), RESULT_ROLES[hand.result])
	end
	row.value:SetText(text)
	row.bet:SetText("Bet " .. ns.Thousands(hand.bet) .. (hand.doubled and " (doubled)" or ""))
	row.mark:SetShown(active)
end

-- dealing: the first cards of a round are still coming.
local function Message(game, settled, dealing)
	local round = game.round
	if not round then
		if game.chips < ns.BLACKJACK_MIN_BET then
			return "You're out of chips."
		end
		return "Place your bet, then Deal."
	end
	if round.phase == "player" then
		if #round.hands > 1 then
			return ("Hand %d of 2."):format(round.active)
		end
		return round.shuffled and "A fresh shoe, shuffled. Your move." or "Your move."
	end
	if not settled then
		return dealing and "" or "Dealer plays..."
	end
	return ns.Blackjack_RoundText(round, ns.Thousands)
end

local function ShowButtons(game, settled)
	local round = game.round
	local inPlay = round and round.phase == "player"
	local broke = not inPlay and game.chips < ns.BLACKJACK_MIN_BET and game.bet == 0
	frame.playing:SetShown(inPlay and true or false)
	frame.betting:SetShown(not inPlay and not broke)
	frame.refill:SetShown(broke and settled)
	if inPlay then
		local can = ns.Blackjack_Actions(game)
		SetUsable(frame.hit, can.hit)
		SetUsable(frame.stand, can.stand)
		SetUsable(frame.double, can.double)
		SetUsable(frame.split, can.split)
	else
		SetUsable(frame.deal, settled and game.bet >= ns.BLACKJACK_MIN_BET and game.bet <= game.chips)
		SetUsable(frame.clear, settled and game.bet > 0)
		frame.deal.label:SetText(round and not shown.betChanged and "Deal again" or "Deal")
		frame.betText:SetText("Bet " .. ns.Thousands(game.bet))
	end
	frame.betting:SetAlpha(settled and 1 or 0.35)
end

local function OutcomeRole(round)
	local net = round.net or 0
	return net > 0 and "success" or (net < 0 and "danger") or "textMuted"
end

local function SignedChips(n)
	if n > 0 then
		return "+" .. ns.Thousands(n)
	elseif n < 0 then
		return "-" .. ns.Thousands(-n)
	end
	return "Push"
end

-- A settled round on the table: winning hands glow, losing ones dim. celebrate: it just ended, here and now, so the
-- sounds, floating numbers, chip roll and the blackjack banner play too.
local function Settled(round, celebrate)
	local blackjack, allBustShown = false, true
	for i, hand in ipairs(round.hands) do
		local row = frame.hands[i]
		local won = hand.result == "win" or hand.result == "blackjack"
		local lost = hand.result == "lose" or hand.result == "bust"
		blackjack = blackjack or hand.result == "blackjack"
		allBustShown = allBustShown and bustShown[hand] == true
		for _, card in ipairs(row.cards) do
			if card:IsShown() then
				card:SetDim(lost)
			end
		end
		if won and celebrate then
			ns.GamesFx_Flash(row.glow, GLOW_REST)
		elseif won then
			row.glow:SetAlpha(GLOW_REST)
			row.glow:Show()
		else
			row.glow:Hide()
		end
		if celebrate then
			ns.GamesFx_Float(frame.fx, SignedChips(hand.payout - hand.bet), RESULT_ROLES[hand.result], row.value,
				"TOP", 0, 14)
		end
	end
	if not celebrate then
		return
	end
	local net = round.net or 0
	if blackjack then
		Sound("blackjack")
		frame.banner:SetText("Blackjack!")
		frame.banner:SetAlpha(1)
		frame.banner:Show()
		ns.GamesFx_PopText(frame.banner, "title", BANNER_SIZE, 2.2, 0.35)
		frame.bannerFade:Stop()
		frame.bannerFade:Play()
	elseif net >= BIG_WIN then
		Sound("bigWin")
	elseif net > 0 then
		Sound("win")
	elseif net == 0 then
		Sound("push")
	elseif not allBustShown then
		Sound("lose") -- a bust already had its sound when it happened
	end
	if ns.Blackjack_Value(round.dealer) > 21 then
		ShakeRow(frame.dealer)
	end
	SetChips(Game().chips, CHIP_ROLL, net > 0 and "success" or (net < 0 and "danger") or nil)
	if net ~= 0 then
		ns.GamesFx_Float(frame.fx, SignedChips(net), OutcomeRole(round), frame.chips, "BOTTOM", 0, -10,
			{ rise = CHIP_FLOAT_DRIFT })
	end
end

-- animate: new cards slide in and the dealer plays out at a pace; otherwise everything shows as it is.
function Draw(animate)
	if not (frame and frame:IsShown()) then
		return
	end
	local game = Game()
	local round = game.round
	local hands = round and round.hands or {}
	local fresh = round ~= shown.round
	if fresh then
		shown.round = round
		shown.hands = { 0, 0 }
		shown.dealer = 0
		shown.hole = false
		shown.handCount = 1
		shown.betChanged = false
		shown.celebrated = nil
		animate = animate and round ~= nil
		wipe(bustShown)
		frame.banner:Hide()
		for _, row in ipairs(frame.hands) do
			row.glow:Hide()
		end
	end
	if not animate then
		shown.hands = { #(hands[1] and hands[1].cards or {}), #(hands[2] and hands[2].cards or {}) }
		shown.dealer = round and #round.dealer or 0
		shown.hole = round and round.phase == "done" or false
	end
	if #hands > shown.handCount then
		-- Just split: the two cards of the pair are already on the table, one per hand.
		shown.hands = { 1, 1 }
		shown.handCount = #hands
		animate = true
	end

	-- Layout: one hand in the middle, two side by side.
	local widths, total = {}, 0
	for i, hand in ipairs(hands) do
		widths[i] = RowWidth(#hand.cards)
		total = total + widths[i]
	end
	total = total + (#hands > 1 and HAND_GAP or 0)
	local x = -total / 2
	for i, row in ipairs(frame.hands) do
		local hand = hands[i]
		if hand then
			LayoutRow(row, hand.cards, x, PLAYER_Y)
			row.value:ClearAllPoints()
			row.value:SetPoint("TOP", frame, "TOP", x + widths[i] / 2, PLAYER_Y - ns.GAMES_CARD_H - 8)
			row.bet:ClearAllPoints()
			row.bet:SetPoint("TOP", row.value, "BOTTOM", 0, -3)
			row.mark:ClearAllPoints()
			row.mark:SetPoint("TOP", frame, "TOP", x + widths[i] / 2, PLAYER_Y + 8)
			row.glow:ClearAllPoints()
			row.glow:SetPoint("CENTER", frame, "TOP", x + widths[i] / 2, PLAYER_Y - ns.GAMES_CARD_H / 2)
			row.glow:SetSize(widths[i] + 110, ns.GAMES_CARD_H + 90)
			x = x + widths[i] + HAND_GAP
		else
			LayoutRow(row, {}, 0, PLAYER_Y)
		end
		row.value:SetShown(hand ~= nil)
		row.bet:SetShown(hand ~= nil)
		row.mark:SetShown(false)
	end
	local dealerCards = round and round.dealer or {}
	LayoutRow(frame.dealer, dealerCards, -RowWidth(#dealerCards) / 2, DEALER_Y)
	frame.dealer.value:ClearAllPoints()
	frame.dealer.value:SetPoint("LEFT", frame.dealerLabel, "RIGHT", 8, 0)

	-- Cards: what was on the table already is placed, the new ones slide in, then (round over) the hole card turns
	-- and the dealer's draws follow. The hole card stays face down until it has turned.
	local holeAt = not shown.hole and 2 or nil
	local delay = 0
	if round then
		local before = { shown.hands[1], shown.hands[2] }
		local beforeDealer = shown.dealer
		for i, hand in ipairs(hands) do
			PlaceAll(frame.hands[i], { unpack(hand.cards, 1, math.min(before[i], #hand.cards)) })
		end
		PlaceAll(frame.dealer, { unpack(round.dealer, 1, math.min(beforeDealer, #round.dealer)) }, holeAt)
		if fresh and animate then
			if round.shuffled then
				-- A fresh shoe: a riffle of card sounds before the deal.
				for t = 0, SHUFFLE_TIME - 0.1, 0.07 do
					C_Timer.After(t, DealSound)
				end
				delay = SHUFFLE_TIME
			end
			-- The first four in deal order: you, dealer, you, dealer.
			local order = { { frame.hands[1], hands[1].cards, 1 }, { frame.dealer, round.dealer, 1 },
				{ frame.hands[1], hands[1].cards, 2 }, { frame.dealer, round.dealer, 2 } }
			for _, o in ipairs(order) do
				local row, cards, i = o[1], o[2], o[3]
				row.cards[i]:SetCard(not (row == frame.dealer and i == holeAt) and cards[i] or nil)
				row.cards[i]:Deal(SLIDE_FROM_X, SLIDE_FROM_Y, delay, DealSound)
				delay = delay + DEAL_STAGGER
			end
			before[1], beforeDealer = 2, 2
		end
		for i, hand in ipairs(hands) do
			delay = DealNew(frame.hands[i], hand.cards, before[i], delay, DEAL_STAGGER)
			shown.hands[i] = #hand.cards
		end
		if round.phase == "done" then
			if holeAt then
				if animate then
					delay = delay + DEAL_STAGGER
					frame.dealer.cards[2]:Flip(round.dealer[2], delay, FlipSound)
					delay = delay + DEALER_PACE
				else
					frame.dealer.cards[2]:SetCard(round.dealer[2])
				end
				shown.hole = true
			end
			delay = DealNew(frame.dealer, round.dealer, beforeDealer, delay, DEALER_PACE)
		end
		shown.dealer = #round.dealer
	end

	-- Labels, message and buttons: the result waits until the last card is down.
	local settledShown = not (round and round.phase == "done" and animate and delay > 0)
	local function Labels(settled)
		local inPlay = round and round.phase == "player"
		local visibleDealer = round and (inPlay and { round.dealer[1] } or round.dealer) or {}
		frame.dealerLabel:SetText(round and "Dealer" or "")
		local dealerText = ""
		if round and settled and round.dealerNatural then
			dealerText = "Blackjack"
		elseif round and (settled or inPlay) then
			dealerText = ns.Blackjack_ValueText(visibleDealer)
		end
		frame.dealer.value:SetText(dealerText)
		for i, hand in ipairs(hands) do
			HandLabels(frame.hands[i], hand, settled, inPlay and #hands > 1 and round.active == i)
		end
		local chips = game.chips
		if round and round.phase == "done" and not settled then
			for _, hand in ipairs(hands) do
				chips = chips - (hand.payout or 0)
			end
		end
		local done = settled and round and round.phase == "done"
		local celebrate = done and animate and shown.celebrated ~= round
		if done then
			shown.celebrated = round
			Settled(round, celebrate)
		end
		if not celebrate then
			SetChips(chips, animate and 0.3)
		end
		frame.message:SetText(Message(game, settled, fresh))
		UI.SetTextRole(frame.message, done and OutcomeRole(round) or "text")
		if celebrate then
			ns.GamesFx_PopText(frame.message, "body", MESSAGE_SIZE, 1.3, 0.3)
		end
		ShowButtons(game, settled)
	end
	if revealTimer then
		revealTimer:Cancel()
		revealTimer = nil
	end
	if settledShown then
		Labels(true)
	else
		Labels(false)
		revealTimer = C_Timer.NewTimer(delay + 0.1, function()
			revealTimer = nil
			Labels(true)
		end)
	end
end

-- API -----------------------------------------------------------------------------------------------------------

function ns.BlackjackTable_Init(saved)
	db = saved
end

function ns.BlackjackTable_Show()
	if not frame then
		Create()
	end
	UI.PlaceDialog(frame)
	if not frame:IsShown() then
		Sound("open")
	end
	frame:Show()
	Draw(false)
end

function ns.BlackjackTable_Hide()
	if frame then
		frame:Hide()
	end
end

function ns.BlackjackTable_IsShown()
	return frame ~= nil and frame:IsShown()
end

function ns.BlackjackTable_Toggle()
	if ns.BlackjackTable_IsShown() then
		ns.BlackjackTable_Hide()
	else
		ns.BlackjackTable_Show()
	end
end

function ns.BlackjackTable_Refresh()
	Draw(false)
end

function ns.BlackjackTable_ResetPlace()
	db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = "CENTER", "CENTER", 0, 60
	if frame then
		ApplyPlace()
	end
end
