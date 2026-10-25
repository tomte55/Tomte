local addonName, ns = ...

-- Loot: the Panel look of the loot window. A themed panel with a header (a small LOOT label over where the loot
-- came from, a hairline under it), a featured item on top only when one deserves it (a Gear Check upgrade or a mount, pet, toy,
-- legendary or set token: Data.lua's Loot_FeaturedIndex), then two-line rows (name and count; the item's type and
-- extras) with the price on the right. Coin sits in the footer next to the Take all button. Registered in
-- ns.LootLooks; the window around it is Window.lua.

local BASE_FONT = 12 -- the font size the sizes below are drawn for; other sizes scale them
local WIDTH = 320
local PAD = 8
local ROW_GAP = 2
local FEATURED_ICON = 40
local ICON_EDGE = 1 -- the quality-colored frame around an icon
local HOVER = 0.15 -- a row's accent fill under the mouse
local FEATURED_FILL, FEATURED_EDGE = 0.12, 0.45 -- the featured item's box, in its quality color
local RULE_ALPHA = 0.5
local LOCKED_ALPHA = 0.6
local CLOSE_W = 18
local BUTTON_PAD = 10 -- inside the Take all button, left and right
-- The Take all button: an accent outline over a faint accent tint, deeper under the mouse.
local TAKE_TINT, TAKE_HOVER, TAKE_EDGE = 0.14, 0.3, 0.8

local UI = ns.UI

local function Scale(n, size)
	return math.floor(n * size / BASE_FONT + 0.5)
end

local function QualityColor(quality)
	local q = quality and ITEM_QUALITY_COLORS[quality]
	return q and { q.r, q.g, q.b } or nil
end

-- An icon with its quality frame behind it, on parent.
local function NewIcon(parent)
	local frameTex = parent:CreateTexture(nil, "ARTWORK", nil, -1)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frameTex:SetPoint("TOPLEFT", icon, -ICON_EDGE, ICON_EDGE)
	frameTex:SetPoint("BOTTOMRIGHT", icon, ICON_EDGE, -ICON_EDGE)
	icon.frame = frameTex
	return icon
end

local function SetIcon(icon, t, size, locked)
	icon:SetSize(size, size)
	icon:SetTexture(t.icon)
	icon:SetDesaturated(locked == true)
	ns.LootParts_IconFrame(icon.frame, t.quality, t.money)
end

