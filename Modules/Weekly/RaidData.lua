local addonName, ns = ...

-- Raids tab: pure logic (tested with plain Lua). Journal instance IDs per expansion, newest first (Plumber's list,
-- checked 2026-10-08), and the four difficulties (DifficultyUtil.ID.PrimaryRaidLFR/Normal/Heroic/Mythic).

ns.WEEKLY_RAIDS = {
	[10] = { 1302, 1296, 1273 }, -- Manaforge Omega, Liberation of Undermine, Nerub-ar Palace
}

ns.WEEKLY_RAID_DIFFICULTIES = {
	{ id = 17, short = "L", name = "LFR" },
	{ id = 14, short = "N", name = "Normal" },
	{ id = 15, short = "H", name = "Heroic" },
	{ id = 16, short = "M", name = "Mythic" },
}

-- raids = { { id, name, mapID, bosses = { { name, encounterID } } } }; isKilled(mapID, encounterID, difficultyID);
-- collapsed[id] = true. Returns { kind = "raid", id, name, totals = { "3/8", ... }, collapsed } and
-- { kind = "boss", name, dots = { bool x 4 } } items, bosses under their raid unless it's collapsed.
function ns.Weekly_RaidModel(raids, isKilled, collapsed)
	local items = {}
	for _, raid in ipairs(raids) do
		local header = { kind = "raid", id = raid.id, name = raid.name, totals = {}, collapsed = collapsed[raid.id] == true }
		items[#items + 1] = header
		local kills, bosses = {}, {}
		for _, boss in ipairs(raid.bosses) do
			local dots = {}
			for d, diff in ipairs(ns.WEEKLY_RAID_DIFFICULTIES) do
				dots[d] = isKilled(raid.mapID, boss.encounterID, diff.id) == true
				kills[d] = (kills[d] or 0) + (dots[d] and 1 or 0)
			end
			bosses[#bosses + 1] = { kind = "boss", name = boss.name, dots = dots }
		end
		for d in ipairs(ns.WEEKLY_RAID_DIFFICULTIES) do
			header.totals[d] = ("%d/%d"):format(kills[d] or 0, #raid.bosses)
		end
		if not header.collapsed then
			for _, b in ipairs(bosses) do
				items[#items + 1] = b
			end
		end
	end
	return items
end
