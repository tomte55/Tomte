# Loot: feed for auto loot, three window looks for manual loot

Date: 2026-10-25. Module: `Modules/Loot`. Mockups: the "Tomte Loot Window Mockups" canvas (private artifact,
boards "Today: List", "A: Feed strips", "B: Rich panel", "C: Tiles").

## Why

The user only likes the Feed style. List and Card feel flat and empty (thin box, tiny icons, every line the same
weight), and the three styles behave inconsistently:

- The feed shows up in List and Card too, because reputation, currency and the replaced Blizzard pop-ups
  (`Toasts.lua`) always go to the feed. A currency looted from the window then shows twice (window row and feed
  line), as Resonance Crystals did.
- With auto loot in List or Card, the window lingers after the loot closes with every row faded and desaturated
  (`TAKEN_ALPHA`), which reads as broken loot, not as "here's what you got".
- Card's "best item" is picked even when nothing is worth featuring (Glittering Glass from a Waxy Blob).

The user's model: auto loot wants the feed only; a window makes sense for manual looting.

## Goals

1. **How loot shows up is decided by auto loot, not by a style setting.**
   - Auto loot (the existing `ns.Loot_ShouldAutoLoot` result, `session.auto`): always the feed. No window, except
     the existing "stuck" case (something left after auto loot: full bags, a roll, locked loot) which opens the
     window after `STUCK_DELAY` as Feed style does today.
   - Manual loot (auto loot off, or the auto loot key held): the loot window opens.
   - The after-auto-loot linger (`ns.LootWindow_Closed(linger)`, `fadeDelay` on the window, the `FadeOut` path) is
     removed. The window closes when the loot closes.
2. **The feed is the one place for everything gained**, in every setup: items and coin taken by auto loot, plus
   reputation, currency and the replaced pop-ups as today. Nothing shows twice.
