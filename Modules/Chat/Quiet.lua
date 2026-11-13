local addonName, ns = ...

-- Quiet Chat module: the chat window stays out of sight until it has something new or you use it
-- (docs/superpowers/specs/2026-11-13-tomte-quiet-chat-design.md). Idle: no background, border, tabs, side buttons or
-- edit box frame, only fresh lines over the world (a faint soft shadow behind just those lines), plus a chip naming
-- tabs with unread whispers. Awake (Blizzard's own
-- hover fade-in, or typing): a soft shadow from the left, tabs as text in the theme's font and a line to type on. The
-- side buttons stay hidden; Friends, Chat channels and Emotes are in the chat tab's right-click menu instead.
-- Pure parts (chip entries, fade step) in Chat/Data.lua.
-- Blizzard's chat frames are restyled, never replaced. Its fades only touch the textures that are shown, so the
-- background and border are hidden; the docked tabs fade with GeneralDockManager's alpha, which Blizzard never sets.
-- Nothing is written into Blizzard's tables (Blizzard keeps tab state off the tabs because chat lines can be handled
-- from addon code). The edit box gets no script hooks (Autocorrect.lua: they taint sending); its focus comes through
-- EventRegistry callbacks, which run through securecallfunction.

local OWNER = "TomteQuietChat" -- EventRegistry callback owner
local FADE_IN = 0.15 -- seconds, Blizzard's CHAT_FRAME_FADE_TIME (read live: a setting can make it 0)
local FADE_OUT = 2 -- seconds, Blizzard's CHAT_FRAME_FADE_OUT_TIME
local TAB_FONT_SIZE = 11
local COUNT_FONT_SIZE = 9
local CHIP_FONT_SIZE = 10
local CHIP_MAX = 3 -- tabs named on the chip; more show as "+N"
local CHIP_PAD_X, CHIP_PAD_Y = 7, 4
-- Shadows: soft-edged rectangles cut from a round glow (nine slices: the glow's quarters as corners, its middle row
-- and column stretched as edges). Each is placed so its feathers lie outside what it covers, so text, tabs and the type
-- line always sit on the even middle, never on a fading edge (the first try put the start of each line on the edge).
local SHADOW_TEXTURE = "Showcase\\Glow" -- under Theme.MEDIA: a 128 px round glow, peak alpha 239 in the middle
local SHADOW_FEATHER = { left = 28, top = 20, right = 90, bottom = 20 } -- px each edge takes to fade to nothing
local SHADOW_PAD = { x = 8, y = 4 } -- px of even shadow around what a shadow covers
local SHADOW_ALPHA = 0.6 -- the middle, on the theme's darkest color
local SLICE_MID = 0.5 -- the glow's middle row/column, sampled for the stretched edges and the middle
local SLICE_HALF = 0.01 -- half the width sampled there (a zero-width sample can land between texels)
local SCROLL_ROOM = 24 -- px right of the chat frame the awake shadow covers: Blizzard's scroll bar sits there
local TAB_ROW = 26 -- px from the chat frame's top to the tabs' top, when the dock can't be measured
-- Asleep, a shadow fitted to the lines still showing, read from the window's own line slots (visibleLines in
-- Blizzard's ScrollingMessageFrame.lua: each drawn line is a font string whose alpha is its fade). A guess from line
-- times got the size wrong (a hover brings every line back). The game's text outline is no help here: it's always
-- solid black, too harsh on dark text colors.
local BACKING_ALPHA = 0.75 -- of the full shadow, times the strongest showing line's alpha
local TRACK_STEP = 0.05 -- seconds between reads of the line slots while lines show
-- Seconds to keep reading after a start even while no line shows: a new line is only drawn on the window's next
-- update, so the first read can come too early (a lone line got no shadow when that read stopped the tracker).
local TRACK_GRACE = 0.5
local DEACTIVATED_EDIT_ALPHA = 0.35 -- Blizzard's alpha for an idle chat edit box (Deactivate in ChatFrameEditBox.lua)
local LINE_INSET = 8 -- the type line's inset from the edit box's ends
local LINE_RAISE = 6 -- and from its bottom edge
-- The tab's art, muted while the module is on (Blizzard shows and hides some of it, but never sets their alpha).
local TAB_ART = {
	"Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
	"HighlightLeft", "HighlightMiddle", "HighlightRight",
}
local EDIT_ART = { "Left", "Right", "Mid" } -- named regions of each chat edit box
local EDIT_FOCUS_ART = { "focusLeft", "focusMid", "focusRight" } -- and its focus border, by parentKey
-- Frames that fade with the chat: the docked tabs and the combat log's filter bar.
local FOLLOWERS = { "GeneralDockManager", "CombatLogQuickButtonFrame_Custom" }
-- The side buttons: hidden while the module is on; their jobs are in the chat tab's right-click menu instead.
-- Where that menu can't be extended (no Menu.ModifyMenu), they fade with the chat like the tabs.
local SIDE_BUTTONS = {
	"ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
	"ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
}
local TAB_MENU = "MENU_FCF_TAB" -- Blizzard's chat tab menu (FCF_Tab_SetupMenu in FloatingChatFrame.lua)
-- Addons that style chat themselves.
local OTHER_CHAT = { "Prat-3.0", "Chattynator", "Glass" }

