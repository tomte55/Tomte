# Weekly board: Factions, Activities, Raids Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Plumber-inspired Factions, Activities and Raids tabs to Tomte's Weekly board, drawn in Tomte's panel style.

**Architecture:** Each tab is a pure model in a `*Data.lua` file (no WoW API, unit-tested with plain Lua) plus a thin
reader that calls the WoW API and a view file that draws the model into its own `UI.Scroll`. The board page
(`BoardPage.lua`) gains three view keys and switches between view objects. A reusable ring widget (`Ring.lua`) draws
progress rings with a Cooldown swipe and is proven in game (Task 1) before anything builds on it.

**Tech Stack:** WoW retail 12.1 Lua (Lua 5.1 in game), plain Lua 5.4 for tests (`lua Tomte/tests/test_*.lua`, run
from the AddOns folder), Tomte's `ns.UI` widgets and `ns.HomeKit`.

**Spec:** `docs/superpowers/specs/2026-10-06-tomte-weekly-factions-activities-raids-design.md`

## Global Constraints

- Base: this plan builds on the This week overhaul (`Weekly_BoardModel`, `WeekView.lua`, `ns.WeeklyRows`,
  `Vault.lua`) from branch `ccr-b8e9c49f-kx5b3x`. Execute on that branch after the user has confirmed that work in
  game and it is committed (or on main once it is merged). Check with `git log --oneline -5` and
  `ls Tomte/Modules/Weekly/WeekView.lua` before Task 1.
- Client: retail 12.1.0, TOC `## Interface: 120100`. Check warcraft.wiki.gg before using any API not already named in
  this plan; every API below was seen working in Plumber's 12.x code (`Plumber/Modules/ExpansionLandingPage`).
- No globals: everything on `ns`. Every new file goes into `Tomte/Tomte.toc` in the order given in its task.
- Expansion key: `GetExpansionLevel()` (10 = The War Within, 11 = Midnight). The user does not own Midnight; their
  content is The War Within. Hand-kept tables are keyed by this number and only need `[10]` now.
- Lua string paths need doubled backslashes (`"Interface\\Icons\\X"`); WoW's Lua silently drops `\I`.
- Tests are plain Lua: `lua Tomte/tests/test_<name>.lua` from `D:\World of Warcraft\_retail_\Interface\AddOns`,
  must print `all passed` (copy the `test`/`eq` helpers from `Tomte/tests/test_weekly.lua`). Also run
  `for f in $(find Tomte -name '*.lua'); do luac -p "$f" || echo "SYNTAX: $f"; done`.
- Claude can't run WoW. In-game checks are steps where the user does `/reload` and reports. Commit only after the
  user confirms in game (project rule); the commit steps below say so.
- Commit messages start with `Tomte: ` and say what the user gets, like the existing history.

## Review Focus

- A faction whose emblem atlas doesn't exist (new patch, odd textureKit): expect the question-mark icon, not a blank
  ring or an error. Tested in Task 2 (`Weekly_FactionAtlas` fallback) and checked in Task 1's probe.
- Maxed renown with and without paragon, and a paragon reward waiting: ring full/gold vs paragon progress vs glow.
  Tested in Task 2.
- A character below max level or with no data yet (no renown unlocked, no learned quests, no raid kills): every tab
  shows a one-line grey note instead of an empty page. Tested in Tasks 2, 4 and 6 (empty inputs).
- The Encounter Journal open while the Raids tab reads it: Blizzard's journal must not jump difficulty. Task 6
  restores `EJ_GetDifficulty()` and mutes `EncounterJournal` events for one frame; in-game check in Task 6.
- Hide completed with every group done: expect "Everything here is done this week." not an empty list. Tested in
  Task 4.

---

## File Structure

| File | Responsibility |
|---|---|
| `Tomte/Modules/Weekly/Ring.lua` (new) | `ns.WeeklyRing_Create(parent, size)`: circle track, Cooldown swipe progress, inner disc, emblem/portrait, level badge, glow |
| `Tomte/Modules/Weekly/FactionData.lua` (new) | Pure: sub-faction table, ring values, detail texts, reward track, atlas name |
| `Tomte/Modules/Weekly/Factions.lua` (new) | Reader (C_MajorFactions, C_Reputation, C_GossipInfo) and the Factions view |
| `Tomte/Modules/Weekly/ActivityData.lua` (new) | Pure: curated War Within list, activity model, resource list |
| `Tomte/Modules/Weekly/Activities.lua` (new) | Reader (quest flags, quest line, currencies) and the Activities view |
| `Tomte/Modules/Weekly/RaidData.lua` (new) | Pure: raid IDs, difficulties, raid model |
| `Tomte/Modules/Weekly/Raids.lua` (new) | Reader (EJ_*, C_RaidLocks) and the Raids view |
| `Tomte/Modules/Weekly/Collect.lua` | Learned quests remember their quest log header (`group`); `BOSS_KILL` refreshes |
| `Tomte/Modules/Weekly/Data.lua` | `Weekly_BoardModel` drops Renown from `progress` |
| `Tomte/Modules/Weekly/BoardPage.lua` | Six tabs; one view object per tab key |
| `Tomte/Modules/Weekly/Weekly.lua` | Defaults `hideCompleted = true`, `raidCollapsed = {}`, `faction = nil`; the `ring` probe command (Task 1, removed in Task 7) |
| `Tomte/tests/test_factions.lua`, `test_activities.lua`, `test_raids.lua` (new) | Model tests |

TOC order (after `Modules/Weekly/Vault.lua`): `Ring.lua`, `FactionData.lua`, `ActivityData.lua`, `RaidData.lua`,
then after `WeekView.lua`: `Factions.lua`, `Activities.lua`, `Raids.lua`.

---

### Task 1: Ring widget, proven in game

**Files:**
- Create: `Tomte/Modules/Weekly/Ring.lua`
- Modify: `Tomte/Tomte.toc` (add `Modules/Weekly/Ring.lua` after `Modules/Weekly/Vault.lua`)
- Modify: `Tomte/Modules/Weekly/Weekly.lua` (temporary `ring` command)

**Interfaces:**
- Produces: `ns.WeeklyRing_Create(parent, size) -> ring` with `ring:SetProgress(frac)` (0-1),
  `ring:SetColor(r, g, b)`, `ring:SetAtlas(atlas)`, `ring:SetFile(fileID)`, `ring:SetPortrait(creatureDisplayID)`,
  `ring:SetBadge(text)` (nil hides), `ring:SetGlow(on)`, `ring:SetSelected(on)`; `ring` is a Button (scripts
  `OnEnter`/`OnLeave`/`OnClick` set by callers).

- [ ] **Step 1: Write `Ring.lua`**