3. **The window has three looks**, picked by one setting:
   - **Strips (default)**, mockup A: no box. Each loot slot is a feed-style strip (quality bar on the left, larger
     icon, name, extras after it, dark strip fading out to the right, same drawing as `Feed.lua`'s lines) that stays
     until taken. Header: the source name (or "Loot") in the heading font with a small spaced muted note after it
     (mockup: "AND 3 MORE" for area loot, if that's readable; otherwise just the name). The hovered strip lights up
     in the accent. Take all below as a keycap plus "Take all".
   - **Panel**, mockup B: replaces both List and Card. A themed panel (`UI.Panel`, full art) with a header band:
     a spaced "LOOT" label over the source name, close button. A featured item on top only when one deserves it
     (see below), then two-line rows: name and count on top, a muted second line (item type, owned count), value
     right-aligned. Coin moves to the footer as "+ 12g 40s"; Take all is a filled accent button with its keycap.
   - **Tiles**, mockup C: a grid of large icon tiles (5 per row at the default size) with quality-colored borders,
     stack counts bottom-right, an upgrade marked on its tile. A caption strip under the grid names the item under
     the mouse (name, count, extras); with nothing hovered it names the first item. Footer: item count and total
     value, Take all with its keycap.
4. **Taken rows disappear instead of greying.** When a slot is looted by hand, its row/strip/tile leaves the window
   and the rest close up. The window closes by itself when the loot closes (as the game's does). *(Claude's call:
   greying was what the user disliked, and with feed confirmation the window doesn't need to keep a record.)*
5. **Feed confirmation for manual loot**, a setting, on by default: each item, coin or currency taken from the
   window by hand also slides into the feed, so the player sees it was looted. Off: the window alone.
6. **No duplicates.** A currency taken from a loot window is noted like items are (`ns.LootToasts_Note`, a
   `c:<currencyID>` key checked by `PushCurrency`'s `Fresh`), so the currency event doesn't add a second line.
   Coin likewise comes once (PLAYER_MONEY delta, as today).

## Who writes which feed line *(Claude's calls, after the builder check)*

- "Hand-looted" means the loot session was not auto loot (`not session.auto`). A window that opened because auto
  loot left something behind is part of an auto loot session: what you take from it always goes to the feed,
  whatever `feedManual` says.
- In an auto loot session the loot path writes item and junk lines (as Feed style does today), coin comes from the
  PLAYER_MONEY delta, currency from the loot path too.
- In a manual session with `feedManual` on: the same, so the feed confirms each slot you click.
- In a manual session with `feedManual` off: no feed line for anything taken from that window, coin and currency
  included (the PLAYER_MONEY handler checks the session).
- A currency taken from any loot window is always noted (`c:<currencyID>`), so the currency event never adds a
  line for it, with `feedManual` on or off. `extras.repCurrency` keeps covering currency gained outside loot
  windows (quests, world events) and reputation.
- Another addon owns the loot window (`session.other`): Tomte opens no window, as today. Auto loot sessions still
  feed (the feed is Tomte's own); manual sessions follow `feedManual`. That's a window and a confirmation, not
  the same gain shown twice.

## Non-goals

- No change to fast loot, the take-all key, the key binding, the boss banner, pop-up replacement, reputation lines,
  junk folding or the extras' meaning.
- No new feed look; the feed stays as it is (the user likes it).
- No window for auto loot as an option. *(Claude's call; easy to add later if asked.)*

## Anti-goals

- Anything that makes a looted item look disabled or broken.
- A setup where the same gain shows twice.
- Losing a player's current choice silently: an existing choice maps to the nearest new one.

## Featured item (Panel)

Shown only when an item deserves it: a Gear Check upgrade, or an item `ns.Loot_IsValuable` accepts (mount, pet,
toy, legendary, set token). Otherwise no featured slot; everything is a row. *(Claude's call; today's
`ns.Loot_BestIndex` always picks something, which gave Glittering Glass the big spot.)* This is pure logic: a new
`ns.Loot_FeaturedIndex(entries)` (or a stricter mode of `Loot_BestIndex`) in `Data.lua`, with tests.

## Settings

- `style` ("list" | "card" | "feed") is replaced by `look` ("strips" | "panel" | "tiles"), default "strips".
  A migration appended to `ns.MIGRATIONS` maps list and feed to strips, card to panel, and removes `style`
  (cope with a missing `loot` table; a case in `tests/test_migrations.lua`).
- New `feedManual = true`: the feed confirmation of goal 5. Label "Show hand-looted items in the feed".
- `fadeDelay` now only concerns the feed: tooltip "How long a feed line stays before it fades."
- Font size, background opacity, items per page, grow upward and open at the mouse apply to all three looks
  (Tiles: items per page counts tiles).
- The settings card text, the module `summary`, `description`, the Style tooltip, `/tomte loot why` wording, the
  Edit Mode options list and the `PREVIEW` sample follow the new model. `/tomte loot test` shows the chosen look.
- The extra `source` ("Where it came from") stays and feeds every look's header.

## Constraints (from the codebase)

- Midnight rules as today: `Readable` checks on event payloads, no combat-dependent logic, the take-all key's
  keyboard handling stays out of combat (`ns.LootWindow_UpdateKeys`), Blizzard's `LootFrame` handover unchanged.
- Colors and fonts by theme role only; strips reuse the feed's drawing rather than copying it (move the shared
  strip drawing where both can use it, e.g. a helper exported from `Feed.lua` or a small new file).
- `Window.lua` is 785 lines. The looks go into new files from the start (`LookStrips.lua`, `LookPanel.lua`,
  `LookTiles.lua`, shared pieces in `Parts.lua`) and Window.lua loses the List/Card drawing and the linger, so it
  shrinks; no pure-move split is needed first. *(Changed while planning.)*
- Each look draws into a parent frame it's given, from entries and settings it's given (not only `db` and the one
  window), so the next project, live previews of visual settings (`IDEAS.md`), can draw a look with sample loot in
  the settings. No preview UI in this project.
- README module row and description, CHANGELOG under Unreleased (`### Improved`) once confirmed in game.

## Left to the builder

- Exact sizes and spacing, within the mockups' proportions, scaled by the font size as today.
- How a strip, row or tile leaves when taken (instant or a short fade), as long as it never greys and lingers.
- Paging in Tiles and Strips (same `ns.Loot_Page` rules).
- Whether Strips' area-loot note is possible; drop it if the corpse count isn't readable.
