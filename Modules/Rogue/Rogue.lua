local addonName, ns = ...

-- Rogue Poisons: a row of buttons that appears when a poison is missing or about to run out, each one applying
-- that poison with a click (or the "Apply missing poison" key binding), plus a poison check with a banner when
-- you enter a dungeon, raid or delve and on ready checks. Rogues only. Out of combat only: applying a poison is
-- a protected action, so the buttons are secure and can't change in combat. Pure rules in Data.lua.

local BUTTONS = 4 -- two lethal and two non-lethal with Dragon-Tempered Blades
local SIZE, GAP = 40, 6
local TICK = 5 -- seconds between checks out of combat (counts down "low" poisons, catches them running low)
local ENTER_DELAY = 4
local RED, YELLOW = { 1, 0.25, 0.2 }, { 1, 0.82, 0 }
local ICON = "Interface\\Icons\\Ability_Rogue_DualWeild"
local PREVIEW = { { spellID = 2823, reason = "missing" }, { spellID = 3408, reason = "low", left = 420 } }
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local module, db, holder, ticker
local buttons = {}

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

local function IsRogue()
	local _, class = UnitClass("player")
	return class == "ROGUE"
end

local function CharDB()
	local guid = UnitGUID("player")
	local char = db.chars[guid]
	if not char then
		char = { last = { lethal = {}, nonLethal = {} } }
		db.chars[guid] = char
	end
	return char
end

local function Known(spellID)
	if IsPlayerSpell and IsPlayerSpell(spellID) then
		return true
	end
	return C_SpellBook.IsSpellKnown(spellID) and true or false
end

-- Seconds left on a poison, math.huge when the time can't be read, nil when it isn't on.
local function TimeLeft(spellID)
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	if not aura then
		local name = C_Spell.GetSpellName(spellID)
		aura = name and C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
	end
	if not aura then
		return nil
	end
	local expires = aura.expirationTime
	if IsSecret(expires) or type(expires) ~= "number" or expires == 0 then
		return math.huge
	end
	return expires - GetTime()
end

local function Situation()
	local s = { known = {}, active = {}, last = CharDB().last }
	for _, list in ipairs({ ns.ROGUE_LETHAL, ns.ROGUE_NONLETHAL }) do
		for _, id in ipairs(list) do
			if C_Spell.GetSpellName(id) then -- skips an ID this client doesn't have
				s.known[id] = Known(id)
				s.active[id] = TimeLeft(id)
			end
		end
	end
	s.twoEach = Known(ns.ROGUE_DRAGON_TEMPERED_BLADES)
	local index = GetSpecialization()
	s.specID = index and GetSpecializationInfo(index) or nil
	return s
end

local function Rules()
	return { lethal = db.lethal, nonLethal = db.nonLethal, lowSeconds = db.lowMinutes * 60 }
end

local function Problems()
	return ns.Rogue_PoisonProblems(Situation(), Rules())
end

local function ProblemText(p)
	local name = C_Spell.GetSpellName(p.spellID) or "Poison"
	if p.reason == "low" then
		return name .. ": " .. ns.Rogue_FormatLeft(p.left) .. " left"
	end
	return (p.kind == "lethal" and "No lethal poison: " or "No non-lethal poison: ") .. name
end

-- Buttons -----------------------------------------------------------------------------------------------------

local function ButtonOnEnter(self)
	local p = self.problem
	if not p then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetSpellByID(p.spellID)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(p.reason == "low" and ("Runs out in " .. ns.Rogue_FormatLeft(p.left) .. ".")
		or "Not on your weapons.", 1, 0.82, 0)
	GameTooltip:AddLine("Click to apply it.", 0.4, 1, 0.4)
	local key = GetBindingKey("CLICK TomtePoison1:LeftButton")
	if key and self:GetID() == 1 then
		GameTooltip:AddLine("Key: " .. GetBindingText(key), 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function CreateButton(i)
	local b = CreateFrame("Button", "TomtePoison" .. i, holder, "SecureActionButtonTemplate")
	b:SetID(i)
	b:SetSize(SIZE, SIZE)
	if i == 1 then
		b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	else
		b:SetPoint("LEFT", buttons[i - 1], "RIGHT", GAP, 0)
	end
	b:RegisterForClicks("AnyDown")
	b:SetAttribute("useOnKeyDown", true)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -2, 2)
	b.border:SetPoint("BOTTOMRIGHT", 2, -2)
	b.border:SetColorTexture(1, 1, 1)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)

	b.pulse = b.border:CreateAnimationGroup()
	b.pulse:SetLooping("BOUNCE")
	local fade = b.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.7)

	b:SetScript("OnEnter", ButtonOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	buttons[i] = b
	return b
end

local function CreateHolder()
	holder = CreateFrame("Frame", "TomtePoisonBar", UIParent, "SecureFrameTemplate")
	holder:SetSize(SIZE, SIZE)
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:SetFrameStrata("MEDIUM")
	holder.title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	holder.title:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 4)
	holder.title:SetText("Apply poison")
	for i = 1, BUTTONS do
		CreateButton(i)
	end
	holder:Hide()
