local addonName, ns = ...

-- Flight scene for the cinematic engine, drawn inside the letterbox bands:
-- top = title card (destination),
-- bottom = character (left), flight timer (center), rotating flight stats (right).
-- The "Entering <zone>" text (ZoneText.lua) belongs to this scene too.

local GOLD, GREY, WHITE = ns.SCENE_GOLD, ns.SCENE_GREY, ns.SCENE_WHITE
local PAD = 48 -- side padding inside the bottom band
local LINE_WIDTH = 440 -- progress line under the timer
local STATS_PAGE_TIME = 6
local Text, Spaced, Place, SetText = ns.SceneText, ns.Spaced, ns.ScenePlace, ns.SceneSetText

local card
local flight
local ticks = {}
local statsSwap
local pages, page, pageTimer = {}, 1, 0

-- "Gundargaz, The Ringing Deeps" -> "Gundargaz", "The Ringing Deeps"
local function SplitName(name)
	local place, zone = name:match("^(.-),%s*(.+)$")
	return place or name, zone
end

local function SetTitle(label, title, subtitle)
	card.label:SetText(Spaced(label))
	card.title:SetText(title)
	card.subtitle:SetText(subtitle or "")
end

local function SetDestinationTitle()
	local place, zone = SplitName(flight.destName)
	local from = flight.originName and SplitName(flight.originName)
	local subtitle
	if zone and from then
		subtitle = zone .. "   -   from " .. from
	else
		subtitle = zone or (from and ("from " .. from)) or ""
	end
	SetTitle("Now flying to", place, subtitle)
end

local function ShowPage(elapsed)
	local title, line = pages[page](elapsed)
	SetText(card.statTitle, title)
	SetText(card.statLine, line)
end

