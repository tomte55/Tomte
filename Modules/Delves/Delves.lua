local addonName, ns = ...

-- Delves module: today's bountiful delves with a click to track them, Restored Coffer Keys and shards, the delve tier
-- that raises the Great Vault's World slots, and the companion's level, role and curios. A page in the Tomte window,
-- a note beside the tier picker, an "Around you" block, three Next up sources and a companion level moment.
-- Pure logic: Data.lua. Readers: Scan.lua, Read.lua. See docs/superpowers/specs/2026-10-10-tomte-delves-design.md.

local module, db

local NEXT_BOUNTIFUL_CHOICES = {
	{ value = "key", text = "With a key" },
	{ value = "always", text = "Always" },
}

local events = ns.Delves_Events

local function Open()
	ns.Panel_OpenPage("delves")
end

-- After a read or a new scan: redraw what shows it.
function ns.Delves_Changed()
	ns.DelvesPage_Refresh()
	ns.DelvesEntrance_Refresh()
	if ns.Panel_IsShown() then
		ns.Panel_Refresh()
	end
end

local refreshScan = ns.UI.Debounce(1, function()
	ns.DelvesScan_Invalidate()
	ns.Delves_Changed()
end)

-- Events ---------------------------------------------------------------------------------------------------------

events:On("delves", "PLAYER_ENTERING_WORLD", function()
	refreshScan()
	ns.DelvesRead_Dirty()
end)
events:On("delves", "ZONE_CHANGED_NEW_AREA", refreshScan)
events:On("delves", "AREA_POIS_UPDATED", refreshScan)

local function KeysChanged()
	ns.DelvesRead_Dirty("keys")
end
events:On("delves", "CURRENCY_DISPLAY_UPDATE", KeysChanged)
events:On("delves", "BAG_UPDATE_DELAYED", KeysChanged)

events:On("delves", "WEEKLY_REWARDS_UPDATE", function()
	ns.DelvesRead_Dirty("vault")
end)

local function CompanionChanged()
	ns.DelvesRead_Dirty("companion")
end
events:On("delves", "UPDATE_FACTION", CompanionChanged)
events:On("delves", "TRAIT_CONFIG_UPDATED", CompanionChanged)
events:On("delves", "DELVES_ACCOUNT_DATA_ELEMENT_CHANGED", CompanionChanged)
events:On("delves", "PLAYER_SPECIALIZATION_CHANGED", CompanionChanged)

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "AREA_POIS_UPDATED", "CURRENCY_DISPLAY_UPDATE",
	"BAG_UPDATE_DELAYED", "WEEKLY_REWARDS_UPDATE", "UPDATE_FACTION", "TRAIT_CONFIG_UPDATED",
	"DELVES_ACCOUNT_DATA_ELEMENT_CHANGED",
}

local function Toggle(active)
	if active then
		for _, event in ipairs(EVENTS) do
			events:Watch("delves", event)
		end
		events:Watch("delves", "PLAYER_SPECIALIZATION_CHANGED", "player")
		ns.DelvesScan_Invalidate()
		ns.DelvesRead_Dirty()
	else
		events:UnwatchAll("delves")
		ns.DelvesRead_Stop()
	end
	ns.DelvesEntrance_Toggle(active)
end

-- Shared bits ----------------------------------------------------------------------------------------------------

local function Keys()
	local k = ns.DelvesRead_State().keys
	return k and k.keys or nil
end

local function CountBountiful(list)
	local n = 0
	for _, e in ipairs(list) do
		if e.bountiful then
			n = n + 1
		end
	end
	return n
end

