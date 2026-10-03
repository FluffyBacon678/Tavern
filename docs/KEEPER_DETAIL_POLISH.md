# Keeper face, hands and editor detail — 2026-10-02

**Later follow-up:** [CHARACTER_WARDROBE.md](CHARACTER_WARDROBE.md) adds usable
clothing slots, original cook/travel garments and further face refinement.
Measurements below describe the October 2 pass.

This continues [the keeper/editor sculpt](CHARACTER_EDITOR_POLISH.md). The
ordinary keeper gets a warmer face, clearer hands and a dedicated Hands view
for judging future cuffs and held-item art. Geometry remains original procedural
low-poly fantasy work; no external assets or licensing dependencies were added.

## What changed

The face has warm irises, tiny eye highlights, gently mirrored brow arches and
a thin closed smile. The nose tip projects less. Details still follow the
existing cheek/brow surface and retain their small-facet tolerance locally;
the common mesh-builder threshold is unchanged. Light and dark palettes were
captured in front and profile rather than assuming all skin colours work.

`KeeperLimbArt` authors the ordinary sleeve, cuff, wrist and hand behind
`KeeperMesh.arm`. The wrist narrows into a slimmer palm, the fingertip edge has
four shallow contours, and a bent, capped thumb replaces the pointed peg.
Shoulder caps sit inward against the tunic. The ordinary editor stance is
slightly asymmetric so both cuffs and palms remain visible. NPC presets retain
their authored rest pose.

The initial integrated render passed its functional checks but measured 1,409
triangles with the largest travel kit. Simplifying the covered shoulder end
removed 12 triangles without removing hand detail. The final maximum is
**1,397**, beneath the existing 1,400 ceiling. Closed shoulder/hand ends and
mirrored fingertip boundaries were reviewed, and actual front/profile/rear
captures show no obvious holes or reversed facets.

The rear gallery also revealed a thin exposed scalp band: the nape hair shell
briefly passed inside the rear cheek/brow profile. Moving its two lower rear
points outward, and deepening the upper rear edge when a hat skips the middle
ring, restored a continuous hair silhouette without adding triangles. All
hairstyles and both body builds were captured again from the rear, including
the combined travel kit.

The editor now has **Full body / Face / Hands** controls. Hands frames both
cuffs and palms with the belt and lower tunic for context; drag/turn works in
all three views. Framing changes the camera, preserving the mesh, rotation,
appearance draft and equipment. It is transient UI state rather than a saved
character choice. Selecting the same view requests no additional render.

![Actual Face view](../.verification/keeper_details_20261002/view_default_face.png)

![Actual Hands view](../.verification/keeper_details_20261002/view_default_hands.png)

![Both body builds and all hairstyles](../.verification/keeper_details_20261002/gallery_front.png)

## Measured verification

Evidence: `.verification/keeper_details_20261002/`.

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

The default cropped-fringe keeper is **1,059 triangles**, versus 1,029 in the
preceding sculpt pass (30 more, about 2.9%). The largest equipped ordinary
keeper is 1,397; all sixteen body/hair/equipment combinations retain one
surface, six unit-scale bone rests, exact floor contact and the original carry
anchor. Warm iris/highlight colours and pupils survive mesh construction.
The 128 existing NPC appearance combinations still peak at **1,393** and retain
their two-draw RNG contract. The fixed staff/customer rendering fixture stays
at **65 draws / 68,706 primitives**; it does not sample the ordinary keeper.
The eight-keeper gallery separately reports **37 draws**, 18,830 primitives
in its front capture and 23,932 with the travelling kits.

The real Hands control enlarges projected cuffs/hands by at least twice their
full-body height, while keeping both inside the preview. Face still enlarges
the head by at least twice its full-body height and fills at least 35% of the
preview height. All three view controls, confirmation and the appropriate
character bounds fit at **1280×720, 1024×768, 1440×900 and 2560×1080**. All
requested sizes were honored. Headless verifies state/layout and explicitly
notes that projected render bounds require windowed execution.

Modern and legacy saves restore through separate engine processes; real
New-game/Keeper acceptance, cancellation and dirty-state checks pass. SHA-256
hashes of all five existing player save/backup files are unchanged. Current
test saves were removed on exit; three older September 28–29 test folders were
retained. Import, character, gallery and benchmark logs have no new errors or
warnings. The gameplay regression retains its intentional load-intent warning.

## Reproduce

Import first, then run from the project directory:

```powershell
$godot = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --import
& $godot --headless --path . res://dev/character_smoke.tscn
# Create the destination folder first when choosing another smoke prefix.
& $godot --path . res://dev/character_smoke.tscn -- shots=res://.verification/keeper_details_20261002/recheck
& $godot --path . res://dev/character_showcase.tscn -- res://.verification/keeper_details_20261002/gallery_recheck
& $godot --headless --path . res://dev/adventurer_mesh_smoke.tscn
& $godot --headless --path . res://dev/regressions.tscn
& $godot --headless --path . res://dev/polish_regressions.tscn
& $godot --headless --path . res://dev/house_smoke.tscn
& $godot --path . res://dev/pawn_benchmark.tscn -- res://.verification/keeper_details_20261002/benchmark_recheck.png
```

## Remaining art limits

The fingertips are one closed rigid group, not individually articulated
fingers. Elbows and knees remain rigid. The body and face still need further
sculpting and animation work to reach the supplied concept's quality. Hands
view helps inspect future equipment; it does not introduce held equipment or
a playable keeper. Android rendering/touch and live-game frame timing remain
unverified. No gameplay, balance, save-schema or ownership fields change.

Edited: `keeper_mesh.gd`, new `keeper_limb_art.gd`,
`character_preview.gd`, `character_creator.gd`, and `dev/character_smoke.gd`.
