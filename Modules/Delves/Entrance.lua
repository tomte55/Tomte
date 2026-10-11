local addonName, ns = ...

-- Delves: a note beside Blizzard's tier picker at a delve entrance (PLAYER_INTERACTION_MANAGER_FRAME_SHOW with
-- Enum.PlayerInteractionType.TieredEntrance, which loads Blizzard_DelvesDifficultyPicker). It only anchors to
-- DelvesDifficultyPickerFrame (a normal frame): nothing of Blizzard's is hooked, changed or clicked. Lines: the tier
-- for your vault, the tier for your gear, your keys (and "Bountiful" when this is today's), your companion.

local UI = ns.UI
local W, PAD, GAP = 260, 12, 8

local db
local active = false
local open = false -- the tier picker interaction is on (between its _SHOW and _HIDE)
local card

local events = ns.Delves_Events

local Secret = ns.IsSecret

local function Picker()
	return DelvesDifficultyPickerFrame
end

local function Build()
	card = CreateFrame("Frame", nil, UIParent)
	card:SetSize(W, 40)
	card:SetFrameStrata("DIALOG")
	card:Hide()
	UI.Panel(card)
	card.title = UI.Text(card, 14, "heading", "title")
	card.title:SetPoint("TOPLEFT", PAD, -PAD)
	card.title:SetText("Tomte")
	card.blocks = {}
	local elapsed = 0
	-- The picker can close without its _HIDE reaching us first (a loading screen): follow it.
	card:SetScript("OnUpdate", function(self, dt)
		elapsed = elapsed + dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		local picker = Picker()
		if not (picker and picker:IsShown()) then
			self:Hide()
		end
	end)
end

-- The i-th block: a small muted heading over one or two lines of text.
local function Block(i)
	local b = card.blocks[i]
	if not b then
		b = {}
		b.head = UI.Text(card, 11, "textMuted", "label")
		b.text = UI.Text(card, 12, "text")
		b.text:SetWordWrap(true)
		b.text:SetWidth(W - 2 * PAD)
		b.sub = UI.Text(card, 11, "textMuted")
		b.sub:SetWordWrap(true)
		b.sub:SetWidth(W - 2 * PAD)
		card.blocks[i] = b
	end
	return b
end

local function GearLine()
	if not (C_DelvesUI and C_DelvesUI.GetDelveEntranceTiers) then
		return nil
	end
	local _, equipped = GetAverageItemLevel()
	if not equipped or Secret(equipped) then
		return nil
	end
	local tier = ns.Delves_SuggestTier(C_DelvesUI.GetDelveEntranceTiers(), math.floor(equipped))
	return tier and ("Tier %d suits your item level %d"):format(tier.tier, math.floor(equipped)) or nil
end

-- Two game strings compared with each other (the entrance's title and the scanned POI name), never with English.
local function IsBountifulHere()
	local title = C_DelvesUI and C_DelvesUI.GetDelveEntranceTitleString and C_DelvesUI.GetDelveEntranceTitleString()
	if not title or Secret(title) then
		return false
	end
	for _, e in ipairs(ns.DelvesScan_List()) do
		if e.bountiful and e.name == title then
			return true
		end
	end
	return false
end

local function Lines()
	local s = ns.DelvesRead_State()
	local lines = {}
	local vault = s.vault
	if vault and vault.plan.text then
		lines[#lines + 1] = { head = "Your vault", text = vault.plan.text, color = vault.plan.advice and "accent" or "success",
			sub = ns.Delves_LadderText(vault.ladder) }
	end
	local gear = GearLine()
	if gear then
		lines[#lines + 1] = { head = "Your gear", text = gear }
	end
	if s.keyLine then
		local text = s.keyLine
		if IsBountifulHere() then
			text = text .. " · " .. UI.Wrap("Bountiful", "accent")
		end
		lines[#lines + 1] = { head = "Keys", text = text }
	end
	local c = s.companion
	if c then
		local parts = { c.name, "level " .. c.level }
		if c.roleName then
			parts[#parts + 1] = c.roleName
		end
		local hint = ns.DelvesRead_RoleHint()
		lines[#lines + 1] = { head = "Companion", text = table.concat(parts, " · "), sub = hint, subColor = "warning" }
	end
	return lines
end

local function Show()
	local picker = Picker()
	if not (open and active and db.entrance and picker and picker:IsShown()) or InCombatLockdown() then
		return
	end
	if not card then
		Build()
	end
	local lines = Lines()
	local y = PAD + 22
	for i, line in ipairs(lines) do
		local b = Block(i)
		b.head:ClearAllPoints()
		b.head:SetPoint("TOPLEFT", PAD, -y)
		b.head:SetText(line.head)
		b.head:Show()
		y = y + 14
		b.text:ClearAllPoints()
		b.text:SetPoint("TOPLEFT", PAD, -y)
		b.text:SetText(line.text)
		UI.SetTextRole(b.text, line.color or "text")
		b.text:Show()
		y = y + b.text:GetStringHeight()
		if line.sub then
			b.sub:ClearAllPoints()
			b.sub:SetPoint("TOPLEFT", PAD, -(y + 2))
			b.sub:SetText(line.sub)
			UI.SetTextRole(b.sub, line.subColor or "textMuted")
			b.sub:Show()
			y = y + 2 + b.sub:GetStringHeight()
		else
			b.sub:Hide()
		end
		y = y + GAP
	end
	for i = #lines + 1, #card.blocks do
		local b = card.blocks[i]
		b.head:Hide()
		b.text:Hide()
		b.sub:Hide()
	end
	if #lines == 0 then
		card:Hide()
		return
	end
	card:SetHeight(y - GAP + PAD)
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", picker, "TOPRIGHT", 8, 0)
	card:Show()
end

local function Hide()
	if card then
		card:Hide()
	end
end

events:On("entrance", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
	if kind == Enum.PlayerInteractionType.TieredEntrance and db.entrance then
		open = true
		ns.DelvesRead_Dirty() -- fresh numbers for the card; it redraws when they arrive
		-- Blizzard shows the picker from the same event (TryShow): try on the next frame and shortly after.
		C_Timer.After(0, Show)
		C_Timer.After(0.3, Show)
	end
end)

events:On("entrance", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
	if kind == Enum.PlayerInteractionType.TieredEntrance then
		open = false
		Hide()
	end
end)

events:On("entrance", "PLAYER_REGEN_DISABLED", function()
	Hide()
end)

function ns.DelvesEntrance_Init(saved)
	db = saved
end

-- Redraw while the picker is up (Delves_Changed after a read).
function ns.DelvesEntrance_Refresh()
	if open then
		Show()
	end
end

function ns.DelvesEntrance_Toggle(on)
	active = on
	if on then
		events:Watch("entrance", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
		events:Watch("entrance", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
		events:Watch("entrance", "PLAYER_REGEN_DISABLED")
	else
		events:UnwatchAll("entrance")
		open = false
		Hide()
	end
end
