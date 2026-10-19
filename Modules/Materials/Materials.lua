local addonName, ns = ...

-- Material uses: item tooltips on crafting materials say which of your characters craft with them (from Alts'
-- recipes, ns.Alts_UsedBy), which other professions use them (Generated.lua, made by tools/materials.py) or that
-- nothing uses them. Holding Shift lists the recipes. Wording and rules in Data.lua.

local UI = ns.UI

local module, db
local tagged -- the tooltip that last got our lines, refreshed when Shift changes

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local profNames = {} -- [skill line] = localized profession name, or false when the client has none

local function ProfName(line)
	local name = profNames[line]
	if name == nil then
		name = C_TradeSkillUI.GetTradeSkillDisplayName(line)
		name = (type(name) == "string" and name ~= "") and name or false
		profNames[line] = name
	end
	return name or nil
end

-- Trade goods and plain reagents. Mythic Keystones and context tokens are in the Reagent class too, but nothing
-- crafts with them.
local function IsMaterial(itemID)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	return classID == Enum.ItemClass.Tradegoods
		or (classID == Enum.ItemClass.Reagent and subclassID == Enum.ItemReagentSubclass.Reagent)
end

local function LinesFor(itemID, shift)
	return ns.Materials_Lines({
		usedBy = ns.Alts_UsedBy(itemID), uses = ns.MATERIALS_USES[itemID], isMaterial = IsMaterial(itemID),
		known = ns.Materials_Known(itemID, ns.MATERIALS_LAST_ITEM), notUsed = db.notUsed, shift = shift,
		profName = ProfName,
	})
end

local function OnItem(tooltip, data)
	if not (module.active and db.tooltip and tooltip.AddLine and data) then
		return
	end
	local itemID = data.id
	if not itemID or ns.IsSecret(itemID) or type(itemID) ~= "number" then
		return
	end
	local lines = LinesFor(itemID, IsShiftKeyDown())
	for _, line in ipairs(lines) do
		tooltip:AddLine(UI.Wrap(line.text, line.role), 1, 1, 1, true)
	end
	if #lines > 0 then
		tagged = tooltip
	end
end

-- Bag buttons rebuild their tooltip every 0.2 s anyway (GameTooltip_OnUpdate calls the owner's UpdateTooltip);
-- other tooltips (bank, mail, auction house) only rebuild when asked, so a Shift change asks.
function events:MODIFIER_STATE_CHANGED(key)
	if (key == "LSHIFT" or key == "RSHIFT") and tagged and tagged:IsShown() and tagged.RefreshDataNextUpdate then
		tagged:RefreshDataNextUpdate()
	end
end

-- /tomte materials why <item>: both sources' answers, for checking the table against the game.
local function Why(arg)
	local itemID = tonumber(arg) or tonumber((arg or ""):match("item:(%d+)"))
	if not itemID then
		ns.Print("usage: /tomte materials why <item link or ID>")
		return
	end
	local name = C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
	local usedBy = ns.Alts_UsedBy(itemID)
	ns.Print(("%s (%d), %s:"):format(name, itemID, IsMaterial(itemID) and "a material" or "not a trade good or crafting reagent"))
	if #usedBy == 0 then
		ns.Print("  Alts: no known recipe uses it" .. (ns.altsModule and ns.altsModule.active and "." or " (Alts is off)."))
	end
	for _, entry in ipairs(usedBy) do
		ns.Print(("  Alts: %s, %s, %d recipes"):format(entry.name or "?", entry.profName or "?", #entry.recipes))
	end
	local uses = ns.MATERIALS_USES[itemID]
	if not uses then
		ns.Print("  Table: no profession uses it.")
	end
	if not ns.Materials_Known(itemID, ns.MATERIALS_LAST_ITEM) then
		ns.Print("  Table: the item is newer than the table, so it never says \"Not used in crafting\".")
	end
	for line, count in pairs(uses or {}) do
		ns.Print(("  Table: %s (%d), %d recipes"):format(ProfName(line) or "?", line, count))
	end
end

module = ns.RegisterModule({
	key = "materials",
	name = "Material uses",
	category = "professions",
	icon = 132906, -- inv_fabric_silk_02
	summary = "Material tooltips say who crafts with them, so you know what to keep.",
	description = "Crafting materials say on their tooltip what they're for, so you know what to bank and what to "
		.. "sell: which of your characters craft with them, which other professions use them, or that nothing does. "
		.. "Hold Shift for the recipes. Your characters' recipes come from Alts, read when a profession window opens.",
	enabledByDefault = true,
	defaults = {
		tooltip = true,
		notUsed = true, -- "Not used in crafting" on trade goods and reagents no recipe uses
	},
	init = function(saved)
		db = saved
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	end,
	toggle = function(active)
		if active then
			events:RegisterEvent("MODIFIER_STATE_CHANGED")
		else
			events:UnregisterEvent("MODIFIER_STATE_CHANGED")
			tagged = nil
		end
	end,
	options = {
		{ type = "header", label = "Tooltips" },
		{ type = "checkbox", key = "tooltip", label = "Material uses on item tooltips",
			tooltip = "\"Used by\" names your characters who know a recipe with the material (needs Alts, and each "
				.. "profession window opened once). \"Also\" lists the other professions that use it." },
		{ type = "checkbox", key = "notUsed", label = "Say when nothing uses a material", parent = "tooltip",
			tooltip = "Trade goods and reagents that no recipe in Tomte's list uses get \"Not used in crafting\". Items newer than the list get no line." },
	},
	commands = {
		{ "why", "what both sources know about an item: /tomte materials why <item link or ID>", function(arg)
			Why(arg)
		end },
	},
})
