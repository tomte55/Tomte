local addonName, ns = ...

-- Moments module: short title cards for things worth a pause (level up, achievement, new mount, first
-- steps in a new zone, ...). Each type is off, a banner over the UI, or a cinematic (the shared engine
-- without camera moves: letterbox, hidden UI, title card, character showcase or creature model). A
-- cinematic waits for a safe moment (out of combat, no instance or taxi, standing still); if none comes
-- soon, it shows as a banner instead. It never takes control: every key and click goes to the game and
-- ends the moment. The cinematic scene is Scene.lua, Tomte's zone text ZoneText.lua, pure logic Data.lua.

local TICK = 0.25
local MAX_WAIT = 10 -- seconds a cinematic moment waits before it becomes a banner
local SETTLE = 8 -- seconds after a loading screen in which collection events are ignored (login catch-up)
local DISCOVERY_DELAY = 0.5 -- seconds: the map's explored overlays update after the message
local ZONE_TEXT_HIDE = 6 -- seconds Blizzard's zone text stays hidden after a discovery we show ourselves
local CHAPTER_DELAY = 2 -- seconds: a chapter's hidden reward quest completes after the last turn-in
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "ACHIEVEMENT_EARNED",
	"NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED", "UI_INFO_MESSAGE",
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "QUEST_TURNED_IN", "PLAYER_HOUSE_LIST_UPDATED", "HOUSE_LEVEL_FAVOR_UPDATED",
}

local module
local waiting = {} -- cinematic moments not shown yet: { moment, waited }
local playing -- engine state of the cinematic moment on screen (state.moment, state.left)
local settleUntil = 0
local exploredAtEntry = {} -- [zone mapID] = explored map textures when we entered it (this session)
local ownedHouses = {} -- [house GUID] = true for the player's own houses (this session)
local discoveryPatterns

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
local ticker = CreateFrame("Frame")
ticker:Hide()

local Secret = ns.IsSecret

local UI_PANEL_KEYS = { "left", "center", "right", "doublewide", "fullscreen" }

