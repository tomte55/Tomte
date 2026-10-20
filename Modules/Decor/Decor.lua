local addonName, ns = ...

-- Housing decor: a Decor page listing the decor you're missing by source (Page.lua), a "Decor: collected / not
-- collected" line on decor item tooltips, a Next up source and an Around you block for decor vendors in your zone,
-- and Blizzard's own tracking (C_ContentTracking) as the click action that leads to a vendor, achievement or boss,
-- with a waypoint to a learned vendor spot (Vendors.lua) where Blizzard's tracking can't lead.
-- Read-only. Every housing call is guarded so an account or client without housing stays quiet. The catalog is read
-- in Catalog.lua, rules in Data.lua. Decor achievement rewards stay in Almost Done (Achievements/Rewards.lua).

local START_DELAY = 8 -- seconds after the first loading screen before the catalog is read
local RESCAN_DELAY = 3 -- seconds of storage updates gathered into one catalog read
local ICON = 134249 -- inv_misc_lantern_01
local STOP_MANUAL = 2 -- Enum.ContentTrackingStopType.Manual, when the enum is missing
local HOUSING_EVENTS = {
	-- Storage changed (decor bought, placed, destroyed): read the catalog again.
	"HOUSING_STORAGE_UPDATED",
	-- A decor reached your house chest: read just that one.
	"HOUSE_DECOR_ADDED_TO_CHEST",
	-- The housing service came up or went down.
	"HOUSING_SERVICES_AVAILABILITY_UPDATED",
	-- Something was tracked or untracked: the page's "tracked" marks.
	"CONTENT_TRACKING_UPDATE",
}
local UI = ns.UI

local module, db
local started = false
local startTimer
local printWhenRead = false -- /tomte decor scan prints the counts when the read it started finishes
local hooked = false

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Ready()
	return ns.DecorCatalog_State().usable
end

-- Tracking (Blizzard's) -------------------------------------------------------------------------------------------

local function DecorTrackingType()
	return C_ContentTracking and Enum.ContentTrackingType and Enum.ContentTrackingType.Decor
end

function ns.Decor_IsTracking(decorID)
	local kind = DecorTrackingType()
	if not kind then
		return false
	end
	local ok, tracking = pcall(C_ContentTracking.IsTracking, kind, decorID)
	return ok and tracking == true
end

-- False when the player turned Blizzard's tracking of collectibles off in the game's settings.
local function TrackingEnabled()
	if not C_ContentTracking.GetCollectableSourceTrackingEnabled then
		return true
	end
	local ok, enabled = pcall(C_ContentTracking.GetCollectableSourceTrackingEnabled)
	return not (ok and enabled == false)
end

local function Trackable(kind, id)
	local ok, trackable = pcall(C_ContentTracking.IsTrackable, kind, id)
	return ok and trackable == true
end

-- What a click on this decor does (ns.Decor_Action): stop Blizzard's tracking, track, waypoint, learn or none.
function ns.Decor_ActionFor(e)
	local kind = DecorTrackingType()
	return ns.Decor_Action(e, {
		tracking = kind ~= nil and ns.Decor_IsTracking(e.id),
		trackable = kind ~= nil and TrackingEnabled() and Trackable(kind, e.id),
		spot = ns.DecorVendors_Spot(e) ~= nil,
	})
end

-- The click on a decor: Blizzard's tracking when it can lead there (the objective tracker lists where it comes
-- from; the map pin and arrow lead there; a second click stops it), else a waypoint to the vendor Tomte learned
-- (Vendors.lua). Through ns.SafeTrack: the tracker and map redraw inside the call, which in combat hits protected
-- code.
function ns.Decor_ToggleTracking(e)
	local kind = DecorTrackingType()
	local id, name = e.id, e.name
	local action = ns.Decor_ActionFor(e)
	if action == "stop" then
		local manual = Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual or STOP_MANUAL
		ns.SafeTrack(function()
			pcall(C_ContentTracking.StopTracking, kind, id, manual)
		end)
		ns.Print(("stopped tracking %s."):format(name))
		return
	elseif action == "waypoint" then
		ns.DecorVendors_Waypoint(e)
		return
	elseif action == "learn" then
		ns.Print(("Tomte doesn't know where %s stands yet: open their shop once and it remembers the spot%s."):format(
			e.vendor, e.zone and (" (" .. e.zone .. ")") or ""))
		return
	elseif action == "none" then
		if kind and not TrackingEnabled() then
			local prompt = CONTENT_TRACKING_DISABLED_TOOLTIP_PROMPT
			ns.Print(type(prompt) == "string" and prompt
				or "Blizzard's tracking of collectibles is turned off in the game's settings.")
		else
			ns.Print(("%s can't be tracked (no known place to get it)."):format(name))
		end
		return
	end
	local now = ns.SafeTrack(function()
		local ok2, err = pcall(C_ContentTracking.StartTracking, kind, id)
		if not ok2 or err then
			local maxed = ok2 and Enum.ContentTrackingError and err == Enum.ContentTrackingError.MaxTracked
			ns.Print(("can't track %s%s."):format(name,
				maxed and ": you're tracking as many collectibles as Blizzard allows" or ""))
			return
		end
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedContent then
			pcall(C_SuperTrack.SetSuperTrackedContent, kind, id)
		end
	end)
	ns.Print(("%s %s."):format(now and "tracking" or "after combat: tracking", name))
