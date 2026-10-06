# Tomte: Send to alt

Date: 2026-10-06. Agreed with the user: choices are settings with defaults rather than fixed decisions. Mail waits on an in-game prototype (below); the Warband bank part doesn't. Builds on Alts
(`2026-10-05-tomte-alts-design.md`).

## Goal

The main gathers, the alts craft. At a mailbox or the bank, show what this character carries that another
character uses, and move it there with one click per mail (or one click to the Warband bank).

## What counts as "used by"

From Alts' data (`TomteDB.alts`):

- An item is a reagent of a recipe that another character **knows** (`recipes[id].reagents`, quality ranks
  included) and this character doesn't know a recipe using it. The recipient is the character with the most known
  recipes using it; ties go to the last played.
- The Crafting tab's current plan: materials assigned to a crafter in the plan's steps go to that crafter, ahead of
  the rule above.
- Optional manual rules: "always send <item or item class> to <character>".

Not suggested: soulbound items, items the current character needs for its own known recipes, quest items, and
anything in a Baganator/Syndicator "keep" category if there's a way to read it (to check).

## At the mailbox (`MAIL_SHOW`)

A panel docked to the right of the mail frame (like the Achievements dock), "For your alts":

- Grouped by recipient: name in class color, items with counts and (with Gold & value) value.
- **Send to <name>** button per group: fills the recipient and a subject ("Tomte: herbs"), attaches up to 12 stacks
  (`ATTACHMENTS_MAX_SEND`) on the Send Mail tab, and sends with `SendMail`. More than 12 stacks means another
  click. One click per mail, nothing automatic, out of combat only.
- Postage is shown (`GetSendMailPrice`) and checked against `GetMoney()`.
- Results: `MAIL_SEND_SUCCESS` / `MAIL_FAILED` → a vendor-style summary toast.

API status (Blizzard UI source 12.1.0): `SendMail`, `ClickSendMailItemButton`, `GetSendMailPrice` are legacy globals
with no restriction info in the generated docs; `C_Container.PickupContainerItem` / `UseContainerItem` are not
restricted. Whether `SendMail` needs a hardware event when called from our button's OnClick (it will be in one)
**must be tested in game first**, with a tiny prototype, before building the panel. If Blizzard's "send to stranger"
confirmation (`SECURE_TRANSFER_CONFIRM_SEND_MAIL`) appears, it's Blizzard's dialog and stays.

## At the bank: Warband bank

Warbound reagents don't need mail: with the Warband bank tab open, **Deposit for alts** puts the suggested warbound
items in it. Blizzard's own bank frame does exactly this with
`C_Container.UseContainerItem(bag, slot, nil, Enum.BankType.Account, false)`; one click, a few items per frame to
stay under the item lock. Blizzard asks a "no refund" confirmation for refundable items; those are skipped.

## Home

The Alts page gets a small "For your alts" line ("38 stacks for Mira, Tolvan") and Next up can suggest "Mail herbs
to Mira" when you're standing at a mailbox (score 60).

## Options (Alts module, "Send to alt" header)

| Setting | Choices | Default |
|---|---|---|
| At the mailbox | on/off | on |
| At the Warband bank | on/off | on |
| Use the current craft plan | on/off | on |
| Manual rules | list of item or item class → character (an input and a dropdown per row) | empty |
| Keep gold on alts | off / an amount; the mail panel offers "Top up <name> to Xg" | off |
| Subject | text input | "Tomte" |

## Testing

- Plain Lua: the recipient rule (ties, plan override, own recipes excluded), grouping into 12-stack mails.
- In game: **prototype first** (one button that sends one stack to an alt), then the full panel; Warband deposit
  with a mix of warbound and soulbound items.

## As built (2026-10-06)

Built in one go with the other four; not yet tested in game.

- Mail is two clicks per mail: **Attach** (opens the Send Mail tab if needed, fills recipient and subject, attaches up
  to 12 stacks with `PickupContainerItem` + `ClickSendMailItemButton`) then **Send** (`SendMail`), so the client has
  attached the items before sending. Still needs the in-game check that `SendMail` from our button works.
- Mail only offers unbound stacks; the Warband button offers what `C_Bank.IsItemAllowedInBankType(Account, ...)`
  allows, deposited in the click with `UseContainerItem(bag, slot, nil, Enum.BankType.Account, false)`.
- Manual rules are one text setting ("210796 = Mira, mycobloom = Tolvan"). Gold top-up is a slider in thousands.
- Next up gets a "Materials for your alts" source (score 40).
