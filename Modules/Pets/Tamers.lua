local addonName, ns = ...

-- Pet Battles: the tamer table, merged from Data/<Expansion>/Pets.lua (pure logic: no WoW API calls; unit-tested in
-- tests/test_pets.lua). Each expansion registers "petSections" (Xu-Fu's sections, in list order) and "petEncounters"
-- ([Xu-Fu encounter id] = { section, name, npcs }) under the expansion that added the content; sources and fields are
-- described in Data/WarWithin/Pets.lua. The list covers every expansion on purpose (any character can fight old
-- tamers), so it doesn't follow the character's content expansion.

-- expansions: oldest first (ns.Content_Expansions), get = ns.Content_Get. Returns sections (newest expansion first,
-- registration order inside one; each gets .expansion), encounters (one map) and dupes (encounter ids registered by
-- two expansions, sorted; the newer one is kept).
function ns.Pets_MergeTamers(expansions, get)
	local sections, encounters, dupes = {}, {}, {}
	for i = #expansions, 1, -1 do
		local e = expansions[i]
		for _, s in ipairs(get(e, "petSections") or {}) do
			s.expansion = e
			sections[#sections + 1] = s
		end
		for id, encounter in pairs(get(e, "petEncounters") or {}) do
			if encounters[id] then
				dupes[#dupes + 1] = id
			else
				encounters[id] = encounter
			end
		end
	end
	table.sort(dupes)
	return sections, encounters, dupes
end

ns.PETS_SECTIONS, ns.PETS_ENCOUNTERS = ns.Pets_MergeTamers(ns.Content_Expansions(), ns.Content_Get)

-- /tomte data: what this expansion adds to the list (a Midnight owner can paste it).
ns.Content_AddCheck("Pet tamers", function(expansion)
	local count = 0
	for _ in pairs(ns.Content_Get(expansion, "petEncounters") or {}) do
		count = count + 1
	end
	local sections = ns.Content_Get(expansion, "petSections") or {}
	return { ("%d sections and %d fights from this expansion; %d sections in all"):format(#sections, count,
		#ns.PETS_SECTIONS) }
end)
