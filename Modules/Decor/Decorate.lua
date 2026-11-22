local addonName, ns = ...

-- Decorating tools: keys and helpers for Blizzard's house editor. Copy, cut, paste and place another (Clipboard.lua),
-- a quickbar (Quickbar.lua), the Decorating panel with the clipboard, recent and saved decor and export/import
-- (Dock.lua), Expert mode resets, axis keys, turn buttons and gizmo size (Expert.lua), locked decor and hover hints
-- (Lock.lua), a search on the placed-decor list (PlacedSearch.lua), favorites, tags and Destroy a number in the
-- storage list's menu (CatalogMenu.lua) and the keys themselves (Keys.lua). Placing goes through Place.lua, shared with
-- the Decor module; rules in ToolsData.lua. Everything waits for the editor to open and stops when it closes.

local ICON = 134520 -- inv_misc_wrench_01
local PULSES = { 5, 15, 45, 90 } -- the turn buttons' choices, degrees

local OWNER = "decorate"
local events = ns.Decorate_Events

local module, db

local function SetEditing(mode)
	local none = ns.DecorPlace_Mode("None")
	local on = mode ~= none
	ns.DecorateClip_Editing(on)
	ns.DecorateBar_Editing(on, mode)
	ns.DecorateDock_Editing(on)
	ns.DecorateExpert_Editing(on, mode)
	ns.DecorateLock_Editing(on, mode)
	ns.DecoratePlaced_Editing(on and mode == ns.DecorPlace_Mode("ExpertDecor"))
	ns.DecorateKeys_Editing(on, mode)
end

-- The real state, a frame later: the mode-change event can be missed or come out of order around loading screens.
local function Reconcile()
	C_Timer.After(0, function()
		if module.active then
			SetEditing(ns.DecorPlace_EditorMode())
		end
	end)
end

events:On(OWNER, "HOUSE_EDITOR_MODE_CHANGED", Reconcile)
events:On(OWNER, "PLAYER_ENTERING_WORLD", Reconcile)
events:On(OWNER, "PLAYER_LEAVING_WORLD", function()
	SetEditing(ns.DecorPlace_Mode("None"))
end)

local function Start()
	if not events:TryWatch(OWNER, "HOUSE_EDITOR_MODE_CHANGED") then
		return -- a client without the house editor
	end
	events:Watch(OWNER, "PLAYER_ENTERING_WORLD")
	events:Watch(OWNER, "PLAYER_LEAVING_WORLD")
	ns.DecorateBar_Start()
	ns.DecorateDock_Start()
	ns.DecorateExpert_Start()
	ns.DecorateLock_Start()
	ns.DecoratePlaced_Start()
	ns.DecorateMenu_Start()
	ns.DecorateKeys_Start()
	Reconcile()
end

local function Stop()
	events:UnwatchAll(OWNER)
	SetEditing(ns.DecorPlace_Mode("None"))
	ns.DecorateBar_Stop()
	ns.DecorateDock_Stop()
	ns.DecorateExpert_Stop()
	ns.DecorateLock_Stop()
	ns.DecoratePlaced_Stop()
	ns.DecorateMenu_Stop()
	ns.DecorateKeys_Stop()
end

-- Settings ------------------------------------------------------------------------------------------------------------

local labels = {} -- [action] = its key row's label

-- One key per action: a key set on one action comes off any other that had it (only one binding would work).
local function KeyRow(key, label, tooltip)
	labels[key] = label
	return { type = "key", key = "keys." .. key, label = label, tooltip = tooltip, onChange = function(value)
		if value ~= "" then
			for other, bound in pairs(db.keys) do
				if other ~= key and bound == value then
					db.keys[other] = ""
					ns.Print(("%s was on %s; now it's on %s only."):format(ns.KeyText(value), labels[other] or other,
						label))
					C_Timer.After(0, ns.Panel_Refresh) -- the other row shows "Not set" (after this row is done)
				end
			end
		end
		ns.DecorateKeys_Apply()
		ns.DecorateBar_Refresh()
	end }
end

local function PulseChoices()
	local out = {}
	for i, degrees in ipairs(PULSES) do
		out[i] = { value = degrees, text = ("%d°"):format(degrees) }
	end
	return out
end

local function Percent(value)
	return ("%d%%"):format(math.floor(value * 100 + 0.5))
