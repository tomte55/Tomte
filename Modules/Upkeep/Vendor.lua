local addonName, ns = ...

-- Vendor Helper: at a merchant, repair (guild funds first when the remaining withdraw limit covers it) and sell
-- grey items, then one toast that sums it up. Holding Shift while opening the merchant skips both. Nothing runs
-- while an addon restriction is active. Rules in Data.lua.

local GUILD_CHECK_DELAY = 1 -- seconds before checking that a guild repair went through
local ACCENT = { 0.95, 0.75, 0.3 }

local module, db
local last -- { repaired, funds, sold, junkValue, poor } from the latest visit, for /tomte vendor last

local function Restricted()
	if not (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum.AddOnRestrictionType) then
		return false
	end
	for _, value in pairs(Enum.AddOnRestrictionType) do
		if C_RestrictedActions.IsAddOnRestrictionActive(value) then
			return true
		end
	end
	return false
end

local function Money(copper)
	return GetMoneyString(copper, true)
end

local function Summary(visit)
	local parts = {}
	if visit.repaired then
		parts[#parts + 1] = ("Repaired %s%s"):format(Money(visit.repaired), visit.funds == "guild" and " (guild)" or "")
	elseif visit.poor then
		parts[#parts + 1] = ("|cffff6040Can't afford repairs (%s)|r"):format(Money(visit.poor))
	end
	if visit.sold then
		parts[#parts + 1] = ("Sold %d junk %s +%s"):format(visit.sold, visit.sold == 1 and "item" or "items",
			Money(visit.junkValue))
	end
	return parts
end

local function Report(visit)
	local parts = Summary(visit)
	if #parts == 0 then
		return
	end
	if db.toast then
		ns.Toast_Show({
			owner = "vendor", label = "Vendor", accent = ACCENT, title = UnitName("npc") or "Merchant",
			text = table.concat(parts, "\n"), icon = "Interface\\Icons\\INV_Misc_Bag_10", hold = 6,
		})
	else
		ns.Print(table.concat(parts, "  -  "))
	end
end

-- Bag contents for ns.Upkeep_JunkValue, honoring the "Ignore junk selling" bag flags.
local function BagItems()
	local items = {}
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		local excluded
		if bag == BACKPACK_CONTAINER then
			excluded = C_Container.GetBackpackSellJunkDisabled and C_Container.GetBackpackSellJunkDisabled()
		else
			excluded = C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags.ExcludeJunkSell)
		end
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				local price = select(11, C_Item.GetItemInfo(info.hyperlink or info.itemID))
				items[#items + 1] = {
					quality = info.quality, count = info.stackCount, price = price,
					noValue = info.hasNoValue, excluded = excluded,
				}
			end
		end
	end
	return items
end

local function Repair(visit)
	if not db.repair or not CanMerchantRepair() then
		return
	end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair then
		return
	end
	local canGuild = IsInGuild() and CanGuildBankRepair()
	local plan = ns.Upkeep_RepairPlan(cost, GetMoney(), db.guild, canGuild, canGuild and GetGuildBankWithdrawMoney() or nil)
	if plan == "guild" then
		RepairAllItems(true)
		visit.repaired, visit.funds, visit.pending = cost, "guild", true
		-- If the guild bank didn't pay after all (bank empty, limit changed), pay with our own gold. The summary
		-- waits for this.
		C_Timer.After(GUILD_CHECK_DELAY, function()
			visit.pending = nil
			local left = GetRepairAllCost()
			if left and left > 0 and MerchantFrame:IsShown() and CanMerchantRepair() then
				if GetMoney() >= left then
					RepairAllItems()
					visit.repaired, visit.funds = left, "own"
				else
					visit.repaired, visit.poor = nil, left
				end
			end
			Report(visit)
		end)
	elseif plan == "own" then
		RepairAllItems()
		visit.repaired, visit.funds = cost, "own"
	elseif plan == "poor" then
		visit.poor = cost
	end
end

local function SellJunk(visit)
	if not db.junk or not C_MerchantFrame.IsSellAllJunkEnabled() or C_MerchantFrame.GetNumJunkItems() == 0 then
		return
	end
	local value, n = ns.Upkeep_JunkValue(BagItems())
	C_MerchantFrame.SellAllJunkItems()
	if n > 0 then
		visit.sold, visit.junkValue = n, value
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

function events:MERCHANT_SHOW()
	if IsShiftKeyDown() or Restricted() then
		return
	end
	local visit = {}
	Repair(visit)
	SellJunk(visit)
	last = visit
	if not visit.pending then
		Report(visit)
	end
end

local function Toggle(active)
	if active then
		events:RegisterEvent("MERCHANT_SHOW")
	else
		events:UnregisterAllEvents()
		ns.Toast_Clear("vendor")
	end
end

module = ns.RegisterModule({
	key = "vendor",
	name = "Vendor Helper",
	category = "Upkeep",
	description = "Repairs (guild funds first) and sells grey items when you open a vendor, then sums it up in a toast. Hold Shift while opening the vendor to skip it.",
	enabledByDefault = true,
	defaults = {
		repair = true,
		guild = true,
		junk = true,
		toast = true,
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = Toggle,
	commands = {
		{ "last", "what happened at the last vendor", function()
			if not last then
				ns.Print("no vendor visit yet this session.")
				return
			end
			local parts = Summary(last)
			ns.Print(#parts > 0 and table.concat(parts, "  -  ") or "nothing to repair or sell last time.")
		end },
	},
	options = {
		{ type = "header", label = "At a vendor" },
		{ type = "checkbox", key = "repair", label = "Repair everything" },
		{ type = "checkbox", key = "guild", label = "Use guild funds first",
			tooltip = "When the guild lets you repair and today's withdraw limit covers the whole bill. Otherwise your own gold pays." },
		{ type = "checkbox", key = "junk", label = "Sell grey items",
			tooltip = "Bags set to \"Ignore junk selling\" are left alone." },
		{ type = "checkbox", key = "toast", label = "Summary toast",
			tooltip = "Off: one line in chat instead." },
	},
})
