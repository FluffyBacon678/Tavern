# Keeper sculpt and character editor — 2026-10-01

**Later face/hand follow-up:** [KEEPER_DETAIL_POLISH.md](KEEPER_DETAIL_POLISH.md)
records the warmer expression, shaped hands and verified Hands close-up.
Measurements below describe the preceding sculpt pass.

The requested follow-up focuses on the default keeper's appearance and an
editor that makes future character art easier to judge. This is original
procedural low-poly fantasy art, inspired by the supplied direction. No
outside models, textures or new licensing dependencies were added.

## What changed

The ordinary keeper now uses continuous body contours instead of stacked
closed blocks. The tunic has a chest, fitted waist, shoulder-to-neck slope,
visible opening/collar and broad shallow cloth folds. The sleeves transition
through cuff, forearm, wrist and palm; trousers shape the thigh and knee before
meeting the boots. The contours cap only their ends, removing hidden internal
faces so these changes remain inexpensive.

The head has a separate chin, jaw, cheek, brow and forehead profile, with
different front and rear depths. Eyes and a quiet mouth follow that profile.
The nose has a bridge/tip/underside, and the hair crown narrows and turns over
the skull. Broad swept locks replace the separate spike silhouettes. Both
body builds and all four existing hairstyles use the ordinary sculpt.

`KeeperMesh` isolates this base-body artwork behind the shared `PawnMesh`
builder. It keeps the six bones, existing heights, floor contact and carry
anchor. Future ordinary outfits can follow the same body sections; no saved
appearance fields, equipment slots, identity, ownership or RNG contract changes.
Legacy NPC costume topology retains its existing measured budget.

The editor has real **Full body** and **Face** controls, a larger body view,
sharper preview, calmer blue/plaster backdrop, restrained lanterns and balanced
lighting. Appearance choices remain scrollable while confirmation stays
visible. Framing changes the camera only; rotation and selected appearance
remain intact. The preview still draws only on a change, rotation or resize.
Resolution is bounded by a 1280px long edge and 921,600 pixels.

The first actual render exposed detached shoulder sockets, a partially buried
collar and an overly flat hair crown. These were corrected and captured again.
A separate read-only art review found no clear holes, flipped face patches,
hair culling or equipment intersections in the final supplied captures.

![Default keeper in the actual editor](../.verification/character_editor_20261001/view_starter_front.png)

![Actual Face view](../.verification/character_editor_20261001/view_default_face.png)

![Side profile](../.verification/character_editor_20261001/view_default_face_profile.png)

## Measured verification

Evidence: `.verification/character_editor_20261001/`.

```text
CHARACTER SMOKE: 0 failure(s)                 # windowed and headless
ADVENTURER MESH SMOKE: 0 failure(s)
CHARACTER SHOWCASE: 0 failure(s)
REGRESSIONS PASS (0 failures)
POLISH REGRESSIONS: 0 failure(s)
RECONCILIATION PASS: days=3 gold=3679 expected=3679
HOUSE SMOKE PASS: one of everything, three days traded; made bread 52, beer 68, water 38, fish 68, wheat 72; 32 plots growing; 3679g
PAWN_BENCHMARK count=15 draw_calls=65 primitives=68706
```

New assertions cover both ordinary builds × four hairstyles, with and without
the combined travel kit: one surface/six unit-scale bone rests, surviving
pupils, finite bounds, exact floor contact and retained carry anchor.
The default is **1,029 triangles** versus 954 before (**7.9% more**). The
largest ordinary keeper with combined kit is **1,367**, below the same 1,400
ceiling. The 128 existing NPC combinations still peak at **1,393**.
The fixed 15-pawn staff/customer benchmark is unchanged at 65 draws / 68,706
rendered primitives; it does not sample the ordinary keeper. The gallery
separately prints the ordinary mesh counts and rendering totals.

The character suite presses the actual Face/Full body buttons, then checks
that mesh instance, appearance, equipment, rotation and RNG are preserved.
The default head is fully inside the rendered close-up, at least twice the
full-body projected height and at least 35% of the preview height. Windowed
checks confirm head and full-body silhouette bounds, visible framing/actions,
retained choices and camera angle at **1280×720, 1024×768, 1440×900 and
2560×1080**. All requested sizes were honored. Headless runs verify logic and
layout, with an explicit note that rendered bounds require the windowed run.
Repeated selected framing causes no redraw; the idle-preview check still passes.

Modern and legacy saves restore through separate engine processes, and actual
new-game/Keeper acceptance and cancellation still pass. SHA-256 hashes of all
five existing player save/backup files are unchanged. All current test-save
folders were cleaned on exit; three older September 28–29 folders were retained.
Import, character and gallery output has no new errors or warnings. The
gameplay regression suite retains its intentional old load-intent warning.

## Reproduce

From the project directory, import first:

```powershell
$godot = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --import
& $godot --headless --path . res://dev/character_smoke.tscn
# The directory exists in this pass; create it first if using another prefix.
& $godot --path . res://dev/character_smoke.tscn -- shots=res://.verification/character_editor_20261001/recheck
& $godot --path . res://dev/character_showcase.tscn -- res://.verification/character_editor_20261001/gallery_recheck
```

The smoke suite runs the real editor and produces full-body, face/profile,
four-size Face captures and equipped-fixture captures. The gallery renders
both builds, all four hairs, varied palettes and the combined travelling kit.

## Remaining art work

The character is still deliberately coarse, with rigid elbows/knees and a
neutral expression. It has not reached the supplied concept's sculpted face,
natural hands or cloth quality. Further art work should refine one ordinary
keeper in front, profile and three-quarter views before adding more costume
catalog entries. Android rendering/touch and live-game frame timing remain
unverified; these desktop captures do not establish those.

Edited: `src/world/pawn/pawn_mesh.gd`, new `src/world/pawn/keeper_mesh.gd`,
`src/ui/character/character_preview.gd`,
`src/ui/character/character_creator.gd`, and `dev/character_smoke.gd`.
