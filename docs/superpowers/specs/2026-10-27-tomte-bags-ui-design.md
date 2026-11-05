# Bags UI overhaul: one case, hairline slots, a calmer categories page

Date: 2026-10-27. Module: `Modules/Bags` (and the bag-related panels). Follows
`docs/superpowers/specs/2026-10-27-tomte-bags-design.md`, whose features are all built and confirmed in game. Mockups
from the design talk (throwaway, scratchpad): `ui-directions.html` (A chosen), `slot-pick.html`,
`categories-page.html`.

## Why

The user, about the bag window today: "it feels flat and the buttons and search bar feels just pasted on,
everything feels so disconnected, it all looks so basic and like a prototype." Priority now is UI/UX: good visuals
and above all layout. No feature changes are asked for; this is how the existing features look and sit.

## Goals

1. Every control belongs to a structure: actions live in a **header band**, items in a **tray**, totals in a
   **footer band**. Nothing floats.
2. One visual language across the bag window, the bank window, the side panels (currencies, Find on all
   characters), the bag slots row, the bank tabs, the gold drawer and the Bag categories page.
3. Item slots that look like Tomte, not Blizzard's slot art.
4. Works in all seven themes with no new art: built from theme roles and flat textures only.

## Non-goals

- New features, new settings beyond what the look needs, changes to categories or search. One exception the user
  asked for: dragging rows to reorder on the Bag categories page (below).
- Editing categories inside the bag window (still a later idea).
- New theme art, new fonts (both need tools and a client restart).

## Anti-goals

- Anything that still reads as a prototype: loose buttons at different heights, mismatched sizes, controls not
  aligned to a shared edge.
