local addonName, ns = ...

-- Menus in the theme: right-click menus (UI.ContextMenu) and the list a UI.Dropdown opens (UI.OpenChoiceList).
-- UI.ContextMenu takes the same generator as Blizzard's MenuUtil.CreateContextMenu, with the parts Tomte uses:
-- CreateTitle, CreateButton (with children it opens a submenu), CreateRadio, CreateCheckbox, CreateDivider. A pick
-- closes the menu, a checkbox keeps it open; a click outside or Esc closes it. A button can also do something on a
-- right-click (desc:SetOnRightClick(fn)), such as opening a menu of its own.

local UI = ns.UI
local ROW_H = 22
local DIVIDER_H = 9
local MAX_H = 12 * ROW_H -- taller menus scroll
local TEXT_INSET = 12
local CHECK = 10 -- checkbox square
local ARROW_W = 14 -- room for a submenu's ">"
local SCROLL_W = 10

local levels = {} -- [depth] = menu frame; 1 is the menu, 2 a submenu
local catcher
local owner, ownerArrow -- what opened the menu; a dropdown's arrow flips while it's open

-- Descriptions ------------------------------------------------------------------------------------------------

local Desc = {}
Desc.__index = Desc

local function NewDesc(kind, text)
	return setmetatable({ kind = kind, text = text, children = {} }, Desc)
end