local UI = ns.UI
local Theme = ns.Theme
local IsSecret = ns.IsSecret

local module
local hooked = false
local styled = {} -- [chat frame] = what Tomte changed on it, to put back
local tabs = {} -- [chat tab] = { underline, count } (Tomte's frames on the tab)
local hovered = {} -- [docked chat frame] = true while Blizzard has it faded in
local unread = {} -- [chat frame] = whispers since its tab started flashing
local typingBox -- the chat edit box with the cursor in it
local followerAlpha = {} -- [FOLLOWERS name] = its alpha before the module started
local buttonState = {} -- [SIDE_BUTTONS name] = { alpha, mouse } before the module hid it
local menuHooked = false
local wake, wakeTarget = 0, 0 -- 0 asleep .. 1 awake
local holder, line, chip, driver
local asleepLayer, backing, tracker -- the backing lives on a layer faded opposite to the wake
local lineInfo = {} -- the shown window's line slots, as ns.Chat_ShadowSpan reads them (reused)
local lineHooked = {} -- [chat frame] = true once its AddMessage is hooked
local backingTop, backingBottom, backingWidth -- what the backing is anchored to now

local function PrimaryFrame()
	return GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.primary or DEFAULT_CHAT_FRAME
end

local function SelectedFrame()
	return GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) or DEFAULT_CHAT_FRAME
end

local function EachChatFrame(fn)
	for _, name in ipairs(CHAT_FRAMES or {}) do
		local frame = _G[name]
		if frame then
			fn(frame, name)
		end
	end
end

local function IsDocked(frame)
	return frame.isDocked or frame == PrimaryFrame()
end

-- Tomte's frames ----------------------------------------------------------------------------------------------------

-- One slice of the shadow. u/v: "low" (the glow's rising half), "mid" (its middle, stretched) or "high".
local SLICE_COORDS = {
	low = { 0, SLICE_MID },
	mid = { SLICE_MID - SLICE_HALF, SLICE_MID + SLICE_HALF },
	high = { SLICE_MID, 1 },
}

local function Slice(parent, u, v)
	local tex = parent:CreateTexture(nil, "BACKGROUND")
	tex:SetTexture(Theme.MEDIA .. SHADOW_TEXTURE)
	tex:SetTexCoord(SLICE_COORDS[u][1], SLICE_COORDS[u][2], SLICE_COORDS[v][1], SLICE_COORDS[v][2])
	tex:SetVertexColor(UI.RGBA("frameDark", SHADOW_ALPHA))
	return tex
end

-- Nine slices filling `parent`: corners sized by the feathers, edges between them, the middle in the rest.
local function SoftShadow(parent)
	local f = SHADOW_FEATHER
	local tl, tr = Slice(parent, "low", "low"), Slice(parent, "high", "low")
	local bl, br = Slice(parent, "low", "high"), Slice(parent, "high", "high")
	tl:SetPoint("TOPLEFT")
	tl:SetSize(f.left, f.top)
	tr:SetPoint("TOPRIGHT")
	tr:SetSize(f.right, f.top)
	bl:SetPoint("BOTTOMLEFT")
	bl:SetSize(f.left, f.bottom)
	br:SetPoint("BOTTOMRIGHT")
	br:SetSize(f.right, f.bottom)
	local top, bottom = Slice(parent, "mid", "low"), Slice(parent, "mid", "high")
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
	top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
	bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	local left, right = Slice(parent, "low", "mid"), Slice(parent, "high", "mid")
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
	left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
	right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	local middle = Slice(parent, "mid", "mid")
	middle:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
	middle:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
end

-- The shadow and the type line live on one holder, faded as a whole.
local function CreateHolder()
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetFrameStrata("BACKGROUND")
	holder:SetAlpha(0)
	SoftShadow(holder)

	line = CreateFrame("Frame", nil, holder)
	line:SetHeight(1)
	line.tex = line:CreateTexture(nil, "ARTWORK")
	line.tex:SetAllPoints()

	asleepLayer = CreateFrame("Frame", nil, UIParent)
	asleepLayer:SetFrameStrata("BACKGROUND")
	asleepLayer:SetAllPoints(UIParent)
	backing = CreateFrame("Frame", nil, asleepLayer)
	backing:Hide()
	SoftShadow(backing)
	tracker = CreateFrame("Frame")

	chip = CreateFrame("Frame", nil, UIParent)
	chip:SetFrameStrata("LOW")
	chip:EnableMouse(false)
	local bg = chip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.RGBA("frameDark", 0.6))
	UI.Border(chip, "frame", 0.6)
	chip.text = UI.Text(chip, CHIP_FONT_SIZE, "heading", "label")
	chip.text:SetPoint("CENTER")
	chip:Hide()

	driver = CreateFrame("Frame")
