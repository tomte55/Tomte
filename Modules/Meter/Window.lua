local addonName, ns = ...

-- DPS meter: the small window, and the same drawing for the settings preview. One thin line per place: the place, the
-- name in its class color and the damage per second, over a bar of its share of the top damage. The top few, then
-- your own line when you're further down. Rules in Data.lua, reads in Read.lua, shown and hidden by Meter.lua.

local ROW_GAP = 1
local PAD = 3
local RANK_W = 14
local MINE_GAP = 4 -- sets your own line off from the top lines above it
local MARK_W = 2 -- your line's accent edge
local NUMBER_GAP = 4 -- between the dimmer second number and the main one
-- The game's raid health fill, as the pet health bar uses (Modules/Combat/UnitBar.lua).
local BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"

local UI = ns.UI
local Theme = ns.Theme

-- Made-up places for Edit Mode and the settings preview (your own name and class read when drawn).
local function Sample()
	return {
		max = 100,
		mine = 5,
		sources = {
			{ name = "Aldric", classFilename = "WARRIOR", total = 100, perSecond = 1840 },
			{ name = "Kesha", classFilename = "MAGE", total = 86, perSecond = 1590 },
			{ name = "Mira", classFilename = "ROGUE", total = 71, perSecond = 1310 },
			{ name = "Brann", classFilename = "PRIEST", total = 30, perSecond = 560 },
			{ name = UnitName("player") or "You", classFilename = select(2, UnitClass("player")), total = 22,
				perSecond = 410, isLocalPlayer = true },
		},
	}
end

local function ClassRGB(classFilename)
	local color = classFilename and C_ClassColor.GetClassColor(classFilename)
	if color then
		return color:GetRGB()
	end
	return UI.Color("textMuted")
end

-- A name without its realm; a secret one (in combat) as it comes: it can't be cut.
local function ShortName(name)
	if ns.IsSecret(name) or type(name) ~= "string" then
		return name
	end
	return Ambiguate(name, "short")
end

local function SetFonts(row, size)
	Theme.SetFont(row.rank, "number", size - 1)
	Theme.SetFont(row.value, "number", size)
	Theme.SetFont(row.extra, "number", size - 1)
	Theme.SetFont(row.name, "body", size)
end

local function Row(f, i)
	local row = f.rows[i]
	if not row then
		row = CreateFrame("Frame", nil, f)
		row.bar = CreateFrame("StatusBar", nil, row)
		row.bar:SetAllPoints()
		row.bar:SetStatusBarTexture(BAR_TEXTURE)
		row.mark = row:CreateTexture(nil, "OVERLAY")
		row.mark:SetPoint("TOPLEFT")
		row.mark:SetPoint("BOTTOMLEFT")
		row.mark:SetWidth(MARK_W)
		local text = CreateFrame("Frame", nil, row) -- above the bar
		text:SetAllPoints()
		text:SetFrameLevel(row.bar:GetFrameLevel() + 1)
		row.rank = UI.Text(text, 10, "textFaint", "number")
		row.rank:SetPoint("LEFT", MARK_W + 2, 0)
		row.rank:SetWidth(RANK_W)
		row.rank:SetJustifyH("RIGHT")
		row.value = UI.Text(text, 11, "text", "number")
		row.value:SetPoint("RIGHT", -3, 0)
		row.value:SetJustifyH("RIGHT")
		row.extra = UI.Text(text, 10, "textMuted", "number")
		row.extra:SetPoint("RIGHT", row.value, "LEFT", -NUMBER_GAP, 0)
		row.extra:SetJustifyH("RIGHT")
		row.name = UI.Text(text, 11, "text")
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		f.rows[i] = row
	end
	if row.textSize ~= f.style.textSize then
		row.textSize = f.style.textSize
		SetFonts(row, row.textSize)
	end
	return row
end

-- A meter on parent. sample: the settings preview's copy.
function ns.MeterUI_New(parent, sample)
	local f = CreateFrame("Frame", nil, parent)
	f.sample = sample
	f.rows = {}
	f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	f.bg:SetAllPoints()
	if not sample then
		f:SetFrameStrata("LOW")
		f:SetClampedToScreen(true)
		f:SetMovable(true)
	end
	return f
end

-- Lays out one line: the place (when shown), the name, then the numbers from the right.
local function DrawRow(row, s, place, style, max)
	local r, g, b = ClassRGB(s.classFilename)
	local main, extra = ns.Meter_Numbers(style.number)
	row:SetHeight(style.rowHeight)
	row.rank:SetShown(style.ranks)
	row.rank:SetText(tostring(place))
	row.name:ClearAllPoints()
	if style.ranks then
		row.name:SetPoint("LEFT", row.rank, "RIGHT", 4, 0)
	else
		row.name:SetPoint("LEFT", MARK_W + 4, 0)
	end
	row.name:SetPoint("RIGHT", extra and row.extra or row.value, "LEFT", -4, 0)
	row.name:SetText(ShortName(s.name))
	if style.classNames then
		row.name:SetTextColor(r, g, b)
	else
		UI.SetTextRole(row.name, "text")
	end
	-- Secret in combat: AbbreviateLargeNumbers takes it, as Blizzard's own meter does (DamageMeterEntry.lua).
	row.value:SetText(AbbreviateLargeNumbers(s[main]))
	row.extra:SetShown(extra ~= nil)
	if extra then
		row.extra:SetText(AbbreviateLargeNumbers(s[extra]))
	end
	row.bar:SetMinMaxValues(0, max)
	row.bar:SetValue(s.total)
	if style.barColor == "theme" then
		row.bar:SetStatusBarColor(UI.Color("accent"))
	else
		row.bar:SetStatusBarColor(r, g, b)
	end
	row.bar:GetStatusBarTexture():SetAlpha(style.barAlpha)
	row.mark:SetColorTexture(UI.Color("accent"))
	row.mark:SetShown(s.isLocalPlayer == true)
end

-- Draws ranking (MeterRead_Ranking's shape) into f; nil draws the sample (Edit Mode and the settings preview), an
-- empty ranking no lines (a fight nobody has hit anything in yet). style: { lines, ranks, number, classNames,
-- barColor, barAlpha, background, bgAlpha, width, rowHeight, textSize } (the module's settings).
function ns.MeterUI_Draw(f, ranking, style)
	ranking = ranking or Sample()
	f.style = style
	f:SetWidth(style.width)
	local rows = ns.Meter_Rows(#ranking.sources, ranking.mine, style.lines)
	local y = PAD
	for n, place in ipairs(rows) do
		local row = Row(f, n)
		if place > style.lines then
			y = y + MINE_GAP
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD, -y)
		row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
		DrawRow(row, ranking.sources[place], place, style, ranking.max)
		row:Show()
		y = y + style.rowHeight + ROW_GAP
	end
	for n = #rows + 1, #f.rows do
		f.rows[n]:Hide()
	end
	f.bg:SetColorTexture(UI.Color("bg"))
	f.bg:SetAlpha(style.bgAlpha)
	f.bg:SetShown(style.background and #rows > 0)
	f:SetHeight(math.max(y - ROW_GAP + PAD, style.rowHeight))
end

-- The settings preview: the sample with the settings under the mouse.
function ns.MeterUI_Preview(host, style, scale)
	local f = host.meter
	if not f then
		f = ns.MeterUI_New(host, true)
		f:SetPoint("TOPLEFT")
		host.meter = f
	end
	ns.MeterUI_Draw(f, nil, style)
	f:SetScale(scale)
	return f:GetWidth() * scale, f:GetHeight() * scale
end
