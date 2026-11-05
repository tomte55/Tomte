local addonName, ns = ...

-- Nameplates: the badges Tomte adds to Blizzard's nameplates. A quest icon with the progress ("3/8") beside the
-- plate of a unit your quests need, and an item count under Keyflame plates in Hallowfall. Badges are our own
-- frames parented to the nameplate; nothing of Blizzard's plate is changed. Rules in Data.lua, reads in Read.lua,
-- module in Nameplates.lua.

local ICON_SIZE = 16
local COUNT_ICON_SIZE = 14
local GAP = 3
-- Blizzard's own icon for an unfinished quest objective (TooltipDataRules.lua, QUEST_OBJECTIVE_ICON_INCOMPLETE).
local QUEST_ICON = 3083385
-- Seconds to gather a burst of quest log updates (one kill fires several) into one rescan of every plate.
local QUEST_DELAY = 0.3
-- The settings preview's sample: a quest of yours, a group member's, and the Radiant Remnants carried.
local SAMPLE_QUESTS = { { progress = "3/8", party = false }, { progress = "45%", party = true } }
local SAMPLE_COUNT = 12
-- The preview's mock plates copy Blizzard's default plate with the name above the bar (Blizzard_NamePlates, live
-- 12.1): NAMEPLATE_WIDTH 230 less HORIZONTAL_INSET 12 a side, SMALL_HEALTH_BAR_HEIGHT 10, HEALTH_BAR_FONT_HEIGHT 12,
-- HEALTH_BAR_TO_NAME_ABOVE_SPACING 2, and the room the cast bar keeps under the health bar (10 high, 2 apart) above
-- the widget container.
local MOCK_WIDTH = 206
local MOCK_BAR_H = 10
local MOCK_NAME_H = 12
local MOCK_NAME_GAP = 2
local MOCK_CAST_ROOM = 12
-- Blizzard's health bar background reaches 2 left, 3 up, 6 right and 6 down past the bar (UpdateAnchors).
local MOCK_BG_LEFT, MOCK_BG_TOP, MOCK_BG_RIGHT, MOCK_BG_BOTTOM = 2, 3, 6, 6
local MOCK_SPACING = 12 -- between two mock plates, as plates stack in a crowd
-- FACTION_BAR_COLORS indexes: hostile (red) and neutral (yellow), the colors the plates' health bars use.
local HOSTILE, NEUTRAL = 2, 4
-- Mob names are made up; the Keyflame keeps its in-game role so the count reads as Hallowfall's.
local MOCK_PLATES = {
	{ name = "Ashfang Prowler", health = 1, quest = SAMPLE_QUESTS[1] },
	{ name = "Duskmaw Hound", health = 0.62, quest = SAMPLE_QUESTS[2] },
	{ name = "Keyflame", health = 1, neutral = true, count = true },
}
local UI = ns.UI
local IsSecret = ns.IsSecret

local events = ns.NewEvents()
ns.Plates_Events = events
local owner = "badges"

local db
local active = false
local allowed = false
local badges = {} -- [unit token] = badge frame on that unit's plate
local pool = {} -- released badges
local sets = {} -- [widgetSetID] = { item = itemID }, from every expansion's "plateWidgets"
local pendingSecret = {} -- [unit token] = true: read while unit data was secret, read again after combat

-- Frames -------------------------------------------------------------------------------------------------------

