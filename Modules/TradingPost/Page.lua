local addonName, ns = ...

-- Trading Post page in the Tomte window: your Tender and what waits in the Collector's Cache, the month's time left,
-- the Traveler's Log (points bar with its milestones, then the activities, closest to done first; click to track one)
-- and the shop from your last visit this month. It renders Read.lua's state; registered in TradingPost.lua.

local UI = ns.UI
local Kit = ns.HomeKit
local PAD = 8
local BAR_H = 8
local CHEST_ICON = "Interface\\Icons\\INV_Misc_Treasurechest02b"

local page, scroll, c -- c: the scroll content
local activityRows, shopRows, ticks = {}, {}, {}
local showDone = false

local function Text(size, role)
	local fs = UI.Text(c, size, role)
	fs:SetWordWrap(true)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Build()
	scroll = UI.Scroll(page)
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -10, 0)
	c = scroll.content
	scroll.onWidthChanged = function()
		ns.TradingPostPage_Refresh()
	end
	c.tender = Text(14, "text")
	c.cache = Kit.Row(c)
	c.month = Text(12, "textMuted")
	c.logHead = Kit.Heading(c)
	c.bar = UI.Bar(c, BAR_H)
	c.milestones = Text(12, "textMuted")
	c.nextText = Text(13, "accent")
	c.noLog = Text(13, "textMuted")
	c.actHead = Kit.Heading(c)
	c.shopHead = Kit.Heading(c)
	c.shopNote = Text(13, "textMuted")
end

-- Places fs at y (full width) and returns the y below it.
local function Place(fs, y, text, gap)
	if not text or text == "" then
		fs:Hide()
		return y
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", PAD, -y)
	fs:SetPoint("RIGHT", -PAD, 0)
	fs:SetText(text)
	fs:Show()
	return y + fs:GetStringHeight() + (gap or 4)
end

local function PlaceFrame(frame, y, height)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", PAD, -y)
	frame:SetPoint("RIGHT", -PAD, 0)
	frame:Show()
	return y + height
end

-- Tender and the cache ---------------------------------------------------------------------------------------

local function RenderTender(y, s)
	local icon = s.tenderIcon and ("|T%d:16:16|t "):format(s.tenderIcon) or ""
	y = Place(c.tender, y, ("%s%s %s"):format(icon, ns.Thousands(s.tender), s.tenderName or "Trader's Tender"), 6)
	if s.waiting > 0 then
		c.cache:Set(CHEST_ICON, ("%s Tender waiting in the Collector's Cache"):format(ns.Thousands(s.waiting)),
			"success", "Waypoint", "accent")
		c.cache.onClick = ns.TradingPost_Waypoint
		c.cache.onEnter = function(row)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText("Collector's Cache", UI.Color("heading"))
			GameTooltip:AddLine("At the Trading Post in Stormwind, Orgrimmar or Dornogal. Open it to collect.",
				UI.RGB("textMuted"))
			GameTooltip:AddLine("Click: waypoint to the nearest one", UI.RGB("accent"))
			GameTooltip:Show()
		end
		y = PlaceFrame(c.cache, y, Kit.ROW_H) + 4
	else
		c.cache:Hide()
	end
	local left = ns.TradingPost_SecondsLeft()
	local month
	if left then
		month = ("%s ends in %s: new stock and a fresh Traveler's Log then."):format(s.monthName or "This month",
			ns.TradingPost_TimeLeft(left))
	end
	return Place(c.month, y, month, 4) + 14
end

-- Traveler's Log --------------------------------------------------------------------------------------------

local function Tick(i)
	local t = ticks[i]
	if not t then
		t = c.bar:CreateTexture(nil, "OVERLAY")
		t:SetWidth(2)
		ticks[i] = t
	end
	return t
end

local function RenderLog(y, s)
	if not s.available then
		c.logHead:Set("Traveler's Log")
		y = PlaceFrame(c.logHead, y, 30) + 6
		c.bar:Hide()
		c.milestones:Hide()
		c.nextText:Hide()
		for _, t in ipairs(ticks) do
			t:Hide()
		end
		return Place(c.noLog, y, "The Traveler's Log isn't open to this character (trial accounts and characters "
			.. "below level 10).", 4) + 14
	end
	c.noLog:Hide()
	c.logHead:Set("Traveler's Log", ("%s / %s points"):format(ns.Thousands(s.earned), ns.Thousands(s.max)))
	y = PlaceFrame(c.logHead, y, 30) + 8
	y = PlaceFrame(c.bar, y, BAR_H) + 8
	c.bar:SetValue(s.max > 0 and s.earned / s.max or 0)
	local width = c:GetWidth() - 2 * PAD
	local parts = {}
	for i, m in ipairs(s.milestones) do
		local t = Tick(i)
		t:SetColorTexture(UI.Color(m.reached and "frameDark" or "text"))
		t:ClearAllPoints()
		t:SetPoint("TOP", c.bar, "TOPLEFT", width * m.required / s.max, 0)
		t:SetHeight(BAR_H)
		t:SetShown(m.required < s.max)
		local text = ("%s: %s Tender"):format(ns.Thousands(m.required), ns.Thousands(m.tender))
		local role = m.reached and "textFaint" or (m == s.nextOne and "accent" or "textMuted")
		parts[i] = UI.Wrap(text, role)
	end
	for i = #s.milestones + 1, #ticks do
		ticks[i]:Hide()
	end
	y = Place(c.milestones, y, table.concat(parts, "    "), 6)
	local nextText = ns.TradingPost_NextText(s.earned, s.nextOne)
	UI.SetTextRole(c.nextText, nextText and "accent" or "success")
	return Place(c.nextText, y, nextText or "Every milestone reached this month.", 4) + 14
