local addonName, ns = ...

-- Hunter Pets module: Call Pet tooltips, a Stable tab (pets, families, tame log), a tame-log line on beast
-- tooltips, and a pet readiness check for dungeons, raids, delves and ready checks. Hunters only.
-- Pure logic is in Data.lua.

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "READY_CHECK", "UNIT_PET", "PET_STABLE_SHOW", "PET_STABLE_UPDATE",
	"PET_SPECIALIZATION_CHANGED",
}

local module

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

function events:PLAYER_ENTERING_WORLD()
	ns.Stable_OnEnterWorld()
	ns.Checks_OnEnterWorld()
end

function events:READY_CHECK()
	ns.Checks_OnReadyCheck()
end

function events:UNIT_PET(unit)
	if unit == "player" then
		ns.Stable_Refresh()
	end
end

events.PET_STABLE_SHOW = ns.Stable_Refresh
events.PET_STABLE_UPDATE = ns.Stable_Refresh
events.PET_SPECIALIZATION_CHANGED = ns.Stable_Refresh

local function IsHunter()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

local function Check()
	if not module.active then
		ns.Print("Hunter Pets is off.")
		return
	end
	ns.Checks_Run(true)
end

local function ResetSeen()
	wipe(ns.hunterDB.seen)
	ns.StablePage_Refresh()
	ns.Print("tame log cleared.")
end

local SPEC_CHOICES = {
	{ value = "any", text = "Any" },
	{ value = "Ferocity", text = "Ferocity" },
	{ value = "Tenacity", text = "Tenacity" },
	{ value = "Cunning", text = "Cunning" },
}
local function SpecChoices()
	return SPEC_CHOICES
end

module = ns.RegisterModule({
	key = "hunter",
	name = "Hunter Pets",
	category = "Class",
	description = "Call Pet tooltips, a Stable tab with your pets and a tame log of beasts you've seen, and a pet check when you enter a dungeon, raid or delve and on ready checks.",
	enabledByDefault = true,
	defaults = {
		callPetTooltip = true,
		tameTooltip = true,
		check = {
			onEnter = true,
			onReadyCheck = true,
			banner = true,
			noPet = true,
			marksman = false,
			passive = true,
			growl = true,
			specs = { dungeon = "Ferocity", raid = "any", delve = "any" },
		},
		chars = {}, -- [player GUID] = stable snapshot (Stable.lua)
		seen = {}, -- tame log, account-wide: [family] = { creatures = { [npcID] = { name, zone, at } } }
	},
	init = function(db)
		ns.hunterDB = db
	end,
	blocked = function()
		if not IsHunter() then
			return "Only for hunters."
		end
	end,
	toggle = function(active)
		if active then
			ns.HunterTooltips_Hook()
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
			if ns.inWorld then
				ns.Stable_Refresh()
			end
		else
			events:UnregisterAllEvents()
			ns.Banner_Clear("hunter")
		end
	end,
	page = ns.StablePage,
	commands = {
		{ "check", "run the pet check now", Check },
	},
	options = {
		{ type = "header", label = "Tooltips" },
		{ type = "checkbox", key = "callPetTooltip", label = "Call Pet tooltips",
			tooltip = "Call Pet 1-5 tooltips show the pet's name, family, spec and spec ability." },
		{ type = "checkbox", key = "tameTooltip", label = "Tame log on beasts",
			tooltip = "Beast tooltips show their family and whether you have it, and every beast you hover goes into the tame log on the Stable tab." },

		{ type = "header", label = "Pet check" },
		{ type = "checkbox", key = "check.onEnter", label = "When entering an instance",
			tooltip = "Check a few seconds after entering a dungeon, raid or delve." },
		{ type = "checkbox", key = "check.onReadyCheck", label = "On ready checks" },
		{ type = "checkbox", key = "check.banner", label = "Banner and sound",
			tooltip = "Show problems as a banner with a warning sound. Off: chat only." },
		{ type = "checkbox", key = "check.noPet", label = "No pet or dead pet",
			tooltip = "For Beast Mastery and Survival." },
		{ type = "checkbox", key = "check.marksman", label = "Marksmanship wants a pet too" },
		{ type = "checkbox", key = "check.passive", label = "Pet on Passive" },
		{ type = "checkbox", key = "check.growl", label = "Growl autocast",
			tooltip = "Growl on in a group with a tank, or off when you're alone in a delve." },
		{ type = "dropdown", key = "check.specs.dungeon", label = "Pet spec in dungeons", choices = SpecChoices,
			tooltip = "Ferocity brings Primal Rage (Bloodlust)." },
		{ type = "dropdown", key = "check.specs.raid", label = "Pet spec in raids", choices = SpecChoices },
		{ type = "dropdown", key = "check.specs.delve", label = "Pet spec in delves", choices = SpecChoices },
		{ type = "button", label = "Pet check", text = "Run", onClick = Check,
			tooltip = "Run the pet check now." },

		{ type = "header", label = "Data" },
		{ type = "button", label = "Tame log", text = "Clear", onClick = ResetSeen,
			confirm = "Forget every beast in the tame log?",
			tooltip = "Forget the beasts you've seen (your pets stay)." },
	},
})
ns.hunterModule = module
