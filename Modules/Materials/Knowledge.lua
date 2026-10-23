local addonName, ns = ...

-- Material uses: unspent profession knowledge on the Professions book (Blizzard_ProfessionsBook, load-on-demand).
-- Under each primary profession's skill bar a line says how much specialization knowledge is left to spend, and the
-- profession's spell buttons say it on their tooltip. Read from the specialization trees (C_ProfSpecs + C_Traits),
-- which answer without the profession window open. Rules in Data.lua, registered in Materials.lua.

local REPAINT_DELAY = 0.2 -- seconds: TRAIT_TREE_CURRENCY_INFO_UPDATED comes once per tab, paint once after them

local UI = ns.UI
local Secret = ns.IsSecret

-- The module's event bus (Materials.lua uses it too).
local events = ns.NewEvents()
ns.Materials_Events = events
local OWNER = "knowledge"

local db
local active = false
local waiting, hooked = false, false
local labels = {} -- [1 or 2] = the FontString under PrimaryProfession<n>'s skill bar
local owners = {} -- [spell button] = 1 or 2: which profession a tooltip owner belongs to
local skillLines = {} -- ["<base>:<name>"] = expansion skill line or false, per session (cleared on skill changes)
local pending = false

local function Readable(v)
	return v ~= nil and not Secret(v)
end

-- The expansion skill line shown for the profession at GetProfessions() index.
local function SkillLineFor(index)
	local _, _, _, _, _, _, base, _, _, _, name = GetProfessionInfo(index)
	if not Readable(base) then
		return nil
	end
	local key = tostring(base) .. ":" .. tostring(name)
	if skillLines[key] == nil then
		local candidates = {}
		for _, id in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines() or {}) do
			local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(id)
			if info then
				candidates[#candidates + 1] = { id = id, name = info.professionName, parent = info.parentProfessionID,
					spec = C_ProfSpecs.SkillLineHasSpecialization(id) }
			end
		end
		skillLines[key] = ns.Materials_PickSkillLine(candidates, base, name) or false
	end
	return skillLines[key] or nil
end

local function Unspent(skillLine)
	local configID = C_ProfSpecs.GetConfigIDForSkillLine(skillLine)
	local tabIDs = C_ProfSpecs.GetSpecTabIDsForSkillLine(skillLine)
	if not (configID and configID ~= 0 and tabIDs and #tabIDs > 0) then
		return nil
	end
	local tabs = {}
	for _, treeID in ipairs(tabIDs) do
		local root = C_ProfSpecs.GetRootPathForTab(treeID)
		local quantities = {}
		for _, c in ipairs(C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {}) do
			if Readable(c.quantity) then
				quantities[c.traitCurrencyID] = c.quantity
			end
		end
		tabs[#tabs + 1] = { currency = root and C_ProfSpecs.GetSpendCurrencyForPath(root), quantities = quantities }
	end
	return ns.Materials_KnowledgeSum(tabs)
end

-- The line for primary profession 1 or 2, or nil.
local function TextFor(slot)
	local index = select(slot, GetProfessions())
	local skillLine = index and SkillLineFor(index)
	return skillLine and ns.Materials_KnowledgeText(Unspent(skillLine))
end

local function On()
	return active and db and db.knowledge
end

local function Paint()
	local shown = ProfessionsBookFrame and ProfessionsBookFrame:IsShown()
	for slot = 1, 2 do
		local label = labels[slot]
		if label then
			local text = On() and shown and TextFor(slot)
			label:SetText(text or "")
			label:SetShown(text and true or false)
		end
	end
end

local function PaintSoon()
	if pending then
		return
	end
	pending = true
	C_Timer.After(REPAINT_DELAY, function()
		pending = false
		if ProfessionsBookFrame and ProfessionsBookFrame:IsShown() then
			Paint()
		end
	end)
end

-- Spell tooltips of the book's profession buttons get the same line (a tooltip post-call, so it survives the
-- button's tooltip refreshes). Does nothing while off.
local function OnSpellTooltip(tooltip)
	if not On() or not tooltip.GetOwner then
		return
	end
	local slot = owners[tooltip:GetOwner()]
	local text = slot and TextFor(slot)
	if text then
		tooltip:AddLine(UI.Wrap(text, "accent"))
	end
end

local function Hook()
	if hooked or not (ProfessionsBookFrame_Update and PrimaryProfession1 and PrimaryProfession2) then
		return
	end
	hooked = true
	for slot, frame in ipairs({ PrimaryProfession1, PrimaryProfession2 }) do
		local label = UI.Text(frame, 11, "accent", "label")
		label:SetPoint("TOPLEFT", frame.statusBar, "BOTTOMLEFT", 0, -4)
		label:Hide()
		labels[slot] = label
		for _, button in ipairs({ frame.SpellButton1, frame.SpellButton2 }) do
			if button then
				owners[button] = slot
			end
		end
	end
	hooksecurefunc("ProfessionsBookFrame_Update", Paint)
	if ProfessionsBookFrame:IsShown() then
		Paint()
	end
end

events:On(OWNER, "TRAIT_TREE_CURRENCY_INFO_UPDATED", PaintSoon)
events:On(OWNER, "TRAIT_CONFIG_UPDATED", PaintSoon)
events:On(OWNER, "SKILL_LINES_CHANGED", function()
	wipe(skillLines)
	PaintSoon()
end)

function ns.MaterialsKnowledge_Init(moduleDB)
	db = moduleDB
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnSpellTooltip)
end

function ns.MaterialsKnowledge_Toggle(on)
	active = on
	if on then
		events:Watch(OWNER, "TRAIT_TREE_CURRENCY_INFO_UPDATED")
		events:Watch(OWNER, "TRAIT_CONFIG_UPDATED")
		events:Watch(OWNER, "SKILL_LINES_CHANGED")
		if not waiting then
			waiting = true
			EventUtil.ContinueOnAddOnLoaded("Blizzard_ProfessionsBook", Hook)
		end
	else
		events:UnwatchAll(OWNER)
	end
	if hooked then
		Paint()
	end
end

-- The setting changed: paint the open book again.
function ns.MaterialsKnowledge_Refresh()
	if hooked then
		Paint()
	end
end
