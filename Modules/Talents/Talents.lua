local addonName, ns = ...

-- Talent check: remembers which saved talent loadout you use per kind of place (open world, dungeon, raid, delve,
-- PvP; a single dungeon, raid or delve can have its own) per character and spec. Entering a place or a ready check
-- on the wrong loadout shows a card with a one-click switch; switching by hand inside a place offers to remember it.
-- Pure rules in Data.lua, the card in Card.lua. Design: docs/superpowers/specs/2026-10-20-tomte-talents-design.md.

local ENTER_DELAY = 4 -- seconds after zoning before the check: talent and instance data settle after the load screen
local OBSERVE_DELAY = 0.5 -- seconds to let Blizzard's talent frame write the new selection after a commit
local SWITCH_TIMEOUT = 20 -- seconds to wait for the "Changing talents" cast to confirm or fail
local SPEC_DELAY = 1 -- seconds after a spec change before checking the new spec
local MAX_ROWS = 30 -- saved-entry rows in settings (5 kinds plus overrides, for up to 4 specs)
-- The Starter Build's pseudo config ID (Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID), as
-- GetLastSelectedSavedConfigID reports it.
local STARTER_FALLBACK = -2

local UI = ns.UI
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local module, db
local visit = 0 -- counts loading screens: a delayed check from an earlier place does nothing
local lastKind -- the kind of place before the last loading screen
local lastSpec -- the specID PLAYER_SPECIALIZATION_CHANGED last saw
local dismissed = {} -- [visit] = true: "Not now" on this visit (a ready check still asks)
local declined = {} -- [placeKey .. "#" .. configID] = true: "No" to remembering, this session
local seen = {} -- { spec, config }: the selection last seen, to tell a hand switch from no change
local pending -- { config, spec, name, timer }: a switch waiting for the cast to finish
local writing = false -- our own UpdateLastSelectedSavedConfigID call (the hook ignores it)

-- A loadout's name as it shows in chat: in the accent color.
local function NameText(name)
	return UI.Wrap(name or "?", "accent")
end

-- Reading the game -------------------------------------------------------------------------------------------------

local function StarterID()
	local consts = Constants.TraitConsts
	return consts and consts.STARTER_BUILD_TRAIT_CONFIG_ID or STARTER_FALLBACK
end

local function CurrentSpec()
	local index = GetSpecialization()
	if not index then
		return nil
	end
	local specID, name = GetSpecializationInfo(index)
	return specID, name
end

