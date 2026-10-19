local addonName, ns = ...

-- Whisper inbox: a resizable window with your whisper conversations on the left (pinned first, then newest; avatar,
-- online dot, unread count) and the chosen conversation on the right: who they are (InboxWho.lua), the messages as
-- bubbles (InboxMessages.lua) and a chat line to answer from the window. Right-click a conversation (or its "···")
-- for pin, invite, add friend, copy and delete. Opening a conversation marks it read; a NEW divider shows where the
-- unread part began. Esc closes it. Built on first use.
-- The Whispers module owns the data (ns.Whispers_Convos / ns.Whispers_Get) and calls ns.Inbox_Refresh when
-- it changes. The session-only "In instance" conversation holds secret messages: shown, never inspected.

local UI = ns.UI
local WIDTH, HEIGHT = 660, 440
local MIN_W, MIN_H = 520, 340
local TITLE_H = 36
local LIST_W = 220
local ROW_H = 44
local SECTION_H = 22
local AVATAR = 28
local HEADER_AVATAR = 34
local HEADER_H = 50
local INPUT_H = 26
local WHO_SECONDS = 10 -- online status and zones are read again this often while the window is open
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local BNET_PORTRAIT = "Interface\\FriendsFrame\\Battlenet-Portrait"
local UNKNOWN_ICON = 134400 -- inv_misc_questionmark

local frame
local rows, sections = {}, {}
local current -- conversation key on the right
local newIndex -- first unread message of the current conversation when it was opened (the NEW divider)
local drawn -- { key, count, last, newIndex } of what the message pane holds: redrawn only when that changes
local ticker

