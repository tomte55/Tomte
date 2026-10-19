local addonName, ns = ...

-- Gear Check quest reward pick: pure logic (no WoW API calls; unit-tested in tests/test_gear_rewards.lua). Which
-- reward choice is best for you (by Gear Check's verdicts) and which sells for the most. The card is in
-- RewardCard.lua.

local IsClean = ns.Gear_IsCleanUpgrade -- Rules.lua
local IsMaybe = ns.Gear_IsMaybeUpgrade

-- 2: a clean upgrade, 1: stats say upgrade but something needs checking, 0: not worth picking for you.
local function Tier(v)
	if IsClean(v) then
		return 2
	elseif IsMaybe(v) then
		return 1
	end
	return 0
end

-- In the same tier: an empty slot first, then a higher item level while leveling, then the bigger stat gain.
local function Better(a, b)
	if (a.kind == "empty") ~= (b.kind == "empty") then
		return a.kind == "empty"
	end
	if (a.kind == "levelUp") ~= (b.kind == "levelUp") then
		return a.kind == "levelUp"
	end
	if a.kind == "levelUp" and a.ilvlDiff ~= b.ilvlDiff then
		return (a.ilvlDiff or 0) > (b.ilvlDiff or 0)
	end
	return (a.pct or 0) > (b.pct or 0)
end

-- choices: list of { verdict = Gear Check verdict or nil, sell = sell price in copper or nil }.
-- Returns best (index of the best choice for you, or nil when none is an upgrade), sure (true when best is a clean
-- upgrade, false when it needs checking), gold (index of the highest sell price, or nil when none sells). Ties go to
-- the first choice.
function ns.GearRewards_Pick(choices)
	local best, bestTier, gold, goldSell = nil, 0, nil, 0
	for i, c in ipairs(choices) do
		local v = c.verdict
		local tier = v and Tier(v) or 0
		if tier > bestTier or (tier > 0 and tier == bestTier and Better(v, choices[best].verdict)) then
			best, bestTier = i, tier
		end
		if (c.sell or 0) > goldSell then
			gold, goldSell = i, c.sell
		end
	end
	return best, best and bestTier == 2 or false, gold
end
