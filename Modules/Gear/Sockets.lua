local addonName, ns = ...

-- Gear Check's gem socket helper: while the socketing window is open, a strip under it with the gems in your bags
-- that fit its sockets, the one Gear Check recommends for your spec marked. Clicking a gem picks it up and puts it
-- in the first empty socket (the player still presses Apply). Rules in HelperData.lua; gem values from the same
-- weights as the tooltips (Context.lua); started and stopped by Gear.lua.

local SIZE = 34 -- gem button size
local GAP = 6
local PAD = 10
local PER_ROW = 8
local HEADER_H = 18
local MARK_H = 12 -- the "BEST" label under the recommended gem
local ROW_H = SIZE + MARK_H + GAP
-- The backpack, the four bags and the reagent bag (some gems stack there).
local BAGS = { 0, 1, 2, 3, 4, Enum.BagIndex.ReagentBag }
local GEM_CLASS = Enum.ItemClass.Gem
local RELIC_SUBCLASS = Enum.ItemGemSubclass.Artifactrelic
local UI = ns.UI

local events = ns.Gear_Events
local Secret = ns.IsSecret
local TakesGems = ns.GearHelpers_TakesGems
local IsGem = ns.GearHelpers_IsGem
local EmptySocket = ns.GearHelpers_EmptySocket
local RankGems = ns.GearHelpers_RankGems

local db, strip
local buttons = {}

local function Wanted()
	return ns.gearModule.active and db and db.gemHelper
end

-- The item being socketed: { { type, filled } } per socket.
local function ReadSockets()
	local sockets = {}
	for i = 1, C_ItemSocketInfo.GetNumSockets() or 0 do
		sockets[i] = {
			type = C_ItemSocketInfo.GetSocketTypes(i),
			filled = C_ItemSocketInfo.GetNewSocketInfo(i) ~= nil or C_ItemSocketInfo.GetExistingSocketInfo(i) ~= nil,
		}
	end
	return sockets
end

