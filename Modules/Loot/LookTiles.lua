local addonName, ns = ...

-- Loot: the Tiles look of the loot window. Like a bag: large icons in a grid with quality borders and stack counts,
-- an upgrade marked on its tile, and a caption under the grid that names the item under the mouse (the first one
-- otherwise). The count and worth of what's left and Take all at the bottom. Registered in ns.LootLooks; the window
-- around it is Window.lua.

local BASE_FONT = 12 -- the font size the sizes below are drawn for; other sizes scale them
local COLUMNS = 5
local TILE = 44
local TILE_GAP = 8
local EDGE = 2 -- the quality border around a tile's icon
local PAD = 10
local MARK_W, MARK_H = 18, 20 -- the upgrade arrow, in proportion to Baganator's (22 x 24 on a 37 slot)
local MARK_SHADOW = 0.9 -- the dark copy behind the arrow
local MAYBE_ROLE = "warning" -- a maybe-upgrade's arrow, as Gear Check colors it in Baganator
local HOVER = 0.3 -- the accent over a tile under the mouse
local CAPTION_BAR = 2 -- the quality bar on the caption's left edge
local LOCKED_ALPHA = 0.6
local CLOSE_W = 18

local UI = ns.UI

local function Scale(n, size)
	return math.floor(n * size / BASE_FONT + 0.5)
end

local function SetCaption(view, line)
	local c = view.caption
	if not line then
		c.name:SetText("")
		c.sub:SetText("")
		return
	end
	local t = ns.LootParts_LineText(line, "tag", true)
	c.name:SetText(t.name)
	c.sub:SetText(t.detail)
	local q = t.quality and ITEM_QUALITY_COLORS[t.quality]
	if q and not t.money then
		c.bar:SetColorTexture(q.r, q.g, q.b, 1)
	else
		c.bar:SetColorTexture(UI.Color("frame"))
	end
end

local function TileEnter(self)
	ns.LootParts_Tooltip(self)
	SetCaption(self.view, self.line)
end

local function TileLeave(self)
	GameTooltip_Hide()
	SetCaption(self.view, self.view.firstLine)
end

local function NewTile(view)
	local tile = CreateFrame("Button", nil, view.root)
	tile.view = view
	tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	tile.border = tile:CreateTexture(nil, "ARTWORK", nil, -1)
	tile.border:SetAllPoints()
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	tile.icon:SetPoint("TOPLEFT", EDGE, -EDGE)
	tile.icon:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	tile.count = UI.Text(tile, BASE_FONT, "text", "number")
	tile.count:SetPoint("BOTTOMRIGHT", -3, 3)
	-- The upgrade arrow, as Gear Check draws it in Baganator's bags (Modules/Gear/Baganator.lua): the bag arrow in the
	-- top-left corner over a dark copy, so it reads on bright icons.
	tile.markShadow = tile:CreateTexture(nil, "OVERLAY", nil, 1)
	tile.markShadow:SetAtlas("bags-greenarrow")
	tile.markShadow:SetVertexColor(0, 0, 0, MARK_SHADOW)
	tile.mark = tile:CreateTexture(nil, "OVERLAY", nil, 2)
	tile.mark:SetAtlas("bags-greenarrow")
	tile.mark:SetPoint("TOPLEFT", EDGE, -EDGE)
	tile.markShadow:SetPoint("TOPLEFT", tile.mark, 1.5, -1.5)
	tile.markShadow:SetPoint("BOTTOMRIGHT", tile.mark, 1.5, -1.5)
	tile.hl = tile:CreateTexture(nil, "HIGHLIGHT")
	tile.hl:SetPoint("TOPLEFT", EDGE, -EDGE)
	tile.hl:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	tile:SetScript("OnClick", ns.LootParts_Click)
	tile:SetScript("OnEnter", TileEnter)
	tile:SetScript("OnLeave", TileLeave)
	return tile
end

