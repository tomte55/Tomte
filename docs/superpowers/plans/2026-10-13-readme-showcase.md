# README showcase (2026-10-13)

Goal: turn README.md into a player-facing showcase with screenshots. The user takes the pictures in game, then
Claude rewrites the README around them.

Status: 2026-10-13, README rewritten around the first batch (27 images in docs/screenshots/, cropped, alpha
flattened, character and guild names pixelated). Not committed yet. Unused so far: gearcheck-sidegrade.png,
material-tooltip-short.png. Missing shots below can be added to the tour later.

## Where the images go

`docs/screenshots/` (already export-ignored, so the release zip doesn't grow). PNG, cropped to the feature.

Before shooting: one theme for everything (Cartographer) except the themes shot; blur Battle.net friend names,
whisper text and other players' names; hide BugSack, DBM bars and other clutter.

## Must-have (hero and core)

- [x] `hero.png`: character with something striking on screen (Showcase is probably best), top of the README
- [x] `window-home.png`: Tomte window on Home (Next up, Around you, characters, rail with counts)
- [x] `setup.png`: first-login setup choice (`/tomte setup`)
- [ ] `showcase.png`: Showcase with gear columns and stats
- [x] `showcase-card.png`: Showcase hovering a slot (item card with the 3D model)
- [x] `waypoints.png`: in-world marker on a tracked quest at a distance (distance and arrival time)
- [x] `waypoints-card.png`: the same marker up close (objectives card)
- [x] `gearcheck-tooltip.png`: item tooltip with Gear Check's verdict, ideally "Upgrade for <alt>"
- [x] `weekly-board.png`: Weekly board, This week tab
- [x] `alts.png`: Alts, detailed Characters view

## Nice to have

World map side panel
- [x] `map-worldquests.png`: World quests tab with mounts or gear rewards on top
- [x] `map-collect.png`: Collect here tab
- [x] `map-teleports.png`: Teleports tab
- [x] `gathering-map.png`: world map with node spots and a route

Gold, crafting, pets
- [x] `gold-wq.png`: Gold world quests window with zone totals
- [x] `crafting.png`: Crafting tab with cost and profit, or the crafting list tracker
- [x] `mailbox-alts.png`: "For your alts" panel at a mailbox
- [x] `material-tooltip.png`: material tooltip "Used by Aldric: Blacksmithing..."
- [ ] `pet-battle.png`: pet battle helper during a fight ("Swap to X?")
- [ ] `pet-tamer.png`: tamer card (team, ready status, Load team)

Ambience
- [x] `afk.png`: AFK screen
- [x] `recap.png`: session recap card (`/tomte recap`)
- [x] `sessions.png`: Sessions page with the gold-per-hour chart
- [x] `moment.png`: a Moments reveal (mount or level-up)
- [x] `flight.png`: flight countdown or cinematic flight mode

Smaller pieces
- [ ] `delves.png`: Delves page or the note beside the tier picker
- [ ] `achievements.png`: Almost Done docked to the Achievements window
- [ ] `dressing-room.png`: bigger dressing room with the slot bar
- [ ] `toasts.png`: two or three toasts, or the Recent list
- [ ] `trade-filter.png`: Trade chat with highlighted matches (names blurred)
- [ ] `themes.png`: the Tomte window in 3-4 themes (or `theme-<key>.png` each)

## Optional GIFs (under ~10 s and ~5 MB each, e.g. ShareX)

- [ ] Showcase camera glide-in
- [ ] Waypoints arrow turning into the card while walking up
- [ ] Gathering follow mode moving the pin to the next spot
- [ ] A Moments reveal

## README plan (once the images are in)

1. Hero image and a short pitch.
2. Install.
3. Feature tour grouped by what a player does (gear, gold and crafting, travel, collecting, ambience), with images.
4. The full module table and commands kept, but folded into `<details>` so the page stays scannable.

Missing shots are fine: write around what exists.
