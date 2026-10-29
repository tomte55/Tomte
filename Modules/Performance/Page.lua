local addonName, ns = ...

-- Performance page in the Tomte window: how much of the frame Tomte takes (Blizzard's profiler), frame rate,
-- latency and memory tiles, Tomte's modules as a table from Tomte's own measuring (hover a row for its files and
-- events), recent hitches, startup and login per module, and every loaded addon. Redrawn every second while it
-- shows. Numbers from Read.lua and Core/Perf.lua, rules in Data.lua; registered in Performance.lua.

local PAD = 8
local GAP = 8
local TILE_H = 56
local ROW_H = 22
local COL_GAP = 6
local BUTTON_W = 96
local REFRESH_SECONDS = 1
local MODULE_COLUMNS = { 72, 72, 64, 44, 72 } -- now, session, peak, slow, memory made
local ADDON_COLUMNS = { 60, 60, 64, 72 } -- now, session, peak, memory
local LIST_SHOWN = 8 -- hitches, startup and login rows
local ADDONS_SHOWN = 15

local UI = ns.UI
local Kit = ns.HomeKit

local page, scroll, c
local ticker
local moduleRows, addonRows, hitchRows, startRows, loginRows = {}, {}, {}, {}, {}
local tiles = {}
local prev, rates, sampledAt = {}, {}, nil

-- Rows with columns -------------------------------------------------------------------------------------------

-- A row with a name on the left and right-aligned number columns (widths, left to right); a faint bar behind the
-- name shows its share. row:Set(name, nameRole, values, roles, share). header = true: small faint labels, no hover.
local function ColumnRow(parent, widths, header)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.colsWidth = 0
	row.bar = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.bar:SetPoint("TOPLEFT", 0, -2)
	row.bar:SetPoint("BOTTOMLEFT", 0, 2)
	row.bar:SetColorTexture(UI.RGBA("accent", 0.14))
	row.bar:Hide()
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(UI.Color("hover"))
	row.hover:Hide()
	row.cols = {}
	local anchor
	for i = #widths, 1, -1 do
		local fs = header and UI.Text(row, 11, "textFaint") or UI.Text(row, 12, "text", Kit.NARROW_FONT)
		fs:SetJustifyH("RIGHT")
		fs:SetWidth(widths[i])
		fs:SetWordWrap(false)
		if anchor then
			fs:SetPoint("RIGHT", anchor, "LEFT", -COL_GAP, 0)
		else
			fs:SetPoint("RIGHT", -6, 0)
		end
		anchor = fs
		row.cols[i] = fs
		row.colsWidth = row.colsWidth + widths[i] + COL_GAP
	end
	row.name = header and UI.Text(row, 11, "textFaint") or UI.Text(row, 13, "text")
	row.name:SetPoint("LEFT", 6, 0)
	row.name:SetPoint("RIGHT", anchor, "LEFT", -COL_GAP * 2, 0)
	row.name:SetWordWrap(false)
	local function Bar(self)
		local share = self.share or 0
		self.bar:SetShown(share > 0)
		self.bar:SetWidth(math.max((self:GetWidth() - self.colsWidth) * share, 1))
	end
	row:SetScript("OnSizeChanged", Bar)
	if header then
		row:EnableMouse(false)
	else
		row:SetScript("OnEnter", function(self)
			self.hover:Show()
			if self.onEnter then
				self.onEnter(self)
			end
		end)
		row:SetScript("OnLeave", function(self)
			self.hover:Hide()
			GameTooltip:Hide()
		end)
	end
	function row:Set(name, nameRole, values, roles, share)
		self.name:SetText(name or "")
		UI.SetTextRole(self.name, nameRole or (header and "textFaint" or "text"))
		for i, fs in ipairs(self.cols) do
			fs:SetText(values[i] or "")
			UI.SetTextRole(fs, roles and roles[i] or (header and "textFaint" or "text"))
		end
		self.share = share
		Bar(self)
	end
	return row
end

local function PoolColumnRow(pool, i, widths)
	local row = pool[i]
	if not row then
		row = ColumnRow(c, widths)
		pool[i] = row
	end
	row.onEnter = nil
	row:Show()
	return row
end

-- Tiles ---------------------------------------------------------------------------------------------------------

local function Tile()
	local t = CreateFrame("Frame", nil, c)
	t:SetHeight(TILE_H)
	UI.Surface(t)
	t.label = UI.Text(t, 11, "textMuted")
	t.label:SetPoint("TOPLEFT", 10, -8)
	t.value = UI.Text(t, 18, "text", Kit.NARROW_FONT)
	t.value:SetPoint("BOTTOMLEFT", 10, 9)
	t.note = UI.Text(t, 11, "textFaint")
	t.note:SetPoint("BOTTOMRIGHT", -10, 11)
	t.note:SetJustifyH("RIGHT")
	function t:Set(label, value, role, note)
		self.label:SetText(label)
		self.value:SetText(value)
		UI.SetTextRole(self.value, role or "text")
		self.note:SetText(note or "")
	end
	return t
end

-- Layout helpers --------------------------------------------------------------------------------------------------

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

local function Text(size, role, fontRole)
	local fs = UI.Text(c, size, role, fontRole)
	fs:SetWordWrap(true)
	fs:SetJustifyH("LEFT")
	return fs
end

-- Tooltips ---------------------------------------------------------------------------------------------------------

local function TipDouble(left, right, leftRole, rightRole)
	local r, g, b = UI.Color(leftRole or "text")
	local r2, g2, b2 = UI.Color(rightRole or "textMuted")
	GameTooltip:AddDoubleLine(left, right, r, g, b, r2, g2, b2)
end

local function ModuleTip(row, data)
	local stat = ns.Perf_Stats()[data.group]
	if not stat then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(data.name, UI.Color("heading"))
	UI.TipLine(("%s in %s calls"):format(ns.Perf_MsText(stat.total), ns.Thousands(stat.calls)), "text")
	if stat.peakWhat then
		UI.TipLine(("Longest call: %s (%s)"):format(ns.Perf_MsText(stat.peak),
			ns.Perf_PartText(data.group, stat.peakSub, stat.peakWhat)), "text")
	end
	if stat.slow > 0 then
		UI.TipLine(("%d calls of %d ms or more, %d of them %d ms or more"):format(stat.slow, ns.PERF_SLOW_MS,
			stat.hitches, ns.PERF_HITCH_MS), stat.hitches > 0 and "warning" or "textMuted")
	end
	if stat.login > 0 then
		UI.TipLine(("%s of it while logging in"):format(ns.Perf_MsText(stat.login)), "textMuted")
	end
	GameTooltip:AddLine(" ")
	UI.TipLine("Where the time goes", "heading")
	for _, p in ipairs(ns.Perf_TopParts(stat)) do
		TipDouble(ns.Perf_PartText(data.group, p.sub, p.what), ("%s · %s×"):format(ns.Perf_MsText(p.total),
			ns.Thousands(p.calls)))
	end
	GameTooltip:Show()
end

local function TextTip(row, title, lines)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, UI.Color("heading"))
	for _, line in ipairs(lines) do
		UI.TipLine(line, "textMuted", true)
	end
	GameTooltip:Show()
