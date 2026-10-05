local addonName, ns = ...

-- Alts page, Characters tab: every character Tomte has seen, current one first. Two views (toggle saved):
-- compact (one line, sortable columns, details in the row's tooltip) and detailed (two lines, sort dropdown).
-- A pill after a profession is its unspent knowledge.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local GREEN = { 0.45, 0.85, 0.45 }
local COMPACT_H, DETAILED_H, HEAD_H, FOOT_H = 22, 42, 22, 26

local tab, db
local rows = {}

-- Compact columns: x offset (fraction of width), header, sort key, right-aligned.
local COLUMNS = {
	{ x = 0, w = 0.17, text = "Name", sort = "name" },
	{ x = 0.17, w = 0.06, text = "Lvl", sort = "level", right = true },
	{ x = 0.25, w = 0.13, text = "Spec" },
	{ x = 0.38, w = 0.07, text = "iLvl", sort = "ilvl", right = true },
	{ x = 0.47, w = 0.31, text = "Professions" },
	{ x = 0.78, w = 0.12, text = "Gold", sort = "gold", right = true },
	{ x = 0.91, w = 0.09, text = "Last", sort = "seen", right = true },
}

local function ClassColor(c)
	local color = c.class and C_ClassColor.GetClassColor(c.class)
	if color then
		return { color.r, color.g, color.b }
	end
	return WHITE
end

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function Pill(n)
	return n and n > 0 and (" |cffffd100[%d]|r"):format(n) or ""
end

local function ProfsText(c, short)
	local parts = {}
	for _, prof in ipairs(ns.Alts_Profs(c)) do
		parts[#parts + 1] = ns.Alts_ProfText(prof, short) .. Pill(prof.unspent)
	end
	return #parts > 0 and table.concat(parts, short and "  " or " · ") or "|cff666666no professions|r"
end

local function Ago(c)
	if c.guid == UnitGUID("player") then
		return "now"
	end
	return c.seen and ns.Alts_Ago(GetServerTime() - c.seen) or "?"
end

local function RestText(c)
	return c.rested and c.rested > 0 and ("rested %d%%"):format(c.rested) or nil
end

local function ShowTooltip(row)
	local c = row.char
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(c.name or "?", unpack(ClassColor(c)))
	GameTooltip:AddLine(("Level %d %s %s"):format(c.level or 0, c.race or "", c.spec or ""), 1, 1, 1)
	if c.ilvl then
		GameTooltip:AddLine(("Item level %d"):format(c.ilvl), 1, 1, 1)
	end
	for _, prof in ipairs(ns.Alts_Profs(c)) do
		local line = ns.Alts_ProfText(prof)
		if prof.unspent and prof.unspent > 0 then
			line = line .. (" · %d knowledge unspent"):format(prof.unspent)
		end
		if not prof.scannedAt then
			line = line .. " |cff9e9e9e(recipes not read yet)|r"
		end
		GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
	end
	local secondary = ns.Alts_SecondaryText(c)
	if secondary then
		GameTooltip:AddLine(secondary, 0.62, 0.62, 0.62, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(("%s · %s"):format(c.zone or "?", Ago(c)), 0.62, 0.62, 0.62)
	local rest = RestText(c)
	if rest then
		GameTooltip:AddLine(rest, GREEN[1], GREEN[2], GREEN[3])
	end
	GameTooltip:Show()
end

local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:EnableMouse(true)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, 0.05)
	row.bg:Hide()
	row.cells = {}
	for i, col in ipairs(COLUMNS) do
		local fs = UI.Text(row, 12, WHITE)
		fs:SetWordWrap(false)
		if col.right then
			fs:SetJustifyH("RIGHT")
		end
		row.cells[i] = fs
	end
	row.l1 = UI.Text(row, 13, WHITE)
	row.l1:SetPoint("TOPLEFT", 6, -5)
	row.l1:SetWordWrap(false)
	row.l1r = UI.Text(row, 13, GOLD)
	row.l1r:SetPoint("TOPRIGHT", -6, -5)
	row.l1r:SetJustifyH("RIGHT")
	row.l1:SetPoint("RIGHT", row.l1r, "LEFT", -8, 0)
	row.l2 = UI.Text(row, 12, GREY)
	row.l2:SetPoint("BOTTOMLEFT", 6, 6)
	row.l2:SetWordWrap(false)
	row.l2r = UI.Text(row, 12, GREY)
	row.l2r:SetPoint("BOTTOMRIGHT", -6, 6)
	row.l2r:SetJustifyH("RIGHT")
	row.l2:SetPoint("RIGHT", row.l2r, "LEFT", -8, 0)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(1, 1, 1, 0.06)
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT")
	row.line:SetPoint("BOTTOMRIGHT")
	row:SetScript("OnEnter", function(self)
		self.bg:Show()
		ShowTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:Hide()
		GameTooltip:Hide()
	end)
	return row
end

local function FillCompact(row, c, width)
	row:SetHeight(COMPACT_H)
	for i, col in ipairs(COLUMNS) do
		local fs = row.cells[i]
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", math.floor(col.x * width) + 6, 0)
		fs:SetWidth(math.floor(col.w * width) - 6)
		fs:Show()
		SetColor(fs, WHITE)
	end
	local cells = row.cells
	cells[1]:SetText(c.name or "?")
	SetColor(cells[1], ClassColor(c))
	cells[2]:SetText(c.level or "?")
	cells[3]:SetText(c.spec or "")
	cells[4]:SetText(c.ilvl or "")
	cells[5]:SetText(ProfsText(c, true))
	cells[6]:SetText(ns.Alts_Gold(c.money))
	SetColor(cells[6], GOLD)
	cells[7]:SetText(Ago(c))
	SetColor(cells[7], GREY)
	for _, fs in ipairs({ row.l1, row.l1r, row.l2, row.l2r }) do
		fs:Hide()
	end
end

local function FillDetailed(row, c)
	row:SetHeight(DETAILED_H)
	for _, fs in ipairs(row.cells) do
		fs:Hide()
	end
	local color = ClassColor(c)
	local nameText = ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, c.name or "?")
	local parts = { nameText, tostring(c.level or "?") .. (c.spec and (" " .. c.spec) or "") }
	if c.ilvl then
		parts[#parts + 1] = ("iLvl %d"):format(c.ilvl)
	end
	row.l1:SetText(table.concat(parts, " · "))
	row.l1r:SetText(ns.Alts_Gold(c.money))
	row.l2:SetText(ProfsText(c, false))
	local right = { c.zone or "?", Ago(c) }
	local rest = RestText(c)
	if rest then
		right[#right + 1] = "|cff73d973" .. rest .. "|r"
	end
	row.l2r:SetText(table.concat(right, " · "))
	for _, fs in ipairs({ row.l1, row.l1r, row.l2, row.l2r }) do
		fs:Show()
	end
end

local function Layout()
	local compact = db.roster ~= "detailed"
	local list = ns.Alts_Roster(db.chars, db.sort, UnitGUID("player"))
	tab.head:SetShown(compact)
	tab.scroll:ClearAllPoints()
	tab.scroll:SetPoint("TOPLEFT", 0, compact and -(HEAD_H + 34) or -34)
	tab.scroll:SetPoint("BOTTOMRIGHT", -8, FOOT_H + 4)
	local width = math.max(tab.scroll:GetWidth(), 300) -- the scroll may not be sized yet on the first layout
	for i, col in ipairs(COLUMNS) do
		local h = tab.head.cells[i]
		h:ClearAllPoints()
		h:SetPoint("LEFT", math.floor(col.x * width) + 6, 0)
		h:SetSize(math.floor(col.w * width) - 6, HEAD_H)
		local c = col.sort and col.sort == db.sort and GOLD or GREY
		h.text:SetTextColor(c[1], c[2], c[3])
		h.text:SetJustifyH(col.right and "RIGHT" or "LEFT")
	end
	local y = 0
	for i, c in ipairs(list) do
		local row = rows[i] or CreateRow(tab.scroll.content)
		rows[i] = row
		row.char = c
		if compact then
			FillCompact(row, c, width)
		else
			FillDetailed(row, c)
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT")
		row:Show()
		y = y + row:GetHeight()
	end
	for i = #list + 1, #rows do
		rows[i]:Hide()
	end
	tab.scroll:SetContentHeight(y)
	tab.footLeft:SetText(#list == 1 and "1 character · log in on the others once to add them"
		or ("%d characters"):format(#list))
	tab.footRight:SetText("Total " .. ns.Alts_Gold(ns.Alts_TotalGold(db.chars)))
	tab.mode.label:SetText(compact and "Detailed view" or "Compact view")
	tab.sort:Refresh()
end

function ns.AltsRoster_Create(frame, altsDB)
	tab, db = frame, altsDB
	-- Toolbar: view toggle and sort.
	tab.mode = UI.Button(tab, 110, "")
	tab.mode:SetPoint("TOPRIGHT", -8, -4)
	tab.mode:SetScript("OnClick", function()
		db.roster = db.roster == "detailed" and "compact" or "detailed"
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Layout()
	end)
	tab.sort = UI.Dropdown(tab, 130)
	tab.sort:SetPoint("RIGHT", tab.mode, "LEFT", -8, 0)
	tab.sort.getValue = function()
		return db.sort
	end
	tab.sort.setValue = function(value)
		db.sort = value
		Layout()
	end
	tab.sort.choices = function()
		local list = {}
		for _, s in ipairs(ns.ALTS_SORTS) do
			list[#list + 1] = { value = s.key, text = "Sort: " .. s.text }
		end
		return list
	end

	-- Column headers (compact view); a click sorts by that column.
	tab.head = CreateFrame("Frame", nil, tab)
	tab.head:SetPoint("TOPLEFT", 0, -34)
	tab.head:SetPoint("RIGHT", -8, 0)
	tab.head:SetHeight(HEAD_H)
	local line = tab.head:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	tab.head.cells = {}
	for i, col in ipairs(COLUMNS) do
		local b = CreateFrame("Button", nil, tab.head)
		b.text = UI.Text(b, 11, GREY)
		b.text:SetAllPoints()
		b.text:SetText(col.text)
		if col.sort then
			b:SetScript("OnClick", function()
				db.sort = col.sort
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Layout()
			end)
		end
		tab.head.cells[i] = b
	end

	tab.scroll = UI.Scroll(tab)
	tab.scroll:SetPoint("TOPLEFT", 0, -(HEAD_H + 34))
	tab.scroll:SetPoint("BOTTOMRIGHT", -8, FOOT_H + 4)
	tab.scroll.onWidthChanged = function()
		if tab:IsVisible() then
			Layout()
		end
	end

	local foot = tab:CreateTexture(nil, "ARTWORK")
	foot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
	foot:SetHeight(1)
	foot:SetPoint("BOTTOMLEFT", 0, FOOT_H)
	foot:SetPoint("BOTTOMRIGHT", -8, FOOT_H)
	tab.footLeft = UI.Text(tab, 12, GREY)
	tab.footLeft:SetPoint("BOTTOMLEFT", 6, 6)
	tab.footRight = UI.Text(tab, 12, GOLD)
	tab.footRight:SetPoint("BOTTOMRIGHT", -14, 6)
end

function ns.AltsRoster_Refresh()
	if tab and tab:IsVisible() then
		Layout()
	end
end
