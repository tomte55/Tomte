local addonName, ns = ...

-- Tooltip extras: which unfinished achievements need an item, from the criteria that name one (acquire, eat or
-- drink, fish up, own; ns.TIPS_ITEM_CRITERIA). Built once a session on the shared achievement walk
-- (Modules/Achievements/Walk.lua, a few milliseconds per frame); until it's done the "what's left to do" line
-- (Tooltip.lua) stays off, so it never calls an item safe to delete unchecked. Started and stopped from Tips.lua.

local WALK_KEY = "tips"
local SCAN_DELAY = 5 -- seconds after starting, so the walk doesn't add to the loading screen

local index = {} -- [itemID] = achievementID: an unfinished achievement with an unfinished criterion naming the item
local building -- the index being built; nil while no walk runs
local scanned = false
local timer

local function Visit(id)
	local _, _, _, completed = GetAchievementInfo(id)
	if completed then
		return
	end
	for i = 1, GetAchievementNumCriteria(id) or 0 do
		local _, criteriaType, done, _, _, _, _, asset = GetAchievementCriteriaInfo(id, i)
		if ns.TIPS_ITEM_CRITERIA[criteriaType] and not done and asset and asset > 0 and not building[asset] then
			building[asset] = id
		end
	end
end

local function Finish()
	index, building, scanned = building, nil, true
end

function ns.TipsScan_Start()
	if scanned or building or timer then
		return
	end
	timer = C_Timer.NewTimer(SCAN_DELAY, function()
		timer = nil
		building = {}
		ns.AchWalk_Join(WALK_KEY, { visit = Visit, finish = Finish })
	end)
end

function ns.TipsScan_Stop()
	if timer then
		timer:Cancel()
		timer = nil
	end
	if building then
		ns.AchWalk_Leave(WALK_KEY)
		building = nil
	end
end

-- The name of an unfinished achievement that needs the item, or nil.
function ns.Tips_AchievementFor(itemID)
	local id = index[itemID]
	if not id then
		return nil
	end
	local _, name = GetAchievementInfo(id)
	return name
end

function ns.Tips_AchievementsScanned()
	return scanned
end