-- Name in its class color (Battle.net friends in Blizzard's BN blue).
function ns.Inbox_ColoredName(convo)
	local name = convo.name or convo.key
	if convo.restricted then
		return UI.Wrap(name, "heading")
	elseif convo.bn then
		return FRIENDS_BNET_NAME_COLOR and FRIENDS_BNET_NAME_COLOR:WrapTextInColorCode(name) or UI.Wrap(name, "accent")
	end
	return UI.ClassColored(name, convo.class)
end

-- Avatar: the class icon, Battle.net's portrait for a friend who isn't in WoW, else a question mark.
local function SetAvatar(texture, convo, who)
	local classFile = (who and who.classFile) or convo.class
	local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	if coords and not convo.restricted then
		texture:SetTexture(CLASS_CIRCLES)
		texture:SetTexCoord(unpack(coords))
	elseif convo.bn then
		texture:SetTexture(BNET_PORTRAIT)
		texture:SetTexCoord(0, 1, 0, 1)
	else
		texture:SetTexture(UNKNOWN_ICON)
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

-- Online dot: green online, grey offline, hidden when it isn't known.
local function SetDot(dot, who)
	dot:SetShown(who ~= nil)
	if who then
		dot.fill:SetColorTexture(UI.Color(who.online and "success" or "textFaint"))
	end
end

local function CreateDot(parent, anchor)
	local dot = CreateFrame("Frame", nil, parent)
	dot:SetSize(10, 10)
	dot:SetPoint("CENTER", anchor, "BOTTOMRIGHT", -2, 2)
	dot:SetFrameLevel(parent:GetFrameLevel() + 3)
	dot.ring = dot:CreateTexture(nil, "ARTWORK")
	dot.ring:SetAllPoints()
	dot.ring:SetColorTexture(UI.Color("bg"))
	UI.CircleMask(dot.ring, dot)
	dot.fill = dot:CreateTexture(nil, "OVERLAY")
	dot.fill:SetPoint("TOPLEFT", 2, -2)
	dot.fill:SetPoint("BOTTOMRIGHT", -2, 2)
	UI.CircleMask(dot.fill, dot)
	return dot
end

local function Stamp(at)
	return date("%Y-%m-%d %H:%M", at)
end

-- Menu ------------------------------------------------------------------------------------------------------------

local function OpenMenu(owner, key)
	local convo = ns.Whispers_Get(key)
	if not convo or convo.restricted then
		return
	end
	local who = ns.InboxWho_Get(convo)
	local name = convo.name or convo.key
	UI.ContextMenu(owner, function(_, root)
		root:CreateTitle(name)
		root:CreateButton(convo.pinned and "Unpin" or "Pin to the top", function()
			ns.Whispers_SetPinned(key, not convo.pinned)
		end)
		if ns.InboxWho_CanInvite(who) then
			root:CreateButton("Invite to group", function()
				ns.InboxWho_Invite(who)
			end)
		end
		if ns.InboxWho_CanAddFriend(convo, who) then
			root:CreateButton("Add friend", function()
				ns.InboxWho_AddFriend(convo)
			end)
		end
		root:CreateButton("Copy conversation", function()
			ns.Dialog_Show({ title = "Whispers with " .. name, hint = "Ctrl+C copies it.", readOnly = true,
				height = 320, atEnd = true, text = ns.Inbox_CopyText(convo, Stamp) })
		end)
		root:CreateDivider()
		root:CreateButton("Delete", function()
			ns.Confirm_Show(("Delete the conversation with %s?\n\nIts messages are gone for good; a new whisper starts "
				.. "a new one."):format(name), function()
				ns.Whispers_Delete(key)
			end)
		end)
	end)
end

-- Conversation ----------------------------------------------------------------------------------------------------

local function ShowConversation()
	local convo = current and ns.Whispers_Get(current)
	local header = frame.header
	-- Secret "In instance" whispers can only be answered through Blizzard's chat box.
	header.reply:SetShown(convo ~= nil and convo.restricted == true)
	frame.input:SetShown(convo ~= nil and not convo.restricted)
	header:SetShown(convo ~= nil)
	frame.empty:SetShown(convo == nil and #ns.Whispers_Convos() == 0)
	if not convo then
		drawn = nil
		frame.pane:Show(nil)
		return
	end
	if not convo.restricted then
		frame.input.placeholder:SetText("Whisper " .. (convo.name or convo.key))
	end
	local who = ns.InboxWho_Get(convo)
	SetAvatar(header.avatar, convo, who)
	SetDot(header.dot, who)
	header.name:SetText(ns.Inbox_ColoredName(convo))
	header.status:SetText(convo.restricted and "Names and messages are hidden from addons in instances"
		or ns.Inbox_StatusText(who))
	header.invite:SetShown(ns.InboxWho_CanInvite(who))
	header.more:SetShown(not convo.restricted)

	-- Same conversation, no new message (someone else wrote, or it was only marked read): keep the scroll.
	local count, newest = #convo.messages, convo.messages[#convo.messages]
	if drawn and drawn.key == convo.key and drawn.count == count and drawn.last == newest
		and drawn.newIndex == newIndex then
		return
	end
	drawn = { key = convo.key, count = count, last = newest, newIndex = newIndex }
	frame.pane:Show(convo, newIndex)
end

-- Opens key on the right: the NEW divider goes where its unread messages began, then it's marked read.
local function Open(key)
	if key ~= current then
		frame.input:SetText("")
		local convo = key and ns.Whispers_Get(key)
		newIndex = convo and ns.Inbox_NewIndex(#convo.messages, convo.unread) or nil
	end
	current = key
	if key then
		ns.Whispers_MarkRead(key) -- refreshes the inbox
	else
		ns.Inbox_Refresh()
	end
end

-- List ------------------------------------------------------------------------------------------------------------

local function NewRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("hover"))
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetColorTexture(UI.Color("accent"))
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.RGBA("hover", 0.5))
	row.hover:Hide()
	row.avatar = row:CreateTexture(nil, "ARTWORK")
	row.avatar:SetSize(AVATAR, AVATAR)
	row.avatar:SetPoint("LEFT", 10, 0)
	row.dot = CreateDot(row, row.avatar)
	row.badge = CreateFrame("Frame", nil, row)
	row.badge:SetHeight(14)
	row.badge:SetPoint("TOPRIGHT", -8, -7)
	row.badge.bg = row.badge:CreateTexture(nil, "BACKGROUND")
	row.badge.bg:SetAllPoints()
	row.badge.bg:SetColorTexture(UI.Color("accent"))
	row.badge.text = UI.Text(row.badge, 10, "bg", "number")
	row.badge.text:SetPoint("CENTER", 0, 0)
	row.badge.text:SetShadowOffset(0, 0)
	row.ago = UI.Text(row, 10, "textFaint", "number")
	row.ago:SetJustifyH("RIGHT")
	row.ago:SetPoint("TOPRIGHT", -8, -8)
	row.name = UI.Text(row, 13, "text")
	row.name:SetPoint("TOPLEFT", row.avatar, "TOPRIGHT", 9, 0)
	row.name:SetPoint("RIGHT", -40, 0)
	row.name:SetWordWrap(false)
	row.preview = UI.Text(row, 11, "textMuted", "chat")
	row.preview:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.preview:SetPoint("RIGHT", -8, 0)
	row.preview:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		self.hover:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			OpenMenu(self, self.key)
		else
			Open(self.key)
		end
	end)
	return row
end

