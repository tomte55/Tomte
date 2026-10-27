local addonName, ns = ...

-- Bags: the bank window. The character bank or the Warband bank in the same categories and marks as the bags
-- (View.lua), the bank's tabs in a column outside its right edge (click: only that tab; right-click: rename it; "+"
-- buys the next tab when one can be bought), Clean Up, deposit everything that can go in, and the Warband bank's gold.
--
-- Blizzard's BankFrame stays open the whole visit, invisible and off screen (alpha 0, moved off): it runs the bank
-- (its OnShow picks the tab, its OnHide ends the visit), and Blizzard's item buttons read its bank panel's type when an
-- item is right-clicked. The Character / Warband switch sets that type on the panel itself (BankPanel:SetBankType):
-- right-click deposits from it work from addon code (Alts' Deposit for alts measured C_Container.UseContainerItem
-- with a bank type), and it skips BankFrame:SetTab's UI panel layout. Buying a tab and moving gold are restricted
-- to a real click, which Tomte's buttons are. Closing is C_Bank.CloseBankFrame, not HideUIPanel (the panel manager
-- from addon code taints). Blizzard's bank source: Blizzard_UIPanels_Game/Mainline/BankFrame.lua. Registered in
-- Bags.lua.

local PAD = 10
local MIN_W = 360
local TOP_H = 30
local FOOT_H = 26
local TAB_SIZE = 28 -- a bank tab's icon in the side column
local TAB_GAP = 4
local OFF_SCREEN = -10000 -- where Blizzard's bank frame waits while Tomte's shows the bank
local CHARACTER, ACCOUNT = Enum.BankType.Character, Enum.BankType.Account
local DEPOSIT_REAGENTS_CVAR = "bankAutoDepositReagents" -- the game's "Include reagents" choice (BankFrame.lua)
local SORT_ICON = "Interface\\Icons\\INV_Pet_Broom"
local COIN_ICONS = {
	gold = "%s|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "%s|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "%s|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

local UI = ns.UI

local db
local active = false -- the Bags module is on
local frame, body, view, title, tabColumn, typeButtons, deposit, reagents, money, moneyIn, moneyOut, buyTab
local tabButtons = {}
local Place -- the window at its saved top-left corner (below)
local RenameTab -- below
local tabFilter -- a tab's container ID: only that tab shows; nil for all
local hooked = false
local queued = false
local blizzardPoints -- where Blizzard put its bank frame, to put it back

-- Blizzard's bank frame ----------------------------------------------------------------------------------------------

-- Our window is the bank right now (the module is on, the bank is open, the player didn't ask for the game's).
local function Taking()
	return active and BankFrame and BankFrame:IsShown()
end

-- Blizzard's bank frame invisible and out of the way, or back where Blizzard put it.
local function HideGameBank()
	if not BankFrame then
		return
	end
	if Taking() then
		if BankFrame:GetLeft() and BankFrame:GetLeft() > OFF_SCREEN / 2 then
			blizzardPoints = {}
			for i = 1, BankFrame:GetNumPoints() do
				blizzardPoints[i] = { BankFrame:GetPoint(i) }
			end
		end
		BankFrame:SetAlpha(0)
		BankFrame:ClearAllPoints()
		BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", OFF_SCREEN, 0)
	elseif BankFrame:GetAlpha() < 1 then
		BankFrame:SetAlpha(1)
		if blizzardPoints then
			BankFrame:ClearAllPoints()
			for _, p in ipairs(blizzardPoints) do
				BankFrame:SetPoint(unpack(p))
			end
		end
	end
end

-- The bank type Blizzard's bank shows (CHARACTER or ACCOUNT), nil while the bank is closed.
local function ActiveType()
	if BankFrame and BankFrame:IsShown() and BankFrame.GetActiveBankType then
		return BankFrame:GetActiveBankType()
	end
	return nil
end

-- Drawing ------------------------------------------------------------------------------------------------------------

-- The purchased tabs of a bank type: { { ID = container ID, name, icon } }.
local function Tabs(bankType)
	return C_Bank.FetchPurchasedBankTabData(bankType) or {}
end

-- Renames a tab, keeping its icon and what it takes (C_Bank.UpdateBankTabSettings).
function RenameTab(tab)
	if not tab then
		return
	end
	ns.Dialog_Show({
		title = "Rename the bank tab", hint = "A name for it", text = tab.name or "", height = 60, saveText = "Rename",
		onSave = function(name)
			name = name:match("^%s*(.-)%s*$")
			if name == "" then
				return "It needs a name."
			end
			C_Bank.UpdateBankTabSettings(tab.bankType, tab.ID, name, tab.icon, tab.depositFlags)
			return nil
		end,
	})
end

local function TabButton(i)
	local b = tabButtons[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, tabColumn)
	b:SetSize(TAB_SIZE, TAB_SIZE)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	UI.Border(b, "frame", 0.8)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tabName ~= "" and self.tabName or "Bank tab")
		UI.TipLine(tabFilter == self.containerID and "Click: show every tab" or "Click: show only this tab", "textMuted")
		UI.TipLine("Right-click: rename it", "textMuted")
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			RenameTab(self.tab)
			return
		end
		tabFilter = tabFilter ~= self.containerID and self.containerID or nil
		view:Release()
		ns.BagsBank_Refresh()
	end)
	tabButtons[i] = b
	return b
