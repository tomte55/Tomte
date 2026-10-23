local addonName, ns = ...

-- Gear Check helpers: pure logic (no WoW API calls; unit-tested in tests/test_gear_helpers.lua). Which bag gems fit
-- the open sockets and which one Gear Check recommends (the strip is in Sockets.lua), which socket a picked gem goes
-- into, which bag items get the stronger quality border and the bag sort direction (Bags.lua), and when the
-- character pane opened at the upgrade NPC is closed again (Upgrade.lua).

-- Socket types any ordinary gem goes into. The others (Meta, Cogwheel, Domination, Primordial, the Singing ones,
-- Tinker...) take their own kind of gem, which bags rarely hold and the item data doesn't name: no strip for them.
local ORDINARY_SOCKETS = { Prismatic = true, Red = true, Yellow = true, Blue = true }

-- Quality at and above which an item gets the stronger border (Enum.ItemQuality.Rare = 3).
ns.GEAR_GLOW_MIN_QUALITY = 3

-- socketTypes: { "Prismatic", ... } per socket of the item being socketed. True when an ordinary gem fits one.
function ns.GearHelpers_TakesGems(socketTypes)
	for _, socketType in ipairs(socketTypes or {}) do
		if ORDINARY_SOCKETS[socketType] then
			return true
		end
	end
	return false
end

-- A bag item fits an ordinary socket when it's a gem (classID == gemClass) and not an artifact relic.
function ns.GearHelpers_IsGem(classID, subclassID, gemClass, relicSubclass)
	return classID ~= nil and classID == gemClass and subclassID ~= relicSubclass
end

-- sockets: { { type = "Prismatic", filled = bool } } (filled: a gem is in it or proposed for it). The first empty
-- ordinary socket, nil when none (then the gem just stays on the cursor for the player to drop).
function ns.GearHelpers_EmptySocket(sockets)
	for index, socket in ipairs(sockets or {}) do
		if not socket.filled and ORDINARY_SOCKETS[socket.type] then
			return index
		end
	end
	return nil
end

-- gems: { { itemID, name, count, stats, diamond } } as read from the bags (one entry per item ID). score(stats):
-- the gem's value under the character's weights (nil without weights). Sorts best first (unique diamonds after the
-- ranked gems, then by name) and marks the single best stat gem with .best when its value is above zero.
function ns.GearHelpers_RankGems(gems, score)
	local bestEntry, bestValue
	for _, gem in ipairs(gems) do
		gem.value = (not gem.diamond and gem.stats and score) and score(gem.stats) or 0
		gem.best = nil
		if gem.value > 0 and (not bestValue or gem.value > bestValue) then
			bestEntry, bestValue = gem, gem.value
		end
	end
	if bestEntry then
		bestEntry.best = true
	end
	table.sort(gems, function(a, b)
		if (a.diamond and true or false) ~= (b.diamond and true or false) then
			return not a.diamond
		end
		if a.value ~= b.value then
			return a.value > b.value
		end
		return (a.name or "") < (b.name or "")
	end)
	return gems
end

-- Whether a bag item of this quality gets the stronger border.
function ns.GearHelpers_Glows(quality)
	return type(quality) == "number" and quality >= ns.GEAR_GLOW_MIN_QUALITY
end

-- The bag sort setting ("keep", "ltr", "rtl") as the value for C_Container.SetSortBagsRightToLeft, nil for "keep"
-- (leave the game's own setting alone).
function ns.GearHelpers_SortRightToLeft(choice)
	if choice == "rtl" then
		return true
	elseif choice == "ltr" then
		return false
	end
	return nil
end

-- At the upgrade NPC: open the character pane when it's wanted and not already open. Close it on leaving only
-- when Tomte opened it and it's still open.
function ns.GearHelpers_ShouldOpenPane(wanted, inCombat, alreadyShown)
	return wanted and not inCombat and not alreadyShown
end

function ns.GearHelpers_ShouldClosePane(openedByUs, inCombat, shown)
	return openedByUs and not inCombat and shown
end