local function CreateBadge()
	local b = CreateFrame("Frame")
	b:SetSize(1, 1)

	b.quest = CreateFrame("Frame", nil, b)
	b.quest:SetSize(ICON_SIZE, ICON_SIZE)
	b.quest.icon = b.quest:CreateTexture(nil, "ARTWORK")
	b.quest.icon:SetAllPoints()
	b.quest.icon:SetTexture(QUEST_ICON)
	b.quest.text = b.quest:CreateFontString(nil, "OVERLAY")
	b.quest.text:SetPoint("RIGHT", b.quest.icon, "LEFT", -1, 0) -- outward, away from the health bar
	b.quest:Hide()

	b.count = CreateFrame("Frame", nil, b)
	b.count:SetSize(COUNT_ICON_SIZE, COUNT_ICON_SIZE)
	b.count.icon = b.count:CreateTexture(nil, "ARTWORK")
	b.count.icon:SetSize(COUNT_ICON_SIZE, COUNT_ICON_SIZE)
	b.count.icon:SetPoint("RIGHT", b.count, "CENTER", -1, 0)
	b.count.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.count.text = b.count:CreateFontString(nil, "OVERLAY")
	b.count.text:SetPoint("LEFT", b.count, "CENTER", 1, 0)
	b.count:Hide()
	return b
end

-- Fonts and colors come from the theme each time a badge is placed, so a theme switch reaches them.
local function Style(b)
	UI.SetFont(b.quest.text, "number", 11, "OUTLINE")
	UI.SetFont(b.count.text, "number", 11, "OUTLINE")
	UI.SetTextRole(b.count.text, "heading")
end

-- Where a badge sits on a plate's unit frame (Blizzard's, or the settings preview's mock with the same keys): the
-- quest icon beside the health bar when the plate has one, else beside the name; the count under Blizzard's widgets.
local function Place(b, unitFrame)
	b:ClearAllPoints()
	b:SetAllPoints(unitFrame)
	local bars = unitFrame.HealthBarsContainer
	b.quest:ClearAllPoints()
	if bars and bars:IsShown() then
		b.quest:SetPoint("RIGHT", bars, "LEFT", -GAP, 0)
	elseif unitFrame.name then
		b.quest:SetPoint("RIGHT", unitFrame.name, "LEFT", -GAP, 0)
	else
		b.quest:SetPoint("BOTTOM", unitFrame, "TOP", 0, GAP)
	end
	b.count:ClearAllPoints()
	b.count:SetPoint("TOP", unitFrame.WidgetContainer or unitFrame, "BOTTOM", 0, -GAP)
end

local function Acquire(plate)
	local b = table.remove(pool) or CreateBadge()
	b:SetParent(plate)
	b:SetFrameLevel(plate:GetFrameLevel() + 10)
	b:SetScale(db.scale)
	Place(b, plate.UnitFrame)
	Style(b)
	b:Show()
	return b
end

