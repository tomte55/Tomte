local addonName, ns = ...

-- Hidden settings: pure logic (no WoW API calls; unit-tested in tests/test_hidden.lua). The list of the game's hidden
-- settings (CVars with no place in Blizzard's own Settings panel on that client), and the rules for putting the
-- player's choices on and the game's values back. Registered in Hidden.lua.

-- One entry per setting, in page order. cvar: the game's name; kind: "switch" (on is "1") or "slider" (min, max,
-- step, format); invert: on means the CVar is "0"; client: "retail" or "forever" when only that client hides it
-- (the CVar is also checked to exist at run time). Sources: each CVar's own help text in the client, and
-- Blizzard_SettingsDefinitions_* on the live and forever branches of github.com/Gethe/wow-ui-source for what the
-- Settings panel already shows.
ns.HIDDEN_SETTINGS = {
	{ group = "Camera and screen" },
	{ cvar = "cameraDistanceMaxZoomFactor", kind = "slider", min = 1, max = 2.6, step = 0.1, client = "retail",
		label = "Camera zoom distance", format = "%.1fx",
		tooltip = "How far out the camera can zoom, times the usual limit." },
	{ cvar = "ffxDeath", kind = "switch", label = "Gray world while dead",
		tooltip = "The screen loses its color while you're a ghost." },
	{ cvar = "ffxGlow", kind = "switch", label = "Full-screen glow",
		tooltip = "A soft glow over the whole picture. Off looks a little sharper." },
	{ cvar = "screenshotQuality", kind = "slider", min = 1, max = 10, step = 1, label = "Screenshot quality",
		tooltip = "For JPG screenshots: 10 is the sharpest, and the largest file." },

	{ group = "Map" },
	{ cvar = "mapFade", kind = "switch", label = "Fade the world map while moving",
		tooltip = "The open map turns see-through while you walk." },
	{ cvar = "showDungeonEntrancesOnMap", kind = "switch", label = "Dungeon entrances on the map",
		tooltip = "Mark dungeon entrances on the world map." },
	{ cvar = "minimapTrackingShowAll", kind = "switch", label = "Every tracking type in the minimap menu",
		tooltip = "The minimap's tracking menu lists every kind of thing it can track." },

	{ group = "Tooltips" },
	{ cvar = "UberTooltips", kind = "switch", label = "Detailed tooltips",
		tooltip = "Spell and button tooltips with their full text. Off shows less." },
	{ cvar = "alwaysCompareItems", kind = "switch", label = "Always compare items",
		tooltip = "An item's tooltip shows what you're wearing beside it without holding Shift." },
	{ cvar = "dontShowEquipmentSetsOnItems", kind = "switch", invert = true, label = "Equipment sets in item tooltips",
		tooltip = "Item tooltips say which of your equipment sets the item is in." },
	{ cvar = "deemphasizeOffspecPrimaryStats", kind = "switch", client = "forever",
		label = "Gray out stats your spec doesn't use",
		tooltip = "Item tooltips gray out or hide main stats your spec has no use for." },
	{ cvar = "tooltipPointsShowMinAndMax", kind = "switch", client = "forever", label = "Spell numbers as a range",
		tooltip = "Spell tooltips show \"120 to 140\" instead of the average." },

	{ group = "Chat" },
	{ cvar = "colorChatNamesByClass", kind = "switch", label = "Class-colored names in chat",
		tooltip = "The names of players talking in chat take their class color." },
	{ cvar = "chatMouseScroll", kind = "switch", label = "Scroll chat with the mouse wheel" },
	{ cvar = "breakUpLargeNumbers", kind = "switch", label = "Commas in large numbers",
		tooltip = "The game writes 1,234,567 instead of 1234567." },
	{ cvar = "showLootSpam", kind = "switch", client = "forever", label = "Every loot roll in chat",
		tooltip = "Each player's roll on group loot, not only who won." },

	{ group = "Controls" },
	{ cvar = "ActionButtonUseKeyDown", kind = "switch", label = "Cast when the key goes down",
		tooltip = "Abilities on your bars go off when you press the key, not when you let go." },
	{ cvar = "SpellQueueWindow", kind = "slider", min = 0, max = 400, step = 10, format = "%d ms",
		label = "Spell queue window",
		tooltip = "How early you can press your next ability while the current one is still going." },
	{ cvar = "autoUnshift", kind = "switch", label = "Leave a form when needed",
		tooltip = "Using something you can't use in a shapeshift form takes you out of it." },
	{ cvar = "autoStand", kind = "switch", label = "Stand up when needed",
		tooltip = "Casting while you sit stands you up." },

	{ group = "Quests" },
	{ cvar = "autoQuestWatch", kind = "switch", label = "Track quests you pick up",
		tooltip = "New quests go straight to the objective tracker." },
	{ cvar = "showQuestLevel", kind = "switch", client = "forever", label = "Quest levels",
		tooltip = "Show each quest's level in the quest log and quest text." },
	{ cvar = "canUseQuestItemWithLeftClick", kind = "switch", client = "forever",
		label = "Use quest items by clicking the creature",
		tooltip = "Left-click a creature a quest item is meant for to use the item on it." },
	{ cvar = "showTaxiNodeLearnedIcon", kind = "switch", client = "forever", label = "Mark flight masters you know",
		tooltip = "An icon over a flight master's head once you've learned that flight point." },

	{ group = "Interface" },
	{ cvar = "scriptErrors", kind = "switch", label = "Show Lua errors",
		tooltip = "The game's own error window when an addon breaks. An error catcher like BugSack works without it." },
	{ cvar = "showKeyring", kind = "switch", client = "forever", label = "Keyring button",
		tooltip = "The keyring button beside your bags." },
	{ cvar = "targetHighlightAlwaysShown", kind = "switch", client = "forever", label = "Always highlight your target",
		tooltip = "Your target gets its highlight even with outlines turned off." },
}

