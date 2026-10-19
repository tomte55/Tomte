local addonName, ns = ...

-- Send to alt, Warband bank: at the bank, "Deposit for alts" puts what your other characters use (and may go into
-- the Warband bank) there. The mailbox side and the bag reading are in Send.lua, the rules in SendData.lua.

local UI = ns.UI
local ClassColor, BagStacks, Context = ns.AltsSend_ClassColor, ns.AltsSend_BagStacks, ns.AltsSend_Context
local Warbandable, GearOn, GearStacks = ns.AltsSend_Warbandable, ns.AltsSend_GearOn, ns.AltsSend_GearStacks
local Without, Slots = ns.AltsSend_Without, ns.AltsSend_Slots
local Busy, UsersChanged = ns.AltsSend_Busy, ns.AltsSend_UsersChanged

local db
local bankButton
local depositing = false
local bankOpen = false

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

local function Deposit()
	if Busy() or depositing then
		return
	end
	local list = DepositGroups()
	local n = 0
	depositing = true
	for _, g in ipairs(list) do
		for _, s in ipairs(g.stacks) do
			C_Container.UseContainerItem(s.bag, s.slot, nil, Enum.BankType.Account, false)
			n = n + 1
		end
	end
	depositing = false
	ns.Print(n == 0 and "nothing to put in the Warband bank for your alts." or ("put %d stack%s in the Warband bank for your alts."):format(n, n == 1 and "" or "s"))
	C_Timer.After(0.5, function()
		if bankButton and bankOpen then
			bankButton:Update()
		end
	end)
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
		GameTooltip:SetText("Deposit for alts", 1, 1, 1)
		GameTooltip:AddLine("Puts what your other characters craft with (and you don't) into the Warband bank"
			.. (GearOn() and ", and warbound gear that's an upgrade for them." or ", and warbound profession gear that's an "
			.. "upgrade for them."), nil, nil, nil, true)
		for _, g in ipairs(self.groups or {}) do
			local c = ns.altsDB.chars[g.guid]
			GameTooltip:AddDoubleLine((g.gear and "Gear for " or "") .. (c.name or "?"), ("%d stack%s"):format(#g.stacks, #g.stacks == 1 and "" or "s"),
				unpack(ClassColor(c)))
		end
		GameTooltip:Show()
	end)
	bankButton:SetScript("OnLeave", function(self)
		UI.SetBorderColor(self, "frame", UI.BUTTON_RULE)
		GameTooltip:Hide()
	end)
	function bankButton:Update()
		self.groups = DepositGroups()
		local n = 0
		for _, g in ipairs(self.groups) do
			n = n + #g.stacks
		end
		self.label:SetText(("Deposit for alts (%d)"):format(n))
		self:SetShown(n > 0)
	end
end

local function UpdateBankButton()
	if not (bankOpen and db and db.sendWarband and ns.altsDB) then
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

function ns.AltsDeposit_Start(moduleDB)
	db = moduleDB
end

function ns.AltsDeposit_Stop()
	if bankButton then
		bankButton:Hide()
	end
	bankOpen = false
end
