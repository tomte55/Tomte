local addonName, ns = ...

-- Session recap card for the cinematic engine (always passthrough: any key or click ends it):
-- top band = label ("Session recap", "Last session") over the time played and the time range,
-- under it, during a logout = a countdown (Blizzard's popup timer) with a draining bar,
-- right side = the session's highlights (mirrors the showcase on the left),
-- bottom band = character (left), net gold and where it came from (center), level and counts (right).
-- state.summary is built by Recap.lua; state.build rebuilds it when something new is noted while it's up.

local PAD = 48
local CENTER_LINE = 300
local REFRESH = 0.25
local ROWS = 6
local ROW_WIDTH = 380
local ICON = 22
local LIST_PAD = 80 -- from the right screen edge
local LIST_TOP = 170
local SHADE_WIDTH = 620
local TIMER_TOP = 60 -- countdown block, below the top band
local TIMER_BAR = 260
local Text, Spaced, Place, SetText = ns.SceneText, ns.Spaced, ns.ScenePlace, ns.SceneSetText

local COIN_ICONS = {
	gold = "%s|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "%s|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "%s|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

local card, list
local state
local rows = {}
local sinceRefresh = 0

function ns.Recap_Coins(copper, detailed)
	return ns.AFK_MoneyText(copper, detailed, COIN_ICONS)
end

local function Signed(copper)
	if copper == 0 then
		return ns.Recap_Coins(0)
	end
	return (copper > 0 and "+" or "-") .. ns.Recap_Coins(math.abs(copper))
end

local function SourcesLine(sources)
	local parts = {}
	for i = 1, math.min(#sources, 4) do
		local s = sources[i]
		parts[i] = Signed(s.amount) .. " " .. ns.RECAP_SOURCE_NAMES[s.source]
	end
	return table.concat(parts, "  ·  ")
end

local function Label()
	return Spaced(state.summary.label)
end

-- Every frame during a logout: whole seconds in the number, the bar drains smoothly.
local function UpdateTimer()
	local timer = card.timer
	if not state.logoutAt then
		timer:Hide()
		return
	end
	timer:Show()
	local left = ns.Recap_LogoutLeft(state)
	SetText(timer.number, tostring(math.ceil(left)))
	local p = math.min(math.max(left / (state.logoutTotal or 20), 0), 1)
	timer.fill:SetWidth(math.max(TIMER_BAR * p, 0.01))
end

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = {}
	row.icon = list:CreateTexture(nil, "OVERLAY")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.meta = Text(list, 10, "textMuted")
	row.meta:SetJustifyH("RIGHT")
	row.body = Text(list, 14, "text")
	row.body:SetJustifyH("RIGHT")
	row.body:SetWidth(ROW_WIDTH)
	row.body:SetWordWrap(false)
	if i == 1 then
		row.icon:SetPoint("TOPRIGHT", list.header, "BOTTOMRIGHT", 0, -22)
	else
		row.icon:SetPoint("TOPRIGHT", rows[i - 1].icon, "BOTTOMRIGHT", 0, -14)
	end
	row.meta:SetPoint("TOPRIGHT", row.icon, "TOPLEFT", -10, 0)
	row.body:SetPoint("TOPRIGHT", row.meta, "BOTTOMRIGHT", 0, -2)
	rows[i] = row
	return row
end

local function ItemColor(entry)
	if entry.quality and C_Item.GetItemQualityColor then
		local r, g, b = C_Item.GetItemQualityColor(entry.quality)
		if r then
			return r, g, b
		end
	end
	if entry.kind == "achievement" or entry.kind == "renown" then
		return ns.UI.Color("heading")
	end
	return ns.UI.Color("text")
end

local function ShowHighlights()
	local summary = state.summary
	local shown = summary.highlights
	local visible = #shown > 0
	list:SetShown(visible)
	for i, row in ipairs(rows) do
		local on = visible and i <= #shown
		row.icon:SetShown(on)
		row.meta:SetShown(on)
		row.body:SetShown(on)
	end
	if not visible then
		return
	end
	for i, entry in ipairs(shown) do
		local row = Row(i)
		row.icon:SetTexture(entry.icon or 134400) -- question mark
		row.meta:SetText(Spaced(ns.Recap_RowLabel(entry)))
		row.body:SetText(entry.title or "")
		row.body:SetTextColor(ItemColor(entry))
		row.icon:Show()
		row.meta:Show()
		row.body:Show()
	end
	list.more:ClearAllPoints()
	list.more:SetPoint("TOPRIGHT", rows[#shown].body, "BOTTOMRIGHT", 0, -14)
	list.more:SetText(summary.more > 0 and ("+%d more"):format(summary.more) or "")
end

local function ShowSummary()
	local summary = state.summary
	SetText(card.label, Label())
	SetText(card.title, summary.title)
	SetText(card.subtitle, summary.subtitle)
	SetText(card.gold, Signed(summary.net))
	local sources = summary.net == 0 and #summary.sources == 0 and "no gold change" or SourcesLine(summary.sources)
	if summary.lootText then
		sources = sources .. "  -  " .. summary.lootText
	end
	SetText(card.sources, sources)
	SetText(card.statTitle, summary.levelLine)
	SetText(card.statLine, summary.countsLine ~= "" and summary.countsLine or "a quiet session")
	ShowHighlights()
end

-- Something was noted while the card is up (only "this session" cards rebuild).
function ns.RecapScene_Refresh()
	if state and state.build and card and ns.Cinematic.IsOwner(state) then
		state.summary = state.build()
		ShowSummary()
	end
end

local scene = {}
ns.RecapScene = scene

function scene.Create(parent, letterbox)
	card = CreateFrame("Frame", nil, parent)
	card:SetAllPoints(letterbox)
	card:SetFrameLevel(letterbox:GetFrameLevel() + 10) -- above the showcase shade
	card:SetAlpha(0)

	-- Top band.
	card.title = Text(card, 32, "heading", "title")
	Place(card, card.title, "TOP", letterbox.top, "CENTER", 0, 22)
	card.label = Text(card, 12, "textMuted")
	Place(card, card.label, "TOP", letterbox.top, "CENTER", 0, 40)
	card.line = ns.SceneLine(card, 300)
	Place(card, card.line, "TOPRIGHT", letterbox.top, "CENTER", 0, -19)
	card.subtitle = Text(card, 14, "textMuted")
	Place(card, card.subtitle, "TOP", letterbox.top, "CENTER", 0, -26)

	-- Bottom band, left: character.
	card.charName = Text(card, 19, "heading")
	Place(card, card.charName, "TOPLEFT", letterbox.bottom, "LEFT", PAD, 20)
	card.charInfo = Text(card, 13, "textMuted")
	Place(card, card.charInfo, "TOPLEFT", letterbox.bottom, "LEFT", PAD, -3)

	-- Bottom band, center: net gold over a hairline and where it came from.
	card.gold = Text(card, 24, "text", "number")
	Place(card, card.gold, "TOP", letterbox.bottom, "CENTER", 0, 32)
	local track = card:CreateTexture(nil, "OVERLAY")
	track:SetColorTexture(1, 1, 1, 0.16)
	track:SetSize(CENTER_LINE, 1)
	track.pixelHeight = 1
	Place(card, track, "TOP", letterbox.bottom, "CENTER", 0, -6)
	card.sources = Text(card, 11, "textMuted")
	Place(card, card.sources, "TOP", letterbox.bottom, "CENTER", 0, -17)

	-- Bottom band, right: level and counts.
	card.statTitle = Text(card, 18, "text")
	Place(card, card.statTitle, "TOPRIGHT", letterbox.bottom, "RIGHT", -PAD, 19)
	card.statLine = Text(card, 13, "textMuted")
	Place(card, card.statLine, "TOPRIGHT", letterbox.bottom, "RIGHT", -PAD, -3)

	-- Right side: highlights, on a gradient like the showcase's.
	list = CreateFrame("Frame", nil, card)
	list:SetAllPoints(card)
	local shade = list:CreateTexture(nil, "BACKGROUND", nil, -8)
	shade:SetColorTexture(1, 1, 1, 1)
	shade:SetPoint("TOPRIGHT", letterbox, "TOPRIGHT")
	shade:SetPoint("BOTTOMRIGHT", letterbox, "BOTTOMRIGHT")
	shade:SetWidth(SHADE_WIDTH)
	shade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.75))
	list.header = Text(list, 12, "heading")
	Place(card, list.header, "TOPRIGHT", letterbox, "RIGHT", -LIST_PAD, LIST_TOP)
	list.header:SetText(Spaced("Highlights"))
	list.lineWidth = 300
	list.line = ns.SceneLine(list, list.lineWidth)
	Place(card, list.line, "TOPLEFT", letterbox, "RIGHT", -LIST_PAD - list.lineWidth, LIST_TOP - 20)
	list.more = Text(list, 11, "textMuted")
	list.more:SetJustifyH("RIGHT")
	list:Hide()

	-- Under the top band, during a logout: seconds left, a draining accent bar and "Esc to cancel".
	local timer = CreateFrame("Frame", nil, card)
	timer:SetAllPoints(card)
	card.timer = timer
	timer.caption = Text(timer, 11, "textMuted")
	Place(card, timer.caption, "TOP", letterbox.top, "BOTTOM", 0, -TIMER_TOP)
	timer.caption:SetText(Spaced("Logging out in"))
	timer.number = Text(timer, 42, "text", "number")
	Place(card, timer.number, "TOP", letterbox.top, "BOTTOM", 0, -TIMER_TOP - 18)
	local track = timer:CreateTexture(nil, "OVERLAY")
	track:SetColorTexture(1, 1, 1, 0.16)
	track:SetSize(TIMER_BAR, 2)
	track.pixelHeight = 2
	Place(card, track, "TOP", letterbox.top, "BOTTOM", 0, -TIMER_TOP - 72)
	timer.fill = timer:CreateTexture(nil, "OVERLAY", nil, 1)
	timer.fill:SetColorTexture(ns.UI.RGBA("accent", 0.9))
	timer.fill:SetHeight(2)
	timer.fill:SetPoint("TOPLEFT", track, "TOPLEFT")
	timer.fill:SetWidth(TIMER_BAR)
	timer.hint = Text(timer, 11, "textMuted")
	Place(card, timer.hint, "TOP", letterbox.top, "BOTTOM", 0, -TIMER_TOP - 84)
	timer.hint:SetText("Esc to cancel")
	timer:Hide()
end

function scene.Begin(s)
	state = s
	card:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	ns.SceneSnap(card)

	local className, classFile = UnitClass("player")
	local color = C_ClassColor.GetClassColor(classFile)
	card.charName:SetText(UnitName("player"))
	if color then
		card.charName:SetTextColor(color:GetRGB())
	end
	card.charInfo:SetText(("Level %d %s %s"):format(UnitLevel("player"), UnitRace("player"), className))
	ShowSummary()
	UpdateTimer()
	sinceRefresh = 0
end

function scene.Update(alpha, dt)
	card:SetAlpha(alpha)
	if not state or alpha <= 0 then
		return
	end
	UpdateTimer()
	sinceRefresh = sinceRefresh + dt
	if sinceRefresh >= REFRESH then
		sinceRefresh = 0
		SetText(card.label, Label())
		if state.build then
			SetText(card.title, state.summary.titleNow and state.summary.titleNow() or state.summary.title)
		end
	end
end

function scene.End()
	state = nil
end
