local addonName, ns = ...

-- Groups in chat: the page in the Tomte window. Who's looking for what, newest first, with the page's two filters. Click
-- whispers; right-click invites someone looking for a group. Rules in Data.lua; registered in ChatGroups.lua.

local PAD = 8
local TOP_H = 34 -- the row of filters
local FILTER_GAP = 12
local KINDS = {
	{ value = "all", text = "Everyone" },
	{ value = "group", text = "Groups" },
	{ value = "player", text = "Players" },
}
local LEVELS = {
	{ value = true, text = "Near my level" },
	{ value = false, text = "All levels" },
}

local UI = ns.UI
local Kit = ns.HomeKit

local page, c
local rows = {}

local function RowEnter(row)
	local entry = row.entry
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(entry.name, UI.RGB("heading"))
	UI.TipLine(entry.text, "text", true)
	UI.TipLine(entry.kind == "player" and "Click to whisper. Right-click to invite." or "Click to whisper.", "textMuted")
	GameTooltip:Show()
end

local function RowClick(row)
	ns.Chat_SendTell(row.entry.sender)
end

local function RowRightClick(row)
	if row.entry.kind == "player" then
		C_PartyInfo.InviteUnit(row.entry.sender)
	end
end

local function Layout()
	local db = ns.ChatGroups_DB()
	local byKey = ns.ChatGroups_Dungeons()
	local width = c:GetWidth()
	local list = ns.ChatGroups_View(ns.ChatGroups_List(), db.kind, db.near, UnitLevel("player"), byKey)
	local now = time()
	local y = 0
	for i, entry in ipairs(list) do
		local row = Kit.PoolRow(rows, i, c)
		row.entry = entry
		row.onClick, row.onRightClick, row.onEnter = RowClick, RowRightClick, RowEnter
		row:Set(nil, ns.ChatGroups_Title(entry, byKey), "text",
			ns.Ago(now - entry.at), nil, ("%s  %s"):format(UI.ClassColored(entry.name, entry.class), entry.text))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
		row:SetWidth(width - 2 * PAD)
		y = y + Kit.ROW2_H
	end
	Kit.HideFrom(rows, #list + 1)
	page.empty:SetShown(#list == 0)
	page.list:SetContentHeight(y + PAD)
end

local function Create(frame)
	page = frame
	local db = ns.ChatGroups_DB()

	page.kinds = UI.Segmented(page)
	page.kinds:SetPoint("TOPLEFT", PAD, -PAD)
	page.kinds.choices = function()
		return KINDS
	end
	page.kinds.getValue = function()
		return db.kind
	end
	page.kinds.setValue = function(value)
		db.kind = value
		Layout()
	end
	page.kinds:Refresh()

	page.levels = UI.Segmented(page)
	page.levels:SetPoint("LEFT", page.kinds, "RIGHT", FILTER_GAP, 0)
	page.levels.choices = function()
		return LEVELS
	end
	page.levels.getValue = function()
		return db.near
	end
	page.levels.setValue = function(value)
		db.near = value
		Layout()
	end
	page.levels:Refresh()

	page.list = UI.Scroll(page)
	page.list:SetPoint("TOPLEFT", 0, -(PAD + TOP_H))
	page.list:SetPoint("BOTTOMRIGHT", -12, 0)
	c = page.list.content
	page.list.onWidthChanged = Layout

	page.empty = UI.Text(page, 13, "textMuted")
	page.empty:SetPoint("TOPLEFT", page.list, "TOPLEFT", PAD, -PAD)
	page.empty:SetPoint("RIGHT", page.list, "RIGHT", -PAD, 0)
	page.empty:SetJustifyH("LEFT")
	page.empty:SetWordWrap(true)
	page.empty:SetText("Nobody has asked yet. This fills up as people post in the chat channels you've joined, so join "
		.. "General or LookingForGroup. The game's own Looking For Group window lists groups too.")
end

-- From ChatGroups.lua when the list changed. Nothing is drawn while the page is closed.
function ns.ChatGroupsPage_Refresh()
	if page and page:IsVisible() then
		Layout()
	end
end

ns.ChatGroupsPage = {
	title = "Groups in chat",
	Create = Create,
	Refresh = Layout,
}
