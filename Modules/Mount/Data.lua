local addonName, ns = ...

-- Smart Mount pure logic (unit-tested with plain Lua): what a mount type can do, the riding context, which zone
-- favorites apply, and picking a mount for the context.

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

local GROUND = {}

function ns.Mount_TypeInfo(mountTypeID)
	return TYPES[mountTypeID] or GROUND
end

function ns.Mount_KnownType(mountTypeID)
	return TYPES[mountTypeID] ~= nil
end

-- s = { submerged, flyable, indoors } -> "water" | "flying" | "ground"
function ns.Mount_Context(s)
	if s.submerged then
		return "water"
	end
	if s.flyable and not s.indoors then
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

-- The action bar macro: #showtooltip makes the bar show that spell's icon, tooltip and usable/greyed state, and the
-- /click presses the Smart Mount button (down, as the button only takes down clicks). Macros hold 255 characters.
function ns.Mount_MacroBody(spell, buttonName)
	local click = "/click " .. buttonName .. " LeftButton 1"
	local body = spell and ("#showtooltip " .. spell .. "\n" .. click)
	if not body or #body > 255 then
		return "#showtooltip\n" .. click
	end
	return body
end
