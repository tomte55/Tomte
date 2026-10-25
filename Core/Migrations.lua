local addonName, ns = ...

-- Settings migrations, in order, each run once per SavedVariables (TomteDB.schema, ns.RunMigrations in Modules.lua)
-- before defaults are merged. Only add to the end. A migration must cope with missing tables. Pure
-- (tests/test_migrations.lua). Fix-ups that need live game data stay in their modules: Gear_MigrateHinted (Gear),
-- Session.lua's name/class re-fill and Chat Tabs' Name-Realm records (ns.Chat_TabsRecord).
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
	-- 10: Delves' own "Delves in Around you" switch became the Tomte window's "Around you shows" one (delvesaround).
	function(db)
		local delves = type(db.delves) == "table" and db.delves
		if not delves then
			return
		end
		if delves.around == false then
			if type(db.window) ~= "table" then
				db.window = {}
			end
			if type(db.window.around) ~= "table" then
				db.window.around = {}
			end
			db.window.around.delvesaround = false
		end
		delves.around = nil
	end,
	-- 11: quieter defaults (Friend sharing off, Group Alerts once on the effects channel) are for new installs only.
	-- Core.lua merges its defaults, db.enabled among them, after the migrations: no enabled table here means a fresh
	-- install. Mentions' flash and sound and Group Alerts' repeats need nothing: every load saved their old defaults.
	function(db)
		if type(db.enabled) ~= "table" then
			return
		end
		if db.enabled.share == nil then
			db.enabled.share = true
		end
		if type(db.alerts) == "table" and db.alerts.channel == nil then
			db.alerts.channel = "Master"
		end
	end,
	-- 12: Minimap Buttons: the one button before 1.10 kept its spot in minimap.angle; it's Tomte's own button now
	-- (minimap.buttons.minimap), shown as it always was. Was done in Minimap.lua's init on every load.
	function(db)
		local saved = db.minimap
		if type(saved) ~= "table" or saved.angle == nil then
			return
		end
		if type(saved.buttons) ~= "table" then
			saved.buttons = {}
		end
		if saved.buttons.minimap == nil then
			saved.buttons.minimap = { shown = true, angle = saved.angle }
		end
		saved.angle = nil
	end,
	-- 13: Blackjack became the Casino (1.20): its saved game and settings, its on/off and Recent's checkbox for its
	-- toasts move from the key "blackjack" to "casino".
	function(db)
		if type(db.blackjack) == "table" and db.casino == nil then
			db.casino = db.blackjack
		end
		db.blackjack = nil
		local include = type(db.recent) == "table" and db.recent.include
		for _, list in pairs({ enabled = db.enabled, include = include }) do
			if type(list) == "table" and list.blackjack ~= nil then
				if list.casino == nil then
					list.casino = list.blackjack
				end
				list.blackjack = nil
			end
		end
	end,
	-- 14: Loot's style (list, card, feed) became the loot window's look (1.23): auto loot always uses the feed now,
	-- and the window that opens by hand is Strips, Panel or Tiles. Card was the Panel's start; List and Feed take
	-- the new default.
	function(db)
		local loot = type(db.loot) == "table" and db.loot
		if not loot or loot.style == nil then
			return
		end
		if loot.look == nil then
			loot.look = loot.style == "card" and "panel" or "strips"
		end
		loot.style = nil
	end,
}
