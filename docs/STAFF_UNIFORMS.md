# Recognizable staff clothing — 2026-10-03

The following [adult-character reference pass](CHARACTER_REFERENCE_PASS.md)
supersedes the body/face proportions and measured triangle counts below, while
retaining these eight role outfits and their save/default rules.

The real tavern crew now wears job-specific hats and clothing cuts, extending
[the character wardrobe](CHARACTER_WARDROBE.md). Role colours retain their
existing definitions; silhouettes, sleeves and apron lengths provide additional
recognition from the management camera. These are original procedural meshes,
with no external assets or new licensing dependencies.

| Position | Identifying outfit |
|---|---|
| Waiter | Burgundy server cap with brass pin; burgundy waistcoat, pale sleeves and short waist apron |
| Busser | Olive work cap; short olive sleeves and short waist apron |
| Host | Navy dress cap with brass band; navy waistcoat, pale sleeves and copper pendant |
| Cook | Tall white cook's hat; pale short sleeves and full linen apron |
| Porter | Brown peaked work cap; brown waistcoat, pale sleeves and work gloves |
| Cleaner | Pale teal tied headscarf; grey short sleeves and full linen apron |
| Fisherman | Teal brimmed fishing hat; teal short sleeves and work gloves |
| Farmer | Wide straw hat with dark band; moss-green short sleeves, rolled trousers and work gloves |

![Actual staff gallery](../.verification/staff_uniforms_20261003/gallery_staff_front.png)

![Actual management-angle gallery](../.verification/staff_uniforms_20261003/gallery_staff_overhead.png)

![Backs and scarf/apron ties](../.verification/staff_uniforms_20261003/gallery_staff_back.png)

## How it works

Hiring and restoring a worker provide the saved job ID to the shared renderer.
`StaffUniforms` composes a default outfit from the existing clothing slots.
`KeeperWardrobeArt` renders six new hat cuts, a dyed house waistcoat and an
independent waist apron; hats have closed crowns and aprons retain rear ties.
The refined keeper face is shared by these modular crew outfits.
Waistcoats have small brass buttons, and the cleaner's headscarf has a diagonal
fold plus correctly facing rear ties. These final details were captured again
and checked through a save restart.

Role defaults remain visual context, rather than silently writing new equipment
or changing a saved appearance. A worker's existing saved role restores the
context without a new world-save field. Explicit equipped pieces override
matching defaults. Unavailable explicit cosmetics retain their saved ID and
render a safe fallback. A deliberately customized ordinary appearance keeps
its chosen clothes; the legacy all-rounder retains the original house uniform.

Changing a role updates the clothing while preserving identity, stored
appearance, position, animation, carried geometry and pawn randomness. It uses
the existing role priorities; fees, wages, allowed jobs and production rules
are unchanged.

Six hats plus the waistcoat and waist apron expand the free demo wardrobe from
15 to **23 items**. Try them through **Keeper → Clothing**, choose **Keep changes**,
then **Save**. Loading an existing owned list does not grant anything; opening
the editor offers the free items in its private draft, and cancellation leaves
the original profile unchanged. Staff uniforms require no purchases or supply
orders. A staff wardrobe editor and cosmetic acquisition remain future work.

## Measured checks

Evidence and full logs: `.verification/staff_uniforms_20261003/`.

- Eight jobs × two builds × four hairstyles × five skin tones: **320 job uniforms**
  keep one skinned surface and six unit-scale bones, exact floor/carry contracts
  and finite walking bounds. Their largest mesh is **1,109 triangles**.
- A further **128 full ten-slot outfits** cover both builds, all hairstyles,
  every covered hat, the new waistcoat, either apron, jewellery, gloves, cape
  and backpack. These peak at **1,353 triangles**, below the unchanged 1,400 cap.
  The older keeper travel-kit maximum remains 1,399.
- The real full-house crew spawns all eight uniforms. Role changes retain cargo,
  position, appearance, name and RNG. A separate engine process restores every
  exact mesh signature and saved appearance/equipment/role, including a worker
  with a custom outfit. Existing character tests also restore modern and
  pre-character snapshots with buildings, items and gold intact.
- All 23 demo items change the rendered geometry or colour appropriately. Real
  wardrobe controls, ownership, unknown IDs, cancellation and four PC window
  shapes pass headless and windowed checks. The existing 128 guest variants
  remain distinct and peak at 1,393 triangles; their two-draw RNG contract passes.
- Front, back, side and management-angle captures were inspected. A mirrored
  headscarf tie initially faced inward and was corrected before final captures.
  The eight-staff close gallery reports **37 draws / 18,508 rendered primitives**
  including the stage and individual plinths; this is not a live-tavern timing.
- A separate populated-tavern capture reaches four real seated guests at
  **126 game seconds**. The cook's white hat, server caps, work cap and cleaner's
  headscarf were inspected among actual guests at two management-camera distances.

![Actual populated tavern](../.verification/staff_uniforms_20261003/live_tavern_close.png)

The three-day full-house run was measured immediately before and after the
staff changes. Both produce **56 bread, 76 beer, 37 water, 63 fish and 72 wheat**,
with 32 planted plots and **3,743g**, exactly reconciled. Every printed item
balance has zero difference. The guided opening passes and restores 78 buildings,
823g and 13 served. Gameplay regressions and polish regressions also pass.

```text
STAFF UNIFORM SMOKE: 0 failure(s)
WARDROBE SMOKE: 0 failure(s)                 # headless and windowed
CHARACTER SMOKE: 0 failure(s)
CHARACTER SHOWCASE: 0 failure(s)
ADVENTURER MESH SMOKE: 0 failure(s)
REGRESSIONS PASS (0 failures)
POLISH REGRESSIONS: 0 failure(s)
SMOKE TEST PASS: no holes in the guided opening
RECONCILIATION PASS: days=3 gold=3743 expected=3743
```

The first uniform-restart fixture compared integer descriptors to JSON float
descriptors and reported a false mismatch despite identical rendered meshes.
It now compares both descriptors in the same JSON representation; mesh
signatures still have to match exactly. This was a fixture correction, not a
relaxed mesh/save requirement.

All five existing player save/backup hashes remain unchanged. Current sandbox
save directories are removed on exit; the three older September directories
are retained. Final logs have no new warnings or errors; the regression suite
retains its intentional missing-load-intent warning.

## Reproduce

Import first, then run from the project directory:

```powershell
$godot = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --import
& $godot --headless --path . res://dev/staff_uniform_smoke.tscn
& $godot --headless --path . res://dev/wardrobe_smoke.tscn
& $godot --path . res://dev/character_showcase.tscn -- res://.verification/staff_uniforms_20261003/gallery_recheck staff
& $godot --headless --path . res://dev/character_smoke.tscn
& $godot --headless --path . res://dev/adventurer_mesh_smoke.tscn
& $godot --headless --path . res://dev/regressions.tscn
& $godot --headless --path . res://dev/polish_regressions.tscn
& $godot --headless --path . res://dev/house_smoke.tscn
```

`staff_uniform_smoke` is included in `dev/run_tests.sh`. Showcase requires a
windowed renderer and creates its requested capture directory. All engine
fixtures sandbox saves with `begin_test_session`.

Android/touch and live-game GPU timing remain unverified. These uniforms improve
role recognition; there are no new job types, clothing stats, purchases or unlocks.
