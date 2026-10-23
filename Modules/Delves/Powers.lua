local addonName, ns = ...

-- Delves: auto-pick delve powers (off by default). When a player choice opens inside a delve and every option is a
-- power (a spell with one plain button), the only option, or the one first on the "Preferred powers" list, is picked.
-- C_PlayerChoice.SendPlayerChoiceResponse needs no hardware event (warcraft.wiki.gg and Blizzard's
-- PlayerChoiceDocumentation, checked 2026-10-23: only its argument must not be secret), so no key press is needed.
-- Rules in Data.lua (Delves_PickPower); started and stopped from Delves.lua.

local PICK_DELAY = 0 -- seconds: the next frame, so Blizzard's choice window has opened before the answer closes it
local REPEAT_GUARD = 2 -- seconds: the same choice isn't answered twice while the first answer is on its way

local db
local events = ns.Delves_Events
local pending = false
local lastChoice, lastAt
local refusedSaid = false -- the "pick it yourself" note goes to chat once per session

-- The open choice with plain values only, or nil (none open, or a value that is secret in this context).
local function Choice()
	local info = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
	if not info or ns.IsSecret(info.choiceID) then
		return nil
	end
	local options = {}
	for i, o in ipairs(info.options or {}) do
		local buttons = {}
		for j, b in ipairs(o.buttons or {}) do
			if ns.IsSecret(b.id, b.disabled, b.confirmation) then
				return nil
			end
			buttons[j] = { id = b.id, disabled = b.disabled, confirmation = b.confirmation }
		end
		if ns.IsSecret(o.spellID, o.header, o.disabledOption) then
			return nil
		end
		options[i] = { spellID = o.spellID, header = o.header, disabledOption = o.disabledOption, buttons = buttons }
	end
	return { id = info.choiceID, options = options }
end

local function InDelve()
	return C_PartyInfo.IsDelveInProgress() == true
end

local function PowerText(option)
	return (option.spellID and C_Spell.GetSpellLink(option.spellID)) or option.header or "a power"
end

local function Pick()
	pending = false
	if not (db and db.autoPower and InDelve()) then
		return
	end
	-- An answer (ours or the player's) is already on its way: the choice's updates until then aren't a new choice.
	if C_PlayerChoice.IsWaitingForPlayerChoiceResponse() then
		return
	end
	local choice = Choice()
	if not choice then
		return
	end
	local option = ns.Delves_PickPower(choice.options, ns.Delves_ParsePowers(db.powers))
	if not option then
		return
	end
	local now = GetTime()
	if lastChoice == choice.id and lastAt and now - lastAt < REPEAT_GUARD then
		return
	end
	lastChoice, lastAt = choice.id, now
	-- pcall: a client that does want a hardware event here refuses the call; then the player picks it as usual.
	local ok = pcall(C_PlayerChoice.SendPlayerChoiceResponse, option.buttons[1].id)
	if ok then
		ns.Print(("picked %s."):format(PowerText(option)))
	elseif not refusedSaid then
		refusedSaid = true
		ns.Print("the game didn't let Tomte pick the delve power; pick it yourself.")
	end
end

events:On("powers", "PLAYER_CHOICE_UPDATE", function()
	if not pending then
		pending = true
		C_Timer.After(PICK_DELAY, Pick)
	end
end)

function ns.DelvesPowers_Init(saved)
	db = saved
end

-- Watches the choice window while the module is on and the setting is on.
function ns.DelvesPowers_Toggle(active)
	if active and db and db.autoPower then
		events:Watch("powers", "PLAYER_CHOICE_UPDATE")
	else
		events:Unwatch("powers", "PLAYER_CHOICE_UPDATE")
	end
end

local REASON = {
	only = "it's the only one",
	preferred = "it's on your preferred list",
	nomatch = "none is on your preferred list",
	notpowers = "this isn't a power choice",
	none = "no options",
}

-- /tomte delves powers: the open choice's options (name and spell ID, for the preferred list) and what auto-pick does.
function ns.DelvesPowers_Why()
	local choice = Choice()
	if not choice then
		ns.Print("no choice window is open. Run this while the delve power choice shows.")
		return
	end
	ns.Print(("choice %d, %d %s:"):format(choice.id, #choice.options, #choice.options == 1 and "option" or "options"))
	for _, o in ipairs(choice.options) do
		print(("  %s (spell %s)"):format(o.header or "?", tostring(o.spellID)))
	end
	local option, why = ns.Delves_PickPower(choice.options, ns.Delves_ParsePowers(db.powers))
	local verdict = option and ("would pick %s: %s"):format(option.header or "?", REASON[why])
		or ("would pick nothing: %s"):format(REASON[why] or why)
	if not db.autoPower then
		verdict = verdict .. " (auto-pick is off)"
	elseif not InDelve() then
		verdict = verdict .. " (only inside a delve)"
	end
	print("  " .. verdict)
end
