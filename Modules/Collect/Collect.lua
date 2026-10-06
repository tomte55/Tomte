local addonName, ns = ...

-- Collect here module: mounts, battle pets and achievements still missing on the map you're looking at, in a tab of
-- the world map's side panel (Tab.lua), plus two toasts: arriving in a zone with mounts or pets left, and a rare
-- that's up and drops something you're missing. Data in Catalog.lua, pure logic in Data.lua.

local OWNER = "collect"
local START_DELAY = 6 -- seconds after the first loading screen before the journals are read
local ZONE_DELAY = 2 -- seconds after arriving before the zone toast
local DEBOUNCE = 1
local CRITERIA_DEBOUNCE = 2
local ACCENT = { 0.55, 0.85, 0.55 }
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "ACHIEVEMENT_EARNED",
	"CRITERIA_UPDATE", "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED",
}
local KIND_WORDS = { mount = "mount", pet = "pet" }

local module, db
local started = false
local toastedZones = {} -- [mapID] = true, this session
local toastedRares = {} -- [vignetteGUID] = true, this session
local vignetteTimer, criteriaTimer
local lastUpNow = "" -- the up-now set the tab last showed

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function PlayerMap()
	return C_Map.GetBestMapForUnit("player")
end

-- Counts of what's shown (hidden kinds count as none).
local function ShownCounts(entries)
	local counts = ns.Collect_Counts(entries)
	for key in pairs(counts) do
		if db.show[key] == false then
			counts[key] = 0
		end
	end
	return counts
end

-- Short source for Home's rows: the first label that isn't the zone ("Drop", "Vendor", "Pet Battle"),
-- else what it is.
local function SourceWord(e)
	if e.drop then
		return "Drop"
	end
	for _, line in ipairs(ns.Collect_ParseSource(e.source).lines) do
		if line.label ~= "zone" then
			return line.display
		end
	end
	return e.kind == "pet" and "Wild pet" or "Mount"
end

-- Toasts --------------------------------------------------------------------------------------------------------

local function ShowZoneToast(name, counts)
	ns.Toast_Show({
		owner = OWNER, label = "Collect here", accent = ACCENT, title = name,
		text = ns.Collect_ZoneToastText(counts) .. "\nClick for the list.",
		icon = "Interface\\Icons\\Ability_Mount_RidingHorse", mergeKey = "collect:zone", holdInCombat = true, hold = 10,
		onClick = ns.CollectTab_Open,
	})
end

local function ShowRareToast(rareName, e)
	ns.Toast_Show({
		owner = OWNER, label = "Up now", accent = ACCENT, title = rareName,
		text = ("Drops %s (a %s you're missing).\nClick for a waypoint."):format(e.name, KIND_WORDS[e.kind] or "drop"),
		icon = e.icon, mergeKey = "collect:rare:" .. rareName, holdInCombat = true, hold = 15,
		onClick = function()
			if e.upNow then
				ns.Collect_Waypoint(e.upNow, rareName)
			end
		end,
	})
end

local function ZoneToast()
	if not (module.active and db.toasts.zone) or InCombatLockdown() then
		return
	end
	local state = ns.Collect_State()
	if not (state.mounts and state.pets) then
		return -- tried again when the catalogs are ready
	end
	local entries, name, kind, mapID = ns.Collect_ForMap(PlayerMap())
	if not entries or kind ~= "zone" or toastedZones[mapID] then
		return
	end
	toastedZones[mapID] = true
	local counts = ShownCounts(entries)
	if counts.mounts + counts.pets > 0 then
		ShowZoneToast(name, counts)
	end
end

