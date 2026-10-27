local addonName, ns = ...

-- Bags: the bag window, built from Kit.lua as one case: a header band (bag slots and characters, the title, the search
-- sunk into the band with its "?", saved searches, sort, settings, close), the items in a tray (View.lua draws them
-- in categories or as one bag) and a footer band (currencies, free slots with a fill meter, tracked currencies and
-- Gold & value's items, gold). The equipped bags stand as tabs on the top edge. Another character's bags can be looked at (Item counts' record, display only).
-- Opened and closed by Takeover.lua following Blizzard's bag state; registered in Bags.lua.

local PAD = 8 -- window edge to the tray, and the tray to the bands
local TRAY_PAD = 8 -- tray edge to the items
local MIN_W = 460 -- the header band's clusters, title and a usable search box fit at any column count
local BAND_H = 34 -- the header band
local FOOT_H = 30 -- the footer band
local SLOT_SIZE = 32 -- an equipped bag's tab on the top edge
local SLOT_GAP = 2
local SLOTS_LEFT = 12 -- the first bag tab from the window's left edge
local METER_W = 60
local TITLE_MAX_W = 150 -- the title ("Bags: <name>") never squeezes the search box
local HOVER_POLL = 0.1 -- seconds between mouse checks while the clusters show only on hover
local ICON_SIZE = 12 -- footer currency icons
-- The equipped bag slots: bags 1-4 and the reagent bag (Enum.BagIndex), shown in the bag slots row.
local EQUIPPED = { 1, 2, 3, 4, 5 }
local COIN_ICONS = {
	gold = "%s|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "%s|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "%s|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

local UI = ns.UI

local db
local frame, header, tray, body, search, footer, title, view, leftCluster, rightCluster
local viewChar -- another character's GUID while looking at their bags (Item counts' record), nil for yours
local matcher -- the compiled search, nil for none
local matcherText = false -- the search has words, which also look in the tooltip text
local queued, footerQueued = false, false
local showSlots = false
local holding = false -- a window that takes items is open: items keep their places (ns.BagsWindow_SetHolding)
local slotTabs, coins = {}, {}
local DrawSlots -- the bag slots row (below), redrawn with the window

-- Pools ------------------------------------------------------------------------------------------------------------

local function Pooled(pool, i, make)
	local item = pool[i]
	if not item then
		item = make()
		pool[i] = item
	end
	return item
end

-- Drawing ----------------------------------------------------------------------------------------------------------

-- The open window that takes items from the bags, for Data.lua's Bags_Fits: the ones Blizzard's item context
-- matching doesn't cover (it does the scrapper, sockets, upgrades and the catalyst itself).
local function Situation()
	if ns.BagsBank_ActiveType and ns.BagsBank_ActiveType() == Enum.BankType.Account then
		return "warband"
	elseif TradeFrame and TradeFrame:IsShown() then
		return "trade"
	elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		return "auction"
	elseif MailFrame and MailFrame:IsShown() then
		return "mail"
	elseif MerchantFrame and MerchantFrame:IsShown() then
		return "merchant"
	end
	return nil
end

-- Bright, or faded by the search or because it can't go into the open window (situation, when that look is on).
local function Matches(item, situation)
	if item.empty then
		return true
	end
	if situation == "warband" and item.warbandOK == nil and item.bag then
		item.warbandOK = C_Bank.IsItemAllowedInBankType(Enum.BankType.Account,
			ItemLocation:CreateFromBagAndSlot(item.bag, item.slot)) == true
	end
	if not ns.Bags_Fits(item, situation) then
		return false
	end
	if not matcher then
		return true
	end
	return item.readable ~= false and matcher(item) == true
end

-- Button options for Buttons.lua's paint, from the settings.
local function PaintOptions()
	local looks = db.looks
	return {
		corners = db.corners, ilvlColor = db.ilvlColor, fontSize = looks.fontSize, newGlow = looks.newGlow,
		greyJunk = looks.greyJunk, redUnusable = looks.redUnusable, context = looks.context,
	}
end
ns.BagsWindow_PaintOptions = PaintOptions

local function Draw()
	queued = false
	if not (frame and frame:IsShown()) then
		return
	end
	local items, pending
	if viewChar then
		items = ns.BagsRead_FromList(ns.Counts_CharItems and ns.Counts_CharItems(viewChar, "bags") or {})
	else
		items, pending = ns.BagsRead_Bags()
	end
	if matcher and matcherText then
		ns.BagsRead_LoadText(items)
	end
	local situation = not viewChar and db.looks.context and Situation() or nil
	local n = 0
	local width, height = view:Draw(items, {
		layout = ns.Bags_Layout(), place = "bags", holding = holding and not viewChar, paint = PaintOptions(),
		matches = function(item)
			return Matches(item, situation)
		end,
		button = viewChar and function()
			n = n + 1
			return ns.BagsButtons_GetView(body, n)
		end or nil,
	})
	DrawSlots()
	local w = math.max(width + 2 * (PAD + TRAY_PAD), MIN_W)
	frame:SetSize(w, BAND_H + PAD + 2 * TRAY_PAD + height + PAD + FOOT_H)
	if pending or viewChar then
		-- Some items' data is still on its way (another character's often is): GET_ITEM_INFO_RECEIVED redraws
		-- (Bags.lua).
		frame.pending = true
	end
	ns.BagsWindow_RefreshFooter()
end

-- Footer -----------------------------------------------------------------------------------------------------------

local function Coin(i)
	return Pooled(coins, i, function()
		local b = CreateFrame("Button", nil, footer)
		b:SetHeight(ICON_SIZE)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(ICON_SIZE, ICON_SIZE)
		b.icon:SetPoint("RIGHT")
		b.count = UI.Text(b, 11, "text", "number")
		b.count:SetPoint("RIGHT", b.icon, "LEFT", -2, 0)
		b:SetScript("OnEnter", function(self)
			ns.ValueBackpack_OnEnter(self)
		end)
		b:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		b:SetScript("OnClick", function(self, button)
			ns.ValueBackpack_OnClick(self, button)
		end)
		return b
	end)
end

-- The game's tracked currencies, then Gold & value's entries (when that tracker is on).
local function FooterEntries()
	local entries = {}
	for i = 1, 30 do
		local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
		if not info then
			break
		end
		entries[#entries + 1] = { kind = "currency", id = info.currencyTypesID, count = info.quantity,
			icon = info.iconFileID }
	end
	local valueEntries = ns.ValueBackpack_Entries and ns.ValueBackpack_Entries()
	for _, entry in ipairs(valueEntries or {}) do
		entries[#entries + 1] = entry
	end
	return entries
end

-- Free slots and all slots of the backpack, bags 1-4 and the reagent bag.
local function FreeSlots()
	local free, total = 0, 0
	for bag = 0, 5 do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
		total = total + (C_Container.GetContainerNumSlots(bag) or 0)
	end
	return free, total
end

local function DrawFooter()
	footerQueued = false
	if not (frame and frame:IsShown()) then
		return
	end
	local free, total = FreeSlots()
	footer.free:SetText(free == 1 and "1 free slot" or ("%s free slots"):format(ns.Thousands(free)))
	footer.meter:SetValue(total > 0 and (total - free) / total or 0)
	footer.gold:SetText(ns.Coins(GetMoney(), "exact", COIN_ICONS))
	local meterRight, footerLeft = footer.meter:GetRight(), footer:GetLeft()
	local x, shown = (meterRight and footerLeft) and (meterRight - footerLeft + 14) or 180, 0 -- before the first layout
	local right = footer:GetWidth() - footer.gold:GetStringWidth() - 14
	for _, entry in ipairs(FooterEntries()) do
		local b = Coin(shown + 1)
		b.entry = entry
		b.icon:SetTexture(entry.icon)
		b.count:SetText(ns.Thousands(entry.count or 0))
		local w = b.count:GetStringWidth() + 2 + ICON_SIZE
		if x + w > right then
			break
		end
		b:SetWidth(w)
		b:ClearAllPoints()
		b:SetPoint("LEFT", footer, "LEFT", x, 0)
		b:Show()
		x = x + w + 8
		shown = shown + 1
	end
	for i = shown + 1, #coins do
		coins[i]:Hide()
		coins[i].entry = nil
	end
end

function ns.BagsWindow_RefreshFooter()
	if frame and frame:IsShown() and not footerQueued then
		footerQueued = true
		C_Timer.After(0, DrawFooter)
	end
end

-- Bag slots row ----------------------------------------------------------------------------------------------------

local function SlotTab(i)
	return Pooled(slotTabs, i, function()
		local b = ns.BagsKit_Tab(frame, SLOT_SIZE, "top")
		b:RegisterForDrag("LeftButton")
		b.free = b:CreateFontString(nil, "OVERLAY")
		UI.SetFont(b.free, "number", 11, "OUTLINE")
		b.free:SetPoint("BOTTOMRIGHT", -3, 3)
		b:SetScript("OnEnter", function(self)
			UI.WashTo(self.hoverWash, true)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if not GameTooltip:SetInventoryItem("player", self.invID) then
				GameTooltip:SetText(self.bag == 5 and "Reagent bag slot" or "Bag slot")
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function(self)
			UI.WashTo(self.hoverWash, false)
			GameTooltip:Hide()
		end)
		local function Take(self, button)
			if button and button ~= "LeftButton" then
				return -- right-click does nothing here (it would pick the bag up)
			end
			if CursorHasItem() then
				PutItemInBag(self.invID)
			else
				PickupBagFromSlot(self.invID)
			end
		end
		b:SetScript("OnClick", Take)
		b:SetScript("OnDragStart", Take)
		b:SetScript("OnReceiveDrag", Take)
		return b
	end)
end

-- The equipped bags as tabs standing on the window's top edge, each with its free slots.
function DrawSlots()
	for i, bag in ipairs(EQUIPPED) do
		local b = SlotTab(i)
		b:SetShown(showSlots)
		if showSlots then
			b.bag = bag
			b.invID = C_Container.ContainerIDToInventoryID(bag)
			local texture = GetInventoryItemTexture("player", b.invID)
			b.icon:SetTexture(texture or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
			b.icon:SetDesaturated(texture == nil)
			b.free:SetText(texture and C_Container.GetContainerNumFreeSlots(bag) or "")
			UI.SetTextRole(b.free, "text")
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", SLOTS_LEFT + (i - 1) * (SLOT_SIZE + SLOT_GAP), -1)
		end
	end
	leftCluster:SetLit(1, showSlots)
end

-- Top bar buttons ---------------------------------------------------------------------------------------------------

local hoverTicker

-- The two clusters, shown only while the mouse is over the window when that setting is on (the band stays).
local function ShowTopButtons(shown)
	if not leftCluster then
		return -- not built yet (a settings change before the bags were ever opened)
	end
	leftCluster:SetAlpha(shown and 1 or 0)
	rightCluster:SetAlpha(shown and 1 or 0)
end

-- While "buttons on hover" is on and the window is open: a light poll of the mouse (the window's children take the
-- mouse, so its own OnEnter/OnLeave can't tell).
local function UpdateHover()
	if hoverTicker then
		hoverTicker:Cancel()
		hoverTicker = nil
	end
	if not (frame and frame:IsShown() and db.buttonsOnHover) then
		ShowTopButtons(true)
		return
	end
	ShowTopButtons(frame:IsMouseOver())
	hoverTicker = C_Timer.NewTicker(HOVER_POLL, function()
		ShowTopButtons(frame:IsMouseOver())
	end)
end

-- Dropping items ---------------------------------------------------------------------------------------------------

-- Bag IDs a dropped item may go to, tried in order: the reagent bag first for crafting reagents (it takes nothing
-- else), then the backpack and bags 1-4 (Enum.BagIndex).
local REAGENT_ORDER = { 5, 0, 1, 2, 3, 4 }
local NORMAL_ORDER = { 0, 1, 2, 3, 4 }

-- The cursor's item comes from outside the bags (a bank tab, an equipped slot): ItemLocation or nil.
local function OutsideItem()
	local location = C_Cursor.GetCursorItem()
	if not location then
		return nil
	end
	if location:IsBagAndSlot() then
		local bag = location:GetBagAndSlot()
		if bag >= 0 and bag <= 5 then
			return nil
		end
	end
	return location
end

-- Puts the cursor's item into the first free slot that takes it. Nothing happens when the bags are full.
local function DropInFree()
	local location = C_Cursor.GetCursorItem()
	if not location then
		return
	end
	local itemID = C_Item.GetItemID(location)
	local isReagent = itemID and select(17, C_Item.GetItemInfo(itemID))
	for _, bag in ipairs(isReagent and REAGENT_ORDER or NORMAL_ORDER) do
		local free = C_Container.GetContainerFreeSlots(bag)
		if free and free[1] then
			C_Container.PickupContainerItem(bag, free[1])
			return
		end
	end
end

-- CURSOR_CHANGED (Bags.lua): while an item from outside the bags is held, the item buttons let clicks through to the
-- window, so it goes into a free slot wherever it's dropped.
function ns.BagsWindow_CursorChanged()
	ns.BagsButtons_SetMouse(OutsideItem() == nil)
end

-- Building ---------------------------------------------------------------------------------------------------------

local function OnSearchChanged()
	local text = search:GetText()
	local m, err, usesText = ns.BagsSearch_Compile(text)
	if err then
		search:SetError(err) -- keep the last good filter while a search is half typed
	else
		matcher, matcherText = m, usesText == true
		search:SetError(nil)
	end
	ns.BagsWindow_Refresh()
end

-- Characters and saved searches ---------------------------------------------------------------------------------

-- Shows another character's bags (guid), or yours (nil).
local function ViewCharacter(guid)
	viewChar = guid
	local name = guid and ns.Counts_CharName and ns.Counts_CharName(guid)
	title:SetText(name and ("Bags: " .. name) or "Bags")
	title:SetWidth(math.min(title:GetUnboundedStringWidth(), TITLE_MAX_W)) -- the search box keeps its room
	view:Release()
	ns.BagsWindow_Refresh()
end

local function CharacterMenu(owner)
	UI.ContextMenu(owner, function(_, root)
		root:CreateTitle("Look at the bags of")
		root:CreateButton("You", function()
			ViewCharacter(nil)
		end)
		local chars = ns.Counts_Characters and ns.Counts_Characters() or {}
		if #chars == 0 then
			root:CreateTitle("Item counts is off, or it hasn't seen another character yet")
		end
		for _, c in ipairs(chars) do
			if not c.me then
				root:CreateButton(UI.ClassColored(c.name, c.class), function()
					ViewCharacter(c.guid)
				end)
			end
		end
	end)
end

local function ApplySearch(text)
	search:SetText(text)
	search:SetCursorPosition(0)
end

local function SaveSearch()
	local text = search:GetText()
	if text == "" then
		ns.Print("Type a search first, then save it.")
		return
	end
	ns.Dialog_Show({
		title = "Save this search", hint = "A name for it", text = text, height = 60, saveText = "Save",
		onSave = function(name)
			name = name:match("^%s*(.-)%s*$")
			if name == "" then
				return "It needs a name."
			end
			ns.BagsEdit_SaveSearch(db.searches, name, text)
			return nil
		end,
	})
end

local function SearchMenu(owner)
	UI.ContextMenu(owner, function(_, root)
		root:CreateTitle("Saved searches")
		for _, saved in ipairs(db.searches) do
			local entry = root:CreateButton(saved.name, function()
				ApplySearch(saved.text)
			end)
			entry:CreateButton("Search", function()
				ApplySearch(saved.text)
			end)
			entry:CreateButton("Save as category", function()
				ns.Bags_SearchToCategory(saved.name, saved.text)
			end)
			entry:CreateButton("Delete", function()
				for i, s2 in ipairs(db.searches) do
					if s2 == saved then
						table.remove(db.searches, i)
						break
					end
				end
			end)
		end
		root:CreateDivider()
		root:CreateButton("Find on all characters", function()
			local text = search:GetText()
			if text == "" then
				ns.Print("Type a search first.")
				return
			end
			ns.BagsFind_Show(frame, text)
		end)
		root:CreateButton("Save this search", SaveSearch)
		root:CreateButton("Save this search as a category", function()
			local text = search:GetText()
			if text == "" then
				ns.Print("Type a search first.")
				return
			end
			ns.Bags_SearchToCategory(text, text)
		end)
	end)
end

-- The search box's "?" tooltip (the bank's search uses it too).
local function KeywordHelp(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip:SetText("Search")
	UI.TipLine("Words find names and types. is: finds a kind of item. Combine with and, or, not, -, ( ).", "textMuted", true)
	UI.TipLine("ilvl>=600, count>20, price>10 (gold), exp:tww", "textMuted", true)
	local words = {}
	for _, k in ipairs(ns.BagsSearch_Keywords()) do
		words[#words + 1] = k[1]
	end
	UI.TipLine("is: " .. table.concat(words, ", "), "text", true)
	GameTooltip:Show()
end
ns.BagsWindow_KeywordHelp = KeywordHelp

local function Build()
	frame = CreateFrame("Frame", "TomteBagsWindow", UIParent)
	frame:SetSize(MIN_W, BAND_H + FOOT_H + 4 * PAD) -- Draw sizes it; until then it can still be seen
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not db.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.position.point, db.position.relPoint, db.position.x, db.position.y = point, relPoint, x, y
	end)
	frame:Hide()
	UI.Panel(frame)

	-- Header band: bag slots and characters, the title, the search, then saved searches, sort, settings and close.
	header = ns.BagsKit_Band(frame)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(BAND_H)
	leftCluster = ns.BagsKit_Cluster(header, {
		{ glyph = "Bag", tip = "Bag slots", tipLine = "Show your equipped bags on top of the window.", onClick = function()
			showSlots = not showSlots
			DrawSlots()
		end },
		{ glyph = "People", tip = "Other characters", tipLine = "Look at another character's bags.",
			onClick = function(self)
				CharacterMenu(self)
			end },
		{ glyph = "Bank", tip = "Bank",
			tipLine = "Your bank as you last saw it (or the character's whose bags you're looking at). Needs Item counts.",
			onClick = function()
				ns.BagsBank_ShowRemembered(viewChar)
			end },
	})
	leftCluster:SetPoint("LEFT", PAD, 0)
	title = UI.Text(header, 14, "heading", "title")
	title:SetPoint("LEFT", leftCluster, "RIGHT", 10, 0)
	title:SetWordWrap(false)
	title:SetText("Bags")
	rightCluster = ns.BagsKit_Cluster(header, {
		{ glyph = "Star", tip = "Saved searches",
			tipLine = "Save the search in the box, use a saved one, or make a category of it.", onClick = SearchMenu },
		{ glyph = "Broom", tip = "Clean up bags", onClick = function()
			if InCombatLockdown() then
				ns.Print_Combat("sort your bags")
				return
			end
			C_Container.SortBags()
		end },
		{ glyph = "Gear", tip = "Bags settings", onClick = function()
			ns.Panel_OpenModule("bags")
		end },
		{ glyph = "Close", tip = "Close", onClick = function()
			ns.BagsTakeover_Close() -- Blizzard's bags close too, so the bag key opens them again
		end },
	})
	rightCluster:SetPoint("RIGHT", -PAD, 0)
	search = ns.BagsKit_Search(header, "Search, try is:upgrade", OnSearchChanged)
	search:SetPoint("LEFT", title, "RIGHT", 12, 0)
	search:SetPoint("RIGHT", rightCluster, "LEFT", -10, 0)
	search.help:SetScript("OnEnter", KeywordHelp)

	-- The items in a tray.
	tray = ns.BagsKit_Tray(frame)
	tray:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD - 1, -PAD)
	tray:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, FOOT_H + PAD)
	body = CreateFrame("Frame", nil, tray)
	body:SetPoint("TOPLEFT", TRAY_PAD, -TRAY_PAD)
	view = ns.BagsView_New(body, db, db.folded)

	-- Footer band: currencies, free slots and the meter, tracked currencies, gold.
	footer = ns.BagsKit_Band(frame)
	footer:SetRuleTop(true)
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(FOOT_H)
	local currencies = ns.BagsCurrencies_Button(footer, frame)
	currencies:SetPoint("LEFT", PAD, 0)
	footer.free = UI.Text(footer, 11, "textMuted")
	footer.free:SetPoint("LEFT", currencies, "RIGHT", 10, 0)
	footer.meter = ns.BagsKit_Meter(footer, METER_W)
	footer.meter:SetPoint("LEFT", footer.free, "RIGHT", 8, 0)
	footer.gold = UI.Text(footer, 12, "text", "number")
	footer.gold:SetPoint("RIGHT", -PAD - 2, 0)

	frame:SetScript("OnReceiveDrag", DropInFree)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" and CursorHasItem() then
			DropInFree()
		end
	end)
	frame:SetScript("OnShow", function()
		if db.sortOnOpen and not InCombatLockdown() then
			C_Container.SortBags()
		end
		UpdateHover()
		Draw()
	end)
	frame:SetScript("OnHide", function()
		search:ClearFocus()
		GameTooltip:Hide()
		UpdateHover()
		view:Release()
		ns.BagsRead_ClearNew() -- what Blizzard's bags do when they close
		if viewChar then
			-- Opening the bags again shows yours, not the character you were looking at.
			viewChar = nil
			title:SetText("Bags")
			title:SetWidth(math.min(title:GetUnboundedStringWidth(), TITLE_MAX_W))
		end
	end)
end

local function Place()
	local p = db.position
	frame:ClearAllPoints()
	if p.point then
		frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
	else
		frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 110)
	end
