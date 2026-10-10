local addonName, ns = ...

-- Whisper inbox: a small window with your whisper conversations on the left (newest first, unread ones
-- marked) and the chosen conversation on the right, both directions, with a chat line under it to answer
-- from the window. Opening a conversation marks it read. Esc closes it. Built on first use.
-- The Whispers module owns the data (ns.Whispers_Convos / ns.Whispers_Get) and calls ns.Inbox_Refresh when
-- it changes. The session-only "In instance" conversation holds secret messages: shown, never inspected.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local WIDTH, HEIGHT = 560, 380
local TITLE_H = 36
local LIST_W = 170
local ROW_H = 34
local BN_COLOR = "ff82c5ff"
local OUT_COLOR = { 0.62, 0.62, 0.62 }
local MAX_ROWS = math.floor((HEIGHT - TITLE_H - 16) / ROW_H)
local INPUT_H = 24

local frame
local CreateInput
local rows = {}
local scroll = 0 -- conversations scrolled past at the top of the list
local current -- conversation key on the right
local drawn -- { key, count, last } of the conversation the message pane holds: redrawn only when that changes

-- Name in its class color (Battle.net friends in Blizzard's BN blue).
function ns.Inbox_ColoredName(convo)
	local name = convo.name or convo.key
	if convo.restricted then
		return "|cffffd173" .. name .. "|r"
	elseif convo.bn then
		return "|c" .. BN_COLOR .. name .. "|r"
	end
	local color = convo.class and C_ClassColor.GetClassColor(convo.class)
	if color then
		return color:WrapTextInColorCode(name)
	end
	return name
end

local function Clock(at)
	local t = date("*t", at)
	return ns.AFK_ClockText(t.hour, t.min, C_CVar.GetCVarBool("timeMgrUseMilitaryTime"))
end

local function ShowConversation()
	local messages = frame.messages
	local convo = current and ns.Whispers_Get(current)
	-- Secret "In instance" whispers can only be answered through Blizzard's chat box.
	frame.reply:SetShown(convo ~= nil and convo.restricted == true)
	frame.input:SetShown(convo ~= nil and not convo.restricted)
	if convo and not convo.restricted then
		frame.input.placeholder:SetText("Whisper " .. (convo.name or convo.key))
	end
	if not convo then
		drawn = nil
		messages:Clear()
		frame.header:SetText("")
		frame.empty:SetShown(#ns.Whispers_Convos() == 0)
		return
	end
	frame.empty:Hide()
	frame.header:SetText(ns.Inbox_ColoredName(convo))
	-- Same conversation, no new message (someone else wrote, or it was only marked read): keep the scroll.
	local count, newest = #convo.messages, convo.messages[#convo.messages]
	if drawn and drawn.key == convo.key and drawn.count == count and drawn.last == newest then
		return
	end
	drawn = { key = convo.key, count = count, last = newest }
	messages:Clear()
	local lastDay
	for _, m in ipairs(convo.messages) do
		local day = date("%Y-%m-%d", m.at)
		if day ~= lastDay then
			lastDay = day
			messages:AddMessage(" ")
			messages:AddMessage(date("%A %d %B", m.at), DIM[1], DIM[2], DIM[3])
		end
		local who = m.out and "You" or (m.sender or ns.Inbox_ColoredName(convo))
		local color = m.out and OUT_COLOR or WHITE
		-- format and AddMessage take secrets (the sender and text of "In instance" messages).
		pcall(messages.AddMessage, messages, ("|cff7f7f7f%s|r  %s: %s"):format(Clock(m.at), who, m.text), color[1], color[2], color[3])
	end
	if convo.restricted then
		messages:AddMessage(" ")
		messages:AddMessage("Whispers in instances are hidden from addons: kept until you log out, reply goes to the last one.", DIM[1], DIM[2], DIM[3])
	end
	messages:ScrollToBottom()
end

local function SelectConversation(key)
	if key ~= current then
		frame.input:SetText("")
	end
	current = key
	if key then
		ns.Whispers_MarkRead(key)
	end
	ns.Inbox_Refresh()
end

local function NewRow(i)
	local row = CreateFrame("Button", nil, frame.list)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("RIGHT")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.1)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.04)
	row.hover:Hide()
	row.name = UI.Text(row, 13, WHITE)
	row.name:SetPoint("TOPLEFT", 12, -4)
	row.name:SetPoint("RIGHT", -34, 0)
	row.name:SetWordWrap(false)
	row.ago = UI.Text(row, 10, GREY)
	row.ago:SetJustifyH("RIGHT")
	row.ago:SetPoint("TOPRIGHT", -8, -5)
	row.preview = UI.Text(row, 11, GREY)
	row.preview:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.preview:SetPoint("RIGHT", -8, 0)
	row.preview:SetWordWrap(false)
	row.dot = row:CreateTexture(nil, "OVERLAY")
	row.dot:SetSize(6, 6)
	row.dot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	row.dot:SetPoint("LEFT", 3, 0)
	row:SetScript("OnEnter", function(self)
		self.hover:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
	end)
	row:SetScript("OnClick", function(self)
		SelectConversation(self.key)
	end)
	rows[i] = row
	return row
