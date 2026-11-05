local addonName, ns = ...

-- Expansion summary module: one page with where this character stands in its expansion this week (Great Vault,
-- upgrade crests, raid kills, renown factions, open weekly activities), and a minimap button for it. It reads the
-- Weekly board's readers (read-only ns.Weekly_* exports), never its own copies. Rows in Data.lua, page in Page.lua.

local ICON = 134331 -- inv_misc_note_05
-- What changes the page; each redraws it (debounced) only while it's shown.
local EVENTS = { "WEEKLY_REWARDS_UPDATE", "CURRENCY_DISPLAY_UPDATE", "UPDATE_INSTANCE_INFO",
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "UPDATE_FACTION", "QUEST_TURNED_IN", "QUEST_REMOVED" }

local UI = ns.UI

local events = CreateFrame("Frame")
events:SetScript("OnEvent", ns.Perf_WrapEvents(function()
	ns.SummaryPage_Refresh()
end))

local function Toggle()
	if ns.SummaryPage_IsShown() then
		ns.Panel_Hide()
	else
		ns.Panel_OpenPage("summary")
	end
end

local function Tooltip(tooltip)
	local s = ns.Summary_Read()
	for _, line in ipairs(ns.Summary_TooltipLines(s)) do
		tooltip:AddLine(line.text, UI.RGB(line.role))
	end
	tooltip:AddLine("Click to open or close the summary", UI.RGB("accent"))
end

ns.RegisterModule({
	key = "summary",
	name = "Expansion summary",
	category = "week",
	icon = ICON,
	summary = "Your expansion at a glance: vault, crests, raids, factions and this week's activities.",
	description = "One page with where the character you're playing stands this week in its expansion: Great Vault "
		.. "slots, upgrade crests against their cap, raid bosses killed per difficulty and world bosses, renown "
		.. "factions with their next rewards, and the weekly activities still open. Open it from the Tomte window "
		.. "or its minimap button. It reads the same data as the Weekly board, which has the full detail and your "
		.. "other characters.",
	enabledByDefault = true,
	replaces = { { addon = "Plumber", why = "the expansion summary (landing page) with factions, activities, raids and the vault" } },
	minimapButton = {
		name = "Expansion summary",
		icon = ICON,
		onClick = Toggle,
		tooltip = Tooltip,
	},
	toggle = function(active)
		if active then
			for _, event in ipairs(EVENTS) do
				events:RegisterEvent(event)
			end
		else
			events:UnregisterAllEvents()
		end
	end,
	home = {
		-- Short for the rail (the full name runs past it); the page's own heading says "Expansion summary".
		{ kind = "page", key = "summary", order = 3, name = "Expansion", icon = ICON, page = ns.SummaryPage,
			summary = function()
				local s = ns.Summary_Read()
				return ns.Summary_HomeText(s.vault, s.vaultReady)
			end },
	},
	options = {},
	commands = {
		{ "open", "open the expansion summary", function()
			ns.Panel_OpenPage("summary")
		end },
	},
})
