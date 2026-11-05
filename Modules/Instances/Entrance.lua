local addonName, ns = ...

-- Instances: the entrance picker. Near a dungeon or raid portal, a small card with Normal / Heroic / Mythic
-- (UI.Segmented; 10 N / 10 H / 25 N / 25 H at raids from before Siege of Orgrimmar) and your lockout under each.
-- Usable solo or as group leader, read-only otherwise. "Near" is the player's map position against the portals the
-- Encounter Journal lists for that map
-- (C_EncounterJournal.GetDungeonEntrancesForMap; the approach Plumber's RaidCheck uses, its code not taken), checked
-- by a ticker that only runs on a map with portals and outside instances. Hidden in combat. Moved with Edit Mode.

local RANGE = 30 -- yards from the portal's map pin where the card appears
local RANGE_LEAVE = 40 -- and where it goes again, so it doesn't flicker at the edge
local TICK = 0.5 -- seconds between position checks while on a map with portals
local PAD, W_MIN = 12, 220

local UI = ns.UI
local events = ns.Instances_Events

local db
local active = false
local mapID, entrances = nil, {}
local ticker
local near -- the entrance the card shows
local card

-- What Edit Mode shows when no portal is near.
local PREVIEW = { journalInstanceID = 0, name = "Dungeon portal" }

local function Journal(e)
	if e == PREVIEW then
		return { name = PREVIEW.name, isRaid = false }
	end
	return ns.InstancesRead_Journal(e.journalInstanceID) or { name = e.name or "Instance", isRaid = false,
		isLegacy = false }
end

-- The card's choices for an instance (InstancesRead_Journal): old raids get size and Normal / Heroic together.
local function Choices(j)
	if j.isLegacy then
		return ns.INSTANCES_LEGACY_FULL_CHOICES
	end
	local list = {}
	for i, id in ipairs(j.isRaid and ns.INSTANCES_RAID_CHOICES or ns.INSTANCES_DUNGEON_CHOICES) do
		list[i] = { value = id, text = ns.InstancesRead_DifficultyName(id) }
	end
	return list
end

-- Card ------------------------------------------------------------------------------------------------------------

local function SavePosition()
	local point, _, relPoint, x, y = card:GetPoint()
	db.entranceFrame.point, db.entranceFrame.relPoint, db.entranceFrame.x, db.entranceFrame.y = point, relPoint, x, y
end

local function Place()
	local f = db.entranceFrame
	card:ClearAllPoints()
	card:SetPoint(f.point, UIParent, f.relPoint, f.x, f.y)
end

-- The card's looks on f: the real card's and the settings preview's (InstancesEntrance_DrawSample below).
local function Dress(f)
	f:SetSize(W_MIN, 90)
	UI.Panel(f, { size = "small" })
	f.title = UI.Text(f, 14, "heading", "title")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	f.kind = UI.Text(f, 11, "textMuted", "label")
	f.kind:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
	f.seg = UI.Segmented(f)
	f.seg:SetPoint("TOPLEFT", f.kind, "BOTTOMLEFT", 0, -8)
	f.locks = {}
	f.hint = UI.Text(f, 11, "textMuted")
	f.hint:SetWordWrap(true)
end

local function Build()
	card = CreateFrame("Frame", nil, UIParent)
	card:SetFrameStrata("MEDIUM")
	card:SetMovable(true)
	card:SetClampedToScreen(true)
	card:Hide()
	Dress(card)
	Place()
end

local function Lock(f, i)
	local fs = f.locks[i]
	if not fs then
		fs = UI.Text(f, 11, "textMuted", "number")
		f.locks[i] = fs
	end
	return fs
end

-- Fills card f (Dress) for entrance e (PREVIEW: a sample whose choices do nothing) and sizes it.
local function Fill(f, e)
	local j = Journal(e)
	local kind = j.isLegacy and "legacyFull" or j.isRaid and "raid" or "dungeon"
	local canChoose, reason = ns.InstancesRead_CanChoose()
	local saves = ns.InstancesRead_Saves(j.instanceID)
	f.title:SetText(j.name)
	f.kind:SetText(j.isLegacy and "Old raid: size and difficulty" or j.isRaid and "Raid" or "Dungeon")
	local seg = f.seg
	seg.choices = function()
		return Choices(j)
	end
	seg.getValue = function()
		local dungeon, raid, legacy = ns.InstancesRead_Chosen()
		if j.isLegacy then
			return legacy
		end
		return j.isRaid and raid or dungeon
	end
	seg.setValue = function(value)
		if e == PREVIEW then
			return
		end
		local ok, why = ns.InstancesRead_SetDifficulty(kind, value)
		if not ok then
			ns.Print(why)
		end
	end
	local width = seg:Refresh()
	seg:SetAlpha(canChoose and 1 or 0.5)
	local choices = Choices(j)
	for i, choice in ipairs(choices) do
		local fs = Lock(f, i)
		local text, role = ns.Instances_LockoutShort(ns.Instances_SaveFor(saves, choice.value))
		fs:SetText(text)
		UI.SetTextRole(fs, role)
		fs:ClearAllPoints()
		fs:SetPoint("TOP", seg.segments[i], "BOTTOM", 0, -4)
		fs:Show()
	end
	for i = #choices + 1, #f.locks do
		f.locks[i]:Hide()
	end
	local w = math.max(W_MIN, width + 2 * PAD, math.ceil(f.title:GetUnboundedStringWidth()) + 2 * PAD)
	f:SetWidth(w)
	local height = PAD + f.title:GetStringHeight() + 2 + f.kind:GetStringHeight() + 8 + seg:GetHeight() + 4 + 14
	f.hint:ClearAllPoints()
	if canChoose then
		f.hint:Hide()
	else
		f.hint:SetWidth(w - 2 * PAD)
		f.hint:SetText(reason)
		f.hint:SetPoint("TOPLEFT", PAD, -(height + 6))
		f.hint:Show()
		height = height + 6 + f.hint:GetStringHeight()
	end
	f:SetHeight(height + PAD)
end

local function Draw(e)
	if not card then
		Build()
	end
	Fill(card, e)
	card:Show()
end

-- The settings preview (Panel/Preview.lua): Edit Mode's sample portal card with your chosen difficulty and lockouts,
-- drawn by Dress and Fill like the real one (its choices do nothing for the sample).
function ns.InstancesEntrance_DrawSample(host)
	local f = host.card
	if not f then
		f = CreateFrame("Frame", nil, host)
		f:SetPoint("TOPLEFT")
		Dress(f)
		host.card = f
	end
	Fill(f, PREVIEW)
	return f:GetWidth(), f:GetHeight()
end

local function Hide()
	if card then
		card:Hide()
	end
end

local function Refresh()
	if ns.EditMode_Active() and active then
		Draw(near or PREVIEW)
	elseif near and active and not InCombatLockdown() then
		Draw(near)
	else
		Hide()
	end
end

-- Finding the portal ------------------------------------------------------------------------------------------------

local function Tick()
	if InCombatLockdown() then
		return
	end
	local x, y, w, h = ns.InstancesRead_Position(mapID)
	local e, d = ns.Instances_Nearest(entrances, x, y, w, h, RANGE_LEAVE)
	if e and not near and d > RANGE then
		e = nil
	end
	local was = near
	near = e
	if near and (not was or was.journalInstanceID ~= near.journalInstanceID) then
		RequestRaidInfo() -- fresh lockouts for the card; it redraws on UPDATE_INSTANCE_INFO
	end
	if near ~= was then
		Refresh()
	end
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function Rescan()
	if not active then
		return
	end
	if IsInInstance() then
		mapID, entrances = nil, {}
	else
		mapID, entrances = ns.InstancesRead_Entrances()
	end
	if #entrances > 0 then
		ticker = ticker or C_Timer.NewTicker(TICK, Tick)
		Tick()
	else
		StopTicker()
		near = nil
		Refresh()
	end
end

local rescanSoon = UI.Debounce(0.5, Rescan)

local MAP_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }
for _, event in ipairs(MAP_EVENTS) do
	events:On("entrance", event, function()
		rescanSoon()
	end)
