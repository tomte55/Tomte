local addonName, ns = ...

-- Pet Battles module: a battle helper (matchups, best pet, the strategy's steps and a Next move button that plays
-- its script one press at a time), a card for the tamer you talk to (team, readiness, Load team, Xu-Fu and Wowhead
-- links, Heal), imported Xu-Fu strategies, a leveling slot and a page in the Tomte window. The battle and its events
-- are in Battle.lua, the pet journal and the Heal button in Journal.lua, saved teams in Store.lua, the card in
-- Card.lua, the links window in Guides.lua and the page in Page.lua. Pure rules are in Data.lua, Strings.lua and
-- Script.lua; the tamer table in Tamers.lua.

local module

local function RematchLoaded()
	return C_AddOns.IsAddOnLoaded("Rematch")
end
ns.Pets_RematchLoaded = RematchLoaded

local function Open(view)
	ns.Panel_OpenPage("pets")
	if view then
		ns.PetsPage_SetView(view)
	end
end

local SLOT_CHOICES = {
	{ value = 1, text = "Slot 1" },
	{ value = 2, text = "Slot 2" },
	{ value = 3, text = "Slot 3" },
}

local function TeamCount()
	local n = #ns.PetsStore_Teams()
	if n == 0 then
		return "Paste Xu-Fu strategies to win tamer fights"
	end
	return n == 1 and "1 strategy saved" or (n .. " strategies saved")
end

local function Refresh()
	ns.PetsBattle_Refresh()
	ns.PetsCard_Refresh()
	ns.PetsPage_Refresh()
end

module = ns.RegisterModule({
	key = "pets",
	name = "Pet Battles",
	category = "collections",
	icon = 643856, -- inv_pet_battlepettraining
	summary = "Win pet battles with tips, saved strategies and one key per turn.",
	description = "Help to win pet battles: a battle helper with what hits the enemy hard and your best pet, a card for pet tamers (team, readiness, Load team, Xu-Fu guide links, Heal), Xu-Fu strategies you paste in, played one key press per turn, and a leveling slot.",
	enabledByDefault = true,
	replaces = { { addon = "tdBattlePetScript", why = "pet battle scripts played one key press per turn" } },
	-- Saved keys without a default: cache (round counters, Read.lua), advisor.point (the helper's dragged position,
	-- Battle.lua) and nextID (the next team id, Store.lua).
	defaults = {
		advisor = { shown = true, steps = true, collapsed = false, locked = false, scale = 1 },
		card = { shown = true, autoLoad = false },
		heal = { after = true },
		leveling = { on = false, slot = 1 },
		levelQueue = {}, -- petGUIDs for the leveling slot, in order (a collection: "Reset settings" keeps it)
		runner = { on = true },
		view = "tamers",
		teams = {}, -- [id] = { name, npcs, pets, prefs, notes, script, imported } (Strings.lua)
		active = {}, -- [npcID] = team id used against that NPC
		learned = {}, -- [npcID] = { name, species, types, seen }
	},
	init = function(db)
		ns.PetsStore_Init(db)
		ns.PetsCard_Init(db)
		ns.PetsPage_Init(db)
		ns.PetsBattle_Init(db, module)
	end,
	toggle = function(active)
		ns.PetsBattle_Toggle(active)
		if not active then
			ns.PetsCard_Hide()
		end
	end,
	home = {
		{ kind = "page", key = "pets", order = 40, name = "Pet Battles",
			icon = "Interface\\Icons\\INV_Pet_BattlePetTraining", page = ns.PetsPage, summary = TeamCount },
	},
	commands = {
		{ "open", "open the Pet Battles page", function()
			Open()
		end },
		{ "import", "open the Teams view to paste Xu-Fu strategies", function()
			Open()
			ns.PetsPage_FocusImport()
		end },
		{ "types", "show which family beats which", function()
			Open("types")
		end },
		{ "load", "load the team for the tamer you're talking to", function()
			if not (ns.PetsCard_Shown() and ns.PetsCard_LoadTeam()) then
				ns.Print("talk to a pet tamer that has a saved strategy first.")
			end
		end },
	},
	options = {
		{ type = "header", label = "Battle helper" },
		{ type = "checkbox", key = "advisor.shown", label = "Show the battle helper", onChange = Refresh,
			tooltip = "In pet battles: the enemy team, the attack types that hit the active enemy hard, your best pet against it and, for a saved strategy, its steps and the Next move button." },
		{ type = "checkbox", key = "advisor.steps", label = "Strategy steps", onChange = Refresh,
			parent = "advisor.shown", tooltip = "Show a saved strategy's turn-by-turn notes under the helper, with the round number." },
		{ type = "checkbox", key = "advisor.locked", label = "Lock position", parent = "advisor.shown",
			tooltip = "Off: drag the helper to move it. Blizzard's Edit Mode moves it too." },
		{ type = "slider", key = "advisor.scale", label = "Size", min = 0.6, max = 1.6, step = 0.1,
			parent = "advisor.shown", format = function(v)
				return ("%.1f"):format(v)
			end, onChange = function()
				ns.PetsBattle_Relayout()
			end },
		{ type = "button", label = "Position", text = "Reset", onClick = function()
			ns.PetsBattle_ResetPosition()
		end, tooltip = "Move the helper back above the pet battle bar.", parent = "advisor.shown" },

		{ type = "header", label = "Strategy script" },
		{ type = "checkbox", key = "runner.on", label = "Next move button", onChange = Refresh,
			tooltip = "For a strategy with a script (most Xu-Fu strategies have one): a button that does this turn's move. One press is one action; it never plays by itself. Give it a key in WoW's Key Bindings > Tomte > Next pet battle move (not 1-3: those are your abilities)." },

		{ type = "header", label = "Tamers" },
		{ type = "checkbox", key = "card.shown", label = "Tamer card", onChange = Refresh,
			tooltip = "Talking to a pet tamer Tomte knows shows a card: your team for that fight, whether your pets are ready, Load team, Heal and the guide links." },
		{ type = "checkbox", key = "card.autoLoad", label = "Load the team when talking to the tamer", parent = "card.shown",
			tooltip = "Changes your pet team without asking when the saved strategy's pets differ. Doesn't happen while Rematch is loaded: it loads teams itself." },

		{ type = "header", label = "Healing" },
		{ type = "checkbox", key = "heal.after", label = "Heal button after battles",
			tooltip = "When your pets got hurt, a Heal button shows for 30 seconds after the battle. It uses Revive Battle Pets, or a Battle Pet Bandage while that's on cooldown. Key Bindings > Tomte > Heal battle pets." },

		{ type = "header", label = "Leveling" },
		{ type = "checkbox", key = "leveling.on", label = "Leveling slot", onChange = Refresh,
			tooltip = "After each battle, the pet in this slot is swapped for the next pet in your queue (the page's Leveling view) once it reaches 25. The helper reminds you to swap it out after its first turn; it still gets the XP." },
		{ type = "dropdown", key = "leveling.slot", label = "Slot", choices = function()
			return SLOT_CHOICES
		end, onChange = Refresh, parent = "leveling.on" },
		{ type = "button", label = "Queue", text = "Open", onClick = function()
			Open("leveling")
		end },
	},
})
