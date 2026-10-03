# Tomte: Almost Done, AlmostCompletedAchievements replacement

## Goal

Uninstall AlmostCompletedAchievements (ACA). A new Tomte module, **Almost Done**, covers how the user uses it:

- **Browse**: open the Achievements window and see what's nearly done, to pick something to work on.
- **Chase rewards**: find near-complete achievements that give a mount, pet, toy, title, transmog or decor,
  see the reward, and skip rewards they already own.
- **Notice progress while playing**: a toast when something becomes "almost done", without opening anything.
- **Top 5 tracker**: a small movable window that's always on screen.

Decisions made with the user (2026-10-03):

| Question | Choice |
|---|---|
| Use | Browse, rewards and in-world progress, plus the Top 5 tracker |
| In-world notices | Toasts only at milestones (crossed the threshold, one step left); the tracker updates live otherwise |
| Rewards | Reward type icon, reward filter, model preview, owned rewards greyed out |
| Where the list lives | Docked to the right of the Achievements window, opening with it. The tracker is a separate pop-out window |
| Tracker contents | Pinned achievements first, then the highest percent fills the rest. Separate from Blizzard's tracker |
| List features | Threshold, category filter, expansion filter, ignore list, meta browser, search, account/character scope |
| Live detection | One full scan at login, then a watch set updated from events (below) |

Not carried over from ACA: themes, Remix mode, scan-speed presets, the standalone (undocked) panel mode,
KagrokLauncher support.

## Module

- Key `ach` (`/tomte ach …`, `TomteDB.ach`), name **Almost Done**, a new panel category **Achievements**, on by
  default.
- **Blocked while ACA is loaded**: "The AlmostCompletedAchievements addon is still enabled. Disable it and
  /reload to switch over." ACA's data isn't copied: its cache is rebuilt by the first scan, and the user's ACA
  settings are all defaults (ignore list empty, nothing pinned).
- Moments already shows achievements when they're **earned**. Almost Done never does, so the two don't overlap.

### Files (`Tomte/Modules/Achievements/`)

| File | Role |
|---|---|
| `Data.lua` | Pure logic, unit-tested: percent from criteria, milestones, filter, sort, search, Top 5 selection, reward type from text, expansion from a category name chain, the ACA-style metas list. |
| `Scan.lua` | Background full scan (time budget per frame), the in-memory records, the watch set, live updates, the per-character cache. |
| `Rewards.lua` | Reward item to type and owned state, and model info for the preview. |
| `Metas.lua` | Meta achievements: children from criteria, which metas a record belongs to, the browser's tree. |
| `Dock.lua` | The panel docked to the Achievements window: list, filters, search, meta browser, preview. |
| `Tracker.lua` | The Top 5 window. |
| `Achievements.lua` | Module registration, events, milestone toasts, commands, options. |

## Data

### Record (one per incomplete achievement the scan found)

`{ id, name, icon, points, category, top, expansion, done, total, percent, last, reward, rewardItem }`

- `done` / `total`: criteria completed / criteria counted. `percent` is 0-100 (below).
- `last`: the name of the one incomplete criterion, when exactly one is left (for the "one step left" toast and the
  tooltip).
- `top`: the top-level category name (Quests, Exploration, …). `expansion`: see below, `nil` = Other.
- `reward`: Blizzard's reward text. `rewardItem`: `C_AchievementInfo.GetRewardItemID`. The type and owned state
  aren't stored: they're looked up when shown, since ownership changes.

### Percent

