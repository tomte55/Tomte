local addonName, ns = ...

-- Alts page, Characters tab: every character Tomte has seen, current one first. Two views (toggle saved):
-- compact (one line, sortable columns, details in the row's tooltip) and detailed (two lines, sort dropdown; a third
-- with the Great Vault and Concentration for characters Weekly tracks). A pill after a profession is its unspent
-- knowledge. The footer's professions count says in its tooltip who has a free slot for the missing ones. Right-click
-- a row to forget that character.

local UI = ns.UI
local COMPACT_H, DETAILED_H, WEEKLY_H, HEAD_H, FOOT_H = 22, 42, 18, 22, 26

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
	return { UI.Color("text") }
end

-- c: a theme role or an { r, g, b } table (class colors).
local function SetColor(fs, c)
	fs:SetTextColor(UI.RGBA(c))
end

local function Pill(n)
	return n and n > 0 and (" " .. UI.Wrap(("[%d]"):format(n), "accent")) or ""
end

local function ProfsText(c, short)
	local parts = {}
	for _, prof in ipairs(ns.Alts_Profs(c)) do
		parts[#parts + 1] = ns.Alts_ProfText(prof, short) .. Pill(prof.unspent)
	end
	return #parts > 0 and table.concat(parts, short and "  " or " · ") or UI.Wrap("no professions", "textFaint")
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

-- Vault and Concentration from Weekly's snapshot of the character (max level ones it tracks), nil without.
local function WeeklyStatus(c)
	local wdb = ns.weeklyDB
	if not (ns.Weekly_Active and ns.Weekly_Active() and wdb and c.guid and ns.Weekly_View) then
		return nil
	end
	local snap = wdb.chars and wdb.chars[c.guid]
	if not snap or (wdb.hidden and wdb.hidden[c.guid]) then
		return nil
	end
	local now = GetServerTime()
	return ns.Alts_WeeklyStatus(ns.Weekly_View(snap, now), now)
end

local function ShowTooltip(row)
	local c = row.char
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local color = ClassColor(c)
	GameTooltip:SetText(c.name or "?", color[1], color[2], color[3])
	local tr, tg, tb = UI.Color("text")
	local mr, mg, mb = UI.Color("textMuted")
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
			line = line .. " " .. UI.Wrap("(recipes not read yet)", "textMuted")
		end
		GameTooltip:AddLine(line, tr, tg, tb)
	end
	local secondary = ns.Alts_SecondaryText(c)
	if secondary then
		GameTooltip:AddLine(secondary, mr, mg, mb, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(("%s · %s"):format(c.zone or "?", Ago(c)), mr, mg, mb)
	local rest = RestText(c)
	if rest then
		local r, g, b = UI.Color("success")
		GameTooltip:AddLine(rest, r, g, b)
	end
	local weekly = WeeklyStatus(c)
	if weekly then
		if weekly.vault then
			GameTooltip:AddLine(weekly.vault, 1, 1, 1)
		end
		for _, conc in ipairs(weekly.conc) do
			local text = ("%s Concentration %d/%d"):format(conc.name, conc.qty, conc.max)
			if conc.full then
				local r, g, b = UI.Color("warning")
				GameTooltip:AddLine(conc.name .. " Concentration full", r, g, b)
			else
				GameTooltip:AddLine(conc.text ~= "" and (text .. ", " .. conc.text) or text, 1, 1, 1)
			end
		end
	end
	local worth = ns.Value_CharWorth and ns.Value_CharWorth(c)
	if worth then
		local r, g, b = UI.Color("heading")
		GameTooltip:AddLine(("Carrying %s in bags%s"):format(ns.Alts_Gold(worth), c.worth.bank and " and bank" or ""), r, g, b)
	end
	if c.guid ~= UnitGUID("player") then
		local r, g, b = UI.Color("textFaint")
		GameTooltip:AddLine("Right-click to forget this character", r, g, b)
	end
	GameTooltip:Show()
end

-- Right-click menu: forget the character everywhere (Alts.lua), behind a confirm. Not the one being played.
local function RowMenu(owner, c)
	if not c.guid or c.guid == UnitGUID("player") then
		return
	end
	local name = ("%s-%s"):format(c.name or "?", c.realm or "?")
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(name)
		root:CreateButton("Forget " .. (c.name or "?"), function()
			local dialog = StaticPopup_Show("TOMTE_CONFIRM", ("Forget %s? Tomte drops everything it saved for this "
				.. "character (Alts, Weekly board, session history, stat weights, ...). Logging in on it adds it again.")
				:format(name))
			if dialog then
				local guid = c.guid
				dialog.data = function()
					ns.Alts_ForgetCharacter(guid)
				end
			end
		end)
	end)
end

local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:EnableMouse(true)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("hover"))
	row.bg:Hide()
	row.cells = {}
	for i, col in ipairs(COLUMNS) do
		local fs = UI.Text(row, 12, "text")
		fs:SetWordWrap(false)
		if col.right then
			fs:SetJustifyH("RIGHT")
		end
		row.cells[i] = fs
	end
	row.l1 = UI.Text(row, 13, "text")
	row.l1:SetPoint("TOPLEFT", 6, -5)
	row.l1:SetWordWrap(false)
	row.l1r = UI.Text(row, 13, "heading")
	row.l1r:SetPoint("TOPRIGHT", -6, -5)
	row.l1r:SetJustifyH("RIGHT")
	row.l1:SetPoint("RIGHT", row.l1r, "LEFT", -8, 0)
	row.l2 = UI.Text(row, 12, "textMuted")
	row.l2:SetWordWrap(false)
	row.l2r = UI.Text(row, 12, "textMuted")
	row.l2r:SetJustifyH("RIGHT")
	row.l3 = UI.Text(row, 12, "text")
	row.l3:SetPoint("BOTTOMLEFT", 6, 6)
	row.l3:SetPoint("BOTTOMRIGHT", -6, 6)
	row.l3:SetWordWrap(false)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(UI.Color("rule"))
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
	row:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and self.char then
			GameTooltip:Hide()
			RowMenu(self, self.char)
		end
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
		SetColor(fs, "text")
	end
	local cells = row.cells
	cells[1]:SetText(c.name or "?")
	SetColor(cells[1], ClassColor(c))
	cells[2]:SetText(c.level or "?")
	cells[3]:SetText(c.spec or "")
	cells[4]:SetText(c.ilvl or "")
	cells[5]:SetText(ProfsText(c, true))
	cells[6]:SetText(ns.Alts_Gold(c.money))
	SetColor(cells[6], "heading")
	cells[7]:SetText(Ago(c))
	SetColor(cells[7], "textMuted")
	for _, fs in ipairs({ row.l1, row.l1r, row.l2, row.l2r, row.l3 }) do
		fs:Hide()
	end
