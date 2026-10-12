local addonName, ns = ...

-- Dressing room slot bar: one button per slot along the bottom of Blizzard's dressing room (DressUpFrame), showing
-- what the model wears. Click hides or shows that piece, Shift-click links it, hover shows the item. Faint until the
-- mouse is near or something new is tried on. Reads and changes only the model's player actor
-- (GetItemTransmogInfo / UndressSlot / SetItemTransmogInfo); no Blizzard function is replaced, so the dressing room's
-- own buttons (Link, Reset, outfits) keep working untainted. Behavior studied from Narcissus; no code from it.

local UI = ns.UI

local SIZE, GAP, GROUP_GAP = 30, 3, 10
local IDLE_ALPHA = 0.35
local FADE_AFTER = 2 -- seconds without the mouse before the bar fades back
local FADE_SPEED = 4 -- alpha per second
local BAR_MARGIN = 8 -- room left at each side of the model
local NO_TRANSMOG = Constants and Constants.Transmog and Constants.Transmog.NoTransmogID or 0
local HIDDEN_MARK = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

ns.DressUp_Events = ns.NewEvents() -- the module's event frame (DressUp.lua, Tools.lua)

local BAR = {}
ns.DressUpBar = BAR

local bar
local buttons = {}
local hidden = {} -- [slot] = the ItemTransmogInfo taken off by a click, to put back
local activeAt = 0 -- last time something happened (try-on, hover)
local dirty = false

local function Actor()
	local scene = DressUpFrame and DressUpFrame.ModelScene
	return scene and scene:GetPlayerActor()
end

function BAR.Actor()
	return Actor()
end

local function Wearing(slot)
	local actor = Actor()
	if not actor then
		return nil
	end
	local ok, info = pcall(actor.GetItemTransmogInfo, actor, slot)
	if ok and info and info.appearanceID and info.appearanceID ~= NO_TRANSMOG then
		return info
	end
	return nil
end
BAR.Wearing = Wearing

-- The item link of an appearance source (itemModifiedAppearanceID), or nil.
function BAR.SourceLink(sourceID)
	local info = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
	if type(info) == "table" then
		return info.itemLink
	end
	return select(6, C_TransmogCollection.GetAppearanceSourceInfo(sourceID))
end

local function SlotName(slot)
	return _G[ns.DRESSUP_SLOT_NAMES[slot]] or ""
end
BAR.SlotName = SlotName

-- Buttons ------------------------------------------------------------------------------------------------------------

local function OnEnter(self)
	activeAt = GetTime()
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local info = hidden[self.slot] or Wearing(self.slot)
	local link = info and BAR.SourceLink(info.appearanceID)
	if link then
		GameTooltip:SetHyperlink(link)
	else
		GameTooltip:AddLine(SlotName(self.slot), 1, 1, 1)
	end
	if info then
		GameTooltip:AddLine(UI.Wrap(hidden[self.slot] and "Click to show it again" or "Click to hide it", "textMuted"))
	end
	GameTooltip:Show()
end

local function OnLeave()
	GameTooltip:Hide()
end

local function OnClick(self)
	local actor = Actor()
	if not actor then
		return
	end
	local slot = self.slot
	if IsModifiedClick("CHATLINK") then
		local info = hidden[slot] or Wearing(slot)
		UI.InsertLink(info and BAR.SourceLink(info.appearanceID))
		return
	end
	if hidden[slot] then
		actor:SetItemTransmogInfo(hidden[slot], slot, slot ~= INVSLOT_MAINHAND)
		hidden[slot] = nil
	else
		local info = Wearing(slot)
		if not info then
			return
		end
		hidden[slot] = info
		actor:UndressSlot(slot)
	end
	BAR.Refresh()
	OnEnter(self)
end

local function CreateButton(slot)
	local b = CreateFrame("Button", nil, bar)
	b:SetSize(SIZE, SIZE)
	b.slot = slot
	b:RegisterForClicks("LeftButtonUp")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.RGBA("frameDark", 0.8))
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	UI.Border(b, "frame", 0.7)
	b.mark = b:CreateTexture(nil, "OVERLAY")
	b.mark:SetTexture(HIDDEN_MARK)
	b.mark:SetSize(SIZE * 0.6, SIZE * 0.6)
	b.mark:SetPoint("CENTER")
	b.known = b:CreateTexture(nil, "OVERLAY")
	b.known:SetColorTexture(1, 1, 1, 1)
	b.known:SetSize(5, 5)
	b.known:SetPoint("BOTTOMRIGHT", -2, 2)
	b.known:SetVertexColor(UI.RGBA("success"))
	b:SetScript("OnEnter", OnEnter)
	b:SetScript("OnLeave", OnLeave)
	b:SetScript("OnClick", OnClick)
	return b