-- A window, bag, menu or edit box is open: the player is using the UI. Same checks as the engine's own
-- (Cinematic/Engine.lua PlayerBusy, which isn't exported).
local function UIBusy()
	if GetCurrentKeyBoardFocus() or (IsAnyBagOpen and IsAnyBagOpen()) then
		return true
	end
	for _, key in ipairs(UI_PANEL_KEYS) do
		if GetUIPanel(key) then
			return true
		end
	end
	for _, name in ipairs(UISpecialFrames) do
		local frame = _G[name]
		if type(frame) == "table" and frame.IsVisible and frame:IsVisible() then
			return true
		end
	end
	return (GameMenuFrame and GameMenuFrame:IsVisible()) or (WorldMapFrame and WorldMapFrame:IsVisible()) or false
end

-- Only while the player isn't doing anything: any key or click ends a moment (it never takes control).
-- previewing = asked for from the options panel or a command: an open window doesn't hold it back.
local function CanPlay(previewing)
	return not (InCombatLockdown() or IsInInstance() or UnitOnTaxi("player") or UnitIsDeadOrGhost("player")
		or IsPlayerMoving() or IsMouseButtonDown()
		or ns.Cinematic.IsActive()
		or C_PetBattles.IsInBattle()
		or (InCinematic and InCinematic()) or (IsInCinematicScene and IsInCinematicScene())
		or (MovieFrame and MovieFrame:IsShown())
		or (not previewing and UIBusy()))
end

local function ShowBanner(moment)
	local fx = moment.tier ~= "common" and ns.MOMENT_TIER_FX[moment.tier]
	ns.Banner_Show({
		owner = "moments",
		label = moment.label,
		accent = fx and fx.glow or nil, -- nil: the banner's own text color
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
	local fx = (moment.displayID or moment.itemIcon) and ns.MOMENT_TIER_FX[moment.tier]
	playing = { moment = moment, left = ns.momentsDB.duration + (fx and fx.extraTime or 0), sound = ns.momentsDB.revealSound }
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
	local decision = ns.Moments_Decide(CanPlay(entry.preview), entry.waited, MAX_WAIT)
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

-- The level that decides "Cinematics only at max level": a level-up's new level, otherwise the player's.
local function LevelFor(moment)
	local level = moment.playerLevel or UnitLevel("player")
	if Secret(level) then
		return nil
	end
	return level
end

-- moment = { label, title, subtitle, detail, icon, displayID, showcase, tier, playerLevel }.
-- force = a style for previews.
local function Show(kind, moment, force)
	local style = force or ns.momentsDB.styles[kind] or "off"
	if not force then
		style = ns.Moments_LevelStyle(style, LevelFor(moment), GetMaxLevelForPlayerExpansion())
	end
	if style == "off" then
		return
	end
	if style == "banner" then
		ShowBanner(moment)
		return
	end
	waiting[#waiting + 1] = { moment = moment, waited = 0, preview = force ~= nil }
	ticker:Show()
end

-- For other modules (Hunter Pets' tames: moment.exotic, moment.rareSpawn). Ignored while Moments is off.
function ns.Moments_Trigger(kind, moment)
	if module and module.active then
		if kind == "tame" then
			moment.tier = moment.tier or ns.Moments_TameTier(moment.exotic, moment.rareSpawn)
			moment.label = moment.label or ns.Moments_TierLabel(moment.tier, "companion")
		end
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
		playerLevel = level,
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

-- Share of players who own a mount (0-100), from the MountsRarity library that Mount Journal Enhanced
-- bundles. nil without it.
local function MountRarity(mountID)
	local lib = LibStub and LibStub("MountsRarity-2.0", true)
	local ok, percent = pcall(function()
		return lib and lib:GetRarityByID(mountID)
	end)
	return ok and type(percent) == "number" and percent or nil
end

function Build.mount(mountID, tier)
	local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
	if not name then
		return nil
	end
	local displayID, description = C_MountJournal.GetMountInfoExtraByID(mountID)
	local percent = MountRarity(mountID)
	tier = tier or ns.Moments_MountTier(percent)
	return { label = ns.Moments_TierLabel(tier, "mount"), title = name, subtitle = ns.Moments_OwnedLine(percent),
		detail = description, icon = icon, displayID = displayID, tier = tier }
end

function Build.pet(petGUID, tier)
	local _, customName, _, _, _, displayID, _, name, icon, _, _, _, description = C_PetJournal.GetPetInfoByPetID(petGUID)
	if not name then
		return nil
	end
	local quality = select(5, C_PetJournal.GetPetStats(petGUID))
	tier = tier or ns.Moments_PetTier(quality)
	return { label = ns.Moments_TierLabel(tier, "battle pet"), title = customName or name, detail = description,
		icon = icon, displayID = displayID, tier = tier }
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

-- Blizzard's "You've Reached Level N" and "You have captured" toasts (Blizzard_FrameXML EventToastManager.lua)
-- say what our level-up and battle pet moments say, in the same spot (Data.lua Moments_ReplacesToast). It still runs its course, just unseen: skipping it would mean calling
-- Blizzard's toast code (taint) and its timing holds back the toasts after it (new spells), which then show
-- once our banner is nearly done. Only alpha and mouse change, restored on the next toast or when it hides.
local hiddenToast
local function RestoreToast()
	if hiddenToast then
		hiddenToast = nil
		EventToastManagerFrame:SetAlpha(1)
		EventToastManagerFrame:EnableMouse(true)
	end
end

local function OnDisplayToast(self)
	RestoreToast()
	local info = self.currentDisplayingToast and self.currentDisplayingToast.toastInfo
	local eventType = info and info.eventType
	if not module.active or Secret(eventType)
		or not ns.Moments_ReplacesToast(eventType, Enum.EventToastEventType, ns.momentsDB) then
		return
	end
	hiddenToast = true
	self:SetAlpha(0)
	self:EnableMouse(false) -- right-click dismiss and hover pause on an invisible frame
end

local toastHooked
local function HookToasts()
	if toastHooked or not (EventToastManagerFrame and EventToastManagerFrame.DisplayToast
		and Enum.EventToastEventType) then
		return
	end
	toastHooked = true
	hooksecurefunc(EventToastManagerFrame, "DisplayToast", OnDisplayToast)
	EventToastManagerFrame:HookScript("OnHide", RestoreToast)
	-- Its closing fade animates the frame's alpha from 1, over our 0: the gold lines would flash. The next
	-- toast's Reset hides them anyway.
	local frame = EventToastManagerFrame
	if frame.fastHide then
		frame.fastHide:HookScript("OnPlay", function()
			if hiddenToast then
				for _, key in ipairs({ "GLine", "GLine2", "BlackBG" }) do
					if frame[key] then
						frame[key]:Hide()
					end
				end
			end
		end)
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
			ns.Session_Note("achievement", { title = moment.title, icon = moment.icon }) -- also when the style is off
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
		ns.Session_Note(kind, { title = moment.title, icon = moment.icon, tier = moment.tier })
		Show(kind, moment)
	elseif kind == "toy" then
		-- Item data may not be cached yet: one more try.
		C_Timer.After(1, function()
			local retry = Build.toy(id)
			if retry and module.active then
				ns.Session_Note(kind, { title = retry.title, icon = retry.icon })
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

function events:UI_INFO_MESSAGE(messageType, message)
	if Secret(message) then
		return
	end
	if not discoveryPatterns then
		discoveryPatterns = ns.Moments_DiscoveryPatterns(ERR_ZONE_EXPLORED_XP, ERR_ZONE_EXPLORED)
	end
	local area = ns.Moments_DiscoveredArea(message, discoveryPatterns)
	if not area then
		return
	end
	local styles = ns.momentsDB.styles
	local zoneID, zoneName = ZoneMap()
	local before = zoneID and exploredAtEntry[zoneID]
	local shownZones = zoneID and ns.momentsDB.zones[UnitGUID("player")]
	-- Can this still turn out to be a whole new zone (decided below once the map has updated)?
	local maybeZone = zoneID and not (shownZones and shownZones[zoneID]) and (before == nil or before == 0)
	-- Hide Blizzard's zone text only when a card of ours names this area. Known now unless it's a maybe-zone
	-- with only one of the two styles on: then right before our card shows.
	local function SuppressFor(kind)
		if ns.momentsDB.replaceZoneText and styles[kind] ~= "off" then
			ns.Banner_SuppressZoneText(ZONE_TEXT_HIDE) -- our card names the area; Blizzard's would sit under it
			ns.Banner_SuppressInfoMessage(messageType, message) -- and the yellow "Discovered: <area>" line
		end
	end
	local decideLater = maybeZone and (styles.zone ~= "off") ~= (styles.discovery ~= "off")
	if not decideLater then
		SuppressFor(maybeZone and "zone" or "discovery")
	end
	if not zoneID then
		Show("discovery", { label = "Discovered", title = area })
		return
	end
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
			if decideLater then
				SuppressFor("zone")
			end
			Show("zone", { label = "New lands", title = zoneName, subtitle = area ~= zoneName and ("Discovered: " .. area) or nil })
			return
		end
		if decideLater then
			SuppressFor("discovery")
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
		ns.Session_Note("renown", { factionID = factionID, title = data.name, from = oldLevel, to = newLevel })
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

-- House levels come from HOUSE_LEVEL_FAVOR_UPDATED, kept to the player's own houses and compared with the
-- highest level saved per house. Not RECEIVED_HOUSE_LEVEL_REWARDS: that answers a reward-list request, and
-- Blizzard's housing dashboard requests every level when it loads (a burst of fake "level N" moments), nor
-- HOUSE_LEVEL_CHANGED, which also fires for a friend's house.
function events:PLAYER_HOUSE_LIST_UPDATED(houseInfos)
	wipe(ownedHouses)
	for _, info in ipairs(houseInfos or {}) do
		local guid = info.houseGUID
		if guid and not Secret(guid) then
			ownedHouses[guid] = true
			C_Housing.GetCurrentHouseLevelFavor(guid) -- answers with HOUSE_LEVEL_FAVOR_UPDATED
		end
	end
end

function events:HOUSE_LEVEL_FAVOR_UPDATED(favor)
	local guid, level = favor and favor.houseGUID, favor and favor.houseLevel
	if not guid or Secret(guid) or not ownedHouses[guid] or not level or Secret(level) then
		return
	end
	local saved = ns.momentsDB.houses[guid]
	if saved == nil or level > saved then
		ns.momentsDB.houses[guid] = level
	end
	if ns.Moments_HouseLevelUp(saved, level) then
		Show("house", { label = "House level", title = "Level " .. level, subtitle = "Your house has grown" })
	end
end

-- Previews: sample data, shown in the type's style (a cinematic when the type is off). Creature samples
-- take a tier (nil = the sample's own).
local SAMPLES = {
	levelup = function()
		return Build.levelup(UnitLevel("player"))
	end,
	achievement = function()
		return Build.achievement(6) or { label = "Achievement earned", title = "Level 10", subtitle = "Reach level 10.", detail = "10 points" }
	end,
	mount = function(tier)
		return Build.mount(6, tier) or { label = "New mount", title = "Brown Horse", tier = tier } -- 6 = Brown Horse
	end,
	pet = function(tier)
		-- The first owned pet in the journal (its list follows the journal's filters).
		for i = 1, math.min(C_PetJournal.GetNumPets(), 50) do
			local petGUID = C_PetJournal.GetPetInfoByIndex(i)
			local moment = petGUID and Build.pet(petGUID, tier)
			if moment then
				return moment
			end
		end
		return { label = ns.Moments_TierLabel(tier, "battle pet"), title = "Mechanical Squirrel",
			icon = "Interface\\Icons\\INV_Pet_MechanicalSquirrel", tier = tier }
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
	companion = function()
		return { label = "Level 40", title = "Brann Bronzebeard" }
	end,
	chapter = function()
		return { label = "Chapter complete", title = "The Sunwell Remembers", subtitle = "Midnight" }
	end,
	house = function()
		return { label = "House level", title = "Level 3", subtitle = "Your house has grown" }
	end,
	tame = function(tier)
		local snapshot = ns.Stable_Snapshot and ns.hunterDB and ns.Stable_Snapshot()
		local pet = snapshot and snapshot.active and (snapshot.active[1] or snapshot.active[2])
		tier = tier or (pet and ns.Moments_TameTier(pet.exotic, false)) or "epic"
		local label = ns.Moments_TierLabel(tier, "companion")
		if pet then
			return { label = label, title = pet.name, subtitle = pet.family, icon = pet.icon, displayID = pet.displayID, tier = tier }
		end
		return { label = label, title = "Loque'nahak", subtitle = "Exotic Spirit Beast", tier = tier }
	end,
	upgrade = function(tier)
		-- An item you wear, shown as if it had just dropped.
		for _, slot in ipairs({ 1, 5, 16, 3, 7 }) do
			local location = ItemLocation:CreateFromEquipmentSlot(slot)
			if C_Item.DoesItemExist(location) then
				local quality = C_Item.GetItemQuality(location)
				local r, g, b = C_Item.GetItemQualityColor(quality or 1)
				return { label = "Upgrade +4.2%", title = C_Item.GetItemName(location),
					subtitle = ns.Gear_RevealLine(C_Item.GetCurrentItemLevel(location), "your old one", nil),
					itemIcon = C_Item.GetItemIcon(location), itemColor = { r, g, b },
					tier = tier or ns.Gear_RevealTier(quality) }
			end
		end
		return { label = "Upgrade +4.2%", title = "Sample Helm", itemIcon = "Interface\\Icons\\INV_Helmet_03",
			tier = tier or "rare" }
	end,
}

-- "mount legendary": a type and, for creatures, a tier.
local function Preview(text)
	if not ns.Module_RequireOn(module) then
		return
	end
	local kind, tier = (text or ""):match("^(%S*)%s*(%S*)")
	kind = kind ~= "" and kind or ns.momentsDB.previewKind
	if tier ~= "" and not ns.Moments_IsTier(tier) then
		ns.Print("tier is one of: " .. table.concat(ns.MOMENT_TIERS, ", "))
		return
	end
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
	if style == "cinematicMax" then
		style = "cinematic" -- the preview shows what max level looks like
	end
	if style == "cinematic" and not CanPlay(true) then
		ns.Print("a cinematic moment waits until you're out of combat, instances and taxis (a banner after 10s).")
	end
	Show(kind, sample(tier ~= "" and tier or nil), style == "off" and "cinematic" or style)
end

local function Activate()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	if ns.inWorld then
		NoteZoneEntry()
	end
	ns.Moments_ZoneText(ns.momentsDB.zoneText)
	HookToasts()
	if C_Housing and C_Housing.GetPlayerOwnedHouses then
		C_Housing.GetPlayerOwnedHouses() -- answers with PLAYER_HOUSE_LIST_UPDATED
	end
end

local function Deactivate()
	events:UnregisterAllEvents()
	wipe(waiting)
	ticker:Hide()
	Stop()
	ns.Banner_Clear("moments")
	ns.Moments_ZoneText(false)
	RestoreToast()
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
		tooltip = "Off, a banner over the UI, or a short cinematic (UI hidden, letterbox). Cinematic at max level is a banner while levelling and a cinematic once you reach max level. Cinematics wait until you're out of combat, instances and taxis; after 10 seconds they show as a banner." }
end
options[#options + 1] = { type = "header", label = "Zone text" }
options[#options + 1] = { type = "checkbox", key = "zoneText", label = "Zone text in Tomte's style",
	tooltip = "Show the zone and subzone name you enter (and Sanctuary, Contested and so on) in the Tomte theme instead of Blizzard's text. Same timing as Blizzard's.",
	preview = ns.Preview_When("zoneText", function(host, get)
		return ns.Moments_ZoneTextSample(host, get)
	end),
	onChange = function(on)
		ns.Moments_ZoneText(on and module.active)
	end }
options[#options + 1] = { type = "checkbox", key = "replaceZoneText", label = "No zone text under a discovery",
	tooltip = "When a discovery or new zone shows as a moment, hide the zone and subzone text and the yellow \"Discovered\" line for it. Banners always wait until the zone text is gone." }
options[#options + 1] = { type = "header", label = "Level up" }
options[#options + 1] = { type = "checkbox", key = "replaceLevelUp", label = "Replace Blizzard's level-up text",
	tooltip = "When level ups show as a moment, hide Blizzard's \"You've Reached Level\" text so only the moment shows. Its sound still plays, and the new-spell notices after it still show." }
options[#options + 1] = { type = "header", label = "Battle pets" }
options[#options + 1] = { type = "checkbox", key = "replacePetCapture", label = "Replace Blizzard's capture text",
	tooltip = "When new battle pets show as a moment, hide Blizzard's \"You have captured\" text after a pet battle so only the moment shows." }
options[#options + 1] = { type = "header", label = "Cinematic" }
options[#options + 1] = { type = "slider", key = "duration", label = "Cinematic length", min = 4, max = 15, step = 1,
	format = function(value)
		return value .. "s"
	end,
	tooltip = "How long a cinematic moment stays. Click or Esc closes it sooner. Epic and legendary creatures stay a little longer." }
options[#options + 1] = { type = "checkbox", key = "revealSound", label = "Reveal sounds",
	tooltip = "Play a sound when a new mount, battle pet or tamed pet is revealed. Rarer ones sound grander." }
options[#options + 1] = { type = "header", label = "Preview" }
options[#options + 1] = { type = "dropdown", key = "previewKind", label = "Moment", choices = TypeChoices,
	tooltip = "Which moment the Preview button below shows." }
options[#options + 1] = { type = "button", label = "Preview moment", text = "Show", onClick = function()
	Preview()
end, tooltip = "Show the chosen moment with sample data, in its style." }

module = ns.RegisterModule({
	key = "moments",
	name = "Moments",
	category = "ambience",
	icon = 255130, -- inv_misc_tournaments_banner_human
	summary = "Title cards for level ups, new mounts, achievements and more.",
	description = "Short title cards for moments worth a pause: level ups, achievements, new mounts, pets and toys, new zones, renown, campaign chapters, house levels, tamed pets and gear upgrades. A banner or a small cinematic.",
	enabledByDefault = true,
	toasts = "Moments (banners)",
	defaults = {
		styles = ns.Moments_DefaultStyles(),
		duration = 7,
		previewKind = "levelup",
		replaceZoneText = true,
		replaceLevelUp = true,
		replacePetCapture = true,
		zoneText = true,
		revealSound = true,
		zones = {}, -- [player GUID] = { [zone mapID] = true } once its "new zone" moment ran
		houses = {}, -- [house GUID] = highest house level seen (houses are account-wide)
	},
	noShare = { "previewKind" }, -- not in settings strings (Core/Profile.lua)
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
		{ "preview", "show a sample moment; add a type (levelup, mount, zone, tame, upgrade, ...) and for mount, pet, tame or upgrade a tier (common, rare, epic, legendary)", Preview },
	},
	options = options,
})
