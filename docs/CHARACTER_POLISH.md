# Character polish — 2026-10-01

**Later keeper/editor refinement:** [CHARACTER_EDITOR_POLISH.md](CHARACTER_EDITOR_POLISH.md)
records the continuous ordinary-body sculpt, swept crown and actual Full body /
Face framing checks. The measurements below describe the preceding passes.

## Face, hair and wearable-fit follow-up

The next pass keeps the slimmer shared silhouette and refines the original
procedural traveler. Eyes, brows and mouth now follow the actual face planes
instead of projecting as little boxes. The jaw narrows toward the chin, the
nose projects less, and the forehead/cheeks use quieter broad planes. Hair has
lower crests and broader fringe locks; ordinary cloth sleeves have a narrower
shoulder cap and a tapered neck. Open hats expose the ears consistently.

The close-up gallery revealed a visible gap below the travelling hat. Felt,
feathered, pointed and paper hats now sit lower around the covered hair. The
backpack also sits closer to the cape while retaining clearance at its bottom.
Creator lighting is gentler so the face and cream tunic retain their shading.
These changes also apply to staff and guests through the shared pawn builder.
No save fields, gear ownership, recipes, jobs or economic values change.

A real rendering bug was measured during this pass: the mesh builder's normal
area cutoff silently discarded the tiny pupil triangles. A new character-smoke
assertion failed before the correction (`pupil_reproduction.txt`, exit 1) and
passes afterward. Facial ink alone opts into a finer cutoff; the existing
terrain/prop cutoff and clockwise emission are unchanged. Collapsed faces are
still rejected. This prevents the new small pupils, brows and mouth from
disappearing without a parse error.

### Final measurements

Evidence: `.verification/character_detail_20261001/`.

```text
ADVENTURER MESH SMOKE: 0 failure(s)
CHARACTER SMOKE: 0 failure(s)
CHARACTER SHOWCASE: 0 failure(s)
REGRESSIONS PASS (0 failures)
POLISH REGRESSIONS: 0 failure(s)
RECONCILIATION PASS: days=3 gold=3679 expected=3679
HOUSE SMOKE PASS: one of everything, three days traded; made bread 52, beer 68, water 38, fish 68, wheat 72; 32 plots growing; 3679g
PAWN_BENCHMARK count=15 draw_calls=65 primitives=68706
```

The 128 production-seeded NPC looks remain distinct, deterministic, finite and
one surface/six bones. The maximum is **1,393 triangles**, within the existing
1,400 ceiling but with little headroom for more geometry. The fixed benchmark
retains **65 draw calls**, with **68,706 rendered primitives** versus this
pass's 63,690 baseline (**7.9% more**). Those totals include rendering passes;
they do not establish live-game frame timing or Android performance.

The windowed character suite verifies modern/legacy saves in separate engine
processes, creator actions, cosmetic RNG isolation, carry geometry and layout
at four PC shapes. The new gallery directly renders both builds with all four
hair styles and varied existing palettes, then their combined hat/cape/pack.
Its requested 1600×1100 window was honored. NPC captures cover front, back,
side and stride; the repaired live level again has four seated guests at 126
game seconds, with 9g collected and no lost customers.

Final import, character, mesh and capture logs have no warnings or errors.
The gameplay regressions retain their deliberate load-intent warning. All five
player save/backup SHA-256 hashes remain unchanged. Sandboxed session saves are
cleaned on exit; only the requested evidence captures/logs are retained.
This remains an incremental procedural-art pass toward the supplied sculpted
reference; Android rendering and touch remain untested.

![Current body and hair gallery](../.verification/character_detail_20261001/final_showcase_front.png)

![Current combined travelling kit](../.verification/character_detail_20261001/final_showcase_travel_kit.png)

### Reproduce this pass

From the project directory:

```powershell
$godot = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --import
& $godot --headless --path . res://dev/character_smoke.tscn
& $godot --headless --path . res://dev/adventurer_mesh_smoke.tscn
# Windowed only; the gallery creates the requested capture directory.
& $godot --path . res://dev/character_showcase.tscn -- res://.verification/character_detail_20261001/recheck
```

Changed files: `src/world/pawn/pawn_mesh.gd`,
`src/ui/character/character_preview.gd`, `src/core/mesh_builder.gd`,
`dev/character_smoke.gd`, and the new `dev/character_showcase.gd/.tscn`.

## Earlier slimmer silhouette pass

The owner's requested follow-up to [CHARACTER_FOUNDATION.md](CHARACTER_FOUNDATION.md):
a little slimmer, closer to a classic RuneScape-inspired fantasy silhouette.
This changes original procedural art and creator framing only.

- Torso width is 10% narrower for the broad build and about 8% narrower for
  the slender build. Depth, limbs and heads are adjusted to remain proportional.
- The ordinary tunic has a fitted waist, shorter hem and sloped shoulders;
  its belt follows the new cut instead of floating outside the waist.
- Narrower, faceted cuffs replace square cuffs. Boots have smaller bevelled
  toes and quieter soles. The hair at the nape tapers toward the neck.
- The creator camera moves slightly closer to make the character easier to read.
- All staff and guest outfits use the same slimmer rendering path. Gear is
  baked with the corresponding body/head scales, so hat/cape/pack fit follows it.

Limb lengths, hip/shoulder heights, floor contact and carry-anchor coordinates
are retained. The ordinary shoulder spacing follows its tailored upper torso.
No appearance/save fields, cosmetic ownership, RNG consumption, gameplay,
recipes, jobs or economic values were changed.

### Measured verification

Evidence: `.verification/character_slim_20261001/`. Import and final character,
mesh, render and polish logs have no new warnings, errors or failed checks.

```text
ADVENTURER MESH SMOKE: 0 failure(s)
CHARACTER SMOKE: 0 failure(s)
REGRESSIONS PASS (0 failures)
POLISH REGRESSIONS: 0 failure(s)
PAWN_BENCHMARK count=15 draw_calls=65 primitives=63690
```

The character suite exercises the real new-game and Keeper controls, unchanged
RNG, carry geometry, save/restart and older-save fallback, plus confirmation and
retained choices at 1280×720, 1024×768, 1440×900 and 2560×1080. NPC mesh checks
cover all 128 distinct style/variant combinations, one surface/six bones and
finite geometry; the largest NPC is **1,332 triangles**, below the 1,400 ceiling.

Actual renderer contact sheets cover front, back, side and stride poses.
The repaired live-tavern fixture again captures **four seated guests at 126
game seconds**. Front/rear creator and travel-kit captures show no obvious
holes or equipment intersection; a separate read-only art review agrees.
All fixtures sandbox saves. The five player save/backup hashes are unchanged.

The fixed 15-pawn benchmark increased from **55,690 to 63,690 rendered primitives**
(**14.4%**) while retaining **65 draw calls**. The added closed bevels cost
geometry; rendered primitive totals include passes rather than just source
mesh triangles. This run does not establish Android or live-game frame timings.
The new shape is a modest refinement, not completion of the sculpted art target.

![Current creator](../.verification/character_slim_20261001/final_starter_front.png)

![Original creator before this pass](../.verification/character_slim_20261001/before_front.png)

### Files

- `src/world/pawn/pawn_mesh.gd`: shared proportions and shape changes.
- `src/ui/character/character_preview.gd`: closer camera framing.

Use the commands in the foundation report with an output prefix under this
evidence directory to reproduce the character test and rendered captures.
