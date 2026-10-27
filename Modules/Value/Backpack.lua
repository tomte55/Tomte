local addonName, ns = ...

-- Gold & value: the backpack item tracker. Items you track (/tomte value track, or the settings list), your
-- holiday's token while the holiday is on, and your expansion's upgrade crests, each with your count, on the bag's
-- currency bar next to the currencies Blizzard tracks there. Our own small buttons laid over the bar's free left side
-- (Blizzard's token frame isn't resized or refilled); with no tracked currency the bar is hidden, so they go on the
-- left of the gold line instead. Zero counts are left out. Choices in Data.lua; switched and refreshed from Value.lua
-- (ns.ValueBackpack_Toggle, ns.ValueBackpack_Refresh). Blizzard's bags only: Baganator and others replace them. Tomte's own bags draw the same entries in their
-- footer (ns.ValueBackpack_Entries).

local ICON = 12 -- Blizzard's token icon size (BackpackTokenTemplate)
local GAP = 2 -- between a count and its icon
local SPACING = 8 -- between buttons
local PAD = 6 -- from the bar's left edge
local TOKEN_RIGHT = 17 -- Blizzard's rightmost token's inset from the bar's right edge (GetInitialTokenAnchor)
local CONTAINERS = { "ContainerFrameCombinedBags", "ContainerFrame1" }
local COINS = { "GoldButton", "SilverButton", "CopperButton" }
local MAX_WATCHED = 30 -- a bound for reading Blizzard's tracked currencies (the bar shows far fewer)

local UI = ns.UI

local db
local active = false
local hooked = false
local strip, buttons = nil, {}
local queued = false

-- Reading the game -------------------------------------------------------------------------------------------------

-- The holidays on now, from Holidays & events when it's on: { [key] = true }.
local function ActiveHolidays()
	local holidays = {}
	local events = ns.modulesByKey.events
	if not (db.holidays and events and events.active and ns.Events_Current) then
		return holidays
	end
	local state = ns.HomeCall(ns.Events_Current)
	for _, ev in ipairs(state and state.all or {}) do
		if ev.active and ev.def and ev.def.key then
			holidays[ev.def.key] = true
		end
	end
	return holidays
end

-- This season's crests (the newest set your expansion's data lists), lowest tier first.
local function Crests()
	if not db.crests then
		return nil
	end
	local sets = ns.Content_Get(ns.ContentExpansion(), "crests")
	return sets and sets[1] and sets[1].ids or nil
end

local function Watched()
	local watched = {}
	for i = 1, MAX_WATCHED do
		local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
		if not info then
			break
		end
		watched[info.currencyTypesID] = true
	end
	return watched
end

local function Count(kind, id)
	if kind == "currency" then
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		return info and info.quantity or 0
	end
	return C_Item.GetItemCount(id)
end

local function Icon(entry)
	if entry.kind == "currency" then
		local info = C_CurrencyInfo.GetCurrencyInfo(entry.id)
		return info and info.iconFileID
	end
	return C_Item.GetItemIconByID(entry.id)
end

-- Where the buttons go: Blizzard's token bar when it shows, else the gold line. Returns the frame and the width free
-- on its left, or nil while the bags are closed.
local function Host()
	local manager = ContainerFrameSettingsManager
	local owner = manager and manager.TokenTrackerOwner
	if not (owner and owner:IsShown()) then
		return nil
	end
	local tokens = BackpackTokenFrame
	if tokens and tokens:IsShown() and tokens:GetParent() == owner and tokens:GetLeft() then
		local right = tokens:GetRight() - TOKEN_RIGHT
		for _, button in pairs(tokens.Tokens or {}) do
			if button:IsShown() and button:GetLeft() then
				right = math.min(right, button:GetLeft())
			end
		end
		return tokens, right - tokens:GetLeft() - PAD - SPACING
	end
	local money = owner.MoneyFrame
	if not (money and money:IsShown() and money:GetLeft()) then
		return nil
	end
	local right = money:GetRight()
	for _, key in ipairs(COINS) do
		local coin = money[key]
		if coin and coin:IsShown() and coin:GetLeft() then
			right = math.min(right, coin:GetLeft())
		end
	end
	return money, right - money:GetLeft() - PAD - SPACING
end

-- Buttons ----------------------------------------------------------------------------------------------------------

local function OnEnter(self)
	local entry = self.entry
	if not entry then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if entry.kind == "currency" then
		GameTooltip:SetCurrencyByID(entry.id)
	else
		GameTooltip:SetItemByID(entry.id)
	end
	if entry.tracked then
		UI.TipLine("Right-click: stop showing it here", "textMuted")
	end
	GameTooltip:Show()
end

local function OnLeave()
	GameTooltip:Hide()
end

