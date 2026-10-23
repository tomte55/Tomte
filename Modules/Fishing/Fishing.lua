local addonName, ns = ...

-- Fishing module: one key (Key Bindings > Tomte > Fishing) to cast and, while the bobber is out, to reel in and loot.
-- Helpers while a cast is out: auto loot, no recast while looting, an optional louder splash, raft and Oversized
-- Bobber toys (one press each), and an optional on-screen button. Pure rules in Data.lua, the CVar backup in
-- Helpers.lua, the key and button in Key.lua, the Underlight Angler fix in Angler.lua. Does nothing until a key is
-- bound or the button is shown (the Angler fix only acts in the artifact window).

local UI = ns.UI
local module, db

local function KeyLine()
	local key = GetBindingKey(ns.FISHING_BINDING)
	return key and ("Key: " .. GetBindingText(key)) or "No key: Key Bindings > Tomte > Fishing"
end

local function YesNo(v)
	return v and UI.Wrap("yes", "success") or UI.Wrap("no", "textMuted")
end

local function Status()
	local s = ns.FishingKey_Status()
	ns.Print(KeyLine() .. (module.active and "" or " (the module is off)"))
	ns.Print(("fishing now: %s, reel override: %s%s, loot window: %s"):format(YesNo(s.fishing),
		YesNo(s.overridden), s.overridden and (" (" .. table.concat(s.overriddenKeys, ", ") .. ")") or "",
		YesNo(s.lootOpen)))
	ns.Print(("soft interact: SoftTargetInteract %s, range %s (hard %s); auto loot %s"):format(
		tostring(C_CVar.GetCVar("SoftTargetInteract")), tostring(C_CVar.GetCVar("SoftTargetInteractRange")),
		tostring(C_CVar.GetCVar("SoftTargetInteractRangeIsHard")), tostring(C_CVar.GetCVar("autoLootDefault"))))
	local helpers = {}
	if db.autoLoot then
		helpers[#helpers + 1] = "auto loot"
	end
	if db.lootProtect then
		helpers[#helpers + 1] = "no recast while looting"
	end
	if db.loud.on then
		helpers[#helpers + 1] = "louder splash"
	end
	if db.dismount then
		helpers[#helpers + 1] = "dismount"
	end
	if db.raft.on then
		helpers[#helpers + 1] = "raft"
	end
	if db.bobber then
		helpers[#helpers + 1] = "Oversized Bobber"
	end
	ns.Print("helpers on: " .. (#helpers > 0 and table.concat(helpers, ", ") or "none"))
	local pending = {}
	for cvar, entry in pairs(ns.FishingHelpers_Backups()) do
		pending[#pending + 1] = ("%s %s -> %s"):format(cvar, tostring(entry.set), tostring(entry.old))
	end
	table.sort(pending)
	ns.Print("pending restore: " .. (#pending > 0 and table.concat(pending, ", ") or "none")
		.. (ns.FishingHelpers_Pending() and " (after combat)" or ""))
end

local function Open()
	ns.Panel_OpenModule("fishing")
end

local function Refresh()
	ns.FishingKey_Refresh()
end

local function Relayout()
	ns.FishingKey_Relayout()
	ns.FishingKey_Refresh()
end

local function Percent(v)
	return ("%d%%"):format(math.floor(v * 100 + 0.5))
end

local function Scale(v)
	return ("%.1f"):format(v)
end

-- Options can't grey a row out: a toy option says in its tooltip whether you own one (updated when the page builds).
local RAFT_TIP = "While you swim, the key uses a fishing raft toy so you can fish from open water, and renews it when less than a minute is left. Out of water nothing changes. One press per toy, then the next press casts."
local BOBBER_TIP = "When the Reusable Oversized Bobber's buff is gone and the toy is off cooldown, the key uses it first (a bigger bobber that's easier to see). One press, then the next press casts."
local raftSpec = { type = "checkbox", key = "raft.on", label = "Use a raft when swimming", onChange = Refresh }
raftSpec.shown = function()
	raftSpec.tooltip = RAFT_TIP .. (#ns.Fishing_OwnedRafts() == 0 and "\n\nYou don't own a fishing raft." or "")
	return true
end
local bobberSpec = { type = "checkbox", key = "bobber", label = "Keep the Oversized Bobber up", onChange = Refresh }
bobberSpec.shown = function()
	bobberSpec.tooltip = BOBBER_TIP .. (ns.Fishing_OwnsBobber() and "" or "\n\nYou don't own the Reusable Oversized Bobber.")
	return true
end

-- Angleur's override wins on its own key: say so once per session when both are on and a Tomte key is bound.
local events = ns.Fishing_Events
events:Watch("notice", "PLAYER_ENTERING_WORLD")
events:On("notice", "PLAYER_ENTERING_WORLD", function()
	events:Unwatch("notice", "PLAYER_ENTERING_WORLD")
	if module.active and C_AddOns.IsAddOnLoaded("Angleur") and GetBindingKey(ns.FISHING_BINDING) then
		ns.Print("Angleur is on too. Disable it so your Fishing key works.")
	end
end)

module = ns.RegisterModule({
	key = "fishing",
	name = "Fishing",
	category = "professions",
	icon = 136245, -- trade_fishing
	summary = "Fish with one key: press to cast, press again to reel in and loot.",
	description = "One key for fishing (Key Bindings > Tomte > Fishing): press it to cast, press it again when the bobber splashes to reel in and loot. Auto loot while fishing, no recast while looting, and optional louder splash, raft, Oversized Bobber and an on-screen button.",
	enabledByDefault = true,
	defaults = {
		autoLoot = true,
		loud = { on = false, sfx = 1.0, background = false },
		lootProtect = true,
		dismount = false,
		raft = { on = false, pick = 0 }, -- pick: 0 = a random owned raft, else the toy's item ID
		bobber = false, -- Reusable Oversized Bobber
		button = { shown = false, frame = { point = "CENTER", relPoint = "CENTER", x = 0, y = -180 }, scale = 1 },
		restore = {}, -- [cvar] = { old, set }: the CVar backup while a cast is out (a collection: Reset keeps it)
		angler = true, -- show the Underlight Angler's traits in the artifact window (Angler.lua)
	},
	conflicts = {
		{ addon = "Angleur", why = "both bind a fishing key, and Angleur's override wins on its own key. Turn one off." },
	},
	replaces = {
		{ addon = "Plumber", why = "the fix for the Underlight Angler's missing traits" },
	},
	init = function(moduleDB)
		db = moduleDB
		ns.FishingHelpers_Init(db)
		ns.FishingKey_Init(db, module)
		ns.FishingAngler_Init(db)
	end,
	toggle = function(active)
		ns.FishingKey_Toggle(active)
		ns.FishingAngler_Toggle(active)
	end,
	commands = {
		{ "", "open the Fishing options", Open, hidden = true, whileOff = true },
		{ "options", "open the Fishing options", Open, whileOff = true },
		{ "status", "key, soft interact, helpers and pending restores", Status, whileOff = true },
	},
	options = {
		{ type = "header", label = "Key" },
		{ type = "button", label = KeyLine, text = "Status", onClick = Status,
			tooltip = "Bind the key in WoW's Key Bindings > Tomte > Fishing (cast / reel in). Press it to cast, and again when the bobber splashes to reel in and loot. Status prints the key, soft interact and what's waiting to be put back." },
		{ type = "checkbox", key = "autoLoot", label = "Auto loot while fishing",
			tooltip = "Turns auto loot on while the bobber is out, so the catch goes straight to your bags, and back to how it was after." },
		{ type = "checkbox", key = "lootProtect", label = "No recast while looting",
			tooltip = "While the loot window is open (3 seconds at most), the key does nothing, so a double press or lag can't recast and lose the loot." },
		{ type = "checkbox", key = "dismount", label = "Dismount with the key (never while flying)",
			tooltip = "Off: the key does nothing while you're mounted. On: on the ground it dismounts you and casts." },

		{ type = "header", label = "Louder splash" },
		{ type = "checkbox", key = "loud.on", label = "Louder splash",
			tooltip = "While the bobber is out: music and ambience off, sound effects at the volume below, so the splash is easy to hear. Put back after." },
		{ type = "slider", key = "loud.sfx", label = "Effects volume", min = 0.2, max = 1, step = 0.1, format = Percent,
			parent = "loud.on" },
		{ type = "checkbox", key = "loud.background", label = "Also when WoW is in the background", parent = "loud.on",
			tooltip = "Keeps the game's sound on while you're in another window, during a cast only." },

		{ type = "header", label = "Toys" },
		raftSpec,
		{ type = "dropdown", key = "raft.pick", label = "Raft", choices = function()
			return ns.Fishing_RaftChoices()
		end, onChange = Refresh, parent = "raft.on" },
		bobberSpec,

		{ type = "header", label = "Fishing button" },
		{ type = "checkbox", key = "button.shown", label = "Show the fishing button", onChange = Refresh,
			tooltip = "An icon with what the next press does. A click casts like the key, but reeling in needs the key (or a click on the bobber). Blizzard's Edit Mode moves it." },
		{ type = "slider", key = "button.scale", label = "Size", min = 0.6, max = 1.6, step = 0.1, format = Scale,
			onChange = Relayout, parent = "button.shown" },
		{ type = "button", label = "Position", text = "Reset", parent = "button.shown", onClick = function()
			ns.FishingKey_ResetPosition()
		end, tooltip = "Move the button back to below the middle of the screen." },

		{ type = "header", label = "Underlight Angler" },
		{ type = "checkbox", key = "angler", label = "Show the Underlight Angler's traits", onChange = function()
			ns.FishingAngler_Apply()
		end, tooltip = "The game opens the Underlight Angler's artifact window without its traits. This shows them again, so you can see and pick them." },
	},
})
