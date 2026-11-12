# Emote Wheel (2026-11-12)

A radial emote menu, after screenshots of another addon the user liked (idea only; no code or art taken).

## What the player gets

- **Wheel**: hold a key or mouse button (settings, `key` row; middle, 4 and 5 now count as keys). A wheel opens at
  the cursor; the slice under the cursor lights up (gold wedge, accent name) and the middle shows its name, command
  and `> target`. Letting go runs the slice; letting go in the middle cancels (setting: or keeps the last slice).
- **Slices**: 4 to 12, clockwise from the top, each a command or text plus an optional name (else made from the
  command). An emote (`/bow`, `/ty`) goes to the current target; `%t` is the target's name; chat commands
  (`/s /y /e /p /ra /rw /i /g /o /w name`) are sent; text without a slash is said; other insecure slash commands
  run through `SlashCmdList`; secure ones (`/cast`, `/use` ...) are refused with a reason.
- **Look**: size, opacity, command under the name, target in the middle. Colors from the theme (no own themes).
  Live preview on hover of the slice rows.
- **Buff thanks**: another player's buff of 10 minutes or more, out of combat (instances optional), shows a toast;
  click thanks them (say, whisper or `/thank`), right-click dismisses. Same player and buff again only after 30 min.
- **Toasts** (all modules): a countdown line along the bottom; it stands still while hovered.

## How

- `Data.lua` (pure, `tests/test_emotewheel.lua`): parse, `%t`, slice geometry, buff rules.
- `Wheel.lua`: discs (portrait mask), Showcase art, `Line` objects for spokes and the lit wedge (a fan of thick
  lines, since a texture can't be cut to a wedge).
- `Thanks.lua`: `UNIT_AURA` added auras on the player, secret-checked.
- `EmoteWheel.lua`: override binding click on a named hidden button, `AnyDown`/`AnyUp`; the release runs the slice
  (a hardware event, which `/say` needs outside instances). Override bindings wait for combat to end.
- Emote tokens and chat-type slashes come from Blizzard's localized globals (`EMOTE%d_TOKEN`/`_CMD%d`,
  `SLASH_<TYPE>%d`), as `ChatFrameUtil.ImportEmoteTokensToHash` reads them. Emotes go through
  `C_ChatInfo.PerformEmote` (12.0; `ns.Chat_Emote` falls back to `DoEmote`).

## Unmeasured (test in game)

- Key release through a CLICK override binding counts as a hardware event for `/say` outside instances.
- The fan of lines looks like a clean wedge at 4 and at 12 slices.
