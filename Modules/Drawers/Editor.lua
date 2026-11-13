local addonName, ns = ...

-- Drawers: the editor window. Lists one drawer's entries (move up or down, remove) and adds new ones: shift-click a
-- link while its text box has focus, type a name, item ID or bag search, or drag something from the bags, spellbook, mount
-- journal or toy box onto the window. Above them the drawer's name, which way it opens and buttons per line (the
-- same settings as its card on the settings page). Opened from the settings page or by right-clicking a drawer. Saved
-- straight into the module's db; the drawer itself is rebuilt by Bar.lua (after combat when it's in combat).

local WIDTH, HEIGHT = 380, 590
local ROW_H = 30
local ICON = 24
local LABEL_W = 74 -- the settings rows' labels, left of their controls
local SETTINGS_TOP = -46 -- the name, direction and per-line rows start below the title
local SETTING_H = 30 -- one settings row
local HINT_TOP = -146 -- the hint, below the settings and their rule
local LIST_TOP = -250 -- the list starts below the hint (up to three lines), text box and status line
local NAME_DELAY = 0.3 -- seconds of quiet typing before a new name reaches the drawer on screen
local UI = ns.UI

local db, module
local dialog, input, status, scroll, title, emptyText
local nameBox, opens, perLine
local rows = {}
local current = 1 -- the drawer being edited
local hooked = false

local function Entries()
	local _, entries = ns.Drawers_Saved(db, current)
	return entries
end

local function SetStatus(text, role)
	status:SetText(text or "")
	UI.SetTextRole(status, role or "textMuted")
end

local Rebuild

local function Changed()
	ns.Drawers_Refresh()
	Rebuild()
	if InCombatLockdown() then
		SetStatus("Saved. The drawer changes when combat ends.", "warning")
	end
end

local WHY = {
	duplicate = "Already in this drawer.",
	full = "This drawer is full (" .. ns.DRAWERS_MAX .. ").",
	invalid = "That can't go in a drawer.",
}

local function Add(entry, notFound)
	if not entry then
		SetStatus(notFound or "Only items, spells, mounts and toys go in a drawer.", "danger")
		return false
	end
	local index, why = ns.Drawers_Add(Entries(), entry)
	if not index then
		SetStatus(WHY[why], "warning")
		return false
	end
	if entry.kind == "search" then
		local n = #(ns.Drawers_Found({ entry })[entry] or {})
		SetStatus(("Added the search %s: %s in your bags now."):format(entry.text,
			n == 1 and "1 item" or (n .. " items")), "success")
	else
		local name = ns.Drawers_Info(entry)
		SetStatus("Added " .. (name or ns.DRAWERS_KIND_TEXT[entry.kind]) .. ".", "success")
	end
	Changed()
	return true
end

-- A search entry for text, or nil and why the search language can't read it.
local function SearchEntry(text)
	local match, why = ns.BagsSearch_Compile(text)
	if not match then
		return nil, why
	end
	return { kind = "search", text = text }
end

-- Typed text: a search when it reads like one (is:drink, ilvl>50), else a name; a name nothing is called becomes a
-- search of item names ("water").
local function AddTyped()
	local text = strtrim(input:GetText())
	if text == "" then
		return
	end
	local entry, why
	if ns.Drawers_LooksLikeSearch(text) then
		entry, why = SearchEntry(text)
		if not entry then
			SetStatus("Search: " .. tostring(why), "danger")
			return
		end
	else
		entry = ns.Drawers_FromName(text) or SearchEntry(text)
	end
	if Add(entry,
		"Not found. Shift-click it or drag it here instead (items by name only once they've been in your bags).") then
		input:SetText("")
	end
end

local function AddFromCursor()
	if not GetCursorInfo() then
		return
	end
	Add(ns.Drawers_FromCursor())
	ClearCursor()
end

-- Rows --------------------------------------------------------------------------------------------------------

