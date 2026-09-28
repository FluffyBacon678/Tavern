# World atmosphere — 2026-09-28

The world now changes with the trading clock: golden dawn and dusk, cooler
moonlit nights, drifting clouds, stars, clear/overcast/rainy weather, wind in
tree crowns, moving river highlights, oven flames and drifting chimney smoke.
Completed rooms receive small original iron-and-amber wall lanterns. These
fixtures hide with their supporting cutaway walls; their warm light keeps
tables, goods and adventurers readable at night.

This pass changes presentation. It does not add weather penalties, alter
recipes, prices or customer behaviour, consume gameplay randomness, or add
save fields. Other gameplay changes made concurrently in this workspace were
preserved. All new artwork is procedural; no external assets were added.

## Behaviour and ownership

- `AtmospherePalette` derives weather from world seed, day and clock. A new
  front is selected every four game hours, blending over the first 51 game
  minutes. Saved clock/seed values reproduce the same conditions.
- `WorldAtmosphere` owns sunlight, ambient fill, sky, distance fog, outdoor
  rain and the shelter mask. Light updates are throttled to four per game
  second. Each effect reads the same clock, so pause and the day summary
  freeze its animation; resume and game speed affect it consistently.
- The landscape shader darkens exposed ground during rain and moves tree
  crowns gently. River highlights and normals move without changing the
  terrain or navigation grid. Global lighting colours characters, furniture
  and items through their existing materials.
- Finished, enclosed rooms with completed floors mask rain regardless of
  camera cutaway. Removing a boundary exposes that room; blueprint walls do
  not provide shelter. This is a virtual roof, since roofs are not modelled.
- `WorldHearths` tracks finished ovens, follows their placement rotation and
  removes effects on demolition. Fires remain decorative while the oven is
  built, including when no cooking job is active.
- `WorldLanterns` creates decorative fixtures on completed room boundaries.
  They are not new inventory or buildable furniture. Visible fixtures are
  selected for the camera and spread along surviving walls.

## Rendering budget

Designed for the project's OpenGL Compatibility renderer: ordinary distance
fog, custom shaders and batched geometry. No volumetric fog or post-process
bloom is required. See Godot's [renderer comparison](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)
and [sky shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html).

- Rain: one MultiMesh, 350 / 800 / 1,400 drops at low / medium / high quality.
- Hearths: at most eight visible oven fires; four smoke puffs per oven.
- Lanterns: at most four visible fixtures in one MultiMesh, 104 triangles each.
- Local lights: shared budget of two at low quality, four otherwise; no local
  shadow maps. Low quality disables smoke. Sun shadows retain existing quality
  settings. These caps deliberately limit large taverns' local effects.
- Sky: 128-pixel incremental radiance map; the cubemap pass skips small cloud
  and star details. A bounded noise hash avoids observed OpenGL cloud seams.

In a fixed night tavern view, showing hearth effects and lanterns measured
**295 vs 292 draw calls** and **877,648 vs 877,222 submitted primitives**.
That is three additional mesh draws and 426 submitted primitives in this
fixture, not a timing benchmark for lighting or the complete atmosphere pass.
Different times of day change shadow coverage, so cross-time draw totals are
not a useful direct overhead comparison. Android hardware remains untested.

## Verification

Godot 4.7.2 import is clean. The windowed renderer was OpenGL 3.3 Compatibility
on Intel Arc 140V. Captures were inspected at the actual 1280×720 viewport:
morning, midday, dusk, night, rain, low-camera daytime/night skies and river
motion. Outputs and full logs are in `.verification/atmosphere_20260928/`.

- `atmosphere_smoke`: **22 checks, zero failures**, windowed. Tests RNG and
  save-state isolation; weather range/blending; pause/resume; night readability;
  room shelter; completed vs blueprint and demolished ovens; rotated flame
  transforms; lantern cap; low-quality light/smoke limits; wall demolition and
  reconstruction; save/load restoration. Headless skips the mesh transform
  readback because Godot's dummy renderer does not provide it.
- Existing `regressions`, `polish_regressions` and `smoke_test` pass.
- `level_smoke -- playedonly` completes six days with all nine goods
  differences **zero**. Final reconciliation: **1,851g actual = 1,851g expected**;
  day-six close was 1,821g. This is evidence for the current concurrent build,
  not a balance comparison with earlier art passes.
- `atmosphere_showcase` successfully writes every capture, prints rendering
  totals, and verifies that advancing the visual clock changes river pixels.
- No new engine warnings/errors in import, atmosphere, showcase or level logs.
  Both new harnesses call `begin_test_session()` and clean their own sandbox
  saves on normal exit. Showcase images are intentionally retained.

Import before either harness:

```powershell
$engine = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . --import
& $engine --path . res://dev/atmosphere_smoke.tscn
# Add --headless for logic-only testing (21 checks).

# Windowed visual capture; create the output directory first.
New-Item -ItemType Directory -Force .verification/atmosphere
& $engine --path . res://dev/atmosphere_showcase.tscn -- res://.verification/atmosphere/view
```

The showcase refuses headless operation. It populates the real demo, holds
simulation, then selects clock/day poses that produce each weather state.
Those screenshot poses do not represent a continuously played session; the
separate level smoke supplies production and economy verification.
