local addonName, ns = ...

-- Smart Mount: one key binding (Tomte > Smart Mount) on a secure button. Out of combat its PreClick looks at the
-- situation and sets the button up: leave the vehicle, dismount, leave travel form / Ghost Wolf, or cast a mount
-- picked for where you are (zone favorites, then journal favorites, then every usable mount). In combat the
-- attributes can't change, so entering combat leaves a macro that only gets you out. Rules in Data.lua.

local BUTTON_NAME = "TomteSmartMount" -- global: the CLICK binding in Bindings.xml needs it
local SKYRIDING_AURA = 404464 -- "Flight Style: Skyriding" on the player (confirmed in game)
local TRAVEL_FORMS = { [783] = true, [210053] = true, [2645] = true } -- Travel Form, Mount Form, Ghost Wolf
local MAX_DEPTH = 10

local module, db, button
local lastMount
local nextMount -- the mountID the action bar macro shows; the next press takes it when it still suits
local lastWhy -- details of the latest press, for /tomte mount why

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
	local typeID = select(5, C_MountJournal.GetMountInfoExtraByID(mountID))
	local info = ns.Mount_TypeInfo(typeID)
	return {
		id = mountID, name = name, spellID = spellID, icon = icon, typeID = typeID, steady = isSteadyFlight,
		favorite = isFavorite, flying = info.flying, aquatic = info.aquatic, swimOnly = info.swimOnly,
	}
end

-- The zone favorites list for where you stand, as a set of mountIDs, and its map's name.
local function ZoneFavorites()
	if not db.useZones then
		return nil
	end
	local chain, infos = ns.Mount_Chain()
	local list, mapID = ns.Mount_ZoneList(chain, ns.mountDB.zones)
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