end

local function FillDetailed(row, c)
	local weekly = ns.Alts_WeeklyLine(WeeklyStatus(c), UI.Hex("warning"))
	local bottom = weekly ~= "" and (6 + WEEKLY_H) or 6
	row:SetHeight(DETAILED_H + (weekly ~= "" and WEEKLY_H or 0))
	row.l2:ClearAllPoints()
	row.l2:SetPoint("BOTTOMLEFT", 6, bottom)
	row.l2r:ClearAllPoints()
	row.l2r:SetPoint("BOTTOMRIGHT", -6, bottom)
	row.l2:SetPoint("RIGHT", row.l2r, "LEFT", -8, 0)
	row.l3:SetText(weekly)
	row.l3:SetShown(weekly ~= "")
	for _, fs in ipairs(row.cells) do
		fs:Hide()
	end
	local color = ClassColor(c)
	local nameText = ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, c.name or "?") -- class color
	local parts = { nameText, tostring(c.level or "?") .. (c.spec and (" " .. c.spec) or "") }
	if c.ilvl then
		parts[#parts + 1] = ("iLvl %d"):format(c.ilvl)
	end
	row.l1:SetText(table.concat(parts, " · "))
	local worth = ns.Value_CharWorth and ns.Value_CharWorth(c)
	row.l1r:SetText(ns.Alts_Gold(c.money) .. (worth and "  " .. UI.Wrap(("+ %s in items"):format(ns.Alts_Gold(worth)), "textMuted") or ""))
	row.l2:SetText(ProfsText(c, false))
	local right = { c.zone or "?", Ago(c) }
	local rest = RestText(c)
	if rest then
		right[#right + 1] = UI.Wrap(rest, "success")
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
		UI.SetTextRole(h.text, col.sort and col.sort == db.sort and "accent" or "textMuted")
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
	local uncovered = ns.Alts_Uncovered(db.chars)
	local nProfs = #ns.ALTS_PROFESSIONS
	tab.footLeft:SetText((#list == 1 and "1 character · log in on the others once to add them"
		or ("%d characters"):format(#list)) .. ("  ·  %d of %d professions"):format(nProfs - #uncovered, nProfs))
	tab.footHover:SetWidth(tab.footLeft:GetStringWidth())
	tab.footHover.uncovered = uncovered
	local worth = ns.Value_AccountWorth and ns.Value_AccountWorth(db.chars)
	tab.footRight:SetText("Total " .. ns.Alts_Gold(ns.Alts_TotalGold(db.chars, db.warbandMoney))
		.. ns.Alts_WarbandText(db.warbandMoney) .. (worth and ("  ·  items worth %s"):format(ns.Alts_Gold(worth)) or ""))
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
	line:SetColorTexture(UI.RGBA("frame", 0.2))
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	tab.head.cells = {}
	for i, col in ipairs(COLUMNS) do
		local b = CreateFrame("Button", nil, tab.head)
		b.text = UI.Text(b, 11, "textMuted")
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
	foot:SetColorTexture(UI.RGBA("frame", 0.2))
	foot:SetHeight(1)
	foot:SetPoint("BOTTOMLEFT", 0, FOOT_H)
	foot:SetPoint("BOTTOMRIGHT", -8, FOOT_H)
	tab.footLeft = UI.Text(tab, 12, "textMuted")
	tab.footLeft:SetPoint("BOTTOMLEFT", 6, 6)
	-- The footer's tooltip: which professions nobody has, and who has a free slot for them.
	tab.footHover = CreateFrame("Frame", nil, tab)
	tab.footHover:SetPoint("BOTTOMLEFT", 6, 4)
	tab.footHover:SetHeight(18)
	tab.footHover:EnableMouse(true)
	tab.footHover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Professions", 1, 1, 1)
		local r, g, b = UI.Color("text")
		if #self.uncovered == 0 then
			GameTooltip:AddLine("Somebody has each of the eleven.", r, g, b)
		else
			GameTooltip:AddLine(ns.Alts_GapText(self.uncovered, ns.Alts_FreeSlots(db.chars)), r, g, b, true)
		end
		GameTooltip:Show()
	end)
	tab.footHover:SetScript("OnLeave", GameTooltip_Hide)
	tab.footHover.uncovered = {}
	tab.footRight = UI.Text(tab, 12, "heading")
	tab.footRight:SetPoint("BOTTOMRIGHT", -14, 6)
end

function ns.AltsRoster_Refresh()
	if tab and tab:IsVisible() then
		Layout()
	end
end
