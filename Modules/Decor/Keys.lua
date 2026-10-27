local addonName, ns = ...

-- Decorating tools: the keys. While the house editor is open in Basic or Expert mode, each action's key (settings,
-- `keys` in the db) is an override binding that clicks a hidden button; outside the editor, in the other modes and in
-- combat the keys are the game's again. Override bindings can't change in combat, so a change then waits for its end.
-- Registered in Decorate.lua.

local BUTTON_PREFIX = "TomteDecorKey" -- global names: SetOverrideBindingClick needs a named button

local OWNER = "keys"
local events = ns.Decorate_Events

local db
local active, editing = false, false
local mode = 0
local owner -- the frame that owns the override bindings
local buttons = {} -- [action] = button
local pending = false -- a change waits for combat to end

-- Basic-mode turn keys: something must be held or selected.
local function Rotate(degrees)
	if not ns.DecorPlace_Rotate(degrees) then
		ns.DecorPlace_Error("Pick up or select a decor to turn it.")
	end
end

-- Each action: its key in db.keys, the modes it works in ("basic", "expert" or "both") and what it does.
local ACTIONS = {
	{ key = "duplicate", modes = "both", run = function() ns.DecorateClip_Duplicate() end },
	{ key = "copy", modes = "both", run = function() ns.DecorateClip_Copy() end },
	{ key = "cut", modes = "both", run = function() ns.DecorateClip_Cut() end },
	{ key = "paste", modes = "both", run = function() ns.DecorateClip_Paste() end },
	{ key = "rotate", modes = "basic", run = function() Rotate(90) end },
	{ key = "rotateBack", modes = "basic", run = function() Rotate(-90) end },
	{ key = "reset", modes = "expert", run = function() ns.DecorateExpert_Reset(false) end },
	{ key = "resetAll", modes = "expert", run = function() ns.DecorateExpert_Reset(true) end },
	{ key = "axisX", modes = "expert", run = function() ns.DecorateExpert_Axis(1) end },
	{ key = "axisY", modes = "expert", run = function() ns.DecorateExpert_Axis(2) end },
	{ key = "axisZ", modes = "expert", run = function() ns.DecorateExpert_Axis(3) end },
	{ key = "lock", modes = "both", run = function() ns.DecorateLock_Toggle() end },
}
for slot = 1, 8 do
	ACTIONS[#ACTIONS + 1] = { key = "slot" .. slot, modes = "both", run = function()
		ns.DecorateBar_Press(slot)
	end }
end

local function Works(action)
	local basic = mode == ns.DecorPlace_Mode("BasicDecor")
	local expert = mode == ns.DecorPlace_Mode("ExpertDecor")
	if action.modes == "basic" then
		return basic
	elseif action.modes == "expert" then
		return expert
	end
	return basic or expert
end

-- Made on first use; clicked by the bindings only (a key press is a hardware event, as some editor calls want).
local function Button(action)
	local b = buttons[action.key]
	if b then
		return b
	end
	b = CreateFrame("Button", BUTTON_PREFIX .. action.key, UIParent)
	b:Hide()
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetScript("OnClick", function(_, _, down)
		if down and active and editing then
			action.run()
		end
	end)
	buttons[action.key] = b
	return b
end

local function Apply()
	if InCombatLockdown() then
		pending = true
		events:Watch(OWNER, "PLAYER_REGEN_ENABLED")
		return
	end
	pending = false
	owner = owner or CreateFrame("Frame")
	ClearOverrideBindings(owner)
	if not (active and editing) then
		return
	end
	for _, action in ipairs(ACTIONS) do
		local key = db.keys[action.key]
		if type(key) == "string" and key ~= "" and Works(action) then
			SetOverrideBindingClick(owner, true, key, Button(action):GetName(), "LeftButton")
		end
	end
end

events:On(OWNER, "PLAYER_REGEN_ENABLED", function()
	events:Unwatch(OWNER, "PLAYER_REGEN_ENABLED")
	if pending then
		Apply()
	end
end)

-- Called by Decorate.lua --------------------------------------------------------------------------------------------

function ns.DecorateKeys_Init(saved)
	db = saved
end

function ns.DecorateKeys_Start()
	active = true
	Apply()
end

function ns.DecorateKeys_Stop()
	active = false
	Apply()
end

function ns.DecorateKeys_Editing(on, newMode)
	editing, mode = on, newMode or 0
	Apply()
end

-- A key setting changed.
function ns.DecorateKeys_Apply()
	Apply()
end