end

-- Build -------------------------------------------------------------------------------------------------------------

local function Build()
	scroll = UI.Scroll(page)
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -10, 0)
	c = scroll.content
	scroll.onWidthChanged = function()
		ns.PerfPage_Refresh()
	end
	c.headline = Text(20, "text", Kit.DISPLAY_FONT)
	c.sub = Text(12, "textMuted")
	c.copy = UI.Button(c, BUTTON_W, "Copy report")
	UI.FitButton(c.copy, BUTTON_W)
	c.copy:SetPoint("TOPRIGHT", -PAD, -PAD)
	c.copy:SetScript("OnClick", function()
		ns.Perf_ShowReport()
	end)
	c.reset = UI.Button(c, BUTTON_W, "Start over")
	UI.FitButton(c.reset, BUTTON_W)
	c.reset:SetPoint("RIGHT", c.copy, "LEFT", -6, 0)
	c.reset:SetScript("OnClick", function()
		ns.Perf_StartOver()
	end)
	c.reset:SetScript("OnEnter", function(self)
		TextTip(self, "Start over", { "Clears Tomte's numbers and measures from now, to see what one thing costs." })
	end)
	c.reset:SetScript("OnLeave", GameTooltip_Hide)
	for i = 1, 4 do
		tiles[i] = Tile()
	end
	c.modHead = Kit.Heading(c)
	c.sort = UI.Segmented(c)
	c.sort.choices = function()
		return ns.PERF_SORTS
	end
	c.sort.getValue = function()
		return ns.Perf_SortKey()
	end
	c.sort.setValue = function(value)
		ns.Perf_SetSortKey(value)
		ns.PerfPage_Refresh()
	end
	c.sort:Refresh()
	c.modCols = ColumnRow(c, MODULE_COLUMNS, true)
	c.modNone = Text(12, "textMuted")
	c.hitchHead = Kit.Heading(c)
	c.hitchNone = Text(12, "textMuted")
	c.startHead = Kit.Heading(c)
	c.loginHead = Kit.Heading(c)
	c.addonHead = Kit.Heading(c)
	c.addonCols = ColumnRow(c, ADDON_COLUMNS, true)
	c.addonNone = Text(12, "textMuted")
