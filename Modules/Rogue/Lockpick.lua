local addonName, ns = ...

-- Rogue, Handy Lockpick: right-click a locked lockbox in your bags (or in the trade window's "will not be traded"
-- slot) to pick it with Pick Lock or the Mechagnome racial. Casting needs a secure button and a real click, so a
-- secure button is laid over the hovered slot for as long as the mouse is on it; it only takes right-clicks (left
-- clicks pass through to the bag slot). Out of combat only: the button is made lazily out of combat and hidden on
-- PLAYER_REGEN_DISABLED. Started and fed events by Rogue.lua; pure checks and macros in Data.lua.

local OVERLAY_CHECK = 0.1 -- seconds between checks that the slot under the button is still shown
local SAME_SLOT = 0.5 -- seconds: a slot's tooltip is set again every frame while hovered; read it at most this often
local AFTER_CAST = 1 -- seconds a just-picked slot is left alone (its tooltip says "Locked" a moment longer)
local TRADE_SLOT_BUTTON = "TradeRecipientItem%dItemButton" -- Blizzard's trade window (TradeFrame.xml)
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local UI = ns.UI
local IsSecret = ns.IsSecret
local P = Enum.PlayerInteractionType
-- Windows where right-clicking a bag item already does something (sell, deposit, attach, trade, post, ...).
local BUSY_WINDOWS = { "Merchant", "Banker", "GuildBanker", "MailInfo", "TradePartner", "Auctioneer",
	"VoidStorageBanker", "ScrappingMachine", "ItemUpgrade", "CharacterBanker", "AccountBanker" }

local enabled = false
local hooked = false
local spellID -- the lock-picking spell this character knows
local overlay
local last = { key = nil, at = 0 } -- the slot read last, so a hovered slot isn't read every frame
local picked = { key = nil, at = 0 } -- the slot just picked

local function SlotKey(bag, slot)
	return bag and (bag .. ":" .. slot) or "trade"
end

local function BagWindowBusy()
	for _, name in ipairs(BUSY_WINDOWS) do
		local kind = P[name]
		if kind and C_PlayerInteractionManager.IsInteractingWithNpcOfType(kind) then
			return true
		end
	end
	return false
end

local function CanShow()
	return enabled and spellID and not InCombatLockdown() and not GetCursorInfo() and not SpellIsTargeting()
		and C_SpellBook.IsSpellKnown(spellID)
end

-- Tooltip lines as plain { text, r, g, b } for Rogue_LockState; nil when a line can't be read.
local function Lines(data)
	if not (data and data.lines) then
		return nil
	end
	local lines = {}
	for i, line in ipairs(data.lines) do
		local text = line.leftText
		if IsSecret(text) then
			return nil
		end
		local color = line.leftColor
		local r, g, b
		if color and color.GetRGB then
			r, g, b = color:GetRGB()
		end
		lines[i] = { text = text, r = r, g = g, b = b }
	end
	return lines
end

local function Pickable(data)
	local lines = Lines(data)
	return lines ~= nil and ns.Rogue_LockState(lines, LOCKED) == "pickable"
end

-- The button ----------------------------------------------------------------------------------------------------

local function Hide()
	if overlay and overlay:IsShown() and not InCombatLockdown() then
		overlay:Hide()
	end
end

local function OverlayOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.bag then
		GameTooltip:SetBagItem(self.bag, self.slot)
	else
		GameTooltip:SetTradeTargetItem(TRADE_ENCHANT_SLOT)
	end
	local name = C_Spell.GetSpellName(spellID) or "Pick Lock"
	GameTooltip:AddLine("Right-click: " .. name, UI.RGB("accent"))
	GameTooltip:Show()
end

local function OverlayOnLeave()
	GameTooltip_Hide()
	Hide()
end

local sinceCheck = 0
local function OverlayOnUpdate(self, elapsed)
	sinceCheck = sinceCheck + elapsed
	if sinceCheck < OVERLAY_CHECK then
		return
	end
	sinceCheck = 0
	local owner = self.owner
	if not (owner and owner:IsVisible()) or GetCursorInfo() then
		Hide()
	end
end

