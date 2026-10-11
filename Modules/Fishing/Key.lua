local addonName, ns = ...

-- Fishing: the key (Key Bindings > Tomte > Fishing) and the optional on-screen button. The key clicks the secure
-- button TomteFishing; its PreClick (out of combat) sets a /cast macro or a toy. Reeling in can't be a secure action
-- (there's no "interact" type; INTERACTTARGET runs a restricted function), so while a fishing channel runs, every
-- key bound to TomteFishing gets a priority override to INTERACTTARGET, owned by the event frame below, and loses it
-- when the channel stops. A binding never changes while one of its keys is held: the cast press is still down when
-- the channel starts, so the change waits for the release. One real key press per action, nothing automatic.
-- Bindings, attributes and the protected holder change only out of combat; overrides also not while a Combat,
-- Encounter, ChallengeMode or PvPMatch addon restriction is active.

local UI = ns.UI
local BUTTON_NAME, BAR_NAME = "TomteFishing", "TomteFishingBar"
local BINDING = "CLICK " .. BUTTON_NAME .. ":LeftButton" -- also in Bindings.xml
ns.FISHING_BINDING = BINDING -- Fishing.lua (loads after this file) reads the key from it
local SIZE = 40
local WAIT_STEP, WAIT_LIMIT = 0.05, 10 -- seconds between key checks, and when to give up waiting for a release
local TICK = 1 -- the visible button's refresh
local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }

local db, module, holder, button, ticker
local fishing = false -- a fishing channel runs
local lootOpen -- GetTime() of the last LOOT_OPENED/LOOT_READY, nil once closed
local overridden = {} -- keys that point at INTERACTTARGET right now
local want -- what the waiter applies once the keys are up: "reel" or "clear"

local IsSecret = ns.IsSecret

local function FishingName()
	return C_Spell.GetSpellName(ns.FISHING_SPELL) or PROFESSIONS_FISHING
end

-- A channel is out (a secret answer counts as yes: it only is during restrictions, where nothing changes anyway).
local function ChannelRunning()
	local name = UnitChannelInfo("player")
	return IsSecret(name) or name ~= nil
end

local function Keys()
	return { GetBindingKey(BINDING) }
end

local function KeyText()
	local key = GetBindingKey(BINDING)
	return key and GetBindingText(key) or nil
end

local function Restricted()
	if not (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum.AddOnRestrictionType) then
		return false
	end
	for _, name in ipairs(RESTRICTIONS) do
		local kind = Enum.AddOnRestrictionType[name]
		if kind and C_RestrictedActions.IsAddOnRestrictionActive(kind) then
			return true
		end
	end
	return false
end

-- Whether the module does anything: a key is bound or the button shows. Otherwise fishing by hand is untouched.
local function Engaged()
	return module.active and (GetBindingKey(BINDING) ~= nil or db.button.shown)
end

local function LootOpen()
	return lootOpen ~= nil and GetTime() - lootOpen < ns.FISHING_LOOT_TIMEOUT
end

-- Toys -------------------------------------------------------------------------------------------------------------

