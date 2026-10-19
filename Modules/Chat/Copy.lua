local addonName, ns = ...

-- Chat Copy module: a copy icon on each chat window (shown while the window is faded in, like Blizzard's chat
-- buttons) that opens that window's lines as plain text in Tomte's copy dialog (Panel/Dialog.lua), ready for Ctrl+C.
-- The text rules (links, colors, "Clean lines") are pure, in Chat/Data.lua. The game keeps 128 lines per window.
-- The icon follows Blizzard's FCF_FadeInChatFrame / FCF_FadeOutChatFrame (hooksecurefunc, so Blizzard's chat code
-- stays untainted), with an animation of its own: UIFrameFadeIn would put our frame in Blizzard's shared fade list.
-- Each window gets its icon on its first fade-in, which also covers whisper windows opened later.

local ICON_SIZE = 18
local FADE_IN = 0.15 -- seconds, Blizzard's CHAT_FRAME_FADE_TIME
local FADE_OUT = 2 -- seconds, Blizzard's CHAT_FRAME_FADE_OUT_TIME
local DIALOG_WIDTH = 640
local DIALOG_HEIGHT = 440

local UI = ns.UI

local module
local icons = {} -- [chat frame] = icon button
local hooked = false

-- The window's stored lines, oldest first; false for a line the game hides from addons (chat lockdown).
local function ReadLines(frame)
	local lines = {}
	for i = 1, frame:GetNumMessages() do
		local text = frame:GetMessageInfo(i)
		if ns.Readable(text) and type(text) == "string" then
			lines[#lines + 1] = text
		else
			lines[#lines + 1] = false
		end
	end
	return lines
end

local function WindowName(frame)
	local tab = frame:GetName() and _G[frame:GetName() .. "Tab"]
	local name = tab and tab:GetText()
	if type(name) == "string" and name ~= "" then
		return name
	end
	return "Chat"
end

local function OpenCopy(frame)
	local lines = ReadLines(frame)
	if #lines == 0 then
		ns.Print("Chat Copy: " .. WindowName(frame) .. " has no lines to copy.")
		return
	end
	local db = module.db
	ns.Dialog_Show({
		title = "Copy chat: " .. WindowName(frame),
		hint = ("%d lines, oldest first. Ctrl+C copies them all and closes this window."):format(#lines),
		text = ns.Chat_CopyText(lines, db.clean),
		readOnly = true,
		atEnd = true,
		width = DIALOG_WIDTH,
		height = DIALOG_HEIGHT,
		check = {
			label = "Clean lines (no timestamps or channel tags)",
			checked = db.clean,
			onChange = function(checked)
				db.clean = checked
				return ns.Chat_CopyText(lines, checked)
			end,
		},
	})
end

-- The window the command and key binding copy: the one last clicked or typed in, else the main one.
local function CurrentWindow()
	local frame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
	if frame and frame.GetNumMessages then
		return frame
	end
	return nil
end

local function CopyCurrent()
	if not ns.Module_RequireOn(module) then
		return
	end
	local frame = CurrentWindow()
	if frame then
		OpenCopy(frame)
	end
end

-- Icon ------------------------------------------------------------------------------------------------------------

-- Two overlapping squares, the usual "copy" sign, drawn in theme colors so it needs no art.
local function Square(parent, x, y, level)
	local square = CreateFrame("Frame", nil, parent)
	square:SetSize(8, 8)
	square:SetPoint("TOPLEFT", x, y)
	square:SetFrameLevel(parent:GetFrameLevel() + level)
	local fill = square:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(UI.Color("surface"))
	UI.Border(square, "textMuted")
	return square
end

local function SetIconRole(icon, role)
	UI.SetBorderColor(icon, role, role == "accent" and 1 or 0.5)
	UI.SetBorderColor(icon.back, role)
	UI.SetBorderColor(icon.front, role)
end

local function CreateIcon(frame)
	local icon = CreateFrame("Button", nil, frame)
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("TOPRIGHT", -2, -2)
	icon:SetFrameLevel(frame:GetFrameLevel() + 10)
	UI.Surface(icon, 0.5)
	icon.back = Square(icon, 4, -4, 1)
	icon.front = Square(icon, 7, -7, 2)

	icon.fade = icon:CreateAnimationGroup()
	icon.fade:SetToFinalAlpha(true)
	icon.fadeAlpha = icon.fade:CreateAnimation("Alpha")

	icon:SetScript("OnClick", function()
		GameTooltip:Hide()
		OpenCopy(frame)
	end)
	icon:SetScript("OnEnter", function(self)
		SetIconRole(self, "accent")
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Copy chat")
		UI.TipLine("Opens this window's text to copy with Ctrl+C.", "textMuted", true)
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function(self)
		SetIconRole(self, "textMuted")
		GameTooltip:Hide()
	end)
	SetIconRole(icon, "textMuted")
	icon:SetAlpha(0)
	icon:EnableMouse(false)
	icons[frame] = icon
	return icon
end

local function FadeTo(icon, alpha, seconds)
	local from = icon:GetAlpha()
	icon.fade:Stop()
	icon:SetAlpha(from)
	icon.fadeAlpha:SetFromAlpha(from)
	icon.fadeAlpha:SetToAlpha(alpha)
	icon.fadeAlpha:SetDuration(seconds)
	icon.fade:Play()
	-- Faded out it would still catch clicks on the chat text under it.
	icon:EnableMouse(alpha > 0)
end

-- Hooks (they can't be undone, so they do nothing while the module is off).

local function OnFadeIn(frame)
	if not module.active or not frame or not frame.GetNumMessages then
		return
	end
	local icon = icons[frame] or CreateIcon(frame)
	icon:Show()
	FadeTo(icon, 1, FADE_IN)
end

local function OnFadeOut(frame)
	local icon = module.active and frame and icons[frame]
	if icon then
		FadeTo(icon, 0, FADE_OUT)
	end
end

local function Hook()
	if hooked or not FCF_FadeInChatFrame or not FCF_FadeOutChatFrame then
		return
	end
	hooked = true
	hooksecurefunc("FCF_FadeInChatFrame", OnFadeIn)
	hooksecurefunc("FCF_FadeOutChatFrame", OnFadeOut)
end

local function HideIcons()
	for _, icon in pairs(icons) do
		icon.fade:Stop()
		icon:SetAlpha(0)
		icon:EnableMouse(false)
		icon:Hide()
	end
end

-- Key bindings (Bindings.xml, Key Bindings > Tomte), through ns.Binding_Add.
ns.Binding_Add("CHAT_COPY", "chatcopy", function()
	CopyCurrent()
end)
BINDING_NAME_TOMTE_CHAT_COPY = "Copy chat"

module = ns.RegisterModule({
	key = "chatcopy",
	name = "Chat Copy",
	category = "social",
	icon = 237162, -- inv_inscription_scroll
	summary = "Copy a chat window's text as plain text, ready to paste.",
	description = "A copy icon on your chat windows: their text opens as plain text, ready for Ctrl+C.",
	enabledByDefault = false,
	defaults = {
		clean = false, -- copy without timestamps, channel tags and name brackets
	},
	toggle = function(active)
		if active then
			Hook()
		else
			HideIcons()
		end
	end,
	options = {
		{ type = "checkbox", key = "clean", label = "Clean lines",
			tooltip = "Copy without timestamps, channel tags ([2. Trade], [Guild]) and the brackets around names. The copy window has the same checkbox." },
	},
	commands = {},
	fallbackCommand = { "", "copy the text of the chat window you last used", CopyCurrent, pattern = "^$" },
})
