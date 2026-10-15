# CurseForge project page

Everything to fill in when creating or editing the Tomte project on CurseForge (https://authors.curseforge.com).
Dev-only (docs/ is left out of the release zip).

## Project settings

- **Name:** Tomte
- **Game / class:** World of Warcraft, Addons
- **Main category:** Miscellaneous. Extra categories: Map & Minimap, Professions, Achievements, Bags & Inventory, Pets.
- **License:** GNU General Public License version 3 (GPLv3)
- **Source:** https://github.com/tomte55/Tomte (Project > Source settings, so the page shows a "Source" link)
- **Issues:** https://github.com/tomte55/Tomte/issues
- **Avatar:** `docs/curseforge/logo-400.png` (400x400, rendered from `Media/Logo.svg`)
- **Summary** (one sentence, max 120 characters):

  > Your gear, your week, your alts, gold, travel and collecting in one window, with a cinematic touch.

## Images tab

Upload these from `docs/screenshots/` (real in-game shots, no AI editing, character and guild names hidden), with
the alt text from README.md as the title: `hero.png` (featured), `window-home.png`, `showcase-card.png`,
`gearcheck-tooltip.png`, `weekly-board.png`, `alts.png`, `crafting-list.png`, `waypoints.png`,
`map-worldquests.png`, `gold-wq.png`, `gathering-map.png`, `sessions.png`, `afk.png`, `moment.png`.

## First file

Upload `Tomte-vX.Y.Z.zip` from the latest GitHub release, game version 12.1.5, release type Release, changelog: that
version's section of CHANGELOG.md (Markdown). Later versions upload themselves from the release workflow once
`## X-Curse-Project-ID` is in Tomte.toc and the `CF_API_TOKEN` secret is set.

## Description (paste into the editor, Markdown)

---

**Tomte** is one addon for everything around the fighting: your gear, your week, your alts, gold, travel and
collecting, with a cinematic touch.

It's a set of modules you switch on and off. Everything has a home in one window (`/tomte`), and the rest lives where
you already look: tooltips, the world map, the mailbox, the bags. On first login Tomte asks what you want (Minimal,
Collector, Crafter or Everything), and `/tomte setup` brings that choice back any time.

### Your gear

- **Gear Check:** an upgrade verdict on item tooltips that knows what a simple score doesn't: armor type, main stat,
  tier sets, lost effects, unique limits, upgrade track. It says "sim it" when only a sim can tell, and which of your
  other characters an item would be an upgrade for. Built-in stat weights for every spec, or import your own from
  Raidbots.
- **Showcase:** the camera glides in on your character with your gear around it: item level, missing enchants and
  gems, stats. Hover a slot for the item's 3D model; click to swap, socket or enchant.
- **Dressing room:** Blizzard's dressing room, bigger, with a slot bar and an outfit list.
- **Vendor helper** and **Durability:** repairs, selling grey items, and a warning before a dungeon with low gear.

### Your week and your alts

- **Weekly board:** Great Vault, weekly quests, profession knowledge, renown factions, raids and every alt in one
  grid. Alts roll over at the weekly reset without logging in.
- **Alts:** every character at a glance and crafting across them: who can make something, where the materials are,
  and a crafting list that works out what to buy, craft and mail. At a mailbox, "For your alts" attaches what your
  other characters need.
- **Material uses:** crafting materials say on their tooltip who uses them, so you know what to bank and what to sell.
- **Delves**, **Holidays & events**, **Next up** (the best things to do right now) and **Almost Done** achievements.

### Getting around

- **Waypoints:** a marker in the world on whatever you track, with distance and arrival time. Up close it turns into a
  card with the objectives, and a map pin on another continent is routed through the portals and boats on the way.
- **World map side panel:** World quests sorted by what they're worth to you, Collect here (mounts, pets and
  achievements still missing on that map) and Teleports.
- **Smart Mount** (one key, the right mount for where you are) and the **Flight Timer**.

### Gold and gathering

- **Gold world quests** with a route through them, **Gathering** runs with node spots and routes on the map,
  **Fishing** on one key, and **Sessions**: gold per hour and a recap card for every play session.

### The cinematic side

An AFK screen, a session recap at logout, moments for new mounts, achievements and level ups, and a cinematic flight
mode. Cinematics never lock your controls: any key or click ends them.

### And more

Pet battle help (the right pet to swap to, tamer teams, paste Xu-Fu strategies and play them one key press at a time),
whisper toasts and an inbox, a trade chat filter, chat tabs and copy, group alerts, hunter and rogue helpers, seven
themes, and settings sharing between players.

### Good to know

- Retail only, English only.
- Works with (all optional): Baganator + Syndicator, Auctionator or TradeSkillMaster, Mount Journal Enhanced.
  Tomte's settings have an "Other addons" page that lists what it clashes with, works with or replaces.
- Content follows your character's expansion (The War Within or Midnight). The Midnight data is newer and still
  being checked in game: if something looks wrong there, a comment helps.
- **Found a bug?** Type `/tomte bug`, copy the report and paste it in a comment or a GitHub issue. Nothing is sent
  anywhere by Tomte itself.

### Credits

Tomte is GPL-3.0. It credits every addon and site it learned from or took IDs from (Plumber, LibDBIcon, Narcissus,
Xu-Fu's Pet Guides, wago.tools and more) in the Credits section of its README. Fonts are under the SIL Open Font
License, with their license texts in `Media/Fonts`.

Source and issues: [GitHub](https://github.com/tomte55/Tomte)
