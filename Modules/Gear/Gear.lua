local addonName, ns = ...

-- Gear Check: an upgrade verdict on item tooltips (and Baganator's upgrade arrows) that only says "upgrade" when
-- nothing it can't value is at stake: set bonuses, embellishments, effects and unique limits are checked, and
-- items whose value is an effect are sent to a sim instead of guessed. Rules in Data.lua, advice (weights source,
-- gems, enchants, off-spec) in Advice.lua, built-in weights and gem IDs per expansion in Data/<Expansion>/Gear.lua
-- (picked by the character's content expansion, Scales.lua), item reading in Items.lua,
-- the character sheet button and panel in Sheet.lua, upgrades for other characters in Alts.lua.
-- Weights: imported Pawn string per character and spec > built-in for the spec > primary 1 / secondaries 0.5.

local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local UI = ns.UI
local PRIMARY_KEYS = { [1] = "STR", [2] = "AGI", [4] = "INT" } -- LE_UNIT_STAT_*
-- Verdict color keys (Data.lua) to theme roles.
local COLORS = {
	green = "|c" .. UI.Hex("success"), yellow = "|c" .. UI.Hex("warning"), grey = "|c" .. UI.Hex("textMuted"),
	red = "|c" .. UI.Hex("danger"), orange = "|c" .. UI.Hex("warning"),
}
local LABEL = UI.Wrap("Gear:", "accent") .. " "
local REASON = "|c" .. UI.Hex("textMuted")
local MAX_REASONS = 3
local BAGANATOR_ID = "tomte_gear"
local BAGANATOR_ALT_ID = "tomte_gear_alt"
local BAGANATOR_MAYBE_ID = "tomte_gear_maybe"
local ALT_ROLE = "accent" -- the color of Tomte's map markers, so it can't pass for your own arrow
local MAYBE_ROLE = "warning" -- the tooltip's "Can't judge" color
local MAX_ALT_LINES = 2

local module, db
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local _, classToken, classID = UnitClass("player")

local function SpecAt(index)
	local specID, name, _, icon, _, primaryStat = GetSpecializationInfo(index)
	if not specID or specID == 0 then
		return nil
	end
	return { index = index, id = specID, name = name, icon = icon, primary = PRIMARY_KEYS[primaryStat] }
end

local function Spec()
	local index = GetSpecialization()
	return index and SpecAt(index)
end

local function CharWeights()
	local guid = UnitGUID("player")
	db.weights[guid] = db.weights[guid] or {}
	return db.weights[guid]
end

-- Display season ID, nil when the game doesn't say (0 between seasons).
local function CurrentSeason()
	local id = C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID and C_SeasonInfo.GetCurrentDisplaySeasonID()
	return (id and id > 0) and id or nil
end

-- The evaluator context for a spec ({ id, name, primary }, index only for this character's own specs). guid, class
-- and level default to this character; another character's guid, class token and level judge for them (their
-- imported weights, their armor type, their content expansion's built-in set). ctx.scales is that set;
-- ctx.complete once the best gem is known (or the set has no gems).
local function ContextFor(spec, guid, class, level)
	if not (spec and spec.id and spec.primary) then
		return nil
	end
	local set = ns.Gear_ScalesForLevel(level)
	local ctx = ns.Gear_BuildContext(spec, guid or UnitGUID("player"), class or classToken, db.weights, set,
		ns.GearItems_Gems(set.gems))
	if ctx then
		ctx.scales = set
		ctx.complete = ctx.best ~= nil or #set.gems == 0
	end
	return ctx
end

-- This character's context, kept until RefreshBags (spec, level, weights, items arrived): Baganator and tooltips ask
-- for one per item. Not kept while the gems load (no best gem yet), like Alts.lua does.
local ownCtx
local function Context()
	local spec = Spec()
	if ownCtx and spec and ownCtx.spec.id == spec.id and ownCtx.scales == ns.Gear_ScalesForLevel() then
		return ownCtx
	end
	local ctx = ContextFor(spec)
	ownCtx = ctx and ctx.complete and ctx or nil
	return ctx
end

-- This character's context for another of its specs (tooltip rank and off-spec lines), kept like ownCtx.
local specCtx = {} -- [specID] = ctx
local function SpecContext(spec)
	local held = spec and specCtx[spec.id]
	if held and held.scales == ns.Gear_ScalesForLevel() then
		return held
	end
	local ctx = ContextFor(spec)
	if ctx and ctx.complete then
		specCtx[spec.id] = ctx
	end
	return ctx
end

-- The class's other specs, for off-spec verdicts.
local function OtherSpecs(current)
	local list = {}
	for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
		if i ~= current.index then
			list[#list + 1] = SpecAt(i)
		end
	end
	return list
end

-- verdict (nil when worn), candidate descriptor, equipped snapshot. Nothing while items load.
local function Evaluate(link, ctx)
	ctx = ctx or Context()
	local equipped = ctx and ns.GearItems_Equipped()
	local cand = equipped and ns.GearItems_Describe(link)
	if not cand then
		return nil
	end
	ctx.specOK = cand.specs == nil or cand.specs[ctx.spec.id] == true
	local verdict = ns.Gear_Evaluate(cand, equipped, ctx)
	ctx.specOK = nil -- the context is shared: don't let this item's answer reach the next one
	return verdict, cand, equipped
end

-- For other modules (World quests): the context to judge many items with (nil while Gear Check is off or there's
-- no spec), and verdict, headline, color key for an item link. Gear_Verdict is nil while Gear Check is off, items
-- load, there's no spec, or the item is worn. Pass one Gear_Context() when judging a batch.
function ns.Gear_Context()
	if not (module and module.active) then
		return nil
	end
	return Context()
end

function ns.Gear_Verdict(link, ctx)
	if not (module and module.active) then
		return nil
	end
	local v = Evaluate(link, ctx)
	if not v then
		return nil
	end
	return v, ns.Gear_Headline(v)
end

---------------------------------------------------------------------------------------------------------------
-- Tooltip

-- This character's lines: verdict, reasons, rank, off-spec, gems, enchant.
local function OwnLines(tooltip, link, ctx, verdict, cand, equipped, Add)
	if verdict and not (verdict.kind == "downgrade" and not db.showDowngrades) then
		local headline, color = ns.Gear_Headline(verdict)
		Add(headline, color)
		if db.showReasons then
			for i = 1, math.min(#verdict.reasons, MAX_REASONS) do
				tooltip:AddLine(REASON .. "   " .. verdict.reasons[i] .. "|r", nil, nil, nil, true)
			end
		end
		if ctx.source == "none" and verdict.kind ~= "notForYou" then
			tooltip:AddLine(REASON .. ("   No weights for %s: item level only. /tomte gear import"):format(
				ctx.spec.name) .. "|r", nil, nil, nil, true)
		end
	end
	if verdict and verdict.kind == "notForYou" then
		return
	end

	local worn = ns.Gear_WornSlot(link, equipped)
	if db.rank and worn and ns.Gear_Rankable(cand) then
		local pair = cand.equipLoc == "INVTYPE_FINGER" and 2 or 1 -- trinkets aren't ranked
		local others = {}
		local partner = pair == 2 and equipped[worn == 11 and 12 or 11]
		if partner then
			others[1] = partner
		end
		local bag = ns.GearItems_BagGear()
		local specs = { ctx.spec }
		for _, other in ipairs(OtherSpecs(ctx.spec)) do
			specs[#specs + 1] = other
		end
		for i, spec in ipairs(specs) do
			local sctx = i == 1 and ctx or SpecContext(spec)
			if sctx and (i == 1 or sctx.source ~= "none") and not ns.Gear_Unusable(cand, sctx) then
				local function Score(d)
					return ns.Gear_Score(d, sctx.weights, sctx.primary, sctx.gemValue)
				end
				local rank, better = ns.Gear_Rank(cand, worn, others, bag, sctx, Score)
				local betterName = better and C_Item.GetItemNameByID(better.itemID)
				local text, color = ns.Gear_RankLine(spec.name, rank, pair, betterName)
				if text then
					Add(text, color)
				end
			end
		end
	end
	if db.offspec and not worn then
		for _, other in ipairs(OtherSpecs(ctx.spec)) do
			local octx = SpecContext(other)
			if octx and octx.source ~= "none" then
				local line = ns.Gear_OffspecLine(other.name, (Evaluate(link, octx)))
				if line then
					Add(line, "green")
				end
			end
		end
	end

	if db.gemHints then
		local diamond = not ns.Gear_WearsGem(equipped, ctx.scales.diamondIDs) and ctx.scales.diamondName or nil
		local lines = ns.Gear_GemLines(cand, ctx.best, ctx.bestValue, worn ~= nil, ns.GearItems_GemStats,
			ctx.weights, ctx.primary, diamond)
		for _, line in ipairs(lines) do
			Add(line, worn and "orange" or "grey")
		end
	end
	if db.enchantHints and worn and ns.Gear_MissingEnchant(worn, cand) then
		Add("Not enchanted", "orange")
	end
end

-- "Upgrade for Mira (Holy): +8.2%" for other characters, when the item can get to them (Alts.lua). A bag item is
-- found by its GUID for its exact bind state; else the tooltip's own bind line, else the item's bind type.
local function AltLines(link, data, Add)
	if db.altUpgrades == "off" then
		return
	end
	local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
	if not (equipLoc and ns.Gear_Slots(equipLoc)) then
		return
	end
	local location
	local guid = data and data.guid
	if guid and not (issecretvalue and issecretvalue(guid)) and C_Item.GetItemLocation then
		local ok, loc = pcall(C_Item.GetItemLocation, guid)
		location = ok and loc or nil
	end
	if not ns.GearAlts_Route(link, location, data and data.lines) then
		return
	end
	local lines, more = ns.Gear_AltLines((ns.GearAlts_Upgrades(link)), MAX_ALT_LINES)
	for _, line in ipairs(lines) do
		Add(line, "green")
	end
	if more then
		Add(more, "grey")
	end
end

local function OnItem(tooltip, data)
	if not (module.active and tooltip.AddLine) then
		return
	end
	local compare = tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2
	if compare and not db.compareTooltips then
		return
	end
	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	if not link or (issecretvalue and issecretvalue(link)) then
		return
	end
	local labeled = false
	local function Add(text, color)
		tooltip:AddLine((labeled and "   " or LABEL) .. COLORS[color] .. text .. "|r", nil, nil, nil, true)
		labeled = true
	end
	local ctx = Context()
	local verdict, cand, equipped = Evaluate(link, ctx)
	if cand and ns.Gear_Slots(cand.equipLoc) then
		OwnLines(tooltip, link, ctx, verdict, cand, equipped, Add)
	end
	if not compare then -- comparison tooltips show what you wear: about you only
		AltLines(link, data, Add)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Chat hints: no weights (once per session and spec), built-in weights at max level (once per character and spec,
-- and again when the season moves past theirs), missing enchants and empty sockets when the character pane opens.

local noWeightsSaid = {}

-- This character's db.hinted table ([specID] = seen), with the old account-wide keys of its class moved in.
local function CharHinted()
	local guid = UnitGUID("player")
	if not db.hinted[guid] then
		local own = {}
		for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
			local spec = SpecAt(i)
			if spec then
				own[spec.id] = true
			end
		end
		ns.Gear_MigrateHinted(db.hinted, guid, own)
	end
	return db.hinted[guid]
end

-- The max level of the content expansion of level (nil: this character's).
local function MaxLevel(level)
	return ns.ContentMaxLevel(ns.ContentExpansion(level))
end

-- level: PLAYER_LEVEL_UP's new level (UnitLevel can lag behind it).
local function WeightsHint(level)
	if not module.active then
		return
	end
	local ctx = Context()
	if not ctx then
		return
	end
	local name = ctx.spec.name
	if ctx.source == "none" then
		if not noWeightsSaid[ctx.spec.id] then
			noWeightsSaid[ctx.spec.id] = true
			ns.Print(("Gear Check: no stat weights for %s, so item level decides. For better verdicts, sim stat "
				.. "weights on Raidbots and /tomte gear import."):format(name))
		end
		return
	end
	local hinted = CharHinted()
	level = level or UnitLevel("player")
	local kind, seen = ns.Gear_WeightsHint(ctx.source, ctx.scales, hinted[ctx.spec.id], CurrentSeason(), level,
		MaxLevel(level))
	if kind == "max" then
		ns.Print(("%s is max level: sim %s on Raidbots for weights that fit your gear, then /tomte gear import.")
			:format(UnitName("player"), name))
	elseif kind == "stale" then
		ns.Print(("Gear Check: the built-in weights for %s are from %s and may be out of date. Sim on Raidbots "
			.. "and /tomte gear import."):format(name, ctx.scales.seasonName))
	end
	if kind then
		hinted[ctx.spec.id] = seen
	end
end

local lastAudit

local function AuditHint()
	if not (module.active and db.enchantHints) then
		return
	end
	local equipped = ns.GearItems_Equipped()
	if not equipped then
		return
	end
	local text = ns.Gear_AuditText(ns.Gear_Audit(equipped))
	if text and text ~= lastAudit then
		ns.Print("Gear Check: " .. text .. ". Hover the item for details.")
	end
	lastAudit = text
end

---------------------------------------------------------------------------------------------------------------
-- Baganator

local function RefreshBags()
	ownCtx = nil
	wipe(specCtx)
	if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh()
	end
end

local function RegisterBaganator()
	if module.baganatorRegistered or not (Baganator and Baganator.API and Baganator.API.RegisterUpgradePlugin) then
		return
	end
	module.baganatorRegistered = true
	local function IsUpgrade(link)
		if not (module.active and db.baganator and link) then
			return false
		end
		-- Baganator asks for every item on every refresh. Anything that isn't gear stops here: Evaluate would build a
		-- context and read the item's tooltip, and items without stats are never cached, so they'd be read every time.
		local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
		if not (equipLoc and ns.Gear_Slots(equipLoc)) then
			return false
		end
		return ns.Gear_IsCleanUpgrade(Evaluate(link))
	end
	-- The upgrade plugin only feeds Baganator's "upgrade" search and category; the arrow is a corner widget. Items
	-- still loading say false here, and GearItems_OnReady refreshes the bags once they've arrived.
	Baganator.API.RegisterUpgradePlugin("Tomte Gear Check", BAGANATOR_ID, IsUpgrade)
	if not Baganator.API.RegisterCornerWidget then
		return
	end
	-- Bigger than Blizzard's bag arrow, with a dark copy behind it so it reads on bright icons. role: theme color to
	-- tint with (the arrow is desaturated first so the tint is the color), nil for the atlas's own.
	local function Arrow(itemButton, role)
		local widget = CreateFrame("Frame", nil, itemButton)
		widget:SetSize(22, 24)
		widget.padding = 0.5
		local shadow = widget:CreateTexture(nil, "ARTWORK")
		shadow:SetAtlas("bags-greenarrow")
		shadow:SetVertexColor(0, 0, 0, 0.9)
		shadow:SetPoint("TOPLEFT", 1.5, -1.5)
		shadow:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
		local arrow = widget:CreateTexture(nil, "OVERLAY")
		arrow:SetAtlas("bags-greenarrow")
		arrow:SetAllPoints()
		if role then
			arrow:SetDesaturated(true)
			arrow:SetVertexColor(UI.Color(role))
		end
		return widget
	end
	Baganator.API.RegisterCornerWidget("Tomte Gear Check", BAGANATOR_ID, function(_, details)
		return IsUpgrade(details.itemLink)
	end, function(itemButton)
		return Arrow(itemButton)
	end, { corner = "top_left", priority = 1 })
	-- Maybe an upgrade: stats say so, but there's an effect to sim or a warning. Never the same item as the clean
	-- arrow above, and before the alt arrow so a maybe for you wins over an alt's upgrade.
	Baganator.API.RegisterCornerWidget("Tomte Gear Check: maybe an upgrade", BAGANATOR_MAYBE_ID, function(_, details)
		local link = details.itemLink
		if not (module.active and db.baganator and db.maybeBaganator and link) then
			return false
		end
		local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
		if not (equipLoc and ns.Gear_Slots(equipLoc)) then
			return false
		end
		return ns.Gear_IsMaybeUpgrade(Evaluate(link))
	end, function(itemButton)
		return Arrow(itemButton, MAYBE_ROLE)
	end, { corner = "top_left", priority = 2 })
	-- Upgrade for an alt. Baganator shows only the first widget of a corner that says yes (its array order), so
	-- after the arrows above it never shows with them; the check here also covers them being in different
	-- corners. Items still loading say false, like the arrow above, and are asked again on GearItems_OnReady.
	Baganator.API.RegisterCornerWidget("Tomte Gear Check: upgrade for an alt", BAGANATOR_ALT_ID, function(_, details)
		local link = details.itemLink
		if not (module.active and db.altBaganator and db.altUpgrades ~= "off" and link) then
			return false
		end
		local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
		if not (equipLoc and ns.Gear_Slots(equipLoc)) then
			return false
		end
		local own = Evaluate(link)
		if ns.Gear_IsCleanUpgrade(own) or (db.baganator and db.maybeBaganator and ns.Gear_IsMaybeUpgrade(own)) then
			return false -- an upgrade or maybe one for you: the arrows above win
		end
		if not ns.GearAlts_Route(link, details.itemLocation, nil, details.isBound) then
			return false
		end
		return #(ns.GearAlts_Upgrades(link)) > 0
	end, function(itemButton)
		return Arrow(itemButton, ALT_ROLE)
	end, { corner = "top_left", priority = 2 })
end

---------------------------------------------------------------------------------------------------------------
-- Events

function events:PLAYER_EQUIPMENT_CHANGED()
	ns.GearItems_InvalidateEquipped()
	RefreshBags()
	ns.GearSheet_Refresh()
end

-- Enchanting, socketing or upgrading worn gear changes its link: read the worn gear again, once per burst (the
-- event also fires for new bag items).
local inventoryQueued
local wornLinks = {}

local function WornChanged()
	local changed = false
	for slot = 1, 19 do
		local link = GetInventoryItemLink("player", slot) or false
		if wornLinks[slot] ~= link then
			wornLinks[slot], changed = link, true
		end
	end
	return changed
end

function events:UNIT_INVENTORY_CHANGED()
	if inventoryQueued then
		return
	end
	inventoryQueued = true
	C_Timer.After(0.5, function()
		inventoryQueued = false
		if module.active and WornChanged() then
			ns.GearItems_InvalidateEquipped()
			RefreshBags()
			ns.GearSheet_Refresh()
		end
	end)
end

-- Modules start on ADDON_LOADED, before the inventory has arrived: read worn gear and bags again once in the world.
function events:PLAYER_ENTERING_WORLD()
	ns.GearItems_InvalidateEquipped()
	ns.GearItems_InvalidateBags()
	RefreshBags()
	ns.GearSheet_Refresh()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unit)
	if unit == "player" then
		RefreshBags()
		WeightsHint()
		ns.GearSheet_Refresh()
	end
end

function events:BAG_UPDATE_DELAYED()
	ns.GearItems_InvalidateBags()
end

function events:PLAYER_LEVEL_UP(level)
	ns.GearItems_ClearCache()
	RefreshBags()
	ns.GearSheet_Refresh()
	WeightsHint(level)
	-- UnitLevel (and so the red "Requires Level" lines) can lag behind the event: read everything again once it's
	-- caught up.
	C_Timer.After(2, function()
		if module.active then
			ns.GearItems_ClearCache()
			RefreshBags()
			ns.GearSheet_Refresh()
		end
	end)
end

function events:GET_ITEM_INFO_RECEIVED()
	ns.GearItems_InfoReceived()
end

ns.GearItems_OnReady = function()
	if module.active then
		RefreshBags()
		ns.GearSheet_Refresh()
		if ns.AltsSend_OnGearReady then
			ns.AltsSend_OnGearReady() -- the mailbox's "Gear for" groups
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Weights: import dialog and commands

local SIM_STEPS = {
	"How to check gear the tooltip can't judge (Raidbots Top Gear, free):",
	"  1. Type /simc and press Ctrl+C to copy the text it shows.",
	"  2. Open raidbots.com/simbot/topgear in a browser and paste it into the big box.",
	"  3. Tick the items you're unsure about (it lists your bags), then press Run Top Gear.",
	"  4. The result at the top is the best set to wear. Equip what it lists.",
}

local WEIGHT_STEPS = {
	"How to get stat weights that fit your gear (Raidbots Stat Weights, free):",
	"  1. Type /simc and press Ctrl+C to copy the text it shows.",
	"  2. Open raidbots.com/simbot/stats in a browser, paste it into the big box and press Run Stat Weights.",
	"  3. In the result, copy the Pawn string and paste it into the import box (/tomte gear import).",
}

local function PrintSteps(steps)
	for _, line in ipairs(steps) do
		print(line)
	end
	if not (C_AddOns.IsAddOnLoaded("Simulationcraft")) then
		print("  (/simc needs the SimulationCraft addon, which isn't loaded.)")
	end
end

local function PrintSimSteps()
	PrintSteps(SIM_STEPS)
end

local function PrintWeights()
	local ctx = Context()
	if not ctx then
		ns.Print("Gear Check: no specialization yet.")
		return
	end
	if ctx.source == "none" then
		ns.Print(("Gear Check (%s): no stat weights. Main stat 1.0, secondary stats 0.5, so higher item level "
			.. "wins. Sim stat weights on Raidbots and /tomte gear import."):format(ctx.spec.name))
	else
		local parts = {}
		for key, value in pairs(ctx.weights) do
			parts[#parts + 1] = ("%s %.2f"):format(key, value)
		end
		table.sort(parts)
		ns.Print(("Gear Check (%s): %s - %s"):format(ctx.spec.name, ns.Gear_SourceText(ctx.source, ctx.label),
			table.concat(parts, ", ")))
	end
	if ctx.best then
		print(("  Best gem: %s (%s)"):format(ctx.best.name, ns.Gear_StatLabel(ctx.best.stats)))
	end
	print(("  Built-in set: %s. Season ID: %s."):format(ns.Gear_ScalesName(ctx.scales, ns.ContentExpansion()),
		tostring(CurrentSeason())))
end

-- Panel row label: where the current spec's weights come from.
local function SourceLabel()
	local ctx = module.active and db and Context()
	if not ctx then
		return "Weights in use"
	end
	local source = ctx.source == "imported" and "imported" or ns.Gear_SourceText(ctx.source, ctx.label)
		or "none, item level decides"
	return ("%s: %s"):format(ctx.spec.name, source)
end

local function ClearWeights()
	local ctx = Context()
	if ctx then
		CharWeights()[ctx.spec.id] = nil
		ns.GearAlts_Invalidate()
		local after = ctx.scales.specs[ctx.spec.id] and "the built-in weights" or "item level"
		ns.Print(("Gear Check: imported weights for %s cleared, back to %s."):format(ctx.spec.name, after))
		RefreshBags()
		ns.GearSheet_Refresh()
	end
end

local dialog

local function Import(text)
	local ctx = Context()
	if not ctx then
		return "No specialization yet."
	end
	local parsed, err = ns.Gear_ParsePawn(strtrim(text or ""))
	if not parsed then
		return err
	end
	if parsed.class ~= classToken or parsed.spec ~= ctx.spec.index then
		return ("That string is for another class or spec. You're %s right now."):format(ctx.spec.name)
	end
	CharWeights()[ctx.spec.id] = { name = parsed.name, weights = parsed.weights }
	ns.GearAlts_Invalidate()
	ns.Print(("Gear Check: imported \"%s\" for %s."):format(parsed.name, ctx.spec.name))
	RefreshBags()
	ns.GearSheet_Refresh()
	return nil
end

local function BuildDialog()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(480, 230)
	f:SetPoint("CENTER", 0, 120)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	UI.Panel(f)

	f.title = UI.Text(f, 15, "heading", "title")
	f.title:SetPoint("TOPLEFT", 16, -14)
	f.help = UI.Text(f, 12, "textMuted")
	f.help:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
	f.help:SetPoint("RIGHT", -16, 0)
	f.help:SetJustifyH("LEFT")
	f.help:SetWordWrap(true)
	f.help:SetText("Optional. On raidbots.com choose Stat Weights, paste your /simc text, run it, then copy the "
		.. "Pawn string from the result and paste it here.")

	local box = CreateFrame("EditBox", nil, f)
	box:SetMultiLine(true)
	box:SetAutoFocus(true)
	UI.SetFont(box, "body", 12)
	UI.SetTextRole(box, "text")
	box:SetTextInsets(6, 6, 6, 6)
	box:SetPoint("TOPLEFT", f.help, "BOTTOMLEFT", 0, -10)
	box:SetPoint("RIGHT", -16, 0)
	box:SetHeight(80)
	UI.Surface(box, 0.35)
	box:SetScript("OnEscapePressed", function()
		f:Hide()
	end)
	f.box = box

	f.error = UI.Text(f, 12, "danger")
	f.error:SetPoint("BOTTOMLEFT", 16, 18)
	f.error:SetPoint("RIGHT", -200, 0)
	f.error:SetJustifyH("LEFT")
	f.error:SetWordWrap(true)

	local cancel = UI.Button(f, 80, "Cancel")
	cancel:SetPoint("BOTTOMRIGHT", -16, 12)
	cancel:SetScript("OnClick", function()
		f:Hide()
	end)
	local ok = UI.Button(f, 80, "Import")
	ok:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
	ok:SetScript("OnClick", function()
		local err = Import(box:GetText())
		if err then
			f.error:SetText(err)
		else
			f:Hide()
		end
	end)
	f:Hide()
	return f
end

local function OpenImport()
	local ctx = Context()
	if not ctx then
		ns.Print("Gear Check: no specialization yet.")
		return
	end
	dialog = dialog or BuildDialog()
	dialog.title:SetText("Import stat weights for " .. ctx.spec.name)
	dialog.box:SetText("")
	dialog.error:SetText("")
	dialog:Show()
end

local function Command(fn)
	return function()
		if not module.active then
			ns.Print("Gear Check is off.")
			return
		end
		fn()
	end
end

-- Next up "Sim on Raidbots": this character, built-in weights, max level. Not now hides it like any other source.
local function NextSim()
	local ctx = Context()
	if not (ctx and ns.Gear_SimSuggested(ctx.source, UnitLevel("player"), MaxLevel())) then
		return {}
	end
	return { {
		key = "gearsim:" .. ctx.spec.id,
		text = ("Sim %s on Raidbots"):format(ctx.spec.name),
		why = "Built-in weights are a guide; your own sim fits your gear",
		icon = ctx.spec.icon,
		hint = "Click: how to sim, and the import box",
		onClick = function()
			PrintSteps(WEIGHT_STEPS)
			OpenImport()
		end,
	} }
end

-- Hidden (/tomte gear specs): every class's specs as the game reports them, against the built-in set of this
-- character's content expansion. Lines marked "check" are a missing spec or a different main stat.
local function PrintSpecs()
	local seen, bad = {}, 0
	local scales = ns.Gear_ScalesForLevel()
	ns.Print(("Gear Check specs (ID, name, role, main stat) against the built-in set %s:"):format(
		ns.Gear_ScalesName(scales, ns.ContentExpansion())))
	for cid = 1, GetNumClasses() do
		local info = C_CreatureInfo.GetClassInfo(cid)
		for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(cid) or 0 do
			local specID, name, _, _, role, primaryStat = GetSpecializationInfo(i, false, false, nil, nil, nil, cid)
			if specID and specID ~= 0 then
				seen[specID] = true
				local main = PRIMARY_KEYS[primaryStat]
				local scale = scales.specs[specID]
				local problem = not scale and "no built-in weights"
					or (main and not scale.weights[main]) and "built-in has another main stat" or nil
				bad = bad + (problem and 1 or 0)
				print(("  |c%s%d %s %s, %s, %s%s|r"):format(UI.Hex(problem and "warning" or "textMuted"), specID,
					name or "?", info and info.className or cid, tostring(role), tostring(main),
					problem and (": check, " .. problem) or ""))
			end
		end
	end
	for specID in pairs(scales.specs) do
		if not seen[specID] then
			bad = bad + 1
			print("  " .. UI.Wrap(("%d is in the built-in set but the game has no such spec: check"):format(specID), "warning"))
		end
	end
	ns.Print(bad == 0 and "every spec matches the built-in set." or (bad .. " to check."))
end

-- ns.Gear_Context (above, nil while Gear Check is off) is for the character sheet panel and the upgrade reveal too.
-- For judging gear for another character: ns.Gear_ContextFor({ id, name, primary }, guid, classToken, level).
ns.Gear_ContextFor = ContextFor
-- Another character's context from Alts' stored snapshot (chars[guid]: specID, spec, primary, class token); nil
-- until their spec has been read. Their level picks their built-in set (content expansion); whether they can wear an
-- item is Gear_AltVerdict's.
function ns.Gear_ContextForChar(char)
	return ContextFor(ns.Gear_CharSpec(char), char.guid, char.class, char.level)
end
ns.Gear_EvaluateLink = Evaluate
ns.Gear_OpenImport = OpenImport
ns.Gear_ClearWeights = ClearWeights
ns.Gear_PrintSimSteps = PrintSimSteps

---------------------------------------------------------------------------------------------------------------

local function Start()
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	ns.GearItems_InvalidateBags()
	if not module.tooltipHooked then
		module.tooltipHooked = true -- post-calls can't be removed; OnItem checks module.active
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	end
	RegisterBaganator()
	if not module.paneHooked then
		module.paneHooked = true -- like the tooltip hook: AuditHint checks module.active
		EventUtil.ContinueOnAddOnLoaded("Blizzard_UIPanels_Game", function()
			CharacterFrame:HookScript("OnShow", AuditHint)
		end)
	end
	ns.GearItems_InvalidateEquipped()
	RefreshBags()
	ns.GearSheet_Init()
	ns.GearReveal_Start(db)
	C_Timer.After(ns.inWorld and 0 or 8, WeightsHint) -- at login, after the chat flood
end

local function Stop()
	events:UnregisterAllEvents()
	ns.GearReveal_Stop()
	if dialog then
		dialog:Hide()
	end
	RefreshBags()
	ns.GearSheet_Refresh()
end

module = ns.RegisterModule({
	key = "gear",
	uses = {
		{ addon = "Baganator", why = "upgrade arrows on your bag items", without = "no upgrade arrows in bags" },
		{ addon = "Simulationcraft", why = "the /simc export for Raidbots Top Gear", without = "no /simc export" },
	},
	home = {
		{ kind = "quick", key = "reveal", order = 3, name = "Reveal upgrades", open = function()
			ns.GearReveal_ShowBags()
		end },
		{ kind = "next", key = "nextsim", name = "Sim on Raidbots", score = 30,
			description = "This character is max level and uses built-in stat weights: a Raidbots sim fits its gear "
				.. "better.",
			candidates = NextSim },
	},
	name = "Gear Check",
	category = "Gear",
	description = "Says on each item's tooltip whether it's an upgrade, and why not when it isn't: wrong armor or "
		.. "main stat, breaks your tier set, loses an embellishment or effect, unique limits. Trinkets and items "
		.. "with effects are marked to sim instead of guessed. Also: upgrades for your other specs, the best gem "
		.. "for empty sockets, and missing enchants. Can mark upgrades in Baganator and reveal new upgrades as a moment "
		.. "with a click-to-equip toast. Warbound and Bind on Equip gear also says which of your other characters "
		.. "it's an upgrade for.",
	enabledByDefault = true,
	defaults = {
		showReasons = true,
		showDowngrades = true,
		compareTooltips = false,
		baganator = true,
		maybeBaganator = true,
		offspec = true,
		rank = true,
		gemHints = true,
		enchantHints = true,
		weights = {}, -- [playerGUID][specID] = { name, weights = { AGI = 1, ... } }
		hinted = {}, -- [playerGUID][specID] = which built-in weights hint was shown ("max" or "stale:<season>";
		-- "builtin" from before, which was per spec only: [specID] = ..., moved to a character by CharHinted)
		sheetButton = true,
		sheetOpen = false, -- the panel next to the character sheet
		reveal = true,
		revealToast = true,
		revealMinPct = 2,
		altUpgrades = "all", -- all | max | off: other characters judged on tooltips, Baganator and the mailbox
		altBaganator = true,
		altMail = true,
	},
	init = function(moduleDB)
		db = moduleDB
		ns.gearDB = moduleDB
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "sim", "how to check an item with Raidbots Top Gear", PrintSimSteps },
		{ "import", "paste Raidbots stat weights for your current spec", Command(OpenImport) },
		{ "weights", "show the stat weights in use and where they come from", Command(PrintWeights) },
		{ "clear", "remove the imported weights for your current spec", Command(ClearWeights) },
		{ "upgrades", "reveal the clean upgrades already in your bags", function()
			ns.GearReveal_ShowBags()
		end },
		{ "specs", "every spec's ID and main stat against the built-in weights", PrintSpecs, hidden = true },
	},
	options = {
		{ type = "header", label = "Tooltip" },
		{ type = "checkbox", key = "showReasons", label = "Show reasons",
			tooltip = "Up to three short lines under the verdict, e.g. \"Breaks your 4-set\"." },
		{ type = "checkbox", key = "showDowngrades", label = "Show downgrades" },
		{ type = "checkbox", key = "compareTooltips", label = "Also on comparison tooltips",
			tooltip = "The tooltips of your equipped items that appear next to the hovered one." },
		{ type = "checkbox", key = "offspec", label = "Upgrades for your other specs",
			tooltip = "\"Also an upgrade for Marksmanship +4%\" when an item is a clean upgrade for another spec "
				.. "with weights (imported or built-in)." },
		{ type = "checkbox", key = "rank", label = "Rank on worn items",
			tooltip = "On items you wear: \"your best\" or \"your second best\" (rings) against your bags, per spec "
				.. "with weights, or \"bag has better\". Stats only, so trinkets and items with effects aren't ranked." },
		{ type = "checkbox", key = "gemHints", label = "Gem advice",
			tooltip = "The best gem for empty sockets under your weights, and a hint on your worn items when a "
				.. "socketed gem is clearly worse." },
		{ type = "checkbox", key = "enchantHints", label = "Missing enchants",
			tooltip = "\"Not enchanted\" on worn items that take an enchant, and a chat line when you open the "
				.. "character pane and something is missing." },
		{ type = "checkbox", key = "sheetButton", label = "Button on the character sheet", onChange = function()
			ns.GearSheet_Refresh()
		end, tooltip = "A Gear button under the trinkets that opens a panel with your stat weights, best gem and "
			.. "missing enchants and sockets." },
		{ type = "header", label = "Bags" },
		{ type = "checkbox", key = "baganator", label = "Mark upgrades in Baganator", onChange = RefreshBags,
			tooltip = "Only clean upgrades get the arrow. In Baganator's settings (Icons), \"Tomte Gear Check\" is a "
				.. "corner icon (the arrow) and an upgrade source (the upgrade search and category)." },
		{ type = "checkbox", key = "maybeBaganator", label = "Mark maybe-upgrades in Baganator", onChange = RefreshBags,
			tooltip = "An orange arrow on gear whose stats say upgrade but that needs checking: a trinket or effect to "
				.. "sim, same item level with different stats, or a warning like breaking your set. Not in the upgrade "
				.. "search. In Baganator's settings (Icons) it's \"Tomte Gear Check: maybe an upgrade\"." },
		{ type = "header", label = "Upgrades for alts" },
		{ type = "dropdown", key = "altUpgrades", label = "Upgrades for alts", onChange = function()
			ns.GearAlts_Invalidate()
			RefreshBags()
		end, choices = function()
			return { { value = "all", text = "All characters" }, { value = "max", text = "Max level only" },
				{ value = "off", text = "Off" } }
		end, tooltip = "\"Upgrade for Mira (Holy): +8.2%\" on gear that can get to another character (warbound, or Bind "
			.. "on Equip and not bound yet), judged with what they wore, their spec, level and stat weights when you "
			.. "last played them. Only clean upgrades. Characters not played for 60 days are left out. Needs Alts." },
		{ type = "checkbox", key = "altBaganator", label = "Mark alt upgrades in Baganator", onChange = RefreshBags,
			tooltip = "A small blue arrow on gear that's an upgrade for another character and not for you (your own "
				.. "upgrades keep the gold arrow). In Baganator's settings (Icons) it's \"Tomte Gear Check: upgrade for an "
				.. "alt\"." },
		{ type = "checkbox", key = "altMail", label = "Gear for alts at the mailbox",
			tooltip = "In Send to alt's \"For your alts\" panel: a \"Gear for Mira\" group with the Bind on Equip "
				.. "upgrades for them. Warbound ones go through the Warband bank instead: \"Deposit for alts\" at the "
				.. "bank puts them there. Needs Alts' \"For your alts\" at the mailbox." },
		{ type = "header", label = "Upgrade reveal" },
		{ type = "checkbox", key = "reveal", label = "Reveal new upgrades",
			tooltip = "When gear that's new to your bags (loot, quest rewards, the vault, mail) is a clean upgrade, show "
				.. "it as a moment. Choose banner or cinematic under Moments > Gear upgrade. Items taken out of a bank "
				.. "don't count." },
		{ type = "slider", key = "revealMinPct", label = "Smallest upgrade", min = 0, max = 10, step = 0.5,
			format = function(value)
				return ("%g%%"):format(value)
			end,
			tooltip = "Upgrades below this are left alone (gear for an empty slot always counts)." },
		{ type = "checkbox", key = "revealToast", label = "Equip toast",
			tooltip = "A toast with the upgrade: click it to equip the item, right-click to dismiss. Not in combat." },
		{ type = "header", label = "Stat weights" },
		{ type = "button", label = SourceLabel, text = "Show", onClick = Command(PrintWeights),
			tooltip = "Imported weights win, then the built-in ones (every spec: sims for damage and tanks, guide "
				.. "priority for healers), else main stat 1.0 and secondaries 0.5. Show prints them in chat." },
		{ type = "button", label = "Import for your current spec", text = "Import", onClick = Command(OpenImport),
			tooltip = "Raidbots stat weights fit your character better than the built-in ones." },
		{ type = "button", label = "Remove for your current spec", text = "Remove", onClick = Command(ClearWeights),
			confirm = "Remove the imported stat weights for your current spec?" },
		{ type = "button", label = "How to sim an item", text = "Show", onClick = PrintSimSteps,
			tooltip = "Prints the Raidbots Top Gear steps in chat." },
	},
})
ns.gearModule = module
