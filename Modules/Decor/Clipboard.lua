local addonName, ns = ...

-- Decorating tools: the clipboard (copy, cut, paste, place another), the recent placements, and holding Ctrl to keep
-- placing the same decor with each next piece turned a bit more. The clipboard is one saved list, newest first: copy
-- adds the hovered decor, cut puts the selected decor back in storage and counts it as one to place, paste picks up
-- the top one. A copy is turned like the decor it came from, as far as Tomte saw it turned (Turns below). Rules in
-- ToolsData.lua, placing in Place.lua; registered in Decorate.lua. This file makes the tools' event bus
-- (ns.Decorate_Events).

local CLIP_MAX = 100 -- decor on the clipboard (an imported list can be long)
local RECENT_MAX = 10 -- recent placements kept
-- Seconds after a placement before Ctrl picks up the next piece: in the same frame the game drops the start.
local AGAIN_DELAY = 0.05
-- Seconds after picking up the next piece before turning it (the turn is lost while the pickup is still settling).
local TURN_DELAY = 0.1

local OWNER = "clipboard"
local events = ns.NewEvents()
ns.Decorate_Events = events

local db
local editing = false
local listeners = {}
local fromClip -- decor ID last started from the clipboard, until it's placed
local runFrom -- how the Ctrl run started: { clip = from the clipboard, dyeSlots }, carried to each next piece
local held = 0 -- turn steps given to the decor being placed from storage
local hooked = false

local function Changed()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