- Lower density than today: the user values Baganator's density.
- A look that works in Cartographer only. Numeric colors outside the theme (tests/test_theme.lua forbids them).
- Breaking what works: item clicks (Blizzard's template, untainted click path), drag and drop, the bank's hidden
  BankFrame, combat behavior.

## Constraints

- CLAUDE.md "UI and theme": colors and fonts by role only (`UI.Color`, `UI.Text`, `UI.Panel`, `UI.Wrap`), never read
  at file load; theme switch must reach everything (repaint on theme change the way other Tomte windows do).
- Motion: `Panel/Motion.lua` kit only (the user's Motion setting), never scale text (memory: scale on text lags and
  jitters), translations through `UI.EnterUp`-style whole-pixel moves. One orchestrated moment beats many.
- Item buttons stay `ContainerFrameItemButtonTemplate`; their look changes through their own regions (hide or
  recolor NormalTexture, IconBorder and the like) and Tomte's textures on top. Nothing written on the buttons that
  Blizzard's click code reads.
- Files past ~900 lines get split first, as pure moves, in their own commit.

## The bag window (direction A, "one case"; the user's choice)

```
 [bag][bag][bag][bag][bag]                    <- bag slots as tabs on the top edge (when shown)
+-------------------------------------------------------------+
| [bags|chars]  Bags   [ search, try is:upgrade        (?) ]  [★|⇅|⚙|✕] |  <- header band
+-------------------------------------------------------------+
|  ┌ tray ───────────────────────────────────────────────┐   |
|  │ Upgrades   Hearth   Potion       Food                │   |
|  │ ▣          ▣        ▣ ▣          ▣ ▣                 │   |
|  │ Equipment ──────────────────────────────────────── │   |
|  │ Armor                                                │   |
|  │ ▣ ▣                                                  │   |
|  └──────────────────────────────────────────────────────┘   |
| [¤] 117 free slots [▬▬▬▭▭]  13◆ …                17,146g   |  <- footer band
+-------------------------------------------------------------+
```

- **Header band:** a darker band across the top (surface over bg), one height, everything vertically centered.
  - Left: bag slots and character buttons joined as one cluster (one frame, inner dividers).
  - Then the title: "Bags", or "Bags: <name>" while looking at another character.
  - The search box fills the middle, sunk into the band (inset look: darker fill, inner shadow line).
  - The keyword help "?" sits inside the search box at its right end. *(Claude's call)*
  - Right: one joined cluster: saved searches ★, sort, settings, close.
- **Tray:** all items in one recessed tray (darker than the window, a dark edge and a top inner shadow line).
  - Category labels small, above their icons, as today.
  - Section names in the title font, followed by a hairline running to the tray's right edge; the fold sign stays.
  - Dividers are a hairline across the tray.
- **Footer band:** matches the header.
  - Left: the currencies button, "N free slots", and a small fill meter (used / total, accent fill).
  - Then the tracked currencies; gold on the right.
- **Bag slots row:** the equipped bags as tabs standing on the window's top edge, attached to the frame (no
  separate floating panel), each with its free count. Shown and hidden by the bags button as today.

## Item slots (hairline; Claude's suggestion, the user agreed)

- A 1-pixel frame in the theme's rule color around each icon; uncommon and better get the frame in their quality
  color instead (Blizzard's thick IconBorder hidden, its slot art hidden).
- Empty slots: a faint filled square in the same frame; Empty's buttons keep their free count and the reagent leaf.
- The slot under the mouse lights its frame in the accent.
- Search and "doesn't fit" fading stay as they are (Blizzard's context overlay).
- All corner marks keep working (arrow, badge, item level, set, pet level, junk coin, crafting count).

## The bank window (same anatomy; Claude's calls, played back to the user)

- Header band: Character / Warband as one joined two-part switch (selected part lit), the title, then a joined
  cluster with sort and close.
- The same tray.
- Bank tabs: real tabs standing out from the window's right edge, attached to the frame; the selected one (tab
  filter) is visually connected to the window (same fill, no frame line between). The buy "+" is the last tab.
- Footer band: Deposit warbound items and Include reagents on the left; Warband gold with Deposit / Withdraw on
  the right.
- The gold panel becomes a small drawer that slides out under the footer, attached to it (same width as the
  Deposit/Withdraw group or wider, flush with the window's edge).

## Side panels (Claude's calls)

- The currencies panel and Find on all characters dock flush against the bag window's left edge (no gap, same
  height, frame lines meeting), with the same header band (title + close) and their list in a tray.
- Only one side panel at a time: opening one closes the other.

## The Bag categories page (mockup `categories-page.html`; the user: "looks good")

- Header band: the title, a joined cluster "+ Category / + Section / + Divider", and on the right a joined cluster
  "Share / Import / Defaults".
- The list in a tray:
  - A drag grip on each row; dragging reorders (within and between sections, dividers too) with a drop line where
    it will land. **In this pass** (the user's decision): a new pure move operation in EditData.lua (move a node to
    a list position, into or out of a section) with tests, scrolling when the drag reaches the list's edge, its own
    CHANGELOG line. EditPage.lua is split first (pure move) since the new editor groups would push it past 900
    lines. Move up / Move down stay as a fallback.
  - Item counts as small pills on the right.
  - Section rows in the title font with a hairline after the name; their categories indented.
  - Automatic categories (New, Equipment sets, Other, Empty) in a quieter italic.
  - The picked row with an accent edge on the left and a soft accent wash.
- The editor, right: the category name as a large title (click to rename), then three small groups (a frame and a
  slightly darker fill each):
  - **What goes in:** the rule box (sunk), the matching icons, and a one-line result ("2 items in your bags match"
    in success color, or the rule's error in danger color).
  - **When two categories want an item:** the priority slider labeled lower / higher with its number, and one
    line of explanation.
  - **Where it shows:** the Bags / Bank / Warband bank switch, On a row of its own, Hidden.
- **Always in it:** a drop area showing the items as icons (drop to add, right-click an icon to remove), replacing
  the item-ID box. *(Claude's call)* Pasting IDs stays possible behind a small "paste IDs" link.
- A bottom row: Section dropdown, Move up / Move down, and Delete in the danger color on the right.
- Sections and dividers show only what applies to them (name and the bottom row).

## Motion (Claude's calls)

- The bag and bank windows fade in with the kit's window fade (as the Tomte window does); no per-item animation.
- The gold drawer slides out from under the footer; the bag slots tabs and side panels fade in.
- Hover: slot frames and buttons ease to the accent (kit's BorderTo / washes).

## Decided after the builder check *(Claude's calls)*

- "Buttons only on hover" stays: the joined clusters fade, the header band itself stays.
- A bad search shows on the search box itself (danger-colored frame, the reason in its tooltip) instead of a line
  under it, so the band keeps one height.
- The fill meter counts the same bags as the free slots (backpack, bags 1-4, reagent bag).
- Hairline frames are 1 screen pixel whatever the button's scale (corrected for the size/37 scaling).
- On the Bag categories page the Tomte window's own title bar is the title; the page's band holds only the two
  button clusters.
- Window fades use the kit's existing `UI.Appear` / `UI.Disappear`.

## Left to the builder

- Exact sizes, paddings, band heights, tray insets, the meter's size, tab sizes (within "dense").
- How the inset and inner-shadow look is drawn from flat textures and theme roles.
- Whether the windows' code is restructured (e.g. a shared "frame kit" for band / tray / tabs in the Bags folder or
  in Panel/), as long as files stay under ~900 lines and splits are pure moves first.
- How drag reordering is drawn (ghost row, drop line) in the categories list.
