local addonName, ns = ...

-- Holidays & events: the Events page of the Tomte window. "On now" and "Soon", one block per event: a header (name,
-- time left, description in its tooltip), the daily boss, the Darkmoon Faire profession quests and four collapsible
-- lists of what's still missing (mounts, battle pets, toys, achievements). A footer names calendar filters that hide
-- events and opens Blizzard's calendar.

local UI = ns.UI
local ROW_H, HEADER_H, SECTION_H, LIST_H = 22, 30, 30, 22
local ICON, HEADER_ICON = 18, 22
local INDENT = 28
local FOOT_H = 30
local KINDS = {
	{ key = "mounts", title = "Mounts" },
	{ key = "pets", title = "Battle pets" },
	{ key = "toys", title = "Toys" },
	{ key = "achievements", title = "Achievements" },
}

local db
local page
local rows, used = {}, 0
local pendingKey -- scroll to this event on the next layout

function ns.EventsPage_Init(moduleDB)
	db = moduleDB
end

local TipLine = UI.TipLine

-- Tooltip ------------------------------------------------------------------------------------------------------

local function EntryTooltip(row, e)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if e.kind == "ach" then
		local link = GetAchievementLink(e.id)
		if link then
			GameTooltip:SetHyperlink(link)
		else
			GameTooltip:SetText(e.name, 1, 1, 1)
		end
	elseif e.kind == "toy" then
		GameTooltip:SetToyByItemID(e.id)
	else
		GameTooltip:SetText(e.name, 1, 1, 1)
		for _, line in ipairs(ns.Collect_ParseSource(e.source).lines) do
			TipLine(line.display .. ": " .. ns.Collect_Clean(line.raw), "textMuted", true)
		end
	end
	GameTooltip:AddLine(" ")
	TipLine(e.kind == "ach" and "Click: open it in the Achievements window" or "Click: open the journal", "textMuted")
	if e.kind ~= "pet" then
		TipLine("Shift-click: link it in chat", "textMuted")
	end
	GameTooltip:Show()
	if page.preview then
		ns.ModelPreview_Show(page.preview, ns.Entry_Model(e))
	end
end

-- Rows ---------------------------------------------------------------------------------------------------------

local function NewRow()
	local row = CreateFrame("Button", nil, page.scroll.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.Color("hover"))
	row.hover:Hide()
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT", 4, 0)
	row.line:SetPoint("BOTTOMRIGHT", -4, 0)
	row.line:SetColorTexture(UI.RGBA("frame", 0.25))
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.left = UI.Text(row, 12, "text")
	row.left:SetWordWrap(false)
	row.right = UI.Text(row, 11, "textMuted")
	row.right:SetJustifyH("RIGHT")
	row.right:SetWordWrap(false)
	row.right:SetPoint("RIGHT", -8, 0)
	row:SetScript("OnEnter", function(self)
		if self.onClick then
			self.hover:Show()
		end
		if self.tip then
			self.tip(self)
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
		if page.preview then
			ns.ModelPreview_Hide(page.preview)
		end
	end)
	row:SetScript("OnClick", function(self, button)
		if self.onClick then
			self.onClick(button)
		end
	end)
	return row
end

-- kind: "section" | "header" | "list" | "item" | "note"
local function Row(y, height, indent, icon, text, textRole, right, rightRole, kind)
	used = used + 1
	local row = rows[used] or NewRow()
	rows[used] = row
	row:SetHeight(height)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", indent, -y)
	row:SetPoint("RIGHT")
	row.onClick, row.tip = nil, nil
	if row.progress then
		row.progress:Stop()
	end
	local size = kind == "header" and HEADER_ICON or ICON
	row.icon:SetSize(size, size)
	row.icon:SetShown(icon ~= nil)
	if icon then
		row.icon:SetTexture(icon)
	end
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", 6, 0)
	row.left:ClearAllPoints()
	row.left:SetPoint("LEFT", icon and row.icon or row, icon and "RIGHT" or "LEFT", icon and 8 or 6, 0)
	row.left:SetPoint("RIGHT", row.right, "LEFT", -10, 0)
	UI.SetFont(row.left, (kind == "section" or kind == "header") and "title" or "body",
		kind == "section" and 15 or kind == "header" and 14 or 12)
	row.left:SetText(text or "")
	UI.SetTextRole(row.left, textRole or "text")
	row.right:SetText(right or "")
	UI.SetTextRole(row.right, rightRole or "textMuted")
	row.line:SetShown(kind == "header")
	row:Show()
	return row
