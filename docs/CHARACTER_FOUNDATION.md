# Character foundation — 2026-10-01

**Later visual follow-up:** [CHARACTER_POLISH.md](CHARACTER_POLISH.md) records
the owner's requested slimmer proportions, fitted tunic, cuffs/boots/hair and
updated rendering totals. Measurements below describe the initial foundation.
The next [keeper/editor pass](CHARACTER_EDITOR_POLISH.md) adds the ordinary
sculpted body and verified Full body / Face views.

The first functional character slice in [PRODUCTION_ROADMAP.md](PRODUCTION_ROADMAP.md)
is implemented. New games open a small creator; existing games expose the same
saved person through **Keeper** in the HUD. Player, staff and guest meshes now
consume explicit appearance data through one rendering path.

This is a usable foundation, not approval of the reference-image art quality.
The ordinary traveler still needs stronger adult proportions, shoulder/torso
shaping and more natural animation. The personal character is a profile and
preview today; it is not a controllable world pawn or a free employee.

## Player-facing changes

- Separate character and tavern names; broad/slender builds, five skin tones,
  four hairstyles, hair/shirt/trouser/boot palettes, and local Randomize.
- One rotating live preview in a timber/plaster setting, with brass borders
  and green confirmation. Appearance choices scroll; confirmation stays visible.
- Back/Cancel edits a private draft. New-game scenario, slot, seed and tavern
  choices survive resizing and cancellation. Continue and Load bypass creation.
- Keeper reopens the saved character. It holds simulation and camera input,
  restores their previous state on close, and reminds the player to Save after
  accepting changes. An appearance edit counts as unsaved progress even paused.
- Four distinct hair masses, face/nose planes, tapered limbs, hands/thumbs,
  boots, and a simple open-collar tunic are shared with the NPC renderer.

Existing adventurer outfit families, dyes and staff uniforms remain available.
No recipe, wage, price, yield, arrival rule or unlock was changed. All new
character and preview geometry is original procedural work; no external asset
source or new licensing dependency was introduced.

## Data and rendering contract

`CharacterAppearance` is a versioned, explicit cosmetic descriptor. `PawnMesh`
separates the existing two-draw preset generation from pure `build_appearance`.
Appearance rebuilding preserves pawn RNG, role, guest archetype, movement,
pose and carried geometry. Guest behavior is restored independently before
`CustomerBrain.setup`; changing a visual family does not change preferences.

`CharacterProfile` stores person ID, name, appearance, owned cosmetic IDs and
equipped references. Slots are head, body, legs, feet, hands, neck, ring, cape
and backpack. Cape and backpack have separate geometry offsets and can coexist.
The original felt hat, travel cape and road pack exercise that contract.
They are test cosmetics, with no acquisition loop or automatic grants to new
players. A new owner owns the three starter clothing IDs only; Keeper shows
extra selectors when the corresponding item is already owned.

Saving adds an optional top-level `owner` field to the current format-2 snapshot.
Staff and active customer rows also save explicit appearance/equipment;
customers save their independent archetype. Old saves receive a stable default
owner and retain buildings, goods, crew and finances. Invalid optional cosmetics
fall back field by field. Unknown bounded cosmetic IDs retain ownership so a
missing catalog definition does not discard a possession.

This does not add persistent biographies or return-visit histories for every
traveler. Those remain in the later visitor milestone.

## Verification

Evidence: `.verification/characters_20260930/` (the work began September 30).
Import completed without warnings or errors. Final headless and windowed
`character_smoke` runs both ended **CHARACTER SMOKE: 0 failure(s)**. They exercise
real creator signals and scene transitions, modern and pre-character disk saves
in separate engine processes, dirty-state tracking, cancellation, global/pawn
RNG isolation, guest preferences and carried geometry.

Confirmation and retained draft choices were measured at 1280×720, 1024×768,
1440×900 and 2560×1080. The requested sizes were honored on this Windows display;
there were no clamped-shape skips. A measured wrapping bug initially pushed the
footer off screen at 720px and was corrected before the final run. The preview
renders on changes, rotation and resize rather than continuously rendering an
idle or hidden character.

Existing checks also passed: regressions, polish regressions, HUD layout smoke,
adventurer mesh smoke, opening smoke, save-resume smoke, save-UI smoke and the
three-day full-house run. The full house still produces **52 bread, 68 beer,
38 water, 68 fish and 72 wheat**, has 32 plots growing, and finishes with
**3,679g**, matching the previous result with goods/money reconciliation.
The regression suite's intentional load-intent warning remains; final
character/import/render logs have no warnings, errors or failed checks.

Front, back, side and stride contact sheets cover 24 production-seeded NPCs.
The tavern showcase initially captured zero seated guests because it used the
deliberately broken inherited level without a wash basin. Its fixture now buys
the same prep table, sink and shelf as the level test, and rejects an empty
seating capture. The corrected run captures **four real seated guests at 126
game seconds**. This is fixture repair, not a gameplay or level-design change.

All engine fixtures use `begin_test_session`. SHA-256 hashes of the five existing
player save/backup files are unchanged after the final runs. No session folders
from this pass remain; three older September 28–29 folders were left untouched.

## Rendering measurements and limits

All NPC styles remain one skinned mesh surface with six bones. The tested 128
style/variant combinations remain distinct, deterministic and within their
walking envelope. The largest measured NPC is **1,212 triangles**, below the
existing 1,400 ceiling.

The fixed 15-pawn benchmark reports **65 draw calls / 55,690 rendered primitives**.
The prior wardrobe-variant baseline was 65 / 48,514: draws are unchanged, but
rendered primitives increased **14.8%**. This includes rendering passes and is
not the source mesh triangle count.

Frozen full-tavern profile, 1280×720, GL Compatibility, Intel Arc 140V, uncapped
FPS and VSync disabled; two seconds warmup and five seconds sampling per count:

| Pawns | Median frame interval | p95 | Draws | Rendered primitives |
|---|---:|---:|---:|---:|
| 5 | 1.219 ms | 6.502 ms | 235 | 805,093 |
| 15 | 1.322 ms | 6.769 ms | 268 | 853,491 |
| 30 | 1.437 ms | 7.080 ms | 315 | 921,659 |

These are wall-clock rendered frame intervals including presentation/scheduling,
not GPU timings. Simulation is frozen; they do not establish live gameplay or
Android performance. Android touch and device rendering remain untested.

## Reproduce

From the project directory, always import first:

```powershell
$godot = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --import
& $godot --headless --path . res://dev/character_smoke.tscn
# Create the destination directory first for retained screenshots:
& $godot --path . res://dev/character_smoke.tscn -- shots=res://.verification/characters_20260930/recheck
& $godot --path . res://dev/tavern_profile.tscn -- res://.verification/characters_20260930/profile_recheck
```

The smoke suite is included in `dev/run_tests.sh`. Saved evidence is intentional;
temporary save slots are cleaned on normal engine exit.

## Next work

Continue refining one ordinary base traveler toward the supplied art target,
especially proportions and natural poses, before growing the wardrobe catalog.
Then proceed to roadmap order 2: the minimal beer opening and starter controls.
The reproduced shelf-filter lesson defect and manual/shared-station ownership
questions still need their own fixes. Purchasable wearable rewards belong in
the first complete ownership loop; outside exploration and direct avatar control
remain later work.