end

local function ActivityTooltip(row, a)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(a.name or "?", UI.Color("heading"))
	if a.eventName and a.eventName ~= "" then
		GameTooltip:AddLine(a.eventName, UI.RGB("accent"))
	end
	if a.description and a.description ~= "" then
		GameTooltip:AddLine(a.description, UI.RGB("text"), true)
	end
	for _, r in ipairs(a.requirements or {}) do
		GameTooltip:AddLine(r.text, UI.RGB(r.completed and "textFaint" or "textMuted"), true)
	end
	GameTooltip:AddLine(("%d points"):format(a.points or 0), UI.RGB("textMuted"))
	if a.completed then
		GameTooltip:AddLine("Done this month", UI.RGB("success"))
	else
		GameTooltip:AddLine(a.tracked and "Click: stop tracking" or "Click: track it in your objectives",
			UI.RGB("accent"))
	end
	GameTooltip:Show()
end

local function RightText(a)
	local cur, max = ns.TradingPost_Progress(a)
	local pts = ("%d pts"):format(a.points or 0)
	if cur then
		return ("%d/%d · %s"):format(cur, max, pts)
	end
	return pts
end

local function RenderActivities(y, s)
	if not s.available then
		c.actHead:Hide()
		Kit.HideFrom(activityRows, 1)
		return y
	end
	local open, done = 0, 0
	for _, a in ipairs(s.sorted) do
		if a.completed then
			done = done + 1
		else
			open = open + 1
		end
	end
	c.actHead:Set("Activities", ("%d open, %d done"):format(open, done),
		done > 0 and (showDone and "Hide done" or "Show done") or nil, function()
			showDone = not showDone
			ns.TradingPostPage_Refresh()
		end)
	y = PlaceFrame(c.actHead, y, 30) + 4
	local n = 0
	for _, a in ipairs(s.sorted) do
		if showDone or not a.completed then
			n = n + 1
			local row = Kit.PoolRow(activityRows, n, c)
			local color = a.completed and "textFaint" or (a.tracked and "accent" or "text")
			row:Set(nil, a.tracked and ("%s  ·  tracked"):format(a.name) or a.name, color, RightText(a),
				a.completed and "textFaint" or "textMuted")
			row.onEnter = function(self)
				ActivityTooltip(self, a)
			end
			if not a.completed then
				row.onClick = function()
					ns.TradingPost_ToggleTrack(a)
				end
			end
			y = PlaceFrame(row, y, Kit.ROW_H)
		end
	end
	Kit.HideFrom(activityRows, n + 1)
	return y + 14
end

-- The shop ----------------------------------------------------------------------------------------------------

local function ShopRight(it)
	if it.state == "bought" then
		return "Bought", "textFaint"
	elseif it.state == "owned" then
		return "Owned", "textFaint"
	end
	return ns.Thousands(it.price), nil
end

local function ShopTooltip(row, it)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if it.itemID and it.itemID > 0 then
		GameTooltip:SetItemByID(it.itemID)
	else
		GameTooltip:SetText(it.name, UI.Color("heading"))
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(("%s · %s Tender"):format(ns.TradingPost_CategoryWord(it.category), ns.Thousands(it.price)),
		UI.RGB("textMuted"))
	if it.state == "bought" then
		GameTooltip:AddLine("Bought at the Trading Post", UI.RGB("success"))
	elseif it.state == "owned" then
		GameTooltip:AddLine("Already in your collection", UI.RGB("success"))
	end
	GameTooltip:Show()
end

local function RenderShop(y, s)
	local shop = ns.TradingPost_Shop()
	if not shop then
		c.shopHead:Set("Shop")
		y = PlaceFrame(c.shopHead, y, 30) + 6
		Kit.HideFrom(shopRows, 1)
		return Place(c.shopNote, y, "Visit a Trading Post (Stormwind, Orgrimmar or Dornogal) to see this month's "
			.. "stock here.", 4) + 10
	end
	local summary = ns.TradingPost_ShopSummary(shop.items, s.tender)
	c.shopHead:Set("Shop", ("seen %s ago · %s"):format(ns.Ago(GetServerTime() - shop.at),
		ns.TradingPost_ShopText(summary) or ""))
	y = PlaceFrame(c.shopHead, y, 30) + 4
	c.shopNote:Hide()
	for i, it in ipairs(shop.items) do
		local row = Kit.PoolRow(shopRows, i, c)
		local right, rightColor = ShopRight(it)
		local color = it.state and "textFaint" or (it.price <= s.tender and "accent" or "text")
		row:Set(it.icon, it.name, color, right, rightColor)
		row.onEnter = function(self)
			ShopTooltip(self, it)
		end
		y = PlaceFrame(row, y, Kit.ROW_H)
	end
	Kit.HideFrom(shopRows, #shop.items + 1)
	return y + 10
end

local function Render()
	if not (page and page:IsVisible()) then
		return
	end
	local s = ns.TradingPost_State()
	local y = PAD
	y = RenderTender(y, s)
	y = RenderLog(y, s)
	y = RenderActivities(y, s)
	y = RenderShop(y, s)
	scroll:SetContentHeight(y + PAD)
end

function ns.TradingPostPage_Refresh()
	Render()
end

ns.TradingPostPage = {
	title = "Trading Post",
	Create = function(frame)
		page = frame
		Build()
	end,
	Refresh = function()
		ns.TradingPost_ReadAll()
		Render()
	end,
}