end

local function PlaceHolder()
	local primary = PrimaryFrame()
	if not primary then
		return
	end
	-- From the tabs' top to the type line, and from the text's left edge to past the scroll bar; feathers outside that.
	local box = primary.editBox
	local f, pad = SHADOW_FEATHER, SHADOW_PAD
	local above, below = TAB_ROW, 0
	local dock, top, bottom = GeneralDockManager, primary:GetTop(), primary:GetBottom()
	if dock and dock:IsShown() and dock:GetTop() and top then
		above = dock:GetTop() - top
	end
	if box and box:GetBottom() and bottom then
		below = bottom - (box:GetBottom() + LINE_RAISE)
	end
	holder:ClearAllPoints()
	holder:SetPoint("TOPLEFT", primary, "TOPLEFT", -(pad.x + f.left), above + pad.y + f.top)
	holder:SetPoint("BOTTOMRIGHT", primary, "BOTTOMRIGHT", SCROLL_ROOM + f.right, -(below + pad.y + f.bottom))
	line:ClearAllPoints()
	if box then
		line:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", LINE_INSET, LINE_RAISE)
		line:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -LINE_INSET, LINE_RAISE)
		chip:ClearAllPoints()
		chip:SetPoint("LEFT", box, "LEFT", LINE_INSET, 0)
	end
end

-- The type line: faint while awake, accent while typing. With the classic chat style the box only exists while typing.
local function UpdateLine()
	if typingBox then
		line.tex:SetColorTexture(UI.RGBA("accent", 0.7))
	else
		line.tex:SetColorTexture(UI.RGBA("frame", 0.45))
	end
	line:SetShown(typingBox ~= nil or C_CVar.GetCVar("chatStyle") ~= "classic")
end

-- Backing -----------------------------------------------------------------------------------------------------------

-- The shown window's line slots as plain values. A line's width or row count can be secret (chat lockdown): then
-- the width is unknown and the shadow takes the frame's width.
local function ReadLines(frame)
	local slots = frame.visibleLines
	if type(slots) ~= "table" then
		return nil
	end
	local count = 0
	for index, fs in ipairs(slots) do
		count = index
		local info = lineInfo[index] or {}
		lineInfo[index] = info
		info.shown = fs:IsShown()
		info.alpha = fs:GetAlpha()
		local width, rows = fs:GetUnboundedStringWidth(), fs:GetNumLines()
		if IsSecret(width, rows) then
			info.width, info.wraps = nil, false
		else
			info.width, info.wraps = width, rows > 1
		end
	end
	for index = #lineInfo, count + 1, -1 do
		lineInfo[index] = nil
	end
	return lineInfo
end

local function HideBacking()
	backing:Hide()
	backingTop, backingBottom, backingWidth = nil, nil, nil
	tracker:SetScript("OnUpdate", nil)
end

