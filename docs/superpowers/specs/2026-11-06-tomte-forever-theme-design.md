# Forever theme

A theme that only exists on World of Warcraft: Forever and makes Tomte look like part of that game's UI. The user was
on Cartographer because it felt closest, but its cool charcoal, hairlines, small-caps fonts and purple accent stuck out
next to the Character and Professions windows. From three mockups (new paint; paint and frames; paint, frames and the
game's window shape) the user chose the third, then handed the rest over: "make it as good as you can with the
limitations you have. You decide what fits and works best."

## Goals

- Tomte's windows sit next to Forever's own without looking like another addon.
- Forever only: never loaded on retail, so it may lean on Forever's art and needs no fallback look.
- Other themes draw exactly as before, on both clients.

## Non-goals

- Not the default theme yet. It starts as a choice in Settings; that can change once it has been seen in game.
- Not a restyle of every module's insides. Shared widgets carry the look; module-specific art stays until it bothers.

## The key finding

Forever's frames are Blizzard's standard templates with reskinned art (branch `forever` of Gethe/wow-ui-source,
`Camelot/` folders): `PortraitFrameBaseTemplate`, the `PortraitFrameTemplate` and `SimplePanelTemplate` nine-slice
layouts, `RedButton-Exit`, the `common-sidetab*` atlases, `UI-Character-Info-Title` and `UI-Character-Info-Line-Bounce`.
So the theme points at the art the client already has rather than imitating it: nothing of Blizzard's is shipped, and
it is an exact match instead of a lookalike.

## Decisions (mine unless marked)

- **The window shape (user's choice):** the Tomte window gets the metal portrait frame with Tomte's logo in the round
  badge, the title centered in the title strip and the pages as icon tabs on the right edge instead of the left list.
- **Too many tabs:** the column scales down to fit the window's height rather than scrolling, so no page is ever out of
  reach. Names and counts' meaning are in the tooltip; a page's count sits on its icon.
- **Settings** keeps its own group rail and module list (too many modules for tabs). It gets the frame and widgets.
- **Other windows** (bags, dialogs, cards) get rock and the window frame's bronze edge with its bottom flipped for the
  top, no badge: their headers are laid out to the top-left corner, and the badge would sit on the bags' buttons.
  `SimplePanelTemplate` was the first try, but it's grey on Forever (seen in game).
- **Rock:** the game's rock is pale grey beside its warm dark windows (seen in game), so the theme's `bg` lies over it.
- **Widgets over the game world** (`subtle` panels, `small` panels) stay light: a flat fill and a faint bronze rule.
- **Toasts** use the game's tooltip frame and fill, to look like the game's own messages over the world.
- **Buttons** use the game's red `UI-Panel-Button` art; every "x" button becomes the real `RedButton-Exit`, the bags'
  close glyph too. Dropdowns are not red: they read as a field.
- **Headings:** Home's section headings and the settings cards' titles sit on the stat plaque, three-sliced so it
  stretches without smearing its ends. List rows (`Kit.PoolRow`) get the stat list's alternating stripe.
- **Bars and toggles:** `UI.Bar` is the game's progress bar (`common-stat-bar-*`), and `UI.Switch` and `UI.Checkbox` are
  its checkbox (`checkbox-minimal`). A bar's own rect stays the caller's and the frame hangs outside it, so layouts stay
  put. Default fill is blue, like the skill bars. The thin progress lines (`UI.ProgressLine`) stay as they are.
- **Action icons** (added 2026-11-06, when the user asked for everything to match): anything you press on screen, the
  fishing, feed, poison, seed and drawer buttons, the missing buffs and Pet Health's spells, is the game's action button
  (`UI.ActionIcon`). Its light replaces the colored edge that says how urgent a poison or buff is (`UI.ActionIconMark`).
- **StatusBars:** Pet Health and the Flight Timer can't be a `UI.Bar` (health can be secret, the flight bar's fill is the
  game's), so `UI.Forever_StatusBarArt` gives a StatusBar the same frame, its fill tinted on the white bar.
- **Bag slots** keep the template's own slot art and quality border instead of the hairline look. A line only shows for
  what the art can't say: a category's color, or what a vendor takes as payment.
- **Left as they are on purpose:** the Casino, cinematics and Loot's strips and tiles have designs of their own, and
  list rows inside windows only have small icons.
- **Search boxes** use the game's field and magnifying glass, applied where every search box already calls
  `UI.SearchBoxClear`. Other text fields keep the plain surface.
- **Whispers** reads as chat: messages are the game's chat lines rather than bubbles, theirs in the player's whisper
  color and yours as "[You]:" in a muted color on a faint band (all in one color they were hard to tell apart), the
  input is the chat frame's line, and the list and messages sit in sunken wells (`UI.Forever_Well`, the
  `common-insideframe` art) for depth rather than being divided by lines. Other themes keep the bubbles.
- **No Background opacity setting and no scroll edge fades:** rock isn't a flat color a fade could match, and the
  game's own windows are solid.
- **The bag and bank windows have the game's bag top** (the user's call): metal title strip, round badge, centered title and
  the red close button in the corner, with the search and buttons on a band under the strip. Other themes keep them in the band.
- **Settings cards don't light up under the mouse** (the user's call): the game's own panels don't. Other themes keep it.
- **Text:** the client's font everywhere, white text and yellow headings from Blizzard's color globals.

## Where the code lives

- `Themes/Forever.lua`, `Panel/ForeverArt.lua`, `Panel/ForeverTabs.lua`: loaded only through `extra` in
  `tools/forever_list.lua`. `Theme.panel == "forever"` is the switch; shared files check it and call in at run time.
- `UI.Panel`, `UI.Button`, `UI.Dropdown`, `Kit.Heading`, `Kit.PoolRow`, the settings cards, the theme preview, the bags'
  close button and `Panel.lua`'s title bar and rail each have a small branch.

## Open until seen in game

The art's real sizes aren't readable from the source: tab size and plaque ends come from `C_Texture.GetAtlasInfo` at
run time, but the title strip's height, the frame's overhang and the plaque's cap fraction are judged from the source
and may need a nudge.
