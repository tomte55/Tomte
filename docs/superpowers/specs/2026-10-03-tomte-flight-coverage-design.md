# Tomte: flight-master coverage overview

Agreed in conversation: coverage by flight master, a Coverage tab next to Flight's options in the panel,
continents > zones > flight masters, and a coverage strip with pin markers on the flight master map. After
part 1 of the design the user handed the remaining decisions to Claude ("implement it all, come back when
done"); those decisions are recorded here.

## Goal

Show how complete the recorded flight data is, so the user (and later friends) can work towards timing every
flight master.

**Success means:**

- The panel's Flight Timer entry has an Options tab and a Coverage tab.
- Coverage lists every continent and zone that has flight masters for the player's faction (plus neutral),
  with timed / total counts and timed legs, and per zone the flight masters and their state.
- The flight master map shows coverage for the map on screen and for the zone the player is in, and marks
  each flight master that has no recorded time yet.
- A flight that just landed counts the next time the page or map is shown.

**Out of scope:** sharing data with friends (its own round later), the legacy `TaxiFrame` (no markers, no
strip), opposite-faction flight masters, saving the expanded/collapsed state.

## Rules (Coverage.lua, pure)

- A flight master is **timed** when its node ID is in any stored hop (`a>b`) or route (`a>b>c`).
- Otherwise it is **known** (discovered by this character) or **undiscovered**.
- **Legs** are distinct stored hops, A>B and B>A counted once. A zone's legs are the legs with at least one
  end in that zone; a continent's are the legs with at least one end in one of its zones.
- Counts are derived from `routes` and `hops`. Nothing new is saved.

## Atlas (Atlas.lua, WoW API)

- Zones: `C_Map.GetMapChildrenInfo(946, Enum.UIMapType.Zone, true)`; each zone's continent is found by
  walking `parentMapID` up to a Continent map (or the top-most parent below the cosmic map).
- Flight masters per zone: `C_TaxiMap.GetTaxiNodesForMap`, kept when neutral or of the player's faction, and
  only for maps where `C_TaxiMap.ShouldMapShowTaxiNodes` is true. A flight master on several maps belongs to
  the first zone that claims it.
- Built once per session on first use (Coverage tab or flight master map). Discovery states are re-read on
  every refresh, since they change as the character plays.
- Known limitation: phased copies of a zone with their own node IDs (old/new versions of a zone) can add
  flight masters that are no longer reachable. Accepted; revisit if the numbers look wrong in game.

## Panel

- Panel.lua: a module with both `options` and `page` gets two tabs under its description (`Options` and
  `page.title`). The chosen tab is remembered per module for the session. Modules with only one of them are
  unchanged.
- Coverage page: an overall line ("312 / 540 flight masters timed - 655 legs"), then a scrolling list.
  Continent rows (click to expand) show a bar and timed / total. Zone rows (click to expand) show a bar,
  timed / total and legs. Flight master rows show a state dot and name: gold = timed, white = known,
  dim = undiscovered. Continents keep map order; zones and flight masters are sorted by name. Empty zones and
  continents are left out.

## Flight master map

- A small dark strip at the top of `FlightMapFrame`: the map's name with timed / total flight masters on
  that map, and the player's current zone with its own count.
- Each shown flight-master pin without a recorded time gets a small orange dot at its top right; its
  tooltip adds "No recorded time to or from here".
- Updated on every `FlightMapFrame` show, one frame after Blizzard's pins are placed. Hidden while the
  module is off.

## Testing

- `tests/test_coverage.lua` covers the rules with plain Lua.
- In game: Coverage tab, expanding rows, flight master map strip and markers, and a fresh flight showing up
  as timed.
