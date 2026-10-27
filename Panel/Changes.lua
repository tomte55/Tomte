local addonName, ns = ...

-- What's new: after an update, the first login shows a small window with the new release's highlights (several when
-- versions were skipped), grouped New / Improved / Fixed, each line with its module's icon and name. "Don't show this
-- after updates" turns it off (Tomte window settings turn it back on); /tomte changes opens it any time. A fresh
-- install never gets it. Highlights and the rules for which releases show: Core/ChangesData.lua.

local W = 520
local PAD = 18
local MAX_LIST_H = 380 -- the list scrolls past this
local ICON = 22
local LINE_GAP = 10 -- between two lines
local GROUP_GAP = 14 -- above a group's heading
local FIRST_DELAY = 4 -- seconds after PLAYER_ENTERING_WORLD: the world settles, a login cinematic gets to start
local BUSY_RETRY = 5 -- seconds between tries while a cinematic or movie plays
local RELEASES = "https://github.com/tomte55/Tomte/releases/tag/v"
local GROUPS = {
	{ key = "new", name = "New", role = "accent" },
	{ key = "improved", name = "Improved", role = "info" },
	{ key = "fixed", name = "Fixed", role = "success" },
}

local UI = ns.UI

local frame, scroll
local rows = {} -- pooled: { kind = "version" | "group" | "line", ... }
local shownEntries

-- "2026-10-27" -> "27 October 2026".
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
	"November", "December" }
local function DateText(date)
	local y, m, d = tostring(date or ""):match("^(%d+)-(%d+)-(%d+)$")
	if not y then
		return date or ""
	end
	return ("%d %s %s"):format(tonumber(d), MONTHS[tonumber(m)] or m, y)
end

-- A line's module name and icon (from the module), or its label with Tomte's logo.
local function Who(line)
	local module = line.module and ns.modulesByKey[line.module]
	if module then
		return module.name, module.icon
	end
	return line.label or line.module or "Tomte", ns.ICON
end

-- Rows ---------------------------------------------------------------------------------------------------------------

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, scroll.content)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("TOPLEFT", 0, -1)
	row.who = UI.Text(row, 12, "heading", "title")
	row.who:SetPoint("TOPLEFT", ICON + 10, 0)
	row.text = UI.Text(row, 12, "text")
	row.text:SetPoint("TOPLEFT", row.who, "BOTTOMLEFT", 0, -2)
	row.text:SetWordWrap(true)
	row.heading = UI.Text(row, 13, "accent", "title")
	row.heading:SetPoint("TOPLEFT")
	row.date = UI.Text(row, 11, "textMuted")
	row.date:SetPoint("LEFT", row.heading, "RIGHT", 8, 0)
	row.rule = UI.Hairline(row, 100, 0.5)
	row.rule:SetPoint("LEFT", row.date, "RIGHT", 10, 0)
	row.rule:SetPoint("RIGHT")
	rows[i] = row
	return row
end

-- Lays the releases out in the list; returns its height.
local function Fill(entries)
	local width = W - 2 * PAD - 12
	local n, y = 0, 0
	local function Next(height)
		n = n + 1
		local row = Row(n)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.icon:Hide()
		row.who:Hide()
		row.text:Hide()
		row.heading:Hide()
		row.date:Hide()
		row.rule:Hide()
		row:Show()
		return row
	end
	for i, entry in ipairs(entries) do
		if #entries > 1 then
			-- Several releases: each gets its version as a heading.
			if i > 1 then
				y = y + GROUP_GAP
			end
			local row = Next()
			row.heading:SetText("Version " .. entry.version)
			UI.SetTextRole(row.heading, "heading")
			row.date:SetText(DateText(entry.date))
			row.heading:Show()
			row.date:Show()
			row.rule:Show()
			row:SetHeight(18)
			y = y + 18 + 4
		end
		for _, group in ipairs(GROUPS) do
			local lines = entry[group.key]
			if lines and #lines > 0 then
				y = y + (y > 0 and GROUP_GAP or 0)
				local head = Next()
				head.heading:SetText(group.name)
				UI.SetTextRole(head.heading, group.role)
				head.heading:Show()
				head:SetHeight(16)
				y = y + 16 + 6
				for _, line in ipairs(lines) do
					local row = Next()
					local name, icon = Who(line)
					row.icon:SetTexture(icon)
					row.icon:Show()
					row.who:SetText(name)
					row.who:Show()
					row.text:SetWidth(width - ICON - 10)
					row.text:SetText(line.text)
					row.text:Show()
					local h = math.max(ICON, row.who:GetStringHeight() + 2 + row.text:GetStringHeight())
					row:SetHeight(h)
					y = y + h + LINE_GAP
				end
			end
		end
	end
	for i = n + 1, #rows do
		rows[i]:Hide()
	end
	return y
