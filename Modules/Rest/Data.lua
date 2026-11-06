local addonName, ns = ...

-- Eat and drink (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in tests/test_rest.lua). What an
-- item is, which one to use and what a press does. Rest.lua reads the game and owns the button. See
-- docs/superpowers/specs/2026-11-06-tomte-forever-rest-and-chat-groups.md.

ns.REST_FOOD_SPELL, ns.REST_DRINK_SPELL, ns.REST_BANDAGE_SPELL = 433, 430, 746 -- Food, Drink, First Aid: one ID names every rank
ns.REST_WELL_FED = 19705
ns.REST_BANDAGED = 11196 -- the Recently Bandaged debuff

-- "food", "drink", "bandage" or nil, from the name of the spell an item casts. names: those spells' names in this client.
function ns.Rest_ItemKind(spellName, names)
	if not spellName then
		return nil
	end
	if spellName == names.food then
		return "food"
	elseif spellName == names.drink then
		return "drink"
	elseif spellName == names.bandage then
		return "bandage"
	end
	return nil
end

-- The one to use from items ({ { itemID, level, buff } }): plain food before buff food the player may be saving, then the
-- highest level, then the first (the bags' order), so the choice doesn't jump around. nil: none.
function ns.Rest_Pick(items)
	local best
	for _, item in ipairs(items) do
		if not best then
			best = item
		elseif (best.buff and not item.buff) or (best.buff == item.buff and (item.level or 0) > (best.level or 0)) then
			best = item
		end
	end
	return best
end

-- What a press does now. s = { blocked (combat, dead, mounted...), health, mana (0..1, mana nil for a class without it),
-- manaUnknown (has mana, but the game won't say how much), healthAt, manaAt (0..1, the settings), eating, drinking, bandaged,
-- food, drink, bandage (item IDs or nil) }. health is nil on Forever, where the game hides it from addons: a press there
-- means the player wants to recover, so it counts as low. The same for mana that can't be read.
-- Returns { uses = { item IDs }, text, role, icon = the first use }; text nil: nothing to say.
function ns.Rest_Plan(s)
	local plan = { uses = {} }
	if s.blocked then
		return plan
	end
	local lowHealth = s.health == nil or s.health < s.healthAt
	local lowMana = s.manaUnknown or (s.mana ~= nil and s.mana < s.manaAt)
	local ate, drank, wrapped, noFood, noDrink = false, false, false, false, false
	if lowHealth and not s.eating then
		if s.food then
			plan.uses[#plan.uses + 1] = s.food
			ate = true
		elseif s.bandage and not s.bandaged then
			plan.uses[#plan.uses + 1] = s.bandage
			wrapped = true
		elseif not s.bandaged then
			noFood = true
		end
	end
	if lowMana and not s.drinking then
		if s.drink then
			plan.uses[#plan.uses + 1] = s.drink
			drank = true
		else
			noDrink = true
		end
	end
	if ate and drank then
		plan.text, plan.role = "Eat and drink", "text"
	elseif ate then
		plan.text, plan.role = "Eat", "text"
	elseif drank then
		plan.text, plan.role = "Drink", "text"
	elseif wrapped then
		plan.text, plan.role = "Bandage", "text"
	elseif noFood then
		plan.text, plan.role = "No food", "warning"
	elseif noDrink then
		plan.text, plan.role = "No drink", "warning"
	end
	plan.icon = plan.uses[1]
	return plan
end

-- A curve's points for the game to turn a hidden share (0..1) into the button's opacity: 1 below `at`, 0 from there up.
function ns.Rest_CurvePoints(at)
	return { { 0, 1 }, { at, 1 }, { at + 0.001, 0 }, { 1, 0 } }
end

-- The secure button's macro: one line per item, or nothing.
function ns.Rest_Macro(uses)
	local lines = {}
	for i, itemID in ipairs(uses) do
		lines[i] = ("/use item:%d"):format(itemID)
	end
	return table.concat(lines, "\n")
end

-- Whether a supply just dropped to the low count: was above it and now isn't, and there is a limit.
function ns.Rest_JustLow(before, now, limit)
	return limit > 0 and before ~= nil and before > limit and now <= limit
end
