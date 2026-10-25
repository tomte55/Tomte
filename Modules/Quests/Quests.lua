local addonName, ns = ...

-- Quests: accepts and hands in quests and picks gossip for you (Automation.lua, with the ignore entry in the
-- target's menu in Menu.lua), race medals on the timekeeper's gossip (Medals.lua), skips cinematics
-- (Cinematics.lua), quiets the Talking Head (TalkingHead.lua) and explains quest-starting items (Items.lua).
-- Pure rules in Data.lua, reads in Read.lua, event IDs per expansion in Data/<Expansion>/Quests.lua. This file
-- owns db, starts and stops the pieces and registers the module.

local SKIP_KEY_CHOICES = { { value = "shift", text = "Shift" }, { value = "ctrl", text = "Ctrl" },
	{ value = "alt", text = "Alt" } }
local CINEMATIC_CHOICES = { { value = "off", text = "Off" }, { value = "seen", text = "Ones you've seen" },
	{ value = "all", text = "All" } }
local TALKING_HEAD_CHOICES = { { value = "off", text = "Blizzard's" }, { value = "hide", text = "Hide" },
	{ value = "text", text = "Text only" } }

local module, db

local function Start()
	ns.QuestsAuto_Start(db)
	ns.QuestsMenu_Start()
	ns.QuestsMedals_Start(db)
	ns.QuestsCinematics_Start(db)
	ns.QuestsTalkingHead_Start(db)
	ns.QuestsItems_Start(db)
end

local function Stop()
	ns.QuestsAuto_Stop()
	ns.QuestsMenu_Stop()
	ns.QuestsMedals_Stop()
	ns.QuestsCinematics_Stop()
	ns.QuestsTalkingHead_Stop()
	ns.QuestsItems_Stop()
end

local function Command(fn)
	return function(arg)
		if ns.Module_RequireOn(module) then
			fn(arg)
		end
	end
end

local function IgnoreCommand(arg)
	arg = arg and arg:match("^%s*(.-)%s*$") or ""
	if arg == "clear" then
		wipe(db.ignored)
		ns.Print("the ignore list is empty.")
		return
	end
	local npcID = tonumber(arg)
	if not npcID then
		ns.QuestsAuto_PrintIgnored()
		return
	end
	if db.ignored[npcID] then
		ns.QuestsAuto_ToggleIgnore(npcID, type(db.ignored[npcID]) == "string" and db.ignored[npcID] or nil)
	else
		ns.Print(("NPC %d isn't on the ignore list."):format(npcID))
	end
end

local function TalkingHeadIs(...)
	for i = 1, select("#", ...) do
		if db.talkingHead == select(i, ...) then
			return true
		end
	end
	return false
end

local function TextSize(v)
	return v .. " pt"
end

-- Settings preview (Panel/Preview.lua): the "Text only" subtitle with a sample line.
local function TalkingHeadPreview(host, get, choosing)
	return ns.QuestsTalkingHead_DrawSample(host, get, choosing)
end

module = ns.RegisterModule({
	key = "quests",
	name = "Quests",
	category = "quests",
	icon = 236669, -- achievement_quests_completed_06
	summary = "Accepts and hands in quests, picks gossip and skips cinematics you've seen.",
	description = "Talk to an NPC and Tomte accepts its quests, hands in the finished ones and picks the gossip option that moves a quest on. Hold Shift (or your skip key) to do it yourself. Also skips cinematics you've already seen, can quiet the Talking Head, shows your race medals at skyriding timekeepers and tells you which quest an item starts.",
	enabledByDefault = false,
	conflicts = { { addon = "EnhanceQoL", why = "both accept and hand in quests: turn off one of them" } },
	replaces = {
		{ addon = "EnhanceQoL", why = "quest and gossip automation, and skipping cinematics" },
		{ addon = "Plumber", why = "the Talking Head, quest item alerts and tooltips, event sign-ups and race medals" },
	},
	defaults = {
		auto = true,
		skipKey = "shift",
		announce = false,
		skipRepeatable = true,
		skipTrivial = false,
		skipCosts = true,
		skipDoneElsewhere = false,
		ignored = {}, -- [NPC ID] = NPC name (true when the name couldn't be read)
		pickReward = false,
		gossipStep = true,
		gossipOnly = true,
		gossipEvents = true,
		raceMedals = true,
		cinematics = "seen", -- "off", "seen" or "all"
		inEngine = false,
		quickSkip = true,
		seenMovies = {}, -- [movie ID] = true, account-wide
		talkingHead = "off", -- "off" (Blizzard's), "hide" or "text"
		thChat = true,
		thHideInstance = false,
		thHideWorldQuest = false,
		thSize = 14,
		-- TalkingHead.lua's ResetPosition repeats this position.
		thFrame = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 200 },
		itemDelete = true,
		itemTooltip = true,
	},
	init = function(moduleDB)
		db = moduleDB
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "why", "why the last NPC's quests and gossip were or weren't done for you", Command(function()
			ns.QuestsAuto_PrintWhy()
		end) },
		{ "ignore", "list the NPCs left to you; ignore <ID> takes one off, ignore clear empties the list",
			Command(IgnoreCommand) },
	},
	options = {
		{ type = "header", label = "Accept and hand in" },
		{ type = "checkbox", key = "auto", label = "Accept and hand in quests",
			tooltip = "When you talk to an NPC, finished quests are handed in and new ones accepted. Gossip options below are picked too." },
		{ type = "dropdown", key = "skipKey", label = "Hold to do it yourself", parent = "auto", choices = function()
			return SKIP_KEY_CHOICES
		end, tooltip = "Hold this key while you start talking: nothing is done for you until that NPC's window closes." },
		{ type = "checkbox", key = "announce", label = "Say in chat what was done", parent = "auto",
			tooltip = "A chat line for each quest accepted or finished and each gossip option picked. /tomte quests why explains the last NPC either way." },
		{ type = "checkbox", key = "skipRepeatable", label = "Leave daily and weekly quests to me", parent = "auto",
			tooltip = "Daily, weekly and other repeatable quests are neither accepted nor handed in for you." },
		{ type = "checkbox", key = "skipTrivial", label = "Leave low-level quests to me", parent = "auto",
			tooltip = "Grey quests, far below your level." },
		{ type = "checkbox", key = "skipCosts", label = "Leave quests that cost gold to me", parent = "auto",
			tooltip = "Hand-ins that take gold or a currency wait for you to click." },
		{ type = "checkbox", key = "skipDoneElsewhere", label = "Leave quests done on an alt to me", parent = "auto",
			tooltip = "Quests another character of your account has already done." },
		{ type = "checkbox", key = "pickReward", label = "Pick the reward for me", parent = "auto",
			tooltip = "When a quest lets you choose, take the one Gear Check calls a clear upgrade. When Gear Check is off or not sure, the choice stays yours." },
		{ type = "button", label = "Ignored NPCs", text = "Clear", parent = "auto",
			confirm = "Let Tomte handle quests at every NPC again?", onClick = function()
				wipe(db.ignored)
				ns.Print("the ignore list is empty.")
			end,
			tooltip = "Right-click a targeted NPC's portrait and pick \"Don't automate quests here\" to leave an NPC to you. /tomte quests ignore lists them." },

		{ type = "header", label = "Talking to NPCs" },
		{ type = "checkbox", key = "gossipStep", label = "Pick the quest step", parent = "auto",
			tooltip = "The one gossip option marked as part of a quest." },
		{ type = "checkbox", key = "gossipOnly", label = "Pick the only option", parent = "auto",
			tooltip = "When an NPC offers just one thing to say, say it (once per conversation)." },
		{ type = "checkbox", key = "gossipEvents", label = "Sign up for events", parent = "auto",
			tooltip = "Join events like the Theater Troupe and Time Rifts when you talk to their NPC." },
		{ type = "checkbox", key = "raceMedals", label = "Race medals at timekeepers",
			tooltip = "At a skyriding race start, each course in the timekeeper's list shows the medal you've earned on it." },

		{ type = "header", label = "Cinematics" },
		{ type = "dropdown", key = "cinematics", label = "Skip cinematics", choices = function()
			return CINEMATIC_CHOICES
		end, tooltip = "Ones you've seen: a movie plays the first time and is skipped after that." },
		{ type = "checkbox", key = "inEngine", label = "Also skip in-engine cutscenes", shown = function()
			return db.cinematics == "seen"
		end, tooltip = "Cutscenes played in the game world can't be told apart, so Tomte can't know whether you've seen one. On: they're always skipped." },
		{ type = "checkbox", key = "quickSkip", label = "Skip with one key press",
			tooltip = "Space, Enter or Esc ends a cutscene or movie at once, without \"Are you sure?\"." },
		{ type = "button", label = "Movies you've seen", text = "Forget",
			confirm = "Play every movie again the next time?", onClick = function()
				local n = 0
				for _ in pairs(db.seenMovies) do
					n = n + 1
				end
				wipe(db.seenMovies)
				ns.Print(("forgot %d movies: each plays once more."):format(n))
			end },

		{ type = "header", label = "Talking Head" },
		{ type = "dropdown", key = "talkingHead", label = "Talking Head", choices = function()
			return TALKING_HEAD_CHOICES
		end, onChange = function()
			ns.QuestsTalkingHead_Apply()
		end, preview = TalkingHeadPreview, tooltip = "Hide: you only hear the voice. Text only: the line shows as a plain subtitle instead of the portrait frame." },
		{ type = "checkbox", key = "thChat", label = "Write hidden lines in chat", shown = function()
			return TalkingHeadIs("hide", "text")
		end },
		{ type = "checkbox", key = "thHideInstance", label = "No text in instances", shown = function()
			return TalkingHeadIs("text")
		end, tooltip = "In dungeons, raids and delves you only hear the voice." },
		{ type = "checkbox", key = "thHideWorldQuest", label = "No text for world quests", shown = function()
			return TalkingHeadIs("text")
		end, tooltip = "Lines that start while you're in a world quest's area, or right after taking or finishing one." },
		{ type = "slider", key = "thSize", label = "Text size", min = 11, max = 20, step = 1, format = TextSize,
			preview = TalkingHeadPreview, shown = function()
				return TalkingHeadIs("text")
			end },
		{ type = "button", label = "Sample line", text = "Show", shown = function()
			return TalkingHeadIs("text")
		end, onClick = function()
			ns.QuestsTalkingHead_Test()
		end },
		{ type = "button", label = "Text position", text = "Reset", shown = function()
			return TalkingHeadIs("text")
		end, onClick = function()
			ns.QuestsTalkingHead_ResetPosition()
		end, tooltip = "Back to just above the action bars. Blizzard's Edit Mode moves it too." },

		{ type = "header", label = "Quest items" },
		{ type = "checkbox", key = "itemDelete", label = "Name the quest when deleting",
			tooltip = "Deleting an item that starts a quest shows which quest, and whether you've done it." },
		{ type = "checkbox", key = "itemTooltip", label = "Quest on item tooltips",
			tooltip = "Items in your bags that start a quest name it, and where you stand with it." },
	},
})
