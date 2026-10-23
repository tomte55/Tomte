local addonName, ns = ...

-- Quests: pure logic (no WoW API calls; unit-tested in tests/test_quests.lua). Which quests to accept and turn in,
-- which reward to take, which gossip option to pick, which cinematics to skip, what a Talking Head line becomes,
-- and the skyriding race medals read from the "Race Times" aura. The game is read in Read.lua, acted on in
-- Automation.lua, Cinematics.lua, TalkingHead.lua and Medals.lua; registered in Quests.lua.

-- Enum.QuestFrequency: 0 Default, 1 Daily, 2 Weekly, 3 ResetByScheduler (checked in QuestLogDocumentation.lua).
local FREQUENCY_NAMES = { [1] = "daily", [2] = "weekly", [3] = "repeatable" }
-- Enum.GossipOptionRecFlags.QuestLabelPrepend: the option is a step of a quest ("(Quest) ..." in its label).
local FLAG_QUEST_STEP = 1
local FLAG_PLAY_MOVIE = 4 -- PlayMovieLabelPrepend: picking it plays a movie
-- Gossip icons of plain talk: gossipgossipicon and chatbubblegossipicon. Services (vendor, taxi, trainer, bank)
-- have their own icons.
local CHAT_ICONS = { [132053] = true, [1019848] = true }
-- Enum.GossipOptionStatus.Available. Unavailable, locked and already-complete options are never picked.
local STATUS_AVAILABLE = 0
-- The title line of each course in the "Race Times" aura tooltip starts with this color (lower case).
local RACE_TITLE_COLOR = "|cffffd100" -- theme: matched in Blizzard's text, never shown

ns.QUESTS_SKIP_KEYS = { "shift", "ctrl", "alt" }

-- Skip key ----------------------------------------------------------------------------------------------------

-- True when the chosen skip key ("shift", "ctrl", "alt") is held.
function ns.Quests_SkipKeyDown(setting, shift, ctrl, alt)
	if setting == "ctrl" then
		return ctrl and true or false
	elseif setting == "alt" then
		return alt and true or false
	end
	return shift and true or false
end

-- The creature or object ID in a GUID ("Creature-0-1-2-3-<id>-<spawn>"), nil for players and anything else.
function ns.Quests_NpcID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then
		return tonumber(id)
	end
	return nil
end

-- Quest filters -----------------------------------------------------------------------------------------------

-- "daily", "weekly", "repeatable" or nil. info: { frequency, repeatable }.
function ns.Quests_RepeatKind(info)
	local kind = FREQUENCY_NAMES[info.frequency or 0]
	if kind then
		return kind
	end
	return info.repeatable and "repeatable" or nil
end

-- Whether to accept an offered quest, and why not.
-- info: { frequency, repeatable, trivial, doneElsewhere, pvp, fromItem }
-- rules: { skipRepeatable, skipTrivial, skipDoneElsewhere }
function ns.Quests_ShouldAccept(info, rules)
	if info.pvp then
		return false, "a PvP quest (the game asks first)"
	end
	if info.fromItem then
		return false, "offered by an item (the game shows it in the quest tracker)"
	end
	local kind = ns.Quests_RepeatKind(info)
	if rules.skipRepeatable and kind then
		return false, "a " .. kind .. " quest"
	end
	if rules.skipTrivial and info.trivial then
		return false, "a low-level (grey) quest"
	end
	if rules.skipDoneElsewhere and info.doneElsewhere then
		return false, "already done on another character"
	end
	return true
end

-- Whether to hand in a quest at its progress or reward step, and why not.
-- info: { completable, money (copper the turn-in costs), currencies (how many currencies it costs), frequency,
-- repeatable }; completable is only checked when it isn't nil (the reward step has no such question).
-- rules: { skipRepeatable, skipCosts }
function ns.Quests_ShouldTurnIn(info, rules)
	if info.completable == false then
		return false, "not finished yet"
	end
	local kind = ns.Quests_RepeatKind(info)
	if rules.skipRepeatable and kind then
		return false, "a " .. kind .. " quest"
	end
	if rules.skipCosts and (info.money or 0) > 0 then
		return false, "the turn-in costs gold"
	end
	if rules.skipCosts and (info.currencies or 0) > 0 then
		return false, "the turn-in costs a currency"
	end
	return true
end

