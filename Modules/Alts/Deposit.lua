local addonName, ns = ...

-- Send to alt, Warband bank: at the bank, "Deposit for alts" puts what your other characters use (and may go into
-- the Warband bank) there, and "Take for crafts" takes out what your tracked crafts need (the crafting list's
-- "take", "grab" and "fetch" lines). In Tomte's bank window (Bags) both are buttons in its footer (ns.AltsBank_*);
-- with the game's bank or Baganator's, "Deposit for alts" floats above it. The mailbox side and the bag reading are
-- in Send.lua, the rules in SendData.lua and ListData.lua (Alts_BankWants).

local UI = ns.UI
local ClassColor, BagStacks, Context = ns.AltsSend_ClassColor, ns.AltsSend_BagStacks, ns.AltsSend_Context
local Warbandable, GearOn, GearStacks = ns.AltsSend_Warbandable, ns.AltsSend_GearOn, ns.AltsSend_GearStacks
local Without, Slots = ns.AltsSend_Without, ns.AltsSend_Slots
local Busy, UsersChanged = ns.AltsSend_Busy, ns.AltsSend_UsersChanged

local db
local bankButton
local depositing = false
local bankOpen = false
local WARBAND_TABS = { 12, 13, 14, 15, 16 } -- Enum.BagIndex.AccountBankTab_1..5
local CHECK_AFTER = 1 -- seconds after a deposit before looking at what moved
local CHECK_TRIES = 3 -- looks while moved stacks are still locked (on their way)
local BAG_FIRST, BAG_LAST = 0, 5 -- the backpack to the reagent bag: where taken stacks go
local TAKE_MAX = 100 -- moves per click (Alts_AttachPlan's limit; far above what a crafting list asks for)

local events = ns.Alts_Events

-- Warband bank ----------------------------------------------------------------------------------------------------

-- What "Deposit for alts" puts in the Warband bank: materials, then warbound gear for alts ("Gear for" groups).
local function DepositGroups()
	local gear = {}
	for _, g in ipairs(ns.Alts_GearGroups(GearStacks(), "warband", ns.altsDB.chars)) do
		local allowed = {}
		for _, s in ipairs(g.stacks) do
			if Warbandable(s) then
				allowed[#allowed + 1] = s
			end
		end
		if #allowed > 0 then
			g.stacks = allowed
			gear[#gear + 1] = g
		end
	end
	local list = ns.Alts_SendGroups(Without(BagStacks(), Slots(gear)), Context(), Warbandable)
	for _, g in ipairs(gear) do
		list[#list + 1] = g
	end
	return list
end

-- Why the Warband bank takes nothing: "closed" (can't be used now), "tabs" (no tab bought), with full also
-- "full" (no free slot; up front a full bank may still take stacks that merge into partial ones), else nil.
local function WarbandProblem(full)
	if not C_Bank.CanUseBank(Enum.BankType.Account) then
		return "closed"
	end
	if (C_Bank.FetchNumPurchasedBankTabs(Enum.BankType.Account) or 0) == 0 then
		return "tabs"
	end
	if full then
		local free = 0
		for _, bag in ipairs(WARBAND_TABS) do
			free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
		end
		if free == 0 then
			return "full"
		end
	end
	return nil
end

local function SlotNow(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info then
		return nil, 0, false
	end
	return info.itemID, info.stackCount, info.isLocked
end

local function Report(tried, tries)
	local moved, left, moving = ns.Alts_DepositOutcome(tried, SlotNow)
	if moving > 0 and tries < CHECK_TRIES then
		C_Timer.After(CHECK_AFTER, function()
			Report(tried, tries + 1)
		end)
		return
	end
	-- Still locked after the last look: the game took it and is moving it.
	ns.Print(ns.Alts_DepositText(#tried, moved + moving, left > 0 and WarbandProblem(true) or nil))
	if bankButton and bankOpen then
		bankButton:Update()
	end
	if ns.BagsBank_Refresh then
		ns.BagsBank_Refresh()
	end
end

local function Deposit()
	if Busy() or depositing then
		return
	end
	local tried = {}
	for _, g in ipairs(DepositGroups()) do
		for _, s in ipairs(g.stacks) do
			tried[#tried + 1] = { bag = s.bag, slot = s.slot, itemID = s.itemID, count = s.count }
		end
	end
	local problem = #tried > 0 and WarbandProblem(false)
	if #tried == 0 or problem then
		ns.Print(ns.Alts_DepositText(#tried, 0, problem or nil))
		return
	end
	depositing = true
	for _, s in ipairs(tried) do
		C_Container.UseContainerItem(s.bag, s.slot, nil, Enum.BankType.Account, false)
	end
	depositing = false
	C_Timer.After(CHECK_AFTER, function()
		Report(tried, 1)
	end)
end

-- What "Deposit for alts" would put in now, as a tooltip on GameTooltip (owned by the caller).
local function DepositTip(groups)
	GameTooltip:SetText("Deposit for alts", 1, 1, 1)
	GameTooltip:AddLine("Puts what your other characters craft with (and you don't) into the Warband bank"
		.. (GearOn() and ", and warbound gear that's an upgrade for them." or ", and warbound profession gear that's an "
		.. "upgrade for them."), nil, nil, nil, true)
	for _, g in ipairs(groups or {}) do
		local c = ns.altsDB.chars[g.guid]
		GameTooltip:AddDoubleLine((g.gear and "Gear for " or "") .. (c.name or "?"), ("%d stack%s"):format(#g.stacks, #g.stacks == 1 and "" or "s"),
			unpack(ClassColor(c)))
	end
end

local function StackCount(groups)
	local n = 0
	for _, g in ipairs(groups) do
		n = n + #g.stacks
	end
	return n
end

-- Take for crafts -------------------------------------------------------------------------------------------------

-- The stacks in the banks you can use now: { bag, slot, itemID, count } per bank ("warband", "bank").
local function BankStacks()
	local out = { warband = {}, bank = {} }
	for from, bankType in pairs({ warband = Enum.BankType.Account, bank = Enum.BankType.Character }) do
		if C_Bank.CanUseBank(bankType) then
			for _, tab in ipairs(C_Bank.FetchPurchasedBankTabData(bankType) or {}) do
				for slot = 1, C_Container.GetContainerNumSlots(tab.ID) do
					local info = C_Container.GetContainerItemInfo(tab.ID, slot)
					if info and not info.isLocked then
						out[from][#out[from] + 1] = { bag = tab.ID, slot = slot, itemID = info.itemID, count = info.stackCount }
					end
				end
			end
		end
	end
	return out
end

-- The moves "Take for crafts" makes now: { { bag, slot, itemID, n | split } }, exact amounts.
local function TakePlan()
	if not (ns.altsModule.active and ns.AltsList_Todos) then
		return {}
	end
	local wants, stacks = ns.Alts_BankWants(ns.AltsList_Todos()), BankStacks()
	local plan = {}
	for _, from in ipairs({ "warband", "bank" }) do
		for _, move in ipairs(ns.Alts_AttachPlan(wants[from], stacks[from], true, TAKE_MAX)) do
			plan[#plan + 1] = move
		end
	end
	return plan
end

-- Empty bag slots, backpack first (the reagent bag last: only reagents fit there).
local function FreeSlots()
	local out = {}
	for bag = BAG_FIRST, BAG_LAST do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			if not C_Container.GetContainerItemInfo(bag, slot) then
				out[#out + 1] = { bag = bag, slot = slot }
			end
		end
	end
	return out
end

-- One click: split stacks first (each into its own empty bag slot, found before anything moves), then whole stacks
-- (the game finds them a place).
local function Take()
	if Busy() then
		return
	end
	local plan = TakePlan()
	if #plan == 0 then
		ns.Print("nothing in the bank for your crafting list.")
		return
	end
	local free = FreeSlots()
	local moved, i = 0, 1
	ClearCursor()
	for _, m in ipairs(plan) do
		if m.split then
			local to = free[i]
			if to then
				i = i + 1
				C_Container.SplitContainerItem(m.bag, m.slot, m.split)
				C_Container.PickupContainerItem(to.bag, to.slot)
				ClearCursor() -- didn't fit there (a reagent bag slot): back where it came from
				moved = moved + 1
			end
		end
	end
	for _, m in ipairs(plan) do
		if not m.split then
			C_Container.UseContainerItem(m.bag, m.slot)
			moved = moved + 1
		end
	end
	if moved < #plan then
		ns.Print(("took %d of %d stacks for your crafts: your bags are full."):format(moved, #plan))
	end
	UI.Sound("confirm")
end

local function TakeTip(plan)
	GameTooltip:SetText("Take for crafts", 1, 1, 1)
	GameTooltip:AddLine("Takes out of the bank what your tracked crafts need (the crafting list), exact amounts.", nil,
		nil, nil, true)
	local byItem, order = {}, {}
	for _, m in ipairs(plan) do
		if not byItem[m.itemID] then
			order[#order + 1] = m.itemID
		end
		byItem[m.itemID] = (byItem[m.itemID] or 0) + (m.split or m.n or 0)
	end
	for _, itemID in ipairs(order) do
		GameTooltip:AddDoubleLine(C_Item.GetItemNameByID(itemID) or ("Item " .. itemID), byItem[itemID], 1, 1, 1, 1, 1, 1)
	end
end

-- Baganator's bank view, when it's the one showing (Baganator parents Blizzard's BankFrame to a hidden frame). It
-- has no API for the frame; its views are named "Baganator_<Single|Category>ViewBankViewFrame<skin key>" (Baganator
-- ViewManagement/Initialize.lua). The current skin comes from its API; the built-in skin keys (its Skins/*.lua) are
-- the fallback. Only looked at, never changed.
local BAGANATOR_SKINS = { "blizzard", "blizzard_black", "dark", "elvui", "gw2_ui", "ndui", "ellesmereui" }
local function BaganatorBankFrame()
	if not C_AddOns.IsAddOnLoaded("Baganator") then
		return nil
	end
	local skins = BAGANATOR_SKINS
	local api = _G.Baganator and Baganator.API and Baganator.API.Skins
	local ok, current = pcall(function()
		return api and api.GetCurrentSkin and api.GetCurrentSkin()
	end)
	if ok and type(current) == "string" then
		skins = { current }
		for _, skin in ipairs(BAGANATOR_SKINS) do
			skins[#skins + 1] = skin
		end
	end
	for _, skin in ipairs(skins) do
		for _, view in ipairs({ "Single", "Category" }) do
			local f = _G["Baganator_" .. view .. "ViewBankViewFrame" .. skin]
			if type(f) == "table" and f.IsVisible and f:IsVisible() then
				return f
			end
		end
	end
	return nil
end

-- Above the bank window you see: Baganator's, else Blizzard's, else near the top of the screen.
local function PlaceBankButton()
	local anchor = BaganatorBankFrame() or (BankFrame and BankFrame:IsVisible() and BankFrame) or nil
	bankButton:ClearAllPoints()
	if anchor then
		bankButton:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)
		bankButton:SetFrameStrata(anchor:GetFrameStrata())
		bankButton:SetFrameLevel(anchor:GetFrameLevel() + 20)
	else
		bankButton:SetPoint("TOP", UIParent, "TOP", 0, -120)
		bankButton:SetFrameStrata("HIGH")
	end
end

local function CreateBankButton()
	-- On UIParent: a bag addon (Baganator) may keep Blizzard's BankFrame hidden for good.
	bankButton = UI.Button(UIParent, 150, "")
	bankButton:SetHeight(22)
	bankButton:SetClampedToScreen(true)
	bankButton:Hide()
	bankButton:SetScript("OnClick", Deposit)
	bankButton:SetScript("OnEnter", function(self)
		UI.SetBorderColor(self, "accent", 1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		DepositTip(self.groups)
		GameTooltip:Show()
	end)
	bankButton:SetScript("OnLeave", function(self)
		UI.SetBorderColor(self, "frame", UI.BUTTON_RULE)
		GameTooltip:Hide()
	end)
	function bankButton:Update()
		self.groups = DepositGroups()
		local n = StackCount(self.groups)
		self.label:SetText(("Deposit for alts (%d)"):format(n))
		self:SetShown(n > 0)
	end
end

local function UpdateBankButton()
	local tomteBank = ns.BagsBank_ActiveType and ns.BagsBank_ActiveType() ~= nil -- its footer has the buttons
	if tomteBank then
		ns.BagsBank_Refresh()
	end
	if tomteBank or not (bankOpen and db and db.sendWarband and ns.altsDB) then
		if bankButton then
			bankButton:Hide()
		end
		return
	end
	if not bankButton then
		CreateBankButton()
	end
	PlaceBankButton()
	bankButton:Update()
end

events:On("send", "BANKFRAME_OPENED", function()
	bankOpen = true
	UsersChanged()
	C_Timer.After(0.3, UpdateBankButton) -- after the bank window (Blizzard's or Baganator's) has opened
end)

events:On("send", "BANKFRAME_CLOSED", function()
	bankOpen = false
	if bankButton then
		bankButton:Hide()
	end
end)

function ns.AltsDeposit_IsOpen()
	return bankOpen
end

function ns.AltsDeposit_Update()
	UpdateBankButton()
end

-- Tomte's bank window (Bags/Bank.lua) -----------------------------------------------------------------------------

-- How many stacks "Deposit for alts" would put in the Warband bank now (0 while it's off).
function ns.AltsBank_DepositCount()
	if not (bankOpen and db and db.sendWarband and ns.altsDB and ns.altsModule.active) then
		return 0
	end
	return StackCount(DepositGroups())
end

function ns.AltsBank_Deposit()
	Deposit()
end

-- Fills GameTooltip (the caller owns and shows it).
function ns.AltsBank_DepositTip()
	DepositTip(DepositGroups())
end

-- How many stacks "Take for crafts" would take out now.
function ns.AltsBank_TakeCount()
	if not (bankOpen and ns.altsDB) then
		return 0
	end
	return #TakePlan()
end

function ns.AltsBank_Take()
	Take()
end

function ns.AltsBank_TakeTip()
	TakeTip(TakePlan())
end

function ns.AltsDeposit_Start(moduleDB)
	db = moduleDB
end

function ns.AltsDeposit_Stop()
	if bankButton then
		bankButton:Hide()
	end
	bankOpen = false
end