end

local function DrawTabs(tabs)
	for i, tab in ipairs(tabs) do
		local b = TabButton(i)
		b.containerID, b.tabName, b.tab = tab.ID, tab.name, tab
		b.icon:SetTexture(tab.icon)
		b.icon:SetDesaturated(tabFilter ~= nil and tabFilter ~= tab.ID)
		UI.SetBorderColor(b, tabFilter == tab.ID and "accent" or "frame", tabFilter == tab.ID and 1 or 0.8)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", tabColumn, "TOPLEFT", 0, -(i - 1) * (TAB_SIZE + TAB_GAP))
		b:Show()
	end
	for i = #tabs + 1, #tabButtons do
		tabButtons[i]:Hide()
	end
	local bankType = tabs[1] and tabs[1].bankType or ns.BagsBank_ActiveType()
	local canBuy = bankType and C_Bank.CanPurchaseBankTab and C_Bank.CanPurchaseBankTab(bankType)
	buyTab:ClearAllPoints()
	buyTab:SetPoint("TOPLEFT", tabColumn, "TOPLEFT", 0, -#tabs * (TAB_SIZE + TAB_GAP))
	buyTab:SetShown(canBuy == true)
end

local function DrawFooter(bankType)
	local auto = C_Bank.DoesBankTypeSupportAutoDeposit and C_Bank.DoesBankTypeSupportAutoDeposit(bankType)
	deposit:SetShown(auto == true)
	deposit.label:SetText(bankType == ACCOUNT and "Deposit warbound items" or "Deposit all")
	UI.FitButton(deposit, 80)
	reagents:SetShown(auto == true and bankType == ACCOUNT)
	reagents:SetChecked(C_CVar.GetCVarBool(DEPOSIT_REAGENTS_CVAR))
	local transfer = C_Bank.DoesBankTypeSupportMoneyTransfer and C_Bank.DoesBankTypeSupportMoneyTransfer(bankType)
	money:SetShown(transfer == true)
	moneyIn:SetShown(transfer == true)
	moneyOut:SetShown(transfer == true)
	if transfer then
		money:SetText(ns.Coins(C_Bank.FetchDepositedMoney(bankType) or 0, false, COIN_ICONS))
	end
end

local function Draw()
	queued = false
	if not (frame and frame:IsShown()) then
		return
	end
	local bankType = ActiveType()
	if not bankType then
		return
	end
	local tabs = Tabs(bankType)
	local containers = {}
	for _, tab in ipairs(tabs) do
		if not tabFilter or tabFilter == tab.ID then
			containers[#containers + 1] = tab.ID
		end
	end
	local items = ns.BagsRead_Bags(containers)
	local matcher, usesText = ns.BagsWindow_Matcher()
	if matcher and usesText then
		ns.BagsRead_LoadText(items)
	end
	local width, height = view:Draw(items, {
		layout = ns.Bags_Layout(), place = bankType == ACCOUNT and "warband" or "bank", holding = true,
		columns = db.bankWidth, paint = ns.BagsWindow_PaintOptions(),
		matches = function(item)
			return item.empty or not matcher or (item.readable ~= false and matcher(item) == true)
		end,
	})
	title:SetText(bankType == ACCOUNT and "Warband bank" or "Character bank")
	for t, b in pairs(typeButtons) do
		UI.SetBorderColor(b, t == bankType and "accent" or "frame", t == bankType and 1 or 0.6)
		b:SetShown(C_Bank.CanViewBank(t) == true) -- some bankers serve only one of the two
	end
	DrawTabs(tabs)
	DrawFooter(bankType)
	frame:SetSize(math.max(width + 2 * PAD, MIN_W), TOP_H + height + PAD + FOOT_H + PAD / 2)
end

function ns.BagsBank_Refresh()
	if frame and frame:IsShown() and not queued then
		queued = true
		C_Timer.After(0, Draw)
	end
end

-- Actions ------------------------------------------------------------------------------------------------------------

-- Any item in the bags that the Warband bank would take and that can still be refunded (deposited, it can't be).
local function RefundableForWarband()
	for bag = 0, 5 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
			if C_Item.DoesItemExist(location) and C_Bank.IsItemAllowedInBankType(ACCOUNT, location)
				and C_Item.CanBeRefunded(location) then
				return true
			end
		end
	end
	return false
end

local function DepositAll()
	local bankType = ActiveType()
	if not bankType then
		return
	end
	if bankType == ACCOUNT and RefundableForWarband() then
		ns.Confirm_Show("Some items you could still refund would go in too, and then can't be refunded. Deposit "
			.. "anyway?", function()
			C_Bank.AutoDepositItemsIntoBank(bankType)
		end)
		return
	end
	C_Bank.AutoDepositItemsIntoBank(bankType)
end

-- Asks for an amount of gold and moves it (deposit = true: into the Warband bank).
-- The gold panel: a small box under the Deposit / Withdraw buttons with gold, silver and copper, and a button that
-- moves the amount. Made on first use.
local moneyBox
local MONEY_W = 300 -- the gold panel: three boxes with their coin icons, then the button

local function Copper()
	local function N(box)
		return tonumber(box:GetText()) or 0
	end
	return N(moneyBox.gold) * 10000 + N(moneyBox.silver) * 100 + N(moneyBox.copper)
end

local function MoveNow()
	local bankType = ActiveType()
	local copper = Copper()
	if not bankType or copper <= 0 then
		return
	end
	-- More than there is moves all there is (99999 and Enter takes everything).
	if moneyBox.depositing then
		copper = math.min(copper, GetMoney())
		if copper > 0 then
			C_Bank.DepositMoney(bankType, copper)
		end
	else
		copper = math.min(copper, C_Bank.FetchDepositedMoney(bankType) or 0)
		if copper > 0 then
			C_Bank.WithdrawMoney(bankType, copper)
		end
	end
	moneyBox:Hide()
end

local function CoinBox(width, after, icon)
	local box = CreateFrame("EditBox", nil, moneyBox)
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	UI.SetFont(box, "number", 12)
	UI.SetTextRole(box, "text")
	box:SetJustifyH("RIGHT")
	box:SetTextInsets(4, 4, 0, 0)
	UI.Surface(box, 0.35)
	if after then
		box:SetPoint("LEFT", after, "RIGHT", 18, 0)
	else
		box:SetPoint("LEFT", 8, 0)
	end
	box.icon = box:CreateTexture(nil, "ARTWORK")
	box.icon:SetSize(12, 12)
	box.icon:SetPoint("LEFT", box, "RIGHT", 3, 0)
	box.icon:SetTexture(icon)
	box:SetScript("OnEnterPressed", MoveNow)
	box:SetScript("OnEscapePressed", function()
		moneyBox:Hide()
	end)
	box:SetScript("OnTabPressed", function(self)
		local order = { moneyBox.gold, moneyBox.silver, moneyBox.copper }
		for i, b in ipairs(order) do
			if b == self then
				order[i % #order + 1]:SetFocus()
				return
			end
		end
	end)
	return box
end

local function BuildMoneyBox()
	moneyBox = CreateFrame("Frame", nil, frame)
	moneyBox:SetSize(MONEY_W, 32)
	moneyBox:SetFrameLevel(frame:GetFrameLevel() + 20)
	moneyBox:EnableMouse(true)
	UI.Panel(moneyBox, { subtle = true })
	moneyBox.gold = CoinBox(70, nil, "Interface\\MoneyFrame\\UI-GoldIcon")
	moneyBox.silver = CoinBox(30, moneyBox.gold, "Interface\\MoneyFrame\\UI-SilverIcon")
	moneyBox.copper = CoinBox(30, moneyBox.silver, "Interface\\MoneyFrame\\UI-CopperIcon")
	moneyBox.go = UI.Button(moneyBox, 70, "Deposit")
	moneyBox.go:SetPoint("RIGHT", -6, 0)
	moneyBox.go:SetScript("OnClick", MoveNow)
	moneyBox:Hide()
end

-- Opens the gold panel under the buttons (depositing: into the Warband bank), or closes it when it's open for the same.
local function MoveMoney(depositing)
	if not moneyBox then
		BuildMoneyBox()
	end
	if moneyBox:IsShown() and moneyBox.depositing == depositing then
		moneyBox:Hide()
		return
	end
	moneyBox.depositing = depositing
	moneyBox.go.label:SetText(depositing and "Deposit" or "Withdraw")
	for _, box in ipairs({ moneyBox.gold, moneyBox.silver, moneyBox.copper }) do
		box:SetText("")
	end
	moneyBox:ClearAllPoints()
	moneyBox:SetPoint("TOPRIGHT", moneyOut, "BOTTOMRIGHT", 0, -4)
	moneyBox:Show()
	moneyBox.gold:SetFocus()
end

-- Buys the next tab of the bank type shown, after asking (the cost from the game; a real click buys it).
local function BuyTab()
	local bankType = ActiveType()
	local data = bankType and C_Bank.FetchNextPurchasableBankTabData(bankType)
	if not data then
		return
	end
	if not data.canAfford then
		ns.Print(("The next bank tab costs %s: you don't have that much."):format(ns.Coins(data.tabCost, false, COIN_ICONS)))
		return
	end
	ns.Confirm_Show(("Buy a new %s tab for %s?"):format(bankType == ACCOUNT and "Warband bank" or "bank",
		ns.Coins(data.tabCost, false, COIN_ICONS)), function()
		C_Bank.PurchaseBankTab(bankType)
	end, { yes = "Buy" })
end

-- The Character / Warband switch: the bank panel's own call (see the top of the file).
local function SwitchTo(bankType)
	local panel = BankFrame and BankFrame.BankPanel
	if not (panel and panel.SetBankType) or ActiveType() == bankType or not C_Bank.CanViewBank(bankType) then
		return
	end
	panel:SetBankType(bankType)
	view:Release()
	tabFilter = nil
	ns.BagsBank_Refresh()
	ns.BagsWindow_Refresh() -- the Warband bank fades what can't go in
end

-- Building -----------------------------------------------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", "TomteBankWindow", UIParent)
	frame:SetSize(MIN_W, 200)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not db.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Kept as the top-left corner, so switching banks only grows or shrinks the window right and down.
		wipe(db.bankPosition)
		db.bankPosition.left, db.bankPosition.top = self:GetLeft(), self:GetTop()
		Place()
	end)
	frame:Hide()
	UI.Panel(frame)

	typeButtons = {}
	typeButtons[CHARACTER] = UI.Button(frame, 70, "Character")
	typeButtons[CHARACTER]:SetPoint("TOPLEFT", PAD - 2, -6)
	typeButtons[ACCOUNT] = UI.Button(frame, 70, "Warband")
	typeButtons[ACCOUNT]:SetPoint("LEFT", typeButtons[CHARACTER], "RIGHT", 4, 0)
	for bankType, button in pairs(typeButtons) do
		button:SetScript("OnClick", function()
			SwitchTo(bankType)
		end)
	end
	title = UI.Text(frame, 14, "heading", "title")
	title:SetPoint("LEFT", typeButtons[ACCOUNT], "RIGHT", 10, 0)

	local close = UI.Button(frame, 20, "x")
	close:SetPoint("TOPRIGHT", -6, -5)
	close:SetScript("OnClick", function()
		C_Bank.CloseBankFrame()
	end)
	local sort = CreateFrame("Button", nil, frame)
	sort:SetSize(18, 18)
	sort:SetPoint("RIGHT", close, "LEFT", -8, 0)
	sort.icon = sort:CreateTexture(nil, "ARTWORK")
	sort.icon:SetAllPoints()
	sort.icon:SetTexture(SORT_ICON)
	sort:SetScript("OnClick", function()
		local bankType = ActiveType()
		if bankType and not InCombatLockdown() then
			C_Container.SortBank(bankType)
		end
	end)
	sort:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Clean up this bank")
		GameTooltip:Show()
	end)
	sort:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- The tabs hang outside the window's right edge.
	tabColumn = CreateFrame("Frame", nil, frame)
	tabColumn:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, -TOP_H)
	tabColumn:SetSize(TAB_SIZE, 1)
	buyTab = UI.Button(tabColumn, TAB_SIZE, "+")
	buyTab:SetHeight(TAB_SIZE)
	buyTab:SetScript("OnClick", BuyTab)
	buyTab:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Buy a bank tab")
		local bankType = ActiveType()
		local data = bankType and C_Bank.FetchNextPurchasableBankTabData(bankType)
		if data then
			UI.TipLine(ns.Coins(data.tabCost, false, COIN_ICONS), data.canAfford and "text" or "danger")
		end
		GameTooltip:Show()
	end)
	buyTab:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", PAD, -TOP_H)
	view = ns.BagsView_New(body, db, db.bankFolded)

	deposit = UI.Button(frame, 120, "Deposit all")
	deposit:SetPoint("BOTTOMLEFT", PAD, PAD / 2 + 2)
	deposit:SetScript("OnClick", DepositAll)
	reagents = UI.Checkbox(frame)
	reagents:SetPoint("LEFT", deposit, "RIGHT", 8, 0)
	reagents.text = UI.Text(frame, 11, "textMuted")
	reagents.text:SetPoint("LEFT", reagents, "RIGHT", 4, 0)
	reagents.text:SetText("Include reagents")
	reagents:HookScript("OnClick", function(self)
		C_CVar.SetCVar(DEPOSIT_REAGENTS_CVAR, self.checked and "1" or "0")
	end)
	reagents:HookScript("OnShow", function()
		reagents.text:Show()
	end)
	reagents:HookScript("OnHide", function()
		reagents.text:Hide()
	end)
	moneyOut = UI.Button(frame, 70, "Withdraw")
	moneyOut:SetPoint("BOTTOMRIGHT", -PAD, PAD / 2 + 2)
	moneyOut:SetScript("OnClick", function()
		MoveMoney(false)
	end)
	moneyIn = UI.Button(frame, 60, "Deposit")
	moneyIn:SetPoint("RIGHT", moneyOut, "LEFT", -4, 0)
	moneyIn:SetScript("OnClick", function()
		MoveMoney(true)
	end)
	money = UI.Text(frame, 12, "text", "number")
	money:SetPoint("RIGHT", moneyIn, "LEFT", -8, 0)
	frame:SetScript("OnShow", function()
		Draw()
	end)
	frame:SetScript("OnHide", function()
		view:Release()
		tabFilter = nil
		if moneyBox then
			moneyBox:Hide()
		end
	end)