-- Owned and its data loaded (a toy whose info isn't loaded yet counts as not owned for this press).
local function OwnsToy(item)
	return PlayerHasToy(item) and C_ToyBox.GetToyInfo(item) ~= nil
end

function ns.Fishing_OwnedRafts()
	local list = {}
	for _, raft in ipairs(ns.FISHING_RAFTS) do
		if OwnsToy(raft.item) then
			list[#list + 1] = raft.item
		end
	end
	return list
end

-- Choices for the raft dropdown: Random first, then each owned raft by name.
function ns.Fishing_RaftChoices()
	local owned = ns.Fishing_OwnedRafts()
	if #owned == 0 then
		return { { value = 0, text = "You own no fishing raft" } }
	end
	local list = { { value = 0, text = "Random" } }
	for _, item in ipairs(owned) do
		local _, name = C_ToyBox.GetToyInfo(item)
		list[#list + 1] = { value = item, text = name or ("Raft " .. item) }
	end
	return list
end

function ns.Fishing_OwnsBobber()
	return OwnsToy(ns.FISHING_BOBBER_TOY.item)
end

-- Seconds left on one of the player's auras, math.huge when the time can't be read, nil when it isn't on.
local function AuraLeft(spellID)
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
	if not aura or IsSecret(aura) then
		return nil
	end
	local expires = aura.expirationTime
	if IsSecret(expires) or type(expires) ~= "number" or expires == 0 then
		return math.huge
	end
	return expires - GetTime()
end

local function ToyIcon(item)
	local _, _, icon = C_ToyBox.GetToyInfo(item)
	return icon or C_Item.GetItemIconByID(item)
end

-- The next press ------------------------------------------------------------------------------------------------

local function Known()
	if C_SpellBook.IsSpellKnown(ns.FISHING_SPELL) then
		return true
	end
	local _, _, _, fishingIndex = GetProfessions()
	return fishingIndex ~= nil
end

local function Situation()
	local s = {
		known = Known(),
		dead = UnitIsDeadOrGhost("player"),
		blocked = UnitInVehicle("player") or UnitOnTaxi("player") or C_PetBattles.IsInBattle(),
		mounted = IsMounted(),
		flying = IsFlying(),
		swimming = IsSwimming(),
		lootOpen = LootOpen(),
		fishing = fishing and ChannelRunning(),
		rafts = ns.Fishing_OwnedRafts(),
	}
	if db.raft.on then
		for _, raft in ipairs(ns.FISHING_RAFTS) do
			s.raftLeft = s.raftLeft or AuraLeft(raft.aura)
		end
	end
	local bobber = ns.FISHING_BOBBER_TOY
	if db.bobber then
		s.bobberOwned = OwnsToy(bobber.item)
		s.bobberUp = AuraLeft(bobber.aura) ~= nil
		local start = C_Container.GetItemCooldown(bobber.item)
		s.bobberReady = not start or start == 0
	end
	return s
end

local function Options()
	return { lootProtect = db.lootProtect, dismount = db.dismount, raft = db.raft, bobber = db.bobber,
		random = math.random }
end

local function NextAction()
	return ns.Fishing_NextAction(Situation(), Options())
end

local function SetMacro(text)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", text)
end

local function Message(text)
	UIErrorsFrame:AddMessage("Fishing: " .. text, UI.RGB("warning"))
end

local function PreClick()
	if InCombatLockdown() then
		return
	end
	if not module.active then
		button:SetAttribute("type", nil)
		return
	end
	local action = NextAction()
	if action.kind == "toy" then
		button:SetAttribute("type", "toy") -- the toy type, as on the Teleports map tab
		button:SetAttribute("toy", action.item)
	else
		SetMacro(ns.Fishing_MacroText(action, { fishing = FishingName() }))
	end
	if action.reason == "unknown" then
		Message("you haven't learned Fishing.")
	elseif action.reason == "loot" then
		Message("still looting.")
	elseif action.reason == "mounted" and action.kind == "none" then
		Message(db.dismount and "land first." or "dismount first.")
	elseif action.reason == "fishing" then
		local key = KeyText()
		Message(key and ("press " .. key .. " to reel in.") or "click the bobber to reel in.")
	end
end

-- The reel override -------------------------------------------------------------------------------------------

local keyEvents = CreateFrame("Frame")
keyEvents:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local function ClearReel()
	if next(overridden) then
		ClearOverrideBindings(keyEvents)
		wipe(overridden)
	end
end

local function SetReel()
	ClearReel()
	for _, key in ipairs(Keys()) do -- read after clearing: only the player's own bindings
		SetOverrideBinding(keyEvents, true, key, "INTERACTTARGET")
		overridden[#overridden + 1] = key
	end
end

-- Keys whose state matters: the ones overridden now and the ones bound to the button.
local function WatchedKeys()
	local keys = Keys()
	for _, key in ipairs(overridden) do
		keys[#keys + 1] = key
	end
	return keys
end

local waiter = CreateFrame("Frame")
waiter:Hide()
local waited, sinceCheck = 0, 0
waiter:SetScript("OnUpdate", function(self, elapsed)
	waited, sinceCheck = waited + elapsed, sinceCheck + elapsed
	if waited > WAIT_LIMIT then
		self:Hide()
		return
	end
	if sinceCheck < WAIT_STEP then
		return
	end
	sinceCheck = 0
	if InCombatLockdown() or Restricted() or not ns.Fishing_KeysUp(WatchedKeys(), IsKeyDown) then
		return
	end
	if want == "reel" and fishing and Engaged() then
		SetReel()
	else
		ClearReel()
	end
	self:Hide()
	ns.FishingKey_Refresh()
end)

local function Wait(what)
	want = what
	waited, sinceCheck = 0, WAIT_STEP -- check on the next frame
	waiter:Show()
end

-- Button -----------------------------------------------------------------------------------------------------------

local function ButtonOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Fishing", UI.RGB("heading"))
	local key = KeyText()
	if key then
		GameTooltip:AddLine("Key: " .. key .. ". Press it to cast, and again on the splash to reel in.", UI.RGB("text"))
	else
		GameTooltip:AddLine("No key: Key Bindings > Tomte > Fishing.", UI.RGB("warning"))
	end
	GameTooltip:AddLine("A click casts, but can't reel in: use the key or click the bobber.", UI.RGB("textMuted"))
	GameTooltip:Show()
end

local function ApplyLayout()
	local f = db.button.frame
	holder:ClearAllPoints()
	holder:SetPoint(f.point, UIParent, f.relPoint, f.x, f.y)
	holder:SetScale(db.button.scale)
end

-- The holder is what Edit Mode moves and what shows or hides. It's protected (SecureFrameTemplate) because a protected
-- frame can't be anchored to an ordinary one ("Cannot anchor protected frames to regions"), so the secure button needs
-- a protected parent to SetAllPoints on. That also makes the holder's show, hide and layout out of combat only.
local function Create()
	holder = CreateFrame("Frame", BAR_NAME, UIParent, "SecureFrameTemplate")
	holder:SetSize(SIZE, SIZE)
	holder:SetMovable(true)
	holder:SetClampedToScreen(true)
	holder:SetFrameStrata("MEDIUM")
	holder:Hide()
	button = CreateFrame("Button", BUTTON_NAME, holder, "SecureActionButtonTemplate")
	button:SetAllPoints()
	-- Act on the press, not the release: with useOnKeyDown the secure handler runs the action on the down click, and
	-- the button has to be registered for down clicks to get it. The reel override then waits for that key's release.
	button:RegisterForClicks("AnyDown")
	button:SetAttribute("useOnKeyDown", true)
	button:SetScript("PreClick", PreClick)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	UI.Border(button, "frame", 0.8)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button.label = UI.Text(button, 10, "textMuted", "label")
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -3)
	button:SetScript("OnEnter", ButtonOnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	ApplyLayout()
end

-- The label and icon: what a press does now. Not protected, so it may run in combat too.
local function UpdateLook()
	if not (holder and holder:IsShown()) then
		return
	end
	local icon = C_Spell.GetSpellTexture(ns.FISHING_SPELL)
	local key = KeyText()
	local text, role
	if fishing then
		text, role = key and ("Reel in: " .. key) or "Click the bobber", "accent"
	elseif LootOpen() then
		text, role = "Looting", "textMuted"
	elseif not key then
		text, role = "No key bound", "warning"
	elseif InCombatLockdown() then
		text, role = "In combat", "textMuted"
	else
		local action = NextAction()
		if action.kind == "toy" then
			icon = ToyIcon(action.item) or icon
			text = action.reason == "bobber" and "Bobber" or "Raft"
		elseif action.kind == "cast" or action.kind == "dismount" then
			text = "Cast"
		elseif action.reason == "unknown" then
			text = "Not learned"
		elseif action.reason == "mounted" then
			text = "Mounted"
		elseif action.reason == "swimming" then
			text = "Swimming"
		else
			text = ""
		end
		role = action.kind == "none" and "textMuted" or "text"
	end
	button.icon:SetTexture(icon)
	button.icon:SetDesaturated(role == "textMuted" and not fishing)
	button.label:SetText(text)
	UI.SetTextRole(button.label, role)
end

local function Tick()
	if holder and holder:IsShown() then
		UpdateLook()
	elseif ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- Shows or hides the holder (out of combat: it's protected) and redraws it.
function ns.FishingKey_Refresh()
	if not holder then
		return
	end
	if not InCombatLockdown() then
		local show = module.active and (db.button.shown or ns.EditMode_Active())
		holder:SetShown(show and true or false)
		if show and not ticker then
			ticker = C_Timer.NewTicker(TICK, Tick)
		end
	end
	UpdateLook()
end

function ns.FishingKey_Relayout()
	if holder and not InCombatLockdown() then
		ApplyLayout()
	end
end

function ns.FishingKey_ResetPosition()
	local f = db.button.frame
	f.point, f.relPoint, f.x, f.y = "CENTER", "CENTER", 0, -180
	ns.FishingKey_Relayout()
end

ns.EditMode_Register({
	name = "Fishing button",
	frame = function()
		return holder
	end,
	refresh = function()
		ns.FishingKey_Refresh()
	end,
	saved = function()
		local point, _, relPoint, x, y = holder:GetPoint()
		local f = db.button.frame
		f.point, f.relPoint, f.x, f.y = point, relPoint, x, y
	end,
})

-- Events -------------------------------------------------------------------------------------------------------

local function StartReel()
	if not InCombatLockdown() then
		ns.FishingHelpers_Start()
	end
	Wait("reel")
end

local function StopFishing()
	fishing = false
	ns.FishingHelpers_Stop()
	Wait("clear")
	ns.FishingKey_Refresh()
end

function keyEvents:UNIT_SPELLCAST_CHANNEL_START(unit, _, spellID)
	if unit ~= "player" or IsSecret(spellID) then
		return
	end
	local name = spellID and C_Spell.GetSpellName(spellID)
	if not ns.Fishing_IsFishingSpell(spellID, name, FishingName()) then
		return
	end
	fishing = true
	if Engaged() then
		StartReel()
	end
	ns.FishingKey_Refresh()
end

-- Every stop while fishing (or with an override left) cleans up, even without a matching start (reload, zoning).
function keyEvents:UNIT_SPELLCAST_CHANNEL_STOP(unit)
	if unit ~= "player" or not (fishing or next(overridden)) then
		return
	end
	StopFishing()
end

-- Fires just before the combat lockdown starts: the last moment bindings, attributes and secure CVars can change.
-- In combat the key does nothing; clicking the bobber with the mouse still works.
function keyEvents:PLAYER_REGEN_DISABLED()
	waiter:Hide()
	ClearReel()
	if button then
		SetMacro("")
	end
	ns.FishingHelpers_Stop()
	ns.FishingKey_Refresh()
end

function keyEvents:PLAYER_REGEN_ENABLED()
	if not holder then
		Create()
	end
	if fishing and ChannelRunning() and Engaged() then
		StartReel()
	elseif fishing then
		StopFishing()
	end
	ns.FishingKey_Refresh()
end

function keyEvents:ADDON_RESTRICTION_STATE_CHANGED()
	if fishing and not next(overridden) and Engaged() then
		StartReel() -- a cast that started under a restriction
	elseif not fishing and next(overridden) and not waiter:IsShown() then
		Wait("clear") -- an override the waiter gave up on while a restriction lasted
	end
end

-- A key bound mid-cast gets the override (and the CVars, which weren't set while nothing was engaged). An override
-- already in place stays on its keys until the cast ends (the keys are read again then): reading the bindings while
-- our own override sits on them isn't reliable.
function keyEvents:UPDATE_BINDINGS()
	if fishing and not next(overridden) and GetBindingKey(BINDING) and Engaged() then
		StartReel()
	end
	ns.FishingKey_Refresh()
end

-- After a /reload mid-cast the override is gone: set it again.
function keyEvents:PLAYER_ENTERING_WORLD()
	local name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
	if not IsSecret(name) and not IsSecret(spellID) and name
		and ns.Fishing_IsFishingSpell(spellID, name, FishingName()) then
		fishing = true
		if Engaged() then
			StartReel()
		end
	elseif fishing and not IsSecret(name) then
		StopFishing() -- the channel ended during a loading screen without a stop event: restore the CVars
		return
	end
	ns.FishingKey_Refresh()
end

function keyEvents:PLAYER_LEAVING_WORLD()
	waiter:Hide()
	if not InCombatLockdown() then
		ClearReel()
	end
end

function keyEvents:LOOT_OPENED()
	lootOpen = GetTime()
	ns.FishingKey_Refresh()
end
keyEvents.LOOT_READY = keyEvents.LOOT_OPENED

function keyEvents:LOOT_CLOSED()
	lootOpen = nil
	ns.FishingKey_Refresh()
end

local EVENTS = {
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD",
	"PLAYER_LEAVING_WORLD", "LOOT_OPENED", "LOOT_READY", "LOOT_CLOSED",
}

-- API ---------------------------------------------------------------------------------------------------------------

function ns.Fishing_IsFishing()
	return fishing
end

-- For /tomte fishing status.
function ns.FishingKey_Status()
	return { fishing = fishing, lootOpen = LootOpen(), overridden = #overridden > 0, overriddenKeys = overridden }
end

function ns.FishingKey_Init(moduleDB, owner)
	db, module = moduleDB, owner
	if not InCombatLockdown() then -- otherwise at PLAYER_REGEN_ENABLED (a /reload in combat)
		Create()
	end
	keyEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function ns.FishingKey_Toggle(active)
	if active then
		for _, event in ipairs(EVENTS) do
			keyEvents:RegisterEvent(event)
		end
		keyEvents:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
		keyEvents:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		keyEvents:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED") -- new in 12.0.0
	else
		keyEvents:UnregisterAllEvents()
		keyEvents:RegisterEvent("PLAYER_REGEN_ENABLED") -- creates the button after a /reload in combat
		waiter:Hide()
		fishing = false
		if not InCombatLockdown() then
			ClearReel()
			if button then
				button:SetAttribute("type", nil)
			end
		end
		ns.FishingHelpers_Stop()
	end
	ns.FishingKey_Refresh()
end

_G["BINDING_NAME_" .. BINDING] = "Fishing (cast / reel in)"
