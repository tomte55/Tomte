local addonName, ns = ...

-- Alts, recipes you can learn now: after a profession skill-up or a new level, a toast names the recipe items in your
-- bags, your bank (as last seen, from Item counts) and the Warband bank that you couldn't learn before and can now;
-- and a recipe you can learn that turns up in your bags (looted, bought, from the mail) gets one too.
-- "Can't" is the item's tooltip saying so in red (Bags' red check: a skill or level too low, or "Already known"), so a
-- recipe you know never shows. The first read of a session only notes what's red. Rules in LearnData.lua; started
-- and stopped by Alts.lua.

local RECIPE = 9 -- Enum.ItemClass.Recipe
local BAGS = { 0, 1, 2, 3, 4, 5 } -- Backpack .. ReagentBag (Enum.BagIndex); a bag the client hasn't got has no slots
local FIRST_READ_DELAY = 5 -- seconds after starting: item data and Item counts' banks settle after login
local SKILL_DELAY = 2 -- seconds: a skill-up comes with a burst of skill events, and tooltips catch up after them
local LEVEL_LAG = 2 -- seconds: the red "Requires Level" lines can lag behind PLAYER_LEVEL_UP (as Gear Check found)
local TOAST_HOLD = 12

local events = ns.Alts_Events
local EVENTS_OWNER = "learnable" -- its toasts go out as Alts' (owner "alts")
local db
local active = false
local before -- [link] = red, from the last read; nil until the session's first read
local seen -- [link] = true for every recipe held since the first read (read or still loading then)

-- Every recipe item you hold: [link] = { name, icon, where }, bags first (where it's easiest to reach).
local function Held()
	local held = {}
	local function Add(link, where)
		if not link or held[link] or ns.IsSecret(link) then
			return
		end
		local itemID, _, _, _, icon, classID = C_Item.GetItemInfoInstant(link)
		if classID == RECIPE then
			held[link] = { itemID = itemID, icon = icon, where = where }
		end
	end
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			Add(info and info.hyperlink, "bags")
		end
	end
	if ns.Counts_Bank then
		for _, entry in ipairs((ns.Counts_Bank(UnitGUID("player")))) do
			Add(entry.link, "bank")
		end
		for _, entry in ipairs((ns.Counts_Bank(nil))) do
			Add(entry.link, "warband")
		end
	end
	return held
end

-- [link] = red for each held recipe whose data has loaded (an unloaded one has no red lines yet, which would read as
-- learnable: it's asked for and read next time).
local function ReadRed(held)
	local red = {}
	for link, item in pairs(held) do
		if C_Item.IsItemDataCachedByID(item.itemID) then
			red[link] = ns.BagsRead_LinkUnusable(link, true)
		else
			C_Item.RequestLoadItemDataByID(item.itemID)
		end
	end
	return red
end

local function Toast(links, held)
	local entries = {}
	for i, link in ipairs(links) do
		entries[i] = { name = C_Item.GetItemInfo(link) or link, where = held[link].where }
	end
	local title, text = ns.Alts_LearnToast(entries)
	ns.Toast_Show({
		owner = "alts",
		label = "Can learn now",
		accent = "success",
		title = title,
		text = text,
		icon = held[links[1]].icon,
		hold = TOAST_HOLD,
	})
end

local function Check()
	if not (active and db.learnToast) then
		return
	end
	local held = Held()
	local now = ReadRed(held)
	if before then
		local links = ns.Alts_NewlyLearnable(before, now, seen)
		if #links > 0 then
			Toast(links, held)
		end
	else
		-- The first read: everything held counts as seen, loaded or not, so nothing you had at login is "new".
		before, seen = {}, {}
		for link in pairs(held) do
			seen[link] = true
		end
	end
	for link, red in pairs(now) do
		before[link] = red
		seen[link] = true
	end
end

local checkSoon = ns.UI.Debounce(SKILL_DELAY, Check)

-- A skill-up: SKILL_LINES_CHANGED on both clients, and the chat line as a backstop (the profession window's own skill
-- events can come without it). Bag changes: a recipe looted, bought or taken from the mail.
local SKILL_EVENTS = { "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "BAG_UPDATE_DELAYED" }
for _, event in ipairs(SKILL_EVENTS) do
	events:On(EVENTS_OWNER, event, checkSoon)
end
events:On(EVENTS_OWNER, "PLAYER_LEVEL_UP", function()
	C_Timer.After(LEVEL_LAG, Check)
end)

-- Called by Alts.lua ------------------------------------------------------------------------------------------------

function ns.AltsLearnable_Start(moduleDB)
	db = moduleDB
	active = true
	for _, event in ipairs(SKILL_EVENTS) do
		events:TryWatch(EVENTS_OWNER, event)
	end
	events:Watch(EVENTS_OWNER, "PLAYER_LEVEL_UP")
	C_Timer.After(FIRST_READ_DELAY, Check)
end

function ns.AltsLearnable_Stop()
	active = false
	events:UnwatchAll(EVENTS_OWNER)
	before, seen = nil, nil -- turned on again later: a fresh first read, so nothing held meanwhile toasts as new
end

-- /tomte alts learnable: what each held recipe reads as now (for checking the red read).
function ns.AltsLearnable_Print()
	local held = Held()
	local red = ReadRed(held)
	local any = false
	for link, item in pairs(held) do
		any = true
		local state = red[link] == nil and "loading" or red[link] and "red (can't learn)" or "can learn"
		ns.Print(("%s in %s: %s"):format(link, item.where, state))
	end
	if not any then
		ns.Print("no recipe items in your bags or banks.")
	end
end
