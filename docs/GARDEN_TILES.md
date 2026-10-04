# Garden tiles, park props and the bar — 2026-10-03, revised 2026-10-04

A low-poly garden set for building parks and paths beside the tavern (or in
it), made to the supplied reference sheet: simple, crisp shapes that read from
the management camera, no painterly texture. Everything is original procedural
geometry in `src/world/build/garden_art.gd`; no images or external models.

**Gardens are for looks.** Inside or out, they are the player's to make as they
like: no beauty score, no review bonus, nothing that makes one arrangement the
correct one (see `docs/CURRENT_GAME_VISION.md`, "Decorative expression remains
optional and broad"). The one thing a tile does is set the walking pace, and
only the dearer paths are quicker than open ground.

![Tile sheet](../.verification/garden_20261004b/sheet.png)

![A small park beside the tavern, laid with the build bar's Garden tab](../.verification/garden_20261003/garden_park.png)

## The pieces (Build → Garden)

Walking pace is against a laid floor (wood or stone, 100%); open ground is 78%
and the dirt road 89%.

| Piece | Kind | Cost | Walking pace | Triangles |
|---|---|---:|---:|---:|
| Stone Path | tile | 3g | 100% | up to 278 |
| Dirt Path | tile | 1g | 89% | up to 220 |
| Trimmed Lawn | tile | 1g | 78% | 65 |
| Meadow Grass | tile | 1g | 78% | 208 |
| Worn Grass | tile | 1g | 78% | 104 |
| Daisy Bed | tile | 4g | 78%, walked round | 446 |
| Mixed Flower Bed | tile | 5g | 78%, walked round | 552 |
| Border Flower Bed | tile | 5g | 78%, walked round | 650 |
| Tulip Bed | tile | 5g | 78%, walked round | 446 |
| Lavender Bed | tile | 5g | 78%, walked round | 398 |
| Rose Bed | tile | 6g | 78%, walked round | 368 |
| Sunflower Bed | tile | 5g | 78%, walked round | 378 |
| Tall Grass | tile | 2g | 78%, kept off | 206 |
| Tall Grass with Flowers | tile | 2g | 78%, kept off | 344 |
| Overgrown Plot | tile | 2g | 78%, kept off | 186 |
| Park Bench (2 x 1) | prop | 12g | solid | 156 |
| Rocks | prop | 6g | solid | 66 |
| Leafy Tree | prop | 15g | solid | 70 |
| Pine | prop | 15g | solid | 60 |
| Lantern Post | prop | 10g | solid | 80 |
| Parasol Table (2 x 1) | prop | 16g | a table: chairs beside it seat guests | 115 |
| Garden Fence | prop | 2g a tile | dragged like a wall; joins its neighbours | up to 196 |

Tiles are 1 x 1 floor pieces, dragged out like flooring, 0.05 thick with a
soil edge, so props and goods placed on them sit on the bed. Decoration stays
inside each tile, so neighbours join cleanly, and each tile is turned a fixed
quarter by its position (`BuildController.tile_turn`), so a lawn of one kind
does not repeat. Pace is `BuildingDef.walk_cost`; where people go is
`BuildingDef.keep_off`, a route preference only: nobody tramples a flower bed
when there is a way round, but a step on one is no slower. Idle staff keep to
the house floors. Fences link to fence on each side
(`BuildController.link_mask`), drawn with one mesh per joint shape, so corners,
ends and crossings meet cleanly.

## The bar (Build → Dining)

![A fenced garden with a bar on a stone square](../.verification/garden_20261004b/garden.png)

The **Bar Table** (2 x 1, 30g) keeps drinks on its counter, one to each tile:
its own lemonade, pressed there, and then the other drinks on the menu (beer).
It works inside or out, and serves both.

- **Lemonade**: lemons (2g, from the merchant) and water, pressed at the bar
  into four jugs (sold at 7g). Lemonade has a meal target in Stores like
  anything else (12 by default), so auto restock buys the lemons. Cooks press
  it; the lemons and water wait on the ground beside the bar.
- **Beer** is brought to the bar by the porters, six at a time.
- **Walk-up guests.** A guest who wants only drinks, and is no more patient
  than the ordinary traveller (travellers, warriors, rangers, duelists), gets
  up from the table, takes the drinks off the bar's counter, sits back down
  with them, and pays on the way out: no waiter, no bill to wait for, and no
  tip. Patient guests (wizards, delvers, pilgrims), and anyone wanting a
  meal, put a hand up and are waited on.
- Waiters fetch drinks from a bar too, as from a serving counter. The kitchen
  plates nothing onto a bar: food goes to the serving counters.
- **Pieces have roles, not names.** `BuildingDef.furniture_role` (table, chair,
  counter, bar) is what seating, plating, serving and saves read, so any new
  table, counter or bar works without touching them.

The tutorial's last lesson, *The bar*, has the player build a bar and a parasol
table, waits for the first lemonade, and watches a guest fetch their own drink.
The sandbox's test house has a small front garden with a bar, a parasol table,
flowers and a fence.

## Try it

Open **Build → Garden**, drag a path out from a door, edge it with flower beds,
fill the rest with lawn, and add benches, lanterns and trees. **C** takes back
the last drag. Put a **Bar Table** (Dining) where inside and outside guests can
both reach it. The tutorial's Growing lesson asks for a short path and a daisy
bed by the front door.

## Showcase and checks

- `dev/garden_showcase.tscn -- sheet <png>`: the tile sheet above (display
  soil blocks are for the picture only).
- `dev/garden_showcase.tscn -- park <png>`: the park above, laid by the real
  build system beside the sandbox's tavern, with a back door where the path
  meets the hall.
- `dev/garden_showcase.tscn -- stand <png>`: a fenced garden with a bar on a
  stone square, laid the same way.
- `dev/regressions.tscn -- group=garden`: catalogue, budgets, faces-up, tiles
  stay inside their square, garden tiles walk like open ground and paths
  quicker, beds are walked round, idle staff stay indoors, tile turns; the
  bar: roles, the press, lemons beside it and each drink on its own tile,
  porters stocking the beer, where a walk-up guest stands, old saves (the
  market stall's name, a dropped review part), fence joints.
- `dev/persona_playtest.tscn -- persona=idle|profit|garden [days=5] [sim=N]
  [fence=0] [lemonade=0] [strip=ids] [hire=roles] [watch=day] [shots=dir]`:
  scripted players on the sandbox house, with switches to measure each part.

**Paths join up.** A dirt or stone path joins any path beside it and is edged
where it meets anything else: a grass verge with tufts on a dirt path, kerb
stones on a stone one. A straight run of dirt path carries cart ruts. Each
joint shape is drawn four ways, so a long path does not repeat
(`GardenArt.path`, `BuildingDef.link_group`).

Not yet: a gate for fences.
