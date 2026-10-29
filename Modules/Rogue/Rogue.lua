local addonName, ns = ...

-- Rogue Poisons: a row of buttons that appears when a poison is missing or about to run out, each one applying
-- that poison with a click (or the "Apply missing poison" key binding), plus a poison check with a banner when
-- you enter a dungeon, raid or delve and on ready checks. Out of combat only: applying a poison is a protected
-- action, so the buttons are secure and can't change in combat. Also Handy Lockpick (Lockpick.lua), which
-- Mechagnomes of any class get too; the poison parts stay off for them. Pure rules in Data.lua.

local BUTTONS = 4 -- two lethal and two non-lethal with Dragon-Tempered Blades
local SIZE, GAP = 40, 6
local BORDER = 2 -- the colored border reaches this far outside a button
-- The settings preview's room for the title over the buttons and the labels under them.
local PREVIEW_TOP, PREVIEW_BOTTOM = 20, 16
local TICK = 5 -- seconds between checks out of combat (counts down "low" poisons, catches them running low)
local ENTER_DELAY = 4 -- seconds after zoning in before the poison check
-- Seconds to gather a burst of aura changes (a city full of buffs, applying a poison) into one rebuild.
local AURA_DELAY = 0.2
local UI = ns.UI
local ICON = "Interface\\Icons\\Ability_Rogue_DualWeild"
-- Global names: the CLICK binding in Bindings.xml needs the first button's.
local BUTTON_PREFIX = "TomtePoison"
local BINDING = "CLICK " .. BUTTON_PREFIX .. "1:LeftButton"
-- What Edit Mode shows: Deadly Poison missing, Crippling Poison with 7 minutes left.
local PREVIEW = { { spellID = 2823, reason = "missing" }, { spellID = 3408, reason = "low", left = 420 } }
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local module, db, holder, ticker
local buttons = {}

local IsSecret = ns.IsSecret

local function IsRogue()
	local _, class = UnitClass("player")
	return class == "ROGUE"
end

local function IsMechagnome()
	local _, race = UnitRace("player")
	return race == "Mechagnome"
end

-- The spell that picks locks for this character: Pick Lock for a rogue, else the Mechagnome racial; nil for
-- anyone else.
local function LockSpell()
	if IsRogue() and (C_SpellBook.IsSpellKnown(ns.ROGUE_PICK_LOCK) or not IsMechagnome()) then
		return ns.ROGUE_PICK_LOCK
	elseif IsMechagnome() then
		return ns.ROGUE_SKELETON_PINKIE
	end
	return nil
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
		or "Not on your weapons.", UI.RGB(p.reason == "low" and "warning" or "danger"))
	GameTooltip:AddLine("Click to apply it.", UI.RGB("success"))
	local key = GetBindingKey(BINDING)
	if key and self:GetID() == 1 then
		GameTooltip:AddLine("Key: " .. GetBindingText(key), UI.RGB("textMuted"))
	end
	GameTooltip:Show()
end

-- A button's looks (icon, border, label, pulse), on the secure button or on a settings preview's plain frame; row is
-- the frame the buttons sit in, previous the button left of this one.
local function Decorate(b, row, previous)
	b:SetSize(SIZE, SIZE)
	if previous then
		b:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
	else
		b:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	end
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -2, 2)
	b.border:SetPoint("BOTTOMRIGHT", 2, -2)
	b.border:SetColorTexture(1, 1, 1)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	UI.SetFont(b.label, "body", 10)
	b.label:SetShadowOffset(1, -1)
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)

	b.pulse = b.border:CreateAnimationGroup()
	b.pulse:SetLooping("BOUNCE")
	local fade = b.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.7)
end

-- What a button shows for problem p (icon, border and label colored by how urgent, the pulse).
local function Paint(b, p)
	b.icon:SetTexture(C_Spell.GetSpellTexture(p.spellID) or ICON)
	local role = p.reason == "low" and "warning" or "danger"
	b.border:SetVertexColor(UI.Color(role))
	b.label:SetText(p.reason == "low" and ns.Rogue_FormatLeft(p.left) or "Missing")
	UI.SetTextRole(b.label, role)
	if not b.pulse:IsPlaying() then
		b.pulse:Play()
	end
end

local function CreateButton(i)
	local b = CreateFrame("Button", BUTTON_PREFIX .. i, holder, "SecureActionButtonTemplate")
	b:SetID(i)
	Decorate(b, holder, buttons[i - 1])
	b:RegisterForClicks("AnyDown")
	b:SetAttribute("useOnKeyDown", true)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnEnter", ButtonOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	buttons[i] = b
	return b
end

-- The "Apply poison" title over row (the holder, or a settings preview's row).
local function AddTitle(row)
	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	UI.SetFont(row.title, "title", 12)
	UI.SetTextRole(row.title, "heading")
	row.title:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 4)
	row.title:SetText("Apply poison")
end

