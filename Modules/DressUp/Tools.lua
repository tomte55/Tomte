local addonName, ns = ...

-- Dressing room toolbar: three buttons down the right side of the model. Undress (everything off), Target's outfit
-- (inspects your target and puts its transmog on the model: the target's body, or yours with the setting) and Item
-- list (the outfit as copyable text, with where each piece comes from). Like the slot bar, these only talk to the
-- model's player actor and never call Blizzard's dressing room functions (DressUpFrame_Show and friends taint the
-- window when an addon calls them: its Link > Copy button then gets blocked).

local UI = ns.UI
local BAR = ns.DressUpBar

local OWNER = "dressupTools"
local SIZE, GAP = 32, 6
local INSPECT_TIMEOUT = 3
local events = ns.DressUp_Events

local TOOLS = {}
ns.DressUpTools = TOOLS

local toolbar
local pending -- { guid, unit } while an inspect is out
local db

-- Actions ------------------------------------------------------------------------------------------------------------

local function Undress()
	local actor = BAR.Actor()
	if actor then
		actor:Undress()
	end
end

local function StopInspect()
	pending = nil
	events:Unwatch(OWNER, "INSPECT_READY")
end

-- Blizzard's Inspect window's unit while it's open (Blizzard_InspectUI loads on demand), else nil. That window owns
-- the inspect then: we may read it but never clear it.
local function InspectWindowUnit()
	return InspectFrame and InspectFrame:IsShown() and InspectFrame.unit or nil
end

local function TargetOutfit()
	local unit = "target"
	if not (UnitExists(unit) and UnitIsPlayer(unit)) then
		ns.Print("target a player first.")
		return
	end
	if not CanInspect(unit) then
		ns.Print("can't inspect your target (too far away?).")
		return
	end
	local inspecting = InspectWindowUnit()
	if inspecting and not UnitIsUnit(inspecting, unit) then
		ns.Print("close the Inspect window first.")
		return
	end
	local actor = BAR.Actor()
	if not actor then
		return
	end
	if not db.ownBody then
		-- The target's own body, undressed until its transmog arrives.
		actor:SetModelByUnit(unit, false, false, false, true)
	end
	pending = { guid = UnitGUID(unit) }
	events:Watch(OWNER, "INSPECT_READY")
	NotifyInspect(unit)
	local asked = pending
	C_Timer.After(INSPECT_TIMEOUT, function()
		if pending == asked then
			StopInspect()
			ns.Print("your target's outfit didn't arrive. Try again closer.")
		end
	end)
end

events:On(OWNER, "INSPECT_READY", function(_, guid)
	if not pending or guid ~= pending.guid then
		return
	end
	StopInspect()
	local list = C_TransmogCollection.GetInspectItemTransmogInfoList()
	if not InspectWindowUnit() then
		ClearInspectPlayer() -- ours alone; the Inspect window clears its own when it closes
	end
	local actor = BAR.Actor()
	if not (actor and list) then
		return
	end
	actor:Undress()
	for slot, info in ipairs(list) do
		pcall(actor.SetItemTransmogInfo, actor, info, slot, slot ~= INVSLOT_MAINHAND)
	end
end)

local function SourceText(sourceID)
	local info = C_TransmogCollection.GetSourceInfo(sourceID)
	local drops = C_TransmogCollection.GetAppearanceSourceDrops(sourceID)
	local drop = drops and drops[1]
	if drop then
		drop = { encounter = drop.encounter, instance = drop.instance,
			difficulty = drop.difficulties and drop.difficulties[1] }
	end
	local names = setmetatable({}, { __index = function(_, n)
		return _G["TRANSMOG_SOURCE_" .. n]
	end })
	-- The name: the source's own, else the item's (asked for when the client hasn't loaded it yet).
	local name = info and info.name
	if (not name or name == "") and info and info.itemID then
		name = C_Item.GetItemNameByID(info.itemID)
		if not name then
			C_Item.RequestLoadItemDataByID(info.itemID)
		end
	end
	if not name or name == "" then
		local link = BAR.SourceLink(sourceID)
		name = link and C_Item.GetItemNameByID(link)
	end
	return ns.DressUp_SourceText(info and info.sourceType, drop, names), name
end

local function ItemList()
	local lines = {}
	for _, slot in ipairs(ns.DRESSUP_SLOTS) do
		local info = slot and not BAR.IsHidden(slot) and BAR.Wearing(slot)
		if info then
			local source, name = SourceText(info.appearanceID)
			local line = ns.DressUp_ListLine(BAR.SlotName(slot), name, source)
			if line then
				lines[#lines + 1] = line
			end
		end
	end
	if #lines == 0 then
		ns.Print("no item names yet (the game is still loading them). Try again in a moment.")
		return
	end
	ns.Dialog_Show({
		title = "Outfit",
		hint = "Ctrl+C to copy. Blizzard's Link button posts the outfit itself.",
		text = table.concat(lines, "\n"),
		readOnly = true,
		height = 300,
	})
end

-- Buttons ------------------------------------------------------------------------------------------------------------

local TOOLS_LIST = {
	{ icon = "Interface\\Icons\\INV_Shirt_White_01", label = "Undress", tip = "Take everything off the model.",
		run = Undress },
	{ icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath", label = "Target's outfit",
		tip = "Inspect your target and show its transmog.", run = TargetOutfit },
	{ icon = "Interface\\Icons\\INV_Misc_Note_01", label = "Item list",
		tip = "The outfit as text to copy, with where each piece comes from.", run = ItemList },
}

local function CreateButton(def, i)
	local b = CreateFrame("Button", nil, toolbar)
	b:SetSize(SIZE, SIZE)
	b:SetPoint("TOPRIGHT", 0, -(i - 1) * (SIZE + GAP))
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", -1, 1)
	icon:SetTexture(def.icon)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	UI.Border(b, "frame", 0.8)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(icon)
	hover:SetColorTexture(UI.RGBA("hover"))
	b:SetScript("OnEnter", function(self)
		UI.SetBorderColor(self, "accent", 1)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(def.label, 1, 1, 1)
		GameTooltip:AddLine(def.tip, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		UI.SetBorderColor(self, "frame", 0.8)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", def.run)
	return b
end

local function Create()
	toolbar = CreateFrame("Frame", nil, DressUpFrame)
	toolbar:SetFrameLevel(DressUpFrame.ModelScene:GetFrameLevel() + 10)
	toolbar:SetSize(SIZE, #TOOLS_LIST * (SIZE + GAP))
	toolbar:SetPoint("TOPRIGHT", DressUpFrame.ModelScene, "TOPRIGHT", -10, -44)
	for i, def in ipairs(TOOLS_LIST) do
		CreateButton(def, i)
	end
	toolbar:Hide()
end

function TOOLS.Init(saved)
	db = saved
end

function TOOLS.Update(on)
	if not DressUpFrame then
		return
	end
	if not toolbar then
		if not on then
			return
		end
		Create()
	end
	toolbar:SetShown(on and DressUpFrame:IsShown() and DressUpFrame:GetMode() == "player" and BAR.Actor() ~= nil)
	if not toolbar:IsShown() then
		StopInspect()
	end
end