end

-- Shift-click: the item's link in the chat box, once the item data is there.
function ns.Decor_Link(e)
	if not e.itemID then
		return
	end
	local _, link = C_Item.GetItemInfo(e.itemID)
	if link then
		UI.InsertLink(link)
		return
	end
	Item:CreateFromItemID(e.itemID):ContinueOnItemLoad(function()
		local _, loaded = C_Item.GetItemInfo(e.itemID)
		UI.InsertLink(loaded)
	end)
end

-- Your zone ---------------------------------------------------------------------------------------------------

local function ZoneNames()
	local _, info = ns.MapTabs_ResolveMap(C_Map.GetBestMapForUnit("player"))
	return ns.Decor_NameSet({ info and info.name, GetRealZoneText(), GetZoneText(), GetSubZoneText() })
end

local function VendorsHere()
	if not Ready() then
		return {}, 0
	end
	return ns.Decor_VendorsHere(ns.DecorCatalog_Entries(), ZoneNames(), ns.DecorVendors_HereItems())
end

local function VendorTooltip(row, v)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(v.vendor, UI.Color("heading"))
	if v.zone then
		UI.TipLine(v.zone, "textMuted")
	end
	GameTooltip:AddLine(" ")
	for _, e in ipairs(v.entries) do
		UI.TipLine(e.name, "text")
	end
	GameTooltip:AddLine(" ")
	UI.TipLine("Click for the way to the vendor (Blizzard's tracking or a waypoint).", "textMuted", true)
	GameTooltip:Show()
end

-- Starting ----------------------------------------------------------------------------------------------------

function ns.Decor_EnsureScan()
	if module.active and ns.DecorCatalog_State().state == "idle" then
		ns.DecorCatalog_Scan()
	end
end

local function OnChanged()
	ns.DecorPage_Refresh()
	if ns.Panel_IsShown() then
		ns.Panel_Refresh() -- Home's Next up, Around you and the rail's count
	end
	local state = ns.DecorCatalog_State().state
	if printWhenRead and state ~= "searching" and state ~= "reading" then
		printWhenRead = false
		ns.Decor_PrintCounts()
	end
end

local rescan = UI.Debounce(RESCAN_DELAY, function()
	if module.active and started then
		ns.DecorCatalog_Scan()
	end
end)

