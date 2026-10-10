local addonName, ns = ...

-- Alts on Tomte's Home ("characters" slot): every character with level, profession icons (unspent knowledge in
-- brackets) and gold, then the account's total gold (the Warband bank's included) and which of the eleven professions
-- somebody has (an unlit one's tooltip says who has a free slot for it).

local UI = ns.UI
local ROW_H = 24
local FOOT_H = 84

local PROFESSIONS = ns.ALTS_PROFESSIONS -- the eleven, with stand-in icons (Data.lua)

-- Numbers (level, gold, counts) in the number font.
local function Narrow(parent, size, role)
	return UI.Text(parent, size, role, "number")
end

local function ShowCharTooltip(row)
	local c = row.char
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(c.name or "?", 1, 1, 1)
	local tr, tg, tb = UI.Color("text")
	local mr, mg, mb = UI.Color("textMuted")
	GameTooltip:AddLine(("Level %d %s %s"):format(c.level or 0, c.race or "", c.spec or ""), tr, tg, tb)
	for _, prof in ipairs(ns.Alts_Profs(c)) do
		local line = ns.Alts_ProfText(prof)
		if prof.unspent and prof.unspent > 0 then
			line = line .. (", %d knowledge unspent"):format(prof.unspent)
		end
		GameTooltip:AddLine(line, tr, tg, tb)
	end
	local secondary = ns.Alts_SecondaryText(c)
	if secondary then
		GameTooltip:AddLine(secondary, mr, mg, mb, true)
	end
	if c.zone then
		GameTooltip:AddLine(c.zone, mr, mg, mb)
	end
	GameTooltip:Show()
end

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("hover"))
	row.bg:Hide()
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(UI.Color("rule"))
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT")
	row.line:SetPoint("BOTTOMRIGHT")
	row.name = UI.Text(row, 13, "text")
	row.name:SetPoint("LEFT")
	row.name:SetWidth(110)
	row.name:SetWordWrap(false)
	row.level = Narrow(row, 14, "textMuted")
	row.level:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
	row.level:SetWidth(26)
	row.level:SetJustifyH("RIGHT")
	row.gold = Narrow(row, 14, "heading")
	row.gold:SetPoint("RIGHT")
	row.gold:SetJustifyH("RIGHT")
	row.profs = {}
	for i = 1, 2 do
		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(16, 16)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local pill = Narrow(row, 12, "accent")
		row.profs[i] = { icon = icon, pill = pill }
	end
	row.none = UI.Text(row, 12, "textFaint")
	row.none:SetPoint("LEFT", row.level, "RIGHT", 18, 0)
	row.none:SetText("no professions")
	row:SetScript("OnEnter", function(self)
		self.bg:Show()
		ShowCharTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function()
		ns.Panel_OpenPage("alts")
	end)
	return row
end

