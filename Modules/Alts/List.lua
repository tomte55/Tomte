local addonName, ns = ...

-- Crafting list: crafts added from the Crafting tab, an on-screen tracker with the to-do for the character you're
-- on ("Grab 10 Iron Ingot from bank", "Mail 20 Mycobloom to Mira", "Ready: craft 3 Flask"),
-- crafts counted down as they're made, and marks on the items to move in Baganator's bags and bank. The mailbox rows
-- are in Send.lua, the List tab in ListTab.lua, the rules in ListData.lua.

local UI = ns.UI
local GOLD, WHITE, GREY = UI.GOLD, UI.WHITE, UI.GREY
local GREEN = { 0.45, 0.85, 0.45 }
local RED = { 1, 0.45, 0.35 }
local WIDTH = 300
local TITLE_H = 22
local HEAD_H = 20
local LINE_H = 15
local MAX_LINES = 6 -- per craft in the tracker
local DEFAULT_POINT = { "TOPRIGHT", "TOPRIGHT", -40, -260 }
local BAGANATOR_ID = "tomte_craftlist"
local CACHE = 1 -- seconds the to-do is kept before it's worked out again
local LINE_COLORS = {
	grab = WHITE, collect = WHITE, take = WHITE, mail = WHITE, fetch = WHITE, missing = RED, craft = GOLD,
	ready = GREEN, wait = GREY, other = GREY,
}

local db
local frame
local blocks = {}
local cache, cacheAt
local pending -- recipe spell ID of the craft that just started
local inCombat = false
local refreshTimer

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

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

-- { { guid, where, n } } for one item: every character's bags, bank and mail, and the Warband bank.
local function Where(itemID)
	local list = {}
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

local function ItemName(itemID)
	return C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
end

local function RecipeName(recipeID)
	local r = ns.altsDB.recipes[recipeID]
	return r and r.name or "?"
end

-- Text in an item's rarity colour (as it is until the item's data has loaded).
local function InQuality(text, itemID)
	local quality = itemID and C_Item.GetItemQualityByID(itemID)
	if not quality then
		return text
	end
	local r, g, b = C_Item.GetItemQualityColor(quality)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

local function Icon(icon, size)
	return icon and size and ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t "):format(icon, size, size) or ""
end

-- An item as the crafting list shows it: its icon (when size is given) and its name in its rarity colour.
function ns.Alts_ItemLabel(itemID, size)
	return Icon(C_Item.GetItemIconByID(itemID), size) .. InQuality(ItemName(itemID), itemID)
end

-- A recipe: its icon (when size is given) and its name in the rarity colour of what it makes.
function ns.Alts_RecipeLabel(recipeID, size)
	local r = ns.altsDB.recipes[recipeID]
	return Icon(r and r.icon, size) .. InQuality(RecipeName(recipeID), r and r.item)
end

-- Every tracked craft's to-do for the character you're on (cached for a second).
function ns.AltsList_Todos()
	if not (db and ns.altsDB) then
		return {}
	end
	local now = GetTime()
	if cache and now - cacheAt < CACHE then
		return cache
	end
	local alts = ns.altsDB
	local producers = ns.Alts_Producers(alts.recipes)
	local ok, todos = xpcall(ns.Alts_ListTodo, function(err)
		return ns.errorHandler(err)
	end, alts.list, {
		me = UnitGUID("player"), chars = alts.chars, recipes = alts.recipes,
		pool = ns.Alts_Pool(Where),
		plan = function(recipeID, crafts, count)
			return ns.Alts_Plan(recipeID, crafts, {
				recipes = alts.recipes, chars = alts.chars, producers = producers, count = count,
				maxDepth = alts.chain == "one" and 1 or ns.ALTS_FULL_DEPTH,
			})
		end,
		-- Names in the to-do lines: items with their icon, both in rarity colour.
		itemName = function(itemID)
			return ns.Alts_ItemLabel(itemID, 13)
		end,
		recipeName = function(recipeID)
			return ns.Alts_RecipeLabel(recipeID)
		end,
		price = db.listPrice and ns.Value_ItemPrice and function(itemID)
			return (ns.Value_ItemPrice(itemID))
		end or nil,
		gold = ns.Alts_Price,
	})
	cache, cacheAt = ok and todos or {}, now
	return cache
