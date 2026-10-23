local addonName, ns = ...

-- Drawers: the editor window. Lists one drawer's entries (move up or down, remove) and adds new ones: shift-click a
-- link while its text box has focus, type a name or item ID, or drag something from the bags, spellbook, mount
-- journal or toy box onto the window. Opened from the settings page or by right-clicking a drawer. Saved straight
-- into the module's db; the drawer itself is rebuilt by Bar.lua (after combat when it's in combat).

local WIDTH, HEIGHT = 380, 470
local ROW_H = 30
local ICON = 24
local LIST_TOP = -128 -- the list starts below the title, hint, text box and status line
local UI = ns.UI

local db, module
local dialog, input, status, scroll, title, emptyText
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
	local name = ns.Drawers_Info(entry)
	SetStatus("Added " .. (name or ns.DRAWERS_KIND_TEXT[entry.kind]) .. ".", "success")
	Changed()
	return true
end

local function AddTyped()
	local text = strtrim(input:GetText())
	if text == "" then
		return
	end
	if Add(ns.Drawers_FromName(text),
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
		row.kind:SetText(ns.DRAWERS_KIND_TEXT[entry.kind] .. (have and "" or ", not yours"))
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

local function CreateInput()
	input = CreateFrame("EditBox", nil, dialog)
	input:SetHeight(22)
	input:SetPoint("TOPLEFT", 16, -72)
	input:SetPoint("RIGHT", -84, 0)
	input:SetAutoFocus(false)
	UI.SetFont(input, "body", 12)
	UI.SetTextRole(input, "text")
	input:SetTextInsets(6, 6, 0, 0)
	UI.Surface(input, 0.35)
	input.placeholder = UI.Text(input, 12, "textFaint")
	input.placeholder:SetPoint("LEFT", 6, 0)
	input.placeholder:SetPoint("RIGHT", -6, 0)
	input.placeholder:SetWordWrap(false)
	input.placeholder:SetText("Shift-click a link, or type a name")
	input:SetScript("OnTextChanged", function(self)
		self.placeholder:SetShown(self:GetText() == "")
	end)
	input:SetScript("OnEnterPressed", AddTyped)
	input:SetScript("OnEscapePressed", input.ClearFocus)
	input:SetScript("OnEditFocusGained", function(self)
		UI.SetBorderColor(self, "accent", 0.8)
	end)
	input:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, "frame", 0.35)
	end)
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

	local hint = UI.Text(dialog, 11, "textMuted")
	hint:SetPoint("TOPLEFT", 16, -42)
	hint:SetPoint("RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Add items, spells, mounts and toys: shift-click one, type its name, or drag it onto this window.")

	CreateInput()

	status = UI.Text(dialog, 11, "textMuted")
	status:SetPoint("TOPLEFT", 16, -102)
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
