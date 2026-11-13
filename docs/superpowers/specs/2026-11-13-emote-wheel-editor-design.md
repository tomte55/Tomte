# Emote wheel editor (2026-11-13)

## Why

Setting up the wheel meant two text boxes per slice in a long settings list (16 to 24 rows), retyping slots to
change the order, and knowing every emote command by heart. The user found it tedious and not visually clear.

## Approaches

- **A. A page of its own with the wheel as the editor (picked).** Full-size wheel left, the clicked slice's editor
  right. Visual and quick; the most work.
- B. The same editor inside a settings card: needs a new shared row type, cramped by the card width, fights the hover
  preview.
- C. A tidier list (one row per slice, emote dropdown, up/down arrows): cheap, still a list.

## Design (A)

- A `page` home entry, `noRail` (an editor, not something opened daily). The settings page's automatic
  "Open Emote wheel >" button reaches it. The settings keep the wheel card (key, size, opacity, checkboxes) and buff
  thanks; the "Slices" card goes.
- **Band**: how many slices and how to use the wheel; "Add slice" (disabled at 12) and "Starting slices" (confirm).
- **Wheel** (left): drawn by Wheel.lua exactly as in game, the picked slice lit. Hover tints a slice. Click picks it;
  drag a slice onto another to move it there (a ghost label follows the cursor). The grey slots of a wheel with fewer
  than four slices add a slice when clicked.
- **Editor** (right) for the picked slice: its name as a title, "Slice N, clockwise from the top", then three ways to
  fill it (segmented):
  - **Emote**: a search box and every game emote as buttons (localized, from `EMOTE<i>_TOKEN`/`_CMD<j>`); the slice's
    emote is lit, emotes on other slices are marked. Hovering one shows it on the wheel.
  - **Chat line**: Say, Yell, Party, Guild or Whisper target, and the message (`%t` is the target).
  - **Command**: any text or slash command, as before.
  - Below: a line saying what the slice does, the name box ("From the command" when empty), and Move left/right
    (counter-clockwise / clockwise) and Remove.
- Every change saves at once (`db.slots`, same shape: `s1..s12 = { name, text }`), so no migration. A slice whose text
  is still empty is kept while the page is open (it shows "Pick an emote") and drops out of the live wheel as before.

## Pure logic (Data.lua, tested)

`EmoteWheel_Store(list)` (list -> slots), `EmoteWheel_Move`, `EmoteWheel_Kind(text, lookups)` (which of the three
ways a text is), `EmoteWheel_Line(chatType, message, commands)`, `EmoteWheel_Describe(action)`,
`EmoteWheel_FilterEmotes(list, query)`.

## Calls made without the user

noRail; Move buttons besides drag; the chat-line channels (Say, Yell, Party, Guild, Whisper target); emote buttons
show the name ("Wave") with the command in the tooltip.

## Acts out and voice marks (added after the first in-game look)

Each emote button shows a figure when your character acts the emote out and a speaker when it has a voice line for
your character's race and sex (a few lines are a class's own: Demon Hunters). A legend sits right of the search box;
the tooltip and the "Does ..." sentence say it in words. The data is generated from the client's EmotesText, Emotes
and EmotesTextSound tables by `tools/emotes.py` into `Modules/EmoteWheel/Generated.lua` (rerun after a patch that
adds emotes). Picked over Blizzard's own EmoteList / TextEmoteSpeechList, which only hold the chat menu's ~30 emotes.
