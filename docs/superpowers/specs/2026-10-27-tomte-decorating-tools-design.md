# Decorating tools (2026-10-27)

The user asked for "everything AdvancedDecorationTools (ADT) has": duplicate, cut, copy, paste and the rest, then
delegated the decisions ("plan it and then build it, come back when it is all done"). This spec records what was
built and the calls made along the way.

ADT has no license file, so none of its code is copied. Only facts about how the game behaves were taken from it
(API calls, measured delays, CVar names). Those facts are listed under "Game facts" with where they came from.

## Intent

Decorating a house means placing the same decor many times, moving pieces around, and turning things exactly. Blizzard's
editor makes you go back to the storage list every time. The tools put the decor you're using one key away, and add
the precision keys the editor lacks.

## What exists already (Decor module, `Modules/Decor/Editor.lua`)

- The hover info (storage count, budget cost).
- Alt places another of the hovered decor.
- Right-click copies dyes, and Paste dyes puts them on another decor.
- A clock above the editor.

All of these stay where they are. Alt's "place another" now goes through the shared placing code (`Place.lua`).

## Shape

- **The new module** is `decorate`, "Decorating tools", category `collections`, icon 134520 (`inv_misc_wrench_01`).
  It lives in `Modules/Decor/` beside the Decor module. **It is off by default**: while the house editor is open it
  takes over keys like Q, E, L and F1-F8 (our call: that's invasive for a friend who didn't choose it).
- **Everything works only while the house editor is open.** Override bindings are set when the editor opens and
  cleared when it closes, on leaving the world and when the module stops. Nothing is changed in combat; changes
  queued in combat are made when it ends.
- **The pure rules** live in `ToolsData.lua`: clipboard, recent list, quickbar, locks, tags, share strings, rotation
  steps, key text and the placed-list search. They are tested in `tests/test_decor_tools.lua`.

### Files (TOC order inside `Modules/Decor/`)

| File | Role |
| --- | --- |
| `ToolsData.lua` | Pure rules (above). |
| `Place.lua` | Shared service. Reads the hovered and selected decor in any mode, starts placing a decor by ID (switches to Basic mode first when needed, picks the stored variant, checks indoor/outdoor and the budget), removes the selected decor, and rotates. Used by Editor.lua's Alt and by the tools. Comes before Editor.lua. |
| `Clipboard.lua` | The clipboard, recent placements, holding Ctrl to keep placing, and the turn applied to each next piece. |
| `Quickbar.lua` | The 8 quickbar slots and the recent slot, as a bar beside the editor's mode bar. |
| `Dock.lua` | The tools panel in the editor: Clipboard, Recent and Saved tabs, plus Export and Import. |
| `Expert.lua` | Expert mode: reset keys, axis keys, rotate buttons, gizmo size. |
| `Lock.lua` | Locking decor against being picked up. |
| `PlacedSearch.lua` | A search box on Blizzard's placed-decor list. |
| `CatalogMenu.lua` | Entries in the right-click menu of Blizzard's storage catalog: Favorite, Tags, Destroy a number. |
| `Keys.lua` | The editor keys. |
| `Decorate.lua` | Main file: registers the module and owns the events bus (`ns.Decorate_Events`). Last in the folder. |

## Features

### Keys

Each key can be changed in settings with a new option row type, `key`. Click the row and press a key combination to
set it, press Esc to cancel, right-click to clear (an empty key means the action has no key). The row stores a binding
string like `CTRL-C`.

Default keys follow ADT's, so ADT users find them where they expect:

| Action | Default |
| --- | --- |
| Place another (duplicate) | Ctrl+D |
| Copy | Ctrl+C |
| Cut | Ctrl+X |
| Paste | Ctrl+V |
| Rotate 90° left / right (Basic mode) | Q / E |
| Reset this transform / all transforms (Expert mode) | T / Ctrl+T |
| Rotate around X / Y / Z (Expert mode) | none |
| Lock / unlock | L |
| Quickbar slots 1-8 | F1-F8 |

### Clipboard (our call: one list instead of ADT's two)

ADT keeps two things: a one-item clipboard (Ctrl+C/V/X) and a separate saved "Store/Recall" list (Ctrl+S/R). We use
one saved list, newest first, at most 20 decor.

- **Copy:** puts the hovered decor (else the selected one) at the top of the list.
- **Cut:** returns the selected decor to storage, puts it at the top and adds 1 to its "cut" count. The game only
  lets addons remove the *selected* decor. With only a hover, Cut copies and says "click it, then cut".
- **Paste:** starts placing the top decor. Placing one from the clipboard lowers its cut count (never below 0).
- **The list in the panel:** left-click places that decor; right-click opens a menu (put on a quickbar slot,
  remove). There is also a Clear button.

### Recent

The last 10 decor placed, newest first, no repeats. Placements are counted on `HOUSING_DECOR_PLACE_SUCCESS`, with the
decor ID read from the new decor's GUID.

### Keep placing and turning each piece

- **Hold Ctrl while placing:** you pick up another of the same decor right away. This is a setting, off by default.
- **"Turn each next piece by":** a slider, 0 to 180° in 15° steps, default 0. It counts the pieces placed in one Ctrl
  run and turns each new piece by count × angle.

### Rotating in Basic mode

Q and E turn the held or selected decor 90°. ADT measured that each `C_HousingBasicMode.RotateDecor(±1)` call turns
one 15° step and that calls in the same frame are dropped. So we send 6 calls, one per frame.

### Quickbar