local function SetRow(row, convo, now)
	row.key = convo.key
	local who = ns.InboxWho_Get(convo)
	SetAvatar(row.avatar, convo, who)
	SetDot(row.dot, who)
	row.name:SetText(ns.Inbox_ColoredName(convo))
	local unread = convo.unread or 0
	row.badge:SetShown(unread > 0)
	row.ago:SetShown(unread == 0)
	if unread > 0 then
		row.badge.text:SetText(unread > 99 and "99+" or unread)
		row.badge:SetWidth(math.max(math.ceil(row.badge.text:GetStringWidth()) + 8, 14))
	else
		row.ago:SetText(ns.Social_Ago(now - (convo.last or now)))
	end
	local last = convo.messages[#convo.messages]
	if convo.restricted then
		row.preview:SetText(#convo.messages .. " during restrictions")
	else
		row.preview:SetText(last and ((last.out and "You: " or "") .. ns.Social_PlainText(last.text)) or "")
	end
	local selected = convo.key == current
	row.bg:SetShown(selected)
	row.bar:SetShown(selected)
	UI.SetTextRole(row.preview, unread > 0 and "text" or "textMuted")
end

local function Section(i, parent)
	local s = sections[i]
	if not s then
		s = UI.Text(parent, 10, "textFaint", "label")
		sections[i] = s
	end
	return s
end

local function RefreshList()
	local content = frame.list.content
	local list, pinnedCount = ns.Inbox_Order(ns.Whispers_Convos())
	local now = time()
	local y, nSections = 4, 0
	local function Heading(text)
		nSections = nSections + 1
		local s = Section(nSections, content)
		s:ClearAllPoints()
		s:SetPoint("TOPLEFT", 12, -(y + 7))
		s:SetText(ns.Spaced(text))
		s:Show()
		y = y + SECTION_H
	end
	for i, convo in ipairs(list) do
		if pinnedCount > 0 and i == 1 then
			Heading("Pinned")
		elseif pinnedCount > 0 and i == pinnedCount + 1 then
			Heading("Recent")
		end
		local row = rows[i] or NewRow(content)
		rows[i] = row
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", content, "RIGHT")
		SetRow(row, convo, now)
		row:Show()
		y = y + ROW_H
	end
	for i = #list + 1, #rows do
		rows[i]:Hide()
	end
	for i = nSections + 1, #sections do
		sections[i]:Hide()
	end
	frame.list:SetContentHeight(y + 4)
end

function ns.Inbox_Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	if current and not ns.Whispers_Get(current) then
		current, newIndex = nil, nil
	end
	RefreshList()
	ShowConversation()
end

-- Window ----------------------------------------------------------------------------------------------------------

local function SaveLayout()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	local db = ns.whispersDB.inbox
	db.point = { point, relPoint, x, y }
	db.w, db.h = frame:GetWidth(), frame:GetHeight()
end

local function ApplyLayout()
	local maxW, maxH = math.max(UIParent:GetWidth(), MIN_W), math.max(UIParent:GetHeight(), MIN_H)
	frame:SetResizeBounds(MIN_W, MIN_H, maxW, maxH)
	local db = ns.whispersDB.inbox
	frame:ClearAllPoints()
	if db.point then
		frame:SetSize(math.min(math.max(db.w or WIDTH, MIN_W), maxW), math.min(math.max(db.h or HEIGHT, MIN_H), maxH))
		frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
	else
		frame:SetSize(WIDTH, HEIGHT)
		frame:SetPoint("CENTER", 0, 60)
	end
end

-- The chat line under the conversation: Enter sends to whoever is open and keeps the box focused for the
-- next line, Esc leaves it. Not focused on open, so movement keys keep working while you read.
local function CreateInput(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(INPUT_H)
	box:SetPoint("BOTTOMLEFT")
	box:SetPoint("BOTTOMRIGHT")
	box:SetAutoFocus(false)
	box:SetMaxLetters(255)
	box:SetFontObject(ChatFontNormal)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(10, 10, 0, 0)
	UI.Surface(box, 0.5)
	box.placeholder = UI.Text(box, 12, "textFaint")
	box.placeholder:SetPoint("LEFT", 10, 0)
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
		UI.SetBorderColor(self, "accent", 0.8)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		UI.SetBorderColor(self, "frame", 0.5)
	end)
	return box
end

local function CreateHeader(parent)
	local header = CreateFrame("Frame", nil, parent)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_H)
	header.avatar = header:CreateTexture(nil, "ARTWORK")
	header.avatar:SetSize(HEADER_AVATAR, HEADER_AVATAR)
	header.avatar:SetPoint("LEFT", 0, 2)
	header.dot = CreateDot(header, header.avatar)
	header.more = UI.Button(header, 30, "...") -- the conversation's menu (same as right-click in the list)
	header.more:SetHeight(22)
	header.more:SetPoint("RIGHT", 0, 2)
	header.more:SetScript("OnClick", function(self)
		OpenMenu(self, current)
	end)
	header.invite = UI.Button(header, 70, "Invite")
	header.invite:SetHeight(22)
	header.invite:SetPoint("RIGHT", header.more, "LEFT", -6, 0)
	header.invite:SetScript("OnClick", function()
		local convo = current and ns.Whispers_Get(current)
		local who = convo and ns.InboxWho_Get(convo)
		if ns.InboxWho_CanInvite(who) then
			ns.InboxWho_Invite(who)
		end
	end)
	header.reply = UI.Button(header, 70, "Reply")
	header.reply:SetHeight(22)
	header.reply:SetPoint("RIGHT", 0, 2)
	header.reply:SetScript("OnClick", function()
		if current then
			ns.Whispers_Reply(current)
		end
	end)
	header.name = UI.Text(header, 16, "text", "title")
	header.name:SetPoint("TOPLEFT", header.avatar, "TOPRIGHT", 10, -1)
	header.name:SetPoint("RIGHT", header.invite, "LEFT", -10, 0)
	header.name:SetWordWrap(false)
	header.status = UI.Text(header, 11, "textMuted")
	header.status:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -4)
	header.status:SetPoint("RIGHT", header.invite, "LEFT", -10, 0)
	header.status:SetWordWrap(false)
	local line = header:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(UI.Color("rule"))
	line:SetAlpha(0.6)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	return header
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true) -- same strata as the Tomte window: a click brings it to the front
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetClampedToScreen(true)
	frame:SetDontSavePosition(true) -- saved in Whispers' settings (whispers.inbox)
	frame:EnableMouse(true)
	frame:Hide()
	UI.Panel(frame)
	ApplyLayout()

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
		SaveLayout()
	end)
	local title = UI.Text(titleBar, 18, "heading", "title")
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
	line:ClearAllPoints()
	line:SetPoint("BOTTOMLEFT", 20, 0)
	line:SetPoint("BOTTOMRIGHT", -20, 0)

	frame.list = UI.Scroll(frame)
	frame.list:SetPoint("TOPLEFT", 6, -TITLE_H - 6)
	frame.list:SetPoint("BOTTOMLEFT", 6, 10)
	frame.list:SetWidth(LIST_W)
	local divider = UI.VLine(frame)
	divider:SetPoint("TOP", frame.list, "TOPRIGHT", 12, 0)
	divider:SetPoint("BOTTOM", frame.list, "BOTTOMRIGHT", 12, 0)

	local right = CreateFrame("Frame", nil, frame)
	right:SetPoint("TOPLEFT", frame.list, "TOPRIGHT", 24, -2)
	right:SetPoint("BOTTOMRIGHT", -16, 14)
	frame.header = CreateHeader(right)
	frame.empty = UI.Text(right, 13, "textMuted")
	frame.empty:SetPoint("CENTER")
	frame.empty:SetText("No whispers yet.")
	frame.input = CreateInput(right)
	frame.pane = ns.InboxMessages_Create(right)
	frame.pane.frame:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -6)
	frame.pane.frame:SetPoint("BOTTOMRIGHT", frame.input, "TOPRIGHT", 0, 8)

	UI.ResizeGrip(frame, SaveLayout)

	frame:SetScript("OnShow", function()
		ns.Inbox_Refresh()
		-- Online status and zones change without a whisper: read them again now and then while it's open.
		ticker = C_Timer.NewTicker(WHO_SECONDS, ns.Inbox_Refresh)
	end)
	frame:SetScript("OnHide", function()
		-- Closed (not hidden with the whole UI by Alt-Z or a cinematic): opens at the newest message again.
		if UIParent:IsShown() then
			drawn = nil
			newIndex = nil
		end
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
	end)

	UI.CloseOnEscape(frame) -- after the SetScripts above: they would drop its hooks
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
		local list = ns.Inbox_Order(ns.Whispers_Convos())
		for _, convo in ipairs(list) do
			if convo.unread > 0 then
				key = convo.key
				break
			end
		end
		key = key or (current and ns.Whispers_Get(current) and current) or (list[1] and list[1].key)
	end
	frame:Show()
	frame:Raise() -- opened from the Tomte window, whose click just raised it
	current = nil -- so Open sets the NEW divider for it
	Open(key)
end

function ns.Inbox_IsShowing(key)
	return frame ~= nil and frame:IsShown() and current == key
end

function ns.Inbox_Hide()
	if frame then
		frame:Hide()
	end
end
