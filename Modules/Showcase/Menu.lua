local addonName, ns = ...

-- Showcase gear menu: a click on a slot opens this panel beside it. Three rows (Equipment, Enchants, Gems) with a
-- status each; a row opens its list in the same panel. Equipping and socketing run from the row's own click
-- (PickupContainerItem / PickupInventoryItem, C_ItemSocketInfo); using an enchant scroll or oil is protected, so the
-- enchant rows get one secure macro button laid over the hovered row (on WorldFrame: UIParent is hidden while the
-- Showcase is open). The game's confirmations (bind on equip, replace enchant, bind on socket) are asked here, since
-- its popups sit on the hidden UIParent.
-- Design: docs/superpowers/specs/2026-10-12-tomte-showcase-gear-menu-design.md.

local UI = ns.UI

local W = 340
local PAD = 16
local ENTRY_H = 62
local ROW_H = 46
local HEAD_H = 40
local MAX_ROWS = 9
local ICON = 32
local OWNER = "showcaseMenu"
local BAGS = { 0, 1, 2, 3, 4 }
local GEM_BAGS = { 0, 1, 2, 3, 4, 5 } -- gems may sit in the reagent bag
local ENCHANTS_ICON = "Interface\\Icons\\Trade_Engraving"
local GEMS_ICON = "Interface\\Icons\\INV_Misc_Gem_01"
local VERDICT_ROLES = { green = "success", yellow = "warning", grey = "textMuted", red = "danger", orange = "warning" }
local LINE = Enum.TooltipDataLineType

local MENU = {}
ns.CharShowMenu = MENU

local events = ns.CharShow_Events
local panel, secure
local owner -- the slot widget the menu is open for
local view = "root" -- root, equip, enchant, gems
local socketPick -- the socket the gem list fills
local socketJob -- { slot, socket, bag, bagSlot } while a gem goes in
local message -- { text, role } shown under the list once (a refusal, a result)
local confirm -- { text, accept, cancel } while the panel asks
local rows, entries, chips = {}, {}, {}

local function Tex(parent, layer, file)
	local t = parent:CreateTexture(nil, layer)
	if file then
		t:SetTexture(file)
	else
		t:SetColorTexture(1, 1, 1, 1)
	end
	return t
end

local function QualityColor(quality)
	if quality then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		return { r, g, b }
	end
	return "text"
end

local function SlotName(w)
	local desc = w.desc
	return desc and desc.equipLoc and _G[desc.equipLoc] or _G[ns.CHARSHOW_SLOT_NAMES[w.slot]] or "this slot"
end

-- Bags ---------------------------------------------------------------------------------------------------------------