- **The bar:** 8 slots plus a "last placed" slot, in a bar left of the editor's mode bar. Each slot shows the decor
  icon, its key and the count in storage.
- **Clicking a slot:** left-click places that decor; right-click clears the slot.
- **Pressing a slot's key:** places that decor. If a slot is empty and you're holding or have selected a decor, the
  key puts that decor on the slot.
- **Filling slots from the panel:** the clipboard, recent and saved lists all have "Put on quickbar slot N" in their
  right-click menus.

### Expert mode

- **T and Ctrl+T:** reset the current transform (`ResetPrecisionChanges(true)`) or all of them (`(false)`).
- **Axis keys:** pick X, Y or Z for rotating.
- **Rotate buttons:** shown in the rotate submode while a decor is selected. Each turns the decor by a set amount
  (setting: 5/15/45/90°, default 45).
- **Gizmo size:** two sliders, for the move arrows and the rotate rings. They set CVars, which are put back to the
  game's defaults when the module stops or the slider returns to 100%.

### Lock

- **Toggling:** L locks or unlocks the hovered decor, keyed by decor GUID.
- **What a lock does:** selecting a locked decor in Basic or Expert mode cancels the selection, with the message
  "Locked: press L over it to unlock".
- **On hover:** the tooltip says "Locked".

### Placed decor search

A search box at the top of Blizzard's placed-decor list (Expert mode). Rows whose name doesn't match are dimmed. We only
change the rows' alpha and never replace Blizzard's data, so its list keeps working.

### Export and import

- **The share string:** `TomteDecor1:` followed by a comma-separated list of `decorID` or `decorIDxcount`, for
  example `TomteDecor1:1234x2,5678`. We don't compress it (our call): no library, and the strings stay short and
  readable.
- **Export:** from the clipboard, or from the placed-decor list while it's open (counted per decor).
- **Import:** reads a string into the clipboard, either added to it or replacing it (a Yes/No question).

### Storage catalog right-click menu

Added through `Menu.ModifyMenu("MENU_HOUSING_CATALOG_ENTRY")`, the way Tomte already extends Blizzard's menus:

- **Favorite:** a checkbox.
- **Tags:** a submenu of checkboxes for your tags, plus "New tag…".
- **Destroy a number…:** shown only when there's more than one in storage. It asks how many, confirms, then destroys
  one per 0.5 s. It stops at the first failure or when the module stops.

Favorites and tags show in the panel's **Saved** tab, one group per tag. We don't filter Blizzard's catalog the way ADT
does: that replaces Blizzard's menu generator and taints the catalog.

### Dye presets (in the Decor module, beside Paste dyes)

A Presets button next to Paste dyes opens a menu:

- Save the copied dyes as a preset.
- Each saved preset (pick it to copy and paste it).
- Delete a preset.

At most 10 presets, saved in the Decor module's db as `dyePresets`.

### Key hints

A line in the hover tooltip with the main keys (for example "Ctrl+D another · Ctrl+C copy · L lock"). This is a
setting, on by default.

## Left out on purpose (our calls)

- **Moving Blizzard's mode bar, the "interface style" switch, and the hover panel that replaces Blizzard's
  instructions:** layout changes that move Blizzard frames and taint them.
- **Hiding the whole editor UI (ADT's Alt+Z eye):** it uses `SetUIVisibility` and parents to WorldFrame. Blizzard's
  own Alt+Z behavior stays.
- **Showing the storage panel in Expert mode:** it calls Blizzard methods on Blizzard's frame from addon code. Our
  panel places from Expert mode anyway, by switching to Basic.
- **ADT's visit assistant:** it adds you as a friend to read a GUID. The Decor module's View Houses cards cover visiting.
- **ADT's "learn"/"sequence" auto-rotate modes:** not built in ADT itself; only "turn each next piece" exists there.

## Game facts used (from ADT's comments and code, and Blizzard's UI source)

- **`StartPlacingNewDecor`** takes an entryVariantID table. It works only in Basic mode. After
  `C_HouseEditor.ActivateHouseEditorMode(BasicDecor)`, wait 0.2 s. Cancel any active editing first.
- **A click that starts placing** must defer the start (0.05-0.1 s). Otherwise the same click drops the decor at the
  mouse.
- **`RemoveSelectedDecor`** exists in the Basic, Expert, Cleanup and Decor namespaces and returns nothing.
- **Selecting a locked decor:** after cancelling the selection, Blizzard's editor sometimes ignores clicks until the
  mode is switched away and back on the next frame.
- **Expert rotation:** `SetPrecisionIncrementingActive(RotateLeft/Right, true)` turns about 5° per 0.1 s.
  - **Picking an axis:** switch the submode to Translate and back to Rotate (the axis resets to X), then call
    `SelectNextRotationAxis` 0, 1 or 2 times.
- **Gizmo CVars:** `housingExpertGizmos_Translation_BaseArrowHeadScale`, `_BaseArrowStemScale`, `_BaseCubeScale`,
  `housingExpertGizmos_Rotation_BaseRingScale`, `_BaseOrbScale`. They take effect after switching the submode away
  and back.
- **`C_HousingDecor.GetAllPlacedDecor`, `SetPlacedDecorEntrySelected` and `...Hovered`** are restricted. The placed
  list can only be read from Blizzard's list's data provider while it's shown.
- **`C_HousingCatalog.DestroyEntry(entryVariantID, false)`** destroys one item. It isn't hardware-protected: ADT
  calls it from timers, 0.5 s apart.
- **`HOUSE_EDITOR_MODE_CHANGED`** can be missed on cross-zone loads, so the editor state is read again on the next
  frame.
