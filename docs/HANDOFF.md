# Handoff — Mobile Tavern

**Owner vision clarification, 2026-09-30:** read
[`CURRENT_GAME_VISION.md`](CURRENT_GAME_VISION.md) before planning gameplay.
The primary direction is a minimal beer business, optional building, cozy
collecting/decorating, and earning toward products, methods and interesting
adventurers. The full-house start is for testing; hard service/cash deadlines
are not the defining contract of the main cozy mode. This supersedes conflicting
older scope and opening assumptions below.

**Production roadmap, 2026-09-30:** see
[`PRODUCTION_ROADMAP.md`](PRODUCTION_ROADMAP.md) for current readiness, shared
character creation first, art direction from the owner's reference images,
and the ordered demo milestones. This is a plan, not implemented gameplay.

**Character foundation, 2026-10-01:** see
[`CHARACTER_FOUNDATION.md`](CHARACTER_FOUNDATION.md) for the implemented creator,
Keeper profile, shared player/NPC appearance path and save compatibility.
The functional slice is verified; reference art quality and later demo
milestones remain open. New games enter the creator before the world; Continue
and Load still enter the saved world directly.

**Visual follow-up, 2026-09-22:** see [VISUAL_POLISH.md](VISUAL_POLISH.md).
Later gameplay work has continued alongside it; the older line counts and
remaining-work lists below are historical, not a current inventory.

**Update, 2026-09-21:** Tier 1 has been implemented and measured. Read
[`POLISH_REPORT.md`](POLISH_REPORT.md) for current evidence, commands and limits.
`world_3d.gd` is now 364 lines; `WorldHUD` and `WorldBootstrap` own the extracted
responsibilities, and scenario hooks live in `dev/world_scenario.gd`. The
historical baseline below is retained for context; Tier 2/3 remain outstanding.

You are taking over a working prototype. **Your job is to review, fix and polish
what is here — not to add new milestones.** The gameplay loop already runs end
to end; it needs hardening, not extending.

Read this whole file before touching code. Then read
`docs/medieval_tavern_game_design_notes.txt`, which is the actual spec. Section
numbers referenced below (§8, §21…) point into it.

---

## 1. What this is

A medieval tavern management / colony sim for **PC and Android**, in
**Godot 4.7.2**. Part RimWorld / Prison Architect, part Papa's Pizzeria.

- **Art direction:** OSRS-style low-poly 3D world, 2D menus. All geometry is
  generated procedurally in code — there are no model or texture files.
- **Engine binary:** `../_tools/godot/Godot_v4.7.2-stable_win64.exe`
  (and `..._console.exe` for stdout). Not on PATH.
- **Size:** ~7,500 lines across 53 GDScript/shader files.

---

## 2. What works, verified

Every claim below was measured, not eyeballed.

| Milestone | State | Evidence |
|---|---|---|
| Menu, settings, routing, audio | ✅ | Clean boot, no stderr |
| Procedural forest backdrop (2D) | ✅ | Ported from a canvas wallpaper |
| 3D terrain, trees, water, camera | ✅ | 60fps, ~150k tris, 350ms generation |
| Construction, blueprints, demolish | ✅ | 199 pieces placed, 0 refused |
| Pawns + A* pathfinding | ✅ | 5/5 routed through a single door |
| Job system (construct/haul/cook/serve) | ✅ | 199 blueprints built, queue drained to 0 |
| Physical economy | ✅ | Books reconcile exactly (see §5) |
| Customers, seating, serving, tips | ✅ | 15 served, 1 lost, +147g in one day |
| Day cycle, wages, profit/loss | ✅ | Four consecutive days measured |
| Production bills (§21) | ✅ | Beer capped at exactly its target |

**The loop, unattended:** order supplies → cart unloads → haulers shelve it →
cook fetches flour/water/yeast → dough → carried to oven → bread; brewer makes
beer → bills cap production → customers arrive on a footfall curve → take a
chair beside a table → order only what is in stock → waiter delivers it to the
table → they eat, pay, tip by promptness, leave → wages charged at close, books
ruled off.

Everything is physical. Nothing is a counter being incremented.

---

## 3. Architecture