-- The class's specs: list of specIDs in the game's order, and [specID] = name.
local function ClassSpecs()
	local order, names = {}, {}
	local _, _, classID = UnitClass("player")
	for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
		local specID, name = GetSpecializationInfo(i)
		if specID then
			order[#order + 1] = specID
			names[specID] = name
		end
	end
	return order, names
end

-- The selected saved loadout, or nil on the Default loadout and the Starter Build.
local function ActiveConfig(specID)
	local id = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
	if id == StarterID() then
		return nil
	end
	return id
end

-- The spec's saved loadouts: { [configID] = true }, how many.
local function SavedLoadouts(specID)
	local valid, count = {}, 0
	for _, id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
		valid[id] = true
		count = count + 1
	end
	return valid, count
end

local function LoadoutName(id)
	local info = id and C_Traits.GetConfigInfo(id)
	return info and info.name or nil
end

local function CurrentPlace()
	local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
	return ns.Talents_Place(instanceType, difficultyID, instanceID, name)
end

local function KeyRunning()
	return C_ChallengeMode.IsChallengeModeActive() and true or false
end

local function CharDB()
	local guid = UnitGUID("player")
	local char = db.chars[guid]
	if not char then
		char = { specs = {} }
		db.chars[guid] = char
	end
	return char
end

-- Everything the rules need (Data.lua's s), for the current spec; nil without a spec. Forgets saved choices whose
-- loadout was deleted, but only when the list of loadouts has loaded (it's empty for a moment at login).
local function State()
	local specID, specName = CurrentSpec()
	if not specID then
		return nil
	end
	local valid, count = SavedLoadouts(specID)
	local spec = ns.Talents_Spec(CharDB(), specID)
	if spec and count > 0 then
		ns.Talents_Prune(spec, valid)
	end
	return {
		specID = specID,
		specName = specName,
		place = CurrentPlace(),
		spec = spec,
		active = ActiveConfig(specID),
		starter = C_ClassTalents.GetStarterBuildActive() and true or false,
		keyRunning = KeyRunning(),
		valid = valid,
		count = count,
		learn = db.learn,
	}
end

-- Switching --------------------------------------------------------------------------------------------------------

local Check -- defined below; a failed switch asks again

-- Blizzard's frame writes the selection after a switch (LoadConfig doesn't), so the talent window's dropdown shows it.
local function WriteSelection(specID, configID)
	writing = true
	C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
	writing = false
	seen.spec, seen.config = specID, configID
end

local function EndPending()
	if pending and pending.timer then
		pending.timer:Cancel()
	end
	pending = nil
end

local function Switched(specID, configID, name)
	WriteSelection(specID, configID)
	ns.TalentsCard_Hide()
	ns.Print(("switched to %s."):format(NameText(name)))
end

-- A button click (a hardware event); out of combat. The result of the cast arrives later (TRAIT_CONFIG_UPDATED or
-- CONFIG_COMMIT_FAILED).
local function Switch(specID, configID)
	if not module.active or pending then
		return
	end
	if InCombatLockdown() then
		ns.Print_Combat("switch talents")
		return
	end
	if CurrentSpec() ~= specID then
		return
	end
	local name = LoadoutName(configID)
	if not name then
		ns.Print("that loadout no longer exists.")
		return
	end
	local result, changeError = C_ClassTalents.LoadConfig(configID, true)
	local results = Enum.LoadConfigResult
	if result == results.NoChangesNecessary then
		Switched(specID, configID, name)
	elseif result == results.LoadInProgress or result == results.Ready then
		pending = { spec = specID, config = configID, name = name }
		pending.timer = C_Timer.NewTimer(SWITCH_TIMEOUT, function()
			if pending and pending.config == configID then
				pending = nil
				ns.Print(UI.Wrap(("the switch to %s didn't finish. Open your talents to check."):format(name),
					"warning"))
			end
		end)
	else
		ns.Print(UI.Wrap(("couldn't switch to %s: %s"):format(name,
			(changeError and changeError ~= "") and changeError or "the game refused."), "danger"))
	end
end

-- Cards ------------------------------------------------------------------------------------------------------------

local function ShowSwitch(s, d)
	local wantName = LoadoutName(d.want)
	if not wantName then
		return
	end
	local thisVisit = visit
	-- Only a saved loadout's name: the last-selected ID can be a deleted loadout or the spec's base config.
	local activeName = s.active and s.valid[s.active] and LoadoutName(s.active) or nil
	ns.TalentsCard_Show({
		text = ns.Talents_WrongText(activeName, wantName, ns.Talents_PlacePhrase(s.place, d.source)),
		buttons = {
			{ text = "Switch to " .. wantName, onClick = function()
				Switch(s.specID, d.want)
			end },
			{ text = "Not now", onClick = function()
				dismissed[thisVisit] = true
			end },
		},
	})
end

-- learned: the module picked it up on its own (nothing was saved for this place), rather than the player's answer.
local function Remembered(s, configID, scope, learned)
	local spec = ns.Talents_Spec(CharDB(), s.specID, true)
	ns.Talents_Remember(spec, s.place, configID, scope)
	local where = (scope == "instance" and s.place.name) or ns.Talents_KindPhrase(s.place.kind)
	local line = learned and "remembered %s for %s (%s)." or "%s for %s from now on (%s)."
	ns.Print(line:format(NameText(LoadoutName(configID)), where, s.specName or "this spec"))
end

local function ShowOffer(s, configID, before)
	local name = LoadoutName(configID)
	if not name then
		return
	end
	local place = s.place
	local key = ns.Talents_PlaceKey(place) .. "#" .. configID
	local buttons
	local function no()
		declined[key] = true
	end
	if place.instanceID and place.name then
		buttons = {
			{ text = "For all " .. ns.Talents_KindPhrase(place.kind), onClick = function()
				Remembered(s, configID, "kind")
			end },
			{ text = "Only " .. place.name, onClick = function()
				Remembered(s, configID, "instance")
			end },
			{ text = "No", onClick = no },
		}
	else
		buttons = {
			{ text = "Yes", onClick = function()
				Remembered(s, configID, "kind")
			end },
			{ text = "No", onClick = no },
		}
	end
	local beforeName = before and LoadoutName(before)
	ns.TalentsCard_Show({
		text = ns.Talents_OfferText(name, place),
		detail = beforeName and ("Until now: " .. beforeName .. ".") or nil,
		buttons = buttons,
	})
end

-- The check --------------------------------------------------------------------------------------------------------

-- trigger: "enter", "leave", "readycheck", "spec" or "command" (verbose: says what it found).
Check = function(trigger)
	local verbose = trigger == "command"
	if not module.active then
		if verbose then
			ns.Print(ns.Module_OffText(module))
		end
		return
	end
	if InCombatLockdown() then
		if verbose then
			ns.Print_Combat("run the talent check")
		end
		return
	end
	if pending then
		return
	end
	local s = State()
	if not s then
		if verbose then
			ns.Print("talent check: you have no specialization yet.")
		end
		return
	end
	seen.spec, seen.config = s.specID, s.active
	local d = ns.Talents_Decide(s)
	if d.action == "learn" then
		Remembered(s, d.want, "kind", true)
	elseif d.action == "switch" then
		if dismissed[visit] and trigger ~= "readycheck" and not verbose then
			return
		end
		ShowSwitch(s, d)
	else
		if verbose then
			ns.Print("talent check: " .. ns.Talents_ReasonText(d.reason))
		end
	end
end

-- After the selection may have changed: a hand switch inside a place offers to remember it.
local function Observe()
	if not module.active or pending then
		return
	end
	local specID = CurrentSpec()
	if not specID then
		return
	end
	local config = ActiveConfig(specID)
	if specID ~= seen.spec then
		seen.spec, seen.config = specID, config
		return
	end
	if config == seen.config then
		return
	end
	seen.config = config
	if InCombatLockdown() then
		return
	end
	local s = State()
	if not s then
		return
	end
	ns.TalentsCard_Hide() -- whatever it asked was about the loadout before
	if not db.offer then
		return
	end
	local ok, before = ns.Talents_ShouldOffer(s, config, declined)
	if ok then
		ShowOffer(s, config, before)
	end
end
local observeSoon = UI.Debounce(OBSERVE_DELAY, Observe)

-- Blizzard's dropdown writes the selection with this call, also for a switch that needs no cast (no trait event then).
-- Can't be unhooked: does nothing while the module is off.
hooksecurefunc(C_ClassTalents, "UpdateLastSelectedSavedConfigID", function()
	if module and module.active and not writing then
		observeSoon()
	end
end)

-- Events -----------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Later(delay, trigger)
	local thisVisit = visit
	C_Timer.After(delay, function()
		if module.active and visit == thisVisit then
			Check(trigger)
		end
	end)
end

function events:PLAYER_ENTERING_WORLD()
	visit = visit + 1
	ns.TalentsCard_Hide()
	local place = CurrentPlace()
	local kind = place and place.kind
	local fromInstance = lastKind ~= nil and lastKind ~= "world"
	lastKind = kind
	if kind and kind ~= "world" and db.check.onEnter then
		Later(ENTER_DELAY, "enter")
	elseif kind == "world" and fromInstance and db.check.afterInstance then
		Later(ENTER_DELAY, "leave")
	end
end

function events:READY_CHECK()
	if db.check.onReadyCheck then
		Check("readycheck")
	end
end

-- The card's buttons do nothing useful in combat (talents can't change), so it goes.
function events:PLAYER_REGEN_DISABLED()
	ns.TalentsCard_Hide()
end

-- Only a real spec change: the event is not documented as talent-only, and a stray one mid-switch would drop the
-- pending switch and the hand-switch tracking.
function events:PLAYER_SPECIALIZATION_CHANGED()
	local specID = CurrentSpec()
	if specID == lastSpec then
		return
	end
	lastSpec = specID
	EndPending()
	ns.TalentsCard_Hide()
	seen.spec, seen.config = nil, nil
	local place = CurrentPlace()
	if place and place.kind ~= "world" then
		Later(SPEC_DELAY, "spec")
	end
end

-- configID: the spec's base config for talents (not the loadout's); profession configs fire it too.
function events:TRAIT_CONFIG_UPDATED(configID)
	if configID ~= C_ClassTalents.GetActiveConfigID() then
		return
	end
	if pending then
		local p = pending
		EndPending()
		if CurrentSpec() == p.spec then
			Switched(p.spec, p.config, p.name)
		end
		return
	end
	observeSoon()