-- Inventory location bits (Blizzard's Constants.lua), for GetInventoryItemsForSlot's keys.
local LOC_PLAYER = ITEM_INVENTORY_LOCATION_PLAYER or 0x00100000
local LOC_BAGS = ITEM_INVENTORY_LOCATION_BAGS or 0x00200000
local LOC_BANK = ITEM_INVENTORY_LOCATION_BANK or 0x00400000
local BAG_SHIFT = ITEM_INVENTORY_BAG_BIT_OFFSET or 8

-- bag, slot of a bag location; nil for worn, bank or anything else.
local function BagLocation(location)
	if type(location) ~= "number" or location < 0 or bit.band(location, LOC_BANK) ~= 0
		or bit.band(location, LOC_BAGS) == 0 then
		return nil
	end
	local rest = location - LOC_BAGS
	if bit.band(rest, LOC_PLAYER) ~= 0 then
		rest = rest - LOC_PLAYER
	end
	local bag = bit.rshift(rest, BAG_SHIFT)
	return bag, rest - bit.lshift(bag, BAG_SHIFT)
end

local function EquipCandidates(slot)
	local list, found = {}, {}
	GetInventoryItemsForSlot(slot, found)
	local ctx = ns.Gear_Context and ns.Gear_Context()
	for location in pairs(found) do
		local bag, bagSlot = BagLocation(location)
		local link = bag and C_Container.GetContainerItemLink(bag, bagSlot)
		if link and not ns.IsSecret(link) then
			local item = { bag = bag, bagSlot = bagSlot, link = link,
				icon = C_Item.GetItemIconByID(link),
				quality = C_Item.GetItemQualityByID(link),
				ilvl = C_Item.GetCurrentItemLevel(ItemLocation:CreateFromBagAndSlot(bag, bagSlot)) or 0 }
			if ns.Gear_Verdict then
				local _, headline, color = ns.Gear_Verdict(link, ctx)
				item.headline, item.role = headline, VERDICT_ROLES[color]
			end
			list[#list + 1] = item
		end
	end
	table.sort(list, function(a, b)
		if a.ilvl ~= b.ilvl then
			return a.ilvl > b.ilvl
		end
		return a.link < b.link
	end)
	return list
end

-- One entry per item ID: the first stack's bag and slot, the count over all stacks.
local function ScanBags(bags, keep)
	local list, byID = {}, {}
	for _, bag in ipairs(bags) do
		for bagSlot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, bagSlot)
			local itemID = info and info.itemID
			if itemID and not ns.IsSecret(itemID) then
				local entry = byID[itemID]
				if entry then
					entry.count = entry.count + (info.stackCount or 1)
				else
					local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
					local kind = keep(classID, subclassID)
					if kind then
						entry = { itemID = itemID, bag = bag, bagSlot = bagSlot, count = info.stackCount or 1,
							icon = info.iconFileID, quality = info.quality, link = info.hyperlink, kind = kind }
						byID[itemID] = entry
						list[#list + 1] = entry
					end
				end
			end
		end
	end
	return list
end

-- The bag item's Use line ("Use: Permanently enchant a ..."), for the enchant rows.
local function UseText(bag, bagSlot)
	local data = C_TooltipInfo.GetBagItem(bag, bagSlot)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if line.type == LINE.ItemSpellTriggerOnUse and text and not ns.IsSecret(text) then
			return text
		end
	end
	return nil
end

local function EnchantCandidates(w)
	local equipLoc = w.desc and w.desc.equipLoc
	local list = ScanBags(BAGS, function(classID, subclassID)
		return ns.CharShow_EnchantFits(w.slot, equipLoc, classID, subclassID)
	end)
	for _, e in ipairs(list) do
		e.detail = UseText(e.bag, e.bagSlot)
	end
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then
			return a.kind == "permanent"
		end
		return a.itemID > b.itemID -- newer items first
	end)
	return list
end

local function GemCandidates()
	local ctx = ns.Gear_Context and ns.Gear_Context()
	local best = ctx and ctx.best and ctx.best.itemID
	local list = ScanBags(GEM_BAGS, function(classID, subclassID)
		return ns.CharShow_IsGem(classID, subclassID) and "gem" or nil
	end)
	for _, g in ipairs(list) do
		local stats = ns.GearItems_GemStats(g.itemID)
		g.detail = stats and ns.Gear_StatLabel(stats) or nil
		if g.itemID == best and ctx.spec then
			g.best = true
			g.headline, g.role = ("Best for %s"):format(ctx.spec.name), "success"
		end
	end
	table.sort(list, function(a, b)
		if (a.best or false) ~= (b.best or false) then
			return a.best == true
		end
		return a.itemID > b.itemID
	end)
	return list
end

-- Actions ------------------------------------------------------------------------------------------------------------

local function Say(text, role)
	message = { text = text, role = role or "textMuted" }
end

local function Equip(item)
	if InCombatLockdown() then
		return
	end
	ClearCursor()
	C_Container.PickupContainerItem(item.bag, item.bagSlot)
	if C_PaperDollInfo.CanCursorCanGoInSlot and not C_PaperDollInfo.CanCursorCanGoInSlot(owner.slot) then
		ClearCursor()
		Say("That doesn't fit this slot.", "danger")
		return
	end
	-- The worn item goes to the bag slot the new one came from. No ClearCursor right after: a bind-on-equip item
	-- waits on the cursor for EQUIP_BIND_CONFIRM's answer. A refused swap (level, unique) would leave the item on
	-- the cursor, and a click on the world would then ask to destroy it on the hidden UI: drop it next frame.
	PickupInventoryItem(owner.slot)
	C_Timer.After(0, function()
		if CursorHasItem() and not confirm then
			ClearCursor()
		end
		-- Swapped: the menu is done (unless it's asking about binding).
		if not confirm and not CursorHasItem() then
			MENU.Close()
		end
	end)
end

-- Socketing: the gem goes on the cursor, into the socket, and the change is accepted, all inside the click when the
-- socket info is already there (SOCKET_INFO_UPDATE finishes it otherwise).
local function FinishSocket()
	local job = socketJob
	if not job or C_ItemSocketInfo.GetNumSockets() < job.socket then
		return false
	end
	socketJob = nil
	ClearCursor()
	C_Container.PickupContainerItem(job.bag, job.bagSlot)
	C_ItemSocketInfo.ClickSocketButton(job.socket)
	ClearCursor()
	local _, _, fits = C_ItemSocketInfo.GetNewSocketInfo(job.socket)
	if fits == false then
		C_ItemSocketInfo.CloseSocketInfo()
		Say("That gem doesn't fit this socket.", "danger")
		MENU.Refresh()
		return true
	end
	C_ItemSocketInfo.AcceptSockets()
	return true
end

local function Socket(gem)
	if InCombatLockdown() or not socketPick then
		return
	end
	socketJob = { slot = owner.slot, socket = socketPick, bag = gem.bag, bagSlot = gem.bagSlot }
	events:Watch(OWNER, "SOCKET_INFO_UPDATE")
	SocketInventoryItem(owner.slot)
	FinishSocket()
end

local function SocketAsked(gem)
	local current = owner.desc and owner.desc.gemSlots and owner.desc.gemSlots[socketPick]
	if current then
		local name = C_Item.GetItemNameByID(current) or "the gem"
		confirm = {
			text = ("Replace %s? It's destroyed."):format(name),
			button = "Replace",
			accept = function()
				Socket(gem)
			end,
		}
		MENU.Refresh()
	else
		Socket(gem)
	end
end

-- Secure enchant button ----------------------------------------------------------------------------------------------

local function Detach()
	if secure and not InCombatLockdown() then
		secure:Hide()
		secure:ClearAllPoints()
	end
	if secure then
		secure.row = nil
	end
end

-- A protected frame can't be anchored to an ordinary one: it's placed in WorldFrame coordinates over the row.
local function PlaceOver(row)
	local scale = row:GetEffectiveScale() / WorldFrame:GetEffectiveScale()
	local left, bottom, width, height = row:GetRect()
	if not left then
		return false
	end
	secure:ClearAllPoints()
	secure:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", left * scale, bottom * scale)
	secure:SetSize(width * scale, height * scale)
	return true
end

local function CreateSecure()
	secure = CreateFrame("Button", nil, WorldFrame, "SecureActionButtonTemplate")
	secure:SetFrameStrata("TOOLTIP") -- above the menu panel (FULLSCREEN_DIALOG), over the row it covers
	secure:Hide()
	secure:RegisterForClicks("AnyUp")
	secure:SetAttribute("useOnKeyDown", false)
	secure:SetAttribute("type", "macro")
	secure:SetScript("OnEnter", function(self)
		if self.row then
			self.row.hover:Show()
		end
	end)
	secure:SetScript("OnLeave", function(self)
		if self.row then
			self.row.hover:Hide()
		end
		Detach()
	end)
	secure:SetScript("PostClick", function(self)
		local slot = self.slot
		-- The macro's /use <slot> normally applies it; if a targeting cursor is still up, apply it here.
		if slot and SpellIsTargeting() and not InCombatLockdown() then
			PickupInventoryItem(slot)
		end
	end)
end

local function Attach(row)
	if InCombatLockdown() or not row.item then
		return
	end
	if not secure then
		CreateSecure()
	end
	if not PlaceOver(row) then
		return
	end
	local item = row.item
	secure:SetAttribute("macrotext", ns.CharShow_EnchantMacro(item.bag, item.bagSlot, owner.slot))
	secure.slot = owner.slot
	secure.row = row
	secure:Show()
end

-- Building -----------------------------------------------------------------------------------------------------------

local function Back()
	view, confirm, message = "root", nil, nil
	MENU.Refresh()
end

local function CreateEntry(i)
	local e = CreateFrame("Button", nil, panel)
	e:SetSize(W - 2 * PAD, ENTRY_H - 6)
	e:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * ENTRY_H)
	e.hover = Tex(e, "BACKGROUND")
	e.hover:SetAllPoints()
	e.hover:SetColorTexture(UI.RGBA("hover"))
	e.hover:Hide()
	e.icon = Tex(e, "ARTWORK")
	e.icon:SetSize(36, 36)
	e.icon:SetPoint("LEFT", 6, 0)
	e.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	e.title = UI.Text(e, 16, "text", "title")
	e.title:SetPoint("TOPLEFT", e.icon, "TOPRIGHT", 12, -1)
	e.status = UI.Text(e, 13, "textMuted")
	e.status:SetPoint("TOPLEFT", e.title, "BOTTOMLEFT", 0, -4)
	e.status:SetWidth(W - 2 * PAD - 60)
	e.status:SetWordWrap(false)
	e:SetScript("OnEnter", function(self)
		self.hover:Show()
	end)
	e:SetScript("OnLeave", function(self)
		self.hover:Hide()
	end)
	e:SetScript("OnClick", function(self)
		view, confirm, message = self.view, nil, nil
		MENU.Refresh()
	end)
	entries[i] = e
	return e
end

local function CreateRow(i)
	local r = CreateFrame("Button", nil, panel.list)
	r:SetSize(W - 2 * PAD, ROW_H - 4)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r:RegisterForClicks("LeftButtonUp")
	r.hover = Tex(r, "BACKGROUND")
	r.hover:SetAllPoints()
	r.hover:SetColorTexture(UI.RGBA("hover"))
	r.hover:Hide()
	r.iconFrame = CreateFrame("Frame", nil, r)
	r.iconFrame:SetSize(ICON + 2, ICON + 2)
	r.iconFrame:SetPoint("LEFT", 4, 0)
	UI.Border(r.iconFrame, "frame", 0.8)
	r.icon = Tex(r.iconFrame, "ARTWORK")
	r.icon:SetPoint("TOPLEFT", 1, -1)
	r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.count = UI.Text(r.iconFrame, 11, "text", "number")
	r.count:SetPoint("BOTTOMRIGHT", -2, 2)
	r.name = UI.Text(r, 14, "text")
	r.name:SetPoint("TOPLEFT", r.iconFrame, "TOPRIGHT", 10, -1)
	r.name:SetWidth(W - 2 * PAD - ICON - 70)
	r.name:SetWordWrap(false)
	r.right = UI.Text(r, 13, "heading", "number")
	r.right:SetPoint("TOPRIGHT", -6, -3)
	r.detail = UI.Text(r, 12, "textMuted")
	r.detail:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
	r.detail:SetWidth(W - 2 * PAD - ICON - 24)
	r.detail:SetWordWrap(false)
	r:SetScript("OnEnter", function(self)
		self.hover:Show()
		if view == "enchant" then
			Attach(self)
		end
	end)
	r:SetScript("OnLeave", function(self)
		if not (secure and secure:IsShown() and secure.row == self and secure:IsMouseOver()) then
			self.hover:Hide()
		end
	end)
	r:SetScript("OnClick", function(self)
		local item = self.item
		if not item then
			return
		end
		if IsModifiedClick("CHATLINK") and item.link then
			UI.InsertLink(item.link)
		elseif view == "equip" then
			Equip(item)
		elseif view == "gems" then
			SocketAsked(item)
		end
	end)
	rows[i] = r
	return r
end

local function CreateChip(i)
	local c = CreateFrame("Button", nil, panel)
	c:SetSize(30, 30)
	c.gem = Tex(c, "ARTWORK")
	c.gem:SetSize(22, 22)
	c.gem:SetPoint("CENTER")
	UI.CircleMask(c.gem, c)
	c.ring = Tex(c, "OVERLAY", ns.Theme.MEDIA .. "Showcase\\Ring")
	c.ring:SetSize(28, 28)
	c.ring:SetPoint("CENTER")
	c:SetScript("OnClick", function(self)
		socketPick, confirm = self.index, nil
		MENU.Refresh()
	end)
	c.index = i
	chips[i] = c
	return c
end

local function CreatePanel(parent)
	panel = CreateFrame("Frame", nil, parent)
	panel:SetFrameStrata("FULLSCREEN_DIALOG") -- above the scene (the letterbox is FULLSCREEN)
	panel:SetWidth(W)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:Hide()
	UI.Panel(panel)
	UI.Border(panel, "frame", 0.5)

	panel.close = UI.Button(panel, 22, "x")
	panel.close:SetHeight(22)
	panel.close:SetPoint("TOPRIGHT", -8, -8)
	panel.close:SetFrameLevel(panel:GetFrameLevel() + 5)
	panel.close:SetScript("OnClick", function()
		MENU.Close()
	end)

	panel.back = UI.Button(panel, 26, "<")
	panel.back:SetHeight(22)
	panel.back:SetPoint("TOPLEFT", PAD, -10)
	panel.back:SetScript("OnClick", Back)
	panel.title = UI.Text(panel, 16, "heading", "title")
	panel.title:SetPoint("LEFT", panel.back, "RIGHT", 10, 0)

	panel.list = CreateFrame("Frame", nil, panel)
	panel.list:SetWidth(W - 2 * PAD)

	panel.empty = UI.Text(panel, 14, "textMuted")
	panel.empty:SetText("Nothing in your bags fits here")
	panel.more = UI.Text(panel, 12, "textFaint")
	panel.socketLabel = UI.Text(panel, 12, "textMuted")
	panel.note = UI.Text(panel, 13, "textMuted")
	panel.note:SetWidth(W - 2 * PAD)
	panel.note:SetWordWrap(true)

	panel.confirm = CreateFrame("Frame", nil, panel)
	panel.confirm:SetSize(W - 2 * PAD, 74)
	local cbg = Tex(panel.confirm, "BACKGROUND")
	cbg:SetAllPoints()
	cbg:SetColorTexture(UI.RGBA("warning", 0.08))
	UI.Border(panel.confirm, "warning", 0.4)
	panel.confirm.text = UI.Text(panel.confirm, 13, "text")
	panel.confirm.text:SetPoint("TOPLEFT", 10, -9)
	panel.confirm.text:SetWidth(W - 2 * PAD - 20)
	panel.confirm.text:SetWordWrap(true)
	panel.confirm.yes = UI.Button(panel.confirm, 90, "Yes")
	panel.confirm.yes:SetPoint("BOTTOMLEFT", 10, 9)
	panel.confirm.no = UI.Button(panel.confirm, 90, CANCEL or "Cancel")
	panel.confirm.no:SetPoint("LEFT", panel.confirm.yes, "RIGHT", 8, 0)
	panel.confirm.yes:SetScript("OnClick", function()
		local c = confirm
		confirm = nil
		if c and c.accept then
			c.accept()
		end
		MENU.Refresh()
	end)
	panel.confirm.no:SetScript("OnClick", function()
		local c = confirm
		confirm = nil
		if c and c.cancel then
			c.cancel()
		end
		MENU.Refresh()
	end)
end

-- Views --------------------------------------------------------------------------------------------------------------

local function HideViews()
	for _, e in ipairs(entries) do
		e:Hide()
	end
	for _, r in ipairs(rows) do
		r:Hide()
		r.item = nil
	end
	for _, c in ipairs(chips) do
		c:Hide()
	end
	panel.back:Hide()
	panel.title:Hide()
	panel.list:Hide()
	panel.empty:Hide()
	panel.more:Hide()
	panel.socketLabel:Hide()
	panel.note:Hide()
	panel.confirm:Hide()
	Detach()
end

local function EnchantState(w)
	local hints = w.hints or {}
	return hints.missing, hints.enchant
end

local function ShowRoot()
	local w = owner
	local equipCount = #EquipCandidates(w.slot)
	local missing, current = EnchantState(w)
	local enchants = #EnchantCandidates(w)
	local desc = w.desc or {}
	local sockets = desc.sockets or 0
	local list = {
		{ view = "equip", title = "Equipment", icon = select(2, GetInventorySlotInfo(ns.CHARSHOW_SLOT_NAMES[w.slot])),
			status = { ns.CharShow_EquipStatus(equipCount, SlotName(w)) } },
		{ view = "enchant", title = "Enchants", icon = ENCHANTS_ICON,
			status = { ns.CharShow_EnchantStatus(missing, current, enchants) } },
		{ view = "gems", title = "Gems", icon = GEMS_ICON,
			status = { ns.CharShow_GemStatus(sockets, math.max(sockets - (desc.gems or 0), 0)) } },
	}
	for i, def in ipairs(list) do
		local e = entries[i] or CreateEntry(i)
		e.view = def.view
		e.icon:SetTexture(def.icon)
		e.title:SetText(def.title)
		e.status:SetText(def.status[1])
		e.status:SetTextColor(UI.RGBA(def.status[2]))
		e:Show()
	end
	return PAD + #list * ENTRY_H
end

-- The gem view's socket chips: current gem or an empty ring; the picked one has the accent ring.
local function ShowChips(y)
	local desc = owner.desc or {}
	local gems = desc.gemSlots or {}
	local n = desc.sockets or 0
	if not socketPick or socketPick > n then
		socketPick = ns.CharShow_PickSocket(n, gems)
	end
	for i = 1, n do
		local c = chips[i] or CreateChip(i)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", PAD + (i - 1) * 36, y)
		local id = gems[i]
		c.gem:SetShown(id ~= nil)
		if id then
			c.gem:SetTexture(C_Item.GetItemIconByID(id))
		end
		c.ring:SetVertexColor(UI.RGBA(i == socketPick and "accent" or (id and "frame" or "danger"), 1))
		c:Show()
	end
	if n > 0 then
		local label = panel.socketLabel
		label:ClearAllPoints()
		label:SetPoint("LEFT", chips[n], "RIGHT", 10, 0)
		label:SetText(("Socket %d"):format(socketPick or 1))
		label:Show()
	end
	return n > 0 and y - 40 or y
end

local function ShowList()
	panel.back:Show()
	local titles = { equip = "Equipment", enchant = "Enchants", gems = "Gems" }
	panel.title:SetText(titles[view])
	panel.title:Show()
	local y = -HEAD_H
	local items
	if view == "equip" then
		items = EquipCandidates(owner.slot)
	elseif view == "enchant" then
		items = EnchantCandidates(owner)
	else
		local sockets = owner.desc and owner.desc.sockets or 0
		if sockets == 0 then
			items = {}
		else
			y = ShowChips(y)
			items = GemCandidates()
		end
	end
	if #items == 0 then
		panel.empty:ClearAllPoints()
		panel.empty:SetPoint("TOP", panel, "TOP", 0, y - 24)
		panel.empty:SetText(view == "gems" and (owner.desc and (owner.desc.sockets or 0) == 0) and "No sockets"
			or "Nothing in your bags fits here")
		panel.empty:Show()
		return -y + 64
	end
	panel.list:ClearAllPoints()
	panel.list:SetPoint("TOPLEFT", PAD, y)
	local shown = math.min(#items, MAX_ROWS)
	panel.list:SetHeight(shown * ROW_H)
	panel.list:Show()
	for i = 1, shown do
		local item = items[i]
		local r = rows[i] or CreateRow(i)
		r.item = item
		r.icon:SetTexture(item.icon)
		r.name:SetText(item.link and C_Item.GetItemNameByID(item.link) or C_Item.GetItemNameByID(item.itemID) or "")
		r.name:SetTextColor(UI.RGBA(QualityColor(item.quality)))
		r.count:SetText(item.count and item.count > 1 and item.count or "")
		r.right:SetText(view == "equip" and item.ilvl or "")
		if view == "equip" then
			r.detail:SetText(item.headline or "")
			r.detail:SetTextColor(UI.RGBA(item.role or "textMuted"))
		elseif view == "gems" then
			r.detail:SetText(item.headline and (item.headline .. "  ·  " .. (item.detail or "")) or item.detail or "")
			r.detail:SetTextColor(UI.RGBA(item.role or "textMuted"))
		else
			local detail = item.detail or ""
			if item.kind == "temporary" then
				detail = "Temporary · " .. detail
			end
			r.detail:SetText(detail)
			r.detail:SetTextColor(UI.RGBA("textMuted"))
		end
		r:Show()
	end
	y = y - shown * ROW_H
	if #items > shown then
		panel.more:ClearAllPoints()
		panel.more:SetPoint("TOPLEFT", PAD, y - 2)
		panel.more:SetText(("and %d more in your bags"):format(#items - shown))
		panel.more:Show()
		y = y - 20
	end
	return -y + 8
end

-- Where the panel goes: beside the slot, like the card.
local function Place(w)
	panel:SetScale(w:GetParent():GetScale())
	panel:ClearAllPoints()
	if w.side == "LEFT" then
		panel:SetPoint("TOPLEFT", w, "TOPLEFT", w.cardX or 0, 0)
	else
		panel:SetPoint("TOPLEFT", w, "TOPRIGHT", 12, 0)
	end
end

function MENU.Refresh()
	if not (panel and owner and panel:IsShown()) then
		return
	end
	-- Not under a press on the enchant button: rebuilding hides it, and the click would be lost.
	if secure and secure:IsShown() and secure:IsMouseOver() then
		return
	end
	HideViews()
	local height = view == "root" and ShowRoot() or ShowList()
	if message then
		panel.note:ClearAllPoints()
		panel.note:SetPoint("TOPLEFT", PAD, -height)
		panel.note:SetText(message.text)
		panel.note:SetTextColor(UI.RGBA(message.role))
		panel.note:Show()
		height = height + math.ceil(panel.note:GetStringHeight()) + 8
	end
	if confirm then
		panel.confirm.text:SetText(confirm.text)
		panel.confirm.yes.label:SetText(confirm.button or "Yes")
		panel.confirm:ClearAllPoints()
		panel.confirm:SetPoint("TOPLEFT", PAD, -height)
		panel.confirm:Show()
		height = height + 74 + 8
	end
	panel:SetHeight(height + PAD - 8)
end

-- Opening ------------------------------------------------------------------------------------------------------------

local CONFIRM_EVENTS = { "EQUIP_BIND_CONFIRM", "EQUIP_BIND_REFUNDABLE_CONFIRM", "EQUIP_BIND_TRADEABLE_CONFIRM",
	"REPLACE_ENCHANT", "REPLACE_TRADESKILL_ENCHANT", "BIND_ENCHANT", "ACTION_WILL_BIND_ITEM",
	"SOCKET_INFO_BIND_CONFIRM", "SOCKET_INFO_REFUNDABLE_CONFIRM", "SOCKET_INFO_SUCCESS", "SOCKET_INFO_FAILURE",
	"BAG_UPDATE_DELAYED", "GLOBAL_MOUSE_DOWN" }

function MENU.Create(parent)
	CreatePanel(parent)
end

function MENU.Open(w)
	if not panel or InCombatLockdown() then
		return
	end
	if owner ~= w then
		view, socketPick = "root", nil
	end
	owner, confirm, message = w, nil, nil
	Place(w)
	panel:Show()
	for _, event in ipairs(CONFIRM_EVENTS) do
		events:TryWatch(OWNER, event)
	end
	MENU.Refresh()
end

function MENU.Close()
	if confirm and confirm.cancel then
		confirm.cancel()
	end
	owner, confirm, message, socketJob = nil, nil, nil, nil
	Detach()
	if panel then
		panel:Hide()
	end
	events:UnwatchAll(OWNER)
	if C_ItemSocketInfo.GetNumSockets() > 0 then
		C_ItemSocketInfo.CloseSocketInfo()
	end
end

function MENU.Toggle(w)
	if owner == w and panel:IsShown() then
		MENU.Close()
	else
		MENU.Open(w)
	end
end

function MENU.IsOpen()
	return panel ~= nil and panel:IsShown()
end

function MENU.IsMouseOver()
	return MENU.IsOpen() and (panel:IsMouseOver() or (secure ~= nil and secure:IsShown() and secure:IsMouseOver()))
end

-- Events -------------------------------------------------------------------------------------------------------------

-- Blizzard's own popup for the same question also opens, on the hidden UIParent. It's left alone (StaticPopup_Hide
-- from addon code taints the popup system); the game hides it itself once answered (cursor emptied, cast changed),
-- and if one is left when the UI comes back its buttons do nothing anymore.
local function Ask(text, button, accept, cancel)
	confirm = { text = text, button = button, accept = accept, cancel = cancel }
	MENU.Refresh()
end

for _, event in ipairs({ "EQUIP_BIND_CONFIRM", "EQUIP_BIND_REFUNDABLE_CONFIRM", "EQUIP_BIND_TRADEABLE_CONFIRM" }) do
	events:On(OWNER, event, function(_, slot)
		Ask("Equipping it binds it to you.", "Equip", function()
			EquipPendingItem(slot)
			C_Timer.After(0, MENU.Close)
		end, function()
			CancelPendingEquip(slot)
		end)
	end)
end

local function StopTargeting()
	if SpellIsTargeting() then
		SpellStopTargeting()
	end
	ClearCursor()
end

events:On(OWNER, "REPLACE_ENCHANT", function(_, existing, replacement)
	Ask(("Replace %s with %s?"):format(existing or "the enchant", replacement or "this one"), "Replace", function()
		C_Item.ReplaceEnchant()
	end, StopTargeting)
end)
events:On(OWNER, "REPLACE_TRADESKILL_ENCHANT", function(_, existing, replacement)
	Ask(("Replace %s with %s?"):format(existing or "the enchant", replacement or "this one"), "Replace", function()
		C_Item.ReplaceTradeskillEnchant()
	end, StopTargeting)
end)
events:On(OWNER, "BIND_ENCHANT", function()
	Ask("Enchanting it binds it to you.", "Enchant", function()
		C_Item.BindEnchant()
	end, StopTargeting)
end)
events:On(OWNER, "ACTION_WILL_BIND_ITEM", function()
	Ask("This binds the item to you.", "Go on", function()
		C_Item.ActionBindsItem()
	end, StopTargeting)
end)

for _, event in ipairs({ "SOCKET_INFO_BIND_CONFIRM", "SOCKET_INFO_REFUNDABLE_CONFIRM" }) do
	events:On(OWNER, event, function()
		Ask("Socketing it binds it to you.", "Socket", function()
			C_ItemSocketInfo.CompleteSocketing()
		end, function()
			C_ItemSocketInfo.CloseSocketInfo()
		end)
	end)
end

events:On(OWNER, "SOCKET_INFO_UPDATE", function()
	if socketJob then
		FinishSocket()
	end
end)

events:On(OWNER, "SOCKET_INFO_SUCCESS", function()
	events:Unwatch(OWNER, "SOCKET_INFO_UPDATE")
	C_ItemSocketInfo.CloseSocketInfo()
	socketPick = nil
end)

events:On(OWNER, "SOCKET_INFO_FAILURE", function()
	events:Unwatch(OWNER, "SOCKET_INFO_UPDATE")
	socketJob = nil
	C_ItemSocketInfo.CloseSocketInfo()
	Say("The game refused that gem (a unique gem you already wear?).", "danger")
	MENU.Refresh()
end)

events:On(OWNER, "BAG_UPDATE_DELAYED", function()
	MENU.Refresh()
end)

-- A press anywhere but the menu, its slot or the enchant button closes it.
events:On(OWNER, "GLOBAL_MOUSE_DOWN", function()
	if owner and not (MENU.IsMouseOver() or owner:IsMouseOver()) then
		MENU.Close()
	end
end)
