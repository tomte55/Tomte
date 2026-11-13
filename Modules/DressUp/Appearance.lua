local addonName, ns = ...

-- Dressing room, appearance lines: item tooltips for gear say whether you have its look ("Appearance not collected",
-- "... (not for this character)", "Appearance collected from another item", "Appearance collected"). Where the game
-- already says it ("You haven't collected this appearance" and its "not from this item" twin, matched through their
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

-- /tomte dressup looks: every item in your bags whose look isn't collected, with what the game answers about it
-- (PlayerCanCollectSource: has data, can collect), to see why one shows as "not for this character".
function ns.DressUp_LooksReport()
	local n = 0
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local link = C_Container.GetContainerItemLink(bag, slot)
			local sourceID
			if link then
				sourceID = select(2, C_TransmogCollection.GetItemInfo(link))
			end
			local info = sourceID and C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
			if info and not ns.AppearanceCollected(sourceID, info) then
				local hasData, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
				ns.Print(("%s source %d, has data %s, can collect %s"):format(link, sourceID,
					tostring(hasData), tostring(canCollect)))
				n = n + 1
			end
		end
	end
	if n == 0 then
		ns.Print("no item in your bags has a look you haven't collected.")
	end
end

function ns.DressUp_AppearanceInit(mod, settings)
	module, db = mod, settings
end

-- On toggle and when the setting changes.
function ns.DressUp_AppearanceUpdate()
	if On() and not hooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		hooked = true -- post-calls can't be removed; OnItem checks On()
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Perf_Wrap(OnItem, "tooltip"))
	end
end