local function Release(unit)
	local b = badges[unit]
	if not b then
		return
	end
	badges[unit] = nil
	b.lastState = nil
	b:Hide()
	b.quest:Hide()
	b.count:Hide()
	b:ClearAllPoints()
	b:SetParent(nil)
	pool[#pool + 1] = b
end

local function ReleaseAll()
	for unit in pairs(badges) do
		Release(unit)
	end
	wipe(pendingSecret)
end

-- Quest icon ---------------------------------------------------------------------------------------------------

-- The quest state of a unit: a table from ns.Plates_QuestState, false for none, nil when it can't be read now.
local function QuestState(unit)
	if ns.Plates_IsPlayer(unit) ~= false then
		return false -- players never, and a unit we can't tell apart is left alone
	end
	local lines, why = ns.Plates_ReadQuestLines(unit)
	if not lines then
		if why == "secret" then
			-- The tooltip is hidden right now; the game may still say whether the unit is a quest unit.
			local related = ns.Plates_IsQuestUnit(unit)
			if related == nil then
				return nil
			end
			return related and { party = false } or false
		end
		return false
	end
	return ns.Plates_QuestState(lines, db.questParty) or false
end

-- showProgress: the "Show progress" setting.
local function ShowQuest(b, state, showProgress)
	if not state then
		b.quest:Hide()
		return
	end
	b.quest.icon:SetDesaturated(state.party)
	if state.party then
		b.quest.icon:SetVertexColor(UI.Color("info"))
	else
		b.quest.icon:SetVertexColor(1, 1, 1)
	end
	local text = showProgress and state.progress or nil
	b.quest.text:SetText(text or "")
	UI.SetTextRole(b.quest.text, state.party and "info" or "warning")
	b.quest:Show()
end

-- Item count ---------------------------------------------------------------------------------------------------

local function FillCount(b, item, count)
	b.count.item = item
	b.count.icon:SetTexture(C_Item.GetItemIconByID(item))
	b.count.text:SetText(ns.Thousands(count))
	b.count:Show()
end

local function ShowCount(b, unit)
	local info = db.keyflame and sets[ns.Plates_WidgetSet(unit) or 0]
	if not info then
		b.count:Hide()
		return
	end
	FillCount(b, info.item, C_Item.GetItemCount(info.item) or 0)
end

local function UpdateCounts()
	for _, b in pairs(badges) do
		if b.count:IsShown() and b.count.item then
			b.count.text:SetText(ns.Thousands(C_Item.GetItemCount(b.count.item) or 0))
		end
	end
end

-- Per plate ----------------------------------------------------------------------------------------------------

local function UpdateUnit(unit)
	if not (active and allowed) then
		return
	end
	local plate = ns.Plates_Plate(unit)
	if not plate then
		Release(unit)
		return
	end
	local state = false
	if db.quests then
		state = QuestState(unit)
		if state == nil then
			-- Unreadable now (combat): keep what the plate showed and read it again after combat.
			pendingSecret[unit] = true
			state = badges[unit] and badges[unit].lastState or false
		else
			pendingSecret[unit] = nil
		end
	end
	local b = badges[unit]
	if not b then
		b = Acquire(plate)
		badges[unit] = b
	end
	b.lastState = state
	ShowQuest(b, state, db.questProgress)
	ShowCount(b, unit)
	if not (b.quest:IsShown() or b.count:IsShown()) then
		Release(unit)
	end
end

local function UpdateAll()
	if not (active and allowed) then
		ReleaseAll()
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.UnitFrame and plate:GetUnit()
		if unit and not IsSecret(unit) then
			UpdateUnit(unit)
		end
	end
end

local updateSoon = UI.Debounce(QUEST_DELAY, function()
	if active then
		UpdateAll()
	end
end)

-- Settings preview ----------------------------------------------------------------------------------------------

-- A stand-in for Blizzard's plate unit frame with the keys Place reads (HealthBarsContainer, name, WidgetContainer),
-- drawn with the default plate's own art, and a badge of its own.
local function MockPlate(parent)
	local plate = CreateFrame("Frame", nil, parent)
	plate:SetSize(MOCK_WIDTH, MOCK_NAME_H + MOCK_NAME_GAP + MOCK_BAR_H + MOCK_CAST_ROOM)

	local bars = CreateFrame("Frame", nil, plate)
	bars:SetPoint("TOPLEFT", 0, -(MOCK_NAME_H + MOCK_NAME_GAP))
	bars:SetPoint("TOPRIGHT", 0, -(MOCK_NAME_H + MOCK_NAME_GAP))
	bars:SetHeight(MOCK_BAR_H)
	bars.bg = bars:CreateTexture(nil, "BACKGROUND")
	bars.bg:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
	bars.bg:SetPoint("TOPLEFT", -MOCK_BG_LEFT, MOCK_BG_TOP)
	bars.bg:SetPoint("BOTTOMRIGHT", MOCK_BG_RIGHT, -MOCK_BG_BOTTOM)
	bars.fill = bars:CreateTexture(nil, "ARTWORK")
	bars.fill:SetAtlas("UI-HUD-CoolDownManager-Bar")
	bars.fill:SetPoint("TOPLEFT")
	bars.fill:SetPoint("BOTTOMLEFT")
	plate.HealthBarsContainer = bars

	-- Blizzard's nameplate font, not a theme font: the plate is Blizzard's, only the badge is ours.
	plate.name = plate:CreateFontString(nil, "OVERLAY")
	plate.name:SetFontObject(SystemFont_NamePlate)
	plate.name:SetTextHeight(MOCK_NAME_H)
	plate.name:SetJustifyH("LEFT")
	plate.name:SetWordWrap(false)
	plate.name:SetPoint("BOTTOMLEFT", bars, "TOPLEFT", 4, MOCK_NAME_GAP)
	plate.name:SetPoint("BOTTOMRIGHT", bars, "TOPRIGHT", -4, MOCK_NAME_GAP)

	-- Empty, like the real one on a plate without widgets; 1 high so it has a bottom edge to hang the count from.
	plate.WidgetContainer = CreateFrame("Frame", nil, plate)
	plate.WidgetContainer:SetPoint("TOPLEFT", bars, "BOTTOMLEFT", 0, -MOCK_CAST_ROOM)
	plate.WidgetContainer:SetPoint("TOPRIGHT", bars, "BOTTOMRIGHT", 0, -MOCK_CAST_ROOM)
	plate.WidgetContainer:SetHeight(1)

	plate.badge = CreateBadge()
	plate.badge:SetParent(plate)
	plate.badge:SetFrameLevel(plate:GetFrameLevel() + 10)
	return plate
end

local function FillMock(plate, spec)
	plate.name:SetText(spec.name)
	plate.name:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
	local c = FACTION_BAR_COLORS[spec.neutral and NEUTRAL or HOSTILE]
	plate.HealthBarsContainer.fill:SetVertexColor(c.r, c.g, c.b)
	plate.HealthBarsContainer.fill:SetWidth(MOCK_WIDTH * spec.health)
end

-- Settings preview (Panel/Preview.lua): three mock plates stacked like a crowd in the world (a mob your quest needs,
-- one a group member's quest needs, a Keyflame), each with its badge put on by the same code as on a real plate.
-- opts = { scale, quests, progress, party, keyflame } (the settings); the size scales the badges, not the plates, as
-- in the game. Returns the size in host units, or nil when no badge would show.
function ns.Plates_DrawSample(host, opts)
	local root = host.plateSample
	if not root then
		root = CreateFrame("Frame", nil, host)
		root:SetPoint("TOPLEFT")
		root:SetSize(1, 1)
		root.plates = {}
		for i = 1, #MOCK_PLATES do
			root.plates[i] = MockPlate(root)
		end
		host.plateSample = root
	end
	local scale = opts.scale
	-- Fill every plate and badge first: the quest text, which reaches out left of the plate, sets the left margin.
	local left, any = MOCK_BG_LEFT, false
	for i, spec in ipairs(MOCK_PLATES) do
		local plate = root.plates[i]
		FillMock(plate, spec)
		local b = plate.badge
		b:SetScale(scale)
		Place(b, plate)
		Style(b)
		local state = spec.quest and opts.quests and (opts.party or not spec.quest.party) and spec.quest
		ShowQuest(b, state, opts.progress)
		if spec.count and opts.keyflame then
			FillCount(b, ns.PLATES_RADIANT_REMNANT, SAMPLE_COUNT)
		else
			b.count:Hide()
		end
		b:Show()
		if b.quest:IsShown() then
			-- The progress text ends 1 left of the icon, which ends GAP left of the health bar.
			local text = math.ceil(b.quest.text:GetUnboundedStringWidth())
			left = math.max(left, (GAP + ICON_SIZE + (text > 0 and text + 1 or 0)) * scale)
		end
		any = any or b.quest:IsShown() or b.count:IsShown()
	end
	if not any then
		return nil
	end
	left = math.ceil(left)
	local y = 0
	for i, plate in ipairs(root.plates) do
		plate:ClearAllPoints()
		plate:SetPoint("TOPLEFT", root, "TOPLEFT", left, -y)
		y = y + plate:GetHeight()
		if plate.badge.count:IsShown() then
			y = y + (GAP + COUNT_ICON_SIZE) * scale
		end
		if i < #root.plates then
			y = y + MOCK_SPACING
		elseif not plate.badge.count:IsShown() then
			-- Nothing hangs under the last plate: end at its health bar background, not the empty cast bar room.
			y = y - MOCK_CAST_ROOM + MOCK_BG_BOTTOM
		end
	end
	return left + MOCK_WIDTH + MOCK_BG_RIGHT, math.ceil(y)
end

local function CheckAllowed()
	allowed = ns.Plates_Allowed()
	UpdateAll()
end

-- Events -------------------------------------------------------------------------------------------------------

events:On(owner, "NAME_PLATE_UNIT_ADDED", function(_, unit)
	UpdateUnit(unit)
end)

events:On(owner, "NAME_PLATE_UNIT_REMOVED", function(_, unit)
	pendingSecret[unit] = nil
	Release(unit)
end)

events:On(owner, "QUEST_LOG_UPDATE", updateSoon)
events:On(owner, "UNIT_QUEST_LOG_CHANGED", updateSoon)
events:On(owner, "GROUP_ROSTER_UPDATE", updateSoon)
events:On(owner, "BAG_UPDATE_DELAYED", UpdateCounts)
events:On(owner, "PLAYER_ENTERING_WORLD", CheckAllowed)

-- The restriction is only in force after this event is dispatched: look again a frame later.
events:On(owner, "ADDON_RESTRICTION_STATE_CHANGED", function()
	C_Timer.After(0, function()
		if active then
			CheckAllowed()
		end
	end)
end)

-- Plates read while their data was secret (in combat) get a real read now.
events:On(owner, "PLAYER_REGEN_ENABLED", function()
	for unit in pairs(pendingSecret) do
		UpdateUnit(unit)
	end
end)

local EVENTS = {
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
	"GROUP_ROSTER_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
}

-- Called from Nameplates.lua with the module's db.
function ns.Plates_BadgesStart(moduleDB)
	db = moduleDB
	active = true
	local maps = {}
	for _, expansion in ipairs(ns.Content_Expansions()) do
		maps[#maps + 1] = ns.Content_Get(expansion, "plateWidgets")
	end
	sets = ns.Plates_MergeSets(maps)
	for _, event in ipairs(EVENTS) do
		events:Watch(owner, event)
	end
	events:TryWatch(owner, "ADDON_RESTRICTION_STATE_CHANGED")
	CheckAllowed()
end

function ns.Plates_BadgesStop()
	active = false
	events:UnwatchAll(owner)
	ReleaseAll()
end

-- Settings changed: redraw every plate.
function ns.Plates_BadgesRefresh()
	if not active then
		return
	end
	ReleaseAll()
	UpdateAll()
end

-- Why a unit's plate shows what it shows (/tomte plates why): lines for chat.
function ns.Plates_BadgesWhy(unit)
	local out = {}
	local ok, why = ns.Plates_Allowed()
	out[#out + 1] = ok and "nameplates may be decorated here" or ("not here: " .. why)
	if not UnitExists(unit) then
		out[#out + 1] = "no target"
		return out
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	out[#out + 1] = plate and (plate:IsForbidden() and "its nameplate is protected" or "it has a nameplate")
		or "it has no nameplate"
	local lines, reason = ns.Plates_ReadQuestLines(unit)
	if not lines then
		out[#out + 1] = "quest lines: " .. (reason == "secret" and "hidden by the game right now" or "none")
	else
		local titles, objectives = 0, {}
		for _, line in ipairs(lines) do
			if line.kind == "title" then
				titles = titles + 1
			elseif line.kind == "objective" then
				objectives[#objectives + 1] = tostring(line.text) .. (line.completed and " (done)" or "")
			end
		end
		out[#out + 1] = ("quests: %d, objectives: %s"):format(titles,
			#objectives > 0 and table.concat(objectives, "; ") or "none")
		local state = ns.Plates_QuestState(lines, db and db.questParty)
		out[#out + 1] = "shows: " .. (state and ("quest icon" .. (state.progress and (" " .. state.progress) or "")
			.. (state.party and " (group member's)" or "")) or "nothing")
	end
	local set = ns.Plates_WidgetSet(unit)
	out[#out + 1] = "widget set: " .. tostring(set) .. (set and sets[set] and " (item count)" or "")
	return out
end