-- The reward index to take: 0 when there's nothing to choose, 1 when there's one, Gear Check's pick when the player
-- asked for that and Gear Check is sure, else nil (leave the window to the player).
function ns.Quests_RewardChoice(numChoices, bestChoice, pickForMe)
	numChoices = numChoices or 0
	if numChoices <= 0 then
		return 0
	end
	if numChoices == 1 then
		return 1
	end
	if pickForMe and type(bestChoice) == "number" and bestChoice >= 1 and bestChoice <= numChoices then
		return bestChoice
	end
	return nil
end

-- Which quest to open from an NPC's list: a finished one first, then one that may be accepted. Quests already
-- tried in this conversation are passed over, so a quest the player backed out of isn't opened again.
-- active: { { questID, title, complete, frequency, repeatable } }, available: { { questID, title, frequency,
-- repeatable, trivial, doneElsewhere } }, tried: { [questID] = true }, rules: the accept and turn-in rules.
-- Returns "active" or "available", the list entry, and the reasons quests were passed over ({ text }).
function ns.Quests_PickQuest(active, available, tried, rules)
	local passed = {}
	for _, q in ipairs(active or {}) do
		if q.complete and not tried[q.questID] then
			local kind = rules.skipRepeatable and ns.Quests_RepeatKind(q)
			if kind then
				passed[#passed + 1] = ("%s: a %s quest"):format(q.title or q.questID, kind)
			else
				return "active", q, passed
			end
		end
	end
	for _, q in ipairs(available or {}) do
		if not tried[q.questID] then
			local ok, why = ns.Quests_ShouldAccept(q, rules)
			if ok then
				return "available", q, passed
			end
			passed[#passed + 1] = ("%s: %s"):format(q.title or q.questID, why)
		end
	end
	return nil, nil, passed
end

-- Gossip ------------------------------------------------------------------------------------------------------

local function HasFlag(flags, flag)
	return type(flags) == "number" and math.floor(flags / flag) % 2 == 1
end

-- The key a gossip option is remembered by in one conversation.
function ns.Quests_GossipKey(option)
	return option.gossipOptionID
end

-- Whether a sole option is plain talk ("Tell me more"), not a service (vendor, taxi, trainer), a spell, a movie or
-- a step that pulls a fight.
local function PlainChat(o)
	local icon = o.overrideIconID or o.icon
	return CHAT_ICONS[icon] == true and not o.spellID and not HasFlag(o.flags, FLAG_PLAY_MOVIE)
end

-- Which gossip option to pick, by its index in options (sorted as the game shows them), why, and which rule
-- picked it ("event", "step" or "only").
-- options: { { gossipOptionID, flags, status, selectOptionWhenOnlyOption, icon, overrideIconID, spellID } };
-- eventIDs: { [gossipOptionID] = name } (event sign-ups); already: { [key] = true } options picked earlier in
-- this conversation; rules: { questStep, only, events, hasQuests, forceGossip (C_GossipInfo.ForceGossip()),
-- inInstance, onlyPicked (the only-option rule already fired in this conversation) } (nil: all on, no quests).
-- Options without an ID are never picked: picking by position could hit a different option if the list changes
-- under us.
function ns.Quests_GossipPick(options, eventIDs, already, rules)
	rules = rules or { questStep = true, only = true, events = true }
	already = already or {}
	local function usable(o)
		return o.gossipOptionID and o.status == STATUS_AVAILABLE and not already[o.gossipOptionID]
	end
	if rules.events and eventIDs then
		for i, o in ipairs(options) do
			if usable(o) and eventIDs[o.gossipOptionID] then
				return i, "event: " .. tostring(eventIDs[o.gossipOptionID]), "event"
			end
		end
	end
	if rules.questStep then
		local found, count = nil, 0
		for i, o in ipairs(options) do
			if HasFlag(o.flags, FLAG_QUEST_STEP) then
				count = count + 1
				found = usable(o) and i or found
			end
		end
		if count == 1 and found then
			return found, "the quest step", "step"
		end
	end
	if not (rules.only and #options == 1 and not rules.hasQuests and usable(options[1])) then
		return nil
	end
	local o = options[1]
	if o.selectOptionWhenOnlyOption then
		return nil, "the game picks this one itself"
	end
	if rules.onlyPicked then
		return nil, "an only option was already picked in this conversation"
	end
	if rules.forceGossip then
		return nil, "the game wants this one read"
	end
	if rules.inInstance then
		return nil, "only options aren't picked in instances"
	end
	if not PlainChat(o) then
		return nil, "the only option isn't plain talk"
	end
	return 1, "the only option", "only"
end

-- Cinematics --------------------------------------------------------------------------------------------------

-- Whether to skip a movie ("movie", with its ID) or an in-engine cutscene ("cinematic", no ID).
-- policy: "off", "seen" or "all"; seen: { [movieID] = true }; alsoInEngine: skip cutscenes under "seen".
function ns.Quests_SkipCinematic(policy, kind, movieID, seen, alsoInEngine)
	if policy == "all" then
		return true
	end
	if policy ~= "seen" then
		return false
	end
	if kind == "movie" then
		return movieID ~= nil and seen ~= nil and seen[movieID] == true
	end
	return alsoInEngine and true or false
end

-- Talking Head ------------------------------------------------------------------------------------------------

-- What a Talking Head line becomes: "blizzard" (Blizzard's frame), "text" (Tomte's subtitle) or "hide" (only the
-- voice, and the chat line). mode: "off", "hide" or "text"; ctx: { inInstance, worldQuest };
-- rules: { hideInInstance, hideWorldQuest }.
function ns.Quests_TalkingHeadAction(mode, ctx, rules)
	if mode == "hide" then
		return "hide"
	end
	if mode ~= "text" then
		return "blizzard"
	end
	if rules.hideInInstance and ctx.inInstance then
		return "hide"
	end
	if rules.hideWorldQuest and ctx.worldQuest then
		return "hide"
	end
	return "text"
end

-- Quest items -------------------------------------------------------------------------------------------------

-- The state line for the quest an item starts, and its color role.
-- s: { onQuest, ready, done, doneOnAccount }
function ns.Quests_ItemQuestState(s)
	if s.onQuest then
		if s.ready then
			return "In your quest log, ready to hand in", "success"
		end
		return "In your quest log", "info"
	end
	if s.done then
		return "Already done", "textMuted"
	end
	if s.doneOnAccount then
		return "Not done here, done on another character", "info"
	end
	return "Not started", "warning"
end

-- Race medals -------------------------------------------------------------------------------------------------

-- The medal per course from the "Race Times" aura tooltip's text lines: each course is a title line (in the
-- tooltip's gold) followed by your record, which carries a medal atlas when you've earned one. Returns
-- { atlas or false } and { course title } in course order.
function ns.Quests_RaceMedals(lines)
	local medals, titles = {}, {}
	local i = 1
	while i <= #lines do
		local line = lines[i]
		if type(line) == "string" and line:lower():find(RACE_TITLE_COLOR, 1, true) then
			local record = lines[i + 1]
			local atlas = type(record) == "string" and record:match("|A:([^:|]*medal%-small%-%a+)")
			medals[#medals + 1] = atlas or false
			titles[#titles + 1] = line:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
			i = i + 1
		end
		i = i + 1
	end
	return medals, titles
end

-- Which medal goes on which gossip option: { [option index] = atlas }. A course's option is the one whose name
-- holds the course title (or the other way round), so options that aren't courses get nothing. When no name
-- matches at all and every option is a course, they go by order, the way the timekeeper lists them.
-- options: { { name } } in the order shown.
function ns.Quests_RaceMedalOptions(medals, titles, options)
	local marks, matched, used, done = {}, 0, {}, {}
	local names = {}
	for i, o in ipairs(options) do
		names[i] = type(o.name) == "string" and o.name ~= "" and o.name:lower() or nil
	end
	local function match(c, i)
		used[i], done[c] = true, true
		matched = matched + 1
		marks[i] = medals[c] or nil
	end
	-- Exact names first ("Course" isn't "Reverse Course"), then the closest name that holds the title.
	for c, title in ipairs(titles) do
		for i in ipairs(options) do
			if not used[i] and names[i] == title:lower() then
				match(c, i)
				break
			end
		end
	end
	for c, title in ipairs(titles) do
		local lower, best = title:lower(), nil
		for i in ipairs(options) do
			local name = names[i]
			if not done[c] and not used[i] and name and lower ~= ""
				and (name:find(lower, 1, true) or lower:find(name, 1, true))
				and (not best or #name < #names[best]) then
				best = i
			end
		end
		if best then
			match(c, best)
		end
	end
	if matched == 0 and #medals > 0 and #medals == #options then
		for i, atlas in ipairs(medals) do
			marks[i] = atlas or nil
		end
	end
	return marks
end
