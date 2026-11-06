local addonName, ns = ...

-- Smart Mount pure logic (unit-tested with plain Lua): what a mount type can do, the riding context, which zone
-- favorites apply, class, passenger and repair mounts, the order mounts are picked in, when a travel form beats a mount,
-- and picking a mount for the context.

-- Raw mountTypeID (GetMountInfoExtraByID return 5) -> what it does. From community tables, not the wiki: an
-- unknown ID counts as a ground mount (/tomte mount why prints the ID so it can be added).
local TYPES = {
	[230] = {}, -- ground
	[241] = {}, -- ground (Qiraji battle tanks)
	[269] = {}, -- ground (water striders walk on water)
	[284] = {}, -- ground (chauffeured)
	[408] = {}, -- ground
	[231] = { aquatic = true, swimOnly = true }, -- turtles: fast in water, slow on land
	[232] = { aquatic = true, swimOnly = true }, -- Vashj'ir seahorse
	[254] = { aquatic = true, swimOnly = true }, -- underwater only
	[412] = { aquatic = true }, -- ground and water (otters)
	[407] = { flying = true, aquatic = true }, -- flies and swims
	[242] = { flying = true }, -- flying (spectral)
	[247] = { flying = true },
	[248] = { flying = true },
	[398] = { flying = true },
	[402] = { flying = true }, -- skyriding
	[424] = { flying = true }, -- skyriding
	[436] = { flying = true },
	[437] = { flying = true },
	[444] = { flying = true },
	[306] = { flying = true },
}

-- Mount lists by mountID, from Mount Journal Enhanced's database (restrictions.db.lua and the Type table in
-- Database.lua). Class mounts can only be ridden by their class (a few also by one race), so any of them that's usable
-- is this character's own.
ns.MOUNT_CLASS = {
	[17] = true, -- Felsteed
	[41] = true, -- Warhorse
	[83] = true, -- Dreadsteed
	[84] = true, -- Charger
	[149] = true, -- Thalassian Charger
	[150] = true, -- Thalassian Warhorse
	[221] = true, -- Acherus Deathcharger
	[236] = true, -- Winged Steed of the Ebon Blade
	[338] = true, -- Argent Charger
	[350] = true, -- Sunwalker Kodo
	[351] = true, -- Great Sunwalker Kodo
	[367] = true, -- Exarch's Elekk
	[368] = true, -- Great Exarch's Elekk
	[780] = true, -- Felsaber
	[860] = true, -- Archmage's Prismatic Disc
	[861] = true, -- High Priest's Lightsworn Seeker
	[864] = true, -- Ban-Lu, Grandmaster's Companion
	[865] = true, -- Huntmaster's Loyal Wolfhawk
	[866] = true, -- Deathlord's Vilebrood Vanquisher
	[867] = true, -- Battlelord's Bloodthirsty War Wyrm
	[868] = true, -- Slayer's Felbroken Shrieker
	[870] = true, -- Huntmaster's Fierce Wolfhawk
	[872] = true, -- Huntmaster's Dire Wolfhawk
	[884] = true, -- Shadowblade's Murderous Omen
	[885] = true, -- Highlord's Golden Charger
	[888] = true, -- Farseer's Raging Tempest
	[889] = true, -- Shadowblade's Lethal Omen
	[890] = true, -- Shadowblade's Baneful Omen
	[891] = true, -- Shadowblade's Crimson Omen
	[892] = true, -- Highlord's Vengeful Charger
	[893] = true, -- Highlord's Vigilant Charger
	[894] = true, -- Highlord's Valorous Charger
	[898] = true, -- Netherlord's Chaotic Wrathsteed
	[930] = true, -- Netherlord's Brimstone Wrathsteed
	[931] = true, -- Netherlord's Accursed Wrathsteed
	[1046] = true, -- Darkforge Ram
	[1047] = true, -- Dawnforge Ram
	[1225] = true, -- Crusader's Direhorn
	[1568] = true, -- Lightforged Ruinstrider
	[2233] = true, -- Earthen Ordinant's Ramolith
	[2720] = true, -- Felscorned Vilebrood Vanquisher
	[2721] = true, -- Slayer's Felscorned Shrieker
	[2723] = true, -- Felscorned Wolfhawk
	[2724] = true, -- Archmage's Felscorned Disc
	[2725] = true, -- Felscorned Grandmaster's Companion
	[2726] = true, -- Felscorned Highlord's Charger
	[2727] = true, -- High Priest's Felscorned Seeker
	[2728] = true, -- Shadowblade's Felscorned Omen
	[2729] = true, -- Farseer's Felscorned Tempest
	[2730] = true, -- Felscorned Netherlord's Dreadsteed
	[2731] = true, -- Felscorned War Wyrm
}