end

local options = {
	{ type = "header", label = "Panel and quickbar" },
	{ type = "checkbox", key = "bar", label = "Quickbar",
		tooltip = "Eight slots for decor you place often, plus the last one you placed, left of the editor's mode bar. Click a slot or press its key to pick the decor up; press an empty slot's key while holding a decor to put it there.",
		onChange = function()
			ns.DecorateBar_Apply()
		end },
	{ type = "checkbox", key = "dock.shown", label = "Decorating panel",
		tooltip = "A panel in the editor with your clipboard, recent placements and saved decor (favorites and tags), plus export and import. The wrench on the quickbar opens and closes it too.",
		onChange = function()
			ns.DecorateDock_Apply()
		end },
	{ type = "checkbox", key = "hints", label = "Key hints on hover",
		tooltip = "The hovered decor's tooltip lists the keys for place another, copy, cut and lock." },
	{ type = "header", label = "Placing" },
	{ type = "checkbox", key = "batch", label = "Hold Ctrl to keep placing",
		tooltip = "Place a decor with Ctrl held and you pick up another of the same right away, until you let go of Ctrl." },
	{ type = "slider", key = "turnEach", parent = "batch", label = "Turn each next piece by", min = 0, max = 180,
		step = 15, format = function(value)
			return value == 0 and "Off" or ("%d°"):format(value)
		end,
		tooltip = "While you keep placing with Ctrl, each new piece is turned like the one before plus this much: a ring of chairs, a fan of books." },
	{ type = "header", label = "Expert mode" },
	{ type = "checkbox", key = "rotateButtons", label = "Turn buttons",
		tooltip = "Two buttons above the submode bar while you rotate a decor, each turning it by a set amount around the gizmo's axis.",
		onChange = function()
			ns.DecorateExpert_Apply()
		end },
	{ type = "dropdown", key = "pulse", label = "Turn buttons turn by", parent = "rotateButtons", choices = PulseChoices,
		onChange = function()
			ns.DecorateExpert_Apply()
		end },
	{ type = "slider", key = "gizmoMove", label = "Move arrows size", min = 0.5, max = 3, step = 0.25, format = Percent,
		tooltip = "Makes the gizmo's move arrows bigger or smaller. 100% is the game's size.",
		onChange = function()
			ns.DecorateExpert_GizmoChanged()
		end },
	{ type = "slider", key = "gizmoTurn", label = "Turn rings size", min = 0.5, max = 3, step = 0.25, format = Percent,
		tooltip = "Makes the gizmo's turn rings bigger or smaller. 100% is the game's size.",
		onChange = function()
			ns.DecorateExpert_GizmoChanged()
		end },
	{ type = "checkbox", key = "placedSearch", label = "Search the placed decor list",
		tooltip = "A search box over Blizzard's placed decor list: decor whose name doesn't match fades out.",
		onChange = function()
			ns.DecoratePlaced_Apply()
		end },
	{ type = "header", label = "Keys (only in the house editor)" },
	KeyRow("duplicate", "Place another", "Picks up another of the decor under the mouse (or the selected one) from storage."),
	KeyRow("copy", "Copy", "Puts the decor under the mouse (or the selected one) on the clipboard."),
	KeyRow("cut", "Cut", "Puts the selected decor back in storage and on the clipboard, to place again later."),
	KeyRow("paste", "Paste", "Picks up the decor at the top of the clipboard."),
	KeyRow("rotate", "Turn 90°", "Turns the decor you hold or selected by 90 degrees (Basic mode)."),
	KeyRow("rotateBack", "Turn 90° the other way", "Basic mode."),
	KeyRow("reset", "Reset this transform", "Expert mode: puts the selected decor's move, turn or size (the open one) back."),
	KeyRow("resetAll", "Reset all transforms", "Expert mode: puts the selected decor's move, turn and size back."),
	KeyRow("axisX", "Turn around X", "Expert mode: picks the X axis for turning."),
	KeyRow("axisY", "Turn around Y", "Expert mode: picks the Y axis for turning."),
	KeyRow("axisZ", "Turn around Z", "Expert mode: picks the Z axis for turning."),
	KeyRow("lock", "Lock or unlock", "Locks the decor under the mouse so it can't be picked up by mistake, or unlocks it."),
}
for slot = 1, 8 do
	options[#options + 1] = KeyRow("slot" .. slot, ("Quickbar slot %d"):format(slot))
end

-- Commands ------------------------------------------------------------------------------------------------------------

local function PrintKeys()
	ns.Print("decorating keys (in the house editor):")
	for _, row in ipairs(options) do
		if row.type == "key" then
			local key = db.keys[row.key:match("^keys%.(.+)$")]
			print(("  %s: %s"):format(row.label, key ~= "" and ns.KeyText(key) or "not set"))
		end
	end
end

local function UnlockAll()
	local n = 0
	for guid in pairs(db.locked) do
		db.locked[guid] = nil
		n = n + 1
	end
	ns.Print(("unlocked %d decor."):format(n))
end

module = ns.RegisterModule({
	key = "decorate",
	name = "Decorating tools",
	category = "collections",
	icon = ICON,
	summary = "Copy, cut, paste, a quickbar and precision keys for Blizzard's house editor.",
	description = "Keys and helpers in the house editor. Copy, cut and paste decor, place another of the one under the mouse, and keep a clipboard of decor to place later. A quickbar of eight decor you use often plus the last one placed, and a Decorating panel with your clipboard, recent placements and saved decor (favorites and tags from the right-click menu of Blizzard's storage list). Hold Ctrl to keep placing the same decor, each next piece turned a bit more. Turn 90 degrees with a key in Basic mode; in Expert mode, reset keys, axis keys, turn buttons and a bigger gizmo. Lock decor so it can't be picked up by mistake, search Blizzard's placed decor list, share decor lists as text, and destroy a number of a decor from storage. Off by default: in the editor it takes over keys like Q, E, L and F1-F8.",
	enabledByDefault = false,
	defaults = {
		-- Binding strings ("CTRL-C"), "" for no key; ADT's keys, so they're where its players expect them.
		keys = {
			duplicate = "CTRL-D", copy = "CTRL-C", cut = "CTRL-X", paste = "CTRL-V", rotate = "Q", rotateBack = "E",
			reset = "T", resetAll = "CTRL-T", axisX = "", axisY = "", axisZ = "", lock = "L",
			slot1 = "F1", slot2 = "F2", slot3 = "F3", slot4 = "F4", slot5 = "F5", slot6 = "F6", slot7 = "F7", slot8 = "F8",
		},
		clipboard = {}, -- { { id = decor ID, cut = how many are still to place } }, newest first
		recent = {}, -- decor IDs placed last, newest first
		slots = {}, -- [quickbar slot 1-8] = decor ID
		locked = {}, -- [decor GUID] = { id = decor ID, at = time() }
		-- [decor GUID] = Basic-mode turn steps Tomte saw it get (copies get the same), false: turned in Expert mode
		turns = {},
		favorites = {}, -- [decor ID] = true
		tags = {}, -- [tag name] = { [decor ID] = true }
		bar = true,
		-- The Decorating panel: shown, the open tab, and x, y (from the editor's bottom left) once it was dragged
		dock = { shown = true, tab = "clipboard" },
		hints = true,
		batch = false,
		turnEach = 0, -- degrees each next Ctrl-placed piece turns more, 0 = off
		rotateButtons = true,
		pulse = 45, -- degrees a turn button turns
		gizmoMove = 1, -- gizmo size, 1 = the game's
		gizmoTurn = 1,
		placedSearch = true,
	},
	noShare = { "clipboard", "recent", "locked", "turns", "dock" },
	replaces = {
		{ addon = "AdvancedDecorationTools", why = "copy, cut, paste, duplicate, the quickbar, rotation and reset keys, "
			.. "locks, favorites and tags, placed decor search, export and import" },
	},
	init = function(saved)
		db = saved
		ns.DecorateClip_Init(db)
		ns.DecorateBar_Init(db)
		ns.DecorateDock_Init(db)
		ns.DecorateExpert_Init(db)
		ns.DecorateLock_Init(db)
		ns.DecoratePlaced_Init(db)
		ns.DecorateMenu_Init(db)
		ns.DecorateKeys_Init(db)
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "panel", "open or close the Decorating panel (in the house editor)", function()
			ns.DecorateDock_Toggle()
		end },
		{ "keys", "list the decorating keys", PrintKeys },
		{ "unlock", "unlock every locked decor", UnlockAll },
	},
	options = options,
})
