-- Run from the AddOns folder: lua Tomte/tests/test_graphics.lua
local ns = {}
assert(loadfile("Tomte/Core/CheckData.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Graphics/Data.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local DELVE = 208

local function list(t)
	return table.concat(t, " ")
end

local function presets(quality, fps)
	return { quality = quality or {}, fps = fps or {} }
end

test("instances are their own situation", function()
	eq(list(ns.Graphics_Situations({ instanceType = "pvp", difficultyID = 0 })), "pvp")
	eq(list(ns.Graphics_Situations({ instanceType = "arena", difficultyID = 0, afk = true })), "pvp")
	eq(list(ns.Graphics_Situations({ instanceType = "raid", difficultyID = 16, resting = true })), "raid")
	eq(list(ns.Graphics_Situations({ instanceType = "party", difficultyID = 8 })), "dungeon")
	eq(list(ns.Graphics_Situations({ instanceType = "scenario", difficultyID = DELVE })), "dungeon")
	eq(list(ns.Graphics_Situations({ instanceType = "scenario", difficultyID = 12 })), "dungeon")
end)

test("outside instances: AFK, then city, then open world", function()
	eq(list(ns.Graphics_Situations({ instanceType = "none", difficultyID = 0 })), "world")
	eq(list(ns.Graphics_Situations({ instanceType = "none", difficultyID = 0, resting = true })), "city world")
	eq(list(ns.Graphics_Situations({ instanceType = "none", difficultyID = 0, resting = true, afk = true })),
		"afk city world")
	eq(list(ns.Graphics_Situations({ instanceType = "neighborhood", difficultyID = 0, afk = true })), "afk world")
end)

test("AFK inside an instance doesn't count", function()
	eq(list(ns.Graphics_Situations({ instanceType = "party", difficultyID = 1, afk = true })), "dungeon")
end)

test("winner falls through leave-alone situations, per group", function()
	local p = presets({ afk = 0, city = 5, world = 0 }, { afk = 30, city = 0 })
	local situations = { "afk", "city", "world" }
	local key, value = ns.Graphics_Winner(situations, p, "quality")
	eq(key, "city")
	eq(value, 5)
	key, value = ns.Graphics_Winner(situations, p, "fps")
	eq(key, "afk")
	eq(value, 30)
	eq(ns.Graphics_Winner({ "world" }, p, "quality"), nil)
end)

test("decide: nothing set means nothing applied", function()
	local out = ns.Graphics_Decide({ "raid" }, presets(), {})
	eq(out.quality, nil)
	eq(out.fps, nil)
end)

test("decide: a hand change pauses the group until another situation wins", function()
	local p = presets({ raid = 3, world = 7 })
	local paused = { quality = "raid" }
	eq(ns.Graphics_Decide({ "raid" }, p, paused).quality, nil)
	eq(paused.quality, "raid")
	local out = ns.Graphics_Decide({ "world" }, p, paused)
	eq(paused.quality, nil)
	eq(out.quality.situation, "world")
	eq(out.quality.value, 7)
	-- Back in the raid: the preset applies again.
	eq(ns.Graphics_Decide({ "raid" }, p, paused).quality.value, 3)
end)

test("decide: a pause also ends when no preset wins any more", function()
	local paused = { fps = "afk" }
	ns.Graphics_Decide({ "world" }, presets({}, { afk = 30 }), paused)
	eq(paused.fps, nil)
end)

test("decide: a pause in one group leaves the other alone", function()
	local paused = { quality = "city" }
	local out = ns.Graphics_Decide({ "city", "world" }, presets({ city = 4 }, { city = 60 }), paused)
	eq(out.quality, nil)
	eq(out.fps.value, 60)
end)

test("quality value is the level minus one", function()
	eq(ns.Graphics_QualityValue(1), 0)
	eq(ns.Graphics_QualityValue(10), 9)
	eq(ns.Graphics_QualityValue(0), nil)
	eq(ns.Graphics_QualityValue(11), nil)
end)

test("raid CVar names", function()
	eq(ns.Graphics_RaidCVar("graphicsQuality"), "raidGraphicsQuality")
	eq(ns.Graphics_RaidCVar("graphicsSSAO"), "raidGraphicsSSAO")
end)

test("all CVars: overall quality first, frame rate last, groups right", function()
	local all = ns.Graphics_AllCVars()
	eq(all[1], "graphicsQuality")
	eq(all[#all], "maxFPS")
	eq(#all, 2 + 2 * (1 + #ns.GRAPHICS_QUALITY_SUBS))
	local groupOf = ns.Graphics_GroupOf()
	eq(groupOf.graphicsQuality, "quality")
	eq(groupOf.raidGraphicsGroundClutter, "quality")
	eq(groupOf.maxFPS, "fps")
	eq(groupOf.useMaxFPS, "fps")
end)

test("same compares numbers as numbers", function()
	eq(ns.Graphics_Same("1", "1.0"), true)
	eq(ns.Graphics_Same("60", 60), true)
	eq(ns.Graphics_Same("2", "3"), false)
	eq(ns.Graphics_Same("abc", "abc"), true)
end)

local ORDER = { "graphicsQuality", "graphicsShadowQuality", "useMaxFPS", "maxFPS" }

test("plan: first change keeps the original and writes in order", function()
	local saved = {}
	local writes = ns.Graphics_Plan(saved, { graphicsQuality = 2, graphicsShadowQuality = 1 },
		{ graphicsQuality = "7", graphicsShadowQuality = "4", useMaxFPS = "0", maxFPS = "100" }, ORDER)
	eq(#writes, 2)
	eq(writes[1].cvar, "graphicsQuality")
	eq(writes[1].value, 2)
	eq(writes[2].cvar, "graphicsShadowQuality")
	eq(saved.graphicsQuality, "7")
	eq(saved.graphicsShadowQuality, "4")
	eq(saved.maxFPS, nil)
end)

test("plan: a second preset keeps the first original", function()
	local saved = { graphicsQuality = "7" }
	local writes = ns.Graphics_Plan(saved, { graphicsQuality = 4 }, { graphicsQuality = "2" }, ORDER)
	eq(#writes, 1)
	eq(writes[1].value, 4)
	eq(saved.graphicsQuality, "7")
end)

test("plan: no write when the value is already right", function()
	local saved = {}
	local writes = ns.Graphics_Plan(saved, { graphicsQuality = 4 }, { graphicsQuality = "4.0" }, ORDER)
	eq(#writes, 0)
	eq(saved.graphicsQuality, "4.0")
end)

test("plan: leaving restores and forgets the original", function()
	local saved = { graphicsQuality = "7", maxFPS = "100", useMaxFPS = "0" }
	local writes = ns.Graphics_Plan(saved, { graphicsQuality = 3 },
		{ graphicsQuality = "3", useMaxFPS = "1", maxFPS = "30" }, ORDER)
	eq(#writes, 2)
	eq(writes[1].cvar, "useMaxFPS")
	eq(writes[1].value, "0")
	eq(writes[2].cvar, "maxFPS")
	eq(writes[2].value, "100")
	eq(saved.useMaxFPS, nil)
	eq(saved.maxFPS, nil)
	eq(saved.graphicsQuality, "7")
end)

test("plan: a CVar this client lacks is never touched", function()
	local saved = {}
	local writes = ns.Graphics_Plan(saved, { graphicsShadowQuality = 1 }, {}, ORDER)
	eq(#writes, 0)
	eq(saved.graphicsShadowQuality, nil)
end)

test("changed groups: only CVars Tomte set and that read differently", function()
	local groupOf = ns.Graphics_GroupOf()
	local changed = ns.Graphics_ChangedGroups({ graphicsQuality = "2", maxFPS = "30" },
		{ graphicsQuality = "5", maxFPS = "30", graphicsShadowQuality = "1" }, groupOf)
	eq(changed.quality, true)
	eq(changed.fps, nil)
	eq(next(ns.Graphics_ChangedGroups({ graphicsQuality = "2" }, { graphicsQuality = "2.0" }, groupOf)), nil)
end)

test("adopt forgets one group only", function()
	local groupOf = ns.Graphics_GroupOf()
	local saved = { graphicsQuality = "7", graphicsShadowQuality = "4", maxFPS = "100" }
	local applied = { graphicsQuality = "2", maxFPS = "30" }
	ns.Graphics_Adopt(saved, applied, "quality", groupOf)
	eq(saved.graphicsQuality, nil)
	eq(saved.graphicsShadowQuality, nil)
	eq(saved.maxFPS, "100")
	eq(applied.graphicsQuality, nil)
	eq(applied.maxFPS, "30")
end)

test("labels", function()
	eq(ns.Graphics_QualityText(0), "Leave alone")
	eq(ns.Graphics_QualityText(6), "Level 6")
	eq(ns.Graphics_FPSText(0), "Leave alone")
	eq(ns.Graphics_FPSText(60), "60 fps")
	eq(ns.Graphics_SliderText(0), "off")
	eq(ns.Graphics_SliderText(10), "10")
	eq(ns.Graphics_SliderText(200), "200")
end)

H.done()
