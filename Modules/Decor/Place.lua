local addonName, ns = ...

-- Housing decor: placing and reading decor in the house editor, shared by the Decor module's Alt "place another"
-- (Editor.lua) and the decorating tools (Decorate.lua and the files before it). Reads the hovered and selected decor
-- in any editor mode, starts placing a decor from storage by its decor ID, returns the selected decor to storage and
-- turns it in Basic mode. No state of its own besides the decor being placed; pure rules in EditorData.lua and
-- ToolsData.lua.

local ENTRY_DECOR = 1 -- Enum.HousingCatalogEntryType.Decor, when the enum is missing
local MODES = { None = 0, BasicDecor = 1, ExpertDecor = 2, Layout = 3, Customize = 4, Cleanup = 5 } -- fallbacks
-- Seconds after switching to Basic mode before StartPlacingNewDecor works (measured by AdvancedDecorationTools).
local MODE_SWITCH_DELAY = 0.2
-- The switch waits on the server: look this often, this many times, before saying it didn't happen.
local MODE_POLL, MODE_POLLS = 0.1, 20
local SUCCESS = 0 -- Enum.HousingResult.Success, when the enum is missing

local placing -- decor ID last started with StartPlacingNewDecor, while it's being placed

-- Modes -----------------------------------------------------------------------------------------------------------

function ns.DecorPlace_Mode(name)
	return Enum.HouseEditorMode and Enum.HouseEditorMode[name] or MODES[name]
end

-- The open editor mode, or None.
function ns.DecorPlace_EditorMode()
	if not (C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()) then
		return ns.DecorPlace_Mode("None")
	end
	return C_HouseEditor.GetActiveHouseEditorMode() or ns.DecorPlace_Mode("None")
end

local function DecorType()
	return Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor or ENTRY_DECOR
end

function ns.DecorPlace_Error(text)
	UIErrorsFrame:AddExternalErrorMessage(text)
end

-- A short confirmation in the middle of the screen, where the editor's own messages show.
function ns.DecorPlace_Note(text)
	local r, g, b = ns.UI.Color("accent")
	UIErrorsFrame:AddMessage(text, r, g, b)
end

-- Catalog ---------------------------------------------------------------------------------------------------------------

-- The catalog's entry for a decor ID (HousingCatalogEntryInfo), or nil.
function ns.DecorPlace_CatalogInfo(decorID)
	if type(decorID) ~= "number" or not C_HousingCatalog then
		return nil
	end
	local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByRecordID, DecorType(), decorID)
	return ok and type(info) == "table" and info or nil
end

-- Name and icon (a file ID or an atlas name, and which) for a decor ID.
function ns.DecorPlace_Look(decorID)
	local info = ns.DecorPlace_CatalogInfo(decorID)
	if not info then
		return ("Decor %d"):format(decorID or 0), 134400, false -- inv_misc_questionmark
	end
	if info.iconTexture then
		return info.name, info.iconTexture, false
	end
	return info.name, info.iconAtlas or 134400, info.iconAtlas ~= nil
end

-- Puts a decor's icon on a texture.
function ns.DecorPlace_SetIcon(texture, decorID)
	local _, icon, isAtlas = ns.DecorPlace_Look(decorID)
	if isAtlas then
		texture:SetAtlas(icon)
	else
		texture:SetTexture(icon)
	end
end

-- Hovered and selected --------------------------------------------------------------------------------------------------

local function Call(api, name)
	local fn = api and api[name]
	if not fn then
		return nil
	end
	local ok, value = pcall(fn)
	return ok and value or nil
end

-- The hovered placed decor (HousingDecorInstanceInfo: decorGUID, decorID, name, ...) or nil, in any mode.
function ns.DecorPlace_Hovered()
	if Call(C_HousingDecor, "IsHoveringDecor") then
		local info = Call(C_HousingDecor, "GetHoveredDecorInfo")
		if info and info.decorID then
			return info
		end
	end
	if Call(C_HousingCustomizeMode, "IsHoveringDecor") then
		return Call(C_HousingCustomizeMode, "GetHoveredDecorInfo")
	end
	return nil
