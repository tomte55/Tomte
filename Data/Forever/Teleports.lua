local addonName, ns = ...

-- Teleports on World of Warcraft: Forever, read by Modules/Teleports/Owned.lua instead of the retail lists in its
-- Data.lua. Each ID checked on wowhead.com/forever (Forever's own spell and item pages); an unknown or unowned ID just
-- doesn't show up.

ns.Content_Register(ns.CONTENT_FOREVER, "teleports", {
	-- Known spells, class by class (the ones in a spellbook flyout, if a class has any, aren't listed twice).
	spells = {
		18960, -- Teleport: Moonglade (Druid)
		556, -- Astral Recall (Shaman)
		3561, -- Teleport: Stormwind (Mage)
		3562, -- Teleport: Ironforge (Mage)
		3565, -- Teleport: Darnassus (Mage)
		3567, -- Teleport: Orgrimmar (Mage)
		3563, -- Teleport: Undercity (Mage)
		3566, -- Teleport: Thunder Bluff (Mage)
		1297659, -- Teleport: Dalaran (Mage; Forever's own)
		10059, -- Portal: Stormwind (Mage)
		11416, -- Portal: Ironforge (Mage)
		11419, -- Portal: Darnassus (Mage)
		11417, -- Portal: Orgrimmar (Mage)
		11418, -- Portal: Undercity (Mage)
		11420, -- Portal: Thunder Bluff (Mage)
	},
	-- None known yet: no hearthstone toy or hearthstone-like item is confirmed on Forever (the Hearthstone itself is
	-- Blizzard's HEARTHSTONE_ITEM_ID, which Data.lua's TP_HEARTHSTONE already is).
	hearthToys = {},
	hearthItems = {},
	-- kind "either": retail made these two toys; on Forever they may be bag items.
	items = {
		{ kind = "either", id = 18984 }, -- Dimensional Ripper - Everlook
		{ kind = "either", id = 18986 }, -- Ultrasafe Transporter: Gadgetzan
	},
})
