local addonName, ns = ...

-- Friend crafting at the mailbox: a "For your friends" block under the "For your alts" panel (Send.lua's dock), or
-- beside the mail frame when that panel isn't up. One group per request that needs a mail: the materials you said
-- you'd send (exactly what the recipe takes), or a friend's craft you've made. Attach fills the Send Mail tab, Send
-- sends it; sending a made craft marks the request done on both sides. Groups are FriendsData.lua's
-- AltsFriends_MailGroups; the requests are Friends.lua's.

local OWNER = "friendmail" -- this file's owner on Alts' event bus
local WIDTH = 270 -- as Send.lua's dock
local ROW_H = 46
local PAD = 12

local UI = ns.UI
local events = ns.Alts_Events -- Collect.lua

local db
local block
local rows = {}
local attached -- { id, kind } of the group in the Send Mail tab
local sending -- the attached group, from our Send button until the game says the mail went (or failed)
local Draw

-- Groups for the requests, only to friends this character's mail reaches; none while friends' crafting is off.
local function Groups()
	if not ns.AltsFriends_Sharing() then
		return {}
	end
	local recipes = {}
	for _, req in pairs(db.requests) do
		recipes[req.recipeID] = ns.AltsFriends_Recipe(req.recipeID)
	end
	return ns.AltsFriends_MailGroups(db.requests, recipes,
		{ faction = UnitFactionGroup("player"), realms = ns.Alts_MailRealms() })
end

local function Title(g)
	local name = ns.AltsFriends_RecipeName(g.req)
	if g.kind == "item" then
		return ("For %s: %s"):format(g.to.name or "?", name)
	end
	return ("For %s: materials for %s"):format(g.to.name or "?", name)
end

local function Attach(g)
	if not ns.AltsSend_ReadyToAttach() then
		return
	end
	local stacks = {}
	for _, s in ipairs(ns.AltsSend_BagStacks()) do
		if not s.bound then
			stacks[#stacks + 1] = s
		end
	end
	local plan = ns.Alts_AttachPlan(g.wants, stacks, true, ns.AltsSend_MAX_ATTACH)
	if #plan == 0 then
		ns.Print(g.kind == "item" and "the craft isn't in your bags." or "none of the materials are in your bags.")
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
	SendMailNameEditBox:SetText(ns.Alts_MailName(g.to, GetRealmName()))
	SendMailSubjectEditBox:SetText("Tomte: " .. ns.AltsFriends_RecipeName(g.req))
	attached = { id = g.req.id, kind = g.kind }
	UI.Sound("confirm")
	Draw()
end

local function Send()
	if not attached or ns.AltsSend_AttachmentCount() == 0 then
		ns.Print("nothing attached to send.")
		attached = nil
		Draw()
		return
	end
	if (GetSendMailPrice and GetSendMailPrice() or 0) > GetMoney() then
		ns.Print("not enough gold for the postage.")
		return
	end
	SetSendMailCOD(0)
	SetSendMailMoney(0)
	sending = attached
	SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), SendMailBodyEditBox and SendMailBodyEditBox:GetText() or "")
end

local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row.text = UI.Text(row, 12, "text")
	row.text:SetPoint("TOPLEFT", 0, -2)
	row.text:SetPoint("RIGHT")
	row.text:SetWordWrap(false)
	row.attach = UI.Button(row, 80, "Attach")
	row.attach:SetHeight(20)
	row.attach:SetPoint("BOTTOMLEFT", 0, 2)
	row.send = UI.Button(row, 80, "Send")
	row.send:SetHeight(20)
	row.send:SetPoint("LEFT", row.attach, "RIGHT", 6, 0)
	row.attach:SetScript("OnClick", function()
		Attach(row.group)
	end)
	row.send:SetScript("OnClick", Send)
	return row
end

local function Create()
	block = CreateFrame("Frame", nil, MailFrame)
	block:SetWidth(WIDTH)
	block:SetFrameStrata("HIGH")
	block:EnableMouse(true)
	UI.Panel(block, { alpha = 0.96 })
	block.title = UI.Text(block, 15, "heading", "title")
	block.title:SetPoint("TOPLEFT", PAD, -PAD)
	block.title:SetText("For your friends")
end

function Draw()
	if not (block and block:IsShown()) then
		return
	end
	local groups = Groups()
	if #groups == 0 then
		block:Hide()
		return
	end
	block:ClearAllPoints()
	local dock = ns.AltsSend_Dock()
	if dock then
		block:SetPoint("TOPLEFT", dock, "BOTTOMLEFT", 0, -6)
	else
		block:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
	end
	for _, row in ipairs(rows) do
		row:Hide()
	end
	local y = PAD + 26
	for i, g in ipairs(groups) do
		local row = rows[i] or CreateRow(block)
		rows[i] = row
		row.group = g
		row.text:SetText(Title(g))
		local isAttached = attached and attached.id == g.req.id and attached.kind == g.kind
		row.send:SetEnabled(isAttached == true)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD, -y)
		row:SetPoint("RIGHT", -PAD, 0)
		row:Show()
		y = y + ROW_H
	end
	block:SetHeight(y + PAD)
end

local function Show()
	if #Groups() == 0 then
		if block then
			block:Hide()
		end
		return
	end
	if not block then
		Create()
	end
	block:Show()
	Draw()
end

events:On(OWNER, "MAIL_SHOW", function()
	attached, sending = nil, nil
	C_Timer.After(0.3, Show) -- after Send.lua's dock (0.2 s) has opened, to sit under it
end)

events:On(OWNER, "MAIL_CLOSED", function()
	attached, sending = nil, nil
	if block then
		block:Hide()
	end
end)

-- The group our Send button sent went: materials are marked sent, a made craft is done (and its asker hears so). A
-- mail sent another way (the game's own button, after changing the attachments) marks nothing.
events:On(OWNER, "MAIL_SEND_SUCCESS", function()
	local sent = sending
	attached, sending = nil, nil
	local req = sent and db.requests[sent.id]
	if req then
		if sent.kind == "item" then
			ns.AltsFriends_Answer(req.id, "done")
		else
			req.matsSent = true
		end
	end
	Draw()
end)

events:On(OWNER, "MAIL_FAILED", function()
	attached, sending = nil, nil
	Draw()
end)

-- While the mailbox is open: a craft just made (or materials just looted) can bring the block up.
events:On(OWNER, "BAG_UPDATE_DELAYED", function()
	if MailFrame and MailFrame:IsShown() then
		Show()
	end
end)

local EVENTS = { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "BAG_UPDATE_DELAYED" }

function ns.AltsFriendMail_Start(moduleDB)
	db = moduleDB
	for _, event in ipairs(EVENTS) do
		events:Watch(OWNER, event)
	end
end

function ns.AltsFriendMail_Stop()
	events:UnwatchAll(OWNER)
	attached, sending = nil, nil
	if block then
		block:Hide()
	end
end
