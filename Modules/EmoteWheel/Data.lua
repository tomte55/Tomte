local addonName, ns = ...

-- Emote wheel: pure logic (no WoW API calls; unit-tested in tests/test_emotewheel.lua). What a slice's text means
-- (an emote, a chat line, another slash command), which slice the cursor points at, and when a buff is worth a thank
-- you. The wheel is drawn in Wheel.lua, buff thanks live in Thanks.lua, registered in EmoteWheel.lua.

ns.EMOTEWHEEL_MIN, ns.EMOTEWHEEL_MAX = 4, 12 -- slices on the wheel; fewer filled slots than the minimum still draw
ns.EMOTEWHEEL_LONG_BUFF = 600 -- seconds: a buff shorter than this (a heal over time, a short shield) isn't thanked
ns.EMOTEWHEEL_THANK_AGAIN = 1800 -- seconds before the same player's same buff is thanked again (rebuffs)
ns.EMOTEWHEEL_THANK_LINE = "Thanks for the buff, %t!" -- the thank-you line when the setting is empty

local TWO_PI = 2 * math.pi
local atan2 = math.atan2 or function(y, x)
	return math.atan(y, x)
end

-- The slots in order, empty ones skipped: { { name, text }, ... }. slots = db.slots ({ s1 = { name, text }, ... }).
function ns.EmoteWheel_Slices(slots)
	local list = {}
	for i = 1, ns.EMOTEWHEEL_MAX do
		local slot = slots and slots["s" .. i]
		local text = slot and type(slot.text) == "string" and slot.text:match("^%s*(.-)%s*$") or ""
		if text ~= "" then
			list[#list + 1] = { name = slot.name or "", text = text, slot = i }
		end
	end
	return list
end

-- The name shown on a slice: its own, else made from the command ("/bow" -> "Bow"), else the text's start.
function ns.EmoteWheel_Label(slice)
	local name = slice.name and slice.name:match("^%s*(.-)%s*$") or ""
	if name ~= "" then
		return name
	end
	local cmd = slice.text:match("^/(%S+)$")
	if cmd then
		return cmd:sub(1, 1):upper() .. cmd:sub(2):lower()
	end
	return ns.EmoteWheel_Short(slice.text, 12)
end

-- text cut to max characters with "..." (counted in characters, not bytes, so accented letters aren't split).
function ns.EmoteWheel_Short(text, max)
	local chars = {}
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		chars[#chars + 1] = ch
	end
	if #chars <= max then
		return text
	end
	return table.concat(chars, "", 1, max - 1) .. "..."
end

-- UnitName's name and realm as one name a whisper reaches: "Kesha-Realm" from another realm, "Kesha" from yours.
function ns.EmoteWheel_FullName(name, realm)
	if realm and realm ~= "" then
		return name .. "-" .. realm
	end
	return name
end

-- %t becomes target; nil when the text has %t and there's no target.
function ns.EmoteWheel_Fill(text, target)
	if not text:find("%%t") then
		return text
	end
	if not target or target == "" then
		return nil
	end
	return (text:gsub("%%t", function()
		return target
	end))
end

-- What a filled-in slice text does. lookups (built in game from Blizzard's localized slash globals, upper-cased with
-- the slash): chat = { ["/S"] = "SAY", ["/W"] = "WHISPER", ... }, emotes = { ["/BOW"] = "BOW" },
-- secure = { ["/CAST"] = true }, slash = { ["/DANCE"] = "DANCE" } (SlashCmdList keys).
-- Returns { kind = "chat", chatType, text, target } | { kind = "emote", token, target } |
--   { kind = "slash", key, msg } | { kind = "secure", command } | { kind = "unknown", command } | nil (nothing to do).
-- Text without a slash is said out loud.
function ns.EmoteWheel_Parse(text, lookups)
	text = text and text:match("^%s*(.-)%s*$") or ""
	if text == "" then
		return nil
	end
	if text:sub(1, 1) ~= "/" then
		return { kind = "chat", chatType = "SAY", text = text }
	end
	local command, rest = text:match("^(/%S+)%s*(.-)$")
	local upper = command:upper()
	local chatType = lookups.chat and lookups.chat[upper]
	if chatType then
		if chatType == "WHISPER" then
			local target, message = rest:match("^(%S+)%s*(.-)$")
			if not target or message == "" then
				return nil
			end
			return { kind = "chat", chatType = "WHISPER", text = message, target = target }
		end
		if rest == "" then
			return nil
		end
		return { kind = "chat", chatType = chatType, text = rest }
	end
	local token = lookups.emotes and lookups.emotes[upper]
	if token then
		return { kind = "emote", token = token, target = rest ~= "" and rest or nil }
	end
	if lookups.secure and lookups.secure[upper] then
		return { kind = "secure", command = command }
	end
	local key = lookups.slash and lookups.slash[upper]
	if key then
		return { kind = "slash", key = key, msg = rest }
	end
	return { kind = "unknown", command = command }
end

-- Slice i of count's middle, as an angle clockwise from straight up (radians). Slice 1 sits at the top.
function ns.EmoteWheel_Angle(i, count)
	return (i - 1) * TWO_PI / count
end

-- x, y (y up) of a point radius out at angle (clockwise from up).
function ns.EmoteWheel_Point(angle, radius)
	return math.sin(angle) * radius, math.cos(angle) * radius
end

-- The slice under the cursor at dx, dy from the wheel's middle (y up), or nil inside deadRadius.
function ns.EmoteWheel_SliceAt(dx, dy, count, deadRadius)
	if count < 1 or (dx * dx + dy * dy) < deadRadius * deadRadius then
		return nil
	end
	local angle = atan2(dx, dy) -- clockwise from up
	if angle < 0 then
		angle = angle + TWO_PI
	end
	local step = TWO_PI / count
	return math.floor((angle + step / 2) / step) % count + 1
end

-- Buff thanks ---------------------------------------------------------------------------------------------------------

-- Whether a buff that just landed on you is worth a thank-you card. buff = { fromPlayer (cast by another player, not
-- you or your pet), duration (seconds, 0 for none), inCombat, inInstance }, rules = { instances }, lastAt = when this
-- player's same buff was last offered (or nil), now.
function ns.EmoteWheel_ShouldThank(buff, rules, lastAt, now)
	if not buff.fromPlayer or buff.inCombat then
		return false
	end
	if buff.inInstance and not rules.instances then
		return false
	end
	if not buff.duration or buff.duration < ns.EMOTEWHEEL_LONG_BUFF then
		return false
	end
	return not (lastAt and now - lastAt < ns.EMOTEWHEEL_THANK_AGAIN)
end
