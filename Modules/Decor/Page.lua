local addonName, ns = ...

-- Housing decor: the Decor page of the Tomte window. Two views: the decor you're missing (or all of it) grouped by
-- source, with how much of each source you have, and decor by vendor, each vendor folding open to everything they
-- sell. A source filter, a search box and counts on top; clicking a row shows the decor in the preview pane
-- (Detail.lua), where you can turn and zoom it and track it with Blizzard's tracking or get a waypoint to a learned
-- vendor (Vendors.lua); shift-click links it. With the preview off, a click tracks it straight away. A Houses button
-- opens the house list (Houses.lua).
-- Filtering, grouping and counts in Data.lua, the entries from Catalog.lua, actions in Decor.lua.

local ROW_H, HEADER_H = 26, 28
local ICON = 20
local TOP = 30 -- below the view switch and source filter
local LIST_TOP = TOP + 30 -- below the search box
local PANE_W = 320 -- the preview pane on the right
local GAP = 12 -- between the list and the pane
local MAX_ROWS = 400 -- decor rows drawn at once; a search or a source narrows the rest
local OPEN_MATCHES = 5 -- a search that leaves this many vendors or fewer opens them all
local NONE_ICON = 134400 -- inv_misc_questionmark
local VIEWS = { { value = "items", text = "Decor" }, { value = "vendors", text = "By vendor" } }
-- The row tooltip's click line per ns.Decor_ActionFor answer, while the preview is off; %s is the vendor's name.
local CLICK_HINTS = {
	stop = "Click to stop tracking it.",
	track = "Click to track it: Blizzard's tracking leads you there.",
	waypoint = "Click for a waypoint to %s.",
	learn = "Open %s's shop once and Tomte remembers where they stand for a waypoint.",
	none = "Blizzard's tracking can't lead to this one.",
}
local UI = ns.UI

local db
local page
local selectedID -- the decor in the preview pane

function ns.DecorPage_Init(moduleDB)
	db = moduleDB
end

local function Choices()
	local list = { { value = "all", text = "All" } }
	for _, s in ipairs(ns.DECOR_SOURCES) do
		list[#list + 1] = { value = s.key, text = s.title }
	end
	return list
end

local function ByVendor()
	return db.filter.view == "vendors"
end

-- Rows ---------------------------------------------------------------------------------------------------------

local function EntryTooltip(self, e)
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 24, -8)
	if e.itemID then
		GameTooltip:SetItemByID(e.itemID)
	else
		GameTooltip:SetText(e.name, UI.Color("heading"))
	end
	if not db.preview then
		GameTooltip:AddLine(" ")
		if e.raw and e.raw ~= "" then
			local text = ns.Decor_CleanSource(e.raw):gsub("\r?\n", "|n")
			for line in (text .. "|n"):gmatch("(.-)|n") do
				if line ~= "" then
					UI.TipLine(line, "text", true)
				end
			end
		end
		-- The item tooltip already carries the "Decor: collected (n)" line while that setting is on.
		if (e.owned or 0) > 0 and not (e.itemID and db.tooltip) then
			UI.TipLine(("You have %d."):format(e.owned), "success")
		end
		UI.TipLine(CLICK_HINTS[ns.Decor_ActionFor(e)]:format(e.vendor or ""), "textMuted", true)
	end
	if e.itemID then
		UI.TipLine("Shift-click to link it.", "textMuted")
	end
	GameTooltip:Show()
end

local function VendorTooltip(self, v)
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 24, -8)
	GameTooltip:SetText(v.vendor, UI.Color("heading"))
	if v.zone then
		UI.TipLine(v.zone, "textMuted")
	end
	UI.TipLine(("You have %d of the %d decor they sell."):format(v.owned, v.total), "text")
	GameTooltip:AddLine(" ")
	UI.TipLine("Click to show or hide what they sell.", "textMuted")
	if ns.DecorVendors_Spot({ vendor = v.vendor }) then
		UI.TipLine("Right-click for a waypoint to them.", "textMuted")
	else
		UI.TipLine("Open their shop once and Tomte remembers where they stand for a waypoint.", "textMuted", true)
	end
	GameTooltip:Show()
end

local function RowEnter(self)
	if self.clickable then
		self.hover:Show()
	end
	if self.entry then
		EntryTooltip(self, self.entry)
	elseif self.vendor then
		VendorTooltip(self, self.vendor)
	end