function events:PLAYER_ENTERING_WORLD()
	if started then
		return
	end
	started = true
	startTimer = C_Timer.NewTimer(START_DELAY, function()
		startTimer = nil
		ns.Decor_EnsureScan()
	end)
end

function events:HOUSING_STORAGE_UPDATED()
	rescan()
end

function events:HOUSE_DECOR_ADDED_TO_CHEST(_, decorID)
	if type(decorID) ~= "number" or not ns.DecorCatalog_Update(decorID) then
		rescan()
	end
end

function events:HOUSING_SERVICES_AVAILABILITY_UPDATED()
	rescan()
end

function events:CONTENT_TRACKING_UPDATE()
	ns.DecorPage_Refresh()
end

-- A shop opened (or its list filled in): learn the vendor if it sells decor.
function events:MERCHANT_SHOW()
	if ns.DecorVendors_Learn() then
		OnChanged()
	end
end
events.MERCHANT_UPDATE = events.MERCHANT_SHOW

-- Tooltip -----------------------------------------------------------------------------------------------------

local function IsDecorItem(itemID)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	local housing = Enum.ItemClass.Housing
	local decor = Enum.ItemHousingSubclass and Enum.ItemHousingSubclass.Decor
	return housing ~= nil and classID == housing and (decor == nil or subclassID == decor)
end

-- The live catalog answer for a decor item, or nil (not decor, or no housing here).
local function ItemInfo(itemID)
	if not (C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) or not IsDecorItem(itemID) then
		return nil
	end
	local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemID)
	return ok and type(info) == "table" and info or nil
end

local function OnItem(tooltip, data)
	if not (module.active and db.tooltip and tooltip.AddLine and data) then
		return
	end
	local itemID = data.id
	if not itemID or ns.IsSecret(itemID) or type(itemID) ~= "number" then
		return
	end
	local info = ItemInfo(itemID)
	if not info then
		return
	end
	local text, role = ns.Decor_TooltipLine(ns.Decor_OwnedCount(info))
	tooltip:AddLine(UI.Wrap(text, role))
end

local function Start()
	for _, event in ipairs(HOUSING_EVENTS) do
		pcall(events.RegisterEvent, events, event) -- a client without housing doesn't know these events
	end
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("MERCHANT_SHOW")
	events:RegisterEvent("MERCHANT_UPDATE")
	if not hooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		hooked = true -- post-calls can't be removed; OnItem checks module.active
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
	end
	if ns.inWorld then
		events:PLAYER_ENTERING_WORLD()
	end
end

local function Stop()
	events:UnregisterAllEvents()
	if startTimer then
		startTimer:Cancel()
		startTimer = nil
	end
	started, printWhenRead = false, false
	ns.DecorCatalog_Stop()
	ns.DecorPage_Refresh()
end

-- Commands ----------------------------------------------------------------------------------------------------

function ns.Decor_PrintCounts()
	local info = ns.DecorCatalog_State()
	if info.state == "unavailable" then
		local _, why = ns.DecorCatalog_Available()
		ns.Print("decor: " .. (why or "the housing catalog can't be read here."))
		return
	end
	local counts = ns.Decor_Counts(ns.DecorCatalog_Entries())
	ns.Print(("decor: %s, %s missing."):format(ns.Decor_CollectedText(counts, ns.Thousands),
		ns.Thousands(counts.missing)))
	for _, line in ipairs(ns.Decor_ScanLines(counts)) do
		print("  " .. line)
	end
	local vendors, total = VendorsHere()
	print("  " .. (ns.Decor_VendorsHereText(vendors, total) or "No decor vendor in your zone sells decor you're missing."))
end

local function Scan()
	local available, why = ns.DecorCatalog_Available()
	if not available then
		ns.Print("decor: " .. why)
		return
	end
	printWhenRead = true
	ns.Print("reading the housing catalog...")
	ns.DecorCatalog_Scan()
end

-- Shows the escape codes instead of running them.
local function Escaped(s)
	return (tostring(s):gsub("|", "||"))
