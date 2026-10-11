local addonName, ns = ...

-- Bug report, pure part: which Lua errors are Tomte's, error entries from BugGrabber / Blizzard / Tomte's own saved
-- list in one shape, the small saved list for players without BugSack, and the report text. No WoW API except
-- issecretvalue, looked up when called. The game side (reading the error lists, the dialog) is Panel/Bug.lua.

ns.BUG_MAX_SHOWN = 3
ns.BUG_MAX_SAVED = 5
ns.BUG_STACK_LINES = 12
ns.BUG_MAX_MESSAGE = 500

local TOMTE_PATH = "AddOns/Tomte/"
local BLOCKED = "AddOn 'Tomte'" -- BugGrabber's ADDON_ACTION_BLOCKED text (localized, keeps the quoted name)
local TAIL = "%.%.%.([^%s%[%]\"':]+%.lua)" -- a path Lua shortened to "...<end of path>"
local TAIL_MIN = 12 -- shorter tails could be anyone's file
local SECRET_TEXT = "(hidden by the game: secret value)"
local UNREADABLE = "(unreadable)"

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- v when it's a readable string; nil, true when it's a secret.
local function Readable(v)
	if v == nil then
		return nil
	end
	if IsSecret(v) then
		return nil, true
	end
	if type(v) == "string" then
		return v
	end
	return nil
end

-- A shortened path in text whose tail matches the end of one of Tomte's files (files: paths inside the addon folder).
local function OwnTail(text, files)
	for tail in text:gmatch(TAIL) do
		if #tail >= TAIL_MIN then
			for _, file in ipairs(files) do
				local full = "Interface/AddOns/Tomte/" .. file
				if #full >= #tail and full:sub(-#tail) == tail then
					return true
				end
			end
		end
	end
	return false
end

local function Mentions(text, files)
	if type(text) ~= "string" then
		return false
	end
	text = text:gsub("\\", "/")
	return text:find(TOMTE_PATH, 1, true) ~= nil or OwnTail(text, files)
end

-- isTomte, stackOnly (the message points elsewhere but the stack goes through Tomte: a hook, a tooltip).
function ns.Bug_IsTomte(message, stack, files)
	files = files or ns.BUG_FILES or {}
	if Mentions(message, files) or (type(message) == "string" and message:find(BLOCKED, 1, true)) then
		return true, false
	end
	if Mentions(stack, files) then
		return true, true
	end
	return false, false
end

-- One shape for every source. raw: a BugGrabber error (counter, numeric time), a ScriptErrorsFrame entry (count,
-- time as text) or a saved entry (count, numeric time). current: from this session.
function ns.Bug_Normalize(raw, current)
	if type(raw) ~= "table" then
		raw = {}
	end
	local message, secret = Readable(raw.message)
	local count = raw.counter or raw.count
	local entry = {
		message = message or (secret and SECRET_TEXT or UNREADABLE),
		stack = (Readable(raw.stack)),
		locals = (Readable(raw.locals)),
		count = type(count) == "number" and count >= 1 and math.floor(count) or 1,
		current = current == true,
		version = Readable(raw.version),
	}
	if type(raw.time) == "number" then
		entry.time = raw.time
	elseif type(raw.time) == "string" and not IsSecret(raw.time) then
		entry.when = raw.time
	end
	return entry
end

