local addonName, ns = ...

-- Pet Battles: the pet journal side. Reads your battle pets (C_PetJournal.GetOwnedPetIDs, which ignores the
-- journal's own filters, so Tomte never touches them), the current team, loads a saved team, refills the leveling
-- slot, and owns the secure Heal button (Revive Battle Pets, or a Battle Pet Bandage while it's on cooldown), shown
-- on the tamer card (Card.lua) and for a while after a battle.

local UI = ns.UI
local REVIVE = 125439 -- Revive Battle Pets (the journal's heal button)
local BANDAGE = 86143 -- Battle Pet Bandage
local HEAL_SIZE = 32

local owned, dirty = nil, true

local IsSecret = ns.IsSecret

-- Owned pets ---------------------------------------------------------------------------------------------------

local function ReadPet(guid)
	local species, customName, level, _, _, _, _, name, icon, petType, _, _, _, _, canBattle =
		C_PetJournal.GetPetInfoByPetID(guid)
	if not species or not canBattle then
		return nil
	end
	local health, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(guid)
	local abilities = C_PetJournal.GetPetAbilityList(species) or {}
	return { guid = guid, species = species, name = customName or name, speciesName = name, icon = icon,
		level = level or 1, type = petType, rarity = rarity or 1, health = health or 0, maxHealth = maxHealth or 1,
		power = power, speed = speed, abilities = abilities }
end

-- Every battle pet you own: { guid, species, name, icon, level, type, rarity (1-6), health, maxHealth, abilities }.
function ns.PetsJournal_Owned()
	if owned and not dirty then
		return owned
	end
	owned = {}
	local guids = C_PetJournal.GetOwnedPetIDs and C_PetJournal.GetOwnedPetIDs() or {}
	for _, guid in ipairs(guids) do
		local p = ReadPet(guid)
		if p then
			owned[#owned + 1] = p
		end
	end
	dirty = false
	return owned
end

function ns.PetsJournal_MarkDirty()
	dirty = true
end

function ns.PetsJournal_Pet(guid)
	for _, p in ipairs(ns.PetsJournal_Owned()) do
		if p.guid == guid then
			return p
		end
	end
	return guid and ReadPet(guid) or nil
end

-- Your team now: { [slot] = owned pet | nil }.
function ns.PetsJournal_Loadout()
	local loadout = {}
	for slot = 1, 3 do
		local guid = C_PetJournal.GetPetLoadOutInfo(slot)
		loadout[slot] = guid and ns.PetsJournal_Pet(guid) or nil
	end
	return loadout
end

function ns.PetsJournal_CanChange()
	if C_PetBattles.IsInBattle() then
		return false, "not during a pet battle"
	elseif InCombatLockdown() then
		return false, "not in combat"
	elseif not C_PetJournal.IsJournalUnlocked() then
		return false, "the pet journal is locked (in use on another character of your account?)"
	end
	return true
end

-- Loads team (Strings.lua shape). opts = { leveling = guid }. Returns ok, missing, reason.
function ns.PetsJournal_LoadTeam(team, opts)
	local ok, reason = ns.PetsJournal_CanChange()
	if not ok then
		return false, {}, reason
	end
	ns.PetsJournal_MarkDirty()
	local current = {}
	for slot = 1, 3 do
		current[slot] = C_PetJournal.GetPetLoadOutInfo(slot)
	end
	local picks, missing = ns.Pets_PickTeam(team, ns.PetsJournal_Owned(), current, opts)
	for slot = 1, 3 do
		local pick = picks[slot]
		if pick.guid and pick.guid ~= C_PetJournal.GetPetLoadOutInfo(slot) then
			C_PetJournal.SetPetLoadOutInfo(slot, pick.guid)
		end
	end
	for slot = 1, 3 do
		local pick = picks[slot]
		if pick.guid then
			for tier = 1, 3 do
				local ability = pick.abilities[tier]
				if ability then
					C_PetJournal.SetAbility(slot, tier, ability)
				end
			end
		end
	end
	return true, missing
end

-- Loads a team and says what happened in chat. Returns ok.
function ns.PetsJournal_LoadAndReport(team, levelingGuid)
	local ok, missing, reason = ns.PetsJournal_LoadTeam(team, { leveling = levelingGuid })
	if not ok then
		ns.Print("can't load the team: " .. reason .. ".")
		return false
	end
	if #missing == 0 then
		ns.Print("loaded " .. team.name .. ".")
		return true
	end
	local names = {}
	for i, m in ipairs(missing) do
		local name = C_PetJournal.GetPetInfoBySpeciesID(m.species) or ("species " .. m.species)
		names[i] = (m.another and "a second " or "") .. name
	end
	if #missing >= 3 then
		ns.Print(("couldn't load %s: you don't own its pets (%s)."):format(team.name, table.concat(names, ", ")))
	else
		ns.Print(("loaded %s, but you're missing %s."):format(team.name, table.concat(names, ", ")))
	end
	return true
end

-- The leveling queue's next pet (nil when the leveling slot is off or the queue is done).
function ns.PetsJournal_NextLeveling(db)
	if not db.leveling.on then
		return nil
	end
	return (ns.Pets_NextLeveling(db.levelQueue, ns.PetsJournal_Owned()))
end

-- After a battle: the leveling slot gets the next queued pet when its pet hit 25 or isn't the queue's.
-- Returns the name of the pet now in the slot when it changed, or nil and why it couldn't.
function ns.PetsJournal_RefillLeveling(db)
	if not db.leveling.on then
		return nil
	end
	local ok, reason = ns.PetsJournal_CanChange()
	if not ok then
		return nil, reason
	end
	ns.PetsJournal_MarkDirty()
	local pets = ns.PetsJournal_Owned()
	if #pets == 0 then -- the journal hasn't loaded: never prune the queue against nothing
		return nil
	end
	local guid, queue = ns.Pets_NextLeveling(db.levelQueue, pets)
	db.levelQueue = queue
	local slot = db.leveling.slot
	if not guid or C_PetJournal.GetPetLoadOutInfo(slot) == guid then
		return nil
	end
	C_PetJournal.SetPetLoadOutInfo(slot, guid)
	ns.PetsJournal_MarkDirty()
	local p = ns.PetsJournal_Pet(guid)
	return p and p.name
end

-- Heal button --------------------------------------------------------------------------------------------------

local holder, heal

-- ready, seconds left, cooldown start, cooldown duration.
local function ReviveReady()
	local cd = C_Spell.GetSpellCooldown(REVIVE)
	if not cd or IsSecret(cd.startTime) or IsSecret(cd.duration) then
		return true, 0
	end
	local left = cd.startTime > 0 and (cd.startTime + cd.duration - GetTime()) or 0
	return left <= 1.5, left, cd.startTime, cd.duration -- the global cooldown doesn't count
end

local function BandageCount()
	return C_Item.GetItemCount(BANDAGE) or 0
end

local function HealTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if self.useBandage then
		GameTooltip:SetItemByID(BANDAGE)
	else
		GameTooltip:SetSpellByID(REVIVE)
	end
	local ready, left = ReviveReady()
	if not ready then
		GameTooltip:AddLine(("Revive Battle Pets is ready in %d:%02d."):format(math.floor(left / 60), math.floor(left % 60)), UI.RGB("warning"))
	end
	local key = GetBindingKey("CLICK TomtePetHeal:LeftButton")
	if key then
		GameTooltip:AddLine("Key: " .. GetBindingText(key), UI.RGB("textMuted"))
	end
	GameTooltip:Show()
end

local function CreateHeal()
	-- On WorldFrame like the tamer card, so a dialogue addon hiding UIParent doesn't take it along. DIALOG: above the
	-- card (HIGH) it's placed on. The button's global name is what its key binding clicks (Bindings.xml).
	holder = CreateFrame("Frame", "TomtePetHealHolder", WorldFrame, "SecureFrameTemplate")
	holder:SetSize(HEAL_SIZE, HEAL_SIZE)
	holder:SetFrameStrata("DIALOG")
	holder:Hide()
	heal = CreateFrame("Button", "TomtePetHeal", holder, "SecureActionButtonTemplate")
	heal:SetAllPoints()
	-- Acts on the press: down clicks only (a key binding's CLICK sends a down and an up), and useOnKeyDown tells the
	-- secure template to act on that down click whatever the ActionButtonUseKeyDown setting is.
	heal:RegisterForClicks("AnyDown")
	heal:SetAttribute("useOnKeyDown", true)
	heal.icon = heal:CreateTexture(nil, "ARTWORK")
	heal.icon:SetAllPoints()
	heal.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	UI.Border(heal, "frame", 0.8)
	heal:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	heal.cooldown = CreateFrame("Cooldown", nil, heal, "CooldownFrameTemplate")
	heal.cooldown:SetAllPoints()
	heal.count = UI.Text(heal, 11, "text", "number")
	heal.count:SetPoint("BOTTOMRIGHT", -2, 2)
	heal.label = UI.Text(heal, 11, "heading", "label")
	heal.label:SetPoint("LEFT", heal, "RIGHT", 6, 0)
	heal:SetScript("OnEnter", HealTooltip)
	heal:SetScript("OnLeave", GameTooltip_Hide)
end

-- Makes the button (hidden) so its key binding works from the start. Out of combat only.
function ns.PetsHeal_Ensure()
	if not holder and not InCombatLockdown() then
		CreateHeal()
		ns.PetsHeal_Refresh()
	end
end

-- Sets what the button does (spell or bandage). Out of combat only.
function ns.PetsHeal_Refresh()
	if not heal or InCombatLockdown() then
		return
	end
	local ready, _, start, duration = ReviveReady()
	local bandages = BandageCount()
	heal.useBandage = not ready and bandages > 0
	local name = C_Spell.GetSpellName(REVIVE)
	if heal.useBandage then
		heal:SetAttribute("type", "macro")
		heal:SetAttribute("macrotext", "/use item:" .. BANDAGE)
		heal.icon:SetTexture(C_Item.GetItemIconByID(BANDAGE))
		heal.count:SetText(bandages)
		heal.label:SetText("Bandage")
	else
		-- A /cast macro rather than type=spell: on 12.1 type=spell silently failed to cast mounts (Smart Mount), and
		-- whether it would work for Revive Battle Pets hasn't been tested.
		heal:SetAttribute("type", name and "macro" or nil)
		heal:SetAttribute("macrotext", name and ("/cast " .. name) or nil)
		heal.icon:SetTexture(C_Spell.GetSpellTexture(REVIVE))
		heal.count:SetText("")
		heal.label:SetText("Heal pets")
	end
	heal.icon:SetDesaturated(not ready and not heal.useBandage)
	if not ready and not heal.useBandage then
		heal.cooldown:SetCooldown(start, duration)
	else
		heal.cooldown:Clear()
	end
end

-- x, y: the button's bottom-left in UIParent coordinates. Out of combat only (returns false otherwise).
function ns.PetsHeal_Show(x, y)
	if InCombatLockdown() then
		return false
	end
	if not holder then
		CreateHeal()
	end
	holder:SetScale(UIParent:GetEffectiveScale() / WorldFrame:GetEffectiveScale()) -- so x, y are UIParent units
	holder:ClearAllPoints()
	holder:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", x, y)
	ns.PetsHeal_Refresh()
	holder:Show()
	return true
end

function ns.PetsHeal_Hide()
	if holder and not InCombatLockdown() then
		holder:Hide()
	end
end

function ns.PetsHeal_Shown()
	return holder ~= nil and holder:IsShown()
end

-- After a battle (Battle.lua) the button shows by itself where the helper sits, for a while; when the time is up it
-- stays if the tamer card is showing it.
local AFTER_BATTLE_SECONDS = 30 -- the Heal option's tooltip (Pets.lua) says 30 seconds
local healTimer
function ns.PetsHeal_AfterBattleShown()
	return healTimer ~= nil
end

function ns.PetsHeal_ShowAfterBattle(anchor)
	local x, y
	if anchor and anchor:GetLeft() then
		local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
		x, y = anchor:GetLeft() * scale + 10, (anchor:GetTop() - 40) * scale
	else
		x, y = UIParent:GetWidth() / 2 - 16, 215
	end
	if ns.PetsHeal_Show(x, y) then
		if healTimer then
			healTimer:Cancel()
		end
		healTimer = C_Timer.NewTimer(AFTER_BATTLE_SECONDS, function()
			healTimer = nil
			if not (ns.PetsCard_Shown and ns.PetsCard_Shown()) then
				ns.PetsHeal_Hide()
			end
		end)
	end
end

-- Its holder hides when combat starts (secure frames can't change in combat).
function ns.PetsHeal_OnCombat()
	if holder then
		holder:Hide()
	end
end

-- Any pet on your team below full health (or dead)?
function ns.PetsJournal_TeamHurt()
	for slot = 1, 3 do
		local guid = C_PetJournal.GetPetLoadOutInfo(slot)
		if guid then
			local health, maxHealth = C_PetJournal.GetPetStats(guid)
			if health and maxHealth and health < maxHealth then
				return true
			end
		end
	end
	return false
end

_G["BINDING_NAME_CLICK TomtePetHeal:LeftButton"] = "Heal battle pets"