end

function events:CONFIG_COMMIT_FAILED()
	if not pending then
		return
	end
	local name = pending.name
	EndPending()
	ns.Print(UI.Wrap(("the switch to %s didn't finish (interrupted?)."):format(name), "danger"))
	Check("retry")
end

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "READY_CHECK", "PLAYER_REGEN_DISABLED", "TRAIT_CONFIG_UPDATED", "CONFIG_COMMIT_FAILED",
}

local function Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
	local place = CurrentPlace()
	lastKind = place and place.kind
	local specID = CurrentSpec()
	lastSpec = specID
	seen.spec, seen.config = specID, specID and ActiveConfig(specID)
end

local function Stop()
	events:UnregisterAllEvents()
	EndPending()
	visit = visit + 1 -- drops delayed checks
	ns.TalentsCard_Hide()
end

-- Commands ---------------------------------------------------------------------------------------------------------

local function LoadoutLabel(id)
	return LoadoutName(id) or "a deleted loadout"
end

local function SavedLines()
	local order, names = ClassSpecs()
	local lines = {}
	for _, entry in ipairs(ns.Talents_Entries(CharDB(), order)) do
		lines[#lines + 1] = ns.Talents_EntryText(entry, names[entry.specID] or ("Spec " .. entry.specID),
			LoadoutLabel(entry.config))
	end
	return lines