end

local function RowLeave(self)
	self.hover:Hide()
	GameTooltip:Hide()
end

local function RowClick(self, button)
	if self.onClick then
		self.onClick(button)
	end
end

local function NewRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(UI.RGBA("accent", 0.16))
	row.selected:Hide()
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.Color("hover"))
	row.hover:Hide()
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT", 8, 0)
	row.line:SetPoint("BOTTOMRIGHT", -8, 0)
	row.line:SetColorTexture(UI.RGBA("frame", 0.25))
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 12, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.left = UI.Text(row, 12, "text")
	row.left:SetWordWrap(false)
	row.right = UI.Text(row, 11, "textMuted")
	row.right:SetJustifyH("RIGHT")
	row.right:SetWordWrap(false)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	row:SetScript("OnClick", RowClick)
	return row
end

local function SetIcon(t, e)
	if e.atlas and not e.icon then
		t:SetTexCoord(0, 1, 0, 1)
		t:SetAtlas(e.atlas)
	else
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		t:SetTexture(e.icon or NONE_ICON)
	end
end

-- item = { kind = "header" | "row" | "note", text, right, role, entry, vendor, indent, onClick(button) }
local function Render(items)
	local list = page.list
	for i = 1, list.used do
		list.rows[i]:Hide()
	end
	list.used = 0
	local y = 0
	for _, item in ipairs(items) do
		list.used = list.used + 1
		local row = list.rows[list.used] or NewRow(list.scroll.content)
		list.rows[list.used] = row
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row.entry, row.vendor, row.onClick = item.entry, item.vendor, item.onClick
		row.clickable = item.onClick ~= nil
		row:EnableMouse(item.onClick ~= nil or item.entry ~= nil)
		row.hover:Hide()
		row.selected:SetShown(item.entry ~= nil and db.preview and item.entry.id == selectedID)
		row.left:ClearAllPoints()
		row.right:ClearAllPoints()
		row.right:SetPoint("RIGHT", -12, 0)
		local height
		if item.kind == "header" then
			height = HEADER_H
			row.icon:Hide()
			UI.SetFont(row.left, "body", 14)
			UI.SetTextRole(row.left, "heading")
			row.left:SetPoint("BOTTOMLEFT", 8, 6)
			row.right:ClearAllPoints()
			row.right:SetPoint("BOTTOMRIGHT", -12, 7)
			row.line:Show()
		else
			height = ROW_H
			row.line:Hide()
			local x = 12 + (item.indent or 0)
			if item.entry then
				row.icon:SetPoint("LEFT", x, 0)
				SetIcon(row.icon, item.entry)
				row.icon:Show()
				x = x + ICON + 8
			else
				row.icon:Hide()
			end
			UI.SetFont(row.left, "body", 12)
			UI.SetTextRole(row.left, item.role or "text")
			row.left:SetPoint("LEFT", x, 0)
		end
		row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
		row.left:SetText(item.text or "")
		row.right:SetText(item.right or "")
		row:SetHeight(height)
		row:Show()
		y = y + height
	end
	list.scroll:SetContentHeight(y)
end

-- What a row says on its right: how many you have, the vendor's price (by vendor), the vendor and zone, or the
-- source line.
local function RightText(e, vendorKey)
	if (e.owned or 0) > 0 then
		return UI.Wrap(("Collected (%d)"):format(e.owned), "success")
	end
	if vendorKey then
		return ns.Decor_CostAt(e, vendorKey) or ""
	end
	if e.source == "vendor" and e.vendor then
		return e.vendor .. (e.zone and UI.Wrap(" · " .. e.zone, "textFaint") or "")
	end
	return e.line or ns.Decor_SourceWord(e.source)
end

local function EntryClick(e)
	return function(button)
		if IsModifiedClick("CHATLINK") then
			ns.Decor_Link(e)
		elseif button == "LeftButton" then
			if db.preview then
				selectedID = e.id
			else
				ns.Decor_ToggleTracking(e)
			end
			ns.DecorPage_Refresh()
		end
	end
end

local function EntryItem(e, vendorKey)
	return { entry = e, indent = vendorKey and 12 or 0,
		text = e.name .. (ns.Decor_IsTracking(e.id) and UI.Wrap("  tracked", "accent") or ""),
		right = RightText(e, vendorKey), role = (e.owned or 0) > 0 and "textMuted" or "text", onClick = EntryClick(e) }