local function CreateHolder()
	holder = CreateFrame("Frame", "TomtePoisonBar", UIParent, "SecureFrameTemplate")
	holder:SetSize(SIZE, SIZE)
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:SetFrameStrata("MEDIUM")
	AddTitle(holder)
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
		Paint(b, p)
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
	if InCombatLockdown() or not IsRogue() or not (holder or module.active) then
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
local function FindProblems(verbose)
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
	local lines = {}
	for i, p in ipairs(problems) do
		lines[i] = ProblemText(p)
	end
	return lines, problems[1] and (C_Spell.GetSpellTexture(problems[1].spellID) or ICON)
end

local function Check(verbose)
	if not IsRogue() then
		ns.Print("poisons are for rogues only.")
		return
	end
	ns.Check_Report({
		active = module.active,
		verbose = verbose,
		offMessage = "Rogue Poisons is off.",
		name = "poison check",
		find = function()
			return FindProblems(verbose)
		end,
		banner = db.check.banner,
		bannerOnVerbose = false,
		owner = "rogue",
		label = "Poison check",
		accent = "danger",
	})
end

-- Events ------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

function events:PLAYER_ENTERING_WORLD()
	Refresh()
	if not db.check.onEnter then
		return
	end
	ns.Check_OnEnterWorld(ENTER_DELAY, function()
		Check(false)
	end)
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
	ns.RogueLock_Hide()
end

function events:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if IsSecret(spellID) then
		return
	end
	ns.RogueLock_OnCast(spellID)
	local kind = IsRogue() and ns.Rogue_PoisonKind(spellID)
	if kind then
		local last = CharDB().last
		last[kind] = ns.Rogue_RememberPoison(last[kind], spellID)
	end
end

-- An item picked up, or the other side of a trade changed its slots: the lockpick button's slot may be stale.
function events:CURSOR_CHANGED()
	ns.RogueLock_Hide()
end

function events:TRADE_TARGET_ITEM_CHANGED()
	ns.RogueLock_Hide()
end

for _, event in ipairs({
	"PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED",
	"PLAYER_SPECIALIZATION_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_CONTROL_GAINED", "PET_BATTLE_CLOSE",
	"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
}) do
	events[event] = Refresh
end

-- Aura changes come in bursts: one rebuild per burst. In combat nothing can change anyway (Refresh would return),
-- so no timer then; a deferred Refresh that lands in combat or after Stop is handled by Refresh's own guards.
local refreshSoon = UI.Debounce(AURA_DELAY, Refresh)
function events:UNIT_AURA()
	if not InCombatLockdown() then
		refreshSoon()
	end
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

-- Handy Lockpick's events (PLAYER_REGEN_DISABLED and UNIT_SPELLCAST_SUCCEEDED are the poison parts' too).
local LOCK_EVENTS = { "PLAYER_REGEN_DISABLED", "CURSOR_CHANGED", "TRADE_TARGET_ITEM_CHANGED" }

-- Turns Handy Lockpick on or off to match the module and its option.
local function ApplyLockpick()
	local spellID = LockSpell()
	if module.active and db.lockpick and spellID then
		ns.RogueLock_Start(spellID)
		for _, event in ipairs(LOCK_EVENTS) do
			events:RegisterEvent(event)
		end
		events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		return
	end
	ns.RogueLock_Stop()
	events:UnregisterEvent("CURSOR_CHANGED")
	events:UnregisterEvent("TRADE_TARGET_ITEM_CHANGED")
	if not (module.active and IsRogue()) then
		events:UnregisterEvent("PLAYER_REGEN_DISABLED")
		events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	end
end

local function Start()
	if IsRogue() then
		for _, event in ipairs(EVENTS) do
			events:RegisterEvent(event)
		end
		for _, event in ipairs(UNIT_EVENTS) do
			events:RegisterUnitEvent(event, "player")
		end
		ticker = ticker or C_Timer.NewTicker(TICK, Refresh)
		Refresh()
	end
	ApplyLockpick()
end

local function Stop()
	events:UnregisterAllEvents()
	ns.RogueLock_Stop()
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

-- The same position as the `frame` default below.
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
	module = "rogue",
	options = { "scale", "lethal", "nonLethal", "hideResting" },
	reset = ResetPosition,
})

local function Minutes(v)
	return v == 0 and "off" or (v .. " min")
end

