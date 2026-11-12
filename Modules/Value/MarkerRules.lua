local addonName, ns = ...

-- Gold & value, item markers: the "How each marker is decided" window. Lists MarkerData.lua's rules in the order they're
-- tried, each with the marker it gives. Opened from Gold & value's settings and /tomte value markers.

local WIDTH, HEIGHT = 560, 600
local PAD = 18
local TITLE_TOP = 16
local ICON = 20 -- the marker beside a rule (drawn at the bags' size, scaled up)
local MARKER_SIZE = 14 -- MarkerArt.lua's widget
local ROW_GAP = 10
local TEXT_X = ICON + 10 -- a rule's text starts right of its marker
local TITLE_Y = 2 -- from a row's top to its title
local TEXT_GAP = 3 -- between a rule's title and its text
local DASH_W, DASH_H = 8, 2 -- the bar beside rules that give no marker

local UI = ns.UI

local dialog

local function Row(i)
	local row = dialog.rows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, dialog.scroll.content)
	row.title = UI.Text(row, 13, "heading", "label")
	row.title:SetPoint("TOPLEFT", TEXT_X, -TITLE_Y)
	row.title:SetJustifyH("LEFT")
	row.text = UI.Text(row, 12, "text")
	row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -TEXT_GAP)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(true)
	-- The marker sits level with the title's first line, whatever the font's line height.
	row.icon = CreateFrame("Frame", nil, row)
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("LEFT", row.title, "LEFT", -TEXT_X, 0)
	row.marker = ns.Value_MarkerWidget(row.icon)
	row.marker:SetScale(ICON / MARKER_SIZE)
	row.marker:SetPoint("CENTER")
	row.none = row.icon:CreateTexture(nil, "ARTWORK") -- a short bar for the rules that give no marker
	row.none:SetSize(DASH_W, DASH_H)
	row.none:SetPoint("CENTER")
	dialog.rows[i] = row
	return row
end

-- Each row's height from its texts, measured after their width is set (a wrapped rule is two or three lines).
local function Layout()
	local width = dialog.scroll:GetWidth()
	if width < 1 then
		return
	end
	local y = 0
	for i, rule in ipairs(ns.VALUE_MARKER_RULES) do
		local row = Row(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.title:SetWidth(width - TEXT_X)
		row.text:SetWidth(width - TEXT_X)
		row.title:SetText(("%d. %s"):format(i, rule.title))
		row.text:SetText(rule.text)
		row.marker:SetKind(rule.kind)
		row.none:SetColorTexture(UI.Color("textFaint"))
		row.none:SetShown(rule.kind == nil)
		local h = TITLE_Y + row.title:GetStringHeight() + TEXT_GAP + row.text:GetStringHeight()
		row:SetHeight(math.max(h, ICON))
		y = y + row:GetHeight() + ROW_GAP
	end
	dialog.scroll:SetContentHeight(y)
end

local function Build()
	dialog = UI.Dialog("TomteValueMarkerRules", WIDTH, HEIGHT) -- Escape closes it
	dialog.title = UI.Text(dialog, 16, "heading", "title")
	dialog.title:SetPoint("TOPLEFT", PAD, -TITLE_TOP)
	dialog.title:SetText("How each marker is decided")
	dialog.intro = UI.Text(dialog, 12, "textMuted")
	dialog.intro:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -8)
	dialog.intro:SetPoint("RIGHT", -PAD, 0)
	dialog.intro:SetJustifyH("LEFT")
	dialog.close = UI.Button(dialog, 80, "Close")
	dialog.close:SetPoint("BOTTOMRIGHT", -PAD, 14)
	dialog.close:SetScript("OnClick", function()
		dialog:Hide()
	end)
	dialog.summary = UI.Text(dialog, 11, "textMuted")
	dialog.summary:SetPoint("BOTTOMLEFT", PAD, 18)
	dialog.summary:SetPoint("RIGHT", dialog.close, "LEFT", -12, 0)
	dialog.summary:SetJustifyH("LEFT")
	dialog.scroll = UI.Scroll(dialog)
	dialog.scroll:SetPoint("TOPLEFT", dialog.intro, "BOTTOMLEFT", 0, -14)
	dialog.scroll:SetPoint("BOTTOMRIGHT", -PAD, 48)
	dialog.scroll.onWidthChanged = Layout
	dialog.rows = {}
end

-- limit: the player's limit, in copper.
function ns.ValueMarkerRules_Show(limit)
	if not dialog then
		Build()
	end
	UI.PlaceDialog(dialog)
	dialog.intro:SetText(("Everything you carry of one item is judged together, by these rules in this order. The "
		.. "first that fits decides. Your limit is %s. /tomte value why <item> says which rule decided an item.")
		:format(ns.Price(limit)))
	dialog.summary:SetText(ns.ValueMarkers_Summary())
	dialog:Show()
	Layout()
end
