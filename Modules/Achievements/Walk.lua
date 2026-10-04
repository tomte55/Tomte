local addonName, ns = ...

-- The shared achievement walk: every achievement in every category, a few milliseconds per frame. Almost Done's
-- scan and Collect here both ride on it, so with both on there's one walk. A subscriber that joins while a walk
-- is running starts at the next category and stays until it has seen every category once (the walk wraps around
-- for it). Categories the skip test rejects (Feats of Strength, Legacy) give no visits.
--
-- ns.AchWalk_Join(key, { visit(id, categoryID), category(), finish() }) (joining again restarts that key),
-- ns.AchWalk_Leave(key), ns.AchWalk_Progress(key) -> 0..1 or nil, ns.AchWalk_SetSkipped(fn(categoryID) -> bool).

local BUDGET_MS = 4

local subs = {} -- [key] = { handlers, active (gets the current category), left (categories to go, nil until started) }
local categories -- the list of this walk; nil while idle
local ci, ai, count, started = 1, 1, 0, false
local skipped = function()
	return false
end

local frame = CreateFrame("Frame")
frame:Hide()

local function Idle()
	frame:Hide()
	categories = nil
end

local function StartCategory()
	for _, sub in pairs(subs) do
		sub.left = sub.left or #categories
		sub.active = true
	end
	local categoryID = categories[ci]
	count = skipped(categoryID) and 0 or (GetCategoryNumAchievements(categoryID) or 0)
	started = true
end

local function EndCategory()
	local finished = {}
	for key, sub in pairs(subs) do
		if sub.active then
			sub.left = sub.left - 1
			if sub.handlers.category then
				sub.handlers.category()
			end
			if sub.left <= 0 then
				finished[#finished + 1] = key
			end
		end
	end
	-- Removed before their finish runs, so a finish can join again.
	local done = {}
	for _, key in ipairs(finished) do
		done[#done + 1] = subs[key]
		subs[key] = nil
	end
	ci, ai, started = ci + 1, 1, false
	if ci > #categories then
		ci = 1
	end
	for _, sub in ipairs(done) do
		if sub.handlers.finish then
			sub.handlers.finish()
		end
	end
end

local function Step()
	local deadline = debugprofilestop() + BUDGET_MS
	while debugprofilestop() < deadline do
		if not next(subs) then
			Idle()
			return
		end
		if not started then
			StartCategory()
		end
		if ai > count then
			EndCategory()
		else
			local categoryID = categories[ci]
			local id = GetAchievementInfo(categoryID, ai)
			ai = ai + 1
			if id then
				for _, sub in pairs(subs) do
					if sub.active then
						sub.handlers.visit(id, categoryID)
					end
				end
			end
		end
	end
	if not next(subs) then
		Idle()
	end
end

frame:SetScript("OnUpdate", Step)

function ns.AchWalk_Join(key, handlers)
	if not categories then
		categories = GetCategoryList() or {}
		ci, ai, count, started = 1, 1, 0, false
	end
	if #categories == 0 then
		subs[key] = nil
		if not next(subs) then
			Idle()
		end
		if handlers.finish then
			handlers.finish()
		end
		return
	end
	subs[key] = { handlers = handlers, active = false, left = nil }
	frame:Show()
end

function ns.AchWalk_Leave(key)
	subs[key] = nil
	if not next(subs) then
		Idle()
	end
end

function ns.AchWalk_Progress(key)
	local sub = subs[key]
	if not sub or not categories then
		return nil
	end
	if not sub.left then
		return 0
	end
	return math.min((#categories - sub.left) / #categories, 1)
end

function ns.AchWalk_SetSkipped(fn)
	skipped = fn
end