-- The poison rows (shown to rogues only: a Mechagnome of another class only gets Handy Lockpick), then the
-- lockpick card.
local function Options(poisonRows)
	for _, row in ipairs(poisonRows) do
		row.shown = IsRogue
	end
	poisonRows[#poisonRows + 1] = { type = "header", label = "Handy Lockpick" }
	poisonRows[#poisonRows + 1] = { type = "checkbox", key = "lockpick", label = "Right-click to pick lockboxes",
		onChange = ApplyLockpick,
		tooltip = "Right-click a locked lockbox in your bags, or in the trade window's \"will not be traded\" slot, to pick its lock (Pick Lock, or the Mechagnome racial). Out of combat only. Left-click still works as usual." }
	return poisonRows
end

local function Scale(v)
	return ("%.1f"):format(v)
end

-- Settings preview (Panel/Preview.lua): Edit Mode's sample buttons at the chosen size, on plain frames (the real
-- ones are secure), also while they're off (the preview answers their switch as on). Nothing on other classes: the
-- buttons are a rogue's.
local function BarPreview(host, get)
	if not IsRogue() then
		return nil
	end
	local row = host.row
	if not row then
		row = CreateFrame("Frame", nil, host)
		AddTitle(row)
		row.buttons = {}
		for i = 1, #PREVIEW do
			row.buttons[i] = CreateFrame("Frame", nil, row)
			Decorate(row.buttons[i], row, row.buttons[i - 1])
		end
		host.row = row
	end
	local scale = get("scale")
	row:SetScale(scale)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", BORDER, -PREVIEW_TOP)
	local width = #PREVIEW * (SIZE + GAP) - GAP
	row:SetSize(width, SIZE)
	UI.SetTextRole(row.title, "heading")
	for i, b in ipairs(row.buttons) do
		Paint(b, PREVIEW[i])
	end
	return (width + 2 * BORDER) * scale, (PREVIEW_TOP + SIZE + PREVIEW_BOTTOM) * scale
end

module = ns.RegisterModule({
	key = "rogue",
	name = "Rogue Poisons",
	category = "class",
	icon = 132273, -- ability_poisons
	summary = "One click to reapply a missing poison, a poison check, and right-click to pick lockboxes.",
	description = "Buttons that appear when a poison is missing from your weapons or about to run out: click one to apply that poison. A poison check when you enter a dungeon, raid or delve and on ready checks. Handy Lockpick: right-click a locked lockbox in your bags or the trade window to pick it (rogues, and Mechagnomes of any class).",
	enabledByDefault = true,
	toasts = "Rogue poison check (banners)",
	replaces = { { addon = "Plumber", why = "Handy Lockpick: right-click a lockbox to pick it" } },
	defaults = {
		lockpick = false,
		bar = true,
		lethal = true,
		nonLethal = true,
		lowMinutes = 10,
		hideResting = false,
		scale = 1,
		frame = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 }, -- ResetPosition repeats it
		check = { onEnter = true, onReadyCheck = true, banner = true },
		chars = {}, -- [player GUID] = { last = { lethal = { spellIDs }, nonLethal = { spellIDs } } }, newest first
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	blocked = function()
		if not IsRogue() and not IsMechagnome() then
			return "Only for rogues and Mechagnomes."
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
	options = Options({
		{ type = "header", label = "Poison buttons" },
		{ type = "checkbox", key = "bar", label = "Show poison buttons", onChange = Refresh,
			preview = ns.Preview_When("bar", BarPreview),
			tooltip = "Out of combat, a button appears for each poison that's missing or about to run out. Click it to apply the poison. Key Bindings > Tomte > Apply missing poison does the same with a key." },
		{ type = "checkbox", key = "hideResting", label = "Hide in cities and inns", onChange = Refresh,
			parent = "bar" },
		{ type = "slider", key = "scale", label = "Size", min = 0.6, max = 1.6, step = 0.1, format = Scale,
			onChange = Relayout, parent = "bar", preview = ns.Preview_When("bar", BarPreview) },
		{ type = "button", label = "Position", text = "Reset", onClick = ResetPosition, parent = "bar",
			tooltip = "Move the buttons back to just below the middle of the screen. Blizzard's Edit Mode moves them too." },
		{ type = "checkbox", key = "lethal", label = "Lethal poison", onChange = Refresh,
			tooltip = "Deadly, Instant, Wound or Amplifying Poison. The button offers the one you applied last." },
		{ type = "checkbox", key = "nonLethal", label = "Non-lethal poison", onChange = Refresh,
			tooltip = "Crippling, Atrophic or Numbing Poison. The button offers the one you applied last." },
		{ type = "slider", key = "lowMinutes", label = "Warn when less than", min = 0, max = 30, step = 1,
			format = Minutes, onChange = Refresh,
			tooltip = "Poisons last an hour. Below this the button appears to refresh it." },

		{ type = "header", label = "Poison check" },
		{ type = "checkbox", key = "check.onEnter", label = "When entering an instance",
			tooltip = "Check a few seconds after entering a dungeon, raid or delve." },
		{ type = "checkbox", key = "check.onReadyCheck", label = "On ready checks" },
		{ type = "checkbox", key = "check.banner", label = "Banner and sound",
			tooltip = "Show problems as a banner with a warning sound. Off: chat only." },
		{ type = "button", label = "Poison check", text = "Run", onClick = function()
			Check(true)
		end, tooltip = "List the poisons you know and have on, and what's missing." },
	}),
})

_G["BINDING_NAME_" .. BINDING] = "Apply missing poison"