end

function Place()
	local p = db.bankPosition
	frame:ClearAllPoints()
	if p.left and p.top then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.left, p.top)
	else
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120)
	end
end

-- Open and close -----------------------------------------------------------------------------------------------------

local function Opened()
	if not active then
		return
	end
	HideGameBank()
	if not frame then
		Build()
	end
	Place()
	frame:Show()
	-- The bank opens on the one the player picked (Blizzard picks the character bank first) when this banker has it.
	SwitchTo(db.bankStart == "character" and CHARACTER or ACCOUNT)
end

local function Closed()
	if frame then
		frame:Hide()
	end
	HideGameBank()
end

local function Hook()
	if hooked or not BankFrame then
		return
	end
	hooked = true
	BankFrame:HookScript("OnShow", function()
		if active then
			Opened()
		end
	end)
	BankFrame:HookScript("OnHide", function()
		if active then
			Closed()
		end
	end)
	-- Blizzard places UI panels again whenever one opens or closes: ours goes back off screen.
	hooksecurefunc("UpdateUIPanelPositions", function()
		if Taking() then
			HideGameBank()
		end
	end)
	hooksecurefunc(BankFrame, "SetTab", function()
		if active then
			if frame then
				view:Release()
				tabFilter = nil
			end
			ns.BagsBank_Refresh()
			ns.BagsWindow_Refresh() -- the Warband bank fades what can't go in
		end
	end)
end

-- API ----------------------------------------------------------------------------------------------------------------

function ns.BagsBank_Init(moduleDB)
	db = moduleDB
end

-- The bank type the bank is on while Tomte's bank window shows it, nil otherwise.
function ns.BagsBank_ActiveType()
	if frame and frame:IsShown() then
		return ActiveType()
	end
	return nil
end

-- A layout setting changed.
function ns.BagsBank_Relayout()
	if view then
		view:Release()
	end
	ns.BagsBank_Refresh()
end

function ns.BagsBank_Start()
	active = true
	Hook()
	if BankFrame and BankFrame:IsShown() then
		Opened()
	end
end

function ns.BagsBank_Stop()
	active = false
	Closed()
end
