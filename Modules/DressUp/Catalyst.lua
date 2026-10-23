local addonName, ns = ...

-- Dressing room, Catalyst preview: in the Catalyst (ItemInteractionFrame converting an item, Blizzard_ItemInteractionUI)
-- a line under the result slot names the piece you would get and says whether its look is new; the slot's tooltip
-- gains the clicks, Ctrl-click tries the piece on and Shift-click links it. Only hooks (HookScript, hooksecurefunc on
-- the slot's RefreshIcon); they do nothing while the module or its setting is off. Text in Data.lua; registered in
-- DressUp.lua.

local STRIP_WIDTH = 170 -- the result slot sits 75 px right of the frame's middle: room without crossing the arrow
local STRIP_GAP = 6

local UI = ns.UI
local BAR = ns.DressUpBar
local LookText = ns.DressUp_LookText

local module, db
local hooked = false
local strip

local function On()
	return module and module.active and db.catalyst
end

local function OutputSlot()
	local conversion = ItemInteractionFrame and ItemInteractionFrame.ItemConversionFrame
	return conversion and conversion.ItemConversionOutputSlot
end

-- The converted piece's link, or nil while nothing is in the Catalyst.
local function ResultLink()
	local frame = ItemInteractionFrame
	local slot = OutputSlot()
	if not (frame and slot and slot:IsVisible() and frame:GetItemLocation()) then
		return nil
	end
	local data = C_TooltipInfo.GetItemInteractionItem()
	local link = data and data.hyperlink
	if not link or ns.IsSecret(link) then
		return nil
	end
	return link
end

-- Whether the piece's look is collected; nil when it has none or isn't loaded yet.
local function LookCollected(link)
	local _, sourceID = C_TransmogCollection.GetItemInfo(link)
	if not sourceID then
		return nil
	end
	local info = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
	return info and info.appearanceIsCollected
end

local function Update()
	if not strip then
		return
	end
	local link = On() and ResultLink()
	if not link then
		strip:Hide()
		return
	end
	strip.name:SetText(link) -- the link shows as the item's name in its quality color
	local text, role = LookText(LookCollected(link))
	strip.look:SetText(text and UI.Wrap(text, role) or "")
	strip:Show()
end

-- Ctrl-click: on the open dressing room's model (no Blizzard function called, so the window stays untainted), else
-- through Blizzard's modified click, which opens it. Shift-click: Blizzard's modified click links it.
local function OnClick()
	if not (On() and IsModifiedClick()) then
		return
	end
	local link = ResultLink()
	if not link then
		return
	end
	if IsModifiedClick("DRESSUP") then
		local frame, actor = DressUpFrame, BAR.Actor()
		-- pcall: TryOn errors on an item the model can't dress.
		if frame and frame:IsShown() and frame:GetMode() == "player" and actor and pcall(actor.TryOn, actor, link) then
			return
		end
	end
	HandleModifiedItemClick(link)
end

local function OnEnter(slot)
	if not (On() and GameTooltip:IsOwned(slot) and ResultLink()) then
		return
	end
	UI.TipLine("Ctrl-click: try it on", "textMuted")
	UI.TipLine("Shift-click: link it", "textMuted")
	GameTooltip:Show()
end

local function CreateStrip(slot)
	strip = CreateFrame("Frame", nil, slot:GetParent())
	strip:SetSize(STRIP_WIDTH, 30)
	strip:SetPoint("TOP", slot, "BOTTOM", 0, -STRIP_GAP)
	strip.name = UI.Text(strip, 11, "text")
	strip.name:SetPoint("TOP")
	strip.name:SetWidth(STRIP_WIDTH)
	strip.name:SetJustifyH("CENTER")
	strip.name:SetWordWrap(false)
	strip.look = UI.Text(strip, 10, "textMuted")
	strip.look:SetPoint("TOP", strip.name, "BOTTOM", 0, -2)
	strip.look:SetJustifyH("CENTER")
	strip:Hide()
end

local function Hook()
	local slot = OutputSlot()
	if hooked or not slot then
		return
	end
	hooked = true -- hooks can't be undone: each checks On()
	CreateStrip(slot)
	slot:HookScript("OnClick", OnClick)
	slot:HookScript("OnEnter", OnEnter)
	hooksecurefunc(slot, "RefreshIcon", Update)
	ItemInteractionFrame:HookScript("OnShow", Update)
	ItemInteractionFrame:HookScript("OnHide", Update)
end

function ns.DressUp_CatalystInit(mod, saved)
	module, db = mod, saved
end

-- On toggle and when the setting changes.
function ns.DressUp_CatalystUpdate()
	if On() and not hooked then
		EventUtil.ContinueOnAddOnLoaded("Blizzard_ItemInteractionUI", Hook)
	end
	Update()
end
