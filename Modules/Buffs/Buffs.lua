local addonName, ns = ...

-- Buff reminders: in dungeons, raids and delves and during ready checks, an icon strip for each buff you're missing
-- (food, flask, augment rune, weapon oil or stone, and the group buff your class brings when someone lacks it),
-- plus a buff check in chat on entering and on ready checks. Out of combat only: the strip hides on
-- PLAYER_REGEN_DISABLED and nothing is read in combat. Pure rules in Data.lua, reads in Read.lua, the strip in
-- Strip.lua; consumable lists in Data/<Expansion>/Buffs.lua.

local ENTER_DELAY = 4 -- seconds after zoning in before the buff check: auras and the group are back by then
-- Seconds to gather a burst of aura changes (a raid buffing up) into one rebuild.
local AURA_DELAY = 0.5
local TEST_SECONDS = 15 -- how long /tomte buffs test shows the sample strip
local FOOD_ICON = 136000 -- spell_misc_food
local WEAPON_ICON = 135248 -- inv_stone_sharpeningstone_01, when the weapon has no icon
local SLOT_NAME = { [16] = "main hand", [17] = "off hand" }
local GROUP_NAMES_SHOWN = 10 -- names in the group buff tooltip
local UI = ns.UI

local module, db
local readyUntil -- GetTime() when the running ready check times out
local testUntil -- GetTime() when the /tomte buffs test preview ends

local function ReadyCheck()
	return readyUntil ~= nil and GetTime() < readyUntil
end

local function Rules()
	local rules = {}
	for _, key in ipairs(ns.BUFFS_CHECKS) do
		rules[key] = db[key]
	end
	return rules
end

local function FirstTexture(ids)
	for _, id in ipairs(ids or {}) do
		local texture = C_Spell.GetSpellTexture(id)
		if texture then
			return texture
		end
	end
	return ns.ICON
end

local function GroupName(s)
	return s.group and s.group.name or ns.Buffs_Label("group")
end

-- Strip items ----------------------------------------------------------------------------------------------------