local function SetTile(tile, line, ctx, size)
	local t = ns.LootParts_LineText(line, "tag", true)
	tile.line, tile.ctx = line, ctx
	tile.icon:SetTexture(t.icon)
	ns.LootParts_IconFrame(tile.border, t.quality, t.money)
	local e = t.entry
	local quantity = line.junk and line.quantity or (e and e.kind ~= "money" and e.quantity) or 0
	UI.SetFont(tile.count, "number", size)
	tile.count:SetText(quantity > 1 and ns.Thousands(quantity) or "")
	-- An upgrade gets the arrow in its own green, a maybe-upgrade the same arrow in the warning color (as in Baganator).
	local v = ctx.extras.verdict and e and e.verdict
	local upgrade, maybe = v and v.upgrade == true, v and not v.upgrade and v.maybe == true
	local markW = Scale(MARK_W, size)
	tile.mark:SetSize(markW, markW * MARK_H / MARK_W)
	tile.mark:SetDesaturated(maybe == true)
	if maybe then
		tile.mark:SetVertexColor(UI.Color(MAYBE_ROLE))
	else
		tile.mark:SetVertexColor(1, 1, 1, 1)
	end
	tile.mark:SetShown(upgrade or maybe)
	tile.markShadow:SetShown(upgrade or maybe)
	tile.hl:SetColorTexture(UI.Color("accent"))
	tile.hl:SetAlpha(HOVER)
	local locked = e and e.locked
	tile.icon:SetDesaturated(locked == true)
	tile:SetAlpha(locked and LOCKED_ALPHA or 1)
	tile:Show()
end

local function Build(host)
	local view = { tiles = {} }
	local root = CreateFrame("Frame", nil, host)
	view.root = root
	view.panel = UI.Panel(root)
	view.title = UI.Text(root, BASE_FONT + 2, "heading", "title")
	view.title:SetWordWrap(false)
	view.close = ns.LootParts_FlatButton(root, "x", BASE_FONT)
	view.close:SetSize(CLOSE_W, CLOSE_W)
	view.close:SetScript("OnClick", function()
		view.ctx.actions.Close()
	end)
	view.empty = UI.Text(root, BASE_FONT, "textMuted")
	view.empty:SetText("Nothing left")

	local c = CreateFrame("Frame", nil, root)
	c.fill = c:CreateTexture(nil, "BACKGROUND")
	c.fill:SetAllPoints()
	c.bar = c:CreateTexture(nil, "ARTWORK")
	c.bar:SetPoint("TOPLEFT")
	c.bar:SetPoint("BOTTOMLEFT")
	c.bar:SetWidth(CAPTION_BAR)
	c.name = UI.Text(c, BASE_FONT, "text")
	c.name:SetWordWrap(false)
	c.name:SetPoint("TOPLEFT", CAPTION_BAR + 8, -6)
	c.name:SetPoint("RIGHT", -6, 0)
	c.sub = UI.Text(c, BASE_FONT - 1, "textMuted")
	c.sub:SetWordWrap(false)
	c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -2)
	c.sub:SetPoint("RIGHT", -6, 0)
	view.caption = c

	view.summary = UI.Text(root, BASE_FONT - 1, "textMuted")
	view.take = ns.LootParts_FlatButton(root, "Take all", BASE_FONT, "accent")
	view.take.label:ClearAllPoints()
	view.take.label:SetPoint("LEFT")
	view.take.cap = ns.LootParts_Keycap(view.take)
	view.take:SetScript("OnClick", function()
		view.ctx.actions.TakeAll()
	end)
	view.take:HookScript("OnEnter", ns.LootParts_TakeAllTooltip)
	view.take:HookScript("OnLeave", GameTooltip_Hide)
	view.pager = ns.LootParts_Pager(root)
	return view
end

-- "5 items · 3g 96s": what's left and, with the value extra, what it's worth.
local function Summary(ctx, lines)
	local count, worth = 0, 0
	for _, line in ipairs(lines) do
		for _, e in ipairs(ns.Loot_LineEntries(line)) do
			count = count + 1
			worth = worth + (ns.Loot_Worth(e) or 0)
		end
	end
	local text = count == 1 and "1 item" or (count .. " items")
	if ctx.extras.value and worth > 0 then
		text = text .. "  " .. ns.Price(worth)
	end
	return text
end

