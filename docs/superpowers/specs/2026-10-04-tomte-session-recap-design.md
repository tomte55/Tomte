# Tomte: Session recap

Date: 2026-10-04. Backlog item 3. The user picked what counts, where it shows and the structure (approach A below),
then handed over the remaining decisions ("build it and come back when it is all done"). The decisions made after
that point are marked *(decided while building)*.

## Goal

"What did I get done this session?" Shown on the AFK screen, as a cinematic card during the /camp or /quit
countdown, on demand with `/tomte recap`, and as a login toast for the last session (which also covers instant
logouts).

## What counts (picked by the user)

1. **Time and gold**: time online, net gold change, and a split by where the money moved (loot, vendor, mail, auction,
   other).
2. **Notable loot**: items of epic quality or better that you receive (the threshold is an option: rare or epic),
   Gear Check upgrades, and new mounts, pets and toys.
3. **Achievements, rares, tames**: achievements earned (no guild ones), rares killed, and hunter tames.
4. **Progress**: levels and XP (hidden when the XP bar can't show, like the AFK page now), and renown levels
   gained.

Not tracked: quests done, zones, chapters, house levels, item counts, greens and blues.

## APIs (checked on warcraft.wiki.gg and wow-ui-source live, client 12.1.0)

- **Logout**: `PLAYER_CAMPING` (no payload) and `PLAYER_QUITING` are what Blizzard's own UI uses to show the "CAMP" and
  "QUIT" countdown popups (`Blizzard_Game/Shared/EventImplementation.lua`). `LOGOUT_CANCEL` fires when the
  countdown is cancelled. An instant logout in a rested area shows no popup, so it gives no window. `Logout()` is
  protected, so it can't be delayed. `PLAYER_LOGOUT` comes too late to show anything.
- **Kills** (12.0.0 frame events; the GUIDs are `SecretWhenUnitIdentityRestricted`): `UNIT_DIED(unitGUID)`,
  `PARTY_KILL(attackerGUID, targetGUID)`, `PLAYER_TARGET_DIED` (no payload).
- **Vignettes**: `C_VignetteInfo.GetVignettes()` and `GetVignetteInfo(guid)`, which return `objectGUID, name, atlasName,
  isDead, ...`. Events `VIGNETTES_UPDATED` and `VIGNETTE_MINIMAP_UPDATED`.
- **Classification**: `UnitClassification(unit)` gives "rare" or "rareelite" (`AllowedWhenUntainted`, may be secret).
- **Loot**: `GetLootSourceInfo(slot)` gives source GUID and quantity pairs, used in `LOOT_OPENED`.
  `CHAT_MSG_LOOT(text, ...)`: the text is matched against `LOOT_ITEM_SELF`, `LOOT_ITEM_SELF_MULTIPLE`,
  `LOOT_ITEM_PUSHED_SELF`, `LOOT_ITEM_PUSHED_SELF_MULTIPLE`, `LOOT_ITEM_BONUS_ROLL_SELF` and
  `LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE`. The text can be secret (chat lockdown), and is skipped then.
- **Money**: `PLAYER_MONEY` (no payload) plus `GetMoney()`. Nothing tells where the money came from, so the source is
  inferred from what's open: `LOOT_OPENED`/`LOOT_CLOSED` and `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`/`HIDE` with
  `Enum.PlayerInteractionType.Merchant`, `MailInfo` and `Auctioneer`.
- **Toast and engine**: the existing `ns.Toast_Show` and `ns.Cinematic.Enter` (passthrough).

Nothing is read in combat logic. Every GUID, classification and text passes an `issecretvalue` check, so in
instances the rares and loot simply don't count.

## Structure (approach A, picked by the user)

- **`Core/SessionData.lua` (pure) + `Core/Session.lua`**: the session is always tracked, also with the Recap module
  off, because AFK needs it. It moved out of AFK.
  - `TomteDB.session = { guid, start, money, level, xpFraction, moneyNow, levelNow, xpNow, seen, gold = { ["in"] = {},
    out = {} }, log = {}, rares = {}, shownAtLogout }`.
  - On `PLAYER_ENTERING_WORLD` with `isInitialLogin` (or a different character GUID), the old session moves to
    `TomteDB.sessionLast[oldGuid]` and a new one starts. A `/reload` keeps the session.
  - `moneyNow` is updated on `PLAYER_MONEY`, and `levelNow`/`xpNow` on `PLAYER_XP_UPDATE` and `PLAYER_LEVEL_UP`. At
    `PLAYER_LOGOUT` only `seen = GetServerTime()` is stamped, so no API data is read at logout.
  - `ns.Session_Current()` (lazily ensured), `ns.Session_Last(guid)`.
  - `ns.Session_Note(kind, entry)` forwards to the Recap module while it's on and does nothing otherwise.
  - `ns.Session_OnMoney` is the listener for money deltas.
  - Migration: `TomteDB.afk.session` (same character GUID) becomes `TomteDB.session`, and the old key is removed.
- **Hooks into existing detection** (no duplicate event handlers):
  - Moments: `ACHIEVEMENT_EARNED` (after its guild and already-earned filter), `NEW_MOUNT_ADDED`, `NEW_PET_ADDED`,
    `NEW_TOY_ADDED` (after the settle window) and `MAJOR_FACTION_RENOWN_LEVEL_CHANGED` call `Session_Note` *before*
    the style check, so a type set to "off" still counts. With the Moments module off, these aren't logged; the
    option tooltip says so.
  - Gear Reveal: `Reveal()` notes an `upgrade`.
  - Hunter Stable: each fresh tame notes a `tame`.
- **`Modules/Recap/`** (module key `recap`, "Session recap", category Ambience, on by default):
  - `Data.lua`: pure logic.
  - `Track.lua`: gold attribution, loot, rares.
  - `Scene.lua`: the card.
  - `Recap.lua`: registration, the camp/quit trigger, the login toast, commands, options.
- **AFK**: reads `ns.Session_Current()`. Its rotating stats band gets one extra "Highlights" page when Recap is on
  and the session has entries.

## Tracking rules (pure, `Modules/Recap/Data.lua`)

- **Log entry**: `{ kind, at, title, icon, quality, tier, link, detail, factionID, from, to, guid }`.
  The kinds are `loot, upgrade, mount, pet, toy, achievement, rare, tame, renown`.
- **AddNote(log, entry, max=40)**:
  - Renown collapses per faction (the first `from` is kept and `to` is updated).
  - A rare with a GUID already in the log is ignored.
  - Loot of an item already noted as an upgrade (same link) is ignored. An upgrade whose link is already in the log
    as loot turns that entry into the upgrade.
  - Over `max`, the oldest entry is dropped and `log.dropped` counts it.
- **Gold**:
  - Net is `moneyNow - money`, which is always correct.
  - Each `PLAYER_MONEY` delta goes to `gold.in[source]` or `gold.out[source]`, where the source is the open context.
    Precedence: loot window > auction > mail > vendor.
  - **GoldSources(gold, net)** gives the net per source. "other" is the remainder (`net - attributed`), so the parts
    always add up, also across reloads and loading screens. Zero entries are dropped, and the list is sorted by size.
- **Rares**:
  - Candidates (`[guid] = name`, at most 200 kept, this session only, not saved) come from:
    - vignettes whose `atlasName` starts with `VignetteKill` and whose `objectGUID` is a `Creature-` or `Vehicle-` GUID;
    - target or mouseover units classified "rare" or "rareelite" that the player can attack.
  - A candidate counts once (`session.rares[guid]`) when any of these happens:
    - `PLAYER_TARGET_DIED` while it is the target;
    - `PARTY_KILL` with it as the target;
    - its corpse is looted (`GetLootSourceInfo`).
- **Counts(log)** gives counts per kind.
- **SummaryLine** gives "2h 14m · +3,420g · 2 achievements · 3 rares · 1 tame · 1 mount · 2 items · +2 renown". Gold
  is left out when it's zero, and so is any count of zero. "items" counts loot and upgrades.
- **Duration** gives "2h 14m", "14m" or "<1m".
- **Highlights(log, n)** ranks entries as legendary or better items, then mounts, epic items and upgrades,
  achievements, rares, tames, pets, toys, renown, and other loot. Newest first within a rank. Returns the first n
  plus how many more there are.
- **Worth(summary)**: at least 10 minutes and (an entry, |net| ≥ 1g, or an XP gain). Only then does the login toast
  show.

## Showing it

### The card (`Modules/Recap/Scene.lua`, cinematic engine)

The card is always a passthrough cinematic: `skipCamera`, `passthrough`, `showcase`. Any key or click goes to the game
and ends the card (see the memory rule "cinematics never lock controls").
- **Top band**: a spaced label ("Session recap", "Last session", or "Logging out in 17"), the duration in
  Morpheus, and the time range as subtitle ("Saturday 18:02 - 20:16").
- **Right side**: "Highlights", up to 6 rows (a small grey kind label over an icon and a quality-colored title),
  "+N more", on a gradient like AFK's whisper list. The list is hidden when there are no entries.
- **Bottom band**:
  - left: character name and "Level 80 Race Class";
  - center: the net gold (large) over a hairline, with the sources line underneath;
  - right: the level (with "+1.5 levels" when there's XP progress) over the counts line.
- **Left**: the character showcase.
- **When it plays**:
  - **`/camp` or `/quit`** (option "While logging out", on): plays on `PLAYER_CAMPING` or `PLAYER_QUITING` when
    allowed: no combat, instance, taxi, pet battle, other cinematic or Blizzard movie. AFK screen up: no card, since
    AFK already shows the session. The label counts down from 20 s. `LOGOUT_CANCEL` or any key or click ends it (the
    UI comes back with Blizzard's popup still counting). Shown cards set `session.shownAtLogout`, and
    `LOGOUT_CANCEL` clears it again.
  - **`/tomte recap`**: this session, 20 s or until any key or click. `/tomte recap last`: the last session.
    `/tomte recap preview`: sample data.
  - It never waits or queues. If it can't play right now, the command prints why.

### Login toast

On an initial login, 8 s in, if the character's last session is `Worth()` and wasn't already shown at logout: one
toast (owner `recap`) "Last session" / character name / the summary line. A click plays the last-session card.

### AFK screen

The stats band adds a "Highlights" page: the top highlight's title over the counts line ("2 rares · 1 achievement
this session"). It shows only when the Recap module is on, the AFK option "Session highlights" is on, and there is
something to show.

## Options

- While logging out (on)
- Login toast for the last session (on)
- Loot quality: rare or better / epic or better (epic)
- On the AFK screen (on)
- Preview button

## Testing

Plain Lua (`tests/test_recap.lua`) covers:
- `SessionData` start and rollover: initial login, other character, reload, migration from `afk.session`;
- AddNote: renown collapse, rare dedupe, loot/upgrade dedupe both ways, cap;
- gold attribution and sources, including "other" as the remainder and negative nets;
- Counts, SummaryLine, Duration, Highlights order and "more", Worth, IsRareVignette, MoneySource precedence, and the
  loot patterns from the LOOT_* format strings.
`test_afk.lua` keeps passing.

In game (main things to verify):
- rare kills are counted in the open world, so the GUIDs aren't secret there;
- `CHAT_MSG_LOOT` matches for epics;
- the gold split while selling at a vendor and collecting AH mail;
- `/camp` shows the card with the countdown, and moving cancels both;
- an instant logout in an inn shows the toast at the next login.

## Out of scope

Quest counts, profession skill-ups, a panel page, the Weekly popup tab, cross-session history beyond the last
session, and account-wide totals.

## Changes during the build

- The AFK highlights page is controlled by the Recap option "On the AFK screen" only. There is no separate AFK
  option.
- `ns.Session_Note` sets `entry.kind`, and the Recap side stamps `at`. Rares are also remembered in
  `session.rares`, so a rare that has dropped out of the 40-entry log still isn't counted twice.
- `/tomte recap` works anywhere except in combat, on a taxi, during another cinematic, a cutscene or a pet battle
  (instances are fine, since you asked for it). The logout card uses the same rules.
- A logout card that is still up 5 s after its countdown ended closes itself (the logout didn't happen).
- The loot window context ends 0.5 s after `LOOT_CLOSED`, because auto-loot money can land just after the window
  closes, unless a new loot window opened in between.
- `UNIT_DIED` isn't used: it fires for any death nearby, so kills come from `PLAYER_TARGET_DIED`, `PARTY_KILL` and
  looting.

## After the first in-game test

- **Moving doesn't cancel a retail logout.** The user reported that neither closing the card nor moving
  cancelled it. Only the popup's Cancel and Esc do, both through the protected `CancelLogout`, so the card can't
  cancel by itself.
- **Esc on the logout card** now goes through to the game. Engine option `escapeToGame`: Esc is propagated, and the
  card closes (UI shown again) *before* the game's Esc runs. The first version closed one frame later. Blizzard's
  Esc then hid the CAMP popup while it was invisible, so its OnHide never ran and it stayed on the shown-dialog
  list, which made every later Esc "close" it again (no game menu until /reload). The user found this in the second
  test. Blizzard's `ToggleGameMenu` runs its handlers
  via `securecallfunction`, and `StaticPopup_EscapePressed` comes first: it finds the CAMP popup, which stays in
  Blizzard's shown list and keeps ticking while the UI is hidden, and calls its `OnCancel` → `CancelLogout`. Then
  `LOGOUT_CANCEL` closes the card. Any other key or click only closes the card; the popup and its Cancel button are
  back.
- **The countdown** is a block under the top band: "LOGGING OUT IN", the seconds in Morpheus, a gold bar that
  drains, and "Esc to cancel". The user asked for that as the only hint, so the engine's top-right hint is
  empty on this card. The time is read from the CAMP popup's
  own `timeleft` (`StaticPopup_FindVisible("CAMP")`), falling back to 20 s from `PLAYER_CAMPING`.
- **No card on `/quit`.** Hiding the UI hides Blizzard's QUIT popup, and its `OnHide` calls `CancelLogout` while
  time is left. Run from our insecure UI hide, that would be a blocked action.