end

function ns.AltsList_Changed()
	cache = nil
	guidByName = nil
	if refreshTimer then
		return
	end
	refreshTimer = C_Timer.NewTimer(0.3, function()
		refreshTimer = nil
		ns.AltsList_Refresh()
		if ns.AltsListTab_Refresh then
			ns.AltsListTab_Refresh()
		end
		if ns.AltsSend_Refresh then
			ns.AltsSend_Refresh()
		end
		if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh and db.listBaganator then
			Baganator.API.RequestItemButtonsRefresh()
		end
	end)
end

function ns.AltsList_Add(recipeID, crafts)
	ns.Alts_ListAdd(ns.altsDB.list, recipeID, crafts, GetServerTime())
	ns.Print(("added %d %s to the crafting list."):format(crafts, RecipeName(recipeID)))
	ns.AltsList_Changed()
end

function ns.AltsList_Remove(recipeID)
	ns.Alts_ListRemove(ns.altsDB.list, recipeID)
	ns.AltsList_Changed()
end

-- Tracker -------------------------------------------------------------------------------------------------------

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function SavePoint()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	db.tracker.point = { point, relPoint, x, y }
end

local function Place()
	local p = db.tracker.point or DEFAULT_POINT
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local SEARCHABLE = { grab = true, take = true, collect = true, fetch = true, mail = true }

-- Baganator has no search API; its slash command is the public way in ("/bgr search <text>", lower case). It opens
-- the bags too, and an open bank view highlights the matches.
function ns.AltsList_Search(itemID)
	local name = itemID and C_Item.GetItemNameByID(itemID)
	local slash = SlashCmdList and SlashCmdList["Baganator"]
	if not (name and slash and db.listBaganator) then
		return false
	end
	local ok = pcall(slash, "search " .. name:lower())
	return ok
end

local function LineTooltip(owner, line)
	if not line.itemID then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetItemByID(line.itemID)
	if SEARCHABLE[line.kind] and SlashCmdList and SlashCmdList["Baganator"] then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click: find it in Baganator", GOLD[1], GOLD[2], GOLD[3])
	end
	GameTooltip:Show()
end

local function Block(i)
	local b = blocks[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, frame)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.title = UI.Text(b, 13, GOLD)
	b.title:SetPoint("TOPLEFT", 0, 0)
	b.title:SetPoint("RIGHT", -50, 0)
	b.title:SetWordWrap(false)
	b.crafter = UI.Text(b, 11, GREY)
	b.crafter:SetPoint("TOPRIGHT", 0, -1)
	b.crafter:SetJustifyH("RIGHT")
	b.track = b:CreateTexture(nil, "ARTWORK")
	b.track:SetColorTexture(1, 1, 1, 0.08)
	b.track:SetHeight(2)
	b.track:SetPoint("TOPLEFT", 0, -16)
	b.track:SetPoint("RIGHT")
	b.fill = b:CreateTexture(nil, "OVERLAY")
	b.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
	b.fill:SetHeight(2)
	b.fill:SetPoint("TOPLEFT", b.track, "TOPLEFT")
	b.lines = {}
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			local entry = self.todo and self.todo.entry
			if entry then
				ns.AltsList_Remove(entry.recipeID)
				ns.Print(("removed %s from the crafting list."):format(RecipeName(entry.recipeID)))
			end
		else
			ns.Panel_OpenPage("alts")
			ns.Alts_ShowTab("list")
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self.todo and RecipeName(self.todo.entry.recipeID) or "?", 1, 1, 1)
		GameTooltip:AddLine("Click: the crafting list. Right-click: remove it.", GREY[1], GREY[2], GREY[3])
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	blocks[i] = b
	return b
end

