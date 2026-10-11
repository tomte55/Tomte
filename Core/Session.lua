local addonName, ns = ...

-- Play session (always on, also without the Session recap module): start time and the money, level and XP it
-- started with, kept current as they change. AFK's stats pages and the Session recap read it. Rollover and
-- migration are in SessionData.lua. Nothing is read at logout: PLAYER_LOGOUT only stamps the time.

local db

local events = ns.Core_Events

local function XPFraction()
	local max = UnitXPMax("player")
	return max > 0 and UnitXP("player") / max or 0
end

local function Baseline()
	local _, class = UnitClass("player")
	return { money = GetMoney(), level = UnitLevel("player"), xpFraction = XPFraction(), name = UnitName("player"),
		class = class }
end

local function ZoneTick(session)
	local zone = GetZoneText()
	if zone and zone ~= "" and zone ~= session.zoneNow then
		ns.Session_ZoneTick(session, zone, GetServerTime())
	end
end

local function Begin(newLogin)
	local session = ns.Session_Begin(db, UnitGUID("player"), newLogin, GetServerTime(), Baseline())
	session.moneyNow = GetMoney()
	session.levelNow, session.xpNow = UnitLevel("player"), XPFraction()
	session.seen = GetServerTime()
	return session
end

-- The live session (started on first use if the world event hasn't come yet).
function ns.Session_Current()
	local session = db.session
	local guid = UnitGUID("player")
	if not guid then
		return type(session) == "table" and session or ns.Session_New("?", GetServerTime(), Baseline())
	end
	if type(session) ~= "table" or session.guid ~= guid then
		session = Begin(false)
	end
	return session
end

function ns.Session_Last(guid)
	return db.sessionLast and db.sessionLast[guid]
end

-- Something worth a line in the recap happened (Moments, Gear Check, Hunter Pets call this). Only kept while the
-- Session recap is on: it sets ns.Recap_OnNote.
function ns.Session_Note(kind, entry)
	if ns.Recap_OnNote then
		entry.kind = kind
		ns.Recap_OnNote(entry)
	end
end

events:On("session", "PLAYER_ENTERING_WORLD", function(self, isInitialLogin)
	local session = Begin(isInitialLogin) -- registered before any module's handler, so they see the new session
	-- A continued session (after /reload) is the saved one, and one saved before sessions kept name and class (or
	-- taken over from the AFK module) has neither: Baseline only fills them in a new session.
	session.name = session.name or UnitName("player")
	session.class = session.class or select(2, UnitClass("player"))
	ZoneTick(session)
end)

events:On("session", "ZONE_CHANGED_NEW_AREA", function()
	ZoneTick(ns.Session_Current())
end)

events:On("session", "PLAYER_MONEY", function()
	local session = ns.Session_Current()
	local money = GetMoney()
	local delta = money - (session.moneyNow or money)
	session.moneyNow = money
	session.seen = GetServerTime()
	if delta ~= 0 and ns.Session_OnMoney then
		ns.Session_OnMoney(session, delta)
	end
end)

-- Warband bank gold only changes at a bank, so it's read when the bank opens and every change while it's open is
-- a deposit or withdrawal (PLAYER_MONEY already moved moneyNow; this keeps the net as it was).
local bankOpen, warbandNow

local function WarbandMoney()
	if not (C_Bank and C_Bank.FetchDepositedMoney and Enum.BankType and Enum.BankType.Account) then
		return nil
	end
	local ok, money = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
	return ok and type(money) == "number" and money or nil
end

events:On("session", "BANKFRAME_OPENED", function()
	bankOpen, warbandNow = true, WarbandMoney()
end)

events:On("session", "BANKFRAME_CLOSED", function()
	bankOpen = nil
end)

events:On("session", "ACCOUNT_MONEY", function()
	local money = WarbandMoney()
	if bankOpen and money and warbandNow and money ~= warbandNow then
		ns.Session_WarbandMoved(ns.Session_Current(), money - warbandNow)
	end
	warbandNow = money or warbandNow
end)

local function OnXPUpdate(_, unit)
	if unit and unit ~= "player" then
		return
	end
	local session = ns.Session_Current()
	session.levelNow, session.xpNow = UnitLevel("player"), XPFraction()
	session.seen = GetServerTime()
end

events:On("session", "PLAYER_XP_UPDATE", OnXPUpdate)

events:On("session", "PLAYER_LEVEL_UP", function(self)
	OnXPUpdate(self, "player")
end)

events:On("session", "PLAYER_LOGOUT", function()
	if type(db.session) == "table" then
		db.session.seen = GetServerTime()
	end
end)

-- From Core on ADDON_LOADED, before the modules start.
function ns.Session_Init(saved)
	db = saved
	db.sessionLast = db.sessionLast or {}
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT",
		"ZONE_CHANGED_NEW_AREA", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "ACCOUNT_MONEY" }) do
		events:Watch("session", event)
	end
end