local function Item(r, s)
	local data = ns.Content_Get(s.expansion, "buffs") or {}
	if r.key == "food" then
		return { icon = FOOD_ICON, title = ns.Buffs_Label("food"), role = "danger",
			lines = { { "You're not Well Fed. Eat before the pull.", "textMuted" } } }
	elseif r.key == "flask" then
		return { icon = FirstTexture(data.flask), title = ns.Buffs_Label("flask"), role = "danger",
			lines = { { "No flask on.", "textMuted" } } }
	elseif r.key == "rune" then
		return { icon = FirstTexture(data.rune), title = ns.Buffs_Label("rune"), role = "warning",
			lines = { { "No augment rune on.", "textMuted" } } }
	elseif r.key == "weapon" then
		local lines = {}
		for _, w in ipairs(r.weapons) do
			lines[#lines + 1] = { "Nothing on your " .. SLOT_NAME[w.slot] .. ".", "textMuted" }
		end
		return { icon = GetInventoryItemTexture("player", r.weapons[1].slot) or WEAPON_ICON,
			title = ns.Buffs_Label("weapon"), role = "warning", lines = lines }
	end
	local lines = { { "Missing on:", "textMuted" } }
	for i, m in ipairs(r.missing) do
		if i > GROUP_NAMES_SHOWN then
			lines[#lines + 1] = { "and " .. (#r.missing - GROUP_NAMES_SHOWN) .. " more", "textMuted" }
			break
		end
		lines[#lines + 1] = { m.isPlayer and "You" or UI.ClassColored(m.name, m.class), "text" }
	end
	return { icon = C_Spell.GetSpellTexture(r.spellID) or ns.ICON, title = GroupName(s), role = "accent",
		count = #r.missing > 1 and #r.missing or nil, lines = lines }
end

-- What Edit Mode and /tomte buffs test show.
local function SampleItems()
	local _, class = UnitClass("player")
	local groupSpell = ns.BUFFS_GROUP[class] or ns.BUFFS_GROUP.MAGE
	local sample = { "Sample: shows when this is missing.", "textMuted" }
	local flasks = (ns.Content_Get(ns.ContentExpansion(), "buffs") or {}).flask
	return {
		{ icon = FOOD_ICON, title = ns.Buffs_Label("food"), role = "danger", lines = { sample } },
		{ icon = FirstTexture(flasks), title = ns.Buffs_Label("flask"), role = "danger", lines = { sample } },
		{ icon = WEAPON_ICON, title = ns.Buffs_Label("weapon"), role = "warning", lines = { sample } },
		{ icon = C_Spell.GetSpellTexture(groupSpell) or ns.ICON, title = C_Spell.GetSpellName(groupSpell)
			or ns.Buffs_Label("group"), role = "accent", count = 3, lines = { sample } },
	}
end

-- Refresh --------------------------------------------------------------------------------------------------------

-- Whether the strip may show at all right now (what's missing aside).
local function Allowed()
	if not db.strip or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or UnitInVehicle("player") then
		return false
	end
	return not (C_PetBattles and C_PetBattles.IsInBattle())
end

local function CurrentContent()
	local _, instanceType, difficultyID = GetInstanceInfo()
	return ns.Check_ContentKind(instanceType, difficultyID)
end

local function Refresh()
	if not module.active or InCombatLockdown() then
		ns.Buffs_StripHide()
		return
	end
	-- Edit Mode only shows the strip when it's turned on; the test command and Preview button show it either way.
	if (db.strip and ns.EditMode_Active()) or (testUntil and GetTime() < testUntil) then
		ns.Buffs_StripShow(SampleItems())
		return
	end
	if not Allowed() or not ns.Buffs_Watching(CurrentContent(), ReadyCheck()) then
		ns.Buffs_StripHide()
		return
	end
	local s = ns.Buffs_Read(ReadyCheck())
	local items = {}
	for _, r in ipairs(ns.Buffs_Missing(ns.Buffs_Evaluate(s, Rules()))) do
		items[#items + 1] = Item(r, s)
	end
	ns.Buffs_StripShow(items)
end

-- One rebuild AURA_DELAY after the first change of a burst. Not a debounce: a raid's steady stream of aura changes
-- would keep pushing a debounced rebuild back and the strip would never update.
local refreshPending = false

local function RefreshNow()
	refreshPending = false
	Refresh()
end

local function refreshSoon()
	if not refreshPending then
		refreshPending = true
		C_Timer.After(AURA_DELAY, RefreshNow)
	end
end

-- Buff check (chat, optional banner) -----------------------------------------------------------------------------

local function FindProblems()
	local s = ns.Buffs_Read(ReadyCheck())
	local lines, icon = {}, nil
	for _, r in ipairs(ns.Buffs_Missing(ns.Buffs_Evaluate(s, Rules()))) do
		lines[#lines + 1] = ns.Buffs_MissingText(r, GroupName(s))
		icon = icon or Item(r, s).icon
	end
	return lines, icon
end

local function Check(verbose)
	ns.Check_Report({
		active = module.active,
		verbose = verbose,
		offMessage = "Buff reminders is off.",
		name = "buff check",
		find = FindProblems,
		banner = db.check.banner,
		bannerOnVerbose = false,
		owner = "buffs",
		label = "Buff check",
		accent = "warning",
	})
end

local STATE_ROLE = { missing = "danger", ok = "success", unknown = "warning" }

-- /tomte buffs why: every check, its result and the reason.
local function Why()
	if not module.active then
		ns.Print("Buff reminders is off.")
		return
	end
	if InCombatLockdown() then
		ns.Print_Combat("check your buffs")
		return
	end
	local s = ns.Buffs_Read(ReadyCheck())
	ns.Print(("buffs: %s, content %s, place %s%s, max level %s."):format(tostring(s.class),
		ns.ExpansionName(s.expansion), s.content or "open world", s.readyCheck and " (ready check)" or "",
		s.atMax and "yes" or "no"))
	if s.aurasHidden then
		print("  " .. UI.Wrap("The game hides buffs from addons right now (combat, boss, Mythic+ or PvP).", "warning"))
	end
	if not ns.Buffs_Watching(s.content, s.readyCheck) then
		print("  " .. UI.Wrap("The strip only shows in dungeons, raids, delves and during ready checks.", "textMuted"))
	end
	for _, r in ipairs(ns.Buffs_Evaluate(s, Rules())) do
		local label = r.key == "group" and GroupName(s) or ns.Buffs_Label(r.key)
		local why = r.state == "missing" and ns.Buffs_MissingText(r, GroupName(s)) or r.why
		local looked = s.names[r.key]
		if looked and #looked > 0 and r.state ~= "off" then
			why = why .. " (looks for: " .. table.concat(looked, ", ") .. ")"
		end
		print("  " .. UI.Wrap(label .. ": " .. r.state, STATE_ROLE[r.state] or "textMuted") .. " - " .. why)
	end
end

local function Test()
	if not module.active then
		ns.Print("Buff reminders is off.")
		return
	end
	if testUntil and GetTime() < testUntil then
		testUntil = nil
	else
		testUntil = GetTime() + TEST_SECONDS
		C_Timer.After(TEST_SECONDS + 0.1, Refresh)
		ns.Print("showing a sample strip for " .. TEST_SECONDS .. " seconds (run it again to hide it).")
	end
	Refresh()
end

-- Events ---------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

function events:PLAYER_ENTERING_WORLD()
	Refresh()
	if db.check.onEnter then
		ns.Check_OnEnterWorld(ENTER_DELAY, function()
			Check(false)
			Refresh()
		end)
	end
end

function events:READY_CHECK(_, timeLeft)
	readyUntil = GetTime() + (type(timeLeft) == "number" and not ns.IsSecret(timeLeft) and timeLeft or 35)
	C_Timer.After(readyUntil - GetTime() + 0.1, Refresh)
	Refresh()
	if db.check.onReadyCheck then
		Check(false)
	end
end

function events:READY_CHECK_FINISHED()
	readyUntil = nil
	Refresh()
end

function events:PLAYER_REGEN_DISABLED()
	ns.Buffs_StripHide()
end

-- Player and group aura changes come in bursts: one rebuild per burst, and none in combat (Refresh would hide).
-- Only your own auras matter, and the group's when your class brings a group buff; nameplates, target, focus and
-- boss units are skipped before anything else is asked.
function events:UNIT_AURA(unit)
	if unit ~= "player" then
		local _, class = UnitClass("player")
		if not ns.BUFFS_GROUP[class] or not (unit:find("^party%d") or unit:find("^raid%d")) then
			return
		end
	end
	if not InCombatLockdown() and (ReadyCheck() or CurrentContent()) then
		refreshSoon()
	end
end

for _, event in ipairs({
	"ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
	"WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED", "SPELLS_CHANGED", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"PLAYER_CONTROL_GAINED", "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE",
}) do
	events[event] = function()
		refreshSoon()
	end
end

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "READY_CHECK", "READY_CHECK_FINISHED", "PLAYER_REGEN_DISABLED", "UNIT_AURA",
	"ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
	"WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED", "SPELLS_CHANGED", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"PLAYER_CONTROL_GAINED", "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE",
}

local function ApplyLayout()
	ns.Buffs_StripLayout(db.frame, db.scale)
end

local function Start()
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	ApplyLayout()
	Refresh()
end

local function Stop()
	events:UnregisterAllEvents()
	readyUntil, testUntil = nil, nil
	ns.Banner_Clear("buffs")
	ns.Buffs_StripHide()
end

local function Relayout()
	if module.active then
		ApplyLayout()
		Refresh()
	end
end

-- The same position as the `frame` default below.
local function ResetPosition()
	db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = "TOP", "TOP", 0, -160
	Relayout()
end

ns.EditMode_Register({
	name = "Buff reminders",
	frame = ns.Buffs_StripFrame,
	refresh = Refresh,
	saved = function()
		local point, _, relPoint, x, y = ns.Buffs_StripFrame():GetPoint()
		db.frame.point, db.frame.relPoint, db.frame.x, db.frame.y = point, relPoint, x, y
	end,
	module = "buffs",
	options = { "scale" },
	reset = ResetPosition,
})

local function Scale(v)
	return ("%.1f"):format(v)
end

local function WhereChoices()
	return {
		{ value = "raid", text = "Raids" },
		{ value = "group", text = "And dungeons" },
		{ value = "all", text = "And delves" },
	}
end

-- Settings preview (Panel/Preview.lua): the sample strip at the chosen size, also while the strip is off (the
-- preview answers its switch as on, to show what turning it on gives).
local function StripPreview(host, get)
	return ns.Buffs_DrawSample(host, SampleItems(), get("scale"))
end

local WHERE_TIP = "Where to check: raids only, raids and dungeons, or delves too. Ready checks outside an "
	.. "instance check everything that's on."

local options = {
	{ type = "header", label = "Reminder strip" },
	{ type = "checkbox", key = "strip", label = "Show missing buffs as icons", onChange = Refresh,
		preview = ns.Preview_When("strip", StripPreview),
		tooltip = "In dungeons, raids and delves and during ready checks, out of combat: an icon for each buff you're missing. Point at one to see what it is." },
	{ type = "slider", key = "scale", label = "Size", min = 0.6, max = 1.6, step = 0.1, format = Scale,
		onChange = Relayout, parent = "strip", preview = ns.Preview_When("strip", StripPreview) },
	{ type = "button", label = "Position", text = "Reset", onClick = ResetPosition, parent = "strip",
		tooltip = "Move the icons back to the top middle of the screen. Blizzard's Edit Mode moves them too." },
	{ type = "button", label = "Preview", text = "Show", onClick = Test,
		tooltip = "Show a sample strip for a few seconds." },
	{ type = "header", label = "What to check" },
}

-- A check's switch and its "Where" choice under it.
local function AddCheck(key, label, tooltip)
	options[#options + 1] = { type = "checkbox", key = key .. ".on", label = label, onChange = Refresh,
		tooltip = tooltip }
	options[#options + 1] = { type = "dropdown", key = key .. ".where", label = "Where", choices = WhereChoices,
		onChange = Refresh, parent = key .. ".on", tooltip = WHERE_TIP }
end

AddCheck("food", "Food buff", "Well Fed from food or a feast. Only at max level.")
AddCheck("flask", "Flask", "A flask from this expansion. Only at max level.")
AddCheck("rune", "Augment rune", "An augment rune from this expansion. Only at max level.")
AddCheck("weapon", "Weapon oil or stone",
	"A temporary weapon enchant (oil, whetstone, weightstone, or a class imbue) on each weapon that takes one. Not for rogues: Rogue Poisons covers them. Only at max level.")
AddCheck("group", "Your group buff",
	"The buff your class brings (Arcane Intellect, Power Word: Fortitude, Battle Shout, Mark of the Wild, Skyfury, Blessing of the Bronze) when you or anyone in your group nearby lacks it.")

for _, row in ipairs({
	{ type = "header", label = "Buff check" },
	{ type = "checkbox", key = "check.onEnter", label = "When entering an instance",
		tooltip = "List what's missing in chat a few seconds after entering a dungeon, raid or delve." },
	{ type = "checkbox", key = "check.onReadyCheck", label = "On ready checks" },
	{ type = "checkbox", key = "check.banner", label = "Banner and sound",
		tooltip = "Also show what's missing as a banner with a warning sound. Off: chat and the icons only." },
	{ type = "button", label = "Buff check", text = "Run", onClick = Why,
		tooltip = "List every check and what it found." },
}) do
	options[#options + 1] = row
end

module = ns.RegisterModule({
	key = "buffs",
	name = "Buff reminders",
	category = "class",
	icon = FOOD_ICON,
	summary = "Icons for missing food, flask, rune, weapon oil and your group buff before the pull.",
	description = "In dungeons, raids and delves and during ready checks, out of combat: an icon for each buff you're missing (food, flask, augment rune, weapon oil or stone, and the group buff your class brings when someone in the group lacks it). A buff check in chat when you enter and on ready checks.",
	enabledByDefault = true,
	toasts = "Buff check (banners)",
	defaults = {
		strip = true,
		scale = 1,
		frame = { point = "TOP", relPoint = "TOP", x = 0, y = -160 }, -- ResetPosition repeats it
		-- Each check: on, and where ("raid" | "group": raids and dungeons | "all": delves too).
		food = { on = true, where = "all" },
		flask = { on = true, where = "group" },
		rune = { on = true, where = "raid" },
		weapon = { on = true, where = "group" },
		group = { on = true, where = "all" },
		check = { onEnter = true, onReadyCheck = true, banner = false },
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "why", "list each buff check and what it found", Why },
		{ "test", "show the reminder strip with sample icons", Test },
		{ "check", "run the buff check now (chat)", function()
			Check(true)
		end },
	},
	options = options,
})
