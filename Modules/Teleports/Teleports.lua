local addonName, ns = ...

-- Teleports: every teleport this character can use, in a tab of the world map's side panel (MapTab.lua). What's
-- owned comes from Owned.lua; this file keeps it current and registers the module.

local REFRESH_DELAY = 0.3 -- coalesce bursts of bag and spell events

local module, db
local pending = false
local requestedHouses = false

local function Dirty()
	ns.Tp_MarkDirty()
	if pending then
		return
	end
	pending = true
	C_Timer.After(REFRESH_DELAY, function()
		pending = false
		if module.active then
			ns.TpTab_Refresh()
		end
	end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local DIRTY_EVENTS = {
	"SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "TOYS_UPDATED", "NEW_TOY_ADDED", "BAG_UPDATE_DELAYED",
	"PLAYER_EQUIPMENT_CHANGED", "ITEM_DATA_LOAD_RESULT", "SPELL_TEXT_UPDATE", "CHALLENGE_MODE_MAPS_UPDATE",
	"HEARTHSTONE_BOUND",
}
for _, event in ipairs(DIRTY_EVENTS) do
	events[event] = Dirty
end

function events:PLAYER_HOUSE_LIST_UPDATED(houseInfos)
	ns.Tp_SetHouses(houseInfos)
	Dirty()
end

function events:PLAYER_REGEN_DISABLED()
	ns.TpTab_CombatStart()
end

function events:PLAYER_REGEN_ENABLED()
	ns.TpTab_Refresh()
end

function events:PLAYER_ENTERING_WORLD()
	if not requestedHouses and C_Housing and C_Housing.GetPlayerOwnedHouses then
		requestedHouses = true
		C_Housing.GetPlayerOwnedHouses() -- answers with PLAYER_HOUSE_LIST_UPDATED
	end
	if C_MythicPlus and C_MythicPlus.RequestMapInfo then
		C_MythicPlus.RequestMapInfo() -- season dungeons, for "this season first"
	end
	Dirty()
end

local function Start()
	for _, event in ipairs(DIRTY_EVENTS) do
		events:RegisterEvent(event)
	end
	events:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	ns.TpTab_SetEnabled(true)
	if ns.inWorld then
		events:PLAYER_ENTERING_WORLD()
	end
end

local function Stop()
	events:UnregisterAllEvents()
	ns.TpTab_SetEnabled(false)
end

-- /tomte tp scan: what was found, to check the data.
local function Scan()
	ns.Tp_MarkDirty()
	local entries = ns.Tp_Entries(db)
	local counts, groups = {}, {}
	for _, e in ipairs(entries) do
		local key = e.section .. (e.known and "" or " (not earned)")
		counts[key] = (counts[key] or 0) + 1
		if e.group then
			groups[e.group] = (groups[e.group] or 0) + 1
		end
		if e.known and not e.dest then
			ns.Print(("no destination found for %s (%s)"):format(e.name, e.key))
		end
	end
	ns.Print("teleports found:")
	for key, n in pairs(counts) do
		print(("  %s: %d"):format(key, n))
	end
	for name, n in pairs(groups) do
		print(("  flyout %s: %d spells"):format(name, n))
	end
	print(("  hearthstone toys owned: %d"):format(#ns.Tp_OwnedHearthToys()))
end

module = ns.RegisterModule({
	key = "tp",
	name = "Teleports",
	category = "Travel",
	description = "A Teleports tab in the world map's side panel: your hearthstone (and a random hearthstone toy), house, dungeon teleports (this season first), class teleports and teleport items, with cooldowns. Teleports that go to the map you're looking at float to the top. Click to use, right-click to favorite.",
	enabledByDefault = true,
	home = {
		{ kind = "map", key = "teleports", order = 2, name = "Teleports", icon = "Interface\\Icons\\Spell_Arcane_PortalDalaran",
			open = function()
				ns.TpTab_Open()
			end,
			summary = function()
				local ready = 0
				for _, e in ipairs(ns.Tp_Entries(db)) do
					if e.known and ns.Tp_Cooldown(e) == 0 then
						ready = ready + 1
					end
				end
				return ready .. " ready"
			end },
		{ kind = "around", key = "teleportsaround", order = 3, name = "Teleports", maxRows = 3,
			icon = "Interface\\Icons\\Spell_Arcane_PortalDalaran",
			open = function()
				ns.TpTab_Open()
			end,
			title = function()
				local ready = 0
				for _, e in ipairs(ns.Tp_Entries(db)) do
					if e.known and ns.Tp_Cooldown(e) == 0 then
						ready = ready + 1
					end
				end
				return ("Teleports: %d ready"):format(ready)
			end,
			items = function(limit)
				local rows = {}
				for _, e in ipairs(ns.Tp_Entries(db)) do
					if #rows >= limit then
						break
					end
					if e.known and ns.Tp_Cooldown(e) == 0 then
						rows[#rows + 1] = { icon = e.icon, text = e.name, right = "ready" }
					end
				end
				return rows
			end },
	},
	defaults = {
		favorites = {}, -- [entry key] = true
		showUnearned = true,
		allToys = false,
		sections = { hearth = true, dungeon = true, class = true, items = true, here = true, favorites = true },
	},
	init = function(moduleDB)
		db = moduleDB
		ns.TpTab_Init(db)
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "open", "open the map on the Teleports tab", ns.TpTab_Open },
		{ "scan", "list what was found (to check the data)", Scan },
	},
	options = {
		{ type = "header", label = "List" },
		{ type = "checkbox", key = "showUnearned", label = "Show unearned dungeon teleports", onChange = Dirty,
			tooltip = "This season's dungeon teleports you haven't earned yet, greyed out: what's left to get." },
		{ type = "checkbox", key = "allToys", label = "List every hearthstone toy", onChange = Dirty,
			tooltip = "Off: one \"Random hearthstone toy\" row." },
		{ type = "header", label = "Sections" },
		{ type = "checkbox", key = "sections.favorites", label = "Favorites", onChange = Dirty },
		{ type = "checkbox", key = "sections.here", label = "To this map", onChange = Dirty },
		{ type = "checkbox", key = "sections.hearth", label = "Hearthstone", onChange = Dirty },
		{ type = "checkbox", key = "sections.dungeon", label = "Dungeons", onChange = Dirty },
		{ type = "checkbox", key = "sections.class", label = "Class", onChange = Dirty },
		{ type = "checkbox", key = "sections.items", label = "Items and toys", onChange = Dirty },
	},
})
