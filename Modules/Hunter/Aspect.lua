local addonName, ns = ...

-- Hunter Pets on World of Warcraft: Forever: the aspect button. One click (or the "Put on your aspect" key binding)
-- casts the aspect it shows:
--   no aspect on: Hawk (Monkey before it), out of combat;
--   travelling (on the move a while, sooner when the quest you're heading for is far; nothing to fight targeted, not
--   in a dungeon): Cheetah, if you know it;
--   Cheetah or Pack on close to the quest you'll fight at, with something to fight targeted, or as a fight starts:
--   Hawk (they daze you when you're hit).
-- The quest you're heading for is the game's super-tracked quest (the Quest list's follow, a clicked quest), with its
-- distance (C_QuestLog.GetDistanceSqToQuest); a finished one is a hand-in, nothing to fight. In an inn or a city only
-- Cheetah; never mounted, on a flight or dead. Casting is protected, so the button is secure and only
-- changes out of combat: PLAYER_REGEN_DISABLED, just before the lockdown, is the last moment to show or hide it. A
-- button shown for a fight stays up through it and fades once Hawk is on. Rules in Data.lua (Hunter_AspectToCast);
-- registered in Hunter.lua. Forever only: not in the retail TOC.

local BUTTON_NAME = "TomteHunterAspect"
local SIZE = 40
local LABEL_GAP = 3
local UPDATE_DELAY = 0.2 -- seconds: an aspect swap is a burst of aura events
local STOP_GRACE = 3 -- seconds standing still before travelling ends (stopping to loot or turn doesn't)
local MOVE_TICK = 1 -- seconds between checks while you're on the move (how long you've run, how close the quest is)
local DEFAULT_POINT = { point = "CENTER", relPoint = "CENTER", x = 0, y = -140 }
-- Per kind of suggestion: the label under the icon, its color role and the tooltip's line.
local KINDS = {
	none = { label = "No aspect", role = "warning", tip = "No aspect is on. Click to put it on." },
	travel = { label = "Travelling", role = "info", tip = "You're travelling. Click for Aspect of the Cheetah; Tomte "
		.. "reminds you to swap back when you target something to fight." },
	fight = { label = "Swap aspect", role = "danger", tip = "Cheetah and Pack daze you when you're hit. Click to swap "
		.. "before the fight." },
	arrive = { label = "Nearly there", role = "warning", tip = "You're close to your quest. Cheetah and Pack daze you "
		.. "when you're hit: click to swap before the fight." },
}

local UI = ns.UI
local IsSecret = ns.IsSecret

local db, button
local active = false
local updatePending = false
local movingSince -- GetTime when you started moving, nil while standing still
local stopTimer, moveTicker
local events = ns.NewEvents()
local OWNER = "hunterAspect"

-- The aspect on, as the rank 1 ID in HUNTER_ASPECTS; false for none, nil when the buffs can't be read right now.
local function AspectOn()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
		return nil
	end
	for _, id in ipairs(ns.HUNTER_ASPECTS) do
		local name = C_Spell.GetSpellName(id)
		if name then
			local aura = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
			if IsSecret(aura) then
				return nil
			end
			if aura then
				return id
			end
		end
	end
	return false
end

-- Your target is something alive you could fight (a secret answer counts as no).
local function Hostile()
	if not UnitExists("target") then
		return false
	end
	local attackable, dead = UnitCanAttack("player", "target"), UnitIsDeadOrGhost("target")
	if IsSecret(attackable, dead) then
		return false
	end
	return attackable and not dead or false
end

-- The quest you're heading for: { yards, fight } (fight: it isn't finished, so it's something to do there, not a
-- hand-in), or nil without a super-tracked quest on this continent.
local function Destination()
	local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	if not questID or questID == 0 or IsSecret(questID) then
		return nil
	end
	local distSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
	if not distSq or not onContinent or IsSecret(distSq) then
		return nil
	end
	-- Without IsComplete on this client every quest counts as one to do there.
	local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
	return { yards = math.sqrt(distSq), fight = not done }
end

local function Situation(combat)
	local dest = Destination()
	local known = {}
	for _, id in ipairs(ns.HUNTER_ASPECT_BEST) do
		known[id] = ns.SpellKnown(id)
	end
	known[ns.HUNTER_ASPECT_CHEETAH] = ns.SpellKnown(ns.HUNTER_ASPECT_CHEETAH)
	return {
		known = known,
		on = AspectOn(),
		combat = combat,
		dead = UnitIsDeadOrGhost("player"),
		resting = IsResting(),
		mounted = IsMounted(),
		taxi = UnitOnTaxi("player"),
		travelling = ns.Hunter_Travelling(movingSince and GetTime() - movingSince, dest),
		hostile = Hostile(),
		inInstance = IsInInstance(),
		dest = dest,
		travel = db.aspectTravel,
	}
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(self.spellName or "Aspect")
	UI.TipLine(KINDS[self.kind or "none"].tip, "text", true)
	GameTooltip:Show()
end

-- Out of combat only: protected frames can't be made in combat.
local function CreateButton()
	button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetMovable(true)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("LeftButtonDown")
	button:SetAttribute("useOnKeyDown", true)
	button:SetAttribute("type", "spell")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	UI.ActionIcon(button, button.icon, SIZE)
	button.label = UI.Text(button, 11, "warning", "label")
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -LABEL_GAP)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetPoint(db.aspectFrame.point, UIParent, db.aspectFrame.relPoint, db.aspectFrame.x, db.aspectFrame.y)
	button:Hide()