end

-- Layout ---------------------------------------------------------------------------------------------------------

-- Folding is remembered per holiday, not per occurrence: ev.key's ":<start minute>" suffix is dropped.
local function Collapsed(ev, kind)
	return db.collapsed[ev.key:gsub(":%d+$", "") .. kind] == true
end

local function ToggleCollapsed(ev, kind)
	local key = ev.key:gsub(":%d+$", "") .. kind
	db.collapsed[key] = not db.collapsed[key] or nil
	ns.EventsPage_Refresh()
end

local function EventHeader(ev, y)
	local right = ns.Events_When(ev)
	local row = Row(y, HEADER_H, 0, ev.texture, ev.name, ev.active and "heading" or "textMuted", right,
		ev.active and "text" or "textFaint", "header")
	row.tip = function(self)
		ns.Events_Tooltip(self, ev)
	end
	return y + HEADER_H
end

local function BossRows(ev, y)
	for _, b in ipairs(ns.Events_BossesFor(ev)) do
		local status, role
		if not b.eligible then
			status, role = "not available on this character", "textFaint"
		elseif b.doneToday then
			status, role = "done today", "success"
		else
			status, role = "not done today", "warning"
		end
		local row = Row(y, ROW_H, INDENT, nil, b.name, b.eligible and not b.doneToday and "text" or "textMuted", status, role,
			"item")
		if b.eligible then
			local id = b.id
			row.onClick = function()
				ns.Events_OpenFinder(id)
			end
			row.tip = function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(b.name, 1, 1, 1)
				TipLine("The holiday's daily boss, in the Dungeon Finder.", "textMuted", true)
				TipLine("Click: open the Dungeon Finder", "textMuted")
				GameTooltip:Show()
			end
		end
		y = y + ROW_H
	end
	return y
end

local function DarkmoonRows(ev, y)
	if not (ev.def and ev.def.key == "darkmoon" and ev.active) then
		return y
	end
	local quests = ns.Events_DarkmoonNow() or {}
	if #quests == 0 then
		Row(y, ROW_H, INDENT, nil, "No profession quests for this character", "textMuted", nil, nil, "note")
		return y + ROW_H
	end
	for _, q in ipairs(quests) do
		Row(y, ROW_H, INDENT, nil, ("%s: %s"):format(q.profession, q.title or "Loading..."), q.done and "textMuted" or "text",
			q.done and "done" or "not done", q.done and "success" or "warning", "item")
		y = y + ROW_H
	end
	return y
end

local function EntryRight(e)
	if e.kind == "ach" then
		if e.total and e.total > 0 then
			return ("%d%%  %d/%d"):format(math.floor(e.percent or 0), e.done or 0, e.total)
		end
		return nil
	end
	return e.line and ns.Collect_Clean(e.line) or nil
end

