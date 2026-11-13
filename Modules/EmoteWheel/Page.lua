local addonName, ns = ...

-- Emote wheel: the editor page in the Tomte window (docs/superpowers/specs/2026-11-13-emote-wheel-editor-design.md).
-- The wheel on the left, drawn as in game: click a slice to pick it, drag one onto another to move it there, click a
-- grey slot to add a slice. The picked slice on the right: an emote from the game's list, a chat line or any command,
-- what it does, its name on the wheel, and move / remove. Every change is saved at once. Rules in Data.lua, the wheel
-- in Wheel.lua, registered in EmoteWheel.lua.

local PAD = 8
local BAND_H = 30
local WHEEL_COL = 360 -- the wheel's column
local WHEEL_SIZE = 320 -- the drawn wheel at scale 1 (Wheel.lua's OUTER * 2)
local DRAG = 6 -- pixels the mouse moves with the button down before a press becomes a drag
local CHIP_MIN_W = 104 -- emote buttons are at least this wide; the columns share what's left
local CHIP_H = 26
local CHIP_GAP = 6
local CHIP_USED = 0.6 -- the dot on an emote another slice already has
local CHIP_LIT = 0.22 -- the accent wash on the picked slice's emote
local BOX_H = 26
local CMD_INSET = 6 -- the Command box's space above and below its lines
local GAP = 12 -- between the editor's groups
local FOOT_H = 26 -- the move / remove row
local MODES = {
	{ value = "emote", text = "Emote" }, { value = "line", text = "Chat line" }, { value = "command", text = "Command" },
}
local CHANNEL_NAMES = { SAY = "Say", YELL = "Yell", PARTY = "Party", GUILD = "Guild", WHISPER = "Whisper target" }
local EMPTY_LABEL = "Not set" -- a slice still without an emote or line
local MARK = 14 -- the acts-out and voice marks on an emote button
local MARK_PAD = 6
local MARK_ALPHA = 0.85
local DOT = ns.Theme.MEDIA .. "Showcase\\Dot"
local ART = ns.Theme.MEDIA .. "EmoteWheel\\"

local UI = ns.UI
local Kit = ns.HomeKit

local page, ed
local list = {} -- the slices being edited: { name, text }, in order
local selected -- index into list
local hover -- slice under the mouse on the wheel
local pressed, pressX, pressY, dragging
local mode, channel = "emote", "SAY" -- the editor's way of filling the picked slice
local preview -- an emote under the mouse in the list, shown on the picked slice
local chips = {}
local Refresh

local function Sel()
	return selected and list[selected]
end

-- Wheel ---------------------------------------------------------------------------------------------------------------

local function DrawWheel()
	local slices = {}
	for i, slice in ipairs(list) do
		slices[i] = slice
	end
	if preview and selected then
		slices[selected] = { name = "", text = preview.commands[1] }
	end
	local room = math.min(WHEEL_COL - PAD, page:GetHeight() - BAND_H - 2 * PAD)
	local scale = math.max(0.5, math.min(1, room / WHEEL_SIZE))
	local opts = ns.EmoteWheel_Look()
	opts.scale, opts.hover, opts.emptyLabel = scale, hover, EMPTY_LABEL
	local size = ns.EmoteWheel_Draw(page.wheel, slices, opts, selected)
	page.wheel:SetSize(size, size)
end

local function Save()
	ns.EmoteWheel_SaveList(list)
	Refresh()
end

local function Pick(i)
	selected, preview = i, nil
	local slice = Sel()
	if slice then
		local kind, a = ns.EmoteWheel_Kind(slice.text, ns.EmoteWheel_Lookups())
		mode = kind
		if kind == "line" then
			channel = a
		end
	end
	if ed.search:HasFocus() then
		ed.search:ClearFocus()
	end
	Refresh()
end

local function Add()
	if #list >= ns.EMOTEWHEEL_MAX then
		return
	end
	local at = selected and selected + 1 or #list + 1
	table.insert(list, at, { name = "", text = "" })
	selected, mode, preview = at, "emote", nil
	Save()
	ed.search:SetFocus()
end

local function Remove()
	if not selected then
		return
	end
	table.remove(list, selected)
	selected = #list > 0 and math.min(selected, #list) or nil
	Pick(selected)
	Save()
end

local function MoveBy(step)
	local to = selected and selected + step
	if to and list[to] then
		ns.EmoteWheel_Move(list, selected, to)
		selected = to
		Save()
	end
end

local function Under()
	return ns.EmoteWheel_SliceUnder(page.wheel, #list)
end

local function PlaceGhost()
	local x, y = GetCursorPosition()
	local scale = page:GetEffectiveScale()
	page.ghost:ClearAllPoints()
	page.ghost:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", x / scale - page:GetLeft() + 14, y / scale - page:GetBottom() + 4)
end

-- Runs only while the mouse is over the wheel or a slice is held.
local function WheelUpdate()
	local i = Under()
	if pressed and not dragging then
		local x, y = GetCursorPosition()
		local far = DRAG * page:GetEffectiveScale()
		if math.abs(x - pressX) > far or math.abs(y - pressY) > far then
			dragging = true
			page.ghost:SetText(ns.EmoteWheel_Label(list[pressed]) ~= "" and ns.EmoteWheel_Label(list[pressed])
				or EMPTY_LABEL)
			page.ghost:Show()
		end
	end
	if dragging then
		PlaceGhost()
		i = i and math.min(i, #list) -- dropped on a grey slot: the end of the wheel
	end
	if i ~= hover then
		hover = i
		DrawWheel()
	end
end

local function StopWatching()
	page.hit:SetScript("OnUpdate", nil)
	if hover then
		hover = nil
		DrawWheel()
	end
end

local function WheelDown(_, button)
	if button ~= "LeftButton" then
		return
	end
	local i = Under()
	if i and list[i] then
		pressed, dragging = i, false
		pressX, pressY = GetCursorPosition()
	end
end

local function WheelUp(self, button)
	if button ~= "LeftButton" then
		return
	end
	local i = Under()
	local from, drag = pressed, dragging
	pressed, dragging = nil, false
	page.ghost:Hide()
	if drag then
		local to = i and math.min(i, #list)
		if to and to ~= from then
			ns.EmoteWheel_Move(list, from, to)
			selected = to
			UI.Sound("nav")
			Save()
		end
	elseif i and list[i] then
		UI.Sound("nav")
		Pick(i)
	elseif i then
		UI.Sound("nav")
		selected = #list
		Add()
	end
	if not self:IsMouseOver() then
		StopWatching()
	end
end

-- Editor --------------------------------------------------------------------------------------------------------------

-- A text box saved as you type: onChange(text) on every change made by the player.
local function Box(parent, placeholder, onChange)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(BOX_H)
	box:SetAutoFocus(false)
	UI.SetFont(box, "body", 13)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(8, 8, 0, 0)
	UI.Surface(box, 0.35)
	box.placeholder = UI.Text(box, 13, "textFaint")
	box.placeholder:SetPoint("LEFT", 8, 0)
	box.placeholder:SetPoint("RIGHT", -8, 0)
	box.placeholder:SetWordWrap(false)
	box.placeholder:SetText(placeholder or "")
	box:SetScript("OnTextChanged", function(self, byPlayer)
		self.placeholder:SetShown(self:GetText() == "")
		if byPlayer then
			onChange(self:GetText())
		end
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEditFocusGained", function(self)
		UI.BorderTo(self, "accent", 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.BorderTo(self, "frame", 0.35)
	end)
	return box
end

-- Sets a box's text unless the player is typing in it (their text is the newer one).
local function Fill(box, text)
	if not box:HasFocus() and box:GetText() ~= text then
		box:SetText(text)
		box:SetCursorPosition(0)
	end
end

local function Label(parent, text)
	local fs = UI.Text(parent, 12, "textMuted", "label")
	fs:SetText(text)
	return fs
end

local function SetText(text)
	local slice = Sel()
	if slice then
		slice.text = text
		Save()
	end
end

local function WriteLine()
	local message = ed.message:GetText()
	SetText(strtrim(message) == "" and "" or ns.EmoteWheel_Line(channel, message, ns.EmoteWheel_LineCommands()))
end

local function Segmented(parent, choices, get, set)
	local s = UI.Segmented(parent)
	s.choices = choices
	s.getValue = get
	s.setValue = set
	return s
end

-- Whether an emote acts out and has a voice line for this character (Generated.lua's data).
local function Extras(token)
	local _, _, race = UnitRace("player")
	local _, _, class = UnitClass("player")
	return ns.EmoteWheel_Extras(token, race, UnitSex("player"), class)
end

local function ChipEnter(b)
	preview = b.emote
	DrawWheel()
	GameTooltip:SetOwner(b, "ANCHOR_TOP")
	GameTooltip:SetText(b.emote.name, UI.RGB("heading"))
	UI.TipLine(table.concat(b.emote.commands, "  "), "textMuted")
	local extras = ns.EmoteWheel_ExtrasText(b.acts, b.voice)
	if extras then
		UI.TipLine(extras, "text")
	end
	if b.used then
		UI.TipLine("Already on another slice.", "textFaint")
	end
	GameTooltip:Show()
end

local function ChipLeave()
	preview = nil
	DrawWheel()
	GameTooltip:Hide()
end

local function ChipClick(b)
	UI.Sound("nav")
	preview = nil
	SetText(b.emote.commands[1])
end

local function Chip(i)
	local b = chips[i]
	if not b then
		b = CreateFrame("Button", nil, ed.chips.content)
		b:SetHeight(CHIP_H)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		UI.Border(b, "frame", 0.3)
		b.dot = b:CreateTexture(nil, "OVERLAY")
		b.dot:SetTexture(DOT)
		b.dot:SetSize(10, 10)
		b.dot:SetPoint("LEFT", 2, 0)
		-- The marks sit in fixed places, so they line up down a column of buttons.
		b.voiceMark = b:CreateTexture(nil, "OVERLAY")
		b.voiceMark:SetTexture(ART .. "Voice")
		b.voiceMark:SetSize(MARK, MARK)
		b.voiceMark:SetPoint("RIGHT", -MARK_PAD, 0)
		b.actsMark = b:CreateTexture(nil, "OVERLAY")
		b.actsMark:SetTexture(ART .. "Acts")
		b.actsMark:SetSize(MARK, MARK)
		b.actsMark:SetPoint("RIGHT", b.voiceMark, "LEFT", -2, 0)
		b.label = UI.Text(b, 12, "text")
		b.label:SetPoint("LEFT", 12, 0)
		b.label:SetPoint("RIGHT", b.actsMark, "LEFT", -2, 0)
		b.label:SetWordWrap(false)
		b:SetScript("OnEnter", ChipEnter)
		b:SetScript("OnLeave", ChipLeave)
		b:SetScript("OnClick", ChipClick)
		chips[i] = b
	end
	return b
end

local function LayoutChips()
	local width = ed.chips:GetWidth()
	if width < CHIP_MIN_W then
		return
	end
	local mr, mg, mb = UI.RGBA("textMuted")
	ed.legend.Acts:SetVertexColor(mr, mg, mb, MARK_ALPHA)
	ed.legend.Voice:SetVertexColor(mr, mg, mb, MARK_ALPHA)
	local lookups = ns.EmoteWheel_Lookups()
	local _, current = ns.EmoteWheel_Kind(Sel() and Sel().text or "", lookups)
	local used = {}
	for i, slice in ipairs(list) do
		local kind, token = ns.EmoteWheel_Kind(slice.text, lookups)
		if i ~= selected and kind == "emote" and token then
			used[token] = true
		end
	end
	local emotes = ns.EmoteWheel_FilterEmotes(ns.EmoteWheel_Emotes(), ed.search:GetText())
	local cols = math.max(1, math.floor((width + CHIP_GAP) / (CHIP_MIN_W + CHIP_GAP)))
	local w = (width - (cols - 1) * CHIP_GAP) / cols
	for i, emote in ipairs(emotes) do
		local b = Chip(i)
		b.emote = emote
		b.used = used[emote.token]
		local lit = emote.token == current
		b.label:SetText(emote.name)
		UI.SetTextRole(b.label, lit and "accent" or "text")
		if lit then
			b.bg:SetColorTexture(UI.RGBA("accent"))
			b.bg:SetAlpha(CHIP_LIT)
		else
			b.bg:SetColorTexture(UI.RGBA("surface"))
			b.bg:SetAlpha(1)
		end
		local r, g, bl = UI.RGBA("accent")
		b.dot:SetVertexColor(r, g, bl, CHIP_USED)
		b.dot:SetShown(b.used == true)
		b.acts, b.voice = Extras(emote.token)
		for _, mark in ipairs({ b.actsMark, b.voiceMark }) do
			local mr, mg, mb = UI.RGBA(lit and "accent" or "textMuted")
			mark:SetVertexColor(mr, mg, mb, MARK_ALPHA)
		end
		b.actsMark:SetShown(b.acts)
		b.voiceMark:SetShown(b.voice)
		b:SetWidth(w)
		b:ClearAllPoints()
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		b:SetPoint("TOPLEFT", col * (w + CHIP_GAP), -row * (CHIP_H + CHIP_GAP))
		b:Show()
	end
	for i = #emotes + 1, #chips do
		chips[i]:Hide()
	end
	ed.noEmotes:SetShown(#emotes == 0)
	ed.chips:SetContentHeight(math.ceil(#emotes / cols) * (CHIP_H + CHIP_GAP))
end

local function BuildEditor()
	ed = CreateFrame("Frame", nil, page)
	ed:SetPoint("TOPLEFT", page, "TOPLEFT", WHEEL_COL + GAP, -(BAND_H + PAD))
	ed:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAD, PAD)

	ed.title = UI.Text(ed, 22, "heading", Kit.DISPLAY_FONT)
	ed.title:SetPoint("TOPLEFT", 0, -2)
	ed.title:SetPoint("RIGHT")
	ed.title:SetWordWrap(false)
	ed.sub = UI.Text(ed, 12, "textMuted")
	ed.sub:SetPoint("TOPLEFT", ed.title, "BOTTOMLEFT", 0, -4)
	ed.sub:SetPoint("RIGHT")
	ed.sub:SetJustifyH("LEFT")

	ed.modes = Segmented(ed, function()
		return MODES
	end, function()
		return mode
	end, function(value)
		mode = value
		Refresh()
		if value == "emote" then
			ed.search:SetFocus()
		elseif value == "line" then
			ed.message:SetFocus()
		else
			ed.command:SetFocus()
		end
	end)
	ed.modes:SetPoint("TOPLEFT", ed.sub, "BOTTOMLEFT", 0, -GAP)

	-- Bottom up: move / remove, the name, what it does.
	ed.left = UI.Button(ed, 28, "<")
	ed.left:SetHeight(FOOT_H)
	ed.left:SetPoint("BOTTOMLEFT")
	ed.left:SetScript("OnClick", function()
		MoveBy(-1)
	end)
	ed.right = UI.Button(ed, 28, ">")
	ed.right:SetHeight(FOOT_H)
	ed.right:SetPoint("LEFT", ed.left, "RIGHT", 4, 0)
	ed.right:SetScript("OnClick", function()
		MoveBy(1)
	end)
	ed.moveLabel = Label(ed, "Move")
	ed.moveLabel:SetPoint("LEFT", ed.right, "RIGHT", 8, 0)
	ed.remove = UI.Button(ed, 90, "Remove")
	ed.remove:SetHeight(FOOT_H)
	ed.remove:SetPoint("BOTTOMRIGHT")
	ed.remove:SetScript("OnClick", Remove)

	ed.name = Box(ed, "", function(text)
		local slice = Sel()
		if slice then
			slice.name = strtrim(text)
			ns.EmoteWheel_SaveList(list)
			ed.title:SetText(ns.EmoteWheel_Label(slice) ~= "" and ns.EmoteWheel_Label(slice) or EMPTY_LABEL)
			DrawWheel()
		end
	end)
	ed.name:SetPoint("BOTTOMLEFT", ed.left, "TOPLEFT", 0, GAP)
	ed.name:SetPoint("RIGHT")
	ed.nameLabel = Label(ed, "Name on the wheel")
	ed.nameLabel:SetPoint("BOTTOMLEFT", ed.name, "TOPLEFT", 0, 4)

	ed.does = UI.Text(ed, 13, "text")
	ed.does:SetPoint("BOTTOMLEFT", ed.nameLabel, "TOPLEFT", 0, GAP)
	ed.does:SetPoint("RIGHT")
	ed.does:SetJustifyH("LEFT")
	ed.does:SetWordWrap(true)
	ed.does:SetMaxLines(2)

	-- The three ways, between the modes and what it does.
	ed.body = CreateFrame("Frame", nil, ed)
	ed.body:SetPoint("TOPLEFT", ed.modes, "BOTTOMLEFT", 0, -GAP)
	ed.body:SetPoint("RIGHT")
	ed.body:SetPoint("BOTTOM", ed.does, "TOP", 0, GAP)

	ed.emote = CreateFrame("Frame", nil, ed.body)
	ed.emote:SetAllPoints()
	ed.search = Box(ed.emote, "Search emotes", function() end)
	ed.search:HookScript("OnTextChanged", LayoutChips) -- also the right-click clear, which isn't typed
	UI.SearchBoxClear(ed.search)
	local textX = UI.SearchTextX() -- past the Forever field's magnifying glass
	ed.search:SetTextInsets(textX, 8, 0, 0)
	ed.search.placeholder:SetPoint("LEFT", textX, 0)
	-- What the marks on the buttons mean, right of the search box.
	ed.legend = CreateFrame("Frame", nil, ed.emote)
	ed.legend:SetHeight(BOX_H)
	ed.legend:SetPoint("TOPRIGHT", -12, 0)
	local x = 0
	for _, part in ipairs({ { "Acts", "Acts it out" }, { "Voice", "Voice line" } }) do
		local mark = ed.legend:CreateTexture(nil, "OVERLAY")
		mark:SetTexture(ART .. part[1])
		mark:SetSize(MARK, MARK)
		mark:SetPoint("LEFT", x, 0)
		ed.legend[part[1]] = mark
		local text = UI.Text(ed.legend, 12, "textMuted")
		text:SetPoint("LEFT", mark, "RIGHT", 4, 0)
		text:SetText(part[2])
		x = x + MARK + 4 + math.ceil(text:GetUnboundedStringWidth()) + GAP
	end
	ed.legend:SetWidth(x - GAP)
	ed.search:SetPoint("TOPLEFT")
	ed.search:SetPoint("RIGHT", ed.legend, "LEFT", -GAP, 0)
	ed.chips = UI.Scroll(ed.emote)
	ed.chips:SetPoint("TOPLEFT", ed.search, "BOTTOMLEFT", 0, -8)
	ed.chips:SetPoint("BOTTOMRIGHT", -12, 0)
	ed.chips.onWidthChanged = LayoutChips
	ed.noEmotes = UI.Text(ed.emote, 13, "textMuted")
	ed.noEmotes:SetPoint("TOPLEFT", ed.chips, "TOPLEFT", 0, -4)
	ed.noEmotes:SetText("No emote has that in its name. Try part of the word, like \"dan\" for dance.")

	ed.line = CreateFrame("Frame", nil, ed.body)
	ed.line:SetAllPoints()
	ed.channels = Segmented(ed.line, function()
		local choices = {}
		for i, chatType in ipairs(ns.EMOTEWHEEL_LINE_TYPES) do
			choices[i] = { value = chatType, text = CHANNEL_NAMES[chatType] }
		end
		return choices
	end, function()
		return channel
	end, function(value)
		channel = value
		if strtrim(ed.message:GetText()) ~= "" then -- a channel alone doesn't replace what the slice does now
			WriteLine()
		end
	end)
	ed.channels:SetPoint("TOPLEFT")
	ed.message = Box(ed.line, "What to say", WriteLine)
	ed.message:SetPoint("TOPLEFT", ed.channels, "BOTTOMLEFT", 0, -GAP)
	ed.message:SetPoint("RIGHT")
	ed.lineHelp = UI.Text(ed.line, 12, "textMuted")
	ed.lineHelp:SetPoint("TOPLEFT", ed.message, "BOTTOMLEFT", 0, -8)
	ed.lineHelp:SetPoint("RIGHT")
	ed.lineHelp:SetJustifyH("LEFT")
	ed.lineHelp:SetText("%t becomes your target's name: \"Thanks, %t!\" Whisper target sends it to them only.")

	ed.cmd = CreateFrame("Frame", nil, ed.body)
	ed.cmd:SetAllPoints()
	ed.command = Box(ed.cmd, "/bow, /w %t Thanks!, or text to say", SetText)
	ed.command:SetMultiLine(true) -- grows with its lines
	ed.command:SetTextInsets(8, 8, CMD_INSET, CMD_INSET)
	ed.command:SetScript("OnEnterPressed", nil) -- Enter starts a new line
	ed.command.placeholder:ClearAllPoints()
	ed.command.placeholder:SetPoint("TOPLEFT", 8, -CMD_INSET)
	ed.command.placeholder:SetPoint("RIGHT", -8, 0)
	ed.command:SetPoint("TOPLEFT")
	ed.command:SetPoint("RIGHT")
	ed.cmdHelp = UI.Text(ed.cmd, 12, "textMuted")
	ed.cmdHelp:SetPoint("TOPLEFT", ed.command, "BOTTOMLEFT", 0, -8)
	ed.cmdHelp:SetPoint("RIGHT")
	ed.cmdHelp:SetJustifyH("LEFT")
	ed.cmdHelp:SetText("An emote like /bow goes to your target. %t becomes your target's name. Any chat command works "
		.. "(/p, /g, /e ...), and other addons' commands too. Text without a / at the start is said out loud. Put "
		.. "each thing on a line of its own (Enter) and one press runs them all, like a macro: Thanks! and then /ty.")

	ed.none = UI.Text(ed, 13, "textMuted")
	ed.none:SetPoint("TOPLEFT", ed.sub, "BOTTOMLEFT", 0, -GAP)
	ed.none:SetPoint("RIGHT")
	ed.none:SetJustifyH("LEFT")
	ed.none:SetText("Add a slice with Add slice, or click a grey slot on the wheel. Starting slices puts the eight "
		.. "starting emotes back.")
end

local function RefreshEditor()
	local slice = Sel()
	local any = slice ~= nil
	for _, f in ipairs({ ed.modes, ed.body, ed.does, ed.name, ed.nameLabel, ed.left, ed.right, ed.moveLabel,
		ed.remove }) do
		f:SetShown(any)
	end
	ed.none:SetShown(not any)
	if not any then
		ed.title:SetText("No slices yet")
		ed.sub:SetText("")
		return
	end
	local label = ns.EmoteWheel_Label(slice)
	ed.title:SetText(label ~= "" and label or EMPTY_LABEL)
	ed.sub:SetText(("Slice %d of %d, clockwise from the top"):format(selected, #list))
	ed.modes:Refresh()
	ed.emote:SetShown(mode == "emote")
	ed.line:SetShown(mode == "line")
	ed.cmd:SetShown(mode == "command")
	local lookups = ns.EmoteWheel_Lookups()
	if mode == "emote" then
		LayoutChips()
	elseif mode == "line" then
		local kind, _, message = ns.EmoteWheel_Kind(slice.text, lookups)
		ed.channels:Refresh()
		Fill(ed.message, kind == "line" and message or "")
	else
		Fill(ed.command, slice.text)
	end
	local does = ns.EmoteWheel_Describe(slice.text, lookups)
	local kind, token = ns.EmoteWheel_Kind(slice.text, lookups)
	local extras = kind == "emote" and token and ns.EmoteWheel_ExtrasText(Extras(token))
	ed.does:SetText(extras and (does .. " " .. extras) or does)
	ed.name.placeholder:SetText(slice.text ~= "" and ns.EmoteWheel_Label({ name = "", text = slice.text })
		or "From the emote")
	Fill(ed.name, slice.name or "")
	ed.left:SetEnabled(selected > 1)
	ed.right:SetEnabled(selected < #list)
end

-- Page ----------------------------------------------------------------------------------------------------------------

Refresh = function()
	if not (page and page:IsVisible()) then
		return
	end
	local full = #list >= ns.EMOTEWHEEL_MAX
	page.add:SetEnabled(not full)
	page.count:SetText(("%d of %d slices. Click a slice to change it, drag it onto another to move it."):format(#list,
		ns.EMOTEWHEEL_MAX))
	DrawWheel()
	RefreshEditor()
end

local function Load()
	list = ns.EmoteWheel_EditList()
	pressed, dragging, hover, preview = nil, false, nil, nil
	Pick(#list > 0 and math.min(selected or 1, #list) or nil)
end

local function Create(frame)
	page = frame

	page.count = UI.Text(page, 12, "textMuted")
	page.count:SetPoint("TOPLEFT", PAD, -PAD - 4)
	page.add = UI.Button(page, 90, "Add slice")
	page.add:SetPoint("TOPRIGHT", -PAD, -PAD)
	page.add:SetScript("OnClick", Add)
	page.reset = UI.Button(page, 110, "Starting slices")
	UI.FitButton(page.reset, 110)
	page.reset:SetPoint("RIGHT", page.add, "LEFT", -6, 0)
	page.reset:SetScript("OnClick", function()
		ns.Confirm_Show("Put the eight starting emotes back on the wheel? Your own slices are cleared.", function()
			ns.EmoteWheel_ResetSlices()
			selected = 1
			Load()
		end)
	end)
	page.count:SetPoint("RIGHT", page.reset, "LEFT", -GAP, 0)
	page.count:SetJustifyH("LEFT")
	page.count:SetWordWrap(false)

	-- The wheel, centered in its column; a mouse catcher over it (the drawn wheel takes no mouse).
	page.wheelCol = CreateFrame("Frame", nil, page)
	page.wheelCol:SetPoint("TOPLEFT", 0, -(BAND_H + PAD))
	page.wheelCol:SetPoint("BOTTOMLEFT", 0, PAD)
	page.wheelCol:SetWidth(WHEEL_COL)
	page.wheel = CreateFrame("Frame", nil, page.wheelCol)
	page.wheel:SetPoint("TOP", 0, 0)
	page.wheel:SetSize(WHEEL_SIZE, WHEEL_SIZE)
	page.hit = CreateFrame("Frame", nil, page.wheelCol)
	page.hit:SetAllPoints(page.wheel)
	page.hit:EnableMouse(true)
	page.hit:SetScript("OnEnter", function(self)
		self:SetScript("OnUpdate", WheelUpdate)
	end)
	page.hit:SetScript("OnLeave", function()
		if not pressed then
			StopWatching()
		end
	end)
	page.hit:SetScript("OnMouseDown", WheelDown)
	page.hit:SetScript("OnMouseUp", WheelUp)
	page.ghost = UI.Text(page, 15, "accent", "title")
	page.ghost:SetDrawLayer("OVERLAY", 7)
	page.ghost:Hide()

	BuildEditor()
	page:SetScript("OnSizeChanged", function()
		if page:IsVisible() then
			Refresh()
		end
	end)
	page:SetScript("OnHide", function()
		pressed, dragging, preview = nil, false, nil
		page.ghost:Hide()
		StopWatching()
	end)
end

ns.EmoteWheelPage = {
	Create = Create,
	Refresh = function()
		Load()
	end,
}
