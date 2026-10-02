# Stores and farming polish — 29 September 2026

## Player flow

Open **Stores (U)**. Every finished dish/drink has one toggle and one
**Restock below X** target. Ingredients are listed underneath, together with
current meal stock. Turning a meal off stops that meal's production; existing
food remains available to sell. The global Auto restock switch pauses buying
while existing kitchen orders continue.

Manual ingredient purchases and advanced kitchen details are secondary
buttons. Production no longer occupies another top-bar button; its P shortcut
still opens advanced details. Stores uses a compact scrollable panel, rescales
after window changes, and keeps controls at least 24 physical pixels high at
the tested PC sizes. Other panels have not received a global redesign.

## Why the ordering logic changed

Only finished menu targets drive shopping. The previous calculation also
treated intermediate targets such as dough as separate shopping demands.
`MealSupplyPlan` now shares one virtual pantry across the whole menu, counting
physical ingredients, ready dough, harvested wheat, and fish co-products once.
It can use either trout or perch, including heads as secondary recipe outputs.
An unavailable local catch does not trigger purchases of unusable soup water.
Missing/disabled stations or prep recipes cannot create speculative orders.

For an empty working kitchen, targets of **10 bread + 12 beer** require exactly
**5 flour, 5 yeast, 8 water, 3 malt, 3 hops**. With **1 ready dough, 1 flour,
and 4 harvested wheat**, that falls to **1 flour, 4 yeast, 7 water, 3 malt,
3 hops**. Three perch can supply six soup and three grilled fish, requiring
only three purchased water when no other stock exists.

Existing deliveries unload immediately and therefore count as current stock;
there is no in-transit delivery simulation. Shared cart cooldown, unloading
capacity checks and the wage reserve remain. Cooldown now survives saving.
Explicit meal configuration can start auto-ordering without a manual first cart.
Old saves retain their targets, enabled choices and ingredient exclusions;
meal restart lines migrate to the single displayed target. A contextual
“Allow all ingredients” button can clear old exclusions.

This cannot guarantee food at every moment: cooks, stations, hauling, local
fish, available storage and sufficient money are still required. No ingredient
prices, wages or recipe work times were changed. Meal cooking now restarts just
below its target, rather than waiting for the old, lower hidden threshold.

## Farming polish

- Wheat now has distinct sprouts, green heads and golden ripe heads; hops use
  wooden string trellises and pale cones. Crop rendering uses at most six
  shared batches rather than a separate mesh instance per plot.
- Tilled beds have earth clods. Wells have an open collector and winding drum;
  pumps have collars, a bolted foot, turned spout and hollow banded bucket.
  All art is original procedural geometry, with no new asset licenses.
- Wells collect only actual deterministic rainfall and only outside completed
  shelter. Full wells neither overflow nor book phantom production. Partial
  rainfall progress survives saving.
- Full/partially full harvest surroundings leave uncollected yield standing.
  Retrying or saving/loading cannot lose or duplicate that remainder. The
  inspector explains when space is needed. Switching crops cancels old work.
- Growth remains 1,300 game seconds, wheat yield 3, hops yield 2; pump work
  remains 25 seconds. Rain retains 36 full-intensity rainy seconds per barrel.
  Rain gating intentionally reduces supply compared with the previous bug
  that filled wells in all weather. Wells retain their existing near-water
  placement rule.
- Construction lessons already satisfied on entry now require fresh placement
  practice and explain this in the tutorial panel. The full-house sandbox and
  the empty-plot tutorial remain separate starts.

## Verification

Import first, using the supplied Godot 4.7.2 console executable:

```powershell
& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --import
& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://dev/stores_smoke.tscn
& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://dev/farm_polish_smoke.tscn
```

