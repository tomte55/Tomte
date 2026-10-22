local addonName, ns = ...

-- Slots: the machine, a face of the casino window (Window.lua). Three reels of WoW icons behind a glass, five paylines
-- drawn when they win, the pay table in chips for the bet beside them, the message line, and under it the bet chips
-- and Spin. A spin is settled at once (SlotsRules.lua); the reels only play it out: each rolls on a decelerating tween
-- (Effects.lua) and stops left to right, and the win shows when the last one lands. Registered in Blackjack.lua.

local WIDTH = ns.GAMES_WINDOW_W
local REEL_W, REEL_GAP = 96, 8
local CELL_H = 76 -- pixels per row
local ICON = 58 -- icon size in a cell
local REELS_X, REELS_TOP = 26, -72 -- the reels' top left, from the window's top left
local GLASS_PAD = 10 -- pixels of cabinet around the reels
local SPIN_FIRST, SPIN_STEP = 0.9, 0.35 -- seconds the first reel rolls, and how much longer each next one rolls
local SPIN_LAPS = 1 -- whole turns of the strip before the stop, one more for each reel
local LINE_REACH = 0.3 -- a payline runs this share of its length past the outer reels' middles
local TABLE_X = 360 -- the pay table's left edge
local TABLE_TOP = -76
local TABLE_ROW = 30
local TABLE_ICON = 22
local MESSAGE_Y = -352
local CHIP_ROLL = 0.8
local BIG_WIN = 500 -- chips won in one spin that count as a big win (a bigger sound)
local BANNER_SIZE, MESSAGE_SIZE = 34, 14
local ICON_CROP = 0.07 -- trims the icon art's dark rim

local UI = ns.UI
local Sound, SetChips, ChipFloat = ns.GamesWindow_Sound, ns.GamesWindow_SetChips, ns.GamesWindow_ChipFloat
local Button, SetUsable = ns.GamesWindow_Button, ns.GamesWindow_SetUsable

local db, root
local face = { key = "slots", name = "Slots" }
local Draw
local shown = { last = nil, celebrated = nil } -- the result on the reels, and the one that had its effects
local revealTimer
local spinning = false
local quiet = false -- stopping the reels without their sounds (the window closing)

local function Game()
	return db.game
end

local function Slots()
	return db.game.slots
end

local function Random(n)
	return math.random(n)
end

-- Reels ---------------------------------------------------------------------------------------------------------

-- Reel i at position pos (a stop; fractions roll between stops): the symbol for each of the four cells that can show,
-- and their offsets. The strip moves down as pos falls.
local function Render(reel, pos)
	local k = math.floor(pos)
	local f = pos - k
	for r, cell in ipairs(reel.cells) do
		local symbol = ns.Slots_Symbol(ns.Slots_At(reel.index, k + r - 2))
		cell:SetTexture(symbol.icon)
		cell:ClearAllPoints()
		cell:SetPoint("CENTER", reel.strip, "TOP", 0, (1 + f - r) * CELL_H - CELL_H / 2)
	end
end

local function ReelStopped(reel)
	if quiet then
		return
	end
	Sound("reelStop")
	reel.bounce:Stop()
	reel.bounce:Play()
end

-- Rolls reel i from where it stands to `stop`, a few laps first.
local function Roll(reel, stop)
	local length = #ns.SLOTS_REELS[reel.index]
	local from = reel.pos or stop
	local start = stop + (SPIN_LAPS + reel.index) * length + (from - stop) % length
	reel.pos = stop
	ns.GamesFx_Tween(reel, SPIN_FIRST + (reel.index - 1) * SPIN_STEP, function(e)
		Render(reel, start + (stop - start) * e)
		if e >= 1 then
			ReelStopped(reel)
		end
	end)
end

