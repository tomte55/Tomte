local addonName, ns = ...

-- Instances: pure logic (no WoW API calls; unit-tested in tests/test_instances.lua). The minimap badge text, who
-- may change difficulty, the lockout lines, the nearest instance portal, the queue ring's fill and wait text, and
-- the holiday dungeon pick. Read.lua reads the game into the tables these take.

-- DifficultyIDs (warcraft.wiki.gg DifficultyID, Blizzard's DifficultyUtil.ID).
ns.INSTANCES_DIFF = {
	dungeonNormal = 1, dungeonHeroic = 2, dungeonMythic = 23, keystone = 8, dungeonTimewalking = 24,
	raid10 = 3, raid25 = 4, raid10Heroic = 5, raid25Heroic = 6, raidLFRLegacy = 7, raid40 = 9,
	raidNormal = 14, raidHeroic = 15, raidMythic = 16, raidLFR = 17, raidTimewalking = 33, raidStory = 220,
}
local D = ns.INSTANCES_DIFF

-- The three choices on the entrance card and in the badge menu, Normal / Heroic / Mythic.
ns.INSTANCES_DUNGEON_CHOICES = { D.dungeonNormal, D.dungeonHeroic, D.dungeonMythic }
ns.INSTANCES_RAID_CHOICES = { D.raidNormal, D.raidHeroic, D.raidMythic }
ns.INSTANCES_LEGACY_CHOICES = { D.raid10, D.raid25 } -- the raid size for raids before Warlords of Draenor
-- The portal card at a raid from before Siege of Orgrimmar: size and Normal / Heroic together, with short labels.
ns.INSTANCES_LEGACY_FULL_CHOICES = {
	{ value = D.raid10, text = "10 N" }, { value = D.raid10Heroic, text = "10 H" },
	{ value = D.raid25, text = "25 N" }, { value = D.raid25Heroic, text = "25 H" },
}

-- Instance types that are outside for the badge: Blizzard's flag shows nothing in them (player housing).
local OUTSIDE = { none = true, interior = true, neighborhood = true }

-- A lockout on a legacy raid (10 or 25 player) counts for the Normal or Heroic choice it maps onto.
local SAME = {
	[D.raidNormal] = { [D.raidNormal] = true, [D.raid10] = true, [D.raid25] = true, [D.raid40] = true },
	[D.raidHeroic] = { [D.raidHeroic] = true, [D.raid10Heroic] = true, [D.raid25Heroic] = true },
}

-- Queue ring: how much each role counts towards "the group is forming". Tanks and healers are the scarce ones.
local ROLE_WEIGHT = { tank = 3, healer = 2, dps = 1 }

-- Holiday and Timewalking random dungeons (LfgDungeonIDs; the list Plumber's HolidayDungeon.lua keeps, game IDs
-- only). The isHoliday flag catches the rest.
ns.INSTANCES_SPECIAL_DUNGEONS = {
	[285] = true, -- Hallow's End, The Headless Horseman
	[286] = true, -- Midsummer Fire Festival, The Frost Lord Ahune
	[287] = true, -- Brewfest, Coren Direbrew
	[288] = true, -- Love is in the Air, The Crown Chemical Co.
	[744] = true, -- Random Timewalking Dungeon (Burning Crusade)
	[995] = true, -- Random Timewalking Dungeon (Wrath of the Lich King)
	[1146] = true, -- Random Timewalking Dungeon (Cataclysm)
	[1453] = true, -- Random Timewalking Dungeon (Mists of Pandaria)
	[1971] = true, -- Random Timewalking Dungeon (Warlords of Draenor)
	[2274] = true, -- Random Timewalking Dungeon (Legion)
	[2634] = true, -- Random Timewalking Dungeon (Classic)
	[2874] = true, -- Random Timewalking Dungeon (Battle for Azeroth)
	[3076] = true, -- Random Timewalking Dungeon (Shadowlands)
}

-- Badge ----------------------------------------------------------------------------------------------------------

-- The letter for a difficulty with its color role: "N", "H", "M", plus the named ones.
local LETTERS = {
	[D.dungeonNormal] = "N", [D.dungeonHeroic] = "H", [D.dungeonMythic] = "M", [D.keystone] = "M+",
	[D.dungeonTimewalking] = "TW", [D.raid10] = "N", [D.raid25] = "N", [D.raid10Heroic] = "H", [D.raid25Heroic] = "H",
	[D.raidLFRLegacy] = "LFR", [D.raid40] = "N", [D.raidNormal] = "N", [D.raidHeroic] = "H", [D.raidMythic] = "M",
	[D.raidLFR] = "LFR", [D.raidTimewalking] = "TW", [D.raidStory] = "Story",
}
local ROLES = { N = "text", H = "info", M = "accent", ["M+"] = "accent", D = "warning", LFR = "textMuted",
	TW = "info", Story = "textMuted", PvP = "danger" }

function ns.Instances_Letter(difficultyID)
	return LETTERS[difficultyID]
end

local function Role(letter)
	return ROLES[letter] or "text"
end

-- info (Read.lua's InstancesRead_Current): { instanceType ("none", "party", "raid", "scenario", "pvp", "arena"),
-- difficultyID, groupSize, isHeroic, isChallengeMode, displayHeroic, displayMythic, isLFR, keystone (level),
-- delveTier, worldTier ("heroic" | "mythic" | nil) }. Returns text, color role; nil outside instances.
function ns.Instances_BadgeText(info)
	if not info then
		return nil
	end
	local kind, id = info.instanceType, info.difficultyID
	if kind == "interior" or kind == "neighborhood" then
		return nil
	end
	if kind == nil or kind == "none" then
		if info.worldTier == "heroic" then
			return "H", Role("H")
		elseif info.worldTier == "mythic" then
			return "M", Role("M")
		end
		return nil
	end
	if kind == "pvp" or kind == "arena" then
		return "PvP", Role("PvP")
	end
	if info.delveTier then
		return "D" .. info.delveTier, Role("D")
	end
	if info.isChallengeMode or id == D.keystone then
		return "M+" .. (info.keystone and info.keystone > 0 and info.keystone or ""), Role("M+")
	end
	local letter = LETTERS[id]
	if info.isLFR or letter == "LFR" then
		return "LFR", Role("LFR")
	end
	if letter == "TW" or letter == "Story" then
		return letter, Role(letter)
	end
	if not letter or letter == "N" then
		if info.displayMythic then
			letter = "M"
		elseif info.isHeroic or info.displayHeroic then
			letter = "H"
		else
			letter = "N"
		end
	end
	local size = info.groupSize
	if size and size > 0 then
		return size .. " · " .. letter, Role(letter)
	end
	return letter, Role(letter)
end

-- True where the badge shows (and a click changes) the difficulty you've chosen: the open world and housing.
function ns.Instances_IsOutside(instanceType)
	return instanceType == nil or OUTSIDE[instanceType] == true
end

-- The legacy raid setting for a size (raid10 or raid25) on top of the raid difficulty: 10 Heroic while raids are
-- Heroic. nil while raids are Mythic: old raids have no Mythic, and Blizzard's portrait menu greys the sizes out.
function ns.Instances_LegacyFor(size, raidID)
	if raidID == D.raidMythic then
		return nil
	end
	if raidID == D.raidHeroic then
		return size == D.raid10 and D.raid10Heroic or D.raid25Heroic
	end
	return size == D.raid10 and D.raid10 or D.raid25
end

ns.INSTANCES_LEGACY_MYTHIC_REASON = "Old raids have no Mythic: set raids to Normal or Heroic first."

-- Outside an instance: the chosen dungeon and raid difficulty, "H / M".
function ns.Instances_OutsideText(dungeonID, raidID)
	return (LETTERS[dungeonID] or "?") .. " / " .. (LETTERS[raidID] or "?")
end

-- Who may choose ------------------------------------------------------------------------------------------------

-- state: { inInstance, inGroup, isLeader, inInstanceGroup (a Dungeon Finder group) }. Returns true, or false and
-- the reason in player wording.
function ns.Instances_CanChoose(state)
	if state.inInstance then
		return false, "You can't change difficulty inside an instance."
	end
	if state.inInstanceGroup then
		return false, "You can't change difficulty in a Dungeon Finder group."
	end
	if state.inGroup and not state.isLeader then
		return false, "Only the group leader can change difficulty."
	end
	return true
end

-- Lockouts ------------------------------------------------------------------------------------------------------

-- saves: { { difficultyID, locked, numEncounters, encounterProgress, extended } } for one instance. The save that
-- counts for a choice (Normal / Heroic / Mythic, legacy sizes folded in), or nil.
function ns.Instances_SaveFor(saves, choiceID)
	local same = SAME[choiceID]
	for _, s in ipairs(saves or {}) do
		if s.locked and (s.difficultyID == choiceID or (same and same[s.difficultyID])) then
			return s
		end
	end
	return nil
end

-- One save as a sentence for the banner: "Saved: 3 of 8 bosses down", "Saved: all 8 bosses down", "Not saved".
function ns.Instances_LockoutSummary(saved)
	if not (saved and saved.locked) then
		return "Not saved", "success"
	end
	local total, done = saved.numEncounters or 0, saved.encounterProgress or 0
	local text
	if total > 0 and done >= total then
		text = ("Saved: all %d bosses down"):format(total)
	elseif total > 0 then
		text = ("Saved: %d of %d bosses down"):format(done, total)
	else
		text = "Saved"
	end
	if saved.extended then
		text = text .. " (extended)"
	end
	return text, done >= total and total > 0 and "danger" or "warning"
end

-- The short form under a choice on the entrance card: "3/8", or "free".
function ns.Instances_LockoutShort(saved)
	if not (saved and saved.locked) then
		return "free", "textMuted"
	end
	local total, done = saved.numEncounters or 0, saved.encounterProgress or 0
	if total == 0 then
		return "saved", "warning"
	end
	return done .. "/" .. total, done >= total and "danger" or "warning"
end

-- Entrance ------------------------------------------------------------------------------------------------------

-- The nearest portal to the player. entrances: { { x, y, ... } } in map coordinates (0..1); px, py the player's;
-- width, height the map's size in yards. Returns the entrance and its distance in yards, or nil when none is
-- within range yards.
function ns.Instances_Nearest(entrances, px, py, width, height, range)
	if not (px and py and width and height) or width <= 0 or height <= 0 then
		return nil
	end
	local best, bestD
	for _, e in ipairs(entrances or {}) do
		local dx, dy = (e.x - px) * width, (e.y - py) * height
		local d = math.sqrt(dx * dx + dy * dy)
		if d <= range and (not bestD or d < bestD) then
			best, bestD = e, d
		end
	end
	return best, bestD
end

-- Queue ---------------------------------------------------------------------------------------------------------

-- How far the group has formed, 0..1. needs and totals: { tank, healer, dps } (still needed, needed in all).
-- nil when the queue has no roles (scenarios) or no data.
function ns.Instances_QueueProgress(needs, totals)
	if not (needs and totals) then
		return nil
	end
	local found, all = 0, 0
	for role, weight in pairs(ROLE_WEIGHT) do
		local total, need = totals[role], needs[role]
		if type(total) ~= "number" or type(need) ~= "number" then
			return nil
		end
		need = math.max(0, math.min(need, total))
		found = found + weight * (total - need)
		all = all + weight * total
	end
	if all <= 0 then
		return nil
	end
	return found / all
end

local function Clock(seconds)
	seconds = math.floor(math.max(seconds, 0) + 0.5)
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
	end
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- Time in queue and the average wait under it: "4:12", "avg 5:42", "textMuted"; once the wait runs 30 seconds past
-- the average, how far past: "2:10 over avg", "warning". The second part is nil without an average (the game gives 0
-- or nothing for some queues).
function ns.Instances_WaitText(elapsed, average)
	local text = Clock(elapsed or 0)
	if not average or average <= 0 then
		return text, nil, nil
	end
	local diff = (elapsed or 0) - average
	if diff >= 30 then
		return text, Clock(diff) .. " over avg", "warning"
	end
	return text, "avg " .. Clock(average), "textMuted"
end

local ROLE_ORDER = { { key = "tank", role = "TANK" }, { key = "healer", role = "HEALER" }, { key = "dps", role = "DAMAGER" } }

-- The queue plate's role slots: { { role = "TANK", found, total } ... } in tank, healer, damage order, roles the
-- group has no place for left out. Nil when the queue has no role data (scenarios) or a number is missing.
function ns.Instances_RoleSlots(needs, totals)
	if not (needs and totals) then
		return nil
	end
	local slots = {}
	for _, r in ipairs(ROLE_ORDER) do
		local total, need = totals[r.key], needs[r.key]
		if type(total) ~= "number" or type(need) ~= "number" then
			return nil
		end
		if total > 0 then
			slots[#slots + 1] = { role = r.role, found = total - math.max(0, math.min(need, total)), total = total }
		end
	end
	return #slots > 0 and slots or nil
end

-- Holiday dungeon -----------------------------------------------------------------------------------------------

-- list: { { id, isHoliday, isTimeWalker, joinable } } (Dungeon Finder's random dungeons). The one to select: a
-- holiday boss first, then Timewalking, the lowest ID within each; nil when none can be joined.
function ns.Instances_PickHoliday(list)
	local holiday, timewalking
	for _, d in ipairs(list or {}) do
		if d.joinable and (d.isHoliday or d.isTimeWalker or ns.INSTANCES_SPECIAL_DUNGEONS[d.id]) then
			if d.isTimeWalker then
				if not timewalking or d.id < timewalking then
					timewalking = d.id
				end
			elseif not holiday or d.id < holiday then
				holiday = d.id
			end
		end
	end
	return holiday or timewalking
end
