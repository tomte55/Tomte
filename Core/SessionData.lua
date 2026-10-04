local addonName, ns = ...

-- Play session, pure logic: no WoW API calls (unit-tested with plain Lua). Session.lua feeds it.
-- A session counts from the character's login and survives /reload. A new login (or another character) moves
-- the old session to db.sessionLast[its GUID], which the Session recap's login toast reads.

function ns.Session_New(guid, now, baseline)
	return {
		guid = guid,
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
	end
	db.session = ns.Session_New(guid, now, baseline)
	return db.session, true
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
