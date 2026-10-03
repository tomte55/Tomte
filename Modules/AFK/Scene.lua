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
local Text, Spaced = ns.SceneText, ns.Spaced

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

local function Coins(copper)
	return C_CurrencyInfo.GetCoinTextureString(copper)
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
				line = "+" .. Coins(delta) .. " this session"
			elseif delta < 0 then
				line = "-" .. Coins(-delta) .. " this session"
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
	card.statTitle:SetText(title)
	card.statLine:SetText(line)
end

local function RefreshText()
	card.label:SetText(Spaced("Away for " .. ns.FormatTime(GetTime() - state.since)))
	card.title:SetText(GetZoneText() or "")
	local zone, sub = GetZoneText(), GetSubZoneText()
	card.subtitle:SetText((sub and sub ~= zone) and sub or "")
	card.clock:SetText(ClockNow())
	card.date:SetText(DateText())
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
	card.title = Text(card, 36, GOLD, ns.SCENE_TITLE_FONT)
	card.title:SetPoint("CENTER", letterbox.top, "CENTER", 0, 4)
	card.label = Text(card, 12, GREY)
	card.label:SetPoint("BOTTOM", card.title, "TOP", 0, 6)
	card.line = ns.SceneGoldLine(card, 300)
	card.line:SetPoint("TOPRIGHT", card.title, "BOTTOM", 0, -5)
	card.subtitle = Text(card, 14, GREY)
	card.subtitle:SetPoint("TOP", card.title, "BOTTOM", 0, -12)

	-- Bottom band, left: character.
	card.charName = Text(card, 19, GOLD)
	card.charName:SetPoint("BOTTOMLEFT", letterbox.bottom, "LEFT", PAD, 1)
	card.charInfo = Text(card, 13, GREY)
	card.charInfo:SetPoint("TOPLEFT", card.charName, "BOTTOMLEFT", 0, -4)

	-- Bottom band, center: clock over a hairline and the date.
	card.clock = Text(card, 28, { 1, 1, 1 })
	card.clock:SetPoint("BOTTOM", letterbox.bottom, "CENTER", 0, 8)
	local track = card:CreateTexture(nil, "OVERLAY")
	track:SetColorTexture(1, 1, 1, 0.16)
	track:SetSize(CLOCK_LINE, 1)
	track:SetPoint("TOP", card.clock, "BOTTOM", 0, -14)
	card.date = Text(card, 10, GREY)
	card.date:SetPoint("TOP", track, "BOTTOM", 0, -12)

	-- Bottom band, right: rotating session stats.
	local statsGroup = CreateFrame("Frame", nil, card)
	statsGroup:SetAllPoints(card)
	statsSwap = ns.NewSwap(statsGroup)
	card.statTitle = Text(statsGroup, 18, WHITE)
	card.statTitle:SetPoint("BOTTOMRIGHT", letterbox.bottom, "RIGHT", -PAD, 1)
	card.statLine = Text(statsGroup, 13, GREY)
	card.statLine:SetPoint("TOPRIGHT", card.statTitle, "BOTTOMRIGHT", 0, -4)

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
	list.header:SetPoint("TOPRIGHT", letterbox, "RIGHT", -WHISPER_PAD, WHISPER_TOP)
	list.header:SetText(Spaced("While you were away"))
	list.lineWidth = 300
	list.line = ns.SceneGoldLine(list, list.lineWidth)
	-- Ends under the header's right edge (the line fades out to both ends).
	list.line:SetPoint("TOPLEFT", list.header, "BOTTOMRIGHT", -list.lineWidth, -8)
	list.more = Text(list, 11, GREY)
	list.more:SetJustifyH("RIGHT")
	list:Hide()
end

function scene.Begin(s)
	state = s
	card:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
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
