local addonName, ns = ...

-- Bags: the bank window's gold drawer, a small panel that slides out under the footer's Deposit / Withdraw
-- buttons to move gold in or out of the Warband bank. The bank window is in Bank.lua.

local DRAWER_H = 34 -- the gold drawer under the footer
local DRAWER_SLIDE = 0.15 -- seconds
local UI = ns.UI
local PAD = ns.BAGS_BANK_PAD
-- The bank's type while the bank window shows (the drawer is part of it).
local ActiveType = ns.BagsBank_ActiveType
local frame -- the bank window, from ns.BagsGold_Toggle

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

-- For Bank.lua: opens the drawer under window, the bank window (depositing: into the Warband bank), or closes it
-- when it's open for the same.
function ns.BagsGold_Toggle(window, depositing)
	frame = window
	MoveMoney(depositing)
end

function ns.BagsGold_Hide()
	if moneyBox then
		moneyBox:Hide()
	end
end
