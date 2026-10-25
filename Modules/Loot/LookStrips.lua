local addonName, ns = ...

-- Loot: the Strips look of the loot window (the default). No box: each slot is a strip like the feed's lines (Parts.lua)
-- that stays until you take it, so looting by hand looks like auto loot's feed. The source on top, Take all with its
-- key below. Registered in ns.LootLooks; the window around it is Window.lua.

local BASE_FONT = 12 -- the font size the sizes below are drawn for; other sizes scale them
local WIDTH = 320
local STRIP_EXTRA = 16 -- a strip's height over the font size (the feed's lines are 10: these are clicked)
local ICON_EXTRA = 10 -- the icon's size over the font size
local GAP = 3 -- between strips
local SECTION_GAP = 6 -- under the title, above the footer
local CLOSE_W = 18
local HOVER_GLOW = 0.35 -- the accent under the mouse, at the strip's left edge
local LOCKED_ALPHA = 0.6 -- a strip that can't be looted (someone else's, a roll)
local HEAD_ALPHA = 0.6 -- the title's and footer's strips, times the Background opacity

local UI = ns.UI

local function Scale(n, size)
	return math.floor(n * size / BASE_FONT + 0.5)
end

-- A dark strip fading out to the right behind the title and the footer, so they read over the world.
local function Backing(parent)
	local t = parent:CreateTexture(nil, "BACKGROUND")
	t:SetColorTexture(1, 1, 1, 1)
	return t
end

local function ColorBacking(t, bgAlpha)
	t:SetGradient("HORIZONTAL", UI.ColorObject("bg", bgAlpha * HEAD_ALPHA), UI.ColorObject("bg", 0))
end

local function NewStrip(view)
	local s = CreateFrame("Button", nil, view.root)
	s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	ns.LootParts_Strip(s)
	s.tipAnchor = s.detail -- right after the name and its extras, not at the strip's faded end
	s.hl = s:CreateTexture(nil, "HIGHLIGHT")
	s.hl:SetAllPoints()
	s.hl:SetColorTexture(1, 1, 1, 1) -- colored by the gradient (Draw)
	s:SetScript("OnClick", ns.LootParts_Click)
	s:SetScript("OnEnter", ns.LootParts_Tooltip)
	s:SetScript("OnLeave", GameTooltip_Hide)
	return s
end

local function Build(host)
	local view = { strips = {} }
	local root = CreateFrame("Frame", nil, host)
	view.root = root
	view.headBack = Backing(root)
	view.title = UI.Text(root, BASE_FONT + 4, "heading", "title")
	view.title:SetWordWrap(false)
	view.close = ns.LootParts_FlatButton(root, "x", BASE_FONT)
	view.close:SetSize(CLOSE_W, CLOSE_W)
	view.close:SetScript("OnClick", function()
		view.ctx.actions.Close()
	end)
	view.empty = UI.Text(root, BASE_FONT, "textMuted")
	view.empty:SetText("Nothing left")

	view.footBack = Backing(root)
	view.take = CreateFrame("Button", nil, root)
	view.take.cap = ns.LootParts_Keycap(view.take)
	view.take.cap:SetPoint("LEFT")
	view.take.label = UI.Text(view.take, BASE_FONT, "text", "label")
	view.take.label:SetText("Take all")
	view.take:SetScript("OnClick", function()
		view.ctx.actions.TakeAll()
	end)
	view.take:SetScript("OnEnter", function(self)
		UI.SetTextRole(self.label, "accent")
		ns.LootParts_TakeAllTooltip(self)
	end)
	view.take:SetScript("OnLeave", function(self)
		UI.SetTextRole(self.label, "text")
		GameTooltip_Hide()
	end)
	view.pager = ns.LootParts_Pager(root)
	return view
end

