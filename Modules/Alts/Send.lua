local addonName, ns = ...

-- Send to alt: at a mailbox, a panel beside the mail frame lists what this character carries that another
-- character uses (reagents of recipes they know, the Crafting tab's plan, manual rules), grouped by who gets it.
-- Per group: "Attach" fills the Send Mail tab (recipient, subject, up to 12 stacks), then "Send" sends it. At the
-- bank, "Deposit for alts" puts the suggested items that may go into the Warband bank there. With Gear Check's
-- upgrades for alts, Bind on Equip gear that's a clean upgrade for another character gets a "Gear for <name>" group
-- at the mailbox, and warbound gear goes in the Warband bank with the rest. Every move is one click; nothing happens
-- in combat. Rules in SendData.lua.

local UI = ns.UI
local WIDTH = 270
local ROW_H = 18
local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local MAX_ITEM_ROWS = 4 -- per group; the rest is "+n more"
local TRADESKILL = 7 -- Enum.ItemClass.Tradegoods
local QUEST = 12

local db
local dock, bankButton
local groups = {}
local gearGroups = {}
local attached -- { guid, stacks } while a mail is filled in and not sent yet
local toppingUp -- { c, amount, money, timer } while a gold top-up is on its way
local depositing = false
local bankOpen = false
local TOPUP_WAIT = 30 -- seconds a gold top-up may wait for its confirmation before it's forgotten
local REBUILD_EVERY = 1 -- seconds between rebuilds on bag changes at the mailbox or bank

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Say(text)
	ns.Print(text)
end

local function ClassColor(c)
	local color = c.class and C_ClassColor.GetClassColor(c.class)
	if color then
		return { color.r, color.g, color.b }
	end
	local r, g, b = UI.Color("text")
	return { r, g, b }
end

-- This character's bag stacks with what the rules need.
local function BagStacks()
	local stacks = {}
	for bag = 0, 5 do -- Backpack .. ReagentBag
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isLocked then
				local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
				if classID ~= QUEST then
					stacks[#stacks + 1] = {
						bag = bag, slot = slot, itemID = info.itemID, name = info.itemName, count = info.stackCount,
						icon = info.iconFileID, link = info.hyperlink, bound = info.isBound, quality = info.quality,
						classID = classID,
					}
				end
			end
		end
	end
	return stacks
end

-- The realms mail reaches (ns.Alts_RealmSet), nil while that isn't known. The connected realms don't change in a
-- session, so a non-empty list is kept. GetAutoCompleteRealms moved to C_AutoComplete (the global is a deprecation
-- fallback since 12.0.5); either answers an empty list on a realm that isn't connected.
local realmSet
function ns.Alts_MailRealms()
	if realmSet then
		return realmSet
	end
	local myRealm = GetNormalizedRealmName and GetNormalizedRealmName()
	if not myRealm or myRealm == "" then
		return nil
	end
	local get = (C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms) or GetAutoCompleteRealms
	local ok, realms = false, nil
	if get then
		ok, realms = pcall(get)
	end
	realms = ok and type(realms) == "table" and realms or {}
	local set = ns.Alts_RealmSet(realms, myRealm)
	if #realms > 0 then
		realmSet = set
	end
	return set
end

-- Every character's reagent users, kept until recipes or characters change (Alts_RecipesChanged, a new recipe, a
-- mailbox or bank visit) or a minute has passed: the panel is drawn again on bag changes.
local usersCache, usersAt
local function UsersChanged()
	usersCache = nil
end
ns.AltsSend_UsersChanged = UsersChanged

local function Users()
	local now = GetTime()
	if not usersCache or now - usersAt > 60 then
		usersCache, usersAt = ns.Alts_ReagentUsers(ns.altsDB.chars, ns.altsDB.recipes), now
	end
	return usersCache
end

-- forMail: leave out characters mail can't reach (the Warband bank reaches everyone).
local function Context(forMail)
	local alts = ns.altsDB
	local plan = db.sendPlan and ns.AltsCraft_LastPlan and ns.Alts_PlanAssignments(ns.AltsCraft_LastPlan, alts.recipes) or nil
	return {
		me = UnitGUID("player"), chars = alts.chars, users = Users(),
		plan = plan, rules = ns.Alts_ParseRules(db.sendRules), realms = forMail and ns.Alts_MailRealms() or nil,
	}
end

local function Mailable(s)
	return not s.bound
