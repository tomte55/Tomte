local addonName, ns = ...

-- What a row for a mount, battle pet, toy or achievement does when clicked, shift-clicked or hovered. Shared by the
-- Collect here map tab and the Events page; each caller keeps its own tooltip wording and preview setting.

local UI = ns.UI

-- Puts the entry's chat link into the open edit box (shift-click).
function ns.Entry_Link(e)
	if e.kind == "mount" then
		UI.InsertLink(e.spellID and C_MountJournal.GetMountLink(e.spellID))
	elseif e.kind == "toy" then
		UI.InsertLink(C_ToyBox.GetToyLink(e.id))
	elseif e.kind == "ach" then
		ns.Ach_Link(e.id)
	end
end

-- Opens the entry's journal page or achievement. Neither opens in combat: opening the load-on-demand
-- Achievements UI there may be blocked, and the journals are protected frames.
function ns.Entry_Open(e)
	if InCombatLockdown() then
		ns.Print_Combat("open the journal")
		return
	end
	if e.kind == "ach" then
		ns.Ach_Open(e.id)
	elseif e.kind == "mount" then
		SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS)
		if MountJournal_SelectByMountID then
			MountJournal_SelectByMountID(e.id)
		end
	elseif e.kind == "pet" then
		SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_PETS)
		if PetJournal and PetJournal_SelectSpecies then
			PetJournal_SelectSpecies(PetJournal, e.id)
		end
	elseif e.kind == "toy" then
		SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_TOYS)
	end
end

-- The spec for the turning model next to the tooltip (Panel/ModelPreview.lua), for mounts and pets; nil for the rest.
function ns.Entry_Model(e)
	if e.kind == "mount" then
		local displayID, _, _, isSelfMount, _, sceneID = C_MountJournal.GetMountInfoExtraByID(e.id)
		if not displayID then
			-- Mounts with several looks have no single display ID: use the first one.
			local all = C_MountJournal.GetMountAllCreatureDisplayInfoByID(e.id)
			displayID = all and all[1] and all[1].creatureDisplayID
		end
		return { sceneID = sceneID, displayID = displayID, selfMount = isSelfMount, name = e.name, sub = "Mount" }
	elseif e.kind == "pet" then
		-- Event entries carry their display ID; Collect's don't, so those read the journal.
		local displayID = e.displayID or select(12, C_PetJournal.GetPetInfoBySpeciesID(e.id))
		local sceneID = C_PetJournal.GetPetModelSceneInfoBySpeciesID(e.id)
		return { sceneID = sceneID, displayID = displayID, name = e.name, sub = "Battle pet" }
	end
	return nil
end