local function DrawFooter(view, ctx, y, width, size)
	local take = view.take
	take:SetShown(ctx.canTake)
	local pagerW = view.pager:Set(ctx, size)
	if not ctx.canTake and pagerW == 0 then
		view.footBack:Hide()
		return y
	end
	y = y + SECTION_GAP
	local h = size + 10
	local x = 4
	if ctx.canTake then
		UI.SetFont(take.label, "label", size)
		UI.SetTextRole(take.label, "text")
		local capW = take.cap:SetKey(ctx.keyText, size)
		take.label:ClearAllPoints()
		take.label:SetPoint("LEFT", capW > 0 and capW + 6 or 0, 0)
		take:SetSize((capW > 0 and capW + 6 or 0) + math.ceil(take.label:GetUnboundedStringWidth()), h)
		take:ClearAllPoints()
		take:SetPoint("TOPLEFT", x, -y)
	end
	view.pager:ClearAllPoints()
	view.pager:SetPoint("TOPRIGHT", -4, -y - (h - view.pager:GetHeight()) / 2)
	view.footBack:ClearAllPoints()
	view.footBack:SetPoint("TOPLEFT", 0, -y)
	view.footBack:SetSize(width, h)
	ColorBacking(view.footBack, ctx.bgAlpha)
	view.footBack:Show()
	return y + h
end

local function Draw(view, ctx)
	view.ctx = ctx
	local size = ctx.size
	local width = Scale(WIDTH, size)
	local stripH = size + STRIP_EXTRA

	-- Title
	UI.SetFont(view.title, "title", size + 4)
	view.title:SetText(ctx.title)
	-- The x sits right after the title, on its strip, rather than out where the strip has faded away.
	view.title:ClearAllPoints()
	view.title:SetPoint("TOPLEFT", 6, -3)
	view.title:SetWidth(math.min(math.ceil(view.title:GetUnboundedStringWidth()) + 1, width - CLOSE_W - 40))
	local headH = math.max(math.ceil(view.title:GetStringHeight()) + 6, CLOSE_W)
	view.close:ClearAllPoints()
	view.close:SetPoint("LEFT", view.title, "RIGHT", 10, 0)
	view.headBack:ClearAllPoints()
	view.headBack:SetPoint("TOPLEFT")
	view.headBack:SetSize(width, headH)
	ColorBacking(view.headBack, ctx.bgAlpha)
	local y = headH + SECTION_GAP

	-- Strips
	local lines = ns.Loot_Lines(ctx.entries, { foldJunk = ctx.foldJunk, hideTaken = true })
	local shown
	shown, ctx.page, ctx.pages = ns.Loot_Page(lines, ctx.perPage, ctx.page)
	local strips = view.strips
	for i, line in ipairs(shown) do
		local s = strips[i] or NewStrip(view)
		strips[i] = s
		local t = ns.LootParts_LineText(line)
		s.line, s.ctx = line, ctx
		ns.LootParts_FillStrip(s, { icon = t.icon, text = t.name, detail = t.detail, quality = t.quality,
			role = t.role }, size, ctx.bgAlpha, width, size + ICON_EXTRA)
		s.hl:SetGradient("HORIZONTAL", UI.ColorObject("accent", HOVER_GLOW), UI.ColorObject("accent", 0))
		local locked = t.entry and t.entry.locked
		s.icon:SetDesaturated(locked == true)
		s:SetAlpha(locked and LOCKED_ALPHA or 1)
		s:SetSize(width, stripH)
		s:ClearAllPoints()
		s:SetPoint("TOPLEFT", 0, -y)
		s:Show()
		y = y + stripH + GAP
	end
	for i = #shown + 1, #strips do
		strips[i]:Hide()
		strips[i].line = nil
	end
	if #shown == 0 then
		UI.SetFont(view.empty, "body", size)
		view.empty:ClearAllPoints()
		view.empty:SetPoint("TOPLEFT", 8, -y)
		view.empty:Show()
		y = y + math.ceil(view.empty:GetStringHeight()) + GAP
	else
		view.empty:Hide()
	end
	y = y - GAP

	y = DrawFooter(view, ctx, y, width, size)
	return width, y
end

ns.LootLooks.strips = { name = "Strips", Build = Build, Draw = Draw }
