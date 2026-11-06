local addonName, ns = ...

-- Smart Mount: one key binding (Tomte > Smart Mount) on a secure button. Out of combat its PreClick looks at the
-- situation and sets the button up: leave the vehicle, dismount, leave travel form / Ghost Wolf, or cast a mount
-- picked for where you are (zone favorites, then journal favorites, then every usable mount; the settings add
-- passenger and class mounts and a travel form). In combat the attributes can't change, so entering combat leaves a
-- macro that only gets you out (or into the travel form). Picking rules, mount lists and the action bar macro's text in
-- Data.lua, class forms in Forms.lua, the zone favorite star in Journal.lua, the panel's Zones tab in ZonesPage.lua.

local BUTTON_NAME = "TomteSmartMount" -- global: the CLICK binding in Bindings.xml needs it
local SKYRIDING_AURA = 404464 -- "Flight Style: Skyriding" on the player (confirmed in game)
local TRAVEL_FORMS = { [783] = true, [210053] = true, [2645] = true } -- Travel Form, Mount Form, Ghost Wolf
local MAX_DEPTH = 10 -- map levels walked up from where you stand; a guard against a parent loop
local MOUNT_ICON = "Interface\\Icons\\Ability_Mount_Charger"
local POOL_CHOICES = { { value = "favorites", text = "Favorites first" },
	{ value = "favoritesOnly", text = "Favorites only" }, { value = "all", text = "All mounts" } }
local TRAVEL_FORM_CHOICES = { { value = "never", text = "Never" }, { value = "moving", text = "While moving" },
	{ value = "always", text = "Outdoors" } }
-- Forever's Ghost Wolf has a cast time: no form on the move, so "moving" only leaves the form's line in the combat macro.
local CAST_FORM_CHOICES = { { value = "never", text = "Never" }, { value = "moving", text = "In combat" },
	{ value = "always", text = "Outdoors" } }
local FROM_FORM_CHOICES = { { value = "leave", text = "Leaves the form" }, { value = "mount", text = "Summons a mount" } }

local module, db, button
local lastMount
local nextMount -- the mountID the action bar macro shows; the next press takes it when it still suits
local lastWhy -- details of the latest press, for /tomte mount why
local pickKey -- the situation nextMount was picked in (PickKey)
local mountIDs -- C_MountJournal.GetMountIDs(), once a session (NEW_MOUNT_ADDED reads it again)
local mountTypes = {} -- [mountID] = mount type ID, which doesn't change

local function MountIDs()
	if not mountIDs then
		local list = C_MountJournal.GetMountIDs()
		if not list or #list == 0 then
			return list or {} -- the journal isn't loaded yet: not kept
		end
		mountIDs = list
	end
	return mountIDs
end

local function MountType(mountID)
	local typeID = mountTypes[mountID]
	if typeID == nil then
		typeID = select(5, C_MountJournal.GetMountInfoExtraByID(mountID))
		mountTypes[mountID] = typeID
	end
	return typeID
end