end

-- Out of combat (or in PLAYER_REGEN_DISABLED, before the lockdown): the button shows spellID for kind, or hides.
local function Apply(spellID, kind)
	if not spellID then
		if button then
			button:Hide()
		end
		return
	end
	if not button then
		CreateButton()
	end
	-- By name, without a rank: the game casts the highest rank you know.
	button.spellName = C_Spell.GetSpellName(spellID)
	button.kind = kind
	button:SetAttribute("spell", button.spellName)
	button.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
	button.label:SetText(KINDS[kind].label)
	UI.SetTextRole(button.label, KINDS[kind].role)
	button:SetAlpha(1)
	button:Show()
end

local function Update()
	if InCombatLockdown() then
		return
	end
	if not (active and db.aspect) then
		Apply(nil)
	elseif ns.EditMode_Active() then
		Apply(ns.HUNTER_ASPECT_BEST[1], "none")
	else
		Apply(ns.Hunter_AspectToCast(Situation(false)))
	end
end

local function UpdateSoon()
	if updatePending then
		return
	end
	updatePending = true
	C_Timer.After(UPDATE_DELAY, function()
		updatePending = false
		Update()
	end)
end

local function CancelTimer(timer)
	if timer then
		timer:Cancel()
	end
end

-- Moving and stopping: while you're on the move the button checks every MOVE_TICK (how long you've run, how close the
-- quest is now); the run ends STOP_GRACE after you stop. Nothing ticks while you stand still.
local function StartedMoving()
	CancelTimer(stopTimer)
	stopTimer = nil
	if movingSince then
		return
	end
	movingSince = GetTime()
	CancelTimer(moveTicker)
	moveTicker = C_Timer.NewTicker(MOVE_TICK, UpdateSoon)
end

local function StoppedMoving()
	CancelTimer(stopTimer)
	stopTimer = C_Timer.NewTimer(STOP_GRACE, function()
		stopTimer = nil
		movingSince = nil
		CancelTimer(moveTicker)
		moveTicker = nil
		UpdateSoon()
	end)
end

local WATCHED = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "PLAYER_MOUNT_DISPLAY_CHANGED",
	"PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_DEAD", "SPELLS_CHANGED",
	"PLAYER_TARGET_CHANGED" }
-- Another quest followed, or the followed one finished (a hand-in now). TryWatch: an event this client hasn't got.
local QUEST_EVENTS = { "SUPER_TRACKING_CHANGED", "QUEST_LOG_UPDATE" }
for _, event in ipairs(WATCHED) do
	events:On(OWNER, event, UpdateSoon)
end
for _, event in ipairs(QUEST_EVENTS) do
	events:On(OWNER, event, UpdateSoon)
end
events:On(OWNER, "PLAYER_STARTED_MOVING", StartedMoving)
events:On(OWNER, "PLAYER_STOPPED_MOVING", StoppedMoving)