local function CreateOverlay()
	overlay = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	overlay:SetIgnoreParentScale(true)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	overlay:RegisterForClicks("RightButtonUp")
	overlay:SetAttribute("useOnKeyDown", false)
	overlay:SetAttribute("type2", "macro")
	-- Left clicks (and drags) reach the bag slot underneath. Restricted: out of combat only, like everything here.
	overlay:SetPassThroughButtons("LeftButton")
	overlay:SetHighlightTexture(HIGHLIGHT, "ADD")
	overlay:SetScript("OnEnter", OverlayOnEnter)
	overlay:SetScript("OnLeave", OverlayOnLeave)
	overlay:SetScript("OnUpdate", ns.Perf_Wrap(OverlayOnUpdate, "OnUpdate"))
	overlay:Hide()
end

-- Lays the button over owner (the hovered slot) in UIParent coordinates: a protected frame can't be anchored to
-- an ordinary one. Its scale is the slot's, so the slot's own coordinates place it.
local function ShowOver(owner, bag, slot)
	if not overlay then
		CreateOverlay()
	end
	local x, y = owner:GetCenter()
	if not x then
		return
	end
	local name = C_Spell.GetSpellName(spellID)
	if not name then
		return
	end
	local macro
	if bag then
		macro = ns.Rogue_LockpickMacro(name, bag, slot)
	else
		macro = ns.Rogue_LockpickTradeMacro(name, TRADE_SLOT_BUTTON:format(TRADE_ENCHANT_SLOT))
	end
	overlay:SetAttribute("macrotext2", macro)
	overlay.bag, overlay.slot, overlay.owner = bag, slot, owner
	overlay:ClearAllPoints()
	overlay:SetScale(owner:GetEffectiveScale())
	overlay:SetSize(owner:GetSize())
	overlay:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	sinceCheck = 0
	overlay:Show()
end

-- Tooltip hooks ---------------------------------------------------------------------------------------------------

-- The frame a tooltip was set for, when it's a slot under the mouse (not our own button, nor a tooltip some code
-- set for a frame elsewhere), and the button isn't already up.
local function HoveredOwner(tooltip)
	local owner = tooltip:GetOwner()
	if not owner or owner == overlay or (overlay and overlay:IsShown()) or not owner:IsMouseOver() then
		return nil
	end
	return owner
end

-- Whether this slot was read a moment ago (or just picked): nothing new to decide.
local function Recent(key)
	local now = GetTime()
	if picked.key == key and now - picked.at < AFTER_CAST then
		return true
	end
	if last.key == key and now - last.at < SAME_SLOT then
		return true
	end
	last.key, last.at = key, now
	return false
end

local function OnSetBagItem(tooltip, bag, slot)
	if not CanShow() or type(bag) ~= "number" or type(slot) ~= "number" then
		return
	end
	local owner = HoveredOwner(tooltip)
	if not owner or Recent(SlotKey(bag, slot)) or BagWindowBusy() then
		return
	end
	if Pickable(C_TooltipInfo.GetBagItem(bag, slot)) then
		ShowOver(owner, bag, slot)
	end
end

local function OnSetTradeTargetItem(tooltip, index)
	if not CanShow() or index ~= TRADE_ENCHANT_SLOT then
		return
	end
	local owner = HoveredOwner(tooltip)
	if not owner or Recent(SlotKey()) then
		return
	end
	if Pickable(C_TooltipInfo.GetTradeTargetItem(index)) then
		ShowOver(owner)
	end
end

-- Called by Rogue.lua ---------------------------------------------------------------------------------------------

-- id: Pick Lock or the Mechagnome racial, whichever this character has. The hooks can't be removed: they do
-- nothing until the next Start once Stop has run.
function ns.RogueLock_Start(id)
	spellID = id
	enabled = true
	if not hooked then
		hooked = true
		hooksecurefunc(GameTooltip, "SetBagItem", OnSetBagItem)
		hooksecurefunc(GameTooltip, "SetTradeTargetItem", OnSetTradeTargetItem)
	end
end

function ns.RogueLock_Stop()
	enabled = false
	last.key, picked.key = nil, nil
	Hide()
end

-- PLAYER_REGEN_DISABLED (the last moment the button can be hidden), CURSOR_CHANGED (an item picked up) and
-- TRADE_TARGET_ITEM_CHANGED.
function ns.RogueLock_Hide()
	Hide()
end

-- UNIT_SPELLCAST_SUCCEEDED on the player: the lock is open, the button goes and the slot is left alone a moment.
function ns.RogueLock_OnCast(castID)
	if not enabled or castID ~= spellID or not (overlay and overlay:IsShown()) then
		return
	end
	picked.key, picked.at = SlotKey(overlay.bag, overlay.slot), GetTime()
	Hide()
end
