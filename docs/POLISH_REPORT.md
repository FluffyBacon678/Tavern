# Tier 1 review and polish — 2026-09-21

The Tier 1 structural pass is complete. This is not completion of the full
demo or the later Tier 2/3 backlog. Design-note prices, recipes and wages were
not changed. No external art was introduced.

## Changes

- `world_3d.gd`: 1,061 → 364 lines. Keeps world state, player actions and day
  handling. `WorldHUD` owns controls and readouts; `WorldBootstrap` builds the
  environment and wires dependencies.
- Scripted tavern layouts, path tests, restocking, automatic day advancement
  and reconciliation now live in `dev/world_scenario.gd`. The screenshot
  harness and test entry scenes refuse release builds. The world regeneration
  button is debug-only. Shipping world scripts have no scenario dependency.
- Pawns use one mesh surface with six rigidly weighted bones. Joint pivots,
  gait, tunic palettes and the carry anchor are preserved. No imported art.
- Fixed the root HUD's zero-size anchor setup.
- Supplier orders reserve capacity for the whole bundle before charging.
  Insufficient space rejects the order without partial delivery or payment.
  Every accepted quantity is recorded independently of placement for auditing.
- Reconciliation includes delivered goods, recipe inputs, intended recipe
  yields, customer consumption (including partial meals), ground stock and
  worker cargo. Money is reconciled against closed days plus today's ledger.
  A mismatch exits with code 1. Requested completed-day and blueprint counts
  are checked too.
- The harness refuses a report time at or after its exit time, accepts a seed,
  and finishes correctly in headless mode without waiting for a rendered frame.
  Morning restocking skips day 1, preventing a duplicate initial order.

## Measured validation

Godot 4.7.2, Windows, Intel Arc 140V, GL Compatibility. This is **not Android
validation**. No Android device was exercised; `adb` was not on PATH and no
export preset was present. Device performance and release exports remain open.

| Check | Result |
|---|---|
| Headless editor import/parse | Clean |
| Fixed 15-pawn benchmark, 1280×720 | **352 → 65 draw calls**, 81.5% reduction |
| Benchmark geometry submitted including shadow passes | 7,642 → 7,930 primitives |
| Before/after pawn captures | Same visible body shapes, poses and colours |
| Full three-day run, seed 12345, normal speed | All nine item types: zero discrepancy; gold 36 = expected 36 |
| Full / partially full / repeat delivery | Refused without charges or partial stock changes |
| Empty delivery area | Exact 107g charge; all five ingredients reconcile |
| Inventory while a worker carries malt | Reconciles including one unit in transit |
| Demo layout / pathfinding | 199 placed, zero refused; 5/5 routes, average 11 tiles |
| Blueprint construction, accelerated headless run | 199/199 built; zero open or active jobs |
| 2D menu and world/build-bar captures | Rendered without errors; visually checked |

The rendering benchmark isolates 15 pawns plus a floor and directional light
with shadows. It is not a claim that the whole tavern renders in 65 calls.
Shadow culling changes slightly when parts become one bounded mesh, explaining
the small increase in submitted primitives. The world/build-bar capture showed
260 calls at five workers with supplies; this is a different scene/load.

The normal-speed day results were:

| Day | Served | Lost | Profit | Closing purse |
|---|---:|---:|---:|---:|
| 1 | 0 | 1 | -137g | 113g |
| 2 | 6 | 2 | -78g | 35g |
| 3 | 3 | 3 | +1g | 36g |

Two supply bundles were affordable. In total, one dough became two loaves,
both consumed; five beer batches yielded twenty mugs, twelve consumed and
eight remaining. Ingredients also balanced exactly. The original baseline
completed three days, but its ground-only report was insufficient to prove
conservation. Its profits are not a controlled performance/balance comparison:
it used a different seed and the old initial-restock behaviour.

A final accelerated headless run also passed the completed-day assertion and
all conservation checks, including one beer in transit. Its report purse was
67g = expected 67g; see `.verification/reconciliation.log`. This is a separate
timing configuration, not the normal-speed result above. The existing summary
screen pauses the clock but allows workers/customers to finish work, so money
earned after closing appears on the current ledger page and is included.

## Reproduce

Run from the repository root in PowerShell. Create `.verification` first for
captures; its `.gdignore` keeps generated evidence out of Godot imports.

```powershell
& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --editor --quit --path .

& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://dev/regressions.tscn

& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path . res://dev/pawn_benchmark.tscn --resolution 1280x720 -- .verification/pawns.png

& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path . res://scenes/_screenshot_harness.tscn --resolution 1280x720 -- res://src/world/world3d/world_3d.tscn .verification/three_days.png 180 'seed=12345,demo=tavern,economy=on,restock=on,daylength=80,autodays=2,report=175,distance=17,pitch=52,yaw=45'

& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --time-scale 5 res://scenes/_screenshot_harness.tscn -- res://src/world/world3d/world_3d.tscn unused.png 360 'seed=12345,demo=blueprint,report=350'
```

`autodays=2` means advance twice: three completed days. An 80-second day starts
near 07:31, so each actual trading session lasts about 55 seconds. The seed
fixes random choices, but real-time scheduling can still alter outcomes.

Screenshots and the two pre-refactor source snapshots are in `.verification/`.
The workspace had no Git repository, so these snapshots preserve the main
structural/rendering originals. When adding export presets, exclude `dev/**`,
`scenes/_screenshot_harness.*`, and `.verification/**`; entry guards already
prevent release execution, but an actual export has not been inspected.

## Balance recommendation — not applied

Keep the two-stage bread recipe. For a separate, owner-approved balance test,
try bread at **19g**, comparing the same layouts, staffing and seeds against
the unchanged 10g control.

Using the handoff's approximate fetch counts (not measured labour seconds):

- Bread inputs cost **7g per two loaves** (4 + 2 + 1), so gross contribution
  at 10g is 6.5g/loaf, about **3.25g per fetch** at two fetches per loaf.
- Beer inputs cost **9g per four mugs**, so gross contribution at 8g is
  5.75g/mug, about **7.67g per fetch** at 0.75 fetches per mug.
- Bread at 19g yields about **7.75g per fetch**. Alternatively, four loaves
  per batch at 10g would yield about 8.25g/fetch, but would change recipe yield.

These estimates omit processing, serving, tips and delivery fees. The measured
two-loaf output is too small to attribute the losses to price alone; kitchen
throughput and job scheduling deserve observation in that separate pass.

## Remaining scope

Tier 2/3 items remain: pawn separation, wall occlusion, selection/inspection,
interior readability, storage filters, generic room detection, priority UI and
save/load. The debug regeneration action still deserves a dedicated lifecycle
reset review. Existing bounded overflow placement can warn when an entire area
is saturated; conservation checks now expose such losses rather than masking
them. No lost-goods warnings occurred in the measured runs above.

Forbidden asset sources remain forbidden: rimshare and the OSRS cache were not
used. Existing ForestFirewallpaper attribution remains intact.
