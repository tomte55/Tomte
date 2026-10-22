local addonName, ns = ...

-- Video poker: the machine, a face of the casino window (Window.lua). A screen in the felt's color with the pay table
-- on top (one column per bet, the current one lit), five big cards (click to hold), the message line and the bet and
-- win readouts; under it the coin chips, Bet one, Bet max and Deal/Draw. Rules in PokerRules.lua; cards in Card.lua;
-- registered in Casino.lua.

local WIDTH = ns.GAMES_WINDOW_W
local SCREEN_TOP, SCREEN_BOTTOM = -46, -434 -- the screen's edges, from the window's top
local SCREEN_INSET = 12 -- pixels from the window's sides to the screen
local TABLE_TOP = -56 -- the pay table's header row
local ROW_H = 15 -- pixels per pay table row
local NAME_X = 28 -- the hand names' left edge
local COL_W = 66 -- pixels per pay column (right-aligned numbers)
local COLS_RIGHT = -28 -- the last column's right edge, from the window's right
local CARD_SCALE = 1.35 -- the cards are Card.lua's, drawn this much bigger
local CARD_GAP = 16
local CARDS_TOP = -216
local HELD_LIFT = 10 -- pixels a held card rises
local HELD_Y = -334 -- the "Held" tags' middles
local MESSAGE_Y = -362
local READOUT_Y = -406
local DEAL_STAGGER = 0.09 -- seconds between the five cards of a deal
local DRAW_STAGGER = 0.14 -- seconds between the new cards of a draw
local DEAL_DROP = 40 -- pixels a dealt card slides down from
local CHIP_ROLL = 0.8
local BIG_WIN = 500 -- chips won in one hand that count as a big win (a bigger sound)
local BANNER_SIZE, MESSAGE_SIZE = 30, 14
local BANNER_FROM = "quads" -- this hand and better get a banner
local SCREEN_DIM = 0.42 -- the felt color times this for the screen (a touch darker than the table)

local UI = ns.UI
local Sound, SetChips, ChipFloat = ns.GamesWindow_Sound, ns.GamesWindow_SetChips, ns.GamesWindow_ChipFloat
local Button, SetUsable = ns.GamesWindow_Button, ns.GamesWindow_SetUsable

local db, root
local face = { key = "poker", name = "Video poker" }
local Draw
-- What the screen shows, so only changes animate: the round table and its phase when last drawn, and which round's
-- result has had its sounds and effects.
local shown = { round = nil, phase = nil, celebrated = nil }
local revealTimer

local function Game()
	return db.game
end

local function Poker()
	return db.game.poker
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

-- Hands from BANNER_FROM up, best first.
local function BannerHand(key)
	for _, hand in ipairs(ns.POKER_HANDS) do
		if hand.key == key then
			return true
		end
		if hand.key == BANNER_FROM then
			return false
		end
	end
	return false
end

-- Actions -------------------------------------------------------------------------------------------------------

local function Deal()
	if revealTimer then
		return
	end
	local game = Game()
	if ns.Poker_InPlay(game) then
		ns.Poker_Draw(game)
	elseif not ns.Poker_Deal(game, Random) then
		return
	end
	Draw(true)
end

local function BetMax()
	if revealTimer or ns.Poker_InPlay(Game()) then
		return
	end
	ns.Poker_SetCoins(Game(), ns.POKER_MAX_COINS)
	Sound("chip")
	if Game().chips >= ns.Poker_Bet(Game()) then
		Deal()
	else
		Draw(false)
	end
end

local function BetOne()
	if revealTimer or not ns.Poker_BetOne(Game()) then
		return
	end
	Sound("chip")
	ns.GamesFx_PopText(root.betText, "number", 13, 1.35, 0.2)
	Draw(false)
end

local function SetCoin(value)
	if revealTimer or not ns.Poker_SetCoin(Game(), value) then
		return
	end
	Sound("chip")
	ns.GamesFx_PopText(root.betText, "number", 13, 1.35, 0.2)
	Draw(false)
end

local function PlaceCard(i)
	local round = Poker().round
	local card = root.cards[i]
	local lift = round and round.phase == "hold" and round.held[i] and HELD_LIFT or 0
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", root, "TOPLEFT", card.x / CARD_SCALE, (CARDS_TOP + lift) / CARD_SCALE)
end

