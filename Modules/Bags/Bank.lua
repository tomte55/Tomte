local addonName, ns = ...

-- Bags: the bank window, built from Kit.lua like the bag window (header band, tray, footer band). The character bank
-- or the Warband bank in the same categories and marks as the bags (View.lua), the bank's tabs attached to its right
-- edge (click: only that tab; right-click: rename it; "+"
-- buys the next tab when one can be bought), Clean Up, deposit everything that can go in, and the Warband bank's gold.
--
-- Blizzard's BankFrame stays open the whole visit, invisible and off screen (alpha 0, moved off): it runs the bank
-- (its OnShow picks the tab, its OnHide ends the visit), and Blizzard's item buttons read its bank panel's type when an
-- item is right-clicked. The Character / Warband switch sets that type on the panel itself (BankPanel:SetBankType):
-- right-click deposits from it work from addon code (Alts' Deposit for alts measured C_Container.UseContainerItem
-- with a bank type), and it skips BankFrame:SetTab's UI panel layout. The type it writes is tainted, so the panel is
-- hidden when that visit ends (BankFrame's OnHide hook). Buying a tab and moving gold are restricted
-- to a real click, which Tomte's buttons are. Closing is C_Bank.CloseBankFrame, not HideUIPanel (the panel manager
-- from addon code taints). Blizzard's bank source: Blizzard_UIPanels_Game/Mainline/BankFrame.lua. Registered in
-- Bags.lua.
--
-- Away from a banker the same window shows the bank as Item counts last read it (ns.BagsBank_ShowRemembered, the bag
-- window's Bank button): display-only items, no tabs, nothing to deposit, "Seen 2h ago" in the footer.

local PAD = 8 -- window edge to the tray, and the tray to the bands
local TRAY_PAD = 8
local MIN_W = 520 -- the switch, the title, a usable search box and the right cluster fit
local BAND_H = 34
local FOOT_H = 32
local TAB_SIZE = 32 -- a bank tab on the right edge
local TAB_GAP = 2
local EVERYTHING_GAP = 6 -- extra room under the "Everything" tab, apart from the bank's own tabs
local EVERYTHING_ICON = "Interface\\Icons\\Achievement_GuildPerk_MobileBanking"
local DRAWER_H = 34 -- the gold drawer under the footer
local TITLE_W = 110 -- "Character bank" at 14; the search box takes the rest
local DRAWER_SLIDE = 0.15 -- seconds
local OFF_SCREEN = -10000 -- where Blizzard's bank frame waits while Tomte's shows the bank
local CHARACTER, ACCOUNT = Enum.BankType.Character, Enum.BankType.Account
local DEPOSIT_REAGENTS_CVAR = "bankAutoDepositReagents" -- the game's "Include reagents" choice (BankFrame.lua)
local COIN_ICONS = {
	gold = "%s|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "%s|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "%s|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

local UI = ns.UI

local db
local active = false -- the Bags module is on
local frame, header, tray, footer, body, view, title, typeSwitch, deposit, reagents, money, moneyCluster, buyTab
local everyTab, search, altsCluster, right, seen
local matcher, matcherText -- the bank's own compiled search (nil for none) and whether it reads tooltip text
local tabButtons = {}
local Place -- the window at its saved top-left corner (below)
local RenameTab -- below
local tabFilter -- a tab's container ID: only that tab shows; nil for all
local remembered -- { guid (nil: the Warband bank's owner, the account), bankType } while showing the remembered bank
local hooked = false
local queued = false
local blizzardPoints -- where Blizzard put its bank frame, to put it back
local switched = false -- the Character / Warband switch wrote the bank panel's type this visit (SwitchTo)

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
		title = "Rename the bank tab", hint = "A name for it", text = tab.name or "", height = 130, saveText = "Rename",
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
	b = ns.BagsKit_Tab(frame, TAB_SIZE, "right")
	b:SetScript("OnEnter", function(self)
		UI.WashTo(self.hoverWash, true)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tabName ~= "" and self.tabName or "Bank tab")
		UI.TipLine("Click: show only this tab", "textMuted")
		UI.TipLine("Right-click: rename it", "textMuted")
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		UI.WashTo(self.hoverWash, false)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			RenameTab(self.tab)
			return
		end
		if tabFilter == self.containerID then
			return
		end
		tabFilter = self.containerID
		view:Release()
		ns.BagsBank_Refresh()
	end)
	tabButtons[i] = b
	return b
end

-- The tabs hang off the right edge below the header band: "Everything" first (i = 0), then the bank's tabs and "+".
-- The one shown is framed in the accent.
local function TabOffset(i)
	return BAND_H + PAD + i * (TAB_SIZE + TAB_GAP) + (i > 0 and EVERYTHING_GAP or 0)
end

local function TabPoint(b, i)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", frame, "TOPRIGHT", -1, -TabOffset(i))
end

local function DrawTabs(tabs)
	everyTab:SetSelected(tabFilter == nil)
	everyTab.icon:SetDesaturated(tabFilter ~= nil)
	TabPoint(everyTab, 0)
	for i, tab in ipairs(tabs) do
		local b = TabButton(i)
		b.containerID, b.tabName, b.tab = tab.ID, tab.name, tab
		b.icon:SetTexture(tab.icon)
		b.icon:SetDesaturated(tabFilter ~= nil and tabFilter ~= tab.ID)
		b:SetSelected(tabFilter == tab.ID)
		TabPoint(b, i)
		b:Show()
	end
	for i = #tabs + 1, #tabButtons do
		tabButtons[i]:Hide()
	end
	local bankType = tabs[1] and tabs[1].bankType or ns.BagsBank_ActiveType()
	local canBuy = bankType and C_Bank.CanPurchaseBankTab and C_Bank.CanPurchaseBankTab(bankType)
	TabPoint(buyTab, #tabs + 1)
	buyTab:SetShown(canBuy == true)
	if bankType then
		buyTab.buy:SetAttribute("overrideBankType", bankType)
	end
end

local function DrawFooter(bankType)
	local auto = C_Bank.DoesBankTypeSupportAutoDeposit and C_Bank.DoesBankTypeSupportAutoDeposit(bankType)
	deposit:SetShown(auto == true)
	deposit.buttons[1].label:SetText(bankType == ACCOUNT and "Deposit warbound items" or "Deposit all")
	deposit:Layout()
	reagents:SetShown(auto == true and bankType == ACCOUNT)
	reagents:SetChecked(C_CVar.GetCVarBool(DEPOSIT_REAGENTS_CVAR))
	local transfer = C_Bank.DoesBankTypeSupportMoneyTransfer and C_Bank.DoesBankTypeSupportMoneyTransfer(bankType)
	money:SetShown(transfer == true)
	moneyCluster:SetShown(transfer == true)
	if transfer then
		money:SetText(ns.Coins(C_Bank.FetchDepositedMoney(bankType) or 0, "exact", COIN_ICONS))
	end
	-- Alts' crafting help (Alts/Deposit.lua), each shown while it has something to move.
	local forAlts = ns.AltsBank_DepositCount and ns.AltsBank_DepositCount() or 0
	local forCrafts = ns.AltsBank_TakeCount and ns.AltsBank_TakeCount() or 0
	local b1, b2 = altsCluster.buttons[1], altsCluster.buttons[2]
	b1.label:SetText(("For alts (%d)"):format(forAlts))
	b1:SetShown(forAlts > 0)
	b2.label:SetText(("Take for crafts (%d)"):format(forCrafts))
	b2:SetShown(forCrafts > 0)
	altsCluster:Layout()
	altsCluster:SetShown(forAlts > 0 or forCrafts > 0)
	altsCluster:ClearAllPoints()
	if reagents:IsShown() then
		altsCluster:SetPoint("LEFT", reagents.text, "RIGHT", 12, 0)
	elseif deposit:IsShown() then
		altsCluster:SetPoint("LEFT", deposit, "RIGHT", 10, 0)
	else
		altsCluster:SetPoint("LEFT", PAD, 0)
	end
end

-- The footer's width with everything in it shown (the window grows to fit it).
local function FooterWidth()
	local w = 2 * PAD
	if deposit:IsShown() then
		w = w + deposit:GetWidth() + 10
	end
	if reagents:IsShown() then
		w = w + reagents:GetWidth() + 4 + reagents.text:GetStringWidth() + 12
	end
	if altsCluster:IsShown() then
		w = w + altsCluster:GetWidth() + 10
	end
	if moneyCluster:IsShown() then
		w = w + money:GetStringWidth() + 10 + moneyCluster:GetWidth()
	end
	return math.ceil(w)
end

-- The remembered bank (see the top of the file).
local function DrawRemembered()
	local bankType = remembered.bankType
	local owner = remembered.guid
	if bankType == ACCOUNT then
		owner = nil -- the Warband bank's record
	end
	local list, at = ns.Counts_Bank(owner)
	local items = ns.BagsRead_FromList(list)
	if matcher and matcherText then
		ns.BagsRead_LoadText(items)
	end
	local n = 0
	local width, height = view:Draw(items, {
		layout = ns.Bags_Layout(), place = bankType == ACCOUNT and "warband" or "bank",
		columns = db.bankWidth, paint = ns.BagsWindow_PaintOptions(),
		matches = function(item)
			return item.empty or not matcher or (item.readable ~= false and matcher(item) == true)
		end,
		button = function()
			n = n + 1
			return ns.BagsButtons_GetView(body, n)
		end,
	})
	local name = remembered.guid ~= UnitGUID("player") and ns.Counts_CharName(remembered.guid)
	title:SetText(bankType == ACCOUNT and "Warband bank" or name and (name .. "'s bank") or "Character bank")
	for i, t in ipairs({ CHARACTER, ACCOUNT }) do
		typeSwitch.buttons[i]:Show()
		typeSwitch:SetLit(i, t == bankType)
	end
	typeSwitch:Layout()
	everyTab:Hide()
	buyTab:Hide()
	for _, b in ipairs(tabButtons) do
		b:Hide()
	end
	for _, f in ipairs({ deposit, reagents, altsCluster, moneyCluster }) do
		f:Hide()
	end
	seen:Show()
	-- bankAt is newer than the character banks Item counts already holds: those say "last visit" without a time.
	seen:SetText(at and ("Seen %s, at your last visit"):format(ns.AgoText(GetServerTime() - at))
		or #list > 0 and "As of your last visit"
		or "Not seen yet: open the bank once with Item counts on")
	-- The Warband bank's gold can be read anywhere (Blizzard's money frame does, on ACCOUNT_MONEY).
	local gold = bankType == ACCOUNT and C_Bank.FetchDepositedMoney(ACCOUNT)
	local hasGold = type(gold) == "number" and not ns.IsSecret(gold)
	money:SetShown(hasGold)
	if hasGold then
		money:SetText(ns.Coins(gold, "exact", COIN_ICONS))
	end
	frame:SetSize(math.max(width + 2 * (PAD + TRAY_PAD), MIN_W),
		BAND_H + PAD + 2 * TRAY_PAD + height + PAD + FOOT_H) -- items whose data arrives later: Bags.lua redraws
end

local function Draw()
	queued = false
	if not (frame and frame:IsShown()) then
		return
	end
	right.buttons[1]:SetShown(remembered == nil) -- Clean Up: only at a banker
	right:Layout()
	if remembered then
		DrawRemembered()
		return
	end
	everyTab:Show()
	seen:Hide()
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
	if matcher and matcherText then
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
	for i, t in ipairs({ CHARACTER, ACCOUNT }) do
		typeSwitch.buttons[i]:SetShown(C_Bank.CanViewBank(t) == true) -- some bankers serve only one of the two
		typeSwitch:SetLit(i, t == bankType)
	end
	typeSwitch:Layout()
	DrawTabs(tabs)
	DrawFooter(bankType)
	frame:SetSize(math.max(width + 2 * (PAD + TRAY_PAD), MIN_W, FooterWidth()),
		math.max(BAND_H + PAD + 2 * TRAY_PAD + height + PAD + FOOT_H, TabOffset(#tabs + 2)))
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
	moneyBox:SetSize(MONEY_W, DRAWER_H)
	moneyBox:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 1)) -- slides out from behind the window
	moneyBox:EnableMouse(true)
	UI.Panel(moneyBox, { subtle = true })
	ns.BagsKit_Band(moneyBox):SetAllPoints()
	moneyBox.gold = CoinBox(70, nil, "Interface\\MoneyFrame\\UI-GoldIcon")
	moneyBox.silver = CoinBox(30, moneyBox.gold, "Interface\\MoneyFrame\\UI-SilverIcon")
	moneyBox.copper = CoinBox(30, moneyBox.silver, "Interface\\MoneyFrame\\UI-CopperIcon")
	moneyBox.go = ns.BagsKit_Cluster(moneyBox, { { text = "Deposit", onClick = MoveNow } })
	moneyBox.go:SetPoint("RIGHT", -6, 0)
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
	moneyBox.go.buttons[1].label:SetText(depositing and "Deposit" or "Withdraw")
	moneyBox.go:Layout()
	for _, box in ipairs({ moneyBox.gold, moneyBox.silver, moneyBox.copper }) do
		box:SetText("")
	end
	moneyBox:Show()
	-- Slides down from behind the footer.
	UI.Tween(moneyBox, "slide", DRAWER_SLIDE, function(t)
		moneyBox:ClearAllPoints()
		moneyBox:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -PAD, math.floor((1 - t) * DRAWER_H + 0.5) + 1)
	end, nil, UI.EaseOut)
	moneyBox.gold:SetFocus()
end

-- The Character / Warband switch: the bank panel's own call (see the top of the file).
local function SwitchTo(bankType)
	local panel = BankFrame and BankFrame.BankPanel
	if not (panel and panel.SetBankType) or ActiveType() == bankType or not C_Bank.CanViewBank(bankType) then
		return
	end
	panel:SetBankType(bankType)
	switched = true
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

	-- Header band: the Character / Warband switch, the title, Clean Up and close.
	header = ns.BagsKit_Band(frame)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(BAND_H)
	-- At a banker it switches the bank; for the remembered bank, which one is shown.
	local function Pick(bankType)
		if remembered then
			if remembered.bankType ~= bankType then
				remembered.bankType = bankType
				view:Release()
				ns.BagsBank_Refresh()
			end
		else
			SwitchTo(bankType)
		end
	end
	typeSwitch = ns.BagsKit_Cluster(header, {
		{ text = "Character", onClick = function()
			Pick(CHARACTER)
		end },
		{ text = "Warband", onClick = function()
			Pick(ACCOUNT)
		end },
	})
	typeSwitch:SetPoint("LEFT", PAD, 0)
	title = UI.Text(header, 14, "heading", "title")
	title:SetPoint("LEFT", typeSwitch, "RIGHT", 12, 0)
	title:SetWordWrap(false)
	title:SetWidth(TITLE_W)
	right = ns.BagsKit_Cluster(header, {
		{ glyph = "Broom", tip = "Clean up this bank", onClick = function()
			local bankType = ActiveType()
			if bankType and not InCombatLockdown() then
				C_Container.SortBank(bankType)
			end
		end },
		{ glyph = "Close", tip = "Close the bank", onClick = function()
			if remembered then
				frame:Hide()
			else
				C_Bank.CloseBankFrame()
			end
		end },
	})
	right:SetPoint("RIGHT", -PAD, 0)
	-- The bank's own search (the bags keep theirs), the same words and keywords.
	search = ns.BagsKit_Search(header, "Search the bank", function()
		local m, err, usesText = ns.BagsSearch_Compile(search:GetText())
		if err then
			search:SetError(err) -- keep the last good filter while a search is half typed
		else
			matcher, matcherText = m, usesText == true
			search:SetError(nil)
		end
		ns.BagsBank_Refresh()
	end)
	search:SetPoint("LEFT", title, "RIGHT", 10, 0)
	search:SetPoint("RIGHT", right, "LEFT", -10, 0)
	search.help:SetScript("OnEnter", ns.BagsWindow_KeywordHelp)

	-- The items in a tray.
	tray = ns.BagsKit_Tray(frame)
	tray:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD - 1, -PAD)
	tray:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, FOOT_H + PAD)
	body = CreateFrame("Frame", nil, tray)
	body:SetPoint("TOPLEFT", TRAY_PAD, -TRAY_PAD)
	view = ns.BagsView_New(body, db, db.bankFolded)

	-- "Everything": every tab at once (the default; clicking a tab shows only that one).
	everyTab = ns.BagsKit_Tab(frame, TAB_SIZE, "right")
	everyTab.icon:SetTexture(EVERYTHING_ICON)
	everyTab:SetScript("OnEnter", function(self)
		UI.WashTo(self.hoverWash, true)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Everything")
		UI.TipLine("Click: show every tab", "textMuted")
		GameTooltip:Show()
	end)
	everyTab:SetScript("OnLeave", function(self)
		UI.WashTo(self.hoverWash, false)
		GameTooltip:Hide()
	end)
	everyTab:SetScript("OnClick", function(_, button)
		if button ~= "LeftButton" or tabFilter == nil then
			return
		end
		tabFilter = nil
		view:Release()
		ns.BagsBank_Refresh()
	end)

	-- "+": buy the next tab, the last tab on the right edge. C_Bank.PurchaseBankTab is protected (measured in 12.1:
	-- ADDON_ACTION_FORBIDDEN from our own confirm), so the click goes to Blizzard's button template made for addons,
	-- which asks with the game's confirm; DrawTabs tells it the bank type through its "overrideBankType" attribute.
	buyTab = ns.BagsKit_Tab(frame, TAB_SIZE, "right")
	buyTab.icon:Hide()
	buyTab.label = UI.Text(buyTab, 16, "heading", "number")
	buyTab.label:SetPoint("CENTER")
	buyTab.label:SetText("+")
	buyTab.buy = CreateFrame("Button", nil, buyTab, "BankPanelPurchaseButtonScriptTemplate")
	buyTab.buy:SetAllPoints()
	buyTab.buy:SetScript("OnEnter", function()
		UI.WashTo(buyTab.hoverWash, true)
		GameTooltip:SetOwner(buyTab, "ANCHOR_RIGHT")
		GameTooltip:SetText("Buy a bank tab")
		local bankType = ActiveType()
		local data = bankType and C_Bank.FetchNextPurchasableBankTabData(bankType)
		if data then
			UI.TipLine(ns.Coins(data.tabCost, false, COIN_ICONS), data.canAfford and "text" or "danger")
		end
		GameTooltip:Show()
	end)
	buyTab.buy:SetScript("OnLeave", function()
		UI.WashTo(buyTab.hoverWash, false)
		GameTooltip:Hide()
	end)

	-- Footer band: deposit and its reagents choice left, the Warband gold right.
	footer = ns.BagsKit_Band(frame)
	footer:SetRuleTop(true)
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(FOOT_H)
	deposit = ns.BagsKit_Cluster(footer, { { text = "Deposit all", onClick = DepositAll } })
	deposit:SetPoint("LEFT", PAD, 0)
	reagents = UI.Checkbox(footer)
	reagents:SetPoint("LEFT", deposit, "RIGHT", 10, 0)
	reagents.text = UI.Text(footer, 11, "textMuted")
	reagents.text:SetPoint("LEFT", reagents, "RIGHT", 4, 0)
	reagents.text:SetText("Include reagents")
	altsCluster = ns.BagsKit_Cluster(footer, {
		{ text = "For alts", onClick = function()
			ns.AltsBank_Deposit()
		end },
		{ text = "Take for crafts", onClick = function()
			ns.AltsBank_Take()
		end },
	})
	for i, tip in ipairs({ "AltsBank_DepositTip", "AltsBank_TakeTip" }) do
		altsCluster.buttons[i]:SetScript("OnEnter", function(self)
			UI.WashTo(self.hoverWash, true)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			ns[tip]()
			GameTooltip:Show()
		end)
	end
	altsCluster:Hide()
	reagents:HookScript("OnClick", function(self)
		C_CVar.SetCVar(DEPOSIT_REAGENTS_CVAR, self.checked and "1" or "0")
	end)
	reagents:HookScript("OnShow", function()
		reagents.text:Show()
	end)
	reagents:HookScript("OnHide", function()
		reagents.text:Hide()
	end)
	moneyCluster = ns.BagsKit_Cluster(footer, {
		{ text = "Deposit", onClick = function()
			MoveMoney(true)
		end },
		{ text = "Withdraw", onClick = function()
			MoveMoney(false)
		end },
	})
	moneyCluster:SetPoint("RIGHT", -PAD, 0)
	money = UI.Text(footer, 12, "text", "number")
	money:SetPoint("RIGHT", moneyCluster, "LEFT", -10, 0)
	seen = UI.Text(footer, 11, "textMuted")
	seen:SetPoint("LEFT", PAD, 0)
	seen:Hide()
	-- Esc closes the bank window like the game's windows (the remembered bank has nothing else that would close it).
	table.insert(UISpecialFrames, frame:GetName())
	frame:SetScript("OnShow", function()
		Draw()
	end)
	frame:SetScript("OnHide", function()
		view:Release()
		tabFilter = nil
		if not remembered and BankFrame and BankFrame:IsShown() then
			-- Esc hid the window first: the visit ends with it, or the bank would stay open unseen.
			C_Bank.CloseBankFrame()
		end
		remembered = nil
		search:SetText("") -- each visit starts unfiltered
		search:ClearFocus()
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
	if remembered then
		-- The remembered bank was open: the real one takes the window over.
		remembered = nil
		view:Release()
	end
	Place()
	frame:Show()
	UI.Appear(frame)
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
		-- The type the switch wrote is Tomte's (tainted) until the next visit's SetTab writes it again, and Blizzard's
		-- right-click on a bag item reads it through BankFrame:GetActiveBankType, which only checks the panel's own
		-- IsShown (not the hidden bank frame's): using an item away from the bank was forbidden (UseContainerItem in
		-- BugSack). Hidden, the panel's type isn't read; the next visit's SetTab shows it again.
		if switched then
			switched = false
			BankFrame.BankPanel:Hide()
		end
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

-- The bank as Item counts last read it, away from a banker (the bag window's Bank button): guid's character bank (nil:
-- yours). At a banker the real bank is already showing; it comes to the front.
function ns.BagsBank_ShowRemembered(guid)
	if not active then
		return
	end
	if not frame then
		Build()
	end
	if frame:IsShown() and not remembered then
		frame:Raise()
		return
	end
	if frame:IsShown() and remembered and remembered.guid == (guid or UnitGUID("player")) then
		frame:Hide() -- the button closes it again
		return
	end
	remembered = { guid = guid or UnitGUID("player"), bankType = remembered and remembered.bankType
		or (db.bankStart == "character" and CHARACTER or ACCOUNT) }
	view:Release()
	if not frame:IsShown() then
		Place()
		frame:Show()
		UI.Appear(frame)
	else
		ns.BagsBank_Refresh()
	end
end

-- Puts text in the bank's search box while the bank window is open.
function ns.BagsBank_Search(text)
	if search and frame:IsShown() then
		search:SetText(text)
		search:SetCursorPosition(0)
	end
end

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
