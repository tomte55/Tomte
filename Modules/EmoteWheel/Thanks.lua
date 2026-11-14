local addonName, ns = ...

-- Emote wheel: buff thanks. When another player puts a lasting buff on you out of combat, a toast says who and what;
-- clicking it thanks them (said, whispered or the /thank emote, from the settings), right-click dismisses it. The
-- click is the hardware event /say needs outside instances. Rules in Data.lua, registered in EmoteWheel.lua.

local OWNER = "emotewheel" -- events owner and toast owner (the module key, which Recent lists)
local TOAST_HOLD = 20 -- seconds a thank-you card stays up
local SAMPLE_ICON = 135932 -- spell_holy_magicalsentry (Arcane Intellect)

local events = ns.NewEvents()
ns.EmoteWheel_Events = events

local LOG_SIZE = 8 -- buffs kept for /tomte emotewheel why
local SOMEONE = "?" -- the merge and repeat key for a buff whose caster the game doesn't name

local db
local lastOffered = {} -- ["name:spellID"] = GetTime() when its card was shown
local log = {} -- the last buffs that landed on you and what was decided, newest last

local function Note(buff, decision)
	log[#log + 1] = ("%s  %s: %s"):format(date("%H:%M:%S"), tostring(buff or "?"), decision)
	if #log > LOG_SIZE then
		table.remove(log, 1)
	end
end

-- Why a buff got no card, in player wording (the rules in Data.lua's EmoteWheel_ShouldThank).
local function NoCardReason(buff, lastAt, now)
	if buff.inCombat then
		return "in combat"
	elseif buff.inInstance and not db.thanks.instances then
		return "in an instance"
	elseif not buff.duration or buff.duration < ns.EMOTEWHEEL_LONG_BUFF then
		return ("lasts %ss, under %ds"):format(tostring(buff.duration), ns.EMOTEWHEEL_LONG_BUFF)
	end
	return ("same player's same buff %ds ago (again after %ds)"):format(math.floor(now - (lastAt or now)),
		ns.EMOTEWHEEL_THANK_AGAIN)
end

local function InInstance()
	local inside, kind = IsInInstance()
	return inside and kind ~= "none"
end

-- %t (their name) and %b (the buff) in the thank-you line.
local function Line(name, buff)
	local line = db.thanks.line ~= "" and db.thanks.line or ns.EMOTEWHEEL_THANK_LINE
	return (line:gsub("%%([tb])", function(which)
		return which == "t" and name or buff
	end))
end

local function Thank(name, fullName, buff)
	local how = db.thanks.how
	if how == "emote" then
		ns.Chat_Emote("THANK", fullName)
		return
	end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		ns.Print("Chat is locked right now; try again after the fight.")
		return
	end
	if how == "whisper" then
		ns.Chat_Send(Line(name, buff), "WHISPER", nil, fullName)
	else
		ns.Chat_Send(Line(name, buff), "SAY")
	end
end

local function HowText()
	local how = db.thanks.how
	return how == "emote" and "Click: /thank" or how == "whisper" and "Click: whisper thanks" or "Click: say thanks"
end

-- fullName nil: the game doesn't say who cast it, so the card thanks everyone around you (/thank with no target:
-- "none", or the emote would go to your current target).
local function Offer(name, fullName, class, buff, icon, test)
	ns.Toast_Show({
		owner = OWNER,
		label = "Buff thanks",
		title = fullName and ns.UI.ClassColored(name, class) or name,
		accent = "accent",
		icon = icon,
		mergeKey = fullName or SOMEONE,
		hold = TOAST_HOLD,
		test = test,
		recentTitle = name,
		text = "gave you " .. buff .. "\n" .. ns.UI.Wrap((fullName and HowText() or "Click: /thank everyone")
			.. " - Right-click: dismiss", "textFaint"),
		onClick = function(button)
			if button ~= "LeftButton" or test then
				return
			end
			if fullName then
				Thank(name, fullName, buff)
			else
				ns.Chat_Emote("THANK", "none")
			end
		end,
	})
end

-- how: "new" or "recast", for the log.
local function OnAura(aura, how)
	local source = aura.sourceUnit
	if ns.IsSecret(source, aura.duration, aura.spellId, aura.name) then
		Note("a buff", how .. ", no card: its details are hidden right now")
		return
	end
	-- Short buffs are never thanked (EmoteWheel_ShouldThank) and would fill the log.
	if not aura.isHelpful or not aura.duration or aura.duration < ns.EMOTEWHEEL_LONG_BUFF then
		return
	end
	if not source then
		-- The caster has no unit (not your target, mouseover, party member or a nameplate). A player's buff still gets a
		-- card that thanks everyone around; an NPC's (isFromPlayerOrPlayerPet false) doesn't.
		local fromPlayer = aura.isFromPlayerOrPlayerPet
		if ns.IsSecret(fromPlayer) or not fromPlayer then
			Note(aura.name, how .. ", no card: the game doesn't say who cast it, and it wasn't a player")
			return
		end
		local key, now = SOMEONE .. ":" .. aura.spellId, GetTime()
		local buff = { fromPlayer = true, duration = aura.duration, inCombat = InCombatLockdown(),
			inInstance = InInstance() }
		if not ns.EmoteWheel_ShouldThank(buff, db.thanks, lastOffered[key], now) then
			Note(aura.name, ("%s by someone nearby, no card: %s"):format(how, NoCardReason(buff, lastOffered[key], now)))
			return
		end
		Note(aura.name, how .. " by someone nearby (the game doesn't say who): card shown, thanks everyone")
		lastOffered[key] = now
		Offer("Someone nearby", nil, nil, aura.name, aura.icon)
		return
	end
	if UnitIsUnit(source, "player") or not UnitIsPlayer(source) then
		Note(aura.name, how .. ", no card: from you or not from a player")
		return
	end
	local name, realm = UnitName(source)
	if not name or ns.IsSecret(name, realm) then
		Note(aura.name, how .. ", no card: the caster's name is hidden right now")
		return
	end
	local fullName = ns.EmoteWheel_FullName(name, realm)
	local key = fullName .. ":" .. aura.spellId
	local now = GetTime()
	local buff = { fromPlayer = true, duration = aura.duration, inCombat = InCombatLockdown(), inInstance = InInstance() }
	if not ns.EmoteWheel_ShouldThank(buff, db.thanks, lastOffered[key], now) then
		Note(aura.name, ("%s by %s, no card: %s"):format(how, name, NoCardReason(buff, lastOffered[key], now)))
		return
	end
	Note(aura.name, ("%s by %s: card shown"):format(how, name))
	lastOffered[key] = now
	local _, class = UnitClass(source)
	Offer(name, fullName, class, aura.name, aura.icon)
end

events:On(OWNER, "UNIT_AURA", function(_, unit, info)
	-- The update info itself can be secret (isFullUpdate was, seen in BugSack): no buff thanks from such an update.
	if unit ~= "player" or not info or ns.IsSecret(info.isFullUpdate, info.addedAuras) then
		return
	end
	if info.isFullUpdate then
		return
	end
	for _, aura in ipairs(info.addedAuras or {}) do
		OnAura(aura, "new")
	end
	-- Recasting a buff you already have updates it in place instead of adding it.
	local updated = info.updatedAuraInstanceIDs
	if not updated or ns.IsSecret(updated) then
		return
	end
	local now = GetTime()
	for _, id in ipairs(updated) do
		local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", id)
		if aura and not ns.IsSecret(aura.duration, aura.expirationTime, aura.isHelpful) and aura.isHelpful then
			if ns.EmoteWheel_JustRefreshed(aura.duration, aura.expirationTime, now) then
				OnAura(aura, "recast")
			elseif aura.duration and aura.duration >= ns.EMOTEWHEEL_LONG_BUFF then
				-- Long buffs only: short ones update all the time (stacks, ticks) and would fill the log.
				Note(aura.name, ("updated, not a recast (%ds of %ds left)"):format(
					math.floor((aura.expirationTime or 0) - now), aura.duration))
			end
		end
	end
end)

-- Called by EmoteWheel.lua ------------------------------------------------------------------------------------------

function ns.EmoteWheelThanks_Init(saved)
	db = saved
end

function ns.EmoteWheelThanks_Apply(active)
	if active and db.thanks.on then
		events:Watch(OWNER, "UNIT_AURA", "player")
	else
		events:Unwatch(OWNER, "UNIT_AURA")
		ns.Toast_Clear(OWNER)
	end
end

-- /tomte emotewheel why: whether buff thanks listens, and the last buffs that landed on you with what was decided.
function ns.EmoteWheelThanks_Why(active)
	ns.Print(("buff thanks: %s."):format(not active and "off (Emote wheel is off)"
		or not db.thanks.on and "off in the settings" or "listening"))
	if #log == 0 then
		print("  No buffs seen this session.")
	end
	for _, line in ipairs(log) do
		print("  " .. line)
	end
end

function ns.EmoteWheelThanks_Sample()
	Offer("Aldric", "Aldric", "MAGE", "Arcane Intellect", SAMPLE_ICON, true)
end
