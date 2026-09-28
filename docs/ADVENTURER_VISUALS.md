# Adventurer customers — 27 September 2026

## Colour and wardrobe variants — 28 September 2026

The latest pass expands the 32 base customer styles to **128 deterministic
appearances**, with four variants per style. `pawn_wardrobe.gd` holds eight
coordinated dye palettes (cobalt, plum, teal, saffron, wine, moss, ember and
indigo), leather shades and family-specific outfit choices. Warriors retain
their metal tiers; cloth, tabards and heraldry carry their colour variation.
Staff retain the existing role-coloured uniforms.

- Alternate hoods, open/closed helmets, feather hats and jewelled circlets;
  tied hair, beard variation, and round or pointed staff jewels.
- Diamond, chevron, sun and stripe shield devices; cape stripes and side bands.
- Matching scarf, bedroll, arrow-fletching, gem and book-cover accents.
- Split tabards leave belts and buckles visible. Books have proper covers,
  recessed pages, leather straps and small gold seals.

The extra variant is derived from the RNG state after the existing two draws,
without advancing it. No gameplay, prices, items or save-format changes were
made. All art is original procedural geometry; no external assets were added.

Import, `adventurer_mesh_smoke`, `regressions`, `polish_regressions` and
`smoke_test` passed. The mesh check reaches all 128 combinations through real
production seeds, verifies 128 distinct geometry/colour signatures and exact
repeatability, and checks unchanged RNG state, staff colours, bounds, one
surface and six bones. The largest character is **1,100 triangles** (ceiling
1,400). The fixed 15-pawn benchmark remains **65 draw calls**; submitted
primitives increased **47,470 → 48,514**, about **2.2%**. Android remains
unmeasured. Only the existing intentional save-fixture warnings appeared.

Front, rear, side and stride views of 24 representative variants were inspected,
plus real guests in The Wayfarer's Rest at 128 game seconds. Evidence and logs:
`.verification/adventurer_variants_20260928/`. Use the showcase's `variants`
argument for the larger contact sheet, or `tavern` for the live level. The
earlier measurements below describe previous passes.

## Follow-up polish — 28 September 2026

Fresh renders of the current build were inspected from front, rear, side and
mid-stride, followed by the live tavern. This pass:

- Replaces box-shaped chain hoods with rounded crowns and hanging mail, with
  enough clearance to prevent skin showing through the diagonal facets.
- Replaces the delver's horizontal chest bars with staggered mail links.
- Adds visible leather equipment slings and buckles to rangers and staff bearers.
- Closes the bedroll ends, adds rolled-cloth rings, and closes hat undersides.
- Fits shields to the cape's slope, eliminating the obvious gap in side view.
- Tones down bronze, iron and steel so their facets survive the warm lighting.
- Preserves the newer staff-role waistcoat colours; the mesh smoke now checks
  that custom uniform colours survive the build.

The capture fixture now includes a side view and waits for four actual seated
guests (bounded to half a game day), rather than assuming 65 seconds still
represents a busy room after day-length tuning. In this run it captured at
128 game seconds. It does not alter arrivals, seating or inventory.

Import, the character mesh smoke, `regressions`, `polish_regressions` and the
guided opening smoke passed. All 32 customer appearances retain one surface,
six bones and the original RNG consumption. The largest mesh remains 1,040
triangles. The fixed 15-pawn benchmark remains **65 draw calls**; submitted
primitives rose from the previous pass's **46,866 to 47,470** (about 1.3%).
Android hardware remains untested. Only the regression suite's intentional
save-fixture warnings appeared; test-save directories were cleaned up.

Current evidence: `.verification/adventurers_20260928/after_front.png`,
`after_back.png`, `after_side.png`, `after_stride.png`, `after_tavern_close.png`
and the neighbouring logs. The September 27 results below remain historical.

The character pass keeps the original low-poly, vertex-coloured art direction,
with a stronger roadside-adventurer identity. All geometry is authored in the
project; no RuneScape/Jagex, rimshare or other external assets were imported.

## What changed

- Six cosmetic outfit families: plate warriors, mages, rangers, chainmail
  delvers, feather-hatted duelists and wandering sun scholars. The original
  32 deterministic appearance combinations and occasional festive crown remain.
- Faceted breastplates, layered shoulder armour, knee plates, open/closed
  helmets, properly pointed shields with original diamond heraldry and
  sheathed swords.
- Folded, trimmed capes; ankle-length robes, bent pointed hats, crystal-tipped
  traveling staffs, books, belt pouches and small bottles.
- Leather ranger jerkins, lacing, open peaked hoods, curved bows, fletched
  arrows, packs and strapped bedrolls. Clothing colours vary within families.
- Eyes, brows, ears, shaped hair and tapered beards. Skull geometry stays
  underneath the hair and hood at the high management camera angle.
- Staff retain their burgundy-and-cream house uniform for quick recognition.

`src/world/pawn/pawn_mesh.gd` owns outfit selection and the six-bone humanoid.
`src/world/pawn/pawn_equipment.gd` builds cosmetic equipment into the existing
torso mesh. Equipment has no inventory, combat or simulation meaning. No
additional materials, accessory nodes or runtime texture generation are used.
The appearance builder consumes the same two RNG draws as before; save format,
movement, jobs, recipes, prices and customer decisions are unchanged.

## Measured verification

- Godot 4.7.2 import: clean. Front, back and mid-stride contact sheets inspected,
  plus actual guests 65 game-seconds into The Wayfarer's Rest at two zooms.
- `adventurer_mesh_smoke`: all 32 customer combinations covered; RNG state
  preserved across 512 staff/customer builds; one surface and six bones each;
  finite geometry inside the character envelope. Largest mesh: **1,040 triangles**.
- Existing `regressions`, `polish_regressions` and guided `smoke_test`: pass.
- `level_smoke -- playedonly`: six days passed, all nine item differences zero;
  **1,190g actual = 1,190g expected**, with 107 patrons served across the run.
- Fixed 15-pawn OpenGL benchmark: **65 draw calls before and after**. Submitted
  primitives (including shadow passes) increased **22,274 → 46,866**. This is
  extra geometry, not a free performance improvement. Android hardware has
  not been measured.

Evidence is in `.verification/adventurers_20260927/`: `before_front.png`,
`after_front.png`, `after_back.png`, `after_stride.png`, `after_tavern.png`,
`after_tavern_close.png`, plus test and benchmark output. Initial sandboxed
baseline captures logged OS log/certificate-access errors; subsequent elevated
render and validation runs were clean apart from the regression suite's
intentional invalid-save warnings.

The repeatable capture and mesh-check commands are listed in
`docs/gameplay_testing_handoff.md`. Both new dev scenes isolate saves through
`GameState.begin_test_session()`.
