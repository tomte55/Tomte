local addonName, ns = ...

-- Recent: pure logic for the feed of toasts and banners (unit-tested with plain Lua). Entries are plain tables that
-- go straight into SavedVariables: { at, guid, char, class, owner, label, title, text, icon, iconAtlas, accent,
-- count, mergeKey, banner }. Click actions live outside them (Recent.lua), so a saved entry never holds a function.

local HIDDEN = "(hidden: it came in during combat)"

-- A spec field that's safe to keep: a plain string, nil for a secret value or anything else.
local function Plain(value, isSecret)
	if value == nil or isSecret(value) or type(value) ~= "string" then
		return nil
	end
	return value
end

-- Battle.net name tokens (|K...|k) only resolve in the session they came from: saved, they'd show as garbage.
local function NoTokens(value)
	if not value then
		return nil
	end
	local stripped = value:gsub("|K.-|k", "")
	return stripped
end

-- A feed entry from a toast or banner spec. who = { guid, char, class }. isSecret(value) -> bool.
-- spec.recentTitle, when given, is saved instead of spec.title (a saveable name for a |K account name).
function ns.Recent_FromSpec(spec, who, now, isSecret, banner)
	local title = NoTokens(Plain(spec.recentTitle, isSecret)) or NoTokens(Plain(spec.title, isSecret))
	local text = NoTokens(Plain(banner and spec.subtitle or spec.text, isSecret))
	if title == "" then
		title = Plain(spec.label, isSecret) or "Message"
	end
	if (spec.title ~= nil and not title) or (not banner and spec.text ~= nil and not text) then
		title = title or spec.label or "Message"
		text = HIDDEN
	end
	local accent = spec.accent
	return {
		at = now, guid = who.guid, char = who.char, class = who.class,
		owner = spec.owner or "other", label = Plain(spec.label, isSecret), title = title, text = text,
		icon = type(spec.icon) ~= "table" and spec.icon or nil, iconAtlas = spec.iconAtlas,
		-- A theme role is kept by name; a color (game meaning) is copied.
		accent = type(accent) == "string" and accent
			or (accent and { accent[1] or accent.r, accent[2] or accent.g, accent[3] or accent.b }) or nil,
		count = 1, mergeKey = (not text or text ~= HIDDEN) and spec.mergeKey or nil, banner = banner or nil,
	}
end

-- Adds entry to the front of list (newest first). An entry with the same mergeKey and character that's still among
-- the newest `mergeWindow` entries is replaced (count goes up, it moves to the front). Caps the list at max.
-- Returns the entry that's now at the front.
function ns.Recent_Add(list, entry, max, mergeWindow)
	if entry.mergeKey then
		for i = 1, math.min(#list, mergeWindow or 10) do
			local old = list[i]
			if old.mergeKey == entry.mergeKey and old.guid == entry.guid then
				table.remove(list, i)
				entry.count = (old.count or 1) + 1
				break
			end
		end
	end
	table.insert(list, 1, entry)
	ns.Recent_Trim(list, max)
	return entry
end

-- Drops the oldest entries past max (default 50).
function ns.Recent_Trim(list, max)
	for i = #list, (max or 50) + 1, -1 do
		list[i] = nil
	end
end

-- The entries to show: all of them, or one character's (scope "char"), and only owners that are included.
function ns.Recent_Visible(list, scope, guid, include)
	local out = {}
	for _, e in ipairs(list) do
		if (scope ~= "char" or e.guid == guid) and (include[e.owner] ~= false) and not (e.banner and include.banners == false) then
			out[#out + 1] = e
		end
	end
	return out
end

-- How many of the visible entries came after `seenAt`.
function ns.Recent_Unseen(visible, seenAt)
	local n = 0
	for _, e in ipairs(visible) do
		if e.at > (seenAt or 0) then
			n = n + 1
		end
	end
	return n
end

-- "now", "5m", "2h", "3d" (Core/Format.lua).
ns.Recent_Ago = ns.Ago

-- Group label for a row: "Today" when it's from the same calendar day as now (dayOf(t) gives a day number), else
-- "Earlier".
function ns.Recent_Group(at, now, dayOf)
	return dayOf(at) == dayOf(now) and "Today" or "Earlier"
end

-- The Include checkboxes: every module that shows toasts or banners declares module.toasts (true: its name is the
-- label; a string: that label). In registration order: { { key, label } }.
function ns.Recent_Owners(modules)
	local list = {}
	for _, module in ipairs(modules) do
		if module.toasts then
			list[#list + 1] = { key = module.key,
				label = type(module.toasts) == "string" and module.toasts or module.name }
		end
	end
	return list
end
