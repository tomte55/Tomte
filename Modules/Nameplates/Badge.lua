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

local function Acquire(plate)
	local b = table.remove(pool) or CreateBadge()
	b:SetParent(plate)
	b:SetFrameLevel(plate:GetFrameLevel() + 10)
	b:SetScale(db.scale)
	b:ClearAllPoints()
	b:SetAllPoints(plate.UnitFrame)
	Style(b)

	-- Beside the health bar when the plate has one, else beside the name; the count under Blizzard's widgets.
	local unitFrame = plate.UnitFrame
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

local function ShowQuest(b, state)
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
	local text = db.questProgress and state.progress or nil
	b.quest.text:SetText(text or "")
	UI.SetTextRole(b.quest.text, state.party and "info" or "warning")
	b.quest:Show()
end

-- Item count ---------------------------------------------------------------------------------------------------

local function ShowCount(b, unit)
	local info = db.keyflame and sets[ns.Plates_WidgetSet(unit) or 0]
	if not info then
		b.count:Hide()
		return
	end
	b.count.item = info.item
	b.count.icon:SetTexture(C_Item.GetItemIconByID(info.item))
	b.count.text:SetText(ns.Thousands(C_Item.GetItemCount(info.item) or 0))
	b.count:Show()
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
	ShowQuest(b, state)
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
