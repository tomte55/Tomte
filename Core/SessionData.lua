local addonName, ns = ...

-- Play session, pure logic: no WoW API calls (unit-tested with plain Lua). Session.lua feeds it.
-- A session counts from the character's login and survives /reload. A new login (or another character) moves
-- the old session to db.sessionLast[its GUID], which the Session recap's login toast reads.

function ns.Session_New(guid, now, baseline)
	return {
		guid = guid,
		name = baseline.name,
		class = baseline.class,
		zones = {}, -- [zone name] = seconds (the current zone's time since zoneSince isn't in yet)
		start = now,
		seen = now,
		money = baseline.money,
		moneyNow = baseline.money,
		level = baseline.level,
		levelNow = baseline.level,
		xpFraction = baseline.xpFraction,
		xpNow = baseline.xpFraction,
		gold = { ["in"] = {}, out = {} },
		log = {}, -- Session recap entries
		rares = {}, -- [guid] = true: rares counted this session
	}
end

-- Tables a session from before the recap (the AFK module's) doesn't have yet.
local function Fill(session)
	session.gold = type(session.gold) == "table" and session.gold or {}
	session.gold["in"] = session.gold["in"] or {}
	session.gold.out = session.gold.out or {}
	session.log = session.log or {}
	session.rares = session.rares or {}
	session.moneyNow = session.moneyNow or session.money
	session.levelNow = session.levelNow or session.level
	session.xpNow = session.xpNow or session.xpFraction
end

-- The live session for this character, and whether it was just started. baseline = { money, level, xpFraction }.
function ns.Session_Begin(db, guid, newLogin, now, baseline)
	db.sessionLast = db.sessionLast or {}
	local session = db.session
	if type(session) == "table" and session.guid == guid and not newLogin then
		Fill(session)
		return session, false
	end
	if type(session) == "table" and session.guid then
		Fill(session)
		db.sessionLast[session.guid] = session
		if ns.Session_OnEnd then
			ns.Session_OnEnd(session) -- the Sessions page keeps a copy
		end
	end
	db.session = ns.Session_New(guid, now, baseline)
	return db.session, true
end

-- Time per zone: the session moves to `zone` at `now`.
function ns.Session_ZoneTick(session, zone, now)
	session.zones = session.zones or {}
	if session.zoneNow and session.zoneSince then
		session.zones[session.zoneNow] = (session.zones[session.zoneNow] or 0) + math.max(now - session.zoneSince, 0)
	end
	session.zoneNow, session.zoneSince = zone, now
end

-- Where most of the session went (the current zone counted up to endAt), or nil.
function ns.Session_TopZone(session, endAt)
	local totals = {}
	for zone, seconds in pairs(session.zones or {}) do
		totals[zone] = seconds
	end
	if session.zoneNow and session.zoneSince then
		totals[session.zoneNow] = (totals[session.zoneNow] or 0) + math.max(endAt - session.zoneSince, 0)
	end
	local best, bestTime
	for zone, seconds in pairs(totals) do
		if not bestTime or seconds > bestTime or (seconds == bestTime and zone < best) then
			best, bestTime = zone, seconds
		end
	end
	return best
end

-- The AFK module kept the session until the recap took it over.
function ns.Session_Migrate(db)
	local afk = db.afk
	if type(afk) ~= "table" or type(afk.session) ~= "table" then
		return
	end
	if type(db.session) ~= "table" then
		db.session = afk.session
	end
	afk.session = nil
end