local function ArrowButton(row, texture)
	local b = UI.Button(row, 22, "")
	b:SetSize(22, 22)
	b.arrow = b:CreateTexture(nil, "ARTWORK")
	b.arrow:SetPoint("CENTER")
	b.arrow:SetSize(16, 16)
	b.arrow:SetTexture(texture)
	return b
end

local function CreateRow(i)
	local row = CreateFrame("Frame", nil, scroll.content)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("RIGHT", -10, 0)
	row:EnableMouse(true)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.Color("hover"))
	row.hover:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.remove = UI.Button(row, 22, "x")
	row.remove:SetSize(22, 22)
	row.remove:SetPoint("RIGHT", -2, 0)
	row.down = ArrowButton(row, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	row.down:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
	row.up = ArrowButton(row, "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
	row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)

	row.kind = UI.Text(row, 11, "textMuted", "label")
	row.kind:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
	row.name = UI.Text(row, 12, "text")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.kind, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.remove:SetScript("OnClick", function()
		local removed = ns.Drawers_Remove(Entries(), row.index)
		if removed then
			SetStatus("Removed " .. (ns.Drawers_Info(removed) or ns.DRAWERS_KIND_TEXT[removed.kind]) .. ".")
			Changed()
		end
	end)
	row.up:SetScript("OnClick", function()
		if ns.Drawers_Move(Entries(), row.index, -1) then
			Changed()
		end
	end)
	row.down:SetScript("OnClick", function()
		if ns.Drawers_Move(Entries(), row.index, 1) then
			Changed()
		end
	end)
	row:SetScript("OnEnter", function(self)
		self.hover:Show()
		ns.Drawers_Tooltip(self, self.entry)
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnReceiveDrag", AddFromCursor)
	row:SetScript("OnMouseUp", AddFromCursor)
	rows[i] = row
	return row
end

local RebuildSoon -- set below: UI.Debounce needs Rebuild defined

function Rebuild()
	if not (dialog and dialog:IsShown()) then
		return
	end
	local saved, entries = ns.Drawers_Saved(db, current)
	title:SetText(ns.Drawers_Name(saved.name, current)
		.. UI.Wrap("  " .. current .. " / " .. ns.DRAWERS_COUNT, "textFaint"))
	if not nameBox:HasFocus() then
		nameBox:SetText(saved.name or "")
	end
	nameBox.placeholder:SetText("Drawer " .. current)
	opens:Refresh()
	perLine:SetValue(saved.perLine)
	for i, entry in ipairs(entries) do
		local row = rows[i] or CreateRow(i)
		row.index, row.entry = i, entry
		local name, icon, have = ns.Drawers_Info(entry)
		if not name and (entry.kind == "item" or entry.kind == "toy") and C_Item.DoesItemExistByID(entry.id) then
			Item:CreateFromItemID(entry.id):ContinueOnItemLoad(RebuildSoon)
		end
		row.icon:SetTexture(icon)
		row.icon:SetDesaturated(not have)
		row.name:SetText(name or (ns.DRAWERS_KIND_TEXT[entry.kind] .. " " .. entry.id))
		UI.SetTextRole(row.name, have and "text" or "textMuted")
		if entry.kind == "search" then
			row.kind:SetText("Search, " .. #(ns.Drawers_Found({ entry })[entry] or {}) .. " found")
		else
			row.kind:SetText(ns.DRAWERS_KIND_TEXT[entry.kind] .. (have and "" or ", not yours"))
		end
		row.up:SetEnabled(i > 1)
		row.up:SetAlpha(i > 1 and 1 or 0.3)
		row.down:SetEnabled(i < #entries)
		row.down:SetAlpha(i < #entries and 1 or 0.3)
		row:Show()
	end
	for i = #entries + 1, #rows do
		rows[i]:Hide()
	end
	emptyText:SetShown(#entries == 0)
	scroll:SetContentHeight(#entries * ROW_H)
end

RebuildSoon = UI.Debounce(0.1, Rebuild)

-- Window ------------------------------------------------------------------------------------------------------

-- A text box in the editor's look, with a placeholder while it's empty. onChange(self, userInput) follows typing.
local function TextBox(placeholder, onChange)
	local box = CreateFrame("EditBox", nil, dialog)
	box:SetHeight(22)
	box:SetAutoFocus(false)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(6, 6, 0, 0)
	UI.Surface(box, 0.35)
	box.placeholder = UI.Text(box, 12, "textFaint")
	box.placeholder:SetPoint("LEFT", 6, 0)
	box.placeholder:SetPoint("RIGHT", -6, 0)
	box.placeholder:SetWordWrap(false)
	box.placeholder:SetText(placeholder)
	box:SetScript("OnTextChanged", function(self, userInput)
		self.placeholder:SetShown(self:GetText() == "")
		if onChange then
			onChange(self, userInput)
		end
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEditFocusGained", function(self)
		UI.SetBorderColor(self, "accent", 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, "frame", 0.35)
	end)
	return box
end

-- Settings ----------------------------------------------------------------------------------------------------

local function Saved()
	return (ns.Drawers_Saved(db, current))
end

local function SettingLabel(text, row)
	local label = UI.Text(dialog, 12, "textMuted", "label")
	label:SetPoint("TOPLEFT", 16, SETTINGS_TOP - (row - 1) * SETTING_H - 4)
	label:SetWidth(LABEL_W)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

-- The drawer on screen follows the name once typing pauses: each refresh reads the bags for its searches.
local nameSoon = UI.Debounce(NAME_DELAY, function()
	ns.Drawers_Refresh()
end)

local function CreateSettings()
	SettingLabel("Name", 1)
	nameBox = TextBox("Drawer 1", function(self, userInput)
		if userInput then
			Saved().name = self:GetText()
			title:SetText(ns.Drawers_Name(Saved().name, current)
				.. UI.Wrap("  " .. current .. " / " .. ns.DRAWERS_COUNT, "textFaint"))
			nameSoon()
		end
	end)
	nameBox:SetPoint("TOPLEFT", 16 + LABEL_W, SETTINGS_TOP)
	nameBox:SetPoint("RIGHT", -16, 0)
	nameBox:SetScript("OnEnterPressed", nameBox.ClearFocus)

	SettingLabel("Opens", 2)
	opens = UI.Segmented(dialog)
	opens:SetPoint("TOPLEFT", 16 + LABEL_W, SETTINGS_TOP - SETTING_H + 1)
	opens.choices = ns.Drawers_DirectionChoices
	opens.getValue = function()
		return Saved().direction
	end
	opens.setValue = function(value)
		Saved().direction = value
		ns.Drawers_Refresh()
	end

	SettingLabel("Per line", 3)
	local value = UI.Text(dialog, 12, "text", "number")
	value:SetPoint("TOPRIGHT", -16, SETTINGS_TOP - 2 * SETTING_H - 4)
	value:SetWidth(24)
	value:SetJustifyH("RIGHT")
	perLine = UI.Slider(dialog, 100)
	perLine:SetPoint("TOPLEFT", 16 + LABEL_W + 4, SETTINGS_TOP - 2 * SETTING_H - 6)
	perLine:SetPoint("RIGHT", value, "LEFT", -12, 0)
	perLine:SetMinMaxValues(1, 12)
	perLine:SetValueStep(1)
	perLine.valueText = value
	perLine.format = function(v)
		return tostring(math.floor(v + 0.5))
	end
	perLine.onChange = function(v)
		Saved().perLine = math.floor(v + 0.5)
		ns.Drawers_Refresh()
	end

	UI.Hairline(dialog, WIDTH - 32, 0.5):SetPoint("TOP", 0, HINT_TOP + 8)
end

local function CreateInput()
	input = TextBox("Shift-click a link, or type a name or a search")
	input:SetPoint("TOPLEFT", 16, HINT_TOP - 50)
	input:SetPoint("RIGHT", -84, 0)
	input:SetScript("OnEnterPressed", AddTyped)
	local add = UI.Button(dialog, 60, "Add")
	add:SetHeight(22)
	add:SetPoint("LEFT", input, "RIGHT", 8, 0)
	add:SetScript("OnClick", AddTyped)
end

local function Switch(delta)
	current = (current - 1 + delta) % ns.DRAWERS_COUNT + 1
	SetStatus("")
	Rebuild()
end

local function Create()
	dialog = UI.Dialog("TomteDrawersEditor", WIDTH, HEIGHT)
	dialog:SetScript("OnReceiveDrag", AddFromCursor)
	dialog:SetScript("OnMouseUp", AddFromCursor)
	dialog:HookScript("OnHide", function()
		input:ClearFocus()
		nameBox:ClearFocus()
	end)

	title = UI.Text(dialog, 15, "heading", "title")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetPoint("RIGHT", -120, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)

	local close = UI.Button(dialog, 22, "x")
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -12, -12)
	close:SetScript("OnClick", function()
		dialog:Hide()
	end)
	local nextDrawer = UI.Button(dialog, 22, ">")
	nextDrawer:SetSize(22, 22)
	nextDrawer:SetPoint("RIGHT", close, "LEFT", -10, 0)
	nextDrawer:SetScript("OnClick", function()
		Switch(1)
	end)
	local prevDrawer = UI.Button(dialog, 22, "<")
	prevDrawer:SetSize(22, 22)
	prevDrawer:SetPoint("RIGHT", nextDrawer, "LEFT", -4, 0)
	prevDrawer:SetScript("OnClick", function()
		Switch(-1)
	end)

	CreateSettings()

	local hint = UI.Text(dialog, 11, "textMuted")
	hint:SetPoint("TOPLEFT", 16, HINT_TOP)
	hint:SetPoint("RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Add items, spells, mounts and toys: shift-click one, type its name, or drag it onto this window. "
		.. "Or type a bag search, like is:eat, is:drink or is:potion: it fills in from your bags.")

	CreateInput()

	status = UI.Text(dialog, 11, "textMuted")
	status:SetPoint("TOPLEFT", 16, HINT_TOP - 80)
	status:SetPoint("RIGHT", -16, 0)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)

	UI.Hairline(dialog, WIDTH - 32, 0.5):SetPoint("TOP", 0, LIST_TOP + 6)
	scroll = UI.Scroll(dialog)
	scroll:SetPoint("TOPLEFT", 16, LIST_TOP)
	scroll:SetPoint("BOTTOMRIGHT", -16, 16)
	scroll:SetScript("OnReceiveDrag", AddFromCursor)
	scroll:SetScript("OnMouseUp", AddFromCursor)
	emptyText = UI.Text(dialog, 12, "textFaint")
	emptyText:SetPoint("TOP", scroll, "TOP", 0, -24)
	emptyText:SetText("Empty. Drag something here.")
end

-- Shift-click: Blizzard sends a link to ChatFrameUtil.InsertLink, which only fills its own boxes. The hook can't be
-- undone; it does nothing unless the module is on and this window's text box has focus.
local function HookLinks()
	if hooked then
		return
	end
	hooked = true
	hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
		if module.active and dialog and dialog:IsShown() and input:HasFocus() and text then
			if Add(ns.Drawers_FromLink(text)) then
				input:SetText("")
			end
		end
	end)
end

function ns.Drawers_OpenEditor(index)
	if not dialog then
		Create()
	end
	HookLinks()
	current = index or current
	SetStatus(module.active and "" or "Drawers is off: turn it on to see them on screen.", "warning")
	dialog:Show()
	Rebuild()
end

function ns.Drawers_CloseEditor()
	if dialog then
		dialog:Hide()
	end
end

function ns.Drawers_EditorSetup(moduleDB, mod)
	db, module = moduleDB, mod
end
