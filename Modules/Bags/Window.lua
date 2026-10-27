local addonName, ns = ...

-- Bags: the bag window. Top bar (title, search, bag slots, sort, settings, close), the items in categories
-- (Layout.lua packs them, Data.lua sorts them into categories) or as one bag, and a footer (free slots, tracked
-- currencies and Gold & value's items, gold). Opened and closed by Takeover.lua following Blizzard's bag state;
-- registered in Bags.lua.

local PAD = 10 -- window edge to content
local MIN_W = 380 -- the top bar's title, search box and buttons fit at any column count
local TOP_H = 30 -- the top bar
local SEARCH_W = 170
local SEARCH_H = 20
local NOTE_H = 14 -- the line under the search box for a bad search
local SLOT_SIZE = 30 -- an equipped bag's button in the row above the window
local SLOT_GAP = 3
local SLOTS_PAD = 6 -- the bag slots row's panel around its buttons
local HOVER_POLL = 0.1 -- seconds between mouse checks while the top bar's buttons show only on hover
local FOOT_H = 22 -- the footer
local FOOT_LEFT = 24 -- the currencies button and its gap, before the free slots
local LABEL_H = 13 -- a category's label line
local SECTION_H = 18 -- a section heading
local LINE_GAP = 6 -- between lines
local GAP = 2 -- between icons
local FADED = 0.3 -- a category label whose items are all filtered out by the search
local ICON_SIZE = 12 -- footer currency icons
-- The equipped bag slots: bags 1-4 and the reagent bag (Enum.BagIndex), shown in the bag slots row.
local EQUIPPED = { 1, 2, 3, 4, 5 }
local COIN_ICONS = {
	gold = "%s|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "%s|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "%s|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
local SORT_ICON = "Interface\\Icons\\INV_Pet_Broom"
local BAGS_ICON = "Interface\\Icons\\INV_Misc_Bag_08"

local UI = ns.UI

local db
local frame, body, search, note, slotsRow, footer
local categories -- the default layout flattened (Data.lua)
local matcher -- the compiled search, nil for none
local matcherText = false -- the search has words, which also look in the tooltip text
local queued, footerQueued = false, false
local showSlots = false
local holding = false -- a window that takes items is open: items keep their places (ns.BagsWindow_SetHolding)
local snapshot -- the places kept while holding (Data.lua's Bags_Snapshot), taken on the first draw
local labels, headings, rules, slotButtons, coins = {}, {}, {}, {}, {}
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

local function Label(i)
	return Pooled(labels, i, function()
		local fs = UI.Text(body, 10, "textMuted", "label")
		fs:SetWordWrap(false)
		return fs
	end)
end

local function Heading(i)
	return Pooled(headings, i, function()
		local b = CreateFrame("Button", nil, body)
		b:SetHeight(SECTION_H)
		b.text = UI.Text(b, 12, "heading", "title")
		b.text:SetPoint("LEFT")
		b:SetScript("OnClick", function(self)
			db.folded[self.key] = not db.folded[self.key] or nil
			ns.BagsWindow_Refresh()
		end)
		return b
	end)
end

local function Rule(i)
	return Pooled(rules, i, function()
		return UI.Hairline(body, 100, 0.5)
	end)
end

-- Drawing ----------------------------------------------------------------------------------------------------------

-- The blocks Layout.lua packs, and the records each category shows (one Empty button per kind of slot, carrying how
-- many are free).
local function CategoryBlocks(items)
	categories = categories or ns.Bags_Flatten(ns.BAGS_LAYOUT)
	local byKey = ns.Bags_Assign(items, categories)
	local blocks, contents = {}, {}
	local function Add(node, section)
		local list = byKey[node.key] or {}
		if node.auto == "empty" then
			local firstOfKind, free = {}, {}
			for _, slot in ipairs(list) do
				free[slot.kind] = (free[slot.kind] or 0) + 1
				if not firstOfKind[slot.kind] then
					firstOfKind[slot.kind] = slot
				end
			end
			list = {}
			for _, kind in ipairs({ "normal", "reagent" }) do
				if firstOfKind[kind] then
					-- A copy: the slot's own record may also stand in its old place while places are kept, as a plain
					-- empty slot without Empty's count and leaf.
					list[#list + 1] = setmetatable({ free = free[kind] }, { __index = firstOfKind[kind] })
				end
			end
		else
			ns.Bags_SortItems(list, db.sortMethod, db.sortReverse)
		end
		blocks[#blocks + 1] = { kind = "category", key = node.key, label = node.name, count = #list, section = section,
			ownLine = node.ownLine }
		contents[node.key] = list
	end
	for _, node in ipairs(ns.BAGS_LAYOUT) do
		if node.kind == "section" then
			blocks[#blocks + 1] = { kind = "section", key = node.key, label = node.name, folded = db.folded[node.key] }
			for _, child in ipairs(node.children or {}) do
				if child.kind == "category" then
					Add(child, node.key)
				end
			end
		elseif node.kind == "divider" then
			blocks[#blocks + 1] = { kind = "divider" }
		elseif node.kind == "category" then
			Add(node, nil)
		end
	end
	return blocks, contents
end

-- One bag: every item, sorted, then the empty slots.
local function SingleBlocks(items)
	local filled, empty = {}, {}
	for _, item in ipairs(items) do
		if item.empty then
			empty[#empty + 1] = item
		else
			filled[#filled + 1] = item
		end
	end
	ns.Bags_SortItems(filled, db.sortMethod, db.sortReverse)
	for _, slot in ipairs(empty) do
		filled[#filled + 1] = slot
	end
	return { { kind = "category", key = "all", count = #filled } }, { all = filled }
end

-- The open window that takes items from the bags, for Data.lua's Bags_Fits: the ones Blizzard's item context
-- matching doesn't cover (it does the scrapper, sockets, upgrades and the catalyst itself).
local function Situation()
	if TradeFrame and TradeFrame:IsShown() then
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
	if not ns.Bags_Fits(item, situation) then
		return false
	end
	if not matcher then
		return true
	end
	return item.readable ~= false and matcher(item) == true
end

local function Draw()
	queued = false
	if not (frame and frame:IsShown()) then
		return
	end
	local items, pending = ns.BagsRead_Bags()
	if matcher and matcherText then
		ns.BagsRead_LoadText(items)
	end
	if db.group then
		items = ns.Bags_Group(items)
	end
	local blocks, contents
	if db.view == "single" then
		blocks, contents = SingleBlocks(items)
	else
		blocks, contents = CategoryBlocks(items)
	end
	if holding then
		if snapshot then
			local bySlot = {}
			for _, item in ipairs(items) do
				bySlot[item.bag * 1000 + item.slot] = item
			end
			contents = ns.Bags_KeepPlaces(snapshot, contents, bySlot)
			for _, block in ipairs(blocks) do
				if block.kind == "category" then
					block.count = #(contents[block.key] or {})
				end
			end
		else
			snapshot = ns.Bags_Snapshot(contents)
		end
	end
	local size = db.iconSize
	local placed, height, width = ns.Bags_Pack(blocks, {
		columns = db.columns, icon = size, gap = GAP, label = LABEL_H, section = SECTION_H, spacing = db.spacing,
		lineGap = LINE_GAP,
	})
	local nLabels, nHeadings, nRules = 0, 0, 0
	local looks = db.looks
	local opts = {
		corners = db.corners, ilvlColor = db.ilvlColor, fontSize = looks.fontSize, newGlow = looks.newGlow,
		greyJunk = looks.greyJunk, redUnusable = looks.redUnusable, context = looks.context,
	}
	local situation = looks.context and Situation() or nil
	local drawn = {} -- [button] = true
	DrawSlots()
	for _, p in ipairs(placed) do
		local block = p.block
		if block.kind == "section" then
			nHeadings = nHeadings + 1
			local h = Heading(nHeadings)
			h.key = block.key
			h.text:SetText((block.folded and "+ " or "- ") .. block.label)
			h:SetWidth(p.width)
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", body, "TOPLEFT", p.x, -p.y)
			h:Show()
		elseif block.kind == "divider" then
			nRules = nRules + 1
			local r = Rule(nRules)
			r:SetWidth(p.width)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", body, "TOPLEFT", p.x, -(p.y + LINE_GAP / 2))
			r:Show()
		else
			local list = contents[block.key]
			local anyMatch = false
			for i, cell in ipairs(p.cells) do
				local item = list[i]
				local button = ns.BagsButtons_Get(item.bag, item.slot)
				opts.matches = Matches(item, situation)
				opts.free = item.free
				anyMatch = anyMatch or opts.matches
				ns.BagsButtons_Place(button, cell.x, cell.y, size)
				ns.BagsButtons_Paint(button, item, opts)
				drawn[button] = true
			end
			if block.label then
				nLabels = nLabels + 1
				local fs = Label(nLabels)
				fs:SetText(block.label)
				fs:SetWidth(math.max(p.width, size))
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", body, "TOPLEFT", p.x, -p.y)
				fs:SetAlpha(anyMatch and 1 or FADED)
				fs:Show()
			end
		end
	end
	ns.BagsButtons_HideOthers(drawn)
	for i = nLabels + 1, #labels do
		labels[i]:Hide()
	end
	for i = nHeadings + 1, #headings do
		headings[i]:Hide()
	end
	for i = nRules + 1, #rules do
		rules[i]:Hide()
	end
	local top = TOP_H + (note:IsShown() and NOTE_H or 0)
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", PAD, -top)
	body:SetSize(width, math.max(height, 1))
	frame:SetSize(math.max(width + 2 * PAD, MIN_W), top + height + PAD + FOOT_H + PAD / 2)
	if pending then
		-- Some items' data is still on its way: GET_ITEM_INFO_RECEIVED redraws (Bags.lua).
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

local function FreeSlots()
	local free = 0
	for bag = 0, 5 do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
	end
	return free
end

local function DrawFooter()
	footerQueued = false
	if not (frame and frame:IsShown()) then
		return
	end
	local free = FreeSlots()
	footer.free:SetText(free == 1 and "1 free slot" or ("%s free slots"):format(ns.Thousands(free)))
	footer.gold:SetText(ns.Coins(GetMoney(), true, COIN_ICONS))
	local x, shown = FOOT_LEFT + footer.free:GetStringWidth() + 14, 0
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

local function SlotButton(i)
	return Pooled(slotButtons, i, function()
		local b = CreateFrame("Button", nil, slotsRow)
		b:SetSize(SLOT_SIZE, SLOT_SIZE)
		b:RegisterForDrag("LeftButton")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		UI.Border(b, "frame", 0.8)
		b.free = b:CreateFontString(nil, "OVERLAY")
		UI.SetFont(b.free, "number", 12, "OUTLINE")
		b.free:SetPoint("BOTTOMRIGHT", -2, 2)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if not GameTooltip:SetInventoryItem("player", self.invID) then
				GameTooltip:SetText(self.bag == 5 and "Reagent bag slot" or "Bag slot")
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		local function Take(self)
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

-- The equipped bags in a row on top of the window's top-left edge, each with its free slots.
function DrawSlots()
	slotsRow:SetShown(showSlots)
	if not showSlots then
		return
	end
	for i, bag in ipairs(EQUIPPED) do
		local b = SlotButton(i)
		b.bag = bag
		b.invID = C_Container.ContainerIDToInventoryID(bag)
		local texture = GetInventoryItemTexture("player", b.invID)
		b.icon:SetTexture(texture or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
		b.free:SetText(texture and C_Container.GetContainerNumFreeSlots(bag) or "")
		UI.SetTextRole(b.free, "text")
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", slotsRow, "BOTTOMLEFT", SLOTS_PAD + (i - 1) * (SLOT_SIZE + SLOT_GAP), SLOTS_PAD)
		b:Show()
	end
	slotsRow:SetSize(#EQUIPPED * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + 2 * SLOTS_PAD, SLOT_SIZE + 2 * SLOTS_PAD)
end

-- Top bar buttons ---------------------------------------------------------------------------------------------------

local topButtons = {} -- the top bar's icon buttons, shown only on hover when that setting is on
local hoverTicker

local function ShowTopButtons(shown)
	for _, b in ipairs(topButtons) do
		b:SetAlpha(shown and 1 or 0)
	end
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

local function IconButton(parent, texture, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(18, 18)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexture(texture)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(tip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", onClick)
	return b
end

local function OnSearchChanged()
	local text = search:GetText()
	local m, err, usesText = ns.BagsSearch_Compile(text)
	if err then
		note:SetText(err)
		note:Show()
		-- keep the last good filter while a search is half typed
	else
		matcher, matcherText = m, usesText == true
		note:Hide()
	end
	ns.BagsWindow_Refresh()
end

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

local function Build()
	frame = CreateFrame("Frame", "TomteBagsWindow", UIParent)
	frame:SetSize(MIN_W, TOP_H + FOOT_H + 2 * PAD) -- Draw sizes it; until then it can still be seen
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

	-- Top left: the bag slots button, under the row it opens (the character and bank buttons join it later).
	local bags = IconButton(frame, BAGS_ICON, "Show your bag slots", function()
		showSlots = not showSlots
		DrawSlots()
	end)
	bags:SetPoint("TOPLEFT", PAD - 2, -7)
	local title = UI.Text(frame, 14, "heading", "title")
	title:SetPoint("LEFT", bags, "RIGHT", 6, 0)
	title:SetText("Bags")

	local close = UI.Button(frame, 20, "x")
	close:SetPoint("TOPRIGHT", -6, -5)
	close:SetScript("OnClick", function()
		ns.BagsTakeover_Close() -- Blizzard's bags close too, so the bag key opens them again
	end)
	local settings = IconButton(frame, UI.GEAR, "Bags settings", function()
		ns.Panel_OpenModule("bags")
	end)
	settings.icon:SetTexCoord(0, 0.5, 0, 0.5)
	settings.icon:SetVertexColor(UI.RGB("textMuted"))
	settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
	local sort = IconButton(frame, SORT_ICON, "Clean up bags", function()
		if InCombatLockdown() then
			ns.Print_Combat("sort your bags")
			return
		end
		C_Container.SortBags()
	end)
	sort:SetPoint("RIGHT", settings, "LEFT", -6, 0)
	topButtons = { close, settings, sort, bags }

	search = CreateFrame("EditBox", nil, frame)
	search:SetSize(SEARCH_W, SEARCH_H)
	search:SetAutoFocus(false)
	UI.SearchBoxClear(search)
	UI.SetFont(search, "body", 12)
	UI.SetTextRole(search, "text")
	search:SetTextInsets(6, 6, 0, 0)
	UI.Surface(search, 0.35)
	search:SetPoint("RIGHT", sort, "LEFT", -24, 0)
	local placeholder = UI.Text(search, 12, "textFaint")
	placeholder:SetPoint("LEFT", 6, 0)
	placeholder:SetText("Search, try is:upgrade")
	local refresh = UI.Debounce(UI.SEARCH_DELAY, OnSearchChanged)
	search:SetScript("OnTextChanged", function(self)
		placeholder:SetShown(self:GetText() == "")
		refresh()
	end)
	search:SetScript("OnEscapePressed", search.ClearFocus)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	local help = CreateFrame("Button", nil, frame)
	help:SetSize(16, 16)
	help:SetPoint("LEFT", search, "RIGHT", 4, 0)
	help.text = UI.Text(help, 12, "textMuted")
	help.text:SetPoint("CENTER")
	help.text:SetText("?")
	help:SetScript("OnEnter", KeywordHelp)
	help:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	note = UI.Text(frame, 10, "warning")
	note:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -1)
	note:Hide()

	slotsRow = CreateFrame("Frame", nil, frame)
	slotsRow:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 3)
	slotsRow:EnableMouse(true)
	UI.Panel(slotsRow, { size = "small" })
	slotsRow:Hide()

	body = CreateFrame("Frame", nil, frame)
	ns.BagsButtons_SetHost(body)

	footer = CreateFrame("Frame", nil, frame)
	footer:SetHeight(FOOT_H)
	footer:SetPoint("BOTTOMLEFT", PAD, PAD / 2)
	footer:SetPoint("BOTTOMRIGHT", -PAD, PAD / 2)
	local currencies = ns.BagsCurrencies_Button(footer, frame)
	currencies:SetPoint("LEFT")
	footer.free = UI.Text(footer, 11, "textMuted")
	footer.free:SetPoint("LEFT", currencies, "RIGHT", 8, 0)
	footer.gold = UI.Text(footer, 12, "text", "number")
	footer.gold:SetPoint("RIGHT")

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
		snapshot = nil
		ns.BagsRead_ClearNew() -- what Blizzard's bags do when they close
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
	if not frame:IsShown() then
		Place()
		frame:Show()
	end
end

function ns.BagsWindow_Hide()
	if frame then
		frame:Hide()
	end
end

function ns.BagsWindow_IsShown()
	return frame ~= nil and frame:IsShown()
end

-- After a layout setting changed (view, columns, size, marks, sorting, buttons on hover).
function ns.BagsWindow_Relayout()
	snapshot = nil
	UpdateHover()
	ns.BagsWindow_Refresh()
end

-- While a merchant, the mailbox, a trade or the like is open, items keep their places: what's sold or sent leaves an
-- empty slot where it was. When it closes, the window closes up again.
function ns.BagsWindow_SetHolding(on)
	if holding == on then
		return
	end
	holding = on
	snapshot = nil
	ns.BagsWindow_Refresh()
end

-- Back to the default spot (the settings button).
function ns.BagsWindow_ResetPosition()
	wipe(db.position)
	if frame then
		Place()
	end
end
