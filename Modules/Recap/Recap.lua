local addonName, ns = ...

-- Session recap module: what you got done this session (time, gold, notable loot, achievements, rares, tames,
-- progress). A passthrough cinematic card during the /camp logout countdown and on /tomte recap, a login toast
-- for the last session (covers instant logouts in rested areas, which give no countdown), and a page on the AFK
-- screen. The session itself is Core/Session.lua; tracking is Track.lua; pure logic is Data.lua.

local TICK = 0.25
local ROWS = 6
local CARD_TIME = 20 -- seconds a /tomte recap card stays
local CAMP_TIME = 20 -- the logout countdown
local LOGIN_DELAY = 8 -- seconds after login before the last-session toast
local TOAST_HOLD = 15

local module, db
local playing -- engine state of the card on screen

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)
local ticker = CreateFrame("Frame")
ticker:Hide()

local function XPFraction()
	local max = UnitXPMax("player")
	return max > 0 and UnitXP("player") / max or 0
end

local function CanShowXP()
	if GameRulesUtil and GameRulesUtil.CanShowExperienceBar then
		return GameRulesUtil.CanShowExperienceBar()
	end
	return UnitXPMax("player") > 0
end

local function Clock(at)
	local t = date("*t", at)
	return ns.AFK_ClockText(t.hour, t.min, C_CVar.GetCVarBool("timeMgrUseMilitaryTime"))
end

-- The card's (and toast's) view of a session. live = the session going on now.
local function Summarize(session, label, live)
	local now = GetServerTime()
	local endAt = live and now or (session.seen or session.start)
	local duration = endAt - session.start
	local net = (session.moneyNow or session.money) - session.money
	local counts = session.trimmed and session.counts or ns.Recap_Counts(session.log)
	local shown, more = ns.Recap_Highlights(session.log, ROWS)
	local level = live and UnitLevel("player") or (session.levelNow or session.level)
	local xp = live and XPFraction() or (session.xpNow or session.xpFraction)
	local gain = CanShowXP() and ns.AFK_XPGain(session.level, session.xpFraction, level, xp) or nil
	local summary = {
		label = label,
		title = ns.Recap_Duration(duration),
		subtitle = ("%s %s - %s"):format(date("%A", session.start), Clock(session.start), Clock(endAt)),
		duration = duration,
		net = net,
		sources = ns.Recap_GoldSources(session.gold, net),
		counts = counts,
		countsLine = ns.Recap_CountsLine(counts),
		highlights = shown,
		more = more,
		levelLine = gain and ("Level %d  -  %s"):format(level, gain) or ("Level %d"):format(level),
		entries = #session.log,
		xp = gain ~= nil,
		lootText = ns.Value_SessionLootText and ns.Value_SessionLootText(session)
			or (session.lootValue and session.lootValue > 0 and ("loot worth " .. ns.Alts_Gold(session.lootValue))) or nil,
	}
	if live then
		summary.titleNow = function()
			return ns.Recap_Duration(GetServerTime() - session.start)
		end
	end
	return summary
end

local function CurrentSummary()
	return Summarize(ns.Session_Current(), "Session recap", true)
end

---------------------------------------------------------------------------------------------------------------
-- The card

-- Not while the player is busy with something the card would hide. Never waits: it shows now or not at all.
local function BlockedReason()
	if InCombatLockdown() then
		return "in combat"
	elseif UnitOnTaxi("player") then
		return "on a taxi"
	elseif ns.Cinematic.IsActive() then
		return "another cinematic is up"
	elseif (C_PetBattles and C_PetBattles.IsInBattle()) or (InCinematic and InCinematic())
		or (IsInCinematicScene and IsInCinematicScene()) or (MovieFrame and MovieFrame:IsShown()) then
		return "a cutscene or pet battle is on"
	end
	return nil
end

local function Stop()
	if playing then
		ns.Cinematic.Release(playing)
		playing = nil
	end
	ticker:Hide()
end

