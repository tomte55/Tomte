-- Run from the AddOns folder: lua Tomte/tests/test_lootroom.lua
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Loot/RoomData.lua"))("Tomte", ns)

local H = dofile("Tomte/tests/harness.lua")
local test, eq = H.test, H.eq

local function grey(bag, slot, sell, count)
	return { bag = bag, slot = slot, name = "Junk" .. slot, quality = 0, classID = 15, sell = sell, count = count or 1 }
end

test("Fits: a free slot, or room on stacks", function()
	eq(ns.LootRoom_Fits(1, { { free = 0 }, { free = 1 } }), true)
	eq(ns.LootRoom_Fits(5, { { free = 0, topUp = 5 } }), true)
	eq(ns.LootRoom_Fits(5, { { free = 0, topUp = 2 }, { free = 0, topUp = 3 } }), true, "across stacks")
	eq(ns.LootRoom_Fits(6, { { free = 0, topUp = 5 } }), false)
	eq(ns.LootRoom_Fits(1, {}), false, "no bag takes it")
end)

test("MayDestroy: greys go, the common can with a second click, the rest never", function()
	eq(ns.LootRoom_MayDestroy({ quality = 0, classID = 15 }), "grey")
	eq(ns.LootRoom_MayDestroy({ quality = 1, classID = 7 }), "ask")
	eq(ns.LootRoom_MayDestroy({ quality = 2, classID = 4 }), "ask")
	eq(ns.LootRoom_MayDestroy({ quality = 3, classID = 4 }), nil, "rare")
	eq(ns.LootRoom_MayDestroy({ quality = 1, classID = 0 }), nil, "food")
	eq(ns.LootRoom_MayDestroy({ quality = 1, classID = 1 }), nil, "a bag")
	eq(ns.LootRoom_MayDestroy({ quality = 1, classID = 6 }), nil, "ammo")
	eq(ns.LootRoom_MayDestroy({ quality = 1, classID = 12 }), nil, "quest")
	eq(ns.LootRoom_MayDestroy({ quality = 0, classID = 15, bound = true }), nil, "soulbound")
	eq(ns.LootRoom_MayDestroy({ quality = 1, classID = 19 }), nil, "a profession tool (a fishing pole, by Bags_ItemClass)")
	eq(ns.LootRoom_MayDestroy({ quality = 0, classID = 19 }), nil, "a grey profession tool")
	eq(ns.LootRoom_MayDestroy({ quality = 0, classID = 15, upgrade = true }), nil, "an upgrade")
	eq(ns.LootRoom_MayDestroy({ quality = 0, classID = 15, kept = true }), nil, "tool or hearthstone")
	eq(ns.LootRoom_MayDestroy({ quality = 0, classID = 15, noValue = true }), nil, "no vendor price")
	eq(ns.LootRoom_MayDestroy({ quality = 0, classID = 15, locked = true }), nil, "locked")
	eq(ns.LootRoom_MayDestroy({ classID = 15 }), nil, "quality unknown")
end)

test("Worth: a whole stack, by the higher price", function()
	eq(ns.LootRoom_Worth({ sell = 5, count = 3 }), 15)
	eq(ns.LootRoom_Worth({ sell = 5, value = 100, count = 2 }), 200, "the auction price")
	eq(ns.LootRoom_Worth({ sell = 5, quantity = 4 }), 20, "loot counts its quantity")
	eq(ns.LootRoom_Worth({}), 0)
end)

test("Plan: the cheapest grey, one click", function()
	local loot = { name = "Linen", quality = 1, sell = 50, quantity = 1 }
	local plan = ns.LootRoom_Plan(loot, { grey(0, 1, 30), grey(0, 2, 3), grey(1, 3, 3, 2) })
	eq(plan.kind, "destroy")
	eq(plan.target.slot, 2)
	eq(plan.confirm, false)
end)

test("Plan: a grey before anything else, even a cheaper white", function()
	local loot = { name = "Linen", quality = 1, sell = 500, quantity = 1 }
	local white = { bag = 0, slot = 1, name = "Cloth", quality = 1, classID = 7, sell = 1, count = 1 }
	local plan = ns.LootRoom_Plan(loot, { white, grey(0, 2, 40) })
	eq(plan.target.slot, 2)
	eq(plan.confirm, false)
end)