local function Line(b, i)
	local l = b.lines[i]
	if not l then
		l = CreateFrame("Frame", nil, b)
		l:SetHeight(LINE_H)
		l:EnableMouse(true)
		l.text = UI.Text(l, 11, WHITE)
		l.text:SetPoint("TOPLEFT", 8, -1)
		l.text:SetWidth(WIDTH - 28) -- fixed, so the wrapped height is known right after SetText
		l.text:SetJustifyH("LEFT")
		l.text:SetWordWrap(true)
		l.text:SetMaxLines(2) -- a long line wraps once instead of being cut off
		l:SetScript("OnEnter", function(self)
			LineTooltip(self, self.line)
		end)
		l:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		l:SetScript("OnMouseUp", function(self, button)
			local line = self.line
			if button == "LeftButton" and line and SEARCHABLE[line.kind] then
				if not InCombatLockdown() then
					ns.AltsList_Search(line.itemID)
				end
			elseif button == "LeftButton" or button == "RightButton" then
				b:Click(button) -- the line takes the mouse: the craft's own click (open the list, right-click remove)
			end
		end)
		b.lines[i] = l
	end
	l:Show()
	return l
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 60)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:Hide()
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], 0.55)
	frame.title = UI.Text(frame, 10, GREY)
	frame.title:SetPoint("TOPLEFT", 10, -6)
	frame.title:SetText(ns.Spaced and ns.Spaced("Crafting list") or "CRAFTING LIST")
	local mover = CreateFrame("Frame", nil, frame)
	mover:SetAllPoints()
	mover:SetFrameLevel(frame:GetFrameLevel() + 10)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePoint()
	end)
	UI.Border(mover, GOLD[1], GOLD[2], GOLD[3], 0.8)
	local hint = UI.Text(mover, 10, GOLD)
	hint:SetPoint("TOPRIGHT", -8, -6)
	hint:SetText("drag to move")
	frame.mover = mover
end

local function WantShown(todos)
	if not (ns.altsModule and ns.altsModule.active and db.tracker.shown) then
		return false
	end
	if db.tracker.hideInCombat and inCombat then
		return false
	end
	if not db.tracker.locked then
		return true
	end
	if #todos == 0 then
		return false
	end
	if db.tracker.mode == "crafter" then
		local me = UnitGUID("player")
		for _, t in ipairs(todos) do
			if t.crafter == me then
				return true
			end
		end
		return false
	end
	return true
end

