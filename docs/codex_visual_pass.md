# Handoff: visual pass on Mobile Tavern

You are doing a **visuals-only** pass on a working Godot 4.7.2 game. The
simulation is finished and measured; do not change it. Your job is to make the
game look considerably better without touching how it plays.

---

## What the game is

A medieval tavern management sim for PC (Android later). OSRS-inspired
low-poly 3D world, 2D menus. Colony-sim staffing and jobs crossed with
active table service. The design notes are
`docs/medieval_tavern_game_design_notes.txt` and are referred to by § number
throughout the code.

- Engine: **Godot 4.7.2**, GDScript, `gl_compatibility` renderer (chosen for
  Android reach — do not switch to Forward+).
- Run it: `Godot_v4.7.2-stable_win64.exe --path .`
- Regression suite: `--headless --path . res://dev/regressions.tscn` — 229
  assertions, currently all passing. **Keep it green.**

## The single most important constraint

**All art is procedural.** There is not one texture, model or material file in
the project. Every mesh is built at runtime from `src/core/mesh_builder.gd`
using flat-shaded, vertex-coloured triangles. This is deliberate: it makes the
whole look retintable and replaceable from data, and keeps the build tiny.

Work **within** that. Better geometry, better colour, better light, better
composition — yes. Importing .glb models or texture atlases — no, unless you
have a specific reason and you say so plainly.

### The trap that will waste your afternoon

`MeshBuilder.add_tri` takes counter-clockwise vertices, computes the outward
normal, and **emits them reversed**, because Godot treats *clockwise* winding as
front-facing. Geometry authored the "obvious" way is backfaced and silently
invisible. If something you add does not appear, this is why. Do not "fix"
`add_tri`.

---

## Where the visual seams are

| File | What it draws |
| --- | --- |
| `src/core/mesh_builder.gd` | `add_box`, `add_cone`, `add_cylinder`, `add_blob`, `add_limb`, `add_quad` |
| `src/world/build/building_mesh_library.gd` | every buildable: walls, doors, tables, oven, vat, shelf, sink, lectern, well |
| `src/world/build/rooms.gd` | enclosed rooms, derived — nothing is drawn for them yet |
| `src/world/items/item_mesh_library.gd` | sacks, jars, casks, loaves, mugs, dirty dishes |
| `src/world/pawn/pawn_mesh.gd` | the people |
| `src/world/world3d/terrain_mesh_builder.gd` | ground, water, colour per tile, plot levelling |
| `src/world/forest/tree_species.gd` | tree species table (shared with the 2D menu backdrop) |
| `src/world/world3d/world_bootstrap.gd` | sun, sky, fog, ambient, forest instancing, the yard and cart |
| `src/ui/theme/tavern_theme.gd` | every 2D colour, font size and stylebox |
| `src/world/world3d/world_hud.gd` | the in-game HUD |

Rendering is `MultiMesh` per building definition and per tree species. Keep it
that way — a tavern of 200 pieces costs about as many draw calls as the catalog
has entries, and that budget is what makes the Android target plausible.

---

## What specifically looks weak

Ordered roughly by payoff. Use your own judgement; this is what I can see, not
a spec.

1. **Buildings read as brown boxes from above.** The default camera is a fairly
   high three-quarter view and most pieces are box silhouettes of similar value.
   Walls have no capping or corner detail, and nothing has a roof — a finished
   tavern from above is a dark slab. (There is a wall-cutaway mode,
   `world_cutaway.gd`, so a roof would need to participate in it.)
2. **Lighting is flat.** One `DirectionalLight3D` at 0.95 energy plus a warm
   ambient at 0.7, no AO, no contact shadows. Objects do not sit on the ground —
   they hover visually. Cheap fixes: a darker ambient with more sun, a tighter
   shadow distance for crisper contact, faked AO by darkening the bottom ring of
   vertices in `add_box`.
3. **The ground is one flat green.** `terrain_mesh_builder._tile_color` gives
   grass a broad noise tint but the levelled plot ends up near-uniform. It needs
   variation, and the boundary between the plot and the forest floor needs to
   read as an edge, not a colour change.
4. **Colour range is narrow and desaturated.** Greens, browns and one candle
   gold. Nothing draws the eye to where the player should be looking.
