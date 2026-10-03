local addonName, ns = ...

-- AFK scene for the cinematic engine:
-- top band = "Away for 12:34" over the zone and subzone,
-- bottom band = character (left), clock and date (center), rotating session stats (right),
-- right side of the screen = whispers received while away (mirrors the showcase on the left).

local GOLD, GREY, WHITE = ns.SCENE_GOLD, ns.SCENE_GREY, ns.SCENE_WHITE
local BN_COLOR = "ff82c5ff"
local PAD = 48 -- side padding inside the bottom band
local CLOCK_LINE = 300
local STATS_PAGE_TIME = 6
local REFRESH = 0.25 -- seconds between text refreshes (clock, away time, zone)
local WHISPER_ROWS = 5
local WHISPER_WIDTH = 400
local WHISPER_PAD = 80 -- from the right screen edge
local WHISPER_TOP = 150 -- list top, above the screen center
local SHADE_WIDTH = 620
local Text, Spaced, Place, SetText = ns.SceneText, ns.Spaced, ns.ScenePlace, ns.SceneSetText

local card, list
local state
local rows = {}
local statsSwap
local pages, page, pageTimer = {}, 1, 0
local sinceRefresh = 0

local function Clock(hour, minute)
	return ns.AFK_ClockText(hour, minute, C_CVar.GetCVarBool("timeMgrUseMilitaryTime"))
end

-- Follows the Blizzard clock's settings: 24h or 12h, local or realm time.
local function ClockNow()
	if C_CVar.GetCVarBool("timeMgrUseLocalTime") then
		local t = date("*t")
		return Clock(t.hour, t.min)
	end
	return Clock(GetGameTime())
end

local function DateText()
	local t = date("*t")
	return Spaced(("%s %d %s"):format(date("%A"), t.day, date("%B")))
end

local function CanShowXP()
	if GameRulesUtil and GameRulesUtil.CanShowExperienceBar then
		return GameRulesUtil.CanShowExperienceBar()
	end
	return UnitXPMax("player") > 0
end

local function XPFraction()
	local max = UnitXPMax("player")
	return max > 0 and UnitXP("player") / max or 0
end

