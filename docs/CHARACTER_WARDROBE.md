# Character wardrobe — 2026-10-03

The subsequent [adult-character reference pass](CHARACTER_REFERENCE_PASS.md)
updates body proportions, faces and geometry counts while preserving this
wardrobe's slots, items, ownership and editing behaviour.

**Later staff follow-up:** [STAFF_UNIFORMS.md](STAFF_UNIFORMS.md) applies job
uniforms to the real crew and adds eight garments, expanding the demo wardrobe
to 23 items. The fifteen-item measurements below describe the preceding pass.

The keeper now has a usable **Clothing** tab with ten independent slots and
fifteen original demo cosmetics. This follows [the keeper detail pass](KEEPER_DETAIL_POLISH.md):
almond-shaped eyes and a more angular face accompany tall cook hats,
short sleeves, separate linen aprons and practical travelling clothes.
The supplied classic cook references guide the silhouettes; all meshes and
slot icons are original procedural work, with no external asset dependency.

## Try it

Open **Keeper → Clothing**, press a slot and choose its item. A shirt and apron
are separate choices; cape and backpack also coexist. Shirt, trouser and boot
palettes remain available. **None** removes that equipped reference, with safe
base clothing underneath. Use **Full body / Face / Hands**, and drag to turn.
Choose **Keep changes**, then **Save** in the tavern to persist the outfit.
New-game creation offers the same wardrobe before starting the selected tavern.

| Slot | Available original items |
|---|---|
| Head | Felt travelling hat; cook's hat |
| Shirt | Linen shirt; short-sleeved shirt; leather vest |
| Apron / outerwear | Linen apron |
| Trousers | Traveller's trousers; rolled trousers |
| Footwear | Leather boots; work shoes |
| Gloves | Work gloves |
| Neck | Copper pendant |
| Ring | Copper ring |
| Cape | Traveller's cape |
| Backpack | Road pack |

All fifteen are free demo cosmetics. A new keeper starts wearing only the
original shirt, trousers and boots. Loading an existing ownership list does
not add or equip anything. Opening the editor grants the demo items to its
private draft; accepting adopts that ownership, while cancellation leaves the
original person and disk save unchanged. Purchases, stats and unlocks remain
future gameplay work.

The slot grid uses ten cached SVG silhouettes. Selecting a slot outlines it
in brass, equipped slots have green backgrounds, and tooltips name the current
item. Appearance and Clothing share a pinned character name and confirmation;
editing either tab preserves the other tab's choices and preview angle.

The face follow-up adds thin upper eyelids, taller warm irises, brows that keep
contrast with pale hair, a short flat-ended nose bridge, a narrower chin and
smaller ears. The mouth is shorter and less sharply V-shaped. Face details
follow the skin surface, including the nose roots; no appearance or save fields
are added. Light/dark skin and front/profile captures were inspected.

![Actual refined face](../.verification/wardrobe_20261003/character_default_face.png)

![Actual wardrobe editor](../.verification/wardrobe_20261003/editor_cook_front.png)

![Actual wardrobe gallery](../.verification/wardrobe_20261003/gallery_wardrobe_front.png)

![Actual equipped Hands view](../.verification/wardrobe_20261003/editor_cook_hands.png)

## Rendering and persistence

`WardrobeCatalog` supplies stable item IDs, slot assignments and display names.
`KeeperWardrobeArt` authors the modular cuts; `PawnMesh` applies them through
the shared owner/staff/guest renderer. Choosing explicit clothing does not
rewrite the saved appearance family, staff role or guest archetype. Existing
NPC presets without modular equipment retain their costumes and two-draw
generation contract. This does not automatically redress the existing crew
or add an NPC wardrobe editor.

The apron has a bib, pleated skirt, straps and rear ties. Short sleeves, rolled
trousers, low shoes and vest replace their corresponding contours rather than
stacking complete garments. Gloves recolour the shaped hands; the ring belongs
to one hand. The copper pendant cord sits above the apron bib. Ordinary torso
envelopes remain consistent when small jewellery is added. Tall hats expand
Full body and Face framing; Hands accounts for the higher short-sleeve cuffs.

The world save format remains version 2 and the character descriptor remains
version 1. The additional `outer` slot is optional. Known wrong-slot or unowned
equipment is rejected; bounded unknown owned IDs survive saves and show an
unavailable selection with a safe rendered fallback.

## Measured verification

