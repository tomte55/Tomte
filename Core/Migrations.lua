local addonName, ns = ...

-- Settings migrations, in order, each run once per SavedVariables (TomteDB.schema, ns.RunMigrations in Modules.lua)
-- before defaults are merged. Only add to the end. A migration must cope with missing tables. Pure
-- (tests/test_migrations.lua). Two fix-ups need live game data and stay in their modules: Gear_MigrateHinted (Gear)
-- and Session.lua's name/class re-fill.
ns.MIGRATIONS = {
	-- 1: keys of removed features: the old panel's category filter, the old FlightTimer hand-over flag.
	function(db)
		if type(db.panel) == "table" then
			db.panel.category = nil
		end
		db.flightImported = nil
	end,
	-- 2: the first-run picker (1.5): saved variables from before it are an existing user's. No picker and no
	-- message for them; a fresh install was marked "pending" before the migrations ran.
	function(db)
		ns.Setup_Migrate(db)
	end,
	-- 3: Moments' "Cinematics only at max level" checkbox became the per-moment "Cinematic at max level" style.
	function(db)
		ns.Moments_MigrateAtMax(db.moments)
	end,
	-- 4: the AFK module kept the play session until the Session recap took it over.
	function(db)
		ns.Session_Migrate(db)
	end,
	-- 5: NextUp's old default placement "column" became "characters". placedUnderChars marked users the old in-module
	-- fix had already handled (their "column" is a choice).
	function(db)
		local nextDB = db.next
		if type(nextDB) ~= "table" then
			return
		end
		if not nextDB.placedUnderChars and nextDB.placement == "column" then
			nextDB.placement = "characters"
		end
		nextDB.placedUnderChars = nil
	end,
	-- 6: Waypoints: 325 yards was an old default that put the card too far out.
	function(db)
		if type(db.way) == "table" and db.way.cardDistance == 325 then
			db.way.cardDistance = 110
		end
	end,
	-- 7: Almost Done caches saved before records kept topID: dropped, the login scan rebuilds them.
	function(db)
		local cache = type(db.ach) == "table" and db.ach.cache
		if type(cache) ~= "table" then
			return
		end
		for guid, entry in pairs(cache) do
			local records = type(entry) == "table" and entry.records
			if type(records) == "table" then
				for _, record in pairs(records) do
					if type(record) == "table" and record.category and record.topID == nil then
						cache[guid] = nil
						break
					end
				end
			end
		end
	end,
	-- 8: Flight paces saved as lifetime totals (before the PACE_WINDOW of 10 flights) count as 9 flights, so the next
	-- flight starts pulling the average right away. Flight/Data.lua's PACE_WINDOW - 1.
	function(db)
		local paces = type(db.flight) == "table" and db.flight.paces
		if type(paces) ~= "table" then
			return
		end
		for _, pace in pairs(paces) do
			if type(pace) == "table" and pace.flights == nil then
				pace.flights = 9
			end
		end
	end,
	-- 9: the settings sidebar's collapsible categories became groups on a rail (no saved state of their own).
	function(db)
		if type(db.panel) == "table" then
			db.panel.collapsed = nil
		end
	end,
}
