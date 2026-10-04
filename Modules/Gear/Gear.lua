local addonName, ns = ...

-- Gear Check: an upgrade verdict on item tooltips (and Baganator's upgrade arrows) that only says "upgrade" when
-- nothing it can't value is at stake: set bonuses, embellishments, effects and unique limits are checked, and
-- items whose value is an effect are sent to a sim instead of guessed. Rules in Data.lua, advice (weights source,
-- gems, enchants, off-spec) in Advice.lua, built-in weights and gem IDs in Scales.lua, item reading in Items.lua,
-- the character sheet button and panel in Sheet.lua.
-- Weights: imported Pawn string per character and spec > built-in for the spec > primary 1 / secondaries 0.5.

local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local PRIMARY_KEYS = { [1] = "STR", [2] = "AGI", [4] = "INT" } -- LE_UNIT_STAT_*
local COLORS = {
	green = "|cff4fe06a", yellow = "|cffffd24a", grey = "|cffa0a0a0", red = "|cffd9604f", orange = "|cffff9a3c",
}
local LABEL = "|cff66ccffGear:|r "
local REASON = "|cff9d9d9d"
local MAX_REASONS = 3
local BAGANATOR_ID = "tomte_gear"

local module, db
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local _, classToken, classID = UnitClass("player")
local scales = ns.Gear_Scales
local diamondIDs = {}
for _, id in ipairs(scales.diamonds) do
	diamondIDs[id] = true
end

local function SpecAt(index)
	local specID, name, _, _, _, primaryStat = GetSpecializationInfo(index)
	if not specID or specID == 0 then
		return nil
	end
	return { index = index, id = specID, name = name, primary = PRIMARY_KEYS[primaryStat] }
end

local function Spec()
	local index = GetSpecialization()
	return index and SpecAt(index)
end

local function CharWeights()
	local guid = UnitGUID("player")
	db.weights[guid] = db.weights[guid] or {}
	return db.weights[guid]
end

-- Display season ID, nil when the game doesn't say (0 between seasons).
local function CurrentSeason()
	local id = C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID and C_SeasonInfo.GetCurrentDisplaySeasonID()
	return (id and id > 0) and id or nil
end

local function ContextFor(spec)
	if not (spec and spec.id and spec.primary) then
		return nil
	end
	local weights, source, label = ns.Gear_ResolveWeights(CharWeights()[spec.id], scales.specs[spec.id], spec.primary)
	local best, bestValue = ns.Gear_BestGem(ns.GearItems_Gems(scales.gems), weights, spec.primary)
	return {
		spec = spec,
		primary = spec.primary,
		weights = weights,
		source = source,
		label = label,
		noWeights = source == "none",
		armorSubclass = ns.Gear_ArmorForClass(classToken),
		specID = spec.id,
		best = best,
		bestValue = bestValue,
		gemValue = best and bestValue or nil,
	}
end

local function Context()
	return ContextFor(Spec())
end

-- The class's other specs, for off-spec verdicts.
local function OtherSpecs(current)
	local list = {}
	for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
		if i ~= current.index then
			list[#list + 1] = SpecAt(i)
		end
	end
	return list
end

-- verdict (nil when worn), candidate descriptor, equipped snapshot. Nothing while items load.
local function Evaluate(link, ctx)
	ctx = ctx or Context()
	local equipped = ctx and ns.GearItems_Equipped()
	local cand = equipped and ns.GearItems_Describe(link)
	if not cand then
		return nil
	end
	ctx.specOK = cand.specs == nil or cand.specs[ctx.spec.id] == true
	return ns.Gear_Evaluate(cand, equipped, ctx), cand, equipped
end

-- For other modules (World quests): the context to judge many items with (nil while Gear Check is off or there's
-- no spec), and verdict, headline, color key for an item link. Gear_Verdict is nil while Gear Check is off, items
-- load, there's no spec, or the item is worn. Pass one Gear_Context() when judging a batch.
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
-- Tooltip

local function OnItem(tooltip, data)
	if not (module.active and tooltip.AddLine) then
		return
	end
	if (tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2) and not db.compareTooltips then
		return
	end
	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	if not link or (issecretvalue and issecretvalue(link)) then
		return
	end
	local ctx = Context()
	local verdict, cand, equipped = Evaluate(link, ctx)
	if not (cand and ns.Gear_Slots(cand.equipLoc)) then
		return
	end
	local labeled = false
	local function Add(text, color)
		tooltip:AddLine((labeled and "   " or LABEL) .. COLORS[color] .. text .. "|r", nil, nil, nil, true)
		labeled = true
	end

	if verdict and not (verdict.kind == "downgrade" and not db.showDowngrades) then
		local headline, color = ns.Gear_Headline(verdict)
		Add(headline, color)
		if db.showReasons then
			for i = 1, math.min(#verdict.reasons, MAX_REASONS) do
				tooltip:AddLine(REASON .. "   " .. verdict.reasons[i] .. "|r", nil, nil, nil, true)
			end
		end
		if ctx.source == "none" and verdict.kind ~= "notForYou" then
			tooltip:AddLine(REASON .. ("   No weights for %s: item level only. /tomte gear import"):format(
				ctx.spec.name) .. "|r", nil, nil, nil, true)
		end
	end
	if verdict and verdict.kind == "notForYou" then
		return
	end

	local worn = ns.Gear_WornSlot(link, equipped)
	if db.rank and worn and ns.Gear_Rankable(cand) then
		local pair = cand.equipLoc == "INVTYPE_FINGER" and 2 or 1 -- trinkets aren't ranked
		local others = {}
		local partner = pair == 2 and equipped[worn == 11 and 12 or 11]
		if partner then
			others[1] = partner
		end
		local bag = ns.GearItems_BagGear()
		local specs = { ctx.spec }
		for _, other in ipairs(OtherSpecs(ctx.spec)) do
			specs[#specs + 1] = other
		end
		for i, spec in ipairs(specs) do
			local sctx = i == 1 and ctx or ContextFor(spec)
			if sctx and (i == 1 or sctx.source ~= "none") and not ns.Gear_Unusable(cand, sctx) then
				local function Score(d)
					return ns.Gear_Score(d, sctx.weights, sctx.primary, sctx.gemValue)
				end
				local rank, better = ns.Gear_Rank(cand, worn, others, bag, sctx, Score)
				local betterName = better and C_Item.GetItemNameByID(better.itemID)
				local text, color = ns.Gear_RankLine(spec.name, rank, pair, betterName)
				if text then
					Add(text, color)
				end
			end
		end
	end
	if db.offspec and not worn then
		for _, other in ipairs(OtherSpecs(ctx.spec)) do
			local octx = ContextFor(other)
			if octx and octx.source ~= "none" then
				local line = ns.Gear_OffspecLine(other.name, (Evaluate(link, octx)))
				if line then
					Add(line, "green")
				end
			end
		end
	end

	if db.gemHints then
		local diamond = not ns.Gear_WearsGem(equipped, diamondIDs) and scales.diamondName or nil
		local lines = ns.Gear_GemLines(cand, ctx.best, ctx.bestValue, worn ~= nil, ns.GearItems_GemStats,
			ctx.weights, ctx.primary, diamond)
		for _, line in ipairs(lines) do
			Add(line, worn and "orange" or "grey")
		end
	end
	if db.enchantHints and worn and ns.Gear_MissingEnchant(worn, cand) then
		Add("Not enchanted", "orange")
	end
end

---------------------------------------------------------------------------------------------------------------
-- Chat hints: no weights (once per session and spec), built-in weights (once, and again when the season moves
-- past theirs), missing enchants and empty sockets when the character pane opens.

local noWeightsSaid = {}

local function WeightsHint()
	if not module.active then
		return
	end
	local ctx = Context()
	if not ctx then
		return
	end
	local name = ctx.spec.name
	if ctx.source == "none" then
		if not noWeightsSaid[ctx.spec.id] then
			noWeightsSaid[ctx.spec.id] = true
			ns.Print(("Gear Check: no stat weights for %s, so item level decides. For better verdicts, sim stat "
				.. "weights on Raidbots and /tomte gear import."):format(name))
		end
		return
	end
	local kind, seen = ns.Gear_WeightsHint(ctx.source, scales, db.hinted[ctx.spec.id], CurrentSeason())
	if kind == "builtin" then
		ns.Print(("Gear Check: using built-in weights for %s (%s). For weights that fit your gear, sim on "
			.. "Raidbots and /tomte gear import."):format(name, ctx.label))
	elseif kind == "stale" then
		ns.Print(("Gear Check: the built-in weights for %s are from %s and may be out of date. Sim on Raidbots "
			.. "and /tomte gear import."):format(name, scales.seasonName))
	end
	if kind then
		db.hinted[ctx.spec.id] = seen
	end
end

local lastAudit

local function AuditHint()
	if not (module.active and db.enchantHints) then
		return
	end
	local equipped = ns.GearItems_Equipped()
	if not equipped then
		return
	end
	local text = ns.Gear_AuditText(ns.Gear_Audit(equipped))
	if text and text ~= lastAudit then
		ns.Print("Gear Check: " .. text .. ". Hover the item for details.")
	end
	lastAudit = text
end

---------------------------------------------------------------------------------------------------------------
-- Baganator

local function RefreshBags()
	if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh()
	end
end

local function RegisterBaganator()
	if module.baganatorRegistered or not (Baganator and Baganator.API and Baganator.API.RegisterUpgradePlugin) then
		return
	end
	module.baganatorRegistered = true
	Baganator.API.RegisterUpgradePlugin("Tomte Gear Check", BAGANATOR_ID, function(link)
		if not (module.active and db.baganator) then
			return false
		end
		return ns.Gear_IsCleanUpgrade(Evaluate(link))
	end)
end

---------------------------------------------------------------------------------------------------------------
-- Events

function events:PLAYER_EQUIPMENT_CHANGED()
	ns.GearItems_InvalidateEquipped()
	RefreshBags()
	ns.GearSheet_Refresh()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unit)
	if unit == "player" then
		RefreshBags()
		WeightsHint()
		ns.GearSheet_Refresh()
	end
end

function events:BAG_UPDATE_DELAYED()
	ns.GearItems_InvalidateBags()
end

function events:PLAYER_LEVEL_UP()
	ns.GearItems_ClearCache()
	RefreshBags()
	ns.GearSheet_Refresh()
end

function events:GET_ITEM_INFO_RECEIVED()
	ns.GearItems_InfoReceived()
end

ns.GearItems_OnReady = function()
	if module.active then
		RefreshBags()
		ns.GearSheet_Refresh()
	end
end

---------------------------------------------------------------------------------------------------------------
-- Weights: import dialog and commands

local SIM_STEPS = {
	"How to check gear the tooltip can't judge (Raidbots Top Gear, free):",
	"  1. Type /simc and press Ctrl+C to copy the text it shows.",
	"  2. Open raidbots.com/simbot/topgear in a browser and paste it into the big box.",
	"  3. Tick the items you're unsure about (it lists your bags), then press Run Top Gear.",
	"  4. The result at the top is the best set to wear. Equip what it lists.",
}

local function PrintSimSteps()
	for _, line in ipairs(SIM_STEPS) do
		print(line)
	end
	if not (C_AddOns.IsAddOnLoaded("Simulationcraft")) then
		print("  (/simc needs the SimulationCraft addon, which isn't loaded.)")
	end
end

local function PrintWeights()
	local ctx = Context()
	if not ctx then
		ns.Print("Gear Check: no specialization yet.")
		return
	end
	if ctx.source == "none" then
		ns.Print(("Gear Check (%s): no stat weights. Main stat 1.0, secondary stats 0.5, so higher item level "
			.. "wins. Sim stat weights on Raidbots and /tomte gear import."):format(ctx.spec.name))
	else
		local parts = {}
		for key, value in pairs(ctx.weights) do
			parts[#parts + 1] = ("%s %.2f"):format(key, value)
		end
		table.sort(parts)
		local source = ctx.source == "imported" and ("imported \"" .. ctx.label .. "\"") or ("built-in, " .. ctx.label)
		ns.Print(("Gear Check (%s): %s - %s"):format(ctx.spec.name, source, table.concat(parts, ", ")))
	end
	if ctx.best then
		print(("  Best gem: %s (%s)"):format(ctx.best.name, ns.Gear_StatLabel(ctx.best.stats)))
	end
	print(("  Season ID: %s (built-in weights are for %s)"):format(tostring(CurrentSeason()), scales.seasonName))
end

-- Panel row label: where the current spec's weights come from.
local function SourceLabel()
	local ctx = module.active and db and Context()
	if not ctx then
		return "Weights in use"
	end
	local source = ctx.source == "imported" and "imported" or ctx.source == "builtin" and ("built-in, " .. ctx.label)
		or "none, item level decides"
	return ("%s: %s"):format(ctx.spec.name, source)
end

local function ClearWeights()
	local ctx = Context()
	if ctx then
		CharWeights()[ctx.spec.id] = nil
		local after = scales.specs[ctx.spec.id] and "the built-in weights" or "item level"
		ns.Print(("Gear Check: imported weights for %s cleared, back to %s."):format(ctx.spec.name, after))
		RefreshBags()
		ns.GearSheet_Refresh()
	end
end

local dialog

local function Import(text)
	local ctx = Context()
	if not ctx then
		return "No specialization yet."
	end
	local parsed, err = ns.Gear_ParsePawn(strtrim(text or ""))
	if not parsed then
		return err
	end
	if parsed.class ~= classToken or parsed.spec ~= ctx.spec.index then
		return ("That string is for another class or spec. You're %s right now."):format(ctx.spec.name)
	end
	CharWeights()[ctx.spec.id] = { name = parsed.name, weights = parsed.weights }
	ns.Print(("Gear Check: imported \"%s\" for %s."):format(parsed.name, ctx.spec.name))
	RefreshBags()
	ns.GearSheet_Refresh()
	return nil
end

local function BuildDialog()
	local UI = ns.UI
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(480, 230)
	f:SetPoint("CENTER", 0, 120)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], UI.BG[4])
	UI.Border(f, UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.5)

	f.title = UI.Text(f, 15, UI.GOLD)
	f.title:SetPoint("TOPLEFT", 16, -14)
	f.help = UI.Text(f, 12, UI.GREY)
	f.help:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
	f.help:SetPoint("RIGHT", -16, 0)
	f.help:SetJustifyH("LEFT")
	f.help:SetWordWrap(true)
	f.help:SetText("Optional. On raidbots.com choose Stat Weights, paste your /simc text, run it, then copy the "
		.. "Pawn string from the result and paste it here.")

	local box = CreateFrame("EditBox", nil, f)
	box:SetMultiLine(true)
	box:SetAutoFocus(true)
	box:SetFont(STANDARD_TEXT_FONT, 12, "")
	box:SetTextInsets(6, 6, 6, 6)
	box:SetPoint("TOPLEFT", f.help, "BOTTOMLEFT", 0, -10)
	box:SetPoint("RIGHT", -16, 0)
	box:SetHeight(80)
	local boxBg = box:CreateTexture(nil, "BACKGROUND")
	boxBg:SetAllPoints()
	boxBg:SetColorTexture(UI.BOX[1], UI.BOX[2], UI.BOX[3], UI.BOX[4])
	UI.Border(box, UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.35)
	box:SetScript("OnEscapePressed", function()
		f:Hide()
	end)
	f.box = box

	f.error = UI.Text(f, 12, { 1, 0.35, 0.3 })
	f.error:SetPoint("BOTTOMLEFT", 16, 18)
	f.error:SetPoint("RIGHT", -200, 0)
	f.error:SetJustifyH("LEFT")
	f.error:SetWordWrap(true)

	local cancel = UI.Button(f, 80, "Cancel")
	cancel:SetPoint("BOTTOMRIGHT", -16, 12)
	cancel:SetScript("OnClick", function()
		f:Hide()
	end)
	local ok = UI.Button(f, 80, "Import")
	ok:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
	ok:SetScript("OnClick", function()
		local err = Import(box:GetText())
		if err then
			f.error:SetText(err)
		else
			f:Hide()
		end
	end)
	f:Hide()
	return f
end

local function OpenImport()
	local ctx = Context()
	if not ctx then
		ns.Print("Gear Check: no specialization yet.")
		return
	end
	dialog = dialog or BuildDialog()
	dialog.title:SetText("Import stat weights for " .. ctx.spec.name)
	dialog.box:SetText("")
	dialog.error:SetText("")
	dialog:Show()
end

local function Command(fn)
	return function()
		if not module.active then
			ns.Print("Gear Check is off.")
			return
		end
		fn()
	end
end

-- For the character sheet panel (Sheet.lua) and the upgrade reveal (Reveal.lua).
ns.Gear_Context = Context
ns.Gear_EvaluateLink = Evaluate
ns.Gear_OpenImport = OpenImport
ns.Gear_ClearWeights = ClearWeights
ns.Gear_PrintSimSteps = PrintSimSteps

---------------------------------------------------------------------------------------------------------------

local function Start()
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	events:RegisterEvent("BAG_UPDATE_DELAYED")
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
	RefreshBags()
	ns.GearSheet_Init()
	ns.GearReveal_Start(db)
	C_Timer.After(ns.inWorld and 0 or 8, WeightsHint) -- at login, after the chat flood
end

local function Stop()
	events:UnregisterAllEvents()
	ns.GearReveal_Stop()
	if dialog then
		dialog:Hide()
	end
	RefreshBags()
	ns.GearSheet_Refresh()
end

module = ns.RegisterModule({
	key = "gear",
	name = "Gear Check",
	category = "Gear",
	description = "Says on each item's tooltip whether it's an upgrade, and why not when it isn't: wrong armor or "
		.. "main stat, breaks your tier set, loses an embellishment or effect, unique limits. Trinkets and items "
		.. "with effects are marked to sim instead of guessed. Also: upgrades for your other specs, the best gem "
		.. "for empty sockets, and missing enchants. Can mark upgrades in Baganator and reveal new upgrades as a moment "
		.. "with a click-to-equip toast.",
	enabledByDefault = true,
	defaults = {
		showReasons = true,
		showDowngrades = true,
		compareTooltips = false,
		baganator = true,
		offspec = true,
		rank = true,
		gemHints = true,
		enchantHints = true,
		weights = {}, -- [playerGUID][specID] = { name, weights = { AGI = 1, ... } }
		hinted = {}, -- [specID] = which built-in weights hint was shown ("builtin" or "stale:<season>")
		sheetButton = true,
		sheetOpen = false, -- the panel next to the character sheet
		reveal = true,
		revealToast = true,
		revealMinPct = 2,
	},
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
	},
	options = {
		{ type = "header", label = "Tooltip" },
		{ type = "checkbox", key = "showReasons", label = "Show reasons",
			tooltip = "Up to three short lines under the verdict, e.g. \"Breaks your 4-set\"." },
		{ type = "checkbox", key = "showDowngrades", label = "Show downgrades" },
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
		{ type = "header", label = "Bags" },
		{ type = "checkbox", key = "baganator", label = "Mark upgrades in Baganator", onChange = RefreshBags,
			tooltip = "Only clean upgrades get the arrow. In Baganator's settings (Icons), pick \"Tomte Gear Check\" "
				.. "as the upgrade source." },
		{ type = "header", label = "Upgrade reveal" },
		{ type = "checkbox", key = "reveal", label = "Reveal new upgrades",
			tooltip = "When gear that's new to your bags (loot, quest rewards, the vault, mail) is a clean upgrade, show "
				.. "it as a moment. Choose banner or cinematic under Moments > Gear upgrade. Items taken out of a bank "
				.. "don't count." },
		{ type = "slider", key = "revealMinPct", label = "Smallest upgrade", min = 0, max = 10, step = 0.5,
			format = function(value)
				return ("%g%%"):format(value)
			end,
			tooltip = "Upgrades below this are left alone (gear for an empty slot always counts)." },
		{ type = "checkbox", key = "revealToast", label = "Equip toast",
			tooltip = "A toast with the upgrade: click it to equip the item, right-click to dismiss. Not in combat." },
		{ type = "header", label = "Stat weights" },
		{ type = "button", label = SourceLabel, text = "Show", onClick = Command(PrintWeights),
			tooltip = "Imported weights win, then the built-in ones (Beast Mastery, Marksmanship, Protection "
				.. "Paladin), else main stat 1.0 and secondaries 0.5. Show prints them in chat." },
		{ type = "button", label = "Import for your current spec", text = "Import", onClick = Command(OpenImport),
			tooltip = "Raidbots stat weights fit your character better than the built-in ones." },
		{ type = "button", label = "Remove for your current spec", text = "Remove", onClick = Command(ClearWeights),
			confirm = "Remove the imported stat weights for your current spec?" },
		{ type = "button", label = "How to sim an item", text = "Show", onClick = PrintSimSteps,
			tooltip = "Prints the Raidbots Top Gear steps in chat." },
	},
})
ns.gearModule = module
