local addonName, ns = ...

-- Decorating tools: the Decorating panel in the house editor. Three tabs: Clipboard (copied and cut decor), Recent
-- (last placed) and Saved (favorites and tags, set from the right-click menu of Blizzard's storage list,
-- CatalogMenu.lua). A click picks a decor up; a right-click offers the quickbar slots and more. Export and Import
-- share a decor list as text. Opened by the quickbar's panel button (Quickbar.lua); remembers where it was dragged.
-- Rules in ToolsData.lua; registered in Decorate.lua.

local WIDTH, HEIGHT = 300, 430
local PAD = 10
local ROW_H = 30
local HEADER_H = 24 -- a tag's title row on the Saved tab
local TOP = 64 -- the title and the tabs above the list
local BOTTOM = 40 -- the buttons under the list
local SLOTS = 8
-- A click that picks a decor up waits this long: the same click would otherwise drop the new decor at the mouse.
local CLICK_DELAY = 0.1
local TABS = { { value = "clipboard", text = "Clipboard" }, { value = "recent", text = "Recent" },
	{ value = "saved", text = "Saved" } }
local EMPTY = {
	clipboard = "Nothing copied yet. Copy or cut a decor in the editor, or import a list.",
	recent = "Decor you place shows here.",
	saved = "Right-click a decor in Blizzard's storage list to make it a favorite or tag it.",
}
local UI = ns.UI

local db
local active, editing = false, false
local panel
local rows = {}

local function Refresh()
	if panel and panel:IsShown() then
		panel.Layout()
	end
end

-- Rows ----------------------------------------------------------------------------------------------------------------

-- Clipboard decor come turned as they were copied.
local function PickUp(decorID, tab)
	if tab == "clipboard" then
		ns.DecorateClip_PlaceEntry(decorID, CLICK_DELAY)
	else
		ns.DecorateClip_Place(decorID, { delay = CLICK_DELAY })
	end
end

local function RowMenu(row)
	local decorID, tab = row.decorID, db.dock.tab
	UI.ContextMenu(row, function(_, root)
		root:CreateTitle((ns.DecorPlace_Look(decorID)))
		root:CreateButton("Pick it up", function()
			PickUp(decorID, tab)
		end)
		local slots = root:CreateButton("Put on the quickbar")
		for slot = 1, SLOTS do
			local current = db.slots[slot]
			local text = current and ("Slot %d (now %s)"):format(slot, (ns.DecorPlace_Look(current)))
				or ("Slot %d"):format(slot)
			slots:CreateButton(text, function()
				ns.DecorateBar_Set(slot, decorID)
			end)
		end
		if tab == "clipboard" then
			root:CreateButton("Remove from the clipboard", function()
				ns.DecorateClip_Remove(decorID)
			end)
		else
			root:CreateButton("Copy to the clipboard", function()
				ns.DecorateClip_Add(decorID)
			end)
		end
		if tab == "saved" and row.tag then
			root:CreateButton(("Remove from %s"):format(row.tag), function()
				ns.DecorTools_TagToggle(db.tags, row.tag, decorID)
				Refresh()
			end)
		elseif tab == "saved" then
			root:CreateButton("Unfavorite", function()
				db.favorites[decorID] = nil
				Refresh()
			end)
		end
	end)
end

local function RowEnter(row)
	row.wash:SetAlpha(1)
	if not row.decorID then
		if row.tag then
			GameTooltip:SetOwner(row, "ANCHOR_LEFT")
			GameTooltip:SetText(row.tag, UI.Color("heading"))
			UI.TipLine("Right-click: delete this tag", "textMuted")
			GameTooltip:Show()
		end
		return
	end
	local info = ns.DecorPlace_CatalogInfo(row.decorID)
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	GameTooltip:SetText((ns.DecorPlace_Look(row.decorID)), UI.Color("heading"))
	for _, line in ipairs(ns.DecorEditor_HoverLines(info, false)) do
		UI.TipLine(line[1], line[2])
	end
	GameTooltip:AddLine(" ")
	UI.TipLine("Click: pick it up", "accent")
	UI.TipLine("Right-click: quickbar and more", "textMuted")
	GameTooltip:Show()
end

local function RowLeave(row)
	row.wash:SetAlpha(0)
	GameTooltip:Hide()
end

-- A tag's title row: right-click deletes the tag.
local function HeaderMenu(row)
	local tag = row.tag
	UI.ContextMenu(row, function(_, root)
		root:CreateTitle(tag)
		root:CreateButton("Delete this tag", function()
			ns.Confirm_Show(("Delete the tag %s?\n\nThe decor in it stay in your storage."):format(tag), function()
				db.tags[tag] = nil
				Refresh()
			end)
		end)
	end)
end

local function RowClick(row, button)
	if not row.decorID then
		if row.tag and button == "RightButton" then
			HeaderMenu(row)
		end
		return
	end
	if button == "RightButton" then
		RowMenu(row)
	else
		PickUp(row.decorID, db.dock.tab)
	end