-- state = { summary, build?, left?, logoutAt?, logoutTotal? }. True when it's on screen.
local function Play(state, escapeToGame)
	if playing or BlockedReason() then
		return false
	end
	playing = state
	ns.Cinematic.Enter(ns.RecapScene, state, {
		skipCamera = true,
		passthrough = true,
		showcase = true,
		hint = escapeToGame and "" or "Any key or click to continue", -- the logout card says it under the timer
		escapeToGame = escapeToGame,
		onDismiss = Stop,
	})
	if not ns.Cinematic.IsOwner(state) then
		playing = nil
		return false
	end
	ticker:Show()
	return true
end

local function Tick()
	if not playing then
		ticker:Hide()
		return
	end
	-- Combat pauses the engine's cinematic (then it's no longer ours): that card is over.
	if not ns.Cinematic.IsOwner(playing) then
		Stop()
		return
	end
	if playing.left then
		playing.left = playing.left - TICK
		if playing.left <= 0 then
			Stop()
		end
	elseif playing.logoutAt and ns.Recap_LogoutLeft(playing) <= 0 and GetTime() > playing.logoutAt + 5 then
		Stop() -- still here well after the countdown: the logout didn't happen
	end
end

local sinceTick = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	sinceTick = sinceTick + elapsed
	if sinceTick >= TICK then
		sinceTick = 0
		Tick()
	end
end)

local function PlayOrSay(state)
	local reason = BlockedReason()
	if reason then
		ns.Print("the recap can't show right now (" .. reason .. ").")
		return
	end
	Play(state)
end

local function ShowCurrent()
	if not module.active then
		ns.Print("Session recap is off.")
		return
	end
	PlayOrSay({ summary = CurrentSummary(), build = CurrentSummary, left = CARD_TIME })
end

local function ShowLast()
	if not module.active then
		ns.Print("Session recap is off.")
		return
	end
	local last = ns.Session_Last(UnitGUID("player"))
	if not last then
		ns.Print("no earlier session recorded for this character.")
		return
	end
	PlayOrSay({ summary = Summarize(last, "Last session", false), left = CARD_TIME })
end

-- A session from the history (Sessions page).
function ns.Recap_ShowStored(h)
	if not module.active then
		ns.Print("Session recap is off.")
		return
	end
	local label = ("%s, %s"):format(h.name or "Session", date("%a %d %b", h.start))
	PlayOrSay({ summary = Summarize(h, label, false), left = CARD_TIME })
end

-- The finished session goes into the history (SessionData.lua calls this when the next one starts).
function ns.Session_OnEnd(session)
	if not (module.active and db.keepHistory) then
		return
	end
	local endAt = session.seen or session.start
	local value, by
	if ns.Value_SessionLoot then
		value, by = ns.Value_SessionLoot(session)
	end
	local copy = ns.Recap_Compact(session, { zone = ns.Session_TopZone(session, endAt), lootValue = value, lootBy = by })
	if copy then
		ns.Recap_Archive(db.history, copy, { by = db.keepBy, count = db.keepCount, days = db.keepDays }, GetServerTime())
	end
end

