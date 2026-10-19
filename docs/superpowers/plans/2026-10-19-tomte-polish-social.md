# Polish B: Defaults, Social and Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quieter defaults for new installs (existing installs unchanged), a whisper inbox that knows which character each conversation is with, presets that leave the social modules alone plus a Social preset, and the small social/chat fixes from the 2026-10-19 audit.
**Architecture:** Pure rules go into `Modules/Social/Data.lua`, `Modules/Chat/Data.lua`, `Modules/Recent/Data.lua`, `Core/Setup.lua`, `Core/Format.lua` and one appended migration in `Core/Migrations.lua`, each with tests; the module and UI files only wire them. Whisper conversations get optional `with`/`char`/`charName` fields; old ones stay valid without a migration. Recent's Include list is built from a new `toasts` field on the modules.
**Tech Stack:** Lua 5.1 (WoW 12.1.5 retail), plain-Lua unit tests in tests/.
**Spec:** docs/superpowers/specs/2026-10-19-tomte-polish-social-design.md

## Global Constraints

- Plan A (Core/Panel) lands first; don't touch its combat-refusal call sites (`ns.Print_Combat`) or its central "module is off" check; if one of the lines below was already replaced by plan A, keep plan A's version.
- Files are CRLF: edit Lua with the Edit/Write tools only, never sed/awk/heredocs.
- First line `local addonName, ns = ...`, then a header comment; tabs, ~120 columns, double quotes, `local function` for private code.
- Cross-file names are `ns.<Prefix>_<Name>`; unprefixed `ns.Name` only for Core-wide helpers (`ns.FormatToPattern`, `ns.FormatMatch`).
- Pure files (Data.lua, Core/Setup.lua, Core/Format.lua, Core/Migrations.lua) call no WoW API and get a test for every new rule.
- Saved keys are never renamed or reshaped except by a migration appended to `ns.MIGRATIONS` with a case in `tests/test_migrations.lua`; every saved key has a default with a shape comment.
- Colors and fonts by theme role only (`UI.Wrap(text, role)`, `UI.Text(parent, size, role)`), never a `|cff` literal or numeric color.
- `toggle(false)` undoes everything; a hook or event handler does nothing while its module is off.
- `pcall` only around calls that can legitimately fail; our own code runs through `ns.errorHandler`.
- Match game text through Blizzard globals or IDs, not English strings; no real character, realm or guild names (use Aldric, Kesha, Mira).
- Run all tests from the AddOns folder before calling a task done: `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done`.
- After a new or split file: `luac -l <file> | grep -E 'GETGLOBAL|GETTABUP.*_ENV'` lists only WoW API and Lua globals.
- Commit each task only after the user confirmed it in game; message `<Module>: what changed`; pure moves say so and carry no behavior change. CHANGELOG **Unreleased** line in player wording for each confirmed behavior change.

## Review Focus

