local addonName, ns = ...

-- Dressing room, restore transmog changes: Blizzard's transmogrifier (TransmogFrame, Blizzard_Transmog) throws away
-- changes you haven't applied when it closes. While it's open, the pending changes are noted on every slot refresh;
-- on close the last note is kept, and when it opens again on the same outfit a "Restore last changes" button puts
-- them back as pending (you still click Apply and pay). Only hooks and C_TransmogOutfitInfo calls Blizzard's own
-- buttons make; nothing of Blizzard's is replaced. Pure list in Data.lua (DressUp_PendingChanges); registered in
-- DressUp.lua.

local OWNER = "dressupRestore"
-- Next to Blizzard's "clear all pending" button (TOPRIGHT -21, -134, 36 px, Blizzard_Transmog.xml), vertically
-- centered on it.
local BUTTON_X, BUTTON_Y = -63, -142

local UI = ns.UI
local PendingChanges = ns.DressUp_PendingChanges
local events = ns.DressUp_Events

local module, db
local hooked = false
local live -- the changes pending right now, noted while the window is open
local saved -- what was pending when it last closed: { outfitID, secondary, list }
local button

local function On()
	return module and module.active and db.restore
end

local function Shown()
	return TransmogFrame and TransmogFrame:IsShown()
end

local function RightShoulder()
	return Enum.TransmogOutfitSlot.ShoulderRight
end

-- Armor slots have one option; weapon slots one per weapon kind (one-handed, two-handed, ...), each with its own
-- pending appearance.
local function Options(slot)
	if not C_TransmogOutfitInfo.IsSlotWeaponSlot(slot) then
		return { Enum.TransmogOutfitSlotOption.None }
	end
	local options = {}
	local weapons, artifacts = C_TransmogOutfitInfo.GetWeaponOptionsForSlot(slot)
	for _, list in ipairs({ weapons or {}, artifacts or {} }) do
		for _, info in ipairs(list) do
			options[#options + 1] = info.weaponOption
		end
	end
	return options
end

local function ReadSlot(slot, kind, option)
	-- pcall: a slot and weapon option the character can't use may be refused.
	local ok, info = pcall(C_TransmogOutfitInfo.GetViewedOutfitSlotInfo, slot, kind, option)
	return ok and info or nil
end

local function Note()
	local appearance, illusion = C_TransmogOutfitInfo.GetAllSlotLocationInfo()
	local slots = {}
	for _, list in ipairs({ appearance or {}, illusion or {} }) do
		for _, info in ipairs(list) do
			slots[#slots + 1] = { slot = info.slot, type = info.type, options = Options(info.slot) }
		end
	end
	local list = PendingChanges(slots, ReadSlot)
	if not list then
		return nil
	end
	return {
		outfitID = C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID(),
		secondary = C_TransmogOutfitInfo.GetSecondarySlotState(RightShoulder()),
		list = list,
	}
end

local function UpdateButton()
	if not button then
		return
	end
	button:SetShown(On() and Shown() and saved ~= nil
		and saved.outfitID == C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID() or false)
end

local function Restore()
	local note = saved
	saved = nil
	UpdateButton()
	if not note then
		return
	end
	if C_TransmogOutfitInfo.GetSecondarySlotState(RightShoulder()) ~= note.secondary then
		C_TransmogOutfitInfo.SetSecondarySlotState(RightShoulder(), note.secondary)
	end
	local missed = 0
	for _, c in ipairs(note.list) do
		-- pcall: an appearance can stop fitting (another weapon equipped since).
		if not pcall(C_TransmogOutfitInfo.SetPendingTransmog, c.slot, c.type, c.option, c.transmogID,
			c.displayType) then
			missed = missed + 1
		end
	end
	if missed > 0 then
		ns.Print(("%d of your last changes no longer fit and were left out."):format(missed))
	end
end

local function CreateButton()
	local preview = TransmogFrame.CharacterPreview
	button = UI.Button(preview or TransmogFrame, 150, "Restore last changes")
	UI.FitButton(button, 120)
	button:SetFrameLevel((preview or TransmogFrame):GetFrameLevel() + 100)
	if preview then
		button:SetPoint("RIGHT", preview, "TOPRIGHT", BUTTON_X, BUTTON_Y)
	else
		button:SetPoint("TOP", TransmogFrame, "TOP", 0, -40)
	end
	button:SetScript("OnClick", Restore)
	button:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		UI.TipLine("Restore last changes", "heading")
		UI.TipLine("Puts back the changes you hadn't applied when you last closed this window. Apply still keeps "
			.. "them.", "text", true)
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", GameTooltip_Hide)
	button:Hide()
end

local function OnRefresh()
	if On() and Shown() then
		live = Note()
	end
end

local function Hook()
	if hooked or not TransmogFrame then
		return
	end
	hooked = true -- hooks can't be undone: each checks On()
	CreateButton()
	-- Besides the slot refresh event: every way Blizzard's window changes what's pending.
	for _, name in ipairs({ "SetPendingTransmog", "RevertPendingTransmog", "ClearAllPendingTransmogs",
		"SetOutfitToCustomSet", "SetOutfitToSet", "SetOutfitToOutfit" }) do
		if C_TransmogOutfitInfo[name] then
			hooksecurefunc(C_TransmogOutfitInfo, name, OnRefresh)
		end
	end
	TransmogFrame:HookScript("OnShow", function()
		live = nil
		UpdateButton()
	end)
	-- Blizzard's own OnHide has just cleared the pending changes: the note from the last refresh is what they were.
	TransmogFrame:HookScript("OnHide", function()
		if On() then
			saved = live
		end
		live = nil
		UpdateButton()
	end)
end

events:On(OWNER, "VIEWED_TRANSMOG_OUTFIT_SLOT_REFRESH", OnRefresh)
events:On(OWNER, "VIEWED_TRANSMOG_OUTFIT_CHANGED", function()
	OnRefresh()
	UpdateButton()
end)

function ns.DressUp_RestoreInit(mod, settings)
	module, db = mod, settings
end

-- On toggle and when the setting changes.
function ns.DressUp_RestoreUpdate()
	if On() then
		events:Watch(OWNER, "VIEWED_TRANSMOG_OUTFIT_SLOT_REFRESH")
		events:Watch(OWNER, "VIEWED_TRANSMOG_OUTFIT_CHANGED")
		if not hooked then
			EventUtil.ContinueOnAddOnLoaded("Blizzard_Transmog", Hook)
		end
	else
		events:UnwatchAll(OWNER)
		live, saved = nil, nil
	end
	UpdateButton()
end
