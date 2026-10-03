# Garden tiles and park props — 2026-10-03

A low-poly garden set for building parks and paths beside the tavern, made to
the supplied reference sheet: simple, crisp shapes that read from the
management camera, no painterly texture. Everything is original procedural
geometry in `src/world/build/garden_art.gd`; no images or external models.

![Tile sheet](../.verification/garden_20261003/garden_tiles.png)

![A small park beside the tavern, laid with the build bar's Garden tab](../.verification/garden_20261003/garden_park.png)

## The pieces (Build → Garden)

| Piece | Kind | Cost | Walking pace | Triangles |
|---|---|---:|---:|---:|
| Trimmed Lawn | tile | 1g | 91% | 65 |
| Meadow Grass | tile | 1g | 83% | 208 |
| Worn Grass | tile | 1g | 95% | 104 |
| Dirt Path | tile | 1g | 100% | 119 |
| Daisy Bed | tile | 4g | 38% | 446 |
| Mixed Flower Bed | tile | 5g | 38% | 552 |
| Border Flower Bed | tile | 5g | 38% | 650 |
| Tall Grass | tile | 2g | 56% | 206 |
| Tall Grass with Flowers | tile | 2g | 56% | 344 |
| Overgrown Plot | tile | 2g | 45% | 186 |
| Park Bench (2 x 1) | prop | 12g | solid | 156 |
| Rocks | prop | 6g | solid | 66 |
| Leafy Tree | prop | 15g | solid | 70 |
| Pine | prop | 15g | solid | 60 |
| Lantern Post | prop | 10g | solid | 80 |

Tiles are 1 x 1 floor pieces, dragged out like flooring, 0.05 thick with a
soil edge, so props and goods placed on them sit on the bed. Decoration stays
inside each tile, so neighbours join cleanly, and each tile is turned a fixed
quarter by its position (`BuildController.tile_turn`), so a lawn of one kind
does not repeat. Walking pace comes from `BuildingDef.walk_cost`: paths are the
quickest ground, lawns nearly so, tall grass is slow, and people step round
flower beds unless there is no other way. Idle staff keep to the house floors.

## Try it

Open **Build → Garden**, drag a path out from a door, edge it with flower beds,
fill the rest with lawn, and add benches, lanterns and trees. **C** takes back
the last drag. The tutorial's Growing lesson now asks for a short path and a
daisy bed by the front door.

## Showcase and checks

- `dev/garden_showcase.tscn -- sheet <png>`: the tile sheet above (display
  soil blocks are for the picture only).
- `dev/garden_showcase.tscn -- park <png>`: the park above, laid by the real
  build system beside the sandbox's tavern, with a back door where the path
  meets the hall.
- `dev/garden_showcase.tscn -- stand <png>`: a fenced lemonade garden, laid the
  same way.
- `dev/regressions.tscn -- group=garden`: catalogue, budgets, faces-up, tiles
  stay inside their square, beds are walked round, idle staff stay indoors,
  tile turns; the stand: roles, the press, lemons beside the stall and jugs
  on its first tile, fence joints, the view, Surroundings in a save.
- `dev/persona_playtest.tscn -- persona=idle|profit|garden [days=5] [sim=N]
  [fence=0] [lemonade=0] [strip=ids] [hire=roles] [watch=day] [shots=dir]`:
  scripted players on the sandbox house, with switches to measure each part.

## The lemonade stand

![A fenced lemonade garden, laid with the build system](../.verification/stand_20261004/stand_garden.png)

![The garden player's garden on day 3, in the rain](../.verification/stand_20261004/persona_garden/garden_day3_morning.png)

The tile sheet with the stand's row: `../.verification/stand_20261004/garden_sheet.png`.

| Piece | Kind | Cost | Role | Triangles |
|---|---|---:|---|---:|
| Market Stall (2 x 1) | prop | 30g | serving counter and lemonade press | 282 |
| Parasol Table (2 x 1) | prop | 16g | a table: chairs beside it seat guests | 115 |
| Garden Fence | prop | 2g a tile | dragged like a wall; joins its neighbours | up to 196 |

- **Lemonade**: lemons (2g, from the merchant) and water, pressed at a stall
  into four jugs (sold at 7g). Lemonade has a meal target in Stores like
  anything else (12 by default), so auto restock buys the lemons. Cooks press
  it, and fetch the lemons and water to the ground beside the stall; the
  stall's top is kept for jugs and plates.
- **The stall is the garden's counter.** Each table is served from its nearest
  counter: the garden's tables from the stall, the hall's from the hall's.
  The stall keeps its first tile for its own jugs; the kitchen plates the
  garden's food onto the other. Lemonade is sold at the stall's own tables
  only: offered in the hall too, every jug was a cook's walk out and back.
- **Pieces have roles, not names.** `BuildingDef.furniture_role` (table, chair,
  counter) is what seating, plating, rooms and the guest card read, so any new
  table or counter works without touching them.
- **Fences** link to fence on each side (`BuildController.link_mask`), drawn
  with one mesh per joint shape, so corners, ends and crossings meet cleanly.
- **Surroundings.** Every piece has a `beauty` (flower beds 3, trees 3,
  lanterns 2, benches 2, parasol tables and stalls 2, tall grass with flowers
  and fences 1; lawns and paths are the ground, and count for nothing). A guest's
  view is the beauty within three tiles of their chair, out of 24, taken as
  they sit down. A view adds up to **+10** to the review (a new Surroundings
  part, never negative, so a tavern without a garden scores exactly as
  before) and makes the guest up to **50% more patient**, with the wait
  counting for that much less. That is what pays for the garden's tables
  being the far ones from the kitchen.

The tutorial's last lesson, *The garden stand*, has the player build a stall
and a parasol table, waits for the first lemonade, and watches a guest drink
it. The sandbox's test house has a small front garden with a stall, a parasol
table, flowers and a fence, and a third waiter to staff it.

**What it costs.** Garden tables are the far ones from the kitchen, and
footfall comes from reputation alone, so a garden adds walking before it adds
guests. In the persona play tests (`dev/persona_playtest.tscn`, five days,
four dice seeds) the sandbox's front garden cost an idle player about 700g
without its waiter and 400g with one. A player who builds a big garden serves
the most guests of all but, after five days, has not yet earned back its
cost.

Not yet: neighbour-aware path edges (worn grass tiles stand in for ragged path
borders), and a gate for fences.
