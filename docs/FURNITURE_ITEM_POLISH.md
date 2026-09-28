# Furniture and goods polish — 28 September 2026

This pass follows the adventurer wardrobe work, improving the existing props
without new buildable objects, recipes, prices or inventory behavior. The
production changes are confined to `building_mesh_library.gd` and
`item_mesh_library.gd`; all geometry is original and uses the existing atlas.

## Visible changes

- Tables have bevelled edges, end boards and visible square joinery pegs.
  Chairs have bevelled seats, lower stretchers and a restrained painted stripe.
- Serving counters have teal panels, brass marks, an eased top and a foot rail.
- Prep tables are now open workbenches with a pale stone slab, inset chopping
  board, rolling pin and folded towel. They are visibly distinct from bars.
- Ovens have radial arch stones and a stone rear wall; the rear render exposed
  the old firebox lining as a large black rectangle, which is now covered.
- Brewing vats gain a paddle blade and clearer brass tap; wash basins gain a
  slatted draining board on the left rim.
- Yeast crocks have shaped shoulders, tied cloth lids, glaze and a pale stamp.
  Ale mugs have a glazed band and an open faceted D handle. Water barrels have
  stave and lid seams.

Dining tables remain free of fake food, mugs or plates. Fixed workstation tools
sit away from the tile centres where real goods appear. Footprints, support
heights, seating, navigation, stock quantities and save data are unchanged.

## Verification

Godot 4.7.2 import, `regressions`, `polish_regressions`, `smoke_test` and
`level_smoke -- playedonly` passed. The six-day level run served 236 patrons:
all nine item differences were zero, and **2,059g actual = 2,059g expected**.
Only the regression suite's intentional save-fixture warnings appeared. The
test-save directory was empty after the runs.

Front and back furniture renders, the goods gallery, and real guests in the
live tavern were inspected. Every prop retains one cached mesh surface and the
shared material. Nine furniture meshes total **1,798 → 2,106 triangles**; all
nine goods total **890 → 1,079 triangles**. The lit furniture gallery remains
**21 draw calls**, with **3,748 → 4,364 submitted primitives** including shadow
and label geometry. These are geometry/draw counts, not a mobile FPS claim;
Android hardware remains unmeasured.

Evidence is in `.verification/props_20260928/`: `after_front.png`,
`after_back.png`, `items_after.png`, `after_tavern_close.png`, source snapshots
and logs. The initial furniture capture used a lower camera; the final contact
sheet raises it to prevent captions overlapping the next row.

For a repeatable furniture capture, import first, then run windowed:

```powershell
& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --import
& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1600x1000 res://dev/furniture_showcase.tscn -- res://.verification/furniture
```

The showcase isolates saves, prints mesh bounds and render counts, captures two
views, and exits. It refuses headless rendering and fails if a capture cannot
be saved. The output prefix's directory must already exist.
