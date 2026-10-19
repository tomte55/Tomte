local addonName, ns = ...

-- Readiness checks: pure logic (no WoW API calls; unit-tested in tests/test_check.lua). The guards, chat lines and
-- banner are in Check.lua; Hunter Pets, Rogue Poisons and Durability check again on entering content.

local DELVE_DIFFICULTY = 208 -- GetInstanceInfo()'s difficultyID inside a delve, any tier

-- instanceType, difficultyID from GetInstanceInfo() -> "dungeon" | "raid" | "delve" | nil (open world,
-- battlegrounds, other scenarios)
function ns.Check_ContentKind(instanceType, difficultyID)
	if instanceType == "party" then
		return "dungeon"
	elseif instanceType == "raid" then
		return "raid"
	elseif instanceType == "scenario" and difficultyID == DELVE_DIFFICULTY then
		return "delve"
	end
	return nil
end
