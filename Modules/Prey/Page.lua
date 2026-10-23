local addonName, ns = ...

-- Prey page in the Tomte window: the active hunt (target, zone, how hot the trail is, a waypoint button), the
-- journey rank, this week's hunts per difficulty with the chests left, and the achievement collection. Reads
-- ns.PreyRead_State (Read.lua) each time it draws; registered in Prey.lua.

local PAD = 8
local BUTTON_W = 130
local TARGET_ICON = 132212 -- ability_hunter_snipershot
local CHEST_ICON = "Interface\\Icons\\INV_Misc_Treasurechest02b"
local ACHIEVEMENT_ICON = 236544 -- achievement_general
-- The hunt icon's look per Enum.PreyHuntProgressState (Blizzard_UIWidgetTemplatePreyHuntProgress's atlases).
local STATE_ATLAS = { [0] = "ui-prey-targeticon-regular", [1] = "ui-prey-targeticon-inprogress",
	[2] = "ui-prey-targeticon-final", [3] = "ui-prey-targeticon-final" }
local STATE_ROLES = { [0] = "textMuted", [1] = "warning", [2] = "danger", [3] = "success" }

local UI = ns.UI
local Kit = ns.HomeKit

local page, scroll, c
local weekRows, collRows = {}, {}

local function Text(size, role)
	local fs = UI.Text(c, size, role)
	fs:SetWordWrap(true)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Place(fs, y, text, gap, x)
	if not text or text == "" then
		fs:Hide()
		return y
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", x or PAD, -y)
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

local function Build()
	scroll = UI.Scroll(page)
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -10, 0)
	c = scroll.content
	scroll.onWidthChanged = function()
		ns.PreyPage_Refresh()
	end
	c.huntHead = Kit.Heading(c)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(40, 40)
	c.target = Text(16, "text")
	c.zone = Text(12, "textMuted")
	c.state = Text(13, "text")
	c.tip = Text(12, "textMuted")
	c.none = Text(13, "textMuted")
	c.way = UI.Button(c, BUTTON_W, "Set waypoint")
	c.way:SetHeight(24)
	c.way:SetScript("OnClick", function()
		ns.Prey_SetWaypoint()
	end)
	c.weekHead = Kit.Heading(c)
	c.collHead = Kit.Heading(c)
	c.noData = Text(13, "textMuted")
end

local function RenderHunt(y, s)
	local a = s.active
	c.huntHead:Set("Current hunt", a and a.mapName or nil)
	y = PlaceFrame(c.huntHead, y, 30) + 8
	local shown = a ~= nil
	c.icon:SetShown(shown)
	c.way:SetShown(shown)
	if not a then
		c.target:Hide()
		c.zone:Hide()
		c.state:Hide()
		c.tip:Hide()
		return Place(c.none, y, "No hunt active. Pick a target at the Hunt Table in Silvermoon.", 4) + 14
	end
	c.none:Hide()
	local atlas = a.state and STATE_ATLAS[a.state]
	if atlas and C_Texture.GetAtlasInfo(atlas) then
		c.icon:SetAtlas(atlas)
	else
		c.icon:SetTexture(TARGET_ICON)
		c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	c.icon:ClearAllPoints()
	c.icon:SetPoint("TOPLEFT", PAD, -y)
	local x = PAD + 50
	local top = y
	y = Place(c.target, y, a.title or "Prey", 2, x)
	y = Place(c.zone, y, a.mapName, 4, x)
	local stateText = ns.Prey_StateName(a.state)
	if a.ready then
		stateText = "Done: turn it in"
	end
	if stateText then
		UI.SetTextRole(c.state, a.ready and "success" or (STATE_ROLES[a.state] or "text"))
	end
	y = Place(c.state, y, stateText, 4, x)
	y = math.max(y, top + 44)
	y = Place(c.tip, y, a.tip, 6)
	c.way:ClearAllPoints()
	c.way:SetPoint("TOPLEFT", PAD, -y)
	return y + 24 + 18
end

local function RenderWeek(y, s)
	local rankText
	if s.rank then
		rankText = ("%s rank %d"):format(s.journeyName or "Journey", s.rank)
	end
	c.weekHead:Set("This week", rankText)
	y = PlaceFrame(c.weekHead, y, 30) + 4
	for i, row in ipairs(s.week) do
		local r = Kit.PoolRow(weekRows, i, c)
		local full = row.done >= row.max
		r:Set(CHEST_ICON, row.name, full and "textMuted" or "text", ns.Prey_WeekText(row),
			full and "success" or (row.chestsLeft > 0 and "accent" or "textMuted"))
		y = PlaceFrame(r, y, Kit.ROW_H)
	end
	Kit.HideFrom(weekRows, #s.week + 1)
	return y + 14
end

local function RenderCollection(y, s)
	local done, total = 0, 0
	for _, row in ipairs(s.collection) do
		done, total = done + row.done, total + row.total
	end
	c.collHead:Set("Targets defeated", ("%d/%d"):format(done, total))
	y = PlaceFrame(c.collHead, y, 30) + 4
	for i, row in ipairs(s.collection) do
		local r = Kit.PoolRow(collRows, i, c)
		local complete = row.done >= row.total
		r:Set(ACHIEVEMENT_ICON, row.name, "text", ("%d/%d"):format(row.done, row.total), complete and "success" or "textMuted")
		local achievement = row.achievement
		r.onEnter = function(self)
			local link = GetAchievementLink(achievement)
			if link then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink(link)
				GameTooltip:Show()
			end
		end
		y = PlaceFrame(r, y, Kit.ROW_H)
	end
	Kit.HideFrom(collRows, #s.collection + 1)
	return y + 10
end

local function Render()
	if not (page and page:IsVisible()) then
		return
	end
	local s = ns.PreyRead_State()
	local y = PAD
	if not s.def then
		c.huntHead:Hide()
		c.icon:Hide()
		c.way:Hide()
		for _, fs in ipairs({ c.target, c.zone, c.state, c.tip, c.none }) do
			fs:Hide()
		end
		c.weekHead:Hide()
		c.collHead:Hide()
		Kit.HideFrom(weekRows, 1)
		Kit.HideFrom(collRows, 1)
		y = Place(c.noData, y, ("Prey hunts are Midnight content; this character is in %s."):format(
			ns.ExpansionName(ns.ContentExpansion())), 4)
		scroll:SetContentHeight(y + PAD)
		return
	end
	c.noData:Hide()
	y = RenderHunt(y, s)
	y = RenderWeek(y, s)
	y = RenderCollection(y, s)
	scroll:SetContentHeight(y + PAD)
end

local refreshSoon = UI.Debounce(0.3, Render)

function ns.PreyPage_Refresh()
	if page and page:IsVisible() then
		refreshSoon()
	end
end

ns.PreyPage = {
	title = "Prey",
	Create = function(frame)
		page = frame
		Build()
		-- The panel only runs Refresh the first time; this covers reopening the panel on this page.
		page:HookScript("OnShow", Render)
	end,
	Refresh = function()
		Render()
	end,
}
