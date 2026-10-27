local addonName, ns = ...

-- Bags: the "Bag categories" page in the Tomte window. Left, the list: sections, their categories, dividers, each
-- category with how many of your items it holds now. Right, the one picked: name, rule (the search language, with the
-- items it matches as icons), priority, its own row, hidden, where it shows (bags, bank, Warband bank), items always
-- in it (item IDs; drop an item on the box), its section, move up or down, delete. Above: add a category, a section
-- or a divider, share, import, back to the defaults. The editing itself is EditData.lua's; registered in Bags.lua.

local LIST_W = 260
local ROW_H = 20
local INDENT = 14
local TOP = 34 -- the buttons above the list
local FIELD_W = 300
local PREVIEW = 16 -- matching items shown as icons under the rule
local PREVIEW_ICON = 22
local LABEL_W = 110

local UI = ns.UI

local db, page, list, rows, editor
local selected -- the picked node's key
local Refresh

-- What's in the bags now, by category key, for the counts and the rule preview.
local function Contents()
	if not (ns.Bags_Active and ns.Bags_Active()) then
		return nil, {}
	end
	local items = ns.BagsRead_Bags()
	return ns.Bags_Assign(items, ns.Bags_Flatten(ns.Bags_Layout()), "bags"), items
end

local function Changed()
	ns.Bags_LayoutChanged()
	Refresh()
end

-- The list ---------------------------------------------------------------------------------------------------------

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, list.content)
	row:SetHeight(ROW_H)
	UI.HoverWash(row)
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:SetWidth(2)
	row.name = UI.Text(row, 12, "text")
	row.name:SetWordWrap(false)
	row.count = UI.Text(row, 11, "textMuted", "number")
	row.count:SetPoint("RIGHT", -6, 0)
	row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row:SetScript("OnEnter", function(self)
		UI.WashTo(self.hoverWash, true)
	end)
	row:SetScript("OnLeave", function(self)
		UI.WashTo(self.hoverWash, false)
	end)
	row:SetScript("OnClick", function(self)
		selected = self.key
		Refresh()
	end)
	rows[i] = row
	return row
end

local function DrawList(layout, byKey)
	local n, y = 0, 0
	local width = list:GetWidth()
	local function Add(node, depth)
		n = n + 1
		local row = Row(n)
		row.key = node.key
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", 8 + depth * INDENT, 0)
		row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
		if node.kind == "section" then
			UI.SetFont(row.name, "title", 13)
			UI.SetTextRole(row.name, "heading")
			row.name:SetText(node.name)
			row.count:SetText("")
		elseif node.kind == "divider" then
			UI.SetFont(row.name, "body", 12)
			UI.SetTextRole(row.name, "textFaint")
			row.name:SetText("divider")
			row.count:SetText("")
		else
			UI.SetFont(row.name, "body", 12)
			UI.SetTextRole(row.name, node.hidden and "textFaint" or "text")
			row.name:SetText(node.name .. (node.hidden and " (hidden)" or ""))
			local items = byKey and byKey[node.key]
			row.count:SetText(items and #items > 0 and #items or "")
		end
		local picked = node.key == selected
		row.mark:SetColorTexture(UI.Color("accent"))
		row.mark:SetShown(picked)
		row:Show()
		y = y + ROW_H
		if node.kind == "section" then
			for _, child in ipairs(node.children or {}) do
				Add(child, depth + 1)
			end
		end
	end
	for _, node in ipairs(layout) do
		Add(node, 0)
	end
	for i = n + 1, #rows do
		rows[i]:Hide()
	end
	list:SetContentHeight(y)
end

-- The editor -------------------------------------------------------------------------------------------------------

local function Label(text, anchor, y)
	local fs = UI.Text(editor, 12, "textMuted")
	fs:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
	fs:SetWidth(LABEL_W)
	fs:SetText(text)
	return fs
end

-- A one-line box: commit(text) on Enter or when it loses focus.
local function Box(width, commit)
	local box = CreateFrame("EditBox", nil, editor)
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(6, 6, 0, 0)
	UI.Surface(box, 0.35)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self.reverting = true
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self.before = self:GetText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		if self.reverting then
			self.reverting = false
			Refresh()
			return
		end
		if self:GetText() ~= self.before then
			commit(self:GetText())
		end
	end)
	return box
end

local function Selected()
	if not selected then
		return nil
	end
	local _, _, node, section = ns.BagsEdit_Find(ns.Bags_Layout(), selected)
	return node, section
end

-- Every edit goes to the player's own copy (made from the defaults the first time).
local function Edit(fn)
	local layout = ns.Bags_EditLayout()
	local _, _, node, section = ns.BagsEdit_Find(layout, selected)
	if node then
		fn(node, layout, section)
		Changed()
	end