```
src/
  autoload/     GameSettings, GameState, AudioDirector, SceneRouter
  core/         value_noise, raster (2D software), mesh_builder (3D), atlas_cache
  ui/           tavern_theme, main_menu, settings, build_bar,
                production_panel, day_summary
  world/
    tree_species.gd        species table shared by BOTH renderers
    forest/                2D menu backdrop only (atlases, terrain grid, shaders)
    world3d/               world_3d.gd, terrain_mesh_builder, tree_mesh_library,
                           camera_rig
    build/                 building_def/catalog/mesh_library, build_grid,
                           build_controller
    items/                 item_def/catalog/mesh_library, item_world, recipe,
                           recipe_catalog, bill_book
    jobs/                  work_type, job, job_board, worker, job_generator
    pawn/                  pawn, pawn_mesh, nav_grid
    customers/             seating, customer_brain, customer_director
    sim/                   day_clock, ledger
scenes/         boot.gd, _screenshot_harness.gd (dev tool)
```

### Key design decisions — please preserve these

- **A pawn is generic.** `Pawn` walks, turns and carries. A *worker* is a Pawn
  with a `Worker` child; a *customer* is a Pawn with a `CustomerBrain` child.
  The design notes require this (§14). Do not fold role logic into `Pawn`.
- **Content is data, not code.** `BuildingCatalog`, `ItemCatalog`,
  `RecipeCatalog` are lists of Resources. There is no `BakeBread()` — §28
  forbids it. Adding content should never mean adding a branch.
- **Definitions never name a mesh or texture.** They name a `shape` enum; a mesh
  library picks the builder. That seam is how prototype art gets replaced.
- **`JobGenerator` derives all work from world state** on a timer. Nothing else
  posts hauling or production jobs, so a failed or cancelled job is simply
  re-derived next scan. Keep it that way — do not add event-driven job posting.
- **All money routes through `Ledger`.** Nothing may touch `GameState.gold`
  directly, or it will not appear in the end-of-day reckoning.
- **`BuildGrid` answers questions**, e.g. `blocks_movement(tile)`. Pathfinding
  and room detection consume that, not the meshes.

---

## 4. Conventions and traps

**Indentation is tabs.** Mixing spaces is a parse error.

**Comments explain *why*, not *what*.** The existing comments are load-bearing
documentation of non-obvious decisions. Match that standard; do not strip them.

### Three traps that have already cost time

1. **Godot culls by winding, and treats *clockwise* as front-facing.**
   `MeshBuilder.add_tri()` takes counter-clockwise vertices (so the computed
   normal is honestly outward) and **emits them reversed**. Get this wrong and a
   ground plane silently vanishes from above while closed shapes still look
   fine — it reads as "terrain didn't generate".

2. **Goods must never silently vanish.** `ItemWorld.add()` returns 0 when a tile
   holds a different kind. Two call sites once treated that as success and ate
   six yeast per run, invisibly. **Every path that puts an item down must go
   through `ItemWorld.place_near()`**, which spreads outward and warns.

3. **`set_anchors_preset()` preserves the control's current rect.** On a freshly
   constructed Control that rect is 0×0, so it anchors full-screen and stays
   zero-sized. Use `set_anchors_and_offsets_preset()`.

Also: **bump `AtlasCache.VERSION` if you change any 2D sprite draw function**,
or players keep seeing cached sprites from the previous build.

---

## 5. How to verify your work

This workflow caught every bug listed above. Please use it rather than
reasoning about correctness.

**Parse check** (fast, run after every change):

```bash
"../_tools/godot/Godot_v4.7.2-stable_win64_console.exe" --headless --editor --quit --path .
```

**Visual / behavioural check.** `scenes/_screenshot_harness.tscn` loads a scene,
poses it, waits, writes a PNG and quits:

```bash
"../_tools/godot/Godot_v4.7.2-stable_win64_console.exe" --path . \
  res://scenes/_screenshot_harness.tscn --resolution 1280x720 -- \
  res://src/world/world3d/world_3d.tscn out.png 180 \
  "seed=12345,demo=tavern,economy=on,restock=on,daylength=80,autodays=2,report=175,distance=17,pitch=52,yaw=45"
```

Options: `demo=tavern|blueprint`, `economy=on`, `restock=on`, `pathtest=on`,
`report=<seconds>`, `daylength=<seconds>`, `autodays=<n>`, `buildbar=on`,
`camera=locked|free`, `distance`, `pitch`, `yaw`.

**Measure, do not eyeball.** `report=N` now checks delivered + made − recipe
inputs − customer consumption = ground + carried, plus gold versus the ledger.
It exits nonzero on a discrepancy. Reports must precede the screenshot timeout.
The original ground-stock report is what exposed the vanishing
goods — a screenshot looked perfect while the numbers did not add up. When you
change anything touching items, economy or jobs, reconcile the books.

