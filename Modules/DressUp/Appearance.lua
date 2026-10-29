local addonName, ns = ...

-- Dressing room, appearance lines: item tooltips for gear say whether you have its look ("Appearance not collected",
-- "... (another class)", "Appearance collected from another item", "Appearance collected"). Where the game already
-- says it ("You haven't collected this appearance" and its "not from this item" twin, matched through their
-- localized globals), no second line. One item tooltip post-call, added once; it does nothing while the module or
-- its setting is off. States and wording in Data.lua; registered in DressUp.lua. Tomte's bags mark the same looks.

local UI = ns.UI
local State = ns.DressUp_AppearanceState
local Line = ns.DressUp_AppearanceLine

local module, db
local hooked = false

local function On()
	return module and module.active and db.appearance
end

-- The game's own line about this item's look is already in the tooltip.
local function GameSaysIt(data)
	local unknown = _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN
	local otherItem = _G.TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN
	for _, line in ipairs(data.lines or {}) do
		local text = line.leftText
		if text and not ns.IsSecret(text) and (text == unknown or text == otherItem) then
			return true
		end
	end
	return false
end

local function OnItem(tooltip, data)
	if not (On() and tooltip.AddLine and data) then
		return
	end
	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	if not link or ns.IsSecret(link) then
		return
	end
	local _, sourceID = C_TransmogCollection.GetItemInfo(link)
	if not sourceID then
		return
	end
	local info = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
	if info then
		local look, source = ns.AppearanceCollected(sourceID, info)
		info = { appearanceIsCollected = look, sourceIsCollected = source }
	end
	local _, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
	local state = State(info, canCollect)
	if (state == "new" or state == "source") and GameSaysIt(data) then
		return
	end
	local text, role = Line(state)
	if text then
		tooltip:AddLine(UI.Wrap(text, role))
	end
end

function ns.DressUp_AppearanceInit(mod, settings)
	module, db = mod, settings
end

-- On toggle and when the setting changes.
function ns.DressUp_AppearanceUpdate()
	if On() and not hooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		hooked = true -- post-calls can't be removed; OnItem checks On()
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	end
end
