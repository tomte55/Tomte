local addonName, ns = ...

-- Delves page in the Tomte window: keys, the Delver's Journey with its bar, the Gilded Stash, today's delves
-- (bountiful first, click to track), the Great Vault's World track with the tier advice and ladder, and the companion. It renders the readers' cache
-- (Read.lua) and the scan's (Scan.lua); of its own it reads only display bits (the key currency's icon, atlas
-- checks, Blizzard's quality names).

local UI = ns.UI
local Kit = ns.HomeKit
local PAD = 8
local SLOT_W, SLOT_H, SLOT_GAP = 96, 40, 10
local PORTRAIT = 48
local JOURNEY_BAR_GAP = 11 -- the season bar's height plus the space below it

ns.DELVES_ICON = "Interface\\Icons\\INV_Misc_Key_03"

local page, scroll, c -- c: the scroll content
local rows = {}

local QUALITY = {} -- Enum.CurioRarity -> item quality (Blizzard_DelvesCompanionConfiguration's own mapping)

local function RarityText(rarity)
	if not next(QUALITY) and Enum.CurioRarity then
		QUALITY[Enum.CurioRarity.Common] = 1
		QUALITY[Enum.CurioRarity.Uncommon] = 2
		QUALITY[Enum.CurioRarity.Rare] = 3
		QUALITY[Enum.CurioRarity.Epic] = 4
	end
	local q = rarity and QUALITY[rarity]
	return q and _G["ITEM_QUALITY" .. q .. "_DESC"] or nil
end

-- The key currency's own icon (for rows that take a texture).
function ns.Delves_KeyIcon()
	local def = ns.Content_Get(ns.ContentExpansion(), "delves")
	local info = def and C_CurrencyInfo.GetCurrencyInfo(def.keyCurrency)
	return info and info.iconFileID or ns.DELVES_ICON
end

function ns.Delves_JourneyText(j)
	if not j then
		return nil
	end
	if j.max and j.level and j.level >= j.max then
		return ("%s: renown %d (max)"):format(j.name, j.level)
	end
	return ("%s: renown %d (%d/%d)"):format(j.name, j.level or 0, j.earned or 0, j.threshold or 0)
end

local function Text(size, role)
	local fs = UI.Text(c, size, role)
	fs:SetWordWrap(true)
	fs:SetJustifyH("LEFT")
	return fs
end

local function Build()
	scroll = UI.Scroll(page)
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -10, 0)
	c = scroll.content
	scroll.onWidthChanged = function()
		ns.DelvesPage_Refresh()
	end
	c.keys = Text(14, "text")
	c.combine = Text(12, "success")
	c.journey = Text(12, "textMuted")
	c.journeyBar = UI.Bar(c, 5)
	c.stash = Text(12, "textMuted")
	c.today = Kit.Heading(c)
	c.empty = Text(13, "textMuted")
	c.vaultHead = Kit.Heading(c)
	c.slots, c.slotTiers = {}, {}
	for i = 1, 3 do
		c.slots[i] = ns.WeeklySlot_Create(c, SLOT_W, SLOT_H, 13)
		c.slotTiers[i] = UI.Text(c, 11, "textMuted")
		c.slotTiers[i]:SetJustifyH("CENTER")
		c.slotTiers[i]:SetWidth(SLOT_W)
	end
	c.advice = Text(13, "accent")
	c.ladder = Text(12, "textMuted")
	c.compHead = Kit.Heading(c)
	c.portrait = c:CreateTexture(nil, "ARTWORK")
	c.portrait:SetSize(PORTRAIT, PORTRAIT)
	c.compName = Text(14, "text")
	c.xp = UI.Bar(c, 5)
	c.role = Text(12, "textMuted")
	c.curios = {}
	for i = 1, 2 do
		local row = Kit.Row(c)
		c.curios[i] = row
	end
	c.hint = Text(12, "warning")
	c.compNone = Text(13, "textMuted")
end

-- Places fs at y (full width) and returns the y below it.
local function Place(fs, y, text, gap)
	if not text or text == "" then
		fs:Hide()
		return y
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", PAD, -y)
	fs:SetPoint("RIGHT", -PAD, 0)
	fs:SetText(text)
	fs:Show()
	return y + fs:GetStringHeight() + (gap or 4)
end

local function PlaceFrame(frame, y, height)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", PAD, -y)
	frame:SetPoint("RIGHT", -PAD, 0)
	frame:Show()
	return y + height
