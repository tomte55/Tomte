# Tomte: AFK Screen module

The second cinematic scene on the shared engine (see `2026-10-03-tomte-design.md`). The user asked for an
ElvUI-style AFK screen with a few extras and said "just implement it", so this note records what was
built rather than a reviewed spec.

## Behaviour

- **Start:** `PLAYER_FLAGS_CHANGED` (player) and `UnitIsAFK("player")` reads as `true`. A secret
  (unreadable) flag changes nothing.
- **Not shown** in instances, on a taxi, in combat, in a pet battle, during a Blizzard cinematic or movie, or
  while another Tomte cinematic is up.
  - A 1s ticker retries while AFK; nothing runs when not AFK.
  - Ported into an instance while the screen is up: it closes and comes back once out.
- **Flag clears:** the screen closes, and the state and whispers are forgotten.
- **Click/Esc:** the screen closes for the rest of this AFK.
  - With "Click clears AFK" on, it also sends `C_ChatInfo.SendChatMessage("", "AFK")`.
  - That call toggles, so it is only sent while the flag reads `true` and not in chat lockdown.
- **Something needs the UI** (`LFG_PROPOSAL_SHOW`, battlefield "confirm", `READY_CHECK`,
  `PARTY_INVITE_REQUEST`): the screen closes for the rest of this AFK, and you stay AFK.
- **Combat:** the engine pauses the screen; it comes back after 20s idle.
- **No music.**
- **`/reload` while AFK:** `TomteDB.afk.current` is the engine state and holds `since`, `whispers` and
  `dismissed`. It is resumed if still AFK, otherwise released.

## Screen

- **Top band:** "AWAY FOR 12:34" over the zone (Morpheus) and the subzone.
- **Bottom band:**
  - left: name and "Level 80 Race Class - \<Guild\>";
  - center: clock and date. The clock follows Blizzard's `timeMgrUseMilitaryTime` and
    `timeMgrUseLocalTime` CVars.
  - right: rotating pages for time online this session, gold (with the session delta) and level/XP
    progress. The XP page is hidden when the XP bar can't show.
- **Right side:** "While you were away", the 5 newest whispers (max 20 kept), on a gradient that mirrors the
  showcase.
  - Battle.net names are K-strings, shown as-is.
  - Whispers that arrive as secret values are skipped.
- **Session** = since the character's login (`isInitialLogin`), kept across `/reload`, stored in
  `TomteDB.afk.session` with the character's GUID.

## Engine changes

`Enter` takes two new opts:
- `onDismiss(state)`: replaces the pause on click/Esc.
- `hint`: the hint text.

Scene helpers (text, gold line, swap) moved to `Cinematic/SceneKit.lua` and are shared by both scenes.

## Options

Camera orbit, Character showcase, Missed whispers, Click clears AFK, and a Preview button.
`/tomte afk preview` does the same as the button: it shows the screen with sample whispers.
