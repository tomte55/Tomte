local addonName, ns = ...

-- Gear Check, part 4: the upgrade plugin and the corner arrows in Baganator's bags (own upgrades, maybe-upgrades,
-- upgrades for alts). Gear.lua calls GearBaganator_Register when the module starts; the verdicts are Context.lua's.

local UI = ns.UI

local function DB()
	return ns.gearDB
end

local IsGearLink = ns.Gear_IsGearLink
local Evaluate = ns.Gear_EvaluateLink

local BAGANATOR_ID = "tomte_gear"
local BAGANATOR_ALT_ID = "tomte_gear_alt"
local BAGANATOR_MAYBE_ID = "tomte_gear_maybe"
local ALT_ROLE = "accent" -- the color of Tomte's map markers, so it can't pass for your own arrow
local MAYBE_ROLE = "warning" -- the tooltip's "Can't judge" color

local function RegisterBaganator()
	local module = ns.gearModule
	if module.baganatorRegistered or not (Baganator and Baganator.API and Baganator.API.RegisterUpgradePlugin) then
		return
	end
	module.baganatorRegistered = true
	local function IsUpgrade(link)
		if not (module.active and DB().baganator and link) then
			return false
		end
		-- Baganator asks for every item on every refresh. Anything that isn't gear stops here: Evaluate would build a
		-- context and read the item's tooltip, and items without stats are never cached, so they'd be read every time.
		if not IsGearLink(link) then
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
		if not (module.active and DB().baganator and DB().maybeBaganator and link) or not IsGearLink(link) then
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
		if not (module.active and DB().altBaganator and DB().altUpgrades ~= "off" and link) or not IsGearLink(link) then
			return false
		end
		local own = Evaluate(link)
		if ns.Gear_IsCleanUpgrade(own) or (DB().baganator and DB().maybeBaganator and ns.Gear_IsMaybeUpgrade(own)) then
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

ns.GearBaganator_Register = RegisterBaganator
