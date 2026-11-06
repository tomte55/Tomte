# Forever: Eat and drink, Groups in chat

Two World of Warcraft: Forever only modules, chosen by the user from a list of Forever ideas.

## Eat and drink (`Modules/Rest/`, key `rest`)

Downtime after fights is most of a Classic-style session. One key or button uses the best food and drink in the bags when
health or mana is low.

- **Which items:** an item's spell tells what it is: `C_Item.GetItemSpell` compared with the localized names of Food (433),
  Drink (430) and First Aid (746), so it works in any client language and needs no item list. Buff food (its tooltip
  names Well Fed, 19705) is only used when nothing else is left, as the player is probably saving it.
- **Which one:** the highest required level the character can use. Nothing to compare conjured food with: it just counts
  by its level.
- **What a press does:** a macro with one `/use` per need, food and drink together. Already eating or drinking: that part
  is skipped. A bandage only with no food, and not while Recently Bandaged (11196).
- **Warnings:** the button says "No food" or "No drink" when you're low with nothing to use, and one toast when you drop
  to the low count (default 5).
- **Limits:** out of combat only, as secure attributes can't change in combat. Not while mounted.
- **Health is hidden:** `UnitHealth` always returns a secret value to addons on Forever, in combat or not (its API
  documentation says `SecretReturns`; measured on 1.60.1). Nothing can decide by it, so the button can't appear only when
  you're low, and a press can't check. The button stays up, faint, and two extra layers are lit by the game through
  `UnitHealthPercent` and `UnitPowerPercent` with a curve. A press always eats, as pressing means you want to recover. Mana
  decides in Lua when it can be read.

Unconfirmed until seen in game: that one press can start both food and drink.

## Groups in chat (`Modules/ChatGroups/`, key `chatgroups`)

Forever has a Looking For Group listing board of its own (Blizzard_GroupFinder_VanillaStyle: browse and list yourself,
no automatic matching), so this doesn't replace it. It catches what's only posted in chat channels.

- **Reading:** `CHAT_MSG_CHANNEL` while the module is on, nothing saved between sessions. A message counts when it says
  someone is looking (lfm, lf2m, need, lfg, or lf plus a role) and names a dungeon. With no dungeon named, such as a quest
  group, only the plain lfm, lf2m and lfg words count, as "need" and "lf" alone catch too much ("need a drink", "lf
  enchanter"). Sales and boosts are left out.
- **Page:** dungeon, roles wanted, who and how long ago; the whole message in the tooltip. Filters: groups or players, and
  dungeons near your level. Click whispers. Right-click invites a player who's looking for a group.
- **Toast:** optional and off by default, for groups near your level.
- **Words:** players write abbreviations in English whatever their client's language, so the aliases
  (`Data/Forever/Dungeons.lua`) are English. Other languages' messages simply aren't picked up.
- **Levels:** Classic's ranges from memory, only used for the "near my level" filter. Not confirmed for Forever.

Only channels the player has joined can be read.
