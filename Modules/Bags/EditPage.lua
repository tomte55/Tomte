local addonName, ns = ...

-- Bags: the "Bag categories" page in the Tomte window, built from Kit.lua (docs/superpowers/specs/
-- 2026-10-27-tomte-bags-ui-design.md). A band with two clusters (add a category, section or divider; share, import,
-- defaults), the list left in a tray (EditList.lua, rows drag to reorder), and the picked node right: its name as a
-- large title you can type in, then "What goes in" (the rule, saved as you type, and the items it matches), "When two
-- categories want an item" (priority), "Where it shows" (bags, bank, Warband bank, own row, hidden), "Always in it"
-- (items dropped there, as icons) and a bottom row (section, move up / down, delete). The editing is EditData.lua's;
-- registered in Bags.lua.

local LIST_W = 270
local BAND_H = 34
local GAP = 12 -- between groups
local GROUP_PAD = 10
local PREVIEW = 18 -- matching items shown under the rule
local PREVIEW_ICON = 24
local ALWAYS = 18 -- items shown in "Always in it"
local ALWAYS_ICON = 28
local SLIDER_W = 170

local UI = ns.UI

local db, page, band, list, editor
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

local function Selected()
	if not selected then
		return nil
	end
	local _, _, node, section = ns.BagsEdit_Find(ns.Bags_Layout(), selected)
	return node, section
end

-- Every edit goes to the player's own copy (made from the defaults the first time). key: the node to change
-- (default: the picked one).
local function Edit(fn, key)
	local layout = ns.Bags_EditLayout()
	local _, _, node, section = ns.BagsEdit_Find(layout, key or selected)
	if node then
		fn(node, layout, section)
		Changed()
	end
end

-- Pieces -------------------------------------------------------------------------------------------------------------

-- A framed group with a small heading; content goes below group.top (pixels from its top).
local function Group(parent, heading)
	local g = CreateFrame("Frame", nil, parent)
	local fill = g:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0, 0, 0, 0.18)
	UI.Border(g, "rule")
	g.heading = UI.Text(g, 11, "textMuted", "label")
	g.heading:SetPoint("TOPLEFT", GROUP_PAD, -8)
	g.heading:SetText(heading)
	g.top = 26
	return g
end

local function Check(parent, text, onChange)
	local c = UI.Checkbox(parent)
	c.text = UI.Text(parent, 12, "text")
	c.text:SetPoint("LEFT", c, "RIGHT", 6, 0)
	c.text:SetText(text)
	c.onChange = onChange
	return c
end

local function KeywordHelp(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	GameTooltip:SetText("Rules")
	UI.TipLine("The same search as the bag window's: words find names and types, is: finds a kind of item, and, or, "
		.. "not, - and ( ) combine them.", "textMuted", true)
	UI.TipLine("ilvl>=600, count>20, price>10 (gold), exp:tww", "textMuted", true)
	GameTooltip:Show()
end

-- The editor ---------------------------------------------------------------------------------------------------------

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
				icon = editor.what:CreateTexture(nil, "ARTWORK")
				icon:SetSize(PREVIEW_ICON, PREVIEW_ICON)
				editor.preview[n] = icon
			end
			icon:SetTexture(item.icon)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", editor.rule, "BOTTOMLEFT", (n - 1) * (PREVIEW_ICON + 3), -8)
			icon:Show()
		end
	end
	for i = n + 1, #editor.preview do
		editor.preview[i]:Hide()
	end
	return n
end

local function AlwaysIcon(i)
	local b = editor.always[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, editor.drop)
	b:SetSize(ALWAYS_ICON, ALWAYS_ICON)
	b:RegisterForClicks("RightButtonUp")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	UI.Border(b, "rule")
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.itemID)
		UI.TipLine("Right-click: take it out", "textMuted")
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		local id = self.itemID
		Edit(function(node)
			if node.items then
				node.items[id] = nil
				if not next(node.items) then
					node.items = nil
				end
			end
		end)
	end)
	editor.always[i] = b
	return b
end

