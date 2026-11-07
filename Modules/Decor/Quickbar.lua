local addonName, ns = ...

-- Decorating tools: the quickbar. Eight slots, each holding a decor you place often, plus the last placed decor, in a
-- bar left of the house editor's mode bar (Basic and Expert modes). A click or the slot's key picks the decor up; the
-- key on an empty slot while you hold a decor puts that decor there. A button at the bar's left end opens the
-- Decorating panel (Dock.lua). Rules in ToolsData.lua; registered in Decorate.lua.

local SLOTS = 8
local SIZE = 38 -- slot buttons, pixels
local GAP = 4
local BAR_GAP = 16 -- between the bar and Blizzard's mode bar
local ICON_TOOLS = 134520 -- inv_misc_wrench_01, the panel button
local STORAGE_DELAY = 0.3 -- seconds of storage updates gathered into one redraw
-- A click that picks a decor up waits this long: the same click would otherwise drop the new decor at the mouse.
local CLICK_DELAY = 0.1
local UI = ns.UI

local OWNER = "quickbar"
local events = ns.Decorate_Events

local db
local active, editing = false, false
local mode = 0
local bar
local buttons = {} -- [0] = the last placed slot, [1..8] = the quickbar slots

local function SlotDecor(slot)
	if slot == 0 then
		return ns.DecorateClip_Recent()[1]
	end
	return db.slots[slot]
end

local function KeyFor(slot)
	return slot > 0 and db.keys["slot" .. slot] or ""
end

-- Slots ---------------------------------------------------------------------------------------------------------------

local function SlotEnter(self)
	local slot = self.slot
	local decorID = SlotDecor(slot)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if decorID then
		local name = ns.DecorPlace_Look(decorID)
		GameTooltip:SetText(name, UI.Color("heading"))
		local stored = ns.DecorEditor_Stored(ns.DecorPlace_CatalogInfo(decorID))
		UI.TipLine(("In storage: %d"):format(stored), stored > 0 and "text" or "textMuted")
		GameTooltip:AddLine(" ")
		UI.TipLine("Click: pick it up", "accent")
		if slot > 0 then
			UI.TipLine("Right-click: clear this slot", "textMuted")
		end
	elseif slot == 0 then
		GameTooltip:SetText("Last placed", UI.Color("heading"))
		UI.TipLine("The decor you placed last shows here.", "textMuted", true)
	else
		GameTooltip:SetText(("Slot %d"):format(slot), UI.Color("heading"))
		local key = KeyFor(slot)
		UI.TipLine(key ~= "" and ("Hold a decor and press %s to put it here."):format(ns.KeyText(key))
			or "Right-click a decor in the Decorating panel to put it here.", "textMuted", true)
	end
	if slot == 0 then
		UI.TipLine("Your last placements are in the Decorating panel's Recent tab.", "textMuted", true)
	end
	GameTooltip:Show()
end

local function SlotClick(self, button)
	local slot = self.slot
	if button == "RightButton" then
		if slot > 0 and db.slots[slot] then
			db.slots[slot] = nil
			ns.DecorateClip_Changed()
		end
		return
	end
	local decorID = SlotDecor(slot)
	if decorID then
		ns.DecorateClip_Place(decorID, { delay = CLICK_DELAY })
	end
end

