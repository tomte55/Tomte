local addonName, ns = ...

-- Decorating tools: locked decor and the hover lines. The lock key on a hovered decor locks it (by its GUID, saved);
-- picking up a locked decor in Basic or Expert mode is cancelled at once. The hovered decor's tooltip says when it's
-- locked and, in Basic mode, which keys do what (Key hints setting). Registered in Decorate.lua.

local MOUSE_OVER = "HousingDecorInstance.MouseOver" -- EventRegistry event of Blizzard_HouseEditorTemplates.lua
local SUCCESS = 0 -- Enum.HousingResult.Success, when the enum is missing
local UI = ns.UI

local OWNER = "lock"
local events = ns.Decorate_Events

local db
local active, editing = false, false
local mode = 0
local hoverOwner = {} -- our EventRegistry owner
local hoverRegistered = false
local unsticking = false

local function DecorMode()
	return mode == ns.DecorPlace_Mode("BasicDecor") or mode == ns.DecorPlace_Mode("ExpertDecor")
end

function ns.DecorateLock_Toggle()
	local hovered = ns.DecorPlace_Hovered()
	if not (hovered and hovered.decorGUID) then
		ns.DecorPlace_Error("Point at a decor to lock or unlock it.")
		return
	end
	local name = hovered.name or (ns.DecorPlace_Look(hovered.decorID))
	if db.locked[hovered.decorGUID] then
		db.locked[hovered.decorGUID] = nil
		ns.DecorPlace_Note(("Unlocked %s"):format(name))
	else
		db.locked[hovered.decorGUID] = { id = hovered.decorID, at = time() }
		ns.DecorPlace_Note(("Locked %s: it can't be picked up until you unlock it"):format(name))
	end
end

-- After a cancelled pickup Blizzard's editor sometimes ignores clicks until the mode changes: switch to the other decor
-- mode and back, a frame each (measured by AdvancedDecorationTools).
local function Unstick()
	if unsticking then
		return
	end
	local basic, expert = ns.DecorPlace_Mode("BasicDecor"), ns.DecorPlace_Mode("ExpertDecor")
	local current = mode
	local other = current == basic and expert or basic
	local okA, available = pcall(C_HouseEditor.GetHouseEditorModeAvailability, other)
	local success = Enum.HousingResult and Enum.HousingResult.Success or SUCCESS
	if not (okA and available == success) then
		return
	end
	unsticking = true
	C_Timer.After(0, function()
		if editing and mode == current then
			pcall(C_HouseEditor.ActivateHouseEditorMode, other)
			C_Timer.After(0, function()
				if editing then
					pcall(C_HouseEditor.ActivateHouseEditorMode, current)
				end
				unsticking = false
			end)
		else
			unsticking = false
		end
	end)
end

local function SelectionChanged(_, hasSelected)
	if not hasSelected or unsticking then
		return
	end
	local selected = ns.DecorPlace_Selected()
	if selected and selected.decorGUID and db.locked[selected.decorGUID] then
		ns.DecorPlace_CancelEditing()
		local key = db.keys.lock
		ns.DecorPlace_Error(key ~= "" and ("Locked: point at it and press %s to unlock."):format(ns.KeyText(key))
			or "Locked: unlock it in the Decorating tools first.")
		Unstick()
	end
end
events:On(OWNER, "HOUSING_BASIC_MODE_SELECTED_TARGET_CHANGED", SelectionChanged)
events:On(OWNER, "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED", SelectionChanged)

-- Hover lines -----------------------------------------------------------------------------------------------------------

-- Next frame, after the Decor module's hover info (if it's on) has drawn the tooltip: add to it, or start one.
local function OnMouseOver(_, modeFrame)
	if not (active and editing and DecorMode()) then
		return
	end
	C_Timer.After(0, function()
		local hovered = ns.DecorPlace_Hovered()
		if not (hovered and active and editing) then
			return
		end
		local lines = {}
		if hovered.decorGUID and db.locked[hovered.decorGUID] then
			lines[#lines + 1] = { "Locked", "warning" }
		end
		local hint = db.hints and mode == ns.DecorPlace_Mode("BasicDecor") and ns.DecorTools_HintLine(db.keys, ns.KeyText)
		if hint then
			lines[#lines + 1] = { hint, "textMuted" }
		end
		if #lines == 0 then
			return
		end
		if not GameTooltip:IsShown() then
			GameTooltip:SetOwner(modeFrame, "ANCHOR_CURSOR_RIGHT")
			GameTooltip:SetText(hovered.name or "", UI.Color("heading"))
		end
		for _, line in ipairs(lines) do
			UI.TipLine(line[1], line[2])
		end
		GameTooltip:Show()
	end)
end

local function Update()
	local on = active and editing and DecorMode()
	if on then
		events:TryWatch(OWNER, "HOUSING_BASIC_MODE_SELECTED_TARGET_CHANGED")
		events:TryWatch(OWNER, "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED")
	else
		events:UnwatchAll(OWNER)
	end
	if on and not hoverRegistered then
		EventRegistry:RegisterCallback(MOUSE_OVER, OnMouseOver, hoverOwner)
		hoverRegistered = true
	elseif not on and hoverRegistered then
		EventRegistry:UnregisterCallback(MOUSE_OVER, hoverOwner)
		hoverRegistered = false
	end
end

-- Called by Decorate.lua --------------------------------------------------------------------------------------------

function ns.DecorateLock_Init(saved)
	db = saved
end

function ns.DecorateLock_Start()
	active = true
	Update()
end

function ns.DecorateLock_Stop()
	active = false
	Update()
end

function ns.DecorateLock_Editing(on, newMode)
	editing, mode = on, newMode or 0
	Update()
end
