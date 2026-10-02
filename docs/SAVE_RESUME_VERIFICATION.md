# Save/resume hardening — 30 September 2026

All three existing player saves were copied before testing. Original files in
Godot's user-data `saves` directory were read only; SHA-256 comparisons confirm
they are unchanged. Protective copies remain in
`.verification/save_resume/player_backups/`. Tests use `begin_test_session()`
scratch slots, never the player's actual slots.

## Fixed

- Saving previously opened the main file for writing immediately, truncating
  the only good copy. It now writes and flushes `.tmp`, reads and validates it,
  rotates a valid primary into `.bak`, then renames the temporary file into
  place. A failed commit leaves the backup available. A corrupt primary cannot
  replace a good recovery backup. Recovery restores the **previous** save, so
  progress from an interrupted latest save can still be absent.
- A version-2 JSON object missing its building/item arrays could be accepted
  and interpreted as an empty tavern. Slot reads now validate the snapshot,
  required collections, placements, stack counts, cargo and production fields;
  invalid primaries fall back to a valid backup. Unrecoverable files are kept
  and refused, with a menu error instead of an empty replacement world.
- Item loading previously treated saved goods as new deliveries, applying
  current storage filters and searching nearby tiles. Changing a whitelist
  after stocking a shelf can legally leave old stock there. Restoring those
  goods now preserves the exact saved tile, quantity and quality; filters
  continue to govern future deliveries. The crowded-filter fixture failed
  before the fix and passes afterwards.
- A fresh closed-day load restored the paused clock and summary but omitted
  the world/simulation hold. Jobs could run behind the summary and the
  `Open tomorrow` guard rejected continuation. The whole hold now returns
  after staff/guests are restored, without closing the books or charging wages
  again. The new fresh-process check failed before this fix.
- Unsaved-progress detection compared only time, gold and counts. It now
  compares a fingerprint of the full persisted state, excluding save time,
  catching paused edits to crops, storage filters and meal targets.

## Verification

```powershell
& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --import
& '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://dev/save_resume_smoke.tscn
```

The new smoke test saves a populated house with unfinished construction,
stock behind a changed shelf filter, carried water, crop growth and a partial
harvest. It then starts separate Godot processes, whose autoload state begins
fresh, copies the source into their isolated slots, and uses `request_continue`
and the normal world scene. It checks exact building and item fields, staff
and cargo, land, seed, gold and meal choices. Closed-day restart checks the
summary hold, next-day continuation and single payroll. Engine errors in a
child fail the parent even if its process exits zero.

Fault injection covers repeated backup rotation, rejected incomplete writes,
valid JSON missing its world collections, truncated JSON, recovery followed
by saving, interruption between rotation and commit, and failure without a
backup. Test scratch slots are cleaned on exit. The suite is included in
`dev/run_tests.sh`.

Optional `source=res://path/to/copied_save.json` arguments check existing
snapshots read only. All three protected player copies restored with:

| Player slot | Buildings | Ground item stacks |
|---|---:|---:|
| 1 | 437 → 437 | 12 → 12 |
| 2 | 321 → 321 | 15 → 15 |
| 3 | 181 → 181 | 20 → 20 |

Every saved building/item field and cargo matched. Older well `draw_water`
bills are obsolete under rain collection, and old final-meal restart lines
migrate to the current single target; their stock and current target/toggle
choices remain. New default priorities may appear for newly added work kinds.

Final logs: `.verification/save_resume/complete.txt`, `day_final.txt`,
`stores_final.txt`, `regressions_complete.txt`, `visit_final.txt`, `farm_final.txt`, `smoke_final.txt`
and `tutorial_final.txt`. The 61-step tutorial and three-day reconciliation
passed. Earlier failing logs are retained separately. Windows headless tests
exercise real disk saves and separate processes; Android storage and a real
power cut have not been tested. These files cannot establish why an earlier
session lost progress or reconstruct anything already overwritten previously.

## Menu polish and actual button playback (2026-09-30)

Load cards now put actions beneath the details, show built structures, stock
piles and staff, and distinguish Tutorial saves. Long names have a full-name
tooltip. Backup recovery belongs to the individual slot summary, so inspecting
another slot cannot silently change its card's recovery state. The recovery
button says **Load backup** and explains that it restores the previous save.
The pause menu identifies the slot and retains a recovery reminder until a
successful Save. The left title and description stay beside the open Load
page at 4:3 rather than extending underneath it.

`dev/save_ui_smoke.tscn` presses the real menu controls and crosses the normal
scene router. Save → corrupt test primary → Load backup → Save → title screen
→ Continue restores the populated tavern. Both 1280×720 and 1024×768 layout
checks pass, with screenshots inspected. The headless test is in the suite;
windowed mode can capture `-- shots=res://.verification/save_ui_polish/prefix`.

Playback also exposed main-menu looping tweens outliving their deleted
background on resize; animations now bind to the actual animated controls.
Windowed test fixtures finish their first draw before deletion: deleting a
new sky before that draw produced GLES texture leak messages in this harness.
The final windowed run exits cleanly, without altering sky quality or engine
settings. See `.verification/save_ui_polish/windowed_rendered.txt` and
`verified_final_*.png`. Headless Save UI, Stores, fresh-process resume,
regressions and all 61 tutorial steps pass; the tutorial's goods and gold
reconciliation also passes.

Stores now says when it is waiting on the kitchen or local ingredients rather
than suggesting nothing is needed. Its tooltip points to the meal rows and
Kitchen details. This changes messaging only; buying rules and prices remain.