end

local function Why(arg)
	local itemID = ns.Decor_ItemID(arg)
	if not itemID then
		ns.Print("usage: /tomte decor why <item link or ID>")
		return
	end
	local name = C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	ns.Print(("%s (%d): item class %s, subclass %s, %s."):format(name, itemID, tostring(classID), tostring(subclassID),
		IsDecorItem(itemID) and "a decor item" or "not a decor item"))
	if not (C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) then
		print("  This client has no housing catalog.")
		return
	end
	local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemID)
	if not ok then
		print("  The catalog errored on it: " .. Escaped(info))
		return
	end
	if type(info) ~= "table" then
		print("  The catalog has no entry for it.")
		return
	end
	print(("  Catalog: %s, decor %s, type %s"):format(tostring(info.name), tostring(info.recordID),
		tostring(info.entryType)))
	print(("  You have %d: %s stored, %s to redeem, %s placed."):format(ns.Decor_OwnedCount(info),
		tostring(info.totalNumStored), tostring(info.remainingRedeemable), tostring(info.totalNumPlaced)))
	print("  Source text: " .. Escaped(info.sourceText or "(none)"))
	local d = ns.Decor_Describe(info.sourceText or "")
	print(("  Read as: %s; vendor %s; zone %s"):format(d.source, tostring(d.vendor), tostring(d.zone)))
	local here = {}
	for lower in pairs(ZoneNames()) do
		here[#here + 1] = lower
	end
	table.sort(here)
	print(("  Zones it matches by: %s; your zone names: %s"):format(table.concat(d.zones, ", "),
		table.concat(here, ", ")))
	local kind = DecorTrackingType()
	if kind and type(info.recordID) == "number" then
		local okT, trackable = pcall(C_ContentTracking.IsTrackable, kind, info.recordID)
		print(("  Blizzard's tracking: %s%s"):format(okT and trackable and "trackable" or "not trackable",
			ns.Decor_IsTracking(info.recordID) and ", tracked now" or ""))
	end
	local spot = ns.DecorVendors_Spot({ itemID = itemID, vendor = d.vendor })
	print(("  Learned vendor: %s"):format(spot and ("%s, map %s at %.1f, %.1f"):format(tostring(spot.name),
		tostring(spot.mapID), spot.x * 100, spot.y * 100) or "none yet"))
	print(("  Model: %s, scene %s; on the Decor page: %s"):format(tostring(info.asset), tostring(info.uiModelSceneID),
		ns.DecorCatalog_ByItem(itemID) and "yes" or (Ready() and "no" or "catalog not read yet")))
end

local function Open()
	ns.Panel_OpenPage("decor")
end

-- Home entries ------------------------------------------------------------------------------------------------

local function TrackFirst(v)
	local first = v.entries[1]
	return function()
		if first then
			ns.Decor_ToggleTracking(first)
		end
	end
end

local function AroundItems(limit)
	local vendors = VendorsHere()
	local rows = {}
	for i = 1, math.min(#vendors, limit) do
		local v = vendors[i]
		local first = v.entries[1]
		rows[i] = {
			icon = first and first.icon or ICON, text = v.vendor, right = ("%d decor"):format(#v.entries),
			onEnter = function(row)
				VendorTooltip(row, v)
			end,
			onClick = TrackFirst(v),
		}
	end
	return rows
end

local function NextCandidates()
	local vendors, total = VendorsHere()
	if total == 0 then
		return {}
	end
	local parts = {}
	for i, v in ipairs(vendors) do
		parts[i] = ("%s (%d)"):format(v.vendor, #v.entries)
	end
	local top = vendors[1]
	local first = top.entries[1]
	return { {
		key = "decor:vendor:" .. (top.zone or top.vendor), state = total,
		text = ns.Decor_VendorsHereText(vendors, total),
		why = table.concat(parts, ", "),
		icon = first and first.icon or ICON,
		onClick = TrackFirst(top),
		hint = "Click for the way to the vendor",
	} }
end

local function PageSummary()
	local info = ns.DecorCatalog_State()
	if info.state == "unavailable" then
		return "Housing isn't available here"
	elseif not info.usable then
		return "Reading the housing catalog..."
	end
	local counts = ns.Decor_Counts(ns.DecorCatalog_Entries())
	return ns.Decor_CollectedText(counts, ns.Thousands)
end

module = ns.RegisterModule({
	key = "decor",
	name = "Housing decor",
	category = "collections",
	icon = ICON,
	summary = "The housing decor you're missing, where it comes from, and vendors near you.",
	description = "A Decor page with the housing decor you're missing, grouped by where it comes from (vendors, achievements, quests, drops, professions), with search and a turning model. Click one to track it with Blizzard's tracking, which leads you to the vendor, achievement or boss; for vendors Blizzard can't lead to, Tomte learns where they stand when you open their shop and gives a waypoint. Decor item tooltips say whether you have it. Next up and Around you name decor vendors in your zone that sell decor you're missing. Decor rewards of achievements are in Almost Done.",
	enabledByDefault = true,
	home = {
		{ kind = "page", key = "decor", order = 42, name = "Decor", icon = ICON, page = ns.DecorPage,
			summary = PageSummary,
			pill = function()
				local _, total = VendorsHere()
				return total
			end,
			pillTip = "Decor you're missing that vendors in your zone sell" },
		{ kind = "next", key = "decorvendor", name = "Decor vendor here", score = 40,
			description = "A vendor in your zone sells housing decor you're missing (click to track it).",
			candidates = NextCandidates },
		{ kind = "around", key = "decoraround", order = 60, name = "Decor vendors", icon = ICON,
			shown = function()
				local _, total = VendorsHere()
				return total > 0
			end,
			title = function()
				local vendors, total = VendorsHere()
				return ns.Decor_VendorsHereText(vendors, total) or "Decor vendors: none here"
			end,
			items = AroundItems, maxRows = 4, open = Open, openText = "Open the Decor page" },
	},
	defaults = {
		tooltip = true,
		preview = true,
		filter = { source = "all", owned = false }, -- the Decor page's source filter and "Show collected"
		collapsed = {}, -- [source key] = true while that group is folded on the Decor page
		-- Learned decor vendors (Vendors.lua): [npcID] = { name, mapID, x, y, items = { [itemID] = true }, seen }
		vendors = {},
	},
	init = function(saved)
		db = saved
		ns.DecorPage_Init(db)
		ns.DecorVendors_Init(db)
		ns.DecorCatalog_SetChanged(OnChanged)
	end,
	toggle = function(active)
		if active then
			Start()
		else
			Stop()
		end
	end,
	commands = {
		{ "open", "open the Decor page", Open },
		{ "scan", "read the housing catalog again and count decor per source", Scan },
		{ "why", "what the catalog says about a decor item: /tomte decor why <item link or ID>", Why },
		{ "vendors", "the decor vendors Tomte has learned the spot of", function()
			ns.DecorVendors_Print()
		end },
	},
	options = {
		{ type = "header", label = "Decor page" },
		{ type = "checkbox", key = "preview", label = "Model preview",
			tooltip = "Hovering a decor on the Decor page shows its model, turning, next to the tooltip." },
		{ type = "button", label = "Decor page", text = "Open", onClick = Open },
		{ type = "button", label = "Housing catalog", text = "Read again", onClick = Scan,
			tooltip = "Read the catalog again and print how much decor you have per source." },
		{ type = "header", label = "Tooltips" },
		{ type = "checkbox", key = "tooltip", label = "Collected or not on decor items",
			tooltip = "Decor item tooltips get a line: \"Decor: collected\" with how many you have, or \"Decor: not collected\"." },
	},
})
