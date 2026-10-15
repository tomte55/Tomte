# Material uses Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Item tooltips on crafting materials say which of your characters craft with them, which other professions
use them, or that nothing uses them, in at most two lines (details with Shift).

**Architecture:** A generated table (`tools/materials.py` -> `Modules/Materials/Generated.lua`) maps every reagent
item to `{ [profession skill line] = recipe count }`. Alts answers "which characters' known recipes use this item"
through `ns.Alts_UsedBy` (pure index in `PlanData.lua`). A new module's pure `Data.lua` turns both answers into tooltip
lines; `Materials.lua` hooks the item tooltip and refreshes it on Shift.

**Tech Stack:** WoW retail 12.1 Lua (Lua 5.1 for tests), Python 3 stdlib for the generator, wago.tools DB2 CSVs.

**Spec:** `docs/superpowers/specs/2026-10-13-tomte-material-uses-design.md`

## Global Constraints

- Every Lua file starts with `local addonName, ns = ...` and a header comment; tabs; ~120 columns; double quotes.
- Colors only by theme role (`UI.Wrap(text, "accent")`, `"textFaint"`); no `|cff` literals (tests/test_theme.lua).
- Profession names from `C_TradeSkillUI.GetTradeSkillDisplayName(skillLineID)` (verified on warcraft.wiki.gg), never
  English strings.
- The tooltip hook is installed once and does nothing while `module.active` is false.
- Never read Alts' db from the new module: only `ns.Alts_UsedBy`.
- Generated files are never edited by hand.
- Files CRLF: edit Lua with Edit/Write only.
- No commit of code before the user's in-game check (project memory "autonomous when delegated").

## Review Focus

- An item that is a reagent only through Alts (not in the generated table, e.g. a newer recipe): line 1 shows, no
  "Not used" line. Test in Task 3.
- A character knowing recipes in two professions that use the item: one entry per profession, character listed once
  in the short line. Test in Task 3 (`+n` counts characters, not entries).