```lua
local addonName, ns = ...

-- A progress ring around an emblem (Factions tab): a dim circle track, the progress as a Cooldown swipe of a filled
-- circle, an inner disc on top that leaves only a ring showing, the emblem (atlas, file or creature portrait) in the
-- middle, a level badge under it and an optional pulsing glow (a paragon reward waiting).

local UI = ns.UI
local GOLD = UI.GOLD
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local REVERSE = true -- measured in Task 1 step 3; flip if a 25% ring shows three quarters

local function Disc(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetTexture(CIRCLE)
	t:SetVertexColor(r, g, b, a)
	return t
end

function ns.WeeklyRing_Create(parent, size)
	local ring = CreateFrame("Button", nil, parent)
	ring:SetSize(size, size)
	local thick = math.max(math.floor(size * 0.08 + 0.5), 3)

	ring.glow = Disc(ring, "BACKGROUND", GOLD[1], GOLD[2], GOLD[3], 0.45)
	ring.glow:SetPoint("CENTER")
	ring.glow:SetSize(size * 1.3, size * 1.3)
	ring.glow:Hide()
	local pulse = ring.glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.25)
	fade:SetToAlpha(0.9)
	fade:SetDuration(0.9)
	ring.pulse = pulse

	ring.track = Disc(ring, "BORDER", 1, 1, 1, 0.12)
	ring.track:SetAllPoints()

	ring.cd = CreateFrame("Cooldown", nil, ring)
	ring.cd:SetAllPoints()
	ring.cd:SetSwipeTexture(CIRCLE)
	ring.cd:SetDrawEdge(false)
	ring.cd:SetDrawBling(false)
	ring.cd:SetHideCountdownNumbers(true)
	ring.cd:SetReverse(REVERSE)
	ring.cd:SetUseCircularEdge(true)

	ring.inner = CreateFrame("Frame", nil, ring)
	ring.inner:SetPoint("TOPLEFT", thick, -thick)
	ring.inner:SetPoint("BOTTOMRIGHT", -thick, thick)
	ring.inner:SetFrameLevel(ring.cd:GetFrameLevel() + 2)
	ring.disc = Disc(ring.inner, "BACKGROUND", 0.09, 0.09, 0.1, 1)
	ring.disc:SetAllPoints()
	ring.icon = ring.inner:CreateTexture(nil, "ARTWORK")
	ring.icon:SetPoint("CENTER")
	local inner = size - 2 * thick
	ring.icon:SetSize(inner * 0.86, inner * 0.86)
	ring.mask = ring.inner:CreateMaskTexture()
	ring.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	ring.mask:SetAllPoints(ring.inner)

	ring.badge = CreateFrame("Frame", nil, ring)
	ring.badge:SetFrameLevel(ring.inner:GetFrameLevel() + 2)
	ring.badge:SetSize(math.max(size * 0.32, 18), math.max(size * 0.22, 14))
	ring.badge:SetPoint("CENTER", ring, "BOTTOM", 0, thick)
	local bbg = ring.badge:CreateTexture(nil, "BACKGROUND")
	bbg:SetAllPoints()
	bbg:SetColorTexture(0.07, 0.07, 0.08, 1)
	UI.Border(ring.badge, GOLD[1], GOLD[2], GOLD[3], 0.7)
	ring.badge.text = ring.badge:CreateFontString(nil, "OVERLAY")
	ring.badge.text:SetFont(ns.HomeKit.NARROW_FONT, math.max(math.floor(size * 0.16), 11), "")
	ring.badge.text:SetPoint("CENTER", 0, 0)
	ring.badge.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

	ring.selected = Disc(ring, "BACKGROUND", 1, 1, 1, 0.18)
	ring.selected:SetPoint("CENTER")
	ring.selected:SetSize(size + 8, size + 8)
	ring.selected:Hide()

	function ring:SetProgress(frac)
		frac = math.min(math.max(frac or 0, 0), 1)
		if frac <= 0 then
			self.cd:Hide()
			return
		end
		self.cd:Show()
		-- 100 "seconds" of which frac have passed, frozen: Blizzard's CooldownFrame_SetDisplayAsPercentage does this.
		self.cd:SetCooldown(GetTime() - 100 * frac, 100)
		self.cd:Pause()
	end

	function ring:SetColor(r, g, b)
		self.cd:SetSwipeColor(r, g, b, 1)
	end

	local function ClearIcon(self)
		self.icon:RemoveMaskTexture(self.mask)
		self.icon:SetTexCoord(0, 1, 0, 1)
	end

	function ring:SetAtlas(atlas)
		ClearIcon(self)
		self.icon:SetAtlas(atlas)
	end

	function ring:SetFile(fileID)
		ClearIcon(self)
		self.icon:SetTexture(fileID)
		self.icon:AddMaskTexture(self.mask)
	end

	function ring:SetPortrait(displayID)
		ClearIcon(self)
		SetPortraitTextureFromCreatureDisplayID(self.icon, displayID)
		self.icon:AddMaskTexture(self.mask)
	end

	function ring:SetBadge(text)
		self.badge:SetShown(text ~= nil)
		self.badge.text:SetText(text or "")
		self.badge:SetWidth(math.max(self.badge.text:GetUnboundedStringWidth() + 10, self.badge:GetHeight() + 4))
	end

	function ring:SetGlow(on)
		self.glow:SetShown(on)
		if on then
			self.pulse:Play()
		else
			self.pulse:Stop()
		end
	end

	function ring:SetSelected(on)
		self.selected:SetShown(on)
	end

	ring:SetColor(GOLD[1], GOLD[2], GOLD[3])
	ring:SetProgress(0)
	ring:SetBadge(nil)
	return ring
end
```

- [ ] **Step 2: Add a temporary probe command** in `Weekly.lua`'s `commands` list (it's removed in Task 7):

```lua
		{ "ring", "(test) show three progress rings", function()
			local f = ns.weeklyRingProbe
			if not f then
				f = CreateFrame("Frame", nil, UIParent)
				f:SetSize(360, 140)
				f:SetPoint("CENTER")
				local bg = f:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints()
				bg:SetColorTexture(0.06, 0.06, 0.07, 0.95)
				local kit = C_MajorFactions.GetMajorFactionData(2590)
				for i, frac in ipairs({ 0.25, 0.6, 1 }) do
					local r = ns.WeeklyRing_Create(f, 88)
					r:SetPoint("LEFT", 20 + (i - 1) * 115, 0)
					r:SetProgress(frac)
					r:SetBadge(tostring(i * 7))
					if kit and kit.textureKit then
						r:SetAtlas(("majorfactions_icons_%s512"):format(kit.textureKit))
					end
				end
				ns.WeeklyRing_Create(f, 40):SetPoint("TOPRIGHT", -8, -8)
				f:EnableMouse(true)
				f:SetScript("OnMouseUp", f.Hide)
				ns.weeklyRingProbe = f
			end
			f:SetShown(not f:IsShown())
		end },
```

- [ ] **Step 3: In-game probe (user)**

