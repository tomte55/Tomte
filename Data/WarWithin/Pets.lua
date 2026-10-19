local addonName, ns = ...

-- The War Within (expansion 10): pet battle tamers. See Core/Content.lua; merged in Modules/Pets/Tamers.lua.
-- Every NPC battle on Xu-Fu's Pet Guides (https://www.wow-petguide.com), from its section pages, 2026-10-10. Encounter
-- keys are Xu-Fu's encounter page ids (https://www.wow-petguide.com/Encounter/<id>), npcs are the game's NPC ids for
-- that fight. Ids are facts; no strategy content is copied. Names are Xu-Fu's English labels (they title links to an
-- English site); nothing matches on them. One NPC can be in several encounters (a world quest and a Family Battler
-- set). Registered under the expansion that added the content. kind, for the Guides window: "wq" (a pet battle
-- world quest), "family" (a Family Battler style achievement) or "tradingpost".

local E = 10

ns.Content_Register(E, "petSections", {
	{ id = 104, name = "The War Within world quests", kind = "wq" },
	{ id = 105, name = "Family Battler of Khaz Algar", kind = "family" },
	{ id = 111, name = "Undermine" },
	{ id = 107, name = "Incognitro mount hunt" },
	{ id = 94, name = "Gurgl, the blue murloc" },
})

ns.Content_Register(E, "petEncounters", {
	-- [Xu-Fu encounter id] = { section, name, npcs = { npcID, ... } }

	-- The War Within world quests
	[1589] = { section = 104, name = "Collector Dyna (Rock Collector)", npcs = { 223446 } },
	[1590] = { section = 104, name = "Robot Rumble", npcs = { 223407 } },
	[1592] = { section = 104, name = "Friendhaver Grem (The Power of Friendship)", npcs = { 223444 } },
	[1593] = { section = 104, name = "Major Malfunction", npcs = { 222535 } },
	[1595] = { section = 104, name = "Kyrie (Miniature Army)", npcs = { 223442 } },
	[1596] = { section = 104, name = "The Thing from the Swamp", npcs = { 223409 } },
	[1598] = { section = 104, name = "Ziriak", npcs = { 223443 } },
	[1599] = { section = 104, name = "One Hungry Worm", npcs = { 223406 } },

	-- Family Battler of Khaz Algar
	[1601] = { section = 105, name = "Collector Dyna (Rock Collector (Humanoid))", npcs = { 223446 } },
	[1603] = { section = 105, name = "Friendhaver Grem (The Power of Friendship (Humanoid))", npcs = { 223444 } },
	[1605] = { section = 105, name = "Kyrie (Miniature Army (Humanoid))", npcs = { 223442 } },
	[1607] = { section = 105, name = "Ziriak", npcs = { 223443 } },

	-- Undermine
	[1726] = { section = 111, name = "Precision Powerdrill (Drilling Down)", npcs = { 237701 } },
	[1727] = { section = 111, name = "Baxx the Purveyor (Tiny, Expensive, and Deadly)", npcs = { 237703 } },
	[1728] = { section = 111, name = "Prezly Wavecutter (Loyal Crewmates)", npcs = { 237712 } },
	[1729] = { section = 111, name = "Creech (Approach the Croach)", npcs = { 237718 } },

	-- Incognitro mount hunt
	[1725] = { section = 107, name = "Jeremy Feasel", npcs = { 232048 } },

	-- Gurgl, the blue murloc
	[1363] = { section = 94, name = "Trainer Iris Greedsway", npcs = { 179694 } },
})
