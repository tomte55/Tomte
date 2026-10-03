# Tomte: settings panel redesign, minimap button, seen-beast models

## Goal

The panel was a fixed 760×480 frame with three columns: categories, modules, details. With 10 modules and two
custom pages (Stable, Coverage) the detail pane is too small: the Stable list shows about 5 rows. The user wants a
layout that fits all modules and pages and is clear to use. Two additions came up in the same session: a minimap
button, and 3D models for beasts in the tame log.

Decisions agreed with the user (2026-10-03): standalone panel only, resizable and remembered, layout "A"
(sidebar + full page), Stable preview in a right-hand column, minimap button, seen-beast models.

## 1. Window

- Standalone only. `/tomte`, the addon compartment and the minimap button open it. Esc and the `x` close it.
- Opens at 960×640 the first time. Resize grip in the bottom-right corner (Blizzard's chat size grabber
  textures). Resize bounds: min 820×560, max the UIParent size.
- Position and size are saved in `TomteDB.panel.layout = { point, x, y, w, h }` (point relative to UIParent's
  same point) on drag stop and resize stop, and restored when the panel is built. Clamped to the screen.
- The title bar drags it. A small icon (`ns.ICON`) sits left of the "Tomte" title.
- Options → AddOns → Tomte is a canvas page with a title, one line of text and an **Open Tomte** button. The button
  closes Blizzard's settings (`HideUIPanel(SettingsPanel)`) and opens the panel. The old embedded mode
  (re-parenting the panel into the canvas) is removed.

## 2. Sidebar (left, 220 px)

- Search box at the top. It filters by module name and description. Esc clears it. Category groups with no
  matching module are hidden. "No matching modules." when nothing matches.
- All modules in one scrollable list, grouped under grey upper-case category headers, in registration order.
- Categories collapse and expand on a click on their header (`+`/`-`, module count on the right). The collapsed
  ones are saved in `TomteDB.panel.collapsed[category] = true`; all are expanded by default. While searching,
  every match shows regardless. A collapsed category that holds the selected module has a gold header.
- Module row: checkbox (enables/disables the module) + name. Clicking the row selects the module: gold bar on the
  left and a light background. Blocked modules show dimmed with the checkbox disabled.
- Hovering a row shows a tooltip with the name and description. The page on the right doesn't change on hover.
- The selected module is saved in `TomteDB.panel.selected` (module key). Default: the first module. If the saved
  key no longer exists, the first module is used.
- The old category buttons and `TomteDB.panel.category` are removed (the key is cleared on load).

## 3. Module page (right of the sidebar)

- Header: module name (Morpheus, 22) and an **Enabled** checkbox on the right that mirrors the sidebar checkbox.
  Below: the description in grey (wraps), and the red blocked reason when there is one.
- Tabs (**Options | <page title>**) only for modules with a page. The chosen tab is remembered per module for the
  session; Options is the default.
- The content fills all the remaining height and scrolls.
- Options rows are unchanged (header, checkbox, slider, dropdown, button, input). The column is capped at 560 px
  wide and left-aligned.
- A blocked module shows only the header and reason (its data may be getting replaced), as before.
- A module with no options and no page shows "No options."

## 4. Minimap button (new module)

- Module `minimap`, name "Minimap Button", category **General**, on by default. Its files load before the other
  modules, so General is the first category in the sidebar. Turning the module off hides the button.
- Built without a library, matching LibDBIcon's retail look: 31×31 button on `Minimap`, MEDIUM strata, level 8,
  tracking border (136430, 50×50 at TOPLEFT), background (136467, 24×24 centered), icon 18×18 centered with a round
  mask, Blizzard's zoom-button highlight (136477).
- Left-click toggles the panel. Drag moves it around the minimap edge. The angle (degrees, default 225) is saved in
  the module db. Tooltip: "Tomte", "Click to open settings", "Drag to move".
- Position follows `GetMinimapShape()` when another addon defines it (square minimaps), else round. The maths is
  pure Lua in `Modules/Minimap/Data.lua` and unit-tested.
- One option: **Reset position** button (angle back to 225).

## 5. Logo

- `ns.ICON` in Core.lua is the one place the icon path lives. It's used by the panel title bar and the minimap
  button. The TOC `IconTexture` is set separately (the TOC can't read Lua).
- Until the user makes `Tomte/Media/Logo.png` it stays `Interface\Icons\INV_Misc_PocketWatch_01`.
- Image requirements (warcraft.wiki.gg, SetTexture): BLP, JPEG, PNG or TGA, power-of-two dimensions. PNG paths
  must include `.png`. Recommended: 256×256 PNG, transparent background, one bold shape that reads at 16 px, key
  content inside the centre circle (the minimap version is masked round).

## 6. Stable page

- Summary line across the top, then a hairline.
- Below: the scrollable list on the left (full height) and a fixed 260 px preview column on the right, split by a
  vertical line. The preview has a model about 240×240 with name, info and two detail lines under it.
- Rows under **Seen, not tamed** that have an npcID are hoverable and clickable like pet rows. The preview then
  shows the creature's model, name, its family, "Seen in <zone>" and the date (`date()`).
- Models use Blizzard's stable setup (Blizzard_StableUI): a ModelScene (`NoCameraControlModelSceneMixinTemplate`)
  transitioned to the pet's `uiModelSceneID` (saved in the snapshot; default 718, Blizzard's pet scene) and its
  `"pet"` actor with `SetModelByCreatureDisplayID`. The scene centres the model and normalises its size, so every
  model is framed the same way and turns around its middle (the actor's yaw is animated).
- Seen creatures only have an npcID: a 1×1 invisible PlayerModel does `SetCreature(npcID)` and
  `GetDisplayInfo()` (on `OnModelLoaded`, plus one re-check after 0.5 s) to get the display ID, cached for the
  session. Until then the text shows without a model.
- The default creature look is shown (the exact colour variant isn't recorded).
- Data change: `Hunter_StableSummary` adds `npcID` (when the tame log key is a number) and `family` to each seen
  creature. Old name-keyed entries get no model.

## 7. Code layout

- `Panel/Widgets.lua`: adds `UI.Scroll(parent)`, the scroll frame + content + thumb used by the sidebar, the
  options pane and the Stable list.
- `Panel/Options.lua` (new): option row factories, moved from Panel.lua. Exposes `ns.PanelOptions_Build(content,
  module)` and `ns.PanelOptions_Release()`.
- `Panel/Panel.lua`: window, sidebar, module page, Options → AddOns stub, `ns.Panel_Toggle`, `ns.Panel_Open`.
- `Modules/Minimap/Data.lua`, `Modules/Minimap/Minimap.lua` (new).
- Coverage page: unchanged (it already stretches on resize).

## Testing

- Plain Lua: `tests/test_minimap.lua` (angle ↔ offset for round and square shapes), `tests/test_hunter.lua`
  (summary carries npcID and family). All existing tests keep passing.
- In game: the checklist in the hand-over message.