end

local function PreviewIcons(items, rule)
	local m = rule and rule ~= "" and ns.BagsSearch_Compile(rule)
	local n = 0
	for _, item in ipairs(items) do
		if n >= PREVIEW then
			break
		end
		if m and not item.empty and item.readable ~= false and m(item) then
			n = n + 1
			local icon = editor.preview[n]
			if not icon then
				icon = editor:CreateTexture(nil, "ARTWORK")
				icon:SetSize(PREVIEW_ICON, PREVIEW_ICON)
				editor.preview[n] = icon
			end
			icon:SetTexture(item.icon)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", editor.rule, "BOTTOMLEFT", (n - 1) * (PREVIEW_ICON + 2), -20)
			icon:Show()
		end
	end
	for i = n + 1, #editor.preview do
		editor.preview[i]:Hide()
	end
	return n
end

local function BuildEditor()
	editor = CreateFrame("Frame", nil, page)
	editor:SetPoint("TOPLEFT", list, "TOPRIGHT", 24, 0)
	editor:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 0)
	editor.preview = {}
	editor.title = UI.Text(editor, 16, "heading", "title")
	editor.title:SetPoint("TOPLEFT")

	local x = LABEL_W
	editor.nameLabel = Label("Name", editor, -34)
	editor.name = Box(FIELD_W, function(text)
		text = text:match("^%s*(.-)%s*$")
		if text ~= "" then
			Edit(function(node)
				node.name = text
			end)
		end
	end)
	editor.name:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -30)

	editor.ruleLabel = Label("Rule", editor, -64)
	editor.rule = Box(FIELD_W, function(text)
		local _, err = ns.BagsSearch_Compile(text)
		if err then
			editor.ruleNote:SetText(err)
			return
		end
		Edit(function(node)
			node.rule = text
		end)
	end)
	editor.rule:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -60)
	editor.ruleNote = UI.Text(editor, 11, "textMuted")
	editor.ruleNote:SetPoint("TOPLEFT", editor.rule, "BOTTOMLEFT", 2, -3)
	editor.ruleNote:SetWidth(FIELD_W)

	editor.priorityLabel = Label("Priority", editor, -140)
	editor.priority = UI.Slider(editor, FIELD_W - 60)
	editor.priority:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -142)
	editor.priority:SetMinMaxValues(-10, 20)
	editor.priority:SetValueStep(1)
	editor.priority:SetObeyStepOnDrag(true)
	editor.priority.onChange = function(value)
		Edit(function(node)
			node.priority = math.floor(value + 0.5)
		end)
	end
	editor.priorityHelp = UI.Text(editor, 11, "textFaint")
	editor.priorityHelp:SetPoint("TOPLEFT", editor.priority, "BOTTOMLEFT", 0, -4)
	editor.priorityHelp:SetText("An item matching two categories goes to the higher priority; on a tie, the one higher up.")
	editor.priorityHelp:SetWidth(FIELD_W)

	editor.flagsLabel = Label("Show", editor, -196)
	editor.ownLine = UI.Checkbox(editor)
	editor.ownLine:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -194)
	editor.ownLineText = UI.Text(editor, 12, "text")
	editor.ownLineText:SetPoint("LEFT", editor.ownLine, "RIGHT", 6, 0)
	editor.ownLineText:SetText("On a row of its own")
	editor.ownLine.onChange = function(on)
		Edit(function(node)
			node.ownLine = on or nil
		end)
	end
	editor.hidden = UI.Checkbox(editor)
	editor.hidden:SetPoint("TOPLEFT", editor.ownLine, "BOTTOMLEFT", 0, -8)
	editor.hiddenText = UI.Text(editor, 12, "text")
	editor.hiddenText:SetPoint("LEFT", editor.hidden, "RIGHT", 6, 0)
	editor.hiddenText:SetText("Hidden (its items aren't shown)")
	editor.hidden.onChange = function(on)
		Edit(function(node)
			node.hidden = on or nil
		end)
	end

	editor.placesLabel = Label("In", editor, -256)
	editor.places = UI.Segmented(editor)
	editor.places:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -252)
	editor.places.choices = function()
		return { { value = "bags", text = "Bags" }, { value = "bank", text = "Bank" },
			{ value = "warband", text = "Warband bank" } }
	end
	editor.places.isOn = function(value)
		local node = Selected()
		return not (node and node.shows and node.shows[value] == false)
	end
	editor.places.toggle = function(value)
		Edit(function(node)
			node.shows = node.shows or {}
			if node.shows[value] == false then
				node.shows[value] = nil
			else
				node.shows[value] = false
			end
			if not next(node.shows) then
				node.shows = nil
			end
		end)
	end

	editor.itemsLabel = Label("Always in it", editor, -290)
	editor.items = Box(FIELD_W, function(text)
		Edit(function(node)
			local ids = ns.BagsEdit_ParseIDs(text)
			node.items = next(ids) and ids or nil
		end)
	end)
	editor.items:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -286)
	editor.items:SetScript("OnReceiveDrag", function()
		local kind, itemID = GetCursorInfo()
		if kind == "item" and itemID then
			ClearCursor()
			Edit(function(node)
				node.items = node.items or {}
				node.items[itemID] = true
			end)
		end
	end)
	editor.itemsHelp = UI.Text(editor, 11, "textFaint")
	editor.itemsHelp:SetPoint("TOPLEFT", editor.items, "BOTTOMLEFT", 2, -3)
	editor.itemsHelp:SetText("Item IDs, or drop an item here. These go in whatever the rules say.")

	editor.sectionLabel = Label("Section", editor, -338)
	editor.section = UI.Dropdown(editor, 200)
	editor.section:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -334)
	editor.section.choices = function()
		local choices = { { value = "", text = "None (top level)" } }
		for _, node in ipairs(ns.Bags_Layout()) do
			if node.kind == "section" then
				choices[#choices + 1] = { value = node.key, text = node.name }
			end
		end
		return choices
	end
	editor.section.getValue = function()
		local _, section = Selected()
		return section and section.key or ""
	end
	editor.section.setValue = function(value)
		local layout = ns.Bags_EditLayout()
		if ns.BagsEdit_SetSection(layout, selected, value ~= "" and value or nil) then
			Changed()
		end
	end

	editor.up = UI.Button(editor, 70, "Move up")
	editor.up:SetPoint("TOPLEFT", editor, "TOPLEFT", x, -376)
	editor.up:SetScript("OnClick", function()
		if ns.BagsEdit_Move(ns.Bags_EditLayout(), selected, -1) then
			Changed()
		end
	end)
	editor.down = UI.Button(editor, 80, "Move down")
	editor.down:SetPoint("LEFT", editor.up, "RIGHT", 6, 0)
	editor.down:SetScript("OnClick", function()
		if ns.BagsEdit_Move(ns.Bags_EditLayout(), selected, 1) then
			Changed()
		end
	end)
	editor.delete = UI.Button(editor, 60, "Delete")
	editor.delete:SetPoint("LEFT", editor.down, "RIGHT", 18, 0)
	editor.delete:SetScript("OnClick", function()
		local node = Selected()
		if not node then
			return
		end
		ns.Confirm_Show(("Delete %s?"):format(node.name or "this divider"), function()
			if ns.BagsEdit_Remove(ns.Bags_EditLayout(), selected) then
				selected = nil
				Changed()
			end
		end)
	end)
	editor.empty = UI.Text(editor, 12, "textMuted")
	editor.empty:SetPoint("TOPLEFT", 0, -34)
	editor.empty:SetText("Pick a category on the left, or add one.")
end

-- The rows that belong to each kind of node.
local CATEGORY_ONLY = {
	"ruleLabel", "rule", "ruleNote", "priorityLabel", "priority", "priorityHelp", "flagsLabel", "ownLine",
	"ownLineText", "hidden", "hiddenText", "placesLabel", "places", "itemsLabel", "items", "itemsHelp",
	"sectionLabel", "section",
}

local function DrawEditor(items)
	local node = Selected()
	editor.empty:SetShown(node == nil)
	local isCategory = node and node.kind == "category"
	for _, key in ipairs(CATEGORY_ONLY) do
		editor[key]:SetShown(isCategory == true)
	end
	local named = node and node.kind ~= "divider"
	editor.nameLabel:SetShown(named == true)
	editor.name:SetShown(named == true)
	for _, key in ipairs({ "up", "down", "delete", "title" }) do
		editor[key]:SetShown(node ~= nil)
	end
	if not node then
		for _, icon in ipairs(editor.preview) do
			icon:Hide()
		end
		return
	end
	editor.title:SetText(node.kind == "section" and "Section" or node.kind == "divider" and "Divider"
		or (node.auto and "Category (automatic)" or "Category"))
	if not editor.name:HasFocus() then
		editor.name:SetText(node.name or "")
	end
	local removable = not (node.auto == "other" or node.auto == "empty")
	editor.delete:SetEnabled(removable)
	if not isCategory then
		for _, icon in ipairs(editor.preview) do
			icon:Hide()
		end
		return
	end
	local auto = node.auto ~= nil
	if not editor.rule:HasFocus() then
		editor.rule:SetText(auto and "" or (node.rule or ""))
	end
	editor.rule:SetEnabled(not auto)
	local shown = auto and 0 or PreviewIcons(items, node.rule)
	if auto then
		editor.ruleNote:SetText("Filled by the game: new items, equipment sets, items no other category takes, empty "
			.. "slots.")
		for _, icon in ipairs(editor.preview) do
			icon:Hide()
		end
	else
		local _, err = ns.BagsSearch_Compile(node.rule or "")
		editor.ruleNote:SetText(err or (shown > 0 and "Matches in your bags now:" or "Nothing in your bags matches."))
	end
	editor.priority:SetValue(node.priority or 0)
	editor.ownLine:SetChecked(node.ownLine == true)
	editor.hidden:SetChecked(node.hidden == true)
	editor.places:Refresh()
	if not editor.items:HasFocus() then
		editor.items:SetText(ns.BagsEdit_IDsText(node.items))
	end
	editor.section:Refresh()
end

function Refresh()
	if not (page and page:IsVisible()) then
		return
	end
	local layout = ns.Bags_Layout()
	if selected and not ns.BagsEdit_Find(layout, selected) then
		selected = nil
	end
	local byKey, items = Contents()
	DrawList(layout, byKey)
	DrawEditor(items)
end

-- The page -----------------------------------------------------------------------------------------------------------

local function TopButtons()
	local add = UI.Button(page, 110, "Add category")
	UI.FitButton(add, 100)
	add:SetPoint("TOPLEFT", 8, 0)
	add:SetScript("OnClick", function()
		selected = ns.BagsEdit_AddCategory(ns.Bags_EditLayout(), "New category", "").key
		Changed()
		editor.name:SetFocus()
		editor.name:HighlightText()
	end)
	local sec = UI.Button(page, 100, "Add section")
	UI.FitButton(sec, 90)
	sec:SetPoint("LEFT", add, "RIGHT", 6, 0)
	sec:SetScript("OnClick", function()
		selected = ns.BagsEdit_AddSection(ns.Bags_EditLayout(), "New section").key
		Changed()
	end)
	local div = UI.Button(page, 90, "Add divider")
	UI.FitButton(div, 80)
	div:SetPoint("LEFT", sec, "RIGHT", 6, 0)
	div:SetScript("OnClick", function()
		selected = ns.BagsEdit_AddDivider(ns.Bags_EditLayout()).key
		Changed()
	end)
	local reset = UI.Button(page, 90, "Defaults")
	UI.FitButton(reset, 80)
	reset:SetPoint("TOPRIGHT", -8, 0)
	reset:SetScript("OnClick", function()
		ns.Confirm_Show("Go back to the default categories? Your own categories and changes are removed.", function()
			wipe(db.layout)
			selected = nil
			Changed()
		end)
	end)
	local import = UI.Button(page, 70, "Import")
	UI.FitButton(import, 60)
	import:SetPoint("RIGHT", reset, "LEFT", -6, 0)
	import:SetScript("OnClick", function()
		ns.Dialog_Show({
			title = "Import categories", hint = "Paste categories someone shared", text = "", saveText = "Import",
			onSave = function(text)
				local added, err = ns.BagsEdit_Import(ns.Bags_EditLayout(), text)
				if not added then
					return err
				end
				ns.Print(("%d categories or sections added at the top."):format(#added))
				Changed()
				return nil
			end,
		})
	end)
	local share = UI.Button(page, 70, "Share")
	UI.FitButton(share, 60)
	share:SetPoint("RIGHT", import, "LEFT", -6, 0)
	share:SetScript("OnClick", function()
		local node = Selected()
		local nodes = node and node.kind ~= "divider" and { node } or ns.Bags_Layout()
		ns.Dialog_Show({
			title = node and ("Share " .. (node.name or "")) or "Share every category",
			hint = "Copy this and send it; Import on the other side.",
			text = ns.BagsEdit_Export(nodes), readOnly = true,
		})
	end)
	share:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Share")
		UI.TipLine("The picked category or section, or all of them when nothing is picked.", "textMuted", true)
		GameTooltip:Show()
	end)
	share:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

function ns.BagsEditPage_Init(moduleDB)
	db = moduleDB
end

function ns.BagsEditPage_Create(frame)
	page = frame
	rows = {}
	list = UI.Scroll(page)
	list:SetPoint("TOPLEFT", 8, -TOP)
	list:SetPoint("BOTTOMLEFT", 8, 0)
	list:SetWidth(LIST_W)
	TopButtons()
	BuildEditor()
end

function ns.BagsEditPage_Refresh()
	Refresh()
end

-- Opens the page with a category picked (Save as category).
function ns.BagsEditPage_Select(key)
	selected = key
	ns.Panel_OpenPage("bagcategories")
	Refresh()
end