function ns.AltsList_Refresh()
	if not db then
		return
	end
	local todos = ns.AltsList_Todos()
	if not WantShown(todos) then
		if frame then
			frame:Hide()
		end
		return
	end
	if not frame then
		Build()
		Place()
	end
	frame:SetScale(db.tracker.scale or 1)
	frame.mover:SetShown(not db.tracker.locked)
	local y = TITLE_H
	for i, t in ipairs(todos) do
		local b = Block(i)
		b.todo = t
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 10, -y)
		b:SetPoint("RIGHT", -10, 0)
		b.title:SetText(("%s  |cff9e9e9ex%d|r"):format(ns.Alts_RecipeLabel(t.entry.recipeID, 15), t.entry.crafts))
		local c = t.crafter and ns.altsDB.chars[t.crafter]
		local color = c and c.class and C_ClassColor.GetClassColor(c.class)
		b.crafter:SetText(c and c.name or "nobody")
		if color then
			b.crafter:SetTextColor(color.r, color.g, color.b)
		else
			SetColor(b.crafter, GREY)
		end
		b.fill:SetWidth(math.max((WIDTH - 20) * ns.Alts_CraftProgress(t), 1))
		local ly = HEAD_H
		local shown = 0
		for _, line in ipairs(t.lines) do
			if shown >= MAX_LINES then
				break
			end
			shown = shown + 1
			local l = Line(b, shown)
			l.line = line
			l:ClearAllPoints()
			l:SetPoint("TOPLEFT", 0, -ly)
			l:SetPoint("RIGHT")
			l.text:SetText(line.text)
			SetColor(l.text, line.mine and (LINE_COLORS[line.kind] or WHITE) or GREY)
			local h = math.max(LINE_H, math.ceil(l.text:GetStringHeight()) + 3)
			l:SetHeight(h)
			ly = ly + h
		end
		if #t.lines > MAX_LINES then
			shown = shown + 1
			local l = Line(b, shown)
			l.line = {}
			l:ClearAllPoints()
			l:SetPoint("TOPLEFT", 0, -ly)
			l:SetPoint("RIGHT")
			l.text:SetText(("+ %d more (the List tab has them all)"):format(#t.lines - MAX_LINES))
			SetColor(l.text, GREY)
			l:SetHeight(LINE_H)
			ly = ly + LINE_H
		end
		for j = shown + 1, #b.lines do
			b.lines[j]:Hide()
		end
		b:SetHeight(ly)
		b:Show()
		y = y + ly + 8
	end
	for i = #todos + 1, #blocks do
		blocks[i]:Hide()
	end
	if #todos == 0 then
		y = y + 18
	end
	frame:SetHeight(y + 4)
	frame:Show()
end

function ns.AltsList_ResetPosition()
	db.tracker.point = nil
	if frame then
		Place()
	end
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

local function RegisterBaganator()
	if events.baganator or not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then
		return
	end
	events.baganator = true
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
		edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		edge:SetPoint("BOTTOMLEFT")
		edge:SetPoint("BOTTOMRIGHT")
		edge:SetHeight(1)
		widget.count = widget:CreateFontString(nil, "OVERLAY")
		widget.count:SetFont(ns.HomeKit.NARROW_FONT, 11, "OUTLINE")
		widget.count:SetPoint("CENTER", 0, 0)
		widget.count:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		return widget
	end, { corner = "top_right", priority = 1 })
end

-- Events ----------------------------------------------------------------------------------------------------------

function events:TRADE_SKILL_CRAFT_BEGIN(recipeSpellID)
	pending = recipeSpellID
end

-- One result per craft (a multicraft is still one craft). Recipe IDs are the recipes' spell IDs.
function events:TRADE_SKILL_ITEM_CRAFTED_RESULT(data)
	if not pending or (data and data.bonusCraft) then
		return
	end
	local entry = ns.Alts_ListCrafted(ns.altsDB.list, pending, db.listDone == "auto")
	if entry and entry.crafts <= 0 then
		ns.Print(("%s done: %s."):format(RecipeName(pending), db.listDone == "auto" and "off the crafting list" or "right-click it in the tracker to remove it"))
	end
	ns.AltsList_Changed()
end

function events:TRADE_SKILL_CLOSE()
	pending = nil
end

function events:PLAYER_REGEN_DISABLED()
	inCombat = true
	ns.AltsList_Refresh()
end

function events:PLAYER_REGEN_ENABLED()
	inCombat = false
	ns.AltsList_Refresh()
end

local CHANGED = { "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
	"MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "PLAYER_ENTERING_WORLD" }
for _, event in ipairs(CHANGED) do
	events[event] = function()
		ns.AltsList_Changed()
	end
end

local EVENTS = { "TRADE_SKILL_CRAFT_BEGIN", "TRADE_SKILL_ITEM_CRAFTED_RESULT", "TRADE_SKILL_CLOSE",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

function ns.AltsList_Start(moduleDB)
	db = moduleDB
	for _, list in ipairs({ EVENTS, CHANGED }) do
		for _, event in ipairs(list) do
			pcall(events.RegisterEvent, events, event)
		end
	end
	RegisterBaganator()
	if _G.Syndicator and Syndicator.CallbackRegistry and not events.syndicator then
		events.syndicator = true
		for _, name in ipairs({ "BagCacheUpdate", "MailCacheUpdate", "WarbandBankCacheUpdate" }) do
			pcall(Syndicator.CallbackRegistry.RegisterCallback, Syndicator.CallbackRegistry, name, function()
				if ns.altsModule.active then
					ns.AltsList_Changed()
				end
			end, events)
		end
	end
	ns.AltsList_Changed()
end

function ns.AltsList_Stop()
	events:UnregisterAllEvents()
	if frame then
		frame:Hide()
	end
end
