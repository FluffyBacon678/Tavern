# Handoff: gameplay testing on Mobile Tavern

Your job is to **play this game and find where it breaks**. Not to review code,
not to add features — to find the places where a real player has a bad time, and
say so precisely enough that somebody can fix them.

The systems all pass their own unit tests. Every bug worth finding here is
*emergent*: it only appears when the whole tavern runs for several simulated
days, and it is invisible in any single component.

---

## What the game is

A medieval tavern management sim for PC (Android later). Godot 4.7.2, GDScript,
`gl_compatibility` renderer. Build a kitchen, hire staff, order supplies, let
customers in, get paid. The design notes are
`docs/medieval_tavern_game_design_notes.txt`, referred to by § number in code.

- Run it: `Godot_v4.7.2-stable_win64.exe --path .`
- The demo level is on the main menu as **"Play the demo"**.

## The rule that matters most

**Never trust a simulation number until you have confirmed the build compiles.**

A new `class_name` file that Godot has not reimported produces
`Parse Error: Identifier "X" not declared`, buried in tens of thousands of log
lines — and the world silently comes up `nil` while the run *appears* to
proceed. This has produced confidently wrong conclusions more than once.

So, every time, in this order:

```bash
Godot_v4.7.2-stable_win64.exe --headless --path . --import
Godot_v4.7.2-stable_win64.exe --headless --path . res://dev/regressions.tscn
```

Confirm `REGRESSIONS PASS (0 failures)` before running anything else.

---

## How to run a measured session

**Start with the suites** (next section). They play at the real day (870 s of clock, about ten minutes
played at 1x, since 2026-09-28), at test speed, and give the same numbers every
time: a real-day measurement of the demo level takes about six minutes. The capture harness below still runs in
real time -- use it for screenshots and for watching, not for balance.

```bash
Godot_v4.7.2-stable_win64.exe --headless --path . res://scenes/_screenshot_harness.tscn -- \
  res://src/world/world3d/world_3d.tscn user://out.png 560 \
  "seed=493774,demo=starter,economy=on,restock=on,autodays=2,daylength=870,report=536"
```

`daylength=870` is the real day (180 before 2026-09-28). **Use it.** Wages and deliveries are charged per
*day* while production and arrivals happen per *second*, so a shortened test day
makes the tavern look far more marginal than it is. A whole balance pass was
once tuned against a 4×-compressed day and had to be redone.

In the harness, four real days is about 13 minutes of wall clock.

Useful options after the `--`: `demo=tavern|starter|blueprint`,
`level=wayfarers_rest`, `camera=free|locked`, `distance=`, `pitch=`, `yaw=`,
`panel=staff|production|handson`, `inspect=` and `hover=` (`worker`, `patron`,
`items`, `ground`, `storage`, or any building id such as `brewing_vat`), with
`poseat=<seconds>` to hold those poses until patrons are in, and
`livehover=off` so the real pointer does not raise a card over the capture,
`rooms=on`, `well=on`, `buyland=<n>`, `flatcost=on`, `buildbar=on|off`,
`economy=on`, `restock=on`, `daylength=`, `autodays=`, `report=`.

### Existing suites

