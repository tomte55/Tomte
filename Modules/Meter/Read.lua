local addonName, ns = ...

-- DPS meter: reads the game's own damage meter (C_DamageMeter, retail and World of Warcraft: Forever). Its sessions keep
-- counting whether or not Blizzard's meter window is on. In combat a source's name and amounts are secret: they go
-- straight to font strings and status bars, never compared or added up here (warcraft.wiki.gg API_C_DamageMeter).

-- Whether the game has a damage meter for addons to read; second: why not, in its words.
function ns.MeterRead_Available()
	if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
		return false, "This client has no damage meter."
	end
	if C_DamageMeter.IsDamageMeterAvailable then
		local ok, reason = C_DamageMeter.IsDamageMeterAvailable()
		if not ok then
			return false, reason
		end
	end
	return true
end

-- The ranking: { sources = { { name, classFilename, total, perSecond, isLocalPlayer } } best first, max (the top total),
-- mine (your place, or nil) }. overall: the whole session instead of the current fight; healing: healing done instead
-- of damage done. The total gives the bars (every source over the same fight, so its share is its share of the
-- amount per second); amountPerSecond the number.
function ns.MeterRead_Ranking(overall, healing)
	local sessionType = overall and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
	local meterType = healing and Enum.DamageMeterType.HealingDone or Enum.DamageMeterType.DamageDone
	local session = C_DamageMeter.GetCombatSessionFromType(sessionType, meterType)
	local ranking = { sources = {}, max = session and session.maxAmount or 0 }
	for i, source in ipairs(session and session.combatSources or {}) do
		ranking.sources[i] = {
			name = source.name,
			classFilename = source.classFilename,
			total = source.totalAmount,
			perSecond = source.amountPerSecond,
			isLocalPlayer = source.isLocalPlayer,
		}
		if source.isLocalPlayer then
			ranking.mine = i
		end
	end
	return ranking
end