Evidence and complete logs: `.verification/wardrobe_20261003/`.

- All fifteen garments visibly change geometry or colour against an appropriate
  counterfactual. Ninety-six fully equipped body/hair/garment combinations retain
  one skinned surface, six unit-scale bones, finite walking bounds, exact floor
  contact and the existing carry anchor. Their maximum is **1,353 triangles**,
  below the unchanged 1,400 ceiling.
- Both builds of all seven staff/adventurer families accept the complete
  ten-slot outfit without changing their saved family. Jewellery preserves the
  underlying body envelope and unrelated bones.
- The default cropped-fringe keeper is **1,061 triangles** (previously 1,059).
  The older felt-hat/cape/backpack travel-kit fixture peaks at **1,399**; this
  differs from the full modular outfit fixture above. Existing 128 NPC variants
  still peak at **1,393**. The fixed fifteen-pawn benchmark remains
  **65 draw calls / 68,706 rendered primitives**.
- Real Clothing/slot/dropdown controls equip all ten slots, remove items, retain
  unknown keepsakes, reject invalid choices and preserve the private draft.
  Idle previews do not rebuild or redraw.
- Windowed checks measured all ten slot buttons, selector, confirmation and
  framing controls at **1280×720, 1024×768, 1440×900 and 2560×1080**. All requested
  sizes were honored. Fully equipped Full body, complete tall-hat Face and both
  actual cuffs/palms fit; Face and Hands enlarge their subjects at least twice
  their full-body height. Headless verifies logical state/layout and explicitly
  reports that projected render bounds require the windowed run.
- Separate engine processes restore every equipped slot for owner, staff and
  active guest; modern and pre-character saves retain buildings, items and gold.
  Actual New-game/Keeper confirmation and cancellation also pass.

Final suite results:

```text
WARDROBE SMOKE: 0 failure(s)                # headless and windowed
CHARACTER SMOKE: 0 failure(s)               # headless and windowed
CHARACTER SHOWCASE: 0 failure(s)
ADVENTURER MESH SMOKE: 0 failure(s)
REGRESSIONS PASS (0 failures)
POLISH REGRESSIONS: 0 failure(s)
RECONCILIATION PASS: days=3 gold=3743 expected=3743
HOUSE SMOKE PASS: one of everything, three days traded; made bread 56, beer 76, water 37, fish 63, wheat 72; 32 plots growing; 3743g
PAWN_BENCHMARK count=15 draw_calls=65 primitives=68706
```

The guided-opening smoke also passes and reloads 78 buildings with 823g. The
three-day totals above are this run's measured result, not an assertion that
the historical October 2 totals were reproduced. No recipes, prices, wages,
production rates or customer rules were edited in this pass.

SHA-256 hashes of all five existing player save/backup files remain unchanged.
Current test saves are removed on exit; three older September test directories
were retained. Import, wardrobe, character, gallery and benchmark logs contain
no new errors or warnings. The gameplay regression retains its intentional
load-intent warning.

## Reproduce

Import first; run from the project directory:

```powershell
$godot = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --import
& $godot --headless --path . res://dev/wardrobe_smoke.tscn
# Create the destination folder before requesting screenshots.
& $godot --path . res://dev/wardrobe_smoke.tscn -- shots=res://.verification/wardrobe_20261003/recheck
& $godot --headless --path . res://dev/character_smoke.tscn
& $godot --path . res://dev/character_smoke.tscn
& $godot --path . res://dev/character_showcase.tscn -- res://.verification/wardrobe_20261003/gallery_recheck
& $godot --headless --path . res://dev/adventurer_mesh_smoke.tscn
& $godot --headless --path . res://dev/regressions.tscn
& $godot --headless --path . res://dev/polish_regressions.tscn
& $godot --headless --path . res://dev/house_smoke.tscn
```

`wardrobe_smoke` is included in `dev/run_tests.sh`. Captures are intentionally
retained; test saves use `begin_test_session` and never target player slots.

## Remaining limits

The keeper is still a saved profile and preview, not a controllable world pawn.
Hands, elbows and knees remain rigid; fingers are not individually articulated.
The largest older travel-kit combination has only one triangle of headroom;
further geometry needs simplification elsewhere rather than raising the budget.
An acquisition/reward loop, additional clothing families and NPC wardrobe UI
are future work. Android rendering and touch have not been verified. These
captures show the current original art, not completion of the full reference
quality or animation gate.