| Scene | What it does |
| --- | --- |
| `dev/tutorial_watch.tscn` | Sandboxed live tutorial observer/player: default manual controls; `-- auto` uses existing actions with the real director; `-- probe_filter` reproduces premature shelf-filter completion (currently expected exit 1). Writes compact `state.json`, transition-only `events.jsonl`, and windowed step screenshots. Read with `./dev/read_tutorial_watch.ps1`. See `docs/TUTORIAL_PLAY_REPORT.md` for limitations, findings and commands. |
| `dev/regressions.tscn` | 366 assertions in four groups -- goods, building, people, game (`dev/regressions_<group>.gd`) -- each on a fresh copy of the demo tavern, so no check passes on another's leftovers. `-- group=people` runs one group. A new check goes in the group it belongs to and sets up what it needs (`open_for_trade()` in `dev/regression_group.gd` for a delivery and something to sell). |
| `dev/day_regressions.tscn` | day rollover and its save/restore |
| `dev/visit_regressions.tscn` | a customer visit surviving save/load |
| `dev/polish_regressions.tscn` | batch output that must fit whole, and seats behind walls |
| `dev/atmosphere_smoke.tscn` | Sandboxed atmosphere checks: gameplay/RNG isolation, weather blending, pause/resume, night readability, indoor rain shelter, oven completion/rotation/demolition, lantern/light limits and save/load. Import first, then `Godot_v4.7.2-stable_win64_console.exe --path . res://dev/atmosphere_smoke.tscn`. Windowed checks the actual mesh transforms (22 checks); `--headless` skips that dummy-renderer readback (21). Expected to pass. |
| `dev/atmosphere_showcase.tscn` | Windowed, sandboxed morning/day/dusk/night/rain, sky and river captures, with rendering totals and a river-animation pixel check. Import first; create the destination folder, then `Godot_v4.7.2-stable_win64_console.exe --path . res://dev/atmosphere_showcase.tscn -- res://.verification/atmosphere/view`. Headless is refused; PNG write failures exit nonzero. See `docs/WORLD_ATMOSPHERE.md`. |
| `dev/furniture_showcase.tscn` | Windowed front/back contact sheet of nine production furniture meshes, with surface/triangle counts, bounds and rendering totals. Import first, then `Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x1000 res://dev/furniture_showcase.tscn -- res://.verification/furniture`. The output directory must exist; saves are sandboxed, headless is refused, and failed PNG writes exit nonzero. |
| `dev/adventurer_mesh_smoke.tscn` | Headless character-art check: covers all 32 base styles × four variants (128 distinct appearances), repeatable geometry/colour, unchanged simulation RNG consumption, staff role colours, one skinned surface/six bones, finite bounded geometry and a 1400-triangle ceiling. Import first, then `Godot_v4.7.2-stable_win64_console.exe --headless --path . res://dev/adventurer_mesh_smoke.tscn`. |
| `dev/adventurer_showcase.tscn` | Windowed art contact sheet: front, back, side and mid-stride. Run after import with `Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 res://dev/adventurer_showcase.tscn -- res://.verification/adventurers`. Add `variants` after the output prefix for 24 guests spanning all four wardrobe variants and six families. Alternatively add `tavern` to capture at two camera distances when four actual guests are seated (wait bounded to half a game day, actual time/count printed). Saves are sandboxed; only the requested PNGs are retained. |
| `dev/tutorial_smoke.tscn` | **The end-to-end test.** Plays the whole tutorial (40 steps: building, kitchen, supplies, production, hands-on, staff, service with counter and bills, the day's close, land, well, saving) through the player's own actions, and checks each step's done-condition. One line per step, detail only for a failure. About 10 real seconds. A feature is not finished until its tutorial step passes here. |
| `bash dev/run_tests.sh` | Every suite in parallel with `-- --brief`: one line per suite, the lines that explain a failure, logs kept for detail. `--quick` skips the level and the long chaos run. |
| `dev/playthrough.tscn` | Not a test: a new player's first sandbox session from the title screen, with a screenshot and notes per step (windowed; `-- <out dir>`). For finding where a newcomer gets stuck. |
| `dev/hud_layout_smoke.tscn` | HUD button bounds, 24×24 pixel click targets, panel overlap, clock/pause/speed visibility across six PC window shapes; fresh worlds with and without level briefing, plus live resize. Headless resizing is supported and probed; run after import with `Godot_v4.7.2-stable_win64_console.exe --headless --path . res://dev/hud_layout_smoke.tscn` (or omit `--headless` for windowed). Prints actual sizes and explicit skips if clamped. Passes since the 2026-09-27 HUD layout rebuild (bar placed from the header's real height, wraps when narrow, rescales on resize); a failure here is a real layout regression. Do not weaken checks to make it pass. |
| `dev/smoke_test.tscn` | plays the guided opening from an empty plot, at the real day (~20 s) |
| `dev/level_smoke.tscn` | plays the demo level six ways at the real day: neglected, repaired at once, repaired on day 3, never repaired, and the first repair replayed to prove the run repeats (~1 min). After `--`: `playedonly [latefix]`, `unfixed`, `shortday` |
| `dev/chaos_test.tscn` | plays badly at random -- demolishes under diners, saves mid-haul, dismisses staff -- and checks invariants after every move (~30 s for 1800 game seconds, about 40 days). `-- seed=N seconds=S level=wayfarers_rest` |

All three run in **game time at test speed** (see below) and accept `realtime`
to play at ordinary speed instead, for watching.

The chaos test is the best bug-finder the project has. Its first runs found
three real bugs in an afternoon, none of which any other suite could reach:
seats renumbered under seated patrons, cargo written to saves but never read
back, and the new hover card crashing on a patron who had left. A failure is
printed with its seed and the eight actions before it, so it can be replayed.
Run several seeds; each finds different trouble.

The last two scripted suites are the model to copy: they report **holes in plain language**
rather than assertions, because "the tavern stops cooking on day three" is not
something an assertion can phrase usefully.

---

## Game time and speed

All simulated systems (day clock, job generator, customer director, patrons,
workers, pawns) run on one `SimClock` per world (`src/world/sim/sim_clock.gd`)
in fixed 1/60 s steps, through `sim_step(dt)` rather than `_process`. The player
has pause and 1x/2x/3x/5x (Space, 1-4, or the buttons beside the clock). Worth
knowing when you test:

- `set_process(false)` on a sim node still freezes it -- `sim_step` checks it --
  and the day summary holds the whole clock (`SimClock.held`).
- Anything a test drove with `node._process(dt)` must now call `node.sim_step(dt)`.
- `speed=0..3` in the capture harness sets the speed; `lineup=on` stands every
  staff and patron look in a row for judging outfits.

### Test speed, and runs that repeat

The long suites run the clock at **test speed** -- `SimClock.turbo_steps`, a
fixed 60 game steps per frame whatever the frame took -- and wait on
`SimClock.sim_time`, never the wall clock (`dev/sim_wait.gd`). That makes them
fast, and it makes them **repeatable**: the same command gives the same
numbers, to the coin. The chaos test prints a `FINGERPRINT` of its final state;
two runs of one seed must print the same one. The level smoke replays a branch
and fails if the two disagree.

If you write a new suite, follow the same four steps, or it will quietly stop
repeating:

1. `SimWait.seed_run()` before making a world -- the patron director draws its
   seed from the global generator.
2. `SimWait.configure(world)` for test speed.
3. `SimWait.hold(world)` while you set up, then `SimWait.release(world)`. A
   world made during `_ready` starts stepping a frame earlier than one made
   mid-frame, and at test speed a frame is a game-second: without the hold, the
   same branch gave 911g alone and 944g after another world had run.
4. `await SimWait.seconds(world, n)` to wait, and dismiss day summaries --
   game time does not pass while one is up.

## Read the report, not the screen

`dev/world_scenario.gd`'s `reconcile()` prints the instruments that have found
every real bug so far. Learn what each one means:

- **Goods reconciliation** — `received + made − used − eaten − on_ground −
  carried == 0` per item. Anything that creates or destroys goods must appear on
  one side of it. This caught six yeast vanishing per run.
- **Loss causes** — patrons lost split into *no seat / unserved / nothing to
  sell*. Three different fixes; never accept the total on its own.
- **`Service: N items to M patrons (X.XX each)`** — **the trap.** Patrons served
  is not throughput. A tavern with only beer sells one item a head; one with
  bread as well sells two or three, so identical production serves half as many
  people and reads as a collapse. Judge the kitchen on **goods used per day**.
- **Per-kind job tally** — `Build=.. Haul=.. Cook=..`. This exposed jobs that
  were posted and never withdrawn, which had cut trade from 21 patrons a day
  to zero.
- **`Untaken:`** — jobs nobody will take, and how many workers refused each.
- **`Kitchen:`** — each bench's bill state and what it is waiting for, including
  *why* it cannot be fed (`no source outside the bench`, `nowhere on the bench
  accepts it`, `job already posted`).
- **`Storage: N tiles, M empty`** — check this **first** when production stalls
  with staff idle. Too little storage silently stops the kitchen: shelves fill,
  goods heap around the benches, and there is then nowhere to put the one
  ingredient a recipe is short of.
- **`Abandoned:`** (level smoke) — work claimed and never finished, split by
  reason. A job that is claimed and abandoned forever reads as "in progress" on
  the board.

---

## Resolved by the 2026-09-24 playtest round

The playtest report in `.verification/playtest_20260924/REPORT.md` found five
problems. Four were code, one was its own fixture; all are fixed and covered by
regressions. Worth knowing because each will look familiar if it ever recurs.

- **Dead jobs kept their keys.** A feed job whose source tile emptied stayed on
  the board for as long as its bench was hungry, and its key blocked any
  replacement. Symptom: `Untaken: Fetch Hops refused by 5`. Fix:
  `JobBoard.withdraw_dead_pickups()` at the start of every scan.
- **Claims outlived goods.** A cook, diner or washer taking stock left the claim
  standing, so real stock read as spoken-for and `post()` refused silently.
  Symptom: `ready to post` over an empty board. Fix: `ItemWorld._clamp_claims`.
- **Work was posted where nobody could stand.** `adjacent_walkable` did not ask
  whether a neighbour was reachable. Fix: it now checks a route, and the
  generator filters through a flood fill from the road (`_standable`).
- **The first-sale objective read a daily counter** and un-ticked every morning.
- **The report's level fixture sealed the tavern:** its wash basin covers the
  one tile inside the only door. The game now warns when a placement cuts off
  seats or benches from the road (`TavernWorld.route_warning`).

Measured at the real day length with the report's own guided fixture: final
purse **−64g → 328g**, kitchen output **3 dough / 4 beer → 8 / 16 bread / 24 beer**.
Demo level: beer **0 → 40**, "no seat" **16–18 a day → 0**, "goods gone" **684 → 5**.

A later pass (2026-09-25) found the largest remaining source of churn:

- **A worker already standing where a job wanted it gave the job up.**
  `find_path(a, a)` has no steps, so `goto()` reported "no route". Over nine
  real days that was 298 "no route" and 131 "could not deliver" -- both now 0,
  and the day-6 purse rose from ~1035g to ~1313g. Any new `goto()` caller must
  handle "already there" itself.
- **`place_near` prefers tiles a worker can stand beside**, falling back to
  anywhere only when nothing reachable has room.
- **The demo level now ends.** Won at the first close with the purse at the
  goal, lost if the deadline day closes short -- derived from the ledger, so it
  survives a reload and cannot be un-won by a later bad day or won after the
  deadline (both were possible). The day summary announces it once, with Keep
  trading / Main menu. Saves also now remember which level they are; a saved
  demo used to reload as a plain sandbox with no goal at all. Pose it with
  `verdict=won|lost` in the capture harness.
- **The level smoke's gold check assumed the sandbox's 600g opening purse**
  and reported the level's books 340g out; it now uses the level's own purse.
- **The HUD now says what is going wrong** (`src/world/sim/trouble.gd`): a
  red-edged line under the goal naming the most urgent cause -- tables under
  dirty plates, an ingredient run out, guests leaving for a seat or unserved.
  Before it, the demo level's lesson was invisible: guests on the grass, +0g,
  and nothing on screen to say why. **Worth testing:** does it ever name the
  wrong cause, nag about something that is fine, or stay silent while the
  tavern earns nothing? Any of those is a finding.

## Known-open, worth confirming or refuting

1. **The demo level's goal is 1100g by the end of day 6** (1200g until the 2026-09-28 scaling pass; now 1821 / 1229 / -124g) (set 2026-09-28 for
   the ten-minute day, staff positions and doubled wages; re-measured after
   table service and the doubled plot). The level smoke enforces it on every
   run: repaired at once 1828g, repaired on day 3 1300g, never repaired -125g. The fixture restocks perfectly and builds nothing
   extra, so a human's margin is smaller than the ~200g it shows. Measure other crews with `-- crew=porter,cook,...`. Worth confirming by hand that a first-time player
   finds the three gaps within two days.
2. **Abandoned-work counters should now sit at or near zero** in the demo
   level (last real-day runs: 0 no route, 0 could not deliver, 1-7 goods gone).
   If they climb again, something new is wrong -- see the zero-step note above.
3. **The guided opening's lowest purse is 76g**, at the real day, which the
   smoke test now uses by default. (At the old shortened 60s day it read as low
   as 16g, because two days of wages elapse before the first sale.)
4. **Bread costs ~2.7× the labour of beer for 1.25× the price** (§13 prices, §8
   two-stage flow). Design-note numbers, deliberately untouched — the owner's
   call, not yours.

## The hover card and inspector

Resting the pointer on anything shows a card (`src/ui/hover_card.gd`); clicking
opens the full inspector. Both read from one place, `src/ui/world_stats.gd`, so
they cannot disagree with each other. A patron's **Mood** is the review they
would write if they left now, computed by the review's own scoring. Worth
testing:

- Does a card ever show something stale, or describe the wrong person in a
  crowd? Does it flicker while the camera moves?
- Does a patron's mood match the review they then write?
- Follow (F, or the inspector's button): does the view ever fight the player,
  or keep following someone who has left?
- Stack numbers (zoom in, or hold Alt): does a number ever hang over a stack
  that has gone, or disagree with the hover card?
- Does any figure contradict the report lines above? The report is measured;
  the card is what a player trusts.

## Things that are *not* bugs

- The game stops dead at close of business until the player dismisses the day
  summary. A test that does not dismiss it measures a paused game.
- Two *different* seeds, or a change to the code, give different numbers --
  a busy tavern is chaotic, and a one-coin change early compounds. But the
  **same** command must always give the same result; if it does not, that *is*
  a bug. (Before the clock rework, runs varied freely and every figure needed
  several samples.)
- A tavern with nothing to sell gets no arrivals at all. That is deliberate — it
  stops the opening day collecting one-star reviews for a situation the rules
  created. It also means **a fixture that orders supplies once will go quiet
  once the larder is empty**: that is the fixture running out, not the game
  stalling. Check `On the ground:` before calling it a stall.
- `on a shelf` in the level smoke's goods listing means a building stands on the
  tile and staff take the goods from beside it. `UNREACHABLE` there is now a
  real claim: nowhere next to the stack can be walked to from the staff.

## Ground rules

- Typed GDScript, `##` doc comments, comments that say *why*.
- Do not change `dev/world_scenario.gd`'s economy numbers: they are measured.
- When you report a finding, give the command that reproduces it and the
  report lines that show it. A claim without a measurement behind it has been
  wrong about as often as it has been right on this project.

## Table service, menus and the bigger plot (2026-09-28)

- **Service is waited on, twice.** A patron reads the menu, then raises a hand
  and waits (45 s) for a waiter to take the order -- it is decided then, from
  stock at that moment. After eating they wait (30 s) for somebody to bring the
  bill: a new Bill work kind, done by waiters and bussers. Nobody comes: they
  pay at the door without a tip, having held the table the whole time.
- **The serving counter is the pass.** Built, cooks plate taken orders onto it
  ("Plate bread") and waiters only collect from it; porters never file food
  off it. Without one, waiters fetch from the shelves as before.
- **The plot is 37 x 28** (was 26 x 20). Designed levels keep their building the
  same distance from the southern road; `LevelDef.origin` says where it stands,
  and anything a test adds to it must be placed from there.
- **Esc no longer leaves the game.** With nothing to close it opens the pause
  menu (game time held via `SimClock.menu_held`), which asks before leaving
  with unsaved progress. The title screen, pause menu and settings share
  `src/ui/menus/` (UiKit, ModalDialog, SettingsScreen, PauseMenu).
- **Settings in tests go to the test's own folder** (`GameSettings.settings_path()`),
  never the player's `user://settings.cfg`.
- Chaos fingerprints after these changes: seed 81 `2973e532`; seed 90 level and
  seed 33 level print the same values as before in a different goods order.

## Scaling (2026-09-28, `dev/stress_test.tscn`)

The biggest tavern the game allows -- every parcel bought (79 x 52), 16 rooms,
96 seats, 117 staff, 2,320 placements -- at 5x. Run windowed for frame times,
headless for the simulation alone, `-- --profile` for cost per system.

- Before: 125 ms a frame (8 fps), 2.7x of the 5x asked. Pawns cost 234 ms per
  game-second (every pawn checked every other pawn for crowding, every step,
  and posed its body every step); the guest director rebuilt every service job
  60 times a game-second (51 ms); header tooltips 11 ms four times a second.
- After: 16.8 ms median (p95 30 ms), full 5x. Crowding uses a per-frame tile
  bucket, posing runs once per drawn frame, service jobs are rebuilt 4 times a
  game-second, tooltips only for the chip under the pointer.
- Found and fixed along the way: guests were capped at 10 whatever the size of
  the tavern (now 1.25 x seats + 4, 10..160); every order was plated on the
  first counter built, however far from the guest (now the table's nearest).
- Still open, design rather than bugs: guests walk in from one road on the
  south edge, so the far side of a large plot is a long walk; footfall does not
  grow with seating, so a very large hall cannot fill; 8.4 M primitives a frame
  in the biggest tavern is fine on the Arc 140V but heavy for weaker GPUs.
- **Minimum spec is the Dell 14 Pro (Intel Arc 140V)**, per the user
  (2026-09-28). At 1080p and 5x: a normal tavern (`-- --small`) holds 60 fps,
  vsync-locked (median 16.7 ms, p95 18.8 ms); the biggest possible tavern
  holds 60 fps median with p95 30 ms. Anything that makes either worse on
  this machine is a regression.
- **The high road** (2026-09-28): a 3-tile dirt road across the whole map, four
  rows south of the yard (`TavernWorld.high_road_row()`), crossing the lane up
  to the yard. Guests spawn at either end of it and leave toward either end;
  path tiles are cheap to walk, so they keep to it and turn up the lane.
  Footfall stays reputation-only by design. Level: 1811 / 1272 / -127g.
- **The fisherman** (2026-09-28): a position from day 2 (20g, 8g a day, fish
  and carry). A Fishing Spot (30g) has to touch the water; each catch is a
  trout or a perch, one or two, rolled on `world.sim_rng`. Goods picked up at
  the spot are carried in as fishing work, so cooks and porters stay indoors.
  The prep table cleans a fish into a fillet and a head; the oven grills the
  fillet (14g) or boils the head with water into two bowls of soup (9g each).
  Guests order from every priced product in stock (`CustomerDirector.menu_ids()`,
  the same dice as before when only bread and beer are on); three dishes score
  a little better on food than two.
- **A recipe that cannot be made holds nothing** (found by the level smoke when
  fish soup arrived): if an ingredient is nowhere in the tavern, the bench does
  not fetch or claim the others, and other benches may take them. Before, the
  oven called for water for soup it had no heads for, and the vat sold no ale.
  Gathering and fishing jobs now come off the board when their reason goes,
  like the others. Level after both: 1878 / 1283 / -127g; the generator is
  cheaper in the biggest tavern (30 ms a game-second against 36).
- Chaos fingerprints now: seed 81 `4a0a210e`, seed 90 `9d91141f`, seed 33
  `7b6b6f68` (they moved because chaos can now build fishing spots and hire
  fishermen; a repeat run matches).
- **The pass is kept clear** (2026-09-29, found by the new soak): guests who
  gave up left plates on the serving counter and nothing moved them; with four
  dishes and two counter tiles, leftovers stopped every other order (15-27
  guests a day lost to service). When an order has nowhere to go, a cook now
  carries off a plate nobody is waiting for (`CustomerDirector._clear_the_pass`).
- **Soak** (`tutorial_smoke --days N`, suite `soak` at 6 days): trades on after
  the tutorial, ordering the standard supplies each morning; fails when service
  losses pass 3 a day. Now 272 served, 5 lost to service, 962g -> 4131g.
- **Guest types** (phase 3, 2026-09-29, `src/world/customers/guest_type.gd`):
  the outfit decides the kind. Warrior drinks up to 3, tips 0.8; wizard weighs
  menu choice double, tips 1.3; ranger 0.75 patience, service weighs 1.5;
  delver up to 2 plates, tips 0.7; duelist orders the dearest dish, tips 1.5;
  pilgrim rarely drinks, weighs cleanliness double. The hover card names the
  kind and what it wants; tutorial step `guest_type` (47 steps). Level 1900 /
  1328 / -127g. Chaos: 81 `ba221835`, 90 `266b307e`, 33 `7b6b6f68`.
- **Key bindings** (2026-09-29, `src/core/key_bindings.gd`): every shortcut is a
  named action with two slots, installed into the InputMap at startup and
  rebound in Settings > Controls (click a slot, press a key; Esc cancels,
  Backspace clears; a key in use moves and the page says what lost it). Only
  changes are saved, in the settings file's `controls` section. Buttons, the
  hint strip, tutorial and advice text all name the player's keys. New keys:
  +/- zoom, H home, X demolish, U supplies, L ledger, V cutaway, F5 save,
  F12 screenshot. Fixed: Esc, Alt, mouse.
- The chaos fingerprint now sorts goods as text (StringNames sort by identity,
  so unrelated code moved the hash). Now: 81 `3e0ca0f5`, 90 `b6807bbe`,
  33 `f0fa2628`.
- **Bookings** (phase 3, 2026-09-29, `src/world/customers/bookings.gd`): with a
  host's stand and someone allowed to host, a "Take today's bookings" job runs
  each morning until 11:00. Count = seats x 0.5 x standing (reputation 30 -> 0,
  70 -> 1, capped 1.5, at most 12); times lean to the 15:00-16:00 lull. Booked
  parties (1-2) arrive at their hour on top of footfall, with doubled seat
  patience. Saved with the guests. The stand's card lists the day's book.
  Tutorial steps host_stand / hire_host / bookings / booked_guest (51 steps).
  Soak: 274 served, 3 lost to service, 1 for a seat.
- **Booking premium** (2026-09-29, user's rule): booked guests pay 2% over the
  menu, booked under the new ledger line Bookings (income, shown after
  Takings); walk-ins stay under Takings and keep coming whether or not anyone
  books. The 2% carries fractions across guests (`Bookings.carry`), so it is
  exact overall though one 20g bill's 0.4g never rounds to a coin.
- **Round of 2026-09-29 (user's list):** C in the build bar takes back the last
  placement (`BuildController.history`, a drag at once; full refund for a
  blueprint, half for a finished piece). Loose goods sell for half value
  (`TavernWorld.sell_stack`, Sold stock line, `world.sold` in the books).
  Auto-order (`AutoSupply`): targets buy their ingredients after the first
  delivery; never-buy marks; keeps wages; 70 game-s cooldown; halves to fit
  the yard. Faint outlines (gold staff, blue guests: `PawnMesh.outline_material`)
  and thought bubbles (`ThoughtBubble`, `ThoughtDirector`, frame clock only),
  both switchable in Settings > Video. Idle staff wander to built floors 75%
  of the time (stone twice as likely). HUD 10% smaller, 1px borders, softer
  corners, fading panels, a day bar with the rushes marked, "N idle / N
  waiting" in the header, a fish-dish chip. Soak hires a waiter when the
  advice says to. Level 2939 / 1841 / -128g (goal 1100: auto-order made it
  much easier; goal left for the user to decide). Chaos 81 `8d3250b4`,
  90 `b6807bbe`, 33 `f0fa2628`. Max tavern 17.1 ms median, 30.9 ms p95.