local function DrawAlways(node)
	local ids = {}
	for id in pairs(node.items or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local fit = math.max(math.floor((editor.drop:GetWidth() - 12) / (ALWAYS_ICON + 3)), 1)
	local shown = math.min(#ids, ALWAYS, fit)
	for i = 1, shown do
		local b = AlwaysIcon(i)
		b.itemID = ids[i]
		b.icon:SetTexture(C_Item.GetItemIconByID(ids[i]))
		b:ClearAllPoints()
		b:SetPoint("LEFT", editor.drop, "LEFT", 6 + (i - 1) * (ALWAYS_ICON + 3), 0)
		b:Show()
	end
	for i = shown + 1, #editor.always do
		editor.always[i]:Hide()
	end
	editor.dropHint:SetShown(#ids == 0)
end

local function DropItem()
	local kind, itemID = GetCursorInfo()
	if kind == "item" and itemID then
		ClearCursor()
		Edit(function(node)
			node.items = node.items or {}
			node.items[itemID] = true
		end)
	end
end

local function BuildEditor()
	editor = CreateFrame("Frame", nil, page)
	editor:SetPoint("TOPLEFT", list, "TOPRIGHT", 20, 0)
	editor:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 0)
	editor.preview, editor.always = {}, {}

	-- The name as a large title you can type in (Enter or clicking away saves a change; Escape puts it back).
	editor.name = CreateFrame("EditBox", nil, editor)
	editor.name:SetHeight(30)
	editor.name:SetPoint("TOPLEFT", 0, 0)
	editor.name:SetPoint("RIGHT", 0, 0)
	editor.name:SetAutoFocus(false)
	UI.SetFont(editor.name, "title", 18)
	UI.SetTextRole(editor.name, "heading")
	editor.name:SetTextInsets(6, 6, 0, 0)
	UI.Border(editor.name, "rule", 0)
	editor.name:SetScript("OnEditFocusGained", function(self)
		self.before = self:GetText()
		UI.SetBorderColor(self, "accent")
	end)
	editor.name:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, "rule", 0)
		if self.reverting then
			self.reverting = false
			Refresh()
			return
		end
		local text = self:GetText():match("^%s*(.-)%s*$")
		if text ~= "" and text ~= self.before then
			Edit(function(node)
				node.name = text
			end)
		end
	end)
	editor.name:SetScript("OnEnterPressed", editor.name.ClearFocus)
	editor.name:SetScript("OnEscapePressed", function(self)
		self.reverting = true
		self:ClearFocus()
	end)
	editor.kind = UI.Text(editor, 11, "textMuted", "label")
	editor.kind:SetPoint("TOPLEFT", editor.name, "BOTTOMLEFT", 6, -2)

	-- What goes in: the rule, saved as you type; the items it matches.
	editor.what = Group(editor, "What goes in")
	editor.what:SetPoint("TOPLEFT", 0, -56)
	editor.what:SetPoint("RIGHT", 0, 0)
	editor.what:SetHeight(26 + 22 + 8 + PREVIEW_ICON + 8 + 16 + GROUP_PAD)
	editor.rule = ns.BagsKit_Search(editor.what, "A search, like is:food", function()
		local text = editor.rule:GetText()
		local _, err = ns.BagsSearch_Compile(text)
		editor.rule:SetError(err)
		-- Saved to the category the box shows (editor.rule.key), never to a row picked since.
		local key = editor.rule.key
		local _, _, node = ns.BagsEdit_Find(ns.Bags_Layout(), key or "")
		if not err and node and node.kind == "category" and not node.auto and text ~= (node.rule or "") then
			Edit(function(n)
				n.rule = text
			end, key)
		end
	end)
	editor.rule:SetPoint("TOPLEFT", GROUP_PAD, -editor.what.top)
	editor.rule:SetPoint("RIGHT", -GROUP_PAD, 0)
	editor.rule.help:SetScript("OnEnter", KeywordHelp)
	editor.result = UI.Text(editor.what, 11, "textMuted")
	editor.result:SetPoint("BOTTOMLEFT", GROUP_PAD, GROUP_PAD - 2)
	editor.result:SetPoint("RIGHT", -GROUP_PAD, 0)

	-- When two categories want an item: the priority.
	editor.prio = Group(editor, "When two categories want an item")
	editor.prio:SetPoint("TOPLEFT", editor.what, "BOTTOMLEFT", 0, -GAP)
	editor.prio:SetPoint("RIGHT", editor, "CENTER", -GAP / 2, 0)
	editor.prio:SetHeight(104)
	local lower = UI.Text(editor.prio, 11, "textFaint")
	lower:SetPoint("TOPLEFT", GROUP_PAD, -editor.prio.top - 4)
	lower:SetText("lower")
	editor.priority = UI.Slider(editor.prio, SLIDER_W)
	editor.priority:SetPoint("LEFT", lower, "RIGHT", 8, 0)
	editor.priority:SetMinMaxValues(-10, 20)
	editor.priority:SetValueStep(1)
	editor.priority:SetObeyStepOnDrag(true)
	local higher = UI.Text(editor.prio, 11, "textFaint")
	higher:SetPoint("TOPRIGHT", -GROUP_PAD, -editor.prio.top - 4)
	higher:SetText("higher")
	editor.priority:SetPoint("RIGHT", higher, "LEFT", -8, 0) -- the slider stretches to the group's width
	editor.priority.onChange = function(value)
		Edit(function(node)
			node.priority = math.floor(value + 0.5)
		end)
	end
	local prioHelp = UI.Text(editor.prio, 11, "textMuted")
	prioHelp:SetPoint("TOPLEFT", lower, "BOTTOMLEFT", 0, -16)
	prioHelp:SetPoint("RIGHT", -GROUP_PAD, 0)
	prioHelp:SetJustifyH("LEFT")
	prioHelp:SetText("The higher priority takes the item; on a tie, the one higher in the list.")

	-- Where it shows.
	editor.where = Group(editor, "Where it shows")
	editor.where:SetPoint("TOPLEFT", editor.what, "BOTTOM", GAP / 2, -GAP)
	editor.where:SetPoint("RIGHT", 0, 0)
	editor.where:SetHeight(104)
	editor.places = UI.Segmented(editor.where)
	editor.places:SetPoint("TOPLEFT", GROUP_PAD, -editor.where.top)
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
	editor.ownLine = Check(editor.where, "On a row of its own", function(on)
		Edit(function(node)
			node.ownLine = on or nil
		end)
	end)
	editor.ownLine:SetPoint("TOPLEFT", editor.places, "BOTTOMLEFT", 0, -10)
	editor.hidden = Check(editor.where, "Hidden (its items aren't shown)", function(on)
		Edit(function(node)
			node.hidden = on or nil
		end)
	end)
	editor.hidden:SetPoint("TOPLEFT", editor.ownLine, "BOTTOMLEFT", 0, -6)

	-- Always in it: items dropped here go in whatever the rules say.
	editor.alwaysGroup = Group(editor, "Always in it")
	editor.alwaysGroup:SetPoint("TOPLEFT", editor.prio, "BOTTOMLEFT", 0, -GAP)
	editor.alwaysGroup:SetPoint("RIGHT", 0, 0)
	editor.alwaysGroup:SetHeight(26 + ALWAYS_ICON + 12 + GROUP_PAD)
	editor.drop = CreateFrame("Button", nil, editor.alwaysGroup)
	editor.drop:SetPoint("TOPLEFT", GROUP_PAD, -editor.alwaysGroup.top)
	editor.drop:SetPoint("RIGHT", -GROUP_PAD - 70, 0)
	editor.drop:SetHeight(ALWAYS_ICON + 8)
	UI.Border(editor.drop, "frame", 0.6)
	editor.drop:SetScript("OnReceiveDrag", DropItem)
	editor.drop:SetScript("OnClick", DropItem)
	editor.dropHint = UI.Text(editor.drop, 11, "textFaint")
	editor.dropHint:SetPoint("LEFT", 8, 0)
	editor.dropHint:SetText("Drop items here to keep them in this category")
	editor.paste = CreateFrame("Button", nil, editor.alwaysGroup)
	editor.paste:SetSize(64, 20)
	editor.paste:SetPoint("LEFT", editor.drop, "RIGHT", 6, 0)
	editor.paste.text = UI.Text(editor.paste, 11, "accent")
	editor.paste.text:SetPoint("CENTER")
	editor.paste.text:SetText("Paste IDs")
	editor.paste:SetScript("OnClick", function()
		local node = Selected()
		ns.Dialog_Show({
			title = "Items always in " .. (node and node.name or "it"), hint = "Item IDs, separated by commas or spaces",
			text = ns.BagsEdit_IDsText(node and node.items), saveText = "Save",
			onSave = function(text)
				Edit(function(n)
					local ids = ns.BagsEdit_ParseIDs(text)
					n.items = next(ids) and ids or nil
				end)
				return nil
			end,
		})
	end)

	-- Bottom row: section, move, delete.
	editor.section = UI.Dropdown(editor, 150)
	editor.section:SetPoint("TOPLEFT", editor.alwaysGroup, "BOTTOMLEFT", 0, -GAP)
	editor.section.choices = function()
		local choices = { { value = "", text = "No section" } }
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
		if ns.BagsEdit_SetSection(ns.Bags_EditLayout(), selected, value ~= "" and value or nil) then
			Changed()
		end
	end
	editor.move = ns.BagsKit_Cluster(editor, {
		{ text = "Move up", onClick = function()
			if ns.BagsEdit_Move(ns.Bags_EditLayout(), selected, -1) then
				Changed()
			end
		end },
		{ text = "Move down", onClick = function()
			if ns.BagsEdit_Move(ns.Bags_EditLayout(), selected, 1) then
				Changed()
			end
		end },
	})
	editor.delete = ns.BagsKit_Cluster(editor, { { text = "Delete", onClick = function()
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
	end } })
	UI.SetTextRole(editor.delete.buttons[1].label, "danger")
	editor.delete:SetPoint("TOPRIGHT", editor.alwaysGroup, "BOTTOMRIGHT", 0, -GAP)

	editor.empty = UI.Text(editor, 13, "textMuted")
	editor.empty:SetPoint("TOPLEFT", 6, -8)
	editor.empty:SetText("Pick a category on the left, or add one. Drag rows to reorder them.")
