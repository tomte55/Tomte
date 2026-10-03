local addonName, ns = ...

-- Smart Mount: one key binding (Tomte > Smart Mount) on a secure button. Out of combat its PreClick looks at the
-- situation and sets the button up: leave the vehicle, dismount, leave travel form / Ghost Wolf, or cast a mount
-- picked for where you are (zone favorites, then journal favorites, then every usable mount). In combat the
-- attributes can't change, so entering combat leaves a macro that only gets you out. Rules in Data.lua.

local BUTTON_NAME = "TomteSmartMount" -- global: the CLICK binding in Bindings.xml needs it
local SKYRIDING_AURA = 404464 -- "Flight Style: Skyriding" on the player (test in game)
local TRAVEL_FORMS = { [783] = true, [210053] = true, [2645] = true } -- Travel Form, Mount Form, Ghost Wolf
local MAX_DEPTH = 10

local module, db, button
local lastMount
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

local function Candidate(mountID)
	local name, spellID, icon, _, isUsable, _, _, _, _, _, isCollected, _, isSteadyFlight = C_MountJournal.GetMountInfoByID(mountID)
	if not name or not isCollected or not isUsable or not C_MountJournal.GetMountUsabilityByID(mountID, true) then
		return nil
	end
	local typeID = select(5, C_MountJournal.GetMountInfoExtraByID(mountID))
	local info = ns.Mount_TypeInfo(typeID)
	return {
		id = mountID, name = name, spellID = spellID, icon = icon, typeID = typeID, steady = isSteadyFlight,
		flying = info.flying, aquatic = info.aquatic, swimOnly = info.swimOnly,
	}
end

local function Candidates(ids, favoritesOnly)
	local list = {}
	for _, mountID in ipairs(ids) do
		if not favoritesOnly or select(7, C_MountJournal.GetMountInfoByID(mountID)) then
			local c = Candidate(mountID)
			if c then
				list[#list + 1] = c
			end
		end
	end
	return list
end

-- The usable candidates and where they came from: zone favorites, journal favorites, or all mounts.
local function Pool()
	if db.useZones then
		local chain, infos = ns.Mount_Chain()
		local list, mapID = ns.Mount_ZoneList(chain, ns.mountDB.zones)
		if list then
			local pool = Candidates(list)
			if #pool > 0 then
				local name = mapID
				for i, id in ipairs(chain) do
					if id == mapID then
						name = infos[i].name
					end
				end
				return pool, "zone favorites (" .. name .. ")"
			end
		end
	end
	local all = C_MountJournal.GetMountIDs()
	local pool = Candidates(all, true)
	if #pool > 0 then
		return pool, "journal favorites"
	end
	return Candidates(all), "all mounts"
end

local function Choose()
	local context = ns.Mount_Context({
		submerged = IsSubmerged(),
		flyable = IsFlyableArea() or IsAdvancedFlyableArea(),
		indoors = IsIndoors(),
	})
	local skyriding = C_UnitAuras.GetPlayerAuraBySpellID(SKYRIDING_AURA) ~= nil
	local pool, source = Pool()
	local mount = ns.Mount_Pick(pool, context, {
		preferGround = db.preferGround,
		skyriding = skyriding,
		avoid = db.noRepeat and lastMount or nil,
	}, math.random)
	lastWhy = { context = context, skyriding = skyriding, source = source, count = #pool, mount = mount }
	return mount
end

local function SetMacro(text)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", text)
end

-- What the key does in combat: only ways out (mounting isn't possible in combat).
local function CombatMacro()
	local lines = { "/leavevehicle [canexitvehicle]", "/dismount [mounted,noflying]" }
	local form = TravelFormIndex()
	if form then
		lines[#lines + 1] = ("/cancelform [form:%d]"):format(form)
	end
	return table.concat(lines, "\n")
end

local function PreClick()
	if InCombatLockdown() then
		return
	end
	if not module.active then
		button:SetAttribute("type", nil)
		return
	end
	if CanExitVehicle() then
		SetMacro("/leavevehicle")
	elseif IsMounted() then
		if IsFlying() and db.keepFlying then
			SetMacro("")
			UIErrorsFrame:AddMessage("Smart Mount: land first (or turn off \"Don't dismount while flying\").", 1, 0.82, 0)
		else
			SetMacro("/dismount")
		end
	elseif InTravelForm() then
		SetMacro("/cancelform")
	else
		local mount = Choose()
		if mount then
			lastMount = mount.id
			button:SetAttribute("type", "spell")
			button:SetAttribute("spell", mount.spellID)
		else
			SetMacro("")
			UIErrorsFrame:AddMessage("Smart Mount: no usable mount here.", 1, 0.82, 0)
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

local function Why()
	if not lastWhy then
		ns.Print("press the Smart Mount key first.")
		return
	end
	local w = lastWhy
	ns.Print(("context: %s%s, pool: %s (%d usable)"):format(w.context, w.skyriding and " (skyriding)" or "",
		w.source, w.count))
	local m = w.mount
	if m then
		local kind = m.flying and "flying" or (m.swimOnly and "swim only" or (m.aquatic and "aquatic" or "ground"))
		print(("  picked %s (mountID %d, type %s = %s%s%s)"):format(m.name, m.id, tostring(m.typeID), kind,
			m.steady and ", steady flight only" or "", ns.Mount_KnownType(m.typeID) and "" or ", |cffff9940unknown type|r"))
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

module = ns.RegisterModule({
	key = "mount",
	name = "Smart Mount",
	category = "Travel",
	description = "One key (Key Bindings > Tomte > Smart Mount) that summons a mount that fits where you are: swimming, flying or ground, from your zone favorites, then your journal favorites. Pressed again it dismounts, leaves a vehicle or leaves travel form. Set zone favorites with the star in the Mount Journal.",
	enabledByDefault = true,
	defaults = {
		zones = {}, -- [mapID] = { mountID, ... }, account-wide like mounts
		useZones = true,
		preferGround = true,
		noRepeat = true,
		keepFlying = true,
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
		else
			events:UnregisterAllEvents()
		end
		if not InCombatLockdown() then
			button:SetAttribute("type", nil)
		end
		ns.MountJournal_Refresh()
	end,
	commands = {
		{ "why", "context, pool and pick of your last press", Why },
		{ "zone", "zone favorites where you stand", ZoneCommand },
	},
	options = {
		{ type = "header", label = "Picking" },
		{ type = "checkbox", key = "useZones", label = "Use zone favorites",
			tooltip = "Mounts starred for the zone you're in (or its continent) come first. Set them with the star in the Mount Journal." },
		{ type = "checkbox", key = "preferGround", label = "Ground mounts on the ground",
			tooltip = "Where you can't fly, use ground mounts if the pool has any. Off: flying mounts can be picked too." },
		{ type = "checkbox", key = "noRepeat", label = "Avoid the same mount twice in a row" },
		{ type = "header", label = "Dismounting" },
		{ type = "checkbox", key = "keepFlying", label = "Don't dismount while flying",
			tooltip = "The key does nothing in the air, so you can't fall off by accident." },
	},
	page = ns.MountZonesPage,
})
ns.mountModule = module

_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Smart Mount"
