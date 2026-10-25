# Setting previews (2026-10-25)

From IDEAS.md "Live previews for visual settings". The user picked **on hover** and handed every other decision over
("you decide, build it, find all modules where it's useful").

## What a player sees

Pointing at a settings row that changes how something looks shows a small card under the row's tooltip: "Preview"
and a live drawing of the thing the setting changes, with sample data. Pointing at one segment of segmented buttons,
or at an item in an open dropdown list, previews that choice before it's picked ("Preview: Tiles"). Dragging a slider
or clicking a switch redraws the card at once.

## Decisions

- **Live miniatures** (decided before): drawn by the module's own drawing code, so theme, fonts and the module's other
  settings always match. No screenshots.
- **On hover** (the user's choice), not an always-shown area in the card: the settings layout stays as it is.
- **Real size**, shrunk evenly only past 420 x 340 (`ns.PanelLayout_PreviewScale`). A preview at real size answers
  "how big is size 14" honestly.
- **Placement**: under the row's tooltip (over it when there's no room below), beside the row when it has no tooltip,
  beside the list for a dropdown item. TOOLTIP strata, never takes the mouse.
- **Module pages only.** Edit Mode's settings dialog shares the rows but shows the real widget, so no card there.
- **Switches preview their "on" state** (changed after the first in-game check: the user wants a switch to explain
  itself before it's turned on). Rows under a switch that's off preview with that switch on too. During the draw the
  previewed values sit in the module's db (restored after), so tooltip lines and shared helpers that read db draw them.
- **Images for what can't be drawn still** (full-screen scenes, Blizzard's frames): `ns.Preview_Image(file, w, h)`
  shows a PNG from `Media/Previews/`, screenshots taken by the user with names hidden.
- **Which settings count as visual**: a setting gets a preview when its effect can be seen in a still drawing (looks,
  styles, sizes, opacity, fonts, which parts show). Not for behavior, timing, sounds, thresholds, or where something sits
  on screen (Edit Mode shows that).

## Framework

- `Panel/Preview.lua`: the card. `ns.Preview_Show(row, value, has, label, anchor)`, `ns.Preview_Hide(row)`,
  `ns.Preview_Refresh(module)`.
- Options schema: `preview = function(host, get) -> width, height` on any row. `host` is a frame owned by that preview
  function (the same one every time: build into it once, e.g. `host.view = host.view or Build(host)`). `get(key)` reads
  the module's settings by options key; for the row's own key it answers the hovered choice. Return nil for nothing.
- `Panel/OptionRows.lua` calls it from row hover, segment hover (`UI.Segmented` passes `onEnter(value, text)`) and the
  dropdown list (`UI.OpenChoiceList(..., onHover)`, `UI.Dropdown.onHover`). A slider keeps the card while dragged.
- Pure parts in `Panel/Layout.lua` (`PanelLayout_PreviewScale`, `PanelLayout_PreviewGetter`), tested in
  `tests/test_panel_layout.lua`.
- Widgets expose `ns.<Module>_DrawSample(host, get)` (or similar) that draws their sample into any frame: the same
  code path as the real widget, not a copy.

## Where previews went

The first user is Loot (window looks, extras, font size, opacity, items per page, Take all key; feed lines for
growing upward and reputation lines). The full list per module is in the CHANGELOG line and the final report.
