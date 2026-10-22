local addonName, ns = ...

-- Blackjack: the table, the blackjack face of the casino window (Window.lua). A classic half-moon table (Felt.lua):
-- dealer row on top, the rules printed across the middle, your hand or hands below with their bets in betting circles,
-- a message line near the rail, the bet chips or the play buttons under the table. Rules and the saved game in
-- BlackjackRules.lua and ChipRules.lua; cards in Card.lua; registered in Blackjack.lua.

local WIDTH = ns.GAMES_WINDOW_W
local CARD_STEP = 30 -- pixels between overlapping cards in a hand
local HAND_GAP = 70 -- pixels between two split hands
local MAX_CARDS = 11 -- the most cards a hand can hold without busting (four aces, four twos, three threes)
local DEAL_STAGGER = 0.15 -- seconds between the first four cards
local DEALER_PACE = 0.55 -- seconds between the dealer's cards once you stand
local DEALER_Y, PLAYER_Y = -70, -246 -- card rows' tops, from the window's top (around the print on the felt)
local SPOT_Y = -368 -- the betting circles' middles
local MESSAGE_Y = -402 -- the message line's middle, just inside the rail
local RESULT_ROLES = { blackjack = "success", win = "success", push = "textMuted", lose = "danger", bust = "danger" }
local BIG_WIN = 500 -- chips won in one round that count as a big win (a bigger sound)
local SHUFFLE_TIME = 0.4 -- seconds of shuffling sounds before the first card of a fresh shoe
local CHIP_ROLL = 0.8 -- seconds for the chip count to roll to a round's payout
local GLOW_REST = 0.35 -- a winning hand's glow once it has flashed
local MESSAGE_SIZE, BANNER_SIZE = 14, 30 -- font sizes of the message line and the "Blackjack!" banner
local PLAY_W, PLAY_H, PLAY_ICON, PLAY_GAP = 56, 34, 26, 8 -- the play buttons: size, icon size, space between
local PLAY_LABEL = 14 -- pixels under the play buttons for their names
local PLAY_MEDIA = "Interface\\AddOns\\Tomte\\Media\\Games\\"

local UI = ns.UI
local Sound, SetChips, ChipFloat = ns.GamesWindow_Sound, ns.GamesWindow_SetChips, ns.GamesWindow_ChipFloat
local Button, SetUsable = ns.GamesWindow_Button, ns.GamesWindow_SetUsable

local db, frame -- frame: the felt, this face's root (it covers the window)
local face = { key = "blackjack", name = "Blackjack" }
local Draw
-- What the window shows of the round, so only new cards animate: the round table, cards shown per hand and for
-- the dealer, whether the hole card is face up, and which round's result has had its sounds and effects.
local shown = { round = nil, hands = {}, dealer = 0, hole = false, handCount = 1 }
local revealTimer
local bustShown = {} -- [hand] = true: already shook and sounded when it busted

local function Game()
	return db.game
end

local function Random(n)
	return math.random(n)
end

local function DealSound()
	Sound("deal")
end

local function FlipSound()
	Sound("flip")
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
			if ns.GamesWindow_Showing(face) and row then
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
		-- Over the bet text, right-aligned with it, but anchored to Deal: the text pops (changes size) as it floats.
		ns.GamesFx_Float(frame.fx, "+" .. ns.Thousands(game.bet - before), "accent", frame.deal, "LEFT", -12, 7,
			{ size = 13, own = "BOTTOMRIGHT" })
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