end
-- Flying from one floor of a map to another (Caverns of Time, Blackrock Mountain) may only fire this one.
events:On("entrance", "NEW_WMO_CHUNK", function()
	rescanSoon()
end)

local REDRAW_EVENTS = { "PLAYER_DIFFICULTY_CHANGED", "UPDATE_INSTANCE_INFO", "GROUP_ROSTER_UPDATE",
	"PARTY_LEADER_CHANGED", "PLAYER_REGEN_ENABLED" }
for _, event in ipairs(REDRAW_EVENTS) do
	events:On("entrance", event, function()
		Refresh()
	end)
end

events:On("entrance", "PLAYER_REGEN_DISABLED", function()
	Hide()
end)

ns.EditMode_Register({
	name = "Instance difficulty",
	frame = function()
		return card
	end,
	refresh = function()
		if active then
			if not card then
				Build()
			end
			Refresh()
		end
	end,
	saved = SavePosition,
	module = "instances",
	reset = function()
		ns.InstancesEntrance_ResetPosition()
	end,
})

function ns.InstancesEntrance_Init(saved)
	db = saved
end

function ns.InstancesEntrance_ResetPosition()
	db.entranceFrame.point, db.entranceFrame.relPoint, db.entranceFrame.x, db.entranceFrame.y = "TOP", "TOP", 0, -140
	if card then
		Place()
	end
end

function ns.InstancesEntrance_Toggle(on)
	if on == active then
		return
	end
	active = on
	if on then
		for _, event in ipairs(MAP_EVENTS) do
			events:Watch("entrance", event)
		end
		events:TryWatch("entrance", "NEW_WMO_CHUNK")
		for _, event in ipairs(REDRAW_EVENTS) do
			events:Watch("entrance", event)
		end
		events:Watch("entrance", "PLAYER_REGEN_DISABLED")
		Rescan()
	else
		events:UnwatchAll("entrance")
		StopTicker()
		mapID, entrances, near = nil, {}, nil
		Hide()
	end
end

-- For /tomte instances why.
function ns.InstancesEntrance_Why()
	local x, y, w, h = ns.InstancesRead_Position(mapID)
	local e, d = ns.Instances_Nearest(entrances, x, y, w, h, math.huge)
	return ("entrance: map %s, %d portals, nearest %s at %s yards (shows within %d)"):format(tostring(mapID),
		#entrances, e and tostring(e.name) or "none", d and ("%.0f"):format(d) or "?", RANGE)
end
