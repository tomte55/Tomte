local addonName, ns = ...

-- Pet Battles: everything during a battle. Remembers which NPC you talked to (no battle API says who you fight),
-- uses Read.lua's readers (round counters, the interpreter's api, the plain tables for the matchup rules) and draws
-- the battle helper: the enemy team, what hits it hard, your best pet, the strategy's steps and the Next move button.
-- Next move does one action per press (a click, or its key from WoW's Key Bindings menu); nothing acts on its own.
-- After a battle it refills the leveling slot and shows the Heal button (both live in Journal.lua), waiting for
-- combat to end when needed.

local UI = ns.UI
local ALLY, ENEMY = 1, 2
local NPC_FRESH = 60 -- seconds a talked-to NPC counts as "the one you're fighting"
local AFTER_SECONDS = 5 -- how long after the after-battle work a journal update still redoes it (see afterUntil)
local WIDTH = 460
local CELL = 38
local LINE_H = 20
local STEPS_H = 150
local CELLS_Y = 40 -- top of the pet icons, below the title row and the "best" mark
-- Top middle, under the VS bar: the bottom of the screen is the ability bar and the pet swap panel that opens above it.
local DEFAULT_POINT = { "TOP", "TOP", 0, -150 }
local FAMILY_TEX = "|TInterface\\PetBattles\\PetIcon-%s:%d:%d:0:0:128:256:63:102:129:168|t"
local SKIP_ICON = "Interface\\Icons\\Ability_Rogue_Sprint"
local NONE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local module, db
local last = { npc = nil, at = 0, name = nil } -- last NPC talked to or targeted
local ctx -- this battle: { npc, wild, pvp, team, script, scriptErr }
local frame, nextButton
local afterBattleDone = true
local afterUntil -- the journal may get the battle's results after PET_BATTLE_CLOSE: redo the checks until then
local afterInCombat -- the battle ended in combat: do the after-battle work when it's over

local IsSecret = ns.IsSecret
local Cache, ResetCache = ns.PetsRead_Cache, ns.PetsRead_ResetCache
local api, ReadSide = ns.PetsRead_Api, ns.PetsRead_Side

local function InBattle()
	return C_PetBattles.IsInBattle()
end

-- Families ---------------------------------------------------------------------------------------------------

function ns.Pets_FamilyName(t)
	return t and _G["BATTLE_PET_NAME_" .. t] or "?"
end

function ns.Pets_FamilyIcon(t, size)
	local suffix = t and PET_TYPE_SUFFIX and PET_TYPE_SUFFIX[t]
	if not suffix then
		return ""
	end
	size = size or 14
	return FAMILY_TEX:format(suffix, size, size)
end

local chart
function ns.Pets_Chart()
	if not chart then
		local n = C_PetJournal.GetNumPetTypes and C_PetJournal.GetNumPetTypes() or 10
		chart = ns.Pets_TypeChart(C_PetBattles.GetAttackModifier, n)
	end
	return chart
end

-- The NPC you're facing ------------------------------------------------------------------------------------------

local function NPCFromUnit(unit)
	local guid = UnitGUID(unit)
	if not guid or IsSecret(guid) or UnitIsPlayer(unit) then
		return nil
	end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" then
		return nil
	end
	return tonumber(id)
end

local function Remember(unit)
	if InCombatLockdown() then
		return
	end
	local npc = NPCFromUnit(unit)
	if npc then
		local name = UnitName(unit)
		last.npc, last.at, last.name = npc, GetTime(), (not IsSecret(name)) and name or nil
	end
	return npc
end

function ns.PetsBattle_LastNPC()
	if last.npc and GetTime() - last.at <= NPC_FRESH then
		return last.npc, last.name
	end
	return nil
end

-- UI ---------------------------------------------------------------------------------------------------------

local function Cell(parent)
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(CELL, CELL + 6)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(CELL, CELL)
	c.icon:SetPoint("TOP")
	c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	c.ring = CreateFrame("Frame", nil, c)
	c.ring:SetPoint("TOPLEFT", c.icon, -2, 2)
	c.ring:SetPoint("BOTTOMRIGHT", c.icon, 2, -2)
	UI.Border(c.ring, "accent", 1)
	c.family = c:CreateFontString(nil, "OVERLAY")
	UI.SetFont(c.family, "body", 10)
	c.family:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 3, -3)
	c.bar = UI.Bar(c, 3)
	c.bar:SetPoint("TOPLEFT", c.icon, "BOTTOMLEFT", 0, -2)
	c.bar:SetPoint("TOPRIGHT", c.icon, "BOTTOMRIGHT", 0, -2)
	c.mark = UI.Text(c, 12, "success", "label")
	c.mark:SetPoint("BOTTOM", c.icon, "TOP", 0, 2)
	c:EnableMouse(true)
	c:SetScript("OnEnter", function(self)
		if not self.tip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.tip[1], UI.Color("heading"))
		for k = 2, #self.tip do
			GameTooltip:AddLine(self.tip[k], 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", GameTooltip_Hide)
	return c
end

local function SetCell(c, p, active, mark)
	if not p then
		c:Hide()
		return
	end
	c:Show()
	c.icon:SetTexture(p.icon or NONE_ICON)
	c.icon:SetDesaturated(p.dead)
	c.ring:SetShown(active)
	c.family:SetText(ns.Pets_FamilyIcon(p.type, 16))
	c.bar:SetValue(p.health / math.max(p.maxHealth, 1))
	c.bar:SetColorRole(p.dead and "danger" or (p.health / math.max(p.maxHealth, 1) < 0.35 and "warning" or "success"))
	c.mark:SetText(mark or "")
	c.tip = { p.name or "?", ns.Pets_FamilyName(p.type) .. "  " .. p.health .. " / " .. p.maxHealth }
end

local function Families(list)
	local out = {}
	for _, t in ipairs(list) do
		out[#out + 1] = ns.Pets_FamilyIcon(t, 17) .. " " .. ns.Pets_FamilyName(t)
	end
	return table.concat(out, "   ")
end

local function SavePoint()
	db.advisor.point = UI.TopLeftPoint(frame)
end

local function Place()
	local p = db.advisor.point or DEFAULT_POINT
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	frame:SetScale(db.advisor.scale or 1)
end

local function ActionLabel(action)
	if not action then
		return NONE_ICON, "Nothing to do"
	end
	if action.kind == "ability" then
		local active = C_PetBattles.GetActivePet(ALLY)
		local _, name, icon = C_PetBattles.GetAbilityInfo(ALLY, active, action.slot)
		return icon or NONE_ICON, name or ("Ability " .. action.slot)
	elseif action.kind == "change" then
		return C_PetBattles.GetIcon(ALLY, action.pet) or NONE_ICON,
			"Swap to " .. (C_PetBattles.GetName(ALLY, action.pet) or ("#" .. action.pet))
	elseif action.kind == "skip" then
		return SKIP_ICON, "Pass"
	elseif action.kind == "trap" then
		local trap = C_PetBattles.GetPlayerTrapAbility()
		local _, name, icon = C_PetBattles.GetAbilityInfoByID(trap or 0)
		return icon or NONE_ICON, name or "Trap"
	elseif action.kind == "quit" then
		return NONE_ICON, "Forfeit"
	end
	return NONE_ICON, "Test: " .. tostring(action.text)
end

-- The key from WoW's Key Bindings menu (Tomte > Next pet battle move), if one is set.
local function KeyText()
	local key = GetBindingKey("CLICK TomtePetNext:LeftButton")
	return key and GetBindingText(key) or nil
end

local function Perform(action)
	if not action then
		return
	end
	if action.kind == "ability" then
		C_PetBattles.UseAbility(action.slot)
	elseif action.kind == "change" then
		C_PetBattles.ChangePet(action.pet)
	elseif action.kind == "skip" then
		C_PetBattles.SkipTurn()
	elseif action.kind == "trap" then
		C_PetBattles.UseTrap()
	elseif action.kind == "quit" then
		C_PetBattles.ForfeitGame()
	elseif action.kind == "test" then
		ns.Print("script: " .. tostring(action.text))
	end
end

local function ScriptAction()
	if not (ctx and ctx.script) then
		return nil
	end
	local ok, action = pcall(ns.PetScript_Next, ctx.script, api)
	if not ok then
		if not ctx.errorReported then -- Refresh runs on every health and aura change: report once per battle
			ctx.errorReported = true
			ns.errorHandler(action)
		end
		return nil
	end
	return action
end

local function NextOnClick()
	if not (module.active and InBattle() and ctx and ctx.script) then
		return
	end
	Perform(ScriptAction())
	-- A short wait, presumably so the battle state reflects the action before the button shows the next one.
	C_Timer.After(0.2, ns.PetsBattle_Refresh)
end

-- A plain Button, not a secure one: the pet battle actions need a hardware event but aren't protected. Its global
-- name is what the key binding clicks (Bindings.xml).
local function CreateNextButton(parent)
	local b = CreateFrame("Button", "TomtePetNext", parent)
	b:SetSize(36, 36)
	-- Down clicks only: a key binding's CLICK sends a down and an up, and one press must be one action.
	b:RegisterForClicks("AnyDown")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	UI.Border(b, "accent", 0.9)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b.label = UI.Text(parent, 14, "heading")
	b.label:SetPoint("TOPLEFT", b, "TOPRIGHT", 8, -1)
	b.label:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
	b.label:SetWordWrap(false)
	b.sub = UI.Text(parent, 12, "textMuted")
	b.sub:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -2)
	b.sub:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
	b.sub:SetWordWrap(false)
	b:SetScript("OnClick", NextOnClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Next move", UI.Color("heading"))
		GameTooltip:AddLine("Does what the strategy's script says for this turn. One press, one action.", 1, 1, 1, true)
		local key = KeyText()
		GameTooltip:AddLine(key and ("Key: " .. key) or "Set a key in Key Bindings > Tomte > Next pet battle move.", UI.RGB("textMuted"))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function Build()
	frame = CreateFrame("Frame", "TomtePetBattleHelper", UIParent)
	frame:SetSize(WIDTH, 100)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:Hide()
	UI.Panel(frame, { alpha = 0.8, subtle = true })

	frame.title = UI.Text(frame, 12, "textMuted", "label")
	frame.title:SetPoint("TOPLEFT", 10, -6)
	frame.title:SetText(ns.Spaced("Pet battle"))
	frame.foe = UI.Text(frame, 14, "heading")
	frame.foe:SetPoint("LEFT", frame.title, "RIGHT", 10, 0)
	frame.foe:SetPoint("RIGHT", frame, "RIGHT", -86, 0)
	frame.foe:SetWordWrap(false)
	frame.guide = UI.Button(frame, 60, "Guide")
	frame.guide:SetHeight(20)
	frame.guide:SetPoint("TOPRIGHT", -26, -3)
	frame.guide:SetScript("OnClick", function()
		if ctx and ctx.npc then
			ns.PetsGuides_ShowNPC(ctx.npc)
		end
	end)

	frame.enemyLabel = UI.Text(frame, 12, "textMuted", "label")
	frame.enemyLabel:SetPoint("TOPLEFT", 10, -CELLS_Y - 12)
	frame.enemyLabel:SetText("Enemy")
	frame.enemy = {}
	for i = 1, 3 do
		frame.enemy[i] = Cell(frame)
		frame.enemy[i]:SetPoint("TOPLEFT", 72 + (i - 1) * (CELL + 10), -CELLS_Y)
	end
	frame.allyLabel = UI.Text(frame, 12, "textMuted", "label")
	frame.allyLabel:SetPoint("TOPLEFT", 252, -CELLS_Y - 12)
	frame.allyLabel:SetText("You")
	frame.ally = {}
	for i = 1, 3 do
		frame.ally[i] = Cell(frame)
		frame.ally[i]:SetPoint("TOPLEFT", 296 + (i - 1) * (CELL + 10), -CELLS_Y)
	end

	frame.lines = {}
	for i = 1, 3 do
		local fs = UI.Text(frame, 14, "text")
		fs:SetPoint("TOPLEFT", 10, -CELLS_Y - CELL - 16 - (i - 1) * LINE_H)
		fs:SetPoint("RIGHT", -10, 0)
		fs:SetWordWrap(false)
		frame.lines[i] = fs
	end

	frame.script = CreateFrame("Frame", nil, frame)
	frame.script:SetHeight(44)
	frame.script:SetPoint("LEFT", 0, 0)
	frame.script:SetPoint("RIGHT", 0, 0)
	nextButton = CreateNextButton(frame.script)
	nextButton:SetPoint("TOPLEFT", 10, -4)

	frame.steps = CreateFrame("Frame", nil, frame)
	frame.steps:SetHeight(STEPS_H)
	frame.steps:SetPoint("LEFT", 0, 0)
	frame.steps:SetPoint("RIGHT", 0, 0)
	frame.steps.head = UI.Text(frame.steps, 12, "textMuted", "label")
	frame.steps.head:SetPoint("TOPLEFT", 10, -2)
	frame.steps.scroll = UI.Scroll(frame.steps)
	frame.steps.scroll:SetPoint("TOPLEFT", 10, -20)
	frame.steps.scroll:SetPoint("BOTTOMRIGHT", -16, 6)
	frame.steps.text = UI.Text(frame.steps.scroll.content, 13, "text", "chat")
	frame.steps.text:SetPoint("TOPLEFT")
	frame.steps.text:SetPoint("RIGHT")
	frame.steps.text:SetJustifyV("TOP")
	frame.steps.text:SetSpacing(2)
	frame.steps.scroll.onWidthChanged = function(width)
		frame.steps.text:SetWidth(width)
		frame.steps.scroll:SetContentHeight(frame.steps.text:GetStringHeight() + 4)
	end

	-- Drag by the title strip when the helper isn't locked (Edit Mode moves it too).
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not db.advisor.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePoint()
	end)

	frame.collapse = UI.CollapseButton(frame, function()
		return db.advisor.collapsed
	end, function()
		db.advisor.collapsed = not db.advisor.collapsed
		ns.PetsBattle_Refresh()
	end)
	Place()
end

local function SetLine(i, text, role)
	local fs = frame.lines[i]
	fs:SetText(text or "")
	UI.SetTextRole(fs, role or "text")
	fs:SetShown(text ~= nil)
	return text ~= nil
end

-- Lines of advice for the active enemy. Returns how many lines were used.
local function Advice(enemy, allies)
	local foe = enemy.pets[enemy.active]
	if not foe then
		return 0
	end
	local n = 0
	local c = ns.Pets_Chart()
	n = n + 1
	SetLine(n, "Hit it with:  " .. Families(ns.Pets_Strong(c, foe.type)), "text")
	-- Its attacks (unknown against players).
	local types, seen = {}, {}
	for _, a in ipairs(foe.abilities) do
		if a.type and not a.noHints and not seen[a.type] then
			seen[a.type] = true
			types[#types + 1] = a.type
		end
	end
	if #types > 0 then
		n = n + 1
		SetLine(n, "Its attacks:  " .. Families(types), "textMuted")
	end
	-- Swap advice, leveling pet, catch hint (one line, most useful first).
	local leveling = db.leveling.on and db.leveling.slot or nil
	local opts = { active = allies.active, leveling = leveling }
	local line, role
	if leveling and ctx and not ctx.pvp and allies.active == leveling and (api:Round(ALLY) or 0) >= 2 then
		line, role = "Swap your leveling pet out (it already gets the XP).", "warning"
	end
	if not line and ctx and not (allies.pets[allies.active] or {}).dead then
		local advice = ns.Pets_SwapAdvice(c, allies.pets, foe, opts)
		if advice then
			local p = allies.pets[advice.index]
			local why = {}
			if advice.info.strong > 0 then
				why[#why + 1] = "strong vs " .. ns.Pets_FamilyName(foe.type)
			end
			if advice.info.resists > 0 and advice.info.weakTo == 0 then
				why[#why + 1] = "resists its attacks"
			end
			line, role = ("Swap to %s?  %s"):format(p.name or "#" .. advice.index, table.concat(why, ", ")), "accent"
		end
	end
	if not line and ctx and ctx.wild and (foe.quality or 0) >= 3 and foe.species then
		local owned = C_PetJournal.GetNumCollectedInfo(foe.species)
		if (owned or 0) == 0 then
			line, role = "Not in your collection: catch it?", "success"
		end
	end
	if line then
		n = n + 1
		SetLine(n, line, role)
	end
	return n
end

local PREVIEW_SIDE = {
	active = 1,
	pets = {
		{ name = "Enemy pet", type = 8, health = 900, maxHealth = 1400, abilities = { { type = 3 } } },
		{ name = "Enemy pet", type = 5, health = 1400, maxHealth = 1400, abilities = {} },
		{ name = "Enemy pet", type = 10, health = 0, maxHealth = 1400, dead = true, abilities = {} },
	},
}

-- Shows, hides and fills the helper.
function ns.PetsBattle_Refresh()
	local editMode = ns.EditMode_Active()
	local battle = InBattle()
	local want = module.active and db.advisor.shown and (battle or editMode)
	if not want then
		if frame then
			frame:Hide()
		end
		return
	end
	if not frame then
		Build()
	end
	local enemy, allies
	if battle then
		enemy, allies = ReadSide(ENEMY), ReadSide(ALLY)
	else
		enemy, allies = PREVIEW_SIDE, PREVIEW_SIDE
	end
	local team = ctx and ctx.team
	frame.foe:SetText(battle and ((ctx and ctx.npc and ns.PetsStore_NPCName(ctx.npc))
		or (ctx and ctx.wild and "Wild pets") or (ctx and ctx.pvp and "PvP") or "") or "Edit Mode preview")
	frame.guide:SetShown(battle and ctx and ctx.npc ~= nil)

	local collapsed = db.advisor.collapsed
	local y = 26
	if collapsed then
		for i = 1, 3 do
			frame.enemy[i]:Hide()
			frame.ally[i]:Hide()
			frame.lines[i]:Hide()
		end
		frame.enemyLabel:Hide()
		frame.allyLabel:Hide()
		frame.script:Hide()
		frame.steps:Hide()
		frame:SetHeight(y)
		frame:Show()
		return
	end
	frame.enemyLabel:Show()
	frame.allyLabel:Show()

	local c = ns.Pets_Chart()
	local foe = enemy.pets[enemy.active]
	local best = foe and ns.Pets_Best(c, allies.pets, foe, {
		active = allies.active, leveling = db.leveling.on and db.leveling.slot or nil })
	for i = 1, 3 do
		SetCell(frame.enemy[i], enemy.pets[i], i == enemy.active)
		SetCell(frame.ally[i], battle and allies.pets[i] or nil, i == allies.active, i == best and "best" or nil)
	end
	y = CELLS_Y + CELL + 16
	for i = 1, 3 do
		frame.lines[i]:Hide()
	end
	local used = foe and Advice(enemy, allies) or 0
	for i = 1, used do
		frame.lines[i]:ClearAllPoints()
		frame.lines[i]:SetPoint("TOPLEFT", 10, -y - (i - 1) * LINE_H)
		frame.lines[i]:SetPoint("RIGHT", -10, 0)
	end
	y = y + used * LINE_H + 4

	-- Strategy: the Next move button and the steps.
	local hasScript = battle and ctx and ctx.script and db.runner.on
	frame.script:SetShown(hasScript or (battle and ctx and ctx.scriptErr ~= nil) or false)
	if frame.script:IsShown() then
		frame.script:ClearAllPoints()
		frame.script:SetPoint("TOPLEFT", 0, -y)
		frame.script:SetPoint("RIGHT")
		if hasScript then
			local icon, label = ActionLabel(ScriptAction())
			nextButton.icon:SetTexture(icon)
			nextButton:Show()
			local key = KeyText()
			nextButton.label:SetText(label .. (key and ("  " .. UI.Wrap("[" .. key .. "]", "textMuted")) or ""))
			nextButton.sub:SetText(team.name)
		else
			nextButton:Hide()
			nextButton.label:SetText(UI.Wrap("Script error: " .. ctx.scriptErr, "danger"))
			nextButton.sub:SetText(team.name)
		end
		y = y + 46
	end
	local notes = battle and team and team.notes ~= "" and team.notes or nil
	frame.steps:SetShown(db.advisor.steps and notes ~= nil)
	if frame.steps:IsShown() then
		frame.steps:ClearAllPoints()
		frame.steps:SetPoint("TOPLEFT", 0, -y)
		frame.steps:SetPoint("RIGHT")
		local author = ns.Pets_ParseAuthor(notes)
		frame.steps.head:SetText(ns.Spaced("Round " .. math.max(api:Round(nil), 1)) .. "   "
			.. UI.Wrap(author and ("Strategy by " .. author .. ", Xu-Fu's Pet Guides") or team.name, "textFaint"))
		local text = ns.Pets_CleanNotes(notes)
		if frame.steps.shownNotes ~= text then
			frame.steps.shownNotes = text
			frame.steps.text:SetText(text)
			frame.steps.scroll:SetScroll(0)
		end
		frame.steps.scroll:SetContentHeight(frame.steps.text:GetStringHeight() + 4)
		y = y + STEPS_H
	end
	frame:SetHeight(y + 4)
	frame:Show()
end

-- The battle -------------------------------------------------------------------------------------------------

local function EnemySpecies()
	local species = {}
	for i = 1, C_PetBattles.GetNumPets(ENEMY) or 0 do
		species[#species + 1] = C_PetBattles.GetPetSpeciesID(ENEMY, i)
	end
	return species
end

local function StartBattle(fresh)
	local wild = C_PetBattles.IsWildBattle()
	local npcBattle = not wild and C_PetBattles.IsPlayerNPC(ENEMY)
	ctx = { wild = wild, pvp = not wild and not npcBattle }
	if npcBattle then
		local npc, name = ns.PetsBattle_LastNPC()
		local species = EnemySpecies()
		if fresh and npc then
			ns.PetsStore_Learn(npc, species, name)
			local types = {}
			for i = 1, C_PetBattles.GetNumPets(ENEMY) or 0 do
				types[i] = C_PetBattles.GetPetType(ENEMY, i)
			end
			ns.PetsStore_SetTypes(npc, types)
		end
		ctx.npc = (fresh and npc) or db.cache.npc or ns.PetsStore_MatchSignature(species)
		db.cache.npc = ctx.npc
		ctx.team = ns.PetsStore_TeamFor(ctx.npc)
		if ctx.team then
			ctx.script, ctx.scriptErr = ns.PetsStore_Script(ctx.team)
		end
	end
	afterBattleDone, afterUntil, afterInCombat = false, nil, false
	if not frame then
		Build() -- the Next move button exists even while the helper is hidden
	end
	ns.PetsHeal_Hide()
	ns.PetsCard_Hide()
	ns.PetsBattle_Refresh()
end

-- Leveling refill and the Heal button. Safe to run more than once for the same battle.
local function AfterBattleWork()
	local name, why = ns.PetsJournal_RefillLeveling(db)
	if name then
		ns.Print(("leveling slot: %s is up next."):format(name))
	elseif why and not afterUntil then
		ns.Print("leveling slot: can't swap pets now: " .. why .. ".")
	end
	if db.heal.after and not InCombatLockdown() and ns.PetsJournal_TeamHurt() then
		ns.PetsHeal_ShowAfterBattle(frame)
	end
end

local function AfterBattle()
	if afterBattleDone or InBattle() then
		return
	end
	afterBattleDone = true
	ctx = nil
	ns.PetsBattle_Refresh()
	ns.PetsJournal_MarkDirty()
	if InCombatLockdown() then
		afterInCombat = true
		return
	end
	AfterBattleWork()
	afterUntil = GetTime() + AFTER_SECONDS
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

function events:GOSSIP_SHOW()
	local npc = Remember("npc")
	if npc and db.card.shown then
		ns.PetsCard_OnGossip(npc)
	end
end

function events:GOSSIP_CLOSED()
	ns.PetsCard_Hide()
end

function events:PLAYER_TARGET_CHANGED()
	Remember("target")
end

function events:PET_BATTLE_OPENING_START()
	ResetCache()
	StartBattle(true)
end

function events:PET_BATTLE_OPENING_DONE()
	ns.PetsBattle_Refresh()
end

function events:PET_BATTLE_PET_ROUND_RESULTS(round)
	local c = Cache()
	if round == c.round - 1 then -- fires twice when a pet dies
		return
	end
	c.round = round + 1
	c.rounds[ALLY] = (c.rounds[ALLY] or 0) + 1
	c.rounds[ENEMY] = (c.rounds[ENEMY] or 0) + 1
end

function events:PET_BATTLE_PET_CHANGED(owner)
	local c = Cache()
	if owner == ALLY or owner == ENEMY then
		c.rounds[owner] = 1
		local active = C_PetBattles.GetActivePet(owner)
		if active then
			c.played[owner .. ":" .. active] = true
		end
	end
	ns.PetsBattle_Refresh()
end

events.PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE = function()
	ns.PetsBattle_Refresh()
end
events.PET_BATTLE_HEALTH_CHANGED = events.PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE
events.PET_BATTLE_AURA_APPLIED = events.PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE
events.PET_BATTLE_AURA_CANCELED = events.PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE
events.PET_BATTLE_AURA_CHANGED = events.PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE

function events:PET_BATTLE_CLOSE()
	-- Fires twice; the second time the battle is over. The work waits a moment and runs once.
	C_Timer.After(0.5, AfterBattle)
end

function events:PLAYER_REGEN_DISABLED()
	ns.PetsHeal_OnCombat()
end

function events:PLAYER_REGEN_ENABLED()
	if not module.active then
		ns.PetsHeal_Disarm()
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	ns.PetsHeal_Ensure()
	if afterInCombat then
		afterInCombat = false
		AfterBattleWork()
		afterUntil = GetTime() + AFTER_SECONDS
	end
end

function events:PET_JOURNAL_LIST_UPDATE()
	ns.PetsJournal_MarkDirty()
	if afterUntil and GetTime() <= afterUntil and not InBattle() and not InCombatLockdown() then
		afterUntil = nil -- once: the battle's levels and health have arrived
		AfterBattleWork()
	end
	if ns.PetsHeal_Shown() then
		ns.PetsHeal_Refresh()
		if not ns.PetsJournal_TeamHurt() and not (ns.PetsCard_Shown and ns.PetsCard_Shown()) then
			ns.PetsHeal_Hide()
		end
	end
	if ns.PetsCard_Refresh then
		ns.PetsCard_Refresh()
	end
	if ns.PetsPage_Refresh then
		ns.PetsPage_Refresh()
	end
end
events.PET_JOURNAL_PETS_HEALED = events.PET_JOURNAL_LIST_UPDATE

-- The Heal button (and its key) keeps spell or bandage right while hidden too. Refresh skips itself in combat.
function events:SPELL_UPDATE_COOLDOWN()
	ns.PetsHeal_Refresh()
end
events.BAG_UPDATE_DELAYED = events.SPELL_UPDATE_COOLDOWN

local EVENTS = {
	"GOSSIP_SHOW", "GOSSIP_CLOSED", "PLAYER_TARGET_CHANGED", "PET_BATTLE_OPENING_START", "PET_BATTLE_OPENING_DONE",
	"PET_BATTLE_PET_ROUND_RESULTS", "PET_BATTLE_PET_CHANGED", "PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE",
	"PET_BATTLE_HEALTH_CHANGED", "PET_BATTLE_AURA_APPLIED", "PET_BATTLE_AURA_CANCELED", "PET_BATTLE_AURA_CHANGED",
	"PET_BATTLE_CLOSE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PET_JOURNAL_LIST_UPDATE",
	"PET_JOURNAL_PETS_HEALED", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
}

function ns.PetsBattle_Init(moduleDB, mod)
	db, module = moduleDB, mod
	ns.PetsRead_Init(db)
	if not db.cache then
		ResetCache()
	end
end

function ns.PetsBattle_Toggle(active)
	if active then
		for _, event in ipairs(EVENTS) do
			events:RegisterEvent(event)
		end
		ns.PetsHeal_Ensure() -- its key binding works from the start
		if InBattle() then -- a /reload mid-battle: the round counters come back from the saved cache
			StartBattle(false)
		end
	else
		events:UnregisterAllEvents()
		ctx = nil
		if not ns.PetsHeal_Disarm() then
			events:RegisterEvent("PLAYER_REGEN_ENABLED") -- turned off in combat: disarm the Heal key once it ends
		end
	end
	ns.PetsBattle_Refresh()
end

function ns.PetsBattle_ResetPosition()
	db.advisor.point = nil
	if frame then
		Place()
	end
end

function ns.PetsBattle_Relayout()
	if frame then
		Place()
	end
end

_G["BINDING_NAME_CLICK TomtePetNext:LeftButton"] = "Next pet battle move"

ns.EditMode_Register({
	name = "Pet battle helper",
	frame = function()
		return frame
	end,
	refresh = function()
		ns.PetsBattle_Refresh()
	end,
	saved = SavePoint,
})