local function Lists(ev, y)
	if not ev.def then
		return y
	end
	local missing = ns.Events_Missing(ev)
	if not missing then
		local row = Row(y, ROW_H, INDENT, nil, "Reading your collections...", "textMuted", nil, nil, "note")
		if not row.progress then
			row.progress = UI.ProgressLine(row)
			row.progress:SetPoint("TOPLEFT", row.left, "BOTTOMLEFT", 0, -2)
		end
		if row.progress:Track(ns.EventsCatalog_Progress) then
			row.progress:SetWidth(row.left:GetStringWidth())
		end
		return y + ROW_H
	end
	local any = false
	for _, k in ipairs(KINDS) do
		local list = missing[k.key]
		if db.show[k.key] ~= false and #list > 0 then
			any = true
			local collapsed = Collapsed(ev, k.key)
			local head = Row(y, LIST_H, INDENT, nil, (collapsed and "+ " or "- ") .. k.title, "accent", tostring(#list),
				"textMuted", "list")
			local kind = k.key
			head.onClick = function()
				ToggleCollapsed(ev, kind)
			end
			y = y + LIST_H
			if not collapsed then
				for _, e in ipairs(list) do
					local row = Row(y, ROW_H, INDENT + 14, e.icon, e.name, "text", EntryRight(e), "textMuted", "item")
					row.onClick = function()
						if IsShiftKeyDown() then
							ns.Entry_Link(e)
						else
							ns.Entry_Open(e)
						end
					end
					row.tip = function(self)
						EntryTooltip(self, e)
					end
					y = y + ROW_H
				end
			end
		end
	end
	if not any then
		Row(y, ROW_H, INDENT, nil, "Nothing left to collect", "success", nil, nil, "note")
		y = y + ROW_H
	end
	return y
end

local function StartText(ev)
	local t = ev.startTime
	if t and t.monthDay and FormatShortDate then
		return ("Starts %s, %s"):format(FormatShortDate(t.monthDay, t.month), ns.Events_When(ev))
	end
	return ns.Events_When(ev)
end

local function Layout()
	for i = 1, used do
		rows[i]:Hide()
	end
	used = 0
	local s = ns.Events_Current()
	local y = 0
	local scrollTo
	if s.lockdown then
		Row(y, ROW_H, 0, nil, "The calendar can't be read right now. It comes back after the lockdown.", "warning", nil, nil,
			"note")
		y = y + ROW_H
	end
	local active, soon = {}, {}
	for _, ev in ipairs(s.list) do
		table.insert(ev.active and active or soon, ev)
	end
	if #s.list == 0 then
		Row(y, ROW_H, 0, nil, ("No world events now or in the next %d days."):format(db.soonDays), "textMuted", nil, nil,
			"note")
		y = y + ROW_H
	end
	if #active > 0 then
		Row(y, SECTION_H, 0, nil, "On now", "heading", nil, nil, "section")
		y = y + SECTION_H
		for _, ev in ipairs(active) do
			if ev.key == pendingKey then
				scrollTo = y
			end
			y = EventHeader(ev, y)
			y = BossRows(ev, y)
			y = DarkmoonRows(ev, y)
			y = Lists(ev, y)
			y = y + 8
		end
	end
	if #soon > 0 then
		Row(y, SECTION_H, 0, nil, "Soon", "heading", nil, nil, "section")
		y = y + SECTION_H
		for _, ev in ipairs(soon) do
			if ev.key == pendingKey then
				scrollTo = y
			end
			y = EventHeader(ev, y)
			Row(y, ROW_H, INDENT, nil, StartText(ev), "textMuted", nil, nil, "note")
			y = y + ROW_H + 8
		end
	end
	page.scroll:SetContentHeight(y)
	if pendingKey then
		page.scroll:SetScroll(scrollTo or 0)
		pendingKey = nil
	end
	local hidden = s.hidden
	page.filters:SetText(#hidden > 0 and ("Hidden by your calendar filter: " .. table.concat(hidden, ", ")) or "")
end

function ns.EventsPage_Refresh()
	if page and page:IsVisible() then
		Layout()
	end
end

-- Opens the page, at an event when key is given.
function ns.EventsPage_Open(key)
	pendingKey = key
	ns.Panel_OpenPage("events")
	ns.EventsPage_Refresh()
end

ns.EventsPage = {
	title = "Events",
	Create = function(frame)
		page = frame
		page.scroll = UI.Scroll(page)
		page.scroll:SetPoint("TOPLEFT", 0, 0)
		page.scroll:SetPoint("BOTTOMRIGHT", -12, FOOT_H + 6)
		page.calendar = UI.Button(page, 110, "Open calendar")
		page.calendar:SetPoint("BOTTOMRIGHT", -12, 0)
		page.calendar:SetScript("OnClick", function()
			ns.Events_OpenCalendar()
		end)
		page.filters = UI.Text(page, 12, "warning")
		page.filters:SetPoint("LEFT", page, "BOTTOMLEFT", 4, FOOT_H / 2)
		page.filters:SetPoint("RIGHT", page.calendar, "LEFT", -12, 0)
		page.filters:SetWordWrap(false)
		page.preview = ns.ModelPreview_Create(page)
	end,
	Refresh = function()
		Layout()
	end,
}
