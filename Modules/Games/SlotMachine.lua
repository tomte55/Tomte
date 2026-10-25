local addonName, ns = ...

-- Slots: the machine, a face of the casino window (Window.lua). A cabinet in the felt's color with the jackpot on a
-- strip across its top, three dark reels of WoW icons with the five paylines numbered down both sides, and a lever
-- on its right; beside it the pay table in chips for the bet, under it the win and the message, then the bet chips
-- and Spin. A spin is settled at once (SlotsRules.lua); the reels only play it out: each rolls on a decelerating tween
-- (Effects.lua) and stops left to right, and the win shows when the last one lands. Registered in Casino.lua.

local WIDTH = ns.GAMES_WINDOW_W
local CAB_X, CAB_TOP, CAB_W = 14, -50, 372 -- the cabinet's top left (from the window's top left) and width
local MARQUEE_H = 40 -- the jackpot strip across the cabinet's top
local REEL_W, REEL_GAP = 96, 6
local CELL_H = 82 -- pixels per row
local ICON = 62 -- icon size in a cell
local ICON_CROP = 0.07 -- trims the icon art's rim
local REELS_TOP = CAB_TOP - MARQUEE_H - 10
local CAB_PAD = 12 -- cabinet below the reels
local MARKER_W, MARKER_H = 20, 16 -- a payline's number tab
local SHADE = 0.6 -- the reels' top and bottom shading (black, this alpha at the edge), so they read as drums
local SPIN_FIRST, SPIN_STEP = 0.9, 0.35 -- seconds the first reel rolls, and how much longer each next one rolls
local SPIN_LAPS = 1 -- whole turns of the strip before the stop, one more for each reel
local LEVER_X = CAB_X + CAB_W + 16 -- the lever's pivot, from the window's left
local LEVER_LEN = 62 -- pixels from the pivot to the knob
local LEVER_TIME = 0.55 -- seconds for a pull and the swing back
local LEVER_DOWN = 0.35 -- share of that time spent going down
local KNOB = 20
local TABLE_X = 428 -- the pay table's left edge
local TABLE_TOP = -72
local TABLE_ROW = 34
local TABLE_ICON = 18 -- small enough that three icons and a six-digit pay fit the column
local TABLE_RIGHT = 10 -- the pay table's right margin
local WIN_Y, MESSAGE_Y = -386, -416
local CHIP_ROLL = 0.8
local BIG_WIN = 500 -- chips won in one spin that count as a big win (a bigger sound)
local BANNER_SIZE, MESSAGE_SIZE, WIN_SIZE = 34, 13, 22
local MEDIA = "Interface\\AddOns\\Tomte\\Media\\Games\\"

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

local function ReelsLeft()
	return CAB_X + (CAB_W - (3 * REEL_W + 2 * REEL_GAP)) / 2
end

-- A cell's middle, from the reels' top left.
local function CellCenter(i, row)
	return (i - 1) * (REEL_W + REEL_GAP) + REEL_W / 2, -(row - 1) * CELL_H - CELL_H / 2
end

-- Reels ---------------------------------------------------------------------------------------------------------

-- Reel at position pos (a stop; fractions roll between stops): the symbol for each of the four cells that can show,
-- and their offsets. The strip moves down as pos falls.
local function Render(reel, pos)
	local k = math.floor(pos)
	local f = pos - k
	for r, cell in ipairs(reel.cells) do
		cell:SetTexture(ns.Slots_Symbol(ns.Slots_At(reel.index, k + r - 2)).icon)
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

-- Rolls the reel from where it stands to `stop`, a few laps first.
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

local function Shade(frame, edge)
	local shade = frame:CreateTexture(nil, "OVERLAY")
	shade:SetPoint(edge .. "LEFT")
	shade:SetPoint(edge .. "RIGHT")
	shade:SetHeight(CELL_H * 0.7)
	shade:SetColorTexture(1, 1, 1, 1)
	local dark, clear = CreateColor(0, 0, 0, SHADE), CreateColor(0, 0, 0, 0)
	if edge == "TOP" then
		shade:SetGradient("VERTICAL", clear, dark)
	else
		shade:SetGradient("VERTICAL", dark, clear)
	end
