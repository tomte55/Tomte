local addonName, ns = ...

-- What's new: pure logic (no WoW API calls; unit-tested in tests/test_changes.lua). Each release's few highlights,
-- newest first, written at release time from CHANGELOG.md (README "Releasing"); the window that shows them after an
-- update is Panel/Changes.lua. A line names its module by key (its name and icon come from the module) or, for
-- something that isn't a module, by label.
--
-- ns.CHANGES = { { version = "1.24.0", date = "2026-10-27", new = { lines }, improved = { lines }, fixed = { lines } } }
-- line = { module = key | label = text, text = "..." }

ns.CHANGES = {
	{
		version = "1.30.0", date = "2026-11-06",
		new = {
			{ module = "sources", text = "On Forever: type any item's name to see who sells it, what it's gathered "
				.. "from and which mobs drop it, the best places for your level first, with map pins." },
			{ module = "loot", text = "On Forever: when your bags are full, one click destroys your cheapest grey "
				.. "junk and loots what didn't fit." },
			{ module = "leveling", text = "On Forever: a button that puts your armor kit on worn gear with nothing on it." },
		},
		improved = {
			{ module = "gear", text = "On Forever: lighter armor is no longer an upgrade on item level alone, and "
				.. "enchants and armor kits count." },
			{ label = "Tomte window", text = "A shorter side column: Stable, Flight coverage, Mount zones, Recent and "
				.. "Friend sharing open from their settings." },
		},
		fixed = {
			{ module = "whispers", text = "On Forever: the reply key opens the right name the first time." },
		},
	},
	{
		version = "1.29.0", date = "2026-11-06",
		new = {
			{ module = "rest", text = "On Forever: one key or button uses your best food, and drink if you're low on "
				.. "mana. It lights up when you're low and keeps buff food for last." },
			{ module = "chatgroups", text = "On Forever: a page of everyone looking for a group in chat, for a dungeon, "
				.. "a quest or anything else. Click to whisper." },
			{ module = "leveling", text = "On Forever: an ammo counter with your full count, past the quiver's 999. "
				.. "Hover it for all your ammo, click it to switch." },
		},
		improved = {
			{ module = "fishing", text = "On Forever: the key equips your rod and can put on a lure, and your weapons "
				.. "go back afterwards." },
			{ module = "bags", text = "With Group identical items on, the tooltip says how big a stack gets and how "
				.. "many more fit, and a right-click at a merchant sells every stack." },
		},
		fixed = {
			{ label = "World map", text = "On Forever: Esc closes the map in combat again." },
		},
	},
	{
		version = "1.28.0", date = "2026-11-06",
		new = {
			{ label = "Forever theme", text = "On Forever: Tomte drawn with that game's own frames, buttons, bars and "
				.. "tabs, so it looks like part of the game. Pick it in the Tomte window's settings." },
		},
		improved = {
			{ module = "bags", text = "A category can fade or hide its items while a vendor is open, so you can't "
				.. "sell them by accident, and can have its own color." },
			{ module = "leveling", text = "The ammo button fills your quiver in one click, and can buy by itself." },
			{ module = "bags", text = "Gear whose armor or weapon type you can't use shows as unusable. On Forever, "
				.. "profession tools and fishing poles no longer count as weapons." },
		},
	},
	{
		version = "1.27.0", date = "2026-11-06",
		new = {
			{ label = "World of Warcraft: Forever", text = "Tomte now runs there too, with every module that works in "
				.. "that game: bags, alts, Smart Mount, Gear Check and many more." },
			{ module = "leveling", text = "On Forever: your XP, what's new at your trainer, old spell ranks, supplies "
				.. "and your quests sorted by what's worth doing." },
			{ module = "petcare", text = "On Forever, for Hunters: a button that feeds your pet when it's hungry." },
			{ module = "mount", text = "Pick from favorites only or all mounts, class mounts first, a passenger mount "
				.. "in a group, and when druids and shamans take a travel form." },
		},
		improved = {
			{ module = "bags", text = "A clearer mark on appearances you haven't collected, and free slots that say "
				.. "which of your bags they're in." },
		},
		fixed = {
			{ module = "bags", text = "A grey item Gear Check calls an upgrade no longer counts as junk." },
		},
	},
	{
		version = "1.26.0", date = "2026-10-29",
		new = {
			{ module = "perf", text = "Performance: see how much of the game's time Tomte takes, which module, and "
				.. "what made the game hitch. Off by default." },
			{ module = "tips", text = "Bag items say when they have no use left: safe to delete, or sell it." },
			{ module = "bags", text = "Right-click a bag's tab to assign it to Equipment, Consumables and more." },
		},
		improved = {
			{ label = "Faster login", text = "Tomte takes a much smaller share of the game's time right after you "
				.. "log in." },
			{ module = "bags", text = "One bag keeps items where they are, so you can move them yourself; vendor "
				.. "payment items like Dark Particles stand out." },
		},
	},
	{
		version = "1.25.0", date = "2026-10-29",
		new = {
			{ module = "window", text = "A small toast when Tomte hits an error; click it for a bug report to send." },
		},
		improved = {
			{ module = "alts", text = "Recipe tooltips say which of your characters can learn them, and whether their "
				.. "skill is high enough yet." },
		},
		fixed = {
			{ module = "bags", text = "Using items from the bags works again after switching Character / Warband at "
				.. "the bank." },
			{ label = "Appearances", text = "Looks you already have no longer show as new on armor you can't wear." },
			{ module = "loot", text = "The \"you own\" count on loot lines updates once the item is in your bags." },
		},
	},
	{
		version = "1.24.3", date = "2026-10-27",
		fixed = {
			{ module = "bags", text = "Find on all characters searches tooltip words too (\"Use:\", \"Equip:\")." },
			{ module = "bags", text = "Gear no longer stays red after a fight; the red tint checks again by itself "
				.. "after combat, a spec change or a new recipe." },
			{ module = "bags", text = "Saved searches run with a click and have a right-click menu; the currencies "
				.. "search finds folded currencies." },
			{ module = "bags", text = "Category names aren't cut off, and naming a saved search has room to type "
				.. "again." },
		},
	},
	{
		version = "1.24.2", date = "2026-10-27",
		fixed = {
			{ module = "window", text = "Updating from 1.23 or older, What's new shows every release since, not only "
				.. "the newest one." },
		},
	},
	{
		version = "1.24.1", date = "2026-10-27",
		fixed = {
			{ module = "bags", text = "Everything from a bag or cache you open shows in New and stays there until you "
				.. "close your bags." },
			{ module = "bags", text = "Items you can't use, profession gear included, are tinted red, and lose the red "
				.. "when a level-up makes them usable." },
			{ module = "events", text = "Holidays and weekly bonus events show a proper icon instead of a blank sliver "
				.. "of calendar art." },
		},
	},
	{
		version = "1.24.0", date = "2026-10-27",
		new = {
			{ module = "bags", text = "Tomte's own bag and bank windows: items sorted into categories, upgrade and "
				.. "transmog marks, a search that reads tooltips, and categories you make yourself. Off by default." },
			{ module = "counts", text = "Item tooltips say how many each of your characters has, and where." },
			{ module = "alts", text = "At the bank, \"For alts\" and \"Take for crafts\" move crafting materials in "
				.. "one click." },
			{ module = "dressup", text = "Gear tooltips say whether you already have the item's look." },
			{ module = "window", text = "Motion and sound settings: how much Tomte animates and which sounds play." },
		},
		improved = {
			{ label = "Everywhere", text = "Smoother: windows fade, lists glide and counts tick to their new values." },
			{ module = "alts", text = "Clicking a material in the crafting list finds it in your bags." },
		},
		fixed = {
			{ module = "alts", text = "The crafting list no longer says nobody knows a recipe after a slow login." },
			{ label = "Home", text = "Collect here opens the map on its tab and updates once your collections are read." },
		},
	},
}

-- "1.24.0" -> { 1, 24, 0 }.
local function Parts(version)
	local parts = {}
	for n in tostring(version or ""):gmatch("%d+") do
		parts[#parts + 1] = tonumber(n)
	end
	return parts
end

-- -1, 0 or 1: a older than, the same as or newer than b (by number: "1.10.0" is newer than "1.9.0").
function ns.Changes_Compare(a, b)
	local pa, pb = Parts(a), Parts(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then
			return x < y and -1 or 1
		end
	end
	return 0
end

-- The releases to show after an update: newer than seen, up to current, newest first. seen nil: someone updating
-- from a Tomte older than this list (a new user starts with seen set, Core.lua), so every release up to current.
-- Empty when there's nothing new.
function ns.Changes_ToShow(list, seen, current)
	local out = {}
	for _, entry in ipairs(list) do
		local upToCurrent = ns.Changes_Compare(entry.version, current) <= 0
		local newer = not seen or ns.Changes_Compare(entry.version, seen) > 0
		if upToCurrent and newer then
			out[#out + 1] = entry
		end
	end
	return out
end
