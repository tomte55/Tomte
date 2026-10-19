local addonName, ns = ...

-- AFK module, pure logic: no WoW API calls (unit-tested with plain Lua).

local EPSILON = 1e-6 -- level + fraction sums aren't exact in floating point
local AUTO_AFK_DELAY = 300 -- seconds without input before the game flags you AFK by itself
local MANUAL_WINDOW = 5 -- seconds: a flag this soon after typing /afk came from the command, not the idle timer

-- When the player really went away, given when the AFK flag appeared and when they last typed /afk (or nil).
-- A typed /afk means they left just then; otherwise the game's idle timer set the flag after AUTO_AFK_DELAY.
function ns.AFK_AwaySince(flaggedAt, manualAt)
	if manualAt and flaggedAt - manualAt >= 0 and flaggedAt - manualAt <= MANUAL_WINDOW then
		return flaggedAt
	end
	return flaggedAt - AUTO_AFK_DELAY
end

function ns.AFK_ClockText(hour, minute, military)
	if military then
		return ("%02d:%02d"):format(hour, minute)
	end
	local suffix = hour < 12 and "AM" or "PM"
	local h = hour % 12
	if h == 0 then
		h = 12
	end
	return ("%d:%02d %s"):format(h, minute, suffix)
end

-- Progress since the session start, from level + fraction of the level (xp / xpMax). nil when none.
function ns.AFK_XPGain(startLevel, startFraction, level, fraction)
	local delta = (level + fraction) - (startLevel + startFraction)
	if delta <= EPSILON then
		return nil
	end
	if delta < 1 - EPSILON then
		return ("+%d%% of a level"):format(math.floor(delta * 100 + EPSILON))
	end
	return ("+%.1f levels"):format(delta)
end

-- Appends a whisper; past max the oldest is dropped (list.dropped counts them).
function ns.AFK_AddWhisper(list, entry, max)
	list[#list + 1] = entry
	while #list > max do
		table.remove(list, 1)
		list.dropped = (list.dropped or 0) + 1
	end
end

-- The newest n whispers, oldest first, and how many whispers in total aren't among them.
function ns.AFK_VisibleWhispers(list, n)
	local first = math.max(#list - n + 1, 1)
	local shown = {}
	for i = first, #list do
		shown[#shown + 1] = list[i]
	end
	return shown, (first - 1) + (list.dropped or 0)
end

-- Popups the AFK screen gives way to: it closes for the rest of this AFK so the popup can be seen. true = always,
-- { arg, value } = only when the payload's arg-th value is value. Names and payloads from warcraft.wiki.gg,
-- 2026-10-19. UPDATE_BATTLEFIELD_STATUS is handled in AFK.lua: it needs GetBattlefieldStatus.
ns.AFK_INTERRUPTS = {
	LFG_PROPOSAL_SHOW = true, -- a Dungeon or Raid Finder group is ready
	READY_CHECK = true,
	PARTY_INVITE_REQUEST = true,
	CONFIRM_SUMMON = true,
	LFG_ROLE_CHECK_SHOW = true,
	LFG_READY_CHECK_SHOW = true,
	LFG_LIST_APPLICATION_STATUS_UPDATED = { arg = 2, value = "invited" }, -- searchResultID, newStatus, ...
	PET_BATTLE_QUEUE_PROPOSE_MATCH = true, -- a PvP pet battle was found
	DUEL_REQUESTED = true,
	TRADE_REQUEST = true,
	TRADE_SHOW = true, -- a trade usually opens straight away, without a request
	RESURRECT_REQUEST = true,
	GUILD_INVITE_REQUEST = true,
	GROUP_INVITE_CONFIRMATION = true, -- someone in your group wants to invite a player
}

function ns.AFK_Interrupts(event, ...)
	local rule = ns.AFK_INTERRUPTS[event]
	if rule == true then
		return true
	end
	if type(rule) == "table" then
		return select("#", ...) >= rule.arg and (select(rule.arg, ...)) == rule.value
	end
	return false
end

-- Money text with coin icons lives in Core/Format.lua; this name stays for the callers.
ns.AFK_MoneyText = ns.Coins
