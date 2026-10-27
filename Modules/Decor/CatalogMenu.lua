local addonName, ns = ...

-- Decorating tools: Tomte's entries in the right-click menu of a decor in Blizzard's storage list. Favorite, Tags
-- (your own named groups) and Destroy a number (Blizzard's menu only destroys one or all). Favorites and tags show on
-- the Decorating panel's Saved tab (Dock.lua). Added with Menu.ModifyMenu, the way Blizzard's menus are extended; the
-- addition can't be taken off again, so it does nothing while the module is off. Rules in ToolsData.lua; registered in
-- Decorate.lua.

local MENU_TAG = "MENU_HOUSING_CATALOG_ENTRY" -- Blizzard_HousingCatalogEntry.lua's context menu
local DESTROY_MAX = 100 -- most decor one Destroy a number run takes out
-- Seconds between two destroys: one at a time, spaced so the server keeps up (measured by AdvancedDecorationTools).
local DESTROY_GAP = 0.5

local db
local active = false
local hooked = false
local destroying -- { variant, left, name } while a Destroy a number run goes on

local function Refresh()
	ns.DecorateDock_Refresh()
end

-- Destroy a number --------------------------------------------------------------------------------------------------

local function DestroyNext()
	local run = destroying
	if not run then
		return
	end
	if not active or run.left <= 0 then
		destroying = nil
		ns.Print(("destroyed %d %s."):format(run.done, run.name))
		return
	end
	local ok = pcall(C_HousingCatalog.DestroyEntry, run.variant, false)
	if not ok then
		destroying = nil
		ns.Print(("stopped destroying %s after %d: the game refused."):format(run.name, run.done))
		return
	end
	run.left, run.done = run.left - 1, run.done + 1
	C_Timer.After(DESTROY_GAP, DestroyNext)
end

local function AskDestroy(variant, name, destroyable)
	ns.Dialog_Show({ title = "Destroy a number", text = "", saveText = "Destroy", height = 150,
		hint = ("How many %s to destroy? You can destroy up to %d."):format(name, destroyable),
		onSave = function(text)
			local count = ns.DecorTools_DestroyCount(text, destroyable, DESTROY_MAX)
			if not count then
				return "Type a number."
			end
			C_Timer.After(0, function()
				ns.Confirm_Show(("Destroy %d %s?\n\nThey're gone for good. Tomte destroys one every half second."):format(
					count, name), function()
					destroying = { variant = variant, left = count, done = 0, name = name }
					DestroyNext()
				end, { yes = "Destroy", no = "Cancel" })
			end)
			return nil
		end })
end

-- Menu --------------------------------------------------------------------------------------------------------------

local function NewTag(decorID)
	ns.Dialog_Show({ title = "New tag", text = "", saveText = "Add", height = 150,
		hint = "A name for the tag (Kitchen, Garden...). The decor goes in it.",
		onSave = function(text)
			local name = ns.DecorTools_TagName(text)
			if not name then
				return "Type a name."
			end
			db.tags[name] = db.tags[name] or {}
			db.tags[name][decorID] = true
			Refresh()
			return nil
		end })
end

local function AddEntries(owner, root)
	if not active then
		return
	end
	local variant = owner and owner.entryVariantID
	local info = owner and owner.entryInfo
	local decorID = type(variant) == "table" and variant.recordID
	if not (decorID and info) then
		return
	end
	root:CreateDivider()
	root:CreateTitle("Tomte")
	root:CreateCheckbox("Favorite", function()
		return db.favorites[decorID] == true
	end, function()
		db.favorites[decorID] = not db.favorites[decorID] or nil
		Refresh()
	end)
	local tags = root:CreateButton("Tags")
	for _, name in ipairs(ns.DecorTools_TagNames(db.tags)) do
		tags:CreateCheckbox(name, function()
			return db.tags[name] and db.tags[name][decorID] == true
		end, function()
			ns.DecorTools_TagToggle(db.tags, name, decorID)
			Refresh()
		end)
	end
	tags:CreateButton("New tag...", function()
		NewTag(decorID)
	end)
	local context = owner.GetDisplayContext and owner:GetDisplayContext()
	local destroyable = info.destroyableInstanceCount or 0
	if context and context.showDestroyOptions and destroyable > 1 and not destroying then
		root:CreateButton("Destroy a number...", function()
			AskDestroy(variant, info.name or "decor", destroyable)
		end)
	end
end

-- Called by Decorate.lua --------------------------------------------------------------------------------------------

function ns.DecorateMenu_Init(saved)
	db = saved
end

function ns.DecorateMenu_Start()
	active = true
	if not hooked and Menu and Menu.ModifyMenu then
		hooked = true
		Menu.ModifyMenu(MENU_TAG, AddEntries)
	end
end

function ns.DecorateMenu_Stop()
	active = false
	destroying = nil
end
