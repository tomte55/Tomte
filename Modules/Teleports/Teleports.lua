local addonName, ns = ...

-- Teleports: every teleport this character can use, in a tab of the world map's side panel (MapTab.lua). What's
-- owned comes from Owned.lua, IDs and pure logic from Data.lua; this file keeps it current and registers the module.

local REFRESH_DELAY = 0.3 -- coalesce bursts of bag and spell events
local PORTAL_ICON = "Interface\\Icons\\Spell_Arcane_PortalDalaran"

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

local events = ns.Tp_Events -- made in MapTab.lua, which also has the "secure" owner
local OWNER = "teleports"

local DIRTY_EVENTS = {
	"SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "TOYS_UPDATED", "NEW_TOY_ADDED", "BAG_UPDATE_DELAYED",
	"PLAYER_EQUIPMENT_CHANGED", "CHALLENGE_MODE_MAPS_UPDATE", "HEARTHSTONE_BOUND",
}
for _, event in ipairs(DIRTY_EVENTS) do
	events:On(OWNER, event, Dirty)
end

-- Item and spell data loads happen all the time (bags, tooltips, other addons): only the list's own count.
events:On(OWNER, "ITEM_DATA_LOAD_RESULT", function(_, itemID)
	if ns.Tp_Watches("item", itemID) then
		Dirty()
	end
end)

events:On(OWNER, "SPELL_TEXT_UPDATE", function(_, spellID)
	if ns.Tp_Watches("spell", spellID) then
		Dirty()
	end
end)

events:On(OWNER, "PLAYER_HOUSE_LIST_UPDATED", function(_, houseInfos)
	ns.Tp_SetHouses(houseInfos)
	Dirty()
end)

events:On(OWNER, "PLAYER_REGEN_DISABLED", function()
	ns.TpTab_CombatStart()
end)

events:On(OWNER, "PLAYER_REGEN_ENABLED", function()
	ns.TpTab_Refresh()
end)

local function OnEnteringWorld()
	if not requestedHouses and C_Housing and C_Housing.GetPlayerOwnedHouses then
		requestedHouses = true
		C_Housing.GetPlayerOwnedHouses() -- answers with PLAYER_HOUSE_LIST_UPDATED
	end
	if C_MythicPlus and C_MythicPlus.RequestMapInfo then
		C_MythicPlus.RequestMapInfo() -- season dungeons, for "this season first"
	end
	Dirty()
end

events:On(OWNER, "PLAYER_ENTERING_WORLD", OnEnteringWorld)

local function Start()
	for _, event in ipairs(DIRTY_EVENTS) do
		events:Watch(OWNER, event)
	end
	events:Watch(OWNER, "ITEM_DATA_LOAD_RESULT")
	events:Watch(OWNER, "SPELL_TEXT_UPDATE")
	events:Watch(OWNER, "PLAYER_HOUSE_LIST_UPDATED")
	events:Watch(OWNER, "PLAYER_REGEN_DISABLED")
	events:Watch(OWNER, "PLAYER_REGEN_ENABLED")
	events:Watch(OWNER, "PLAYER_ENTERING_WORLD")
	ns.TpTab_SetEnabled(true)
	if ns.inWorld then
		OnEnteringWorld()
	end
end

local function Stop()
	events:UnwatchAll(OWNER)
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

-- Known teleports off cooldown, for Home.
local function ReadyCount()
	local ready = 0
	for _, e in ipairs(ns.Tp_Entries(db)) do
		if e.known and ns.Tp_Cooldown(e) == 0 then
			ready = ready + 1
		end
	end
	return ready
end

module = ns.RegisterModule({
	key = "tp",
	name = "Teleports",
	category = "Travel",
	description = "A Teleports tab in the world map's side panel: your hearthstone (and a random hearthstone toy), house, dungeon teleports (this season first), class teleports and teleport items, with cooldowns. Teleports that go to the map you're looking at float to the top. Click to use, right-click to favorite.",
	enabledByDefault = true,
	home = {
		{ kind = "map", key = "teleports", order = 2, name = "Teleports", icon = PORTAL_ICON,
			open = function()
				ns.TpTab_Open()
			end,
			summary = function()
				return ReadyCount() .. " ready"
			end },
		{ kind = "around", key = "teleportsaround", order = 3, name = "Teleports", maxRows = 3,
			icon = PORTAL_ICON,
			open = function()
				ns.TpTab_Open()
			end,
			title = function()
				return ("Teleports: %d ready"):format(ReadyCount())
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
