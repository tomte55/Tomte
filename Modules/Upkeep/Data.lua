local addonName, ns = ...

-- Upkeep pure logic (unit-tested with plain Lua): how to pay for a repair, what the junk in the bags is worth,
-- the worst durability among equipped items and when a durability warning fires.

-- How to pay for a repair: "guild", "own", "poor" (can't afford it) or nil (nothing to repair).
-- withdraw is GetGuildBankWithdrawMoney(): what you may still take out today, -1 for the guild leader (no limit).
-- bankMoney is GetGuildBankMoney(): the guild can't pay more than it has (if it reads 0 because the client hasn't
-- heard from the bank yet, own gold pays: safe). Like Blizzard's tooltip: available = the limit capped
-- by the bank. RepairAllItems(true) quietly takes the rest from your own gold, so the guild only counts when it covers
-- the whole bill.
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

-- items: { { quality, count, price, noValue, excluded } }. Grey items (quality 0) that sell, outside bags
-- excluded from junk selling. Returns copper, item count (stacks).
function ns.Upkeep_JunkValue(items)
	local value, n = 0, 0
	for _, item in ipairs(items) do
		if item.quality == 0 and not item.noValue and not item.excluded and (item.price or 0) > 0 then
			value = value + item.price * (item.count or 1)
			n = n + 1
		end
	end
	return value, n
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
