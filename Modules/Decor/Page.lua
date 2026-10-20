local addonName, ns = ...

-- Housing decor: the Decor page of the Tomte window. The decor you're missing (or all of it), grouped by source with
-- a source filter, a search box and counts; hovering a row shows the item and its model, clicking tracks it with
-- Blizzard's tracking (the objective tracker and map lead to the vendor, achievement or boss) or gives a waypoint to
-- a learned vendor (Vendors.lua), shift-click links it.
-- Filtering and grouping in Data.lua, the entries from Catalog.lua, actions in Decor.lua.

local ROW_H, HEADER_H = 26, 28
local ICON = 20
local TOP = 30 -- below the source filter
local LIST_TOP = TOP + 30 -- below the search box
local MAX_ROWS = 400 -- rows drawn at once; a search or a source narrows the rest
local NONE_ICON = 134400 -- inv_misc_questionmark
-- The row tooltip's click line per ns.Decor_ActionFor answer; %s is the vendor's name.
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
local preview

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

-- Rows ---------------------------------------------------------------------------------------------------------

local function RowEnter(self)
	if self.clickable then
		self.hover:Show()
	end
	local e = self.entry
	if not e then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if e.itemID then
		GameTooltip:SetItemByID(e.itemID)
	else
		GameTooltip:SetText(e.name, UI.Color("heading"))
	end
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
	if e.itemID then
		UI.TipLine("Shift-click to link it.", "textMuted")
	end
	GameTooltip:Show()
	if db.preview then
		preview = preview or ns.DecorPreview_Create(UIParent)
		ns.DecorPreview_Show(preview, e)
	end
end

local function RowLeave(self)
	self.hover:Hide()
	GameTooltip:Hide()
	ns.DecorPreview_Hide(preview)
end

local function RowClick(self, button)
	if self.onClick then
		self.onClick(button)
	end
end

local function NewRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.hover = row:CreateTexture(nil, "BACKGROUND")
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

-- item = { kind = "header" | "row" | "note", text, right, role, entry, onClick(button) }
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
		row.entry, row.onClick = item.entry, item.onClick
		row.clickable = item.onClick ~= nil
		row:EnableMouse(item.onClick ~= nil or item.entry ~= nil)
		row.hover:Hide()
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
			local x = 12
			if item.entry then
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

-- What a row says on its right: the vendor's zone, the source line, or how many you have.
local function RightText(e)
	if (e.owned or 0) > 0 then
		return UI.Wrap(("Collected (%d)"):format(e.owned), "success")
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
			ns.Decor_ToggleTracking(e)
			ns.DecorPage_Refresh()
		end
	end
end

local function ToggleSection(key)
	db.collapsed[key] = not db.collapsed[key] or nil
	ns.DecorPage_Refresh()
end

-- Page ---------------------------------------------------------------------------------------------------------

local function StatusText(info, counts)
	if info.state == "unavailable" then
		local _, why = ns.DecorCatalog_Available()
		return UI.Wrap(why or "The housing catalog can't be read here.", "textMuted")
	elseif info.usable then
		return ns.Decor_CollectedText(counts, ns.Thousands)
			.. UI.Wrap(("  ·  %s missing"):format(ns.Thousands(counts.missing)), "textMuted")
	end
	local pct = math.floor(info.progress * 100)
	return UI.Wrap(("Reading the housing catalog... %d%%"):format(pct), "textMuted")
end

local function Layout()
	local info = ns.DecorCatalog_State()
	local entries = ns.DecorCatalog_Entries()
	local counts = ns.Decor_Counts(entries)
	page.filter:Refresh()
	page.owned:SetChecked(db.filter.owned)
	page.status:SetText(StatusText(info, counts))
	local items = {}
	if info.usable then
		local list = ns.Decor_List(entries, { source = db.filter.source, query = page.search:Query(),
			owned = db.filter.owned })
		local shown, more = 0, false
		for _, section in ipairs(ns.Decor_Sections(list, db.collapsed)) do
			local key = section.key
			items[#items + 1] = { kind = "header", text = (section.collapsed and "+ " or "- ") .. section.title,
				right = db.filter.owned and ("%d of %d collected"):format(section.owned, #section.entries)
					or ("%d missing"):format(section.missing),
				onClick = function()
					ToggleSection(key)
				end }
			if not section.collapsed then
				for _, e in ipairs(section.entries) do
					if shown >= MAX_ROWS then
						more = true
						break
					end
					shown = shown + 1
					items[#items + 1] = { entry = e, text = e.name .. (ns.Decor_IsTracking(e.id)
						and UI.Wrap("  tracked", "accent") or ""), right = RightText(e),
						role = (e.owned or 0) > 0 and "textMuted" or "text", onClick = EntryClick(e) }
				end
			end
		end
		if more then
			items[#items + 1] = { kind = "note", role = "textMuted",
				text = ("Showing the first %d. Search or pick a source to see the rest."):format(MAX_ROWS) }
		end
		if #items == 0 then
			items[1] = { kind = "note", role = "textMuted", text = counts.total == 0
				and "The housing catalog is empty on this character."
				or (counts.missing == 0 and not db.filter.owned) and "You have every decor. Tick Show collected to list it."
				or "No decor matches." }
		end
	end
	Render(items)
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
		page.filter = UI.Segmented(page)
		page.filter:SetPoint("TOPLEFT", 8, 0)
		page.filter.choices = Choices
		page.filter.getValue = function()
			return db.filter.source
		end
		page.filter.setValue = function(value)
			db.filter.source = value
			ns.DecorPage_Refresh()
		end
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
		page.list.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
		page:HookScript("OnHide", function()
			ns.DecorPreview_Hide(preview)
		end)
	end,
	Refresh = function()
		ns.Decor_EnsureScan()
		Layout()
	end,
}
