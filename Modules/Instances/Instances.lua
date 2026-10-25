local addonName, ns = ...

-- Instances module: a difficulty picker at dungeon and raid portals, a readable difficulty badge on the minimap, a
-- lockout banner when you enter a dungeon or raid, a queue plate by the queue eye with who's found so far, and the
-- holiday dungeon selected in Dungeon Finder. Each piece is its own switch. Pure logic: Data.lua. Reader and the
-- difficulty setter: Read.lua. Pieces: Badge.lua, Entrance.lua, Queue.lua; the lockout banner lives here.
-- See docs/superpowers/specs/2026-10-22-tomte-enhanceqol-plumber-absorption-design.md (Phase 3).

local ENTER_DELAY = 2 -- seconds after zoning in before the instance info is read for the banner
local SAVES_WAIT = 3 -- seconds to wait for RequestRaidInfo's answer before the banner shows without it
local REPEAT_AFTER = 30 * 60 -- seconds before the same instance and difficulty gets a banner again (run-backs)

local events = ns.Instances_Events

local module, db
local bannerActive = false
local shown = {} -- [instanceID .. ":" .. difficultyID] = GetTime() of its last banner
local waiting -- the instance info a banner waits on (for UPDATE_INSTANCE_INFO)

-- Lockout banner --------------------------------------------------------------------------------------------------

local function Key(info)
	return tostring(info.instanceID) .. ":" .. tostring(info.difficultyID)
end

local function ShowBanner(info)
	waiting = nil
	if not bannerActive then
		return
	end
	local save = ns.Instances_SaveFor(ns.InstancesRead_Saves(info.instanceID), info.difficultyID)
	local text, role = ns.Instances_LockoutSummary(save)
	ns.Banner_Show({
		owner = "instances",
		label = info.difficultyName or "Instance",
		accent = role,
		title = info.name or "Instance",
		subtitle = text,
	})
end

local function CheckEntered()
	if not bannerActive or waiting then
		return
	end
	local info = ns.InstancesRead_Current()
	if (info.instanceType ~= "party" and info.instanceType ~= "raid") or not info.instanceID or info.keystone then
		return
	end
	local key = Key(info)
	if shown[key] and GetTime() - shown[key] < REPEAT_AFTER then
		return
	end
	shown[key] = GetTime()
	waiting = info
	RequestRaidInfo() -- answers with UPDATE_INSTANCE_INFO
	C_Timer.After(SAVES_WAIT, function()
		if waiting == info then
			ShowBanner(info)
		end
	end)
end

events:On("banner", "PLAYER_ENTERING_WORLD", function(_, _, isReload)
	if isReload then
		-- A /reload inside an instance isn't a zone-in: remember it so it doesn't get a banner.
		local info = ns.InstancesRead_Current()
		if info.instanceID then
			shown[Key(info)] = GetTime()
		end
		return
	end
	C_Timer.After(ENTER_DELAY, CheckEntered)
end)

events:On("banner", "UPDATE_INSTANCE_INFO", function()
	if waiting then
		ShowBanner(waiting)
	end
end)

local function BannerToggle(on)
	bannerActive = on
	if on then
		events:Watch("banner", "PLAYER_ENTERING_WORLD")
		events:Watch("banner", "UPDATE_INSTANCE_INFO")
	else
		events:UnwatchAll("banner")
		waiting = nil
		ns.Banner_Clear("instances")
	end
end

-- Switches --------------------------------------------------------------------------------------------------------

local function Apply()
	local on = module.active
	ns.InstancesEntrance_Toggle(on and db.entrance)
	ns.InstancesBadge_Toggle(on and db.badge)
	BannerToggle(on and db.banner)
	ns.InstancesQueue_Toggle(on and db.queue)
	ns.InstancesHoliday_Toggle(on and db.holiday)
end

-- Settings preview (Panel/Preview.lua): sample minimap badges, drawn in Badge.lua.
local function BadgePreview(host, get)
	return ns.InstancesBadge_DrawSample(host, get)
end

