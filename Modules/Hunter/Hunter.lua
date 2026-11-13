local addonName, ns = ...

-- Hunter Pets module: Call Pet tooltips, a Stable tab (pets, families, tame log), a tame-log line on beast
-- tooltips, and a pet readiness check for dungeons, raids, delves and ready checks. Hunters only.
-- Stable.lua reads the stable, StablePage.lua draws the tab, Tooltips.lua and Checks.lua do what their names say,
-- pure logic is in Data.lua.

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "READY_CHECK", "PET_STABLE_SHOW", "PET_STABLE_UPDATE",
	"PET_SPECIALIZATION_CHANGED", "GROUP_ROSTER_UPDATE",
}

local module

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function(self, event, ...)
	self[event](self, ...)
end))

function events:PLAYER_ENTERING_WORLD()
	ns.Stable_OnEnterWorld()
	ns.Checks_OnEnterWorld()
	ns.Checks_GrowlSoon()
end

function events:GROUP_ROSTER_UPDATE()
	ns.Checks_GrowlSoon()
end

function events:READY_CHECK()
	ns.Checks_OnReadyCheck()
end

function events:UNIT_PET(unit)
	if unit == "player" then
		ns.Stable_Refresh()
		ns.Checks_GrowlSoon()
	end
end

events.PET_STABLE_SHOW = ns.Stable_Refresh
events.PET_STABLE_UPDATE = ns.Stable_Refresh
events.PET_SPECIALIZATION_CHANGED = ns.Stable_Refresh

-- Tame Beast is a channel; START too in case that ever changes.
function events:UNIT_SPELLCAST_CHANNEL_START(_, _, spellID)
	ns.Stable_OnSpellcast(spellID)
end
events.UNIT_SPELLCAST_START = events.UNIT_SPELLCAST_CHANNEL_START

local function IsHunter()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