end

local function ApplyLayout()
	holder:ClearAllPoints()
	holder:SetPoint(db.frame.point, UIParent, db.frame.relPoint, db.frame.x, db.frame.y)
	holder:SetScale(db.scale)
end

-- Secure attributes: out of combat only. The preview never casts.
local function SetButton(b, p, preview)
	b.problem = p
	if p then
		local name = C_Spell.GetSpellName(p.spellID)
		b:SetAttribute("type", (name and not preview) and "macro" or nil)
		b:SetAttribute("macrotext", (name and not preview) and ("/cast " .. name) or nil)
		b.icon:SetTexture(C_Spell.GetSpellTexture(p.spellID) or ICON)
		local color = p.reason == "low" and YELLOW or RED
		b.border:SetVertexColor(color[1], color[2], color[3])
		b.label:SetText(p.reason == "low" and ns.Rogue_FormatLeft(p.left) or "Missing")
		b.label:SetTextColor(color[1], color[2], color[3])
		if not b.pulse:IsPlaying() then
			b.pulse:Play()
		end
		b:Show()
	else
		b:SetAttribute("type", nil)
		b:SetAttribute("macrotext", nil)
		b.pulse:Stop()
		b:Hide()
	end
end

-- Whether the buttons may show at all right now (problems aside).
local function Allowed()
	if not (module.active and db.bar) then
		return false
	end
	if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or UnitInVehicle("player") then
		return false
	end
	if C_PetBattles and C_PetBattles.IsInBattle() then
		return false
	end
	if db.hideResting and IsResting() then
		return false
	end
	return true
end

