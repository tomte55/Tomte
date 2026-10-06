local addonName, ns = ...

-- Send to alt: at a mailbox, a panel beside the mail frame lists what this character carries that another
-- character uses (reagents of recipes they know, the Crafting tab's plan, manual rules), grouped by who gets it.
-- Per group: "Attach" fills the Send Mail tab (recipient, subject, up to 12 stacks), then "Send" sends it. At the
-- bank, "Deposit for alts" puts the suggested items that may go into the Warband bank there. With Gear Check's
-- upgrades for alts, Bind on Equip gear that's a clean upgrade for another character gets a "Gear for <name>" group
-- at the mailbox, and warbound gear goes in the Warband bank with the rest. Every move is one click; nothing happens
-- in combat. Rules in SendData.lua.

local UI = ns.UI
local GOLD, WHITE, GREY = UI.GOLD, UI.WHITE, UI.GREY
local RED = { 1, 0.45, 0.35 }
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
local toppingUp -- { c, amount } while a gold top-up is on its way
local depositing = false

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function Say(text)
	ns.Print(text)
end

local function ClassColor(c)
	local color = c.class and C_ClassColor.GetClassColor(c.class)
	return color and { color.r, color.g, color.b } or WHITE
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

local function Context()
	local alts = ns.altsDB
	local plan = db.sendPlan and ns.AltsCraft_LastPlan and ns.Alts_PlanAssignments(ns.AltsCraft_LastPlan, alts.recipes) or nil
	return {
		me = UnitGUID("player"), chars = alts.chars, users = ns.Alts_ReagentUsers(alts.chars, alts.recipes),
		plan = plan, rules = ns.Alts_ParseRules(db.sendRules),
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
	return ns.Alts_GearGroups(GearStacks(), "mail", ns.altsDB.chars)
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

-- Tracked crafts that need something from your bags: { { todo, wants, to } }.
local function CraftMails()
	if not ns.AltsList_Todos then
		return {}
	end
	local out = {}
	for _, todo in ipairs(ns.AltsList_Todos()) do
		local wants, to = ns.Alts_CraftMail(todo)
		if to and #wants > 0 and ns.altsDB.chars[to] then
			out[#out + 1] = { todo = todo, wants = wants, to = to }
		end
	end
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
	local list = g.gear and gear or ns.Alts_SendGroups(Without(FreeStacks(), Slots(gear)), Context(), Mailable)
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
	toppingUp = { c = c, amount = amount }
	SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), "")
end

-- Dock ------------------------------------------------------------------------------------------------------------

local function CreateDock()
	dock = CreateFrame("Frame", "TomteSendDock", MailFrame)
	dock:SetWidth(WIDTH)
	dock:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
	dock:SetFrameStrata("HIGH")
	dock:EnableMouse(true)
	local bg = dock:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], 0.96)
	UI.Border(dock, GOLD[1], GOLD[2], GOLD[3], 0.45)
	dock.title = UI.Text(dock, 16, GOLD, ns.HomeKit.DISPLAY_FONT)
	dock.title:SetPoint("TOPLEFT", 12, -10)
	dock.title:SetText("For your alts")
	dock.postage = UI.Text(dock, 11, GREY)
	dock.postage:SetPoint("TOPRIGHT", -12, -14)
	dock.blocks = {}
	dock.lines = {}
	dock.note = UI.Text(dock, 11, GREY)
	dock.note:SetWordWrap(true)
end