end

local function NewReel(parent, i)
	local reel = { index = i, cells = {} }
	reel.clip = CreateFrame("Frame", nil, parent)
	reel.clip:SetSize(REEL_W, 3 * CELL_H)
	reel.clip:SetPoint("TOPLEFT", (i - 1) * (REEL_W + REEL_GAP), 0)
	reel.clip:SetClipsChildren(true)
	local fill = reel.clip:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(UI.Color("bg"))
	-- The middle row, a touch lit: payline 1.
	local band = reel.clip:CreateTexture(nil, "BORDER")
	band:SetPoint("LEFT", reel.clip, "TOPLEFT", 0, -1.5 * CELL_H)
	band:SetPoint("RIGHT", reel.clip, "TOPRIGHT", 0, -1.5 * CELL_H)
	band:SetHeight(CELL_H)
	local r, g, b = UI.Color("accent")
	band:SetColorTexture(r, g, b, 0.1)
	reel.strip = CreateFrame("Frame", nil, reel.clip)
	reel.strip:SetAllPoints()
	for n = 1, 4 do
		local cell = reel.strip:CreateTexture(nil, "ARTWORK")
		cell:SetSize(ICON, ICON)
		cell:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
		reel.cells[n] = cell
	end
	Shade(reel.strip, "TOP")
	Shade(reel.strip, "BOTTOM")
	UI.Border(reel.clip, "frameDark", 1)
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

-- The lever ------------------------------------------------------------------------------------------------------

-- p: 0 up, 1 pulled all the way down. Seen from the front: the knob comes down past the pivot, a little bigger as it
-- swings toward you, and the stick runs from the pivot to it.
local function PoseLever(p)
	local lever = root.lever
	local y = LEVER_LEN * math.cos(math.pi * p)
	lever.knob:ClearAllPoints()
	lever.knob:SetPoint("CENTER", lever.pivot, "CENTER", 0, y)
	local size = KNOB * (1 + 0.3 * math.sin(math.pi * p))
	lever.knob:SetSize(size, size)
	lever.stick:ClearAllPoints()
	lever.stick:SetPoint("BOTTOM", lever.pivot, "CENTER", 0, math.min(y, 0))
	lever.stick:SetHeight(math.max(math.abs(y), 1))
end

local function PullLever()
	ns.GamesFx_Tween(root.lever, LEVER_TIME, function(e)
		PoseLever(e < LEVER_DOWN and e / LEVER_DOWN or 1 - (e - LEVER_DOWN) / (1 - LEVER_DOWN))
	end)
end

-- Wins ----------------------------------------------------------------------------------------------------------

local function ClearWins()
	for _, line in ipairs(root.lines) do
		line:Hide()
	end
	for _, glow in ipairs(root.glows) do
		glow:Hide()
	end
	for _, marker in ipairs(root.markers) do
		marker:Light(false)
	end
	for _, row in ipairs(root.payTable) do
		UI.SetTextRole(row.pay, row.role)
	end
end

-- The winning lines drawn across the reels, their symbols and numbers lit, their pay table rows lit. flash: they just
-- won.
local function ShowWins(last, flash)
	ClearWins()
	for _, win in ipairs(last.wins) do
		local rows = ns.SLOTS_LINES[win.line]
		root.lines[win.line]:Show()
		for _, marker in ipairs(root.markers) do
			if marker.line == win.line then
				marker:Light(true)
			end
		end
		for i = 1, 3 do
			local glow = root.glows[(i - 1) * 3 + rows[i]]
			glow:Show()
			if flash then
				ns.GamesFx_Flash(glow.tint, 0.5)
			else
				glow.tint:SetAlpha(0.5)
			end
		end
		local key = win.kind == "bars" and "bars" or win.symbol
		for _, row in ipairs(root.payTable) do
			if row.key == key then
				UI.SetTextRole(row.pay, "warning")
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
	ns.GamesWindow_NetLines(double, "slots", s.net)
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
	PullLever()
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

