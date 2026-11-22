local addonName, ns = ...

-- Crafting list: crafts added from the Crafting tab, the to-do for the character you're on ("Grab 10 Iron Ingot from
-- bank", "Mail 20 Mycobloom to Mira", "Ready: craft 3 Flask"), crafts counted down as they're made, and marks on the
-- items to move in Baganator's bags and bank. The on-screen tracker is in Tracker.lua, the mailbox rows in Send.lua,
-- the List tab in ListTab.lua, the rules in ListData.lua.
-- The shared labels the Alts files draw items and recipes with (Alts_ItemLabel, Alts_RecipeLabel...) are in
-- Labels.lua.

local UI = ns.UI
local BAGANATOR_ID = "tomte_craftlist"
-- Seconds the to-do is kept. AltsList_Changed drops it on bag, bank, mail, craft and recipe changes; this only
-- catches what has no event (item names and prices arriving). The rail polls the pill every second.
local CACHE = 15
-- Under the to-do without Item counts or Syndicator (List tab and tracker).
local PARTIAL_NOTE = "Materials on your other characters aren't counted: turn on Item counts."
ns.ALTS_PARTIAL_NOTE = PARTIAL_NOTE

local db
local cache, cacheAt
local pending -- recipe spell ID of the craft that just started
local refreshTimer

local events = ns.Alts_Events
local RecipeName = ns.Alts_RecipeName -- Labels.lua
local baganatorRegistered, syndicatorRegistered, countsRegistered
-- Syndicator's callback registry stores callbacks per owner: its own table, not shared with CraftMats.lua.
local listOwner = {}

-- Where things are ----------------------------------------------------------------------------------------------

local function SyndicatorAPI()
	local api = _G.Syndicator and _G.Syndicator.API
	if api and api.GetInventoryInfoByItemID and api.IsReady and api.IsReady() then
		return api
	end
	return nil
end

-- Syndicator names characters "Name-Realm"; find the GUID we keep for it.
local guidByName
local function GuidOf(character)
	if not guidByName then
		guidByName = {}
		for guid, c in pairs(ns.altsDB.chars) do
			local realm = (c.realm or ""):gsub("[%s%-]", "")
			guidByName[(c.name or "") .. "-" .. realm] = guid
			guidByName[c.name or ""] = guidByName[c.name or ""] or guid
		end
	end
	if not character then
		return nil
	end
	local plain = character:gsub("%s", "")
	return guidByName[plain] or guidByName[character:match("^([^%-]+)") or character]
end