-- In a fight the button can't change; once Hawk (or anything but Cheetah and Pack) is on, it fades. Alpha isn't
-- protected, the rest waits for PLAYER_REGEN_ENABLED.
events:On(OWNER, "UNIT_AURA", function()
	if not InCombatLockdown() then
		UpdateSoon()
	elseif button and button:IsShown() then
		local on = AspectOn()
		if on and not ns.HUNTER_ASPECT_TRAVEL[on] then
			button:SetAlpha(0)
		end
	end
end)

-- Fires just before the lockdown starts: the last moment a secure button can show, hide or change its spell. Cheetah
-- or Pack on (or no aspect) as the fight starts: Hawk, shown for the whole fight. A fight ends the run.
events:On(OWNER, "PLAYER_REGEN_DISABLED", function()
	movingSince = nil
	CancelTimer(moveTicker)
	moveTicker = nil
	if active and db.aspect then
		Apply(ns.Hunter_AspectToCast(Situation(true)))
	elseif button then
		button:Hide()
	end
end)

ns.EditMode_Register({
	name = "Aspect button",
	frame = function()
		return button
	end,
	refresh = Update,
	saved = function()
		local point, _, relPoint, x, y = button:GetPoint()
		db.aspectFrame.point, db.aspectFrame.relPoint, db.aspectFrame.x, db.aspectFrame.y = point, relPoint, x, y
	end,
	module = "hunter",
	reset = function()
		db.aspectFrame.point, db.aspectFrame.relPoint = DEFAULT_POINT.point, DEFAULT_POINT.relPoint
		db.aspectFrame.x, db.aspectFrame.y = DEFAULT_POINT.x, DEFAULT_POINT.y
		if button and not InCombatLockdown() then
			button:ClearAllPoints()
			button:SetPoint(db.aspectFrame.point, UIParent, db.aspectFrame.relPoint, db.aspectFrame.x, db.aspectFrame.y)
		end
	end,
})

function ns.HunterAspect_Update()
	UpdateSoon()
end

-- For /tomte hunter aspect: what the button sees.
function ns.HunterAspect_Why()
	local s = Situation(InCombatLockdown())
	local known = {}
	for id, isKnown in pairs(s.known) do
		known[#known + 1] = ("%s %s"):format(tostring(C_Spell.GetSpellName(id)), isKnown and "known" or "not known")
	end
	table.sort(known)
	local cast, kind = ns.Hunter_AspectToCast(s)
	local on = s.on == nil and "unreadable" or s.on and C_Spell.GetSpellName(s.on) or "none"
	local moved = movingSince and ("%.0f s"):format(GetTime() - movingSince) or "standing"
	local dest = s.dest and ("%d yards, %s"):format(s.dest.yards, s.dest.fight and "to do" or "hand-in") or "none"
	ns.Print(("Aspect: %s. On: %s. Combat %s, dead %s, resting %s, mounted %s, flying %s, moving %s, travelling %s, "
		.. "followed quest %s, target to fight %s, dungeon %s. The button: %s."):format(table.concat(known, ", "),
		tostring(on), tostring(s.combat), tostring(s.dead), tostring(s.resting), tostring(s.mounted), tostring(s.taxi),
		moved, tostring(s.travelling), dest, tostring(s.hostile), tostring(s.inInstance),
		cast and ("%s (%s)"):format(tostring(C_Spell.GetSpellName(cast)), kind) or "hidden"))
end

function ns.HunterAspect_Start(moduleDB)
	db = moduleDB
	active = true
	for _, event in ipairs(WATCHED) do
		events:Watch(OWNER, event)
	end
	for _, event in ipairs({ "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", unpack(QUEST_EVENTS) }) do
		events:TryWatch(OWNER, event)
	end
	events:Watch(OWNER, "PLAYER_REGEN_DISABLED")
	events:Watch(OWNER, "UNIT_AURA", "player")
	UpdateSoon()
end

function ns.HunterAspect_Stop()
	active = false
	events:UnwatchAll(OWNER)
	CancelTimer(stopTimer)
	CancelTimer(moveTicker)
	stopTimer, moveTicker, movingSince = nil, nil, nil
	if InCombatLockdown() then
		events:Watch(OWNER, "PLAYER_REGEN_ENABLED") -- a secure button can't hide until the fight ends
	else
		Update()
	end
end
