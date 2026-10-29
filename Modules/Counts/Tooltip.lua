local addonName, ns = ...

-- Item counts: the lines on item tooltips: who has the item and where ("Kesha  20 (mail)"), the Warband bank, guild
-- banks, and a total. One item tooltip post-call, added once; it does nothing while the module or its setting is off.
-- Lines built in Data.lua; registered in Counts.lua.

local UI = ns.UI

local module, db
local hooked = false

local function On()
	return module and module.active and db.tooltip
end

local function OnItem(tooltip, data)
	if not (On() and tooltip.AddDoubleLine and data) then
		return
	end
	local itemID = data.id
	if not itemID or ns.IsSecret(itemID) or type(itemID) ~= "number" then
		return
	end
	local rows, total = ns.Counts_Rows(ns.Counts_Entry(itemID), db, UnitGUID("player"))
	if total == 0 then
		return
	end
	local lines = ns.Counts_TipLines(rows, total)
	tooltip:AddLine(" ")
	for _, line in ipairs(lines) do
		local left = line.class and UI.ClassColored(line.left, line.class) or UI.Wrap(line.left, line.role or "text")
		local r, g, b = UI.Color(line.role == "heading" and "heading" or "text")
		tooltip:AddDoubleLine(left, line.right, nil, nil, nil, r, g, b)
	end
end

function ns.CountsTooltip_Init(mod, settings)
	module, db = mod, settings
end

-- On toggle and when the setting changes.
function ns.CountsTooltip_Update()
	if On() and not hooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		hooked = true -- post-calls can't be removed; OnItem checks On()
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Perf_Wrap(OnItem, "tooltip"))
	end
end