local function Add(parent, kind, text)
	local d = NewDesc(kind, text)
	parent.children[#parent.children + 1] = d
	return d
end

function Desc:CreateTitle(text)
	return Add(self, "title", text)
end

function Desc:CreateDivider()
	return Add(self, "divider")
end

function Desc:CreateButton(text, onClick, data)
	local d = Add(self, "button", text)
	d.onClick, d.data = onClick, data
	return d
end

-- fn(data) on a right-click of this row (the menu closes first).
function Desc:SetOnRightClick(fn)
	self.onRightClick = fn
end

function Desc:CreateRadio(text, isSelected, onSelect, data)
	local d = Add(self, "radio", text)
	d.isSelected, d.onSelect, d.data = isSelected, onSelect, data
	return d
end

function Desc:CreateCheckbox(text, isSelected, onSelect, data)
	local d = Add(self, "checkbox", text)
	d.isSelected, d.onSelect, d.data = isSelected, onSelect, data
	return d
end

-- Frames ------------------------------------------------------------------------------------------------------

local function CloseFrom(depth)
	for d = #levels, depth, -1 do
		if levels[d]:IsShown() then
			levels[d]:Hide()
		end
	end
end

local function CloseAll()
	CloseFrom(1)
end
UI.CloseMenu = CloseAll
UI.CloseChoiceList = CloseAll

local Render -- forward declaration

local function Paint(row)
	local d = row.desc
	local selected = (d.kind == "radio" or d.kind == "checkbox") and d.isSelected(d.data) and true or false
	row.bar:SetShown(d.kind == "radio" and selected)
	row.boxFill:SetShown(d.kind == "checkbox" and selected)
	if d.kind == "title" then
		UI.SetTextRole(row.label, "accent")
	else
		UI.SetTextRole(row.label, d.kind == "radio" and selected and "heading" or "text")
	end
end

local function Interactive(d)
	return d.kind ~= "title" and d.kind ~= "divider"
end

local function CreateRow(level)
	local row = CreateFrame("Button", nil, level.scroll.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("hover"))
	row.bg:SetAlpha(0) -- eased in while the mouse is on the row (UI.WashTo)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetColorTexture(UI.Color("accent"))
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	row.bar:SetWidth(2)
	row.box = CreateFrame("Frame", nil, row)
	row.box:SetSize(CHECK, CHECK)
	row.box:SetPoint("LEFT", TEXT_INSET, 0)
	UI.Surface(row.box, 0.8)
	row.boxFill = row.box:CreateTexture(nil, "ARTWORK")
	row.boxFill:SetPoint("TOPLEFT", 2, -2)
	row.boxFill:SetPoint("BOTTOMRIGHT", -2, 2)
	row.boxFill:SetColorTexture(UI.Color("accent"))
	row.label = UI.Text(row, 12, "text")
	row.label:SetWordWrap(false)
	row.arrow = UI.Text(row, 11, "accent")
	row.arrow:SetPoint("RIGHT", -8, 0)
	row.arrow:SetText(">")
	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetColorTexture(UI.Color("rule"))
	row.rule:SetHeight(1)
	row.rule:SetPoint("LEFT", 8, 0)
	row.rule:SetPoint("RIGHT", -8, 0)
	row:SetScript("OnEnter", function(self)
		local d = self.desc
		if Interactive(d) then
			UI.WashTo(self.bg, true)
		end
		local hover = levels[1].root.onHover
		if hover and d.kind == "radio" then
			hover(d.data, d.text, self)
		end
		if d.kind == "button" and #d.children > 0 then
			Render(level.depth + 1, d, self)
		else
			CloseFrom(level.depth + 1)
		end
	end)
	row:SetScript("OnLeave", function(self)
		UI.WashTo(self.bg, false)
		local hover = levels[1].root.onHover
		if hover then
			hover(nil)
		end
	end)
	row:SetScript("OnClick", function(self, button)
		local d = self.desc
		if button == "RightButton" then
			if d.onRightClick then
				UI.Sound("pick")
				CloseAll()
				d.onRightClick(d.data)
			end
			return
		end
		if d.kind == "checkbox" then
			UI.Sound("pick")
			d.onSelect(d.data)
			for _, other in ipairs(level.rows) do
				if other:IsShown() then
					Paint(other)
				end
			end
		elseif d.kind == "radio" or (d.kind == "button" and #d.children == 0) then
			UI.Sound("pick")
			CloseAll() -- before the action, which may open something of its own
			local fn = d.kind == "radio" and d.onSelect or d.onClick
			if fn then
				fn(d.data)
			end
		end
	end)
	return row
end

local function BuildCatcher()
	-- Behind the menus and as big as the screen: a click anywhere else closes them.
	catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:EnableMouse(true)
	catcher:SetScript("OnMouseDown", CloseAll)
	catcher:Hide()
end

local function Level(depth)
	local level = levels[depth]
	if level then
		return level
	end
	if not catcher then
		BuildCatcher()
	end
	level = CreateFrame("Frame", nil, UIParent)
	level.depth = depth
	level.rows = {}
	level:SetFrameStrata("FULLSCREEN_DIALOG")
	level:SetFrameLevel(catcher:GetFrameLevel() + 10 * depth)
	level:SetClampedToScreen(true)
	level:EnableMouse(true)
	level:Hide()
	level.bg = level:CreateTexture(nil, "BACKGROUND")
	level.bg:SetAllPoints()
	local r, g, b = UI.Color("bg")
	level.bg:SetColorTexture(r, g, b, 1) -- opaque, whatever the theme's alpha: it sits over other frames
	UI.Border(level, "frame", 0.8)
	level.scroll = UI.Scroll(level)
	if depth == 1 then
		-- Esc closes only the menu, not the window behind it. Keyboard input can't be claimed in combat, so the menu
		-- then doesn't take keys (a click outside still closes it).
		level:SetScript("OnKeyDown", function(self, key)
			if InCombatLockdown() then
				return
			end
			self:SetPropagateKeyboardInput(key ~= "ESCAPE")
			if key == "ESCAPE" then
				CloseAll()
			end
		end)
		level:SetScript("OnHide", function(self)
			if self.root.onHover then
				self.root.onHover(nil)
			end
			CloseFrom(2)
			catcher:Hide()
			if ownerArrow then
				ownerArrow:SetText("v")
			end
			owner, ownerArrow = nil, nil
		end)
	end
	levels[depth] = level
	return level
end

-- Lays desc's children out in the menu at depth. anchor: a row (submenu), or { owner = frame } to open under it, or
-- nil to open at the cursor. minWidth: at least this wide (a dropdown's button).
function Render(depth, desc, anchor, minWidth)
	local level = Level(depth)
	CloseFrom(depth + 1)
	local y, widest = 0, minWidth or 0
	for i, d in ipairs(desc.children) do
		local row = level.rows[i] or CreateRow(level)
		level.rows[i] = row
		row.desc = d
		local height = d.kind == "divider" and DIVIDER_H or ROW_H
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", level.scroll.content, "RIGHT")
		row.rule:SetShown(d.kind == "divider")
		row.box:SetShown(d.kind == "checkbox")
		row.arrow:SetShown(d.kind == "button" and #d.children > 0)
		local left = TEXT_INSET + (d.kind == "checkbox" and CHECK + 8 or 0)
		row.label:ClearAllPoints()
		row.label:SetPoint("LEFT", left, 0)
		row.label:SetPoint("RIGHT", row.arrow:IsShown() and -(8 + ARROW_W) or -8, 0)
		if d.kind == "title" then
			UI.SetFont(row.label, "label", 11)
		else
			UI.SetFont(row.label, "body", 12)
		end
		row.label:SetText(d.text or "")
		widest = math.max(widest, math.ceil(row.label:GetUnboundedStringWidth()) + left + 16
			+ (row.arrow:IsShown() and ARROW_W or 0))
		UI.WashTo(row.bg, false, true)
		Paint(row)
		row:Show()
		y = y + height
	end
	for i = #desc.children + 1, #level.rows do
		level.rows[i]:Hide()
	end

	local scrolls = y > MAX_H
	local width = widest + (scrolls and SCROLL_W or 0)
	local height = math.min(y, MAX_H) + 2
	level:SetSize(width, height)
	level.scroll:ClearAllPoints()
	level.scroll:SetPoint("TOPLEFT", 1, -1)
	level.scroll:SetPoint("BOTTOMRIGHT", scrolls and -(1 + SCROLL_W) or -1, 1)
	level.scroll.content:SetWidth(width - 2 - (scrolls and SCROLL_W or 0))
	level.scroll:SetContentHeight(y)
	level.scroll:SetScroll(0)

	level:ClearAllPoints()
	if depth > 1 then
		level:SetScale(levels[depth - 1]:GetScale())
		level:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 1)
	elseif anchor then
		local o = anchor.owner
		level:SetScale(o:GetEffectiveScale() / UIParent:GetEffectiveScale())
		-- Below the button, unless that runs off the bottom of the screen (both in screen pixels).
		local room = (o:GetBottom() or 0) * o:GetEffectiveScale() - (height + 2) * level:GetEffectiveScale()
		if room >= 0 then
			level:SetPoint("TOPLEFT", o, "BOTTOMLEFT", 0, -2)
		else
			level:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 0, 2)
		end
	else
		level:SetScale(1)
		local x, cy = GetCursorPosition()
		local scale = level:GetEffectiveScale()
		level:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 2, cy / scale - 2)
	end
	-- Opening (not a submenu redrawn for another row): a quick fade and grow in.
	if not level:IsShown() then
		level:Show()
		UI.Appear(level)
	end
end

local function Open(by, root, anchor, minWidth, arrow)
	CloseAll()
	if #root.children == 0 then
		return
	end
	Level(1).root = root -- before Render: its rows ask for root.onHover
	Render(1, root, anchor, minWidth)
	owner, ownerArrow = by, arrow
	if arrow then
		arrow:SetText("^")
	end
	catcher:Show()
	local level = levels[1]
	if not InCombatLockdown() then
		level:EnableKeyboard(true)
		level:SetPropagateKeyboardInput(true)
	else
		level:EnableKeyboard(false)
	end
end

-- API ---------------------------------------------------------------------------------------------------------

-- Right-click menu at the cursor. generator(owner, root) fills root like Blizzard's MenuUtil.CreateContextMenu.
function UI.ContextMenu(by, generator)
	local root = NewDesc("root")
	generator(by, root)
	Open(by, root, nil)
end

-- A dropdown's list under its button. choices: { { text, value } }; isSelected(value) marks the current one;
-- onPick(value) runs after the list closes. onHover(value, text, item), optional: the mouse is on a choice's item in
-- the list; onHover(nil) when it leaves or the list closes.
function UI.OpenChoiceList(by, choices, isSelected, onPick, onHover)
	local root = NewDesc("root")
	root.onHover = onHover
	for _, choice in ipairs(choices) do
		root:CreateRadio(choice.text, isSelected, onPick, choice.value)
	end
	Open(by, root, { owner = by }, by:GetWidth(), by.arrow)
end

-- The frame whose menu or list is open, or nil.
function UI.ChoiceListOwner()
	return levels[1] and levels[1]:IsShown() and owner or nil
end