local function Check()
	if not ns.Module_RequireOn(module) then
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
	category = "class",
	icon = 132161, -- ability_hunter_beastcall
	summary = "Pet tooltips, a stable overview and a pet check before you pull.",
	description = "Call Pet tooltips, a Stable tab with your pets and a tame log of beasts you've seen, and a pet check when you enter a "
		.. (ns.FOREVER and "dungeon or raid" or "dungeon, raid or delve") .. " and on ready checks.",
	enabledByDefault = true,
	toasts = "Hunter pet check (banners)",
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
			happy = true, -- only Forever's pets have happiness
			growl = true,
			growlSolo = true, -- a toast when Growl is left off, alone in the open world
			specs = { dungeon = "Ferocity", raid = "any", delve = "any" },
		},
		aspect = true, -- Forever: the aspect button (Aspect.lua)
		aspectTravel = true, -- the aspect button suggests Cheetah when you're travelling
		aspectFrame = { point = "CENTER", relPoint = "CENTER", x = 0, y = -140 }, -- its spot (Edit Mode)
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
			events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
			events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
			events:RegisterUnitEvent("UNIT_PET", "player") -- not every group member's pet
			if ns.inWorld then
				ns.Stable_Refresh()
			end
			if ns.HunterAspect_Start then -- Forever only (Aspect.lua)
				ns.HunterAspect_Start(ns.hunterDB)
			end
		else
			events:UnregisterAllEvents()
			if ns.HunterAspect_Stop then
				ns.HunterAspect_Stop()
			end
			ns.Banner_Clear("hunter")
		end
	end,
	home = {
		{ kind = "page", key = "stable", noRail = true, order = 3, name = "Stable", icon = "Interface\\Icons\\Ability_Hunter_BeastCall",
			page = ns.StablePage,
			summary = function()
				local snapshot = ns.Stable_Snapshot()
				if not snapshot then
					return "Visit a stable master to read your pets"
				end
				local n = ns.Hunter_PetCount(snapshot)
				return n == 1 and "1 pet" or (n .. " pets")
			end },
	},
	commands = {
		{ "check", "run the pet check now", Check },
		{ "aspect", "what the aspect button sees (World of Warcraft: Forever)", function()
			if ns.Module_RequireOn(module) and ns.HunterAspect_Why then
				ns.HunterAspect_Why()
			end
		end },
	},
	options = {
		{ type = "header", label = "Tooltips" },
		{ type = "checkbox", key = "callPetTooltip", label = "Call Pet tooltips",
			tooltip = ns.FOREVER and "The Call Pet tooltip shows your pet's name, family and loyalty."
				or "Call Pet 1-5 tooltips show the pet's name, family, spec and spec ability." },
		{ type = "checkbox", key = "tameTooltip", label = "Tame log on beasts",
			tooltip = "Beast tooltips show their family and whether you have it, and every beast you hover goes into the tame log on the Stable tab." },

		{ type = "header", label = "Aspects", shown = function()
			return ns.FOREVER
		end },
		{ type = "checkbox", key = "aspect", label = "Aspect button", onChange = function()
			ns.HunterAspect_Update()
		end, shown = function()
			return ns.FOREVER
		end, tooltip = "A button when no aspect is on, out of combat and away from inns and cities. One click puts on "
			.. "Aspect of the Hawk, or the Monkey before you learn the Hawk. With Cheetah or Pack on, it comes back as "
			.. "you target something to fight, or as a fight starts, to swap to the Hawk: they daze you when you're "
			.. "hit. Also a key binding (Key Bindings > Tomte). Blizzard's Edit Mode moves it." },
		{ type = "checkbox", key = "aspectTravel", label = "Cheetah when travelling", parent = "aspect",
			onChange = function()
				ns.HunterAspect_Update()
			end, shown = function()
				return ns.FOREVER
			end, tooltip = "Once you've been on the move for a while out of combat (sooner when the quest you follow is "
				.. "far), the button offers Aspect of the Cheetah, in cities too. Close to a quest you'll fight at, it "
				.. "offers the Hawk again. Not in dungeons, and not while you have something to fight targeted." },

		{ type = "header", label = "Pet check" },
		{ type = "checkbox", key = "check.onEnter", label = "When entering an instance",
			tooltip = "Check a few seconds after entering a "
				.. (ns.FOREVER and "dungeon or raid." or "dungeon, raid or delve.") },
		{ type = "checkbox", key = "check.onReadyCheck", label = "On ready checks" },
		{ type = "checkbox", key = "check.banner", label = "Banner and sound",
			tooltip = "Show problems as a banner with a warning sound. Off: chat only." },
		{ type = "checkbox", key = "check.noPet", label = "No pet or dead pet",
			tooltip = not ns.FOREVER and "For Beast Mastery and Survival." or nil },
		{ type = "checkbox", key = "check.marksman", label = "Marksmanship wants a pet too", shown = ns.NotForever },
		{ type = "checkbox", key = "check.passive", label = "Pet on Passive" },
		{ type = "checkbox", key = "check.happy", label = "Pet not happy",
			shown = function()
				return ns.FOREVER
			end, tooltip = "An unhappy pet does less damage and loses loyalty. Feed Pet fixes it." },
		{ type = "checkbox", key = "check.growl", label = "Growl autocast",
			tooltip = ns.FOREVER and "Growl on in a group that has a tank."
				or "Growl on in a group with a tank, or off when you're alone in a delve." },
		{ type = "checkbox", key = "check.growlSolo", label = "Growl left off",
			tooltip = "A toast when your pet is out with Growl's autocast off and you're alone in the open world, as after a dungeon. Once, until Growl has been on again." },
		-- Forever's pets have no specs (Blizzard's camelot stable shows none), and it has no delves.
		{ type = "dropdown", key = "check.specs.dungeon", label = "Pet spec in dungeons", choices = SpecChoices,
			shown = ns.NotForever, tooltip = "Ferocity brings Primal Rage (Bloodlust)." },
		{ type = "dropdown", key = "check.specs.raid", label = "Pet spec in raids", choices = SpecChoices,
			shown = ns.NotForever },
		{ type = "dropdown", key = "check.specs.delve", label = "Pet spec in delves", choices = SpecChoices,
			shown = ns.NotForever },
		{ type = "button", label = "Pet check", text = "Run", onClick = Check,
			tooltip = "Run the pet check now." },

		{ type = "header", label = "Data" },
		{ type = "button", label = "Tame log", text = "Clear", onClick = ResetSeen,
			confirm = "Forget every beast in the tame log?",
			tooltip = "Forget the beasts you've seen (your pets stay)." },
	},
})
ns.hunterModule = module