local function Refresh()
	if InCombatLockdown() or not (holder or module.active) then
		return
	end
	if not holder then -- made here, out of combat: a /reload in combat can't place a protected frame
		CreateHolder()
		ApplyLayout()
	end
	local problems
	local preview = ns.EditMode_Active() and module.active
	if preview then
		problems = PREVIEW
	elseif Allowed() then
		problems = Problems()
	else
		problems = {}
	end
	for i = 1, BUTTONS do
		SetButton(buttons[i], problems[i], preview)
	end
	local n = math.min(#problems, BUTTONS)
	holder:SetSize(math.max(n, 1) * (SIZE + GAP) - GAP, SIZE)
	holder:SetShown(n > 0)
end

-- Poison check (banner) ---------------------------------------------------------------------------------------

-- verbose: also report when everything's fine, and list what was found (the slash command and options button).
local function Check(verbose)
	if not module.active then
		if verbose then
			ns.Print("Rogue Poisons is off.")
		end
		return
	end
	if InCombatLockdown() or UnitIsDeadOrGhost("player") then
		if verbose then
			ns.Print("poison check: not in combat or while dead.")
		end
		return
	end
	local s = Situation()
	if verbose then
		local known, active = {}, {}
		for id, isKnown in pairs(s.known) do
			if isKnown then
				known[#known + 1] = C_Spell.GetSpellName(id) .. " (" .. id .. ")"
			end
		end
		for id, left in pairs(s.active) do
			active[#active + 1] = C_Spell.GetSpellName(id)
				.. (left == math.huge and "" or (" " .. ns.Rogue_FormatLeft(left)))
		end
		table.sort(known)
		table.sort(active)
		ns.Print("poisons you know: " .. (#known > 0 and table.concat(known, ", ") or "none"))
		ns.Print("on your weapons: " .. (#active > 0 and table.concat(active, ", ") or "none")
			.. (s.twoEach and " (Dragon-Tempered Blades: two of each)" or ""))
	end
	local problems = ns.Rogue_PoisonProblems(s, Rules())
	if #problems == 0 then
		if verbose then
			ns.Print("poison check: all good.")
		end
		return
	end
	local lines = {}
	for i, p in ipairs(problems) do
		lines[i] = ProblemText(p)
		ns.Print("|cffff9940" .. lines[i] .. "|r")
	end
	if db.check.banner and not verbose then
		ns.Banner_Show({
			owner = "rogue",
			label = "Poison check",
			accent = RED,
			title = lines[1],
			subtitle = #lines > 1 and table.concat(lines, "   -   ", 2) or nil,
			icon = C_Spell.GetSpellTexture(problems[1].spellID) or ICON,
			hold = 5,
		})
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
end

-- Events ------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

function events:PLAYER_ENTERING_WORLD()
	Refresh()
	if not db.check.onEnter then
		return
	end
	local _, instanceType, difficultyID = GetInstanceInfo()
	if ns.Hunter_ContentKind(instanceType, difficultyID) then
		C_Timer.After(ENTER_DELAY, function()
			Check(false)
		end)
	end
end

function events:READY_CHECK()
	if db.check.onReadyCheck then
		Check(false)
	end
end

-- Fires just before the combat lockdown starts: the last moment the secure holder can be hidden.
function events:PLAYER_REGEN_DISABLED()
	if holder then
		holder:Hide()
	end
end

function events:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	local kind = not IsSecret(spellID) and ns.Rogue_PoisonKind(spellID)
	if kind then
		local last = CharDB().last
		last[kind] = ns.Rogue_RememberPoison(last[kind], spellID)
	end
end

for _, event in ipairs({
	"PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_CONTROL_GAINED", "PET_BATTLE_CLOSE",
	"UNIT_AURA", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
}) do
	events[event] = Refresh
end

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "READY_CHECK", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE",
	"PLAYER_UNGHOST", "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_UPDATE_RESTING", "PLAYER_CONTROL_GAINED",
	"PET_BATTLE_CLOSE",
}
local UNIT_EVENTS = {
	"UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
	"PLAYER_SPECIALIZATION_CHANGED",
}

local function Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	for _, event in ipairs(UNIT_EVENTS) do
		events:RegisterUnitEvent(event, "player")
	end
	ticker = ticker or C_Timer.NewTicker(TICK, Refresh)
	Refresh()
end

local function Stop()
	events:UnregisterAllEvents()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	ns.Banner_Clear("rogue")
	if holder and not InCombatLockdown() then
		Refresh() -- module.active is false by now: hides everything and clears the attributes
	end
end

local function Relayout()
	if holder and not InCombatLockdown() then
		ApplyLayout()
		Refresh()
	end
end

local function ResetPosition()
	db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = "CENTER", "CENTER", 0, -120
	Relayout()
end

ns.EditMode_Register({
	name = "Poison buttons",
	frame = function()
		return holder
	end,
	refresh = Refresh,
	saved = function()
		local point, _, relPoint, x, y = holder:GetPoint()
		db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = point, relPoint, x, y
	end,
})

local function Minutes(v)
	return v == 0 and "off" or (v .. " min")
end

local function Scale(v)
	return ("%.1f"):format(v)
end

module = ns.RegisterModule({
	key = "rogue",
	name = "Rogue Poisons",
	category = "Class",
	description = "Buttons that appear when a poison is missing from your weapons or about to run out: click one to apply that poison. A poison check when you enter a dungeon, raid or delve and on ready checks.",
	enabledByDefault = true,
	defaults = {
		bar = true,
		lethal = true,
		nonLethal = true,
		lowMinutes = 10,
		hideResting = false,
		scale = 1,
		frame = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
		check = { onEnter = true, onReadyCheck = true, banner = true },
		chars = {}, -- [player GUID] = { last = { lethal = { spellIDs }, nonLethal = { spellIDs } } }, newest first
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	blocked = function()
		if not IsRogue() then
			return "Only for rogues."
		end
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "check", "list your poisons and run the poison check now", function()
			Check(true)
		end },
	},
	options = {
		{ type = "header", label = "Poison buttons" },
		{ type = "checkbox", key = "bar", label = "Show poison buttons", onChange = Refresh,
			tooltip = "Out of combat, a button appears for each poison that's missing or about to run out. Click it to apply the poison. Key Bindings > Tomte > Apply missing poison does the same with a key." },
		{ type = "checkbox", key = "lethal", label = "Lethal poison", onChange = Refresh,
			tooltip = "Deadly, Instant, Wound or Amplifying Poison. The button offers the one you applied last." },
		{ type = "checkbox", key = "nonLethal", label = "Non-lethal poison", onChange = Refresh,
			tooltip = "Crippling, Atrophic or Numbing Poison. The button offers the one you applied last." },
		{ type = "slider", key = "lowMinutes", label = "Warn when less than", min = 0, max = 30, step = 1,
			format = Minutes, onChange = Refresh,
			tooltip = "Poisons last an hour. Below this the button appears to refresh it." },
		{ type = "checkbox", key = "hideResting", label = "Hide in cities and inns", onChange = Refresh },
		{ type = "slider", key = "scale", label = "Size", min = 0.6, max = 1.6, step = 0.1, format = Scale,
			onChange = Relayout },
		{ type = "button", label = "Position", text = "Reset", onClick = ResetPosition,
			tooltip = "Move the buttons back to just below the middle of the screen. Blizzard's Edit Mode moves them too." },

		{ type = "header", label = "Poison check" },
		{ type = "checkbox", key = "check.onEnter", label = "When entering an instance",
			tooltip = "Check a few seconds after entering a dungeon, raid or delve." },
		{ type = "checkbox", key = "check.onReadyCheck", label = "On ready checks" },
		{ type = "checkbox", key = "check.banner", label = "Banner and sound",
			tooltip = "Show problems as a banner with a warning sound. Off: chat only." },
		{ type = "button", label = "Poison check", text = "Run", onClick = function()
			Check(true)
		end, tooltip = "List the poisons you know and have on, and what's missing." },
	},
})

_G["BINDING_NAME_CLICK TomtePoison1:LeftButton"] = "Apply missing poison"
