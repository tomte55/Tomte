# Tomte: Hunter Pets and Moments modules

Agreed in conversation: ideas 1-3 (Call Pet tooltips + stable page, pet readiness check, tame log) as one
Hunter module, and idea 6 (Moments: short cinematic cards for notable events). The user handed every design
decision to Claude ("implement all of it, you make decisions, come back when done"); the decisions are
recorded here. API facts were checked against wow-ui-source 12.1.0.69933 and warcraft.wiki.gg.

## Shared: banner (Cinematic/Banner.lua)

A title-card banner over the normal UI, in the cinematic style: spaced label, Morpheus title, gold line with
a diamond, grey subtitle, optional icon above. Fades in with a small drift, holds, fades out. Click-through.
Banners queue (one at a time) and wait while a cinematic is active (the UI is hidden then). They also wait
(up to 8s) while Blizzard's own center-screen text is up: `ZoneTextFrame`, `SubZoneTextFrame`,
`EventToastManagerFrame`, `RaidWarningFrame`, `RaidBossEmoteFrame` (user report: moments overlapped the
"entering area" text). `ns.Banner_SuppressZoneText(seconds)` hides Blizzard's zone/subzone text (an
`OnShow` hook plus hiding what's up); Moments uses it on a discovery it shows itself (option "Replace
Blizzard's zone text", on by default).
`ns.Banner_Show({ label, title, subtitle, icon, accent, hold })`.

## Hunter Pets (key `hunter`, category "Class")

Blocked (greyed out in the panel) on non-hunters.

**Stable cache (Stable.lua).** `C_StableInfo.GetStablePetInfo(1..6)` (Call Pet 1-5, 6 = BM bonus slot) and
`GetStabledPetList()` are read on login, `PET_STABLE_UPDATE`, `PET_STABLE_SHOW`, `UNIT_PET` and
`PET_SPECIALIZATION_CHANGED`. A non-empty read is saved per character (`db.chars[guid]`), so everything works
even if the API only answers at a stable master (unverified; the cache covers it). A pet number the
character never had (every number seen is kept) is a new tame (no tame event exists) and triggers the
Moments "tame" moment. Not within 10s of a loading screen (reads may be partial), and never more than 2 at
once (that's the cache catching up).

**Call Pet tooltips (Tooltips.lua).** Spell tooltips for Call Pet 1-5 (883, 83242-83245) get the pet's name,
family, spec and spec ability, plus "Summoned" when it is out. Name falls back to `GetCallPetSpellInfo`.

**Tame log (Tooltips.lua + Data.lua).** There is no "tameable" API. A unit tooltip for a non-player-controlled
creature with a hunter-pet family (`UnitCreatureFamily`, guarded against secret values; warlock/DK families
excluded) gets one line: the family plus "N in your stable" / "new family", and "You have this one" when its
NPC ID matches a stabled pet's `creatureID`. Every such creature is recorded account-wide in `db.seen`
(family > creature > name, zone) for the stable page.

**Readiness check (Checks.lua).** Runs 4s after entering a dungeon, raid or delve, on `READY_CHECK`, and on
`/tomte hunter check`. Out of combat only. Warnings go to a banner (orange label "PET CHECK") and chat:
- no pet out / pet dead (BM and SV; MM optional; specs from `C_SpecializationInfo`),
- pet spec doesn't match the rule for this content (dungeon / raid / delve: Any, Ferocity, Tenacity,
  Cunning; default dungeon = Ferocity for Primal Rage, others Any),
- pet on Passive,
- Growl on autocast in a group instance that has a tank (companions count as tanks); Growl off when no other
  players are in a delve (the delve companion doesn't count).

**Stable page (StablePage.lua).** A "Stable" tab next to the options: a slowly turning model of the hovered
(or summoned) pet with name, family, spec and level, then a list: Call Pet slots, owned families (expand to
pets) and "Seen, not tamed" families from the tame log (expand to creature and zone).

## Moments (key `moments`, category "Ambience")

Each moment type has a style: Off, Banner or Cinematic.

| Moment | Source | Default |
|---|---|---|
| Level up (max level gets its own label) | `PLAYER_LEVEL_UP` | Cinematic |
| Achievement (skips account re-earns and guild) | `ACHIEVEMENT_EARNED` | Banner |
| New mount (mount model) | `NEW_MOUNT_ADDED` | Cinematic |
| New battle pet | `NEW_PET_ADDED` | Banner |
| New toy | `NEW_TOY_ADDED` | Banner |
| Area discovered | `UI_INFO_MESSAGE` matching `ERR_ZONE_EXPLORED(_XP)` | Banner |
| New zone (first discovery in a zone with no explored overlays before; zones without map fog never count; once per zone and character) | same, plus `C_MapExplorationInfo` at zone entry and 0.5s after the discovery | Cinematic |
| Renown level | `MAJOR_FACTION_RENOWN_LEVEL_CHANGED` | Banner |
| Campaign chapter complete | `QUEST_TURNED_IN` = a chapter's `rewardQuestID`, or a chapter's (often hidden) reward quest newly flagged complete 2s after a campaign quest | Cinematic |
| House level | `RECEIVED_HOUSE_LEVEL_REWARDS` (owner only; `HOUSE_LEVEL_CHANGED` also fires for other people's houses) | Banner |
| Tame (from Hunter Pets) | stable cache | Cinematic |

Left out: rare/elite kills (no combat log in 12.x), boss kills (instances are restricted and noisy).

**Cinematic style** uses the shared engine without camera moves: letterbox, UI fades out, title card in the
top band, a line in the bottom band, and the character showcase (level up) or a creature model (mount, tame)
on the left. It plays for the configured time (default 7s).

**It never takes control** (user requirement): the engine's `passthrough` option leaves the mouse and wheel
to the game and passes every key on; any key press or mouse click ends the moment and brings the UI back
(Esc ends it without opening the game menu). It only starts while the player is standing still with no mouse
button down, out of combat, outside instances, off taxis and when no other cinematic runs; if that doesn't
happen within 10s the moment shows as a banner instead. Combat or a taxi during the moment ends it.

Options: style per moment, cinematic length, preview button per moment (`/tomte moments preview <type>`).

## Testing

- `tests/test_hunter.lua` and `tests/test_moments.lua` cover the pure logic (Data.lua files).
- In game (user): stable page and tooltips, a ready check, `/tomte hunter check`, and `/tomte moments preview`.
