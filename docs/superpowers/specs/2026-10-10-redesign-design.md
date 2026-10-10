# Tomte: Redesign ("Cartographer" theme)

Date: 2026-10-10. The look was chosen by the user step by step in the visual companion (mockups compared side by side);
the build details below follow the four sections the user approved in chat. The user then delegated spec, plan, build
and review ("come back to me when it is all done").

## Why

Tomte's dark flat panels, sharp edges and gold hairlines look almost identical to another addon the user saw. The goal
is a look that is unique, good looking, easy on the eyes in a dark room, and still feels like World of Warcraft.

## The look

Night-time map drawn by an explorer:

| Part | Decision |
|---|---|
| Background | Warm charcoal (`#1d2026` top to `#15171b` bottom), a soft lighter patch top-left, faint terrain contour rings in one corner (big windows only), a fine grain over everything, a dark inner vignette |
| Frame | 2 px near-black outer edge, a 1 px brown rule (`#8a7b5a`, ~47% alpha) inset 5 px. Sharp corners. No gold |
| Titles | Cinzel, centered where there's room, cream (`#eadbb5`), with a small diamond ink flourish under main titles |
| Body text | Alegreya, cream (`#e6dcc4`); secondary text muted grey-brown (`#9c9480`) |
| Accent | Muted arcane lavender `#a99be0`, deep end `#5d4f9a`: progress bars (gradient deep to light), links, selected row (2 px left bar + faint wash), button rules on hover, checkbox fill, slider thumb, scroll thumb |
| Rows | Thin dotted or faint brown separators (`#a8956a` ~15%) |
| Buttons | Ruled top and bottom lines in the frame color, small caps text; accent rules on hover |

Rejected along the way (kept for the record): Frost & Slate (too common), Field Journal light (too bright), Arcane
Night (too modern), Nordic (too silly), Carved Slate (too modern), the compass rose watermark (busy), a grid
background (blueprint, not Azeroth), teal / wax red / verdigris accents, Cormorant and Spectral+Source Sans fonts.

## Scope

Every surface Tomte draws: the main window (title bar, rail, Home, every content page, Settings), on-screen widgets
(Almost Done tracker and dock, Crafting list, Weekly popup and ring, social toasts and inbox, Rogue poison buttons,
unit and pet bars, flight bar, Next up, Recent, Gear reveal), cinematic overlays (banner, Moments, AFK, Recap, flight
showcase), world map tabs and Tomte's lines in tooltips. **Look only**: layouts and behavior don't change.

Not themed (they carry game meaning): item quality colors, class colors, faction/reputation colors, chat-type colors
(whisper, guild, GM: read from `ChatTypeInfo`, not hardcoded), Blizzard frames and tooltips themselves, the Blizzard
navigation arrow on the map marker, money icons.

## Theme layer (`Core/Theme.lua`)

Loaded right after `Core/Core.lua`, before everything that draws. Exposes `ns.Theme`:

```lua
ns.Theme = {
	name = "cartographer",
	colors = { [role] = { r, g, b [, a] } },
	fonts = { title = path, body = path, number = path },
	media = { grain = path, contours = path, flourish = path },
}
```

Color roles:

| Role | Value | Use |
|---|---|---|
| `bg` | `#191a1e`, alpha from the window opacity setting | panel fill (with `bgTop`/`bgBottom` gradient) |
| `bgTop`, `bgBottom` | `#1d2026`, `#15171b` | the fill's vertical gradient |
| `surface` | black, 19% | inset boxes (vault slots, cards, input fields) |
| `hover` | accent, 14% | row hover/selected wash |
| `text` | `#e6dcc4` | normal text |
| `heading` | `#eadbb5` | titles, section headings, button labels |
| `textMuted` | `#9c9480` | secondary text, counts, meta |
| `textFaint` | `#6b6658` | disabled, placeholders, empty states |
| `accent` | `#a99be0` | links, selection, progress fill, active controls |
| `accentDeep` | `#5d4f9a` | gradient start of progress fills |
| `frame` | `#8a7b5a` | panel inner rule, dividers, button rules, control borders |
| `frameDark` | `#0a0b0d` | panel outer edge |
| `rule` | `#a8956a`, 15% | row separators |
| `success` | `#8fbf7a` | done, ready, upgrade |
| `warning` | `#d9a55b` | soon, low, partial |
| `danger` | `#d0654f` | missing, failed, broken, errors |

Today's per-module REDs, GREENs and ORANGEs collapse into `danger`, `success` and `warning`. Today's `MAP_BLUE`,
`VALUE_BLUE` and other "this is clickable/map" blues become `accent`. Gold maps by meaning: gold heading text →
`heading`, gold borders/lines → `frame`, gold fills/thumbs/active states → `accent`.

Font roles and the client-language fallback (decided once at load with `GetLocale()`):

| Client | `title` | `body` | `number` |
|---|---|---|---|
| enUS, enGB, deDE, frFR, esES, esMX, itIT, ptBR | Cinzel | Alegreya | Alegreya Numbers |
| ruRU | the client's own (`GameFontNormalHuge:GetFont()`) | Alegreya | Alegreya Numbers |
| koKR, zhCN, zhTW | client's own | client's own (`STANDARD_TEXT_FONT`) | client's own |

