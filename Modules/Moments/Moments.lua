local addonName, ns = ...

-- Moments module: short title cards for things worth a pause (level up, achievement, new mount, first
-- steps in a new zone, ...). Each type is off, a banner over the UI, or a cinematic (the shared engine
-- without camera moves: letterbox, hidden UI, title card, character showcase or creature model). A
-- cinematic waits for a safe moment (out of combat, no instance or taxi, standing still); if none comes
-- soon, it shows as a banner instead. It never takes control: every key and click goes to the game and
-- ends the moment. Pure logic is in Data.lua.

local TICK = 0.25
local MAX_WAIT = 10 -- seconds a cinematic moment waits before it becomes a banner
local SETTLE = 8 -- seconds after a loading screen in which collection events are ignored (login catch-up)
local DISCOVERY_DELAY = 0.5 -- seconds: the map's explored overlays update after the message
local ZONE_TEXT_HIDE = 6 -- seconds Blizzard's zone text stays hidden after a discovery we show ourselves
local CHAPTER_DELAY = 2 -- seconds: a chapter's hidden reward quest completes after the last turn-in
local ACCENT = { 0.85, 0.85, 0.85 }
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "ACHIEVEMENT_EARNED",
	"NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED", "UI_INFO_MESSAGE",
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "QUEST_TURNED_IN", "RECEIVED_HOUSE_LEVEL_REWARDS",
}

local module
local waiting = {} -- cinematic moments not shown yet: { moment, waited }
local playing -- engine state of the cinematic moment on screen (state.moment, state.left)
local settleUntil = 0
local exploredAtEntry = {} -- [zone mapID] = explored map textures when we entered it (this session)
local discoveryPatterns

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
local ticker = CreateFrame("Frame")
ticker:Hide()

local function Secret(...)
	if not issecretvalue then
		return false
	end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return true
		end
	end
	return false
end

-- Only while the player isn't doing anything: any key or click ends a moment (it never takes control).
local function CanPlay()
	return not (InCombatLockdown() or IsInInstance() or UnitOnTaxi("player") or UnitIsDeadOrGhost("player")
		or IsPlayerMoving() or IsMouseButtonDown()
		or ns.Cinematic.IsActive()
		or (C_PetBattles and C_PetBattles.IsInBattle())
		or (InCinematic and InCinematic()) or (IsInCinematicScene and IsInCinematicScene())
		or (MovieFrame and MovieFrame:IsShown()))
end

local function ShowBanner(moment)
	ns.Banner_Show({
		owner = "moments",
		label = moment.label,
		accent = ACCENT,
		title = moment.title,
		subtitle = moment.subtitle or moment.detail,
		icon = moment.icon,
	})
end

local function Stop()
	if playing then
		ns.Cinematic.Release(playing)
		playing = nil
	end
end

local function Play(moment)
	playing = { moment = moment, left = ns.momentsDB.duration }
	ns.Cinematic.Enter(ns.MomentScene, playing, {
		skipCamera = true,
		passthrough = true,
		showcase = moment.showcase,
		hint = "Any key or click to continue",
		onDismiss = Stop,
	})
	if not ns.Cinematic.IsOwner(playing) then
		playing = nil
		ShowBanner(moment) -- the engine said no after all
	end
end

local function Tick()
	if playing then
		playing.left = playing.left - TICK
		-- Combat pauses the engine's cinematic (then it's no longer ours): that moment is over. A taxi
		-- takes over for the flight's own cinematic.
		if playing.left <= 0 or not ns.Cinematic.IsOwner(playing) or UnitOnTaxi("player") then
			Stop()
		end
		return
	end
	local entry = waiting[1]
	if not entry then
		ticker:Hide()
		return
	end
	entry.waited = entry.waited + TICK
	local decision = ns.Moments_Decide(CanPlay(), entry.waited, MAX_WAIT)
	if decision == "cinematic" then
		table.remove(waiting, 1)
		Play(entry.moment)
	elseif decision == "banner" then
		table.remove(waiting, 1)
		ShowBanner(entry.moment)
	end
end

local sinceTick = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick >= TICK then
		sinceTick = 0
		Tick()
	end
end)