-- Tooltip lines (Window.lua's chip count tooltip) -------------------------------------------------------------------

function face.Stats(line, double)
	local s = Game().stats
	double("Hands played", ns.Thousands(s.hands))
	double("Won / lost / pushed", ("%s / %s / %s"):format(ns.Thousands(s.wins), ns.Thousands(s.losses),
		ns.Thousands(s.pushes)))
	double("Blackjacks", ns.Thousands(s.blackjacks))
	double("Biggest win", ns.Thousands(s.biggestWin))
	double("Best win streak", ns.Thousands(s.bestStreak))
end

function face.StatsFooter(line)
	line(("%d cards left in the shoe"):format(ns.Blackjack_Left(Game())), "textFaint")
end

-- Building ------------------------------------------------------------------------------------------------------

-- A play button: an icon in its color role with its name underneath, the border taking that color on hover.
local function PlayButton(parent, icon, role, name, onClick)
	local b = Button(parent, PLAY_W, nil, onClick)
	b:SetHeight(PLAY_H)
	b.name = UI.Text(b, 10, "textMuted", "label")
	b.name:SetPoint("TOP", b, "BOTTOM", 0, -3)
	b.name:SetText(name)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(PLAY_ICON, PLAY_ICON)
	b.icon:SetPoint("CENTER")
	b.icon:SetTexture(PLAY_MEDIA .. icon)
	b.icon:SetVertexColor(UI.Color(role))
	b:HookScript("OnEnter", function(self)
		UI.SetBorderColor(self, role, 1)
	end)
	b:HookScript("OnMouseDown", function(self)
		self.icon:SetPoint("CENTER", 1, -1)
	end)
	b:HookScript("OnMouseUp", function(self)
		self.icon:SetPoint("CENTER")
	end)
	return b
end

local function NewHandRow(parent)
	local row = { cards = {} }
	for i = 1, MAX_CARDS do
		row.cards[i] = ns.GamesCard_Create(parent)
	end
	row.value = UI.Text(parent, 13, "heading", "number")
	row.value:SetJustifyH("CENTER")
	row.bet = UI.Text(parent, 11, "text", "number")
	row.mark = UI.Hairline(parent, 90, 1, "accent")
	-- Behind a winning hand: the cards are child frames, so any texture of the window is under them.
	row.glow = parent:CreateTexture(nil, "ARTWORK")
	row.glow:SetTexture(ns.Theme.media.glow)
	row.glow:SetBlendMode("ADD")
	row.glow:SetVertexColor(UI.Color("success"))
	row.glow:Hide()
	return row
end

-- The table: the felt and everything on it, on a frame the Cashier swaps out.
function face.Create(window)
	local felt = ns.BlackjackFelt_Create(window)
	frame = felt

	frame.dealerLabel = UI.Text(felt, 12, "textMuted", "label")
	frame.dealerLabel:SetPoint("TOP", 0, -52)
	frame.dealer = NewHandRow(felt)
	frame.dealer.bet:Hide()
	frame.dealer.mark:Hide()

	frame.message = UI.Text(felt, MESSAGE_SIZE, "text")
	frame.message:SetPoint("CENTER", frame, "TOP", 0, MESSAGE_Y)
	frame.message:SetWidth(WIDTH - 140)
	frame.message:SetJustifyH("CENTER")

	frame.hands = { NewHandRow(felt), NewHandRow(felt) }

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

	-- Bottom row, under the table: chips and Deal between rounds, the play buttons during one.
	local bottom = CreateFrame("Frame", nil, felt)
	bottom:SetSize(WIDTH - 32, PLAY_H + PLAY_LABEL) -- the bet controls center on the play buttons' height
	bottom:SetPoint("BOTTOM", 0, 10)
	frame.bottom = bottom

	frame.betting = CreateFrame("Frame", nil, bottom)
	frame.betting:SetAllPoints()
	local prev
	for _, amount in ipairs(ns.BLACKJACK_CHIPS) do
		local b = ns.BlackjackFelt_ChipButton(frame.betting, amount, function()
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
	frame.clear:SetPoint("LEFT", prev, "RIGHT", 10, 0)
	frame.deal = Button(frame.betting, 90, "Deal", Deal)
	frame.deal:SetPoint("RIGHT")
	frame.betText = UI.Text(frame.betting, 13, "heading", "number")
	frame.betText:SetPoint("RIGHT", frame.deal, "LEFT", -12, 0)
	frame.betText:SetJustifyH("RIGHT")

	frame.playing = CreateFrame("Frame", nil, bottom)
	frame.playing:SetAllPoints()
	frame.stand = PlayButton(frame.playing, "Stand", "danger", "Stand", function()
		Act(ns.Blackjack_Stand)
	end)
	frame.split = PlayButton(frame.playing, "Split", "warning", "Split", function()
		Act(ns.Blackjack_Split)
	end)
	frame.double = PlayButton(frame.playing, "Double", "info", "Double", function()
		Act(ns.Blackjack_Double)
	end)
	frame.hit = PlayButton(frame.playing, "Hit", "success", "Hit", function()
		Act(ns.Blackjack_Hit)
	end)
	-- Left to right; Split and Double only show when you can.
	frame.playOrder = { frame.stand, frame.split, frame.double, frame.hit }

	frame.refill = ns.GamesWindow_RefillButton(bottom)
	frame.refill:SetPoint("CENTER")
	return frame
end

function face.ApplyLook(felt)
	ns.BlackjackFelt_SetFelt(frame, felt)
end

-- The window closed or another face took its place.
function face.OnHide()
	if revealTimer then
		revealTimer:Cancel()
		revealTimer = nil
		ns.Blackjack_CheckFeats() -- the cut-off reveal would have checked them
	end
	shown.round = nil -- shown again later: draw the table as it is, without replaying the deal
end

-- The round's payout is held back from the chip count until the cards are down.
function face.Busy()
	return revealTimer ~= nil
end

-- Drawing -------------------------------------------------------------------------------------------------------

-- Puts a row of cards with its left edge at x, top at y; one card frame shown per entry of cards. Each card notes
-- how far away the shoe is: dealt cards slide from there.
local function LayoutRow(row, cards, x, y)
	for i, card in ipairs(row.cards) do
		local left = x + (i - 1) * CARD_STEP
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", frame, "TOP", left, y)
		card.fromX = ns.BLACKJACK_SHOE_X - (WIDTH / 2 + left + ns.GAMES_CARD_W / 2)
		card.fromY = ns.BLACKJACK_SHOE_Y - (y - ns.GAMES_CARD_H / 2)
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
		card:Deal(card.fromX, card.fromY, delay, DealSound)
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
	row.bet:SetText(ns.Thousands(hand.bet) .. (hand.doubled and " (doubled)" or ""))
	row.mark:SetShown(active)
end

-- dealing: the first cards of a round are still coming.
local function Message(game, settled, dealing)
	local round = game.round
	if not round then
		return ns.GamesWindow_BrokeText() or "Place your bet, then Deal."
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

-- The shown play buttons side by side, centered, their names on the bottom row's bottom.
local function LayoutPlay()
	local shownButtons = {}
	for _, b in ipairs(frame.playOrder) do
		if b:IsShown() then
			shownButtons[#shownButtons + 1] = b
		end
	end
	local x = -((#shownButtons - 1) * (PLAY_W + PLAY_GAP)) / 2
	for _, b in ipairs(shownButtons) do
		b:ClearAllPoints()
		b:SetPoint("BOTTOM", frame.bottom, "BOTTOM", x, PLAY_LABEL)
		x = x + PLAY_W + PLAY_GAP
	end
end

local function ShowButtons(game, settled)
	local round = game.round
	local inPlay = round and round.phase == "player"
	local broke = not inPlay and game.chips < ns.BLACKJACK_MIN_BET and game.bet == 0
	frame.playing:SetShown(inPlay and true or false)
	frame.betting:SetShown(not inPlay and not broke)
	frame.refill:SetShown(broke and settled and ns.GamesWindow_RefillReady())
	if inPlay then
		local can = ns.Blackjack_Actions(game)
		SetUsable(frame.hit, can.hit)
		SetUsable(frame.stand, can.stand)
		frame.double:SetShown(can.double)
		frame.split:SetShown(can.split)
		LayoutPlay()
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
		ChipFloat(SignedChips(net), OutcomeRole(round))
	end
	ns.Blackjack_CheckFeats()
end

-- animate: new cards slide in and the dealer plays out at a pace; otherwise everything shows as it is.
function Draw(animate)
	if not ns.GamesWindow_Showing(face) then
		return
	end
	local game = Game()
	local round = game.round
	local hands = round and round.hands or {}
	local fresh = round ~= shown.round
	ns.GamesWindow_UpdateRank()
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
			row.value:SetPoint("TOP", frame, "TOP", x + widths[i] / 2, PLAYER_Y - ns.GAMES_CARD_H - 6)
			local ring = ns.BlackjackFelt_Spot(frame, i, true, x + widths[i] / 2, SPOT_Y, hand.bet)
			row.bet:ClearAllPoints()
			row.bet:SetPoint("LEFT", ring, "RIGHT", 4, 0)
			row.mark:ClearAllPoints()
			row.mark:SetPoint("TOP", frame, "TOP", x + widths[i] / 2, PLAYER_Y + 8)
			row.glow:ClearAllPoints()
			row.glow:SetPoint("CENTER", frame, "TOP", x + widths[i] / 2, PLAYER_Y - ns.GAMES_CARD_H / 2)
			row.glow:SetSize(widths[i] + 110, ns.GAMES_CARD_H + 90)
			x = x + widths[i] + HAND_GAP
		else
			LayoutRow(row, {}, 0, PLAYER_Y)
			-- Between rounds the first circle holds the bet being placed.
			ns.BlackjackFelt_Spot(frame, i, i == 1, 0, SPOT_Y, i == 1 and game.bet or nil)
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
				local card = row.cards[i]
				card:SetCard(not (row == frame.dealer and i == holeAt) and cards[i] or nil)
				card:Deal(card.fromX, card.fromY, delay, DealSound)
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

face.Draw = Draw
ns.GamesWindow_AddFace(face)