local function OnClick(self, button)
	local entry = self.entry
	if not entry then
		return
	end
	if button == "RightButton" and entry.tracked then
		ns.ValueBackpack_Track(entry.id)
	elseif IsModifiedClick("CHATLINK") then
		if entry.kind == "currency" then
			UI.InsertLink(C_CurrencyInfo.GetCurrencyLink(entry.id))
		else
			UI.InsertLink(select(2, C_Item.GetItemInfo(entry.id)))
		end
	end
end

-- A button showing one entry (self.entry): its tooltip, and its clicks (right-click stops tracking an item the player
-- added, a chat link with the modifier). Tomte's bag window uses the same for its footer.
ns.ValueBackpack_OnEnter = OnEnter
ns.ValueBackpack_OnClick = OnClick

local function Button(i)
	local b = buttons[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, strip)
	b:SetHeight(ICON)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(ICON, ICON)
	b.icon:SetPoint("RIGHT")
	b.count = b:CreateFontString(nil, "OVERLAY")
	b.count:SetFontObject(GameFontHighlightSmall) -- the font of Blizzard's own tokens beside it
	b.count:SetPoint("RIGHT", b.icon, "LEFT", -GAP, 0)
	b:SetScript("OnEnter", OnEnter)
	b:SetScript("OnLeave", OnLeave)
	b:SetScript("OnClick", OnClick)
	buttons[i] = b
	return b
end

local function HideAll()
	if strip then
		strip:Hide()
	end
end

-- What the bar shows, in order: { kind = "item" | "currency", id, count, icon, tracked (an item the player added) },
-- leaving out the currencies Blizzard's own bar tracks; nil while Gold & value's tracker is off. Also drawn on Tomte's
-- own bag window (Modules/Bags/Window.lua).
function ns.ValueBackpack_Entries()
	if not active then
		return nil
	end
	local tracked = ns.Value_ParseItems(db.items)
	local isTracked = {}
	for _, id in ipairs(tracked) do
		isTracked[id] = true
	end
	local entries = ns.Value_BackpackEntries({
		items = tracked, holidays = ActiveHolidays(), crests = Crests(), watched = Watched(), count = Count,
	})
	for _, entry in ipairs(entries) do
		entry.tracked = entry.kind == "item" and isTracked[entry.id] or nil
		entry.icon = Icon(entry)
	end
	return entries
end

local function Layout()
	queued = false
	if not active then
		HideAll()
		return
	end
	local host, free = Host()
	if not host or free <= 0 then
		HideAll()
		return
	end
	local entries = ns.ValueBackpack_Entries()
	if not strip then
		strip = CreateFrame("Frame")
		strip:SetSize(1, ICON)
	end
	strip:SetParent(host)
	strip:SetFrameLevel(host:GetFrameLevel() + 5)
	strip:ClearAllPoints()
	strip:SetPoint("LEFT", host, "LEFT", PAD, 0)
	local x, shown = 0, 0
	for _, entry in ipairs(entries) do
		local b = Button(shown + 1)
		b.entry = entry
		b.icon:SetTexture(entry.icon)
		b.count:SetText(ns.Thousands(entry.count))
		local width = b.count:GetStringWidth() + GAP + ICON
		if x + width > free then
			break
		end
		b:SetWidth(width)
		b:ClearAllPoints()
		b:SetPoint("LEFT", strip, "LEFT", x, 0)
		b:Show()
		x = x + width + SPACING
		shown = shown + 1
	end
	for i = shown + 1, #buttons do
		buttons[i]:Hide()
		buttons[i].entry = nil
	end
	strip:SetWidth(math.max(x, 1))
	strip:SetShown(shown > 0)
end

-- Next frame: Blizzard lays its tokens and gold line out first.
function ns.ValueBackpack_Refresh()
	if active and not queued then
		queued = true
		C_Timer.After(0, Layout)
	end
	if ns.BagsWindow_RefreshFooter then
		ns.BagsWindow_RefreshFooter()
	end
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	for _, name in ipairs(CONTAINERS) do
		local frame = _G[name]
		if frame then
			frame:HookScript("OnShow", ns.ValueBackpack_Refresh)
			if frame.UpdateCurrencyFrames then
				hooksecurefunc(frame, "UpdateCurrencyFrames", ns.ValueBackpack_Refresh)
			end
		end
	end
end

-- Track ------------------------------------------------------------------------------------------------------------

-- Adds an item to the tracked list or takes it off. Returns true when it was added.
function ns.ValueBackpack_Track(itemID)
	local added
	db.items, added = ns.Value_ToggleItem(db.items, itemID)
	local name = C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
	ns.Print(added and ("%s shows on the bag's currency bar."):format(name)
		or ("%s no longer shows on the bag's currency bar."):format(name))
	ns.ValueBackpack_Refresh()
	return added
end

function ns.ValueBackpack_Toggle(on, saved)
	db = saved
	active = on and true or false
	if active then
		Hook()
		ns.ValueBackpack_Refresh()
	else
		HideAll()
		if ns.BagsWindow_RefreshFooter then
			ns.BagsWindow_RefreshFooter()
		end
	end
end