local function NewReel(parent, i)
	local reel = { index = i, cells = {} }
	local x = (i - 1) * (REEL_W + REEL_GAP)
	reel.clip = CreateFrame("Frame", nil, parent)
	reel.clip:SetSize(REEL_W, 3 * CELL_H)
	reel.clip:SetPoint("TOPLEFT", x, 0)
	reel.clip:SetClipsChildren(true)
	local fill = reel.clip:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(UI.Color("text"))
	reel.strip = CreateFrame("Frame", nil, reel.clip)
	reel.strip:SetAllPoints()
	for r = 1, 4 do
		local cell = reel.strip:CreateTexture(nil, "ARTWORK")
		cell:SetSize(ICON, ICON)
		cell:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
		reel.cells[r] = cell
	end
	-- Shade at the top and bottom of the glass, so the reel reads as a drum.
	for _, edge in ipairs({ "TOP", "BOTTOM" }) do
		local shade = reel.strip:CreateTexture(nil, "OVERLAY")
		shade:SetPoint(edge .. "LEFT")
		shade:SetPoint(edge .. "RIGHT")
		shade:SetHeight(CELL_H * 0.55)
		shade:SetColorTexture(1, 1, 1, 1)
		local dark, clear = CreateColor(0, 0, 0, 0.35), CreateColor(0, 0, 0, 0)
		if edge == "TOP" then
			shade:SetGradient("VERTICAL", clear, dark)
		else
			shade:SetGradient("VERTICAL", dark, clear)
		end
	end
	UI.Border(reel.clip, "frameDark", 0.9)
	-- The landing bump: down a little, back up.
	reel.bounce = reel.strip:CreateAnimationGroup()
	local down = reel.bounce:CreateAnimation("Translation")
	down:SetOffset(0, -6)
	down:SetDuration(0.06)
	down:SetOrder(1)
	local up = reel.bounce:CreateAnimation("Translation")
	up:SetOffset(0, 6)
	up:SetDuration(0.12)
	up:SetSmoothing("OUT")
	up:SetOrder(2)
	return reel
end

-- Wins ----------------------------------------------------------------------------------------------------------

local function CellCenter(i, row)
	return (i - 1) * (REEL_W + REEL_GAP) + REEL_W / 2, -(row - 1) * CELL_H - CELL_H / 2
end

local function ClearWins()
	for _, line in ipairs(root.lines) do
		line:Hide()
	end
	for _, glow in ipairs(root.glows) do
		glow:Hide()
	end
end

-- The winning lines drawn across the reels and their symbols lit. flash: they just won.
local function ShowWins(last, flash)
	ClearWins()
	for _, win in ipairs(last.wins) do
		local rows = ns.SLOTS_LINES[win.line]
		root.lines[win.line]:Show()
		for i = 1, 3 do
			local glow = root.glows[(i - 1) * 3 + rows[i]]
			glow:Show()
			if flash then
				ns.GamesFx_Flash(glow.tint, 0.6)
			else
				glow.tint:SetAlpha(0.6)
			end
		end
	end
end