local function Hold(i)
	if revealTimer then
		return
	end
	local held = ns.Poker_Hold(Game(), i)
	if held == nil then
		return
	end
	Sound(held and "hold" or "release")
	PlaceCard(i)
	root.held[i]:SetShown(held)
end

-- Tooltip lines (Window.lua's chip count tooltip) -------------------------------------------------------------------

function face.Stats(line, double)
	local s = Poker().stats
	double("Hands played", ns.Thousands(s.hands))
	double("Hands won", ns.Thousands(s.wins))
	double("Biggest win", ns.Thousands(s.biggestWin))
	ns.GamesWindow_NetLines(double, "poker", s.net)
	for _, hand in ipairs(ns.POKER_HANDS) do
		if hand.key ~= "jacks" and s[hand.key] > 0 then
			double(hand.name, ns.Thousands(s[hand.key]))
		end
	end
end

-- Building ------------------------------------------------------------------------------------------------------

-- The pay table: a header of bets, a row per hand with its pay in chips per bet, a bar under the current bet's column
-- and one behind the winning row.
local function BuildPayTable()
	local t = { rows = {}, heads = {} }
	local function ColumnRight(c)
		return COLS_RIGHT - (ns.POKER_MAX_COINS - c) * COL_W
	end
	t.column = root:CreateTexture(nil, "ARTWORK")
	t.column:SetColorTexture(UI.Color("accentDeep"))
	t.column:SetAlpha(0.55)
	t.column:SetSize(COL_W - 6, ROW_H * (#ns.POKER_HANDS + 1) + 6)
	t.win = root:CreateTexture(nil, "ARTWORK", nil, 1)
	t.win:SetTexture(ns.Theme.media.glow)
	t.win:SetBlendMode("ADD")
	t.win:SetVertexColor(UI.Color("warning"))
	t.win:SetSize(WIDTH - 2 * SCREEN_INSET - 20, ROW_H + 10)
	t.win:Hide()
	for c = 1, ns.POKER_MAX_COINS do
		local head = UI.Text(root, 10, "textMuted", "label")
		head:SetPoint("TOPRIGHT", root, "TOPRIGHT", ColumnRight(c), TABLE_TOP)
		head:SetJustifyH("RIGHT")
		t.heads[c] = head
	end
	for n, hand in ipairs(ns.POKER_HANDS) do
		local y = TABLE_TOP - n * ROW_H
		local row = { key = hand.key, cells = {} }
		row.name = UI.Text(root, 12, "text", "label")
		row.name:SetPoint("TOPLEFT", root, "TOPLEFT", NAME_X, y)
		row.name:SetText(hand.name)
		for c = 1, ns.POKER_MAX_COINS do
			local cell = UI.Text(root, 12, "text", "number")
			cell:SetPoint("TOPRIGHT", root, "TOPRIGHT", ColumnRight(c), y)
			cell:SetJustifyH("RIGHT")
			row.cells[c] = cell
		end
		row.y = y
		t.rows[n] = row
	end
	t.ColumnRight = ColumnRight
	return t
end

-- The pay table for this coin value, the bet's column lit, `winKey`'s row lit (flash: it just won).
local function PaintPayTable(coin, coins, winKey, flash)
	local t = root.payTable
	for c = 1, ns.POKER_MAX_COINS do
		t.heads[c]:SetText("Bet " .. ns.Thousands(coin * c))
		UI.SetTextRole(t.heads[c], c == coins and "heading" or "textMuted")
	end
	t.column:ClearAllPoints()
	t.column:SetPoint("TOPRIGHT", root, "TOPRIGHT", t.ColumnRight(coins) + 3, TABLE_TOP + 3)
	local winRow
	for _, row in ipairs(t.rows) do
		local won = row.key == winKey
		if won then
			winRow = row
		end
		UI.SetTextRole(row.name, won and "warning" or "text")
		for c, cell in ipairs(row.cells) do
			cell:SetText(ns.Thousands(ns.Poker_Pay(row.key, c) * coin))
			UI.SetTextRole(cell, won and c == coins and "warning" or (c == coins and "heading" or "textMuted"))
		end
	end
	if winRow then
		t.win:ClearAllPoints()
		t.win:SetPoint("LEFT", root, "TOPLEFT", SCREEN_INSET + 10, winRow.y - ROW_H / 2 + 1)
		if flash then
			ns.GamesFx_Flash(t.win, 0.45)
		else
			t.win:SetAlpha(0.45)
			t.win:Show()
		end
	else
		t.win:Hide()
	end
end

-- A coin button: Felt.lua's chip, with a ring around the coin value in use.
local function CoinButton(parent, value)
	local b = ns.BlackjackFelt_ChipButton(parent, value, function()
		SetCoin(value)
	end)
	b.ring = b:CreateTexture(nil, "OVERLAY")
	b.ring:SetTexture("Interface\\AddOns\\Tomte\\Media\\Games\\Ring")
	b.ring:SetPoint("CENTER")
	b.ring:SetSize(50, 50)
	b.ring:SetVertexColor(UI.Color("accent"))
	b.value = value
	return b
end

function face.Create(window)
	root = CreateFrame("Frame", nil, window)
	root:SetAllPoints()
	root:SetFrameLevel(window:GetFrameLevel() + 1)

	-- The screen: a fill on root itself (a child frame's fill would cover root's text), its border on a frame.
	root.screen = root:CreateTexture(nil, "BACKGROUND")
	root.screen:SetPoint("TOPLEFT", root, "TOPLEFT", SCREEN_INSET, SCREEN_TOP)
	root.screen:SetPoint("BOTTOMRIGHT", root, "TOPRIGHT", -SCREEN_INSET, SCREEN_BOTTOM)
	local edge = CreateFrame("Frame", nil, root)
	edge:SetAllPoints(root.screen)
	UI.Border(edge, "frameDark", 0.9)

	root.payTable = BuildPayTable()
	local rule = UI.Hairline(root, WIDTH - 2 * SCREEN_INSET - 40, 0.6, "accent")
	rule:SetPoint("TOP", root, "TOP", 0, TABLE_TOP - (#ns.POKER_HANDS + 1) * ROW_H - 4)

	-- Five cards, centered, each a click target that holds it.
	local cardW = ns.GAMES_CARD_W * CARD_SCALE
	local rowW = 5 * cardW + 4 * CARD_GAP
	root.cards, root.held = {}, {}
	for i = 1, 5 do
		local card = ns.GamesCard_Create(root)
		card:SetScale(CARD_SCALE)
		card.x = (WIDTH - rowW) / 2 + (i - 1) * (cardW + CARD_GAP)
		card:SetLevel(root:GetFrameLevel() + 2)
		card:EnableMouse(true)
		card:SetScript("OnMouseDown", function(_, button)
			if button == "LeftButton" then
				Hold(i)
			end
		end)
		root.cards[i] = card
		local held = UI.Text(root, 13, "warning", "title")
		held:SetPoint("CENTER", root, "TOPLEFT", card.x + cardW / 2, HELD_Y)
		held:SetText("Held")
		held:Hide()
		root.held[i] = held
	end

	root.message = UI.Text(root, MESSAGE_SIZE, "text")
	root.message:SetPoint("CENTER", root, "TOP", 0, MESSAGE_Y)
	root.message:SetWidth(WIDTH - 80)
	root.message:SetJustifyH("CENTER")

	root.betText = UI.Text(root, 13, "heading", "number")
	root.betText:SetPoint("LEFT", root, "TOPLEFT", SCREEN_INSET + 16, READOUT_Y)
	root.winText = UI.Text(root, 13, "warning", "number")
	root.winText:SetPoint("RIGHT", root, "TOPRIGHT", -SCREEN_INSET - 16, READOUT_Y)
	root.winText:SetJustifyH("RIGHT")

	-- Above the cards: the banner and floating numbers.
	root.fx = CreateFrame("Frame", nil, root)
	root.fx:SetAllPoints()
	root.fx:SetFrameLevel(root:GetFrameLevel() + 2 + 2 * ns.GAMES_CARD_LEVELS)
	root.banner = UI.Text(root.fx, BANNER_SIZE, "warning", "title")
	root.banner:SetPoint("CENTER", root, "TOP", 0, CARDS_TOP - ns.GAMES_CARD_H * CARD_SCALE / 2)
	root.banner:Hide()
	root.bannerFade = root.banner:CreateAnimationGroup()
	local bannerOut = root.bannerFade:CreateAnimation("Alpha")
	bannerOut:SetFromAlpha(1)
	bannerOut:SetToAlpha(0)
	bannerOut:SetStartDelay(1.6)
	bannerOut:SetDuration(0.6)
	root.bannerFade:SetScript("OnFinished", function()
		root.banner:Hide()
	end)

	-- Under the screen: coin chips, Bet one, Bet max and Deal/Draw.
	local bottom = CreateFrame("Frame", nil, root)
	bottom:SetSize(WIDTH - 32, 48)
	bottom:SetPoint("BOTTOM", 0, 12)
	root.bottom = bottom
	root.controls = CreateFrame("Frame", nil, bottom)
	root.controls:SetAllPoints()
	root.coins = {}
	local prev
	for _, value in ipairs(ns.POKER_COIN_VALUES) do
		local b = CoinButton(root.controls, value)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
		else
			b:SetPoint("LEFT", 4, 0)
		end
		root.coins[#root.coins + 1] = b
		prev = b
	end
	root.betOne = Button(root.controls, 70, "Bet one", BetOne, "One more coin, up to five. Five coins make a royal "
		.. "flush pay 4,000 coins instead of 1,250.")
	root.betOne:SetPoint("LEFT", prev, "RIGHT", 14, 0)
	root.betMax = Button(root.controls, 70, "Bet max", BetMax, "Five coins, and deal.")
	root.betMax:SetPoint("LEFT", root.betOne, "RIGHT", 6, 0)
	root.deal = Button(root.controls, 100, "Deal", Deal)
	root.deal:SetPoint("RIGHT")
	root.refill = ns.GamesWindow_RefillButton(bottom)
	root.refill:SetPoint("CENTER")
	return root
end

function face.ApplyLook(felt)
	local r, g, b = UI.Color(felt.role)
	local dim = (felt.dim or ns.BLACKJACK_FELT_DIM) * SCREEN_DIM / ns.BLACKJACK_FELT_DIM
	root.screen:SetColorTexture(r * dim, g * dim, b * dim)
end

function face.OnHide()
	if revealTimer then
		revealTimer:Cancel()
		revealTimer = nil
		ns.Casino_CheckFeats() -- the cut-off reveal would have checked them
	end
	shown.round = nil -- shown again later: the cards as they are, without replaying the deal
end

function face.Busy()
	return revealTimer ~= nil
end

-- Drawing -------------------------------------------------------------------------------------------------------

-- The message for a hand on the screen; nil between hands (Labels picks the betting line).
local function Message(round, settled)
	if not round then
		return nil
	end
	if not settled then
		return "" -- cards still landing
	end
	if round.phase == "hold" then
		return ns.Poker_HoldText(round.cards) or "Click the cards you want to keep, then Draw."
	end
	return ns.Poker_RoundText(round, ns.Thousands)
end

local function OutcomeRole(round)
	if not round.result then
		return "textMuted"
	end
	return round.net > 0 and "success" or "text"
end

local function ShowControls(game, round, settled)
	local inPlay = round ~= nil and round.phase == "hold"
	local poker = game.poker
	local broke = not inPlay and game.chips < ns.BLACKJACK_MIN_BET
	root.controls:SetShown(not broke)
	root.refill:SetShown(broke and settled and ns.GamesWindow_RefillReady())
	local between = settled and not inPlay
	for _, b in ipairs(root.coins) do
		b.ring:SetShown(b.value == poker.coin)
		b:SetEnabled(between)
		b:SetAlpha(between and 1 or 0.35)
	end
	SetUsable(root.betOne, between)
	SetUsable(root.betMax, between)
	root.deal.label:SetText(inPlay and "Draw" or "Deal")
	SetUsable(root.deal, inPlay or (between and game.chips >= ns.Poker_Bet(game)))
end

-- A drawn hand on the screen: the row lights, and when it just happened (celebrate) the sounds, floats, chip roll
-- and, for the best hands, the banner.
local function Settled(round, celebrate)
	if not celebrate then
		return
	end
	if round.result then
		ns.GamesFx_PopText(root.message, "body", MESSAGE_SIZE, 1.3, 0.3)
	end
	if round.result and BannerHand(round.result) then
		Sound("jackpot")
		root.banner:SetText(ns.Poker_Hand(round.result).name .. "!")
		root.banner:SetAlpha(1)
		root.banner:Show()
		ns.GamesFx_PopText(root.banner, "title", BANNER_SIZE, 2.2, 0.35)
		root.bannerFade:Stop()
		root.bannerFade:Play()
	elseif round.net >= BIG_WIN then
		Sound("bigWin")
	elseif round.net > 0 then
		Sound("win")
	elseif round.result then
		Sound("push")
	end
	SetChips(Game().chips, CHIP_ROLL, round.net > 0 and "success" or nil)
	if round.payout > 0 then
		ChipFloat("+" .. ns.Thousands(round.payout), "success")
		ns.GamesFx_Float(root.fx, "+" .. ns.Thousands(round.payout), "success", root.winText, "RIGHT", 0, 14,
			{ own = "RIGHT" })
	end
	ns.Casino_CheckFeats()
end

-- animate: a fresh deal slides in, a draw turns the new cards over one by one, and the result waits for the last.
function Draw(animate)
	if not ns.GamesWindow_Showing(face) then
		return
	end
	local game = Game()
	local poker = game.poker
	local round = poker.round
	ns.GamesWindow_UpdateRank()
	local fresh = round ~= shown.round
	local drawing = animate and not fresh and round ~= nil and shown.phase == "hold" and round.phase == "done"
	local dealing = animate and fresh and round ~= nil
	if fresh then
		shown.celebrated = nil
		root.banner:Hide()
	end
	shown.round, shown.phase = round, round and round.phase

	local delay = 0
	for i, card in ipairs(root.cards) do
		PlaceCard(i)
		card:SetDim(false)
		if not round then
			card:SetCard(nil)
			card:Place()
		elseif dealing then
			card:SetCard(round.cards[i])
			card:Deal(0, DEAL_DROP / CARD_SCALE, delay, DealSound)
			delay = delay + DEAL_STAGGER
		elseif drawing and not round.held[i] then
			card:Place()
			card:SetCard(nil)
			delay = delay + DRAW_STAGGER
			card:Flip(round.cards[i], delay, FlipSound)
		elseif not (drawing and round.held[i]) then
			card:SetCard(round.cards[i])
			card:Place()
		end
		card:Show()
		root.held[i]:SetShown(round ~= nil and round.phase == "hold" and round.held[i])
	end
	if drawing then
		delay = delay + 0.25
	end

	local function Labels(settled)
		-- The hand's own bet while it's being played out; once it's over, the bet for the next deal (Bet one and the
		-- coin chips change that one).
		local live = round and (round.phase == "hold" or not settled)
		local coin = live and round.coin or poker.coin
		local coins = live and round.coins or poker.coins
		local done = round and round.phase == "done"
		local celebrate = done and settled and animate and shown.celebrated ~= round
		if done and settled then
			shown.celebrated = round
		end
		PaintPayTable(coin, coins, done and settled and round.result or nil, celebrate)
		local text = Message(round, settled)
		if not text then
			text = ns.GamesWindow_BrokeText()
			if not text and game.chips < ns.Poker_Bet(game) then
				text = ("Lower your bet: you have %s chips."):format(ns.Thousands(game.chips))
			end
			text = text or "Pick a coin and how many, then Deal."
		end
		root.message:SetText(text)
		UI.SetTextRole(root.message, done and settled and OutcomeRole(round) or "text")
		root.betText:SetText(("Bet %s  (%d x %s)"):format(ns.Thousands(coin * coins), coins, ns.Thousands(coin)))
		root.winText:SetText(done and settled and round.payout > 0 and ("Win " .. ns.Thousands(round.payout)) or "")
		for i, card in ipairs(root.cards) do
			card:SetDim(done and settled and not round.result or false)
		end
		if done and settled then
			Settled(round, celebrate)
		end
		if not celebrate then
			local chips = game.chips
			if done and not settled then
				chips = chips - round.payout
			end
			SetChips(chips, animate and 0.3)
		end
		ShowControls(game, round, settled)
	end

	if revealTimer then
		revealTimer:Cancel()
		revealTimer = nil
	end
	if dealing then
		delay = delay + 0.25 -- the last card's slide
	end
	if drawing or dealing then
		Labels(false)
		revealTimer = C_Timer.NewTimer(delay, function()
			revealTimer = nil
			Labels(true)
		end)
	else
		Labels(true)
	end
end

-- API -----------------------------------------------------------------------------------------------------------

function ns.PokerMachine_Init(saved)
	db = saved
end

face.Draw = Draw
ns.GamesWindow_AddFace(face)
