local addonName, ns = ...

-- Holidays & events: what's still missing from the holidays on now or soon. Mounts and pets come from the journals'
-- source text, read by the shared journal reader (Core/Journal.lua) once per set of holidays, matched against each
-- holiday's signals (Data.lua). Toys come from the generated table (no toy source API), achievements from the
-- holiday's achievement category; both are read live.

local SCAN_KEY = "holidays"

local targets = {} -- [defKey] = signals
local targetKey = ""
local found = {} -- [defKey] = { mounts = {}, pets = {} }
local ready = false
local onChanged = function() end
local itemWaits = {} -- [itemID] = true while its name loads

function ns.EventsCatalog_SetChanged(fn)
	onChanged = fn
end

local function Store(kind, entry, raw)
	for key, signals in pairs(targets) do
		if ns.Events_MatchEntry(kind, entry.id, raw, signals) then
			local list = found[key][kind == "mount" and "mounts" or "pets"]
			local copy = {}
			for k, v in pairs(entry) do
				copy[k] = v
			end
			list[#list + 1] = copy
		end
	end
end

local scanCallbacks = {
	mount = function(mountID, info)
		Store("mount", { kind = "mount", id = mountID, spellID = info.spellID, name = info.name, icon = info.icon,
			source = info.source, line = ns.Collect_ParseSource(info.source).line }, info.source)
	end,
	pet = function(speciesID, info)
		Store("pet", { kind = "pet", id = speciesID, name = info.name, icon = info.icon, source = info.source,
			displayID = info.displayID, line = ns.Collect_ParseSource(info.source).line }, info.source)
	end,
	done = function()
		ready = true
		onChanged()
	end,
}

local function KeyOf(t)
	local keys = {}
	for key in pairs(t) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

-- targets: { [defKey] = signals }. Starts a read when the set of holidays changed; {} stops it.
function ns.EventsCatalog_Start(newTargets)
	local key = KeyOf(newTargets)
	if key == targetKey and (ready or ns.Journal_Progress(SCAN_KEY)) then
		targets = newTargets -- names may have loaded since; matching already ran
		return
	end
	targetKey, targets = key, newTargets
	found = {}
	for k in pairs(targets) do
		found[k] = { mounts = {}, pets = {} }
	end
	ready = false
	if key == "" then
		ns.Journal_Stop(SCAN_KEY)
		return
	end
	ns.Journal_Scan(SCAN_KEY, scanCallbacks)
end

function ns.EventsCatalog_Stop()
	ns.EventsCatalog_Start({})
end

-- { ready, progress 0..1, empty (nothing to read) }
function ns.EventsCatalog_State()
	local progress = ready and 1 or 0
	local phase, fraction = ns.Journal_Progress(SCAN_KEY)
	if phase == "mounts" then
		progress = fraction / 2
	elseif phase == "pets" then
		progress = 0.5 + fraction / 2
	end
	return { ready = ready, progress = progress, empty = targetKey == "" }
end

-- For a progress line (UI.ProgressLine): 0..1 while the journals are read, nil once they are.
function ns.EventsCatalog_Progress()
	local state = ns.EventsCatalog_State()
	if state.ready then
		return nil
	end
	return state.progress
end

local function StillMissing(e)
	return ns.Journal_StillMissing(e.kind, e.id)
end

-- A mount or pet was learned: drop the ones that are collected now.
function ns.EventsCatalog_Earned()
	for _, lists in pairs(found) do
		for _, kind in ipairs({ "mounts", "pets" }) do
			local list = lists[kind]
			for i = #list, 1, -1 do
				if not StillMissing(list[i]) then
					table.remove(list, i)
				end
			end
		end
	end
	onChanged()
end

local function Toys(key)
	local out = {}
	for _, itemID in ipairs(ns.EVENTS_TOYS and ns.EVENTS_TOYS[key] or {}) do
		if not PlayerHasToy(itemID) then
			local _, name, icon = C_ToyBox.GetToyInfo(itemID)
			if not name and C_Item and C_Item.GetItemNameByID then
				name = C_Item.GetItemNameByID(itemID)
			end
			-- Asked once per session: the callback can run at once for a cached item, and onChanged reads this again,
			-- so clearing the mark (or calling onChanged directly) could loop when the toy API still has no name.
			if not name and not itemWaits[itemID] and Item and Item.CreateFromItemID then
				itemWaits[itemID] = true
				Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
					C_Timer.After(0, function()
						onChanged()
					end)
				end)
			end
			if not icon and C_Item and C_Item.GetItemIconByID then
				icon = C_Item.GetItemIconByID(itemID)
			end
			out[#out + 1] = { kind = "toy", id = itemID, name = name or "Loading...", icon = icon }
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

local function Achievements(category)
	local out = {}
	if not category then
		return out
	end
	local count = GetCategoryNumAchievements(category) or 0
	for i = 1, count do
		local id, name, _, completed, _, _, _, _, _, icon = GetAchievementInfo(category, i)
		if id and name and not completed then
			local percent, _, _, _, have, need = ns.Ach_Percent(ns.Ach_ReadCriteria(id))
			out[#out + 1] = { kind = "ach", id = id, name = name, icon = icon, percent = percent or 0, done = have,
				total = need }
		end
	end
	table.sort(out, function(a, b)
		if a.percent ~= b.percent then
			return a.percent > b.percent
		end
		return a.name < b.name
	end)
	return out
end

local function ByName(a, b)
	return (a.name or "") < (b.name or "")
end

-- { mounts, pets, toys, achievements, counts } for a holiday def, or nil while the journals are still being read.
-- show: { mounts, pets, toys, achievements } (false leaves a kind out).
function ns.EventsCatalog_Missing(def, show)
	if not (def and ready and found[def.key]) then
		return nil
	end
	show = show or {}
	local mounts, pets = {}, {}
	if show.mounts ~= false then
		for _, e in ipairs(found[def.key].mounts) do
			mounts[#mounts + 1] = e
		end
	end
	if show.pets ~= false then
		for _, e in ipairs(found[def.key].pets) do
			pets[#pets + 1] = e
		end
	end
	table.sort(mounts, ByName)
	table.sort(pets, ByName)
	local toys = show.toys ~= false and Toys(def.key) or {}
	local achievements = show.achievements ~= false and Achievements(def.category) or {}
	return {
		mounts = mounts, pets = pets, toys = toys, achievements = achievements,
		counts = { mounts = #mounts, pets = #pets, toys = #toys, achievements = #achievements },
	}
end
