local addonName, ns = ...

-- Vendor Helper: at a merchant, repair (guild funds first when the guild can pay the whole bill) and sell
-- grey items, then one toast that sums it up. Holding Shift while opening the merchant skips both. Nothing runs
-- in combat or during a boss encounter. Rules in Data.lua.

local GUILD_CHECK_DELAY = 1 -- seconds before checking that a guild repair went through
local ACCENT = "accent" -- toast accent (a role)

local module, db
local last -- { repaired, funds, sold, junkValue, poor } from the latest visit, for /tomte vendor last

-- Hold off in combat and during a boss encounter. The other addon restrictions (M+, maps, chat) hide combat
-- information; repairing and selling don't need any.
local function Restricted()
	if InCombatLockdown() then
		return true
	end
	if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum.AddOnRestrictionType then
		return C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)
			or C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Encounter)
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
		parts[#parts + 1] = ns.UI.Wrap(("Can't afford repairs (%s)"):format(Money(visit.poor)), "danger")
	elseif visit.unpaid then
		parts[#parts + 1] = ns.UI.Wrap(("Guild repair didn't go through (%s)"):format(Money(visit.unpaid)), "danger")
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
		-- First line as the title, the rest below it.
		ns.Toast_Show({
			owner = "vendor", label = "Vendor", accent = ACCENT, title = parts[1],
			text = table.concat(parts, "\n", 2), icon = "Interface\\Icons\\INV_Misc_Bag_10", hold = 6,
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

-- Any equipped or bag item below full durability (works away from the vendor, unlike GetRepairAllCost).
-- RepairAllItems repairs the bags too.
local function AnyDamaged()
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and cur < max then
			return true
		end
	end
	for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local cur, max = C_Container.GetContainerItemDurability(bag, slot)
			if cur and max and cur < max then
				return true
			end
		end
	end
	return false
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
	local plan = ns.Upkeep_RepairPlan(cost, GetMoney(), db.guild, canGuild, canGuild and GetGuildBankWithdrawMoney() or nil,
		canGuild and GetGuildBankMoney() or nil)
	if plan == "guild" then
		RepairAllItems(true)
		visit.repaired, visit.funds, visit.pending = cost, "guild", true
		-- If the guild bank didn't pay after all (bank empty, limit changed), pay with our own gold. The summary
		-- waits for this. A guild-funds repair never takes our own gold: it pays in full or not at all.
		C_Timer.After(GUILD_CHECK_DELAY, function()
			visit.pending = nil
			if MerchantFrame:IsShown() and CanMerchantRepair() then
				local left = GetRepairAllCost()
				if left and left > 0 then
					if GetMoney() >= left then
						RepairAllItems()
						visit.repaired, visit.funds = left, "own"
					else
						visit.repaired, visit.poor = nil, left
					end
				end
			elseif visit.funds == "guild" and AnyDamaged() then
				-- Vendor closed before we could check, and the gear still isn't repaired: the guild didn't pay.
				visit.repaired, visit.unpaid = nil, cost
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
		guild = false,
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
			tooltip = "When the guild lets you repair and both your withdraw limit and the guild bank cover the whole bill. Otherwise your own gold pays." },
		{ type = "checkbox", key = "junk", label = "Sell grey items",
			tooltip = "Bags set to \"Ignore junk selling\" are left alone." },
		{ type = "checkbox", key = "toast", label = "Summary toast",
			tooltip = "Off: one line in chat instead." },
	},
})
