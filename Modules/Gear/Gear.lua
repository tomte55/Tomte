local addonName, ns = ...

-- Gear Check: an upgrade verdict on item tooltips (and Baganator's upgrade arrows) that only says "upgrade" when
-- nothing it can't value is at stake: set bonuses, embellishments, effects and unique limits are checked, and
-- items whose value is an effect are sent to a sim instead of guessed. This file holds the module: its events,
-- the verdict API for other files, the commands, the options and the start/stop. The rest is in Modules/Gear:
-- evaluator contexts (Context.lua), tooltip lines (Tooltip.lua), chat hints (Hints.lua), Baganator arrows
-- (Baganator.lua), stat weights import and printouts (Weights.lua), rules in Rules.lua, advice (weights source,
-- gems, enchants, off-spec) in Advice.lua, built-in weights and gem IDs per expansion in Data/<Expansion>/Gear.lua
-- (picked by the character's content expansion, Scales.lua), item reading in Items.lua, the character sheet button
-- and panel in Sheet.lua, upgrades for other characters in Alts.lua, the new-upgrade reveal and equip toast in
-- Reveal.lua.
-- Weights: imported Pawn string per character and spec > built-in for the spec > primary 1 / secondaries 0.5.

local Context = ns.Gear_OwnContext
local Evaluate = ns.Gear_EvaluateLink
local InvalidateVerdicts = ns.Gear_InvalidateVerdicts
local OnItem = ns.GearTooltip_OnItem
local WeightsHint = ns.GearHints_Weights
local AuditHint = ns.GearHints_Audit
local RegisterBaganator = ns.GearBaganator_Register
local PrintWeights = ns.GearWeights_Print
local SourceLabel = ns.GearWeights_SourceLabel
local NextSim = ns.GearWeights_NextSim
local PrintSpecs = ns.GearWeights_PrintSpecs
local OpenImport = ns.Gear_OpenImport
local ClearWeights = ns.Gear_ClearWeights
local PrintSimSteps = ns.Gear_PrintSimSteps

local module, db
local events = ns.NewEvents() -- shared with Reveal.lua (owners "gear", "reveal")
ns.Gear_Events = events

-- For other files (World quests, the character sheet panel): the context to judge many items with (nil while Gear
-- Check is off or there's no spec), and verdict, headline, color key for an item link. Gear_Verdict is nil while
-- Gear Check is off, items load, there's no spec, or the item is worn. Pass one Gear_Context() when judging a batch.
function ns.Gear_Context()
	if not (module and module.active) then
		return nil
	end
	return Context()
end

function ns.Gear_Verdict(link, ctx)
	if not (module and module.active) then
		return nil
	end
	local v = Evaluate(link, ctx)
	if not v then
		return nil
	end
	return v, ns.Gear_Headline(v)
end

---------------------------------------------------------------------------------------------------------------
-- Events

local function RereadWorn()
	ns.GearItems_InvalidateEquipped()
	InvalidateVerdicts()
	ns.GearSheet_Refresh()
end

events:On("gear", "PLAYER_EQUIPMENT_CHANGED", function()
	RereadWorn()
end)

-- Enchanting, socketing or upgrading worn gear changes its link: read the worn gear again, once per burst (the
-- event also fires for new bag items).
local inventoryQueued
local wornLinks = {}

local function WornChanged()
	local changed = false
	for slot = 1, 19 do
		local link = GetInventoryItemLink("player", slot) or false
		if wornLinks[slot] ~= link then
			wornLinks[slot], changed = link, true
		end
	end
	return changed
end

events:On("gear", "UNIT_INVENTORY_CHANGED", function()
	if inventoryQueued then
		return
	end
	inventoryQueued = true
	C_Timer.After(0.5, function()
		inventoryQueued = false
		if module.active and WornChanged() then
			RereadWorn()
		end
	end)
end)

-- Modules start on ADDON_LOADED, before the inventory has arrived: read worn gear and bags again once in the world.
events:On("gear", "PLAYER_ENTERING_WORLD", function()
	ns.GearItems_InvalidateEquipped()
	ns.GearItems_InvalidateBags()
	InvalidateVerdicts()
	ns.GearSheet_Refresh()
end)

events:On("gear", "PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
	if unit == "player" then
		InvalidateVerdicts()
		WeightsHint()
		ns.GearSheet_Refresh()
	end
end)

events:On("gear", "BAG_UPDATE_DELAYED", function()
	ns.GearItems_InvalidateBags()
end)

events:On("gear", "PLAYER_LEVEL_UP", function(_, level)
	ns.GearItems_ClearCache()
	InvalidateVerdicts()
	ns.GearSheet_Refresh()
	WeightsHint(level)
	-- UnitLevel (and so the red "Requires Level" lines) can lag behind the event: read everything again once it's
	-- caught up.
	C_Timer.After(2, function()
		if module.active then
			ns.GearItems_ClearCache()
			InvalidateVerdicts()
			ns.GearSheet_Refresh()
		end
	end)
end)

events:On("gear", "GET_ITEM_INFO_RECEIVED", function()
	ns.GearItems_InfoReceived()
end)

-- Called by Items.lua once requested item data has arrived.
ns.GearItems_OnReady = function()
	if module.active then
		InvalidateVerdicts()
		ns.GearSheet_Refresh()
		if ns.AltsSend_OnGearReady then
			ns.AltsSend_OnGearReady() -- the mailbox's "Gear for" groups
		end
	end
end

---------------------------------------------------------------------------------------------------------------

local function Command(fn)
	return function()
		if not module.active then
			ns.Print("Gear Check is off.")
			return
		end
		fn()
	end
end

local function Start()
	events:Watch("gear", "PLAYER_ENTERING_WORLD")
	events:Watch("gear", "PLAYER_EQUIPMENT_CHANGED")
	events:Watch("gear", "PLAYER_SPECIALIZATION_CHANGED")
	events:Watch("gear", "PLAYER_LEVEL_UP")
	events:Watch("gear", "GET_ITEM_INFO_RECEIVED")
	events:Watch("gear", "BAG_UPDATE_DELAYED")
	events:Watch("gear", "UNIT_INVENTORY_CHANGED", "player")
	ns.GearItems_InvalidateBags()
	if not module.tooltipHooked then
		module.tooltipHooked = true -- post-calls can't be removed; OnItem checks module.active
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	end
	RegisterBaganator()
	if not module.paneHooked then
		module.paneHooked = true -- like the tooltip hook: AuditHint checks module.active
		EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
			CharacterFrame:HookScript("OnShow", AuditHint)
		end)
	end
	ns.GearItems_InvalidateEquipped()
	InvalidateVerdicts()
	ns.GearSheet_Init()
	ns.GearSlotLevels_Init()
	ns.GearReveal_Start(db)
	C_Timer.After(ns.inWorld and 0 or 8, WeightsHint) -- at login, after the chat flood
end

local function Stop()
	events:UnwatchAll("gear")
	ns.GearReveal_Stop()
	ns.GearWeights_HideDialog()
	InvalidateVerdicts()
	ns.GearSheet_Refresh()
	ns.GearSlotLevels_Refresh()
end

module = ns.RegisterModule({
	key = "gear",
	uses = {
		{ addon = "Baganator", why = "upgrade arrows on your bag items", without = "no upgrade arrows in bags" },
		{ addon = "Simulationcraft", why = "the /simc export for Raidbots Top Gear", without = "no /simc export" },
	},
	replaces = { { addon = "Pawn", why = "upgrade verdicts on item tooltips" } },
	home = {
		{ kind = "quick", key = "reveal", order = 3, name = "Reveal upgrades", open = function()
			ns.GearReveal_ShowBags()
		end },
		{ kind = "next", key = "nextsim", name = "Sim on Raidbots", score = 30,
			description = "This character is max level and uses built-in stat weights: a Raidbots sim fits its gear "
				.. "better.",
			candidates = NextSim },
	},
	name = "Gear Check",
	category = "gear",
	icon = 133071, -- inv_helmet_03
	summary = "Item tooltips say whether gear is an upgrade for you, and why not.",
	description = "Says on each item's tooltip whether it's an upgrade, and why not when it isn't: wrong armor or "
		.. "main stat, breaks your tier set, loses an embellishment or effect, unique limits. Trinkets and items "
		.. "with effects are marked to sim instead of guessed; while leveling, higher item level wins. Also: upgrades for your other specs, the best gem "
		.. "for empty sockets, missing enchants, and item levels on the character sheet and Inspect slots. Can mark upgrades in Baganator and reveal new upgrades as a moment "
		.. "with a click-to-equip toast. Warbound and Bind on Equip gear also says which of your other characters "
		.. "it's an upgrade for.",
	enabledByDefault = true,
	defaults = {
		showReasons = true,
		showDowngrades = true,
		levelingIlvl = true,
		compareTooltips = false,
		baganator = true,
		maybeBaganator = true,
		offspec = true,
		rank = true,
		gemHints = true,
		enchantHints = true,
		weights = {}, -- [playerGUID][specID] = { name, weights = { AGI = 1, ... } }
		-- [playerGUID][specID] = which built-in weights hint was shown ("max" or "stale:<season>"). Saved data
		-- from older versions may hold "builtin" values and account-wide [specID] keys; CharHinted moves those.
		hinted = {},
		sheetButton = true,
		sheetOpen = false, -- the panel next to the character sheet
		slotLevels = true,
		reveal = true,
		revealToast = true,
		equipSound = true,
		revealMinPct = 2,
		altUpgrades = "all", -- all | max | off: other characters judged on tooltips, Baganator and the mailbox
		altBaganator = true,
		altMail = true,
	},
	noShare = { "sheetOpen" }, -- not in settings strings (Core/Profile.lua)
	init = function(moduleDB)
		db = moduleDB
		ns.gearDB = moduleDB
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "sim", "how to check an item with Raidbots Top Gear", PrintSimSteps },
		{ "import", "paste Raidbots stat weights for your current spec", Command(OpenImport) },
		{ "weights", "show the stat weights in use and where they come from", Command(PrintWeights) },
		{ "clear", "remove the imported weights for your current spec", Command(ClearWeights) },
		{ "upgrades", "reveal the clean upgrades already in your bags", function()
			ns.GearReveal_ShowBags()
		end },
		{ "specs", "every spec's ID and main stat against the built-in weights", PrintSpecs, hidden = true },
	},
	options = {
		{ type = "header", label = "Tooltip" },
		{ type = "checkbox", key = "showReasons", label = "Show reasons",
			tooltip = "Up to three short lines under the verdict, e.g. \"Breaks your 4-set\"." },
		{ type = "checkbox", key = "showDowngrades", label = "Show downgrades" },
		{ type = "checkbox", key = "levelingIlvl", label = "While leveling, higher item level wins",
			onChange = function()
				ns.GearAlts_Invalidate()
				InvalidateVerdicts()
			end,
			tooltip = "Below max level, gear with a higher item level is an upgrade whatever its stats, trinkets and "
				.. "items with effects too. Wrong armor, main stat or unique limits still say no." },
		{ type = "checkbox", key = "compareTooltips", label = "Also on comparison tooltips",
			tooltip = "The tooltips of your equipped items that appear next to the hovered one." },
		{ type = "checkbox", key = "offspec", label = "Upgrades for your other specs",
			tooltip = "\"Also an upgrade for Marksmanship +4%\" when an item is a clean upgrade for another spec "
				.. "with weights (imported or built-in)." },
		{ type = "checkbox", key = "rank", label = "Rank on worn items",
			tooltip = "On items you wear: \"your best\" or \"your second best\" (rings) against your bags, per spec "
				.. "with weights, or \"bag has better\". Stats only, so trinkets and items with effects aren't ranked." },
		{ type = "checkbox", key = "gemHints", label = "Gem advice",
			tooltip = "The best gem for empty sockets under your weights, and a hint on your worn items when a "
				.. "socketed gem is clearly worse." },
		{ type = "checkbox", key = "enchantHints", label = "Missing enchants",
			tooltip = "\"Not enchanted\" on worn items that take an enchant, and a chat line when you open the "
				.. "character pane and something is missing." },
		{ type = "checkbox", key = "sheetButton", label = "Button on the character sheet", onChange = function()
			ns.GearSheet_Refresh()
		end, tooltip = "A Gear button under the trinkets that opens a panel with your stat weights, best gem and "
			.. "missing enchants and sockets." },
		{ type = "checkbox", key = "slotLevels", label = "Item level on gear slots", onChange = function()
			ns.GearSlotLevels_Refresh()
		end, tooltip = "Each item's level in the top-left corner of its slot on the character sheet and the Inspect "
			.. "window, in the item's quality color." },
		{ type = "header", label = "Bags" },
		{ type = "checkbox", key = "baganator", label = "Mark upgrades in Baganator", onChange = InvalidateVerdicts,
			tooltip = "Only clean upgrades get the arrow. In Baganator's settings (Icons), \"Tomte Gear Check\" is a "
				.. "corner icon (the arrow) and an upgrade source (the upgrade search and category)." },
		{ type = "checkbox", key = "maybeBaganator", label = "Mark maybe-upgrades in Baganator",
			onChange = InvalidateVerdicts,
			tooltip = "An arrow in the theme's warning color on gear whose stats say upgrade but that needs checking: a trinket or effect to "
				.. "sim, same item level with different stats, or a warning like breaking your set. Not in the upgrade "
				.. "search. In Baganator's settings (Icons) it's \"Tomte Gear Check: maybe an upgrade\"." },
		{ type = "header", label = "Upgrades for alts" },
		{ type = "dropdown", key = "altUpgrades", label = "Upgrades for alts", onChange = function()
			ns.GearAlts_Invalidate()
			InvalidateVerdicts()
		end, choices = function()
			return { { value = "all", text = "All characters" }, { value = "max", text = "Max level only" },
				{ value = "off", text = "Off" } }
		end, tooltip = "\"Upgrade for Mira (Holy): +8.2%\" on gear that can get to another character (warbound, or Bind "
			.. "on Equip and not bound yet), judged with what they wore, their spec, level and stat weights when you "
			.. "last played them. Only clean upgrades. Characters not played for 60 days are left out. Needs Alts." },
		{ type = "checkbox", key = "altBaganator", label = "Mark alt upgrades in Baganator",
			onChange = InvalidateVerdicts,
			tooltip = "An arrow in the theme's accent color (like Tomte's map markers) on gear that's an upgrade for "
				.. "another character and not for you (your own upgrades keep the green arrow). In Baganator's settings (Icons) it's \"Tomte Gear Check: upgrade for an "
				.. "alt\"." },
		{ type = "checkbox", key = "altMail", label = "Gear for alts at the mailbox",
			tooltip = "In Send to alt's \"For your alts\" panel: a \"Gear for Mira\" group with the Bind on Equip "
				.. "upgrades for them. Warbound ones go through the Warband bank instead: \"Deposit for alts\" at the "
				.. "bank puts them there. Needs Alts' \"For your alts\" at the mailbox." },
		{ type = "header", label = "Upgrade reveal" },
		{ type = "checkbox", key = "reveal", label = "Reveal new upgrades",
			tooltip = "When gear that's new to your bags (loot, quest rewards, the vault, mail) is a clean upgrade, show "
				.. "it as a moment. Choose banner or cinematic under Moments > Gear upgrade. Items taken out of a bank "
				.. "don't count." },
		{ type = "slider", key = "revealMinPct", label = "Smallest upgrade", min = 0, max = 10, step = 0.5,
			parent = "reveal", format = function(value)
				return ("%g%%"):format(value)
			end,
			tooltip = "Upgrades below this are left alone (gear for an empty slot always counts)." },
		{ type = "checkbox", key = "revealToast", label = "Equip toast", parent = "reveal",
			tooltip = "A toast with the upgrade: click it to equip the item, right-click to dismiss. Not in combat." },
		{ type = "checkbox", key = "equipSound", label = "Sound when equipped", parent = "revealToast",
			tooltip = "Play the item upgrade sound with the \"Equipped\" toast once the upgrade from the toast is worn." },
		{ type = "header", label = "Stat weights" },
		{ type = "button", label = SourceLabel, text = "Show", onClick = Command(PrintWeights),
			tooltip = "Imported weights win, then the built-in ones (every spec: sims for damage and tanks, guide "
				.. "priority for healers), else main stat 1.0 and secondaries 0.5. Show prints them in chat." },
		{ type = "button", label = "Import for your current spec", text = "Import", onClick = Command(OpenImport),
			tooltip = "Raidbots stat weights fit your character better than the built-in ones." },
		{ type = "button", label = "Remove for your current spec", text = "Remove", onClick = Command(ClearWeights),
			confirm = "Remove the imported stat weights for your current spec?" },
		{ type = "button", label = "How to sim an item", text = "Show", onClick = PrintSimSteps,
			tooltip = "Prints the Raidbots Top Gear steps in chat." },
	},
})
ns.gearModule = module