end

local function RenderToday(y, list, minLevel)
	local bountiful = 0
	for _, e in ipairs(list) do
		if e.bountiful then
			bountiful = bountiful + 1
		end
	end
	c.today:Set("Today", #list > 0 and (bountiful .. " bountiful") or nil)
	y = PlaceFrame(c.today, y, 30) + 4
	local empty
	if minLevel then
		empty = ("Delves open at level %d."):format(minLevel)
	elseif not ns.Content_Get(ns.ContentExpansion(), "delves") then
		empty = ("Tomte has no delves for %s."):format(ns.ExpansionName(ns.ContentExpansion()))
	elseif #list == 0 then
		empty = ("No delves found for %s. Open the world map once if this looks wrong."):format(
			ns.ExpansionName(ns.ContentExpansion()))
	elseif bountiful == 0 then
		empty = "No bountiful delves found. Open the map once if this looks wrong."
	end
	y = Place(c.empty, y, empty, 8)
	for i, e in ipairs(list) do
		local row = Kit.PoolRow(rows, i, c)
		row:Set(ns.DELVES_ICON, e.name, e.bountiful and "accent" or "text", ns.DelvesScan_ZoneName(e.map))
		local atlas = e.bountiful and ns.DELVES_BOUNTIFUL_ATLAS or e.atlas
		if atlas and C_Texture.GetAtlasInfo(atlas) then
			row.icon:SetAtlas(atlas)
		else
			row.icon:SetTexture(ns.DELVES_ICON)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		row.onClick = function()
			ns.Delves_Track(e)
		end
		row.onEnter = function(self)
			ns.Delves_Tooltip(self, e)
		end
		y = PlaceFrame(row, y, Kit.ROW_H)
	end
	Kit.HideFrom(rows, #list + 1)
	return y + 14
end

local function RenderVault(y, vault)
	c.vaultHead:Set("Great Vault: World", vault and ("Tier %d tops it"):format(vault.top) or nil)
	y = PlaceFrame(c.vaultHead, y, 30) + 6
	local slots = vault and vault.slots or {}
	local nextLocked
	for i, s in ipairs(slots) do
		if not nextLocked and (s.progress or 0) < s.threshold then
			nextLocked = i
		end
	end
	for i = 1, 3 do
		local slot, tier = c.slots[i], c.slotTiers[i]
		local s = slots[i]
		if s then
			ns.WeeklySlot_Set(slot, { progress = s.progress or 0, threshold = s.threshold }, i == nextLocked, true)
			slot:ClearAllPoints()
			slot:SetPoint("TOPLEFT", PAD + (i - 1) * (SLOT_W + SLOT_GAP), -y)
			slot:Show()
			local row = vault.plan.rows[i]
			tier:ClearAllPoints()
			tier:SetPoint("TOP", slot, "BOTTOM", 0, -3)
			tier:SetText(row and row.unlocked and row.tier and ("Tier " .. row.tier) or "-")
			tier:Show()
		else
			slot:Hide()
			tier:Hide()
		end
	end
	if #slots > 0 then
		y = y + SLOT_H + 20
	end
	local plan = vault and vault.plan
	if plan and plan.text then
		UI.SetTextRole(c.advice, plan.advice and "accent" or "success")
	end
	local advice = plan and plan.text
	if not vault then
		advice = "Reading the Great Vault..."
	end
	y = Place(c.advice, y, advice, 4)
	y = Place(c.ladder, y, vault and ns.Delves_LadderText(vault.ladder), 4)
	return y + 14
end

local function RenderCompanion(y, comp)
	c.compHead:Set("Companion", comp and comp.level and ("level %d/%d"):format(comp.level, comp.maxLevel or comp.level) or nil)
	y = PlaceFrame(c.compHead, y, 30) + 6
	local show = comp ~= nil
	c.portrait:SetShown(show)
	c.compName:SetShown(show)
	c.xp:SetShown(show)
	c.role:SetShown(show)
	for _, row in ipairs(c.curios) do
		row:Hide()
	end
	if not comp then
		c.hint:Hide()
		return Place(c.compNone, y, "Unlocks with your first delve.", 4) + 10
	end
	c.compNone:Hide()
	local textX = PAD
	if comp.displayID then
		SetPortraitTextureFromCreatureDisplayID(c.portrait, comp.displayID)
		c.portrait:ClearAllPoints()
		c.portrait:SetPoint("TOPLEFT", PAD, -y)
		textX = PAD + PORTRAIT + 10
	else
		c.portrait:Hide()
	end
	local top = y
	c.compName:ClearAllPoints()
	c.compName:SetPoint("TOPLEFT", textX, -y)
	c.compName:SetPoint("RIGHT", -PAD, 0)
	c.compName:SetText(("%s · level %d/%d"):format(comp.name, comp.level, comp.maxLevel or comp.level))
	y = y + c.compName:GetStringHeight() + 6
	c.xp:ClearAllPoints()
	c.xp:SetPoint("TOPLEFT", textX, -y)
	c.xp:SetPoint("RIGHT", -PAD, 0)
	c.xp:SetValue(comp.xpMax and comp.xpMax > 0 and comp.xp / comp.xpMax or 1)
	y = y + 11
	c.role:ClearAllPoints()
	c.role:SetPoint("TOPLEFT", textX, -y)
	c.role:SetPoint("RIGHT", -PAD, 0)
	c.role:SetText(comp.roleName or (comp.companionID and "" or "Role and curios show for this season's companion only."))
	y = y + c.role:GetStringHeight() + 6
	if comp.displayID then
		y = math.max(y, top + PORTRAIT + 6)
	end
	for i, curio in ipairs({ comp.combat or false, comp.utility or false }) do
		if curio then
			local row = c.curios[i]
			row:Set(curio.icon, curio.name, "text", RarityText(curio.rarity))
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row.onEnter = function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if curio.link then
					GameTooltip:SetHyperlink(curio.link)
				else
					GameTooltip:SetSpellByID(curio.spellID)
				end
				GameTooltip:Show()
			end
			y = PlaceFrame(row, y, Kit.ROW_H)
		end
	end
	y = Place(c.hint, y + 4, ns.DelvesRead_RoleHint(), 4)
	return y + 10
end

-- The Gilded Stash line; a count kept from earlier this week (or a widget the game marks as not current) says so.
local function StashText(stash)
	local text = ns.Delves_StashText(stash, stash and stash.name)
	if not text then
		return nil
	end
	UI.SetTextRole(c.stash, stash.n >= stash.of and "success" or "textMuted")
	if stash.old then
		text = text .. " · as last seen in the open world"
	end
	return text
end

local function Render()
	if not (page and page:IsVisible()) then
		return
	end
	local s = ns.DelvesRead_State()
	local minLevel = ns.DelvesScan_MinLevel()
	local y = PAD
	y = Place(c.keys, y, s.keyLine or (minLevel and "" or "Reading your keys..."), 4)
	local perKey = s.keys and s.keys.perKey or 100
	y = Place(c.combine, y, s.canCombine and ("Combine %d shards into a key"):format(perKey) or nil, 4)
	local journey = s.companion and s.companion.journey
	y = Place(c.journey, y, ns.Delves_JourneyText(journey), 4)
	if journey then
		c.journeyBar:ClearAllPoints()
		c.journeyBar:SetPoint("TOPLEFT", PAD, -y)
		c.journeyBar:SetPoint("RIGHT", -PAD, 0)
		c.journeyBar:Show()
		c.journeyBar:SetValue(ns.Delves_JourneyFraction(journey))
		y = y + JOURNEY_BAR_GAP
	else
		c.journeyBar:Hide()
	end
	y = Place(c.stash, y, StashText(s.stash), 4)
	y = RenderToday(y + 8, ns.DelvesScan_List(), minLevel)
	if not minLevel then
		y = RenderVault(y, s.vault)
		y = RenderCompanion(y, s.companion)
	else
		c.vaultHead:Hide()
		c.compHead:Hide()
		c.portrait:Hide()
		c.compName:Hide()
		c.xp:Hide()
		c.role:Hide()
		c.hint:Hide()
		c.compNone:Hide()
		c.advice:Hide()
		c.ladder:Hide()
		for i = 1, 3 do
			c.slots[i]:Hide()
			c.slotTiers[i]:Hide()
		end
		for _, row in ipairs(c.curios) do
			row:Hide()
		end
	end
	scroll:SetContentHeight(y + PAD)
end

function ns.DelvesPage_Refresh()
	Render()
end

ns.DelvesPage = {
	title = "Delves",
	Create = function(frame)
		page = frame
		Build()
	end,
	Refresh = function()
		ns.DelvesRead_Dirty()
		Render()
	end,
}