1. **An existing player silently loses Friend sharing or the Master-channel alert.** The "existing install" test in migration 11 relies on `db.enabled` not existing yet for a fresh install. Owned by Task 3: migration tests for fresh, existing and player-chosen values, plus an in-game check on the user's own saved variables (Friend sharing still on, Group Alerts still Master).
2. **A whisper goes to `"Name-Realm@Player-..."`.** Any place still using `convo.key` as the whisper target breaks reply, send, invite, add friend and the friend lookup for every new conversation. Owned by Task 6: a grep step for `convo.key`/`current)` targets and an in-game whisper, reply from toast, reply from the inbox line, Invite and Add friend.
3. **Lower-casing differs between the two sides of a comparison.** If `ParseWords` lowers accents but `IsWatched`, `FindMention`, `Chat_BuildKeywords` or `HighlightPlain` don't, accented keywords stop matching, or highlighting cuts the original text at the wrong byte. Owned by Task 2: tests for each function with "Ásgeir", and a byte-length test for `Social_Lower`.
4. **A toast type without an Include checkbox, or a new checkbox that shows unticked.** Owned by Task 11: a source-scan test that every toast/banner owner is a module with `toasts`, and an in-game look at Recent's settings (Friend sharing ticked) after `/reload`.
5. **Presets still switch the social modules off, or "matches your setup now" never shows again.** Owned by Task 4: tests for Plan, Apply (including Everything keeping a player's choice) and Matches ignoring untouched modules, plus an in-game `/tomte setup` run.

---

## Task 1: Move the format-string patterns into Core (pure move)

**Files:**
- Modify: `Core/Format.lua` (append a section)
- Modify: `Modules/Moments/Data.lua:81-159` (remove `CAPTURES`, `Split`, `Moments_FormatToPattern`, `Moments_Match`), `:167`, `:183`, `:185`
- Modify: `Modules/Recap/Data.lua:268`
- Modify: `Modules/Social/Friends.lua:298`
- Modify: `tests/test_format.lua`, `tests/test_moments.lua:1-5,61-104`, `tests/test_recap.lua:1-5`

**Interfaces:**
- Produces: `ns.FormatToPattern(fmt) -> pattern, spec|nil`, `ns.FormatMatch(text, pattern, spec) -> captures|nil` (the old `ns.Moments_FormatToPattern` / `ns.Moments_Match`, same behavior).
- Consumes: nothing new.

- [ ] **Step 1: Move the tests first (they fail until the code moves).** In `tests/test_moments.lua` cut the three tests "FormatToPattern handles %s, %d and magic characters", "FormatToPattern: positional specifiers (German) give captures in argument order" and "FormatToPattern: grammar tokens match either word and are cut from the capture" and paste them into `tests/test_format.lua` above `H.done()`, replacing every `ns.Moments_FormatToPattern` with `ns.FormatToPattern` and `ns.Moments_Match` with `ns.FormatMatch`. Keep "DiscoveredArea tries every pattern" in test_moments but change its two `ns.Moments_FormatToPattern` calls to `ns.FormatToPattern`. Add the Core file to the loaders:

```lua
-- tests/test_moments.lua, top
local ns = {}
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
assert(loadfile("Tomte/Modules/Moments/Data.lua"))("Tomte", ns)
```

```lua
-- tests/test_recap.lua, top (before Moments/Data.lua)
assert(loadfile("Tomte/Core/Format.lua"))("Tomte", ns)
```

- [ ] **Step 2: Run, see them fail.** `lua Tomte/tests/test_format.lua` -> FAIL "attempt to call field 'FormatToPattern' (a nil value)".

- [ ] **Step 3: Move the code verbatim.** Cut `Modules/Moments/Data.lua` lines 81-159 (`local CAPTURES ...` through the end of `ns.Moments_Match`) and append to `Core/Format.lua` under a ruler, renaming only the two functions and the comment that names them:

```lua
-- Blizzard format strings as patterns ----------------------------------------------------------------------------
-- Used by Moments (discoveries), Session recap (loot) and Friends Online (the "has come online" message).
```

then the moved block with `function ns.FormatToPattern(fmt)`, `function ns.FormatMatch(text, pattern, spec)`, and in the comments "a spec for FormatMatch" / "spec from FormatToPattern". Update the Format.lua header's first sentence to "Number, money and time text, and patterns for Blizzard's format strings, shared by every module."

- [ ] **Step 4: Update the callers.** `Modules/Moments/Data.lua:167` `ns.Moments_FormatToPattern(fmt)` -> `ns.FormatToPattern(fmt)`; `:183` and `:185` `ns.Moments_Match(` -> `ns.FormatMatch(`; the comment above `Moments_DiscoveredArea` says "FormatToPattern strings". `Modules/Recap/Data.lua:268` -> `ns.FormatToPattern(fmt)`. `Modules/Social/Friends.lua:298`:

```lua
		onlinePattern = ns.FormatToPattern(ERR_FRIEND_ONLINE_SS)
```

- [ ] **Step 5: Run.** `grep -rn "Moments_FormatToPattern\|Moments_Match" Tomte --include=*.lua` prints nothing. `lua Tomte/tests/test_format.lua`, `test_moments.lua`, `test_recap.lua` -> all passed. `luac -l Tomte/Core/Format.lua | grep -E 'GETGLOBAL'` lists only Lua globals (`math`, `tostring`, `type`, `ipairs`, `table`).

- [ ] **Step 6: In game.** `/reload`, then have a character friend (or an alt on the friend list of another account) log in: Friends Online still toasts. Discover a new area or loot something: no BugSack error from Moments or Session recap.

- [ ] **Step 7: Commit after confirmation.** `Move Moments_FormatToPattern into Core/Format.lua as ns.FormatToPattern (pure move)`. No CHANGELOG line.

## Task 2: Lower case that knows accented and Cyrillic capitals

**Files:**
- Modify: `Modules/Social/Data.lua` (new `ns.Social_Lower` above `WordByte` ~l.251; `ParseWords` l.230, `FindMention` l.268, `IsWatched` l.308)
- Modify: `Modules/Social/Mentions.lua:43`
- Modify: `Modules/Chat/Data.lua:42`, `:105`
- Modify: `tests/test_social.lua`, `tests/test_chat.lua`

**Interfaces:**
- Produces: `ns.Social_Lower(text) -> text` (same byte length as the input).
- Consumes: nothing.

- [ ] **Step 1: Failing tests.** Append to `tests/test_social.lua` before `H.done()`:

```lua
test("Lower: accented and Cyrillic capitals, byte length kept", function()
	eq(ns.Social_Lower("ÁSGEIR"), "ásgeir")
	eq(ns.Social_Lower("Ærø Ŝtål ŁÓDŹ"), "ærø ŝtål łódź")
	eq(ns.Social_Lower("ТОМТЕ Ёж"), "томте ёж")
	eq(ns.Social_Lower("Ÿ Ŀ"), "ÿ ŀ")
	eq(ns.Social_Lower("×ß İ"), "×ß İ", "no case, or a lower case of another length")
	local s = "Ásgeir ÖRN Ŀ İ Ж"
	eq(#ns.Social_Lower(s), #s, "same length")
end)

test("FindMention: accented capitals match either way", function()
	eq(ns.Social_FindMention("Hej Ásgeir!", ns.Social_ParseWords("ásgeir")), "ásgeir")
	eq(ns.Social_FindMention("hej ásgeir", ns.Social_ParseWords("Ásgeir")), "ásgeir")
	eq(ns.Social_FindMention("ÁSGEIRS", ns.Social_ParseWords("ásgeir")), nil, "still whole words")
end)

test("IsWatched: accented capitals match", function()
	eq(ns.Social_IsWatched(ns.Social_ParseWords("ásgeir"), "Ásgeir-Draenor"), true)
	eq(ns.Social_IsWatched(ns.Social_ParseWords("ÖRN"), "Örn#1234"), true)
end)
```

Append to `tests/test_chat.lua` before `H.done()`:

```lua
test("Keywords and highlight: accented capitals, original text kept", function()
	eq(ns.Chat_BuildKeywords({}, false, "Ásgeir")[1], "ásgeir")
	eq(ns.Chat_Highlight("LF ÖRN smith", { "örn" }, wrap), "LF <ÖRN> smith")
	eq(ns.Chat_Highlight("Ásgeir och ásgeir", { "ásgeir" }, wrap), "<Ásgeir> och <ásgeir>")
	eq(ns.Chat_Decide("Selling ÖRN boots", { "örn" }, {}), true)
end)
```

- [ ] **Step 2: Run, see them fail.** `lua Tomte/tests/test_social.lua` -> FAIL "attempt to call field 'Social_Lower'"; `lua Tomte/tests/test_chat.lua` -> FAIL on "Keywords and highlight".

- [ ] **Step 3: Implement** in `Modules/Social/Data.lua`, just above `-- A letter or digit (ASCII) ...`:

```lua
-- Lower case for names and keywords: string.lower only knows ASCII. Also Latin-1 (À-Þ), Latin Extended-A (Ā-ž) and
-- Cyrillic (Ѐ-Я; ruRU clients). Every mapped letter keeps its byte length, so a position found in the lower-case text
-- is valid in the original (Chat_Highlight relies on that). İ is left alone: its lower case is i plus a combining dot.
local function LowerCodepoint(cp)
	if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then
		return cp + 0x20
	elseif cp >= 0x100 and cp <= 0x17F then
		if cp == 0x178 then
			return 0xFF -- Ÿ -> ÿ
		elseif (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E) then
			return cp % 2 == 1 and cp + 1 or cp -- odd capitals
		elseif cp ~= 0x130 and (cp <= 0x137 or (cp >= 0x14A and cp <= 0x177)) then
			return cp % 2 == 0 and cp + 1 or cp -- even capitals
		end
	elseif cp >= 0x410 and cp <= 0x42F then
		return cp + 0x20
	elseif cp >= 0x400 and cp <= 0x40F then
		return cp + 0x50
	end
	return cp
end

-- A two-byte UTF-8 letter in lower case, or nil to keep it.
local function LowerPair(lead, cont)
	local cp = (lead:byte() - 0xC0) * 64 + (cont:byte() - 0x80)
	local lower = LowerCodepoint(cp)
	if lower == cp then
		return nil
	end
	return string.char(0xC0 + math.floor(lower / 64), 0x80 + lower % 64)
end

function ns.Social_Lower(text)
	return (text:lower():gsub("([\192-\223])([\128-\191])", LowerPair))
end
```

Then replace the ASCII-only calls (both sides of every comparison change together):

```lua
-- ParseWords (l.230)
		local word = ns.Social_Lower(part:match("^%s*(.-)%s*$"))
-- FindMention (l.268)
	local lower = ns.Social_Lower(ns.Social_PlainText(text))
-- IsWatched (l.308)
			local lower = ns.Social_Lower(name)
```

`Modules/Social/Mentions.lua:43`:

```lua
			table.insert(words, 1, ns.Social_Lower(name))
```

`Modules/Chat/Data.lua:42` and `:105` (Social/Data.lua loads earlier in the TOC and in test_chat):

```lua
		word = word and ns.Social_Lower(word:match("^%s*(.-)%s*$"))
```

```lua
	local lower = ns.Social_Lower(plain)
```

Update the comments "lower case, from ParseWords" stay true; ParseWords' comment says "lower-case words (ns.Social_Lower)".

- [ ] **Step 4: Run.** `lua Tomte/tests/test_social.lua` and `lua Tomte/tests/test_chat.lua` -> all passed.

- [ ] **Step 5: In game.** `/reload`. In Mentions settings set Keywords to `ásgeir`, then `/g Hej ÁSGEIR` from a guildmate (or have a friend say it): a Mention toast appears. With Trade Filter on and the keyword `örn`, a trade message "WTB ÖRN" is shown with "ÖRN" highlighted and nothing garbled around it.

- [ ] **Step 6: Commit after confirmation.** `Mentions: accented and Cyrillic capitals match keywords in any case`. CHANGELOG: "Mentions, Trade Filter and Friends Online: names and keywords with accented or Cyrillic capitals (Ásgeir, Örn) now match whatever their case."

## Task 3: New defaults for new installs (Friend sharing, Mentions, Group Alerts)

**Files:**
- Modify: `Core/Migrations.lua` (append migration 11; plan A takes 10, plan E takes 12)
- Modify: `tests/test_migrations.lua`
- Modify: `Modules/Share/Share.lua:486`
- Modify: `Modules/Social/Mentions.lua:176-177` (defaults), `:150-151` (flash tooltip unchanged)
- Modify: `Modules/Social/Alerts.lua:1-5` (header), `:52-58` (`Ring`), `:145-151` (`Test`), `:158-170` (options), `:179-191` (registration)
- Modify: `Modules/Social/Toast.lua:736-750` (`ns.Social_PlaySound`)

**Interfaces:**
- Produces: `ns.Social_PlaySound(choice, channel)` (channel `"Master"` default, or `"SFX"`); saved `alerts.channel`.
- Consumes: `PlaySound(soundKitID, channel)` (warcraft.wiki.gg/wiki/API_PlaySound: channels Master, Music, SFX, Ambience, Dialog, Talking Head).

- [ ] **Step 1: Failing migration tests.** In `tests/test_migrations.lua`, above "migrations don't run twice":

```lua
local NEW_DEFAULTS = 11 -- index of "new defaults are for new installs" in ns.MIGRATIONS

test("New defaults: an existing install keeps Friend sharing on and Group Alerts on Master", function()
	local db = { schema = NEW_DEFAULTS - 1, enabled = {}, alerts = { sound = "bell", repeats = 3 },
		mentions = { flash = true, sound = "chime" } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.enabled.share, true, "share pinned on")
	eq(db.alerts.channel, "Master", "alerts stay on Master")
	eq(db.alerts.repeats, 3, "saved repeats untouched")
	eq(db.mentions.flash, true, "saved flash untouched")
end)
test("New defaults: the player's own choices stay", function()
	local db = { schema = NEW_DEFAULTS - 1, enabled = { share = false }, alerts = { channel = "SFX" } }
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.enabled.share, false, "share off stays off")
	eq(db.alerts.channel, "SFX", "chosen channel stays")
end)
test("New defaults: a fresh install gets them, nothing pinned", function()
	local db = {}
	ns.Setup_MarkFresh(db)
	ns.RunMigrations(db, ns.MIGRATIONS)
	eq(db.enabled, nil, "no enabled table before Core merges its defaults")
	eq(db.alerts, nil, "no alerts table made")
	local old = { schema = NEW_DEFAULTS - 1, enabled = {} }
	ns.RunMigrations(old, ns.MIGRATIONS)
	eq(old.alerts, nil, "an install from before Group Alerts gets the new defaults")
end)
```

- [ ] **Step 2: Run, see them fail.** `lua Tomte/tests/test_migrations.lua` -> FAIL "share pinned on: expected true, got nil".

- [ ] **Step 3: Append the migration** to `ns.MIGRATIONS` in `Core/Migrations.lua`:

```lua
	-- 11: quieter defaults (Friend sharing off, Group Alerts once on the effects channel) are for new installs only.
	-- Core.lua merges its defaults, db.enabled among them, after the migrations: no enabled table here means a fresh
	-- install. Mentions' flash and sound and Group Alerts' repeats need nothing: every load saved their old defaults.
	function(db)
		if type(db.enabled) ~= "table" then
			return
		end
		if db.enabled.share == nil then
			db.enabled.share = true
		end
		if type(db.alerts) == "table" and db.alerts.channel == nil then
			db.alerts.channel = "Master"
		end
	end,
```

Also extend the file header's live fix-up sentence (Task 9 adds Chat Tabs to it).

- [ ] **Step 4: Run.** `lua Tomte/tests/test_migrations.lua` and `lua Tomte/tests/test_setup.lua` -> all passed.

- [ ] **Step 5: Change the defaults.** `Modules/Share/Share.lua:486`: `enabledByDefault = false,`. Mentions defaults:

```lua
		holdInCombat = true,
		flash = false,
		sound = "off",
```

and the header comment: "a toast (and, if you want, a taskbar flash and a sound) when someone says ...".

`Modules/Social/Toast.lua`:

```lua
-- Sound choices (ns.SOCIAL_SOUND_CHOICES). channel: "Master" (default: heard with sound effects off) or "SFX" (follows
-- the effects volume).
local SOUNDS = {
	...unchanged...
}

function ns.Social_PlaySound(choice, channel)
	local kit = SOUNDS[choice] and SOUNDKIT[SOUNDS[choice]]
	if kit then
		PlaySound(kit, channel or "Master")
	end
end
```

`Modules/Social/Alerts.lua`, header:

```lua
-- Group Alerts module: party invites, dungeon/raid finder and PvP queue pops, ready checks and summons get
-- a sound (on the effects channel by default, or Master to be heard with effects muted), optionally repeated until
-- you've answered, and a taskbar flash where Blizzard has none (summons). Blizzard's own popups and sounds stay.
```

Constants under `local POPUP_DELAY`:

```lua
local CHANNEL_CHOICES = {
	{ value = "SFX", text = "Effects" },
	{ value = "Master", text = "Master" },
}
```

`Ring` and `Test`:

```lua
local function Ring(alert)
	ns.Social_PlaySound(ns.alertsDB.sound, ns.alertsDB.channel)
	if alert.flash then
		FlashClientIcon()
	end
end
```

```lua
	ns.Social_PlaySound(ns.alertsDB.sound, ns.alertsDB.channel)
	FlashClientIcon()
```

Options (replace the sound dropdown row and add the channel row after it):

```lua
options[#options + 1] = { type = "dropdown", key = "sound", label = "Sound", onChange = function(value)
	ns.Social_PlaySound(value, ns.alertsDB.channel)
end, choices = function()
	return ns.SOCIAL_SOUND_CHOICES
end, tooltip = "Played on top of Blizzard's own sound." }
options[#options + 1] = { type = "dropdown", key = "channel", label = "Sound channel", onChange = function()
	ns.Social_PlaySound(ns.alertsDB.sound, ns.alertsDB.channel)
end, choices = function()
	return CHANNEL_CHOICES
end, tooltip = "Effects follows your sound effects volume and is silent with effects muted. Master is heard even with sound effects off." }
```

Registration:

```lua
	summary = "Invites, queue pops and summons you can't miss.",
	description = "Invites, queue pops, ready checks and summons you can't miss: a sound (once, or repeating until you've answered), and a taskbar flash for summons.",
	enabledByDefault = true,
	defaults = {
		on = { invite = true, lfg = true, pvp = true, readyCheck = true, summon = true },
		sound = "bell",
		channel = "SFX", -- "SFX" or "Master" (PlaySound channel)
		repeats = 0,
		interval = 5,
	},
```

- [ ] **Step 6: Run all tests** (loop in Global Constraints) -> no FAIL.

- [ ] **Step 7: In game.** `/reload` on the user's own install. Settings > Social & chat: Friend sharing is still on; Group Alerts shows Sound channel = Master and Repeat until answered = 3x; Mentions still has the flash and Chime. Click Group Alerts' Test: the bell plays as before. Switch Sound channel to Effects, mute sound effects in Options > Audio, click Test: silent; switch back to Master: heard. (A fresh-install check needs a copy of WTF without `TomteDB`; optional: rename `WTF\Account\<account>\SavedVariables\Tomte.lua` with the game closed, log in, see Friend sharing off, Mentions without flash/sound, Group Alerts on Effects with repeats off, then put the file back.)

- [ ] **Step 8: Commit after confirmation.** `Group Alerts, Mentions, Friend sharing: quieter defaults for new installs`. CHANGELOG: "New installs start quieter: Friend sharing off, Mentions without the taskbar flash and chime, Group Alerts ringing once on the sound effects channel. Existing installs keep their settings." and "Group Alerts: new Sound channel setting (Effects or Master)."

## Task 4: Presets leave the social modules alone; Crafter adds chat; new Social preset

**Files:**
- Modify: `Core/Setup.lua:1-120`
- Modify: `Panel/Setup.lua:8-11` (constants), `:114-127` (cards, footnote)
- Modify: `tests/test_setup.lua`

**Interfaces:**
- Produces: `ns.SETUP_UNTOUCHED` (module keys a preset only touches when it lists them); plans may omit modules (`plan.enabled[key] == nil`), Everything's plan is `{ clear = true, keep = { [key] = true } }`.
- Consumes: `ns.ModuleEnabled`, `ns.RefreshModule` (Core/Modules.lua).

- [ ] **Step 1: Failing tests.** In `tests/test_setup.lua`: in "presets come in the picker's order" replace the `[4]` line with

```lua
	eq(ns.SETUP_PRESETS[4].key, "social", "4")
	eq(ns.SETUP_PRESETS[5].key, "everything", "5")
```

In "crafter plan ..." replace `eq(plan.enabled.whispers, false, "whispers")` with

```lua
	eq(plan.enabled.whispers, nil, "whispers left alone")
	eq(plan.enabled.tradefilter, true, "trade filter")
	eq(plan.enabled.chattabs, true, "chat tabs")
```

In "OnNames lists ..." replace the everything line with

```lua
	eq(#ns.Setup_OnNames("everything", ns.modules), #ns.modules - 1 - #ns.SETUP_UNTOUCHED,
		"everything: every default-on module it touches")
```

Add before "existing user is marked done":

```lua
test("presets leave Whispers, Mentions, Friends Online and Group Alerts alone", function()
	Register()
	for _, key in ipairs({ "minimal", "collector", "crafter" }) do
		local plan = ns.Setup_Plan(key, ns.modules)
		for _, k in ipairs(ns.SETUP_UNTOUCHED) do
			eq(plan.enabled[k], nil, key .. " " .. k)
		end
	end
end)

test("Social turns the chat and social modules on", function()
	Register()
	local plan = ns.Setup_Plan("social", ns.modules)
	for _, k in ipairs({ "whispers", "mentions", "friends", "alerts", "share", "tradefilter", "chattabs", "chattags",
		"chatcopy", "recent", "way" }) do
		eq(plan.enabled[k], true, k)
	end
	eq(plan.enabled.gather, false, "gather")
	eq(plan.enabled.hunter, true, "class modules are base")
end)

test("a preset keeps the player's choice for the modules it leaves alone", function()
	Register()
	ns.SetModuleEnabled("whispers", false)
	ns.Setup_Apply(ns.db, ns.Setup_Plan("minimal", ns.modules), ns.modules)
	eq(ns.db.enabled.whispers, false, "minimal keeps it")
	eq(ns.Setup_Matches("minimal", ns.modules), true, "matches ignores it")
	ns.Setup_Apply(ns.db, ns.Setup_Plan("everything", ns.modules), ns.modules)
	eq(ns.db.enabled.whispers, false, "everything keeps it too")
	eq(ns.db.enabled.recap, nil, "everything clears the rest")
	eq(ns.Setup_Matches("everything", ns.modules), true, "matches")
	ns.Setup_Apply(ns.db, ns.Setup_Plan("social", ns.modules), ns.modules)
	eq(ns.db.enabled.whispers, true, "a preset that names it turns it on")
end)
```

- [ ] **Step 2: Run, see them fail.** `lua Tomte/tests/test_setup.lua` -> FAIL on "presets come in the picker's order" and the new tests.

- [ ] **Step 3: Implement in `Core/Setup.lua`.** Header comment, second sentence on: "A module that isn't in a preset's list is switched off by it, except the ones in SETUP_UNTOUCHED (left as they are unless the preset lists them); one added in a later Tomte version follows its own enabledByDefault until the user runs /tomte setup again."

```lua
ns.SETUP_BASE = { "minimap", "vendor", "dura", "hunter", "pet", "rogue" }

-- A preset (Everything too) leaves these as the player has them unless it lists them in `on`: switching someone's
-- whisper toasts or group alerts off is a surprise, not a preset.
ns.SETUP_UNTOUCHED = { "whispers", "mentions", "friends", "alerts" }

ns.SETUP_PRESETS = {
	{ key = "minimal", name = "Minimal", text = "Just the helpers, nothing pops up.",
		on = { "way", "mount", "tp", "gear" } },
	{ key = "collector", name = "Collector", text = "Mounts, pets, achievements, holidays and the places to get them.",
		on = { "way", "mount", "tp", "flight", "collect", "ach", "pets", "wq", "moments", "next", "recent", "events",
			"delves" } },
	{ key = "crafter", name = "Crafter", text = "Professions, gathering, alts, gold and trade chat.",
		on = { "way", "mount", "tp", "gear", "alts", "value", "weekly", "next", "recent", "gather", "fishing", "wgq",
			"tradefilter", "chattabs" } },
	{ key = "social", name = "Social", text = "Whispers, mentions, friends, group alerts and chat.",
		on = { "way", "mount", "tp", "recent", "whispers", "mentions", "friends", "alerts", "share", "tradefilter",
			"chattabs", "chattags", "chatcopy" } },
	{ key = "everything", name = "Everything", text = "All of Tomte, as it comes.", all = true },
}

local function UntouchedSet()
	local set = {}
	for _, k in ipairs(ns.SETUP_UNTOUCHED) do
		set[k] = true
	end
	return set
end
```

`ns.Setup_Plan`:

```lua
-- { clear = true, keep = set } for Everything (every module back to its default, except the untouched ones), else
-- { enabled = { [key] = bool } } for every module the preset decides (untouched ones only when it lists them).
function ns.Setup_Plan(key, modules)
	local preset = ns.Setup_Preset(key)
	if not preset then
		return nil, "unknown preset"
	end
	local untouched = UntouchedSet()
	if preset.all then
		return { clear = true, keep = untouched }
	end
	local on = {}
	for _, k in ipairs(ns.SETUP_BASE) do
		on[k] = true
	end
	for _, k in ipairs(preset.on) do
		on[k] = true
	end
	local enabled = {}
	for _, module in ipairs(modules) do
		if not module.alwaysOn and (on[module.key] or not untouched[module.key]) then
			enabled[module.key] = on[module.key] == true
		end
	end
	return { enabled = enabled }
end

-- Whether the plan decides module at all.
local function Touches(plan, module)
	if plan.clear then
		return not plan.keep[module.key]
	end
	return plan.enabled[module.key] ~= nil
end
```

In `ns.Setup_OnNames` the condition becomes `if not module.alwaysOn and Touches(plan, module) and Wants(plan, module) then`; in `ns.Setup_Matches` `if not module.alwaysOn and Touches(plan, module) and ns.ModuleEnabled(module) ~= Wants(plan, module) then`. In `ns.Setup_Apply`:

```lua
	if plan.clear then
		for k in pairs(db.enabled) do
			if not plan.keep[k] then
				db.enabled[k] = nil
			end
		end
	else
```

- [ ] **Step 4: Run.** `lua Tomte/tests/test_setup.lua` -> all passed.

- [ ] **Step 5: Picker layout (`Panel/Setup.lua`).** Five cards: the named presets in two columns, Everything as a short card across the bottom.

```lua
local W, H = 660, 600
local PAD = 16
local CARD_W = (W - PAD * 2 - 12) / 2
local CARD_H = 172
local WIDE_H = 72 -- Everything: one line of text, across the window
```

```lua
	frame.cards = {}
	for i, preset in ipairs(ns.SETUP_PRESETS) do
		local card = CreateCard(frame, preset)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		if preset.all then
			col = 0
			card:SetSize(W - PAD * 2, WIDE_H)
		end
		card:SetPoint("TOPLEFT", PAD + col * (CARD_W + 12), -70 - row * (CARD_H + 12))
		frame.cards[i] = card
	end
```

Footnote:

```lua
	foot:SetText("Hunter Pets, Pet Health and Rogue Poisons only wake up on that class. Whispers, Mentions, Friends "
		.. "Online and Group Alerts stay as they are unless a preset names them. Settings inside modules don't change.")
```

Move `foot` up to leave room for two lines: `foot:SetPoint("BOTTOMLEFT", PAD, 40)`.

- [ ] **Step 6: In game.** `/reload`, `/tomte setup`: five cards, Everything across the bottom, no card overlapping another or the footnote, every "Turns on" line fits its card. Turn Whispers off in settings, pick Minimal, Use this: Whispers is still off and Minimal shows "matches your setup now" when reopening `/tomte setup`. Pick Social: Whispers, Mentions, Trade Filter, Chat Tabs ... on. Put the user's own setup back afterwards (Choose myself).

- [ ] **Step 7: Commit after confirmation.** `Setup: Social preset, presets leave whispers and alerts alone`. CHANGELOG: "Setup: a new Social preset (whispers, mentions, friends, group alerts and chat). Presets no longer switch Whispers, Mentions, Friends Online and Group Alerts off, and Crafter also turns on Trade Filter and Chat Tabs."

## Task 5: Whisper conversations per character (pure logic)

**Files:**
- Modify: `Modules/Social/Data.lua:41-67` (`Social_AddMessage`), new functions after it, `:190-205` (`MarkAllRead`, `Unread`), `:176` (`Inbox_CopyText`)
- Modify: `tests/test_social.lua`

**Interfaces:**
- Produces: `ns.Social_ConvoKey(with, guid) -> key`, `ns.Social_With(convo) -> "Name-Realm" | "bn:Tag"`, `ns.Social_IsMine(convo, guid) -> bool`, `ns.Social_AddMessage(store, key, info, entry) -> convo, claimedKey|nil` (info gains `with`, `char`, `charName`), `ns.Social_Unread(store, guid?)`, `ns.Social_MarkAllRead(store, guid?)`.
- Consumes: nothing.

- [ ] **Step 1: Failing tests.** Append to `tests/test_social.lua`:

```lua
local ME, ALT = "Player-1-AAAA", "Player-1-BBBB"

test("ConvoKey: character whispers per character, Battle.net per account", function()
	eq(ns.Social_ConvoKey("Kesha-Draenor", ME), "Kesha-Draenor@" .. ME)
	eq(ns.Social_ConvoKey("bn:Kesha#1234", ME), "bn:Kesha#1234")
	eq(ns.Social_ConvoKey("Kesha-Draenor", nil), "Kesha-Draenor")
end)

test("AddMessage tags the conversation; two characters keep two conversations", function()
	local store = newStore()
	local a = ns.Social_AddMessage(store, ns.Social_ConvoKey("Kesha-Draenor", ME),
		{ name = "Kesha", with = "Kesha-Draenor", char = ME, charName = "Aldric" }, { at = 1, text = "hi" })
	local b = ns.Social_AddMessage(store, ns.Social_ConvoKey("Kesha-Draenor", ALT),
		{ name = "Kesha", with = "Kesha-Draenor", char = ALT, charName = "Mira" }, { at = 2, text = "hey" })
	eq(a ~= b, true, "two conversations")
	eq(a.char, ME)
	eq(a.charName, "Aldric")
	eq(ns.Social_With(a), "Kesha-Draenor")
	eq(ns.Social_With(b), "Kesha-Draenor")
	eq(ns.Social_With({ key = "Old-Draenor" }), "Old-Draenor", "untagged: the key")
end)

test("IsMine: tagged ones are their character's, untagged ones everyone's", function()
	eq(ns.Social_IsMine({ char = ME }, ME), true)
	eq(ns.Social_IsMine({ char = ALT }, ME), false)
	eq(ns.Social_IsMine({}, ME), true)
end)

test("Unread and MarkAllRead count only this character's and untagged conversations", function()
	local store = newStore()
	ns.Social_AddMessage(store, "Old-Draenor", {}, { at = 1, text = "x" })
	ns.Social_AddMessage(store, "Kesha-Draenor@" .. ME, { with = "Kesha-Draenor", char = ME }, { at = 2, text = "x" })
	ns.Social_AddMessage(store, "Kesha-Draenor@" .. ALT, { with = "Kesha-Draenor", char = ALT }, { at = 3, text = "x" })
	ns.Social_AddMessage(store, "bn:Mira#1", { bn = true, with = "bn:Mira#1" }, { at = 4, text = "x" })
	local total, convos = ns.Social_Unread(store, ME)
	eq(total, 3, "mine, untagged and Battle.net")
	eq(#convos, 3)
	eq((ns.Social_Unread(store)), 4, "no GUID: all")
	ns.Social_MarkAllRead(store, ME)
	eq((ns.Social_Unread(store, ME)), 0)
	eq(store.convos["Kesha-Draenor@" .. ALT].unread, 1, "the alt's stays unread")
end)

test("AddMessage: an untagged conversation is claimed by the first character that whispers with them", function()
	local store = newStore()
	ns.Social_AddMessage(store, "Kesha-Draenor", { name = "Kesha" }, { at = 1, text = "old" })
	store.convos["Kesha-Draenor"].pinned = true
	local key = ns.Social_ConvoKey("Kesha-Draenor", ME)
	local convo, claimed = ns.Social_AddMessage(store, key,
		{ with = "Kesha-Draenor", char = ME, charName = "Aldric" }, { at = 2, text = "new" })
	eq(claimed, "Kesha-Draenor")
	eq(store.convos["Kesha-Draenor"], nil, "old key gone")
	eq(store.convos[key], convo)
	eq(convo.key, key)
	eq(#convo.messages, 2, "messages kept")
	eq(convo.pinned, true, "pin kept")
	eq(convo.name, "Kesha", "name kept")
	local _, again = ns.Social_AddMessage(store, ns.Social_ConvoKey("Kesha-Draenor", ALT),
		{ with = "Kesha-Draenor", char = ALT }, { at = 3, text = "alt" })
	eq(again, nil, "a tagged one isn't claimed")
end)

test("CopyText names a tagged conversation by who it's with", function()
	local convo = { key = "Kesha-Draenor@" .. ME, with = "Kesha-Draenor", messages = { { at = 1, text = "hi" } } }
	eq(ns.Inbox_CopyText(convo, function()
		return "t"
	end), "t Kesha-Draenor: hi")
end)
```

- [ ] **Step 2: Run, see them fail.** `lua Tomte/tests/test_social.lua` -> FAIL "attempt to call field 'Social_ConvoKey'".

- [ ] **Step 3: Implement** in `Modules/Social/Data.lua`. Replace the comment and `ns.Social_AddMessage`:

```lua
-- store = { convos = { [key] = convo } }, convo = { key, with, char, charName, name, class, bn, last, unread, pinned,
-- messages }. Whispers with a character are per character of yours: key = ns.Social_ConvoKey(with, your GUID), with =
-- their "Name-Realm", char = your GUID, charName = your character's name. Battle.net whispers reach your account:
-- key = with = "bn:BattleTag", no char. Conversations saved before tagging have neither with nor char.
-- info = { name, class, bn, with, char, charName } (kept up to date: a later whisper may know the class);
-- entry = { at, text, out }. An outgoing message (entry.out) marks the conversation read: you answered it.
-- An untagged conversation is claimed by the first tagged message with the same person: it moves to the new key and
-- keeps its messages and pin. Returns the conversation and the key it was claimed from (nil when none).
function ns.Social_AddMessage(store, key, info, entry)
	local convo, claimed = store.convos[key], nil
	if not convo and info.with and info.with ~= key then
		local old = store.convos[info.with]
		if old and old.char == nil then
			store.convos[info.with] = nil
			old.key = key
			store.convos[key] = old
			convo, claimed = old, info.with
		end
	end
	if not convo then
		convo = { key = key, unread = 0, messages = {} }
		store.convos[key] = convo
	end
	convo.with = info.with or convo.with
	convo.char = info.char or convo.char
	convo.charName = info.charName or convo.charName
	convo.name = info.name or convo.name
	convo.class = info.class or convo.class
	convo.bn = info.bn or convo.bn
	convo.last = entry.at
	local messages = convo.messages
	messages[#messages + 1] = entry
	while #messages > MAX_MESSAGES do
		table.remove(messages, 1)
	end
	if entry.out then
		convo.unread = 0
	else
		convo.unread = convo.unread + 1
	end
	ns.Social_TrimConvos(store, MAX_CONVERSATIONS)
	return convo, claimed
end

-- A conversation's key: per character of yours (guid) for a character, one per account for Battle.net ("bn:...").
function ns.Social_ConvoKey(with, guid)
	if not guid or with:sub(1, 3) == "bn:" then
		return with
	end
	return with .. "@" .. guid
end

-- Who to whisper: "Name-Realm" or "bn:BattleTag" (an untagged conversation's key is that already).
function ns.Social_With(convo)
	return convo.with or convo.key
end

-- Whether the character with this GUID can answer it: its own, untagged (old or Battle.net) ones.
function ns.Social_IsMine(convo, guid)
	return convo.char == nil or convo.char == guid
end
```

`MarkAllRead` and `Unread`:

```lua
-- guid (optional): only conversations that are that character's (ns.Social_IsMine).
function ns.Social_MarkAllRead(store, guid)
	for _, convo in pairs(store.convos) do
		if not guid or ns.Social_IsMine(convo, guid) then
			convo.unread = 0
		end
	end
end

-- Total unread messages and the unread conversations, newest first. guid (optional): only that character's
-- conversations (ns.Social_IsMine).
function ns.Social_Unread(store, guid)
	local total, convos = 0, {}
	for _, convo in ipairs(ns.Social_SortedConvos(store)) do
		if convo.unread > 0 and (not guid or ns.Social_IsMine(convo, guid)) then
			total = total + convo.unread
			convos[#convos + 1] = convo
		end
	end
	return total, convos
end
```

`Inbox_CopyText`: `(convo.name or ns.Social_With(convo))` in place of `(convo.name or convo.key)`.

- [ ] **Step 4: Run.** `lua Tomte/tests/test_social.lua` -> all passed (the older AddMessage/Unread tests too: their calls pass no `with`/guid).

- [ ] **Step 5: No commit yet**: Task 6 wires it; they are confirmed and committed together.

## Task 6: Whisper inbox per character (module and window)

**Files:**
- Modify: `Modules/Social/Whispers.lua` (functions `UnreadTotal` l.63, `Whispers_MarkAllRead` l.113, `Whispers_Reply` l.155, `Whispers_Send` l.189, `Incoming` l.287, `CHAT_MSG_WHISPER` l.311, `CHAT_MSG_BN_WHISPER` l.328, `Outgoing` l.344, both INFORM handlers l.350-372, `ClearHistory` confirm l.477, defaults l.522)
- Modify: `Modules/Social/Inbox.lua` (`Inbox_ColoredName` l.35, `OpenMenu` l.91, `ShowConversation` l.129, `SetRow` l.237, `Build` l.428, `Inbox_Toggle` l.530, new `ns.Inbox_Rekey`)
- Modify: `Modules/Social/InboxWho.lua:86-133`

**Interfaces:**
- Produces: `ns.Whispers_IsMine(convo) -> bool`, `ns.Inbox_Rekey(oldKey, newKey)`.
- Consumes: `ns.Social_ConvoKey`, `ns.Social_With`, `ns.Social_IsMine`, `ns.Social_AddMessage` (second return), `ns.Social_Unread(store, guid)`, `ns.Social_MarkAllRead(store, guid)`.

- [ ] **Step 1: Whispers.lua.** Add below `FullName`:

```lua
-- Who you are now: character conversations are tagged with it.
local function Me()
	return UnitGUID("player"), UnitName("player")
end

-- Whether convo can be answered from this character (its own, untagged, Battle.net or the instance one).
function ns.Whispers_IsMine(convo)
	return convo ~= nil and ns.Social_IsMine(convo, (Me()))
end
```

```lua
local function UnreadTotal()
	local total, convos = ns.Social_Unread(Store(), (Me()))
	return total + restricted.unread, convos
end
```

```lua
function ns.Whispers_MarkAllRead()
	ns.Social_MarkAllRead(Store(), (Me()))
	restricted.unread = 0
	Changed()
end
```

`ns.Whispers_Reply`, after `local convo = Store().convos[key]` / `if not convo then return end`:

```lua
	if not ns.Whispers_IsMine(convo) then
		ns.Print(("that conversation is on %s: log in there to answer."):format(convo.charName or "another character"))
		return
	end
	local target = ns.Social_With(convo)
	if convo.bn then
		local token = bnTokens[key]
		if not token then
			local friend = FindBNetFriend(target:sub(4))
			token = friend and friend.accountName
		end
		if token then
			ChatFrameUtil.SendBNetTell(token)
		else
			ns.Print(convo.name .. " isn't online on Battle.net.")
		end
		return
	end
	ChatFrameUtil.SendTell(target)
```

`ns.Whispers_Send`, after `local convo = Store().convos[key]`:

```lua
	if convo and not ns.Whispers_IsMine(convo) then
		ns.Print(("that conversation is on %s: log in there to answer."):format(convo.charName or "another character"))
		return false
	end
	local target = convo and ns.Social_With(convo) or key
```

and in its body `FindBNetFriend(target:sub(4))` and `pcall(C_ChatInfo.SendChatMessage, text, "WHISPER", nil, target)`.

`Incoming`, non-secret branch (the `viewing` line moves into each branch, since a claim changes the key):

```lua
local function Incoming(info)
	local viewing
	if info.secret then
		viewing = ns.Inbox_IsShowing(info.key)
		...unchanged secret branch...
	else
		local convo, claimed = ns.Social_AddMessage(Store(), info.key, { name = info.digestName, class = info.class,
			bn = info.bn, with = info.with, char = info.char, charName = info.charName }, { at = time(), text = info.text })
		if claimed then
			ns.Inbox_Rekey(claimed, convo.key)
		end
		viewing = ns.Inbox_IsShowing(info.key)
		if viewing then
			ns.Social_MarkRead(Store(), info.key)
		end
	end
	Changed()
	PlayWhisperSound()
	if not viewing then
		Toast(info)
	end
end
```

`CHAT_MSG_WHISPER`, last lines:

```lua
	local short = Ambiguate(sender, "short")
	local with = FullName(sender)
	local me, myName = Me()
	Incoming({ key = ns.Social_ConvoKey(with, me), with = with, char = me, charName = myName, name = short,
		digestName = short, class = class, text = text, gm = Readable(flags) and (flags == "GM" or flags == "DEV") })
```

`CHAT_MSG_BN_WHISPER`: `Incoming({ key = key, with = key, name = sender, ...})`.

`Outgoing` and the INFORM handlers:

```lua
local function Outgoing(key, text, info)
	local convo, claimed = ns.Social_AddMessage(Store(), key, info, { at = time(), text = text, out = true })
	if claimed then
		ns.Inbox_Rekey(claimed, convo.key)
	end
	Changed()
end
```

```lua
	local with = FullName(target)
	local me, myName = Me()
	Outgoing(ns.Social_ConvoKey(with, me), text, { name = Ambiguate(target, "short"), with = with, char = me,
		charName = myName })
```

```lua
		Outgoing(key, text, { name = ns.Social_ShortTag(info.battleTag), bn = true, with = key })
```

History button: `confirm = "Forget all whisper conversations, on every character?"`. Defaults comment:

```lua
		-- convos[key] = { key, with, char, charName, name, class, bn, last, unread, pinned, messages } (Data.lua);
		-- char = which of your characters (GUID), none for Battle.net and conversations from before 1.16
		store = { convos = {} },
```

Header comment: add "Conversations with characters are per character of yours; the unread counts and the recap only count the one you're on."

- [ ] **Step 2: Inbox.lua.**

```lua
function ns.Inbox_ColoredName(convo)
	local name = convo.name or ns.Social_With(convo)
```

`OpenMenu`: `local name = convo.name or ns.Social_With(convo)`, `local mine = ns.Whispers_IsMine(convo)`, and `if mine and ns.InboxWho_CanInvite(who) then` / `if mine and ns.InboxWho_CanAddFriend(convo, who) then`.

`ShowConversation`, top part:

```lua
	local convo = current and ns.Whispers_Get(current)
	local mine = ns.Whispers_IsMine(convo)
	local header = frame.header
	-- Secret "In instance" whispers can only be answered through Blizzard's chat box.
	header.reply:SetShown(convo ~= nil and convo.restricted == true)
	frame.input:SetShown(convo ~= nil and not convo.restricted and mine)
	frame.elsewhere:SetShown(convo ~= nil and not mine)
	header:SetShown(convo ~= nil)
	...
	if not convo.restricted then
		frame.input.placeholder:SetText("Whisper " .. (convo.name or ns.Social_With(convo)))
	end
	if not mine then
		frame.elsewhere:SetText(("Log in on %s to answer."):format(convo.charName or "that character"))
	end
	...
	local status = convo.restricted and "Names and messages are hidden from addons in instances"
		or ns.Inbox_StatusText(who)
	if not mine then
		status = ("On %s · %s"):format(convo.charName or "another character", status)
	end
	header.status:SetText(status)
	header.invite:SetShown(mine and ns.InboxWho_CanInvite(who))
```

`SetRow`:

```lua
	local mine = ns.Whispers_IsMine(convo)
	local name = ns.Inbox_ColoredName(convo)
	if not mine then
		name = name .. " " .. UI.Wrap("on " .. (convo.charName or "another character"), "textFaint")
	end
	row.name:SetText(name)
	local unread = mine and convo.unread or 0
```

`Build`, after `frame.input = CreateInput(right)`:

```lua
	frame.elsewhere = UI.Text(right, 12, "textFaint") -- in place of the chat line for another character's conversation
	frame.elsewhere:SetPoint("BOTTOMLEFT", 10, 6)
	frame.elsewhere:Hide()
```

`ns.Inbox_Toggle`: `if convo.unread > 0 and ns.Whispers_IsMine(convo) then`. New function after `ns.Inbox_IsShowing`:

```lua
-- An untagged conversation was claimed by this character and moved to a new key (Whispers.lua): keep it open.
function ns.Inbox_Rekey(old, new)
	if current == old then
		current, drawn = new, nil
	end
end
```

- [ ] **Step 3: InboxWho.lua.** In `ns.InboxWho_Get` use `local with = ns.Social_With(convo)` and replace `convo.key` with `with` in `BNetFriend(with)`, `CharacterFriend(with)`, `Guild()[with]`, `who.inviteName = with`; `ns.InboxWho_AddFriend`: `C_FriendList.AddFriend(ns.Social_With(convo))`.

- [ ] **Step 4: Grep for leftover targets.** `grep -n "convo.key\|SendTell(key\|nil, key)\|key:sub(4)" Tomte/Modules/Social/*.lua` may only show list/selection uses (`row.key = convo.key`, `drawn.key`, `key = convo.key` in Toggle, `Inbox_Order`), never a whisper target or friend lookup. Run all tests -> no FAIL. `luac -l Tomte/Modules/Social/Whispers.lua | grep GETGLOBAL` lists only WoW API (`UnitGUID`, `UnitName`, `C_ChatInfo`, ...).

- [ ] **Step 5: In game.** `/reload`. Have a friend whisper the character (or whisper an alt on another account): toast; click it: the chat box opens on the right name; reply from the inbox chat line: it arrives. Open the inbox: old conversations from before show as before (no "on ..."). Log out to another character, `/reload`: the first character's new conversation shows "Kesha on Aldric", no unread badge, the Home "Whisper inbox" count doesn't include it; opening it shows "On Aldric · ..." and "Log in on Aldric to answer." instead of the chat line, and no Invite button; right-click has no Invite/Add friend. A Battle.net whisper shows on both characters and can be answered from either. Go AFK and come back with an unread whisper on this character only: the recap counts only this character's.

- [ ] **Step 6: Commit after confirmation** (Tasks 5 and 6 together). `Whispers: conversations per character, counts follow the character you're on`. CHANGELOG: "Whispers: the inbox shows which of your characters each conversation is with. Unread counts, the Home count and the back-from-AFK recap only count the character you're on; other characters' conversations show "on <name>" and can be read but not answered from here. Battle.net whispers still show on every character."

## Task 7: Mentions from a community channel

**Files:**
- Modify: `Modules/Social/Mentions.lua:59-81` (`ShowMention`), `:83-103` (`OnChat`)

**Interfaces:**
- Consumes: `CHAT_MSG_COMMUNITIES_CHANNEL` payload (warcraft.wiki.gg: text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, ...), `ChatFrameUtil.OpenChat`.

- [ ] **Step 1: Code.** `ShowMention(label, sender, class, text, slash, preview, community)`, its `onClick`:

```lua
		onClick = function()
			if preview then
				return
			end
			if slash then
				ChatFrameUtil.OpenChat(slash)
			elseif community then
				-- Blizzard's Communities window isn't opened from addon code (taint): say where to answer instead.
				ns.Print("Mentions: that community channel isn't in any chat window, so there's no chat line to open. "
					.. "Answer in the Communities window.")
			end
		end,
```

In `OnChat`:

```lua
	local channel = CHANNELS[event]
	local label, slash = channel[1], channel[3]
	-- A channel (or a community stream added to a chat window) has a number to type in.
	local numbered = type(channelIndex) == "number" and channelIndex > 0
	if event == "CHAT_MSG_CHANNEL" then
		label = (channelBaseName and channelBaseName ~= "") and channelBaseName or label
		slash = numbered and ("/" .. channelIndex .. " ") or nil
	elseif event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
		slash = numbered and ("/" .. channelIndex .. " ") or nil
	end
	...
	ShowMention(label, Ambiguate(sender, "short"), class, text, slash, nil, event == "CHAT_MSG_COMMUNITIES_CHANNEL")
```

Header comment: "Left-click opens the chat box in that channel (a community only when its stream is in a chat window)."

- [ ] **Step 2: In game.** `/reload`, Mentions > "Channels and communities" on. In a community whose stream is shown in a chat tab, have someone write your name: click the toast -> the chat line opens with `/<number> `. Remove that stream from every chat window (right-click the tab > Settings > Channels), repeat: clicking prints the "isn't in any chat window" line. Use `/etrace` filtered to CHAT_MSG_COMMUNITIES_CHANNEL if the toast doesn't come, and paste the arguments.

- [ ] **Step 3: Commit after confirmation.** `Mentions: clicking a community mention opens its chat line or says why not`. CHANGELOG: "Mentions: clicking a mention from a community channel opens that channel's chat line, or says why it can't."

## Task 8: Trade Filter pause lasts one play session

**Files:**
- Modify: `Modules/Chat/Filter.lua:159-172` (`PLAYER_ENTERING_WORLD`), after it (file-load registration), `:253-254` (option tooltip), `:307` (defaults comment)

**Interfaces:**
- Consumes: `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)` (warcraft.wiki.gg: isInitialLogin true on login, false on /reload and zoning).

- [ ] **Step 1: Code.**

```lua
-- Professions can still be missing at the first loading screen: look again a little later before warning.
-- Also watched once from file load, module on or off: "Pause the filter" lasts one play session (a forgotten pause
-- would leave Trade unfiltered for good). A /reload keeps it.
local worldEntered = false
function events:PLAYER_ENTERING_WORLD(isInitialLogin)
	if isInitialLogin and module.db.paused then
		module.db.paused = false
	end
	if not module.active then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		return
	end
	playerGUID = UnitGUID("player")
	...unchanged...
end
events:RegisterEvent("PLAYER_ENTERING_WORLD")
```

Option row:

```lua
	{ type = "checkbox", key = "paused", label = "Pause the filter",
		tooltip = "Show everything until you log out, for when you're shopping. Nothing is hidden or toasted while paused." },
```

Defaults: `paused = false, -- until logout: cleared on the next login (PLAYER_ENTERING_WORLD)`.

- [ ] **Step 2: In game.** Trade Filter on, tick "Pause the filter", `/reload`: still ticked and Trade shows everything. Log out to character select and back in: unticked, Trade filtered again. With the module off, log in: no error in BugSack.

- [ ] **Step 3: Commit after confirmation.** `Trade Filter: pausing lasts until you log out`. CHANGELOG: "Trade Filter: "Pause the filter" now lasts until you log out instead of forever."

## Task 9: Chat Tabs keys its record by character GUID

**Files:**
- Modify: `Modules/Chat/Data.lua` (new `ns.Chat_TabsRecord` at the end, under a `-- Chat Tabs` ruler)
- Modify: `Modules/Chat/Tabs.lua:20-39` (`CharacterKey`, `State`), `:192` (`Restore`), `:275` (defaults comment)
- Modify: `Core/Migrations.lua:3-5` (header comment)
- Modify: `tests/test_chat.lua`

**Interfaces:**
- Produces: `ns.Chat_TabsRecord(windows, guid, oldKey) -> record|nil`.

- [ ] **Step 1: Failing tests** in `tests/test_chat.lua`:

```lua
test("TabsRecord: the character's old Name-Realm record moves to its GUID", function()
	local rec = { index = 5, added = {} }
	local windows = { ["Aldric-Draenor"] = rec, ["Mira-Draenor"] = { index = 6 } }
	eq(ns.Chat_TabsRecord(windows, "Player-1-A", "Aldric-Draenor"), rec)
	eq(windows["Player-1-A"], rec, "under the GUID")
	eq(windows["Aldric-Draenor"], nil, "old key gone")
	eq(windows["Mira-Draenor"].index, 6, "other characters wait for their login")
end)

test("TabsRecord: a GUID record wins, a leftover old one goes, nothing saved is nil", function()
	local mine = { index = 7 }
	local windows = { ["Player-1-A"] = mine, ["Aldric-Draenor"] = { index = 5 } }
	eq(ns.Chat_TabsRecord(windows, "Player-1-A", "Aldric-Draenor"), mine)
	eq(windows["Aldric-Draenor"], nil)
	eq(ns.Chat_TabsRecord({}, "Player-1-A", "Aldric-Draenor"), nil)
end)
```

- [ ] **Step 2: Run, see them fail.** `lua Tomte/tests/test_chat.lua` -> FAIL "attempt to call field 'Chat_TabsRecord'".

- [ ] **Step 3: Implement** in `Modules/Chat/Data.lua`:

```lua
-- Chat Tabs ------------------------------------------------------------------------------------------------------

-- Chat Tabs' record for a character in windows ([player GUID] = record). Before 1.16 records were keyed "Name-Realm"
-- (oldKey): a character's own old record moves to its GUID on its first lookup (a migration can't know GUIDs); other
-- characters' move when they log in. Returns the record, or nil when there is none.
function ns.Chat_TabsRecord(windows, guid, oldKey)
	local record = windows[guid]
	local old = oldKey and oldKey ~= guid and windows[oldKey]
	if type(old) == "table" then
		windows[oldKey] = nil
		if type(record) ~= "table" then
			record = old
			windows[guid] = old
		end
	end
	return type(record) == "table" and record or nil
end
```

`Modules/Chat/Tabs.lua`:

```lua
-- Records were keyed like this before 1.16 (ns.Chat_TabsRecord moves this character's to its GUID).
local function OldCharacterKey()
	return (UnitName("player") or "?") .. "-" .. (GetNormalizedRealmName() or "?")
end

-- This character's record: { index, name, created, added = { [zoneID] = name }, removed = { [zoneID] = name } },
-- or nil (create = make one).
local function State(create)
	local guid = UnitGUID("player")
	local state = ns.Chat_TabsRecord(module.db.windows, guid, OldCharacterKey())
	if not state then
		if not create then
			return nil
		end
		state = {}
		module.db.windows[guid] = state
	end
	state.added = state.added or {}
	state.removed = state.removed or {}
	return state
end
```

`Restore`: `module.db.windows[UnitGUID("player")] = nil`. Defaults: `windows = {}, -- [player GUID] = what Tomte changed for that character, see State(); "Name-Realm" keys from before 1.16 until that character logs in`. `Core/Migrations.lua` header: "Fix-ups that need live game data stay in their modules: Gear_MigrateHinted (Gear), Session.lua's name/class re-fill and Chat Tabs' Name-Realm records (ns.Chat_TabsRecord)."

- [ ] **Step 4: Run.** `lua Tomte/tests/test_chat.lua` -> all passed; `lua Tomte/tests/test_migrations.lua` -> all passed.

- [ ] **Step 5: In game.** With Chat Tabs on (the user's Trade tab exists), `/reload`: no second Trade tab opens, and `/dump TomteDB.chattabs.windows` shows the record under `Player-...` and no `Name-Realm` key for this character. Click "Restore my chat": the tab closes and the main window gets its channels back; turn the module on again: the tab comes back.

- [ ] **Step 6: Commit after confirmation.** `Chat Tabs: remember the tab per character GUID`. CHANGELOG: "Chat Tabs: keeps track of the tab it opened after a character rename or realm transfer."

## Task 10: Chat Copy names the right settings group

**Files:**
- Modify: `Modules/Chat/Copy.lua:83`

**Interfaces:**
- Consumes: `ns.PanelLayout_Group(key) -> { name, ... }` (Panel/Layout.lua, looked up at call time).

- [ ] **Step 1: Code** (skip if plan A's central "module is off" check already replaced this line):

```lua
	if not module.active then
		ns.Print(("Chat Copy is off. Turn it on in /tomte (%s)."):format(ns.PanelLayout_Group(module.category).name))
		return
	end
```

- [ ] **Step 2: In game.** Chat Copy off, type `/tomte chatcopy` (its fallback command) or press its key binding: prints "Chat Copy is off. Turn it on in /tomte (Social & chat)."

- [ ] **Step 3: Commit after confirmation.** `Chat Copy: the off message names the Social & chat group`. CHANGELOG: "Chat Copy: its "off" message points to the right settings group."

## Task 11: Recent's Include list comes from the modules; Home block Clear asks first

**Files:**
- Modify: `Modules/Recent/Data.lua` (new `ns.Recent_Owners` at the end; header)
- Modify: `Modules/Recent/Recent.lua:16-23` (remove `OWNERS`), `:225-249` (options and `Defaults`), `:289` (block Clear), `:378` (`init`)
- Modify: `Modules/Social/Toast.lua:14` (header: a module calling Toast_Show declares `toasts`)
- Modify (one line `toasts = ...` right after `enabledByDefault` in the registration):
  `Modules/Social/Whispers.lua` (`true`), `Modules/Social/Mentions.lua` (`true`), `Modules/Social/Friends.lua:372` (`"Friends online"`), `Modules/Gear/Gear.lua:223` (`"Gear upgrades"`), `Modules/Achievements/Achievements.lua:390` (`"Almost Done"`), `Modules/Collect/Collect.lua:287` (`true`), `Modules/WorldQuests/WorldQuests.lua:202` (`true`), `Modules/Holidays/Holidays.lua:546` (`true`), `Modules/Gather/Gather.lua:425` (`true`), `Modules/Chat/Filter.lua` (`true`), `Modules/Weekly/Weekly.lua:438` (`"Concentration"`), `Modules/Upkeep/Durability.lua:170` (`true`), `Modules/Upkeep/Vendor.lua:195` (`"Vendor"`), `Modules/Recap/Recap.lua:388` (`"Session recap"`), `Modules/Moments/Moments.lua:700` (`"Moments (banners)"`), `Modules/Hunter/Hunter.lua:81` (`"Hunter pet check (banners)"`), `Modules/Combat/PetHealth.lua:366` (`"Pet health (banners)"`), `Modules/Rogue/Rogue.lua:408` (`"Rogue poison check (banners)"`), `Modules/Share/Share.lua:486` (`true`)
- Modify: `tests/test_recent.lua`

**Interfaces:**
- Produces: module field `toasts` (`true` = label is the module name, or a label string); `ns.Recent_Owners(modules) -> { { key, label } }`.

- [ ] **Step 1: Failing tests** in `tests/test_recent.lua`:

```lua
test("Owners: modules that declare toasts, in registration order, with their label", function()
	local list = ns.Recent_Owners({
		{ key = "gear", name = "Gear Check", toasts = "Gear upgrades" },
		{ key = "mount", name = "Smart Mount" },
		{ key = "wq", name = "World quests", toasts = true },
	})
	eq(#list, 2)
	eq(list[1].key, "gear")
	eq(list[1].label, "Gear upgrades")
	eq(list[2].key, "wq")
	eq(list[2].label, "World quests")
end)

-- Owners named in files that show toasts or banners, and the modules that declare toasts, read from the source: a
-- new toast owner without a Recent checkbox fails here.
test("every module that shows toasts or banners declares toasts", function()
	local owners, declared = {}, {}
	for line in io.lines("Tomte/Tomte.toc") do
		local file = line:match("^([%w_/\\]+%.lua)%s*$")
		if file then
			local path = "Tomte/" .. file:gsub("\\", "/")
			local f = assert(io.open(path))
			local text = f:read("*a")
			f:close()
			if text:find("Toast_Show", 1, true) or text:find("Banner_Show", 1, true) or text:find("Toast_Pin(", 1, true)
				or text:find("Check_Report(", 1, true) then
				for owner in text:gmatch("owner = \"([%w_]+)\"") do
					owners[owner] = path
				end
				for owner in text:gmatch("local OWNER = \"([%w_]+)\"") do
					owners[owner] = path
				end
				for owner in text:gmatch("spec%.owner, [^=]-= \"([%w_]+)\"") do
					owners[owner] = path
				end
			end
			local key = text:match("RegisterModule%(%{%s*key%s*=%s*\"([%w_]+)\"")
			if key and text:find("\n\ttoasts = ", 1, true) then
				declared[key] = true
			end
		end
	end
	eq(owners.share ~= nil and owners.pet ~= nil, true, "the scan finds owners")
	owners.toast, owners.editmode = nil, nil -- Toast.lua's position sample (Recent skips it)
	for owner, path in pairs(owners) do
		eq(declared[owner], true, owner .. " (" .. path .. ")")
	end
end)
```

- [ ] **Step 2: Run, see them fail.** `lua Tomte/tests/test_recent.lua` -> FAIL "attempt to call field 'Recent_Owners'".

- [ ] **Step 3: Implement.** `Modules/Recent/Data.lua`:

```lua
-- The Include checkboxes: every module that shows toasts or banners declares module.toasts (true: its name is the
-- label; a string: that label). In registration order: { { key, label } }.
function ns.Recent_Owners(modules)
	local list = {}
	for _, module in ipairs(modules) do
		if module.toasts then
			list[#list + 1] = { key = module.key,
				label = type(module.toasts) == "string" and module.toasts or module.name }
		end
	end
	return list
end
```

`Modules/Recent/Recent.lua`: delete `OWNERS` and its comment. In `BuildOptions`:

```lua
	for _, owner in ipairs(ns.Recent_Owners(ns.modules)) do
		options[#options + 1] = { type = "checkbox", key = "include." .. owner.key, label = owner.label }
	end
```

`Defaults()`:

```lua
		include = { banners = true }, -- [module key] = shown; the modules' keys are added in init (ns.Recent_Owners)
```

`init`:

```lua
	init = function(saved)
		db = saved
		-- Every module is registered by now (ns.InitModules runs after all files): add their Include defaults, so a
		-- reset and a profile export know them too.
		for _, owner in ipairs(ns.Recent_Owners(ns.modules)) do
			module.defaults.include[owner.key] = true
		end
		ns.MergeDefaults(module.defaults, db)
		if not db.keep then
			wipe(db.entries)
		end
		module.options = BuildOptions()
	end,
```

Home block Clear (`RefreshBlock`):

```lua
	frame.heading:Set("Recent", unseen > 0 and (unseen .. " new") or nil, "Clear", function()
		ns.Confirm_Show("Clear the Recent list?", function()
			wipe(db.entries)
			UpdateDot()
			ns.Panel_Refresh()
		end)
	end)
```

Header of `Modules/Recent/Recent.lua`: "Its Include list has a checkbox per module that declares `toasts` (ns.Recent_Owners)." `Modules/Social/Toast.lua` header after the `ns.Toast_Show(spec)` line: "-- A module that shows toasts or banners declares toasts = true or a label (Recent's Include list)." Then add the 19 `toasts = ...` lines listed under Files, each with a tab indent right below `enabledByDefault`.

- [ ] **Step 4: Run.** `lua Tomte/tests/test_recent.lua` -> all passed; run all tests -> no FAIL.

- [ ] **Step 5: In game.** `/reload`. Recent's settings, Include: every old checkbox is there with the same label and tick state, plus "Friend sharing" ticked. Set Recent to "block on Home", click Clear on the block: "Clear the Recent list?" appears; No keeps the entries, Yes clears them.

- [ ] **Step 6: Commit after confirmation.** `Recent: Include list from the modules, Clear on Home asks first`. CHANGELOG: "Recent: Friend sharing toasts get their own Include checkbox, and Clear on the Home block asks first."

## Task 12: Docs and final checks

**Files:**
- Modify: `README.md:26`, module rows `:246-250` (Whispers, Mentions, Friend sharing, Group Alerts)
- Modify: `docs/curseforge/page.md:38-40`, `:82-86`
- Modify: `CHANGELOG.md` (Unreleased)

- [ ] **Step 1: README.** Line 26: "On first login Tomte asks what you want: Minimal, Collector, Crafter, Social or Everything (or choose yourself). Presets leave Whispers, Mentions, Friends Online and Group Alerts as they are unless they name them." Rows (leave the Pet Health row to its own plan):

```markdown
| Whispers | Social & chat | A toast per whisper (click to reply), an unread recap when you're back from AFK, and a summary card for whispers received in combat or during a cinematic. The inbox is a resizable window with your conversations as chat bubbles: class avatars with online dots, unread counts, pinned conversations, a NEW line where unread messages start, who they are (level, class, zone) with an Invite button, and a right-click menu to pin, invite, add as a friend, copy or delete. One inbox for all your characters: each conversation says which character it's with, unread counts and the recap follow the character you're on, and another character's conversations are read-only ("on Aldric"). Battle.net whispers show on every character. |
| Mentions | Social & chat | A toast when someone says your name or a keyword in guild, group, say or channel chat (accents and capitals don't matter). Click it to answer in that channel. Taskbar flash and sound are optional (off for new installs). |
| Friend sharing | Social & chat | ...existing text... Off by default for new installs. |
| Group Alerts | Social & chat | Invites, queue pops, ready checks and summons: a sound (once by default, on the Effects or Master channel, optionally repeated until answered), plus a taskbar flash for summons. |
```

- [ ] **Step 2: CurseForge page.** Line 39-40: "(Minimal, Collector, Crafter, Social or Everything)". Replace "### And more" with three sections:

```markdown
### Chat & social

- **Whispers:** a toast for every whisper, an unread recap when you're back from AFK, and an inbox with your
  conversations as chat bubbles, for all your characters.
- **Mentions** (your name or keywords in chat), **Friends Online**, and **Group Alerts** so you never miss an invite,
  queue pop, ready check or summon.
- **Trade Filter** (only the trade messages about your professions and keywords), **Chat Tabs**, **Channel Tags**
  and **Chat Copy**.
- **Friend sharing** (optional): swap flight times and gathering spots with friends who run Tomte.

### Class helpers

- **Hunter Pets:** Call Pet tooltips, a stable tab with a tame log, and a pet check before dungeons and raids.
- **Rogue Poisons:** one click (or key) applies a missing poison.
- **Pet Health:** your pet's health under your character, with reminders for a dead or missing pet.

### And more

Pet battle help (the right pet to swap to, tamer teams, paste Xu-Fu strategies and play them one key press at a time),
seven themes, and settings sharing between players.
```

Align the Pet Health line with that module's README row as it stands when this runs (another plan rewords it).

- [ ] **Step 3: CHANGELOG.** Under **Unreleased**, the lines from Tasks 2-11 for every task the user confirmed (Task 1 has none).

- [ ] **Step 4: Final checks** from the AddOns folder:
  - `for t in Tomte/tests/test_*.lua; do lua "$t" >/dev/null 2>&1 || echo "FAIL $t"; done` -> prints nothing.
  - No TOC change in this plan, so `lua Tomte/tools/bugfiles.lua` isn't needed (run it if a task added a file).
  - `for f in Core/Format.lua Core/Setup.lua Core/Migrations.lua Modules/Social/Data.lua Modules/Social/Whispers.lua Modules/Social/Inbox.lua Modules/Social/InboxWho.lua Modules/Social/Mentions.lua Modules/Social/Alerts.lua Modules/Chat/Data.lua Modules/Chat/Tabs.lua Modules/Chat/Filter.lua Modules/Recent/Data.lua Modules/Recent/Recent.lua; do luac -l "Tomte/$f" | grep -E 'GETGLOBAL|GETTABUP.*_ENV'; done` -> only WoW API and Lua globals (no `Me`, `Touches`, `LowerPair`, `UntouchedSet`, `OldCharacterKey`).

- [ ] **Step 5: In-game checklist** (after `/reload`, BugSack empty throughout):
  1. Existing settings kept: Friend sharing on, Group Alerts on Master with 3 repeats, Mentions flash and Chime (Task 3).
  2. Group Alerts Test on Effects with effects muted is silent, on Master heard (Task 3).
  3. `/tomte setup`: five cards fit; Minimal keeps Whispers as set; Social turns the chat modules on (Task 4).
  4. Whisper, reply from toast and inbox, Invite and Add friend work; another character's conversation is read-only and not counted (Task 6).
  5. "ásgeir" keyword matches "ÁSGEIR" in guild chat; Trade Filter highlights "ÖRN" cleanly (Task 2).
  6. Community mention click opens the channel line or prints the reason (Task 7).
  7. Trade Filter pause survives `/reload`, clears at the next login (Task 8).
  8. Chat Tabs: no second tab after `/reload`, record under the GUID (Task 9).
  9. Chat Copy off message says "Social & chat" (Task 10).
  10. Recent Include has Friend sharing; Home block Clear asks first (Task 11).

- [ ] **Step 6: Commit the docs after the user confirmed the tasks above.** `README and CurseForge page: chat & social, class helpers, new defaults and the Social preset`.
