local addonName, ns = ...

-- Pet care (World of Warcraft: Forever only): pure logic (no WoW API calls; unit-tested in tests/test_petcare.lua). Which
-- food to feed and the words for the pet's state. PetCare.lua reads the game and owns the button.

local HAPPY = 3 -- C_PetInfo.GetPetHappiness: 1 unhappy, 2 content, 3 happy (Blizzard_FrameXML/PetHappiness.lua)
-- The vanilla rule for food a pet still gets something from: at most this many levels under it. Not confirmed on Forever,
-- so food below it is still used when there's nothing else.
local FOOD_LEVEL_RANGE = 30

function ns.PetCare_WantsFood(happiness)
	return happiness ~= nil and happiness < HAPPY
end

-- foods: { { bag, slot, itemID, ilvl, count } } the pet eats. The lowest that's still in range, so the good food stays; else
-- the highest there is. Lowest bag and slot wins a tie, so the choice doesn't jump around.
function ns.PetCare_PickFood(foods, petLevel)
	local inRange, fallback
	local floor = (petLevel or 0) - FOOD_LEVEL_RANGE
	for _, food in ipairs(foods) do
		local ilvl = food.ilvl or 0
		if ilvl >= floor and (not inRange or ilvl < (inRange.ilvl or 0)) then
			inRange = food
		end
		if not fallback or ilvl > (fallback.ilvl or 0) then
			fallback = food
		end
	end
	return inRange or fallback
end

-- The secure button's macro. spellName: Feed Pet in the client's language.
function ns.PetCare_Macro(spellName, food)
	return ("/cast %s\n/use %d %d"):format(spellName, food.bag, food.slot)
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

-- "Meat, Fish" for the toast when no food is in the bags.
function ns.PetCare_DietText(diet)
	return #diet > 0 and table.concat(diet, ", ") or nil
end
