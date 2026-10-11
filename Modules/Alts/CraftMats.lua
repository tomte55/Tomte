local addonName, ns = ...

-- Alts page, Crafting tab: "Materials on hand" (which recipes the account has the materials for, kept until the items
-- change) and /tomte alts why. CraftTab.lua has the entry points, CraftResults.lua the filter that uses these.

local S = ns.AltsCraft_State
local UI = ns.UI

-- "Only what we have materials for": recipes whose whole plan is covered and known. Counts are shared between
-- recipes during one pass (the same reagent is looked up once). Each verdict is kept until the items change (bags,
-- bank, mail, Syndicator), the recipes change or "Crafted materials" switches, so typing and item loads don't plan
-- every recipe again.
local matsKept, matsChain = {}, nil -- [recipeID] = true | false, worked out with db.chain == matsChain
local function ClearMaterials()
	wipe(matsKept)
end

local events = ns.Alts_Events
local MATS_EVENTS = { "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
	"MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "PLAYER_ENTERING_WORLD" }
for _, event in ipairs(MATS_EVENTS) do
	events:On("mats", event, ClearMaterials)
end
-- Syndicator's callback registry stores callbacks per owner: its own table, not shared with List.lua.
local matsOwner = {}
-- Watched once the Craft tab is built and deliberately never unwatched, not even when the module turns off: clearing
-- the kept verdicts is harmless.
local function WatchMaterials()
	for _, event in ipairs(MATS_EVENTS) do
		-- An event name the client doesn't know must not stop the others.
		events:TryWatch("mats", event)
	end
	if _G.Syndicator and Syndicator.CallbackRegistry then
		for _, name in ipairs({ "Ready", "BagCacheUpdate", "MailCacheUpdate", "WarbandBankCacheUpdate" }) do
			pcall(Syndicator.CallbackRegistry.RegisterCallback, Syndicator.CallbackRegistry, name, ClearMaterials, matsOwner)
		end
	end
end

local function HaveMaterials(list)
	if matsChain ~= S.db.chain then
		ClearMaterials()
		matsChain = S.db.chain
	end
	local counts = {}
	local ctx = {
		recipes = S.db.recipes, chars = S.db.chars, producers = S.producers,
		maxDepth = S.db.chain == "one" and 1 or ns.ALTS_FULL_DEPTH,
		count = function(items)
			local key = table.concat(items, ",")
			if not counts[key] then
				counts[key] = (ns.Alts_Have(items))
			end
			return counts[key]
		end,
	}
	local kept = {}
	for _, r in ipairs(list) do
		if matsKept[r.id] == nil then
			local ok, plan = pcall(ns.Alts_Plan, r.id, 1, ctx)
			matsKept[r.id] = ok and plan.missing == 0 and plan.unknown == 0
		end
		if matsKept[r.id] then
			kept[#kept + 1] = r
		end
	end
	return kept
end

-- /tomte alts why <recipe>: why "Materials on hand" keeps or drops a recipe (each material: need, have and where).
function ns.AltsCraft_Why(text)
	text = strtrim(text or ""):lower()
	if text == "" then
		ns.Print("usage: /tomte alts why <part of a recipe name>")
		return
	end
	S.db = S.db or ns.altsDB -- set when the tab is first built; the command can come before that
	S.producers = S.producers or ns.Alts_Producers(S.db.recipes)
	local found = ns.Alts_Search(S.db.recipes, S.db.chars, { text = text, learnable = true }, 3)
	if #found == 0 then
		ns.Print("no recipe matches \"" .. text .. "\".")
		return
	end
	ns.Print(("Syndicator %s."):format(ns.Alts_HasSyndicator() and "is counting" or "isn't loaded or ready: only this character and the Warband bank"))
	for _, r in ipairs(found) do
		local ok, plan = pcall(ns.Alts_Plan, r.id, 1, {
			recipes = S.db.recipes, chars = S.db.chars, producers = S.producers,
			maxDepth = S.db.chain == "one" and 1 or ns.ALTS_FULL_DEPTH,
			count = function(items)
				return (ns.Alts_Have(items))
			end,
		})
		if not ok then
			ns.Print(("%s: plan error %s"):format(r.recipe.name or r.id, tostring(plan)))
		else
			local kept = plan.missing == 0 and plan.unknown == 0
			ns.Print(("%s: %s (missing %d, steps nobody knows %d)"):format(r.recipe.name or r.id,
				kept and UI.Wrap("kept", "success") or UI.Wrap("dropped", "danger"), plan.missing, plan.unknown))
			for _, m in ipairs(plan.materials) do
				local _, where = ns.Alts_Have(m.items)
				local parts = {}
				for _, w in ipairs(where) do
					parts[#parts + 1] = ("%s %d"):format(w.name, w.n)
				end
				ns.Print(("   %s: need %d, have %d%s%s"):format(C_Item.GetItemNameByID(m.items[1]) or ("item " .. m.items[1]),
					m.need, m.have, m.missing > 0 and ", " .. UI.Wrap(("missing %d"):format(m.missing), "danger") or "",
					#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""))
			end
			for _, step in ipairs(plan.steps) do
				if #step.crafters == 0 then
					ns.Print(("   nobody knows %s"):format(S.db.recipes[step.recipeID] and S.db.recipes[step.recipeID].name or step.recipeID))
				end
			end
		end
	end
end

ns.AltsCraft_ClearMaterials = ClearMaterials
ns.AltsCraft_WatchMaterials = WatchMaterials
ns.AltsCraft_HaveMaterials = HaveMaterials
