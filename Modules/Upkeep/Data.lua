local addonName, ns = ...

-- Upkeep pure logic (unit-tested with plain Lua): how to pay for a repair, what the junk in the bags is worth,
-- the worst durability among equipped items and when a durability warning fires.

-- How to pay for a repair: "guild", "own", "poor" (can't afford it) or nil (nothing to repair).
-- guildLimit is GetGuildBankWithdrawMoney(): what you may still withdraw today; negative means no limit.
-- CanGuildBankRepair() doesn't look at that limit, so we do. A repair is all or nothing: no splitting.
function ns.Upkeep_RepairPlan(cost, money, useGuild, canGuild, guildLimit)
	if not cost or cost <= 0 then
		return nil
	end
	if useGuild and canGuild and guildLimit and (guildLimit < 0 or guildLimit >= cost) then
		return "guild"
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
-- armed again once durability is back at or above the threshold (you repaired).
function ns.Durability_Alert(state, lowest, broken, threshold)
	if not lowest then
		state.warned, state.broken = false, 0
		return nil
	end
	local prevBroken = state.broken or 0
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
