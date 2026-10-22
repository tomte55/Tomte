local addonName, ns = ...

-- Games: the casino window (a movable UI.Dialog; Esc closes it). The title bar holds one tab per game, the rank, the
-- chip count (stats on hover), the Cashier (Cashier.lua, shown in place of the game) and close; under it the game's
-- face. Faces register with ns.GamesWindow_AddFace: Table.lua (blackjack), PokerMachine.lua, SlotMachine.lua. Chips,
-- refill and rank rules in ChipRules.lua; registered in Casino.lua. Plain frames: nothing here is protected.

local WIDTH, HEIGHT = 560, 506
local CHIP_ROLL = 0.8 -- seconds for the chip count to roll to a new value
local CHIP_FLOAT_DRIFT = -22 -- pixels the +/- under the chip count drifts (down, away from the count)
local TOP_LEVELS = 80 -- frame levels above the window for the chip count's floats (over any face's cards)
local TAB_SIZE, TAB_GAP = 14, 16 -- the game tabs' font size, and pixels between them

ns.GAMES_WINDOW_W, ns.GAMES_WINDOW_H = WIDTH, HEIGHT

local UI = ns.UI

local db, frame
-- Faces in tab order. Each: key, name, Create(window) -> its frame (covering the window), Draw(animate), and as
-- needed Busy() (a result still held back from the chip count), OnHide() (closed or switched away), ApplyLook(felt),
-- Stats(line, double) and StatsFooter(line, double) (its lines in the chip count's tooltip).
local faces = {}
local active -- the face shown
local shownChips -- the number on the chip count (it rolls to new values)

local function Game()
	return db.game
end

local function Sound(name)
	if db.sounds then
		ns.GamesFx_Sound(name)
	end
end
ns.GamesWindow_Sound = Sound

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
ns.GamesWindow_SetChips = SetChips

-- Floats text under the chip count (anchored to its box: the count itself rolls).
local function ChipFloat(text, role)
	ns.GamesFx_Float(frame.top, text, role, frame.chipsBox, "BOTTOMRIGHT", 0, 0,
		{ rise = CHIP_FLOAT_DRIFT, own = "TOPRIGHT" })
end
ns.GamesWindow_ChipFloat = ChipFloat

local function Redraw()
	if active and active.root and frame:IsShown() then
		active.Draw(false)
	end
end

local function Refill()
	local given = ns.Chips_Refill(Game(), db.earned, (ns.CasinoEarn_Day()))
	if given then
		Sound("refill")
		SetChips(Game().chips, CHIP_ROLL, "success")
		ChipFloat("+" .. ns.Thousands(given), "success")
	end
	Redraw()
end

-- Under the minimum bet: the line that says so, and when the house refills. Nil while you can still bet.
function ns.GamesWindow_BrokeText()
	if Game().chips >= ns.BLACKJACK_MIN_BET then
		return nil
	end
	local day, left = ns.CasinoEarn_Day()
	if ns.Chips_RefillReady(db.earned, day) then
		return "You're out of chips."
	end
	return ("Out of chips. The house refills at reset (%s), or earn chips out in the world."):format(ns.Chips_WaitText(left))
end

-- The house's refill button can show: out of chips and not refilled today.
function ns.GamesWindow_RefillReady()
	return Game().chips < ns.BLACKJACK_MIN_BET and ns.Chips_RefillReady(db.earned, (ns.CasinoEarn_Day()))
end

-- Tooltips ------------------------------------------------------------------------------------------------------

local Line = UI.TipLine

local function Double(left, right)
	local r, g, b = UI.RGB("textMuted")
	GameTooltip:AddDoubleLine(left, right, r, g, b)
end

local function StatsTooltip(owner)
	local s = Game().stats
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
	GameTooltip:SetText("Casino", UI.Color("heading"))
	Line("Play chips only, kept between sessions and shared by all three games. Earn more by playing the game: "
		.. "flight paths, quests, the Great Vault and gold you loot.", "textMuted", true)
	local today = ns.Chips_Today(db.earned, (ns.CasinoEarn_Day()))
	if #today > 0 then
		Line(" ")
		Line("Earned today", "heading")
		for _, row in ipairs(today) do
			Double(row[1], ns.Thousands(row[2]))
		end
	end
	Line(" ")
	Double("Chips earned", ns.Thousands(s.earned))
	Double("Most chips held", ns.Thousands(s.peak))
	if s.refills > 0 then
		Double("House refills", ns.Thousands(s.refills))
	end
	if active and active.Stats then
		Line(" ")
		Line(active.name, "heading")
		active.Stats(Line, Double)
	end
	if active and active.StatsFooter then
		Line(" ")
		active.StatsFooter(Line, Double)
	end
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

-- A text button, 24 high; tip: a line shown on hover.
function ns.GamesWindow_Button(parent, width, text, onClick, tip)
	local b = UI.Button(parent, width, text)
	b:SetHeight(24)
	b:SetScript("OnClick", onClick)
	if tip then
		ButtonTip(b, tip)
	end
	return b
end
local Button = ns.GamesWindow_Button

-- The house's refill button, for a face to place and show when ns.GamesWindow_RefillReady().
function ns.GamesWindow_RefillButton(parent)
	return Button(parent, 140, "House chips", Refill,
		("Out of chips: the house tops you up to %s, once a day."):format(ns.Thousands(ns.CHIPS_REFILL_TO)))
end

function ns.GamesWindow_SetUsable(button, usable)
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

local function Felt()
	return ns.Cashier_Using(db.look, "felt", db.owned, Game())
end

-- The look in use (the Cashier's choice): the felt on every face built so far, and every card's back.
local function ApplyLook()
	if not frame then
		return
	end
	local felt = Felt()
	for _, face in ipairs(faces) do
		if face.root and face.ApplyLook then
			face.ApplyLook(felt)
		end
	end
	ns.GamesCard_SetBack(ns.Cashier_Using(db.look, "back", db.owned, Game()))
end

local function ShowCashier(show)
	if not frame.cashier then
		return
	end
	frame.cashier:SetShown(show)
	active.root:SetShown(not show)
	frame.cashierButton.label:SetText(show and "Table" or "Cashier")
	if not show and frame:IsShown() then
		active.Draw(false)
	end
end

-- Game tabs -----------------------------------------------------------------------------------------------------

local function FaceFor(key)
	for _, face in ipairs(faces) do
		if face.key == key then
			return face
		end
	end
	return faces[1]
end

local function PaintTabs()
	for _, tab in ipairs(frame.tabs) do
		local on = tab.face == active
		UI.SetTextRole(tab.text, on and "heading" or (tab:IsMouseOver() and "text" or "textMuted"))
		tab.line:SetShown(on)
	end
end

-- Builds a face the first time it's needed.
local function Build(face)
	if face.root then
		return
	end
	face.root = face.Create(frame)
	face.root:Hide()
	if face.ApplyLook then
		face.ApplyLook(Felt())
	end
end

-- Shows the face for key (the Cashier closes); the window remembers it for next time.
local function Switch(key)
	local face = FaceFor(key)
	if frame.cashier:IsShown() then
		ShowCashier(false)
	end
	if face == active and face.root:IsShown() then
		return
	end
	if active and active.root and active ~= face then
		if active.OnHide then
			active.OnHide()
		end
		active.root:Hide()
	end
	Build(face)
	active = face
	db.lastGame = face.key
	face.root:Show()
	PaintTabs()
	if frame:IsShown() then
		face.Draw(false)
	end
end

local function NewTab(face, prev)
	local tab = CreateFrame("Button", nil, frame)
	tab.face = face
	tab.text = UI.Text(tab, TAB_SIZE, "textMuted", "title")
	tab.text:SetPoint("LEFT")
	tab.text:SetText(face.name)
	tab:SetSize(tab.text:GetStringWidth() + 2, 22)
	if prev then
		tab:SetPoint("LEFT", prev, "RIGHT", TAB_GAP, 0)
	else
		tab:SetPoint("TOPLEFT", 16, -12)
	end
	tab.line = tab:CreateTexture(nil, "ARTWORK")
	tab.line:SetHeight(2)
	tab.line:SetPoint("BOTTOMLEFT", 0, -2)
	tab.line:SetPoint("BOTTOMRIGHT", 0, -2)
	tab.line:SetColorTexture(UI.Color("accent"))
	tab:SetScript("OnClick", function()
		if active ~= face or frame.cashier:IsShown() then
			Sound("tab")
		end
		Switch(face.key)
	end)
	tab:SetScript("OnEnter", PaintTabs)
	tab:SetScript("OnLeave", PaintTabs)
	return tab
end

local function Create()
	frame = UI.Dialog("TomteCasino", WIDTH, HEIGHT)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePlace()
	end)
	ApplyPlace()

	frame.tabs = {}
	local prev
	for _, face in ipairs(faces) do
		prev = NewTab(face, prev)
		frame.tabs[#frame.tabs + 1] = prev
	end

	local close = UI.Button(frame, 20, "x")
	close:SetPoint("TOPRIGHT", -10, -10)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	frame.cashierButton = Button(frame, 74, "Cashier", function()
		ShowCashier(not frame.cashier:IsShown())
	end, "Card backs and felts, for chips.")
	frame.cashierButton:SetHeight(20)
	frame.cashierButton:SetPoint("TOPRIGHT", close, "TOPLEFT", -8, 0)

	local chips = CreateFrame("Frame", nil, frame)
	chips:SetSize(150, 20)
	chips:SetPoint("TOPRIGHT", frame.cashierButton, "TOPLEFT", -10, 0)
	chips:EnableMouse(true)
	chips:SetScript("OnEnter", StatsTooltip)
	chips:SetScript("OnLeave", GameTooltip_Hide)
	frame.chipsBox = chips
	frame.chips = UI.Text(chips, 15, "accent", "number")
	frame.chips:SetPoint("RIGHT")
	frame.chips:SetJustifyH("RIGHT")
	frame.rank = UI.Text(frame, 11, "textMuted", "label")
	frame.rank:SetPoint("RIGHT", frame.chips, "LEFT", -8, 0) -- follows the count's width as it grows
	frame.rank:SetJustifyH("RIGHT")

	frame.cashier = ns.CasinoCashier_Create(frame, db, ApplyLook)

	-- Above every face: the chip count's floats.
	frame.top = CreateFrame("Frame", nil, frame)
	frame.top:SetAllPoints()
	frame.top:SetFrameLevel(frame:GetFrameLevel() + TOP_LEVELS)
	ApplyLook()
	Switch(db.lastGame)

	frame:HookScript("OnHide", function(self)
		if not self:IsShown() then -- closed, not just hidden with UIParent (Alt+Z, a cinematic)
			Sound("close")
		end
		GameTooltip_Hide()
		if active.OnHide then
			active.OnHide()
		end
		ShowCashier(false)
	end)
end

-- API -----------------------------------------------------------------------------------------------------------

-- face: see `faces` above. Called at file load by each game's face file, in tab order.
function ns.GamesWindow_AddFace(face)
	faces[#faces + 1] = face
end

function ns.GamesWindow_Init(saved)
	db = saved
end

-- The face is on screen (the window shown, the face not swapped out for the Cashier or another game).
function ns.GamesWindow_Showing(face)
	return frame ~= nil and frame:IsShown() and face == active and face.root ~= nil and face.root:IsShown()
end

-- The rank line, set by the face on each draw.
function ns.GamesWindow_UpdateRank()
	frame.rank:SetText((ns.Chips_Rank(Game().stats.peak)))
end

-- key: the game to show ("blackjack", "poker", "slots"); nil shows the last one played.
function ns.GamesWindow_Show(key)
	if not frame then
		Create()
	end
	UI.PlaceDialog(frame)
	if not frame:IsShown() then
		Sound("open")
	end
	frame:Show()
	if key and key ~= active.key then
		Switch(key)
	else
		active.Draw(false)
	end
end

function ns.GamesWindow_Hide()
	if frame then
		frame:Hide()
	end
end

function ns.GamesWindow_IsShown()
	return frame ~= nil and frame:IsShown()
end

function ns.GamesWindow_Toggle()
	if ns.GamesWindow_IsShown() then
		ns.GamesWindow_Hide()
	else
		ns.GamesWindow_Show()
	end
end

-- The saved game changed under the faces (Start over): the active one drops any reveal in progress and draws anew.
function ns.GamesWindow_Refresh()
	if active and active.root and active.OnHide then
		active.OnHide()
	end
	Redraw()
	ns.CasinoCashier_Refresh()
end

-- Chips earned out in the world: the count rolls up with a "+25 quest" under it. While a face holds a result back
-- (Busy), it sets the count itself once that result shows.
function ns.GamesWindow_Earned(source, amount)
	if not (frame and frame:IsShown()) then
		return
	end
	ChipFloat(ns.Chips_FloatText(source, amount, ns.Thousands), "success")
	if not (active.Busy and active.Busy()) then
		SetChips(Game().chips, CHIP_ROLL, "success")
		Redraw()
	end
	ns.CasinoCashier_Refresh()
end

function ns.GamesWindow_ApplyLook()
	ApplyLook()
end

function ns.GamesWindow_ResetPlace()
	db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = "CENTER", "CENTER", 0, 60
	if frame then
		ApplyPlace()
	end
end
