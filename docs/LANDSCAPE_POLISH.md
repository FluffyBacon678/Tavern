# Landscape polish — 2026-09-29

The outdoor world now has irregular shallow river margins, clearer teal depth
colour, transparent water over the banks, moving shoreline foam and longer
curved highlights. Four original procedural decoration batches add grass
tufts, pale/lavender wildflowers, mossy stones and reed beds to the forest and
banks. No external assets or gameplay content were added.

## Implementation

- `WorldScenery` samples the existing terrain using its own seeded RNG. It
  keeps all decoration outside the plot plus a one-tile margin, and away from
  the road. Decorative nodes have no collision or navigation role. Grass and
  reeds share the existing clock-driven wind material, so pause still works.
- Four MultiMeshes cap grass/flowers/rocks/reeds at 900/120/160/260 instances.
  Low quality shows 30%, medium 65%, high 100%. These meshes cast no additional
  shadows. Explicit white instance modulation prevents black vertex colours
  on the tested OpenGL Compatibility renderer when custom data is enabled.
- Water extends into adjacent low bank tiles only. A corner-aligned floating
  height texture clips it to the existing terrain and controls shallow colour,
  transparency and shore foam. No water surface is generated over plot tiles.
  The shallow fringe is cosmetic; the terrain and navigation cells are unchanged.
- Terrain, water, forest and scenery replacement now releases the old node
  names before adding new meshes. Repeated land purchases therefore replace
  one set correctly and remove decoration from newly buildable ground.
  This lifecycle handling lives in `WorldBootstrap` alongside render creation.

## Measured verification

Godot 4.7.2, OpenGL 3.3 Compatibility on Intel Arc 140V. Current settings produced
1920×1080 captures. Before/after frames and logs are retained in
`.verification/landscape_20260929/`.

| Seed 12345 decoration | Instances | Triangles |
| --- | ---: | ---: |
| Grass | 594 | 4,752 |
| Flowers | 102 | 2,142 |
| Rocks | 25 | 875 |
| Reeds | 236 | 7,080 |
| Total | 957 | 14,849 |

The fixed river view increased from **118 to 122 draw calls**, and **616,502 to
633,411 submitted primitives**. The difference includes the expanded water
mesh. These are rendering counts, not a frame-time or Android benchmark.
Android hardware performance remains unverified.

- Import clean; final captures contain no engine errors or warnings.
- `scenery_smoke`: 12 windowed checks / 11 headless checks pass. Covers RNG and
  complete save-state isolation, repeatable placement, clear plot/road areas,
  geometry caps, lower quality density, actual instance-colour readback,
  no water on plot tiles and two consecutive land purchases.
- Existing `regressions`, `polish_regressions`, `smoke_test` and
  `atmosphere_smoke` pass. Regression warnings deliberately exercise old save
  formats and missing load intent. The guided opening retains its goods/gold
  reconciliation and save/reload checks.
- Inspected river and low-camera views plus close-ups of plants. A first render
  exposed black instance colours; this was corrected and captured again.
- Both new dev harnesses sandbox saves; the screenshot harness refuses headless.

## Reproduce

```powershell
$engine = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . --import
& $engine --path . res://dev/scenery_smoke.tscn
# Omit GPU colour readback with --headless for CI.

New-Item -ItemType Directory -Force .verification/scenery
& $engine --path . res://dev/scenery_showcase.tscn -- res://.verification/scenery/detail
& $engine --path . res://dev/atmosphere_showcase.tscn -- res://.verification/scenery/world
```

The close-up showcase follows actual seeded decorations in the world; nearby
trees can occlude them. The atmosphere showcase includes the fixed river view
and confirms that advancing the clock changes the rendered scene.
