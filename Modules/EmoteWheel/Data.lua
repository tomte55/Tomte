local addonName, ns = ...

-- Emote wheel: pure logic (no WoW API calls; unit-tested in tests/test_emotewheel.lua). What a slice's text means
-- (an emote, a chat line, another slash command, or several lines run in turn), which slice the cursor points at,
-- and when a buff is worth a thank you. The wheel is drawn in Wheel.lua, buff thanks live in Thanks.lua, registered
-- in EmoteWheel.lua.

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

-- A slice's text as its lines, trimmed, empty ones left out. Several lines run one after another on one press, like
-- a macro ("Thanks!" then "/ty").
function ns.EmoteWheel_Lines(text)
	local lines = {}
	for line in (text or ""):gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" then
			lines[#lines + 1] = line
		end
	end
	return lines
end

-- The text on one line, for showing on the wheel: "Thanks!; /ty".
function ns.EmoteWheel_OneLine(text)
	return table.concat(ns.EmoteWheel_Lines(text), "; ")
end

-- The name shown on a slice: its own, else made from the (first line's) command ("/bow" -> "Bow"), else its start.
function ns.EmoteWheel_Label(slice)
	local name = slice.name and slice.name:match("^%s*(.-)%s*$") or ""
	if name ~= "" then
		return name
	end
	local first = ns.EmoteWheel_Lines(slice.text)[1] or ""
	local cmd = first:match("^/(%S+)$")
	if cmd then
		return cmd:sub(1, 1):upper() .. cmd:sub(2):lower()
	end
	return ns.EmoteWheel_Short(first, 12)
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
	if not command then
		return nil -- a / with nothing after it (yet): nothing to do
	end
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

-- The editor ----------------------------------------------------------------------------------------------------------

-- Chat lines the editor builds, in its order; a whisper always goes to the target (%t).
ns.EMOTEWHEEL_LINE_TYPES = { "SAY", "YELL", "PARTY", "GUILD", "WHISPER" }
local LINE = {}
for _, chatType in ipairs(ns.EMOTEWHEEL_LINE_TYPES) do
	LINE[chatType] = true
end

local SAYS = { -- how Describe words a chat line: %s is the message
	SAY = "Says \"%s\".", YELL = "Yells \"%s\".", EMOTE = "Emotes \"%s\".", PARTY = "Says \"%s\" to your party.",
	RAID = "Says \"%s\" to your raid.", RAID_WARNING = "Shows \"%s\" as a raid warning.",
	INSTANCE_CHAT = "Says \"%s\" to your instance group.", GUILD = "Says \"%s\" to your guild.",
	OFFICER = "Says \"%s\" to your guild officers.",
}

local function Trim(text)
	return type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
end

-- The editor's list of slices ({ name, text }, in order) in the saved shape: s1 .. s<MAX>, empty slots after it. A
-- slice with no text yet is saved too; the wheel leaves it out until it has some.
function ns.EmoteWheel_Store(list)
	local slots = {}
	for i = 1, ns.EMOTEWHEEL_MAX do
		local s = list[i]
		slots["s" .. i] = { name = s and s.name or "", text = s and s.text or "" }
	end
	return slots
end

-- Moves list[from] to place `to`, the slices between shifting over; in place, returns list.
function ns.EmoteWheel_Move(list, from, to)
	if from ~= to and list[from] and to >= 1 and to <= #list then
		table.insert(list, to, table.remove(list, from))
	end
	return list
end

-- Which of the editor's three ways a slice's text is: "emote", token (nil while none is picked: empty text) |
-- "line", chatType, message (one of EMOTEWHEEL_LINE_TYPES; text without a slash is said) | "command" (anything
-- else, and any slice of several lines). lookups as for EmoteWheel_Parse.
function ns.EmoteWheel_Kind(text, lookups)
	text = Trim(text)
	if text == "" then
		return "emote", nil
	end
	if #ns.EmoteWheel_Lines(text) > 1 then
		return "command"
	end
	if text:sub(1, 1) ~= "/" then
		return "line", "SAY", text
	end
	local command, rest = text:match("^(/%S+)%s*(.-)$")
	if not command then
		return "command" -- a / with nothing after it yet
	end
	local upper = command:upper()
	local chatType = lookups.chat and lookups.chat[upper]
	if chatType then
		if not LINE[chatType] then
			return "command"
		end
		if chatType == "WHISPER" then
			local target, message = rest:match("^(%S+)%s*(.-)$")
			if rest == "" or target == "%t" then
				return "line", "WHISPER", message or ""
			end
			return "command" -- a whisper to someone by name
		end
		return "line", chatType, rest
	end
	local token = lookups.emotes and lookups.emotes[upper]
	if token and rest == "" then
		return "emote", token
	end
	return "command"
end

-- The text for a chat line: commands = { SAY = "/s", ... } (the game's own, localized). Something to say without a
-- slash is kept as plain text, which the wheel says.
function ns.EmoteWheel_Line(chatType, message, commands)
	message = Trim(message)
	if chatType == "SAY" and message ~= "" and message:sub(1, 1) ~= "/" then
		return message
	end
	local command = commands[chatType] or commands.SAY
	if chatType == "WHISPER" then
		command = command .. " %t"
	end
	return message ~= "" and (command .. " " .. message) or command
end

-- One sentence on what a slice's text does, for the editor (one per line, "Then ..." after the first). %t shows as
-- [target].
function ns.EmoteWheel_Describe(text, lookups)
	text = Trim(text)
	if text == "" then
		return "Pick an emote, or write a line to say."
	end
	local lines = ns.EmoteWheel_Lines(text)
	if #lines > 1 then
		local parts = {}
		for i, line in ipairs(lines) do
			local said = ns.EmoteWheel_Describe(line, lookups)
			parts[i] = i == 1 and said or ("Then " .. said:sub(1, 1):lower() .. said:sub(2))
		end
		return table.concat(parts, " ")
	end
	local action = ns.EmoteWheel_Parse(text, lookups)
	local function Shown(s)
		return (s:gsub("%%t", "[target]"))
	end
	if not action then
		return "Sends nothing yet: add a message."
	elseif action.kind == "emote" then
		local command = text:match("^(/%S+)")
		if action.target then
			return ("Does %s at %s."):format(command, Shown(action.target))
		end
		return ("Does %s, at your target if you have one."):format(command)
	elseif action.kind == "chat" then
		if action.chatType == "WHISPER" then
			return ("Whispers \"%s\" to %s."):format(Shown(action.text), action.target == "%t" and "your target"
				or action.target)
		end
		return (SAYS[action.chatType] or SAYS.SAY):format(Shown(action.text))
	elseif action.kind == "slash" then
		return ("Runs %s."):format(Shown(text))
	elseif action.kind == "secure" then
		return ("The wheel can't run %s: only the game's own buttons and macros can."):format(action.command)
	end
	return ("%s isn't a command the game knows."):format(action.command)
end

-- What an emote does besides its chat text, from Generated.lua: acts (your character acts it out), voice (a voice
-- line for your character). race: UnitRace's race id, sex: UnitSex (2 male, 3 female), class: UnitClass's class id.
-- An emote the file doesn't know: neither.
function ns.EmoteWheel_Extras(token, race, sex, class)
	local acts = token ~= nil and ns.EMOTEWHEEL_ACTS ~= nil and ns.EMOTEWHEEL_ACTS[token] == true
	local lines = token ~= nil and ns.EMOTEWHEEL_VOICE and ns.EMOTEWHEEL_VOICE[token]
	local voice = lines == true
	if type(lines) == "table" and race and sex then
		local key = race .. "-" .. (sex == 3 and 1 or 0)
		voice = lines[key] == true or (class ~= nil and lines[key .. "-" .. class] == true)
	end
	return acts, voice
end

-- The editor's sentence for an emote's extras, or nil when it has neither.
function ns.EmoteWheel_ExtrasText(acts, voice)
	if acts and voice then
		return "Your character acts it out and says it out loud."
	elseif acts then
		return "Your character acts it out."
	elseif voice then
		return "Your character says it out loud."
	end
	return nil
end

-- The emotes whose name or one of whose commands holds query (any case, a leading / ignored); all of them for "".
-- emotes = { { name = "Wave", commands = { "/wave", ... } }, ... }.
function ns.EmoteWheel_FilterEmotes(emotes, query)
	query = Trim(query):lower():gsub("^/", "")
	if query == "" then
		return emotes
	end
	local list = {}
	for _, emote in ipairs(emotes) do
		local hit = emote.name:lower():find(query, 1, true)
		for _, command in ipairs(emote.commands) do
			hit = hit or command:lower():find(query, 1, true)
		end
		if hit then
			list[#list + 1] = emote
		end
	end
	return list
end

-- The wheel ------------------------------------------------------------------------------------------------------------

-- Slice i of count's middle, as an angle clockwise from straight up (radians). Slice 1 sits at the top.
function ns.EmoteWheel_Angle(i, count)
	return (i - 1) * TWO_PI / count
end

-- How far a label whose middle is at x, y stays from slice angle's sides (step wide) and rims (inner, outer): the
-- smallest gap, negative when it pokes out. boxes = { { w, h, dy }, ... }: its lines, each centered dy above the
-- label's middle. Wheel units, y up.
local function Clearance(angle, step, x, y, boxes, inner, outer)
	local left, right = angle - step / 2, angle + step / 2
	local cl, sl, cr, sr = math.cos(left), math.sin(left), math.cos(right), math.sin(right)
	local worst = math.huge
	for _, box in ipairs(boxes) do
		local bx, by, w2, h2 = x, y + box[3], box[1] / 2, box[2] / 2
		for _, dx in ipairs({ -w2, w2 }) do
			for _, dy in ipairs({ -h2, h2 }) do
				local px, py = bx + dx, by + dy
				-- The sides: distance into the slice (towards its middle) from each side's line.
				worst = math.min(worst, px * cl - py * sl, py * sr - px * cr, outer - math.sqrt(px * px + py * py))
			end
		end
		-- The inner rim: the box's nearest point to the middle can be on an edge, not a corner.
		local nx = math.max(bx - w2, math.min(0, bx + w2))
		local ny = math.max(by - h2, math.min(0, by + h2))
		worst = math.min(worst, math.sqrt(nx * nx + ny * ny) - inner)
	end
	return worst
end

-- Where a slice's label goes: its middle radius out on the slice's middle (the same for every slice) while it keeps
-- room units from the slice's sides and rims there; else wherever within shift units sideways it has the most room
-- (a wide name on a slanted slice moves out and away from the side its wide line is near). angle and step as for
-- Clearance, boxes too. Returns x, y.
function ns.EmoteWheel_LabelPlace(angle, step, boxes, radius, inner, outer, room, shift)
	local sa, ca = math.sin(angle), math.cos(angle)
	local function At(r, t) -- r out along the middle, t sideways (clockwise)
		return sa * r + ca * t, ca * r - sa * t
	end
	local x, y = At(radius, 0)
	if Clearance(angle, step, x, y, boxes, inner, outer) >= room then
		return x, y
	end
	local best = -math.huge
	for r = inner, outer do
		for t = -shift, shift do
			local px, py = At(r, t)
			local gap = Clearance(angle, step, px, py, boxes, inner, outer)
			if gap > best + 0.01 then
				best, x, y = gap, px, py
			end
		end
	end
	return x, y
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
