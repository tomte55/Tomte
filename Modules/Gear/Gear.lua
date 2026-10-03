local addonName, ns = ...

-- Gear Check: an upgrade verdict on item tooltips (and Baganator's upgrade arrows) that only says "upgrade" when
-- nothing it can't value is at stake: set bonuses, embellishments, effects and unique limits are checked, and
-- items whose value is an effect are sent to a sim instead of guessed. Rules in Data.lua, item reading in
-- Items.lua. Weights: a Pawn string per spec (Raidbots), else primary 1 / secondaries 0.5.

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

local function Spec()
	local index = GetSpecialization()
	if not index then
		return nil
	end
	local specID, name, _, _, _, primaryStat = GetSpecializationInfo(index)
	return { index = index, id = specID, name = name, primary = PRIMARY_KEYS[primaryStat] }
end

local function CharWeights()
	local guid = UnitGUID("player")
	db.weights[guid] = db.weights[guid] or {}
	return db.weights[guid]
end

local function Context()
	local spec = Spec()
	if not (spec and spec.id and spec.primary) then
		return nil
	end
	local saved = CharWeights()[spec.id]
	return {
		spec = spec,
		primary = spec.primary,
		weights = saved and saved.weights or ns.Gear_DefaultWeights(spec.primary),
		noWeights = saved == nil,
		armorSubclass = ns.Gear_ArmorForClass(classToken),
	}
end

local function Evaluate(link)
	local ctx = Context()
	local equipped = ctx and ns.GearItems_Equipped()
	local cand = equipped and ns.GearItems_Describe(link)
	if not cand then
		return nil
	end
	ctx.specOK = cand.specs == nil or cand.specs[ctx.spec.id] == true
	return ns.Gear_Evaluate(cand, equipped, ctx)
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
	local verdict = Evaluate(link)
	if not verdict or (verdict.kind == "downgrade" and not db.showDowngrades) then
		return
	end
	local headline, color = ns.Gear_Headline(verdict)
	tooltip:AddLine(LABEL .. COLORS[color] .. headline .. "|r")
	if db.showReasons then
		for i = 1, math.min(#verdict.reasons, MAX_REASONS) do
			tooltip:AddLine(REASON .. "   " .. verdict.reasons[i] .. "|r", nil, nil, nil, true)
		end
	end
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
end

function events:PLAYER_SPECIALIZATION_CHANGED(unit)
	if unit == "player" then
		RefreshBags()
	end
end

function events:PLAYER_LEVEL_UP()
	ns.GearItems_ClearCache()
	RefreshBags()
end

function events:GET_ITEM_INFO_RECEIVED()
	ns.GearItems_InfoReceived()
end

ns.GearItems_OnReady = function()
	if module.active then
		RefreshBags()
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
	local saved = CharWeights()[ctx.spec.id]
	if not saved then
		ns.Print(("Gear Check (%s): no stat weights imported. Main stat 1.0, secondary stats 0.5, so higher item "
			.. "level wins. That's fine for most choices. Optional: /tomte gear import."):format(ctx.spec.name))
		return
	end
	local parts = {}
	for key, value in pairs(saved.weights) do
		parts[#parts + 1] = ("%s %.2f"):format(key, value)
	end
	table.sort(parts)
	ns.Print(("Gear Check (%s): \"%s\" - %s"):format(ctx.spec.name, saved.name, table.concat(parts, ", ")))
end

local function ClearWeights()
	local ctx = Context()
	if ctx then
		CharWeights()[ctx.spec.id] = nil
		ns.Print(("Gear Check: weights for %s cleared, back to item level."):format(ctx.spec.name))
		RefreshBags()
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

---------------------------------------------------------------------------------------------------------------

local function Start()
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	if not module.tooltipHooked then
		module.tooltipHooked = true -- post-calls can't be removed; OnItem checks module.active
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	end
	RegisterBaganator()
	ns.GearItems_InvalidateEquipped()
	RefreshBags()
end

local function Stop()
	events:UnregisterAllEvents()
	if dialog then
		dialog:Hide()
	end
	RefreshBags()
end

module = ns.RegisterModule({
	key = "gear",
	name = "Gear Check",
	category = "Gear",
	description = "Says on each item's tooltip whether it's an upgrade, and why not when it isn't: wrong armor or "
		.. "main stat, breaks your tier set, loses an embellishment or effect, unique limits. Trinkets and items "
		.. "with effects are marked to sim instead of guessed. Can mark upgrades in Baganator.",
	enabledByDefault = true,
	defaults = {
		showReasons = true,
		showDowngrades = true,
		compareTooltips = false,
		baganator = true,
		weights = {}, -- [playerGUID][specID] = { name, weights = { AGI = 1, ... } }
	},
	init = function(moduleDB)
		db = moduleDB
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
		{ "weights", "show the stat weights in use", Command(PrintWeights) },
		{ "clear", "remove the imported weights for your current spec", Command(ClearWeights) },
	},
	options = {
		{ type = "header", label = "Tooltip" },
		{ type = "checkbox", key = "showReasons", label = "Show reasons",
			tooltip = "Up to three short lines under the verdict, e.g. \"Breaks your 4-set\"." },
		{ type = "checkbox", key = "showDowngrades", label = "Show downgrades" },
		{ type = "checkbox", key = "compareTooltips", label = "Also on comparison tooltips",
			tooltip = "The tooltips of your equipped items that appear next to the hovered one." },
		{ type = "header", label = "Bags" },
		{ type = "checkbox", key = "baganator", label = "Mark upgrades in Baganator", onChange = RefreshBags,
			tooltip = "Only clean upgrades get the arrow. In Baganator's settings (Icons), pick \"Tomte Gear Check\" "
				.. "as the upgrade source." },
		{ type = "header", label = "Stat weights (optional)" },
		{ type = "button", label = "Import for your current spec", text = "Import", onClick = Command(OpenImport),
			tooltip = "Without weights the main stat counts 1.0 and every secondary stat 0.5, so item level decides. "
				.. "Raidbots stat weights fine-tune that for your character." },
		{ type = "button", label = "Remove for your current spec", text = "Remove", onClick = Command(ClearWeights),
			confirm = "Remove the imported stat weights for your current spec?" },
		{ type = "button", label = "How to sim an item", text = "Show", onClick = PrintSimSteps,
			tooltip = "Prints the Raidbots Top Gear steps in chat." },
	},
})
