local addonName, ns = ...

-- Teleports this character can use, as entries for the map tab: { key, kind ("spell"|"toy"|"item"|"home"|"random"),
-- id, section, name, icon, desc, dest, known, current, order, equips, house }. Dungeon and mage teleports come from
-- the spellbook's flyouts (Hero's Path and any flyout whose spells teleport), so they need no data. Rebuilt lazily
-- after anything that changes ownership (Teleports.lua marks it dirty).

-- Flyouts by ID (SpellFlyout game data, 12.1.0), so any client language finds them: the Hero's Path flyouts, and
-- the other flyouts whose spells teleport (mage Teleport and Portal, one each per faction). A Hero's Path flyout
-- added later is still found by its name ("Hero's Path: ..." as this client writes it, read from a known one);
-- another new teleport flyout only by English or German spell text ("eleport"): no API says a spell teleports.
local HERO_PATH_FLYOUTS = {
	[84] = true, [96] = true, [220] = true, [222] = true, [223] = true, [224] = true, [227] = true, [230] = true,
	[231] = true, [232] = true, [242] = true, [244] = true, [246] = true, [274] = true,
}
local TELEPORT_FLYOUTS = { [1] = true, [8] = true, [11] = true, [12] = true }
local HERO_PATH = "Hero's Path"
local heroPath -- this client's "Hero's Path", once a known flyout has answered