end

-- The selected placed decor (HousingDecorInstanceInfo) or nil, in any mode.
function ns.DecorPlace_Selected()
	if Call(C_HousingDecor, "IsDecorSelected") then
		local info = Call(C_HousingDecor, "GetSelectedDecorInfo")
		if info and info.decorID then
			return info
		end
	end
	for _, api in ipairs({ C_HousingBasicMode, C_HousingExpertMode, C_HousingCustomizeMode }) do
		if Call(api, "IsDecorSelected") then
			local info = Call(api, "GetSelectedDecorInfo")
			if info and info.decorID then
				return info
			end
		end
	end
	return nil
end

-- The decor ID being placed from storage right now, or nil.
function ns.DecorPlace_Placing()
	if placing and Call(C_HousingBasicMode, "IsPlacingNewDecor") then
		return placing
	end
	return nil
end

-- The decor ID the last placement from storage started with (still set after it was placed), or nil.
function ns.DecorPlace_LastStarted()
	return placing
end

-- The decor in your hands: being placed, else selected. Decor ID or nil.
function ns.DecorPlace_Holding()
	local selected = ns.DecorPlace_Selected()
	return ns.DecorPlace_Placing() or (selected and selected.decorID)
end

-- Anything picked up (selected or being placed).
function ns.DecorPlace_Busy()
	return Call(C_HousingBasicMode, "IsPlacingNewDecor") or ns.DecorPlace_Selected() ~= nil
end

function ns.DecorPlace_CancelEditing()
	Call(C_HousingBasicMode, "CancelActiveEditing")
	Call(C_HousingExpertMode, "CancelActiveEditing")
end

-- Placing -------------------------------------------------------------------------------------------------------------