- Alts disabled: `ns.Alts_UsedBy` returns `{}`; only the generated line shows. Covered by Task 4 code (module check).
- Shift detail with more than 5 recipes: `+n more`. Test in Task 3.
- Profession name lookup returns nil (skill line the client doesn't know): the profession is skipped, not "nil".
  Test in Task 3.

---

### Task 1: Generator tool and generated table

**Files:**
- Create: `tools/materials.py`
- Create (generated): `Modules/Materials/Generated.lua`

**Interfaces:**
- Produces: `ns.MATERIALS_USES = { [itemID] = { [skillLine] = count } }`, skill lines limited to
  `PROFESSIONS = (164, 165, 171, 182, 185, 186, 197, 202, 333, 393, 755, 773)`.

- [ ] Step 1: write `tools/materials.py` (stdlib, `wago.load`, tables SpellReagents, SkillLineAbility, SkillLine,
  CraftingReagentQuality, MCRSlotXMCRCategory, ModifiedCraftingSpellSlot). Recipe spell -> top skill line via
  `ParentSkillLineID`; old reagents from `Reagent_0..7`; quality-ranked through category -> slot -> spell. Count unique
  spells per (item, profession). Output sorted by item ID, one item per line.
- [ ] Step 2: run `python -I tools/materials.py 12.1.0.69933 <scratch csv dir>`; check Mycobloom 210796 =
  `{[171]=22,[165]=1,[182]=3}`, Copper Bar 2840 has 164/202/755/165/186.
- [ ] Step 3: `luac -p Modules/Materials/Generated.lua`.

### Task 2: Alts reagent index and `ns.Alts_UsedBy`

**Files:**
- Modify: `Modules/Alts/PlanData.lua` (add `ns.Alts_ReagentIndex`, `ns.Alts_UsedByChars`)
- Modify: `Modules/Alts/Alts.lua` (cache `reagentIndex`, cleared in `ns.Alts_RecipesChanged`; `ns.Alts_UsedBy`)
- Test: `tests/test_alts.lua`

**Interfaces:**
- `ns.Alts_ReagentIndex(recipes) -> { [itemID] = { recipeID, ... } }` (sorted, each recipe once per item).
- `ns.Alts_UsedByChars(chars, recipes, ids) -> { { name, class, base, profName, recipes = { { id, name } } } }`,
  sorted by recipe count desc, then name, then profName; recipes sorted by name.
- `ns.Alts_UsedBy(itemID) -> same list` (`{}` when Alts is off or nothing uses it).

- [ ] Step 1: tests in `tests/test_alts.lua` using the file's RECIPES/CHARS: index maps 4001, 4002, 4003 -> {2};
  6001 -> {3}; `Alts_UsedByChars(CHARS, RECIPES, index[4002])` -> one entry, Aldric, Blacksmithing,
  recipes {Charged Alloy}; index[6001] -> Alchy only (Bob knows nothing); unknown recipe ids -> `{}`.
- [ ] Step 2: run `lua Tomte/tests/test_alts.lua`: fails (nil function).
- [ ] Step 3: implement in PlanData.lua.
- [ ] Step 4: run: passes.
- [ ] Step 5: Alts.lua: `local reagentIndex`, nil in `ns.Alts_RecipesChanged`, and
  ```lua
  function ns.Alts_UsedBy(itemID)
  	if not (module.active and itemID) then return {} end
  	reagentIndex = reagentIndex or ns.Alts_ReagentIndex(db.recipes)
  	local ids = reagentIndex[itemID]
  	return ids and ns.Alts_UsedByChars(db.chars, db.recipes, ids) or {}
  end
  ```

### Task 3: Pure tooltip lines (`Modules/Materials/Data.lua`)

**Files:**
- Create: `Modules/Materials/Data.lua`
- Test: `tests/test_materials.lua`

**Interfaces:**
- `ns.Materials_Lines(input) -> { { text, role }, ... }` with
  `input = { usedBy (Alts_UsedBy list), uses (generated entry or nil), isMaterial (bool), notUsed (setting),
  shift (bool), profName = function(skillLine) -> name or nil }`.
- Roles: `"accent"` for line 1 label+text, `"textFaint"` for "Also" and "Not used in crafting". Shift lines:
  `"textMuted"`.
- Wording:
  - short, one character: `Used by Aldric: Alchemy (3)`; same character in two professions:
    `Used by Aldric: Alchemy (3), Leatherworking (1)`.
  - short, several characters: `Used by Aldric, Mira +1` (characters ordered by their total recipes, then name).
  - shift: one line per recipe `Sturdy Ingot - Aldric`, max 5, then `+n more`.
  - `Also: Inscription, Leatherworking` (shift: `Also: Inscription (4), Leatherworking (1)`), alphabetical by
    name, minus professions on line 1, unknown names skipped.
  - `Not used in crafting` when no usedBy, no uses, isMaterial and notUsed.

- [ ] Step 1: write tests covering: one char one prof; one char two profs; three chars (+1); Also subtraction;
  Also with nil name skipped; Also shift counts; Not used only with isMaterial and setting; nothing when
  not material and no uses; usedBy without generated entry gives no "Not used"; shift cap 5 + "+n more".
- [ ] Step 2: run, fails. Step 3: implement. Step 4: run, passes.

### Task 4: Module main file, TOC, docs

**Files:**
- Create: `Modules/Materials/Materials.lua`
- Modify: `Tomte.toc` (after `Modules/Alts/Alts.lua`: Generated.lua, Data.lua, Materials.lua), `Core/BugFiles.lua`
  via `lua Tomte/tools/bugfiles.lua`, `README.md`, `CHANGELOG.md` (only after the in-game check)

- [ ] Step 1: `Materials.lua`: `ns.RegisterModule{ key = "materials", name = "Material uses", category = "General",
  enabledByDefault = true, defaults = { tooltip = true, notUsed = true }, uses = Alts note, options (2 checkboxes),
  commands = { why } }`; `init` adds `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)`;
  `OnItem` guards active/setting/secret, reads class via `C_Item.GetItemInfoInstant`, calls `ns.Materials_Lines`,
  adds lines with `UI.Wrap`. `toggle` registers/unregisters `MODIFIER_STATE_CHANGED`; the handler calls
  `GameTooltip:RefreshDataNextUpdate()` when the shown GameTooltip got our lines.
- [ ] Step 2: TOC lines, `lua Tomte/tools/bugfiles.lua`, all tests, `luac -l` global check on the new files.
- [ ] Step 3: README row, command and layout entry.
- [ ] Step 4: hand to the user for the in-game check (what to hover, what to look for).