end

local function Fade(self, elapsed)
	local target = IDLE_ALPHA
	if self:IsMouseOver(8, -8, -8, 8) or GetTime() - activeAt < FADE_AFTER then
		target = 1
	end
	local alpha = self:GetAlpha()
	if alpha < target then
		self:SetAlpha(math.min(target, alpha + elapsed * FADE_SPEED))
	elseif alpha > target then
		self:SetAlpha(math.max(target, alpha - elapsed * FADE_SPEED))
	end
	if dirty then
		dirty = false
		BAR.Refresh()
	end
end

local function Create()
	bar = CreateFrame("Frame", nil, DressUpFrame)
	bar:SetFrameLevel(DressUpFrame.ModelScene:GetFrameLevel() + 10)
	local x = 0
	for _, slot in ipairs(ns.DRESSUP_SLOTS) do
		if slot then
			local b = CreateButton(slot)
			b:SetPoint("LEFT", bar, "LEFT", x, 0)
			buttons[#buttons + 1] = b
			x = x + SIZE + GAP
		else
			x = x + GROUP_GAP - GAP
		end
	end
	bar:SetSize(x - GAP, SIZE)
	bar:SetPoint("BOTTOM", DressUpFrame.ModelScene, "BOTTOM", 0, 10)
	-- Narrower than the model, whatever its size: the bar shrinks to fit (its anchor offset scales with it).
	local function Fit()
		local room = DressUpFrame.ModelScene:GetWidth() - 2 * BAR_MARGIN
		local width = bar:GetWidth()
		if room > 0 and width > 0 then
			bar:SetScale(math.min(1, room / width))
		end
	end
	DressUpFrame.ModelScene:HookScript("OnSizeChanged", Fit)
	bar.Fit = Fit
	bar:SetAlpha(IDLE_ALPHA)
	bar:SetScript("OnUpdate", Fade)
	bar:Hide()
end

-- Showing ------------------------------------------------------------------------------------------------------------

function BAR.Refresh()
	if not (bar and bar:IsShown()) then
		return
	end
	for _, b in ipairs(buttons) do
		local slot = b.slot
		local off = hidden[slot]
		local info = off or Wearing(slot)
		local id = info and info.appearanceID
		if id then
			b.icon:SetTexture(C_TransmogCollection.GetSourceIcon(id))
			b.icon:SetDesaturated(off ~= nil)
			b.icon:SetAlpha(off and 0.5 or 1)
			local source = C_TransmogCollection.GetSourceInfo(id)
			b.known:SetShown(source ~= nil and source.isCollected == true and not off)
		else
			b.icon:SetTexture(select(2, GetInventorySlotInfo(ns.DRESSUP_SLOT_NAMES[slot])))
			b.icon:SetDesaturated(true)
			b.icon:SetAlpha(0.4)
			b.known:Hide()
		end
		b.mark:SetShown(off ~= nil)
	end
end

-- Only for the player model (not mounts or pets), and only when the setting is on.
function BAR.Update(on)
	if not DressUpFrame then
		return
	end
	if not bar then
		if not on then
			return
		end
		Create()
	end
	local show = on and DressUpFrame:IsShown() and DressUpFrame:GetMode() == "player" and Actor() ~= nil
	bar:SetShown(show)
	bar.Fit()
	BAR.Refresh()
end

-- Something was tried on or taken off: a piece put on again isn't hidden anymore.
function BAR.OnDressModel(_, _, invSlot, removed)
	activeAt = GetTime()
	if invSlot and not removed then
		hidden[invSlot] = nil
	end
	dirty = true -- refreshed on the next frame, once the actor has it
end

-- A fresh start (window opened, Reset): nothing is hidden.
function BAR.Reset()
	wipe(hidden)
	activeAt = GetTime()
	dirty = true
end

function BAR.IsHidden(slot)
	return hidden[slot] ~= nil
end
