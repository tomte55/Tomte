local addonName, ns = ...

-- Blackjack: the Cashier, the table window's other face (the title bar's Cashier button swaps them). Card backs and
-- felts to buy with chips or unlock with a feat, and your rank. Catalog and rules in CashierData.lua and
-- ChipRules.lua; the window is Table.lua's.

local TOP = 44 -- the Cashier's top, below the window's title bar
local COLUMNS = 4
local CELL_W, CELL_GAP = 122, 10
local BACK_CELL_H, FELT_CELL_H = 126, 98
local FELT_SWATCH_W, FELT_SWATCH_H = 104, 44
-- The part of the felt and print textures a felt swatch shows: the middle of the table, where the print is.
local SWATCH_LEFT, SWATCH_RIGHT = 0.3, 0.7
local SWATCH_FELT_TOP, SWATCH_FELT_BOTTOM = 0.18, 0.36
local SWATCH_PRINT_TOP, SWATCH_PRINT_BOTTOM = 0.13, 0.84 -- the same felt rows in the print texture
local BUTTON_W, BUTTON_H = 84, 20
local KIND_NAMES = { back = "card back", felt = "felt" }

local UI = ns.UI

local db, panel, onChange

local function Game()
	return db.game
end

-- Cells ---------------------------------------------------------------------------------------------------------

local function Refresh()
	if not (panel and panel:IsShown()) then
		return
	end
	local game = Game()
	local stats = game.stats
	local rank, nextName, nextAt = ns.Chips_Rank(stats.peak)
	if nextName then
		panel.rank:SetText(("%s  %s"):format(UI.Wrap(rank, "accent"), UI.Wrap(("most chips held %s, %s at %s")
			:format(ns.Thousands(stats.peak), nextName, ns.Thousands(nextAt)), "textMuted")))
	else
		panel.rank:SetText(("%s  %s"):format(UI.Wrap(rank, "accent"),
			UI.Wrap("most chips held " .. ns.Thousands(stats.peak), "textMuted")))
	end
	local playing = ns.Blackjack_InPlay(game)
	for _, cell in ipairs(panel.cells) do
		local item, kind = cell.item, cell.kind
		local has = ns.Cashier_Has(item, db.owned, stats)
		local using = ns.Cashier_Using(db.look, kind, db.owned, stats) == item
		cell.status:SetText(using and "In use" or ns.Cashier_Status(item, db.owned, stats, ns.Thousands))
		UI.SetTextRole(cell.status, using and "success" or (has and "textMuted" or "textFaint"))
		cell.button:SetShown(not using and (has or not item.feat))
		if has then
			cell.button.label:SetText("Use")
			cell.button:SetEnabled(true)
		else
			cell.button.label:SetText("Buy")
			cell.button:SetEnabled(not playing and game.chips >= (item.cost or 0))
		end
		cell.button:SetAlpha(cell.button:IsEnabled() and 1 or 0.4)
	end
end

local function Use(cell)
	db.look[cell.kind] = cell.item.key
	onChange()
	Refresh()
end

local function Buy(cell)
	local item = cell.item
	ns.Confirm_Show(("Buy the %s %s for %s chips?"):format(item.name, KIND_NAMES[cell.kind], ns.Thousands(item.cost)),
		function()
			local ok = ns.Cashier_Buy(Game(), db.owned, item)
			if ok then
				ns.GamesWindow_Sound("bigWin")
				ns.Session_Note("blackjack", { title = ("Blackjack: the %s %s"):format(item.name, KIND_NAMES[cell.kind]),
					icon = ns.BLACKJACK_ICON, detail = "bought for " .. ns.Thousands(item.cost) .. " chips" })
				Use(cell)
			else
				Refresh()
			end
		end)
end