end

-- Render ------------------------------------------------------------------------------------------------------------

local function RenderTop(y, game, width)
	local t = game.tomte
	local share = ns.Perf_Percent(game.app.recent, game.overall.recent, t.recent)
	local role, word = ns.Perf_Verdict(share)
	local headline, sub = "The game's addon profiler is off", "Tomte's own numbers below still work."
	if game.profiler then
		local over = t.over or {}
		headline = ("Tomte takes %s of the frame: %s"):format(ns.Perf_PercentText(share), word)
		sub = ("Session %s, longest frame %s. Frames over 50 ms: %d."):format(
			ns.Perf_PercentText(ns.Perf_Percent(game.app.session, game.overall.session, t.session)),
			ns.Perf_MsText(t.peak), over[50] or 0)
	end
	-- Both lines stop short of the buttons on the right.
	for _, fs in ipairs({ c.headline, c.sub }) do
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", PAD, -y)
		fs:SetPoint("RIGHT", c.reset, "LEFT", -12, 0)
		fs:SetText(fs == c.headline and headline or sub)
		fs:Show()
		y = y + fs:GetStringHeight() + (fs == c.headline and 2 or 10)
	end
	UI.SetTextRole(c.headline, game.profiler and role or "textMuted")
	y = math.max(y, PAD + 24 + 10)

	local w = Kit.Snap((width - 2 * PAD - 3 * GAP) / 4)
	local since = ns.Perf_Since()
	local measured = 0
	for _, s in pairs(ns.Perf_Stats()) do
		measured = measured + s.kb
	end
	local made = since and measured / math.max(GetTime() - since, 1)
	local all = ns.Perf_Percent(game.app.recent, game.overall.recent, game.overall.recent)
	tiles[1]:Set("Frame rate", ("%d fps"):format(math.floor(game.fps + 0.5)))
	tiles[2]:Set("Latency", ("%d ms"):format(game.home or 0), nil, ("world %d ms"):format(game.world or 0))
	tiles[3]:Set("All addons", ns.Perf_PercentText(all), nil, "of the frame")
	tiles[4]:Set("Tomte memory", ns.Perf_KBText(t.mem), nil,
		made and made > 0 and ("makes %s/s"):format(ns.Perf_KBText(made)) or nil)
	for i, tile in ipairs(tiles) do
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", PAD + (i - 1) * (w + GAP), -y)
		tile:SetWidth(w)
		tile:Show()
	end
	return y + TILE_H + 18
end