local COIN_ICONS = {
	gold = "%s|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "%s|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "%s|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

local function Coins(copper, detailed)
	return ns.AFK_MoneyText(copper, detailed, COIN_ICONS)
end

local function BuildPages()
	local session = ns.afkDB.session
	pages = {
		function()
			return ns.FormatTime(GetServerTime() - session.start), "online this session"
		end,
		function()
			local money = GetMoney()
			local delta = money - session.money
			local line = "no change this session"
			if delta > 0 then
				line = "+" .. Coins(delta, true) .. " this session"
			elseif delta < 0 then
				line = "-" .. Coins(-delta, true) .. " this session"
			end
			return Coins(money), line
		end,
	}
	if CanShowXP() then
		pages[#pages + 1] = function()
			local level, fraction = UnitLevel("player"), XPFraction()
			local gain = ns.AFK_XPGain(session.level, session.xpFraction, level, fraction)
			return ("Level %d  -  %d%%"):format(level, math.floor(fraction * 100)), (gain or "no XP") .. " this session"
		end
	end
	page, pageTimer = 1, 0
end

local function ShowPage()
	local title, line = pages[page]()
	SetText(card.statTitle, title)
	SetText(card.statLine, line)
end

local function RefreshText()
	SetText(card.label, Spaced("Away for " .. ns.FormatTime(GetTime() - state.since)))
	local zone, sub = GetZoneText(), GetSubZoneText()
	SetText(card.title, zone)
	SetText(card.subtitle, (sub and sub ~= zone) and sub or "")
	SetText(card.clock, ClockNow())
	SetText(card.date, DateText())
	if page == 1 and not statsSwap.t then
		ShowPage() -- live online time
	end
end

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = {}
	row.meta = Text(list, 11, GREY)
	row.meta:SetJustifyH("RIGHT")
	row.body = Text(list, 13, WHITE)
	row.body:SetJustifyH("RIGHT")
	row.body:SetWidth(WHISPER_WIDTH)
	row.body:SetWordWrap(true)
	row.body:SetMaxLines(2)
	if i == 1 then
		row.meta:SetPoint("TOPRIGHT", list.header, "BOTTOMRIGHT", 0, -24)
	else
		row.meta:SetPoint("TOPRIGHT", rows[i - 1].body, "BOTTOMRIGHT", 0, -12)
	end
	row.body:SetPoint("TOPRIGHT", row.meta, "BOTTOMRIGHT", 0, -3)
	rows[i] = row
	return row
end

local function WhisperTime(at)
	local t = date("*t", at)
	return Clock(t.hour, t.min)
end

local function Sender(entry)
	if entry.bn then
		return "|c" .. BN_COLOR .. entry.sender .. "|r"
	end
	local color = entry.class and C_ClassColor.GetClassColor(entry.class)
	if color then
		return color:WrapTextInColorCode(entry.sender)
	end
	return "|cffffd173" .. entry.sender .. "|r"
end

-- Also called by the module when a whisper arrives while the scene is up.
function ns.AFKScene_RefreshWhispers()
	if not (list and state) then
		return
	end
	local shown, more = ns.AFK_VisibleWhispers(state.whispers, WHISPER_ROWS)
	local visible = ns.afkDB.whispers and #shown > 0
	list:SetShown(visible)
	for i, row in ipairs(rows) do
		row.meta:SetShown(visible and i <= #shown)
		row.body:SetShown(visible and i <= #shown)
	end
	if not visible then
		return
	end
	for i, entry in ipairs(shown) do
		local row = Row(i)
		row.meta:SetText(WhisperTime(entry.at) .. "   " .. Sender(entry))
		row.body:SetText(entry.text)
		row.meta:Show()
		row.body:Show()
	end
	list.more:ClearAllPoints()
	list.more:SetPoint("TOPRIGHT", rows[#shown].body, "BOTTOMRIGHT", 0, -12)
	list.more:SetText(more > 0 and ("+%d earlier"):format(more) or "")
end

local scene = {}
ns.AFKScene = scene

function scene.Create(parent, letterbox)
	card = CreateFrame("Frame", nil, parent)
	card:SetAllPoints(letterbox)
	card:SetFrameLevel(letterbox:GetFrameLevel() + 10) -- above the showcase shade
	card:SetAlpha(0)

	-- Top band: away time over the zone.
	-- Offsets from the band's center (font strings by their top edge, roughly font size tall).
	card.title = Text(card, 36, GOLD, ns.SCENE_TITLE_FONT)
	Place(card, card.title, "TOP", letterbox.top, "CENTER", 0, 22)
	card.label = Text(card, 12, GREY)
	Place(card, card.label, "TOP", letterbox.top, "CENTER", 0, 40)
	card.line = ns.SceneGoldLine(card, 300)
	Place(card, card.line, "TOPRIGHT", letterbox.top, "CENTER", 0, -19)
	card.subtitle = Text(card, 14, GREY)
	Place(card, card.subtitle, "TOP", letterbox.top, "CENTER", 0, -26)

	-- Bottom band, left: character.
	card.charName = Text(card, 19, GOLD)
	Place(card, card.charName, "TOPLEFT", letterbox.bottom, "LEFT", PAD, 20)
	card.charInfo = Text(card, 13, GREY)
	Place(card, card.charInfo, "TOPLEFT", letterbox.bottom, "LEFT", PAD, -3)

	-- Bottom band, center: clock over a hairline and the date.
	card.clock = Text(card, 28, { 1, 1, 1 })
	Place(card, card.clock, "TOP", letterbox.bottom, "CENTER", 0, 36)
	local track = card:CreateTexture(nil, "OVERLAY")
	track:SetColorTexture(1, 1, 1, 0.16)
	track:SetSize(CLOCK_LINE, 1)
	track.pixelHeight = 1
	Place(card, track, "TOP", letterbox.bottom, "CENTER", 0, -6)
	card.date = Text(card, 10, GREY)
	Place(card, card.date, "TOP", letterbox.bottom, "CENTER", 0, -19)

	-- Bottom band, right: rotating session stats.
	local statsGroup = CreateFrame("Frame", nil, card)
	statsGroup:SetAllPoints(card)
	statsSwap = ns.NewSwap(statsGroup)
	card.statTitle = Text(statsGroup, 18, WHITE)
	Place(card, card.statTitle, "TOPRIGHT", letterbox.bottom, "RIGHT", -PAD, 19)
	card.statLine = Text(statsGroup, 13, GREY)
	Place(card, card.statLine, "TOPRIGHT", letterbox.bottom, "RIGHT", -PAD, -3)

	-- Right side: whispers, on a gradient like the showcase's.
	list = CreateFrame("Frame", nil, card)
	list:SetAllPoints(card)
	local shade = list:CreateTexture(nil, "BACKGROUND", nil, -8)
	shade:SetColorTexture(1, 1, 1, 1)
	shade:SetPoint("TOPRIGHT", letterbox, "TOPRIGHT")
	shade:SetPoint("BOTTOMRIGHT", letterbox, "BOTTOMRIGHT")
	shade:SetWidth(SHADE_WIDTH)
	shade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.75))
	list.header = Text(list, 12, GOLD)
	Place(card, list.header, "TOPRIGHT", letterbox, "RIGHT", -WHISPER_PAD, WHISPER_TOP)
	list.header:SetText(Spaced("While you were away"))
	list.lineWidth = 300
	list.line = ns.SceneGoldLine(list, list.lineWidth)
	-- Ends under the header's right edge (the line fades out to both ends).
	Place(card, list.line, "TOPLEFT", letterbox, "RIGHT", -WHISPER_PAD - list.lineWidth, WHISPER_TOP - 20)
	list.more = Text(list, 11, GREY)
	list.more:SetJustifyH("RIGHT")
	list:Hide()
end

function scene.Begin(s)
	state = s
	card:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	ns.SceneSnap(card)
	ns.ResetSwap(statsSwap)

	local className, classFile = UnitClass("player")
	local color = C_ClassColor.GetClassColor(classFile)
	card.charName:SetText(UnitName("player"))
	if color then
		card.charName:SetTextColor(color:GetRGB())
	end
	local info = ("Level %d %s %s"):format(UnitLevel("player"), UnitRace("player"), className)
	local guild = IsInGuild() and GetGuildInfo("player")
	if guild then
		info = info .. "   -   <" .. guild .. ">"
	end
	card.charInfo:SetText(info)

	BuildPages()
	ShowPage()
	RefreshText()
	sinceRefresh = 0
	ns.AFKScene_RefreshWhispers()
end

-- Called every frame while the letterbox is visible.
function scene.Update(alpha, dt)
	card:SetAlpha(alpha)
	if not state or alpha <= 0 then
		return
	end
	sinceRefresh = sinceRefresh + dt
	if sinceRefresh >= REFRESH then
		sinceRefresh = 0
		RefreshText()
	end
	pageTimer = pageTimer + dt
	if pageTimer >= STATS_PAGE_TIME and #pages > 1 then
		pageTimer = 0
		ns.StartSwap(statsSwap, function()
			page = page % #pages + 1
			ShowPage()
		end)
	end
	ns.UpdateSwap(statsSwap, dt)
end
