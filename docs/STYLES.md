# Styles: one piece, several looks

Owner request, 2026-10-05: when a piece is picked in the build menu, show its
variants instead of a separate button for each, so the menu takes less room. A
bar and a lemonade stand should be one piece with two looks, not two pieces.
The owner asked for the idea to be criticised hard, and for its effect on play
to be checked, before it was built. This file records both.

## What was built

- **One button per piece.** A count in the button's corner says how many
  looks it has. Picking it opens a **Style** strip floating just above the
  build bar, over the button, so the bar never grows. The button shows the look
  it will place, and remembers the last one picked. **T** goes to the next
  look. The status line names the look ("Table (Parasol)").
- **Restyling in place.** A placed piece's card has a **Style** row of
  pictures; a click changes the look where it stands, for blueprints as well as
  finished pieces. A dearer look costs the difference. A cheaper one costs
  nothing and gives nothing back.
- **Pieces that became looks** (old ids still load):

  | Piece | Looks |
  |---|---|
  | Table | Plain, Parasol (the parasol table, now in Dining) |
  | Chair | Chair, **Stool** (new) |
  | Bar | Timber Bar, **Lemonade Stall** (new; the old stall look, restored) |
  | Wall | Timber, Stone |
  | Floor | Wood, Stone |
  | Lawn | Trimmed, Meadow, Worn |
  | Flower Bed | Daisies, Mixed, Lupins, Tulips, Lavender, Roses, Sunflowers |
  | Wild Grass | Tall, With Flowers, Overgrown |
  | Tree | Leafy, Pine |

- **Grouped but still separate pieces:** Dirt Path and Stone Path share one
  **Path** button. They walk at different paces, so they are not looks of one
  piece; the strip shows each one's pace.
- **Effect on the build menu:**

  | Tab | Buttons before | Buttons after |
  |---|---|---|
  | Garden | 22 | 9 |
  | Structure | 5 | 3 |
  | Dining | 5 | 5, now 9 looks with the stool and the stall |

## How it works, and why this way

A look is a whole `BuildingDef` that **shares its piece's `id`**. Its own fields
are `skin`, `skin_name` and `art`, which names the drawing.

- **Anything that asks what a piece is sees only the id.** That covers recipes,
  rooms, seating roles, tills, `count_built`, objectives, the tutorial's checks
  and saves. A parasol table is simply a table.
- **Anything that asks what a piece costs or how it is walked reads its own
  look.** A stone wall still costs 8g; overgrown grass is still skirted a
  little more than tall grass.

The catalog builds every piece exactly as before, applies every per-id setting
(prices, paces, surfaces, roles), and only then folds the look-alikes into
looks. So **no look lost or changed a single number**. Old ids resolve through
`BuildingCatalog.get_def`, which is how old saves, the tutorial, the test house
and the dev scripts keep working unchanged.

Rejected alternatives:

- **Grouping separate pieces in the UI only.** This leaves gameplay untouched,
  but every id-based check would need a list of all the looks (rooms, recipes,
  objectives, tutorial, header). Restyling in place would have meant demolish
  and rebuild.
- **One piece plus a skin index, with all stats on the piece.** This is cleaner
  in theory. In practice it would have flattened the real price and preference
  differences between the old pieces, and needed a save migration with nothing
  to fall back on.

## Hard critique, and what was done about each point

1. **"Make the bar and the serving table one item" needs care.** The bar and
   the lemonade stand are the same piece; they are now two looks of the Bar.
   The **Serving Counter** is the kitchen's pass, where cooks plate and waiters
   collect. The **Bar** keeps drinks that guests fetch themselves. Merging them
   would make the look decide the job, which is exactly what a style must
   never do. They stay separate pieces, and the code says so.
2. **A look must never change what a piece does.** Enforced, and tested
   (`regressions_styles`):
   - Every look keeps its piece's footprint, layer, role, solidity, till,
     storage, walls and recipes.
   - Art constraints for new looks: same footprint, same serving or seat
     height, stock centres kept clear.
3. **Paths are not looks.** Dirt and stone walk at different paces, so they
   stay two pieces under one button, and the strip shows the pace. Calling them
   skins would have hidden a gameplay choice.
4. **Hidden gameplay hooks keyed on old ids.** The audit found three.
   - **Idle staff wander.** They prefer stone floors (a weight in
     `NavGrid.random_floor_in`, drawn with the simulation's dice). It now reads
     the look's drawing, so behaviour and the chaos-test fingerprints stay the
     same.
   - **The tutorial** counts parasol tables by id. `placed_in` now accepts a
     look's old name.
   - **The dining-room rule** listed `parasol_table`; it is just `table` now.
5. **Price is the only difference between looks.** That is honest for walls,
   floors and beds (they always cost different amounts). New looks (stool,
   stall) cost the same as their piece. Looks have no effect on guests: that
   would contradict the owner's ruling that gardens are visual.
6. **Restyling must not be an exploit.** Going dearer pays the difference;
   going cheaper refunds nothing. Demolishing refunds by the current look's
   price. No round trip returns more gold than was paid (tested).
7. **Touch.** The strip and the Style row are tap targets of at least 78 px
   and 46 px. T is a keyboard extra, never the only way.
   - The strip prints each look's name and price.
   - The card's Style row is pictures only, but the card's subtitle names the
     current look. Tapping another updates the subtitle.
8. **Draw calls.** Each look is batched separately, so a tavern with every
   look adds a few draw calls. That is negligible against the 30.9 ms p95
   budget problem, which lies elsewhere.

## Not done, and worth doing later

- **Unlockable looks** (bought or earned) would give profit a purpose: weak
  part 5 in the October plan. The data allows it (a look is a definition), but
  no unlock rule exists.
- **More looks:** a round or trestle table, a stone bar, a stone counter. Each
  is a drawing plus one catalog line.
- **Restyling a whole room at once** (all chairs to stools).
- **Choosing a look while dragging** keeps the look picked at the start of the
  drag. That is fine, but T during a drag only takes effect on the next drag.