local function CreateSlot(slot)
	local b = CreateFrame("Button", nil, bar)
	b:SetSize(SIZE, SIZE)
	b.slot = slot
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	UI.Surface(b, 0.5)
	UI.HoverWash(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 3, -3)
	b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.key = UI.Text(b, 10, "textMuted", "number")
	b.key:SetPoint("TOPLEFT", 3, -2)
	b.count = UI.Text(b, 11, "heading", "number")
	b.count:SetPoint("BOTTOMRIGHT", -3, 3)
	b:SetScript("OnEnter", function(self)
		UI.HoverOn(self)
		SlotEnter(self)
	end)
	b:SetScript("OnLeave", function(self)
		UI.HoverOff(self, "frame", 0.5)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", SlotClick)
	buttons[slot] = b
	return b
end

local function FillSlot(b)
	local decorID = SlotDecor(b.slot)
	if decorID then
		ns.DecorPlace_SetIcon(b.icon, decorID)
		b.icon:Show()
		local stored = ns.DecorEditor_Stored(ns.DecorPlace_CatalogInfo(decorID))
		b.count:SetText(stored)
		b.icon:SetDesaturated(stored == 0)
	else
		b.icon:Hide()
		b.count:SetText("")
	end
	b.key:SetText(b.slot == 0 and "last" or ns.KeyText(KeyFor(b.slot)))
end

-- Bar -----------------------------------------------------------------------------------------------------------------

local function CreateBar()
	if bar or not HouseEditorFrame then
		return
	end
	bar = CreateFrame("Frame", nil, HouseEditorFrame)
	bar:SetSize((SLOTS + 2) * (SIZE + GAP) + GAP, SIZE + 2 * GAP)
	local modeBar = HouseEditorFrame.ModeBar
	if modeBar then
		bar:SetPoint("RIGHT", modeBar, "LEFT", -BAR_GAP, 0)
	else
		bar:SetPoint("BOTTOM", -300, 24)
	end
	UI.Surface(bar, 0.5)
	local tools = CreateFrame("Button", nil, bar)
	tools:SetSize(SIZE, SIZE)
	tools:SetPoint("LEFT", GAP, 0)
	UI.Surface(tools, 0.5)
	UI.HoverWash(tools)
	tools.icon = tools:CreateTexture(nil, "ARTWORK")
	tools.icon:SetPoint("TOPLEFT", 4, -4)
	tools.icon:SetPoint("BOTTOMRIGHT", -4, 4)
	tools.icon:SetTexture(ICON_TOOLS)
	tools:SetScript("OnClick", function()
		ns.DecorateDock_Toggle()
	end)
	tools:SetScript("OnEnter", function(self)
		UI.HoverOn(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Decorating panel", UI.Color("heading"))
		UI.TipLine("Your clipboard, recent and saved decor, with export and import.", "textMuted", true)
		GameTooltip:Show()
	end)
	tools:SetScript("OnLeave", function(self)
		UI.HoverOff(self, "frame", 0.5)
		GameTooltip:Hide()
	end)
	local prev = tools
	for slot = 0, SLOTS do
		local b = CreateSlot(slot)
		b:SetPoint("LEFT", prev, "RIGHT", slot == 1 and GAP * 3 or GAP, 0)
		prev = b
	end
	bar:Hide()
end

function ns.DecorateBar_Refresh()
	if not (bar and bar:IsShown()) then
		return
	end
	for slot = 0, SLOTS do
		FillSlot(buttons[slot])
	end
end

local function Update()
	local shown = active and editing and db.bar
		and (mode == ns.DecorPlace_Mode("BasicDecor") or mode == ns.DecorPlace_Mode("ExpertDecor"))
	if shown then
		CreateBar()
	end
	if bar then
		bar:SetShown(shown == true)
	end
	if active and editing then
		events:TryWatch(OWNER, "HOUSING_STORAGE_UPDATED")
	else
		events:UnwatchAll(OWNER)
	end
	ns.DecorateBar_Refresh()
end

-- The panel's storage counts too: a placement's own redraw can come before storage has updated.
local storageChanged = UI.Debounce(STORAGE_DELAY, function()
	ns.DecorateBar_Refresh()
	ns.DecorateDock_Refresh()
end)
events:On(OWNER, "HOUSING_STORAGE_UPDATED", function()
	storageChanged()
end)

-- A slot's key: picks the slot's decor up, or puts the decor you hold on an empty slot.
function ns.DecorateBar_Press(slot)
	local decorID = db.slots[slot]
	local holding = ns.DecorPlace_Holding()
	local action = ns.DecorTools_SlotAction(decorID, holding)
	if action == "place" then
		ns.DecorateClip_Place(decorID)
	elseif action == "bind" then
		db.slots[slot] = holding
		ns.DecorPlace_CancelEditing()
		ns.DecorPlace_Note(("%s is on slot %d now"):format((ns.DecorPlace_Look(holding)), slot))
		ns.DecorateClip_Changed()
	else
		ns.DecorPlace_Error(("Slot %d is empty: hold a decor and press its key to fill it."):format(slot))
	end
end

function ns.DecorateBar_Set(slot, decorID)
	db.slots[slot] = decorID
	ns.DecorateClip_Changed()
end

-- Called by Decorate.lua --------------------------------------------------------------------------------------------

function ns.DecorateBar_Init(saved)
	db = saved
	ns.DecorateClip_Listen(ns.DecorateBar_Refresh)
end

function ns.DecorateBar_Start()
	active = true
	Update()
end

function ns.DecorateBar_Stop()
	active = false
	Update()
end

function ns.DecorateBar_Editing(on, newMode)
	editing, mode = on, newMode or 0
	Update()
end

function ns.DecorateBar_Apply()
	Update()
end
