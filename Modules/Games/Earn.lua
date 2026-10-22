local addonName, ns = ...

-- Casino: chips earned by playing the game, read from the game here and paid by the rules in ChipRules.lua.
-- Flight paths (start and landing come from Casino.lua's taxi checks), quests turned in, the week's first Great
-- Vault claim and gold picked up from loot. Casino.lua owns the event frame and passes events on through
-- ns.CasinoEarn_OnEvent while the module is on.

local db
local onPaid -- onPaid(source, amount): Casino.lua shows it and checks feats
local frequency = {} -- [questID] = "daily" / "weekly", noted when the quest frame offers the turn-in
local looting, moneyBefore = false, nil

ns.CASINO_EARN_EVENTS = { "QUEST_COMPLETE", "QUEST_TURNED_IN", "LOOT_READY", "LOOT_CLOSED", "PLAYER_MONEY" }

local function Day()
	return ns.Chips_ResetKey(GetServerTime(), C_DateAndTime.GetSecondsUntilDailyReset())
end

local function Week()
	return ns.Chips_ResetKey(GetServerTime(), C_DateAndTime.GetSecondsUntilWeeklyReset())
end

local function Pay(source, amount)
	if amount > 0 then
		ns.Blackjack_AddChips(db.game, amount)
		onPaid(source, amount)
	end
end

local function On(source)
	return db ~= nil and ns.Casino_Active() and db.earn[source]
end

-- Flight paths ----------------------------------------------------------------------------------------------------

-- On a taxi: the start time is saved, so a /reload in the air still pays the whole flight.
function ns.CasinoEarn_FlightStart()
	if not db.earned.flightStart then
		db.earned.flightStart = GetServerTime()
	end
end

function ns.CasinoEarn_FlightEnd()
	local start = db.earned.flightStart
	db.earned.flightStart = nil
	if start and On("flight") then
		Pay("flight", ns.Chips_FlightPay(db.earned, Day(), GetServerTime() - start))
	end
end

-- Quests, loot ----------------------------------------------------------------------------------------------------

local handlers = {}

function handlers.QUEST_COMPLETE()
	local questID = GetQuestID()
	if questID and questID > 0 then
		frequency[questID] = (QuestIsWeekly() and "weekly") or (QuestIsDaily() and "daily") or "normal"
	end
end

-- Hidden tracking quests also "turn in": only quests seen at the quest frame, with a reward, or world quests and
-- bonus objectives pay.
function handlers.QUEST_TURNED_IN(questID, xp, money)
	if not ns.Readable(questID, xp, money) then
		return
	end
	local noted = frequency[questID]
	frequency[questID] = nil
	if not On("quest") then
		return
	end
	if noted or (xp or 0) > 0 or (money or 0) > 0 or C_QuestLog.IsWorldQuest(questID)
		or C_QuestLog.IsQuestTask(questID) then
		Pay("quest", ns.Chips_QuestPay(db.earned, Day(), noted ~= "normal" and noted or nil))
	end
end

-- Money that arrives while a loot window is open is looted gold (not vendor, mail, auction or quest gold).
function handlers.LOOT_READY()
	looting, moneyBefore = true, GetMoney()
end

function handlers.LOOT_CLOSED()
	looting = false
end

function handlers.PLAYER_MONEY()
	local now = GetMoney()
	local gained = looting and moneyBefore and now - moneyBefore or 0
	moneyBefore = now
	if gained > 0 and On("loot") then
		Pay("loot", ns.Chips_LootPay(db.earned, Day(), gained))
	end
end

function ns.CasinoEarn_OnEvent(event, ...)
	local handler = handlers[event]
	if handler then
		handler(...)
	end
end

-- Great Vault -----------------------------------------------------------------------------------------------------

-- Blizzard_WeeklyRewards calls this when you pick your reward. The hook stays for the session: it does nothing
-- while the module or the setting is off.
hooksecurefunc(C_WeeklyRewards, "ClaimReward", function()
	if On("vault") then
		Pay("vault", ns.Chips_VaultPay(db.earned, Day(), Week()))
	end
end)

-- API ---------------------------------------------------------------------------------------------------------

function ns.CasinoEarn_Init(saved, paid)
	db, onPaid = saved, paid
end

function ns.CasinoEarn_Stop()
	looting, moneyBefore = false, nil
	wipe(frequency)
end

-- The day key and seconds to the daily reset, for the house refill.
function ns.CasinoEarn_Day()
	return Day(), C_DateAndTime.GetSecondsUntilDailyReset()
end