Both sandbox their saves and exit nonzero on a failed assertion. Stores tests
exact ingredient arithmetic, shared co-products, home-grown preference,
save/load and purchase reconciliation, UI actions, real click sizes and three
window shapes. Farm tests dry/wet/full/roofed wells, blocked and partial
harvests, save recovery, changed crops, bounded visual batches and fresh
tutorial construction. Both are in `dev/run_tests.sh`.

Existing regression, polish, guided-opening, HUD-layout and atmosphere suites
pass. The tutorial passes 61/61 steps. The expanded house completes three
trading days with every role/building and now also reconciles goods and gold:
52 bread, 68 beer, 38 water, 68 fish, 72 wheat; 32 growing plots; 3,679 gold.
These figures describe the seeded test fixture, not a balance guarantee.

Actual windowed screenshots were inspected using the Compatibility renderer.
`dev/stores_showcase.tscn` captures 1280×720 and 1024×768 windows;
`dev/farm_showcase.tscn` captures the field, well and pump with posed crop
stages. Create the output folder, then pass an output prefix after `--`.
Headless showcase launches are refused. The farm pictures are art fixtures,
not evidence of elapsed growth time.

Evidence: `.verification/stores_20260929/` and
`.verification/farm_polish_20260929/`. Earlier failing logs are kept separately
from final runs. Android hardware has not been tested. Regression warnings
intentionally exercise old-save rejection and missing load/new-run intent.

## Follow-up — 30 September 2026

The tenth lesson, **Farming and water**, adds eight steps: hire a farmer, lay
six beds, watch real planting, inspect a bed, switch it to hops, place and build
a river pump, and save. It explains automatic harvest, space for yield, slow
growth, and outdoor rain collection. Growth continues after the lesson instead
of making the player wait two trading days. Existing step indices 0–52 are
unchanged; an old completed tutorial at index 53 now opens the farming lesson.
Construction still requires fresh practice when pieces were already present.

The live observer found that the day-close lesson could accept an earlier
closed day and advance straight into morning-only bookings after noon. The
lesson now requires a fresh close, reviews refer to the current summary, and
the booking instructions explain opening tomorrow when the morning was missed.
Farm smoke includes regressions for these day transitions. The turbo observer
now reselects a current guest for both hover lessons if its previous guest
leaves before the real-time tutorial poll.

Header status chips now flow when their measured widths need another line;
staff, fish and reputation text no longer extends beyond the right edge.
HUD smoke also measures header captions and populated full-house starts.
Stores uses interpolated text filtering at fractional canvas scales and a
larger target caption, avoiding missing glyph rows at 1024×768. Original
procedural crop and furniture art and all recipe/crop balance values remain.

The nine headless shutdown leaks were WAV streams/playbacks. AudioDirector
releases its pool on exit and validates sound IDs without starting inaudible
playback on Godot's Dummy audio driver. Windowed WASAPI playback remains
enabled. Both driver paths exit without that warning in the verified tutorial
runs. “Show me” no longer tries to focus toolbar buttons that reject focus.

Tutorial screenshot capture now stops clock processing only while drawing the
report, preserving the selected speed and preventing screenshots from adding
simulation frames. The tutorial harness now reconciles physical goods and gold
at completion, including after its optional trading soak. A windowed run
completed 61/61 steps in 25 real seconds, then three trading days: **138 guests
served, 3 lost to service, 1,144g → 2,307g**, with **15 wheat, 2 hops and 30 water**
produced in total. Every item difference was zero and gold matched the ledger.
Evidence, including earlier failing runs, is in `.verification/farming_followup/`.

The final live observer also completed **61/61** with its normal director
polling, passing reconciliation at 1,588g on day 3. Final regression, polish,
guided-opening, Stores, farm and HUD suites passed; HUD skipped no shapes.
The observer's compact final state is `live_complete/state.json`; scripted
smoke/soak results are in `tutorial_complete.txt`, and rendered/WASAPI results
in `tutorial_windowed_final.txt`. These are automated player actions, not a
manual mouse playthrough or an Android device test.