-- mapIDs from where you stand up to the world (zone, continent, ...), with their infos.
function ns.Mount_Chain()
	local chain, infos = {}, {}
	local mapID = C_Map.GetBestMapForUnit("player")
	while mapID and mapID > 0 and #chain < MAX_DEPTH do
		local info = C_Map.GetMapInfo(mapID)
		if not info then
			break
		end
		chain[#chain + 1] = mapID
		infos[#infos + 1] = info
		mapID = info.parentMapID
	end
	return chain, infos
end

-- The form index (1..n) of a travel-like form this character has, for "/cancelform [form:n]" in combat.
local function TravelFormIndex()
	for i = 1, GetNumShapeshiftForms() do
		local _, _, _, spellID = GetShapeshiftFormInfo(i)
		if spellID and TRAVEL_FORMS[spellID] then
			return i
		end
	end
	return nil
end

local function InTravelForm()
	local index = GetShapeshiftForm()
	if not index or index == 0 then
		return false
	end
	local _, _, _, spellID = GetShapeshiftFormInfo(index)
	return spellID ~= nil and TRAVEL_FORMS[spellID] == true
end

-- A usable mount as a candidate, or nil. stats counts why mounts were left out, for /tomte mount why.
local function Candidate(mountID, stats)
	local name, spellID, icon, _, isUsable, _, isFavorite, _, _, _, isCollected, _, isSteadyFlight = C_MountJournal.GetMountInfoByID(mountID)
	if not name or not isCollected then
		return nil
	end
	stats.collected = stats.collected + 1
	if not isUsable then
		stats.notUsable = stats.notUsable + 1
		return nil
	end
	local usableHere, useError = C_MountJournal.GetMountUsabilityByID(mountID, true)
	if not usableHere then
		local reason = useError or "?"
		stats.errors[reason] = (stats.errors[reason] or 0) + 1
		return nil
	end
	local typeID = MountType(mountID)
	local info = ns.Mount_TypeInfo(typeID)
	return {
		id = mountID, name = name, spellID = spellID, icon = icon, typeID = typeID, steady = isSteadyFlight,
		favorite = isFavorite, flying = info.flying, aquatic = info.aquatic, swimOnly = info.swimOnly,
		class = ns.MOUNT_CLASS[mountID] or false, passenger = ns.MOUNT_PASSENGER[mountID] or false,
	}
end

-- The zone favorites list for where you stand, as a set of mountIDs, and its map's name.
local function ZoneFavorites()
	if not db.useZones then
		return nil
	end
	local chain, infos = ns.Mount_Chain()
	local list, mapID = ns.Mount_ZoneList(chain, db.zones)
	if not list then
		return nil
	end
	local set = {}
	for _, id in ipairs(list) do
		set[id] = true
	end
	for i, id in ipairs(chain) do
		if id == mapID then
			return set, infos[i].name
		end
	end
	return set, tostring(mapID)
end

local function PassengerFirst()
	return db.passenger and IsInGroup()
end

-- Candidate tiers, in order (Data.lua's Mount_Tiers), from one pass over the journal.
local function Tiers(stats)
	local zoneSet, zoneName = ZoneFavorites()
	local all = {}
	for _, mountID in ipairs(MountIDs()) do
		local c = Candidate(mountID, stats)
		if c then
			c.zone = zoneSet and zoneSet[mountID] or false
			all[#all + 1] = c
		end
	end
	stats.usable = #all
	return ns.Mount_Tiers(all, {
		pool = db.pool, classFirst = db.classMounts, passengerFirst = PassengerFirst(), zoneName = zoneName,
	})
end

-- Forever has no flying of any kind, so every context there is ground or water, whatever a mount's type says.
local function CanFlyHere()
	return not ns.FOREVER and (IsFlyableArea() or IsAdvancedFlyableArea())
end

local function Skyriding()
	return not ns.FOREVER and C_UnitAuras.GetPlayerAuraBySpellID(SKYRIDING_AURA) ~= nil
end

-- Below the water surface: the breath timer is running down. IsSubmerged and IsSwimming are true on the surface too
-- (measured in 12.1). A water-breathing buff hides the timer, so then it counts as the surface.
local MIRROR_TIMERS = MIRRORTIMER_NUMTIMERS or 3 -- fatigue, breath, feign death; the global is gone in 12.1
local function Underwater()
	for i = 1, MIRROR_TIMERS do
		local timer, _, _, scale = GetMirrorTimerInfo(i)
		if timer == "BREATH" and scale < 0 then
			return true
		end
	end
	return false
end

-- Picks a mount for where you are, taking `prefer` (the one the macro shows) when it suits. Returns the mount (or
-- nil) and the details for /tomte mount why.
local function Context()
	return ns.Mount_Context({
		submerged = IsSubmerged(),
		underwater = Underwater(),
		flyable = CanFlyHere(),
		indoors = IsIndoors(),
	})
end

local function Choose(prefer)
	local context = Context()
	local skyriding = Skyriding()
	local stats = { collected = 0, notUsable = 0, usable = 0, errors = {} }
	local mount, source = ns.Mount_PickTiered(Tiers(stats), context, {
		preferGround = db.preferGround,
		skyriding = skyriding,
		avoid = db.noRepeat and lastMount or nil,
		prefer = prefer,
	}, math.random)
	return mount, { context = context, skyriding = skyriding, source = source, stats = stats, mount = mount }
end

-- A repair mount (the Ctrl press), suiting the spot when one does.
local function ChooseRepair()
	local stats = { collected = 0, notUsable = 0, usable = 0, errors = {} }
	local repair = {}
	for mountID in pairs(ns.MOUNT_REPAIR) do
		local c = Candidate(mountID, stats)
		if c then
			repair[#repair + 1] = c
		end
	end
	stats.usable = #repair
	local context = Context()
	local mount = ns.Mount_Pick(repair, context, {}, math.random)
	return mount, { context = context, source = "repair mounts", stats = stats, mount = mount }
end

-- The travel form's spell name when it beats a mount here (Data.lua's Mount_UseForm), or nil. moving: false for the
-- action bar macro, which can't tell.
local function FormFirst(moving)
	local spell, flies = ns.MountForms_Travel()
	if not spell then
		return nil
	end
	local use = ns.Mount_UseForm({
		mode = db.travelForm, moving = moving, indoors = IsIndoors(), formFlies = flies and not ns.FOREVER,
		context = Context(), castTime = ns.MountForms_CastTime(),
	})
	return use and spell or nil
end

-- The form to take indoors when no mount can be, or nil.
local function IndoorForm()
	return db.indoorForm and IsIndoors() and ns.MountForms_Indoor() or nil
end

local function SetMacro(text)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", text)
end

-- What the key does in combat: only ways out (mounting isn't possible in combat), and with the travel form setting on,
-- into the form (forms work in combat). The /cast comes first so leaving the form can't be followed by taking it again.
local function CombatMacro()
	local ground = db.keepFlying and ",noflying" or ""
	local lines = { "/leavevehicle [canexitvehicle]", ("/dismount [mounted%s]"):format(ground) }
	local form = TravelFormIndex()
	if form then
		lines[#lines + 1] = ("/cancelform [form:%d%s]"):format(form, ground)
		local spell, flies = ns.MountForms_Travel()
		if spell and db.travelForm ~= "never" then
			-- Travel Form is outdoors only; Ghost Wolf runs indoors too.
			table.insert(lines, 1, ("/cast [%snomounted,novehicleui,noform:%d] %s"):format(flies and "outdoors," or "",
				form, spell))
		end
	end
	return table.concat(lines, "\n")
end

-- The G-99 Breakneck's spell name when you can call it here (Undermine): its zone ability, or the journal mount of
-- that name if it's usable. The zone ability is spell 1215279 (D.R.I.V.E.), which Undermine overrides with 460013
-- and the Liberation of Undermine raid with 1218373 (IDs from LiteMount's notes); the English name is the fallback.
local G99_SPELLS = { [1215279] = true, [460013] = true, [1218373] = true }
local G99_PATTERN = "^G%-99"
local G99_RECHECK = 60 -- seconds before looking through the journal again when it isn't collected
local g99Mount, g99LookedAt -- its journal ID once found
local function G99Mount()
	if g99Mount then
		return g99Mount
	end
	local now = GetTime()
	if g99LookedAt and now - g99LookedAt < G99_RECHECK then
		return nil
	end
	g99LookedAt = now
	for _, mountID in ipairs(MountIDs()) do
		local name, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
		if name and isCollected and name:find(G99_PATTERN) then
			g99Mount = mountID
			return mountID
		end
	end
	return nil
end

-- The mount's spell name when it's usable where you stand, or nil.
local function StillUsable(mountID)
	local name, spellID, _, _, isUsable = C_MountJournal.GetMountInfoByID(mountID)
	if name and isUsable and C_MountJournal.GetMountUsabilityByID(mountID, true) then
		return C_Spell.GetSpellName(spellID) or name
	end
	return nil
end

local function G99Spell()
	if ns.FOREVER then
		return nil -- Undermine's mount: no such place there
	end
	for _, ability in ipairs(C_ZoneAbility.GetActiveAbilities() or {}) do
		local name = C_Spell.GetSpellName(ability.spellID)
		if name and (G99_SPELLS[ability.spellID] or name:find(G99_PATTERN)) then
			return name
		end
	end
	local mountID = G99Mount()
	if not mountID then
		return nil
	end
	return StillUsable(mountID)
end

-- Casts mount (after `before`, a line run first), for the key and /tomte mount why.
local function CastMount(mount, before)
	lastMount = mount.id
	-- /cast by name, like a hand-made mount macro. The spell name, not the journal name: they can differ.
	local text = (before or "") .. "/cast " .. (C_Spell.GetSpellName(mount.spellID) or mount.name)
	SetMacro(text)
	lastWhy.macro = text
end

local function CastForm(spell, why)
	SetMacro("/cast " .. spell)
	lastWhy = { context = why, macro = "/cast " .. spell }
end

-- In travel form / Ghost Wolf: leave it, or with "summons a mount" go straight onto one (not in the air or on the move,
-- where a mount can't be cast).
local function LeaveForm()
	if db.fromForm == "mount" and not IsFlying() and not ns.MountForms_Moving() then
		local mount
		mount, lastWhy = Choose()
		nextMount = nil
		if mount then
			CastMount(mount, "/cancelform\n")
			return
		end
	end
	SetMacro("/cancelform")
end

-- Not mounted: the repair mount (MiddleButton), the G-99, the travel form, a mount, or the indoor form.
local function MountUp(mouseButton)
	if mouseButton == "MiddleButton" and not ns.FOREVER then -- no repair mounts confirmed there: an ordinary press
		local mount
		mount, lastWhy = ChooseRepair()
		if mount then
			CastMount(mount)
		else
			SetMacro("")
			UIErrorsFrame:AddMessage("Smart Mount: no repair mount you can use here.", ns.UI.RGB("heading"))
		end
		return
	end
	local g99 = db.g99 and mouseButton ~= "RightButton" and G99Spell()
	if g99 then
		CastForm(g99, "G-99 (Shift or the \"normal mount\" key for a mount)")
		return
	end
	local form = FormFirst(ns.MountForms_Moving())
	if form then
		CastForm(form, "travel form (settings: Druids and shamans)")
		return
	end
	local mount
	mount, lastWhy = Choose(nextMount)
	nextMount = nil
	if mount then
		CastMount(mount)
		return
	end
	local indoor = IndoorForm()
	if indoor then
		CastForm(indoor, "indoors, no mount")
		return
	end
	SetMacro("")
	UIErrorsFrame:AddMessage(IsIndoors() and "Smart Mount: you can't mount indoors."
		or "Smart Mount: no usable mount here.", ns.UI.RGB("heading"))
end

-- LeftButton = the Smart Mount key, RightButton = "normal mount" (its own binding, and Shift + your Smart Mount key),
-- MiddleButton = "repair mount" (its own binding, and Ctrl + your Smart Mount key). Modifiers can't be read here:
-- during a binding's click IsShiftKeyDown() is false even with Shift held (measured).
local downSeen = false
local function PreClick(_, mouseButton, down)
	-- Every press brings a down and an up click: the key binding (the button is registered for both), and the action
	-- bar macro's two /click lines when it falls back to clicking the button (Data.lua's Mount_MacroBody: no spell to
	-- show, or over 255 characters; normally the bar macro casts the mount itself). Only one of them acts (the down
	-- one for a key, the up one for a mouse click), so the up click keeps the down click's pick instead of choosing
	-- again.
	if down then
		downSeen = true
	elseif downSeen then
		downSeen = false
		return
	end
	if InCombatLockdown() then
		return
	end
	if not module.active then
		button:SetAttribute("type", nil)
		return
	end
	if CanExitVehicle() then
		SetMacro("/leavevehicle")
	elseif (IsMounted() or InTravelForm()) and IsFlying() and db.keepFlying then
		SetMacro("")
		-- Forever has no such setting: a flight path is the only way to be in the air.
		UIErrorsFrame:AddMessage(ns.FOREVER and "Smart Mount: land first."
			or "Smart Mount: land first (or turn off \"Don't dismount while flying\").", ns.UI.RGB("heading"))
	elseif IsMounted() then
		SetMacro("/dismount")
	elseif InTravelForm() then
		LeaveForm()
	else
		MountUp(mouseButton)
	end
end

local function CreateButton()
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:Hide() -- clicked through the binding or the action bar macro's /click fallback only
	-- Up too: a mouse click on the action bar macro's /click fallback acts on the up click.
	button:RegisterForClicks("AnyDown", "AnyUp")
	button:SetAttribute("useOnKeyDown", true)
	button:SetScript("PreClick", PreClick)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

-- Fires just before the combat lockdown starts, so attributes can still be set here.
function events:PLAYER_REGEN_DISABLED()
	SetMacro(CombatMacro())
end

-- Shift + your Smart Mount key works as the "normal mount" key (a mount instead of the G-99), and Ctrl + it as the
-- "repair mount" key (with that setting on), unless you've bound that combination to something else. Override bindings
-- can't change in combat: redone after it.
local BINDING = "CLICK " .. BUTTON_NAME .. ":LeftButton"
local OUR_BINDINGS = {
	[""] = true, [BINDING] = true, ["CLICK " .. BUTTON_NAME .. ":RightButton"] = true,
	["CLICK " .. BUTTON_NAME .. ":MiddleButton"] = true,
}
local modifierPending = false

local function BindModifier(combo, mouseButton)
	if OUR_BINDINGS[GetBindingAction(combo)] then
		SetOverrideBindingClick(events, false, combo, BUTTON_NAME, mouseButton)
	end
end

local function UpdateModifierBindings()
	if InCombatLockdown() then
		modifierPending = true
		return
	end
	modifierPending = false
	ClearOverrideBindings(events)
	-- Forever: no G-99 or repair mount for these combinations to reach, so they stay free for the player's own use.
	if not module.active or ns.FOREVER then
		return
	end
	for _, key in ipairs({ GetBindingKey(BINDING) }) do
		if not key:find("-", 2, true) then
			BindModifier("SHIFT-" .. key, "RightButton")
			if db.repairKey then
				BindModifier("CTRL-" .. key, "MiddleButton")
			end
		end
	end
end

-- The action bar macro (/tomte mount macro): Tomte keeps it showing and casting what the key would summon (text from
-- Data.lua's Mount_MacroBody), so the bar greys it out when you can't mount, like a mount spell on your bar. Only
-- touched while the macro exists and out of combat (macros can't be edited in combat).
local MACRO_NAME = "Smart Mount"
local MACRO_ICON = 134400 -- the question mark: the icon then follows #showtooltip
local MAX_GENERAL_MACROS = 120

-- The mount you ride: its mountID and spell name, or nil.
local function ActiveMount()
	if lastMount then -- usually the one the key summoned: no journal scan
		local _, spellID, _, isActive = C_MountJournal.GetMountInfoByID(lastMount)
		if isActive then
			return lastMount, C_Spell.GetSpellName(spellID)
		end
	end
	for _, mountID in ipairs(MountIDs()) do
		local _, spellID, _, isActive = C_MountJournal.GetMountInfoByID(mountID)
		if isActive then
			return mountID, C_Spell.GetSpellName(spellID)
		end
	end
	return nil
end

local function ActiveMountSpell()
	local _, spell = ActiveMount()
	return spell
end

-- What a pick depends on besides the mount itself: when it's unchanged and the shown mount is still usable, the
-- macro keeps it without going through the whole journal (zone changes and usability events come often).
local function PickKey()
	local list, zoneMap = nil, nil
	if db.useZones then
		list, zoneMap = ns.Mount_ZoneList(ns.Mount_Chain(), db.zones)
	end
	return table.concat({
		tostring(IsSubmerged()), tostring(Underwater()), tostring(CanFlyHere()), tostring(IsIndoors()),
		tostring(Skyriding()), tostring(zoneMap),
		list and table.concat(list, ",") or "", tostring(db.preferGround), tostring(PassengerFirst()),
		tostring(InTravelForm()),
	}, ":")
end

-- The spell the macro shows: the mount you ride, the G-99, the travel form ("Outdoors" setting), the next pick (kept
-- while it still suits) or the indoor form. Second return: true when it's a mount.
local function MacroSpell()
	if IsMounted() then
		return ActiveMountSpell(), true
	end
	local g99 = db.g99 and G99Spell()
	if g99 then
		return g99
	end
	local form = not InTravelForm() and FormFirst(false)
	if form then
		return form
	end
	local key = PickKey()
	local kept = nextMount and key == pickKey and StillUsable(nextMount)
	if kept then
		return kept, true
	end
	local mount = Choose(nextMount)
	nextMount, pickKey = mount and mount.id, key
	if mount then
		return C_Spell.GetSpellName(mount.spellID) or mount.name, true
	end
	return IndoorForm()
end

local function UpdateMacro()
	if InCombatLockdown() or not module.active then
		return
	end
	local index = GetMacroIndexByName(MACRO_NAME)
	if index == 0 then
		return
	end
	local spell, isMount = MacroSpell()
	if not spell then -- nothing usable: the mount it shows is greyed out anyway
		return
	end
	local body = ns.Mount_MacroBody(spell, BUTTON_NAME, {
		form = TravelFormIndex(), keepFlying = db.keepFlying, formToMount = isMount and db.fromForm == "mount",
	})
	if GetMacroBody(index) ~= body then
		EditMacro(index, nil, nil, body)
	end
end

local macroQueued = false
local function QueueMacroUpdate()
	if macroQueued then
		return
	end
	macroQueued = true
	C_Timer.After(0.5, function()
		macroQueued = false
		UpdateMacro()
	end)
end

local function MacroCommand()
	if InCombatLockdown() then
		ns.Print_Combat("make the mount macro")
		return
	end
	if not ns.Module_RequireOn(module) then
		return
	end
	if GetMacroIndexByName(MACRO_NAME) == 0 then
		if GetNumMacros() >= MAX_GENERAL_MACROS then
			ns.Print("your general macros are full, delete one first.")
			return
		end
		CreateMacro(MACRO_NAME, MACRO_ICON, ns.Mount_MacroBody(nil, BUTTON_NAME))
	end
	UpdateMacro()
	PickupMacro(MACRO_NAME)
	ns.Print("drop the \"" .. MACRO_NAME .. "\" macro on your action bar. It's greyed out when you can't mount.")
end

events.UPDATE_BINDINGS = UpdateModifierBindings

function events:PLAYER_ENTERING_WORLD()
	UpdateModifierBindings()
	QueueMacroUpdate()
end

function events:PLAYER_REGEN_ENABLED()
	if modifierPending then
		UpdateModifierBindings()
	end
	QueueMacroUpdate()
end

-- Joining or leaving a group (passenger mounts) and taking or leaving a form (the macro's form lines).
events.GROUP_ROSTER_UPDATE = QueueMacroUpdate
events.UPDATE_SHAPESHIFT_FORM = QueueMacroUpdate

events.ZONE_CHANGED = QueueMacroUpdate
events.ZONE_CHANGED_INDOORS = QueueMacroUpdate
events.ZONE_CHANGED_NEW_AREA = QueueMacroUpdate
-- Mounted, by the key or by the bar macro (which casts its shown pick itself): that mount counts as the last one
-- (for "don't repeat") and the macro picks a fresh one for the next time.
function events:PLAYER_MOUNT_DISPLAY_CHANGED()
	if IsMounted() then
		local mountID = ActiveMount()
		if mountID then
			lastMount = mountID
		end
		nextMount = nil
	end
	QueueMacroUpdate()
end
events.MOUNT_JOURNAL_USABILITY_CHANGED = QueueMacroUpdate
-- The breath timer starts when you dive and stops when you're back up: water mount or flying mount.
events.MIRROR_TIMER_START = QueueMacroUpdate
events.MIRROR_TIMER_STOP = QueueMacroUpdate

function events:NEW_MOUNT_ADDED()
	mountIDs = nil
	g99Mount, g99LookedAt = nil, nil
	pickKey = nil
	QueueMacroUpdate()
end

-- Fires after a journal favorite changes (Mount Journal Enhanced waits on it after SetIsFavorite), and on journal
-- searches: the macro picks again.
function events:MOUNT_JOURNAL_SEARCH_UPDATED()
	pickKey = nil
	QueueMacroUpdate()
end

-- A Smart Mount setting changed: the macro picks again.
local function SettingChanged()
	pickKey = nil
	QueueMacroUpdate()
end

local function Why()
	if not lastWhy then
		ns.Print("press the Smart Mount key first.")
		return
	end
	local w, st = lastWhy, lastWhy.stats
	if not st then -- the G-99 or a form, no mount was picked
		ns.Print(("%s: %s"):format(w.context, w.macro))
		return
	end
	ns.Print(("context: %s%s, picked from: %s"):format(w.context, w.skyriding and " (skyriding)" or "",
		w.source or "-"))
	print(("  mounts: %d collected, %d usable here, %d not usable on this character"):format(st.collected, st.usable,
		st.notUsable))
	for reason, n in pairs(st.errors) do
		print(("  %d not usable here: %s"):format(n, reason))
	end
	local m = w.mount
	if m then
		local kind = m.flying and "flying" or (m.swimOnly and "swim only" or (m.aquatic and "aquatic" or "ground"))
		print(("  picked %s (mountID %d, type %s = %s%s%s)"):format(m.name, m.id, tostring(m.typeID), kind,
			m.steady and ", steady flight only" or "", ns.Mount_KnownType(m.typeID) and "" or (", " .. ns.UI.Wrap("unknown type", "warning"))))
		print("  macro: " .. tostring(w.macro))
	else
		print("  nothing usable")
	end
end

local function ZoneCommand()
	local chain, infos = ns.Mount_Chain()
	local any = false
	for i, mapID in ipairs(chain) do
		local list = db.zones[mapID]
		if list then
			any = true
			local names = {}
			for _, id in ipairs(list) do
				names[#names + 1] = (C_MountJournal.GetMountInfoByID(id)) or ("#" .. id)
			end
			ns.Print(("%s: %s"):format(infos[i].name, table.concat(names, ", ")))
		end
	end
	if not any then
		ns.Print("no zone favorites here. Add some with the star in the Mount Journal.")
	end
end

-- Home's "Around you": the zone favorites for where you stand; a click summons one (out of combat).
local function ZoneList()
	return ns.Mount_ZoneList(ns.Mount_Chain(), db.zones) or {}
end

local function Summon(mountID)
	if InCombatLockdown() then
		ns.Print_Combat("summon a mount")
		return
	end
	C_MountJournal.SummonByID(mountID)
end

local AROUND = {
	kind = "around", key = "mountaround", order = 5, name = "Mount favorites", maxRows = 2,
	icon = MOUNT_ICON, openText = "Opens Mount zones",
	open = function()
		ns.Panel_OpenPage("mountzones")
	end,
	title = function()
		return ("Mount favorites: %d here"):format(#ZoneList())
	end,
	items = function(limit)
		local list = ZoneList()
		local rows = {}
		for i = 1, math.min(limit, #list) do
			local mountID = list[i]
			local name, _, icon, active = C_MountJournal.GetMountInfoByID(mountID)
			local usable = C_MountJournal.GetMountUsabilityByID(mountID, true)
			rows[i] = {
				icon = icon, text = name or ("#" .. mountID), right = active and "riding" or (not usable and "not here" or nil),
				onClick = function()
					Summon(mountID)
				end,
				onEnter = function(row)
					GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
					GameTooltip:SetText(name or ("#" .. mountID), ns.UI.Color("heading"))
					GameTooltip:AddLine("Click: summon it", ns.UI.RGB("heading"))
					GameTooltip:Show()
				end,
			}
		end
		return rows
	end,
}

module = ns.RegisterModule({
	key = "mount",
	name = "Smart Mount",
	category = "travel",
	icon = 132226, -- ability_mount_charger
	summary = "One key that picks the right mount for where you are.",
	description = ns.FOREVER and "One key (Key Bindings > Tomte > Smart Mount) that summons a mount, from your zone favorites, then your journal favorites. Pressed again it dismounts, leaves a vehicle or leaves travel form. Set zone favorites with the star in the Mount Journal. /tomte mount macro makes an action bar macro that does the same and is greyed out when you can't mount."
		or "One key (Key Bindings > Tomte > Smart Mount) that summons a mount that fits where you are: swimming, flying or ground, from your zone favorites, then your journal favorites. Pressed again it dismounts, leaves a vehicle or leaves travel form. Set zone favorites with the star in the Mount Journal. /tomte mount macro makes an action bar macro that does the same and is greyed out when you can't mount.",
	enabledByDefault = true,
	defaults = {
		zones = {}, -- [mapID] = { mountID, ... }, account-wide like mounts
		useZones = true,
		preferGround = true,
		noRepeat = true,
		keepFlying = true,
		g99 = true,
		pool = "favorites", -- "favorites" | "favoritesOnly" | "all" (Data.lua's Mount_Tiers)
		classMounts = false,
		passenger = false,
		repairKey = true,
		travelForm = "moving", -- "never" | "moving" | "always" (Data.lua's Mount_UseForm)
		indoorForm = true,
		fromForm = "leave", -- in travel form the key: "leave" | "mount"
	},
	init = function(moduleDB)
		db = moduleDB
		ns.mountDB = db -- for Journal.lua and ZonesPage.lua; settings resets refill this same table
		CreateButton()
		ns.MountJournal_Init()
	end,
	toggle = function(active)
		if active then
			events:RegisterEvent("PLAYER_REGEN_DISABLED")
			events:RegisterEvent("PLAYER_REGEN_ENABLED")
			events:RegisterEvent("UPDATE_BINDINGS")
			events:RegisterEvent("PLAYER_ENTERING_WORLD")
			events:RegisterEvent("ZONE_CHANGED")
			events:RegisterEvent("ZONE_CHANGED_INDOORS")
			events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
			events:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
			events:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
			events:RegisterEvent("NEW_MOUNT_ADDED")
			events:RegisterEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
			events:RegisterEvent("MIRROR_TIMER_START")
			events:RegisterEvent("MIRROR_TIMER_STOP")
			events:RegisterEvent("GROUP_ROSTER_UPDATE")
			events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
			QueueMacroUpdate()
		else
			events:UnregisterAllEvents()
		end
		UpdateModifierBindings()
		if not InCombatLockdown() then
			button:SetAttribute("type", nil)
		end
		ns.MountJournal_Refresh()
	end,
	commands = {
		{ "why", "context, pool and pick of your last press", Why },
		{ "zone", "zone favorites where you stand", ZoneCommand },
		{ "macro", "make the action bar macro (greyed out when you can't mount)", MacroCommand },
	},
	options = {
		{ type = "header", label = "Picking" },
		{ type = "dropdown", key = "pool", label = "Pick from", onChange = SettingChanged, choices = function()
			return POOL_CHOICES
		end, tooltip = "Favorites first: your journal favorites, and every mount when none of them suits the spot. Favorites only: never a mount you didn't favorite (unless you have none). All mounts: favorites count like any other mount." },
		{ type = "checkbox", key = "useZones", label = "Use zone favorites", onChange = SettingChanged,
			tooltip = "Mounts starred for the zone you're in (or its continent) come first. Set them with the star in the Mount Journal." },
		{ type = "checkbox", key = "classMounts", label = "Class mounts first", onChange = SettingChanged,
			tooltip = ns.FOREVER and "Your class's own mounts (a paladin's charger, a warlock's dreadsteed) come before your journal favorites."
				or "Your class's own mounts (a paladin's charger, a warlock's dreadsteed, the class hall mounts) come before your journal favorites." },
		{ type = "checkbox", key = "passenger", label = "Passenger mount in a group", onChange = SettingChanged,
			shown = ns.NotForever, -- its list is retail's mounts
			tooltip = "In a party or raid, a mount with a seat for a friend comes first (Traveler's Tundra Mammoth, Grand Expedition Yak, Sandstone Drake and others), if one suits the spot." },
		{ type = "checkbox", key = "preferGround", label = "Ground mounts on the ground", onChange = SettingChanged,
			shown = ns.NotForever, -- no flying there
			tooltip = "Where you can't fly, use ground mounts if the pool has any. Off: flying mounts can be picked too." },
		{ type = "checkbox", key = "noRepeat", label = "Avoid the same mount twice in a row", onChange = SettingChanged },
		{ type = "checkbox", key = "g99", label = "G-99 Breakneck in Undermine", onChange = SettingChanged,
			shown = ns.NotForever,
			tooltip = "Where the G-99 can be called, the key calls it instead of a mount. Shift + your Smart Mount key (or the \"normal mount\" key binding) gives a normal mount." },
		{ type = "checkbox", key = "repairKey", label = "Ctrl for a repair mount", onChange = function()
			UpdateModifierBindings()
		end, shown = ns.NotForever, tooltip = "Ctrl + your Smart Mount key summons a mount with a vendor who repairs (Grand Expedition Yak, Traveler's Tundra Mammoth, Mighty Caravan Brutosaur or Grizzly Hills Packmaster). Not when that Ctrl combination is bound to something else. The \"repair mount\" key binding works either way." },
		{ type = "header", label = "Druids and shamans" },
		{ type = "dropdown", key = "travelForm", label = "Travel form instead of a mount", onChange = SettingChanged,
			shown = ns.MountForms_Class, choices = function()
				return ns.FOREVER and ns.MountForms_CastTime() and CAST_FORM_CHOICES or TRAVEL_FORM_CHOICES
			end, tooltip = ns.FOREVER and "Travel Form or Ghost Wolf. While moving (druid): when you're running or falling, where a mount can't be summoned, and in combat. In combat (shaman): Ghost Wolf takes a moment to cast, so not on the move. Outdoors: always on land."
				or "Travel Form or Ghost Wolf. While moving: when you're running or falling, where a mount can't be summoned (also in combat). Outdoors: always, except where Ghost Wolf can't fly or swim and a mount can." },
		{ type = "checkbox", key = "indoorForm", label = ns.FOREVER and "Cat Form indoors" or "Cat Form or Ghost Wolf indoors", onChange = SettingChanged,
			shown = ns.FOREVER and ns.MountForms_HasIndoor or ns.MountForms_Class,
			tooltip = ns.FOREVER and "Where you can't mount, the key takes Cat Form instead."
				or "Where you can't mount, the key takes Cat Form (druid) or Ghost Wolf (shaman) instead." },
		{ type = "dropdown", key = "fromForm", label = "In travel form, the key", onChange = SettingChanged,
			shown = ns.MountForms_Class, choices = function()
				return FROM_FORM_CHOICES
			end, tooltip = "Summons a mount: on the ground, the key goes straight from the form onto a mount." },
		{ type = "header", label = "Dismounting", shown = ns.NotForever },
		{ type = "checkbox", key = "keepFlying", label = "Don't dismount while flying", onChange = SettingChanged,
			shown = ns.NotForever,
			tooltip = "The key does nothing in the air, so you can't fall off by accident." },
	},
	home = {
		{ kind = "page", key = "mountzones", order = 5, name = "Mount zones", icon = MOUNT_ICON,
			page = ns.MountZonesPage,
			summary = function()
				local list = ns.Mount_ZoneList(ns.Mount_Chain(), db.zones)
				local n = list and #list or 0
				return n == 1 and "1 zone favorite here" or (n .. " zone favorites here")
			end },
		AROUND,
	},
})
ns.mountModule = module

_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Smart Mount"
-- Bindings.xml is shared, so Forever keeps these two rows; with no G-99 or repair mount there they're the same key.
_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":RightButton"] = ns.FOREVER and "Smart Mount (second key)"
	or "Smart Mount: normal mount (not the G-99)"
_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":MiddleButton"] = ns.FOREVER and "Smart Mount (third key)"
	or "Smart Mount: repair mount"