-- Tooltip lines (Window.lua's chip count tooltip) -------------------------------------------------------------------

function face.Stats(line, double)
	local s = Slots().stats
	double("Spins", ns.Thousands(s.spins))
	double("Spins won", ns.Thousands(s.wins))
	double("Biggest win", ns.Thousands(s.biggestWin))
	double("Jackpots", ns.Thousands(s.jackpots))
end

function face.StatsFooter(line)
	line(("The machine pays back %.1f%% of what's bet, over time."):format(ns.Slots_ReturnRate() * 100), "textFaint",
		true)
end

-- Actions -------------------------------------------------------------------------------------------------------

-- Lands every reel now and shows the result.
local function StopNow()
	for _, reel in ipairs(root.reels) do
		ns.GamesFx_TweenStop(reel, true)
	end
	if revealTimer then
		revealTimer:Cancel()
		revealTimer = nil
	end
	spinning = false
	Draw(false, true)
end

local function Spin()
	if spinning then
		StopNow()
		return
	end
	if not ns.Slots_Spin(Game(), Random) then
		return
	end
	Sound("spin")
	Draw(true)
end

local function SetBet(value)
	if spinning or not ns.Slots_SetBet(Game(), value) then
		return
	end
	Sound("chip")
	ns.GamesFx_PopText(root.betText, "number", 13, 1.35, 0.2)
	Draw(false)
end

-- Building ------------------------------------------------------------------------------------------------------

local function Icon(parent, symbolKey, size)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetSize(size, size)
	t:SetTexture(ns.Slots_Symbol(symbolKey).icon)
	t:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	return t
end

-- The pay table: three icons and the line's pay in chips, best first, then any three coins.
local function BuildPayTable()
	local head = UI.Text(root, 11, "textMuted", "label")
	head:SetPoint("TOPLEFT", root, "TOPLEFT", TABLE_X, TABLE_TOP + 14)
	head:SetText("Each line pays")
	local rows = {}
	local list = {}
	for n = #ns.SLOTS_SYMBOLS, 1, -1 do
		local s = ns.SLOTS_SYMBOLS[n]
		list[#list + 1] = { icons = { s.key, s.key, s.key }, pay = s.pay }
	end
	list[#list + 1] = { icons = { "copper", "silver", "gold" }, pay = ns.SLOTS_ANY_COINS, any = true }
	for n, entry in ipairs(list) do
		local y = TABLE_TOP - (n - 1) * TABLE_ROW
		local prev
		for k, key in ipairs(entry.icons) do
			local t = Icon(root, key, TABLE_ICON)
			if prev then
				t:SetPoint("LEFT", prev, "RIGHT", 3, 0)
			else
				t:SetPoint("TOPLEFT", root, "TOPLEFT", TABLE_X, y - 2)
			end
			prev = t
		end
		local label = UI.Text(root, 10, "textMuted", "label")
		label:SetPoint("LEFT", prev, "RIGHT", 6, 0)
		label:SetText(entry.any and "any coins" or "")
		local pay = UI.Text(root, 13, entry.pay >= 1000 and "warning" or "text", "number")
		pay:SetPoint("RIGHT", root, "TOPRIGHT", -24, y - 2 - TABLE_ICON / 2)
		pay:SetJustifyH("RIGHT")
		rows[n] = { pay = pay, mult = entry.pay }
	end
	return rows
end

local function BetButton(parent, value)
	local b = ns.BlackjackFelt_ChipButton(parent, value, function()
		SetBet(value)
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

	local reelsW = 3 * REEL_W + 2 * REEL_GAP
	-- The cabinet around the reels: a fill on root (a child frame's fill would cover root's text).
	root.cabinet = root:CreateTexture(nil, "BACKGROUND")
	root.cabinet:SetPoint("TOPLEFT", root, "TOPLEFT", REELS_X - GLASS_PAD, REELS_TOP + GLASS_PAD)
	root.cabinet:SetSize(reelsW + 2 * GLASS_PAD, 3 * CELL_H + 2 * GLASS_PAD)
	local edge = CreateFrame("Frame", nil, root)
	edge:SetAllPoints(root.cabinet)
	UI.Border(edge, "accent", 0.6)

	local reels = CreateFrame("Frame", nil, root)
	reels:SetPoint("TOPLEFT", root, "TOPLEFT", REELS_X, REELS_TOP)
	reels:SetSize(reelsW, 3 * CELL_H)
	reels:SetFrameLevel(root:GetFrameLevel() + 2)
	root.reels = {}
	for i = 1, 3 do
		root.reels[i] = NewReel(reels, i)
	end

	-- Over the reels: glows on winning symbols, the paylines, floats and the banner.
	local over = CreateFrame("Frame", nil, root)
	over:SetAllPoints(reels)
	over:SetFrameLevel(reels:GetFrameLevel() + 6)
	root.over = over
	-- A winning symbol: a border and a tint (an additive glow wouldn't show on the light reels).
	root.glows = {}
	for i = 1, 3 do
		for row = 1, 3 do
			local glow = CreateFrame("Frame", nil, over)
			glow:SetSize(REEL_W - 6, CELL_H - 6)
			local x, y = CellCenter(i, row)
			glow:SetPoint("CENTER", over, "TOPLEFT", x, y)
			UI.Border(glow, "warning", 1)
			glow.tint = glow:CreateTexture(nil, "BACKGROUND")
			glow.tint:SetAllPoints()
			local r, g, b = UI.Color("warning")
			glow.tint:SetColorTexture(r, g, b, 0.3)
			glow:Hide()
			root.glows[(i - 1) * 3 + row] = glow
		end
	end
	-- The paylines on a frame of their own above the glows (a frame's regions draw under its child frames).
	local lineFrame = CreateFrame("Frame", nil, over)
	lineFrame:SetAllPoints()
	lineFrame:SetFrameLevel(over:GetFrameLevel() + 2)
	root.lines = {}
	for n, rows in ipairs(ns.SLOTS_LINES) do
		local x1, y1 = CellCenter(1, rows[1])
		local x3, y3 = CellCenter(3, rows[3])
		local dx, dy = x3 - x1, y3 - y1
		local line = lineFrame:CreateLine(nil, "OVERLAY")
		line:SetThickness(4)
		line:SetColorTexture(UI.Color("warning"))
		line:SetAlpha(0.85)
		line:SetStartPoint("TOPLEFT", lineFrame, x1 - dx * LINE_REACH, y1 - dy * LINE_REACH)
		line:SetEndPoint("TOPLEFT", lineFrame, x3 + dx * LINE_REACH, y3 + dy * LINE_REACH)
		line:Hide()
		root.lines[n] = line
	end
	root.fx = CreateFrame("Frame", nil, root)
	root.fx:SetAllPoints()
	root.fx:SetFrameLevel(over:GetFrameLevel() + 4)
	root.banner = UI.Text(root.fx, BANNER_SIZE, "warning", "title")
	root.banner:SetPoint("CENTER", reels, "CENTER", 0, 0)
	root.banner:Hide()
	root.bannerFade = root.banner:CreateAnimationGroup()
	local bannerOut = root.bannerFade:CreateAnimation("Alpha")
	bannerOut:SetFromAlpha(1)
	bannerOut:SetToAlpha(0)
	bannerOut:SetStartDelay(2.2)
	bannerOut:SetDuration(0.8)
	root.bannerFade:SetScript("OnFinished", function()
		root.banner:Hide()
	end)

	root.payTable = BuildPayTable()

	root.message = UI.Text(root, MESSAGE_SIZE, "text")
	root.message:SetPoint("CENTER", root, "TOP", 0, MESSAGE_Y)
	root.message:SetWidth(WIDTH - 80)
	root.message:SetJustifyH("CENTER")

	-- Under the machine: the bet chips, the bet and Spin.
	local bottom = CreateFrame("Frame", nil, root)
	bottom:SetSize(WIDTH - 32, 48)
	bottom:SetPoint("BOTTOM", 0, 12)
	root.controls = CreateFrame("Frame", nil, bottom)
	root.controls:SetAllPoints()
	root.bets = {}
	local prev
	for _, value in ipairs(ns.SLOTS_BETS) do
		local b = BetButton(root.controls, value)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
		else
			b:SetPoint("LEFT", 4, 0)
		end
		root.bets[#root.bets + 1] = b
		prev = b
	end
	root.spin = Button(root.controls, 100, "Spin", Spin)
	root.spin:SetPoint("RIGHT")
	root.betText = UI.Text(root.controls, 13, "heading", "number")
	root.betText:SetPoint("RIGHT", root.spin, "LEFT", -14, 0)
	root.betText:SetJustifyH("RIGHT")
	root.refill = ns.GamesWindow_RefillButton(bottom)
	root.refill:SetPoint("CENTER")
	return root
end

function face.ApplyLook(felt)
	local r, g, b = UI.Color(felt.role)
	local dim = felt.dim or ns.BLACKJACK_FELT_DIM
	root.cabinet:SetColorTexture(r * dim, g * dim, b * dim)
end

-- The window closed or another game took its place: the reels land where they stop, quietly.
function face.OnHide()
	if spinning then
		quiet = true
		for _, reel in ipairs(root.reels) do
			ns.GamesFx_TweenStop(reel, true)
		end
		quiet = false
		spinning = false
	end
	if revealTimer then
		revealTimer:Cancel()
		revealTimer = nil
		ns.Blackjack_CheckFeats() -- the cut-off reveal would have checked them
	end
	shown.last = nil
end

function face.Busy()
	return revealTimer ~= nil
end

-- Drawing -------------------------------------------------------------------------------------------------------

local function Celebrate(last)
	if last.jackpot then
		Sound("jackpot")
		root.banner:SetText("Jackpot!")
		root.banner:SetAlpha(1)
		root.banner:Show()
		ns.GamesFx_PopText(root.banner, "title", BANNER_SIZE, 2.4, 0.4)
		root.bannerFade:Stop()
		root.bannerFade:Play()
	elseif last.net >= BIG_WIN then
		Sound("bigWin")
	elseif last.net > 0 then
		Sound("win")
	elseif last.payout > 0 then
		Sound("push")
	end
	if last.payout > 0 then
		ns.GamesFx_PopText(root.message, "body", MESSAGE_SIZE, 1.3, 0.3)
		ChipFloat("+" .. ns.Thousands(last.payout), "success")
		-- Each line's pay over its middle symbol, stacked where lines share one.
		local stacked = {}
		for _, win in ipairs(last.wins) do
			local glow = root.glows[3 + ns.SLOTS_LINES[win.line][2]]
			stacked[glow] = (stacked[glow] or 0) + 1
			ns.GamesFx_Float(root.fx, "+" .. ns.Thousands(win.pay), "success", glow, "CENTER", 0,
				(stacked[glow] - 1) * 18)
		end
	end
	ns.Blackjack_CheckFeats()
end

-- animate: a spin just happened (the reels roll it out). landed: the reels were stopped early, so the result shows
-- now with its effects.
function Draw(animate, landed)
	if not ns.GamesWindow_Showing(face) then
		return
	end
	local game = Game()
	local slots = game.slots
	local last = slots.last
	ns.GamesWindow_UpdateRank()
	local fresh = last ~= shown.last
	shown.last = last

	local rolling = animate and fresh and last ~= nil
	if rolling then
		spinning = true
		root.banner:Hide()
		ClearWins()
		for i, reel in ipairs(root.reels) do
			Roll(reel, slots.stops[i])
		end
	elseif not spinning then
		for i, reel in ipairs(root.reels) do
			reel.pos = slots.stops[i]
			Render(reel, reel.pos)
		end
	end

	local function Labels(settled)
		local bet = slots.bet
		for _, b in ipairs(root.bets) do
			b.ring:SetShown(b.value == bet)
			b:SetEnabled(not spinning)
			b:SetAlpha(spinning and 0.35 or 1)
		end
		for _, row in ipairs(root.payTable) do
			row.pay:SetText(ns.Thousands(row.mult * bet / 5))
		end
		root.betText:SetText(("Bet %s  (%s a line)"):format(ns.Thousands(bet), ns.Thousands(bet / 5)))
		local text
		if last and settled then
			text = ns.Slots_ResultText(last, ns.Thousands)
		elseif last and not settled then
			text = ""
		end
		local broke = ns.GamesWindow_BrokeText()
		if settled and broke then
			text = broke
		elseif settled and game.chips < bet then
			text = (text and text .. " " or "") .. ("Lower your bet: you have %s chips."):format(ns.Thousands(game.chips))
		end
		root.message:SetText(text or "Pick a bet, then Spin. Five lines, all always on.")
		UI.SetTextRole(root.message, last and settled and last.payout > 0 and "success" or "text")
		local celebrate = last and settled and (animate or landed) and shown.celebrated ~= last
		if last and settled then
			shown.celebrated = last
			ShowWins(last, celebrate)
		end
		if celebrate then
			Celebrate(last)
			SetChips(game.chips, CHIP_ROLL, last.net > 0 and "success" or nil)
		else
			SetChips(last and not settled and game.chips - last.payout or game.chips, animate and 0.3)
		end
		local brokeNow = not spinning and game.chips < ns.BLACKJACK_MIN_BET
		root.controls:SetShown(not brokeNow)
		root.refill:SetShown(brokeNow and ns.GamesWindow_RefillReady())
		root.spin.label:SetText(spinning and "Stop" or "Spin")
		SetUsable(root.spin, spinning or game.chips >= bet)
	end

	if rolling then
		if revealTimer then
			revealTimer:Cancel()
		end
		Labels(false)
		revealTimer = C_Timer.NewTimer(SPIN_FIRST + (#root.reels - 1) * SPIN_STEP + 0.1, function()
			revealTimer = nil
			spinning = false
			Labels(true)
		end)
	elseif not revealTimer then
		Labels(true)
	end
end

-- API -----------------------------------------------------------------------------------------------------------

function ns.SlotMachine_Init(saved)
	db = saved
end

face.Draw = Draw
ns.GamesWindow_AddFace(face)