-- The known Hero's Path flyouts' name up to its colon ("Hero's Path: Dragonflight" -> "Hero's Path"), once two of
-- them agree (so one oddly named flyout can't set it).
local function HeroPath()
	if not heroPath then
		local seen = {}
		for id in pairs(HERO_PATH_FLYOUTS) do
			local name = GetFlyoutInfo(id)
			local prefix = type(name) == "string" and (name:match("^(.-)%s*:") or name:match("^(.-)%s*\239\188\154"))
			if prefix and #prefix >= 4 then
				if seen[prefix] then
					heroPath = prefix
					break
				end
				seen[prefix] = true
			end
		end
	end
	return heroPath or HERO_PATH
end

local entries
local houses = {} -- from PLAYER_HOUSE_LIST_UPDATED
local mapNameCache = {} -- [mapID] = { names, entrances = { [lowerName] = position } }
-- The items and spells the list read while it was built: a load or text update for one of them rebuilds it.
local watched = { item = {}, spell = {} }

function ns.Tp_MarkDirty()
	entries = nil
end

-- kind: "item" or "spell". Whether the built list read that ID (ITEM_DATA_LOAD_RESULT, SPELL_TEXT_UPDATE); an
-- unbuilt list reads everything fresh anyway.
function ns.Tp_Watches(kind, id)
	return entries ~= nil and id ~= nil and watched[kind][id] == true
end

function ns.Tp_SetHouses(list)
	houses = list or {}
	entries = nil
end

local function SpellDesc(spellID)
	if spellID then
		watched.spell[spellID] = true
	end
	local desc = spellID and C_Spell.GetSpellDescription(spellID)
	if issecretvalue and issecretvalue(desc) then
		return nil
	end
	return desc ~= "" and desc or nil
end

local function SeasonNames()
	local names = {}
	for _, mapID in ipairs(C_ChallengeMode.GetMapTable() or {}) do
		local name = C_ChallengeMode.GetMapUIInfo(mapID)
		if name then
			names[#names + 1] = name
		end
	end
	return names
end

-- flyoutID -> name for every flyout in the spellbook (class and general tabs).
local function Flyouts()
	local list, seen = {}, {}
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info then
			for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
				if item and item.itemType == Enum.SpellBookItemType.Flyout and not seen[item.actionID] then
					seen[item.actionID] = true
					list[#list + 1] = { id = item.actionID, name = item.name }
				end
			end
		end
	end
	return list
end

local function Add(list, e)
	e.name = e.name or "?"
	e.dest = e.dest or ns.Tp_Destination(e.desc)
	list[#list + 1] = e
end

local function AddFlyouts(list, seasonNames)
	for index, flyout in ipairs(Flyouts()) do
		local _, _, numSlots = GetFlyoutInfo(flyout.id)
		local dungeon = HERO_PATH_FLYOUTS[flyout.id] or flyout.name:find(HeroPath(), 1, true) ~= nil
			or flyout.name:find(HERO_PATH, 1, true) ~= nil
		local slots, teleports = {}, dungeon or TELEPORT_FLYOUTS[flyout.id] == true
		for s = 1, numSlots or 0 do
			local spellID, overrideID, isKnown, spellName = GetFlyoutSlotInfo(flyout.id, s)
			local id = overrideID and overrideID ~= 0 and overrideID or spellID
			local desc = SpellDesc(id)
			if desc and desc:find("eleport", 1, true) then
				teleports = true
			end
			slots[#slots + 1] = { id = id, known = isKnown, name = spellName, desc = desc }
		end
		if teleports then
			for s, slot in ipairs(slots) do
				local info = C_Spell.GetSpellInfo(slot.id)
				Add(list, {
					key = "spell:" .. slot.id, kind = "spell", id = slot.id,
					section = dungeon and "dungeon" or "class",
					name = slot.name or (info and info.name), icon = info and info.iconID, desc = slot.desc,
					-- Off English clients: the current-season dungeon its description names.
					dest = ns.Tp_Destination(slot.desc) or (dungeon and ns.Tp_NamedPlace(slot.desc, seasonNames)) or nil,
					known = slot.known == true,
					current = dungeon and ns.Tp_Mentions(slot.desc, seasonNames),
					order = index * 100 + s, group = flyout.name,
				})
			end
		end
	end
end

local function AddSpells(list)
	for i, spellID in ipairs(ns.TP_CLASS_SPELLS) do
		if C_SpellBook.IsSpellKnown(spellID) then
			local info = C_Spell.GetSpellInfo(spellID)
			Add(list, {
				key = "spell:" .. spellID, kind = "spell", id = spellID, section = "class",
				name = info and info.name, icon = info and info.iconID, desc = SpellDesc(spellID), known = true, order = i,
			})
		end
	end
end

local function ItemDesc(itemID)
	local _, spellID = C_Item.GetItemSpell(itemID)
	return SpellDesc(spellID)
end

local function HasItem(itemID)
	return C_Item.GetItemCount(itemID) > 0 or C_Item.IsEquippedItem(itemID)
end

local function ItemEntry(kind, itemID, section, order)
	watched.item[itemID] = true
	local name, icon
	if kind == "toy" then
		local _, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
		name, icon = toyName, toyIcon
	end
	name = name or C_Item.GetItemNameByID(itemID)
	icon = icon or C_Item.GetItemIconByID(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID) -- ITEM_DATA_LOAD_RESULT rebuilds
	end
	return {
		key = kind .. ":" .. itemID, kind = kind, id = itemID, section = section, name = name, icon = icon,
		desc = ItemDesc(itemID), known = true, order = order,
		equips = kind == "item" and C_Item.IsEquippableItem(itemID) and not C_Item.IsEquippedItem(itemID),
	}
end

function ns.Tp_OwnedHearthToys()
	local owned = {}
	for _, itemID in ipairs(ns.TP_HEARTH_TOYS) do
		if PlayerHasToy(itemID) then
			owned[#owned + 1] = itemID
		end
	end
	return owned
end

local function AddHearth(list, db)
	local bind = GetBindLocation()
	if HasItem(ns.TP_HEARTHSTONE) then
		local e = ItemEntry("item", ns.TP_HEARTHSTONE, "hearth", 1)
		e.dest, e.equips = bind, false
		Add(list, e)
	end
	local toys = ns.Tp_OwnedHearthToys()
	if #toys > 0 then
		Add(list, {
			key = "random", kind = "random", section = "hearth", name = "Random hearthstone toy",
			icon = "Interface\\Icons\\INV_Misc_Rune_01", dest = bind, known = true, order = 2,
			desc = ("Uses one of your %d hearthstone toys at random."):format(#toys),
		})
		if db.allToys then
			for i, itemID in ipairs(toys) do
				local e = ItemEntry("toy", itemID, "hearth", 10 + i)
				e.dest = bind
				Add(list, e)
			end
		end
	end
	for i, house in ipairs(houses) do
		if house.neighborhoodGUID and house.houseGUID then
			Add(list, {
				key = "home:" .. house.houseGUID, kind = "home", section = "hearth", house = house,
				name = house.houseName or "Home", icon = "Interface\\Icons\\INV_Misc_Key_14",
				dest = house.neighborhoodName, desc = "Teleport to your house.", known = true, order = 3 + i / 10,
			})
		end
	end
	for i, itemID in ipairs(ns.TP_HEARTH_ITEMS) do
		if PlayerHasToy(itemID) then
			Add(list, ItemEntry("toy", itemID, "hearth", 5 + i))
		elseif HasItem(itemID) then
			Add(list, ItemEntry("item", itemID, "hearth", 5 + i))
		end
	end
end

local function AddItems(list)
	for i, item in ipairs(ns.TP_ITEMS) do
		local owned = item.kind == "toy" and PlayerHasToy(item.id) or (item.kind == "item" and HasItem(item.id))
		if owned then
			Add(list, ItemEntry(item.kind, item.id, "items", i))
		end
	end
end

function ns.Tp_Entries(db)
	if not entries then
		entries = {}
		watched = { item = {}, spell = {} }
		AddHearth(entries, db)
		AddFlyouts(entries, SeasonNames())
		AddSpells(entries)
		AddItems(entries)
	end
	return entries
end

-- Names of the map, everything under it, and the dungeon entrances on it and its zones, for "To this map".
-- entrances: [lower-case name] = position on this map (only for entrances on the map itself).
function ns.Tp_MapNames(mapID)
	local cached = mapNameCache[mapID]
	if cached then
		return cached
	end
	local names, entrances = {}, {}
	local info = C_Map.GetMapInfo(mapID)
	if info then
		names[#names + 1] = info.name
	end
	for _, e in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(mapID) or {}) do
		names[#names + 1] = e.name
		entrances[e.name:lower()] = e.position
	end
	for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, nil, true) or {}) do
		names[#names + 1] = child.name
		if child.mapType == Enum.UIMapType.Zone then
			for _, e in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(child.mapID) or {}) do
				names[#names + 1] = e.name
			end
		end
	end
	cached = { names = names, entrances = entrances }
	mapNameCache[mapID] = cached
	return cached
end

-- Where on the viewed map this entry goes (an entrance position), or nil.
function ns.Tp_PinPosition(e, mapNames)
	local text = (e.dest or e.desc or ""):lower()
	for name, pos in pairs(mapNames.entrances) do
		if #name >= 4 and text:find(name, 1, true) then
			return pos
		end
	end
	return nil
end

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

-- Seconds left, 0 when ready, nil when the game hides the values (secret, e.g. in combat or M+).
local function Remaining(start, duration, enabled)
	if Secret(start, duration, enabled) then
		return nil
	end
	if not enabled or not start or not duration or duration <= 1.5 or start == 0 then -- 1.5: the global cooldown
		return 0
	end
	return math.max(start + duration - GetTime(), 0)
end

local function ItemRemaining(itemID)
	return Remaining(C_Item.GetItemCooldown(itemID))
end

-- Seconds left on the entry's cooldown (0 = ready), or nil when the game hides it.
function ns.Tp_Cooldown(e)
	if e.kind == "spell" or e.kind == "home" then
		local info
		if e.kind == "spell" then
			info = C_Spell.GetSpellCooldown(e.id)
		else
			info = C_Housing.GetVisitCooldownInfo()
		end
		if not info then
			return nil
		end
		return Remaining(info.startTime, info.duration, info.isEnabled)
	elseif e.kind == "random" then
		local best, hidden
		for _, itemID in ipairs(ns.Tp_OwnedHearthToys()) do
			local left = ItemRemaining(itemID)
			if left == nil then
				hidden = true
			else
				best = best and math.min(best, left) or left
			end
		end
		if best == nil and hidden then
			return nil
		end
		return best or 0
	end
	return ItemRemaining(e.id)
end

-- A random owned hearthstone toy that's off cooldown (any, if all are on cooldown).
function ns.Tp_RandomHearthToy()
	local ready, all = {}, ns.Tp_OwnedHearthToys()
	for _, itemID in ipairs(all) do
		if ItemRemaining(itemID) == 0 then
			ready[#ready + 1] = itemID
		end
	end
	local pool = #ready > 0 and ready or all
	return pool[math.random(#pool)]
end