-- Candidate tiers, in order: zone favorites, journal favorites, all usable mounts (one pass over the journal).
local function Tiers(stats)
	local zoneSet, zoneName = ZoneFavorites()
	local zone, favorites, all = {}, {}, {}
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local c = Candidate(mountID, stats)
		if c then
			all[#all + 1] = c
			if c.favorite then
				favorites[#favorites + 1] = c
			end
			if zoneSet and zoneSet[mountID] then
				zone[#zone + 1] = c
			end
		end
	end
	stats.usable = #all
	local tiers = {}
	if #zone > 0 then
		tiers[#tiers + 1] = { source = "zone favorites (" .. zoneName .. ")", candidates = zone }
	end
	if #favorites > 0 then
		tiers[#tiers + 1] = { source = "journal favorites", candidates = favorites }
	end
	tiers[#tiers + 1] = { source = "all mounts", candidates = all }
	return tiers
end

-- Picks a mount for where you are, taking `prefer` (the one the macro shows) when it suits. Returns the mount (or
-- nil) and the details for /tomte mount why.
local function Choose(prefer)
	local context = ns.Mount_Context({
		submerged = IsSubmerged(),
		flyable = IsFlyableArea() or IsAdvancedFlyableArea(),
		indoors = IsIndoors(),
	})
	local skyriding = C_UnitAuras.GetPlayerAuraBySpellID(SKYRIDING_AURA) ~= nil
	local stats = { collected = 0, notUsable = 0, usable = 0, errors = {} }
	local mount, source = ns.Mount_PickTiered(Tiers(stats), context, {
		preferGround = db.preferGround,
		skyriding = skyriding,
		avoid = db.noRepeat and lastMount or nil,
		prefer = prefer,
	}, math.random)
	return mount, { context = context, skyriding = skyriding, source = source, stats = stats, mount = mount }
end

local function SetMacro(text)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", text)
end

-- What the key does in combat: only ways out (mounting isn't possible in combat).
local function CombatMacro()
	local ground = db.keepFlying and ",noflying" or ""
	local lines = { "/leavevehicle [canexitvehicle]", ("/dismount [mounted%s]"):format(ground) }
	local form = TravelFormIndex()
	if form then
		lines[#lines + 1] = ("/cancelform [form:%d%s]"):format(form, ground)
	end
	return table.concat(lines, "\n")
end

-- The G-99 Breakneck's spell name when you can call it here (Undermine): its zone ability, or the journal mount of
-- that name if it's usable. Matched by name because neither has a stable ID we can check against.
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
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local name, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
		if name and isCollected and name:find(G99_PATTERN) then
			g99Mount = mountID
			return mountID
		end
	end
	return nil
end

local function G99Spell()
	for _, ability in ipairs(C_ZoneAbility.GetActiveAbilities() or {}) do
		local name = C_Spell.GetSpellName(ability.spellID)
		if name and name:find(G99_PATTERN) then
			return name
		end
	end
	local mountID = G99Mount()
	if not mountID then
		return nil
	end
	local name, spellID, _, _, isUsable = C_MountJournal.GetMountInfoByID(mountID)
	if name and isUsable and C_MountJournal.GetMountUsabilityByID(mountID, true) then
		return C_Spell.GetSpellName(spellID) or name
	end
	return nil
end

-- LeftButton = the Smart Mount key, RightButton = "normal mount" (its own binding, and Shift + your Smart Mount key).
-- Modifiers can't be read here: during a binding's click IsShiftKeyDown() is false even with Shift held (measured).
local function PreClick(_, mouseButton)
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
		UIErrorsFrame:AddMessage("Smart Mount: land first (or turn off \"Don't dismount while flying\").", 1, 0.82, 0)
	elseif IsMounted() then
		SetMacro("/dismount")
	elseif InTravelForm() then
		SetMacro("/cancelform")
	else
		local g99 = db.g99 and mouseButton ~= "RightButton" and G99Spell()
		if g99 then
			SetMacro("/cast " .. g99)
			lastWhy = { context = "G-99 (Shift or the \"normal mount\" key for a mount)", macro = "/cast " .. g99 }
			return
		end
		local mount
		mount, lastWhy = Choose(nextMount)
		nextMount = nil
		if mount then
			lastMount = mount.id
			-- /cast by name, like a hand-made mount macro. The spell name, not the journal name: they can differ.
			local spell = C_Spell.GetSpellName(mount.spellID) or mount.name
			SetMacro("/cast " .. spell)
			lastWhy.macro = "/cast " .. spell
		else
			SetMacro("")
			UIErrorsFrame:AddMessage(IsIndoors() and "Smart Mount: you can't mount indoors."
				or "Smart Mount: no usable mount here.", 1, 0.82, 0)
		end
	end
end

local function CreateButton()
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:Hide() -- clicked through the binding only
	button:RegisterForClicks("AnyDown")
	button:SetAttribute("useOnKeyDown", true)
	button:SetScript("PreClick", PreClick)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

-- Fires just before the combat lockdown starts, so attributes can still be set here.
function events:PLAYER_REGEN_DISABLED()
	SetMacro(CombatMacro())
end

-- Shift + your Smart Mount key works as the "normal mount" key (a mount instead of the G-99), unless you've bound
-- that Shift combination to something else. Override bindings can't change in combat: redone after it.
local BINDING = "CLICK " .. BUTTON_NAME .. ":LeftButton"
local NORMAL_BINDING = "CLICK " .. BUTTON_NAME .. ":RightButton"
local shiftPending = false

local function UpdateShiftBindings()
	if InCombatLockdown() then
		shiftPending = true
		return
	end
	shiftPending = false
	ClearOverrideBindings(events)
	if not module.active then
		return
	end
	for _, key in ipairs({ GetBindingKey(BINDING) }) do
		local shifted = "SHIFT-" .. key
		local taken = GetBindingAction(shifted)
		if not key:find("-", 2, true) and (taken == "" or taken == BINDING or taken == NORMAL_BINDING) then
			SetOverrideBindingClick(events, false, shifted, BUTTON_NAME, "RightButton")
		end
	end
end

-- The action bar macro (/tomte mount macro): Tomte keeps its "#showtooltip <mount>" on what the key would summon,
-- so the bar greys it out when you can't mount, like a mount spell on your bar. Only touched while the macro exists
-- and out of combat (macros can't be edited in combat).
local MACRO_NAME = "Smart Mount"
local MACRO_ICON = 134400 -- the question mark: the icon then follows #showtooltip
local MAX_GENERAL_MACROS = 120

local function ActiveMountSpell()
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local _, spellID, _, isActive = C_MountJournal.GetMountInfoByID(mountID)
		if isActive then
			return C_Spell.GetSpellName(spellID)
		end
	end
	return nil
end

-- The spell the macro shows: the mount you ride, the G-99, or the next pick (kept while it still suits).
local function MacroSpell()
	if IsMounted() then
		return ActiveMountSpell()
	end
	local g99 = db.g99 and G99Spell()
	if g99 then
		return g99
	end
	local mount = Choose(nextMount)
	nextMount = mount and mount.id
	return mount and (C_Spell.GetSpellName(mount.spellID) or mount.name)
end

local function UpdateMacro()
	if InCombatLockdown() or not module.active then
		return
	end
	local index = GetMacroIndexByName(MACRO_NAME)
	if index == 0 then
		return
	end
	local spell = MacroSpell()
	if not spell then -- nothing usable: the mount it shows is greyed out anyway
		return
	end
	local body = ns.Mount_MacroBody(spell, BUTTON_NAME)
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
		ns.Print("macros can't be made in combat.")
		return
	end
	if not module.active then
		ns.Print("turn Smart Mount on first.")
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

events.UPDATE_BINDINGS = UpdateShiftBindings

function events:PLAYER_ENTERING_WORLD()
	UpdateShiftBindings()
	QueueMacroUpdate()
end

function events:PLAYER_REGEN_ENABLED()
	if shiftPending then
		UpdateShiftBindings()
	end
	QueueMacroUpdate()
end

events.ZONE_CHANGED = QueueMacroUpdate
events.ZONE_CHANGED_INDOORS = QueueMacroUpdate
events.ZONE_CHANGED_NEW_AREA = QueueMacroUpdate
events.PLAYER_MOUNT_DISPLAY_CHANGED = QueueMacroUpdate
events.MOUNT_JOURNAL_USABILITY_CHANGED = QueueMacroUpdate

local function Why()
	if not lastWhy then
		ns.Print("press the Smart Mount key first.")
		return
	end
	local w, st = lastWhy, lastWhy.stats
	if not st then -- the G-99, no mount was picked
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
			m.steady and ", steady flight only" or "", ns.Mount_KnownType(m.typeID) and "" or ", |cffff9940unknown type|r"))
		print("  macro: " .. tostring(w.macro))
	else
		print("  nothing usable")
	end
end

local function ZoneCommand()
	local chain, infos = ns.Mount_Chain()
	local any = false
	for i, mapID in ipairs(chain) do
		local list = ns.mountDB.zones[mapID]
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
		ns.Print("not in combat.")
		return
	end
	C_MountJournal.SummonByID(mountID)
end

local AROUND = {
	kind = "around", key = "mountaround", order = 5, name = "Mount favorites", maxRows = 2,
	icon = "Interface\\Icons\\Ability_Mount_Charger", openText = "Opens Mount zones",
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
					local gold = ns.UI.GOLD
					GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
					GameTooltip:SetText(name or ("#" .. mountID), 1, 1, 1)
					GameTooltip:AddLine("Click: summon it", gold[1], gold[2], gold[3])
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
	category = "Travel",
	description = "One key (Key Bindings > Tomte > Smart Mount) that summons a mount that fits where you are: swimming, flying or ground, from your zone favorites, then your journal favorites. Pressed again it dismounts, leaves a vehicle or leaves travel form. Set zone favorites with the star in the Mount Journal. /tomte mount macro makes an action bar macro that does the same and is greyed out when you can't mount.",
	enabledByDefault = true,
	defaults = {
		zones = {}, -- [mapID] = { mountID, ... }, account-wide like mounts
		useZones = true,
		preferGround = true,
		noRepeat = true,
		keepFlying = true,
		g99 = true,
	},
	init = function(moduleDB)
		db = moduleDB
		ns.mountDB = db
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
			QueueMacroUpdate()
		else
			events:UnregisterAllEvents()
		end
		UpdateShiftBindings()
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
		{ type = "checkbox", key = "useZones", label = "Use zone favorites",
			tooltip = "Mounts starred for the zone you're in (or its continent) come first. Set them with the star in the Mount Journal." },
		{ type = "checkbox", key = "preferGround", label = "Ground mounts on the ground",
			tooltip = "Where you can't fly, use ground mounts if the pool has any. Off: flying mounts can be picked too." },
		{ type = "checkbox", key = "noRepeat", label = "Avoid the same mount twice in a row" },
		{ type = "checkbox", key = "g99", label = "G-99 Breakneck in Undermine",
			tooltip = "Where the G-99 can be called, the key calls it instead of a mount. Shift + your Smart Mount key (or the \"normal mount\" key binding) gives a normal mount." },
		{ type = "header", label = "Dismounting" },
		{ type = "checkbox", key = "keepFlying", label = "Don't dismount while flying",
			tooltip = "The key does nothing in the air, so you can't fall off by accident." },
	},
	home = {
		{ kind = "page", key = "mountzones", order = 5, name = "Mount zones", icon = "Interface\\Icons\\Ability_Mount_Charger",
			page = ns.MountZonesPage,
			summary = function()
				local list = ns.Mount_ZoneList(ns.Mount_Chain(), ns.mountDB.zones)
				local n = list and #list or 0
				return n == 1 and "1 zone favorite here" or (n .. " zone favorites here")
			end },
		AROUND,
	},
})
ns.mountModule = module

_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Smart Mount"
_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":RightButton"] = "Smart Mount: normal mount (not the G-99)"
