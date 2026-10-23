local addonName, ns = ...

-- Gear Check at the item upgrade NPC: opening the upgrade window opens the character pane beside it, and leaving
-- closes it again when Tomte opened it. Out of combat only (CharacterFrame is a UI panel). Rules in HelperData.lua;
-- started and stopped by Gear.lua.

local UPGRADE = Enum.PlayerInteractionType.ItemUpgrade

local events = ns.Gear_Events
local ShouldOpen = ns.GearHelpers_ShouldOpenPane
local ShouldClose = ns.GearHelpers_ShouldClosePane

local db
local openedByUs = false

local function PaneShown()
	return CharacterFrame and CharacterFrame:IsShown() or false
end

events:On("upgrade", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, interaction)
	if interaction ~= UPGRADE or not ShouldOpen(db.upgradePane, InCombatLockdown(), PaneShown()) then
		return
	end
	-- Next frame: the upgrade window takes its place first, so the character pane opens beside it.
	C_Timer.After(0, function()
		if ns.gearModule.active and ShouldOpen(db.upgradePane, InCombatLockdown(), PaneShown()) then
			ToggleCharacter("PaperDollFrame", true)
			openedByUs = PaneShown()
		end
	end)
end)

events:On("upgrade", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, interaction)
	if interaction ~= UPGRADE then
		return
	end
	if ShouldClose(openedByUs, InCombatLockdown(), PaneShown()) then
		HideUIPanel(CharacterFrame)
	end
	openedByUs = false
end)

function ns.GearUpgrade_Start(moduleDB)
	db = moduleDB
	events:Watch("upgrade", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
	events:Watch("upgrade", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
end

function ns.GearUpgrade_Stop()
	events:UnwatchAll("upgrade")
	openedByUs = false
end