local function RareCheck()
	if not module.active or InCombatLockdown() then
		return
	end
	local entries, _, _, mapID = ns.Collect_ForMap(PlayerMap())
	if not entries then
		return
	end
	local found = ns.Collect_ApplyVignettes(entries, mapID)
	local keys = {}
	for _, f in ipairs(found) do
		keys[#keys + 1] = f.guid .. f.entry.kind .. f.entry.id
	end
	table.sort(keys)
	local upNow = table.concat(keys, ",")
	if db.toasts.rare then
		for _, f in ipairs(found) do
			local key = db.show[f.entry.kind == "mount" and "mounts" or "pets"] ~= false and f.guid
			if key and not toastedRares[key] then
				toastedRares[key] = true
				ShowRareToast(f.name, f.entry)
			end
		end
	end
	if upNow ~= lastUpNow then
		lastUpNow = upNow
		ns.CollectTab_Refresh()
	end
end

-- Events --------------------------------------------------------------------------------------------------------

local function Start()
	if started then
		return
	end
	started = true
	C_Timer.After(START_DELAY, function()
		if module.active then
			ns.Collect_Start()
		end
	end)
end

-- The catalogs changed (one finished, or something was earned).
local function OnChanged()
	ns.CollectTab_Refresh()
	ZoneToast()
end

function events:PLAYER_ENTERING_WORLD()
	Start()
end

function events:ZONE_CHANGED_NEW_AREA()
	C_Timer.After(ZONE_DELAY, ZoneToast)
end

function events:NEW_MOUNT_ADDED()
	ns.Collect_Earned("mount")
end

function events:NEW_PET_ADDED()
	ns.Collect_Earned("pet")
end

function events:ACHIEVEMENT_EARNED(id)
	ns.Collect_Earned("ach", id)
end

-- Progress is read live when the tab draws; this only redraws an open tab.
function events:CRITERIA_UPDATE()
	if not ns.CollectTab_IsShown() then
		return
	end
	if criteriaTimer then
		criteriaTimer:Cancel()
	end
	criteriaTimer = C_Timer.NewTimer(CRITERIA_DEBOUNCE, function()
		criteriaTimer = nil
		ns.CollectTab_Refresh()
	end)
end

local function VignettesChanged()
	if vignetteTimer then
		return
	end
	vignetteTimer = C_Timer.NewTimer(DEBOUNCE, function()
		vignetteTimer = nil
		RareCheck()
	end)
end
events.VIGNETTES_UPDATED = VignettesChanged
events.VIGNETTE_MINIMAP_UPDATED = VignettesChanged

-- Commands ------------------------------------------------------------------------------------------------------

local function RequireActive()
	if not module.active then
		ns.Print("Collect here is off.")
		return false
	end
	return true
end

local function Here()
	if not RequireActive() then
		return
	end
	local state = ns.Collect_State()
	local entries, name, kind = ns.Collect_ForMap(PlayerMap())
	if not entries then
		ns.Print("no zone here.")
		return
	end
	local counts = ns.Collect_Counts(entries)
	ns.Print(("%s (%s): %d mounts, %d pets, %d achievements%s"):format(name, kind, counts.mounts, counts.pets,
		counts.achievements, state.progress < 1 and (" (still reading the journals, %d%%)"):format(state.progress * 100) or ""))
	local names, achNames = ns.Collect_MapNames(PlayerMap())
	print("  sources match: " .. table.concat(names or {}, ", "))
	print("  achievements mention: " .. table.concat(achNames or {}, ", "))
end

local function Test()
	if not RequireActive() then
		return
	end
	ShowZoneToast("Hallowfall", { mounts = 2, pets = 3, achievements = 18 })
	ShowRareToast("Sample Rare", { kind = "mount", name = "Sample Mount", icon = 132261 })
end

local function Changed()
	ns.CollectTab_Refresh()
end

module = ns.RegisterModule({
	key = "collect",
	name = "Collect here",
	category = "Collections",
	description = "A tab in the world map's side panel with the mounts, battle pets and achievements still missing on the map you're looking at (from the journals' source text), toasts when you arrive in a zone with mounts or pets left, and when a rare that drops one is up.",
	enabledByDefault = true,
	home = {
		{ kind = "next", key = "nextrare", name = "Rare up with a missing mount or pet", score = 95,
			description = "A rare that's up now in your zone drops a mount or battle pet you're missing (click for a waypoint).",
			candidates = function()
				local state = ns.Collect_State()
				if not (state.mounts and state.pets) then
					return {}
				end
				local entries, _, _, mapID = ns.Collect_ForMap(PlayerMap())
				if not entries then
					return {}
				end
				local list = {}
				for _, f in ipairs(ns.Collect_ApplyVignettes(entries, mapID)) do
					local e = f.entry
					if db.show[e.kind == "mount" and "mounts" or "pets"] ~= false and e.upNow then
						local upNow = e.upNow
						list[#list + 1] = {
							key = "collect:rare:" .. f.name, state = f.guid,
							text = ("%s is up"):format(f.name),
							why = ("Drops %s, a %s you're missing."):format(e.name, KIND_WORDS[e.kind] or "drop"),
							icon = e.icon, bonus = e.kind == "mount" and 9 or 5,
							onClick = function()
								ns.Collect_Waypoint(upNow, f.name)
							end, hint = "Click for a waypoint",
						}
					end
				end
				return list
			end },
		{ kind = "map", key = "collect", order = 1, name = "Collect here", icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
			open = function()
				ns.CollectTab_Open()
			end,
			summary = function()
				local state = ns.Collect_State()
				if not (state.mounts and state.pets and state.achievements) then
					return "Reading your collections..."
				end
				local entries = ns.Collect_ForMap(PlayerMap())
				return entries and (ns.Collect_ZoneToastText(ShownCounts(entries)) or "Nothing left here") or nil
			end },
		{ kind = "around", key = "collectaround", order = 1, name = "Collect here", keepEmpty = true,
			icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
			open = function()
				ns.CollectTab_Open()
			end,
			title = function()
				local state = ns.Collect_State()
				if not (state.mounts and state.pets and state.achievements) then
					return "Collect here: reading your collections..."
				end
				local entries = ns.Collect_ForMap(PlayerMap())
				local text = entries and ns.Collect_ZoneToastText(ShownCounts(entries))
				return text and ("Collect here: " .. text) or "Collect here: nothing left in this zone"
			end,
			-- Mounts and pets first, then the achievements closest to done.
			items = function(limit)
				local state = ns.Collect_State()
				local entries = state.mounts and state.pets and state.achievements and ns.Collect_ForMap(PlayerMap())
				if not entries or limit <= 0 then
					return {}
				end
				ns.Collect_ReadProgress(entries)
				local list = {}
				for _, e in ipairs(entries) do
					local key = e.kind == "mount" and "mounts" or e.kind == "pet" and "pets" or "achievements"
					if db.show[key] ~= false then
						list[#list + 1] = e
					end
				end
				table.sort(list, function(a, b)
					local ra, rb = a.kind == "ach" and 2 or 1, b.kind == "ach" and 2 or 1
					if ra ~= rb then
						return ra < rb
					end
					if ra == 2 and (a.percent or 0) ~= (b.percent or 0) then
						return (a.percent or 0) > (b.percent or 0)
					end
					return (a.name or "") < (b.name or "")
				end)
				-- Keep two rows for the achievements when there are any (mounts and pets come first and would fill it).
				local collectibles, achievements = {}, {}
				for _, e in ipairs(list) do
					table.insert(e.kind == "ach" and achievements or collectibles, e)
				end
				local achRows = math.min(#achievements, 2, limit)
				local picked = {}
				for i = 1, math.min(#collectibles, limit - achRows) do
					picked[#picked + 1] = collectibles[i]
				end
				for i = 1, math.min(#achievements, limit - #picked) do
					picked[#picked + 1] = achievements[i]
				end
				local rows = {}
				for i, e in ipairs(picked) do
					local right
					if e.kind == "ach" then
						right = e.total and e.total > 0 and ("%d / %d"):format(e.done or 0, e.total) or nil
					else
						right = SourceWord(e)
					end
					rows[i] = { icon = e.icon, text = e.name, right = right }
				end
				return rows
			end },
	},
	defaults = {
		show = { mounts = true, pets = true, achievements = true },
		collapsed = { mounts = false, pets = false, achievements = false },
		toasts = { zone = true, rare = true },
		preview = true,
	},
	init = function(saved)
		db = saved
		ns.CollectTab_Init(db)
		ns.Collect_SetChanged(OnChanged)
	end,
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			ns.CollectTab_SetEnabled(true)
			if ns.inWorld then
				Start()
			end
		else
			events:UnregisterAllEvents()
			started = false
			ns.Collect_Stop()
			ns.CollectTab_SetEnabled(false)
			ns.Toast_Clear(OWNER)
		end
	end,
	commands = {
		{ "open", "open the map on the Collect here tab", ns.CollectTab_Open },
		{ "here", "what's left in your zone, and the names it matches", Here },
		{ "test", "show sample toasts", Test },
	},
	options = {
		{ type = "header", label = "List" },
		{ type = "checkbox", key = "show.mounts", label = "Mounts", onChange = Changed },
		{ type = "checkbox", key = "show.pets", label = "Battle pets", onChange = Changed },
		{ type = "checkbox", key = "show.achievements", label = "Achievements", onChange = Changed,
			tooltip = "Achievements that name the zone in their title or description." },
		{ type = "checkbox", key = "preview", label = "Model preview",
			tooltip = "Hovering a mount or pet shows its model, turning, next to the tooltip." },
		{ type = "header", label = "Toasts" },
		{ type = "checkbox", key = "toasts.zone", label = "Arriving in a zone with mounts or pets left",
			tooltip = "Once per zone per session." },
		{ type = "checkbox", key = "toasts.rare", label = "A rare is up that drops one you're missing",
			tooltip = "Matched by the rare's name on the minimap or map. Click the toast for a waypoint." },
		{ type = "button", label = "Sample toasts", text = "Show", onClick = Test },
	},
})
