local addonName, ns = ...

-- Pet Battles: the tamer card beside the gossip window (who this is, the team Tomte will use, whether your pets
-- are ready, Load team, Guides and the Heal button). Guides opens the links window (Guides.lua).

local UI = ns.UI
local CARD_W = 280
local PAD = 10
local ICON = 26
-- The header's heights, top down: label, gap, tamer name, the section line (when there is one), gap before Team.
local LABEL_H, NAME_GAP, NAME_H, SECTION_H, HEADER_GAP = 10, 3, 16, 14, 8

local db
local card
local cardNPC

function ns.PetsCard_Init(moduleDB)
	db = moduleDB
end

-- Readiness text ---------------------------------------------------------------------------------------------

local KIND_TEXT = {
	empty = "Slot %d is empty",
	dead = "%s is dead",
	low = "%s is level %d",
	hurt = "%s is hurt",
}
local KIND_ROLE = { empty = "danger", dead = "danger", low = "warning", hurt = "warning" }

local function SpeciesName(species)
	return C_PetJournal.GetPetInfoBySpeciesID(species) or ("species " .. species)
end

local function LevelingGuid()
	return ns.PetsJournal_NextLeveling(db)
end

-- Lines saying what's wrong with your team for this fight: { { text, role } }. Empty = ready.
function ns.PetsCard_Problems(team)
	local lines = {}
	local canChange, why = ns.PetsJournal_CanChange()
	if not canChange then
		-- A locked journal reads as an empty team, so say why instead of listing empty slots.
		lines[1] = { "Can't change pets now: " .. why .. ".", "warning" }
		return lines
	end
	local loadout = ns.PetsJournal_Loadout()
	local opts = { minLevel = team and team.prefs and team.prefs.minLevel or nil }
	if team then
		for slot, tag in ipairs(team.pets) do
			if tag.kind == "leveling" then
				opts.leveling = slot
			end
		end
		local current = {}
		for slot = 1, 3 do
			current[slot] = loadout[slot] and loadout[slot].guid
		end
		local picks, missing = ns.Pets_PickTeam(team, ns.PetsJournal_Owned(), current, { leveling = LevelingGuid() })
		for _, m in ipairs(missing) do
			local text = m.another and "You need a second %s (slot %d)" or "You don't have %s (slot %d)"
			lines[#lines + 1] = { text:format(SpeciesName(m.species), m.slot), "danger" }
		end
		for slot = 1, 3 do
			if picks[slot].guid and picks[slot].guid ~= current[slot] then
				lines[#lines + 1] = { "This team isn't loaded yet: press Load team.", "warning" }
				break
			end
		end
	end
	if db.leveling.on and not opts.leveling then
		opts.leveling = db.leveling.slot
	end
	for _, p in ipairs(ns.Pets_Readiness(loadout, opts)) do
		local pet = loadout[p.slot]
		local text = KIND_TEXT[p.kind]
		if p.kind == "empty" then
			text = text:format(p.slot)
		elseif p.kind == "low" then
			text = text:format(pet.name, pet.level)
		else
			text = text:format(pet.name)
		end
		lines[#lines + 1] = { text, KIND_ROLE[p.kind] }
	end
	return lines
end

-- Tamer card -------------------------------------------------------------------------------------------------

local function TeamIcons(parent)
	local icons = {}
	for i = 1, 3 do
		local t = parent:CreateTexture(nil, "ARTWORK")
		t:SetSize(ICON, ICON)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icons[i] = t
	end
	return icons
end

-- Sets three icons to a team's pets (grey when you don't own one).
function ns.PetsCard_SetTeamIcons(icons, team)
	local owned = {}
	for _, p in ipairs(ns.PetsJournal_Owned()) do
		owned[p.species] = true
	end
	for i = 1, 3 do
		local tag = team and team.pets[i]
		local tex, have = "Interface\\Icons\\INV_Misc_QuestionMark", true
		if tag and tag.kind == "species" then
			local _, icon = C_PetJournal.GetPetInfoBySpeciesID(tag.species)
			tex, have = icon or tex, owned[tag.species] == true
		elseif tag and tag.kind == "leveling" then
			tex = "Interface\\Icons\\INV_Pet_BattlePetTraining"
		elseif tag and tag.kind == "random" then
			tex = "Interface\\Icons\\INV_Misc_Dice_01"
		end
		icons[i]:SetTexture(tex)
		icons[i]:SetDesaturated(not have)
		icons[i]:SetAlpha(have and 1 or 0.5)
	end
end

local function LoadTeam()
	local team = cardNPC and ns.PetsStore_TeamFor(cardNPC)
	if not team then
		return false
	end
	ns.PetsJournal_LoadAndReport(team, LevelingGuid())
	-- A short wait, presumably so the journal reads back the new loadout.
	C_Timer.After(0.3, ns.PetsCard_Refresh)
	return true
end
ns.PetsCard_LoadTeam = LoadTeam

local function BuildCard()
	-- On WorldFrame: dialogue addons (DialogueUI, Immersion) hide UIParent while you talk to the tamer. HIGH keeps it
	-- above the gossip window and other panels; the Heal button on it is one strata higher (Journal.lua).
	card = CreateFrame("Frame", "TomtePetsCard", WorldFrame)
	card:SetSize(CARD_W, 120)
	card:SetFrameStrata("HIGH")
	card:SetClampedToScreen(true)
	card:Hide()
	UI.Panel(card, { alpha = 0.95 })
	card.label = UI.Text(card, 10, "textMuted", "label")
	card.label:SetPoint("TOPLEFT", PAD, -PAD)
	card.label:SetText(ns.Spaced("Pet tamer"))
	card.name = UI.Text(card, 14, "heading")
	card.name:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -3)
	card.name:SetPoint("RIGHT", -PAD, 0)
	card.name:SetWordWrap(false)
	card.section = UI.Text(card, 10, "textMuted")
	card.section:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
	card.section:SetPoint("RIGHT", -PAD, 0)
	card.section:SetWordWrap(false)

	card.teamLabel = UI.Text(card, 10, "textMuted", "label")
	card.teamLabel:SetText("Team")
	card.team = UI.Text(card, 12, "text")
	card.team:SetPoint("RIGHT", -PAD, 0)
	card.team:SetWordWrap(false)
	card.pick = UI.Dropdown(card, 150)
	card.pick:SetHeight(18)
	card.pick.choices = function()
		local out = {}
		for _, t in ipairs(ns.PetsStore_TeamsFor(cardNPC)) do
			out[#out + 1] = { value = t.id, text = t.name }
		end
		return out
	end
	card.pick.getValue = function()
		local t = ns.PetsStore_TeamFor(cardNPC)
		return t and t.id
	end
	card.pick.setValue = function(id)
		ns.PetsStore_SetActive(cardNPC, id)
		ns.PetsCard_Refresh()
	end
	card.icons = TeamIcons(card)
	card.lines = {}
	card.seen = UI.Text(card, 11, "textMuted")
	card.seen:SetPoint("RIGHT", -PAD, 0)

	card.load = UI.Button(card, 90, "Load team")
	card.load:SetScript("OnClick", LoadTeam)
	card.links = UI.Button(card, 70, "Guides")
	card.links:SetScript("OnClick", function()
		ns.PetsGuides_ShowNPC(cardNPC)
	end)
	card.close = UI.Button(card, 20, "x")
	card.close:SetPoint("TOPRIGHT", -6, -6)
	card.close:SetScript("OnClick", function()
		ns.PetsCard_Hide()
	end)
end

local function Line(i)
	local fs = card.lines[i]
	if not fs then
		fs = UI.Text(card, 11, "text")
		fs:SetPoint("RIGHT", -PAD, 0)
		fs:SetWordWrap(false)
		card.lines[i] = fs
	end
	return fs
end

local function PlaceHeal()
	local left, bottom = card:GetLeft(), card:GetBottom()
	if not (left and bottom) then
		return
	end
	local scale = card:GetEffectiveScale() / UIParent:GetEffectiveScale()
	ns.PetsHeal_Show(left * scale + PAD, bottom * scale + PAD)
end

function ns.PetsCard_Refresh()
	if not (card and card:IsShown() and cardNPC) then
		return
	end
	local npc = cardNPC
	card.name:SetText(ns.PetsStore_NPCName(npc))
	local encounters = ns.PetsStore_Encounters(npc)
	local sections = {}
	for _, e in ipairs(encounters) do
		local s = ns.PetsStore_Section(e.section)
		sections[#sections + 1] = s and s.name or ""
	end
	card.section:SetText(table.concat(sections, ", "))

	local y = PAD + LABEL_H + NAME_GAP + NAME_H + (#sections > 0 and SECTION_H or 0) + HEADER_GAP
	local team = ns.PetsStore_TeamFor(npc)
	local teams = ns.PetsStore_TeamsFor(npc)
	card.teamLabel:ClearAllPoints()
	card.teamLabel:SetPoint("TOPLEFT", PAD, -y)
	y = y + 14
	if #teams > 1 then
		card.team:Hide()
		card.pick:Show()
		card.pick:ClearAllPoints()
		card.pick:SetPoint("TOPLEFT", PAD + ICON * 3 + 16, -y - 4)
		card.pick:SetPoint("RIGHT", -PAD, 0)
		card.pick:Refresh()
	else
		card.pick:Hide()
		card.team:Show()
		card.team:ClearAllPoints()
		card.team:SetPoint("TOPLEFT", PAD + (team and ICON * 3 + 16 or 0), -y - 7)
		card.team:SetPoint("RIGHT", -PAD, 0)
		card.team:SetWordWrap(team == nil) -- the no-strategy hint wraps; a team name stays on one line by its icons
		card.team:SetText(team and team.name or UI.Wrap("No strategy saved. Get one from Xu-Fu (Guides).", "textMuted"))
	end
	for i, icon in ipairs(card.icons) do
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", PAD + (i - 1) * (ICON + 4), -y)
		icon:SetShown(team ~= nil)
	end
	if team then
		ns.PetsCard_SetTeamIcons(card.icons, team)
		y = y + ICON + 8
	else
		y = y + math.max(22, card.team:GetStringHeight() + 10)
	end

	local problems = ns.PetsCard_Problems(team)
	if #problems == 0 then
		problems = { { "Ready", "success" } }
	end
	for i, p in ipairs(problems) do
		local fs = Line(i)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", PAD, -y)
		fs:SetPoint("RIGHT", -PAD, 0)
		fs:SetText(p[1])
		UI.SetTextRole(fs, p[2])
		fs:Show()
		y = y + 15
	end
	for i = #problems + 1, #card.lines do
		card.lines[i]:Hide()
	end

	local learned = ns.PetsStore_Learned(npc)
	if learned and learned.types and #learned.types > 0 then
		local icons = {}
		for i, t in ipairs(learned.types) do
			icons[i] = ns.Pets_FamilyIcon(t, 14) .. " " .. ns.Pets_FamilyName(t)
		end
		card.seen:ClearAllPoints()
		card.seen:SetPoint("TOPLEFT", PAD, -y - 2)
		card.seen:SetPoint("RIGHT", -PAD, 0)
		card.seen:SetText("Seen:  " .. table.concat(icons, "  "))
		card.seen:Show()
		y = y + 18
	else
		card.seen:Hide()
	end

	y = y + 8
	-- Bottom row: the Heal button (secure, placed by coordinates) on the left, then Load team and Guides.
	card.links:ClearAllPoints()
	card.links:SetPoint("TOPRIGHT", -PAD, -y - 6)
	card.load:ClearAllPoints()
	card.load:SetPoint("RIGHT", card.links, "LEFT", -6, 0)
	local canLoad = team ~= nil and ns.PetsJournal_CanChange()
	card.load:SetEnabled(canLoad)
	card.load:SetAlpha(canLoad and 1 or 0.4)
	card:SetHeight(y + 32 + PAD)
	if not InCombatLockdown() then
		C_Timer.After(0, PlaceHeal) -- after the new height is laid out
	end
end

function ns.PetsCard_Show(npc)
	if not card then
		BuildCard()
	end
	cardNPC = npc
	card:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale())
	card:ClearAllPoints()
	if GossipFrame and GossipFrame:IsShown() then
		card:SetPoint("TOPLEFT", GossipFrame, "TOPRIGHT", 8, 0)
	else
		-- No Blizzard gossip window (a dialogue addon replaced it): roughly where its right edge would be.
		card:SetPoint("LEFT", UIParent, "LEFT", 420, 80)
	end
	card:Show()
	ns.PetsCard_Refresh()
end

function ns.PetsCard_OnGossip(npc)
	if not ns.PetsStore_Known(npc) or C_PetBattles.IsInBattle() then
		return
	end
	ns.PetsCard_Show(npc)
	local team = ns.PetsStore_TeamFor(npc)
	if db.card.autoLoad and team and not ns.Pets_RematchLoaded() and ns.PetsJournal_CanChange() then
		local current = ns.PetsJournal_Loadout()
		local picks = ns.Pets_PickTeam(team, ns.PetsJournal_Owned(), {
			current[1] and current[1].guid, current[2] and current[2].guid, current[3] and current[3].guid,
		}, { leveling = LevelingGuid() })
		local changes = false
		for slot = 1, 3 do
			if picks[slot].guid and picks[slot].guid ~= (current[slot] and current[slot].guid) then
				changes = true
			end
		end
		if changes then
			LoadTeam()
		end
	end
end

function ns.PetsCard_Hide()
	if card then
		card:Hide()
	end
	cardNPC = nil
	if not ns.PetsHeal_AfterBattleShown() then -- the after-battle button keeps its time
		ns.PetsHeal_Hide()
	end
end

function ns.PetsCard_Shown()
	return card ~= nil and card:IsShown()
end
