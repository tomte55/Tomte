local addonName, ns = ...

-- The mount and pet journals, read a few milliseconds per frame (Collect here and Holidays both list what's still
-- missing). Each owner gets one hidden frame, reused by its next scan; a new scan for the same owner replaces the
-- running one. Only uncollected entries reach the callbacks: mounts that are collected or hidden on this character
-- are skipped, as are pets that aren't obtainable or already owned. Journal filters are never touched.
-- A callback that errors is reported once (ns.errorHandler) and stops its scan. Unit-tested in tests/test_journal.lua.

local BUDGET_MS = 4
local MAX_SPECIES = 6000 -- battle pet species IDs are read 1..MAX_SPECIES

local scans = {} -- [owner] = { frame, cb, phase = "mounts" | "pets", ids, i }

-- Calls a callback, its error to BugSack. false when it errored: the scan then stops, since a callback that fails on
-- one entry would fail on the next thousands too, every frame.
local function Call(fn, ...)
	if not fn then
		return true
	end
	return (xpcall(fn, ns.errorHandler, ...))
end

local function ReadMount(scan, mountID)
	local name, spellID, icon, _, _, _, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
	if not name or isCollected or shouldHideOnChar then
		return true
	end
	local _, _, source = C_MountJournal.GetMountInfoExtraByID(mountID)
	return Call(scan.cb.mount, mountID, { name = name, spellID = spellID, icon = icon, source = source })
end

local function ReadPet(scan, speciesID)
	-- pcall: an unused species ID may error instead of returning nothing.
	local ok, name, icon, _, _, source, _, _, _, _, _, obtainable, displayID =
		pcall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)
	if not ok or not name or not obtainable then
		return true
	end
	local owned = C_PetJournal.GetNumCollectedInfo(speciesID)
	if owned and owned > 0 then
		return true
	end
	return Call(scan.cb.pet, speciesID, { name = name, icon = icon, source = source, displayID = displayID })
end

local function Stop(frame)
	frame.scan = nil
	frame:Hide()
end

local function OnUpdate(self)
	local scan = self.scan
	if not scan then
		self:Hide()
		return
	end
	local deadline = debugprofilestop() + BUDGET_MS
	while debugprofilestop() < deadline do
		if self.scan ~= scan then
			return -- a callback stopped or replaced this scan
		end
		local ok
		if scan.phase == "mounts" then
			local mountID = scan.ids[scan.i]
			if mountID then
				scan.i = scan.i + 1 -- before the callback: an entry whose callback errors isn't read again
				ok = ReadMount(scan, mountID)
			else
				scan.phase, scan.i = "pets", 1
				ok = Call(scan.cb.mountsDone)
			end
		elseif scan.i <= MAX_SPECIES then
			local speciesID = scan.i
			scan.i = scan.i + 1
			ok = ReadPet(scan, speciesID)
		else
			Stop(self)
			Call(scan.cb.done)
			return
		end
		if not ok then
			if self.scan == scan then
				Stop(self)
			end
			return
		end
	end
end

-- Starts reading both journals for owner (any key). callbacks: { mount = fn(mountID, info), pet = fn(speciesID,
-- info), mountsDone = fn(), done = fn() }. Mount info: name, spellID, icon, source. Pet info: name, icon, source,
-- displayID.
function ns.Journal_Scan(owner, callbacks)
	local frame = scans[owner]
	if not frame then
		frame = CreateFrame("Frame")
		frame:Hide()
		frame:SetScript("OnUpdate", OnUpdate)
		scans[owner] = frame
	end
	frame.scan = { cb = callbacks, phase = "mounts", ids = C_MountJournal.GetMountIDs() or {}, i = 1 }
	frame:Show()
end

function ns.Journal_Stop(owner)
	local frame = scans[owner]
	if frame then
		Stop(frame)
	end
end

-- The running scan's phase ("mounts" or "pets") and how far into that phase it is (0..1); nil when none runs.
function ns.Journal_Progress(owner)
	local scan = scans[owner] and scans[owner].scan
	if not scan then
		return nil
	end
	if scan.phase == "mounts" then
		return "mounts", (scan.i - 1) / math.max(#scan.ids, 1)
	end
	return "pets", (scan.i - 1) / MAX_SPECIES
end

-- A mount or pet isn't collected yet, read live (lists built from a scan go stale as things are learned).
function ns.Journal_StillMissing(kind, id)
	if kind == "mount" then
		return not select(11, C_MountJournal.GetMountInfoByID(id))
	end
	local owned = C_PetJournal.GetNumCollectedInfo(id)
	return not owned or owned == 0
end