local function CoverageText(game)
	local since, fromLoad, loadedAt = ns.Perf_Since()
	if not since then
		return nil
	end
	if not fromLoad then
		return ("since %s ago"):format(ns.Perf_DurationText(GetTime() - since))
	end
	local coverage = ns.Perf_Coverage(ns.Perf_MeasuredTotal(ns.Perf_Stats()), game.tomte.session, game.app.session,
		(GetTime() - loadedAt) * 1000)
	if not coverage then
		return nil
	end
	return ("measured: about %s of Tomte's time"):format(ns.Perf_PercentText(coverage))
end

local function RenderModules(y, game)
	c.modHead:Set("Tomte's modules", CoverageText(game))
	y = PlaceFrame(c.modHead, y, 30) + 6
	c.sort:ClearAllPoints()
	c.sort:SetPoint("TOPLEFT", PAD, -y)
	c.sort:Show()
	y = y + c.sort:GetHeight() + 6
	c.modCols:Set("Module", nil, { "Now", "Session", "Peak", "Slow", "Memory" })
	y = PlaceFrame(c.modCols, y, ROW_H)
	local rows = ns.Perf_ModuleRows(ns.Perf_Stats(), rates, ns.Perf_SortKey())
	for i, data in ipairs(rows) do
		local row = PoolColumnRow(moduleRows, i, MODULE_COLUMNS)
		row:Set(data.name, "text", {
			ns.Perf_RateText(data.now),
			ns.Perf_MsText(data.total),
			ns.Perf_MsText(data.peak),
			data.slow > 0 and tostring(data.slow) or "",
			ns.Perf_KBText(data.kb),
		}, {
			"text",
			"textMuted",
			data.peak >= ns.PERF_HITCH_MS and "warning" or "textMuted",
			data.hitches > 0 and "warning" or "textMuted",
			"textMuted",
		}, data.share)
		row.onEnter = function(self)
			ModuleTip(self, data)
		end
		y = PlaceFrame(row, y, ROW_H)
	end
	Kit.HideFrom(moduleRows, #rows + 1)
	if #rows == 0 then
		y = Place(c.modNone, y + 4, "Nothing measured yet. Play a little and it fills in.", 4)
	else
		c.modNone:Hide()
	end
	return y + 18
end

local function RenderHitches(y)
	local list = ns.Perf_Hitches()
	c.hitchHead:Set("Hitches", ("calls of %d ms or more"):format(ns.PERF_HITCH_MS))
	y = PlaceFrame(c.hitchHead, y, 30) + 4
	local now = GetTime()
	local shown = math.min(#list, LIST_SHOWN)
	for i = 1, shown do
		local h = list[i]
		local row = Kit.PoolRow(hitchRows, i, c)
		row:Set(nil, ("%s · %s  %s"):format(ns.Perf_GroupName(h.group), ns.Perf_PartText(h.group, h.sub, h.what),
			UI.Wrap(ns.Perf_DurationText(now - h.at) .. " ago", "textFaint")), "text", ns.Perf_MsText(h.ms),
			h.ms >= 50 and "danger" or "warning")
		y = PlaceFrame(row, y, Kit.ROW_H)
	end
	Kit.HideFrom(hitchRows, shown + 1)
	if shown == 0 then
		y = Place(c.hitchNone, y, "None. Tomte hasn't made a frame wait.", 4)
	else
		c.hitchNone:Hide()
	end
	return y + 18
end

local function RenderStartup(y)
	local rows, total = ns.Perf_StartupRows(ns.Perf_StartupTimes())
	c.startHead:Set("Startup", ("modules starting: %s"):format(ns.Perf_MsText(total)))
	y = PlaceFrame(c.startHead, y, 30) + 4
	local shown = math.min(#rows, LIST_SHOWN)
	for i = 1, shown do
		local module = ns.modulesByKey[rows[i].key]
		local row = Kit.PoolRow(startRows, i, c)
		row:Set(nil, module and module.name or rows[i].key, "text", ns.Perf_MsText(rows[i].ms), "textMuted")
		y = PlaceFrame(row, y, Kit.ROW_H)
	end
	Kit.HideFrom(startRows, shown + 1)
	y = y + 14
	local login, loginTotal = ns.Perf_LoginRows(ns.Perf_Stats())
	c.loginHead:Set("Logging in", ("first %d seconds in the world: %s"):format(ns.PERF_LOGIN_SECONDS,
		ns.Perf_MsText(loginTotal)))
	y = PlaceFrame(c.loginHead, y, 30) + 4
	shown = math.min(#login, LIST_SHOWN)
	for i = 1, shown do
		local row = Kit.PoolRow(loginRows, i, c)
		row:Set(nil, login[i].name, "text", ns.Perf_MsText(login[i].ms), "textMuted")
		y = PlaceFrame(row, y, Kit.ROW_H)
	end
	Kit.HideFrom(loginRows, shown + 1)
	return y + 18
end

local function RenderAddons(y, game)
	local rows = ns.Perf_AddonRows(game, game.addons)
	c.addonHead:Set("All addons", ("%d loaded, from the game's profiler"):format(#rows))
	y = PlaceFrame(c.addonHead, y, 30) + 4
	if not game.profiler then
		Kit.HideFrom(addonRows, 1)
		c.addonCols:Hide()
		return Place(c.addonNone, y, "The game's addon profiler is off.", 4) + 10
	end
	c.addonNone:Hide()
	c.addonCols:Set("Addon", nil, { "Now", "Session", "Peak", "Memory" })
	y = PlaceFrame(c.addonCols, y, ROW_H)
	local shown = math.min(#rows, ADDONS_SHOWN)
	local top = rows[1] and rows[1].recent or 0
	for i = 1, shown do
		local a = rows[i]
		local row = PoolColumnRow(addonRows, i, ADDON_COLUMNS)
		local mine = a.name == addonName
		row:Set(a.name, mine and "accent" or "text", {
			ns.Perf_PercentText(a.recent),
			ns.Perf_PercentText(a.session),
			ns.Perf_MsText(a.peak),
			ns.Perf_KBText(a.mem),
		}, { "text", "textMuted", "textMuted", "textMuted" }, top > 0 and (a.recent or 0) / top or 0)
		y = PlaceFrame(row, y, ROW_H)
	end
	Kit.HideFrom(addonRows, shown + 1)
	return y + 10
end

local function Render()
	if not (page and page:IsVisible()) then
		return
	end
	local now = GetTime()
	if sampledAt then
		ns.Perf_UpdateRates(ns.Perf_Stats(), prev, rates, now - sampledAt)
	else
		ns.Perf_UpdateRates(ns.Perf_Stats(), prev, {}, 1) -- the first sample only sets prev
	end
	sampledAt = now
	local game = ns.PerfRead_Game(true)
	local width = c:GetWidth()
	local y = PAD
	y = RenderTop(y, game, width)
	y = RenderModules(y, game)
	y = RenderHitches(y)
	y = RenderStartup(y)
	y = RenderAddons(y, game)
	scroll:SetContentHeight(y + PAD)
end

local function StartTicker()
	if not ticker then
		ticker = C_Timer.NewTicker(REFRESH_SECONDS, Render)
	end
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local refreshSoon = UI.Debounce(0.1, Render)

function ns.PerfPage_Refresh()
	if page and page:IsVisible() then
		refreshSoon()
	end
end

-- The live rates for the report, only while the page samples them (closed, they'd be stale).
function ns.PerfPage_Rates()
	return page and page:IsVisible() and rates or nil
end

-- After the totals were cleared: the live rates start over too.
function ns.PerfPage_StartOver()
	wipe(prev)
	wipe(rates)
	sampledAt = nil
	ns.PerfPage_Refresh()
end

ns.PerfPage = {
	title = "Performance",
	Create = function(frame)
		page = frame
		Build()
		-- The panel only runs Refresh the first time; this covers reopening the panel on this page.
		page:HookScript("OnShow", function()
			Render()
			StartTicker()
		end)
		page:HookScript("OnHide", StopTicker)
	end,
	Refresh = function()
		Render()
		StartTicker()
	end,
}