Text other players wrote (whisper and mail text, guild notes, chat lines) uses `ChatFontNormal:GetFont()` in every
locale, so it renders exactly as it does in chat.

Switching themes: a theme is a plain table. There is one theme now; there is no picker. When a second theme exists, a
Settings dropdown saves the choice and shows a "Reload now" button (`C_UI.Reload()`, needs the click as its hardware
event; disabled in combat). No live repaint.

## `ns.UI` (Panel/Widgets.lua, reworked)

- `UI.Color(role)` → `r, g, b, a`. `UI.Text(parent, size, role, fontRole)`: `role` is a role name (old callers passing
  a color table keep working during migration only; the end state passes roles). `fontRole` defaults to `body`.
- `UI.Panel(frame, opts)`: background fill + gradient, grain tile, optional contour corner, vignette, frame rules.
  `opts.size` = `"large"` (everything), `"medium"` (no contours), `"small"` (fill, grain, outer edge only); default
  picked from the frame's size at the first `OnSizeChanged` (large ≥ 600×400, small < 60 px high). `opts.corner` picks
  the contour corner (default `"BOTTOMRIGHT"`). `opts.alpha` overrides the fill alpha. Returns a handle with
  `:SetAlpha(a)` for the window opacity setting.
- `UI.Title(parent, text, size)`: Cinzel title, flourish under it.
- `UI.Border`, `UI.SetBorderColor` keep their pixel-exact behavior; colors from roles.
- `UI.Hairline`, `UI.VLine`: same shape, `frame` color.
- `UI.Bar(parent)`: a progress bar (sunken track + accent gradient fill) with `:SetValue(0..1)` and
  `:SetColorRole(role)`.
- `UI.Checkbox`, `UI.Button`, `UI.Slider`, `UI.Dropdown`, `UI.ScrollThumb`, `UI.Scroll`, `UI.CollapseButton`
  restyled in place; their APIs don't change.
- The old `UI.GOLD`, `UI.WHITE`, `UI.GREY`, `UI.DIM`, `UI.BG`, `UI.BOX` are removed at the end of the migration.

## Art (`tools/theme_art.py` → `Media/Theme/`, `Media/Fonts/`)

Generated, so it's reproducible (Python + Pillow + fontTools; `tools/` is already export-ignored):

| File | Size | Content | Drawn as |
|---|---|---|---|
| `Media/Theme/Grain.tga` | 128×128 | seamless fine noise, light and dark specks on transparent | tiled (`"REPEAT"`, horiz + vert tile), low alpha |
| `Media/Theme/Contours.tga` | 512×512 | slightly wobbly concentric rings from one corner, cream on transparent, fading | one corner, ~4% alpha, mirrored by texcoords for other corners |
| `Media/Theme/Flourish.tga` | 256×16 | diamond ink rule, white on transparent | under titles, tinted with `frame`/`accent` |
| `Media/Fonts/Cinzel-Medium.ttf` | | static weight 500 instance of Cinzel | |
| `Media/Fonts/Alegreya-Regular.ttf` | | static weight 400 instance of Alegreya | |
| `Media/Fonts/AlegreyaNumbers-Regular.ttf` | | weight 400, digits remapped to tabular lining figures (`*.tf`), renamed family | |
| `Media/Fonts/OFL-Cinzel.txt`, `OFL-Alegreya.txt` | | licenses | |

Measured 2026-10-10 on Google Fonts' current files: Cinzel has all Latin-1 accents, 103/128 Latin Extended-A, no
Cyrillic. Alegreya has all Latin-1, 127/128 Latin Extended-A, all basic Cyrillic. Neither declares a Reserved Font
Name, so modified copies are allowed under OFL 1.1. Alegreya's default digits are proportional old-style (WoW can't
turn on OpenType `lnum`/`tnum`), hence the Numbers build. README Credits names both projects.

## Migration order (branch `redesign`, merged to `main` when complete)

1. Foundation: art + fonts, `Core/Theme.lua`, reworked `ns.UI`, the main window chrome (title bar, rail, Settings,
   options widgets).
2. Home and every content page.
3. On-screen widgets.
4. Cinematic overlays.
5. Map tabs, tooltip lines, removing the old `UI.GOLD`-style constants, the source-scan test.

Each step: the user `/reload`s and checks in game; commit + a CHANGELOG line after confirmation. Released as v1.3.0
(look change, no settings reset).

## Tests (Lua 5.1, `tests/test_theme.lua`)

- Every color role exists and is a valid 3- or 4-number table in 0..1.
- The font fallback picks the right path for enUS, ruRU, koKR, zhCN.
- Source scan: outside `Core/Theme.lua` (and a short allow-list for pure black/white shading and Blizzard API
  colors), no `SetColorTexture`/`SetTextColor`/`SetVertexColor`/`CreateColor` with numeric RGB literals, no
  `Fonts\\` paths and no `STANDARD_TEXT_FONT` in drawing code.

## In-game check per step

Open the surfaces the step touched; look for leftover gold, wrong fonts, missing grain, borders that vanish at the
UI scale, and BugSack errors. `/fstack` over anything off says which frame drew it.