-- Whether two CVar values mean the same: the game hands back numbers in its own format ("1.000000" for "1").
function ns.Hidden_Same(a, b)
	if a == nil or b == nil then
		return a == b
	end
	local na, nb = tonumber(a), tonumber(b)
	if na and nb then
		return math.abs(na - nb) < 1e-6
	end
	return tostring(a) == tostring(b)
end
local Same = ns.Hidden_Same

-- Whether entry belongs on this client's page. exists(cvar): the client has that CVar.
function ns.Hidden_Available(entry, isForever, exists)
	if not entry.cvar then
		return false
	end
	if entry.client and entry.client ~= (isForever and "forever" or "retail") then
		return false
	end
	return exists(entry.cvar) and true or false
end

-- A switch's CVar text for on/off.
function ns.Hidden_SwitchValue(entry, on)
	if entry.invert then
		on = not on
	end
	return on and "1" or "0"
end

-- Whether a switch shows as on for the CVar's text value.
function ns.Hidden_SwitchOn(entry, value)
	local on = value ~= nil and not Same(value, 0) and value ~= ""
	if entry.invert then
		return not on
	end
	return on
end

-- A slider value as the text Tomte writes: whole numbers without decimals, others rounded to the step.
function ns.Hidden_SliderValue(entry, value)
	local step = entry.step or 1
	value = math.floor(value / step + 0.5) * step
	value = math.max(entry.min, math.min(entry.max, value))
	if step >= 1 then
		return tostring(math.floor(value + 0.5))
	end
	return (("%.2f"):format(value):gsub("0+$", ""):gsub("%.$", ""))
end

-- What turning on does, given the saved state and current = { [cvar] = value now }. state: set = { [cvar] = value
-- the player chose here }, saved = { [cvar] = the value before Tomte first wrote it }, applied = { [cvar] = what it
-- read back as after Tomte wrote it }. A CVar no longer at what Tomte left it was changed by someone else (the game's
-- Settings, another addon, /console): theirs wins, so Tomte forgets that choice. Returns writes = { { cvar, value } }
-- in name order and adopted = { cvar names }; the state is updated in place.
function ns.Hidden_StartPlan(state, current)
	local writes, adopted = {}, {}
	local names = {}
	for cvar in pairs(state.set) do
		names[#names + 1] = cvar
	end
	table.sort(names)
	for _, cvar in ipairs(names) do
		local now = current[cvar]
		if now == nil then
			-- Not on this client: keep the choice for the other one.
		elseif state.applied[cvar] ~= nil and not Same(now, state.applied[cvar]) then
			state.set[cvar], state.saved[cvar], state.applied[cvar] = nil, nil, nil
			adopted[#adopted + 1] = cvar
		elseif not Same(now, state.set[cvar]) then
			if state.saved[cvar] == nil then
				state.saved[cvar] = now
			end
			writes[#writes + 1] = { cvar = cvar, value = state.set[cvar] }
		end
	end
	return writes, adopted
end

-- What turning off does: every CVar Tomte changed goes back to its saved value, unless someone else changed it since
-- (theirs stays). Choices stay in state.set, so turning on again puts them back. Returns writes; clears saved and
-- applied for the CVars it handled.
function ns.Hidden_StopPlan(state, current)
	local writes = {}
	local names = {}
	for cvar in pairs(state.saved) do
		names[#names + 1] = cvar
	end
	table.sort(names)
	for _, cvar in ipairs(names) do
		local now = current[cvar]
		if now ~= nil then
			local ours = state.applied[cvar] == nil or Same(now, state.applied[cvar])
			if ours and not Same(now, state.saved[cvar]) then
				writes[#writes + 1] = { cvar = cvar, value = state.saved[cvar] }
			end
			state.saved[cvar], state.applied[cvar] = nil, nil
		end
	end
	return writes
end

-- The player picked value for cvar on the page (now: its value before this change). Records the value to put back
-- the first time, and forgets the choice when it goes back to that value. Returns whether to write the CVar.
function ns.Hidden_Choose(state, cvar, value, now)
	if state.saved[cvar] == nil then
		if Same(now, value) then
			return false
		end
		state.saved[cvar] = now
	end
	if Same(value, state.saved[cvar]) then
		state.set[cvar], state.saved[cvar], state.applied[cvar] = nil, nil, nil
	else
		state.set[cvar] = value
	end
	return not Same(now, value)
end

-- The report of CVars that differ from the game's defaults: a "-- heading" line per group, then
-- "name: now value, game default default". rows = { { name, value, default, category } }; headingOf(category) ->
-- text. Groups and names in alphabetical order. Returns the text and how many rows differ.
function ns.Hidden_DiffText(rows, headingOf)
	local differing = {}
	for _, r in ipairs(rows) do
		if r.default ~= nil and r.value ~= nil and not Same(r.value, r.default) then
			differing[#differing + 1] = r
		end
	end
	table.sort(differing, function(a, b)
		local ha, hb = headingOf(a.category), headingOf(b.category)
		if ha ~= hb then
			return ha < hb
		end
		return a.name:lower() < b.name:lower()
	end)
	local lines, last = {}, nil
	for _, r in ipairs(differing) do
		local heading = headingOf(r.category)
		if heading ~= last then
			if last then
				lines[#lines + 1] = ""
			end
			lines[#lines + 1] = "-- " .. heading
			last = heading
		end
		local default = r.default == "" and '""' or r.default
		lines[#lines + 1] = ("%s: now %s, game default %s"):format(r.name, r.value == "" and '""' or r.value, default)
	end
	return table.concat(lines, "\n"), #differing
end