-- Tomte's errors from lists (each normalized, newest first; concatenated in the order given), deduplicated by
-- message (counts added, the first kept), at most max. Returns the list and how many distinct ones there were.
function ns.Bug_Collect(lists, files, max)
	local out, byMessage, total = {}, {}, 0
	for _, list in ipairs(lists) do
		for _, e in ipairs(list) do
			local isTomte, stackOnly = ns.Bug_IsTomte(e.message, e.stack, files)
			if isTomte then
				local seen = byMessage[e.message]
				if seen then
					seen.count = seen.count + e.count
				else
					total = total + 1
					local copy = {}
					for k, v in pairs(e) do
						copy[k] = v
					end
					copy.stackOnly = stackOnly
					byMessage[e.message] = copy
					if #out < max then
						out[#out + 1] = copy
					end
				end
			end
		end
	end
	return out, total
end

function ns.Bug_StackHead(stack, n)
	if type(stack) ~= "string" then
		return nil
	end
	local lines = {}
	for line in (stack .. "\n"):gmatch("([^\n]*)\n") do
		if #lines >= n then
			break
		end
		lines[#lines + 1] = line
	end
	while #lines > 0 and lines[#lines] == "" do
		lines[#lines] = nil
	end
	return table.concat(lines, "\n")
end

-- The saved list (TomteDB.bugs) for players without BugGrabber: newest first, at most max, no locals. errors:
-- newest first. One already saved gets the count added and moves to the front.
function ns.Bug_Remember(buffer, errors, version, now, max)
	for i = #buffer, 1, -1 do
		if type(buffer[i]) ~= "table" or type(buffer[i].message) ~= "string" then
			table.remove(buffer, i)
		end
	end
	for i = #errors, 1, -1 do
		local e = errors[i]
		local message = e.message:sub(1, ns.BUG_MAX_MESSAGE)
		local found
		for j, saved in ipairs(buffer) do
			if saved.message == message then
				found = j
				break
			end
		end
		if found then
			local saved = table.remove(buffer, found)
			saved.count = (type(saved.count) == "number" and saved.count or 1) + e.count
			saved.time = now
			saved.version = version
			table.insert(buffer, 1, saved)
		else
			table.insert(buffer, 1, { message = message, stack = ns.Bug_StackHead(e.stack, ns.BUG_STACK_LINES),
				count = e.count, time = now, version = version })
		end
	end
	for i = #buffer, max + 1, -1 do
		buffer[i] = nil
	end
end

local function Q(v)
	if v == nil then
		return "?"
	end
	return tostring(v)
end

-- "Label (n): a, b" for a list, "Label: (could not read: ...)" for a part that failed.
local function ListLine(label, list, item)
	if type(list) == "string" then
		return label .. ": " .. list
	end
	list = type(list) == "table" and list or {}
	local parts = {}
	for _, v in ipairs(list) do
		parts[#parts + 1] = item and item(v) or tostring(v)
	end
	return ("%s (%d): %s"):format(label, #parts, #parts > 0 and table.concat(parts, ", ") or "none")
end

local function UseText(use)
	local version = use[2]
	if version == false then
		return use[1] .. " not loaded"
	elseif type(version) == "string" and version ~= "" then
		return use[1] .. " " .. version
	end
	return use[1] .. " loaded"
end

-- info (built by Panel/Bug.lua):
--   version, build, interface, locale, theme, preset   Tomte and client versions, the theme and the setup preset
--   level, class, spec, specID, content                 the character, and the expansion whose content Tomte follows
--   on, off                                             module keys (always-on modules left out)
--   blocked                                             { { module key, reason } }
--   uses                                                { { addon, version | true (loaded) | false (not loaded) } }
--   others                                              other loaded addons' names
--   errors, total, catcher                              ns.Bug_Collect's list and count, which error list was read
--   full, profile                                       "full" report: locals and the settings export text
-- Any field may be missing ("?"); a list field may be a "(could not read: ...)" string instead. No names, realms or
-- gold go in here.
function ns.Bug_ReportText(info)
	local lines = { "Tomte bug report" }
	local function add(s)
		lines[#lines + 1] = s
	end
	add(("Tomte %s | WoW %s (%s) | %s | theme %s"):format(Q(info.version), Q(info.build), Q(info.interface),
		Q(info.locale), Q(info.theme)))
	local spec = info.spec and ("%s, spec %s"):format(info.spec, Q(info.specID)) or "no spec"
	add(("Character: level %s %s (%s) | content %s"):format(Q(info.level), Q(info.class), spec, Q(info.content)))
	add("Setup: preset " .. Q(info.preset))
	add(ListLine("Modules on", info.on))
	add(ListLine("Modules off", info.off))
	add(ListLine("Blocked", info.blocked, function(b)
		return ("%s (%s)"):format(Q(b[1]), Q(b[2]))
	end))
	if type(info.uses) == "string" then
		add("Uses: " .. info.uses)
	else
		local uses = {}
		for _, use in ipairs(info.uses or {}) do
			uses[#uses + 1] = UseText(use)
		end
		add("Uses: " .. (#uses > 0 and table.concat(uses, ", ") or "none"))
	end
	add("Error catcher: " .. (info.catcher or "none"))
	add(ListLine("Other addons", info.others))
	add("")

	local errors = info.errors
	if type(errors) == "string" then
		add("Errors from Tomte: " .. errors)
	elseif info.catcher or (type(errors) == "table" and #errors > 0) then
		errors = type(errors) == "table" and errors or {}
		if #errors == 0 then
			add("No Tomte errors caught.")
		else
			add(("Errors from Tomte (newest first, %d of %d):"):format(#errors, math.max(info.total or 0, #errors)))
			for i, e in ipairs(errors) do
				local head = ("%d) x%d"):format(i, e.count or 1)
				if e.when then
					head = head .. ", " .. e.when
				end
				if e.version then
					head = head .. ", Tomte " .. e.version
				end
				if e.stackOnly then
					head = head .. " (Tomte in the stack)"
				end
				add(head)
				add(e.message or UNREADABLE)
				local stack = ns.Bug_StackHead(e.stack, ns.BUG_STACK_LINES)
				if stack and stack ~= "" then
					add(stack)
				end
				if info.full and e.locals and e.locals ~= "" then
					add("Locals:")
					add(e.locals)
				end
				add("")
			end
		end
	else
		add("No error list available. Install BugSack to catch errors.")
	end
	if info.full and info.profile then
		add("")
		add("Settings:")
		add(info.profile)
	end
	return table.concat(lines, "\n")
end