Same as ACA, so numbers match what the user is used to: every criterion counts equally. A completed one counts 1,
an incomplete one counts `quantity / reqQuantity` (0 when there's no required quantity). Percent = sum / count ×
100. An achievement with no criteria is skipped: it has nothing to measure.

Known limit: "any N of M" achievements count all M criteria, so they show lower than they are. ACA has the same
limit.

### Completed: account or character

Setting `scope`:
- **Account** (default): skip an achievement when `completed` (from `GetAchievementInfo`) is true.
- **This character**: skip only when `wasEarnedByMe` is true. Achievements an alt finished show up again, with
  this character's criteria.

To verify in game: some criteria are account-wide regardless, and some achievements show as completed for every
character.

### Categories and expansion

- Categories come from `GetCategoryList()`. **Feats of Strength and Legacy are always skipped** (they can't be
  done). Guild and statistics categories aren't part of that list.
- `top` is the name of the top-level ancestor. The category filter lists those names (built from what the scan
  found, so new categories just appear).
- **Professions**: setting "All / Mine / None", default **Mine**. "Mine" keeps a professions achievement when
  a criterion's name or the category name contains one of the character's profession names (`GetProfessions`).
- **World Events**: "All / Running / None", default **Running**. "Running" keeps an event achievement when a
  calendar holiday from yesterday, today or tomorrow has the subcategory's name in its title (as ACA does).
- **Expansion**: the first expansion name found in the category's name chain (the category, its parent, …),
  matched against a fixed list: Midnight, The War Within, Dragonflight, Shadowlands, Battle for Azeroth,
  Legion, Warlords of Draenor, Mists of Pandaria, Cataclysm, Wrath of the Lich King, The Burning Crusade,
  Classic. No match = **Other**. The expansion filter has those plus Other. Achievements that belong to one of the
  built-in metas get that meta's expansion when their category has none (ACA does the same).

### Filters (in order)

1. Not ignored (`ignored[id]`, account-wide), unless "Show ignored" is on (they're then shown dimmed).
2. Category allowed (incl. the professions and world events modes).
3. Expansion allowed.
4. Reward filter: Any / Any reward / **New rewards only** (has a reward, not owned) / Mount / Pet / Toy /
   Title / Appearance / Decor.
5. Search: the name, the reward text, or a criterion name contains the text (case-insensitive). Criterion names
   are only checked for records in the watch set (they're kept there).
6. `percent >= threshold`. Pinned achievements are always shown, at any percent.

### Sort

Percent (high first), then name. Other choices: Points (high first), Name, Fewest steps left (total - done).

### Top 5 tracker

The character's pins in pin order (skipping completed ones), then the highest-percent records that pass the
filters and aren't pinned, up to 5. Pins are per character, at most 5.

## Scanning

### Full scan

- Runs 5 seconds after the first `PLAYER_ENTERING_WORLD`, on `/tomte ach scan`, from the dock's Rescan button,
  and when the scope setting changes.
- Walks every category and every achievement (`GetCategoryNumAchievements(catID)` without includeAll, which
  gives Blizzard's visible list: the next step of a series, not the whole chain).
- **Time budget**: an OnUpdate does work until `debugprofilestop()` says 4 ms have passed, then waits for the next
  frame. About 10,000 achievements, which takes a few seconds and causes no stutter.
- Builds records for incomplete achievements with percent > 0, plus pinned ones at any percent.
- Also collects, from every incomplete achievement's criteria, the child → meta links (criteria of type 8 have
  the child achievement ID as their asset ID).
- When it finishes it swaps in the new records, rebuilds the watch set, saves the cache and refreshes the dock
  and the tracker.

### Cache

`ach.cache[guid] = { at, scope, records }`, records only for the watch set (keeps SavedVariables small). At login
the dock and tracker use the cache right away. The scan replaces it a few seconds later.

### Watch set

The records with `percent >= threshold - 20`, plus pins. For each, the scan keeps the per-criterion state (name,
completed, quantity, required), so a live update knows exactly what changed.

### Live updates

- `CRITERIA_UPDATE` (no payload, fires in bursts): debounced 1 s, then every watched achievement is recalculated.
- `CRITERIA_EARNED(achievementID)`: that achievement is recalculated right away. If it isn't watched yet it's
  read, and added to the records and the watch set when it's now in range.
- `ACHIEVEMENT_EARNED(achievementID)`: removed from records, pins and the watch set. Its category is rescanned
  (the next achievement of a series appears there), and so are its metas.
- Any recalculation that changes a record refreshes the dock (if shown) and the tracker. Tracker rows whose
  percent went up flash briefly.

### Milestones

Compared on every live recalculation. Live updates wait until the first full scan of the session has finished,
so a login (criteria bursts, a cache from last session) never spams toasts:

| Milestone | When | Toast |
|---|---|---|
| Almost done | percent went from below the threshold to at or above it | label "ALMOST DONE", title = achievement name, text "80%  -  8/10" plus "Reward: …" when there is one |
| One step left | `total >= 2`, and incomplete criteria went from 2+ to exactly 1 | label "ONE STEP LEFT", text = the remaining criterion's name |
| Pinned step | a pinned achievement gained progress (done or percent went up) | label "PINNED", text "8/10  -  80%" |

A record gets the "almost done" and "one step left" toasts at most once per session (they don't repeat if it dips
and comes back). Pinned steps show on every step. When one change hits several milestones, only the strongest toast is shown: one step left, then
almost done, then pinned step. Every toast: the achievement's icon, `holdInCombat`, `mergeKey` = achievement ID,
click opens the achievement, right-click dismisses. Each kind has its own on/off option.

## Rewards (`Rewards.lua`)

Type, from the reward item when there is one:
- `C_MountJournal.GetMountFromItem` gives a mount → **mount**, owned when `isCollected`.
- `C_PetJournal.GetPetInfoByItemID` gives a species → **pet**, owned when you have one of that species
  (`C_PetJournal.GetNumCollectedInfo`).
- `C_ToyBox.GetToyInfo` knows the item → **toy**, owned when `PlayerHasToy`.
- `C_HousingCatalog.GetCatalogEntryInfoByItem` knows it → **decor**, owned when the entry says you have any.
- An equippable item with an appearance (`C_TransmogCollection.GetItemInfo`) → **appearance**, owned when
  `C_TransmogCollection.PlayerHasTransmog`.

Without an item: reward text starting with "Title" → **title** (never owned: it comes with this achievement).
Other reward text → **other**. No text → no reward. Text matching is in `Data.lua` (tested). Results are cached
per item for the session and cleared on `NEW_MOUNT_ADDED`, `NEW_PET_ADDED`, `NEW_TOY_ADDED` and
`TRANSMOG_COLLECTION_UPDATED`.

Each type has an icon (an atlas or a texture) shown in the row. Owned rewards are shown greyed out with
"(owned)" in the tooltip.

### Preview

The dock's bottom part shows the hovered row's reward, or else the last clicked one, when it's a mount, pet or
appearance. It's a model scene like the Stable tab's (turning slowly), with the reward name under it. Mounts and
pets use their creature display ID, appearances are tried on a player actor. For any other reward type the
preview is hidden and the list uses the space.

## Metas (`Metas.lua`)

- **Children of a meta**: its criteria of type 8 (the asset ID is the child). Plus a small built-in override
  list for metas whose children aren't all criteria: Light Up the Night (taken from ACA's data).
- **Built-in roots**: the big expansion metas, newest first: Light Up the Night (Midnight), Worldsoul-Searching
  (The War Within), A World Awoken (Dragonflight), Back from the Beyond (Shadowlands), A Farewell to Arms (Battle
  for Azeroth), Broken Isles Pathfinder (Legion), Draenor Pathfinder (Warlords of Draenor).
- **Record parents**: the scan's child → meta links. A row's tooltip says "Part of: <meta>" (up to 2 names).

### Meta browser (the dock's Metas tab)

- **Landing**: the built-in roots, then "Metas you're close on" (metas that contain a listed record), each with its
  percent and done/total.
- **Selecting a meta**: a header with its name, icon, percent and reward, then its children: incomplete ones
  first by percent, completed ones dimmed with a check mark. A child that's a meta itself expands in place (one
  level at a time, + / -). A Back button returns to the landing. Clicking a child opens it in the Achievements
  window.
- Children are read when a meta is opened (one `GetAchievementInfo` + criteria call per child), not during the
  scan.

## Dock (`Dock.lua`)

- A frame attached to the Achievements window's right edge (`TOPLEFT` to `AchievementFrame`'s `TOPRIGHT`, same
  height), 380 px wide, in Tomte's dark/gold panel style.