---

## 6. What to work on

Ordered by value. **Polish and correctness only — no new milestones.**

### Tier 1 — structural

**Completed in the current pass; descriptions below record the original issues.**

1. **`world_3d.gd` is 1,061 lines and is a god object.** It owns terrain, forest,
   HUD, input, camera, economy wiring, the demo/test harness and day handling.
   Split it — a `WorldHUD`, a `WorldBootstrap`, and move the scripted
   `build_demo_tavern` / `run_path_test` / `_report_after` test hooks out of
   shipping code. This is the single highest-value refactor.
2. **Draw calls scale badly.** Each pawn is six separate `MeshInstance3D` limbs
   (~10 draw calls each), so ~15 pawns plus items pushes past 500. This matters
   because **Android is the target and has never been tested**. Merge limbs, or
   instance them.
3. **Dev-only code ships.** `_screenshot_harness`, `build_demo_tavern`,
   `run_path_test`, `_report_after`, the `autodays`/`restock` hooks. Gate behind
   `OS.is_debug_build()` or move to a tool script.

### Tier 2 — visible quality

4. **Pawns walk as a clump.** No collision avoidance; several given the same
   order overlap exactly. Even crude separation steering would help a lot.
5. **Wall occlusion.** In free-camera mode the near wall fills the screen and
   hides the interior. Fade or cull walls between camera and focus.
6. **No selection or inspection.** You cannot click a pawn to see who they are,
   or a station to see what it is making. Tile picking already exists
   (`CameraRig.ground_point_at`), so the hard part is done.
7. **Interiors are dark.** Walls shadow the floor heavily at the locked camera
   angle; readability suffers.

### Tier 3 — systems gaps (small, spec'd in the notes)

8. **Storage filters** (§11) — shelves accept anything; the notes want per-shelf
   allow-lists.
9. **Room detection** (§23) — needed by satisfaction later; the generic room
   system is explicitly required.
10. **Work priority UI** (§16) — the matrix exists in `WorkType` and
    `Worker.priorities` but the player cannot see or change it.
11. **Save/load** — `GameState`, `BuildGrid`, `ItemWorld`, `BillBook`, `Ledger`
    are already plain data. Pawns are the awkward part.

### Deliberately NOT for you

Reviews/reputation (§19), dirty dishes, the host role (§14), manual play (§22),
expansion (§11). These are new features and are out of scope for this pass.

---

## 7. One open balance question — do not silently change it

**Bread costs ~2.7× the labour of beer for 1.25× the price.**

| | walks per unit | price |
|---|---|---|
| Beer | ~0.75 (3 fetches → 4 mugs, one station) | 8g |
| Bread | ~2.0 (3 fetches → dough, carry to oven → 2 loaves) | 10g |

Beer quietly subsidises bread, and a bread-heavy tavern cannot make payroll. The
two-stage bread flow is deliberate (§8) — it is what makes kitchen layout matter
— so the lever is **price or batch size**, not the recipe.

These are the project owner's numbers from the design notes. **Flag a
recommendation; do not change them unilaterally.** (Wages were already retuned
12g → 6g because that figure was invented during development, not specified.)

Day totals across runs ranged −224g to +147g. Balance is playable but not yet
judgeable; a dedicated pass would be welcome, with numbers.

---

## 8. Licensing — hard constraints

| Source | Licence | Shippable? |
|---|---|---|
| `ForestFirewallpaper` (owner's own) | MIT | ✅ keep the notice |
| `seraphile/rimshare` | **CC BY-NC-SA 4.0** | ❌ NonCommercial |
| OSRS cache via `OSRS-Environment-Exporter` | Jagex copyright | ❌ |
| Procedural art in this repo | ours | ✅ |

Nothing from the two forbidden sources is currently used. **Keep it that way.**
Emulating the OSRS *look* is fine; shipping its assets is not. For icons prefer
game-icons.net (CC BY 3.0). For 3D placeholders, Kenney or Quaternius (CC0).

---

## 9. Definition of done for this pass

- `--headless --editor --quit` is clean.
- A 3-day measured run completes with the books reconciling and no
  `push_warning` about lost goods.
- No regression in the 2D menu (it shares `ValueNoise`, `TerrainGrid` and
  `TreeSpecies` with the 3D world — changes there affect both).
- Draw calls at 15 pawns materially reduced.
- `world_3d.gd` meaningfully smaller.
