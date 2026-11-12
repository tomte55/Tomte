local addonName, ns = ...

-- Emote wheel: buff thanks. When another player puts a lasting buff on you out of combat, a toast says who and what;
-- clicking it thanks them (said, whispered or the /thank emote, from the settings), right-click dismisses it. The
-- click is the hardware event /say needs outside instances. Rules in Data.lua, registered in EmoteWheel.lua.

local OWNER = "emotewheel" -- events owner and toast owner (the module key, which Recent lists)
local TOAST_HOLD = 20 -- seconds a thank-you card stays up
local SAMPLE_ICON = 135932 -- spell_holy_magicalsentry (Arcane Intellect)

local events = ns.NewEvents()
ns.EmoteWheel_Events = events

local db
local lastOffered = {} -- ["name:spellID"] = GetTime() when its card was shown

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

local function Offer(name, fullName, class, buff, icon, test)
	ns.Toast_Show({
		owner = OWNER,
		label = "Buff thanks",
		title = ns.UI.ClassColored(name, class),
		accent = "accent",
		icon = icon,
		mergeKey = fullName,
		hold = TOAST_HOLD,
		test = test,
		recentTitle = name,
		text = "gave you " .. buff .. "\n" .. ns.UI.Wrap(HowText() .. " - Right-click: dismiss", "textFaint"),
		onClick = function(button)
			if button == "LeftButton" and not test then
				Thank(name, fullName, buff)
			end
		end,
	})
end

local function OnAura(aura)
	local source = aura.sourceUnit
	if ns.IsSecret(source, aura.duration, aura.spellId, aura.name) then
		return
	end
	if not (source and aura.isHelpful) or UnitIsUnit(source, "player") or not UnitIsPlayer(source) then
		return
	end
	local name, realm = UnitName(source)
	if not name or ns.IsSecret(name, realm) then
		return
	end
	local fullName = ns.EmoteWheel_FullName(name, realm)
	local key = fullName .. ":" .. aura.spellId
	local now = GetTime()
	local buff = { fromPlayer = true, duration = aura.duration, inCombat = InCombatLockdown(), inInstance = InInstance() }
	if not ns.EmoteWheel_ShouldThank(buff, db.thanks, lastOffered[key], now) then
		return
	end
	lastOffered[key] = now
	local _, class = UnitClass(source)
	Offer(name, fullName, class, aura.name, aura.icon)
end

events:On(OWNER, "UNIT_AURA", function(_, unit, info)
	if unit ~= "player" or not info or info.isFullUpdate or not info.addedAuras then
		return
	end
	for _, aura in ipairs(info.addedAuras) do
		OnAura(aura)
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

function ns.EmoteWheelThanks_Sample()
	Offer("Aldric", "Aldric", "MAGE", "Arcane Intellect", SAMPLE_ICON, true)
end