-- Mounts with a seat for someone else.
ns.MOUNT_PASSENGER = {
	[240] = true, -- Mechano-Hog
	[275] = true, -- Mekgineer's Chopper
	[280] = true, -- Traveler's Tundra Mammoth (Alliance)
	[284] = true, -- Traveler's Tundra Mammoth (Horde)
	[286] = true, -- Grand Black War Mammoth
	[287] = true, -- Grand Black War Mammoth
	[288] = true, -- Grand Ice Mammoth
	[289] = true, -- Grand Ice Mammoth
	[382] = true, -- X-53 Touring Rocket
	[407] = true, -- Sandstone Drake
	[455] = true, -- Obsidian Nightwing
	[460] = true, -- Grand Expedition Yak
	[959] = true, -- Stormwind Skychaser
	[960] = true, -- Orgrimmar Interceptor
	[1025] = true, -- The Hivemind
	[1039] = true, -- Mighty Caravan Brutosaur
	[1287] = true, -- Explorer's Jungle Hopper
	[1288] = true, -- Explorer's Dunetrekker
	[1698] = true, -- Rocket Shredder 9001
}

-- Mounts with a vendor who repairs.
ns.MOUNT_REPAIR = {
	[280] = true, -- Traveler's Tundra Mammoth (Alliance)
	[284] = true, -- Traveler's Tundra Mammoth (Horde)
	[460] = true, -- Grand Expedition Yak
	[1039] = true, -- Mighty Caravan Brutosaur
	[2237] = true, -- Grizzly Hills Packmaster
}

local GROUND = {}

function ns.Mount_TypeInfo(mountTypeID)
	return TYPES[mountTypeID] or GROUND
end

function ns.Mount_KnownType(mountTypeID)
	return TYPES[mountTypeID] ~= nil
end

-- s = { submerged, underwater, flyable, indoors } -> "water" | "flying" | "ground". submerged is true on the surface
-- too (IsSubmerged, measured in 12.1); underwater = below it. On the surface where you can fly, you want to take off.
function ns.Mount_Context(s)
	local canFly = s.flyable and not s.indoors
	if s.submerged and (s.underwater or not canFly) then
		return "water"
	end
	if canFly then
		return "flying"
	end
	return "ground"
end

-- chain: mapIDs from where you stand up to the world (zone, continent, ...). zones: [mapID] = { mountID, ... }.
-- Returns the first non-empty list and its mapID.
function ns.Mount_ZoneList(chain, zones)
	for _, mapID in ipairs(chain) do
		local list = zones[mapID]
		if list and #list > 0 then
			return list, mapID
		end
	end
	return nil
end

