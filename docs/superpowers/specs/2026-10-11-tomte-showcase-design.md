# Showcase (character view) design

2026-10-11. A Narcissus-style character view: the camera glides in on your character, the UI fades out, and your gear
and stats sit around it. Looks first, with Gear Check's hints on the slots. Nothing is copied from Narcissus (no
license file, so all rights reserved): only its behavior and the game APIs it calls were studied.

## Decisions (made with the user)

- Opens with its own key binding, a minimap button (off by default) and `/tomte showcase`. The C key and Blizzard's
  character sheet stay as they are.
- Right side: the essentials only. Name, title, level and spec; item level (equipped, and the best from bags);
  primary stat, stamina, health, armor; crit, haste, mastery, versatility (percent and rating); leech, avoidance,
  speed; dodge, parry and block for tanks. Hidden when 0, like Blizzard's sheet. Tabs (sets, M+) are a later step.
- Camera: the real game camera (not a model on a backdrop). It glides in, turns to the front, then turns slowly until
  you click or drag the world; after that you steer with the game's own camera controls (drag, scroll).
- Character to the left of center, gear in two columns around it, stats panel on the right.

## Behavior

- **Open:** not in combat, not while another Tomte cinematic runs. The UI fades out, the camera zooms to a full-body
  distance (from the character's model height), lowers to a low pitch, swings round to the front and starts the slow
  turn. The slots and panel fade in.
- **While open:** the world takes the mouse (drag turns the camera, scroll zooms); only the slots and the panel catch
  it. A press on the world stops the slow turn for good. Walking is allowed; it stops the turn too. The shoulder offset
  follows the zoom so the character stays at the same spot on screen.
- **Close:** Esc, the binding, `/tomte showcase` again, the panel's close button, or combat starting. Camera zoom and
  pitch go back, the automatic turn is undone (unless the player took the camera), the UI fades in.
- **/reload or crash while open:** the state and every CVar backup are saved; at the next login they're restored.
  At logout they're restored first, so the client never saves our values.

## Camera

- Built on `Cinematic/Engine.lua` with four new options: `zoom` (a target distance, in or out), `pitch` (the pitch
  limit to settle on), `interactive` (the letterbox leaves the mouse to the world; Esc still closes) and
  `bands = false` (vignette without the black bars).
- The module drives the turn itself (`MoveViewLeftStart`) so it knows how far it turned: a front swing, then the slow
  turn. Degrees turned = `cameraYawMoveSpeed` × speed × time. On close it turns back the short way.
- **Side offset:** `test_cameraOverShoulder` = zoom × `SHIFT_PER_ZOOM`, eased in and out. `CameraKeepCharacterCentered`
  and `CameraReduceUnexpectedMovement` block it, so they're set to 0 while open and restored after.
- **Experimental-feature popup:** 12.1 shows `EXPERIMENTAL_CVAR_WARNING` when a `test_` CVar changes. Blizzard's own
  event routing is left alone (no taint). The module hides that popup itself, but only while UIParent is visible
  (a popup hidden while it's invisible never runs OnHide and blocks later Esc presses); otherwise it hides it right
  after the UI is back.
- Height: a hidden ModelScene actor of the player, measured once per login and on model changes. Zoom =
  `ZOOM_BASE + ZOOM_PER_YARD × height` × the "Camera distance" setting, clamped; mounted: farther.

## Layout (Scene.lua)

- Scene frame on the letterbox, scaled to UIParent units.
- Left column (icons at the left edge, text inward): head, neck, shoulders, back, chest, wrists, then the main hand
  at the bottom row. Right column (icons at the right of the gear area, text inward): hands, waist, legs, feet, rings,
  trinkets, off hand at the bottom row. Shirt and tabard left out.
- Slot: round icon on a quality-colored ring; name in quality color; item level and upgrade track ("Hero 4/6");
  hint line: the enchant (success color) or "No enchant" (danger) on slots that take one at max level, and one dot per
  socket (filled = gem, hollow = empty, danger color).
- Hover: the item tooltip, on the module's own tooltip frame (GameTooltip lives on the hidden UIParent).
  Shift-click puts the link in chat if an edit box is open.
- Stats panel: `UI.Panel`, header (name in class color; title, level, spec), item level block, stat rows, close
  button. Refreshes on gear and stat events while open.

### Revised look ("field manual", replaces the panel above)

Agreed from a browser mockup (claude.ai artifact "Tomte Showcase mockup"), built on a 1600 x 900 design grid
scaled to the screen height:

- Slots: item icon in a diamond (quality edge and glow), name at 17, item level in a quality-tinted pill, track word
  plus pips, gem icons (empty socket: a red ring), a star plus the enchant or "No enchant". Each column hangs on a
  thin vertical rail. Leader lines toward the character were tried and dropped.
- Stats without a box, over a dark gradient: name with a class-colored rule, an item level dial (thick track, accent
  arc for equipped / best in bags, four cross ticks), 2x2 tiles (primary, stamina, health, armor), one bar split by
  secondary stat rating with a legend (colors: danger, warning, accent, success roles), chips for leech, avoidance,
  speed and a tank's dodge, parry, block when above 0.
- Textures: `tools/showcase_art.py` -> `Media/Showcase/*.tga`.
- The slot tooltip is pinned by hand (the ANCHOR_ modes misplace it from a scaled group).

## Settings

Slow turn (on), turn speed, character to the side (on), gear hints on slots (on), letterbox bars (off), camera
distance (100%). Module on by default; its minimap button off by default.

## Testing

Pure logic in `Modules/Showcase/Data.lua`, unit-tested (`tests/test_showcase.lua`): stat rows per role, number
formats, zoom from height, shoulder offset, turn-back angle, upgrade track tag, slot hint list. In game: open/close
every way, grab the camera, walk, combat, `/reload` while open, several races, mounted, druid forms.