-- The gems in the bags, one entry per item ID at its first bag slot: { itemID, name, icon, count, stats, diamond,
-- bag, slot }. Gems still loading are left out until the next update.
local function BagGems(diamondIDs)
	local byID, list = {}, {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not Secret(id) then
				local _, _, _, _, icon, classID, subclassID = C_Item.GetItemInfoInstant(id)
				if IsGem(classID, subclassID, GEM_CLASS, RELIC_SUBCLASS) then
					local entry = byID[id]
					if entry then
						entry.count = entry.count + (info.stackCount or 1)
					else
						entry = { itemID = id, name = C_Item.GetItemNameByID(id), icon = icon,
							count = info.stackCount or 1, stats = ns.GearItems_GemStats(id),
							diamond = diamondIDs[id] or nil, bag = bag, slot = slot, locked = info.isLocked }
						byID[id] = entry
						list[#list + 1] = entry
					end
				end
			end
		end
	end
	return list
end

-- Buttons -----------------------------------------------------------------------------------------------------------

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetBagItem(self.gem.bag, self.gem.slot)
	if self.gem.best then
		UI.TipLine("Gear Check: best gem for your spec", "accent")
	elseif self.gem.diamond then
		UI.TipLine("Gear Check: your one unique gem (sim which)", "textMuted")
	end
	UI.TipLine("Click to put it in the first empty socket.", "textMuted")
	GameTooltip:Show()
end

local function OnClick(self)
	local gem = self.gem
	ClearCursor()
	C_Container.PickupContainerItem(gem.bag, gem.slot)
	local target = EmptySocket(ReadSockets())
	if target and CursorHasItem() then
		C_ItemSocketInfo.ClickSocketButton(target)
	end
end

local function Button(i)
	local b = buttons[i]
	if b then
		return b
	end
	b = CreateFrame("Button", nil, strip)
	b:SetSize(SIZE, SIZE)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	UI.Border(b, "frame", 0.6)
	b.count = UI.Text(b, 11, "text", "number")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.mark = UI.Text(b, 9, "accent", "label")
	b.mark:SetPoint("TOP", b, "BOTTOM", 0, -2)
	b.mark:SetText("BEST")
	b:SetScript("OnEnter", OnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", OnClick)
	buttons[i] = b
	return b
end

-- Strip -------------------------------------------------------------------------------------------------------------

local function Build()
	strip = CreateFrame("Frame", nil, ItemSocketingFrame)
	strip:SetPoint("TOPLEFT", ItemSocketingFrame, "BOTTOMLEFT", 0, -4)
	strip:SetPoint("TOPRIGHT", ItemSocketingFrame, "BOTTOMRIGHT", 0, -4)
	strip:SetHeight(60)
	UI.Panel(strip, { alpha = 0.95 })
	strip.title = UI.Text(strip, 10, "textMuted", "label")
	strip.title:SetPoint("TOPLEFT", PAD, -PAD)
	strip.title:SetText(ns.Spaced("Gems in your bags"))
	strip.empty = UI.Text(strip, 12, "textFaint")
	strip.empty:SetPoint("TOPLEFT", PAD, -PAD - HEADER_H)
	strip.empty:SetText("No gems in your bags fit.")
end

local function Hide()
	if strip then
		strip:Hide()
	end
end

local function Refresh()
	if not (Wanted() and ItemSocketingFrame and ItemSocketingFrame:IsShown()) then
		Hide()
		return
	end
	local sockets = ReadSockets()
	local types = {}
	for i, socket in ipairs(sockets) do
		types[i] = socket.type
	end
	if not TakesGems(types) then
		Hide()
		return
	end
	if not strip then
		Build()
	end
	local ctx = ns.Gear_Context()
	local scales = ctx and ctx.scales or ns.Gear_ScalesForLevel()
	local score = ctx and not ctx.noWeights and function(stats)
		return ns.Gear_StatsScore(stats, ctx.weights, ctx.primary)
	end or nil
	local gems = RankGems(BagGems(scales.diamondIDs or {}), score)
	local hasBest = false
	for i, gem in ipairs(gems) do
		local b = Button(i)
		b.gem = gem
		b:ClearAllPoints()
		local row, col = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
		b:SetPoint("TOPLEFT", strip, "TOPLEFT", PAD + col * (SIZE + GAP), -PAD - HEADER_H - row * ROW_H)
		b.icon:SetTexture(gem.icon)
		b.icon:SetDesaturated(gem.locked and true or false)
		b.count:SetText(gem.count > 1 and gem.count or "")
		b.mark:SetShown(gem.best == true)
		UI.SetBorderColor(b, gem.best and "accent" or "frame", gem.best and 1 or 0.6)
		hasBest = hasBest or gem.best == true
		b:Show()
	end
	for i = #gems + 1, #buttons do
		buttons[i]:Hide()
	end
	strip.empty:SetShown(#gems == 0)
	local rows = math.max(math.ceil(#gems / PER_ROW), 1)
	local height = #gems == 0 and HEADER_H or (rows * ROW_H - GAP - (hasBest and 0 or MARK_H))
	strip:SetHeight(PAD * 2 + HEADER_H + height)
	strip:Show()
end

-- Bursts of bag and socket updates (picking up, socketing) redraw once.
local QueueRefresh = UI.Debounce(0.1, Refresh)

events:On("sockets", "SOCKET_INFO_UPDATE", function()
	QueueRefresh()
end)

events:On("sockets", "SOCKET_INFO_CLOSE", function()
	Hide()
end)

events:On("sockets", "BAG_UPDATE_DELAYED", function()
	if strip and strip:IsShown() then
		QueueRefresh()
	end
end)

function ns.GearSockets_Start(moduleDB)
	db = moduleDB
	events:Watch("sockets", "SOCKET_INFO_UPDATE")
	events:Watch("sockets", "SOCKET_INFO_CLOSE")
	events:Watch("sockets", "BAG_UPDATE_DELAYED")
	Refresh()
end

function ns.GearSockets_Stop()
	events:UnwatchAll("sockets")
	Hide()
end

-- The gemHelper setting changed.
function ns.GearSockets_Refresh()
	Refresh()
end