test("Plan: no grey means a second click", function()
	local loot = { name = "Linen", quality = 1, sell = 500, quantity = 1 }
	local white = { bag = 0, slot = 1, name = "Cloth", quality = 1, classID = 7, sell = 1, count = 1 }
	local plan = ns.LootRoom_Plan(loot, { white })
	eq(plan.kind, "destroy")
	eq(plan.confirm, true)
end)

test("Plan: leave what's worth less than anything you'd destroy (a button that destroys more value gets clicked unread)", function()
	local loot = { name = "Tooth", quality = 0, sell = 2, quantity = 1 }
	local plan = ns.LootRoom_Plan(loot, { grey(0, 1, 5) })
	eq(plan.kind, "leave")
	eq(ns.LootRoom_Plan({ name = "Tooth", quality = 0, sell = 5, quantity = 1 }, { grey(0, 1, 5) }).kind, "leave", "the same is no gain")
	eq(ns.LootRoom_Plan({ name = "Tooth", quality = 0, sell = 6, quantity = 1 }, { grey(0, 1, 5) }).kind, "destroy", "a gain")
end)

test("Plan: quest items, upgrades and new looks are worth it whatever they sell for", function()
	for _, extra in ipairs({ { quest = "item" }, { verdict = { upgrade = true } }, { verdict = { maybe = true } }, { newLook = true } }) do
		local loot = { name = "X", quality = 1, sell = 1, quantity = 1 }
		for k, v in pairs(extra) do
			loot[k] = v
		end
		eq(ns.LootRoom_Plan(loot, { grey(0, 1, 500) }).kind, "destroy")
	end
	eq(ns.LootRoom_Plan({ name = "X", quality = 1, quantity = 1 }, { grey(0, 1, 500) }).kind, "destroy", "no price: can't be compared")
end)

test("Plan: stuck with nothing that may go", function()
	local loot = { name = "X", quality = 1, sell = 1 }
	eq(ns.LootRoom_Plan(loot, {}).kind, "stuck")
	eq(ns.LootRoom_Plan(loot, { { bag = 0, slot = 1, quality = 3, classID = 4 } }).kind, "stuck")
end)

test("PickLoot: what's always wanted, then the most valuable", function()
	local cheap = { slot = 1, quality = 1, sell = 1, quantity = 1 }
	local dear = { slot = 2, quality = 1, sell = 100, quantity = 1 }
	local quest = { slot = 3, quality = 1, sell = 1, quantity = 1, quest = "item" }
	eq(ns.LootRoom_PickLoot({ cheap, dear }).slot, 2)
	eq(ns.LootRoom_PickLoot({ cheap, dear, quest }).slot, 3)
	eq(ns.LootRoom_PickLoot({}), nil)
end)

test("Text says what will happen", function()
	local loot = { name = "Linen", quality = 1, sell = 500, quantity = 1 }
	local one = ns.LootRoom_Plan(loot, { grey(0, 1, 3) })
	eq(ns.LootRoom_Text(one):find("Destroy Junk1", 1, true) ~= nil, true)
	eq(ns.LootRoom_Text(one):find("and loot Linen", 1, true) ~= nil, true)
	local white = ns.LootRoom_Plan(loot, { { bag = 0, slot = 1, name = "Cloth", quality = 1, classID = 7, sell = 1, count = 3 } })
	eq(ns.LootRoom_Text(white):find("Cloth x3", 1, true) ~= nil, true)
	eq(ns.LootRoom_Text(white):find("Click to confirm", 1, true) ~= nil, true)
	eq(ns.LootRoom_Text(white, true):find("Click again", 1, true) ~= nil, true)
	eq(ns.LootRoom_Text({ kind = "stuck", loot = loot }):find("nothing safe", 1, true) ~= nil, true)
	eq(ns.LootRoom_Text({ kind = "leave", loot = loot }):find("Leave Linen", 1, true) ~= nil, true)
end)

H.done()
