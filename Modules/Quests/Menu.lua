local addonName, ns = ...

-- Quests: the "Don't automate this NPC" entry in a targeted NPC's right-click menu, which adds it to (or takes it
-- off) the ignore list in Automation.lua. Blizzard's unit menus can only be extended with Menu.ModifyMenu (the
-- menu system is built so an addon's entries don't taint the rest); the hook can't be removed, so it adds nothing
-- while the module is off. Started by Quests.lua.

local MENU_TAG = "MENU_UNIT_TARGET" -- the target frame's menu ("MENU_UNIT_" .. Blizzard's "TARGET" menu)

local hooked = false
local enabled = false

local function AddEntry(owner, root, contextData)
	if not enabled then
		return
	end
	local unit = contextData and contextData.unit or "target"
	local npcID, name = ns.QuestsRead_UnitNpc(unit)
	if not npcID then
		return
	end
	local ignored = ns.QuestsAuto_IsIgnored(npcID)
	root:CreateDivider()
	root:CreateTitle("Tomte")
	root:CreateButton(ignored and "Automate quests here again" or "Don't automate quests here", function()
		ns.QuestsAuto_ToggleIgnore(npcID, name)
	end)
end

function ns.QuestsMenu_Start()
	enabled = true
	if not hooked and Menu and Menu.ModifyMenu then
		hooked = true
		Menu.ModifyMenu(MENU_TAG, AddEntry)
	end
end

function ns.QuestsMenu_Stop()
	enabled = false
end
