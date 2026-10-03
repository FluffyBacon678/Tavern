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
- `dev/regressions.tscn -- group=garden`: catalogue, budgets, faces-up, tiles
  stay inside their square, beds are walked round, idle staff stay indoors,
  tile turns.

Not yet: fences, garden beauty affecting guests' mood, and neighbour-aware
path edges (worn grass tiles stand in for ragged path borders).