local function Line(i)
	local fs = dock.lines[i]
	if not fs then
		fs = UI.Text(dock, 12, WHITE)
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
		b.name = UI.Text(b, 13, WHITE)
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
		b.name:SetText(("%s: |cffffd173%s x%d|r"):format(
			color and ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, c.name or "?") or c.name,
			recipe and recipe.name or "?", cm.todo.entry.crafts))
		b.name:SetTextColor(1, 1, 1)
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
				fs:SetText(("|cff9e9e9e+ %d more|r"):format(#cm.wants - MAX_ITEM_ROWS))
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
				fs:SetText(("|cff9e9e9e+ %d more|r"):format(#g.stacks - MAX_ITEM_ROWS))
				break
			end
			local icon = s.icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(s.icon) or ""
			fs:SetText(("%s%s |cff4fe06a%s|r"):format(icon, s.link or s.name or "?", s.gainText or ns.Gear_AltGain(s.verdict)))
		end
		y = y + 8
	end
	if blocks > 0 and #groups > 0 then
		lines = lines + 1
		local fs = Line(lines)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 12, -y)
		fs:SetPoint("RIGHT", -12, 0)
		fs:SetText("|cff9e9e9eEverything else your alts craft with|r")
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
		b.name:SetText(("%s  |cff9e9e9e%d stack%s|r"):format(c.name or "?", #g.stacks, #g.stacks == 1 and "" or "s"))
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
				fs:SetText(("|cff9e9e9e+ %d more|r"):format(#g.stacks - MAX_ITEM_ROWS))
				y = y + ROW_H
				break
			end
			lines = lines + 1
			local fs = Line(lines)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", 22, -y)
			fs:SetPoint("RIGHT", -12, 0)
			local icon = s.icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(s.icon) or ""
			fs:SetText(("%s%s |cff9e9e9ex%d|r"):format(icon, s.link or s.name or "?", s.count or 1))
			y = y + ROW_H
		end
		if #g.stacks > MAX_ATTACH then
			lines = lines + 1
			local fs = Line(lines)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", 22, -y)
			fs:SetPoint("RIGHT", -12, 0)
			fs:SetText(("|cff9e9e9e%d mails (12 stacks each)|r"):format(math.ceil(#g.stacks / MAX_ATTACH)))
			y = y + ROW_H
		end
		y = y + 8
	end
	-- Gold top-ups.
	if db.sendGold and db.sendGold > 0 then
		local target = db.sendGold * 1000 * 10000
		for guid, c in pairs(ns.altsDB.chars) do
			local amount = guid ~= UnitGUID("player") and ns.Alts_TopUp(c.money, target, GetMoney(), target)
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
	groups = ns.Alts_SendGroups(Without(FreeStacks(), Slots(gearGroups)), Context(), Mailable)
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
	C_Timer.After(0.2, ShowDock) -- after the mail frame has opened
end

function events:MAIL_CLOSED()
	attached, toppingUp = nil, nil
	if dock then
		dock:Hide()
	end
end

function events:MAIL_SEND_SUCCESS()
	if attached then
		local c = ns.altsDB.chars[attached.guid]
		Say(("sent %d stack%s to %s."):format(#attached.stacks, #attached.stacks == 1 and "" or "s", c and c.name or "?"))
	end
	if toppingUp then
		-- The stored gold is from the alt's last login: count the top-up in, so it isn't offered again.
		toppingUp.c.money = (toppingUp.c.money or 0) + toppingUp.amount
	end
	attached, toppingUp = nil, nil
	C_Timer.After(0.5, ShowDock) -- the bags have changed
end

function events:MAIL_FAILED()
	attached, toppingUp = nil, nil
	if dock and dock:IsShown() then
		ns.AltsSend_Refresh()
	end
end

-- Bags changed with the mailbox open (taking items from the inbox, for one): what there is to send may have too.
-- Not while something is attached: the attached stacks left the bags and the Send button must stay.
local bagsPending
function events:BAG_UPDATE_DELAYED()
	if bagsPending or attached or toppingUp or not (MailFrame and MailFrame:IsShown()) then
		return
	end
	bagsPending = true
	C_Timer.After(0.3, function()
		bagsPending = nil
		if db and not attached and not toppingUp and MailFrame and MailFrame:IsShown() then
			ShowDock()
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
		if bankButton and bankButton:IsShown() then
			bankButton:Update()
		end
	end)
end

local function CreateBankButton()
	bankButton = UI.Button(BankFrame, 150, "")
	bankButton:SetHeight(22)
	bankButton:SetPoint("BOTTOMRIGHT", BankFrame, "TOPRIGHT", 0, 4)
	bankButton:SetScript("OnClick", Deposit)
	bankButton:SetScript("OnEnter", function(self)
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 1)
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
		UI.SetBorderColor(self, GOLD[1], GOLD[2], GOLD[3], 0.45)
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

function events:BANKFRAME_OPENED()
	if not (db.sendWarband and BankFrame and ns.altsDB) then
		return
	end
	C_Timer.After(0.3, function()
		if not bankButton then
			CreateBankButton()
		end
		bankButton:Update()
	end)
end

function events:BANKFRAME_CLOSED()
	if bankButton then
		bankButton:Hide()
	end
end

-- Home line: what's waiting for whom (from the last bag read).
function ns.AltsSend_Summary()
	if not (db and (db.sendMail or db.sendWarband) and ns.altsDB) then
		return nil
	end
	-- Only stacks the mailbox or the Warband bank can actually move (not soulbound ones).
	local list = ns.Alts_SendGroups(BagStacks(), Context(), function(s)
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
	"BAG_UPDATE_DELAYED" }

function ns.AltsSend_Start(moduleDB)
	db = moduleDB
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
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
	attached = nil
end