local function Here()
	local zone = ns.DelvesScan_PlayerZone()
	local list = {}
	if not zone then
		return list
	end
	for _, e in ipairs(ns.DelvesScan_List()) do
		if e.map == zone then
			list[#list + 1] = e
		end
	end
	return list
end

local function Summary()
	local minLevel = ns.DelvesScan_MinLevel()
	if minLevel then
		return ("Delves open at level %d"):format(minLevel)
	end
	local n = CountBountiful(ns.DelvesScan_List())
	local keys = Keys()
	local text = n .. " bountiful"
	if keys then
		text = text .. (" · %d %s"):format(keys, keys == 1 and "key" or "keys")
	end
	return text
end

local function TrackRow(e)
	return {
		icon = e.bountiful and ns.Delves_KeyIcon() or ns.DELVES_ICON,
		text = e.name,
		right = e.bountiful and "Bountiful" or nil,
		rightColor = e.bountiful and "accent" or nil,
		color = e.bountiful and "accent" or nil,
		onClick = function()
			ns.Delves_Track(e)
		end,
		onEnter = function(row)
			ns.Delves_Tooltip(row, e)
		end,
	}
end

-- Home entries ---------------------------------------------------------------------------------------------------

local PAGE = { kind = "page", key = "delves", order = 8, name = "Delves", icon = ns.DELVES_ICON,
	page = ns.DelvesPage, summary = Summary }

local AROUND = { kind = "around", key = "delvesaround", order = 6, name = "Delves", maxRows = 3,
	icon = ns.DELVES_ICON, open = Open, openText = "Opens the Delves page",
	title = function()
		local here = Here()
		local n = CountBountiful(here)
		if n > 0 then
			return ("Delves: %d bountiful here"):format(n)
		end
		return ("Delves: %d here"):format(#here)
	end,
	items = function(limit)
		local rows = {}
		if not db.around then
			return rows
		end
		for _, e in ipairs(Here()) do
			if #rows >= limit then
				break
			end
			rows[#rows + 1] = TrackRow(e)
		end
		return rows
	end }

local NEXT_BOUNTIFUL = { kind = "next", key = "nextbountiful", name = "Bountiful delve with a key", score = 60,
	description = "A bountiful delve is up today (click to track it). With the Delves setting \"Suggest bountiful "
		.. "delves\" on \"With a key\", only while you hold a Restored Coffer Key.",
	candidates = function()
		local list = {}
		if not ns.Delves_SuggestBountiful(Keys(), db.nextBountiful) then
			return list
		end
		local zone = ns.DelvesScan_PlayerZone()
		local keyLine = ns.DelvesRead_State().keyLine
		for _, e in ipairs(ns.DelvesScan_List()) do
			if e.bountiful then
				local where = ns.DelvesScan_ZoneName(e.map) or ""
				list[#list + 1] = {
					key = "delves:bountiful:" .. e.poi,
					text = "Bountiful delve: " .. (e.name or "?"),
					why = keyLine and (where .. " · " .. keyLine) or where,
					icon = ns.Delves_KeyIcon(),
					bonus = e.map == zone and 9 or 0,
					onClick = function()
						ns.Delves_Track(e)
					end,
					hint = "Click to track it",
				}
			end
		end
		return list
	end }

local NEXT_TIER = { kind = "next", key = "nextdelvetier", name = "Delve tier for your vault", score = 55,
	description = "A World slot of your Great Vault is unlocked but pays for a delve tier below the top: the tier "
		.. "and runs that max it.",
	candidates = function()
		local vault = ns.DelvesRead_State().vault
		local a = vault and vault.plan.advice
		if not (a and a.unlocked and ns.ContentAtMax()) then
			return {}
		end
		return { {
			key = "delves:tier:" .. a.index, state = a.tier, text = vault.plan.text,
			why = ns.Delves_LadderText(vault.ladder), icon = ns.DELVES_ICON,
			onClick = Open, stay = true,
		} }
	end }

local NEXT_ROLE = { kind = "next", key = "nextcompanionrole", name = "Companion role", score = 45,
	description = "Your delve companion has the same role as you (a tank with a tanking Brann).",
	candidates = function()
		local hint = ns.DelvesRead_RoleHint()
		local c = ns.DelvesRead_State().companion
		if not hint then
			return {}
		end
		return { {
			key = "delves:role", state = c and c.role, text = hint, icon = ns.DELVES_ICON,
			onClick = Open, stay = true,
		} }
	end }

-- Commands -------------------------------------------------------------------------------------------------------

local function List()
	local minLevel = ns.DelvesScan_MinLevel()
	if minLevel then
		ns.Print(("delves open at level %d."):format(minLevel))
		return
	end
	local list = ns.DelvesScan_List()
	ns.Print(("delves (%s): %d, %d bountiful."):format(ns.ExpansionName(ns.ContentExpansion()), #list,
		CountBountiful(list)))
	for _, e in ipairs(list) do
		local name = e.bountiful and ns.UI.Wrap(e.name .. " (bountiful)", "accent") or e.name
		print(("  %s, %s"):format(name, ns.DelvesScan_ZoneName(e.map) or "?"))
	end
	local keyLine = ns.DelvesRead_State().keyLine
	if keyLine then
		print("  " .. keyLine)
	end
end

local function Vault()
	local vault = ns.DelvesRead_State().vault
	if not vault then
		ns.Print("the Great Vault isn't read yet; try again in a moment.")
		ns.DelvesRead_Dirty("vault")
		return
	end
	ns.Print(("Great Vault, World (top tier %d):"):format(vault.top))
	for _, row in ipairs(vault.plan.rows) do
		print(("  slot %d: %s, %s"):format(row.index,
			row.unlocked and ("Tier " .. (row.tier or 1)) or ("locked (%d runs)"):format(row.threshold),
			row.maxed and "maxed" or (row.need .. " more at the top")))
	end
	if vault.plan.text then
		print("  " .. vault.plan.text)
	end
	print("  " .. (ns.Delves_LadderText(vault.ladder) or "no item level ladder from the game"))
end

-- /tomte data --------------------------------------------------------------------------------------------------

ns.Content_AddCheck("delves", function(expansion)
	local def = ns.Content_Get(expansion, "delves")
	if not def then
		return { ("!no delves table for %s"):format(ns.ExpansionName(expansion)) }
	end
	ns.DelvesScan_Invalidate()
	local list = ns.DelvesScan_List()
	local zones = {}
	for _, e in ipairs(list) do
		zones[e.map] = true
	end
	local nZones = 0
	for _ in pairs(zones) do
		nZones = nZones + 1
	end
	local lines = { ("%d of %d zones with delves, %d delves, %d bountiful"):format(nZones, #def.zones, #list,
		CountBountiful(list)) }
	local seasonFaction, seasonExpansion, companionID = ns.DelvesRead_Season()
	local c = ns.DelvesRead_State().companion
	lines[#lines + 1] = ("companion: %s (season faction %s, expansion %s, companion ID %s; season %s)"):format(
		c and ("%s level %d"):format(c.name, c.level) or "none read", tostring(seasonFaction),
		tostring(seasonExpansion), tostring(companionID),
		tostring(C_DelvesUI and C_DelvesUI.GetCurrentDelvesSeasonNumber and C_DelvesUI.GetCurrentDelvesSeasonNumber()))
	if c and not c.companionID then
		lines[#lines] = lines[#lines] .. ", level only"
	end
	return lines
end)

module = ns.RegisterModule({
	key = "delves",
	name = "Delves",
	category = "World",
	description = "Today's bountiful delves with a click to track them, your coffer keys and shards, the delve tier "
		.. "that raises your Great Vault's World slots, and your companion's level, role and curios. A note beside "
		.. "the tier picker at a delve entrance.",
	enabledByDefault = true,
	defaults = { around = true, entrance = true, roleHint = true, nextBountiful = "key", companionLevel = {} },
	init = function(saved)
		db = saved
		ns.DelvesRead_Init(db)
		ns.DelvesEntrance_Init(db)
	end,
	toggle = Toggle,
	home = { PAGE, AROUND, NEXT_BOUNTIFUL, NEXT_TIER, NEXT_ROLE },
	options = {
		{ type = "checkbox", key = "around", label = "Delves in Around you", onChange = ns.Delves_Changed,
			tooltip = "The delves in your zone on Home, bountiful first. Click one to track it." },
		{ type = "checkbox", key = "entrance", label = "Note at the delve entrance",
			tooltip = "Beside the tier picker: the tier for your vault and your gear, your keys and your companion." },
		{ type = "checkbox", key = "roleHint", label = "Companion role hint", onChange = ns.Delves_Changed,
			tooltip = "Say so when your companion has the same role as you (a tank with a tanking Brann)." },
		{ type = "dropdown", key = "nextBountiful", label = "Suggest bountiful delves", onChange = ns.Delves_Changed,
			choices = function()
				return NEXT_BOUNTIFUL_CHOICES
			end,
			tooltip = "Next up's bountiful delve suggestion: only while you hold a Restored Coffer Key, or always "
				.. "(without a key a bountiful delve is a normal run)." },
		{ type = "button", label = "Page", text = "Open", onClick = Open },
	},
	commands = {
		{ "", "open the Delves page", Open, hidden = true },
		{ "open", "open the Delves page", Open },
		{ "list", "today's delves (bountiful marked) and your keys, in chat", List },
		{ "vault", "the Great Vault World plan and the tier ladder, in chat", Vault },
	},
})