end

function ns.Inbox_Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local list = ns.Whispers_Convos()
	if current and not ns.Whispers_Get(current) then
		current = nil
	end
	local maxRows = MAX_ROWS
	scroll = math.max(math.min(scroll, #list - maxRows), 0)
	local now = time()
	for i = 1, math.min(#list - scroll, maxRows) do
		local convo = list[i + scroll]
		local row = rows[i] or NewRow(i)
		row.key = convo.key
		row.name:SetText(ns.Inbox_ColoredName(convo))
		row.ago:SetText(ns.Social_Ago(now - (convo.last or now)))
		local last = convo.messages[#convo.messages]
		if convo.restricted then
			row.preview:SetText(#convo.messages .. " during restrictions")
		else
			row.preview:SetText(last and ((last.out and "You: " or "") .. ns.Social_PlainText(last.text)) or "")
		end
		row.dot:SetShown(convo.unread > 0)
		row.bg:SetShown(convo.key == current)
		row.bar:SetShown(convo.key == current)
		row:Show()
	end
	for i = math.min(#list - scroll, maxRows) + 1, #rows do
		rows[i]:Hide()
	end
	ShowConversation()
end

-- The chat line under the conversation: Enter sends to whoever is open and keeps the box focused for the
-- next line, Esc leaves it. Not focused on open, so movement keys keep working while you read.
function CreateInput(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(INPUT_H)
	box:SetPoint("BOTTOMLEFT")
	box:SetPoint("BOTTOMRIGHT")
	box:SetAutoFocus(false)
	box:SetMaxLetters(255)
	box:SetFontObject(ChatFontNormal)
	box:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
	box:SetTextInsets(8, 8, 0, 0)
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BOX[1], UI.BOX[2], UI.BOX[3], UI.BOX[4])
	UI.Border(box, GOLD[1], GOLD[2], GOLD[3], 0.35)
	box.placeholder = UI.Text(box, 12, DIM)
	box.placeholder:SetPoint("LEFT", 8, 0)
	box:SetScript("OnTextChanged", function(self)
		self.placeholder:SetShown(self:GetText() == "")
	end)
	box:SetScript("OnEnterPressed", function(self)
		if current and ns.Whispers_Send(current, self:GetText()) then
			self:SetText("")
		end
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnHide", box.ClearFocus)
	box:SetScript("OnEditFocusGained", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.35)
	end)
	return box
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", 0, 60)
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], UI.BG[4])
	UI.Border(frame, GOLD[1], GOLD[2], GOLD[3], 0.35)

	local titleBar = CreateFrame("Frame", nil, frame)
	titleBar:SetPoint("TOPLEFT")
	titleBar:SetPoint("TOPRIGHT")
	titleBar:SetHeight(TITLE_H)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	titleBar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
	end)
	local title = UI.Text(titleBar, 20, GOLD, ns.SCENE_TITLE_FONT)
	title:SetPoint("LEFT", 16, -2)
	title:SetText("Whispers")
	local close = UI.Button(titleBar, 20, "x")
	close:SetPoint("RIGHT", -10, 0)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
	local readAll = UI.Button(titleBar, 110, "Mark all read")
	readAll:SetPoint("RIGHT", close, "LEFT", -8, 0)
	readAll:SetScript("OnClick", function()
		ns.Whispers_MarkAllRead()
	end)
	local line = UI.Hairline(titleBar, WIDTH - 40, 0.5)
	line:SetPoint("BOTTOM")

	frame.list = CreateFrame("Frame", nil, frame)
	frame.list:SetPoint("TOPLEFT", 8, -TITLE_H - 8)
	frame.list:SetPoint("BOTTOMLEFT", 8, 8)
	frame.list:SetWidth(LIST_W)
	frame.list:SetClipsChildren(true)
	frame.list:EnableMouseWheel(true)
	frame.list:SetScript("OnMouseWheel", function(_, delta)
		scroll = scroll - delta
		ns.Inbox_Refresh()
	end)
	local divider = UI.VLine(frame)
	divider:SetPoint("TOP", frame.list, "TOPRIGHT", 6, 0)
	divider:SetPoint("BOTTOM", frame.list, "BOTTOMRIGHT", 6, 0)

	local right = CreateFrame("Frame", nil, frame)
	right:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 16, 0)
	right:SetPoint("BOTTOMRIGHT", -12, 8)
	frame.header = UI.Text(right, 16, WHITE)
	frame.header:SetPoint("TOPLEFT", 0, -2)
	frame.reply = UI.Button(right, 70, "Reply")
	frame.reply:SetPoint("TOPRIGHT", 0, 0)
	frame.reply:SetScript("OnClick", function()
		if current then
			ns.Whispers_Reply(current)
		end
	end)
	frame.empty = UI.Text(right, 13, GREY)
	frame.empty:SetPoint("CENTER")
	frame.empty:SetText("No whispers yet.")

	frame.input = CreateInput(right)

	local messages = CreateFrame("ScrollingMessageFrame", nil, right)
	messages:SetPoint("TOPLEFT", 0, -30)
	messages:SetPoint("BOTTOMRIGHT", frame.input, "TOPRIGHT", 0, 8)
	messages:SetFontObject(ChatFontNormal)
	messages:SetJustifyH("LEFT")
	messages:SetFading(false)
	messages:SetMaxLines(200)
	messages:SetInsertMode("BOTTOM")
	messages:SetHyperlinksEnabled(true)
	messages:SetScript("OnHyperlinkClick", function(_, link, text, button)
		SetItemRef(link, text, button)
	end)
	messages:EnableMouseWheel(true)
	messages:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end)
	frame.messages = messages

	frame:SetScript("OnShow", ns.Inbox_Refresh)
	frame:SetScript("OnHide", function()
		drawn = nil -- opens at the newest message again
	end)

	-- Esc closes it: UISpecialFrames hides this dummy, which hides the window.
	local escape = CreateFrame("Frame", "TomteInboxEscape", UIParent)
	escape:Hide()
	table.insert(UISpecialFrames, "TomteInboxEscape")
	escape:SetScript("OnHide", function()
		if UIParent:IsShown() then -- not when a cinematic or Alt-Z hides the whole UI
			frame:Hide()
		end
	end)
	frame:HookScript("OnShow", function()
		escape:Show()
	end)
	frame:HookScript("OnHide", function()
		escape:Hide()
	end)
end

-- Opens on the newest unread conversation (else the one open last time, else the newest).
function ns.Inbox_Toggle(key)
	if not frame then
		Build()
	end
	if frame:IsShown() and not key then
		frame:Hide()
		return
	end
	if not key then
		local list = ns.Whispers_Convos()
		for _, convo in ipairs(list) do
			if convo.unread > 0 then
				key = convo.key
				break
			end
		end
		key = key or (current and ns.Whispers_Get(current) and current) or (list[1] and list[1].key)
	end
	current = key
	if key then
		ns.Whispers_MarkRead(key)
	end
	frame:Show()
	ns.Inbox_Refresh()
end

function ns.Inbox_IsShowing(key)
	return frame ~= nil and frame:IsShown() and current == key
end

function ns.Inbox_Hide()
	if frame then
		frame:Hide()
	end
end
