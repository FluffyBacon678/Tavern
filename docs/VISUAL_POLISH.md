# RuneScape-inspired visual pass — 2026-09-22

**Landscape follow-up, 2026-09-29:** [Landscape polish](LANDSCAPE_POLISH.md)
records shallow riverbanks, animated shore foam, grass, wildflowers, rocks and
reeds, with rendering budgets and land-expansion checks.

**Atmosphere follow-up, 2026-09-28:** [World atmosphere](WORLD_ATMOSPHERE.md)
records day/night lighting, weather, fire, lanterns, wind, sky and river effects,
rendering limits, visual captures and the current six-day reconciliation.

**Furniture and goods follow-up, 2026-09-28:** [Furniture and goods polish](FURNITURE_ITEM_POLISH.md)
records the distinct prep bench and serving bar, joinery, oven arch, pottery,
captures and six-day reconciliation. Earlier measurements below are historical.

**Character follow-up, 2026-09-27:** [Adventurer customers](ADVENTURER_VISUALS.md)
records the six outfit families, new equipment, visual captures and measured
geometry cost. The earlier benchmark below describes the September 22 pass.

The art direction now uses warmer, quieter terrain, crafted medieval furniture
and readable low-poly people. The 3D artwork remains original procedural
geometry. No Jagex or rimshare assets were used.

## Visible changes

- Olive meadow patches, warm dirt, teal water and darker forest canopies.
  Reduced per-tile colour noise; broader conifers and clustered broadleaf trees.
- Oak plank floors, plaster infill and timber braces, trestle tables, slatted
  chairs, hooped barrels, a brewing rim/paddle and a masonry oven with embers.
  Raised wall caps eliminate coplanar flickering. Floor grain is restrained to
  keep the room readable at management zoom.
- Broader tunics, staff aprons, travelling mantles, belts, boots, hair and faces.
  Small goods have clearer sacks, bread, mugs, foam and handles.
- Warm ambient fill and softer shadows reveal workers indoors.
- Camera-facing wall cutaways, switchable to full walls. Only instance
  transforms change; walls still block movement and doors remain passable.
- A framed header with stock icons, a quieter ledger on demand, and a compact
  current-objective card with an expandable checklist. Existing Save, inspection,
  objectives and subsequent staff/reputation additions are preserved.
- Production now fits below the toolbar, scrolls internally and keeps Close
  visible. Build/Production and ledger/inspection avoid covering one another.

## Free assets and attribution

Three SVGs from [game-icons.net](https://game-icons.net/) are used for the HUD:
Beer stein by Lorc; Bread and Coins by Delapouite. They are CC BY 3.0, displayed
with a gold tint. Their source links and licence are recorded in
`assets/prototype/ui/game_icons/ATTRIBUTION.md` and the tavern crest tooltip.

## Verification and limits

- Godot 4.7.2 headless editor parse is clean on the latest workspace.
- Screenshots checked at 1280×720: tavern, low free-camera angle, production
  panel and the unchanged 2D menu. Current captures:
  `.verification/visual_latest.png` and `.verification/production_visual.png`.
- Fifteen richer pawns still measured **65 draw calls**, versus 352 before the
  earlier batching refactor. Submitted primitives increased from 7,930 to
  22,046 in this isolated lit/shadowed scene; added geometry is a real tradeoff.
- Cutaway test: **189 assertions, zero failures**. Four camera directions plus
  off/on restore preserved 58 placements, 144 occupancy/navigation cells, three
  exact routes, building value, furniture and blueprints. Real OpenGL rendering
  was required because Godot's headless renderer returns dummy mesh transforms.
- The visual pass's three-day run reconciled all nine item types and gold
  (348g expected and actual). New gameplay work was added during the pass;
  that result is recorded evidence, not a balance comparison with newer runs.
- Rechecked the expanded demo afterward: three completed days, all item
  differences zero, **433g actual = expected**, including six yeast and two
  dirty dishes in transit. Evidence: `.verification/visual_latest_economy.log`.
- Android hardware performance remains unverified. The render benchmark is a
  controlled pawn scene, not the whole tavern.

Gameplay values were not retuned by this visual pass. The newer delivery yard,
cart, sink, reputation, staff UI and hands-on work are separate ongoing project
changes and were preserved rather than replaced with the older snapshot.
