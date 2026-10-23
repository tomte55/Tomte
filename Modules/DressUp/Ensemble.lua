local addonName, ns = ...

-- Dressing room, ensemble tooltips: an item that teaches a transmog set (an ensemble or arsenal) gets a line with how
-- many of its looks you have ("5 of 8 appearances collected"). One item tooltip post-call, added once; it does
-- nothing while the module or its setting is off. Counting in Data.lua; registered in DressUp.lua.

local UI = ns.UI
local Counts = ns.DressUp_EnsembleCounts
local Line = ns.DressUp_EnsembleLine

local module, db
local hooked = false

local function On()
	return module and module.active and db.ensemble
end

-- The set's pieces as { appearanceID, collected }, or nil for an item that teaches no set.
local function SetPieces(itemID)
	local setID = C_Item.GetItemLearnTransmogSet(itemID)
	if not setID then
		return nil
	end
	local pieces = {}
	for _, item in ipairs(C_Transmog.GetAllSetAppearancesByID(setID) or {}) do
		local info = C_TransmogCollection.GetAppearanceInfoBySource(item.itemModifiedAppearanceID)
		if info then
			pieces[#pieces + 1] = { appearanceID = info.appearanceID, collected = info.appearanceIsCollected }
		end
	end
	return pieces
end

local function OnItem(tooltip, data)
	if not (On() and tooltip.AddLine and data) then
		return
	end
	local itemID = data.id
	if not itemID or ns.IsSecret(itemID) or type(itemID) ~= "number" then
		return
	end
	local pieces = SetPieces(itemID)
	local text, role = Line(Counts(pieces))
	if text then
		tooltip:AddLine(UI.Wrap(text, role))
	end
end

function ns.DressUp_EnsembleInit(mod, settings)
	module, db = mod, settings
end

-- On toggle and when the setting changes.
function ns.DressUp_EnsembleUpdate()
	if On() and not hooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		hooked = true -- post-calls can't be removed; OnItem checks On()
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	end
end
