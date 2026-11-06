-- Run from the AddOns folder: lua Tomte/tests/test_forevertoc.lua
local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local ForeverToc = dofile("Tomte/tools/forever_build.lua")
local LIST = dofile("Tomte/tools/forever_list.lua")

local function Lines(path)
	local lines = {}
	for line in io.lines(path) do
		lines[#lines + 1] = (line:gsub("\r$", ""))
	end
	return lines
end

local function Has(lines, wanted)
	for i, line in ipairs(lines) do
		if line == wanted then
			return i
		end
	end
	return nil
end

local RETAIL = {
	"## Interface: 120105",
	"## Title: Tomte",
	"## Version: 1.22.0",
	"## X-Curse-Project-ID: 1",
	"",
	"Core/Core.lua",
	"Core/Journal.lua",
	"Data/Midnight/Gear.lua",
	"Modules/Chat/Data.lua",
	"Modules/Chat/New.lua",
	"Modules/Talents/Talents.lua",
	"Modules/Moments/Data.lua",
	"Modules/Moments/Moments.lua",
}

local SMALL = {
	interface = "0",
	keep = { "Core/", "Modules/Chat/", "Modules/Moments/Data.lua" },
	drop = { "Core/Journal.lua" },
	extra = { { after = "Core/Core.lua", files = { "Core/Forever.lua" } } },
}

test("Build keeps the allowed folders and files, drops the rest", function()
	local out = ForeverToc.Build(RETAIL, SMALL)
	eq(Has(out, "Core/Core.lua") ~= nil, true, "core kept")
	eq(Has(out, "Core/Journal.lua"), nil, "dropped file")
	eq(Has(out, "Data/Midnight/Gear.lua"), nil, "data folder not kept")
	eq(Has(out, "Modules/Talents/Talents.lua"), nil, "module not kept")
	eq(Has(out, "Modules/Moments/Data.lua") ~= nil, true, "single file kept")
	eq(Has(out, "Modules/Moments/Moments.lua"), nil, "rest of that folder not kept")
end)

test("Build keeps a file added later to a kept folder", function()
	eq(Has(ForeverToc.Build(RETAIL, SMALL), "Modules/Chat/New.lua") ~= nil, true, "new file")
end)

test("Build rewrites the interface and tags the flavor after the version", function()
	local out = ForeverToc.Build(RETAIL, SMALL)
	eq(out[1], "## Interface: 0", "interface")
	eq(Has(out, "## Title: Tomte") ~= nil, true, "title kept")
	eq(out[Has(out, "## Version: 1.22.0") + 1], "## X-Tomte-Flavor: forever", "flavor")
	eq(Has(out, "## X-Curse-Project-ID: 1") ~= nil, true, "project kept")
end)

test("Build inserts extra files after their anchor", function()
	local out = ForeverToc.Build(RETAIL, SMALL)
	eq(Has(out, "Core/Forever.lua"), Has(out, "Core/Core.lua") + 1, "after Core.lua")
end)

test("the committed Forever TOC is current", function()
	local hint = " (run: lua Tomte/tools/forevertoc.lua)"
	local want = ForeverToc.Build(Lines("Tomte/Tomte.toc"), LIST)
	local have = Lines("Tomte/" .. LIST.name)
	eq(#have, #want, "line count" .. hint)
	for i = 1, #want do
		eq(have[i], want[i], "line " .. i .. hint)
	end
end)

-- Migrations run on Forever too (a fresh TomteDB runs them all): each module function they call must load there.
test("every function the migrations call loads on Forever", function()
	local loaded = {}
	for _, line in ipairs(Lines("Tomte/" .. LIST.name)) do
		if line:match("%.lua$") then
			local text = assert(io.open("Tomte/" .. line)):read("*a")
			for name in text:gmatch("function ns%.([%w_]+)%s*%(") do
				loaded[name] = true
			end
		end
	end
	local text = assert(io.open("Tomte/Core/Migrations.lua")):read("*a")
	for line in text:gmatch("[^\n]+") do
		if not line:match("^%s*%-%-") then
			for name in line:gmatch("ns%.([%w]+_[%w_]+)%s*%(") do
				eq(loaded[name], true, "ns." .. name)
			end
		end
	end
end)

-- Calls guarded in a way the scan can't see, with where the guard is.
local KNOWN_GUARDED = {
	["Panel/HomeHero.lua GearSheet_Open"] = true, -- clickable() is false on Forever
	["Modules/Travel/Waypoint.lua WayRouter_Toggle"] = true, -- the row's shown = ns.NotForever
	["Modules/Achievements/Achievements.lua Events_Current"] = true, -- Holidays() returns first without it
	["Modules/Achievements/Achievements.lua Events_Names"] = true, -- likewise
	["Modules/Alts/Collect.lua Weekly_ProfDef"] = true, -- ExpansionLine and its tiers return first without it
	["Modules/Alts/RosterTab.lua Weekly_View"] = true, -- WeeklyStatus returns first without it
	["Modules/Alts/Send.lua GearAlts_Route"] = true, -- GearOn() is false without ns.GearAlts_Upgrades
	["Modules/Alts/Send.lua GearAlts_Upgrades"] = true, -- likewise
	["Modules/Alts/Send.lua Gear_EvaluateLink"] = true, -- likewise
	["Modules/Alts/Send.lua Gear_AltGain"] = true, -- likewise: s.verdict comes from that path
	-- Instances.lua: Apply returns first on Forever, its rows have shown = ns.NotForever, init and why are guarded.
	["Modules/Instances/Instances.lua InstancesEntrance_Toggle"] = true,
	["Modules/Instances/Instances.lua InstancesBadge_Toggle"] = true,
	["Modules/Instances/Instances.lua InstancesQueue_Toggle"] = true,
	["Modules/Instances/Instances.lua InstancesHoliday_Toggle"] = true,
	["Modules/Instances/Instances.lua InstancesBadge_DrawSample"] = true,
	["Modules/Instances/Instances.lua InstancesBadge_Why"] = true,
	["Modules/Instances/Instances.lua InstancesEntrance_Why"] = true,
	["Modules/Instances/Instances.lua InstancesQueue_Why"] = true,
	["Modules/Instances/Instances.lua InstancesEntrance_Init"] = true,
	["Modules/Instances/Instances.lua InstancesBadge_Init"] = true,
	["Modules/Instances/Instances.lua InstancesEntrance_DrawSample"] = true,
	["Modules/Instances/Instances.lua InstancesQueue_DrawSample"] = true,
	-- Tips.lua: the choice window's row has shown = ns.NotForever.
	["Modules/Tips/Tips.lua TipsChoice_Refresh"] = true,
	["Modules/Tips/Tips.lua TipsChoice_Preview"] = true,
}

-- A Forever file may call a module function defined only in files Forever doesn't load, but only behind a check
-- that it exists (`ns.X and ns.X(...)`, or `if ns.X then` just above).
test("Forever files guard every call into files Forever doesn't load", function()
	local forever, all = {}, {}
	for _, line in ipairs(Lines("Tomte/" .. LIST.name)) do
		if line:match("%.lua$") then
			forever[line] = true
		end
	end
	local definedIn = {} -- name -> true when some Forever file defines it
	local definedElsewhere = {}
	-- Retail's files, then the Forever-only ones (in no retail TOC, but they define and call functions too).
	local files = Lines("Tomte/Tomte.toc")
	for _, extra in ipairs(LIST.extra or {}) do
		for _, file in ipairs(extra.files) do
			files[#files + 1] = file
		end
	end
	for _, line in ipairs(files) do
		if line:match("%.lua$") then
			all[#all + 1] = line
			local text = assert(io.open("Tomte/" .. line)):read("*a")
			for _, pattern in ipairs({ "function ns%.([%w_]+)%s*%(", "\nns%.([%w_]+)%s*=[^=]" }) do
				for name in text:gmatch(pattern) do
					if forever[line] then
						definedIn[name] = true
					else
						definedElsewhere[name] = true
					end
				end
			end
		end
	end
	local unguarded = {}
	for _, file in ipairs(all) do
		if forever[file] then
			local lines = Lines("Tomte/" .. file)
			for i, line in ipairs(lines) do
				for name in line:gmatch("ns%.([%w]+_[%w_]+)%s*%(") do
					if definedElsewhere[name] and not definedIn[name] then
						-- Guarded: "ns.X and" / "ns.X then" on the line or just above, or Home's ModuleOn(key)
						-- (false when the module isn't loaded) a few lines above.
						local above = table.concat({ lines[i - 1] or "", lines[i - 2] or "", lines[i - 3] or "",
							lines[i - 4] or "", lines[i - 5] or "" }, " ")
						local near = line .. " " .. above
						local guarded = near:find("ns%." .. name .. "%s+and") or near:find("ns%." .. name .. "%)?%s+then")
							or above:find("ModuleOn%(") or near:find("ns%.FOREVER") or line:match("^%s*%-%-")
							or KNOWN_GUARDED[file .. " " .. name]
						if not guarded then
							unguarded[#unguarded + 1] = file .. ":" .. i .. " ns." .. name
						end
					end
				end
			end
		end
	end
	eq(table.concat(unguarded, ", "), "", "unguarded calls")
end)

H.done()