-- fn() after the clipboard, the recent list or the quickbar changed (the panel and the quickbar redraw).
function ns.DecorateClip_Listen(fn)
	listeners[#listeners + 1] = fn
end

function ns.DecorateClip_Changed()
	Changed()
end

function ns.DecorateClip_List()
	return db.clipboard
end

function ns.DecorateClip_Recent()
	return db.recent
end

-- Turns ---------------------------------------------------------------------------------------------------------------

-- The game doesn't tell addons how a placed decor is turned, but every Basic-mode turn (Blizzard's rotate keys and
-- Tomte's) goes through C_HousingBasicMode.RotateDecor: Tomte counts them per decor (db.turns, by GUID) and turns a
-- copy the same. A decor turned in Expert mode (any axis, by dragging) can't be followed: it's marked unknown (false).

-- Turn steps of a placed decor: a number (0 when Tomte never saw it turned), or nil when it was turned in Expert mode.
local function TurnsOf(guid)
	local turns = guid and db.turns[guid]
	if turns == false then
		return nil
	end
	return turns or 0
end

local function SelectedGUID()
	local selected = ns.DecorPlace_Selected()
	return selected and selected.decorGUID
end

local function Forget(guid)
	if guid then
		db.turns[guid] = false
	end
end

-- Hooks can't be taken off: they do nothing while the editor is closed or the module is off (editing is false then).
local function Hook()
	if hooked then
		return
	end
	hooked = true
	hooksecurefunc(C_HousingBasicMode, "RotateDecor", function(direction)
		if not editing or type(direction) ~= "number" or direction == 0 then
			return
		end
		local step = direction < 0 and -1 or 1
		if C_HousingBasicMode.IsPlacingNewDecor() then
			held = held + step
			return
		end
		local guid = SelectedGUID()
		if guid and db.turns[guid] ~= false then
			db.turns[guid] = (db.turns[guid] or 0) + step
		end
	end)
	hooksecurefunc(C_HousingBasicMode, "StartPlacingNewDecor", function()
		held = 0
	end)
	-- Expert mode's turn keys and Tomte's turn buttons: the result can't be counted.
	hooksecurefunc(C_HousingExpertMode, "SetPrecisionIncrementingActive", function()
		if editing then
			Forget(SelectedGUID())
		end
	end)
	-- A reset of all transforms (or of the turn alone) puts the decor back the way it was first placed.
	hooksecurefunc(C_HousingExpertMode, "ResetPrecisionChanges", function(activeSubmodeOnly)
		if not editing then
			return
		end
		local ok, submode = pcall(C_HousingExpertMode.GetPrecisionSubmode)
		local rotate = Enum.HousingPrecisionSubmode and Enum.HousingPrecisionSubmode.Rotate or 1
		local guid = SelectedGUID()
		if guid and (not activeSubmodeOnly or (ok and submode == rotate)) then
			db.turns[guid] = nil
		end
	end)
end

-- Dragging Expert mode's gizmo.
events:On(OWNER, "HOUSING_DECOR_PRECISION_MANIPULATION_STATUS_CHANGED", function(_, isManipulating)
	if isManipulating then
		Forget(SelectedGUID())
	end
end)

events:On(OWNER, "HOUSING_DECOR_REMOVED", function(_, decorGUID)
	if decorGUID then
		db.turns[decorGUID] = nil
	end
end)

-- Turns the decor just picked up by `steps` once the pickup has settled (in a Ctrl run only while Ctrl is held).
local function TurnNew(steps, needCtrl)
	if not steps or steps == 0 then
		return
	end
	C_Timer.After(TURN_DELAY, function()
		if editing and (not needCtrl or IsControlKeyDown()) then
			ns.DecorPlace_Steps(steps)
		end
	end)
end

-- Says so when the source decor's turn can't be copied.
local function NoteUnknown(guid)
	if guid and db.turns[guid] == false then
		ns.DecorPlace_Note("It was turned in Expert mode: Tomte can't copy that turn.")
	end
end

-- Placing from the tools ------------------------------------------------------------------------------------------

-- Picks up a decor from storage. opts: fromClip (placing it counts down its clipboard number), delay (a mouse click
-- started it), dyeSlots, turns (turn steps to give it, as the decor it copies).
function ns.DecorateClip_Place(decorID, opts)
	opts = opts or {}
	return ns.DecorPlace_Start(decorID, { delay = opts.delay, dyeSlots = opts.dyeSlots, onStart = function()
		fromClip = opts.fromClip and decorID or nil
		runFrom = { clip = opts.fromClip, dyeSlots = opts.dyeSlots }
		TurnNew(opts.turns)
	end })
end

-- Picks up a clipboard decor, turned as it was when copied.
function ns.DecorateClip_PlaceEntry(decorID, delay)
	local turns
	for _, e in ipairs(db.clipboard) do
		if e.id == decorID then
			turns = e.turns
			break
		end
	end
	return ns.DecorateClip_Place(decorID, { fromClip = true, delay = delay, turns = turns })
end

local function NameOf(info)
	return info.name or (ns.DecorPlace_Look(info.decorID))
end

function ns.DecorateClip_Copy()
	local info = ns.DecorPlace_Hovered() or ns.DecorPlace_Selected()
	if not info then
		ns.DecorPlace_Error("Point at a decor to copy it.")
		return
	end
	ns.DecorTools_ClipAdd(db.clipboard, info.decorID, false, CLIP_MAX).turns = TurnsOf(info.decorGUID)
	ns.DecorPlace_Note(("Copied %s"):format(NameOf(info)))
	NoteUnknown(info.decorGUID)
	Changed()
end

-- Only the selected decor can be put away (addons can't select one): with just a hover, cut copies and says so.
function ns.DecorateClip_Cut()
	local selected = ns.DecorPlace_Selected()
	if not selected then
		local hovered = ns.DecorPlace_Hovered()
		if hovered then
			ns.DecorTools_ClipAdd(db.clipboard, hovered.decorID, false, CLIP_MAX).turns = TurnsOf(hovered.decorGUID)
			ns.DecorPlace_Note("Copied. Click the decor to pick it up, then cut to put it away.")
			Changed()
		else
			ns.DecorPlace_Error("Click a decor first, then cut it.")
		end
		return
	end
	if selected.canBeRemoved == false then
		ns.DecorPlace_Error("This decor can't go back to storage.")
		return
	end
	local turns = TurnsOf(selected.decorGUID)
	if not ns.DecorPlace_RemoveSelected() then
		ns.DecorPlace_Error("Tomte can't put this decor away.")
		return
	end
	ns.DecorTools_ClipAdd(db.clipboard, selected.decorID, true, CLIP_MAX).turns = turns
	NoteUnknown(selected.decorGUID)
	ns.DecorPlace_Note(("Cut %s: back in storage and on the clipboard"):format(NameOf(selected)))
	Changed()
end

function ns.DecorateClip_Paste()
	local top = db.clipboard[1]
	if not top then
		ns.DecorPlace_Error("The clipboard is empty: copy a decor first.")
		return
	end
	ns.DecorateClip_Place(top.id, { fromClip = true, turns = top.turns })
end

function ns.DecorateClip_Duplicate()
	local info = ns.DecorPlace_Hovered() or ns.DecorPlace_Selected()
	if not info then
		ns.DecorPlace_Error("Point at a decor to place another of it.")
		return
	end
	ns.DecorateClip_Place(info.decorID, { dyeSlots = info.dyeSlots, turns = TurnsOf(info.decorGUID) })
	NoteUnknown(info.decorGUID)
end

-- Adds a decor to the top of the clipboard (from the panel's other tabs).
function ns.DecorateClip_Add(decorID)
	ns.DecorTools_ClipAdd(db.clipboard, decorID, false, CLIP_MAX)
	Changed()
end

function ns.DecorateClip_Remove(decorID)
	ns.DecorTools_ClipRemove(db.clipboard, decorID)
	Changed()
end

function ns.DecorateClip_Clear()
	wipe(db.clipboard)
	Changed()
end

-- items: { { id, count } } from a share string, first on top. replace: empty the clipboard first. The count becomes
-- the number to place.
function ns.DecorateClip_Import(items, replace)
	if replace then
		wipe(db.clipboard)
	end
	for i = #items, 1, -1 do
		local entry = ns.DecorTools_ClipAdd(db.clipboard, items[i].id, false, CLIP_MAX)
		entry.cut = math.max(entry.cut or 0, items[i].count or 1)
	end
	Changed()
end

-- Placing ------------------------------------------------------------------------------------------------------------

-- The next piece of a Ctrl run: turned like the piece just placed (base steps), plus the "turn each next piece" angle.
local function Again(decorID, base)
	if not (editing and IsControlKeyDown()) then
		return
	end
	local from = runFrom or {}
	local n, sign = ns.DecorTools_RotateSteps(db.turnEach)
	ns.DecorPlace_Start(decorID, { dyeSlots = from.dyeSlots, onStart = function()
		fromClip = from.clip and decorID or nil
		TurnNew(base + n * sign, true)
	end })
end

-- isNew: placed from storage (false: an already placed decor was moved).
events:On(OWNER, "HOUSING_DECOR_PLACE_SUCCESS", function(_, decorGUID, _, isNew, isPreview)
	if not isNew or isPreview then
		return
	end
	local ok, instance = pcall(C_HousingDecor.GetDecorInstanceInfoForGUID, decorGUID)
	local decorID = ok and type(instance) == "table" and instance.decorID or ns.DecorPlace_LastStarted()
	if not decorID then
		return
	end
	local placedTurns = held
	held = 0
	-- The event doesn't always carry the new decor's GUID (seen in game): then its turn can't be remembered.
	if decorGUID and not ns.IsSecret(decorGUID) then
		db.turns[decorGUID] = placedTurns ~= 0 and placedTurns or nil
	end
	ns.DecorTools_RecentPush(db.recent, decorID, RECENT_MAX)
	if fromClip == decorID then
		ns.DecorTools_ClipPlaced(db.clipboard, decorID)
	end
	fromClip = nil
	if db.batch and IsControlKeyDown() then
		C_Timer.After(AGAIN_DELAY, function()
			Again(decorID, placedTurns)
		end)
	else
		runFrom = nil
	end
	Changed()
end)

-- Called by Decorate.lua --------------------------------------------------------------------------------------------

function ns.DecorateClip_Init(saved)
	db = saved
end

-- The house editor opened (any mode) or closed.
function ns.DecorateClip_Editing(on)
	editing = on
	if on then
		ns.DecorPlace_TrackPlacing()
		Hook()
		events:TryWatch(OWNER, "HOUSING_DECOR_PLACE_SUCCESS")
		events:TryWatch(OWNER, "HOUSING_DECOR_REMOVED")
		events:TryWatch(OWNER, "HOUSING_DECOR_PRECISION_MANIPULATION_STATUS_CHANGED")
	else
		events:UnwatchAll(OWNER)
		fromClip, runFrom, held = nil, nil, 0
	end
end