local SAMPLE_LOG = {
	{ kind = "upgrade", title = "Sample Helm of the Hollow", icon = "Interface\\Icons\\INV_Helmet_03", quality = 4, ago = 4000 },
	{ kind = "achievement", title = "Explore Khaz Algar", icon = "Interface\\Icons\\Achievement_General", ago = 3000 },
	{ kind = "rare", title = "Kereke", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", ago = 2500 },
	{ kind = "rare", title = "Zovex", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", ago = 2000 },
	{ kind = "tame", title = "Loque'nahak", icon = "Interface\\Icons\\Ability_Hunter_BeastTaming", ago = 1500 },
	{ kind = "renown", title = "Council of Dornogal", icon = "Interface\\Icons\\Achievement_Reputation_01", from = 18, to = 19, factionID = 1, ago = 900 },
	{ kind = "loot", title = "Sample Cloak", icon = "Interface\\Icons\\INV_Misc_Cape_01", quality = 4, ago = 600 },
}

local function Preview()
	if not module.active then
		ns.Print("Session recap is off.")
		return
	end
	local now = GetServerTime()
	local session = ns.Session_New("preview", now - 8040, { money = 10000000, level = UnitLevel("player"), xpFraction = XPFraction() })
	session.moneyNow = session.money + 34200000
	session.seen = now
	session.gold = { ["in"] = { loot = 12000000, vendor = 25000000 }, out = { auction = 3500000 } }
	for _, sample in ipairs(SAMPLE_LOG) do
		local entry = {}
		for k, v in pairs(sample) do
			entry[k] = v
		end
		entry.at, entry.ago = now - sample.ago, nil
		ns.Recap_AddNote(session.log, entry, 40)
	end
	PlayOrSay({ summary = Summarize(session, "Session recap", false), left = CARD_TIME })
end

-- The AFK screen's extra stats page (nil when there's nothing to show).
function ns.Recap_AFKPage()
	if not (module.active and db.afkPage) or #ns.Session_Current().log == 0 then
		return nil
	end
	return function()
		local log = ns.Session_Current().log
		local shown = ns.Recap_Highlights(log, 1)
		return shown[1] and shown[1].title or "", ns.Recap_CountsLine(ns.Recap_Counts(log)) .. " this session"
	end
end

---------------------------------------------------------------------------------------------------------------
-- Logout and login

-- Blizzard's logout popup: it keeps ticking while the UI is hidden, and its Cancel (or Esc) is the only way to
-- stay. CancelLogout is protected, so the card can't cancel by itself: Esc goes through to the game instead.
local function LogoutPopup()
	return StaticPopup_FindVisible and StaticPopup_FindVisible("CAMP")
end

-- Seconds until logout: the popup's own timer when it's there, else our estimate.
function ns.Recap_LogoutLeft(state)
	local popup = LogoutPopup()
	if popup and type(popup.timeleft) == "number" and popup.timeleft > 0 then
		return popup.timeleft
	end
	return math.max((state.logoutAt or 0) - GetTime(), 0)
end

-- /camp, the game menu's Log Out and the idle logout. Not /quit: hiding the UI hides Blizzard's quit popup, and
-- its OnHide then tries CancelLogout from our (insecure) call, which the game blocks.
function events:PLAYER_CAMPING()
	if not db.logoutCard then
		return
	end
	local session = ns.Session_Current()
	local state = { summary = CurrentSummary(), build = CurrentSummary, logoutAt = GetTime() + CAMP_TIME }
	local popup = LogoutPopup()
	if popup and type(popup.timeleft) == "number" and popup.timeleft > 0 then
		state.logoutAt = GetTime() + popup.timeleft
	end
	state.logoutTotal = math.max(state.logoutAt - GetTime(), 1)
	if Play(state, true) then
		session.shownAtLogout = true -- no login toast for a session that got its card
	end
end

function events:LOGOUT_CANCEL()
	ns.Session_Current().shownAtLogout = nil
	if playing and playing.logoutAt then
		Stop()
	end
end

local function LoginToast()
	if not (module.active and db.loginToast) then
		return
	end
	local last = ns.Session_Last(UnitGUID("player"))
	if not last or last.toasted then
		return
	end
	last.toasted = true
	if last.shownAtLogout then
		return
	end
	local summary = Summarize(last, "Last session", false)
	if not ns.Recap_Worth(summary) then
		return
	end
	ns.Toast_Show({
		owner = "recap",
		label = "Last session",
		accent = "accent",
		title = UnitName("player"),
		text = ns.Recap_SummaryLine(summary, ns.Recap_Coins) .. "\nClick for the recap.",
		icon = ns.ICON,
		hold = TOAST_HOLD,
		onClick = ShowLast,
	})
end

function events:PLAYER_ENTERING_WORLD(isInitialLogin)
	if isInitialLogin then
		C_Timer.After(LOGIN_DELAY, LoginToast)
	end
end

---------------------------------------------------------------------------------------------------------------

local function Activate()
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_CAMPING", "LOGOUT_CANCEL" }) do
		events:RegisterEvent(event)
	end
	ns.RecapTrack_Start()
end

local function Deactivate()
	events:UnregisterAllEvents()
	ns.RecapTrack_Stop()
	Stop()
	ns.Toast_Clear("recap")
end

local function QualityChoices()
	return {
		{ value = 3, text = "Rare or better" },
		{ value = 4, text = "Epic or better" },
	}
end

module = ns.RegisterModule({
	key = "recap",
	home = {
		{ kind = "page", key = "sessions", order = 7, name = "Sessions", icon = "Interface\\Icons\\INV_Misc_Coin_02",
			page = ns.RecapSessionsPage,
			shown = function()
				return db.keepHistory
			end,
			summary = function()
				local list = ns.Recap_HistoryFilter(db.history, "char", UnitGUID("player"))
				if #list == 0 then
					return "No sessions kept yet"
				end
				local n = ns.Recap_HistoryNumbers(list[1])
				return ("Last: %s, %s%s"):format(ns.Recap_Duration(n.duration), n.net < 0 and "-" or "+", ns.Alts_Gold(math.abs(n.net)))
			end },
		{ kind = "quick", key = "lastrecap", order = 2, name = "Last session recap", open = ShowLast, shown = function()
			return ns.Session_Last(UnitGUID("player")) ~= nil
		end },
	},
	name = "Session recap",
	category = "Ambience",
	description = "What you got done this session: time, gold and where it came from, notable loot, achievements, rares, tames and progress. A card while you log out, on /tomte recap and on the AFK screen; a toast at login for your last session.",
	enabledByDefault = true,
	defaults = {
		logoutCard = true,
		loginToast = true,
		lootQuality = 4,
		afkPage = true,
		history = {}, -- finished sessions, newest first (History.lua)
		keepHistory = true,
		keepBy = "count", -- count | days
		keepCount = 30, -- per character
		keepDays = 28,
		mainNumber = "perHour", -- perHour | net
		nights = false,
		pageScope = "all", -- char | all
		pageRange = "all", -- week | all
	},
	init = function(moduleDB)
		db = moduleDB
		ns.recapDB = moduleDB
	end,
	toggle = function(active)
		if active then
			Activate()
		else
			Deactivate()
		end
	end,
	cinematicState = function()
		return playing
	end,
	commands = {
		{ "last", "the recap of this character's last session", ShowLast },
		{ "preview", "show the recap card with sample data", Preview },
	},
	fallbackCommand = { "", "show this session's recap", ShowCurrent, pattern = "^$" },
	options = {
		{ type = "header", label = "Session recap" },
		{ type = "checkbox", key = "logoutCard", label = "While logging out",
			tooltip = "During the logout countdown (/camp or Log Out), show this session's recap with the time left. Esc cancels the logout (like on Blizzard's popup); any other key or click just closes the card. An instant logout in an inn or city has no countdown: you get the login toast instead." },
		{ type = "checkbox", key = "loginToast", label = "Last session at login",
			tooltip = "A few seconds after logging in, a toast with your last session on this character (when it was at least 10 minutes and something happened). Click it for the recap." },
		{ type = "checkbox", key = "afkPage", label = "On the AFK screen",
			tooltip = "Add a highlights page to the AFK screen's rotating session stats." },
		{ type = "dropdown", key = "lootQuality", label = "Notable loot", choices = QualityChoices,
			tooltip = "Items you receive at this quality or better are listed. Achievements, new mounts, pets, toys and renown come from Moments (also when their style is off, but not with Moments turned off)." },
		{ type = "button", label = "Preview", text = "Show", onClick = Preview,
			tooltip = "Show the recap card with sample data. Any key or click closes it." },
		{ type = "header", label = "Sessions page" },
		{ type = "checkbox", key = "keepHistory", label = "Keep history",
			tooltip = "Keep finished sessions (2 minutes or longer) for the Sessions page. A session is kept when the next one starts." },
		{ type = "dropdown", key = "keepBy", label = "Keep by", choices = function()
			return { { value = "count", text = "Number of sessions" }, { value = "days", text = "Days" } }
		end },
		{ type = "slider", key = "keepCount", label = "Sessions per character", min = 10, max = 100, step = 5 },
		{ type = "slider", key = "keepDays", label = "Days kept", min = 7, max = 90, step = 7 },
		{ type = "dropdown", key = "mainNumber", label = "Chart shows", choices = function()
			return { { value = "perHour", text = "Gold per hour" }, { value = "net", text = "Net gold per session" } }
		end },
		{ type = "checkbox", key = "nights", label = "Group into play nights",
			tooltip = "Sessions less than an hour apart (any character) are grouped under one line with their totals." },
		{ type = "button", label = "History", text = "Clear", confirm = "Clear the session history on every character?",
			onClick = function()
				wipe(db.history)
				ns.Print("session history cleared.")
			end },
	},
})
ns.recapModule = module