end

local function CollectedRight(owned, total)
	return ns.Decor_Ratio(owned, total, ns.Thousands) .. " collected"
end

-- Views --------------------------------------------------------------------------------------------------------

local function ToggleSection(key)
	db.collapsed[key] = not db.collapsed[key] or nil
	ns.DecorPage_Refresh()
end

-- By source: every section counts all its decor (under the search), the rows leave out what you have unless
-- Show collected is ticked.
local function SourceItems(entries, query)
	local items, shown = {}, 0
	local list = ns.Decor_List(entries, { source = db.filter.source, query = query, owned = true,
		full = db.searchSources })
	for _, section in ipairs(ns.Decor_Sections(list, db.collapsed, not db.filter.owned)) do
		local key = section.key
		items[#items + 1] = { kind = "header", text = (section.collapsed and "+ " or "- ") .. section.title,
			right = CollectedRight(section.owned, section.total),
			onClick = function()
				ToggleSection(key)
			end }
		if not section.collapsed then
			for _, e in ipairs(section.entries) do
				if shown >= MAX_ROWS then
					return items, true
				end
				shown = shown + 1
				items[#items + 1] = EntryItem(e)
			end
		end
	end
	return items, false
end

local function VendorClick(v, open)
	return function(button)
		if button == "RightButton" then
			if not ns.DecorVendors_Waypoint({ vendor = v.vendor }) then
				ns.Print(("Tomte doesn't know where %s stands yet: open their shop once and it remembers the spot.")
					:format(v.vendor))
			end
			return
		end
		db.vendorsOpen[v.key] = not open or nil
		ns.DecorPage_Refresh()
	end
end

-- By vendor: vendors with decor you're missing (all of them with Show collected), each folding open to everything
-- they sell. A narrow search opens the vendors it leaves.
local function VendorItems(entries, query)
	local items, shown = {}, 0
	local vendors = ns.Decor_Vendors(entries, ns.DecorVendors_Learned(), { query = query, owned = db.filter.owned,
		full = db.searchSources })
	local openAll = query ~= "" and #vendors <= OPEN_MATCHES
	for _, v in ipairs(vendors) do
		local open = openAll or db.vendorsOpen[v.key] == true
		items[#items + 1] = { kind = "header", vendor = v,
			text = (open and "- " or "+ ") .. v.vendor .. (v.zone and UI.Wrap("  ·  " .. v.zone, "textFaint") or ""),
			right = CollectedRight(v.owned, v.total), onClick = VendorClick(v, open) }
		if open then
			for _, e in ipairs(v.entries) do
				if shown >= MAX_ROWS then
					return items, true, #vendors
				end
				shown = shown + 1
				items[#items + 1] = EntryItem(e, v.key)
			end
		end
	end
	return items, false, #vendors
end

-- Page ---------------------------------------------------------------------------------------------------------

local function StatusText(info, counts, vendors)
	if info.state == "unavailable" then
		local _, why = ns.DecorCatalog_Available()
		return UI.Wrap(why or "The housing catalog can't be read here.", "textMuted")
	elseif info.usable then
		return (vendors and UI.Wrap(("%s vendors  ·  "):format(ns.Thousands(vendors)), "textMuted") or "")
			.. ns.Decor_CollectedText(counts, ns.Thousands)
			.. UI.Wrap(("  ·  %s missing"):format(ns.Thousands(counts.missing)), "textMuted")
	end
	local pct = math.floor(info.progress * 100)
	return UI.Wrap(("Reading the housing catalog... %d%%"):format(pct), "textMuted")
end

local function EmptyText(counts)
	if counts.total == 0 then
		return "The housing catalog is empty on this character."
	elseif counts.missing == 0 and not db.filter.owned then
		return "You have every decor. Tick Show collected to list it."
	end
	return ByVendor() and "No vendor matches." or "No decor matches."
end

-- The list fills the page, less the preview pane while it's on.
local function Place()
	page.list.scroll:SetPoint("BOTTOMRIGHT", db.preview and -(PANE_W + GAP + 8) or -8, 0)
	page.pane:SetShown(db.preview)
end

local function Layout()
	local info = ns.DecorCatalog_State()
	local entries = ns.DecorCatalog_Entries()
	local counts = ns.Decor_Counts(entries)
	page.view:Refresh()
	page.filter:SetShown(not ByVendor())
	page.filter:Refresh()
	page.owned:SetChecked(db.filter.owned)
	page.houses:SetShown(ns.DecorHouses_Enabled())
	Place()
	local items, more, vendors = {}, false, nil
	if info.usable then
		local query = page.search:Query()
		if ByVendor() then
			items, more, vendors = VendorItems(entries, query)
		else
			items, more = SourceItems(entries, query)
		end
		if more then
			items[#items + 1] = { kind = "note", role = "textMuted",
				text = ("Showing the first %d. Search or pick a source to see the rest."):format(MAX_ROWS) }
		end
		if #items == 0 then
			items[1] = { kind = "note", role = "textMuted", text = EmptyText(counts) }
		end
	end
	page.status:SetText(StatusText(info, counts, vendors))
	Render(items)
	if db.preview then
		ns.DecorDetail_Show(page.pane, selectedID and info.usable and ns.DecorCatalog_ByID(selectedID) or nil)
	end
end

function ns.DecorPage_Refresh()
	if page and page:IsVisible() then
		Layout()
	end
end

local function SearchBox(parent, onChange)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(22)
	box:SetAutoFocus(false)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(8, 8, 0, 0)
	UI.Surface(box, 0.35)
	local placeholder = UI.Text(box, 12, "textFaint")
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetText("Search decor, vendors, zones")
	local refresh = UI.Debounce(UI.SEARCH_DELAY, onChange)
	box:SetScript("OnTextChanged", function(self)
		placeholder:SetShown(self:GetText() == "")
		refresh()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	function box:Query()
		return strtrim(self:GetText()):lower()
	end
	return box
end

ns.DecorPage = {
	Create = function(frame)
		page = frame
		page.view = UI.Segmented(page)
		page.view:SetPoint("TOPLEFT", 8, 0)
		page.view.choices = function()
			return VIEWS
		end
		page.view.getValue = function()
			return db.filter.view
		end
		page.view.setValue = function(value)
			db.filter.view = value
			ns.DecorPage_Refresh()
		end
		page.filter = UI.Segmented(page)
		page.filter:SetPoint("LEFT", page.view, "RIGHT", 16, 0)
		page.filter.choices = Choices
		page.filter.getValue = function()
			return db.filter.source
		end
		page.filter.setValue = function(value)
			db.filter.source = value
			ns.DecorPage_Refresh()
		end
		page.houses = UI.Button(page, 80, "Houses")
		UI.FitButton(page.houses, 80)
		page.houses:SetPoint("TOPRIGHT", -8, 0)
		page.houses:SetScript("OnClick", function()
			ns.DecorHouses_Toggle()
		end)
		page.houses:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText("Your houses", UI.Color("heading"))
			UI.TipLine("Every house you own, with a button to teleport there.", "text", true)
			GameTooltip:Show()
		end)
		page.houses:SetScript("OnLeave", GameTooltip_Hide)
		page.search = SearchBox(page, ns.DecorPage_Refresh)
		page.search:SetPoint("TOPLEFT", 8, -TOP)
		page.search:SetWidth(240)
		page.owned = UI.Checkbox(page)
		page.owned:SetPoint("LEFT", page.search, "RIGHT", 14, 0)
		page.owned.onChange = function(on)
			db.filter.owned = on
			ns.DecorPage_Refresh()
		end
		local ownedLabel = UI.Text(page, 12, "text")
		ownedLabel:SetPoint("LEFT", page.owned, "RIGHT", 6, 0)
		ownedLabel:SetText("Show collected")
		page.status = UI.Text(page, 12, "text")
		page.status:SetPoint("LEFT", ownedLabel, "RIGHT", 18, 0)
		page.status:SetPoint("RIGHT", -8, 0)
		page.status:SetJustifyH("RIGHT")
		page.status:SetWordWrap(false)
		page.list = { rows = {}, used = 0 }
		page.list.scroll = UI.Scroll(page)
		page.list.scroll:SetPoint("TOPLEFT", 0, -LIST_TOP)
		page.pane = ns.DecorDetail_Create(page)
		page.pane:SetPoint("TOPRIGHT", -8, -LIST_TOP)
		page.pane:SetPoint("BOTTOMRIGHT", -8, 0)
		page.pane:SetWidth(PANE_W)
		Place()
	end,
	Refresh = function()
		ns.Decor_EnsureScan()
		Layout()
	end,
}