-- The pay table: three icons and the line's pay in chips, best first, then any three bars (a hover says so).
local function BuildPayTable()
	local head = UI.Text(root, 11, "textMuted", "label")
	head:SetPoint("TOPLEFT", root, "TOPLEFT", TABLE_X, TABLE_TOP + 18)
	head:SetText("Each line pays")
	local list = {}
	for n = #ns.SLOTS_SYMBOLS, 1, -1 do
		local s = ns.SLOTS_SYMBOLS[n]
		list[#list + 1] = { key = s.key, icons = { s.key, s.key, s.key }, pay = s.pay }
	end
	list[#list + 1] = { key = "bars", icons = { "copper", "silver", "gold" }, pay = ns.SLOTS_ANY_BARS }
	local rows = {}
	for n, entry in ipairs(list) do
		local y = TABLE_TOP - (n - 1) * TABLE_ROW
		local row = CreateFrame("Frame", nil, root)
		row:SetPoint("TOPLEFT", root, "TOPLEFT", TABLE_X, y)
		row:SetPoint("TOPRIGHT", root, "TOPRIGHT", -TABLE_RIGHT, y)
		row:SetHeight(TABLE_ICON + 4)
		local prev
		for _, key in ipairs(entry.icons) do
			local t = Icon(row, key, TABLE_ICON)
			if prev then
				t:SetPoint("LEFT", prev, "RIGHT", 1, 0)
			else
				t:SetPoint("LEFT")
			end
			prev = t
		end
		row.role = entry.pay >= 1000 and "warning" or "text"
		row.pay = UI.Text(row, 13, row.role, "number")
		row.pay:SetPoint("RIGHT")
		row.pay:SetJustifyH("RIGHT")
		row.key, row.mult = entry.key, entry.pay
		if entry.key == "bars" then
			row:EnableMouse(true)
			row:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				UI.TipLine("Any three bars", "heading")
				UI.TipLine("Copper, silver and gold mixed on one line.", "text", true)
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", GameTooltip_Hide)
		end
		rows[n] = row
	end
	return rows
end

local function BetButton(parent, value)
	local b = ns.BlackjackFelt_ChipButton(parent, value, function()
		SetBet(value)
	end)
	b.ring = b:CreateTexture(nil, "OVERLAY")
	b.ring:SetTexture(MEDIA .. "Ring")
	b.ring:SetPoint("CENTER")
	b.ring:SetSize(50, 50)
	b.ring:SetVertexColor(UI.Color("accent"))
	b.value = value
	return b
end

local function LightMarker(self, on)
	self.bg:SetColorTexture(UI.Color(on and "warning" or "frameDark"))
	UI.SetTextRole(self.text, on and "bg" or "textMuted")
end

-- The payline number tabs down both sides of the reels, where each line meets the side. Returns the tabs and each line's two ends (from the reels' top left).
local function BuildMarkers(reels)
	local markers, ends = {}, {}
	local reelsW = 3 * REEL_W + 2 * REEL_GAP
	for n, rows in ipairs(ns.SLOTS_LINES) do
		ends[n] = {}
		-- The line through its three symbols' middles, carried out to the tabs: a diagonal's tabs end up near the
		-- reels' corners.
		local x1, y1 = CellCenter(1, rows[1])
		local x3, y3 = CellCenter(3, rows[3])
		local slope = (y3 - y1) / (x3 - x1)
		for side = 1, 2 do
			local x = side == 1 and -(MARKER_W / 2 + 4) or reelsW + MARKER_W / 2 + 4
			local inner = side == 1 and x + MARKER_W / 2 or x - MARKER_W / 2
			local y = y1 + slope * (inner - x1)
			local m = CreateFrame("Frame", nil, reels)
			m:SetSize(MARKER_W, MARKER_H)
			m:SetPoint("CENTER", reels, "TOPLEFT", x, y)
			m.bg = m:CreateTexture(nil, "BACKGROUND")
			m.bg:SetAllPoints()
			UI.Border(m, "frame", 0.8)
			m.text = UI.Text(m, 10, "textMuted", "number")
			m.text:SetPoint("CENTER", 0, 0)
			m.text:SetText(n)
			m.line, m.Light = n, LightMarker
			m:Light(false)
			markers[#markers + 1] = m
			ends[n][side] = { x = inner, y = y }
		end
	end
	return markers, ends
end

function face.Create(window)
	root = CreateFrame("Frame", nil, window)
	root:SetAllPoints()
	root:SetFrameLevel(window:GetFrameLevel() + 1)

	local reelsW = 3 * REEL_W + 2 * REEL_GAP
	local cabBottom = REELS_TOP - 3 * CELL_H - CAB_PAD
	-- The cabinet: fills on root itself (a child frame's fill would cover root's text), its border on a frame.
	root.cabinet = root:CreateTexture(nil, "BACKGROUND")
	root.cabinet:SetPoint("TOPLEFT", root, "TOPLEFT", CAB_X, CAB_TOP)
	root.cabinet:SetSize(CAB_W, CAB_TOP - cabBottom)
	local marquee = root:CreateTexture(nil, "BORDER")
	marquee:SetPoint("TOPLEFT", root.cabinet, "TOPLEFT", 1, -1)
	marquee:SetPoint("TOPRIGHT", root.cabinet, "TOPRIGHT", -1, -1)
	marquee:SetHeight(MARQUEE_H)
	local r, g, b = UI.Color("bg")
	marquee:SetColorTexture(r, g, b, 0.55)
	local edge = CreateFrame("Frame", nil, root)
	edge:SetAllPoints(root.cabinet)
	UI.Border(edge, "accent", 0.6)
	local rule = UI.Hairline(root, CAB_W - 40, 0.6, "accent")
	rule:SetPoint("TOP", root.cabinet, "TOP", 0, -MARQUEE_H)
	root.jackpot = UI.Text(root, 18, "text", "title")
	root.jackpot:SetPoint("CENTER", root.cabinet, "TOP", 0, -MARQUEE_H / 2)

	local reels = CreateFrame("Frame", nil, root)
	reels:SetPoint("TOPLEFT", root, "TOPLEFT", ReelsLeft(), REELS_TOP)
	reels:SetSize(reelsW, 3 * CELL_H)
	reels:SetFrameLevel(root:GetFrameLevel() + 2)
	root.reels = {}
	for i = 1, 3 do
		root.reels[i] = NewReel(reels, i)
	end
	local ends
	root.markers, ends = BuildMarkers(reels)

	-- Over the reels: winning symbols' border and tint, the paylines above them, then floats and the banner.
	local over = CreateFrame("Frame", nil, root)
	over:SetAllPoints(reels)
	over:SetFrameLevel(reels:GetFrameLevel() + 6)
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
			local wr, wg, wb = UI.Color("warning")
			glow.tint:SetColorTexture(wr, wg, wb, 0.3)
			glow:Hide()
			root.glows[(i - 1) * 3 + row] = glow
		end
	end
	local lineFrame = CreateFrame("Frame", nil, over)
	lineFrame:SetAllPoints()
	lineFrame:SetFrameLevel(over:GetFrameLevel() + 2)
	root.lines = {}
	for n in ipairs(ns.SLOTS_LINES) do
		local from, to = ends[n][1], ends[n][2]
		local line = lineFrame:CreateLine(nil, "OVERLAY")
		line:SetThickness(4)
		line:SetColorTexture(UI.Color("warning"))
		line:SetAlpha(0.85)
		line:SetStartPoint("TOPLEFT", lineFrame, from.x, from.y)
		line:SetEndPoint("TOPLEFT", lineFrame, to.x, to.y)
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

	-- The lever, on the cabinet's right: a button over its whole swing, drawn by PoseLever.
	local lever = CreateFrame("Button", nil, root)
	lever:SetSize(KNOB * 2, 2 * LEVER_LEN + KNOB * 2)
	lever:SetPoint("CENTER", root, "TOPLEFT", LEVER_X, REELS_TOP - 1.5 * CELL_H)
	lever:SetFrameLevel(reels:GetFrameLevel())
	lever.pivot = lever:CreateTexture(nil, "ARTWORK", nil, 2)
	lever.pivot:SetSize(12, 12)
	lever.pivot:SetPoint("CENTER")
	lever.pivot:SetColorTexture(UI.Color("frameDark"))
	lever.stick = lever:CreateTexture(nil, "ARTWORK", nil, 1)
	lever.stick:SetWidth(5)
	lever.stick:SetColorTexture(UI.Color("frame"))
	lever.knob = lever:CreateTexture(nil, "ARTWORK", nil, 3)
	lever.knob:SetTexture(MEDIA .. "Chip")
	lever.knob:SetVertexColor(UI.Color("danger"))
	lever:SetScript("OnClick", Spin)
	lever:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		UI.TipLine("Pull to spin", "text")
		GameTooltip:Show()
	end)
	lever:SetScript("OnLeave", GameTooltip_Hide)
	root.lever = lever
	PoseLever(0)

	root.payTable = BuildPayTable()

	root.winText = UI.Text(root, WIN_SIZE, "warning", "number")
	root.winText:SetPoint("CENTER", root, "TOPLEFT", CAB_X + CAB_W / 2, WIN_Y)
	root.message = UI.Text(root, MESSAGE_SIZE, "text")
	root.message:SetPoint("CENTER", root, "TOPLEFT", CAB_X + CAB_W / 2, MESSAGE_Y)
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
		local chip = BetButton(root.controls, value)
		if prev then
			chip:SetPoint("LEFT", prev, "RIGHT", 8, 0)
		else
			chip:SetPoint("LEFT", 4, 0)
		end
		root.bets[#root.bets + 1] = chip
		prev = chip
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
	ns.GamesFx_TweenStop(root.lever, true)
	if revealTimer then
		revealTimer:Cancel()
		revealTimer = nil
		ns.Casino_CheckFeats() -- the cut-off reveal would have checked them
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
		ns.GamesFx_PopText(root.jackpot, "title", 18, 1.6, 0.4)
	elseif last.net >= BIG_WIN then
		Sound("bigWin")
	elseif last.net > 0 then
		Sound("win")
	elseif last.payout > 0 then
		Sound("push")
	end
	if last.payout > 0 then
		ns.GamesFx_PopText(root.winText, "number", WIN_SIZE, 1.5, 0.3)
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
	ns.Casino_CheckFeats()
end

-- The message under the win: nothing while the reels roll, a nudge before the first spin, otherwise what the last
-- spin did, or why you can't spin.
local function Message(game, last, settled)
	if last and not settled then
		return ""
	end
	local broke = ns.GamesWindow_BrokeText()
	if broke then
		return broke
	end
	local text
	if not last then
		text = "Pick a bet, then Spin or pull the lever. Five lines, all always on."
	elseif last.payout == 0 then
		text = ns.Slots_ResultText(last, ns.Thousands)
	elseif #last.wins > 1 then
		text = ("%d lines win."):format(#last.wins)
	end
	if game.chips < game.slots.bet then
		text = (text and text .. " " or "") .. ("Lower your bet: you have %s chips."):format(ns.Thousands(game.chips))
	end
	return text or ""
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
		for _, chip in ipairs(root.bets) do
			chip.ring:SetShown(chip.value == bet)
			chip:SetEnabled(not spinning)
			chip:SetAlpha(spinning and 0.35 or 1)
		end
		for _, row in ipairs(root.payTable) do
			row.pay:SetText(ns.Thousands(row.mult * bet / 5))
		end
		local top = ns.SLOTS_SYMBOLS[#ns.SLOTS_SYMBOLS]
		root.jackpot:SetText(UI.Wrap("Jackpot", "textMuted") .. "   "
			.. UI.Wrap(ns.Thousands(top.pay * bet / 5), "warning"))
		root.betText:SetText(("Bet %s  (%s a line)"):format(ns.Thousands(bet), ns.Thousands(bet / 5)))
		root.winText:SetText(last and settled and last.payout > 0 and ("Win " .. ns.Thousands(last.payout)) or "")
		root.message:SetText(Message(game, last, settled))
		UI.SetTextRole(root.message, "textMuted")
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
		local canSpin = spinning or game.chips >= bet
		SetUsable(root.spin, canSpin)
		root.lever:SetEnabled(canSpin)
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
