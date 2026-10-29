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
