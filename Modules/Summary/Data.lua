local addonName, ns = ...

-- Expansion summary: pure logic (no WoW API calls; unit-tested in tests/test_summary.lua). Turns what the Weekly
-- board's readers return (ns.Weekly_ReadLive, ns.Weekly_ReadFactions, ns.WeeklyRaids_Read) into the rows the page,
-- the minimap button's tooltip and the rail draw. Page in Page.lua, registered in Summary.lua.

-- Vault: per track { key, label, slots, unlocked, total, nextSlot }, and the totals over all tracks.
-- vault = { [track key] = { { progress, threshold } } }; tracks = ns.WEEKLY_TRACKS ({ key, label }).
function ns.Summary_Vault(vault, tracks)
	local rows, unlocked, total = {}, 0, 0
	for _, track in ipairs(tracks or {}) do
		local slots = vault and vault[track.key] or {}
		local row = { key = track.key, label = track.label, slots = slots, unlocked = 0, total = #slots }
		for i, s in ipairs(slots) do
			if (s.threshold or 0) > 0 and (s.progress or 0) >= s.threshold then
				row.unlocked = row.unlocked + 1
			elseif not row.nextSlot then
				row.nextSlot = i
			end
		end
		unlocked, total = unlocked + row.unlocked, total + row.total
		rows[#rows + 1] = row
	end
	return { rows = rows, unlocked = unlocked, total = total }
end

-- "Raid 1/3 · Dungeons 0/3 · World 2/3" (unlocked slots per track); nil without tracks.
function ns.Summary_VaultLine(v)
	local parts = {}
	for _, row in ipairs(v.rows) do
		if row.total > 0 then
			parts[#parts + 1] = ("%s %d/%d"):format(row.label, row.unlocked, row.total)
		end
	end
	return #parts > 0 and table.concat(parts, " · ") or nil
end

-- Raids: one row per raid, "Normal 3/8 · Heroic 1/8" over the difficulties with a kill this week.
-- raids = { { id, name, mapID, bosses = { { name, encounterID } } } }; isKilled(mapID, encounterID, difficultyID);
-- difficulties = ns.WEEKLY_RAID_DIFFICULTIES ({ id, name }). Returns { { id, name, text, any, bosses } }.
function ns.Summary_Raids(raids, isKilled, difficulties)
	local rows = {}
	for _, raid in ipairs(raids or {}) do
		local parts = {}
		for _, diff in ipairs(difficulties) do
			local kills = 0
			for _, boss in ipairs(raid.bosses or {}) do
				if isKilled(raid.mapID, boss.encounterID, diff.id) then
					kills = kills + 1
				end
			end
			if kills > 0 then
				parts[#parts + 1] = ("%s %d/%d"):format(diff.name, kills, #raid.bosses)
			end
		end
		rows[#rows + 1] = { id = raid.id, name = raid.name, any = #parts > 0, bosses = #(raid.bosses or {}),
			text = #parts > 0 and table.concat(parts, " · ") or "No kills this week" }
	end
	return rows
end

-- World bosses killed this week, by name (lockouts from ns.Weekly_ReadLive: { name, worldBoss }).
function ns.Summary_WorldBosses(lockouts)
	local names = {}
	for _, l in ipairs(lockouts or {}) do
		if l.worldBoss then
			names[#names + 1] = l.name
		end
	end
	return names
end

-- Factions: the renown factions only (sub-factions stay on the Weekly board), not yet maxed first, then by name.
-- recs: ns.Weekly_ReadFactions. Each gets frac (progress in its level, 1 when maxed) and maxed.
function ns.Summary_Factions(recs)
	local list = {}
	for _, rec in ipairs(recs or {}) do
		if not rec.parent then
			local maxed = rec.max ~= nil and (rec.level or 0) >= rec.max
			local frac = 1
			if not maxed then
				frac = (rec.threshold or 0) > 0 and math.min(math.max((rec.earned or 0) / rec.threshold, 0), 1) or 0
			end
			list[#list + 1] = { rec = rec, maxed = maxed, frac = frac,
				waiting = rec.paragon ~= nil and rec.paragon.pending == true }
		end
	end
	table.sort(list, function(a, b)
		if a.waiting ~= b.waiting then
			return a.waiting
		end
		if a.maxed ~= b.maxed then
			return b.maxed
		end
		return (a.rec.name or "") < (b.rec.name or "")
	end)
	return list
end

-- Activities: the open items of Weekly's activity model (ns.Weekly_ActivityModel with hideCompleted on) as rows
-- under their group, and how many are done. Returns { rows = { { group, text, right } }, done, open }.
function ns.Summary_Activities(model)
	local rows, open = {}, 0
	for _, g in ipairs(model and model.groups or {}) do
		for _, item in ipairs(g.items) do
			-- "open" only: the model's own placeholder rows are "dim" (nothing tracked) or "done" (all done).
			if item.state == "open" then
				open = open + 1
				rows[#rows + 1] = { group = g.title, text = item.left, right = item.right }
			end
		end
	end
	return { rows = rows, done = model and model.hidden or 0, open = open }
end

-- The minimap button's tooltip and the rail's summary. state = { vault (Summary_Vault), vaultReady, crests =
-- { { name, text } }, factionsWaiting = n }. Lines: { text, role }.
function ns.Summary_TooltipLines(state)
	local lines = {}
	if state.vaultReady then
		lines[#lines + 1] = { text = "Great Vault rewards waiting", role = "success" }
	end
	local vault = state.vault and ns.Summary_VaultLine(state.vault)
	if vault then
		lines[#lines + 1] = { text = "Vault: " .. vault, role = "text" }
	end
	for _, c in ipairs(state.crests or {}) do
		lines[#lines + 1] = { text = ("%s: %s"):format(c.name, c.text), role = "textMuted" }
	end
	if (state.factionsWaiting or 0) > 0 then
		lines[#lines + 1] = { text = state.factionsWaiting == 1 and "A paragon reward is waiting"
			or ("%d paragon rewards are waiting"):format(state.factionsWaiting), role = "accent" }
	end
	if #lines == 0 then
		lines[1] = { text = "Nothing read yet", role = "textMuted" }
	end
	return lines
end

-- The rail tooltip line: "Vault 4/9 slots" or "Vault rewards waiting".
function ns.Summary_HomeText(vault, vaultReady)
	if vaultReady then
		return "Great Vault rewards waiting"
	end
	if not vault or vault.total == 0 then
		return "Factions, vault, raids and crests"
	end
	return ("Vault %d/%d slots"):format(vault.unlocked, vault.total)
end