- `Blizzard_AchievementUI` is load-on-demand: the dock hooks `AchievementFrame` on that addon's `ADDON_LOADED`
  (or right away if it's loaded already).
- It opens with the Achievements window when `dock.open` is true. Its close button sets `dock.open = false`.
  Then a narrow handle (a gold ">" tab) stays on the window's edge, and clicking it opens the dock again
  (`dock.open = true`).
- **Header**: "Almost Done", the count shown, scan status ("Scanning 45%" while scanning), a Rescan button, close.
- **Tabs**: List | Metas.
- **List tab, top**:
  - A search box.
  - A row of controls: threshold slider (50-100, step 5), Reward dropdown, Sort dropdown, and a Filters
    button. The Filters button opens a menu with Categories (checkboxes), Professions and World Events modes,
    Expansions (checkboxes), Scope (radio), and "Show ignored".
- **List rows** (pooled, scrolled):
  - Icon, name, a thin progress bar with "80%  8/10", the reward type icon (grey when owned), a pin mark when
    pinned.
  - **Hover**: tooltip with the description, the steps left (up to 8 incomplete criteria with quantities),
    reward text, owned state, "Part of: …". The preview shows the reward when it has a model.
  - **Click**: opens the achievement in the Achievements window and selects the row (preview stays on it).
  - **Shift-click**: puts the achievement link in chat.
  - **Right-click**: a menu with Pin / Unpin, Ignore / Unignore, and "Show meta" (opens the Metas tab on its
    first parent).
- **Empty states**: "Scanning…" during the first scan without a cache. "Nothing at 80% or more with these
  filters." otherwise.

## Tracker (`Tracker.lua`)

- A small frame (260 px wide) on UIParent. Title "ALMOST DONE" spaced, small grey. Five rows: icon, name, a
  thin bar with percent. A pinned row has a gold pin mark.
- Click a row: open it in the Achievements window. Right-click: unpin, if pinned.
- **Movable** while unlocked (drag anywhere). Saved point in `tracker.point`. `/tomte ach lock` / `unlock` and an
  option. When unlocked it shows a dashed "drag to move" hint, the same pattern as Pet Health.
- Options: shown (default on), hide in combat (default on), scale (0.8-1.4).
- Hidden while nothing qualifies. Rows whose percent went up flash for 1.5 s.

## Saved variables (`TomteDB.ach`)

```lua
{
	threshold = 80, sort = "percent", reward = "any", scope = "account", showIgnored = false,
	categories = {}, -- [top category name] = false when hidden (missing = shown)
	expansions = {}, -- [expansion or "Other"] = false when hidden
	professions = "mine", events = "running",
	ignored = {}, -- [achievementID] = true, account-wide
	pins = {}, -- [player GUID] = { achievementID, ... } (order = tracker order, max 5)
	cache = {}, -- [player GUID] = { at, scope, records = { ... } }
	dock = { open = true },
	tracker = { shown = true, locked = false, hideInCombat = true, scale = 1, point = nil },
	toasts = { almost = true, lastStep = true, pinned = true },
	preview = true,
}
```

## Commands

- `/tomte ach scan`: full rescan now.
- `/tomte ach tracker`: show or hide the tracker.
- `/tomte ach lock` / `unlock`: the tracker.
- `/tomte ach test`: one sample toast of each kind (uses a real listed achievement when there is one).

## Options (panel)

Tracker (shown, hide in combat, scale, locked), Toasts (three checkboxes), List (threshold, open with the
Achievements window, reward preview), Data (Rescan button, "Clear ignore list" with confirm).

## Testing

- **Plain Lua** (`Tomte/tests/test_achievements.lua`): percent, milestones (all three, the once-per-session rule,
  priority), filters (each one, pins bypass the threshold), sort orders, search, Top 5 selection, reward type from
  text, expansion from a name chain, meta percent from children.
- **In game**: scan time and stutter, dock docking and handle, filters, preview for each reward type, meta
  browser, tracker drag and lock, milestone toasts (a criterion near the threshold), scope toggle, ACA block.