local function Cell(parent, kind, item, x, y, height)
	local cell = CreateFrame("Frame", nil, parent)
	cell:SetSize(CELL_W, height)
	cell:SetPoint("TOPLEFT", x, y)
	cell.kind, cell.item = kind, item
	local swatch
	if kind == "back" then
		swatch = ns.GamesCard_Swatch(cell, item)
		swatch:SetLevel(cell:GetFrameLevel() + 1)
		swatch:ClearAllPoints()
		swatch:SetPoint("TOP")
	else
		swatch = CreateFrame("Frame", nil, cell)
		swatch:SetSize(FELT_SWATCH_W, FELT_SWATCH_H)
		swatch:SetPoint("TOP")
		local felt = swatch:CreateTexture(nil, "ARTWORK")
		felt:SetAllPoints()
		felt:SetTexture("Interface\\AddOns\\Tomte\\Media\\Games\\Felt")
		felt:SetTexCoord(SWATCH_LEFT, SWATCH_RIGHT, SWATCH_FELT_TOP, SWATCH_FELT_BOTTOM)
		local r, g, b = UI.Color(item.role)
		local dim = item.dim or ns.BLACKJACK_FELT_DIM
		felt:SetVertexColor(r * dim, g * dim, b * dim)
		local ink = swatch:CreateTexture(nil, "ARTWORK", nil, 1)
		ink:SetAllPoints()
		ink:SetTexture("Interface\\AddOns\\Tomte\\Media\\Games\\PrintMain")
		ink:SetTexCoord(SWATCH_LEFT, SWATCH_RIGHT, SWATCH_PRINT_TOP, SWATCH_PRINT_BOTTOM)
		ink:SetVertexColor(UI.Color("accent"))
		ink:SetAlpha(0.85)
		UI.Border(swatch, "frameDark", 0.9)
	end
	cell.name = UI.Text(cell, 12, "heading", "label")
	cell.name:SetPoint("TOP", swatch, "BOTTOM", 0, -5)
	cell.name:SetText(item.name)
	cell.status = UI.Text(cell, 10, "textMuted")
	cell.status:SetPoint("TOP", cell.name, "BOTTOM", 0, -2)
	cell.status:SetWidth(CELL_W)
	cell.status:SetJustifyH("CENTER")
	cell.status:SetWordWrap(false)
	cell.button = UI.Button(cell, BUTTON_W, "Buy")
	cell.button:SetHeight(BUTTON_H)
	cell.button:SetPoint("BOTTOM")
	cell.button:SetScript("OnClick", function()
		if ns.Cashier_Has(item, db.owned, Game().stats) then
			Use(cell)
		else
			Buy(cell)
		end
	end)
	return cell
end

-- A row of cells, `items` dealt into COLUMNS columns centered in the window, from y down. Returns the y under it.
local function Grid(kind, items, y, height)
	local width = COLUMNS * CELL_W + (COLUMNS - 1) * CELL_GAP
	for i, item in ipairs(items) do
		local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
		local cell = Cell(panel, kind, item, (panel:GetWidth() - width) / 2 + col * (CELL_W + CELL_GAP),
			y - row * (height + CELL_GAP), height)
		panel.cells[#panel.cells + 1] = cell
	end
	local rows = math.ceil(#items / COLUMNS)
	return y - rows * height - (rows - 1) * CELL_GAP
end

local function Header(text, y)
	local fs = UI.Text(panel, 13, "heading", "title")
	fs:SetPoint("TOPLEFT", 20, y)
	fs:SetText(text)
	local rule = UI.Hairline(panel, panel:GetWidth() - 40, 0.5)
	rule:SetPoint("TOPLEFT", 20, y - 18)
	return y - 26
end

-- API -------------------------------------------------------------------------------------------------------------

-- changed(): the look in use changed (Table.lua repaints the felt and the cards).
function ns.BlackjackCashier_Create(window, saved, changed)
	db, onChange = saved, changed
	panel = CreateFrame("Frame", nil, window)
	panel:SetPoint("TOPLEFT", 0, -TOP)
	panel:SetPoint("BOTTOMRIGHT")
	panel:Hide()
	panel.cells = {}
	panel:SetScript("OnShow", Refresh)

	panel.rank = UI.Text(panel, 12, "text")
	panel.rank:SetPoint("TOPLEFT", 20, -8)
	local y = Header("Card backs", -30)
	y = Grid("back", ns.CASHIER_BACKS, y, BACK_CELL_H)
	y = Header("Felts", y - 12)
	Grid("felt", ns.CASHIER_FELTS, y, FELT_CELL_H)
	return panel
end

ns.BlackjackCashier_Refresh = Refresh