-- Adds or removes mountID in zones[mapID]; drops the list when it gets empty. Returns true when it's now in.
function ns.Mount_ToggleZone(zones, mapID, mountID)
	local list = zones[mapID]
	if list then
		for i, id in ipairs(list) do
			if id == mountID then
				table.remove(list, i)
				if #list == 0 then
					zones[mapID] = nil
				end
				return false
			end
		end
	else
		list = {}
		zones[mapID] = list
	end
	list[#list + 1] = mountID
	return true
end

function ns.Mount_InZone(zones, mapID, mountID)
	for _, id in ipairs(zones[mapID] or {}) do
		if id == mountID then
			return true
		end
	end
	return false
end

local function Filter(list, fn)
	local out = {}
	for _, m in ipairs(list) do
		if fn(m) then
			out[#out + 1] = m
		end
	end
	return out
end

-- Narrowing steps per context: the first step that leaves anything wins. The first `fit` steps give a mount that
-- suits the context; the rest are fallbacks (a ground mount where you could fly, a turtle on land).
local function Steps(context, opts)
	local function flying(m)
		return m.flying
	end
	local function canSkyride(m)
		return m.flying and not m.steady
	end
	local function landOnly(m)
		return not m.flying and not m.aquatic
	end
	local function notSwimOnly(m)
		return not m.swimOnly
	end
	if context == "water" then
		return { function(m)
			return m.aquatic
		end, flying, notSwimOnly }, 1
	elseif context == "flying" then
		if opts.skyriding then
			return { canSkyride, flying, notSwimOnly }, 2
		end
		return { flying, notSwimOnly }, 1
	end
	if opts.preferGround then
		return { landOnly, notSwimOnly }, 2
	end
	return { notSwimOnly }, 1
end

-- candidates: usable mounts { id, flying, aquatic, swimOnly, steady }. opts = { preferGround, skyriding, avoid
-- (last mountID), prefer (mountID to take when it's in the pool: the one the macro shows), strict (only a mount
-- that suits the context, else nil) }. rand(n) -> 1..n. Returns the chosen candidate or nil.
function ns.Mount_Pick(candidates, context, opts, rand)
	local steps, fit = Steps(context, opts)
	local pool
	for i, step in ipairs(steps) do
		if opts.strict and i > fit then
			break
		end
		pool = Filter(candidates, step)
		if #pool > 0 then
			break
		end
	end
	if not pool or #pool == 0 then
		if opts.strict then
			return nil
		end
		pool = candidates
	end
	if #pool == 0 then
		return nil
	end
	if opts.prefer then
		for _, m in ipairs(pool) do
			if m.id == opts.prefer then
				return m
			end
		end
	end
	if opts.avoid and #pool > 1 then
		pool = Filter(pool, function(m)
			return m.id ~= opts.avoid
		end)
	end
	return pool[rand(#pool)]
end

-- candidates: usable mounts flagged zone, class, passenger and favorite. opts = { pool = "favorites" (journal
-- favorites, then all mounts) | "favoritesOnly" (all mounts only without favorites) | "all" (favorites count like any
-- mount), classFirst, passengerFirst, zoneName }. Returns the tiers for Mount_PickTiered, best first: passenger mounts,
-- zone favorites, class mounts, journal favorites, all mounts. Empty tiers are left out.
function ns.Mount_Tiers(candidates, opts)
	local tiers = {}
	local function add(source, fn)
		local list = Filter(candidates, fn)
		if #list > 0 then
			tiers[#tiers + 1] = { source = source, candidates = list }
		end
		return #list
	end
	if opts.passengerFirst then
		add("passenger mounts", function(m)
			return m.passenger
		end)
	end
	add(opts.zoneName and ("zone favorites (" .. opts.zoneName .. ")") or "zone favorites", function(m)
		return m.zone
	end)
	if opts.classFirst then
		add("class mounts", function(m)
			return m.class
		end)
	end
	local favorites = 0
	if opts.pool ~= "all" then
		favorites = add("journal favorites", function(m)
			return m.favorite
		end)
	end
	if not (opts.pool == "favoritesOnly" and favorites > 0) then
		tiers[#tiers + 1] = { source = "all mounts", candidates = candidates }
	end
	return tiers
end

-- Whether the key takes the travel form (druid Travel Form, shaman Ghost Wolf) instead of a mount. s = { mode =
-- "never" | "moving" | "always", moving, indoors, formFlies (Travel Form also swims and flies; Ghost Wolf only runs),
-- context, castTime (Forever's Ghost Wolf takes 3 seconds to cast, so like a mount it can't be taken on the move) }. A
-- mount can't be summoned on the move, a form can. Indoors is left to the indoor form.
function ns.Mount_UseForm(s)
	if s.mode == "never" or s.indoors then
		return false
	end
	if s.moving then
		return not s.castTime
	end
	return s.mode == "always" and (s.formFlies or s.context == "ground")
end

-- tiers: { { source, candidates } } in order (zone favorites, journal favorites, all mounts). A tier is used only
-- when it has a mount that suits the context; the last tier takes whatever fits best. Returns mount, source.
function ns.Mount_PickTiered(tiers, context, opts, rand)
	for i, tier in ipairs(tiers) do
		local last = i == #tiers
		local mount = ns.Mount_Pick(tier.candidates, context, {
			preferGround = opts.preferGround, skyriding = opts.skyriding, avoid = opts.avoid, prefer = opts.prefer,
			strict = not last,
		}, rand)
		if mount then
			return mount, tier.source
		end
	end
	return nil
end

-- The action bar macro: #showtooltip makes the bar show that spell's icon, tooltip and usable/greyed state. It casts
-- the picked mount itself rather than clicking the Smart Mount button: the button's /cast then runs inside the bar
-- macro, and that nested cast does nothing when the bar is clicked with the mouse (measured in 12.1). The /cast line
-- comes first so that a dismount in the same press can't be followed by mounting again. opts: form = the travel form's
-- shapeshift index (druid, shaman), keepFlying = don't dismount in the air, formToMount = on the ground the travel form
-- is left first and the mount cast right after (spell is a mount then). A spell may start with "!" (/cast !Cat Form
-- stays in the form instead of leaving it). Without a spell, or over the 255 characters a macro holds, it falls back
-- to clicking the button (the key's way). Tomte rewrites the macro after each mount.
function ns.Mount_MacroBody(spell, buttonName, opts)
	opts = opts or {}
	local fallback = "#showtooltip\n/click " .. buttonName .. " LeftButton 1\n/click " .. buttonName .. " LeftButton"
	if not spell then
		return fallback
	end
	local air = opts.keepFlying and ",noflying" or ""
	local form = opts.form
	local lines = { "#showtooltip " .. (spell:gsub("^!", "")) }
	local castIf = form and (",noform:" .. form) or ""
	if form and opts.formToMount then
		lines[#lines + 1] = ("/cancelform [form:%d,noflying]"):format(form)
		castIf = ",noflying"
	end
	lines[#lines + 1] = ("/cast [nomounted,novehicleui%s] %s"):format(castIf, spell)
	lines[#lines + 1] = "/leavevehicle [canexitvehicle]"
	lines[#lines + 1] = ("/dismount [mounted%s]"):format(air)
	if form then
		lines[#lines + 1] = ("/cancelform [form:%d%s]"):format(form, air)
	end
	local body = table.concat(lines, "\n")
	if #body > 255 then
		return fallback
	end
	return body
end