local function Why()
	ns.Print(ns.InstancesBadge_Why())
	ns.Print(ns.InstancesEntrance_Why())
	for _, line in ipairs(ns.InstancesQueue_Why()) do
		ns.Print(line)
	end
	local ok, reason = ns.InstancesRead_CanChoose()
	ns.Print("difficulty: " .. (ok and "you can change it" or reason))
end

module = ns.RegisterModule({
	key = "instances",
	name = "Instances",
	category = "social",
	icon = 255345, -- achievement_dungeon_gloryofthehero
	summary = "Pick difficulty at the portal, see it on the minimap, and follow your queue.",
	description = "Near a dungeon or raid portal, a small card to pick Normal, Heroic or Mythic with your lockout on "
		.. "each. Readable difficulty on the minimap in place of Blizzard's flag (click it outside an instance to "
		.. "change difficulty), a banner with your lockout when you enter a dungeon or raid, a panel by the queue "
		.. "eye with your time in queue and who's been found so far, and the holiday or Timewalking dungeon "
		.. "picked for you the first time you open Dungeon Finder.",
	enabledByDefault = true,
	toasts = "Instance lockout (banners)",
	replaces = {
		{ addon = "Plumber", why = "the difficulty picker at portals, queue status and the holiday dungeon" },
		{ addon = "EnhanceQoL", why = "the difficulty text" },
	},
	defaults = {
		entrance = true,
		badge = true,
		badgeOutside = true,
		banner = true,
		queue = true,
		holiday = true,
		entranceFrame = { point = "TOP", relPoint = "TOP", x = 0, y = -140 }, -- InstancesEntrance_ResetPosition repeats it
	},
	init = function(saved)
		db = saved
		ns.InstancesEntrance_Init(db)
		ns.InstancesBadge_Init(db)
	end,
	toggle = Apply,
	commands = {
		{ "why", "what the badge, the portal card, the queue plate and the holiday pick see right now", Why },
	},
	options = {
		{ type = "header", label = "At the portal" },
		{ type = "checkbox", key = "entrance", label = "Difficulty picker", onChange = Apply,
			preview = ns.Preview_When("entrance", function(host)
				return ns.InstancesEntrance_DrawSample(host)
			end), tooltip = "Near a dungeon or raid portal, a small card to pick Normal, Heroic or Mythic, with your lockout under each. Only the group leader can change it; in a group you see it read-only. Blizzard's Edit Mode moves it." },
		{ type = "button", label = "Position", text = "Reset", onClick = ns.InstancesEntrance_ResetPosition,
			parent = "entrance", tooltip = "Move the card back to the top of the screen." },
		{ type = "checkbox", key = "banner", label = "Lockout banner", onChange = Apply,
			tooltip = "When you enter a dungeon or raid: its difficulty, and whether you're saved and how many bosses are down." },

		{ type = "header", label = "Minimap" },
		{ type = "checkbox", key = "badge", label = "Difficulty badge", onChange = Apply,
			preview = ns.Preview_When("badge", BadgePreview),
			tooltip = "Readable text in place of Blizzard's difficulty flag: 5 · H, 20 · M, M+12, D8, LFR, TW." },
		{ type = "checkbox", key = "badgeOutside", label = "Outside instances too",
			onChange = ns.InstancesBadge_Refresh, parent = "badge",
			tooltip = "Show the dungeon and raid difficulty you've chosen (H / M). Click it to change them." },

		{ type = "header", label = "Dungeon Finder" },
		{ type = "checkbox", key = "queue", label = "Queue plate", onChange = Apply,
			preview = ns.Preview_When("queue", function(host)
				return ns.InstancesQueue_DrawSample(host)
			end), tooltip = "A small panel by the queue eye with your time in queue, the average wait, and a role icon for each place in the group that lights up when it's filled." },
		{ type = "checkbox", key = "holiday", label = "Pick the holiday dungeon", onChange = Apply,
			tooltip = "The first time you open Dungeon Finder in a session, select the holiday boss or Timewalking dungeon when one is up." },
	},
})