local function BuildPages()
	local stats = ns.flightDB.stats
	pages = {
		function(elapsed)
			local live = ns.flightDB.stats -- re-read: /tomte flight resetstats mid-flight replaces the table
			return "Flight #" .. (live.flights + 1), ns.FormatTime(live.seconds + elapsed) .. " in the air"
		end,
	}
	local visited = ns.TopEntry(stats.departures)
	if visited then
		pages[#pages + 1] = function()
			return "Most visited", visited
		end
	end
	local route = ns.TopEntry(stats.routeCounts)
	if route then
		pages[#pages + 1] = function()
			return "Most flown", route
		end
	end
	local info = flight.mapID and C_Map.GetMapInfo(flight.mapID)
	local mapSeconds = flight.mapID and stats.byMap[flight.mapID]
	if info and mapSeconds then
		pages[#pages + 1] = function()
			return info.name, ns.FormatTime(mapSeconds) .. " flown here"
		end
	end
	page, pageTimer = 1, 0
end

local scene = {}
ns.FlightScene = scene

function scene.Create(parent, letterbox)
	card = CreateFrame("Frame", nil, parent)
	card:SetAllPoints(letterbox)
	card:SetFrameLevel(letterbox:GetFrameLevel() + 10) -- above the showcase shade
	card:SetAlpha(0)

	-- Top band: title card.
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

	-- Bottom band, center: timer + progress line + arrival clock.
	card.time = Text(card, 28, { 1, 1, 1 })
	Place(card, card.time, "TOP", letterbox.bottom, "CENTER", 0, 36)

	-- A hairline track with a gold fill and a small glowing head at the fill's leading edge.
	card.track = card:CreateTexture(nil, "OVERLAY")
	card.track:SetColorTexture(1, 1, 1, 0.16)
	card.track:SetSize(LINE_WIDTH, 1)
	card.track.pixelHeight = 1
	Place(card, card.track, "TOP", letterbox.bottom, "CENTER", 0, -6)
	card.fill = card:CreateTexture(nil, "OVERLAY", nil, 1)
	card.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	card.fill:SetHeight(1)
	card.fill:SetPoint("LEFT", card.track, "LEFT")
	card.head = card:CreateTexture(nil, "OVERLAY", nil, 3)
	card.head:SetColorTexture(1, 0.92, 0.7, 1)
	card.head:SetSize(5, 5)
	card.head:SetPoint("CENTER", card.fill, "RIGHT")
	local headMask = card:CreateMaskTexture()
	headMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	headMask:SetAllPoints(card.head)
	card.head:AddMaskTexture(headMask)
	card.halo = card:CreateTexture(nil, "OVERLAY", nil, 2)
	card.halo:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)
	card.halo:SetSize(13, 13)
	card.halo:SetPoint("CENTER", card.head)
	local haloMask = card:CreateMaskTexture()
	haloMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	haloMask:SetAllPoints(card.halo)
	card.halo:AddMaskTexture(haloMask)
	card.eta = Text(card, 10, GREY)
	Place(card, card.eta, "TOP", letterbox.bottom, "CENTER", 0, -19)

	-- Bottom band, right: rotating flight stats.
	local statsGroup = CreateFrame("Frame", nil, card)
	statsGroup:SetAllPoints(card)
	statsSwap = ns.NewSwap(statsGroup)
	card.statTitle = Text(statsGroup, 18, WHITE)
	Place(card, card.statTitle, "TOPRIGHT", letterbox.bottom, "RIGHT", -PAD, 19)
	card.statLine = Text(statsGroup, 13, GREY)
	Place(card, card.statLine, "TOPRIGHT", letterbox.bottom, "RIGHT", -PAD, -3)

	ns.ZoneText_Create(parent)
end

function scene.Begin(f)
	flight = f
	ns.ZoneText_Hide()
	-- Same on-screen size as normal UI text, whatever the UI scale.
	card:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	ns.SceneSnap(card)
	ns.ResetSwap(statsSwap)
	SetDestinationTitle()

	local className, classFile = UnitClass("player")
	local color = C_ClassColor.GetClassColor(classFile)
	card.charName:SetText(UnitName("player"))
	if color then
		card.charName:SetTextColor(color:GetRGB())
	end
	local _, equipped = GetAverageItemLevel()
	card.charInfo:SetText(("Level %d %s %s   -   ilvl %d"):format(
		UnitLevel("player"), UnitRace("player"), className, math.floor(equipped or 0)))

	BuildPages()
	ShowPage(GetTime() - f.start)

	local recording = f.expected == nil
	card.track:SetShown(not recording)
	card.fill:SetShown(not recording)
	card.head:SetShown(not recording)
	card.halo:SetShown(not recording)
	card.eta:SetShown(not recording)

	for _, tick in ipairs(ticks) do
		tick:Hide()
	end
	if not recording and f.stops then
		for i, fraction in ipairs(f.stops) do
			local tick = ticks[i]
			if not tick then
				tick = card:CreateTexture(nil, "OVERLAY", nil, 2)
				tick:SetColorTexture(1, 1, 1, 0.6)
				tick:SetSize(1, 9)
				ticks[i] = tick
			end
			tick:ClearAllPoints()
			tick:SetPoint("CENTER", card.track, "LEFT", fraction * LINE_WIDTH, 0)
			tick:Show()
		end
	end
end

-- Called every frame while the letterbox is visible.
function scene.Update(alpha, dt)
	ns.ZoneText_SetAlpha(alpha)
	card:SetAlpha(alpha)
	if not flight or alpha <= 0 then
		return
	end
	local now = GetTime()
	local elapsed = now - flight.start
	local text, fill, remaining = ns.TimerText(flight.expected, false, elapsed) -- no "~": the cinematic doesn't flag estimates
	SetText(card.time, text)
	if fill then
		-- The line grows left to right as the flight progresses.
		card.fill:SetWidth(math.max((1 - fill) * LINE_WIDTH, 0.01))
		SetText(card.eta, remaining >= 0 and Spaced("Arrives " .. date("%H:%M", time() + math.floor(remaining + 0.5))) or "")
	end

	pageTimer = pageTimer + dt
	if pageTimer >= STATS_PAGE_TIME and #pages > 1 then
		pageTimer = 0
		ns.StartSwap(statsSwap, function()
			page = page % #pages + 1
			ShowPage(elapsed)
		end)
	end
	if page == 1 and not statsSwap.t then
		ShowPage(elapsed) -- live air time
	end
	ns.UpdateSwap(statsSwap, dt)
end