end

local function List()
	local lines = SavedLines()
	if #lines == 0 then
		ns.Print("talent check: nothing saved for this character yet.")
		return
	end
	ns.Print("talent check, saved for this character:")
	for _, line in ipairs(lines) do
		ns.Print("  " .. line)
	end
end

local function Why()
	local s = State()
	if not s then
		ns.Print("talent check: you have no specialization yet.")
		return
	end
	local place = s.place
	if place then
		ns.Print(("place: %s%s"):format(ns.Talents_KindLabel(place.kind),
			place.instanceID and (" - " .. (place.name or "?") .. " (instance " .. place.instanceID .. ")") or ""))
	else
		ns.Print("place: none Talent check knows")
	end
	local on = s.starter and "the Starter Build" or (s.active and (LoadoutLabel(s.active) .. " (" .. s.active .. ")"))
		or "no saved loadout (Default loadout)"
	ns.Print(("spec: %s, on %s"):format(s.specName or s.specID, on))
	local names = {}
	for id in pairs(s.valid) do
		names[#names + 1] = LoadoutLabel(id)
	end
	table.sort(names)
	ns.Print("saved loadouts: " .. (#names > 0 and table.concat(names, ", ") or "none"))
	if place and s.spec then
		local kindID = s.spec.kinds[place.kind]
		local override = place.instanceID and s.spec.instances[place.instanceID]
		ns.Print(("for %s: %s"):format(ns.Talents_KindPhrase(place.kind), kindID and LoadoutLabel(kindID) or "nothing"))
		if override then
			ns.Print(("for %s only: %s"):format(place.name or "this instance", LoadoutLabel(override.config)))
		end
	end
	local d = ns.Talents_Decide(s)
	ns.Print("decision: " .. ns.Talents_ReasonText(d.reason))
end

-- Settings rows ----------------------------------------------------------------------------------------------------

local function Entries()
	if not (db and UnitGUID("player")) then
		return {}
	end
	return ns.Talents_Entries(CharDB(), (ClassSpecs()))
end

local savedRows = {}
for i = 1, MAX_ROWS do
	savedRows[i] = { type = "button", text = "Forget",
		label = function()
			local entry = Entries()[i]
			if not entry then
				return ""
			end
			local _, names = ClassSpecs()
			return ns.Talents_EntryText(entry, names[entry.specID] or ("Spec " .. entry.specID), LoadoutLabel(entry.config))
		end,
		shown = function()
			return Entries()[i] ~= nil
		end,
		onClick = function()
			local entry = Entries()[i]
			if entry then
				ns.Talents_Forget(CharDB(), entry)
			end
		end,
	}
end

-- Settings preview (Panel/Preview.lua): the card that offers to remember a hand switch, drawn in Card.lua.
local function OfferPreview(host)
	return ns.TalentsCard_DrawSample(host, {
		text = ns.Talents_OfferText("Mythic+", { kind = "dungeon" }),
		detail = "Until now: Raid.",
		buttons = { { text = "Yes" }, { text = "No" } },
	})
end

local options = {
	{ type = "header", label = "Checks" },
	{ type = "checkbox", key = "check.onEnter", label = "When entering an instance",
		tooltip = "A few seconds after entering a dungeon, raid, delve, battleground or arena." },
	{ type = "checkbox", key = "check.onReadyCheck", label = "On ready checks" },
	{ type = "checkbox", key = "check.afterInstance", label = "Back in the open world",
		tooltip = "After leaving an instance, check the loadout saved for the open world." },
	{ type = "button", label = "Check now", text = "Run", onClick = function()
		Check("command")
	end },

	{ type = "header", label = "Learning" },
	{ type = "checkbox", key = "learn", label = "Learn on its own",
		tooltip = "The first time you're somewhere with nothing saved, remember the loadout you're on for that kind of place." },
	{ type = "checkbox", key = "offer", label = "Offer to remember a switch",
		preview = ns.Preview_When("offer", OfferPreview),
		tooltip = "When you change loadout by hand inside a place, ask whether to use it there from now on." },

	{ type = "header", label = "Saved loadouts" },
	{ type = "status", label = "Nothing saved yet", status = function()
		return "", "textMuted"
	end, shown = function()
		return Entries()[1] == nil
	end },
}
for _, row in ipairs(savedRows) do
	options[#options + 1] = row
end
options[#options + 1] = { type = "button", label = "Everything for this character", text = "Forget all",
	confirm = "Forget every loadout Talent check saved for this character?",
	shown = function()
		return Entries()[1] ~= nil
	end,
	onClick = function()
		CharDB().specs = {}
	end }
options[#options + 1] = { type = "button", label = "Card position", text = "Reset", onClick = function()
	ns.TalentsCard_ResetPosition()
end, tooltip = "Move the card back to the top of the screen. Blizzard's Edit Mode moves it too." }

module = ns.RegisterModule({
	key = "talents",
	name = "Talent check",
	category = "class",
	icon = 633139, -- inv_inscription_tomeoftheclearmind
	summary = "Remembers your talent loadout per kind of place and offers a one-click switch.",
	description = "Remembers which saved talent loadout you use in the open world, dungeons, raids, delves and PvP (or in one particular dungeon). When you arrive somewhere, or at a ready check, on the wrong loadout, a card offers to switch with one click. Switch by hand inside a place and it asks whether to remember that.",
	enabledByDefault = true,
	defaults = {
		check = { onEnter = true, onReadyCheck = true, afterInstance = true },
		learn = true,
		offer = true,
		card = { point = "TOP", relPoint = "TOP", x = 0, y = -180 }, -- TalentsCard_ResetPosition repeats it
		-- [player GUID] = { specs = { [specID] = { kinds = { [kind] = configID },
		--   instances = { [instanceID] = { config = configID, name = instance name } } } } }
		chars = {},
	},
	init = function(moduleDB)
		db = moduleDB
		ns.TalentsCard_Init(moduleDB, module)
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "why", "explain what Talent check decides here and why", Why },
		{ "list", "list the loadouts saved for this character", List },
		{ "check", "run the talent check now", function()
			Check("command")
		end },
	},
	options = options,
})