end

local function Warbandable(s)
	if not (C_Bank and C_Bank.IsItemAllowedInBankType and Enum.BankType and Enum.BankType.Account) then
		return false
	end
	local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account,
		ItemLocation:CreateFromBagAndSlot(s.bag, s.slot))
	return ok and allowed == true
end

-- Gear Check's "Gear for alts at the mailbox": its module on, the setting on, upgrades for alts not off.
local function GearOn()
	local gear = ns.gearDB
	return ns.gearModule and ns.gearModule.active and gear and gear.altMail and gear.altUpgrades ~= "off"
		and ns.GearAlts_Upgrades ~= nil
end

-- Bag gear that's a clean upgrade for another character and can get to them, marked with to (the character it
-- helps most), route ("mail" | "warband") and verdict (gainText instead for profession gear, ProfGear.lua). Your
-- own upgrades stay with you. Items still loading are left out; AltsSend_OnGearReady draws the panel again once
-- they've arrived.
local function GearStacks()
	local out = {}
	local gearOn = GearOn()
	for _, s in ipairs(BagStacks()) do
		local equipLoc = s.link and select(4, C_Item.GetItemInfoInstant(s.link))
		local up = equipLoc and ns.AltsProf_ItemOf(s.link) and ns.AltsProf_BagUpgrade(s.link)
		if up then
			-- Profession gear: by item level against what they wear (ProfGear.lua), with or without Gear Check.
			local route = ns.GearAlts_Route and ns.GearAlts_Route(s.link, ItemLocation:CreateFromBagAndSlot(s.bag, s.slot))
			if route then
				s.to, s.route = up.guid, route
				s.gainText = ns.AltsProf_GainText(up.gain == nil and "empty" or nil, up.gain)
				out[#out + 1] = s
			end
		elseif gearOn and equipLoc and ns.Gear_Slots(equipLoc) then
			local route = ns.GearAlts_Route(s.link, ItemLocation:CreateFromBagAndSlot(s.bag, s.slot))
			local best = route and ns.GearAlts_Upgrades(s.link)[1]
			if best and not ns.Gear_IsCleanUpgrade(ns.Gear_EvaluateLink(s.link)) then
				s.to, s.route, s.verdict = best.guid, route, best.verdict
				out[#out + 1] = s
			end
		end
	end
	return out
end

-- Stacks not in skip ([bag .. ":" .. slot] = true): what a gear group takes isn't offered twice.
local function Without(stacks, skip)
	local out = {}
	for _, s in ipairs(stacks) do
		if not skip[s.bag .. ":" .. s.slot] then
			out[#out + 1] = s
		end
	end
	return out
end

local function Slots(groupList)
	local set = {}
	for _, g in ipairs(groupList) do
		for _, s in ipairs(g.stacks) do
			set[s.bag .. ":" .. s.slot] = true
		end
	end
	return set
end

local function GearMailGroups()
	return ns.Alts_GearGroups(GearStacks(), "mail", ns.altsDB.chars, ns.Alts_MailRealms())
end

local function Busy()
	if InCombatLockdown() then
		Say("not in combat.")
		return true
	end
	return false
end

-- Mail ------------------------------------------------------------------------------------------------------------

local function SendTabShown()
	return SendMailFrame and SendMailFrame:IsShown()
end

local function AttachmentCount()
	local n = 0
	for i = 1, MAX_ATTACH do
		if HasSendMailItem(i) then
			n = n + 1
		end
	end
	return n
end

-- Tracked crafts that need something from your bags: { { todo, wants, to } }. Worked out once per to-do (List.lua
-- keeps the to-do until something changes).
local craftMails, craftMailsFor
local function CraftMails()
	if not ns.AltsList_Todos then
		return {}
	end
	local todos = ns.AltsList_Todos()
	if craftMails and craftMailsFor == todos then
		return craftMails
	end
	local out = {}
	for _, todo in ipairs(todos) do
		local wants, to = ns.Alts_CraftMail(todo)
		if to and #wants > 0 and ns.altsDB.chars[to] then
			out[#out + 1] = { todo = todo, wants = wants, to = to }
		end
	end
	craftMails, craftMailsFor = out, todos
	return out
end

-- Bag stacks for the "everything else" groups: what the tracked crafts' mails take is left out (else it shows twice).
local function FreeStacks()
	local claims = {}
	for _, cm in ipairs(CraftMails()) do
		for _, w in ipairs(cm.wants) do
			claims[w.itemID] = (claims[w.itemID] or 0) + w.n
		end
	end
	return ns.Alts_Unclaimed(BagStacks(), claims)
end

local function Attach(g)
	if Busy() then
		return
	end
	if not SendTabShown() and MailFrameTab_OnClick then
		MailFrameTab_OnClick(nil, 2)
	end
	if not SendTabShown() then
		Say("open the Send Mail tab first.")
		return
	end
	if AttachmentCount() > 0 then
		Say("the Send Mail tab already has items attached: send or remove them first.")
		return
	end
	local c = ns.altsDB.chars[g.guid]
	-- Read the bags again: the group's bag slots are from when the panel was drawn, and items may have moved since.
	local fresh
	local gear = GearMailGroups()
	local list = g.gear and gear or ns.Alts_SendGroups(Without(FreeStacks(), Slots(gear)), Context(true), Mailable)
	for _, group in ipairs(list) do
		if group.guid == g.guid then
			fresh = group
		end
	end
	if not fresh then
		Say(("nothing left in your bags for %s."):format(c and c.name or "?"))
		ns.AltsSend_Refresh()
		return
	end
	ClearCursor()
	local mail = ns.Alts_NextMail(fresh, MAX_ATTACH)
	local done = {}
	for i, s in ipairs(mail) do
		C_Container.PickupContainerItem(s.bag, s.slot)
		ClickSendMailItemButton(i)
		ClearCursor() -- in case the slot didn't take it
		done[#done + 1] = s
	end
	SendMailNameEditBox:SetText(ns.Alts_MailName(c, GetRealmName()))
	SendMailSubjectEditBox:SetText(db.sendSubject ~= "" and db.sendSubject or "Tomte")
	attached = { guid = g.guid, stacks = done, gear = g.gear }
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	ns.AltsSend_Refresh()
end

-- Crafting list: attach what one tracked craft needs from your bags (exact amounts by splitting stacks, or whole
-- stacks), for its crafter.
local function AttachCraft(cm)
	if Busy() then
		return
	end
	if not SendTabShown() and MailFrameTab_OnClick then
		MailFrameTab_OnClick(nil, 2)
	end
	if not SendTabShown() then
		Say("open the Send Mail tab first.")
		return
	end
	if AttachmentCount() > 0 then
		Say("the Send Mail tab already has items attached: send or remove them first.")
		return
	end
	local stacks = {}
	for _, st in ipairs(BagStacks()) do
		if not st.bound then
			stacks[#stacks + 1] = st
		end
	end
	local plan = ns.Alts_AttachPlan(cm.wants, stacks, db.listMail ~= "stacks", MAX_ATTACH)
	if #plan == 0 then
		Say("nothing in your bags for that craft.")
		return
	end
	ClearCursor()
	for i, a in ipairs(plan) do
		if a.split then
			C_Container.SplitContainerItem(a.bag, a.slot, a.split)
		else
			C_Container.PickupContainerItem(a.bag, a.slot)
		end
		ClickSendMailItemButton(i)
		ClearCursor()
	end
	local c = ns.altsDB.chars[cm.to]
	SendMailNameEditBox:SetText(ns.Alts_MailName(c, GetRealmName()))
	local recipe = ns.altsDB.recipes[cm.todo.entry.recipeID]
	SendMailSubjectEditBox:SetText(("%s: %s"):format(db.sendSubject ~= "" and db.sendSubject or "Tomte", recipe and recipe.name or "craft"))
	attached = { guid = cm.to, stacks = plan, craft = cm.todo.entry.recipeID }
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	ns.AltsSend_Refresh()
end

local function Send()
	if Busy() or not attached then
		return
	end
	if not SendTabShown() or AttachmentCount() == 0 then
		Say("nothing attached to send.")
		attached = nil
		ns.AltsSend_Refresh()
		return
	end
	local price = GetSendMailPrice and GetSendMailPrice() or 0
	if price > GetMoney() then
		Say("not enough gold for the postage.")
		return
	end
	-- Items only: no gold or C.O.D. left over from a top-up or typed in earlier (Blizzard's Send button resets
	-- both too, SendMailMailButton_OnClick).
	SetSendMailCOD(0)
	SetSendMailMoney(0)
	SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), SendMailBodyEditBox and SendMailBodyEditBox:GetText() or "")
end

local function TopUp(c, amount)
	if Busy() then
		return
	end
	if not SendTabShown() and MailFrameTab_OnClick then
		MailFrameTab_OnClick(nil, 2)
	end
	if not SendTabShown() or AttachmentCount() > 0 then
		Say("open an empty Send Mail tab first.")
		return
	end
	SendMailNameEditBox:SetText(ns.Alts_MailName(c, GetRealmName()))
	SendMailSubjectEditBox:SetText(db.sendSubject ~= "" and db.sendSubject or "Tomte")
	SetSendMailCOD(0)
	SetSendMailMoney(amount)
	-- The game asks to confirm a gold mail, and a cancelled confirmation may send no event: the top-up is
	-- forgotten after a while, and MAIL_SEND_SUCCESS only counts it when the gold actually left.
	if toppingUp and toppingUp.timer then
		toppingUp.timer:Cancel()
	end
	local pending = { c = c, amount = amount, money = GetMoney() }
	pending.timer = C_Timer.NewTimer(TOPUP_WAIT, function()
		if toppingUp == pending then
			toppingUp = nil
		end
	end)
	toppingUp = pending
	SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), "")
end

local function ClearTopUp()
	if toppingUp and toppingUp.timer then
		toppingUp.timer:Cancel()
	end
	toppingUp = nil
end

-- Dock ------------------------------------------------------------------------------------------------------------

local function CreateDock()
	dock = CreateFrame("Frame", "TomteSendDock", MailFrame)
	dock:SetWidth(WIDTH)
	dock:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
	dock:SetFrameStrata("HIGH")
	dock:EnableMouse(true)
	UI.Panel(dock, { alpha = 0.96 })
	dock.title = UI.Text(dock, 15, "heading", "title")
	dock.title:SetPoint("TOPLEFT", 12, -10)
	dock.title:SetText("For your alts")
	dock.postage = UI.Text(dock, 11, "textMuted")
	dock.postage:SetPoint("TOPRIGHT", -12, -14)
	dock.blocks = {}
	dock.lines = {}
	dock.note = UI.Text(dock, 11, "textMuted")
	dock.note:SetWordWrap(true)
end

local function Line(i)
	local fs = dock.lines[i]
	if not fs then
		fs = UI.Text(dock, 12, "text")
		fs:SetWordWrap(false)
		dock.lines[i] = fs
	end
	fs:Show()
	return fs
end

local function Block(i)
	local b = dock.blocks[i]
	if not b then
		b = CreateFrame("Frame", nil, dock)
		b:SetHeight(22)
		b.name = UI.Text(b, 13, "text")
		b.name:SetPoint("LEFT", 0, 0)
		b.button = UI.Button(b, 70, "Attach")
		b.button:SetHeight(20)
		b.button:SetPoint("RIGHT", 0, 0)
		b.button:SetScript("OnClick", function(self)
			self.onClick()
		end)
		b.name:SetPoint("RIGHT", b.button, "LEFT", -8, 0)
		b.name:SetWordWrap(false)
		dock.blocks[i] = b
	end
	b:Show()
	return b
end

function ns.AltsSend_Refresh()
	if not (dock and dock:IsShown()) then
		return
	end
	for _, b in ipairs(dock.blocks) do
		b:Hide()
	end
	for _, fs in ipairs(dock.lines) do
		fs:Hide()
	end
	local y = 36
	local lines, blocks = 0, 0
	-- Tracked crafts first.
	for _, cm in ipairs(CraftMails()) do
		local c = ns.altsDB.chars[cm.to]
		local recipe = ns.altsDB.recipes[cm.todo.entry.recipeID]
		blocks = blocks + 1
		local b = Block(blocks)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 12, -y)
		b:SetPoint("RIGHT", -12, 0)
		local color = ClassColor(c)
		-- Who it's for first (like the rows below), so a long recipe name is what gets cut.
		local quality = recipe and ns.Alts_Qualities(recipe) > 1 and ns.Alts_ClampQuality(recipe, cm.todo.entry.quality)
		b.name:SetText(("%s: %s%s"):format(
			color and ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, c.name or "?") or c.name,
			UI.Wrap(("%s x%d"):format(recipe and recipe.name or "?", cm.todo.entry.crafts), "heading"),
			quality and (" " .. ns.Alts_QualityMarkup(cm.todo.entry.recipeID, quality)) or ""))
		UI.SetTextRole(b.name, "text")
		local isAttached = attached and attached.craft == cm.todo.entry.recipeID
		b.button.label:SetText(isAttached and "Send" or "Attach")
		b.button.onClick = function()
			if isAttached then
				Send()
			else
				AttachCraft(cm)
			end
		end
		y = y + 24
		for i, w in ipairs(cm.wants) do
			if i > MAX_ITEM_ROWS then
				lines = lines + 1
				local fs = Line(lines)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", 22, -y)
				fs:SetPoint("RIGHT", -12, 0)
				fs:SetText(UI.Wrap(("+ %d more"):format(#cm.wants - MAX_ITEM_ROWS), "textMuted"))
				y = y + ROW_H
				break
			end
			lines = lines + 1
			local fs = Line(lines)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", 22, -y)
			fs:SetPoint("RIGHT", -12, 0)
			local icon = C_Item.GetItemIconByID(w.itemID)
			fs:SetText(("%s%d %s"):format(icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or "", w.n,
				C_Item.GetItemNameByID(w.itemID) or ("item " .. w.itemID)))
			y = y + ROW_H
		end
		y = y + 8
	end
	-- Gear for alts (Bind on Equip upgrades), one group per character.
	for _, g in ipairs(gearGroups) do
		local c = ns.altsDB.chars[g.guid]
		blocks = blocks + 1
		local b = Block(blocks)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 12, -y)
		b:SetPoint("RIGHT", -12, 0)
		local color = ClassColor(c)
		b.name:SetText("Gear for " .. (c.name or "?"))
		b.name:SetTextColor(color[1], color[2], color[3])
		local isAttached = attached and attached.gear and attached.guid == g.guid
		b.button.label:SetText(isAttached and "Send" or "Attach")
		b.button.onClick = function()
			if isAttached then
				Send()
			else
				Attach(g)
			end
		end
		y = y + 24
		for i, s in ipairs(g.stacks) do
			lines = lines + 1
			local fs = Line(lines)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", 22, -y)
			fs:SetPoint("RIGHT", -12, 0)
			y = y + ROW_H
			if i > MAX_ITEM_ROWS then
				fs:SetText(UI.Wrap(("+ %d more"):format(#g.stacks - MAX_ITEM_ROWS), "textMuted"))
				break
			end
			local icon = s.icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(s.icon) or ""
			fs:SetText(("%s%s %s"):format(icon, s.link or s.name or "?", UI.Wrap(s.gainText or ns.Gear_AltGain(s.verdict), "success")))
		end
		y = y + 8
	end
	if blocks > 0 and #groups > 0 then
		lines = lines + 1
		local fs = Line(lines)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 12, -y)
		fs:SetPoint("RIGHT", -12, 0)
		fs:SetText(UI.Wrap("Everything else your alts craft with", "textMuted"))
		y = y + ROW_H + 4
	end
	for _, g in ipairs(groups) do
		local c = ns.altsDB.chars[g.guid]
		blocks = blocks + 1
		local b = Block(blocks)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 12, -y)
		b:SetPoint("RIGHT", -12, 0)
		local color = ClassColor(c)
		b.name:SetText(("%s  %s"):format(c.name or "?", UI.Wrap(("%d stack%s"):format(#g.stacks, #g.stacks == 1 and "" or "s"), "textMuted")))
		b.name:SetTextColor(color[1], color[2], color[3])
		local isAttached = attached and attached.guid == g.guid and not attached.craft and not attached.gear
		b.button.label:SetText(isAttached and "Send" or "Attach")
		b.button.onClick = function()
			if isAttached then
				Send()
			else
				Attach(g)
			end
		end
		y = y + 24
		for i, s in ipairs(g.stacks) do
			if i > MAX_ITEM_ROWS then
				lines = lines + 1
				local fs = Line(lines)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", 22, -y)
				fs:SetPoint("RIGHT", -12, 0)
				fs:SetText(UI.Wrap(("+ %d more"):format(#g.stacks - MAX_ITEM_ROWS), "textMuted"))
				y = y + ROW_H
				break
			end
			lines = lines + 1
			local fs = Line(lines)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", 22, -y)
			fs:SetPoint("RIGHT", -12, 0)
			local icon = s.icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(s.icon) or ""
			fs:SetText(("%s%s %s"):format(icon, s.link or s.name or "?", UI.Wrap(("x%d"):format(s.count or 1), "textMuted")))
			y = y + ROW_H
		end
		if #g.stacks > MAX_ATTACH then
			lines = lines + 1
			local fs = Line(lines)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", 22, -y)
			fs:SetPoint("RIGHT", -12, 0)
			fs:SetText(UI.Wrap(("%d mails (12 stacks each)"):format(math.ceil(#g.stacks / MAX_ATTACH)), "textMuted"))
			y = y + ROW_H
		end
		y = y + 8
	end
	-- Gold top-ups, by name; only characters mail reaches.
	if db.sendGold and db.sendGold > 0 then
		local target = db.sendGold * 1000 * 10000
		local me, realms = UnitGUID("player"), ns.Alts_MailRealms()
		local topUps = {}
		for guid, c in pairs(ns.altsDB.chars) do
			if guid ~= me and ns.Alts_Reachable(c, realms) then
				topUps[#topUps + 1] = c
			end
		end
		table.sort(topUps, function(a, b)
			if (a.name or "") ~= (b.name or "") then
				return (a.name or "") < (b.name or "")
			end
			return (a.realm or "") < (b.realm or "")
		end)
		for _, c in ipairs(topUps) do
			local amount = ns.Alts_TopUp(c.money, target, GetMoney(), target)
			if amount then
				blocks = blocks + 1
				local b = Block(blocks)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", 12, -y)
				b:SetPoint("RIGHT", -12, 0)
				local color = ClassColor(c)
				b.name:SetText(("Top up %s: %s"):format(c.name or "?", ns.Alts_Gold(amount)))
				b.name:SetTextColor(color[1], color[2], color[3])
				b.button.label:SetText("Send gold")
				b.button.onClick = function()
					TopUp(c, amount)
				end
				y = y + 26
			end
		end
	end
	dock.postage:SetText(attached and GetSendMailPrice and ("postage " .. GetCoinTextureString(GetSendMailPrice())) or "")
	dock.note:ClearAllPoints()
	dock.note:SetPoint("TOPLEFT", 12, -y)
	dock.note:SetPoint("RIGHT", -12, 0)
	dock.note:SetText(blocks == 0 and "Nothing here for your other characters." or "Attach fills the Send Mail tab; Send sends it.")
	dock:SetHeight(y + 34)
end

local function Rebuild()
	if not (db.sendMail and ns.altsDB) then
		groups, gearGroups = {}, {}
		return
	end
	gearGroups = GearMailGroups()
	groups = ns.Alts_SendGroups(Without(FreeStacks(), Slots(gearGroups)), Context(true), Mailable)
end

local function ShowDock()
	if not db.sendMail or not MailFrame then
		return
	end
	if not dock then
		CreateDock()
	end
	Rebuild()
	local hasGold = db.sendGold and db.sendGold > 0
	dock:SetShown(#groups > 0 or #gearGroups > 0 or hasGold or #CraftMails() > 0)
	ns.AltsSend_Refresh()
end

function events:MAIL_SHOW()
	attached = nil
	UsersChanged()
	C_Timer.After(0.2, ShowDock) -- after the mail frame has opened
end

function events:MAIL_CLOSED()
	attached = nil
	ClearTopUp()
	if dock then
		dock:Hide()
	end
end

function events:MAIL_SEND_SUCCESS()
	if attached then
		local c = ns.altsDB.chars[attached.guid]
		Say(("sent %d stack%s to %s."):format(#attached.stacks, #attached.stacks == 1 and "" or "s", c and c.name or "?"))
	end
	local topUp = toppingUp
	attached = nil
	ClearTopUp()
	if topUp then
		-- The stored gold is from the alt's last login: count the top-up in, so it isn't offered again. Only when
		-- the gold left (the amount plus postage): this may be another mail after a cancelled top-up. A moment
		-- later, as the money may not have updated yet.
		C_Timer.After(0.3, function()
			local spent = topUp.money - GetMoney()
			if spent >= topUp.amount and spent <= topUp.amount + 10000 then
				topUp.c.money = (topUp.c.money or 0) + topUp.amount
				ns.AltsSend_Refresh()
			end
		end)
	end
	C_Timer.After(0.5, ShowDock) -- the bags have changed
end

function events:MAIL_FAILED()
	if toppingUp then
		SetSendMailMoney(0) -- not left on the Send Mail tab for the next mail
	end
	attached = nil
	ClearTopUp()
	if dock and dock:IsShown() then
		ns.AltsSend_Refresh()
	end
end

function events:NEW_RECIPE_LEARNED()
	UsersChanged()
end

local UpdateBankButton -- Warband bank, below

-- Bags changed with the mailbox open (taking items from the inbox, for one) or at the bank (moving items by hand):
-- what there is to send or deposit may have too. At most once a second. At the mailbox not while something is
-- attached: the attached stacks left the bags and the Send button must stay.
local bagsPending
function events:BAG_UPDATE_DELAYED()
	if bagsPending or not db or not ((MailFrame and MailFrame:IsShown()) or bankOpen) then
		return
	end
	bagsPending = true
	C_Timer.After(REBUILD_EVERY, function()
		bagsPending = nil
		if not db then
			return
		end
		if not attached and not toppingUp and MailFrame and MailFrame:IsShown() then
			ShowDock()
		end
		if bankOpen then
			UpdateBankButton()
		end
	end)
end

-- Gear Check's items have loaded: the mailbox's gear groups may have changed.
function ns.AltsSend_OnGearReady()
	if db and dock and MailFrame and MailFrame:IsShown() then
		ShowDock()
	end
end

-- Warband bank ----------------------------------------------------------------------------------------------------

-- What "Deposit for alts" puts in the Warband bank: materials, then warbound gear for alts ("Gear for" groups).
local function DepositGroups()
	local gear = {}
	for _, g in ipairs(ns.Alts_GearGroups(GearStacks(), "warband", ns.altsDB.chars)) do
		local allowed = {}
		for _, s in ipairs(g.stacks) do
			if Warbandable(s) then
				allowed[#allowed + 1] = s
			end
		end
		if #allowed > 0 then
			g.stacks = allowed
			gear[#gear + 1] = g
		end
	end
	local list = ns.Alts_SendGroups(Without(BagStacks(), Slots(gear)), Context(), Warbandable)
	for _, g in ipairs(gear) do
		list[#list + 1] = g
	end
	return list
end

local function Deposit()
	if Busy() or depositing then
		return
	end
	local list = DepositGroups()
	local n = 0
	depositing = true
	for _, g in ipairs(list) do
		for _, s in ipairs(g.stacks) do
			C_Container.UseContainerItem(s.bag, s.slot, nil, Enum.BankType.Account, false)
			n = n + 1
		end
	end
	depositing = false
	Say(n == 0 and "nothing to put in the Warband bank for your alts." or ("put %d stack%s in the Warband bank for your alts."):format(n, n == 1 and "" or "s"))
	C_Timer.After(0.5, function()
		if bankButton and bankOpen then
			bankButton:Update()
		end
	end)
end

-- Baganator's bank view, when it's the one showing (Baganator parents Blizzard's BankFrame to a hidden frame). It
-- has no API for the frame; its views are named "Baganator_<Single|Category>ViewBankViewFrame<skin key>" (Baganator
-- ViewManagement/Initialize.lua). The current skin comes from its API; the built-in skin keys (its Skins/*.lua) are
-- the fallback. Only looked at, never changed.
local BAGANATOR_SKINS = { "blizzard", "blizzard_black", "dark", "elvui", "gw2_ui", "ndui", "ellesmereui" }
local function BaganatorBankFrame()
	if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Baganator")) then
		return nil
	end
	local skins = BAGANATOR_SKINS
	local api = _G.Baganator and Baganator.API and Baganator.API.Skins
	local ok, current = pcall(function()
		return api and api.GetCurrentSkin and api.GetCurrentSkin()
	end)
	if ok and type(current) == "string" then
		skins = { current }
		for _, skin in ipairs(BAGANATOR_SKINS) do
			skins[#skins + 1] = skin
		end
	end
	for _, skin in ipairs(skins) do
		for _, view in ipairs({ "Single", "Category" }) do
			local f = _G["Baganator_" .. view .. "ViewBankViewFrame" .. skin]
			if type(f) == "table" and f.IsVisible and f:IsVisible() then
				return f
			end
		end
	end
	return nil
end

-- Above the bank window you see: Baganator's, else Blizzard's, else near the top of the screen.
local function PlaceBankButton()
	local anchor = BaganatorBankFrame() or (BankFrame and BankFrame:IsVisible() and BankFrame) or nil
	bankButton:ClearAllPoints()
	if anchor then
		bankButton:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)
		bankButton:SetFrameStrata(anchor:GetFrameStrata())
		bankButton:SetFrameLevel(anchor:GetFrameLevel() + 20)
	else
		bankButton:SetPoint("TOP", UIParent, "TOP", 0, -120)
		bankButton:SetFrameStrata("HIGH")
	end
end

local function CreateBankButton()
	-- On UIParent: a bag addon (Baganator) may keep Blizzard's BankFrame hidden for good.
	bankButton = UI.Button(UIParent, 150, "")
	bankButton:SetHeight(22)
	bankButton:SetClampedToScreen(true)
	bankButton:Hide()
	bankButton:SetScript("OnClick", Deposit)
	bankButton:SetScript("OnEnter", function(self)
		UI.SetBorderColor(self, "accent", 1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Deposit for alts", 1, 1, 1)
		GameTooltip:AddLine("Puts what your other characters craft with (and you don't) into the Warband bank"
			.. (GearOn() and ", and warbound gear that's an upgrade for them." or ", and warbound profession gear that's an "
			.. "upgrade for them."), nil, nil, nil, true)
		for _, g in ipairs(self.groups or {}) do
			local c = ns.altsDB.chars[g.guid]
			GameTooltip:AddDoubleLine((g.gear and "Gear for " or "") .. (c.name or "?"), ("%d stack%s"):format(#g.stacks, #g.stacks == 1 and "" or "s"),
				unpack(ClassColor(c)))
		end
		GameTooltip:Show()
	end)
	bankButton:SetScript("OnLeave", function(self)
		UI.SetBorderColor(self, "frame", UI.BUTTON_RULE)
		GameTooltip:Hide()
	end)
	function bankButton:Update()
		self.groups = DepositGroups()
		local n = 0
		for _, g in ipairs(self.groups) do
			n = n + #g.stacks
		end
		self.label:SetText(("Deposit for alts (%d)"):format(n))
		self:SetShown(n > 0)
	end
end

function UpdateBankButton()
	if not (bankOpen and db and db.sendWarband and ns.altsDB) then
		if bankButton then
			bankButton:Hide()
		end
		return
	end
	if not bankButton then
		CreateBankButton()
	end
	PlaceBankButton()
	bankButton:Update()
end

function events:BANKFRAME_OPENED()
	bankOpen = true
	UsersChanged()
	C_Timer.After(0.3, UpdateBankButton) -- after the bank window (Blizzard's or Baganator's) has opened
end

function events:BANKFRAME_CLOSED()
	bankOpen = false
	if bankButton then
		bankButton:Hide()
	end
end

-- Home line: what's waiting for whom (from the last bag read).
function ns.AltsSend_Summary()
	if not (db and (db.sendMail or db.sendWarband) and ns.altsDB) then
		return nil
	end
	-- Only stacks the mailbox or the Warband bank can actually move (not soulbound ones; mail only: not to
	-- characters mail can't reach).
	local list = ns.Alts_SendGroups(BagStacks(), Context(not db.sendWarband), function(s)
		return (db.sendMail and Mailable(s)) or (db.sendWarband and Warbandable(s))
	end)
	if #list == 0 then
		return nil
	end
	local names, stacks = {}, 0
	for i, g in ipairs(list) do
		stacks = stacks + #g.stacks
		if i <= 3 then
			names[#names + 1] = ns.altsDB.chars[g.guid].name or "?"
		end
	end
	return ("%d stack%s for %s"):format(stacks, stacks == 1 and "" or "s", table.concat(names, ", "))
end

local EVENTS = { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
	"BAG_UPDATE_DELAYED", "NEW_RECIPE_LEARNED" }

local hookedRecipes = false
function ns.AltsSend_Start(moduleDB)
	db = moduleDB
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	-- Recipes read or a character forgotten (Alts.lua, Collect.lua): the reagent users change.
	if not hookedRecipes and type(ns.Alts_RecipesChanged) == "function" then
		hookedRecipes = true
		hooksecurefunc(ns, "Alts_RecipesChanged", UsersChanged)
	end
end

function ns.AltsSend_Stop()
	events:UnregisterAllEvents()
	if dock then
		dock:Hide()
	end
	if bankButton then
		bankButton:Hide()
	end
	attached, bankOpen = nil, false
	ClearTopUp()
end