end

local function CreateRow(i)
	local row = CreateFrame("Button", nil, panel.list.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.wash = row:CreateTexture(nil, "BACKGROUND")
	row.wash:SetAllPoints()
	row.wash:SetColorTexture(UI.Color("hover"))
	row.wash:SetAlpha(0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_H - 6, ROW_H - 6)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.right = UI.Text(row, 11, "textMuted", "number")
	row.right:SetPoint("RIGHT", -6, 0)
	row.right:SetJustifyH("RIGHT")
	row.name = UI.Text(row, 12, "text")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.title = UI.Text(row, 12, "accent", "title")
	row.title:SetPoint("BOTTOMLEFT", 4, 3)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	row:SetScript("OnClick", RowClick)
	rows[i] = row
	return row
end

local function Row(i)
	local row = rows[i] or CreateRow(i)
	row:ClearAllPoints()
	row:Show()
	return row
end

-- A decor row: icon, name, how many in storage, and on the clipboard how many are still to place.
local function FillDecor(row, decorID, extra)
	row.decorID, row.tag = decorID, nil
	row:EnableMouse(true)
	row.title:Hide()
	row.icon:Show()
	row.name:Show()
	row.right:Show()
	ns.DecorPlace_SetIcon(row.icon, decorID)
	local name = ns.DecorPlace_Look(decorID)
	local stored = ns.DecorEditor_Stored(ns.DecorPlace_CatalogInfo(decorID))
	row.icon:SetDesaturated(stored == 0)
	row.name:SetText(name)
	UI.SetTextRole(row.name, stored > 0 and "text" or "textMuted")
	local right = ("x%d"):format(stored)
	if extra then
		right = UI.Wrap(extra, "accent") .. "   " .. right
	end
	row.right:SetText(right)
end

local function FillHeader(row, title, tag)
	row.decorID, row.tag = nil, tag
	row:EnableMouse(tag ~= nil)
	row.icon:Hide()
	row.name:Hide()
	row.right:Hide()
	row.title:Show()
	row.title:SetText(title)
end

local function Entries()
	local tab = db.dock.tab
	local out = {}
	if tab == "clipboard" then
		for _, e in ipairs(db.clipboard) do
			out[#out + 1] = { id = e.id, extra = (e.cut or 0) > 0 and ("%d to place"):format(e.cut) or nil }
		end
	elseif tab == "recent" then
		for _, id in ipairs(db.recent) do
			out[#out + 1] = { id = id }
		end
	else
		local function nameOf(id)
			return (ns.DecorPlace_Look(id))
		end
		for _, group in ipairs(ns.DecorTools_SavedGroups(db.favorites, db.tags, nameOf)) do
			out[#out + 1] = { header = group.title, tag = group.tag }
			for _, id in ipairs(group.ids) do
				out[#out + 1] = { id = id, tag = group.tag }
			end
		end
	end
	return out
end

local function Layout()
	local entries = Entries()
	local y = 0
	for i, e in ipairs(entries) do
		local row = Row(i)
		local h = e.header and HEADER_H or ROW_H
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", panel.list.content, "RIGHT", 0, 0)
		row:SetHeight(h)
		if e.header then
			FillHeader(row, e.header, e.tag)
		else
			FillDecor(row, e.id, e.extra)
			row.tag = e.tag
		end
		y = y + h
	end
	for i = #entries + 1, #rows do
		rows[i]:Hide()
	end
	panel.list:SetContentHeight(y)
	panel.empty:SetText(EMPTY[db.dock.tab])
	panel.empty:SetShown(#entries == 0)
	panel.tabs:Refresh()
	local clip = db.dock.tab == "clipboard"
	panel.clear:SetShown(clip or db.dock.tab == "recent")
	panel.export:SetShown(true)
	panel.import:SetShown(clip)
end

-- Export and import -----------------------------------------------------------------------------------------------------

local function ShowExport(items, what)
	if #items == 0 then
		ns.DecorPlace_Error(("Nothing to export: %s is empty."):format(what))
		return
	end
	ns.Dialog_Show({ title = "Export decor", readOnly = true, text = ns.DecorTools_ShareEncode(items),
		hint = ("%d decor from %s. Copy the text (Ctrl+C) and share it; Import in Tomte's Decorating panel reads it.")
			:format(#items, what) })
end

local function ExportMenu(button)
	UI.ContextMenu(button, function(_, root)
		root:CreateTitle("Export")
		root:CreateButton("The clipboard", function()
			local items = {}
			for _, e in ipairs(db.clipboard) do
				items[#items + 1] = { id = e.id, count = math.max(e.cut or 0, 1) }
			end
			ShowExport(items, "the clipboard")
		end)
		root:CreateButton("Decor placed in this house", function()
			local ids, why = ns.DecoratePlaced_IDs()
			if not ids then
				ns.DecorPlace_Error(why)
				return
			end
			ShowExport(ns.DecorTools_CountIDs(ids), "this house")
		end)
	end)
end

local function Import()
	ns.Dialog_Show({ title = "Import decor", text = "", saveText = "Import", height = 200,
		hint = "Paste a decor list (it starts with TomteDecor1:). It goes on the clipboard.",
		onSave = function(text)
			local items, why = ns.DecorTools_ShareDecode(text)
			if not items then
				return why
			end
			if #db.clipboard == 0 then
				ns.DecorateClip_Import(items, false)
				return nil
			end
			C_Timer.After(0, function()
				ns.Confirm_Show(("Replace the clipboard with these %d decor?\n\nAdd puts them on top of what's there.")
					:format(#items), function()
					ns.DecorateClip_Import(items, true)
				end, { yes = "Replace", no = "Add", onNo = function()
					ns.DecorateClip_Import(items, false)
				end })
			end)
			return nil
		end })
end

-- Panel ---------------------------------------------------------------------------------------------------------------

local function SavePosition()
	local left, top = panel:GetLeft(), panel:GetTop()
	local parentLeft, parentBottom = HouseEditorFrame:GetLeft(), HouseEditorFrame:GetBottom()
	if left and top and parentLeft and parentBottom then
		db.dock.x, db.dock.y = left - parentLeft, top - parentBottom
	end
end

local function Place()
	panel:ClearAllPoints()
	if db.dock.x and db.dock.y then
		panel:SetPoint("TOPLEFT", HouseEditorFrame, "BOTTOMLEFT", db.dock.x, db.dock.y)
	else
		panel:SetPoint("RIGHT", HouseEditorFrame, "RIGHT", -24, 40)
	end
end

local function SmallButton(text, onClick)
	local b = UI.Button(panel, 70, text)
	UI.FitButton(b, 60)
	b:SetScript("OnClick", onClick)
	return b
end

local function CreatePanel()
	if panel or not HouseEditorFrame then
		return
	end
	panel = CreateFrame("Frame", nil, HouseEditorFrame)
	panel:SetSize(WIDTH, HEIGHT)
	panel:SetFrameStrata("HIGH")
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
		Place()
	end)
	UI.Panel(panel)
	local title = UI.Text(panel, 15, "heading", "title")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Decorating")
	local close = UI.Button(panel, 20, "x")
	close:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
	close:SetScript("OnClick", function()
		ns.DecorateDock_Toggle()
	end)
	panel.tabs = UI.Segmented(panel)
	panel.tabs:SetPoint("TOPLEFT", PAD, -34)
	panel.tabs.choices = function()
		return TABS
	end
	panel.tabs.getValue = function()
		return db.dock.tab
	end
	panel.tabs.setValue = function(value)
		db.dock.tab = value
		panel.list:SetScroll(0)
		Layout()
	end
	panel.list = UI.Scroll(panel)
	panel.list:SetPoint("TOPLEFT", PAD, -TOP)
	panel.list:SetPoint("BOTTOMRIGHT", -PAD - 6, BOTTOM)
	panel.empty = UI.Text(panel, 12, "textMuted")
	panel.empty:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 4, -8)
	panel.empty:SetPoint("RIGHT", panel.list, "RIGHT", -4, 0)
	panel.empty:SetJustifyH("LEFT")
	panel.empty:SetWordWrap(true)
	panel.export = SmallButton("Export", function(self)
		ExportMenu(self)
	end)
	panel.export:SetPoint("BOTTOMLEFT", PAD, 10)
	panel.import = SmallButton("Import", Import)
	panel.import:SetPoint("LEFT", panel.export, "RIGHT", 6, 0)
	panel.clear = SmallButton("Clear", function()
		local tab = db.dock.tab
		ns.Confirm_Show(tab == "clipboard" and "Empty the clipboard?" or "Forget the recent placements?", function()
			if tab == "clipboard" then
				ns.DecorateClip_Clear()
			else
				wipe(db.recent)
				ns.DecorateClip_Changed()
			end
		end)
	end)
	panel.clear:SetPoint("BOTTOMRIGHT", -PAD, 10)
	panel.Layout = Layout
	Place()
	panel:Hide()
end

local function Update()
	local shown = active and editing and db.dock.shown
	if shown then
		CreatePanel()
	end
	if panel then
		panel:SetShown(shown == true)
		Refresh()
	end
end

function ns.DecorateDock_Toggle()
	db.dock.shown = not db.dock.shown
	Update()
end

-- Called by Decorate.lua --------------------------------------------------------------------------------------------

function ns.DecorateDock_Init(saved)
	db = saved
	ns.DecorateClip_Listen(Refresh)
end

function ns.DecorateDock_Start()
	active = true
	Update()
end

function ns.DecorateDock_Stop()
	active = false
	Update()
end

function ns.DecorateDock_Editing(on)
	editing = on
	Update()
end

function ns.DecorateDock_Apply()
	Update()
end

function ns.DecorateDock_Refresh()
	Refresh()
end
