local addonName, ns = ...

-- DPS meter: the small window, and the same drawing for the settings preview. One thin line per place: the place, the
-- name in its class color and the damage per second, over a bar of its share of the top damage. The top few, then
-- your own line when you're further down. Rules in Data.lua, reads in Read.lua, shown and hidden by Meter.lua.

local WIDTH = 170
local ROW_H = 15
local ROW_GAP = 1
local PAD = 3
local RANK_W = 14
local MINE_GAP = 4 -- sets your own line off from the top lines above it
local BAR_ALPHA = 0.4 -- the bars sit behind the text, so they stay a tint
local MARK_W = 2 -- your line's accent edge
-- The game's raid health fill, as the pet health bar uses (Modules/Combat/UnitBar.lua).
local BAR_TEXTURE = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"

local UI = ns.UI

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

local function Row(f, i)
	local row = f.rows[i]
	if not row then
		row = CreateFrame("Frame", nil, f)
		row:SetHeight(ROW_H)
		row.bar = CreateFrame("StatusBar", nil, row)
		row.bar:SetAllPoints()
		row.bar:SetStatusBarTexture(BAR_TEXTURE)
		row.bar:GetStatusBarTexture():SetAlpha(BAR_ALPHA)
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
		row.name = UI.Text(text, 11, "text")
		row.name:SetPoint("LEFT", row.rank, "RIGHT", 4, 0)
		row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		f.rows[i] = row
	end
	return row
end

-- A meter on parent. sample: the settings preview's copy.
function ns.MeterUI_New(parent, sample)
	local f = CreateFrame("Frame", nil, parent)
	f.sample = sample
	f:SetSize(WIDTH, ROW_H)
	f.rows = {}
	if not sample then
		f:SetFrameStrata("LOW")
		f:SetClampedToScreen(true)
		f:SetMovable(true)
	end
	return f
end

-- Draws ranking (MeterRead_Ranking's shape) into f with `lines` top places; an empty ranking draws the sample.
function ns.MeterUI_Draw(f, ranking, lines)
	if not ranking or #ranking.sources == 0 then
		ranking = Sample()
	end
	local rows = ns.Meter_Rows(#ranking.sources, ranking.mine, lines)
	local y = PAD
	for n, place in ipairs(rows) do
		local s = ranking.sources[place]
		local row = Row(f, n)
		if place > lines then
			y = y + MINE_GAP
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD, -y)
		row:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
		local r, g, b = ClassRGB(s.classFilename)
		row.rank:SetText(tostring(place))
		row.name:SetText(ShortName(s.name))
		row.name:SetTextColor(r, g, b)
		-- Secret in combat: AbbreviateLargeNumbers takes it, as Blizzard's own meter does (DamageMeterEntry.lua).
		row.value:SetText(AbbreviateLargeNumbers(s.perSecond))
		row.bar:SetMinMaxValues(0, ranking.max)
		row.bar:SetValue(s.total)
		row.bar:SetStatusBarColor(r, g, b)
		row.mark:SetColorTexture(UI.Color("accent"))
		row.mark:SetShown(s.isLocalPlayer == true)
		row:Show()
		y = y + ROW_H + ROW_GAP
	end
	for n = #rows + 1, #f.rows do
		f.rows[n]:Hide()
	end
	f:SetHeight(math.max(y - ROW_GAP + PAD, ROW_H))
end

-- The settings preview: the sample at the size and lines under the mouse.
function ns.MeterUI_Preview(host, lines, scale)
	local f = host.meter
	if not f then
		f = ns.MeterUI_New(host, true)
		f:SetPoint("TOPLEFT")
		host.meter = f
	end
	ns.MeterUI_Draw(f, nil, lines)
	f:SetScale(scale)
	return f:GetWidth() * scale, f:GetHeight() * scale
end