-- moment = { label, title, subtitle, detail, icon, displayID, showcase }. force = a style for previews.
local function Show(kind, moment, force)
	local style = force or ns.momentsDB.styles[kind] or "off"
	if style == "off" then
		return
	end
	if style == "banner" then
		ShowBanner(moment)
		return
	end
	waiting[#waiting + 1] = { moment = moment, waited = 0 }
	ticker:Show()
end

-- For other modules (Hunter Pets' tames). Ignored while Moments is off.
function ns.Moments_Trigger(kind, moment)
	if module and module.active then
		moment.label = moment.label or "New companion"
		Show(kind, moment)
	end
end

local function Settled()
	return GetTime() >= settleUntil
end

local function CharacterLine()
	local className = UnitClass("player")
	return ("%s %s"):format(UnitRace("player"), className)
end

-- Builders: each returns a moment table (or nil when the data isn't there).
local Build = {}

function Build.levelup(level)
	return {
		label = ns.Moments_LevelLabel(level, GetMaxLevelForPlayerExpansion()),
		title = "Level " .. level,
		subtitle = CharacterLine(),
		showcase = true,
	}
end

function Build.achievement(achievementID)
	local _, name, points, _, _, _, _, description, _, icon = GetAchievementInfo(achievementID)
	if not name then
		return nil
	end
	return {
		label = "Achievement earned",
		title = name,
		subtitle = description,
		detail = points and points > 0 and (points .. " points") or nil,
		icon = icon,
	}
end

function Build.mount(mountID)
	local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
	if not name then
		return nil
	end
	local displayID, description = C_MountJournal.GetMountInfoExtraByID(mountID)
	return { label = "New mount", title = name, detail = description, icon = icon, displayID = displayID }
end

function Build.pet(petGUID)
	local _, customName, _, _, _, displayID, _, name, icon, _, _, _, description = C_PetJournal.GetPetInfoByPetID(petGUID)
	if not name then
		return nil
	end
	return { label = "New battle pet", title = customName or name, detail = description, icon = icon, displayID = displayID }
end

function Build.toy(itemID)
	local _, name, icon = C_ToyBox.GetToyInfo(itemID)
	if not name then
		return nil
	end
	return { label = "New toy", title = name, icon = icon }
end

-- The zone-level map the player is in (walks up from subzone/micro maps).
local function ZoneMap()
	local mapID = C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID > 0 do
		mapID = info.parentMapID
		info = C_Map.GetMapInfo(mapID)
	end
	if info and info.mapType == Enum.UIMapType.Zone then
		return mapID, info.name
	end
	return nil
end

local function ExploredCount(mapID)
	local textures = C_MapExplorationInfo.GetExploredMapTextures(mapID)
	return textures and #textures or 0
end

local function NoteZoneEntry()
	local mapID = ZoneMap()
	if mapID and exploredAtEntry[mapID] == nil then
		exploredAtEntry[mapID] = ExploredCount(mapID)
	end
end

function events:PLAYER_ENTERING_WORLD()
	settleUntil = GetTime() + SETTLE
	NoteZoneEntry()
end

function events:ZONE_CHANGED_NEW_AREA()
	NoteZoneEntry()
end

function events:PLAYER_LEVEL_UP(level)
	if not Secret(level) then
		Show("levelup", Build.levelup(level))
	end
end

function events:ACHIEVEMENT_EARNED(achievementID, alreadyEarned)
	if Secret(achievementID, alreadyEarned) then
		return
	end
	local _, _, _, _, _, _, _, _, _, _, _, isGuild = GetAchievementInfo(achievementID)
	if ns.Moments_ShouldShowAchievement(alreadyEarned, isGuild) then
		local moment = Build.achievement(achievementID)
		if moment then
			Show("achievement", moment)
		end
	end
end

local function Collected(kind, id)
	if not Settled() or Secret(id) then
		return
	end
	local moment = Build[kind](id)
	if moment then
		Show(kind, moment)
	elseif kind == "toy" then
		-- Item data may not be cached yet: one more try.
		C_Timer.After(1, function()
			local retry = Build.toy(id)
			if retry and module.active then
				Show(kind, retry)
			end
		end)
	end
end

function events:NEW_MOUNT_ADDED(mountID)
	Collected("mount", mountID)
end

function events:NEW_PET_ADDED(petGUID)
	Collected("pet", petGUID)
end

function events:NEW_TOY_ADDED(itemID)
	Collected("toy", itemID)
end

function events:UI_INFO_MESSAGE(_, message)
	if Secret(message) then
		return
	end
	if not discoveryPatterns then
		discoveryPatterns = {}
		for _, fmt in ipairs({ ERR_ZONE_EXPLORED, ERR_ZONE_EXPLORED_XP }) do
			if type(fmt) == "string" then
				discoveryPatterns[#discoveryPatterns + 1] = ns.Moments_FormatToPattern(fmt)
			end
		end
	end
	local area = ns.Moments_DiscoveredArea(message, discoveryPatterns)
	if not area then
		return
	end
	local styles = ns.momentsDB.styles
	if ns.momentsDB.replaceZoneText and (styles.discovery ~= "off" or styles.zone ~= "off") then
		ns.Banner_SuppressZoneText(ZONE_TEXT_HIDE) -- our card names the area; Blizzard's would sit under it
	end
	local zoneID, zoneName = ZoneMap()
	if not zoneID then
		Show("discovery", { label = "Discovered", title = area })
		return
	end
	local before = exploredAtEntry[zoneID]
	-- The map's overlays update just after the message: decide once they have.
	C_Timer.After(DISCOVERY_DELAY, function()
		if not module.active then
			return
		end
		local after = ExploredCount(zoneID)
		exploredAtEntry[zoneID] = after -- the next discovery here compares with this
		local guid = UnitGUID("player")
		local shown = ns.momentsDB.zones[guid] or {}
		ns.momentsDB.zones[guid] = shown
		-- The first discovery in a zone that had nothing explored: a whole new zone (once per character).
		if not shown[zoneID] and ns.Moments_IsNewZone(before, after) then
			shown[zoneID] = true
			Show("zone", { label = "New lands", title = zoneName, subtitle = area ~= zoneName and ("Discovered: " .. area) or nil })
			return
		end
		Show("discovery", { label = "Discovered", title = area, subtitle = zoneName ~= area and zoneName or nil })
	end)
end

function events:MAJOR_FACTION_RENOWN_LEVEL_CHANGED(factionID, newLevel, oldLevel)
	if Secret(factionID, newLevel, oldLevel) or not (newLevel and oldLevel and newLevel > oldLevel) then
		return
	end
	local data = C_MajorFactions.GetMajorFactionData(factionID)
	if data and data.name then
		Show("renown", { label = "Renown " .. newLevel, title = data.name })
	end
end

local function ShowChapter(campaignID, chapter)
	local campaign = C_CampaignInfo.GetCampaignInfo(campaignID)
	Show("chapter", { label = "Chapter complete", title = chapter.name, subtitle = campaign and campaign.name or nil })
end

-- Chapters of a campaign whose reward quest is done: [chapterID] = chapter info.
local function DoneChapters(campaignID)
	local done = {}
	for _, chapterID in ipairs(C_CampaignInfo.GetChapterIDs(campaignID) or {}) do
		local chapter = C_CampaignInfo.GetCampaignChapterInfo(chapterID)
		if chapter and chapter.rewardQuestID and C_QuestLog.IsQuestFlaggedCompleted(chapter.rewardQuestID) then
			done[chapterID] = chapter
		end
	end
	return done
end

-- A campaign chapter is complete when its reward quest is done. That's often a hidden quest that never
-- sends QUEST_TURNED_IN itself, so after any campaign quest compare the done chapters with a moment later.
function events:QUEST_TURNED_IN(questID)
	if Secret(questID) or not (C_CampaignInfo and C_CampaignInfo.IsCampaignQuest(questID)) then
		return
	end
	local campaignID = C_CampaignInfo.GetCampaignID(questID)
	if not campaignID then
		return
	end
	for _, chapterID in ipairs(C_CampaignInfo.GetChapterIDs(campaignID) or {}) do
		local chapter = C_CampaignInfo.GetCampaignChapterInfo(chapterID)
		if chapter and chapter.rewardQuestID == questID then
			ShowChapter(campaignID, chapter)
			return
		end
	end
	local before = DoneChapters(campaignID)
	C_Timer.After(CHAPTER_DELAY, function()
		if not module.active then
			return
		end
		for chapterID, chapter in pairs(DoneChapters(campaignID)) do
			if not before[chapterID] then
				ShowChapter(campaignID, chapter)
				return
			end
		end
	end)
end

-- Rewards only go to the house's owner: unlike HOUSE_LEVEL_CHANGED, a friend's house doesn't count.
function events:RECEIVED_HOUSE_LEVEL_REWARDS(level)
	if Settled() and not Secret(level) and level then
		Show("house", { label = "House level", title = "Level " .. level, subtitle = "Your house has grown" })
	end
end
-- Previews: sample data, shown in the type's style (a cinematic when the type is off).
local SAMPLES = {
	levelup = function()
		return Build.levelup(UnitLevel("player"))
	end,
	achievement = function()
		return Build.achievement(6) or { label = "Achievement earned", title = "Level 10", subtitle = "Reach level 10.", detail = "10 points" }
	end,
	mount = function()
		return Build.mount(6) or { label = "New mount", title = "Brown Horse" } -- 6 = Brown Horse
	end,
	pet = function()
		return { label = "New battle pet", title = "Mechanical Squirrel", icon = "Interface\\Icons\\INV_Pet_MechanicalSquirrel" }
	end,
	toy = function()
		return { label = "New toy", title = "Hearthstone Board", icon = "Interface\\Icons\\INV_Misc_Toy_10" }
	end,
	zone = function()
		local _, name = ZoneMap()
		return { label = "New lands", title = name or GetZoneText(), subtitle = "Discovered: " .. (GetSubZoneText() ~= "" and GetSubZoneText() or GetZoneText()) }
	end,
	discovery = function()
		local _, name = ZoneMap()
		return { label = "Discovered", title = GetSubZoneText() ~= "" and GetSubZoneText() or GetZoneText(), subtitle = name }
	end,
	renown = function()
		return { label = "Renown 12", title = "The Silvermoon Court" }
	end,
	chapter = function()
		return { label = "Chapter complete", title = "The Sunwell Remembers", subtitle = "Midnight" }
	end,
	house = function()
		return { label = "House level", title = "Level 3", subtitle = "Your house has grown" }
	end,
	tame = function()
		local snapshot = ns.Stable_Snapshot and ns.hunterDB and ns.Stable_Snapshot()
		local pet = snapshot and snapshot.active and (snapshot.active[1] or snapshot.active[2])
		if pet then
			return { label = "New companion", title = pet.name, subtitle = pet.family, icon = pet.icon, displayID = pet.displayID }
		end
		return { label = "New companion", title = "Loque'nahak", subtitle = "Exotic Spirit Beast" }
	end,
}

local function Preview(kind)
	if not module.active then
		ns.Print("Moments is off.")
		return
	end
	kind = (kind and kind ~= "") and kind or ns.momentsDB.previewKind
	local sample = SAMPLES[kind]
	if not sample then
		local keys = {}
		for _, t in ipairs(ns.MOMENT_TYPES) do
			keys[#keys + 1] = t.key
		end
		ns.Print("preview one of: " .. table.concat(keys, ", "))
		return
	end
	local style = ns.momentsDB.styles[kind]
	if style == "cinematic" and not CanPlay() then
		ns.Print("a cinematic moment waits until you're out of combat, instances and taxis (a banner after 10s).")
	end
	Show(kind, sample(), style == "off" and "cinematic" or style)
end

local function Activate()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	if ns.inWorld then
		NoteZoneEntry()
	end
end

local function Deactivate()
	events:UnregisterAllEvents()
	wipe(waiting)
	ticker:Hide()
	Stop()
	ns.Banner_Clear("moments")
end

local function StyleChoices()
	return ns.MOMENT_STYLES
end

local function TypeChoices()
	local list = {}
	for i, t in ipairs(ns.MOMENT_TYPES) do
		list[i] = { value = t.key, text = t.name }
	end
	return list
end

local options = {
	{ type = "header", label = "Moments" },
}
for _, t in ipairs(ns.MOMENT_TYPES) do
	options[#options + 1] = { type = "dropdown", key = "styles." .. t.key, label = t.name, choices = StyleChoices,
		tooltip = "Off, a banner over the UI, or a short cinematic (UI hidden, letterbox). Cinematics wait until you're out of combat, instances and taxis; after 10 seconds they show as a banner." }
end
options[#options + 1] = { type = "checkbox", key = "replaceZoneText", label = "Replace Blizzard's zone text",
	tooltip = "When a discovery or new zone shows as a moment, hide Blizzard's own zone and subzone text for it. Banners always wait until Blizzard's center-screen text is gone." }
options[#options + 1] = { type = "header", label = "Cinematic" }
options[#options + 1] = { type = "slider", key = "duration", label = "Cinematic length", min = 4, max = 15, step = 1,
	format = function(value)
		return value .. "s"
	end,
	tooltip = "How long a cinematic moment stays. Click or Esc closes it sooner." }
options[#options + 1] = { type = "header", label = "Preview" }
options[#options + 1] = { type = "dropdown", key = "previewKind", label = "Moment", choices = TypeChoices }
options[#options + 1] = { type = "button", label = "Preview moment", text = "Show", onClick = function()
	Preview()
end, tooltip = "Show the chosen moment with sample data, in its style." }

module = ns.RegisterModule({
	key = "moments",
	name = "Moments",
	category = "Ambience",
	description = "Short title cards for moments worth a pause: level ups, achievements, new mounts, pets and toys, new zones, renown, campaign chapters, house levels and tamed pets. A banner or a small cinematic.",
	enabledByDefault = true,
	defaults = {
		styles = ns.Moments_DefaultStyles(),
		duration = 7,
		previewKind = "levelup",
		replaceZoneText = true,
		zones = {}, -- [player GUID] = { [zone mapID] = true } once its "new zone" moment ran
	},
	init = function(db)
		ns.momentsDB = db
	end,
	toggle = function(active)
		if active then
			Activate()
		else
			Deactivate()
		end
	end,
	cinematicState = function()
		return playing
	end,
	commands = {
		{ "preview", "show a sample moment; add a type (levelup, mount, zone, tame, ...)", Preview },
	},
	options = options,
})
