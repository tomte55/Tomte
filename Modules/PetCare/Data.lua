local addonName, ns = ...

-- Pet care (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in tests/test_petcare.lua). Which
-- food to feed and the words for the pet's state. PetCare.lua reads the game and owns the button.

local HAPPY = 3 -- C_PetInfo.GetPetHappiness: 1 unhappy, 2 content, 3 happy (Blizzard_FrameXML/PetHappiness.lua)
-- How much a feeding does by how far the food is under the pet's level, in classic WoW: 35 happiness a bite within about
-- 15 levels, 17 within about 25, 8 below that. Sources differ a little on the edges, and it isn't confirmed on Forever.
local FULL_RANGE, HALF_RANGE = 15, 25

ns.PETCARE_EAT_SECONDS = 20 -- one feeding: 10 bites over this long (classic WoW; not confirmed on Forever)

function ns.PetCare_WantsFood(happiness)
	return happiness ~= nil and happiness < HAPPY
end

-- "full", "half" or "little": how much a feeding of this level does for a pet of this level.
function ns.PetCare_FoodValue(ilvl, petLevel)
	local under = (petLevel or 0) - (ilvl or 0)
	if under <= FULL_RANGE then
		return "full"
	end
	return under <= HALF_RANGE and "half" or "little"
end

-- foods: { { bag, slot, itemID, ilvl, count } } the pet eats. The lowest that still does a full feeding, so better food
-- stays; else the highest there is, the most a feeding can do. Lowest bag and slot wins a tie, so the choice doesn't jump
-- around.
function ns.PetCare_PickFood(foods, petLevel)
	local full, highest
	for _, food in ipairs(foods) do
		local ilvl = food.ilvl or 0
		if ns.PetCare_FoodValue(ilvl, petLevel) == "full" and (not full or ilvl < (full.ilvl or 0)) then
			full = food
		end
		if not highest or ilvl > (highest.ilvl or 0) then
			highest = food
		end
	end
	return full or highest
end

-- The words under the button and their color role. s = { eatingLeft (seconds, nil when not eating), value (of the food),
-- fedBefore (fed since the pet was last happy) }.
function ns.PetCare_Label(s)
	if s.eatingLeft then
		return ("Eating: %ds"):format(math.ceil(s.eatingLeft)), "textMuted"
	end
	if s.value ~= "full" then
		return "Feed: weak food", "warning"
	end
	return s.fedBefore and "Still hungry: feed" or "Click to feed", "text"
end

-- The tooltip's line about the food, and its color role.
function ns.PetCare_FoodTip(value)
	if value == "half" then
		return "Low level for your pet: about half a feeding. Food nearer its level does more.", "warning"
	elseif value == "little" then
		return "Far too low for your pet: it barely helps. Food nearer its level does much more.", "warning"
	end
	return "Good food for your pet's level.", "textMuted"
end

-- "Unhappy", "Content", "Happy".
local MOODS = { "Unhappy", "Content", "Happy" }
function ns.PetCare_Mood(happiness)
	return MOODS[happiness]
end

-- Training points left to spend, 0 when none or unknown.
function ns.PetCare_TrainingLeft(total, used)
	return math.max((total or 0) - (used or 0), 0)
end

-- Pet training ---------------------------------------------------------------------------------------------------------

-- A Beast Training row as the reminder keeps it, nil for what can't be learned any more. GetTrainerServiceInfo's name,
-- serviceType and subtext ("(Rank 2)"), its required level, and GetTrainerServiceCost, which is training points here. A row that
-- costs nothing is left out: Forever can list what the pet already knows as "available" at 0 points, and training it says it's
-- already learned (seen in game; the list came back empty later).
function ns.PetCare_SlimTraining(name, serviceType, rank, level, cost)
	if not name or (serviceType ~= "available" and serviceType ~= "unavailable") or not cost or cost <= 0 then
		return nil
	end
	return { name = rank and rank ~= "" and (name .. " " .. rank) or name, level = level or 0, cost = cost or 0 }
end

-- What the pet can learn right now out of rows, with these points at this level.
function ns.PetCare_TrainingLearnable(rows, left, petLevel)
	local list = {}
	for _, row in ipairs(rows) do
		if row.cost <= left and row.level <= (petLevel or 0) then
			list[#list + 1] = row
		end
	end
	return list
end

-- What to tell the player. record: what Beast Training last showed for this pet { rows, seenLeft, seenLevel }, nil before
-- it's been opened. "ready": it can learn something. "unread": points, but nothing known about what they could buy.
-- nil: nothing to say, also after looking at these same points at this same level (you chose not to spend them).
function ns.PetCare_TrainingState(record, left, petLevel)
	if left <= 0 then
		return nil
	end
	if not record then
		return "unread"
	end
	if record.seenLeft == left and record.seenLevel == petLevel then
		return nil
	end
	return #ns.PetCare_TrainingLearnable(record.rows, left, petLevel) > 0 and "ready" or nil
end

-- The reminder's text for a state.
function ns.PetCare_TrainingText(state, left, rows, petLevel)
	if state == "unread" then
		return ("It has %d training points to spend."):format(left)
	end
	local names = {}
	for _, row in ipairs(ns.PetCare_TrainingLearnable(rows, left, petLevel)) do
		names[#names + 1] = row.name
	end
	return "It can learn: " .. table.concat(names, ", ") .. "."
end

-- "Meat, Fish" for the toast when no food is in the bags.
function ns.PetCare_DietText(diet)
	return #diet > 0 and table.concat(diet, ", ") or nil
end
