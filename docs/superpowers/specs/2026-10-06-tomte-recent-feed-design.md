# Tomte: Recent feed

Date: 2026-10-06. **Draft**, waiting on the user's answers to the open questions at the end.

## Goal

Tomte sends a lot of toasts (whispers, mentions, friends, upgrades, rares, Concentration, durability, achievements,
world quests, vendor summaries). A toast missed while tabbed out, in a fight or in a cinematic is gone for good.
**Recent** keeps the last toasts in a list you can come back to, with the same click actions.

## How entries get in

Every `ns.Toast_Show(spec)` (Social/Toast.lua) also calls `ns.Feed_Add(spec)`, so no module needs changing.
Banners (`ns.Banner_Show`: Moments, durability, hunter pet checks, pet health) are added too, without a click.

Entry: `{ at, owner, label, title, text, icon, iconAtlas, accent, onClick, count }`.

- `mergeKey` merges like the toast does (the entry's count goes up and moves to the top).
- **Secret text**: a whisper or mention shown during chat lockdown has secret text (`spec.secret`). It can't be
  stored or compared. The entry keeps the title (sender) and shows "(message hidden in combat)" instead; the
  Whispers inbox already has the real text once lockdown ends.
- Pinned toasts (`Toast_Pin`, e.g. "While you were away") are added once, when pinned.

## Storage

- In memory: the last 50 entries with their `onClick`.
- Saved (`TomteDB.feed[guid]`, last 30): text-only copies without closures. After a reload or login they show
  dimmed with no click. This also covers "what happened before my disconnect".

## Where it shows

- A **Recent** page in the Home rail, order after Alts: newest first, grouped "Today" / "Earlier", each row with
  icon, title, text, module label (in its accent color) and "5m ago". Click runs the action (only for this
  session's entries). A "Clear" button.
- A quick action in the hero column, "Recent", with the count of entries added while the Tomte window was closed
  ("unseen").
- Optional: a small unread dot on the minimap button when something was added while you were AFK or in combat.

## Options

On by default. "Keep after reload" (on), "Include banners" (on), "Dot on minimap button" (off).

## Testing

- Plain Lua: add/merge/cap, unseen count, the saved copy dropping closures and secret text.
- In game: get a whisper in combat, check the entry; reload and check the saved rows are dimmed.

## Open questions for the user

1. A page in the rail, or a section on Home itself (it would compete with Next up and Around you for room)?
2. Should Vendor summaries and durability warnings be in it, or just "things that happened to you" (whispers,
   loot, achievements, rares)?
3. Keep it per character, or one account-wide list (with the character name on each row)?
