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

Upload the showcase slides from `docs/curseforge/images/` (1920x1080, in this order; real in-game shots laid out on
slides, character and guild names blurred), with these titles. `01-title.png` is the featured image.

| File | Title |
| --- | --- |
| `01-title.png` | Tomte: your gear, your week, your alts, gold and travel, in one window |
| `02-home.png` | Open it and see where you're at |
| `03-showcase.png` | Showcase: your character with all your gear around it |
| `04-gear-check.png` | Gear Check: is it an upgrade? |
| `05-weekly-board.png` | The Weekly board, for all your alts |
| `06-crafting.png` | Crafting with your alts |
| `07-waypoints.png` | Waypoints you can actually see |
| `08-world-map.png` | More out of the world map |
| `09-gold.png` | Making gold |
| `10-social.png` | Chat & social |
| `11-moments.png` | Little moments |
| `12-housing-decor.png` | Housing decor |
| `13-more.png` | And a bunch more |
| `14-your-call.png` | Doesn't get in your way |

The slides were laid out from crops in `docs/screenshots/new/`; the inbox on slide 10 is `/tomte whispers preview`.
Remove the old screenshots from the Images tab when these are up.

## First file

Upload `Tomte-vX.Y.Z.zip` from the latest GitHub release, game version 12.1.5, release type Release, changelog: that
version's section of CHANGELOG.md (Markdown). Later versions upload themselves from the release workflow once
`## X-Curse-Project-ID` is in Tomte.toc and the `CF_API_TOKEN` secret is set.

## Description (paste into the editor, Markdown)

---

### Why Tomte exists

Tomte started out as something just for me. All I wanted was a flight timer, with good cinematics, that looked and
felt the way I had in mind. Then I kept tinkering. One module turned into two, two turned into ten, and somewhere
along the way it became this whole thing.

That's when the real idea took shape: I wanted one addon for everything I need. Not a folder full of addons that each
have to catch up after every game patch, each with its own look, its own settings window and its own minimap
button. So I started building the things I liked about popular addons into one addon of my own, with one look and one
place for all the settings.

The part I like most is that the modules know about each other. Separate addons can't really do that, and it's where
Tomte becomes more than the sum of its parts:

- Gear Check doesn't just tell you whether an item is an upgrade for you. It tells you which of your alts it would be
  an upgrade for.
- Crafting materials say on their tooltip which of your characters use them, and at a mailbox "For your alts" attaches
  what your other characters need.
- **Next up** on the home page looks at your week, delves, world quests and what's left to collect, and tells you the
  best thing to do right now. Click it to start.
- A map pin on another continent gets a waypoint routed through the portals and boats on the way.
- The world map shows what you're still missing on that map: mounts, pets and achievements.
- Gold, sessions, whispers and alts cover all your characters, and when you log out the recap shows what the session
  brought.

After a while my friends wanted it too, so I cleaned it up and shared it with them, and now it's here for anyone who
wants it. I play with it every day and I keep adding to it.

### How it works

Tomte is a set of modules you switch on and off. Everything has a home in one window (`/tomte`), and the rest lives
where you already look: tooltips, the world map, the mailbox, the bags. On first login Tomte asks what you're into
(Minimal, Collector, Crafter, Social or Everything), and `/tomte setup` brings that choice back any time. Anything
you don't want, you turn off, and it's fully gone.

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

### Housing decor

The **Decor** page lists the decor you're missing, by source or by vendor. Turn one in a 3D preview and get led to
where it comes from.

### The cinematic side

This is where it all began. When you go AFK, log out, take a flight or get a new mount, achievement or level, Tomte
gives it a moment. Cinematics never lock your controls: any key or click ends them.

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
- **Pet Health:** your pet's health under your character (Hunters, Warlocks and Unholy Death Knights), with
  reminders for a dead or missing pet.

### And more

Pet battle help (the right pet to swap to, tamer teams, paste Xu-Fu strategies and play them one key press at a time),
seven themes so the whole thing looks the way you like, and settings sharing between players.

### Good to know

- Retail only, and the text is English only.
- It plays nicely with (all optional): Baganator + Syndicator, Auctionator or TradeSkillMaster, Mount Journal
  Enhanced. Tomte's settings have an "Other addons" page that lists what it clashes with, works with or replaces.
- Content follows your character's expansion (The War Within or Midnight). The Midnight data is newer and I'm still
  checking it in game, so if something looks wrong there, a comment helps.
- **Found a bug?** Type `/tomte bug`, copy the report and paste it in a comment or a GitHub issue. Nothing is sent
  anywhere by Tomte itself. This is a hobby project, but I do read them.

### Credits

Tomte is GPL-3.0. It credits every addon and site it learned from or took IDs from (Plumber, LibDBIcon, Narcissus,
Xu-Fu's Pet Guides, wago.tools and more) in the Credits section of its README. Fonts are under the SIL Open Font
License, with their license texts in `Media/Fonts`.

Source and issues: [GitHub](https://github.com/tomte55/Tomte)