-- Fits the backing to the lines showing now; stops reading once none do.
local function UpdateBacking()
	local frame = SelectedFrame()
	if not (module.active and module.db.lineBacking and frame) then
		HideBacking()
		return
	end
	local span = ns.Chat_ShadowSpan(ReadLines(frame), frame:GetWidth())
	if not span then
		if GetTime() < (tracker.keepUntil or 0) then
			backing:Hide()
		else
			HideBacking()
		end
		return
	end
	-- Slot 1 is the newest line: at the bottom, unless the window adds lines at the top.
	local fromTop = frame.GetInsertMode and frame:GetInsertMode() == SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP
	local topLine = frame.visibleLines[fromTop and span.first or span.last]
	local bottomLine = frame.visibleLines[fromTop and span.last or span.first]
	local f, pad = SHADOW_FEATHER, SHADOW_PAD
	if topLine ~= backingTop or bottomLine ~= backingBottom then
		backingTop, backingBottom = topLine, bottomLine
		backing:ClearAllPoints()
		backing:SetPoint("TOPLEFT", topLine, "TOPLEFT", -(pad.x + f.left), pad.y + f.top)
		backing:SetPoint("BOTTOMLEFT", bottomLine, "BOTTOMLEFT", -(pad.x + f.left), -(pad.y + f.bottom))
	end
	local width = span.width + pad.x * 2 + f.left + f.right
	if width ~= backingWidth then
		backingWidth = width
		backing:SetWidth(width)
	end
	backing:SetAlpha(span.alpha * BACKING_ALPHA)
	backing:Show()
end

local function OnTrackerUpdate(self, elapsed)
	self.wait = (self.wait or 0) - elapsed
	if self.wait <= 0 then
		self.wait = TRACK_STEP
		UpdateBacking()
	end
end

-- Lines show (a new one, chat going back to sleep, a setting): read the slots until they've all faded.
local function TrackLines()
	if module.active and module.db.lineBacking then
		tracker.wait = 0
		tracker.keepUntil = GetTime() + TRACK_GRACE
		tracker:SetScript("OnUpdate", OnTrackerUpdate)
	end
end

local function OnLineAdded(frame)
	if module.active and frame == SelectedFrame() then
		TrackLines()
	end
end

-- Unread ------------------------------------------------------------------------------------------------------------

local function WhisperColor()
	local info = ChatTypeInfo and ChatTypeInfo.WHISPER
	return info and { info.r, info.g, info.b } or "accent"
end

local function TabName(frame)
	local tab = _G[frame:GetName() .. "Tab"]
	local name = tab and tab:GetText()
	if IsSecret(name) or type(name) ~= "string" then
		return nil
	end
	return name
end

