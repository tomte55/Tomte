local addonName, ns = ...

-- Nameplates: reads the game for the pure rules in Data.lua. A unit's quest lines from its tooltip data, its
-- widget set, and whether nameplates may be decorated here at all. Every unit value may be secret in Midnight
-- (names, tooltip lines in combat): a secret value ends the read with "secret" and the caller keeps what it had.

local IsSecret = ns.IsSecret

-- Nameplates are decorated in the open world only. In dungeons, raids, delves and arenas Blizzard restricts
-- addons' access to units (friendly plates are forbidden, unit data turns secret), so the module stays out.
function ns.Plates_Allowed()
	local inInstance = IsInInstance()
	if inInstance then
		return false, "in an instance"
	end
	local restriction = Enum.AddOnRestrictionType
	if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and restriction and restriction.Map
		and C_RestrictedActions.IsAddOnRestrictionActive(restriction.Map) then
		return false, "on a restricted map"
	end
	return true
end

-- The nameplate of a unit token we may decorate: nil for forbidden plates and plates without a unit frame.
function ns.Plates_Plate(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or plate:IsForbidden() or not plate.UnitFrame then
		return nil
	end
	return plate
end

-- Plain quest lines (see ns.Plates_QuestState) of a unit's tooltip. Returns lines, or nil plus a reason:
-- "secret" when a value we need is secret right now, "none" when the game has no tooltip for the unit.
function ns.Plates_ReadQuestLines(unit)
	local data = C_TooltipInfo.GetUnit(unit)
	if not data or not data.lines or IsSecret(data.lines) then
		return nil, "none"
	end
	local LineType = Enum.TooltipDataLineType
	local myGUID = UnitGUID("player")
	local lines = {}
	for _, line in ipairs(data.lines) do
		local kind = line.type
		if IsSecret(kind) then
			return nil, "secret"
		end
		if kind == LineType.QuestTitle then
			lines[#lines + 1] = { kind = "title" }
		elseif kind == LineType.QuestPlayer then
			local guid = line.guid
			if IsSecret(guid) or IsSecret(myGUID) then
				return nil, "secret"
			end
			lines[#lines + 1] = { kind = "player", mine = guid ~= nil and guid == myGUID }
		elseif kind == LineType.QuestObjective then
			local text, completed = line.leftText, line.completed
			if IsSecret(text, completed) then
				return nil, "secret"
			end
			lines[#lines + 1] = { kind = "objective", text = text, completed = completed and true or false }
		end
	end
	return lines
end

-- True/false when the game says whether the unit is tied to one of your quests, nil when that's secret.
function ns.Plates_IsQuestUnit(unit)
	local related = C_QuestLog.UnitIsRelatedToActiveQuest(unit)
	if IsSecret(related) then
		return nil
	end
	return related and true or false
end

-- The unit's widget set ID, nil when it has none or it's secret.
function ns.Plates_WidgetSet(unit)
	local id = UnitWidgetSet(unit)
	if IsSecret(id) or type(id) ~= "number" or id == 0 then
		return nil
	end
	return id
end

-- True when a unit is a player character (never decorated with quest icons). nil when that's secret.
function ns.Plates_IsPlayer(unit)
	local isPlayer = UnitIsPlayer(unit)
	if IsSecret(isPlayer) then
		return nil
	end
	return isPlayer and true or false
end

-- True when two unit tokens are the same unit; false when unknown (secret).
function ns.Plates_SameUnit(a, b)
	local same = UnitIsUnit(a, b)
	if IsSecret(same) then
		return false
	end
	return same and true or false
end
