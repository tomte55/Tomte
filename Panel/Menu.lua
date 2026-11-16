local addonName, ns = ...

-- Menus in the theme: right-click menus (UI.ContextMenu) and the list a UI.Dropdown opens (UI.OpenChoiceList).
-- UI.ContextMenu takes the same generator as Blizzard's MenuUtil.CreateContextMenu, with the parts Tomte uses:
-- CreateTitle, CreateButton (with children it opens a submenu), CreateRadio, CreateCheckbox, CreateDivider. A pick
-- closes the menu, a checkbox keeps it open; a click outside or Esc closes it. A button can also do something on a
-- right-click (desc:SetOnRightClick(fn)), such as opening a menu of its own. desc:SetIcon(texture) shows an icon at a
-- row's right end. On the Forever theme the menus are drawn as the game's own (Blizzard_Menu: Forever loads the
-- Mainline variants, as the minimap's tracking menu shows them).

local UI = ns.UI
local ROW_H = 22
local DIVIDER_H = 9
local MAX_H = 12 * ROW_H -- taller menus scroll
local TEXT_INSET = 12
local CHECK = 10 -- checkbox square
local ARROW_W = 14 -- room for a submenu's ">"
local SCROLL_W = 10
local ICON = 16 -- a row's icon at its right end (desc:SetIcon)

-- The Forever theme: the game's menu (MenuStyle1Mixin, Blizzard_Menu/Mainline/MenuTemplates.lua) and its checkboxes
-- and radios (Mainline/MenuVariants.lua: an empty square or ring, the yellow tick drawn over it), the divider and the
-- hover (MenuVariants.lua). Forever has no "-classic" art (seen in game: the menu came out bare).
local GAME_BG = "common-dropdown-bg"
local GAME_BG_X, GAME_BG_Y = 10, 3 -- the art reaches this far past the menu's edges
local GAME_BG_ALPHA = 0.925
local GAME_INSET_X, GAME_INSET_TOP, GAME_INSET_BOTTOM = 8, 8, 15 -- MenuStyle1Mixin:GetInset
local GAME_ROW_H = 20
local GAME_BOX, GAME_CHECKED = "common-dropdown-ticksquare", "common-dropdown-icon-checkmark-yellow"
local GAME_RING, GAME_RADIO_ON = "common-dropdown-tickradial", "common-dropdown-icon-radialtick-yellow"
local GAME_TEXT_GAP = 7 -- pixels from the square to its text
local GAME_DIVIDER = "Interface\\Common\\UI-TooltipDivider-Transparent"
local GAME_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local GAME_ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local levels = {} -- [depth] = menu frame; 1 is the menu, 2 a submenu
local catcher
local owner, ownerArrow -- what opened the menu; a dropdown's arrow flips while it's open
-- What the menus sit on: UIParent, or while UIParent is hidden (Blizzard's house editor hides it) the top frame of what
-- opened them, so they draw over it.
local host = UIParent

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

-- An icon at the row's right end (a texture path or file ID).
function Desc:SetIcon(texture)
	self.icon = texture
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

-- The game's own menu look (the Forever theme).
local function GameLook()
	return ns.Theme.panel == "forever"
end

local function Paint(row)
	local d = row.desc
	local selected = (d.kind == "radio" or d.kind == "checkbox") and d.isSelected(d.data) and true or false
	if GameLook() then
		row.bar:Hide()
		row.boxFill:Hide()
		local box = d.kind == "checkbox" and GAME_BOX or d.kind == "radio" and GAME_RING
		row.tick:SetShown(box and true or false)
		row.tickMark:SetShown(box and selected or false)
		if box then
			row.tick:SetAtlas(box, true)
			row.tickMark:SetAtlas(d.kind == "checkbox" and GAME_CHECKED or GAME_RADIO_ON, true)
			row.tickMark:ClearAllPoints()
			if d.kind == "checkbox" then
				row.tickMark:SetPoint("CENTER", row.tick, "CENTER", 2, 1)
			else
				row.tickMark:SetPoint("TOPLEFT", row.tick, "TOPLEFT")
			end
		end
		UI.SetTextRole(row.label, d.kind == "title" and "heading" or "text")
		return
	end
	row.tick:Hide()
	row.tickMark:Hide()
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
	row.tick = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.tick:SetPoint("LEFT")
	row.tickMark = row:CreateTexture(nil, "ARTWORK", nil, 2)
	row.gameLight = row:CreateTexture(nil, "BACKGROUND")
	row.gameLight:SetAllPoints()
	row.gameLight:SetTexture(GAME_HIGHLIGHT)
	row.gameLight:SetBlendMode("ADD")
	row.gameLight:Hide()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
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
			if GameLook() then
				self.gameLight:Show()
			else
				UI.WashTo(self.bg, true)
			end
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
		self.gameLight:Hide()
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
	level = CreateFrame("Frame", nil, host)
	level.depth = depth
	ns.ownFrames[level] = host == WorldFrame or nil
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
	-- The game's look, at MenuStyle2Mixin's offsets (shown instead on the Forever theme, in Render).
	level.gameBg = level:CreateTexture(nil, "BACKGROUND", nil, 1)
	level.gameBg:SetAtlas(GAME_BG)
	level.gameBg:SetPoint("TOPLEFT", -GAME_BG_X, GAME_BG_Y)
	level.gameBg:SetPoint("BOTTOMRIGHT", GAME_BG_X, -GAME_BG_Y)
	level.gameBg:SetAlpha(GAME_BG_ALPHA)
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

-- Lays desc's children out in the menu at depth. anchor: a row (submenu), { owner = frame } to open under it,
-- { owner = frame, side = "LEFT" } to open beside it on its left (its tops level), or nil to open at the cursor.
-- minWidth: at least this wide (a dropdown's button).
function Render(depth, desc, anchor, minWidth)
	local level = Level(depth)
	CloseFrom(depth + 1)
	local game = GameLook()
	level.bg:SetShown(not game)
	for _, t in ipairs(level.borderEdges) do
		t:SetShown(not game)
	end
	level.gameBg:SetShown(game)
	-- The rows inside the menu's edge.
	local insetX, insetTop, insetBottom = 1, 1, 1
	if game then
		insetX, insetTop, insetBottom = GAME_INSET_X, GAME_INSET_TOP, GAME_INSET_BOTTOM
	end
	local textInset = game and 0 or TEXT_INSET
	local y, widest = 0, minWidth or 0
	for i, d in ipairs(desc.children) do
		local row = level.rows[i] or CreateRow(level)
		level.rows[i] = row
		row.desc = d
		local height = d.kind == "divider" and DIVIDER_H or game and GAME_ROW_H or ROW_H
		row:SetHeight(height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", level.scroll.content, "RIGHT")
		row.rule:SetShown(d.kind == "divider")
		if game then
			row.rule:SetTexture(GAME_DIVIDER)
			row.rule:SetHeight(13)
			row.arrow:SetText("")
		else
			row.rule:SetColorTexture(UI.Color("rule"))
			row.rule:SetHeight(1)
			row.arrow:SetText(">")
		end
		if game and not row.gameArrow then
			row.gameArrow = row:CreateTexture(nil, "ARTWORK")
			row.gameArrow:SetSize(16, 16)
			row.gameArrow:SetPoint("RIGHT")
			row.gameArrow:SetTexture(GAME_ARROW)
		end
		local sub = d.kind == "button" and #d.children > 0
		if row.gameArrow then
			row.gameArrow:SetShown(game and sub)
		end
		row.box:SetShown(not game and d.kind == "checkbox")
		row.arrow:SetShown(sub)
		local ticked = d.kind == "checkbox" or (game and d.kind == "radio")
		Paint(row) -- first: it sets the game's square, whose width places the label
		local tickW = game and math.ceil(row.tick:GetWidth()) + GAME_TEXT_GAP or CHECK + 8
		local left = textInset + (ticked and tickW or 0)
		row.icon:SetShown(d.icon ~= nil)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("RIGHT", sub and -ARROW_W or (game and 0 or -8), 0)
		if d.icon then
			row.icon:SetTexture(d.icon)
		end
		local right = (sub and ARROW_W or 0) + (d.icon and ICON + 6 or 0) + (game and 0 or 8)
		row.label:ClearAllPoints()
		row.label:SetPoint("LEFT", left, 0)
		row.label:SetPoint("RIGHT", -right, 0)
		if d.kind == "title" then
			UI.SetFont(row.label, "label", 11)
		else
			UI.SetFont(row.label, "body", 12)
		end
		row.label:SetText(d.text or "")
		widest = math.max(widest, math.ceil(row.label:GetUnboundedStringWidth()) + left + right + 8)
		row.gameLight:Hide()
		UI.WashTo(row.bg, false, true)
		row:Show()
		y = y + height
	end
	for i = #desc.children + 1, #level.rows do
		level.rows[i]:Hide()
	end

	local maxH = game and 16 * GAME_ROW_H or MAX_H -- the game's menus are taller before they scroll
	local scrolls = y > maxH
	local width = widest + (scrolls and SCROLL_W or 0) + 2 * insetX
	local height = math.min(y, maxH) + insetTop + insetBottom
	level:SetSize(width, height)
	level.scroll:ClearAllPoints()
	level.scroll:SetPoint("TOPLEFT", insetX, -insetTop)
	level.scroll:SetPoint("BOTTOMRIGHT", -(insetX + (scrolls and SCROLL_W or 0)), insetBottom)
	level.scroll.content:SetWidth(width - 2 * insetX - (scrolls and SCROLL_W or 0))
	level.scroll:SetContentHeight(y)
	level.scroll:SetScroll(0)

	level:ClearAllPoints()
	if depth > 1 then
		level:SetScale(levels[depth - 1]:GetScale())
		level:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2 + insetX, insetTop)
	elseif anchor and anchor.side == "LEFT" then
		local o = anchor.owner
		level:SetScale(o:GetEffectiveScale() / host:GetEffectiveScale())
		level:SetPoint("TOPRIGHT", o, "TOPLEFT", -2, 0)
	elseif anchor then
		local o = anchor.owner
		level:SetScale(o:GetEffectiveScale() / host:GetEffectiveScale())
		-- Below the button, unless that runs off the bottom of the screen (both in screen pixels).
		local room = (o:GetBottom() or 0) * o:GetEffectiveScale() - (height + 2) * level:GetEffectiveScale()
		if room >= 0 then
			level:SetPoint("TOPLEFT", o, "BOTTOMLEFT", 0, -2)
		else
			level:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 0, 2)
		end
	else
		level:SetScale(UIParent:GetEffectiveScale() / host:GetEffectiveScale()) -- UIParent's size on either host
		local x, cy = GetCursorPosition()
		local scale = level:GetEffectiveScale()
		level:SetPoint("TOPLEFT", host, "BOTTOMLEFT", x / scale + 2, cy / scale - 2)
	end
	-- Opening (not a submenu redrawn for another row): a quick fade and grow in.
	if not level:IsShown() then
		level:Show()
		UI.Appear(level)
	end
end

-- The frame under UIParent or WorldFrame (or with no parent) that frame sits in: Blizzard's HouseEditorFrame for the
-- Decorating panel. Frames drawn on WorldFrame stay under it whatever their strata (measured in game).
local function TopOf(frame)
	local parent = frame and frame:GetParent()
	while parent and parent ~= UIParent and parent ~= WorldFrame do
		frame, parent = parent, parent:GetParent()
	end
	return frame
end

-- UIParent, or while UIParent is hidden (the house editor, a dialogue addon) the top frame of what opened the menu
-- (WorldFrame when nothing did).
local function SetHost(by)
	local want = UIParent
	if not (UIParent:IsShown() and UIParent:GetAlpha() >= 0.99) then
		local top = TopOf(by)
		want = top and top ~= UIParent and top:IsShown() and top or WorldFrame
	end
	if want == host then
		return
	end
	host = want
	catcher:SetParent(host)
	catcher:ClearAllPoints()
	catcher:SetAllPoints(host)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	for depth, level in ipairs(levels) do
		level:SetParent(host)
		level:SetFrameStrata("FULLSCREEN_DIALOG")
		level:SetFrameLevel(catcher:GetFrameLevel() + 10 * depth)
		ns.ownFrames[level] = host == WorldFrame or nil
	end
	ns.ownFrames[catcher] = host == WorldFrame or nil
end

local function Open(by, root, anchor, minWidth, arrow)
	CloseAll()
	if #root.children == 0 then
		return
	end
	Level(1)
	SetHost(by)
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
-- side: "LEFT" opens it beside by on its left instead (a button's menu that should cover what's left of it).
function UI.ContextMenu(by, generator, side)
	local root = NewDesc("root")
	generator(by, root)
	Open(by, root, side and { owner = by, side = side } or nil)
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