local function RefreshUnread()
	local color = WhisperColor()
	for _, parts in pairs(tabs) do
		local count = unread[parts.frame]
		parts.count:SetText(count and tostring(count) or "")
		parts.count:SetTextColor(UI.RGBA(color))
	end

	local list = {}
	EachChatFrame(function(frame)
		if IsDocked(frame) and unread[frame] then
			list[#list + 1] = { name = TabName(frame), count = unread[frame] }
		end
	end)
	local shown, more = ns.Chat_UnreadChip(list, CHIP_MAX)
	if not module.db.chip or #shown == 0 then
		chip:Hide()
		return
	end
	local parts = {}
	for _, entry in ipairs(shown) do
		parts[#parts + 1] = entry.name .. " " .. UI.Wrap(tostring(entry.count), color)
	end
	local text = table.concat(parts, "   ")
	if more > 0 then
		text = text .. "   " .. UI.Wrap("+" .. more, "textMuted")
	end
	chip.text:SetText(text)
	chip:SetSize(chip.text:GetStringWidth() + CHIP_PAD_X * 2, chip.text:GetStringHeight() + CHIP_PAD_Y * 2)
	chip:Show()
end

-- Waking ------------------------------------------------------------------------------------------------------------

local function CanUseMenu()
	return Menu ~= nil and Menu.ModifyMenu ~= nil
end

local function ApplyWake()
	holder:SetAlpha(wake)
	chip:SetAlpha(1 - wake)
	asleepLayer:SetAlpha(1 - wake)
	-- Edit boxes: a message you clicked away from without sending stays in its box, so it fades with the chat too
	-- (it comes back when you point at the chat or press Enter). The box you type in is always fully shown.
	for frame in pairs(styled) do
		local box = frame.editBox
		if box then
			if box:HasFocus() then
				box:SetAlpha(1)
			else
				box:SetAlpha(box:GetText() == "" and wake * DEACTIVATED_EDIT_ALPHA or wake)
			end
		end
	end
	for _, name in ipairs(FOLLOWERS) do
		local frame = _G[name]
		if frame and frame.SetAlpha then
			frame:SetAlpha(wake)
		end
	end
	if not CanUseMenu() then
		for _, name in ipairs(SIDE_BUTTONS) do
			local frame = _G[name]
			if frame and frame.SetAlpha then
				frame:SetAlpha(wake)
			end
		end
	end
end

local function HideSideButtons()
	if not CanUseMenu() then
		return
	end
	for _, name in ipairs(SIDE_BUTTONS) do
		local frame = _G[name]
		if frame and frame.SetAlpha and not buttonState[name] then
			buttonState[name] = { alpha = frame:GetAlpha(), mouse = frame:IsMouseEnabled() }
			frame:SetAlpha(0)
			frame:EnableMouse(false)
		end
	end
end

local function ShowSideButtons()
	for name, state in pairs(buttonState) do
		_G[name]:SetAlpha(state.alpha)
		_G[name]:EnableMouse(state.mouse)
	end
	wipe(buttonState)
	if not CanUseMenu() then
		for _, name in ipairs(SIDE_BUTTONS) do
			local frame = _G[name]
			if frame and frame.SetAlpha then
				frame:SetAlpha(1)
			end
		end
	end
end

-- The side buttons' jobs, at the end of every chat tab's right-click menu.
local function OpenChatMenu()
	local button = ChatFrameMenuButton
	if button and button.OpenMenu then
		button:OpenMenu()
	end
end

local function AddMenuEntries(_, root)
	if not module.active then
		return
	end
	root:CreateDivider()
	root:CreateButton("Friends", function()
		ToggleFriendsFrame()
	end)
	if ToggleChannelFrame then
		root:CreateButton("Chat channels", function()
			ToggleChannelFrame()
		end)
	end
	if ChatFrameMenuButton and ChatFrameMenuButton.OpenMenu then
		root:CreateButton("Emotes and languages", function()
			-- After this menu has closed, or closing it would close the new one too.
			C_Timer.After(0, OpenChatMenu)
		end)
	end
end

local function OnDriverUpdate(self, elapsed)
	local seconds = wakeTarget == 1 and (CHAT_FRAME_FADE_TIME or FADE_IN) or (CHAT_FRAME_FADE_OUT_TIME or FADE_OUT)
	local done
	wake, done = ns.Chat_FadeStep(wake, wakeTarget, elapsed, seconds)
	ApplyWake()
	if done then
		self:SetScript("OnUpdate", nil)
	end
end

local function UpdateWake()
	local target = (next(hovered) or typingBox) and 1 or 0
	if target == wakeTarget then
		return
	end
	wakeTarget = target
	if target == 1 then
		-- Bring back the lines that already faded, the way Blizzard does when you click a tab.
		local frame = SelectedFrame()
		if frame and frame.ResetAllFadeTimes then
			frame:ResetAllFadeTimes()
		end
		PlaceHolder() -- the window may have been moved or resized since
	else
		TrackLines() -- the lines a hover brought back fade from here on
	end
	driver:SetScript("OnUpdate", OnDriverUpdate)
end

-- Restyling Blizzard's chat -----------------------------------------------------------------------------------------

local function ColorTab(tab, selected)
	local fs = tab:GetFontString()
	local parts = tabs[tab]
	if not fs or not parts then
		return
	end
	-- Whisper and channel windows keep Blizzard's color for their kind.
	if not tab.selectedColorTable then
		fs:SetTextColor(UI.Color(selected and "heading" or "textMuted"))
	end
	parts.underline:SetShown(selected and IsDocked(parts.frame))
	if tab.glow then
		-- The new-message flash: the count beside the name says it instead. Vertex alpha, since the flash
		-- animation drives the texture's own alpha.
		tab.glow:SetVertexColor(1, 1, 1, 0)
	end
end

local function StyleTab(frame, tab, saved)
	local fs = tab:GetFontString()
	if not fs then
		return
	end
	for _, key in ipairs(TAB_ART) do
		if tab[key] then
			tab[key]:SetAlpha(0)
		end
	end
	saved.tabFontObject = fs:GetFontObject()
	saved.tabFont = { fs:GetFont() }
	Theme.SetFont(fs, "label", TAB_FONT_SIZE)

	local parts = tabs[tab]
	if not parts then
		parts = { frame = frame }
		local over = CreateFrame("Frame", nil, tab)
		over:SetAllPoints()
		parts.over = over
		parts.underline = over:CreateTexture(nil, "OVERLAY")
		parts.underline:SetHeight(1)
		parts.underline:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
		parts.underline:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -2)
		parts.count = UI.Text(over, COUNT_FONT_SIZE, "text", "number")
		parts.count:SetPoint("BOTTOMLEFT", fs, "RIGHT", 2, 0)
		tabs[tab] = parts
	end
	parts.underline:SetColorTexture(UI.Color("accent"))
	parts.over:Show()
	ColorTab(tab, not frame.isDocked or frame == SelectedFrame())
end

local function UnstyleTab(tab, saved)
	local fs = tab:GetFontString()
	for _, key in ipairs(TAB_ART) do
		if tab[key] then
			tab[key]:SetAlpha(1)
		end
	end
	if fs then
		if saved.tabFontObject then
			fs:SetFontObject(saved.tabFontObject)
		elseif saved.tabFont and saved.tabFont[1] then
			fs:SetFont(unpack(saved.tabFont))
		end
		local color = tab.selectedColorTable or NORMAL_FONT_COLOR
		fs:SetTextColor(color.r, color.g, color.b)
	end
	local glow = tab.selectedColorTable or DEFAULT_TAB_SELECTED_COLOR_TABLE or NORMAL_FONT_COLOR
	if tab.glow then
		tab.glow:SetVertexColor(glow.r, glow.g, glow.b, 1)
	end
	if tabs[tab] then
		tabs[tab].over:Hide()
	end
end

local function SetOutline(frame, saved)
	local path, size, flags = frame:GetFont()
	if not path then
		return
	end
	if saved.fontFlags == nil then
		saved.fontFlags = flags or ""
	end
	frame:SetFont(path, size, module.db.textOutline and "OUTLINE" or saved.fontFlags)
end

local function SetEditArt(frame, alpha)
	local box = frame.editBox
	if not box or not box:GetName() then
		return
	end
	for _, key in ipairs(EDIT_ART) do
		local tex = _G[box:GetName() .. key]
		if tex then
			tex:SetAlpha(alpha)
		end
	end
	for _, key in ipairs(EDIT_FOCUS_ART) do
		if box[key] then
			box[key]:SetAlpha(alpha)
		end
	end
end

local function Restyle(frame, name)
	if styled[frame] then
		return
	end
	local saved = { hidden = {} }
	for _, key in ipairs(CHAT_FRAME_TEXTURES or {}) do
		local tex = _G[name .. key]
		if tex and tex:IsShown() then
			tex:Hide()
			saved.hidden[#saved.hidden + 1] = tex
		end
	end
	if frame.GetTimeVisible then
		saved.timeVisible = frame:GetTimeVisible()
		frame:SetTimeVisible(module.db.lineSeconds)
	end
	SetOutline(frame, saved)
	SetEditArt(frame, 0)
	if not lineHooked[frame] and frame.AddMessage then
		lineHooked[frame] = true
		hooksecurefunc(frame, "AddMessage", OnLineAdded) -- does nothing while the module is off
	end
	local tab = _G[name .. "Tab"]
	if tab then
		StyleTab(frame, tab, saved)
	end
	styled[frame] = saved
end

local function RestyleAll()
	EachChatFrame(Restyle)
end

local function Unstyle(frame, saved)
	local name = frame:GetName()
	for _, tex in ipairs(saved.hidden) do
		tex:Show()
	end
	if saved.timeVisible then
		frame:SetTimeVisible(saved.timeVisible)
	end
	local path, size = frame:GetFont()
	if path and saved.fontFlags then
		frame:SetFont(path, size, saved.fontFlags)
	end
	SetEditArt(frame, 1)
	local box = frame.editBox
	if box then
		local inUse = box:HasFocus() or box:GetText() ~= ""
		box:SetAlpha(inUse and 1 or DEACTIVATED_EDIT_ALPHA)
	end
	local tab = name and _G[name .. "Tab"]
	if tab then
		UnstyleTab(tab, saved)
	end
end

local function UnstyleAll()
	for frame, saved in pairs(styled) do
		Unstyle(frame, saved)
	end
	wipe(styled)
end

-- Hooks (they can't be undone, so they do nothing while the module is off) ----------------------------------------

local function OnFadeIn(frame)
	if not module.active or not frame or not IsDocked(frame) then
		return
	end
	hovered[frame] = true
	UpdateWake()
end

local function OnFadeOut(frame)
	if not module.active or not frame then
		return
	end
	hovered[frame] = nil
	UpdateWake()
end

local function OnTabColors(tab, selected)
	if module.active and tabs[tab] and tabs[tab].over:IsShown() then
		ColorTab(tab, selected)
	end
end

local function OnAlertStart(frame)
	if module.active and frame then
		unread[frame] = (unread[frame] or 0) + 1
		RefreshUnread()
	end
end

local function OnAlertStop(frame)
	if module.active and frame and unread[frame] then
		unread[frame] = nil
		RefreshUnread()
	end
end

local function OnNewWindow()
	if module.active then
		RestyleAll()
		RefreshUnread()
	end
end

local function Hook()
	if hooked or not FCF_FadeInChatFrame then
		return
	end
	hooked = true
	hooksecurefunc("FCF_FadeInChatFrame", OnFadeIn)
	hooksecurefunc("FCF_FadeOutChatFrame", OnFadeOut)
	hooksecurefunc("FCFTab_UpdateColors", OnTabColors)
	hooksecurefunc("FCF_StartAlertFlash", OnAlertStart)
	hooksecurefunc("FCF_StopAlertFlash", OnAlertStop)
	hooksecurefunc("FCF_OpenTemporaryWindow", OnNewWindow)
	if not menuHooked and CanUseMenu() then
		menuHooked = true
		Menu.ModifyMenu(TAB_MENU, AddMenuEntries)
	end
end

local function OnFocusGained(_, box)
	typingBox = box
	UpdateLine()
	UpdateWake()
end

local function OnFocusLost(_, box)
	if box == typingBox then
		typingBox = nil
		UpdateLine()
		UpdateWake()
	end
end

-- Start and stop ----------------------------------------------------------------------------------------------------

local function Start()
	if not holder then
		CreateHolder()
	end
	Hook()
	for _, name in ipairs(FOLLOWERS) do
		local frame = _G[name]
		if frame and frame.GetAlpha then
			followerAlpha[name] = frame:GetAlpha()
		end
	end
	RestyleAll()
	HideSideButtons()
	PlaceHolder()
	holder:Show()
	wipe(hovered)
	EachChatFrame(function(frame)
		if frame.hasBeenFaded and IsDocked(frame) then
			hovered[frame] = true
		end
		local tab = _G[frame:GetName() .. "Tab"]
		if tab and ChatFrameUtil and ChatFrameUtil.IsTabAlerting and ChatFrameUtil.IsTabAlerting(tab) then
			unread[frame] = unread[frame] or 1
		end
	end)
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained", OnFocusGained, OWNER)
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", OnFocusLost, OWNER)
	wakeTarget = (next(hovered) or typingBox) and 1 or 0
	wake = wakeTarget
	ApplyWake()
	UpdateLine()
	RefreshUnread()
	asleepLayer:Show()
	TrackLines() -- lines from before the start may still be showing
end

local function Stop()
	EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxFocusGained", OWNER)
	EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxFocusLost", OWNER)
	if not holder then
		return
	end
	driver:SetScript("OnUpdate", nil)
	UnstyleAll()
	wake, wakeTarget = 0, 0
	for name, alpha in pairs(followerAlpha) do
		_G[name]:SetAlpha(alpha)
	end
	wipe(followerAlpha)
	ShowSideButtons()
	holder:Hide()
	chip:Hide()
	HideBacking()
	asleepLayer:Hide()
	wipe(hovered)
	wipe(unread)
	typingBox = nil
end

local function OnLinesChange()
	if not module.active then
		return
	end
	for frame in pairs(styled) do
		if frame.SetTimeVisible then
			frame:SetTimeVisible(module.db.lineSeconds)
		end
	end
	TrackLines()
end

local function OnBackingChange()
	if not module.active then
		return
	end
	if module.db.lineBacking then
		TrackLines()
	else
		HideBacking()
	end
end

local function OnOutlineChange()
	if not module.active then
		return
	end
	for frame, saved in pairs(styled) do
		SetOutline(frame, saved)
	end
end

local function OnChipChange()
	if module.active then
		RefreshUnread()
	end
end

local function PrintState()
	if not module.active then
		ns.Print("Quiet Chat is off.")
		return
	end
	local count = 0
	for _ in pairs(hovered) do
		count = count + 1
	end
	ns.Print(("Quiet Chat: %s (%d%%), mouse over %d window(s), %s."):format(wakeTarget == 1 and "awake" or "asleep",
		math.floor(wake * 100 + 0.5), count, typingBox and "typing" or "not typing"))
	local frame = SelectedFrame()
	local span = frame and ns.Chat_ShadowSpan(ReadLines(frame), frame:GetWidth())
	if span then
		ns.Print(("  Lines showing: slots %d to %d, %d px wide, strongest %d%%."):format(span.first, span.last,
			math.floor(span.width + 0.5), math.floor(span.alpha * 100 + 0.5)))
	else
		ns.Print("  No lines showing.")
	end
	EachChatFrame(function(frame)
		if unread[frame] then
			ns.Print(("  %s: %d unread"):format(TabName(frame) or ns.CHAT_UNREAD_FALLBACK, unread[frame]))
		end
	end)
end

module = ns.RegisterModule({
	key = "quietchat",
	name = "Quiet Chat",
	category = "chat",
	icon = 136047, -- spell_nature_invisibilty
	summary = "Chat fades away when nothing is happening and comes back when you need it.",
	description = "The chat window loses its background, border, tabs and buttons until you point at it or type. "
		.. "New lines still show over the world and fade on their own, and a small note says when a tab has unread whispers.",
	enabledByDefault = false,
	conflicts = {
		{ addon = "EllesmereUIChat", why = "it styles the chat window itself; Quiet Chat stays off while it's enabled" },
		{ addon = "MelloUI_Chat", why = "it styles the chat window itself; Quiet Chat stays off while it's on" },
		{ addon = "Prat-3.0", why = "it styles the chat window itself; Quiet Chat stays off while it's enabled" },
		{ addon = "Chattynator", why = "it replaces the chat window; Quiet Chat stays off while it's enabled" },
		{ addon = "Glass", why = "it does the same; Quiet Chat stays off while it's enabled" },
	},
	blocked = function()
		if ns.Ellesmere_Loaded("Chat") then
			return "EllesmereUI Chat styles the chat window itself, so Quiet Chat stays off."
		end
		if ns.Mello_On("Chat") then
			return "MelloUI's chat styles the chat window itself, so Quiet Chat stays off."
		end
		for _, addon in ipairs(OTHER_CHAT) do
			if C_AddOns.IsAddOnLoaded(addon) then
				return ("The %s addon styles the chat window itself, so Quiet Chat stays off."):format(addon)
			end
		end
	end,
	defaults = {
		lineSeconds = 30, -- how long a new line stays before it fades (Blizzard's own is 120)
		textOutline = false, -- outline on chat text (off: Blizzard's drop shadow; an outline muddies dark blue lines)
		chip = true, -- the unread whispers note while chat is asleep
		lineBacking = true, -- a faint soft shadow behind the lines still showing while chat is asleep
	},
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	options = {
		{ type = "slider", key = "lineSeconds", label = "New lines stay for", min = 10, max = 120, step = 5,
			format = function(v)
				return v .. " s"
			end,
			onChange = OnLinesChange,
			tooltip = "How long a new chat line shows before it fades. Pointing at the chat brings faded lines back." },
		{ type = "checkbox", key = "lineBacking", label = "Soft shadow behind new lines", onChange = OnBackingChange,
			tooltip = "While chat is faded, a faint shadow sits behind the lines still showing, so they read on bright ground. It shrinks as lines fade and is gone when they are." },
		{ type = "checkbox", key = "textOutline", label = "Outline chat text", onChange = OnOutlineChange,
			tooltip = "A dark outline around chat text instead of the usual shadow. Helps on snow and other bright ground, but makes dark colors like blue lines harder to read." },
		{ type = "checkbox", key = "chip", label = "Note for unread whispers", onChange = OnChipChange,
			tooltip = "While chat is faded, a small note at the bottom names the tabs with whispers you haven't read and how many." },
	},
	commands = {
		{ "state", "show whether chat is awake and which tabs have unread whispers", PrintState },
	},
})
