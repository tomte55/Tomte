local addonName, ns = ...

-- The mount and pet journals, read a few milliseconds per frame (Collect here and Holidays both list what's still
-- missing). There's one shared read: every owner's scan is handed the entries it found, so two owners cost one read
-- of the journals, and an owner that starts while the read runs, or soon after it finished, gets what was already
-- read at once. A new scan for the same owner replaces its running one. Only uncollected entries reach the
-- callbacks: mounts that are collected or hidden on this character are skipped, as are pets that aren't obtainable
-- or already owned. Journal filters are never touched.
-- A callback that errors is reported once (ns.errorHandler) and stops its scan. Unit-tested in tests/test_journal.lua.

local BUDGET_MS = 2 -- per frame; it runs at login next to the achievement walk and the decor catalog
local MAX_SPECIES = 6000 -- battle pet species IDs are read 1..MAX_SPECIES
local KEEP = 600 -- seconds a finished read is handed to new scans (it drifts as things are learned; see StillMissing)

-- The shared read: mount IDs and how far into them and into the species it is, what it found ({ id, info } each),
-- and when it finished.
local read -- { ids, mountAt, speciesAt, mounts, pets, mountsRead, petsRead, at }
local scans = {} -- [owner] = { owner, cb, phase = "mounts" | "pets", i (the next found entry to hand over) }
local running = {} -- the scans as a list; replaced, never changed in place, so a callback can start or stop scans
local frame

-- Calls a callback, its error to BugSack. false when it errored: the scan then stops, since a callback that fails on
-- one entry would fail on the next thousands too, every frame.
local function Call(fn, ...)
	if not fn then
		return true
	end
	return (xpcall(fn, ns.errorHandler, ...))
end

local function ReadMount(mountID)
	local name, spellID, icon, _, _, _, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
	if not name or isCollected or shouldHideOnChar then
		return nil
	end
	local _, _, source = C_MountJournal.GetMountInfoExtraByID(mountID)
	return { name = name, spellID = spellID, icon = icon, source = source }
end

local function ReadPet(speciesID)
	-- pcall: an unused species ID may error instead of returning nothing.
	local ok, name, icon, _, _, source, _, _, _, _, _, obtainable, displayID =
		pcall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)
	if not ok or not name or not obtainable then
		return nil
	end
	local owned = C_PetJournal.GetNumCollectedInfo(speciesID)
	if owned and owned > 0 then
		return nil
	end
	return { name = name, icon = icon, source = source, displayID = displayID }
end

-- Reads one more journal entry.
local function ReadNext()
	if not read.mountsRead then
		local mountID = read.ids[read.mountAt]
		if not mountID then
			read.mountsRead = true
			return
		end
		read.mountAt = read.mountAt + 1
		local info = ReadMount(mountID)
		if info then
			read.mounts[#read.mounts + 1] = { id = mountID, info = info }
		end
	elseif read.speciesAt <= MAX_SPECIES then
		local speciesID = read.speciesAt
		read.speciesAt = read.speciesAt + 1
		local info = ReadPet(speciesID)
		if info then
			read.pets[#read.pets + 1] = { id = speciesID, info = info }
		end
	else
		read.petsRead, read.at = true, GetTime()
	end
end

local function SetRunning()
	local list = {}
	for _, scan in pairs(scans) do
		list[#list + 1] = scan
	end
	running = list
end

local function Remove(scan)
	if scans[scan.owner] == scan then
		scans[scan.owner] = nil
		SetRunning()
	end
end

-- Hands one found entry, or the end of a phase, to a scan: "wait" when it's caught up with the read, "done" when it
-- has everything, false when its callback errored.
local function HandOver(scan)
	if scan.phase == "mounts" then
		local e = read.mounts[scan.i]
		if e then
			scan.i = scan.i + 1 -- before the callback: an entry whose callback errors isn't handed over again
			return Call(scan.cb.mount, e.id, e.info)
		end
		if not read.mountsRead then
			return "wait"
		end
		scan.phase, scan.i = "pets", 1
		return Call(scan.cb.mountsDone)
	end
	local e = read.pets[scan.i]
	if e then
		scan.i = scan.i + 1
		return Call(scan.cb.pet, e.id, e.info)
	end
	return read.petsRead and "done" or "wait"
end

local function OnUpdate(self)
	local deadline = debugprofilestop() + BUDGET_MS
	while debugprofilestop() < deadline do
		local waiting = false
		for _, scan in ipairs(running) do
			if scans[scan.owner] == scan then -- not stopped or replaced by a callback in this round
				local phase = scan.phase
				local result = HandOver(scan)
				if result == "wait" then
					waiting = true
				elseif result == "done" then
					Remove(scan)
					Call(scan.cb.done)
				elseif not result then
					Remove(scan)
				end
				-- An owner's mountsDone and done redraw its lists: one of those per frame, or owners that finish
				-- together (they share the read) stack their redraws into one long frame.
				if result == "done" or (result and scan.phase ~= phase) then
					if #running == 0 then
						self:Hide()
					end
					return
				end
			end
		end
		if #running == 0 then
			self:Hide()
			return
		end
		if waiting then
			ReadNext()
		end
	end
end

-- Starts reading both journals for owner (any key). callbacks: { mount = fn(mountID, info), pet = fn(speciesID,
-- info), mountsDone = fn(), done = fn() }. Mount info: name, spellID, icon, source. Pet info: name, icon, source,
-- displayID. The info tables are shared between owners: read them, don't change them.
function ns.Journal_Scan(owner, callbacks)
	if not frame then
		frame = CreateFrame("Frame")
		frame:Hide()
		frame:SetScript("OnUpdate", ns.Perf_Wrap(OnUpdate, "OnUpdate"))
	end
	if not read or (read.petsRead and GetTime() - read.at > KEEP) then
		read = { ids = C_MountJournal.GetMountIDs() or {}, mountAt = 1, speciesAt = 1, mounts = {}, pets = {} }
	end
	scans[owner] = { owner = owner, cb = callbacks, phase = "mounts", i = 1 }
	SetRunning()
	frame:Show()
end

function ns.Journal_Stop(owner)
	local scan = scans[owner]
	if scan then
		Remove(scan)
	end
end

-- The running scan's phase ("mounts" or "pets") and how far into that phase it is (0..1); nil when none runs.
function ns.Journal_Progress(owner)
	local scan = scans[owner]
	if not scan then
		return nil
	end
	if scan.phase == "mounts" then
		if read.mountsRead then
			return "mounts", (scan.i - 1) / math.max(#read.mounts, 1)
		end
		return "mounts", (read.mountAt - 1) / math.max(#read.ids, 1)
	end
	if read.petsRead then
		return "pets", (scan.i - 1) / math.max(#read.pets, 1)
	end
	return "pets", (read.speciesAt - 1) / MAX_SPECIES
end

-- A mount or pet isn't collected yet, read live (lists built from a scan go stale as things are learned).
function ns.Journal_StillMissing(kind, id)
	if kind == "mount" then
		return not select(11, C_MountJournal.GetMountInfoByID(id))
	end
	local owned = C_PetJournal.GetNumCollectedInfo(id)
	return not owned or owned == 0
end