Ask the user: "`/reload`, then `/tomte weekly ring`. You should see three rings with the Council of Dornogal emblem:
a quarter ring (from 12 o'clock clockwise), about 60%, and a full ring, with badges 7, 14, 21, plus a small empty
ring top right. Click the box to close it. Tell me: does the 25% ring show a quarter or three quarters? Does the
emblem show? Any BugSack error?"

- If it shows three quarters: set `REVERSE = false` in `Ring.lua` and ask again.
- If the swipe is square instead of round: remove `SetUseCircularEdge` and check the swipe texture path.
- If the emblem is blank: `/dump C_MajorFactions.GetMajorFactionData(2590).textureKit` and
  `/dump C_Texture.GetAtlasInfo("majorfactions_icons_" .. C_MajorFactions.GetMajorFactionData(2590).textureKit .. "512")`;
  fix the atlas pattern in Task 2's `Weekly_FactionAtlas` to what exists.

Record what was measured in the comment on `REVERSE`. Do not continue until the rings look right.

- [ ] **Step 4: Syntax check**

Run: `for f in $(find Tomte -name '*.lua'); do luac -p "$f" || echo "SYNTAX: $f"; done`
Expected: no output.

- [ ] **Step 5: Commit (after the user confirmed the probe)**

```bash
git add Tomte/Modules/Weekly/Ring.lua Tomte/Modules/Weekly/Weekly.lua Tomte/Tomte.toc
git commit -m "Tomte: progress ring widget for the Weekly board (probe command /tomte weekly ring)"
```

---

### Task 2: Faction model (pure)

**Files:**
- Create: `Tomte/Modules/Weekly/FactionData.lua` (TOC: after `Ring.lua`)
- Test: `Tomte/tests/test_factions.lua`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `ns.WEEKLY_SUBFACTIONS[expansion][parentID] = { { id, icon = fileID } | { id, display = creatureDisplayID } }`
  - `ns.Weekly_FactionAtlas(textureKit, atlasExists) -> atlas | nil` (`atlasExists(name) -> bool`)
  - `ns.Weekly_FactionRing(rec) -> { frac, badge, color = "gold" | "blue" | "white", glow }`
  - `ns.Weekly_FactionDetail(rec) -> { title, line1, line2 }`
  - `ns.Weekly_RewardTrack(rec, levels, rewardsFor) -> { { level, earned, rewards = { { name, icon } } } }`
  - `ns.Weekly_FactionLayout(recs) -> { { rec, subs = { rec } } }` (parents in name order, subs in table order)
  - A faction record `rec` (built by Task 3's reader):
    `{ id, name, renown = bool, level, max, earned, threshold, paragon = { value, threshold, pending } | nil, kit,
    icon, display, standing }` (`standing` is the text for non-renown reputations, like "Rank 3" or "Honored").

- [ ] **Step 1: Write the failing test** `Tomte/tests/test_factions.lua`

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_factions.lua
local ns = {}
assert(loadfile("Tomte/Modules/Weekly/FactionData.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local function Rec(over)
	local r = { id = 2590, name = "Council of Dornogal", renown = true, level = 7, max = 25, earned = 1737,
		threshold = 2500, kit = "Dornogal" }
	for k, v in pairs(over or {}) do
		r[k] = v
	end
	return r
end

test("ring: renown in progress", function()
	local ring = ns.Weekly_FactionRing(Rec())
	eq(ring.frac, 1737 / 2500)
	eq(ring.badge, "7")
	eq(ring.color, "blue")
	eq(ring.glow, false)
end)

test("ring: maxed without paragon is full and gold", function()
	local ring = ns.Weekly_FactionRing(Rec({ level = 25, earned = 0 }))
	eq(ring.frac, 1)
	eq(ring.color, "gold")
end)

test("ring: paragon progress and a waiting reward", function()
	local ring = ns.Weekly_FactionRing(Rec({ level = 25, paragon = { value = 2500, threshold = 10000, pending = true } }))
	eq(ring.frac, 0.25)
	eq(ring.color, "gold")
	eq(ring.glow, true)
end)

test("ring: plain reputation uses its standing", function()
	local ring = ns.Weekly_FactionRing({ id = 2669, name = "Darkfuse", renown = false, level = 3, earned = 500,
		threshold = 1000 })
	eq(ring.badge, "3")
	eq(ring.frac, 0.5)
	eq(ring.color, "white")
end)

test("ring: zero threshold doesn't divide by zero", function()
	eq(ns.Weekly_FactionRing(Rec({ threshold = 0 })).frac, 0)
end)

test("detail texts", function()
	local d = ns.Weekly_FactionDetail(Rec())
	eq(d.title, "Council of Dornogal")
	eq(d.line1, "Renown 7/25")
	eq(d.line2, "763 until next level")
	eq(ns.Weekly_FactionDetail(Rec({ level = 25 })).line2, "Max renown")
	eq(ns.Weekly_FactionDetail(Rec({ level = 25, paragon = { value = 4200, threshold = 10000 } })).line2,
		"Paragon 4,200 / 10,000")
	eq(ns.Weekly_FactionDetail(Rec({ level = 25, paragon = { value = 10000, threshold = 10000, pending = true } })).line2,
		"Paragon reward waiting")
	eq(ns.Weekly_FactionDetail({ name = "Darkfuse", renown = false, standing = "Rank 3", earned = 500, threshold = 1000 }).line1,
		"Rank 3")
end)

test("atlas: kit pattern, missing atlas falls back", function()
	local exists = function(name)
		return name == "majorfactions_icons_Dornogal512"
	end
	eq(ns.Weekly_FactionAtlas("Dornogal", exists), "majorfactions_icons_Dornogal512")
	eq(ns.Weekly_FactionAtlas("Nope", exists), nil)
	eq(ns.Weekly_FactionAtlas(nil, exists), nil)
end)

test("reward track: earned levels and rewards per level", function()
	local levels = { { level = 7 }, { level = 8 }, { level = 9 } }
	local track = ns.Weekly_RewardTrack(Rec(), levels, function(level)
		if level == 8 then
			return { { name = "Gem", icon = 1, uiOrder = 2 }, { name = "Pouch", icon = 2, uiOrder = 1 } }
		end
		return { { name = "Level " .. level, icon = 3 } }
	end)
	eq(#track, 3)
	eq(track[1].earned, true, "level 7 is earned at renown 7")
	eq(track[2].earned, false)
	eq(track[2].rewards[1].name, "Pouch", "uiOrder first")
end)

test("layout: parents by name, subs attached, subs not listed on their own", function()
	local recs = {
		Rec({ id = 2653, name = "Cartels of Undermine" }),
		Rec({ id = 2590, name = "Council of Dornogal" }),
		{ id = 2669, name = "Darkfuse", parent = 2653 },
		{ id = 2673, name = "Bilgewater", parent = 2653 },
	}
	local layout = ns.Weekly_FactionLayout(recs)
	eq(#layout, 2)
	eq(layout[1].rec.name, "Cartels of Undermine")
	eq(#layout[1].subs, 2)
	eq(layout[1].subs[1].name, "Darkfuse", "table order kept")
	eq(#layout[2].subs, 0)
	eq(#ns.Weekly_FactionLayout({}), 0)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
```

- [ ] **Step 2: Run it to see it fail**

Run: `lua Tomte/tests/test_factions.lua`
Expected: an error that `Tomte/Modules/Weekly/FactionData.lua` can't be opened.

- [ ] **Step 3: Write `FactionData.lua`**

```lua
local addonName, ns = ...

-- Factions tab: pure logic (tested with plain Lua). Records come from Factions.lua's reader; see the plan for the
-- record shape. Sub-factions (Undermine cartels, Severed Threads' three) aren't renown factions, so they're listed
-- by hand per expansion (GetExpansionLevel()); IDs and icons from Plumber's table, checked 2026-10-06.

local floor, min, max = math.floor, math.min, math.max

ns.WEEKLY_SUBFACTIONS = {
	[10] = {
		[2653] = { -- Cartels of Undermine
			{ id = 2669, icon = 6439629 }, -- Darkfuse Solutions
			{ id = 2673, icon = 6439627 }, -- Bilgewater
			{ id = 2677, icon = 6439630 }, -- Steamwheedle
			{ id = 2675, icon = 6439628 }, -- Blackwater
			{ id = 2671, icon = 6439631 }, -- Venture Company
		},
		[2600] = { -- The Severed Threads
			{ id = 2601, display = 116208 }, -- The Weaver
			{ id = 2605, display = 114775 }, -- The General
			{ id = 2607, display = 114268 }, -- The Vizier
		},
	},
}

local function Thousands(n)
	local text = tostring(floor(n or 0))
	local replaced
	repeat
		text, replaced = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until replaced == 0
	return text
end

local function Maxed(rec)
	return rec.renown and rec.max ~= nil and rec.level >= rec.max
end

function ns.Weekly_FactionAtlas(kit, atlasExists)
	if not kit then
		return nil
	end
	local atlas = ("majorfactions_icons_%s512"):format(kit)
	return atlasExists(atlas) and atlas or nil
end

-- Ring: progress inside the level (paragon progress once maxed), the badge and the colour.
function ns.Weekly_FactionRing(rec)
	local p = rec.paragon
	if Maxed(rec) then
		if p and (p.threshold or 0) > 0 then
			return { frac = min((p.value or 0) % p.threshold / p.threshold, 1), badge = tostring(rec.level), color = "gold",
				glow = p.pending == true }
		end
		return { frac = 1, badge = tostring(rec.level), color = "gold", glow = false }
	end
	local frac = (rec.threshold or 0) > 0 and min(max((rec.earned or 0) / rec.threshold, 0), 1) or 0
	return { frac = frac, badge = rec.level and tostring(rec.level) or nil, color = rec.renown and "blue" or "white",
		glow = p ~= nil and p.pending == true }
end

function ns.Weekly_FactionDetail(rec)
	local d = { title = rec.name or "?" }
	if not rec.renown then
		d.line1 = rec.standing or ""
		d.line2 = (rec.threshold or 0) > 0 and ("%s / %s"):format(Thousands(rec.earned), Thousands(rec.threshold)) or ""
		return d
	end
	d.line1 = rec.max and ("Renown %d/%d"):format(rec.level, rec.max) or ("Renown %d"):format(rec.level)
	local p = rec.paragon
	if Maxed(rec) then
		if p and p.pending then
			d.line2 = "Paragon reward waiting"
		elseif p and (p.threshold or 0) > 0 then
			d.line2 = ("Paragon %s / %s"):format(Thousands((p.value or 0) % p.threshold), Thousands(p.threshold))
			if (p.value or 0) % p.threshold == 0 and (p.value or 0) > 0 then
				d.line2 = ("Paragon %s / %s"):format(Thousands(p.threshold), Thousands(p.threshold))
			end
		else
			d.line2 = "Max renown"
		end
	else
		d.line2 = ("%s until next level"):format(Thousands((rec.threshold or 0) - (rec.earned or 0)))
	end
	return d
end

-- levels: C_MajorFactions.GetRenownLevels; rewardsFor(level): C_MajorFactions.GetRenownRewardsForLevel.
function ns.Weekly_RewardTrack(rec, levels, rewardsFor)
	local track = {}
	for _, info in ipairs(levels or {}) do
		local rewards = {}
		for _, r in ipairs(rewardsFor(info.level) or {}) do
			rewards[#rewards + 1] = { name = r.name or "?", icon = r.icon, uiOrder = r.uiOrder }
		end
		table.sort(rewards, function(a, b)
			if a.uiOrder and b.uiOrder and a.uiOrder ~= b.uiOrder then
				return a.uiOrder < b.uiOrder
			end
			return a.name < b.name
		end)
		track[#track + 1] = { level = info.level, earned = info.level <= (rec.level or 0), rewards = rewards }
	end
	return track
end

-- Parents in name order with their sub-factions (records with .parent) attached in the order they came.
function ns.Weekly_FactionLayout(recs)
	local byParent, parents = {}, {}
	for _, rec in ipairs(recs) do
		if rec.parent then
			byParent[rec.parent] = byParent[rec.parent] or {}
			table.insert(byParent[rec.parent], rec)
		else
			parents[#parents + 1] = rec
		end
	end
	table.sort(parents, function(a, b)
		return (a.name or "") < (b.name or "")
	end)
	local layout = {}
	for _, rec in ipairs(parents) do
		layout[#layout + 1] = { rec = rec, subs = byParent[rec.id] or {} }
	end
	return layout
end
```

Note on the paragon line: `value % threshold == 0` with a value right at the threshold means a full bar; the extra
`if` makes "10,000 / 10,000" show instead of "0 / 10,000". Keep it.

- [ ] **Step 4: Run the test**

Run: `lua Tomte/tests/test_factions.lua`
Expected: every line `ok`, last line `all passed`.

- [ ] **Step 5: Add to the TOC** after `Modules/Weekly/Ring.lua`: `Modules/Weekly/FactionData.lua`. Syntax check
  (Global Constraints command), expected no output.

- [ ] **Step 6: Commit**

```bash
git add Tomte/Modules/Weekly/FactionData.lua Tomte/tests/test_factions.lua Tomte/Tomte.toc
git commit -m "Tomte: faction model for the Weekly board (rings, paragon, reward track, sub-factions)"
```

---

### Task 3: Factions tab (reader + view) and the board's tab switch

**Files:**
- Create: `Tomte/Modules/Weekly/Factions.lua` (TOC: after `Modules/Weekly/WeekView.lua`)
- Modify: `Tomte/Modules/Weekly/BoardPage.lua` (VIEWS and `Layout`)
- Modify: `Tomte/Modules/Weekly/Data.lua` (`Weekly_BoardModel`: no Renown) and `Tomte/tests/test_weekly.lua`
- Saved: `ns.weeklyDB.faction` (the selected faction ID) needs no default; nil means "the first one".

**Interfaces:**
- Consumes: `ns.WeeklyRing_Create` (Task 1); `ns.WEEKLY_SUBFACTIONS`, `ns.Weekly_FactionAtlas`,
  `ns.Weekly_FactionRing`, `ns.Weekly_FactionDetail`, `ns.Weekly_RewardTrack`, `ns.Weekly_FactionLayout` (Task 2);
  `ns.HomeKit.Heading`, `UI.Scroll`, `UI.Text`, `UI.Border`.
- Produces: `ns.WeeklyFactionsView(parent) -> view` with `view.scroll` (anchor it) and `view:Render(width)`.
  The board's view table contract used by Tasks 5 and 6: every tab view has `.scroll` and `:Render(width)`.

- [ ] **Step 1: Remove Renown from This week.** In `Data.lua` `ns.Weekly_BoardModel`, delete the `local renown = {}`
  loop and `Section(progress, "Renown", renown)`; update the comment above the function ("progress: crests and
  lockouts"). In `tests/test_weekly.lua` test "board model: vault notes, to do and progress": change
  `eq(Headers(m.progress), "Renown,Crests,Lockouts")` to `eq(Headers(m.progress), "Crests,Lockouts")` and delete the
  four `renown` lines; in "after the reset": `"Crests"`; in "a maxed faction…": delete the `renown = …` override and
  the four `done` lines (rename the test "board model: a profession with all knowledge"). If `Renown(v)` is now
  unused in `Data.lua`, delete it. Run `lua Tomte/tests/test_weekly.lua`: `all passed`.

- [ ] **Step 2: Write `Factions.lua`**

```lua
local addonName, ns = ...

-- Weekly board, Factions tab: the expansion's renown factions as emblems in progress rings (sub-factions as small
-- rings beside their parent), a tooltip with the next rewards, and a detail panel for the selected faction with its
-- reward track. Read live each time it draws (renown is account-wide). Logic in FactionData.lua.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local BLUE = { 0.3, 0.75, 1 }
local COLORS = { gold = GOLD, blue = BLUE, white = { 0.85, 0.85, 0.85 } }
local BIG, SMALL, GAP = 84, 40, 22
local DETAIL_W = 250
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
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

-- A sub-faction: friendship reputation (rank) or a plain one (standing).
local function SubRecord(sub, parentID)
	local rec = { id = sub.id, parent = parentID, renown = false, icon = sub.icon, display = sub.display }
	local friend = C_GossipInfo.GetFriendshipReputation(sub.id)
	if friend and (friend.friendshipFactionID or 0) > 0 then
		local ranks = C_GossipInfo.GetFriendshipReputationRanks(sub.id)
		rec.name = friend.name
		rec.level = ranks and ranks.currentLevel or nil
		rec.standing = friend.reaction
		rec.earned = (friend.standing or 0) - (friend.reactionThreshold or 0)
		rec.threshold = friend.nextThreshold and (friend.nextThreshold - (friend.reactionThreshold or 0)) or 0
	else
		local data = C_Reputation.GetFactionDataByID(sub.id)
		if not data then
			return nil
		end
		rec.name = data.name
		rec.level = data.reaction
		rec.standing = _G["FACTION_STANDING_LABEL" .. (data.reaction or 0)]
		rec.earned = (data.currentStanding or 0) - (data.currentReactionThreshold or 0)
		rec.threshold = (data.nextReactionThreshold or 0) - (data.currentReactionThreshold or 0)
	end
	rec.paragon = Paragon(sub.id)
	return rec
end

function ns.Weekly_ReadFactions()
	local expansion = GetExpansionLevel()
	local hidden = C_MajorFactions.IsMajorFactionHiddenFromExpansionPage
	local subs = ns.WEEKLY_SUBFACTIONS[expansion] or {}
	local recs = {}
	for _, id in ipairs(C_MajorFactions.GetMajorFactionIDs(expansion) or {}) do
		local data = C_MajorFactions.GetMajorFactionData(id)
		if data and data.isUnlocked and not (hidden and hidden(id)) then
			local levels = C_MajorFactions.GetRenownLevels(id)
			recs[#recs + 1] = {
				id = id, name = data.name, renown = true, level = data.renownLevel,
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
	local c = COLORS[look.color] or GOLD
	ring:SetColor(c[1], c[2], c[3])
	ring:SetProgress(look.frac)
	ring:SetBadge(look.badge)
	ring:SetGlow(look.glow)
end

local function Tooltip(owner, rec)
	local d = ns.Weekly_FactionDetail(rec)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(d.title, 1, 1, 1)
	GameTooltip:AddLine(d.line1, GOLD[1], GOLD[2], GOLD[3])
	if d.line2 ~= "" then
		GameTooltip:AddLine(d.line2, GREY[1], GREY[2], GREY[3])
	end
	if rec.renown and rec.max and rec.level < rec.max then
		local rewards = C_MajorFactions.GetRenownRewardsForLevel(rec.id, rec.level + 1) or {}
		if #rewards > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Next rewards:", WHITE[1], WHITE[2], WHITE[3])
			for _, r in ipairs(rewards) do
				GameTooltip:AddLine(("|T%s:16|t %s"):format(r.icon or QUESTION, r.name or "?"), GOLD[1], GOLD[2], GOLD[3])
			end
		end
	end
	if rec.renown then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click for the reward track", 0.45, 0.85, 0.45)
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
	detail:SetWidth(DETAIL_W)
	local dbg = detail:CreateTexture(nil, "BACKGROUND")
	dbg:SetAllPoints()
	dbg:SetColorTexture(1, 1, 1, 0.03)
	UI.Border(detail, GOLD[1], GOLD[2], GOLD[3], 0.18)
	detail.ring = ns.WeeklyRing_Create(detail, 120)
	detail.ring:SetPoint("TOP", 0, -24)
	detail.ring:EnableMouse(false)
	detail.title = UI.Text(detail, 16, WHITE)
	detail.title:SetPoint("TOP", detail.ring, "BOTTOM", 0, -18)
	detail.title:SetWidth(DETAIL_W - 24)
	detail.title:SetJustifyH("CENTER")
	detail.line1 = UI.Text(detail, 13, GOLD)
	detail.line1:SetPoint("TOP", detail.title, "BOTTOM", 0, -6)
	detail.line2 = UI.Text(detail, 12, GREY)
	detail.line2:SetPoint("TOP", detail.line1, "BOTTOM", 0, -4)
	view.detail = detail
	view.rewardHead = Kit.Heading(c)

	view.none = UI.Text(c, 13, GREY)
	view.none:SetPoint("TOPLEFT", 16, -16)
	view.none:SetText("No renown factions unlocked for this character's expansion yet.")

	local function Ring(i, size)
		local ring = view.rings[i]
		if not ring or ring.size ~= size then
			if ring then
				ring:Hide()
			end
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
			row:SetHeight(30)
			row.level = row:CreateFontString(nil, "OVERLAY")
			row.level:SetFont(Kit.NARROW_FONT, 18, "")
			row.level:SetPoint("LEFT", 0, 0)
			row.level:SetWidth(36)
			row.level:SetJustifyH("RIGHT")
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(24, 24)
			row.icon:SetPoint("LEFT", 50, 0)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row.name = UI.Text(row, 13, WHITE)
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
			row.name:SetPoint("RIGHT", -8, 0)
			row.name:SetWordWrap(false)
			row.line = row:CreateTexture(nil, "ARTWORK")
			row.line:SetHeight(1)
			row.line:SetPoint("TOPLEFT", 0, 0)
			row.line:SetPoint("TOPRIGHT", 0, 0)
			row.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
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
		local recs = ns.Weekly_ReadFactions()
		local layout = ns.Weekly_FactionLayout(recs)
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
			local cellW = BIG + #cell.subs * (SMALL + 8) + (#cell.subs > 0 and 8 or 0)
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
		self.detail:ClearAllPoints()
		self.detail:SetPoint("TOPLEFT", 8, -8)
		self.detail:SetHeight(260)
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
				SetColor(row.level, step.earned and DIM or GOLD)
				row.icon:SetTexture(reward.icon or QUESTION)
				row.icon:SetDesaturated(step.earned)
				row.name:SetText(reward.name)
				SetColor(row.name, step.earned and DIM or WHITE)
				row.line:SetShown(r == 1)
				trackY = trackY + 30
			end
		end
		self.scroll:SetContentHeight(math.max(trackY, 280) + 16)
	end

	return view
end
```

- [ ] **Step 3: Switch the board to one view object per tab.** In `BoardPage.lua`:

  1. Replace the `VIEWS` line with:

```lua
local VIEWS = {
	{ key = "week", text = "This week" }, { key = "factions", text = "Factions" },
	{ key = "activities", text = "Activities" }, { key = "raids", text = "Raids" },
	{ key = "chars", text = "Characters" }, { key = "profs", text = "Professions" },
}
```

  2. Change `local page, list, grid, week` to `local page, list, grid, week, tabViews`.
  3. In `Layout()`, after `week.scroll:SetShown(false)` add:

```lua
	for key, tv in pairs(tabViews) do
		tv.scroll:SetShown(key == view)
	end
	if tabViews[view] then
		tabViews[view]:Render(tabViews[view].scroll:GetWidth())
		return
	end
```

  4. In `Create`, after the `week` view is created, add:

```lua
		tabViews = {}
		local makers = { factions = ns.WeeklyFactionsView, activities = ns.WeeklyActivitiesView, raids = ns.WeeklyRaidsView }
		for key, make in pairs(makers) do
			local tv = make(page)
			tv.scroll:SetPoint("TOPLEFT", 0, -30)
			tv.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
			tv.scroll.onWidthChanged = function()
				ns.WeeklyBoard_Refresh()
			end
			tabViews[key] = tv
		end
```

  Until Tasks 5 and 6 exist, `ns.WeeklyActivitiesView` and `ns.WeeklyRaidsView` are nil; guard with
  `if make then … end` around the body of that loop, and keep the guard (a disabled module file shouldn't break the
  board).

  5. The six tab buttons are 100 px each; if they overlap the reset text at the window's minimum width, change
     `UI.Button(page, 100, view.text)` to `UI.Button(page, 92, view.text)`.

- [ ] **Step 4: TOC and checks.** Add `Modules/Weekly/Factions.lua` after `Modules/Weekly/WeekView.lua`. Run the
  syntax check and `lua Tomte/tests/test_weekly.lua` and `lua Tomte/tests/test_factions.lua`: no syntax output,
  both `all passed`.

- [ ] **Step 5: In-game check (user).** "`/reload`, open the Weekly board, click **Factions**. Expect: emblems in
  rings with level badges, cartels as small rings beside Cartels of Undermine, Weaver/General/Vizier beside Severed
  Threads; hover shows renown, progress and next rewards; clicking an emblem fills the left panel (big ring,
  'Renown 7/25', 'N until next level') and the reward track below the grid, earned levels dimmed. Also check This
  week no longer has Renown. Paste BugSack errors." Fix what's reported before committing.

- [ ] **Step 6: Commit (after the user confirmed)**

```bash
git add Tomte/Modules/Weekly/Factions.lua Tomte/Modules/Weekly/BoardPage.lua Tomte/Modules/Weekly/Data.lua Tomte/tests/test_weekly.lua Tomte/Tomte.toc
git commit -m "Tomte: Weekly board Factions tab (emblems in progress rings, sub-factions, next rewards, reward track); renown leaves This week"
```

---

### Task 4: Activity model (pure) and quest groups

**Files:**
- Create: `Tomte/Modules/Weekly/ActivityData.lua` (TOC: after `FactionData.lua`)
- Modify: `Tomte/Modules/Weekly/Collect.lua` (`ReadQuests` remembers the log header)
- Test: `Tomte/tests/test_activities.lua`

**Interfaces:**
- Consumes: `db.quests[questID] = { title, firstSeen, group }` (`group` new), the snapshot view's
  `v.quests[questID] = "log" | "done"`, `ns.WEEKLY_CRESTS`.
- Produces:
  - `ns.WEEKLY_ACTIVITIES[expansion] = { { group, entries = { entry } } }` where entry is one of
    `{ label, quest, account }`, `{ label, flags = { questIDs } }`, `{ label, questLine }`.
  - `ns.WEEKLY_RESOURCES[expansion] = { currencyIDs }`.
  - `ns.Weekly_ActivityModel(curated, learned, v, hideCompleted) -> { groups = { { title, items } }, hidden = n }`
    where `curated` is `{ { group, entries = { { label, state = "done" | "open" | "progress", n, of, title } } } }`
    (the reader fills `state`/`n`/`of`/`title`), `items` use the board row schema
    (`{ kind = "row", left, right, state }`), and `hidden` counts completed items left out.

- [ ] **Step 1: Write the failing test** `Tomte/tests/test_activities.lua`

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_activities.lua
local ns = {}
assert(loadfile("Tomte/Modules/Weekly/ActivityData.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local function Curated()
	return {
		{ group = "Delves", entries = {
			{ label = "The Key to Success", state = "done" },
			{ label = "Restored Coffer Keys", state = "open", n = 1, of = 4 },
		} },
		{ group = "Dornogal", entries = {
			{ label = "Worldsoul weekly", state = "progress", title = "Worldsoul: Spreading the Light" },
		} },
	}
end

local LEARNED = {
	[100] = { title = "Theater Troupe", group = "Isle of Dorn" },
	[101] = { title = "Spreading the Light", group = "Hallowfall" },
	[102] = { title = "Old one" }, -- learned before groups were kept
}
local VIEW = { quests = { [100] = "log", [101] = "done", [102] = "log" } }

local function Find(groups, title)
	for _, g in ipairs(groups) do
		if g.title == title then
			return g
		end
	end
end

test("curated groups first, then learned quests by their log header", function()
	local m = ns.Weekly_ActivityModel(Curated(), LEARNED, VIEW, false)
	eq(m.groups[1].title, "Delves")
	eq(m.groups[2].title, "Dornogal")
	eq(Find(m.groups, "Isle of Dorn").items[1].left, "Theater Troupe")
	eq(Find(m.groups, "Other weekly quests").items[1].left, "Old one", "no group")
	eq(m.hidden, 0)
end)

test("item texts and states", function()
	local m = ns.Weekly_ActivityModel(Curated(), LEARNED, VIEW, false)
	local delves = m.groups[1].items
	eq(delves[1].right, "done")
	eq(delves[1].state, "done")
	eq(delves[2].left, "Restored Coffer Keys")
	eq(delves[2].right, "1/4")
	eq(delves[2].state, "open")
	eq(m.groups[2].items[1].right, "in progress")
	eq(m.groups[2].items[1].left, "Worldsoul weekly: Worldsoul: Spreading the Light")
end)

test("hide completed drops done items and empty groups, and counts them", function()
	local m = ns.Weekly_ActivityModel(Curated(), LEARNED, VIEW, true)
	eq(#m.groups[1].items, 1, "Delves keeps the keys")
	eq(Find(m.groups, "Hallowfall"), nil, "only done quest")
	eq(m.hidden, 2)
end)

test("everything done and hidden leaves one note", function()
	local curated = { { group = "Delves", entries = { { label = "Key", state = "done" } } } }
	local m = ns.Weekly_ActivityModel(curated, {}, { quests = {} }, true)
	eq(#m.groups, 1)
	eq(m.groups[1].title, "")
	eq(m.groups[1].items[1].left, "Everything here is done this week.")
	eq(m.hidden, 1)
end)

test("no data at all", function()
	local m = ns.Weekly_ActivityModel({}, {}, { quests = {} }, false)
	eq(m.groups[1].items[1].left, "Nothing tracked yet. Weekly quests are learned when they're in your quest log.")
end)

test("curated and resource tables exist for The War Within", function()
	eq(#ns.WEEKLY_ACTIVITIES[10] > 0, true)
	eq(#ns.WEEKLY_RESOURCES[10] > 0, true)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
```

- [ ] **Step 2: Run it to see it fail**

Run: `lua Tomte/tests/test_activities.lua`
Expected: can't open `Tomte/Modules/Weekly/ActivityData.lua`.

- [ ] **Step 3: Write `ActivityData.lua`**

```lua
local addonName, ns = ...

-- Activities tab: pure logic (tested with plain Lua). Learned weekly quests (Collect.lua) grouped by their quest log
-- header, after a short hand-kept list per expansion for what never shows in the log. Quest IDs from Plumber's
-- tables (checked 2026-10-06): Coffer Key flags 91175-91178, Coffer Key Shard flags 84736-84739, "The Key to Success"
-- 84370 (account-wide), Worldsoul weekly quest line 5572.

ns.WEEKLY_ACTIVITIES = {
	[10] = {
		{ group = "Delves", entries = {
			{ label = "The Key to Success", quest = 84370, account = true },
			{ label = "Restored Coffer Keys", flags = { 91175, 91176, 91177, 91178 } },
			{ label = "Coffer Key Shards", flags = { 84736, 84737, 84738, 84739 } },
		} },
		{ group = "Dornogal", entries = {
			{ label = "Worldsoul weekly", questLine = 5572 },
		} },
	},
}

-- Currencies for the Resources list (shown when discovered), after the crests. From Plumber's War Within list.
ns.WEEKLY_RESOURCES = {
	[10] = { 3269, 3028, 3149, 2815, 3218, 3226, 3090, 3056, 2803, 2123, 2797 },
}

local OTHER = "Other weekly quests"

local function CuratedItem(e)
	local right, state
	if e.state == "done" then
		right, state = "done", "done"
	elseif e.of then
		right, state = ("%d/%d"):format(e.n or 0, e.of), (e.n or 0) >= e.of and "done" or "open"
	elseif e.state == "progress" then
		right, state = "in progress", "open"
	else
		right, state = "open", "open"
	end
	local left = e.title and ("%s: %s"):format(e.label, e.title) or e.label
	return { kind = "row", left = left, right = right, state = state }
end

function ns.Weekly_ActivityModel(curated, learned, v, hideCompleted)
	local groups, hidden = {}, 0
	local function Add(title, items)
		local kept = {}
		for _, item in ipairs(items) do
			if hideCompleted and item.state == "done" then
				hidden = hidden + 1
			else
				kept[#kept + 1] = item
			end
		end
		if #kept > 0 then
			groups[#groups + 1] = { title = title, items = kept }
		end
	end
	for _, g in ipairs(curated) do
		local items = {}
		for _, e in ipairs(g.entries) do
			items[#items + 1] = CuratedItem(e)
		end
		Add(g.group, items)
	end

	local byGroup, order = {}, {}
	for id, state in pairs(v.quests or {}) do
		local q = learned[id]
		if q then
			local title = q.group or OTHER
			if not byGroup[title] then
				byGroup[title] = {}
				order[#order + 1] = title
			end
			table.insert(byGroup[title], { kind = "row", left = q.title or ("Quest " .. id),
				right = state == "done" and "done" or "open", state = state == "done" and "done" or "open" })
		end
	end
	table.sort(order, function(a, b)
		if (a == OTHER) ~= (b == OTHER) then
			return b == OTHER
		end
		return a < b
	end)
	for _, title in ipairs(order) do
		table.sort(byGroup[title], function(a, b)
			return a.left < b.left
		end)
		Add(title, byGroup[title])
	end

	if #groups == 0 then
		local text = hidden > 0 and "Everything here is done this week."
			or "Nothing tracked yet. Weekly quests are learned when they're in your quest log."
		groups[1] = { title = "", items = { { kind = "row", left = text, state = hidden > 0 and "done" or "dim" } } }
	end
	return { groups = groups, hidden = hidden }
end
```

- [ ] **Step 4: Run the test**

Run: `lua Tomte/tests/test_activities.lua`
Expected: `all passed`.

- [ ] **Step 5: Remember the quest log header.** In `Collect.lua` `ReadQuests`, track the last header:

```lua
local function ReadQuests(snap, now)
	local quests = {}
	local header -- the quest log header above each quest (its zone or faction): the Activities tab groups by it
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and info.isHeader then
			header = info.title
		elseif info and not info.isHidden and info.frequency == Enum.QuestFrequency.Weekly
			and not ns.Weekly_IsProfQuest(info.questID) then
			local q = db.quests[info.questID] or { firstSeen = now }
			q.title = info.title
			q.group = header or q.group
			db.quests[info.questID] = q
			quests[info.questID] = "log"
		end
	end
	for id in pairs(db.quests) do
		if Completed(id) then
			quests[id] = "done"
		end
	end
	snap.quests = quests
end
```

Also add `"BOSS_KILL"` to `REFRESH_EVENTS` in `Collect.lua` (Task 6's raid dots refresh with it).

- [ ] **Step 6: TOC and checks.** `Modules/Weekly/ActivityData.lua` after `FactionData.lua`. Syntax check; run
  `lua Tomte/tests/test_activities.lua` and `lua Tomte/tests/test_weekly.lua`: `all passed`.

- [ ] **Step 7: Commit**

```bash
git add Tomte/Modules/Weekly/ActivityData.lua Tomte/Modules/Weekly/Collect.lua Tomte/tests/test_activities.lua Tomte/Tomte.toc
git commit -m "Tomte: activity model for the Weekly board (curated War Within list, learned quests by quest log header)"
```

---

### Task 5: Activities tab (reader + view)

**Files:**
- Create: `Tomte/Modules/Weekly/Activities.lua` (TOC: after `Factions.lua`)
- Modify: `Tomte/Modules/Weekly/Weekly.lua` (default `hideCompleted = true`)

**Interfaces:**
- Consumes: `ns.WEEKLY_ACTIVITIES`, `ns.WEEKLY_RESOURCES`, `ns.Weekly_ActivityModel` (Task 4);
  `ns.WeeklyRows(parent)` (`:Render(items) -> height`), `ns.Weekly_CurrentView()`, `ns.weeklyDB.quests`,
  `ns.WEEKLY_CRESTS`, `ns.Weekly_CurrencyProgress(c)`, `UI.Checkbox`, `ns.HomeKit.Heading`.
- Produces: `ns.WeeklyActivitiesView(parent) -> view` with `.scroll` and `:Render(width)`.

- [ ] **Step 1: Add the default** in `Weekly.lua` `defaults`: `hideCompleted = true, -- Activities tab`.

- [ ] **Step 2: Write `Activities.lua`**

```lua
local addonName, ns = ...

-- Weekly board, Activities tab: this week's activities grouped (a short hand-kept list, then learned weekly quests by
-- their quest log header) with "Hide completed", and a Resources list (crests, then the expansion's currencies).
-- Logic in ActivityData.lua.

local UI = ns.UI
local GOLD, WHITE, GREY = UI.GOLD, UI.WHITE, UI.GREY
local SIDE_W = 240
local RES_H = 22

local function Completed(id, account)
	if account and C_QuestLog.IsQuestFlaggedCompletedOnAccount then
		return C_QuestLog.IsQuestFlaggedCompletedOnAccount(id)
	end
	return C_QuestLog.IsQuestFlaggedCompleted(id)
end

-- The hand-kept list with this week's state filled in.
local function ReadCurated()
	local out = {}
	for _, g in ipairs(ns.WEEKLY_ACTIVITIES[GetExpansionLevel()] or {}) do
		local entries = {}
		for _, e in ipairs(g.entries) do
			local item = { label = e.label }
			if e.flags then
				local n = 0
				for _, id in ipairs(e.flags) do
					if Completed(id) then
						n = n + 1
					end
				end
				item.n, item.of = n, #e.flags
			elseif e.questLine then
				item.state = "open"
				for _, id in ipairs(C_QuestLine.GetQuestLineQuests(e.questLine) or {}) do
					if Completed(id) then
						item.state, item.title = "done", C_QuestLog.GetTitleForQuestID(id)
						break
					elseif C_QuestLog.IsOnQuest(id) then
						item.state, item.title = "progress", C_QuestLog.GetTitleForQuestID(id)
					end
				end
			else
				item.state = Completed(e.quest, e.account) and "done"
					or (C_QuestLog.IsOnQuest(e.quest) and "progress" or "open")
			end
			entries[#entries + 1] = item
		end
		out[#out + 1] = { group = g.group, entries = entries }
	end
	return out
end

-- Resources: { { name, icon, text } }, crests first.
local function ReadResources()
	local list = {}
	local function Add(id, crest)
		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		if not (info and info.name and info.name ~= "") then
			return
		end
		if not crest and not info.discovered and (info.quantity or 0) == 0 then
			return
		end
		local text = tostring(info.quantity or 0)
		if crest then
			local have, cap = ns.Weekly_CurrencyProgress({ qty = info.quantity, earnedWeek = info.quantityEarnedThisWeek,
				weeklyCap = info.maxWeeklyQuantity, total = info.totalEarned, seasonCap = info.maxQuantity,
				useTotal = info.useTotalEarnedForMaxQty })
			text = cap and ("%d  |cff9e9e9e%d/%d|r"):format(info.quantity or 0, have, cap) or text
		end
		list[#list + 1] = { name = info.name, icon = info.iconFileID, text = text, dim = (info.quantity or 0) == 0 }
	end
	for _, id in ipairs(ns.WEEKLY_CRESTS) do
		Add(id, true)
	end
	for _, id in ipairs(ns.WEEKLY_RESOURCES[GetExpansionLevel()] or {}) do
		Add(id, false)
	end
	return list
end

function ns.WeeklyActivitiesView(parent)
	local Kit = ns.HomeKit
	local view = { res = {}, cols = {} }
	view.scroll = UI.Scroll(parent)
	local c = view.scroll.content

	view.resHead = Kit.Heading(c)
	view.resHead:SetPoint("TOPLEFT", 8, -8)
	view.resHead:SetWidth(SIDE_W - 16)
	view.resHead:Set("Resources")

	view.hide = UI.Checkbox(c)
	view.hide.label = UI.Text(c, 12, GREY)
	view.hide.label:SetPoint("LEFT", view.hide, "RIGHT", 6, 0)
	view.hide.onChange = function(on)
		ns.weeklyDB.hideCompleted = on
		ns.WeeklyBoard_Refresh()
	end

	view.listFrame = CreateFrame("Frame", nil, c)
	view.rows = ns.WeeklyRows(view.listFrame)

	local function ResRow(i)
		local row = view.res[i]
		if not row then
			row = CreateFrame("Frame", nil, c)
			row:SetSize(SIDE_W - 16, RES_H)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(18, 18)
			row.icon:SetPoint("RIGHT", 0, 0)
			row.text = row:CreateFontString(nil, "OVERLAY")
			row.text:SetFont(Kit.NARROW_FONT, 14, "")
			row.text:SetPoint("RIGHT", row.icon, "LEFT", -6, 0)
			row.name = UI.Text(row, 12, WHITE)
			row.name:SetPoint("LEFT", 0, 0)
			row.name:SetPoint("RIGHT", row.text, "LEFT", -8, 0)
			row.name:SetWordWrap(false)
			view.res[i] = row
		end
		row:Show()
		return row
	end

	function view:Render(width)
		width = math.max(width or 0, 500)
		-- Resources (left).
		local resources = ReadResources()
		for _, row in ipairs(self.res) do
			row:Hide()
		end
		local y = 8 + 38
		for i, r in ipairs(resources) do
			local row = ResRow(i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 8, -y)
			row.icon:SetTexture(r.icon)
			row.icon:SetDesaturated(r.dim)
			row.text:SetText(r.text)
			row.name:SetText(r.name)
			local col = r.dim and GREY or WHITE
			row.name:SetTextColor(col[1], col[2], col[3])
			row.text:SetTextColor(col[1], col[2], col[3])
			y = y + RES_H
		end
		local leftBottom = y

		-- Activities (right).
		local v = ns.Weekly_CurrentView()
		local x = SIDE_W + 24
		local listW = width - x - 8
		local model = ns.Weekly_ActivityModel(ReadCurated(), ns.weeklyDB.quests, v or { quests = {} },
			ns.weeklyDB.hideCompleted)
		self.hide:ClearAllPoints()
		self.hide:SetPoint("TOPLEFT", x + 8, -16)
		self.hide:SetChecked(ns.weeklyDB.hideCompleted)
		self.hide.label:SetText(("Hide completed (%d)"):format(model.hidden))
		local items = {}
		for _, g in ipairs(model.groups) do
			if g.title ~= "" then
				items[#items + 1] = { kind = "header", text = g.title }
			end
			for _, item in ipairs(g.items) do
				items[#items + 1] = item
			end
		end
		self.listFrame:ClearAllPoints()
		self.listFrame:SetPoint("TOPLEFT", x, -36)
		self.listFrame:SetWidth(listW)
		local h = self.rows:Render(items)
		self.listFrame:SetHeight(math.max(h, 1))
		self.scroll:SetContentHeight(math.max(leftBottom, 36 + h) + 16)
	end

	return view
end
```

- [ ] **Step 3: Check the quest line API on the wiki** before relying on it:
  `https://warcraft.wiki.gg/wiki/API_C_QuestLine.GetQuestLineQuests` (returns a table of quest IDs) and
  `https://warcraft.wiki.gg/wiki/API_C_QuestLog.IsQuestFlaggedCompletedOnAccount`. If either changed, adjust
  `ReadCurated` (the guard on `IsQuestFlaggedCompletedOnAccount` is already there).

- [ ] **Step 4: TOC and checks.** `Modules/Weekly/Activities.lua` after `Factions.lua`. Syntax check; all three
  Weekly test files `all passed`.

- [ ] **Step 5: In-game check (user).** "`/reload`, Weekly board → **Activities**. Expect: Resources on the left
  (crests with this week's cap, then the currencies you've seen), on the right 'Hide completed (N)', then Delves
  (The Key to Success, Restored Coffer Keys n/4, Coffer Key Shards n/4), Dornogal (Worldsoul weekly), then your
  learned weekly quests grouped by zone. Untick Hide completed: done rows come back in green. Learned quests only get
  their zone after they've been in your log once since this update, so older ones sit under 'Other weekly quests'
  for now." Fix reports before committing.

- [ ] **Step 6: Commit (after the user confirmed)**

```bash
git add Tomte/Modules/Weekly/Activities.lua Tomte/Modules/Weekly/Weekly.lua Tomte/Tomte.toc
git commit -m "Tomte: Weekly board Activities tab (Delves keys and shards, Worldsoul weekly, learned quests by zone, hide completed, resources)"
```

---

### Task 6: Raids (model, reader, view)

**Files:**
- Create: `Tomte/Modules/Weekly/RaidData.lua` (TOC: after `ActivityData.lua`)
- Create: `Tomte/Modules/Weekly/Raids.lua` (TOC: after `Activities.lua`)
- Modify: `Tomte/Modules/Weekly/Weekly.lua` (default `raidCollapsed = {}`)
- Test: `Tomte/tests/test_raids.lua`

**Interfaces:**
- Produces:
  - `ns.WEEKLY_RAIDS[expansion] = { journalInstanceIDs, newest first }`
  - `ns.WEEKLY_RAID_DIFFICULTIES = { { id = 17, short = "L", name = "LFR" }, { id = 14, short = "N", name = "Normal" },
    { id = 15, short = "H", name = "Heroic" }, { id = 16, short = "M", name = "Mythic" } }`
  - `ns.Weekly_RaidModel(raids, isKilled, collapsed) -> { { kind = "raid", id, name, totals = { "3/8", … }, collapsed } |
    { kind = "boss", name, dots = { bool × 4 } } }` where `raids = { { id, name, mapID, bosses = { { name, encounterID } } } }`,
    `isKilled(mapID, encounterID, difficultyID) -> bool`, `collapsed[id] = true`.
  - `ns.WeeklyRaidsView(parent) -> view` with `.scroll` and `:Render(width)`.

- [ ] **Step 1: Write the failing test** `Tomte/tests/test_raids.lua`

```lua
-- Run from the AddOns folder: lua Tomte/tests/test_raids.lua
local ns = {}
assert(loadfile("Tomte/Modules/Weekly/RaidData.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local RAIDS = {
	{ id = 1302, name = "Manaforge Omega", mapID = 2810, bosses = { { name = "Plexus Sentinel", encounterID = 3129 },
		{ name = "Loom'ithar", encounterID = 3131 } } },
	{ id = 1296, name = "Liberation of Undermine", mapID = 2769, bosses = { { name = "Vexie", encounterID = 3009 } } },
}

local function Killed(mapID, encounterID, difficultyID)
	return encounterID == 3129 and (difficultyID == 14 or difficultyID == 15)
end

test("raid headers with totals per difficulty, bosses with dots", function()
	local items = ns.Weekly_RaidModel(RAIDS, Killed, {})
	eq(#items, 5)
	eq(items[1].kind, "raid")
	eq(items[1].name, "Manaforge Omega")
	eq(items[1].totals[1], "0/2", "LFR")
	eq(items[1].totals[2], "1/2", "Normal")
	eq(items[1].totals[3], "1/2", "Heroic")
	eq(items[2].kind, "boss")
	eq(items[2].dots[2], true)
	eq(items[2].dots[4], false)
	eq(items[3].dots[2], false)
end)

test("a collapsed raid keeps its header and totals only", function()
	local items = ns.Weekly_RaidModel(RAIDS, Killed, { [1302] = true })
	eq(#items, 3)
	eq(items[1].collapsed, true)
	eq(items[2].kind, "raid")
end)

test("no raids", function()
	eq(#ns.Weekly_RaidModel({}, Killed, {}), 0)
end)

test("War Within raid list and four difficulties", function()
	eq(ns.WEEKLY_RAIDS[10][1], 1302)
	eq(#ns.WEEKLY_RAID_DIFFICULTIES, 4)
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")
```

- [ ] **Step 2: Run it to see it fail**

Run: `lua Tomte/tests/test_raids.lua`
Expected: can't open `Tomte/Modules/Weekly/RaidData.lua`.

- [ ] **Step 3: Write `RaidData.lua`**

```lua
local addonName, ns = ...

-- Raids tab: pure logic (tested with plain Lua). Journal instance IDs per expansion, newest first (Plumber's list,
-- checked 2026-10-06), and the four difficulties (DifficultyUtil.ID.PrimaryRaidLFR/Normal/Heroic/Mythic).

ns.WEEKLY_RAIDS = {
	[10] = { 1302, 1296, 1273 }, -- Manaforge Omega, Liberation of Undermine, Nerub-ar Palace
}

ns.WEEKLY_RAID_DIFFICULTIES = {
	{ id = 17, short = "L", name = "LFR" },
	{ id = 14, short = "N", name = "Normal" },
	{ id = 15, short = "H", name = "Heroic" },
	{ id = 16, short = "M", name = "Mythic" },
}

function ns.Weekly_RaidModel(raids, isKilled, collapsed)
	local items = {}
	for _, raid in ipairs(raids) do
		local header = { kind = "raid", id = raid.id, name = raid.name, totals = {}, collapsed = collapsed[raid.id] == true }
		items[#items + 1] = header
		local kills = {}
		local bosses = {}
		for _, boss in ipairs(raid.bosses) do
			local dots = {}
			for d, diff in ipairs(ns.WEEKLY_RAID_DIFFICULTIES) do
				dots[d] = isKilled(raid.mapID, boss.encounterID, diff.id) == true
				kills[d] = (kills[d] or 0) + (dots[d] and 1 or 0)
			end
			bosses[#bosses + 1] = { kind = "boss", name = boss.name, dots = dots }
		end
		for d in ipairs(ns.WEEKLY_RAID_DIFFICULTIES) do
			header.totals[d] = ("%d/%d"):format(kills[d] or 0, #raid.bosses)
		end
		if not header.collapsed then
			for _, b in ipairs(bosses) do
				items[#items + 1] = b
			end
		end
	end
	return items
end
```

- [ ] **Step 4: Run the test**

Run: `lua Tomte/tests/test_raids.lua`
Expected: `all passed`.

- [ ] **Step 5: Check the APIs on the wiki**: `API_EJ_GetInstanceInfo` (10th return is the instance's mapID),
  `API_EJ_GetEncounterInfoByIndex` (7th return dungeonEncounterID), `API_EJ_SetDifficulty`, `API_EJ_GetDifficulty`,
  `API_C_RaidLocks.IsEncounterComplete`. Adjust the reader below if a return position changed.

- [ ] **Step 6: Write `Raids.lua`**

```lua
local addonName, ns = ...

-- Weekly board, Raids tab: the expansion's raids, each boss with four dots (LFR, Normal, Heroic, Mythic) filled when
-- killed this week. The Encounter Journal API is global state: bosses are read once per session, only when this tab
-- shows, with the journal's difficulty restored and Blizzard's journal kept from reacting meanwhile.

local UI = ns.UI
local GOLD, WHITE, GREY, DIM = UI.GOLD, UI.WHITE, UI.GREY, UI.DIM
local GREEN = { 0.45, 0.85, 0.45 }
local RAID_H, BOSS_H, DOT, DOT_GAP = 30, 24, 10, 22

local raids -- read once per session

local function MuteJournal()
	local journal = EncounterJournal
	if not journal then
		return
	end
	journal:UnregisterEvent("EJ_LOOT_DATA_RECIEVED")
	journal:UnregisterEvent("EJ_DIFFICULTY_UPDATE")
	C_Timer.After(0, function()
		journal:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
		journal:RegisterEvent("EJ_DIFFICULTY_UPDATE")
	end)
end

local function ReadRaids()
	if raids then
		return raids
	end
	local list = {}
	MuteJournal()
	local before = EJ_GetDifficulty()
	EJ_SetDifficulty(14) -- EJ_GetEncounterInfoByIndex returns nil without a difficulty set
	for _, jid in ipairs(ns.WEEKLY_RAIDS[GetExpansionLevel()] or {}) do
		local name, _, _, _, _, _, _, _, _, mapID = EJ_GetInstanceInfo(jid)
		if name then
			local bosses = {}
			local i = 1
			local bossName, _, journalEncounterID, _, _, _, encounterID = EJ_GetEncounterInfoByIndex(i, jid)
			while journalEncounterID do
				bosses[#bosses + 1] = { name = bossName, encounterID = encounterID }
				i = i + 1
				bossName, _, journalEncounterID, _, _, _, encounterID = EJ_GetEncounterInfoByIndex(i, jid)
			end
			list[#list + 1] = { id = jid, name = name, mapID = mapID, bosses = bosses }
		end
	end
	if before then
		EJ_SetDifficulty(before)
	end
	raids = list
	return raids
end

local function IsKilled(mapID, encounterID, difficultyID)
	return encounterID ~= nil and C_RaidLocks.IsEncounterComplete(mapID, encounterID, difficultyID) == true
end

function ns.WeeklyRaidsView(parent)
	local Kit = ns.HomeKit
	local view = { rows = {} }
	view.scroll = UI.Scroll(parent)
	local c = view.scroll.content

	view.legend = UI.Text(c, 12, GREY)
	view.none = UI.Text(c, 13, GREY)
	view.none:SetPoint("TOPLEFT", 16, -16)
	view.none:SetText("No raids listed for this character's expansion.")

	local function Row(i)
		local row = view.rows[i]
		if not row then
			row = CreateFrame("Button", nil, c)
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			row.name = UI.Text(row, 13, WHITE)
			row.name:SetPoint("LEFT", 12, 0)
			row.name:SetWordWrap(false)
			row.cells = {}
			for d = 1, #ns.WEEKLY_RAID_DIFFICULTIES do
				local cell = row:CreateTexture(nil, "ARTWORK")
				cell:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
				cell:SetSize(DOT, DOT)
				local text = row:CreateFontString(nil, "OVERLAY")
				text:SetFont(Kit.NARROW_FONT, 13, "")
				row.cells[d] = { dot = cell, text = text }
			end
			row:SetScript("OnClick", function(self)
				if self.raidID then
					ns.weeklyDB.raidCollapsed[self.raidID] = not ns.weeklyDB.raidCollapsed[self.raidID] or nil
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
					ns.WeeklyBoard_Refresh()
				end
			end)
			view.rows[i] = row
		end
		row:Show()
		return row
	end

	function view:Render(width)
		width = math.max(width or 0, 500)
		for _, row in ipairs(self.rows) do
			row:Hide()
		end
		local items = ns.Weekly_RaidModel(ReadRaids(), IsKilled, ns.weeklyDB.raidCollapsed)
		self.none:SetShown(#items == 0)
		local right = width - 24
		local labels = {}
		for _, d in ipairs(ns.WEEKLY_RAID_DIFFICULTIES) do
			labels[#labels + 1] = d.name
		end
		self.legend:ClearAllPoints()
		self.legend:SetPoint("TOPRIGHT", c, "TOPLEFT", right, -8)
		self.legend:SetText(table.concat(labels, "  ·  "))
		self.legend:SetShown(#items > 0)
		local y = 30
		for i, item in ipairs(items) do
			local row = Row(i)
			local raid = item.kind == "raid"
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", raid and 8 or 28, -y)
			row:SetPoint("RIGHT", c, "LEFT", right + 8, 0)
			row:SetHeight(raid and RAID_H or BOSS_H)
			row.bg:SetColorTexture(1, 1, 1, raid and 0.06 or 0.025)
			row.raidID = raid and item.id or nil
			row:EnableMouse(raid)
			row.name:SetFont(STANDARD_TEXT_FONT, raid and 14 or 12, "")
			row.name:SetText(raid and ((item.collapsed and "+  " or "–  ") .. item.name) or item.name)
			local col = raid and GOLD or WHITE
			row.name:SetTextColor(col[1], col[2], col[3])
			for d, cell in ipairs(row.cells) do
				local x = -((#row.cells - d) * (DOT_GAP + 20)) - 12
				cell.dot:ClearAllPoints()
				cell.dot:SetPoint("RIGHT", x, 0)
				cell.text:ClearAllPoints()
				cell.text:SetPoint("RIGHT", x + 6, 0)
				cell.dot:SetShown(not raid)
				cell.text:SetShown(raid)
				if raid then
					cell.text:SetText(item.totals[d])
					cell.text:SetTextColor(GREY[1], GREY[2], GREY[3])
				else
					local c2 = item.dots[d] and GREEN or DIM
					cell.dot:SetVertexColor(c2[1], c2[2], c2[3], item.dots[d] and 1 or 0.6)
				end
			end
			row.name:SetPoint("RIGHT", row.cells[1].dot, "LEFT", -16, 0)
			y = y + (raid and RAID_H + 4 or BOSS_H + 2)
		end
		self.scroll:SetContentHeight(y + 16)
	end

	return view
end
```

- [ ] **Step 7: Default and TOC.** `Weekly.lua` `defaults`: `raidCollapsed = {}, -- Raids tab: [journalInstanceID] = true`.
  TOC: `Modules/Weekly/RaidData.lua` after `ActivityData.lua`, `Modules/Weekly/Raids.lua` after `Activities.lua`.
  Syntax check; `lua Tomte/tests/test_raids.lua`: `all passed`.

- [ ] **Step 8: In-game check (user).** "`/reload`, Weekly board → **Raids**. Expect Manaforge Omega, Liberation of
  Undermine and Nerub-ar Palace with boss rows and four dots each (LFR · Normal · Heroic · Mythic, green when killed
  this week); click a raid header to collapse it. Then open the Encounter Journal (Shift+J), pick a raid on Heroic,
  switch to the Raids tab and back: the journal should still be on Heroic. Paste BugSack errors."

- [ ] **Step 9: Commit (after the user confirmed)**

```bash
git add Tomte/Modules/Weekly/RaidData.lua Tomte/Modules/Weekly/Raids.lua Tomte/Modules/Weekly/Weekly.lua Tomte/tests/test_raids.lua Tomte/Tomte.toc
git commit -m "Tomte: Weekly board Raids tab (bosses killed this week per difficulty, collapsible raids)"
```

---

### Task 7: Clean-up, docs, final check

**Files:**
- Modify: `Tomte/Modules/Weekly/Weekly.lua` (remove the `ring` probe command; update the module `description`)
- Modify: `docs/superpowers/specs/2026-10-06-tomte-weekly-factions-activities-raids-design.md` (append "As built")
- Modify: `README.md` if it lists the Weekly board's tabs (`grep -n "Weekly" README.md`)

- [ ] **Step 1: Remove the probe.** Delete the `{ "ring", … }` entry from `commands` in `Weekly.lua` and the
  `ns.weeklyRingProbe` code with it.

- [ ] **Step 2: Module description.** Replace the `description` string with: "What you haven't done this week and
  where the expansion stands: Great Vault, crests, weekly quests, profession knowledge and Concentration, lockouts,
  renown factions with their reward tracks, weekly activities and raid kills, for every max-level character (alts
  roll over at the weekly reset without logging in). Right-click the minimap button for a quick list."

- [ ] **Step 3: As built.** Append to the spec a `## As built (YYYY-MM-DD)` section listing anything that differed
  from the plan (e.g. the measured `REVERSE` value, any atlas fallback seen, API return changes).

- [ ] **Step 4: Full check.** Syntax check over `Tomte`, then run every test:
  `for t in Tomte/tests/test_*.lua; do lua "$t" | tail -1; done` — every line `all passed`.

- [ ] **Step 5: Whole-board check (user).** "`/reload`; open the Weekly board and click through all six tabs; resize
  the window narrow and wide; open the weekly popup (right-click the minimap button). Paste BugSack errors."

- [ ] **Step 6: Commit (after the user confirmed)**

```bash
git add Tomte/Modules/Weekly/Weekly.lua docs/superpowers/specs/2026-10-06-tomte-weekly-factions-activities-raids-design.md README.md
git commit -m "Tomte: Weekly board Factions, Activities and Raids: as-built notes, probe command removed"
```