end

-- What shows for each kind of node.
local CATEGORY_ONLY = { "what", "prio", "where", "alwaysGroup", "section" }

local function DrawEditor(items)
	local node = Selected()
	editor.empty:SetShown(node == nil)
	local isCategory = node ~= nil and node.kind == "category"
	for _, key in ipairs(CATEGORY_ONLY) do
		editor[key]:SetShown(isCategory)
	end
	editor.name:SetShown(node ~= nil and node.kind ~= "divider")
	editor.kind:SetShown(node ~= nil)
	editor.move:SetShown(node ~= nil)
	editor.delete:SetShown(node ~= nil)
	if not node then
		return
	end
	-- Sections and dividers have only the bottom row, under the title.
	editor.move:ClearAllPoints()
	if isCategory then
		editor.move:SetPoint("LEFT", editor.section, "RIGHT", 10, 0)
	else
		editor.move:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, -56)
	end
	editor.delete:ClearAllPoints()
	if isCategory then
		editor.delete:SetPoint("TOPRIGHT", editor.alwaysGroup, "BOTTOMRIGHT", 0, -GAP)
	else
		editor.delete:SetPoint("LEFT", editor.move, "RIGHT", 18, 0)
	end
	editor.kind:SetText(node.kind == "section" and "Section" or node.kind == "divider" and "Divider"
		or (node.auto and "Category, filled by the game" or "Category"))
	if not editor.name:HasFocus() then
		editor.name:SetText(node.name or "")
	end
	local removable = not (node.auto == "other" or node.auto == "empty")
	editor.delete:SetAlpha(removable and 1 or 0.4)
	editor.delete.buttons[1]:SetEnabled(removable)
	if not isCategory then
		return
	end
	local auto = node.auto ~= nil
	if not editor.rule:HasFocus() then
		editor.rule.key = node.key
		editor.rule:SetText(auto and "" or (node.rule or ""))
	end
	editor.rule:SetEnabled(not auto)
	if auto then
		PreviewIcons(items, nil)
		editor.rule:SetError(nil)
		UI.SetTextRole(editor.result, "textMuted")
		editor.result:SetText("The game fills this one: new items, equipment sets, items no other category takes, or "
			.. "empty slots.")
	else
		local _, err, usesText = ns.BagsSearch_Compile(node.rule or "")
		if usesText then
			ns.BagsRead_LoadText(items) -- words look in the tooltip too
		end
		local shown = PreviewIcons(items, node.rule)
		if err then
			UI.SetTextRole(editor.result, "danger")
			editor.result:SetText(err)
		elseif shown > 0 then
			UI.SetTextRole(editor.result, "success")
			editor.result:SetText(shown == 1 and "1 item in your bags matches"
				or ("%d items in your bags match"):format(shown))
		else
			UI.SetTextRole(editor.result, "textMuted")
			editor.result:SetText("Nothing in your bags matches.")
		end
	end
	editor.priority:SetValue(node.priority or 0)
	editor.ownLine:SetChecked(node.ownLine == true)
	editor.hidden:SetChecked(node.hidden == true)
	editor.places:Refresh()
	DrawAlways(node)
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
	ns.BagsEditList_Draw(list, layout, byKey, selected)
	DrawEditor(items)
