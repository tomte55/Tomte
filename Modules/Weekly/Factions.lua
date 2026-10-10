local addonName, ns = ...

-- Weekly board, Factions tab: the expansion's renown factions as emblems in progress rings (sub-factions as small
-- rings beside their parent), a tooltip with the next rewards, and a detail panel for the selected faction with its
-- reward track. Read live each time it draws (renown is account-wide). Logic in FactionData.lua.

local UI = ns.UI
-- Ring looks (FactionData.lua's "gold"/"blue"/"white") as roles: maxed or paragon, renown, plain reputation.
local RING_ROLES = { gold = "heading", blue = "accent", white = "textMuted" }
local BIG, SMALL, GAP = 84, 40, 22
local DETAIL_W, DETAIL_H = 250, 260
local REWARD_H = 30
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function TipLine(text, role)
	local r, g, b = UI.Color(role)
	GameTooltip:AddLine(text, r, g, b)
end

local function AtlasExists(name)
	return C_Texture.GetAtlasInfo(name) ~= nil
end

local function Paragon(id)
	if not (C_Reputation.IsFactionParagonForCurrentPlayer and C_Reputation.IsFactionParagonForCurrentPlayer(id)) then
		return nil
	end
	local value, threshold, _, pending = C_Reputation.GetFactionParagonInfo(id)
	return value and { value = value, threshold = threshold, pending = pending == true } or nil
end

-- A sub-faction: friendship reputation (rank) or a plain one (standing). nil when it isn't known or unlocked yet.
local function SubRecord(sub, parentID)
	if sub.unlock and not C_QuestLog.IsQuestFlaggedCompletedOnAccount(sub.unlock) then
		return nil
	end
	local rec = { id = sub.id, parent = parentID, renown = false, icon = sub.icon, display = sub.display }
	local friend = C_GossipInfo.GetFriendshipReputation(sub.id)
	if friend and (friend.friendshipFactionID or 0) > 0 then
		local ranks = C_GossipInfo.GetFriendshipReputationRanks(friend.friendshipFactionID)
		rec.name = friend.name
		rec.level = ranks and ranks.currentLevel or nil
		rec.standing = friend.reaction
		rec.earned = (friend.standing or 0) - (friend.reactionThreshold or 0)
		rec.threshold = friend.nextThreshold and (friend.nextThreshold - (friend.reactionThreshold or 0)) or 0
		rec.maxed = friend.nextThreshold == nil
			or (ranks ~= nil and (ranks.maxLevel or 0) > 0 and (ranks.currentLevel or 0) >= ranks.maxLevel)
	else
		local data = C_Reputation.GetFactionDataByID(sub.id)
		if not (data and data.name and data.name ~= "") then
			return nil
		end
		rec.name = data.name
		rec.level = data.reaction
		rec.standing = _G["FACTION_STANDING_LABEL" .. (data.reaction or 0)]
		rec.earned = (data.currentStanding or 0) - (data.currentReactionThreshold or 0)
		rec.threshold = (data.nextReactionThreshold or 0) - (data.currentReactionThreshold or 0)
		rec.maxed = rec.threshold <= 0
	end
	rec.paragon = Paragon(sub.id)
	return rec
end

function ns.Weekly_ReadFactions()
	local expansion = ns.ContentExpansion()
	local hidden = C_MajorFactions.IsMajorFactionHiddenFromExpansionPage
	local subs = ns.Content_Get(expansion, "subfactions") or {}
	local recs = {}
	for _, id in ipairs(C_MajorFactions.GetMajorFactionIDs(expansion) or {}) do
		local data = C_MajorFactions.GetMajorFactionData(id)
		if data and data.isUnlocked and not (hidden and hidden(id)) then
			local levels = C_MajorFactions.GetRenownLevels(id)
			recs[#recs + 1] = {
				id = id, name = data.name, renown = true, level = data.renownLevel or 0,
				max = levels and #levels > 0 and levels[#levels].level or nil,
				earned = data.renownReputationEarned, threshold = data.renownLevelThreshold, kit = data.textureKit,
				paragon = Paragon(id),
			}
			for _, sub in ipairs(subs[id] or {}) do
				local rec = SubRecord(sub, id)
				if rec then
					recs[#recs + 1] = rec
				end
			end
		end
	end
	return recs
end

local function SetEmblem(ring, rec)
	if rec.display then
		ring:SetPortrait(rec.display)
	elseif rec.icon then
		ring:SetFile(rec.icon)
	else
		local atlas = ns.Weekly_FactionAtlas(rec.kit, AtlasExists)
		if atlas then
			ring:SetAtlas(atlas)
		else
			ring:SetFile(QUESTION)
		end
	end
	local look = ns.Weekly_FactionRing(rec)
	ring:SetColor(UI.Color(RING_ROLES[look.color] or "accent"))
	ring:SetBadge(look.badge) -- before the progress: the ring leaves room for the badge
	ring:SetProgress(look.frac)
	ring:SetGlow(look.glow)
end

local function Tooltip(owner, rec)
	local d = ns.Weekly_FactionDetail(rec)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(d.title, UI.Color("text"))
	TipLine(d.line1, "heading")
	if d.line2 ~= "" then
		TipLine(d.line2, "textMuted")
	end
	if rec.renown and rec.max and rec.level < rec.max then
		local rewards = C_MajorFactions.GetRenownRewardsForLevel(rec.id, rec.level + 1) or {}
		if #rewards > 0 then
			GameTooltip:AddLine(" ")
			TipLine("Next rewards:", "text")
			for _, r in ipairs(rewards) do
				TipLine(("|T%s:16|t %s"):format(r.icon or QUESTION, r.name or "?"), "heading")
			end
		end
	end
	if rec.renown then
		GameTooltip:AddLine(" ")
		TipLine("Click for the reward track", "success")
	end
	GameTooltip:Show()
end

function ns.WeeklyFactionsView(parent)
	local Kit = ns.HomeKit
	local view = { rings = {}, rewardRows = {} }
	view.scroll = UI.Scroll(parent)
	local c = view.scroll.content

	-- Detail panel (left).
	local detail = CreateFrame("Frame", nil, c)
	detail:SetSize(DETAIL_W, DETAIL_H)
	detail:SetPoint("TOPLEFT", 8, -8)
	UI.Surface(detail, 0.18)
	detail.ring = ns.WeeklyRing_Create(detail, 120)
	detail.ring:SetPoint("TOP", 0, -24)
	detail.ring:EnableMouse(false)
	detail.title = UI.Text(detail, 16, "text")
	detail.title:SetPoint("TOP", detail.ring, "BOTTOM", 0, -18)
	detail.title:SetWidth(DETAIL_W - 24)
	detail.title:SetJustifyH("CENTER")
	detail.line1 = UI.Text(detail, 13, "heading")
	detail.line1:SetPoint("TOP", detail.title, "BOTTOM", 0, -6)
	detail.line2 = UI.Text(detail, 12, "textMuted")
	detail.line2:SetPoint("TOP", detail.line1, "BOTTOM", 0, -4)
	view.detail = detail
	view.rewardHead = Kit.Heading(c)

	view.none = UI.Text(c, 13, "textMuted")
	view.none:SetPoint("TOPLEFT", 16, -16)
	view.none:SetText("No renown factions unlocked for this character's expansion yet.")

	-- Rings of another size wait in spare[size] for a layout that needs them again.
	local spare = {}
	local function Ring(i, size)
		local ring = view.rings[i]
		if ring and ring.size ~= size then
			ring:Hide()
			spare[ring.size] = spare[ring.size] or {}
			table.insert(spare[ring.size], ring)
			ring = nil
		end
		if not ring and spare[size] and #spare[size] > 0 then
			ring = table.remove(spare[size])
			view.rings[i] = ring
		end
		if not ring then
			ring = ns.WeeklyRing_Create(c, size)
			ring.size = size
			ring:SetScript("OnEnter", function(self)
				Tooltip(self, self.rec)
			end)
			ring:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			ring:SetScript("OnClick", function(self)
				if self.rec.renown then
					ns.weeklyDB.faction = self.rec.id
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
					ns.WeeklyBoard_Refresh()
				end
			end)
			view.rings[i] = ring
		end
		ring:Show()
		return ring
	end

	local function RewardRow(i)
		local row = view.rewardRows[i]
		if not row then
			row = CreateFrame("Frame", nil, c)
			row:SetHeight(REWARD_H)
			row.level = row:CreateFontString(nil, "OVERLAY")
			UI.SetFont(row.level, Kit.NARROW_FONT, 18)
			row.level:SetPoint("LEFT", 0, 0)
			row.level:SetWidth(36)
			row.level:SetJustifyH("RIGHT")
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(24, 24)
			row.icon:SetPoint("LEFT", 50, 0)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row.name = UI.Text(row, 13, "text")
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
			row.name:SetPoint("RIGHT", -8, 0)
			row.name:SetWordWrap(false)
			row.line = row:CreateTexture(nil, "ARTWORK")
			row.line:SetHeight(1)
			row.line:SetPoint("TOPLEFT", 0, 0)
			row.line:SetPoint("TOPRIGHT", 0, 0)
			row.line:SetColorTexture(UI.Color("rule"))
			view.rewardRows[i] = row
		end
		row:Show()
		return row
	end

	function view:Render(width)
		width = math.max(width or 0, 500)
		for _, ring in ipairs(self.rings) do
			ring:Hide()
		end
		for _, row in ipairs(self.rewardRows) do
			row:Hide()
		end
		local layout = ns.Weekly_FactionLayout(ns.Weekly_ReadFactions())
		self.none:SetShown(#layout == 0)
		self.detail:SetShown(#layout > 0)
		self.rewardHead:SetShown(#layout > 0)
		if #layout == 0 then
			self.scroll:SetContentHeight(40)
			return
		end

		-- Selected faction: the saved one if it's still here, else the first.
		local selected
		for _, cell in ipairs(layout) do
			if cell.rec.id == ns.weeklyDB.faction then
				selected = cell.rec
			end
		end
		selected = selected or layout[1].rec

		-- Emblem grid (right of the detail panel), cells flow left to right.
		local gridX, gridW = DETAIL_W + 32, width - DETAIL_W - 40
		local x, y, n = 0, 12, 0
		for _, cell in ipairs(layout) do
			local cellW = BIG + #cell.subs * (SMALL + 8) + (#cell.subs > 0 and 4 or 0)
			if x > 0 and x + cellW > gridW then
				x, y = 0, y + BIG + GAP + 8
			end
			n = n + 1
			local ring = Ring(n, BIG)
			ring.rec = cell.rec
			ring:ClearAllPoints()
			ring:SetPoint("TOPLEFT", gridX + x, -y)
			SetEmblem(ring, cell.rec)
			ring:SetSelected(cell.rec == selected)
			local sx = x + BIG + 12
			for _, sub in ipairs(cell.subs) do
				n = n + 1
				local small = Ring(n, SMALL)
				small.rec = sub
				small:ClearAllPoints()
				small:SetPoint("TOPLEFT", gridX + sx, -(y + (BIG - SMALL) / 2))
				SetEmblem(small, sub)
				small:SetSelected(false)
				sx = sx + SMALL + 8
			end
			x = x + cellW + GAP
		end
		local gridBottom = y + BIG + GAP

		-- Detail panel and reward track.
		local d = ns.Weekly_FactionDetail(selected)
		SetEmblem(self.detail.ring, selected)
		self.detail.title:SetText(d.title)
		self.detail.line1:SetText(d.line1)
		self.detail.line2:SetText(d.line2)

		local trackY = math.max(gridBottom, 20)
		self.rewardHead:ClearAllPoints()
		self.rewardHead:SetPoint("TOPLEFT", gridX, -trackY)
		self.rewardHead:SetWidth(gridW)
		self.rewardHead:Set("Reward track", selected.name)
		trackY = trackY + 38
		local track = ns.Weekly_RewardTrack(selected, C_MajorFactions.GetRenownLevels(selected.id),
			function(level)
				return C_MajorFactions.GetRenownRewardsForLevel(selected.id, level)
			end)
		local i = 0
		for _, step in ipairs(track) do
			for r, reward in ipairs(step.rewards) do
				i = i + 1
				local row = RewardRow(i)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", gridX, -trackY)
				row:SetWidth(gridW)
				row.level:SetText(r == 1 and tostring(step.level) or "")
				UI.SetTextRole(row.level, step.earned and "textFaint" or "heading")
				row.icon:SetTexture(reward.icon or QUESTION)
				row.icon:SetDesaturated(step.earned)
				row.name:SetText(reward.name)
				UI.SetTextRole(row.name, step.earned and "textFaint" or "text")

				row.line:SetShown(r == 1)
				trackY = trackY + REWARD_H
			end
		end
		self.scroll:SetContentHeight(math.max(trackY, DETAIL_H + 8) + 16)
	end

	return view
end