end

-- API --------------------------------------------------------------------------------------------------------------

function ns.BagsWindow_Init(moduleDB)
	db = moduleDB
end

-- Redraws on the next frame (a burst of bag events draws once).
function ns.BagsWindow_Refresh()
	if frame and frame:IsShown() and not queued then
		queued = true
		C_Timer.After(0, Draw)
	end
end

-- Draws now when the last draw waited for item data (GET_ITEM_INFO_RECEIVED).
function ns.BagsWindow_ItemDataArrived()
	if frame and frame.pending then
		frame.pending = false
		ns.BagsWindow_Refresh()
	end
end

function ns.BagsWindow_Show()
	if not frame then
		Build()
	end
	if not frame:IsShown() or frame.disappearing then
		Place()
		frame:Show()
		UI.Appear(frame)
	end
end

-- Opens the bags with a search for an item name (the crafting list's "find it"); the bank searches too while open.
function ns.BagsWindow_Find(name)
	ns.BagsWindow_Show()
	local text = '"' .. name:gsub('"', "") .. '"'
	search:SetText(text)
	search:SetCursorPosition(0)
	ns.BagsBank_Search(text)
end

function ns.BagsWindow_Hide()
	if frame and frame:IsShown() then
		UI.Disappear(frame)
	end
end

-- Back to your own bags (another character was forgotten, or Item counts turned off).
function ns.BagsWindow_ViewOwn()
	if viewChar and frame then
		ViewCharacter(nil)
	end
end

function ns.BagsWindow_IsShown()
	return frame ~= nil and frame:IsShown() and not frame.disappearing -- fading out counts as closed
end

-- After a layout setting changed (view, columns, size, marks, sorting, buttons on hover).
function ns.BagsWindow_Relayout()
	if view then
		view:Release()
	end
	UpdateHover()
	ns.BagsWindow_Refresh()
	if ns.BagsBank_Relayout then
		ns.BagsBank_Relayout()
	end
end

-- While a merchant, the mailbox, a trade or the like is open, items keep their places: what's sold or sent leaves an
-- empty slot where it was. When it closes, the window closes up again.
function ns.BagsWindow_SetHolding(on)
	if holding == on then
		return
	end
	holding = on
	if view then
		view:Release()
	end
	ns.BagsWindow_Refresh()
end

-- Back to the default spot (the settings button).
function ns.BagsWindow_ResetPosition()
	wipe(db.position)
	if frame then
		Place()
	end
end