end

-- The window ---------------------------------------------------------------------------------------------------------

local function Build()
	frame = UI.Dialog("TomteChanges", W, 300) -- Escape closes it
	frame.logo = frame:CreateTexture(nil, "ARTWORK")
	frame.logo:SetSize(40, 40)
	frame.logo:SetPoint("TOPLEFT", PAD, -PAD)
	frame.logo:SetTexture(ns.ICON)
	frame.title = UI.Text(frame, 18, "heading", "title")
	frame.title:SetPoint("TOPLEFT", frame.logo, "TOPRIGHT", 12, -2)
	frame.sub = UI.Text(frame, 12, "textMuted")
	frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
	local rule = UI.Hairline(frame, W - 2 * PAD, 0.6)
	rule:SetPoint("TOP", 0, -(PAD + 40 + 12))

	scroll = UI.Scroll(frame)
	scroll:SetPoint("TOPLEFT", PAD, -(PAD + 40 + 26))
	scroll:SetPoint("RIGHT", -PAD + 6, 0)

	frame.never = UI.Checkbox(frame)
	frame.never:SetPoint("BOTTOMLEFT", PAD, PAD + 4)
	frame.neverText = UI.Text(frame, 11, "textMuted")
	frame.neverText:SetPoint("LEFT", frame.never, "RIGHT", 6, 0)
	frame.neverText:SetText("Don't show this after updates")
	frame.never:HookScript("OnClick", function(self)
		ns.Window_SetWhatsNew(not self.checked)
	end)
	local close = UI.Button(frame, 90, "Got it")
	close:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	close:SetScript("OnClick", function()
		UI.Disappear(frame)
	end)
	local notes = UI.Button(frame, 100, "Full notes")
	notes:SetPoint("RIGHT", close, "LEFT", -8, 0)
	notes:SetScript("OnClick", function()
		local entry = shownEntries and shownEntries[1]
		ns.Dialog_Show({ title = "Full release notes", hint = "Copy the link (Ctrl+C) and open it in your browser.",
			text = RELEASES .. (entry and entry.version or ns.VERSION), readOnly = true })
	end)
	frame:HookScript("OnHide", function()
		ns.db.changes.seen = ns.VERSION -- closed any way: this version's changes count as seen
	end)
end

-- Shows entries (Core/ChangesData.lua's releases, newest first).
local function Show(entries)
	if not frame then
		Build()
	end
	shownEntries = entries
	local newest = entries[1]
	frame.title:SetText("What's new in Tomte " .. newest.version)
	if #entries > 1 then
		frame.sub:SetText(("%d updates since you last played, the newest from %s"):format(#entries,
			DateText(newest.date)))
	else
		frame.sub:SetText(DateText(newest.date))
	end
	frame.never:SetChecked(not ns.Window_WhatsNew())
	local contentH = Fill(entries)
	local listH = math.min(contentH, MAX_LIST_H)
	scroll:SetHeight(listH)
	scroll:SetContentHeight(contentH)
	scroll:SetScroll(0)
	frame:SetHeight(PAD + 40 + 26 + listH + 16 + 24 + PAD)
	UI.PlaceDialog(frame)
	frame:Show()
	UI.Appear(frame)
	local shown = {}
	for _, row in ipairs(rows) do
		if row:IsShown() then
			shown[#shown + 1] = row
		end
	end
	UI.EnterUpRows(shown)
end

-- /tomte changes and the settings button: the newest highlights Tomte has.
function ns.ChangesUI_Show()
	if ns.CHANGES[1] then
		Show({ ns.CHANGES[1] })
	end
end

-- After an update -----------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
events:RegisterEvent("PLAYER_ENTERING_WORLD")

local function Busy()
	return ns.AnyCinematicState() ~= nil
		or (CinematicFrame and CinematicFrame:IsShown())
		or (MovieFrame and MovieFrame:IsShown())
		or (TomteSetup and TomteSetup:IsShown()) -- the first-run picker goes first
end

local function TryShow()
	if not ns.db or (frame and frame:IsShown()) then
		return
	end
	local entries = ns.Changes_ToShow(ns.CHANGES, ns.db.changes.seen, ns.VERSION)
	if #entries == 0 or not ns.Window_WhatsNew() then
		ns.db.changes.seen = ns.VERSION -- turned off, or nothing to say: next time counts from here
		return
	end
	if InCombatLockdown() then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if Busy() then
		C_Timer.After(BUSY_RETRY, TryShow)
		return
	end
	Show(entries)
end

function events:PLAYER_ENTERING_WORLD()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	C_Timer.After(FIRST_DELAY, TryShow)
end

function events:PLAYER_REGEN_ENABLED()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	TryShow()
end
