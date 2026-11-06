local addonName, ns = ...

-- World of Warcraft: Forever: Buff reminders' auras (see Core/Content.lua; read in Modules/Buffs/Read.lua). Matched by
-- localized name, so one spell ID stands for every rank and every food. IDs checked on wowhead.com/forever, 2026-11-05.
-- No flask or rune list: Forever added flasks whose buff IDs can't be checked yet, and a partial list would nag anyone
-- using one of the others. Warriors have no entry: Battle Shout lasts 3 minutes there, so it's no pre-pull check.

ns.Content_Register(ns.CONTENT_FOREVER, "buffs", {
	food = {
		19705, -- Well Fed
	},
	-- The single-target buff and its raid-wide version: either one counts. The first one is what the class must know.
	group = {
		MAGE = { 1459, 23028 }, -- Arcane Intellect, Arcane Brilliance
		PRIEST = { 1243, 21562 }, -- Power Word: Fortitude, Prayer of Fortitude
		DRUID = { 1126, 21849 }, -- Mark of the Wild, Gift of the Wild
	},
})
