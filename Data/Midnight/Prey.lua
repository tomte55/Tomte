local addonName, ns = ...

-- Midnight (expansion 11): Prey hunt data. See Core/Content.lua; read by Modules/Prey. Quest, criteria, achievement
-- and faction IDs from Plumber (no license; game IDs only, no code, checked 2026-10-23: Modules/Shared/SharedData.lua PreyQuestData,
-- Modules/HuntTable.lua, ExpansionLandingPage/Retail/MID_Activity.lua), achievement names checked on Wowhead.
-- Each difficulty's hunt quests are listed in the order of their criteria on that difficulty's "Prey: <difficulty>
-- Mode" achievement: the n-th quest is criteria firstCriteria + n - 1. A friend checks these with /tomte data.

local function Range(first, last, step)
	local list = {}
	for id = first, last, step or 1 do
		list[#list + 1] = id
	end
	return list
end

local function Join(a, b)
	for _, id in ipairs(b) do
		a[#a + 1] = id
	end
	return a
end

ns.Content_Register(11, "prey", {
	journey = 2764, -- Prey: Season 1, the Preyseeker's journey (Hard opens at rank 1, Nightmare at rank 4)
	perWeek = 4, -- hunts per difficulty each week
	chestsPerWeek = 2, -- the first two of a difficulty each week give a chest, later ones a sack
	difficulties = {
		{ name = "Normal", rank = 0, achievement = 42701, firstCriteria = 105912, quests = Range(91095, 91124) },
		{ name = "Hard", rank = 1, achievement = 42702, firstCriteria = 105942,
			quests = Join(Range(91210, 91240, 2), Range(91242, 91255)) },
		{ name = "Nightmare", rank = 4, achievement = 42703, firstCriteria = 105972,
			quests = Join(Range(91211, 91241, 2), Range(91256, 91269)) },
	},
	-- 12.1 Nightmare targets outside the lists, each a criteria of its own achievement.
	extra = {
		{ quest = 95021, difficulty = 3, achievement = 63452, criteria = 115704 }, -- Janoa the Fang (Fangs for the Memories)
		{ quest = 95022, difficulty = 3, achievement = 63452, criteria = 115705 }, -- Kursak the Coiled
		{ quest = 95023, difficulty = 3, achievement = 63451, criteria = 115706 }, -- Batani the Scaled (Scales for Days)
		{ quest = 95024, difficulty = 3, achievement = 63451, criteria = 115707 }, -- Kadani the Claw
	},
})
