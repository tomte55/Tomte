local addonName, ns = ...

-- Upkeep pure logic (unit-tested with plain Lua): how to pay for a repair, what the junk in the bags is worth,
-- the worst durability among equipped items and when a durability warning fires, which merchant costs you lack, and
-- where a split stack goes on its way to being sold.

-- How to pay for a repair: "guild", "own", "poor" (can't afford it) or nil (nothing to repair).
-- withdraw is GetGuildBankWithdrawMoney(): what you may still take out today, -1 for the guild leader (no limit).
-- bankMoney is GetGuildBankMoney(): the guild can't pay more than it has (if it reads 0 because the client hasn't
-- heard from the bank yet, own gold pays: safe). Like Blizzard's tooltip: available = the limit capped
-- by the bank. The guild only counts when it covers the whole bill: whether RepairAllItems(true) can split a bill
-- between guild and own gold is unverified. Vendor.lua checks afterwards and pays whatever is left with own gold.
function ns.Upkeep_RepairPlan(cost, money, useGuild, canGuild, withdraw, bankMoney)
	if not cost or cost <= 0 then
		return nil
	end
	if useGuild and canGuild and withdraw and bankMoney then
		local available = withdraw == -1 and bankMoney or math.min(withdraw, bankMoney)
		if available >= cost then
			return "guild"
		end
	end
	if money >= cost then
		return "own"
	end
	return "poor"
end

-- items: { { quality, count, price, noValue, excluded, keep } }. Grey items (quality 0) that sell, outside bags
-- excluded from junk selling, except what's kept (gear Gear Check calls an upgrade: a grey can be one while leveling).
-- Returns copper, item count (stacks).
local function Sells(item)
	return item.quality == 0 and not item.noValue and not item.excluded and (item.price or 0) > 0 and not item.keep
end

-- Whether a grey that would sell is being kept: Blizzard's "sell all junk" would take it, so greys go one by one.
function ns.Upkeep_KeepsAny(items)
	for _, item in ipairs(items) do
		if item.keep and item.quality == 0 then
			return true
		end
	end
	return false
end

function ns.Upkeep_JunkValue(items)
	local value, n = 0, 0
	for _, item in ipairs(items) do
		if Sells(item) then
			value = value + item.price * (item.count or 1)
			n = n + 1
		end
	end
	return value, n
end

-- When Blizzard's "sell all junk" can't be used: the items (with bag, slot) to sell one by one, at most
-- max of them (the buyback page holds 12, so selling more would lose the chance to buy one back). Skips locked items.
function ns.Upkeep_JunkSlots(items, max)
	local list = {}
	for _, item in ipairs(items) do
		if #list >= max then
			break
		end
		if Sells(item) and not item.locked then
			list[#list + 1] = item
		end
	end
	return list
end

-- slots: { { slot, cur, max } } for equipped items with durability. Returns the lowest fraction (0..1), its slot,
-- and how many items are broken. nil when nothing has durability.
function ns.Durability_Summary(slots)
	local lowest, lowSlot, broken
	broken = 0
	for _, s in ipairs(slots) do
		if s.max and s.max > 0 then
			local f = s.cur / s.max
			if not lowest or f < lowest then
				lowest, lowSlot = f, s.slot
			end
			if s.cur <= 0 then
				broken = broken + 1
			end
		end
	end
	return lowest, lowSlot, broken
end

-- Which durability toast to give, if any: "broken" (more broken items than last time), "low" (just dropped
-- under the threshold) or nil. state = { warned, broken } carries over between calls: one warning per crossing,
-- armed again once durability is back at or above the threshold (you repaired). swapped: the worn gear changed since
-- the last call, so broken items may just have been put on: they're the new baseline, not a break.
function ns.Durability_Alert(state, lowest, broken, threshold, swapped)
	if not lowest then
		state.warned, state.broken = false, 0
		return nil
	end
	-- First call (login, /reload): items that were already broken aren't news.
	local prevBroken = state.broken or broken
	if swapped then
		prevBroken = broken
	end
	state.broken = broken
	if lowest >= threshold then
		state.warned = false
		return nil
	end
	if broken > prevBroken then
		state.warned = true
		return "broken"
	end
	if not state.warned then
		state.warned = true
		return "low"
	end
	return nil
end

-- Percent text for a fraction: floors, so 29.9 % never reads as "30%" under a 30 % threshold.
function ns.Durability_Percent(f)
	return ("%d%%"):format(math.floor(f * 100))
end

-- Which costs of a merchant row you can't pay. price: the gold part in copper (0 or nil: none), money: your copper,
-- costs: { { need, have } } for the row's currency and item costs, in the row's order (nil need or have: unknown,
-- never marked short). -> { money = true when the gold is short, [i] = true for each cost you lack }.
function ns.Upkeep_PriceShort(price, money, costs)
	local short = {}
	if price and price > 0 and money and money < price then
		short.money = true
	end
	for i, cost in ipairs(costs or {}) do
		if cost.need and cost.have and cost.have < cost.need then
			short[i] = true
		end
	end
	return short
end

-- Where a split stack can wait to be sold: the bag and slot, nil when there's no room. bags: { { bag, takes (it fits this
-- bag's kind), free = { slots } } } in the order to try.
function ns.Upkeep_SplitSlot(bags)
	for _, entry in ipairs(bags) do
		if entry.takes and entry.free[1] then
			return entry.bag, entry.free[1]
		end
	end
	return nil
end

-- Whether a slot now holds the split and nothing else may be sold by mistake. placed: { itemID, count }; info: the slot's
-- C_Container.GetContainerItemInfo. The slot stays locked until the server has answered.
function ns.Upkeep_SplitArrived(placed, info)
	return info ~= nil and info.itemID == placed.itemID and info.stackCount == placed.count and not info.isLocked
end