5. **Item stacks are nearly unreadable at play distance.** Goods on the floor
   are the core of the whole loop ("bread is an object on a tile, not +1 in a
   counter") and they are small grey-brown lumps.
6. ~~**People are undifferentiated.**~~ **Done** -- staff wear one formal house uniform (burgundy waistcoat, white shirt, cravat, long apron); patrons are RuneScape-style adventurers derived from their seed: warriors in tiered plate with helms, capes and kiteshields, wizards in robes and pointed hats, hooded rangers with quivers, chainmail adventurers, and the rare party hat (`src/world/pawn/pawn_mesh.gd`, pose with `lineup=on`). Original note: Staff and patrons use the same `Pawn`, and a
   cook, a waiter and a customer look identical. Aprons, a tray, a colour per
   role would carry a lot of information for very little geometry.
7. **Water is one translucent quad at a fixed level.** Shorelines have a flag
   (`FLAG_SHORELINE`) that is barely used.
8. **The HUD is plain.** Panels are flat rectangles. See specifics below.
9. **The supplier's road reads faintly.** `world_bootstrap._carve_approach`
   paves it and clears a verge, but at play distance it is a slightly different
   green.

10. ~~**Checkboxes are nearly invisible.**~~ **Done** — drawn icons in
    `TavernTheme._checkbox_icons`: a dark timber well, candle-filled with an
    ink tick when on. The original note, for the record: The storage filter list in the
    inspector (select a shelf) uses default `CheckBox` squares against a dark
    panel — the tick state is hard to read at a glance, and this is a list the
    player is meant to scan. `TavernTheme` has no checkbox stylebox yet.

11. ~~Rooms are detected but never drawn.~~ **Done** — `room_overlay.gd`, on a
    toggle in the bar. Tinted fill, a border where the room ends, and a caption
    with the name, size and value. Tints live on `RoomCatalog.RoomKind` and are
    deliberately outside the timber family; warm browns over a wooden floor were
    invisible. Two traps if you touch it: the wash must be lifted clear of the
    floor *slab* (0.06 tall), not just the plot plane, and the whole thing is
    rebuilt on toggle and on any placement change.
12. **Nothing shows what ground is quicker.** Laid floors are faster underfoot
    than the beaten road, which is faster than grass, and staff route
    accordingly — but the only cue is the colour of the terrain. Probably wants
    the same treatment as the room overlay: its own toggle, not always on.

### Two concrete HUD bugs worth fixing early

- ~~The camera-rotate buttons render as a small meaningless shape.~~ **Done** —
  the glyphs are in the font but were drawn at the bar's 13px text size, where
  they came out as specks. Now 22px with tooltips naming Q and E.
- ~~Star ratings render as ASCII `***--`.~~ **Done** — confirmed the bundled
  font (Open Sans SemiBold) has no `★`, `☆` or `✓`; Windows' system fallback
  would have hidden that and a phone would not. Ratings are now drawn as
  polygons (`src/ui/star_rating.gd`) in the header, day summary, card and
  inspector. `star_text()` remains for plain-text logs and the ledger note.

---

## Do not touch

- Anything under `src/world/jobs/`, `src/world/customers/`, `src/world/sim/` —
  the job board, customer brains, ledger, reputation, save format.
- `dev/regressions*.gd`, `dev/regression_group.gd`, `dev/world_scenario.gd` — except to **add** visual
  assertions. The economy numbers in them are measured, not guessed.
- `BuildingCatalog`, `ItemCatalog`, `RecipeCatalog` as *content*. You may add a
  `Shape` enum entry and a mesh function for it; do not add per-item branches
  anywhere else (§28 forbids a `BakeBread()`, and the same rule applies to art).
- The `gl_compatibility` renderer.

---

## How to check your work

The screenshot harness drives the game headlessly and writes a PNG. It is the
fastest way to compare before and after:

```bash
Godot_v4.7.2-stable_win64.exe --path . res://scenes/_screenshot_harness.tscn -- \
  res://src/world/world3d/world_3d.tscn "user://shot.png" 9 \
  "seed=493774,demo=tavern,economy=on,distance=30"
```

Output lands in `%APPDATA%/Godot/app_userdata/Mobile Tavern/`.

Useful `--` options: `demo=tavern|starter|blueprint`, `camera=free|locked`,
`distance=`, `pitch=`, `yaw=`, `panel=staff|production|handson`,
`inspect=worker|patron|storage|oven`, `buildbar=on|off`, `economy=on`,
`well=on`, `restock=on`, `buyland=<n>`, `rooms=on`, `flatcost=on`,
`daylength=`, `autodays=`, `report=`.

`seed=493774` is the seed every screenshot in this handoff used — reuse it so
comparisons are like for like.

**Before you finish:** run the regression suite and confirm `REGRESSIONS PASS
(0 failures)`. Several assertions count pieces in the demo layout, so if you add
a building definition you will need to update the expected count — that is
fine, but do it knowingly.

---

## Ground rules

- Match the surrounding code: typed GDScript, `##` doc comments on anything
  non-obvious, comments that say *why* rather than *what*.
- Prefer changes that are data (a colour constant, a shape entry) over changes
  that are code branches.
- If you think a visual problem is really a design problem, say so rather than
  papering over it.
- Keep the frame budget in mind: `MultiMesh` instancing, no per-object
  materials, no per-frame mesh rebuilds. The debug HUD shows fps and draw calls
  in debug builds.