local function DrawFooter(view, ctx, lines, y, width, size)
	local take = view.take
	take:SetShown(ctx.canTake)
	local pagerW = view.pager:Set(ctx, size)
	local h = size + 8
	UI.SetFont(view.summary, "body", size - 1)
	view.summary:SetText(#lines > 0 and Summary(ctx, lines) or "")
	view.summary:ClearAllPoints()
	view.summary:SetPoint("TOPLEFT", PAD, -y - (h - view.summary:GetStringHeight()) / 2)
	local right = -PAD
	if ctx.canTake then
		UI.SetFont(take.label, "label", size)
		local labelW = math.ceil(take.label:GetUnboundedStringWidth())
		local capW = take.cap:SetKey(ctx.keyText, size)
		take.cap:ClearAllPoints()
		take.cap:SetPoint("LEFT", take.label, "RIGHT", 6, 0)
		take:SetSize(labelW + (capW > 0 and capW + 6 or 0), h)
		take:ClearAllPoints()
		take:SetPoint("TOPRIGHT", right, -y)
		right = right - take:GetWidth() - 8
	end
	view.pager:ClearAllPoints()
	view.pager:SetPoint("TOPRIGHT", right, -y - (h - view.pager:GetHeight()) / 2)
	if not ctx.canTake and pagerW == 0 and #lines == 0 then
		return y
	end
	return y + h
end

local function Draw(view, ctx)
	view.ctx = ctx
	local size = ctx.size
	local tileSize = Scale(TILE, size)
	local gap = Scale(TILE_GAP, size)
	local width = PAD * 2 + COLUMNS * tileSize + (COLUMNS - 1) * gap
	view.panel:SetAlpha(ctx.bgAlpha)
	if view.root.Center then -- the Blizzard theme's tooltip fill keeps its own alpha: fade the fill only
		view.root.Center:SetAlpha(ctx.bgAlpha)
	end

	UI.SetFont(view.title, "title", size + 2)
	view.title:SetText(ctx.title)
	view.title:ClearAllPoints()
	view.title:SetPoint("TOPLEFT", PAD, -PAD)
	view.title:SetPoint("RIGHT", view.close, "LEFT", -4, 0)
	view.close:ClearAllPoints()
	view.close:SetPoint("TOPRIGHT", -PAD + 6, -PAD + 4)
	local y = PAD + math.max(math.ceil(view.title:GetStringHeight()), CLOSE_W - 6) + PAD

	local lines = ns.Loot_Lines(ctx.entries, { foldJunk = ctx.foldJunk, hideTaken = true })
	local shown
	shown, ctx.page, ctx.pages = ns.Loot_Page(lines, ctx.perPage, ctx.page)
	local tiles = view.tiles
	for i, line in ipairs(shown) do
		local tile = tiles[i] or NewTile(view)
		tiles[i] = tile
		local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
		tile:SetSize(tileSize, tileSize)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", PAD + col * (tileSize + gap), -(y + row * (tileSize + gap)))
		SetTile(tile, line, ctx, size)
	end
	for i = #shown + 1, #tiles do
		tiles[i]:Hide()
		tiles[i].line = nil
	end

	local c = view.caption
	if #shown > 0 then
		local rows = math.ceil(#shown / COLUMNS)
		y = y + rows * tileSize + (rows - 1) * gap + PAD
		view.empty:Hide()
		view.firstLine = shown[1]
		UI.SetFont(c.name, "body", size)
		UI.SetFont(c.sub, "body", size - 1)
		c.fill:SetColorTexture(UI.Color("surface"))
		SetCaption(view, shown[1])
		local h = 12 + math.ceil(c.name:GetStringHeight()) + 2 + math.ceil(math.max(c.sub:GetStringHeight(), size - 1))
		c:SetSize(width - 2 * PAD, h)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", PAD, -y)
		c:Show()
		y = y + h + PAD
	else
		view.firstLine = nil
		c:Hide()
		UI.SetFont(view.empty, "body", size)
		view.empty:ClearAllPoints()
		view.empty:SetPoint("TOPLEFT", PAD, -y)
		view.empty:Show()
		y = y + math.ceil(view.empty:GetStringHeight()) + PAD
	end

	y = DrawFooter(view, ctx, lines, y, width, size) + PAD
	return width, y
end

ns.LootLooks.tiles = { name = "Tiles", Build = Build, Draw = Draw }