-- { { guid, where, n } } for one item: every character's bags, bank and mail, and the Warband bank. From Item counts
-- (Tomte's own record, by GUID like ours), else Syndicator, else this character only.
local function Stored(itemID)
	local list = {}
	local me = UnitGUID("player")
	-- This character and the Warband bank, live from the game.
	local function Mine()
		local bags = C_Item.GetItemCount(itemID, false, false, true, false) or 0
		local withBank = C_Item.GetItemCount(itemID, true, false, true, false) or 0
		local all = C_Item.GetItemCount(itemID, true, false, true, true) or 0
		if bags > 0 then
			list[#list + 1] = { guid = me, where = "bags", n = bags }
		end
		if withBank > bags then
			list[#list + 1] = { guid = me, where = "bank", n = withBank - bags }
		end
		if all > withBank then
			list[#list + 1] = { where = "warband", n = all - withBank }
		end
	end
	-- Item counts: other characters from its record (it has this one's bank only once it was opened).
	if ns.Counts_Active and ns.Counts_Active() then
		for _, w in ipairs(ns.Counts_Where(ns.Counts_Entry(itemID))) do
			if w.guid and w.guid ~= me and w.where ~= "equipped" then
				list[#list + 1] = w
			elseif w.guid == me and w.where == "mail" then
				list[#list + 1] = w
			end
		end
		Mine()
		return list
	end
	local api = SyndicatorAPI()
	if api then
		local info = api.GetInventoryInfoByItemID(itemID, false, false)
		for _, c in ipairs(info and info.characters or {}) do
			-- c.character is the bare name; the realm tells same-named characters apart.
			local guid = GuidOf(c.realmNormalized and (c.character .. "-" .. c.realmNormalized) or c.character)
			if guid then
				for _, where in ipairs({ "bags", "bank", "mail" }) do
					local n = c[where]
					if n and n > 0 then
						list[#list + 1] = { guid = guid, where = where, n = n }
					end
				end
			end
		end
		local warband = info and info.warband and info.warband[1]
		if warband and warband > 0 then
			list[#list + 1] = { where = "warband", n = warband }
		end
		return list
	end
	-- Without Syndicator: this character and the Warband bank.
	local me = UnitGUID("player")
	local bags = C_Item.GetItemCount(itemID, false, false, true, false) or 0
	local withBank = C_Item.GetItemCount(itemID, true, false, true, false) or 0
	local all = C_Item.GetItemCount(itemID, true, false, true, true) or 0
	if bags > 0 then
		list[#list + 1] = { guid = me, where = "bags", n = bags }
	end
	if withBank > bags then
		list[#list + 1] = { guid = me, where = "bank", n = withBank - bags }
	end
	if all > withBank then
		list[#list + 1] = { where = "warband", n = all - withBank }
	end
	return list
end

-- Stored, plus mail waiting for your characters that no count sees until they read their inbox: what they bought at
-- the Auction House and what you mailed them (mailWaiting on their altsDB.chars record, [itemID] = count).
local function Where(itemID)
	local list = Stored(itemID)
	for guid, c in pairs(ns.altsDB.chars) do
		local n = c.mailWaiting and c.mailWaiting[itemID]
		if n and n > 0 then
			list[#list + 1] = { guid = guid, where = "mail", n = n }
		end
	end
	return list
end

-- items = { [itemID] = count } just went into c's mailbox (an Auction House purchase, or Send.lua's mail to them).
function ns.AltsList_MailWaiting(c, items)
	c.mailWaiting = c.mailWaiting or {}
	for itemID, n in pairs(items) do
		c.mailWaiting[itemID] = (c.mailWaiting[itemID] or 0) + n
	end
	ns.AltsList_Changed()
end

-- Without Syndicator only this character and the Warband bank are counted: a material "to get" may be on another
-- character. True when that can be so (another character known, something missing).
function ns.AltsList_PartialCounts(todos)
	if ns.Alts_HasSyndicator() or not ns.altsDB then
		return false
	end
	local me, others = UnitGUID("player"), false
	for guid in pairs(ns.altsDB.chars) do
		if guid ~= me then
			others = true
			break
		end
	end
	if not others then
		return false
	end
	for _, t in ipairs(todos or {}) do
		if t.plan and t.plan.missing and t.plan.missing > 0 then
			return true
		end
	end
	return false
end

-- Every tracked craft's to-do for the character you're on (cached, see CACHE).
function ns.AltsList_Todos()
	if not (db and ns.altsDB) then
		return {}
	end
	local now = GetTime()
	if cache and now - cacheAt < CACHE then
		return cache
	end
	local alts = ns.altsDB
	if #alts.list == 0 then
		cache, cacheAt = {}, now
		return cache
	end
	local producers = ns.Alts_Producers(alts.recipes)
	local realms = ns.Alts_MailRealms and ns.Alts_MailRealms() -- SendRead.lua
	local ok, todos = xpcall(ns.Alts_ListTodo, function(err)
		return ns.errorHandler(err)
	end, alts.list, {
		me = UnitGUID("player"), chars = alts.chars, recipes = alts.recipes,
		pool = ns.Alts_Pool(Where),
		plan = function(recipeID, crafts, count, entry)
			return ns.Alts_Plan(recipeID, crafts, {
				recipes = alts.recipes, chars = alts.chars, producers = producers, count = count,
				maxDepth = alts.chain == "one" and 1 or ns.ALTS_FULL_DEPTH, ranks = entry and entry.ranks,
			})
		end,
		-- Names in the to-do lines: items with their icon (and rank), both in rarity colour.
		itemName = function(itemID, noRank)
			return ns.Alts_ItemLabel(itemID, 13, noRank)
		end,
		recipeName = function(recipeID, quality)
			return ns.Alts_RecipeLabel(recipeID, nil, quality)
		end,
		price = db.listPrice and ns.Value_ItemPrice and function(itemID)
			return (ns.Value_ItemPrice(itemID))
		end or nil,
		gold = ns.Alts_Price,
		-- Crafters on a realm mail can't reach get a Warband bank line instead of "Mail ... to".
		canMail = function(guid)
			return ns.Alts_Reachable(alts.chars[guid], realms)
		end,
		noWarband = not ns.Alts_WarbandLive(), -- Forever, unless its Warband bank is live: no such line
	})
	cache, cacheAt = ok and todos or {}, now
	return cache
end

local MarksChanged -- Baganator marks, below

function ns.AltsList_Changed()
	cache = nil
	guidByName = nil
	if refreshTimer then
		return
	end
	-- One redraw for a burst of changes (bag, mail and Syndicator events come several at a time).
	refreshTimer = C_Timer.NewTimer(0.3, function()
		refreshTimer = nil
		ns.AltsList_Refresh()
		if ns.AltsListTab_Refresh then
			ns.AltsListTab_Refresh()
		end
		if ns.AltsSend_Refresh then
			ns.AltsSend_Refresh()
		end
		-- A full Baganator refresh runs every corner widget and upgrade plugin on every item: only when our marks moved.
		-- Tomte's own bags (Modules/Bags) redraw their crafting-list marks the same way.
		local baganator = Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh and db.listBaganator
		local tomteBags = ns.Bags_Active and ns.Bags_Active()
		if (baganator or tomteBags) and MarksChanged() then
			if baganator then
				Baganator.API.RequestItemButtonsRefresh()
			end
			if tomteBags then
				ns.BagsWindow_Refresh()
				ns.BagsBank_Refresh()
			end
		end
	end)
end

-- choice (optional) = { quality, ranks }: the Crafting tab's picks, which replace a listed entry's.
function ns.AltsList_Add(recipeID, crafts, choice)
	ns.Alts_ListAdd(ns.altsDB.list, recipeID, crafts, GetServerTime(), choice)
	ns.Print(("added %d %s to the crafting list."):format(crafts, ns.Alts_RecipeLabel(recipeID, nil, choice and choice.quality)))
	ns.AltsList_Changed()
end

function ns.AltsList_Remove(recipeID)
	ns.Alts_ListRemove(ns.altsDB.list, recipeID)
	ns.AltsList_Changed()
end

-- Baganator marks -------------------------------------------------------------------------------------------------

-- [itemID] = count to mark, worked out once per to-do (Baganator asks for every item button).
local marked, markedFor
local function Marked()
	local todos = ns.AltsList_Todos()
	if markedFor ~= todos then
		marked, markedFor = ns.Alts_MarkedItems(todos), todos
	end
	return marked
end

-- How many of an item the crafting list wants moved (Tomte's own bags mark it), nil for none or while Alts is off.
function ns.AltsList_Marked(itemID)
	if not (ns.altsModule.active and itemID) then
		return nil
	end
	return Marked()[itemID]
end

-- Whether the marks differ from the ones the item buttons last showed (and remembers the new ones).
local shownMarks
function MarksChanged()
	local now, before = Marked(), shownMarks
	shownMarks = now
	if not before then
		return true
	end
	for itemID, n in pairs(now) do
		if before[itemID] ~= n then
			return true
		end
	end
	for itemID in pairs(before) do
		if not now[itemID] then
			return true
		end
	end
	return false
end

-- Once per session (baganatorRegistered, like syndicatorRegistered in AltsList_Start): neither registration is undone
-- by AltsList_Stop, so the callbacks check that the module is on.
local function RegisterBaganator()
	if baganatorRegistered or not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then
		return
	end
	baganatorRegistered = true
	Baganator.API.RegisterCornerWidget("Tomte Crafting list", BAGANATOR_ID, function(widget, details)
		if not (db and db.listBaganator and ns.altsModule.active and details and details.itemID) then
			return false
		end
		local n = Marked()[details.itemID]
		if not n then
			return false
		end
		widget.count:SetText(n)
		return true
	end, function(itemButton)
		local widget = CreateFrame("Frame", nil, itemButton)
		widget:SetSize(22, 14)
		widget.padding = 0
		local bg = widget:CreateTexture(nil, "ARTWORK")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.75)
		local edge = widget:CreateTexture(nil, "OVERLAY")
		edge:SetColorTexture(UI.Color("accent"))
		edge:SetPoint("BOTTOMLEFT")
		edge:SetPoint("BOTTOMRIGHT")
		edge:SetHeight(1)
		widget.count = widget:CreateFontString(nil, "OVERLAY")
		UI.SetFont(widget.count, "number", 11, "OUTLINE")
		widget.count:SetPoint("CENTER", 0, 0)
		UI.SetTextRole(widget.count, "accent")
		return widget
	end, { corner = "top_right", priority = 1 })
end

-- Events ----------------------------------------------------------------------------------------------------------

events:On("list", "TRADE_SKILL_CRAFT_BEGIN", function(_, recipeSpellID)
	pending = recipeSpellID
end)

-- One result per craft (a multicraft is still one craft). Recipe IDs are the recipes' spell IDs.
events:On("list", "TRADE_SKILL_ITEM_CRAFTED_RESULT", function(_, data)
	if not data or data.bonusCraft then
		return
	end
	local recipeID = ns.Alts_ListCraftedRecipe(ns.altsDB.list, ns.altsDB.recipes, pending, data.itemID)
	if not recipeID then
		return
	end
	local entry = ns.Alts_ListCrafted(ns.altsDB.list, recipeID, db.listDone == "auto")
	if entry and entry.crafts <= 0 then
		ns.Print(("%s done: %s."):format(RecipeName(recipeID), db.listDone == "auto" and "off the crafting list" or "right-click it in the tracker to remove it"))
	end
	ns.AltsList_Changed()
end)

events:On("list", "TRADE_SKILL_CLOSE", function()
	pending = nil
end)

local CHANGED = { "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
	"MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "PLAYER_ENTERING_WORLD" }
for _, event in ipairs(CHANGED) do
	events:On("list", event, function()
		ns.AltsList_Changed()
	end)
end

-- Auction House purchases: they go to the mailbox, and the counts only see mail once the inbox is read, so Tomte
-- notes them meanwhile (AltsList_MailWaiting). Crafting
-- materials are commodities: C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity), then
-- COMMODITY_PURCHASE_SUCCEEDED or _FAILED (as Auctionator's commodity buying uses them).
local buying -- { itemID, quantity } of the purchase waiting for its answer

if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
	hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
		if ns.altsModule and ns.altsModule.active and type(itemID) == "number" and type(quantity) == "number" then
			buying = { itemID = itemID, quantity = quantity }
		end
	end)
end

events:On("list", "COMMODITY_PURCHASE_SUCCEEDED", function()
	local me = buying and ns.altsDB.chars[UnitGUID("player")]
	if me then
		ns.AltsList_MailWaiting(me, { [buying.itemID] = buying.quantity })
	end
	buying = nil
end)

events:On("list", "COMMODITY_PURCHASE_FAILED", function()
	buying = nil
end)

-- The inbox is read: the counts see the purchases now.
events:On("list", "MAIL_INBOX_UPDATE", function()
	local me = ns.altsDB.chars[UnitGUID("player")]
	if me and me.mailWaiting then
		me.mailWaiting = nil
	end
end)

local EVENTS = { "TRADE_SKILL_CRAFT_BEGIN", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "TRADE_SKILL_CLOSE",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED" }

function ns.AltsList_Start(moduleDB)
	db = moduleDB
	ns.AltsTracker_Start(moduleDB) -- Tracker.lua
	for _, list in ipairs({ EVENTS, CHANGED }) do
		for _, event in ipairs(list) do
			-- An event name the client doesn't know must not stop the others.
			events:TryWatch("list", event)
		end
	end
	RegisterBaganator()
	if ns.Counts_OnChange and not countsRegistered then
		countsRegistered = true -- once per session; the listener checks that Alts is on
		ns.Counts_OnChange(function()
			if ns.altsModule.active then
				ns.AltsList_Changed()
			end
		end)
	end
	if _G.Syndicator and Syndicator.CallbackRegistry and not syndicatorRegistered then
		syndicatorRegistered = true
		for _, name in ipairs({ "BagCacheUpdate", "MailCacheUpdate", "WarbandBankCacheUpdate" }) do
			pcall(Syndicator.CallbackRegistry.RegisterCallback, Syndicator.CallbackRegistry, name, function()
				if ns.altsModule.active then
					ns.AltsList_Changed()
				end
			end, listOwner)
		end
	end
	ns.AltsList_Changed()
end

function ns.AltsList_Stop()
	events:UnwatchAll("list")
	ns.AltsTracker_Stop()
end