local function Clickable(b)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", ns.LootParts_Click)
	b:SetScript("OnEnter", ns.LootParts_Tooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
end

local function NewRow(view)
	local row = CreateFrame("Button", nil, view.root)
	Clickable(row)
	row.icon = NewIcon(row)
	row.icon:SetPoint("LEFT", 4, 0)
	row.name = UI.Text(row, BASE_FONT, "text")
	row.name:SetWordWrap(false)
	row.sub = UI.Text(row, BASE_FONT - 1, "textMuted")
	row.sub:SetWordWrap(false)
	row.worth = UI.Text(row, BASE_FONT - 1, "text", "number")
	row.worth:SetJustifyH("RIGHT")
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.rule = UI.Hairline(row, WIDTH, RULE_ALPHA, "rule")
	row.rule:SetPoint("TOPLEFT", 0, ROW_GAP / 2)
	row.rule:SetPoint("TOPRIGHT", 0, ROW_GAP / 2)
	return row
end

local function Build(host)
	local view = { rows = {} }
	local root = CreateFrame("Frame", nil, host)
	view.root = root
	view.panel = UI.Panel(root)

	view.headRule = UI.Hairline(root, WIDTH, RULE_ALPHA, "rule")
	view.label = UI.Text(root, BASE_FONT - 2, "textMuted", "label")
	view.title = UI.Text(root, BASE_FONT + 3, "heading", "title")
	view.title:SetWordWrap(false)
	view.close = ns.LootParts_FlatButton(root, "x", BASE_FONT)
	view.close:SetSize(CLOSE_W, CLOSE_W)
	view.close:SetScript("OnClick", function()
		view.ctx.actions.Close()
	end)

	local f = CreateFrame("Button", nil, root)
	Clickable(f)
	f.fill = f:CreateTexture(nil, "BACKGROUND")
	f.fill:SetAllPoints()
	UI.Border(f, "frame")
	f.icon = NewIcon(f)
	f.icon:SetPoint("TOPLEFT", 8, -8)
	f.name = UI.Text(f, BASE_FONT + 2, "text")
	f.name:SetWordWrap(false)
	f.verdict = UI.Text(f, BASE_FONT, "text")
	f.verdict:SetWordWrap(false)
	f.sub = UI.Text(f, BASE_FONT - 1, "textMuted")
	f.sub:SetWordWrap(false)
	view.featured = f

	view.empty = UI.Text(root, BASE_FONT, "textMuted")
	view.empty:SetText("Nothing left")

	view.footRule = UI.Hairline(root, WIDTH, RULE_ALPHA, "rule")
	view.money = ns.LootParts_FlatButton(root, "", BASE_FONT, "warning")
	view.money:SetScript("OnClick", function(self)
		if view.ctx.live then
			view.ctx.actions.Loot(self.entries)
		end
	end)
	view.pager = ns.LootParts_Pager(root)

	local take = CreateFrame("Button", nil, root)
	take.fill = take:CreateTexture(nil, "BACKGROUND")
	take.fill:SetAllPoints()
	UI.Border(take, "accent")
	take.label = UI.Text(take, BASE_FONT, "accent", "label")
	take.label:SetText("Take all")
	take.cap = ns.LootParts_Keycap(take)
	take:SetScript("OnClick", function()
		view.ctx.actions.TakeAll()
	end)
	take:SetScript("OnEnter", function(self)
		self.fill:SetColorTexture(UI.RGBA("accent", TAKE_HOVER))
		UI.SetBorderColor(self, "heading")
		UI.SetTextRole(self.label, "heading")
		ns.LootParts_TakeAllTooltip(self)
	end)
	take:SetScript("OnLeave", function(self)
		self.fill:SetColorTexture(UI.RGBA("accent", TAKE_TINT))
		UI.SetBorderColor(self, "accent", TAKE_EDGE)
		UI.SetTextRole(self.label, "accent")
		GameTooltip_Hide()
	end)
	view.take = take
	return view
end

local function DrawHeader(view, ctx, width, size)
	UI.SetFont(view.label, "label", size - 2)
	view.label:SetText(ns.Spaced("Loot"))
	view.label:ClearAllPoints()
	view.label:SetPoint("TOPLEFT", PAD + 2, -PAD)
	UI.SetFont(view.title, "title", size + 3)
	view.title:SetText(ctx.title)
	view.title:ClearAllPoints()
	view.title:SetPoint("TOPLEFT", view.label, "BOTTOMLEFT", 0, -2)
	view.title:SetPoint("RIGHT", view.close, "LEFT", -4, 0)
	view.close:ClearAllPoints()
	view.close:SetPoint("TOPRIGHT", -PAD + 4, -PAD + 2)
	local h = PAD + math.ceil(view.label:GetStringHeight()) + 2 + math.ceil(view.title:GetStringHeight()) + PAD
	view.headRule:ClearAllPoints()
	view.headRule:SetPoint("TOPLEFT", 0, -h)
	view.headRule:SetPoint("TOPRIGHT", 0, -h)
	return h
end

-- The featured item's box; returns its height.
local function DrawFeatured(view, ctx, e, y, size)
	local f = view.featured
	local t = ns.LootParts_LineText({ entry = e }, "full", true)
	f.line, f.ctx = { entry = e }, ctx
	local iconSize = Scale(FEATURED_ICON, size)
	SetIcon(f.icon, t, iconSize, e.locked)
	local color = QualityColor(e.quality) or { UI.Color("accent") }
	f.fill:SetColorTexture(color[1], color[2], color[3], FEATURED_FILL)
	UI.SetBorderColor(f, color, FEATURED_EDGE)
	UI.SetFont(f.name, "body", size + 2)
	f.name:SetText(t.name)
	f.name:ClearAllPoints()
	f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, 0)
	f.name:SetPoint("RIGHT", -8, 0)
	local v = ctx.extras.verdict and e.verdict
	UI.SetFont(f.verdict, "body", size)
	f.verdict:SetText(v and v.text and UI.Wrap(v.text, v.role or "textMuted") or "")
	f.verdict:ClearAllPoints()
	f.verdict:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -2)
	f.verdict:SetPoint("RIGHT", -8, 0)
	local parts = { e.subType and UI.Wrap(e.subType, "textMuted") or nil }
	local detail = ns.Loot_PartsText(ns.Loot_Details(e, ns.Loot_DetailOpts(nil, true)))
	if detail ~= "" then
		parts[#parts + 1] = detail
	end
	UI.SetFont(f.sub, "body", size - 1)
	f.sub:SetText(table.concat(parts, "  "))
	f.sub:ClearAllPoints()
	f.sub:SetPoint("TOPLEFT", (v and v.text) and f.verdict or f.name, "BOTTOMLEFT", 0, -2)
	f.sub:SetPoint("RIGHT", -8, 0)
	local textH = f.name:GetStringHeight() + 2 + f.sub:GetStringHeight()
		+ ((v and v.text) and (2 + f.verdict:GetStringHeight()) or 0)
	local h = math.ceil(math.max(iconSize, textH)) + 16
	f:SetHeight(h)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", PAD, -y)
	f:SetPoint("RIGHT", -PAD, 0)
	f:SetAlpha(e.locked and LOCKED_ALPHA or 1)
	f:Show()
	return h
end

local function SetRow(row, line, ctx, rowH, size)
	local t = ns.LootParts_LineText(line, "tag", false)
	row.line, row.ctx = line, ctx
	row:SetHeight(rowH)
	local locked = t.entry and t.entry.locked
	SetIcon(row.icon, t, rowH - 8, locked)
	UI.SetFont(row.name, "body", size)
	UI.SetFont(row.sub, "body", size - 1)
	UI.SetFont(row.worth, "number", size - 1)
	row.name:SetText(t.name)
	local e = t.entry
	local parts = { e and e.subType and UI.Wrap(e.subType, "textMuted") or nil }
	if t.detail ~= "" then
		parts[#parts + 1] = t.detail
	end
	local sub = table.concat(parts, "  ")
	row.sub:SetText(sub)
	local worth
	if ctx.extras.value then
		worth = line.junk and (line.worth and line.worth > 0 and ns.Price(line.worth)) or (e and ns.Loot_WorthText(e))
	end
	row.worth:SetText(worth or "")
	row.worth:ClearAllPoints()
	row.worth:SetPoint("RIGHT", -4, 0)
	row.name:ClearAllPoints()
	row.sub:ClearAllPoints()
	local right = worth and -(math.ceil(row.worth:GetUnboundedStringWidth()) + 10) or -4
	if sub ~= "" then
		row.name:SetPoint("BOTTOMLEFT", row.icon, "RIGHT", 9, 1)
		row.sub:SetPoint("TOPLEFT", row.icon, "RIGHT", 9, -1)
		row.sub:SetPoint("RIGHT", row, "RIGHT", right, 0)
		row.sub:Show()
	else
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 9, 0)
		row.sub:Hide()
	end
	row.name:SetPoint("RIGHT", row, "RIGHT", right, 0)
	row.hl:SetColorTexture(UI.Color("accent"))
	row.hl:SetAlpha(HOVER)
	row:SetAlpha(locked and LOCKED_ALPHA or 1)
	row:Show()
end

local function DrawFooter(view, ctx, y, width, size)
	local money = {}
	local names = {}
	for _, e in ipairs(ctx.entries) do
		if e.kind == "money" and not e.taken then
			money[#money + 1] = e
			names[#names + 1] = e.name
		end
	end
	local take = view.take
	local pagerW = view.pager:Set(ctx, size)
	local hasMoney = #money > 0
	view.money:SetShown(hasMoney)
	take:SetShown(ctx.canTake)
	if not (hasMoney or ctx.canTake or pagerW > 0) then
		view.footRule:Hide()
		return y
	end
	view.footRule:ClearAllPoints()
	view.footRule:SetPoint("TOPLEFT", 0, -y)
	view.footRule:SetPoint("TOPRIGHT", 0, -y)
	view.footRule:Show()
	y = y + PAD
	local h = size + 12
	if ctx.canTake then
		UI.SetFont(take.label, "label", size)
		UI.SetTextRole(take.label, "accent")
		take.fill:SetColorTexture(UI.RGBA("accent", TAKE_TINT))
		UI.SetBorderColor(take, "accent", TAKE_EDGE)
		local capW = take.cap:SetKey(ctx.keyText, size)
		local labelW = math.ceil(take.label:GetUnboundedStringWidth())
		take.label:ClearAllPoints()
		take.label:SetPoint("LEFT", BUTTON_PAD, 0)
		take.cap:ClearAllPoints()
		take.cap:SetPoint("LEFT", take.label, "RIGHT", 7, 0)
		take:SetSize(BUTTON_PAD * 2 + labelW + (capW > 0 and capW + 7 or 0), h)
		take:ClearAllPoints()
		take:SetPoint("TOPRIGHT", -PAD, -y)
	end
	view.pager:ClearAllPoints()
	if ctx.canTake then
		view.pager:SetPoint("RIGHT", take, "LEFT", -6, 0)
	else
		view.pager:SetPoint("TOPRIGHT", -PAD, -y - (h - view.pager:GetHeight()) / 2)
	end
	if hasMoney then
		view.money.entries = money
		UI.SetFont(view.money.label, "label", size)
		view.money.label:SetText("+ " .. table.concat(names, ", "))
		view.money:SetSize(math.ceil(view.money.label:GetUnboundedStringWidth()) + 4, h)
		view.money.label:ClearAllPoints()
		view.money.label:SetPoint("LEFT", 2, 0)
		view.money:ClearAllPoints()
		view.money:SetPoint("TOPLEFT", PAD, -y)
	end
	return y + h + PAD
end

local function Draw(view, ctx)
	view.ctx = ctx
	local size = ctx.size
	local width = Scale(WIDTH, size)
	view.panel:SetAlpha(ctx.bgAlpha)
	if view.root.Center then -- the Blizzard theme's tooltip fill keeps its own alpha: fade the fill only
		view.root.Center:SetAlpha(ctx.bgAlpha)
	end
	local y = DrawHeader(view, ctx, width, size) + PAD

	local featuredIndex = ns.Loot_FeaturedIndex(ctx.entries)
	local featured = featuredIndex and ctx.entries[featuredIndex]
	if featured then
		y = y + DrawFeatured(view, ctx, featured, y, size) + PAD
	else
		view.featured:Hide()
	end

	local lines = ns.Loot_Lines(ctx.entries, { foldJunk = ctx.foldJunk, hideTaken = true, skipMoney = true,
		skip = featured })
	local shown
	shown, ctx.page, ctx.pages = ns.Loot_Page(lines, ctx.perPage, ctx.page)
	local rowH = size * 2 + 10
	local rows = view.rows
	for i, line in ipairs(shown) do
		local row = rows[i] or NewRow(view)
		rows[i] = row
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD, -y)
		row:SetPoint("RIGHT", -PAD, 0)
		SetRow(row, line, ctx, rowH, size)
		row.rule:SetShown(i > 1)
		y = y + rowH + ROW_GAP
	end
	for i = #shown + 1, #rows do
		rows[i]:Hide()
		rows[i].line = nil
	end
	local hasMoney = false
	for _, e in ipairs(ctx.entries) do
		hasMoney = hasMoney or (e.kind == "money" and not e.taken)
	end
	if #shown == 0 and not featured and not hasMoney then
		UI.SetFont(view.empty, "body", size)
		view.empty:ClearAllPoints()
		view.empty:SetPoint("TOPLEFT", PAD + 2, -y)
		view.empty:Show()
		y = y + math.ceil(view.empty:GetStringHeight()) + PAD
	else
		view.empty:Hide()
		y = y + PAD - ROW_GAP
	end
	y = DrawFooter(view, ctx, y, width, size)
	return width, y
end

ns.LootLooks.panel = { name = "Panel", Build = Build, Draw = Draw }
