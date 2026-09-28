# Visual effects brief (for Codex) — 2026-09-28

Effects that **tell the player something** first, pure ambience last. Every
effect must be driven by an existing game event or state — never by a timer
guessing what the simulation is doing — and must run on game time (pause and
1x/2x/3x) where it depicts the simulation.

## Order of work

1. **Money pops.** Floating "+12g" when a patron pays (gold), "+3g tip" smaller
   with a sparkle, red "−29g wages" over the purse at close. Source: the
   `Ledger.earn()` / `charge_wages()` calls; the payer's pawn position.
2. **Patron mood bubbles.** Small billboards over heads: "…" waiting to order,
   an angry puff when `CustomerBrain.patience_fraction()` < 0.25, a heart or
   star leaving happy (`mood_preview()`). At most one bubble per patron.
3. **Work you can see.** Oven: chimney smoke and a brighter ember glow while a
   bake is in progress; brewing vat: steam; prep table: a flour puff on each
   finished dough. Source: a station's active COOK job (`job.progress()`).
4. **Building and bulldozing.** Dust puff when a blueprint finishes; debris +
   dust cloud on demolish; a thin progress bar over blueprints under
   construction.
5. **Staff state.** "Zz" over idle staff after a few seconds idle; "!" over a
   worker whose job was just abandoned (the `gave_up_*` counters tick).
6. **Ambience.** Day/night light over `DayClock` (warm dusk, lit windows and
   lanterns in the evening), chimney smoke always, fireflies at dusk, gentle
   water movement.
7. **Moments.** Reputation stars burst on a gain; celebration on the day
   summary when a level is won.

## Constraints

- Renderer is **gl_compatibility**: use `CPUParticles3D` or `GPUParticles3D`
  (both supported), unshaded/billboard materials, no screen-space effects.
- **One pooled effects node** (e.g. `src/world/fx/fx_pool.gd`) owned by the
  world; hard cap on live particles and bubbles. A busy evening must not cost
  frame time: measure with `dev/tavern_profile.tscn` before and after.
- Effects are presentation only: **no simulation state, no RNG draws from the
  simulation's generators**. Chaos fingerprints (`dev/chaos_test.tscn -- seed=81
  seconds=1800` and `seed=90 ... level=wayfarers_rest`) must not change.
- Hidden/paused correctly: particles freeze when the game is paused
  (`world.sim.speed == 0` or `world.simulation_paused`), and nothing floats over
  the day summary.
- Staff wear their position's waistcoat colour (`StaffRole.uniform`); effects
  must not recolour pawns.

## Done means

- All suites still pass (see `docs/gameplay_testing_handoff.md`), including
  `dev/hud_layout_smoke.tscn`.
- Screenshots of each effect under `.verification/effects_*`.
- Frame time at 30 people within ~10% of today's ~1.4 ms at 720p.