end

-- The page -----------------------------------------------------------------------------------------------------------

local function Share()
	local node = Selected()
	local nodes = node and node.kind ~= "divider" and { node } or ns.Bags_Layout()
	ns.Dialog_Show({
		title = node and ("Share " .. (node.name or "")) or "Share every category",
		hint = "Copy this and send it; Import on the other side.",
		text = ns.BagsEdit_Export(nodes), readOnly = true,
	})
end

local function Import()
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
end

local function BuildBand()
	band = ns.BagsKit_Band(page)
	band:SetPoint("TOPLEFT", 0, 0)
	band:SetPoint("TOPRIGHT", 0, 0)
	band:SetHeight(BAND_H)
	local add = ns.BagsKit_Cluster(band, {
		{ text = "+ Category", tip = "Add a category", tipLine = "It starts at the top of your bags; drag it where you want it.",
			onClick = function()
				selected = ns.BagsEdit_AddCategory(ns.Bags_EditLayout(), "New category", "").key
				Changed()
				editor.name:SetFocus()
				editor.name:HighlightText()
			end },
		{ text = "+ Section", tip = "Add a section", tipLine = "A heading; drop categories into it.",
			onClick = function()
				selected = ns.BagsEdit_AddSection(ns.Bags_EditLayout(), "New section").key
				Changed()
			end },
		{ text = "+ Divider", tip = "Add a divider", tipLine = "A line across the bags.", onClick = function()
			selected = ns.BagsEdit_AddDivider(ns.Bags_EditLayout()).key
			Changed()
		end },
	})
	add:SetPoint("LEFT", 8, 0)
	local share = ns.BagsKit_Cluster(band, {
		{ text = "Share", tip = "Share", tipLine = "The picked category or section, or all of them when nothing is picked.",
			onClick = Share },
		{ text = "Import", tip = "Import categories someone shared", onClick = Import },
		{ text = "Defaults", tip = "Back to the default categories", onClick = function()
			ns.Confirm_Show("Go back to the default categories? Your own categories and changes are removed.", function()
				wipe(db.layout)
				selected = nil
				Changed()
			end)
		end },
	})
	share:SetPoint("RIGHT", -8, 0)
end

function ns.BagsEditPage_Init(moduleDB)
	db = moduleDB
end

function ns.BagsEditPage_Create(frame)
	page = frame
	BuildBand()
	list = ns.BagsEditList_Create(page, function(key)
		-- The boxes let go first: a rename still typed goes to the node it was typed for.
		editor.name:ClearFocus()
		editor.rule:ClearFocus()
		selected = key
		Refresh()
	end, function(key, targetKey, where)
		editor.name:ClearFocus()
		editor.rule:ClearFocus()
		local layout = ns.Bags_EditLayout()
		local _, _, dragged = ns.BagsEdit_Find(layout, key)
		local _, _, target = ns.BagsEdit_Find(layout, targetKey)
		-- A category dropped just under a section's heading goes first into that section (where the line showed).
		if where == "after" and dragged and dragged.kind == "category" and target and target.kind == "section" then
			local first = target.children and target.children[1]
			if first then
				targetKey, where = first.key, "before"
			else
				where = "into"
			end
		end
		if ns.BagsEdit_MoveTo(layout, key, targetKey, where) then
			selected = key
			Changed()
		end
	end)
	list:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, -10)
	list:SetPoint("BOTTOMLEFT", 0, 0)
	list:SetWidth(LIST_W)
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
