# Texture and item polish — 2026-09-25

Completed visual inspection and refinement of the shared texture pass begun on
September 24. Preserved the owner's subsequent gameplay changes, including
stale-pickup withdrawal and first-sale persistence. No economy values changed.

## Appearance

- Original shared atlas supplies wood grain, stone, plaster, cloth, crust,
  iron and pottery detail. No downloaded or restricted assets were introduced.
- Goods have grain-stamped sacks, a marked water cask, leafy hops, a pottery
  mug with foam, scored bread and a used plate with a spoon.
- This follow-up rounds the dough into a folded mound, tapers and softens bread
  scores, and broadens floorboards with lower-contrast end joints.
- The item gallery now has neutral lighting, a dark backdrop and separated
  captions; diagnostic triangle counts remain in its log rather than covering
  the props.
- Every item remains one mesh surface, ranging from 63 to 140 triangles.
  Dough is now 84 triangles rather than 44; bread remains 88.

## Verification

Godot 4.7.2 import passed and `REGRESSIONS PASS (0 failures)` was confirmed
before and after the edits. The suite's physical-item and ledger reconciliations
passed. This follow-up did not rerun the long gameplay soak and does not claim
to resolve the previously reported simulation stalls.

Inspected real Compatibility-renderer captures of all nine items, the tavern
at management zoom and the main menu. The menu still renders; its existing
format-1 save-slot warning was observed and the save was left untouched.

Whole-tavern frozen rendering, 1280×720 on Intel Arc 140V:

| Pawns | Archived pre-texture draws | Current draws | Current median / p95 ms |
|---|---:|---:|---:|
| 5 | 231 | 215 | 1.276 / 5.919 |
| 15 | 261 | 245 | 1.353 / 6.028 |
| 30 | 306 | 290 | 1.386 / 6.075 |

At 15 pawns, submitted primitives are 896,945 versus 899,337 in the archived
baseline. Reported rendering memory increases from 40.7 to 41.5 MiB. This
comparison covers the combined texture/item pass, not just today's small mesh
refinements. Timings include presentation and OS scheduling; they do not prove
a speed improvement. This is a frozen render test, not simulation throughput.
Android remains untested.

Evidence: `.verification/polish_20260925/`, including `gallery_after.png`,
`world_after.png`, `menu.png`, `regressions_after.log` and `profile/report.json`.
The archived baseline is `.verification/textures_20260924/before_profile/`.

```powershell
$godot = '..\_tools\godot\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --import
& $godot --headless --path . res://dev/regressions.tscn
& $godot --path . --resolution 1280x720 res://scenes/_screenshot_harness.tscn -- res://dev/item_gallery.tscn .verification/polish_20260925/gallery_after.png 3
& $godot --path . res://dev/tavern_profile.tscn -- res://.verification/polish_20260925/profile
```
