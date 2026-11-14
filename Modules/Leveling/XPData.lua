local addonName, ns = ...

-- Leveling: pure logic (no WoW API calls; unit-tested in tests/test_xpdata.lua). The XP each level takes, for how far
-- past the next level your finished quests would carry you. The game only tells the current level's (UnitXPMax).

-- XP from each level to the next: Classic's table (warcraft.wiki.gg Experience_to_level, 2026-11-14). Forever's
-- matches where measured: level 9, 2,010 XP to go at 69% (6,500).
local XP_TO_NEXT = {
	400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
	8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
	25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
	50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
	95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
	153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

-- Where XP past the next level takes you. level: yours now; beyond: XP left once the next level is reached. Returns the
-- level you'd be and how far into it (0..99 percent; nil at the level cap), or nil for a level the table doesn't know.
function ns.Leveling_XPBeyond(level, beyond)
	if not XP_TO_NEXT[level] then
		return nil
	end
	local at = level + 1
	while XP_TO_NEXT[at] and beyond >= XP_TO_NEXT[at] do
		beyond = beyond - XP_TO_NEXT[at]
		at = at + 1
	end
	if not XP_TO_NEXT[at] then
		return at, nil
	end
	return at, math.floor(beyond / XP_TO_NEXT[at] * 100)
end