-- Remembers which decor a placement started with (any start: Blizzard's catalog, Alt, the tools), for the recent list
-- and Ctrl placing. Installed once, by whoever needs it first; it only stores a number.
local hooked = false
function ns.DecorPlace_TrackPlacing()
	if hooked or not (C_HousingBasicMode and C_HousingBasicMode.StartPlacingNewDecor) then
		return
	end
	hooked = true
	hooksecurefunc(C_HousingBasicMode, "StartPlacingNewDecor", function(entry)
		placing = type(entry) == "table" and entry.recordID or nil
	end)
end

-- Why a decor can't be placed here, or nil. info: its HousingCatalogEntryInfo.
local function CantPlace(info)
	if not info or ns.DecorEditor_Stored(info) == 0 then
		return "You have none of this decor in storage."
	end
	local inside = Call(C_Housing, "IsInsideHouse")
	if inside == true and info.isAllowedIndoors == false then
		return "This decor can only go outdoors."
	elseif inside == false and info.isAllowedOutdoors == false then
		return "This decor can only go indoors."
	end
	if not ns.DecorEditor_BudgetAllows(C_HousingDecor.GetSpentPlacementBudget(),
		C_HousingDecor.GetMaxPlacementBudget(), C_HousingDecor.HasMaxPlacementBudget(), info.placementCost) then
		return "No room left in this house's decor budget."
	end
	return nil
end

-- Starts placing a decor from storage. opts: dyeSlots (prefer a stored stack with these dyes), delay (seconds to wait
-- first: a mouse click that starts placing would otherwise drop the new decor where it was clicked), quiet (no error
-- text), onStart(). Switches to Basic mode first when another mode is open. Returns true when it will try.
function ns.DecorPlace_Start(decorID, opts)
	opts = opts or {}
	local info = ns.DecorPlace_CatalogInfo(decorID)
	local why = CantPlace(info)
	if why then
		if not opts.quiet then
			ns.DecorPlace_Error(why)
		end
		return false
	end
	local ok, variants = pcall(C_HousingCatalog.GetAllVariantInfosForEntry, { recordID = decorID, entryType = DecorType() })
	local variantID = ns.DecorEditor_PickVariant(ok and variants or nil, opts.dyeSlots,
		(info.remainingRedeemable or 0) > 0)
	if not variantID then
		if not opts.quiet then
			ns.DecorPlace_Error("Tomte can't find this decor in your storage.")
		end
		return false
	end
	local function Go()
		if ns.DecorPlace_EditorMode() ~= ns.DecorPlace_Mode("BasicDecor") then
			return
		end
		if ns.DecorPlace_Busy() then
			ns.DecorPlace_CancelEditing()
		end
		C_HousingBasicMode.StartPlacingNewDecor(variantID)
		if opts.onStart then
			opts.onStart()
		end
	end
	local basic = ns.DecorPlace_Mode("BasicDecor")
	if ns.DecorPlace_EditorMode() ~= basic then
		ns.DecorPlace_CancelEditing()
		local result = C_HouseEditor.ActivateHouseEditorMode(basic)
		if result ~= nil and result ~= (Enum.HousingResult and Enum.HousingResult.Success or SUCCESS) then
			ns.DecorPlace_Error("The editor can't switch to Basic mode right now.")
			return false
		end
		-- Basic mode once the server answers, then the settle time before placing works.
		local function Wait(tries)
			if ns.DecorPlace_EditorMode() == basic then
				C_Timer.After(math.max(MODE_SWITCH_DELAY, opts.delay or 0), Go)
			elseif tries > 0 and ns.DecorPlace_EditorMode() ~= ns.DecorPlace_Mode("None") then
				C_Timer.After(MODE_POLL, function()
					Wait(tries - 1)
				end)
			elseif tries == 0 then
				ns.DecorPlace_Error("The editor didn't switch to Basic mode: try again.")
			end
		end
		Wait(MODE_POLLS)
	elseif opts.delay then
		C_Timer.After(opts.delay, Go)
	else
		Go()
	end
	return true
end

-- Returns the selected decor to storage (the API that fits the open mode). False when nothing is selected or it
-- can't be removed.
function ns.DecorPlace_RemoveSelected()
	local selected = ns.DecorPlace_Selected()
	if not selected or selected.canBeRemoved == false then
		return false
	end
	local mode = ns.DecorPlace_EditorMode()
	local api = mode == ns.DecorPlace_Mode("ExpertDecor") and C_HousingExpertMode
		or mode == ns.DecorPlace_Mode("Cleanup") and C_HousingCleanupMode
		or mode == ns.DecorPlace_Mode("BasicDecor") and C_HousingBasicMode
		or C_HousingDecor
	if not (api and api.RemoveSelectedDecor) then
		api = C_HousingDecor
	end
	local ok = pcall(api.RemoveSelectedDecor)
	return ok
end

-- Turns the held or selected decor in Basic mode by `steps` of the game's own turn (the rotate keys' step; negative:
-- the other way), one per frame: calls in the same frame are dropped. False when nothing is held.
function ns.DecorPlace_Steps(steps)
	if ns.DecorPlace_EditorMode() ~= ns.DecorPlace_Mode("BasicDecor")
		or not (Call(C_HousingBasicMode, "IsPlacingNewDecor") or Call(C_HousingBasicMode, "IsDecorSelected")) then
		return false
	end
	local sign = steps < 0 and -1 or 1
	local function Step(left)
		if left <= 0 or ns.DecorPlace_EditorMode() ~= ns.DecorPlace_Mode("BasicDecor") then
			return
		end
		pcall(C_HousingBasicMode.RotateDecor, sign)
		C_Timer.After(0, function()
			Step(left - 1)
		end)
	end
	Step(math.abs(steps))
	return true
end

-- The same by about `degrees` (positive: the game's +1 direction).
function ns.DecorPlace_Rotate(degrees)
	local n, sign = ns.DecorTools_RotateSteps(degrees)
	return ns.DecorPlace_Steps(n * sign)
end
