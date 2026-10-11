local addonName, ns = ...

-- Gear Check, part 2: the lines on item tooltips (verdict, reasons, rank, off-spec, gems, enchant, upgrades for other
-- characters). Contexts are in Context.lua; the module and the hook that calls OnItem are in Gear.lua.

local UI = ns.UI

local function DB()
	return ns.gearDB
end

local Context = ns.Gear_OwnContext
local SpecContext = ns.Gear_SpecContext
local OtherSpecs = ns.Gear_OtherSpecs
local IsGearLink = ns.Gear_IsGearLink
local Evaluate = ns.Gear_EvaluateLink

-- Verdict color keys (Data.lua) to theme roles.
-- Color codes are built when used: the theme is chosen on ADDON_LOADED.
local COLOR_ROLES = { green = "success", yellow = "warning", grey = "textMuted", red = "danger", orange = "warning" }
local function Label()
	return UI.Wrap("Gear:", "accent") .. " "
end
local function Reason()
	return "|c" .. UI.Hex("textMuted")
end
local MAX_REASONS = 3
local MAX_ALT_LINES = 2

-- This character's lines: verdict, reasons, rank, off-spec, gems, enchant.
local function OwnLines(tooltip, link, ctx, verdict, cand, equipped, Add)
	if verdict and not (verdict.kind == "downgrade" and not DB().showDowngrades) then
		local headline, color = ns.Gear_Headline(verdict)
		Add(headline, color)
		if DB().showReasons then
			for i = 1, math.min(#verdict.reasons, MAX_REASONS) do
				tooltip:AddLine(Reason() .. "   " .. verdict.reasons[i] .. "|r", nil, nil, nil, true)
			end
		end
		if ctx.source == "none" and verdict.kind ~= "notForYou" then
			tooltip:AddLine(Reason() .. ("   No weights for %s: item level only. /tomte gear import"):format(
				ctx.spec.name) .. "|r", nil, nil, nil, true)
		end
	end
	if verdict and verdict.kind == "notForYou" then
		return
	end

	local worn = ns.Gear_WornSlot(link, equipped)
	if DB().rank and worn and ns.Gear_Rankable(cand) then
		local pairSize = cand.equipLoc == "INVTYPE_FINGER" and 2 or 1 -- trinkets aren't ranked
		local others = {}
		local partner = pairSize == 2 and equipped[worn == 11 and 12 or 11]
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
				local text, color = ns.Gear_RankLine(spec.name, rank, pairSize, betterName)
				if text then
					Add(text, color)
				end
			end
		end
	end
	if DB().offspec and not worn then
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

	if DB().gemHints then
		local diamond = not ns.Gear_WearsGem(equipped, ctx.scales.diamondIDs) and ctx.scales.diamondName or nil
		local lines = ns.Gear_GemLines(cand, ctx.best, ctx.bestValue, worn ~= nil, ns.GearItems_GemStats,
			ctx.weights, ctx.primary, diamond)
		for _, line in ipairs(lines) do
			Add(line, worn and "orange" or "grey")
		end
	end
	if DB().enchantHints and worn and ns.Gear_MissingEnchant(worn, cand) then
		Add("Not enchanted", "orange")
	end
end

-- "Upgrade for Mira (Holy): +8.2%" for other characters, when the item can get to them (Alts.lua). A bag item is
-- found by its GUID for its exact bind state; else the tooltip's own bind line, else the item's bind type.
local function AltLines(link, data, Add)
	if DB().altUpgrades == "off" or not IsGearLink(link) then
		return
	end
	local location
	local guid = data and data.guid
	if guid and not ns.IsSecret(guid) and C_Item.GetItemLocation then
		-- pcall: a GUID the API can't resolve (or rejects) must mean no location, with bind state then from the
		-- tooltip lines, never a Lua error inside the tooltip hook.
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
	if not (ns.gearModule.active and tooltip.AddLine) then
		return
	end
	local compare = tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2
	if compare and not DB().compareTooltips then
		return
	end
	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	if not link or ns.IsSecret(link) then
		return
	end
	local labeled = false
	local function Add(text, color)
		local code = "|c" .. UI.Hex(COLOR_ROLES[color])
		tooltip:AddLine((labeled and "   " or Label()) .. code .. text .. "|r", nil, nil, nil, true)
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

ns.GearTooltip_OnItem = OnItem