local function SetRow(row, c)
	row.char = c
	local color = c.class and C_ClassColor.GetClassColor(c.class)
	row.name:SetText(c.name or "?")
	if color then
		row.name:SetTextColor(color.r, color.g, color.b)
	else
		UI.SetTextRole(row.name, "text")
	end
	row.level:SetText(c.level or "?")
	row.gold:SetText(ns.Alts_Gold(c.money))
	local profs = ns.Alts_Profs(c)
	local anchor, x = row.level, 18
	for i, p in ipairs(row.profs) do
		local prof = profs[i]
		p.icon:SetShown(prof ~= nil)
		p.pill:SetShown(prof ~= nil and (prof.unspent or 0) > 0)
		if prof then
			p.icon:SetTexture(prof.icon or 134400)
			p.icon:ClearAllPoints()
			p.icon:SetPoint("LEFT", anchor, "RIGHT", x, 0)
			anchor, x = p.icon, 6
			if (prof.unspent or 0) > 0 then
				p.pill:SetText(("[%d]"):format(prof.unspent))
				p.pill:ClearAllPoints()
				p.pill:SetPoint("LEFT", p.icon, "RIGHT", 3, 0)
				anchor, x = p.pill, 8
			end
		end
	end
	row.none:SetShown(#profs == 0)
end

local function Create(frame, Kit)
	frame.heading = Kit.Heading(frame)
	frame.heading:SetPoint("TOPLEFT")
	frame.heading:SetPoint("TOPRIGHT")
	frame.rows = {}

	local foot = CreateFrame("Frame", nil, frame)
	foot:SetPoint("BOTTOMLEFT")
	foot:SetPoint("BOTTOMRIGHT")
	foot:SetHeight(FOOT_H)
	foot.totalLabel = UI.Text(foot, 13, "textMuted")
	foot.totalLabel:SetPoint("TOPLEFT", 0, -8)
	foot.totalLabel:SetText("Total gold")
	foot.total = Narrow(foot, 16, "heading")
	foot.total:SetPoint("TOPRIGHT", 0, -6)
	foot.covLabel = UI.Text(foot, 13, "textMuted")
	foot.covLabel:SetPoint("TOPLEFT", 0, -34)
	foot.covLabel:SetText("Professions covered")
	foot.covCount = Narrow(foot, 16)
	foot.covCount:SetPoint("TOPRIGHT", 0, -32)
	foot.icons = {}
	for i, p in ipairs(PROFESSIONS) do
		local b = CreateFrame("Frame", nil, foot)
		b:SetSize(24, 24)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexture(p[3])
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		UI.Border(b, "frame", 0.6)
		b:EnableMouse(true)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(p[2], 1, 1, 1)
			if #self.who > 0 then
				local r, g, b = UI.Color("text")
				for _, line in ipairs(self.who) do
					GameTooltip:AddLine(line, r, g, b)
				end
			else
				-- Who could pick it up: characters with a free profession slot.
				local r, g, b = UI.Color("textMuted")
				GameTooltip:AddLine(ns.Alts_GapText({ p[2] }, ns.Alts_FreeSlots(ns.altsDB.chars)), r, g, b, true)
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		b.who = {}
		foot.icons[i] = b
	end
	frame.foot = foot
	frame.footH = FOOT_H -- Home puts Next up between the list and the footer
	frame.hint = UI.Text(frame, 12, "textMuted")
	frame.hint:SetPoint("RIGHT")
	frame.hint:SetWordWrap(true)
	frame.hint:SetText("Log in on your other characters once to add them here.")
end

local function Refresh(frame)
	local Kit = ns.HomeKit
	local db = ns.altsDB
	frame.heading:Set("Your characters", nil, "Open Alts", function()
		ns.Panel_OpenPage("alts")
	end)
	local list = ns.Alts_Roster(db.chars, "level", UnitGUID("player"))
	local room = math.max(math.floor((frame:GetHeight() - 40 - FOOT_H) / ROW_H), 1)
	local shown = math.min(#list, room)
	for i = 1, shown do
		local row = frame.rows[i]
		if not row then
			row = CreateRow(frame)
			frame.rows[i] = row
		end
		SetRow(row, list[i])
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(40 + (i - 1) * ROW_H))
		row:SetPoint("RIGHT")
		row:Show()
	end
	for i = shown + 1, #frame.rows do
		frame.rows[i]:Hide()
	end
	frame.hint:SetShown(#list <= 2)
	frame.hint:ClearAllPoints()
	frame.hint:SetPoint("TOPLEFT", 0, -(40 + shown * ROW_H + 12))
	frame.hint:SetPoint("RIGHT")

	local foot = frame.foot
	foot.total:SetText(ns.Alts_Gold(ns.Alts_TotalGold(db.chars, db.warbandMoney)))
	foot.totalLabel:SetText("Total gold" .. ns.Alts_WarbandText(db.warbandMoney))
	local covered = 0
	for i, p in ipairs(PROFESSIONS) do
		local b = foot.icons[i]
		wipe(b.who)
		for _, c in pairs(db.chars) do
			local prof = c.profs and c.profs[p[1]]
			if prof then
				b.who[#b.who + 1] = ("%s, %s"):format(c.name or "?", ns.Alts_ProfText(prof))
				if prof.icon then
					b.icon:SetTexture(prof.icon)
				end
			end
		end
		local has = #b.who > 0
		covered = covered + (has and 1 or 0)
		b.icon:SetDesaturated(not has)
		b.icon:SetAlpha(has and 1 or 0.35)
		UI.SetBorderColor(b, "frame", has and 0.6 or 0.1)
	end
	foot.covCount:SetText(("%d of %d"):format(covered, #PROFESSIONS))
	UI.SetTextRole(foot.covCount, covered == #PROFESSIONS and "accent" or "text")
	-- One row of icons under the label, as large as the column allows (up to 26 px).
	local step = math.max(math.min(math.floor((frame:GetWidth() + 4) / #PROFESSIONS), 30), 14)
	for i, b in ipairs(foot.icons) do
		b:SetSize(step - 4, step - 4)
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", (i - 1) * step, 2)
	end
	-- The height the heading, rows and hint use from the top (the footer sits at the bottom).
	local used = 40 + shown * ROW_H
	if frame.hint:IsShown() then
		used = used + 12 + frame.hint:GetStringHeight()
	end
	return used
end

ns.AltsHomeSection = { kind = "section", slot = "characters", key = "altssection", Create = Create, Refresh = Refresh }
