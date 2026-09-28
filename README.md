# Mobile Tavern

A medieval tavern / restaurant management game for **PC and Android**, built in
**Godot 4.7**. Part colony sim (RimWorld, Prison Architect, Dwarf Fortress),
part active service game (Papa's Pizzeria, Penguin Diner).

Full design is in [`docs/medieval_tavern_game_design_notes.txt`](docs/medieval_tavern_game_design_notes.txt).

**Art direction:** OSRS-style low-poly 3D world, 2D menus.

---

## Current state

**2026-09-25 texture polish:** shared material detail, clearer goods, quieter
floorboards and a verified item gallery. See [`docs/TEXTURE_POLISH.md`](docs/TEXTURE_POLISH.md)
for captures, rendering measurements and verification limits.

**2026-09-22 visual polish:** warmer medieval terrain and furniture, clearer
characters, camera-facing wall cutaways and a framed HUD with attributed free
icons. See [`docs/VISUAL_POLISH.md`](docs/VISUAL_POLISH.md) for scope, measurements
and screenshots. Subsequent gameplay work is preserved.

**2026-09-21 Tier 1 polish:** world orchestration split into HUD/bootstrap/scenario
components (1,061 → 364 lines in `world_3d.gd`); fixed 15-pawn benchmark reduced
from 352 to 65 draw calls; three-day item and gold reconciliation passed.
Supplier deliveries now reject insufficient unloading space without charging.
See [`docs/POLISH_REPORT.md`](docs/POLISH_REPORT.md) for commands, measured
results, unchanged balance values, and remaining work. Android remains untested.
The milestone tables below describe the prototype; their earlier performance
figures are historical and use different scene loads.

### M0 — main menu and base ✅ verified

- Autoloads: settings persistence, save slots, scene routing, event-ID audio
  with synthesised placeholder UI sounds.
- Procedural forest backdrop ported from ForestFirewallpaper: noise terrain with
  ponds, winding rivers and paths, nine tree species with per-tree canopy sway,
  ~30 kinds of ground cover.
- Main menu (new tavern with name + seed, continue, settings, quit) and a
  settings screen (audio mixer, quality preset, fullscreen, animation toggle).

### M1 — 3D world and construction 🔨 in progress

- **Low-poly terrain** built from the same `TerrainGrid` the menu uses, with
  elevation *carved by* the grid so rivers become real valleys.
- **3D forest** — the same nine species as 2D, as flat-shaded meshes.
- **Dual-mode camera** — locked near-isometric or free orbit, switchable live.
- **A buildable plot** — a 26×20 site levelled flat, cleared of forest and water,
  eased into the surrounding landscape by a falloff ring.
- **Construction** — 13 buildables across Structure / Dining / Kitchen / Storage,
  with ghost preview, footprint highlight, rotation, refusal reasons, demolish
  and a gold cost per piece.

Measured on an Intel Arc 140V at 1280×720, GL Compatibility:

| | |
|---|---|
| World generation | **~350 ms** (96×96 tiles, ~1,700 trees, ~155k triangles) |
| Runtime, empty plot | **60 fps**, **118 draw calls** |
| Runtime, 199-piece tavern | **60 fps**, **167 draw calls** |

### M2 — pawns 🔨 in progress

- **`NavGrid`** over `AStarGrid2D`: water blocks, walls block, doors and
  furniture do not. Diagonals are allowed but not through a corner gap between
  two solid tiles, so pawns cannot slip out of a sealed room.
- **`Pawn`** — a deliberately generic person. Walks tile-to-tile but renders
  continuously, turns to face its heading, has a distance-driven walk cycle
  (so the feet do not skate), idles by wandering, and can carry something.
- Click anywhere outside build mode to order every pawn there.

Verified: with the demo tavern built, 5/5 pawns placed outside route into the
kitchen through the single door, averaging 11 tiles where a straight line would
be 8.

### M3 — job system 🔨 in progress

- **`JobBoard`** — a global queue. Anything that wants work done posts a `Job`;
  idle workers ask for the best one they will take. Priority dominates
  (a priority-1 job across the map beats a priority-2 underfoot, which is what
  makes the work matrix mean anything); distance only breaks ties.
- **`Worker`** — lives as a child of a Pawn, so the Pawn stays a generic body.
  A customer will be the same Pawn with no Worker attached.
- **Construction is its first customer.** Placing a piece now creates a
  *blueprint*: it reserves the tile, does not block movement, and waits for a
  builder to walk over and work on it.

Verified end to end: 199 blueprints queued, five pawns built every one of them,
queue drained to zero with no deadlock and no stranded workers.

### M4 — the physical economy ✅ proven

The milestone the design notes call foundational. Goods are objects in the
world, not numbers in a counter.

- **`ItemWorld`** — one stack per tile, of one kind. That constraint is what
  makes hauling mean something: a full storage tile is genuinely full, and
  distance to the nearest free one is a real cost.
- **`Recipe`** — generic inputs / station / work / outputs. There is no
  `BakeBread()`; bread and beer are catalog entries fed to one engine.
- **`JobGenerator`** — scans the world and derives work from two rules: loose
  goods that are not where they belong become hauls, and a station with its
  inputs to hand becomes a cooking job. Nothing else posts these, so a failed or
  cancelled job is simply re-derived next pass.
- **Supplier orders** — the notes' prototype ordering screen, charged to the purse.

Verified by reconciliation rather than by eye. 110 seconds from one delivery:

| | delivered | present | consumed | expected |
|---|---|---|---|---|
| Flour | 8 | 7 | 1 | 1 dough ✓ |
| Yeast | 8 | 7 | 1 | 1 dough ✓ |
| Water | 10 | 4 | 6 | 1 dough + 5 brews ✓ |
| Malt / Hops | 6 / 6 | 1 / 1 | 5 / 5 | 5 brews ✓ |
| Dough | — | 0 | 1 | baked ✓ |
| **Bread** | — | **2** | — | 1 dough × 2 ✓ |
| **Beer** | — | **20** | — | 5 batches × 4 ✓ |

### M5 — customers ✅ the loop closes

A customer is the same `Pawn` with a `CustomerBrain` instead of a `Worker` —
the body, pathfinding and animation all came for free, exactly as the notes
intend.

- **`Seating`** — a seat is *derived*, not placed: a chair that happens to be
  orthogonally beside a table. Move the chair and the seat moves with it.
- **`CustomerBrain`** — arrive, seek a table, sit, read the menu, order, wait,
  eat, pay, tip, leave. Patience governs the whole thing; run out waiting for a
  seat or for food and they leave unhappy.
- **Serving is an ordinary haul job** — fetch this from wherever it is, put it
  on that table. No new machinery was needed.
- **Food is delivered physically.** The customer is not told its order arrived;
  it looks at the table and takes what it sees.

Verified: **7 in the house, 10 served, 0 lost, 110g taken**, purse 250 → 143
(delivery) → 253. Bread 4 made / 1 left, beer 20 made / 12 left — the missing
ones were eaten and paid for.

> Patrons wear dark travelling cloaks, staff wear bright tunics. Telling them
> apart at a glance is not decoration — it is the difference between reading a
> busy room and squinting at it.

### M6 — the trading day ✅ it can now be lost

- **`DayClock`** — opening hours, a midday and an evening rush, and a close of
  business. Arrivals follow a footfall curve, so the day has a shape to staff
  against rather than a flat trickle.
- **`Ledger`** — every coin in or out is attributed. "You are down 40g" is
  useless; "wages 30, supplies 107, takings 128" tells the player which decision
  was the bad one. Because all money routes through it, nothing can quietly move
  the purse without appearing in the reckoning.
- **Wages** charged at close, **even when the purse cannot cover them** — going
  into debt is a legitimate way to lose, and skipping payroll would hide it.
- **End-of-day summary**, a full-screen stop rather than a toast.
- **The menu is limited to what is in stock** (§12's "no stock → unavailable"),
  so nobody orders bread the tavern cannot make.

Measured over four consecutive days, restocking each morning:

| Day | Served | Lost | Profit |
|---|---|---|---|
| 1 | 2 | 2 | −224g (stocking up) |
| **2** | **9** | **0** | **+83g** |
| 3 | 5 | 2 | −87g |
| **4** | **6** | **3** | **+29g** |

A longer day reached **15 served, 1 lost, +147g**. Days 1 and 3 lose because
the test orders a full delivery every morning whether one is needed or not —
which is exactly the mistake the game should let a player make.

### M7 — production bills ✅

Standing orders per §21: "maintain 10 bread". Two numbers, not one — produce up
to `target`, do not restart until stock falls to `resume_below`. A single
threshold makes a kitchen flicker on and off around it, starting and abandoning
work every time a loaf is eaten.

Bills are **tavern-wide per recipe**, not per bench: "keep 10 bread" is a policy
about the larder, and two ovens should share a target rather than each chase its
own.

Verified by holding everything else still — one delivery, no customers, 100s:

| | without bills | with bills |
|---|---|---|
| Beer ever made | 20 (ran until ingredients gone) | **12** — exactly the target |
| Malt / hops left | 1 / 1 | **3 / 3** |

Ingredients are now preserved instead of being converted the moment they arrive,
which is what makes stock something to manage.

Not built yet: reviews and reputation, dirty dishes, manual play.

> **Goods must never silently vanish.** Two leaks were found this way, both
> invisible in play: a deposit overflowing onto a tile already holding something
> else, and a station finishing a batch with no room on its bench. Both returned
> 0 from `add()` and dropped the goods. Every path that puts items down now goes
> through `ItemWorld.place_near()`, which spreads outward and warns if it truly
> cannot place. The first version of this ran for 110 seconds and quietly ate
> six yeast — the only reason it was caught is that the report did not add up.

> **Emergent, not a bug:** beer massively out-produces bread. Brewing is one
> station; bread is prep table → haul → oven, so it pays two extra walks per
> loaf. Layout already matters, exactly as the notes intend.

> Two failure modes worth knowing about, both fixed and both invisible until
> they bite:
> - A worker that takes the single best job and finds nowhere to stand will idle
>   for a whole seek interval while the board is full of work. It now considers
>   several candidates per attempt, and forgets past failures after 8s so a job
>   refused because of a temporary obstruction becomes available again.
> - A pawn can be standing on a tile when a wall finishes on it. Pathing from a
>   solid tile returns nothing, stranding it permanently, so `find_path` opens
>   the start tile for the search — a pawn may always walk *out* of somewhere it
>   should not be.

> **Known cost:** each pawn is six separate `MeshInstance3D` limbs, because the
> limbs animate independently. That is roughly ten draw calls per pawn — fine at
> five, but thirty pawns would add ~300. Worth merging or instancing before the
> tavern gets busy.

### Building

`B` or the **Build** button opens the palette. Pick an item, click to place, `R`
rotates, right-click or `Esc` leaves build mode. **Demolish** removes a piece —
the object layer first, so clicking a table takes the table, not the floor
beneath it.

Floors and objects are separate layers, so a table stands *on* a floor but two
tables cannot share a tile. `BuildGrid` answers "what blocks this tile?" because
that is the question pathfinding and room detection will ask later.

---

## Running it

Godot 4.7.2 lives at `../_tools/godot/`. Open the project folder in it and press
F5, or:

```bash
"../_tools/godot/Godot_v4.7.2-stable_win64.exe" --path .
```

In the world: `WASD` pan, wheel zoom, `Q`/`E` rotate, right-drag orbit (free
mode only), middle-drag pan, `C` toggles camera mode, `Esc` back.

### Capturing a screen without clicking through

`scenes/_screenshot_harness.tscn` loads a scene, waits for it to settle, writes a
PNG and quits. A scene can expose `screenshot_setup(opts)` to be posed first:

```bash
"../_tools/godot/Godot_v4.7.2-stable_win64_console.exe" --path . res://scenes/_screenshot_harness.tscn --resolution 1280x720 -- res://src/world/world3d/world_3d.tscn C:/tmp/shot.png 9 "camera=free,distance=26,pitch=18"
```

---

## Layout

```
project.godot          engine config: autoloads, renderer, input map
scenes/                boot entry point, screenshot harness
src/
  autoload/            GameSettings, GameState, AudioDirector, SceneRouter
  core/                value noise, software rasteriser, mesh builder, atlas cache
  world/
    tree_species.gd    species table: distribution + palettes, shared by 2D and 3D
    forest/            2D menu backdrop: atlases, terrain grid, shaders
    world3d/           3D world: terrain mesh, tree meshes, camera rig
  ui/                  theme, main menu, settings
assets/prototype/      disposable placeholder art, by category
docs/                  design notes
```

### What is shared between 2D and 3D

`ValueNoise`, `TerrainGrid` and `TreeSpecies` are **world data** and feed both
renderers — so a birch is the same green in the title screen and in the game,
and the forest's makeup is one file to change. `TerrainGrid.generate()` takes an
optional ground atlas precisely so the 3D path can pass `null` and stay free of
the sprite code.

`Raster`, `TreeAtlas`, `GroundAtlas` and the 2D MultiMesh renderer are menu-only.

---

## How it works

**Terrain.** One pass of layered noise picks each cell: water first (ponds as
noise blobs, rivers as a *narrow band* on a separate channel, which is what makes
them wind rather than pool), then paths, then vegetation modulated by two biome
fields that carve clearings. In 3D, corners touching a water cell are pushed
below the waterline and the field is then smoothed, so rivers get sloped banks.
Generating height independently would run rivers up hillsides.

**Geometry.** `MeshBuilder` emits flat-shaded, vertex-coloured triangles — no
shared vertices, no smoothed normals. Colour in the vertex stream means terrain
and all eighteen tree variants share one material.

> ⚠️ Godot culls by screen-space winding and treats **clockwise** as
> front-facing. `MeshBuilder.add_tri` takes counter-clockwise vertices (so the
> normal is the honest outward one) and reverses them on emit. Get this wrong and
> terrain silently vanishes when viewed from above, while closed shapes like tree
> canopies still look roughly fine — which makes it easy to misdiagnose.

**Atlases (2D).** Sprites rasterise into a byte buffer via `Raster`, built from a
*fixed* seed so they are identical every run and cached as PNGs under
`user://cache/`. **Change a sprite draw function and you must bump
`AtlasCache.VERSION`**, or players keep seeing the previous build's sprites.

---

## Open decisions

- **Camera.** Settled in practice: **locked is the default**, free stays
  available as a "look at your tavern" mode. Building the tavern made the case
  on its own — from the free camera at a low pitch, the near wall fills half the
  screen and the room behind it is invisible. Solving that properly means
  hiding walls between the camera and the interior, which is a real feature and
  a poor use of time before the simulation exists.
- **Renderer.** `gl_compatibility` — widest Android support and well matched to
  flat-shaded low-poly. Moving to `mobile` (Vulkan) buys lighting at the cost of
  older devices.
- **World generation threading.** 499 ms is fine behind a fade; it will not stay
  fine if maps grow. All GDScript, so it can move to a thread when needed.
- **Character pipeline.** Rigged models and animation, replacing sprite frames.

⚠️ **On `OSRS-Environment-Exporter`:** it reads the OSRS game cache, and those
models and maps are Jagex's copyrighted assets — they cannot ship. The *look* is
fine to emulate; the assets are not.

---

## Assets and licensing

| Source | Licence | Safe to ship? |
|---|---|---|
| `ForestFirewallpaper` (yours) | MIT | **Yes.** Keep the notice. |
| `seraphile/rimshare` | **CC BY-NC-SA 4.0** | **No.** |
| OSRS cache via the exporter | Jagex copyright | **No.** |
| Procedural art in this repo | ours | Yes |

**`rimshare` is NonCommercial and ShareAlike** — it cannot ship in a game you
sell, and ShareAlike would force its licence onto derivative art. Nothing from it
is used; worth keeping it that way. For icons prefer
[game-icons.net](https://game-icons.net) directly (CC BY 3.0, commercial OK with
attribution) over the re-export in `rimshare`.

Commercial-safe placeholder sources: [Kenney](https://kenney.nl) (CC0),
[Quaternius](https://quaternius.com) (CC0 low-poly 3D, a good fit for this art
direction), [OpenGameArt](https://opengameart.org) (filter to CC0/CC-BY),
[freesound.org](https://freesound.org) (filter to CC0).

Keep a running attribution list as assets go in.

---

## Progress toward a playable demo

Roughly **80%**. The loop is closed and it can now be *lost*: **buy → haul →
store → make → serve → get paid → pay wages → count the day**.

### Balance finding worth acting on

Measuring a real day exposed something no amount of reading the design would
have: **bread is badly priced against its own labour.**

| | walks per unit | price |
|---|---|---|
| Beer | ~0.75 (3 fetches → 4 mugs, one station) | 8g |
| Bread | ~2.0 (3 fetches → dough, carry to oven → 2 loaves) | 10g |

Bread costs **2.7× the labour for 1.25× the price**, so beer quietly subsidises
it and a bread-heavy tavern cannot pay its wages. The two-stage bread flow is
deliberate (§8) and worth keeping — it is what makes kitchen layout matter — so
the lever is price or batch size, not the recipe. Left alone pending a decision;
these are design-note numbers, not invented ones.

Wages were retuned (12g → 6g per head): that figure was invented here, and at
12g five staff cost more than the tavern could physically earn.

| Area | Weight | State |
|---|---|---|
| Scaffold, settings, routing, audio | 5% | ✅ |
| Menu + UI shell | 5% | ✅ |
| World generation + rendering | 12% | ✅ |
| Camera + tile picking | 4% | ✅ wall cutaway added |
| Construction | 10% | 🔨 90% — no room detection |
| Pawns + pathfinding | 11% | 🔨 90% — no collision avoidance |
| Job system | 14% | 🔨 88% — no priority UI, no skills |
| Production | 10% | 🔨 80% — bills work; no per-bench control, no skills |
| Storage, hauling, items | 8% | 🔨 70% — no storage filters |
| Customer loop | 11% | 🔨 70% — no reviews, no customer classes, no dirty dishes |
| Economy | 6% | 🔨 90% — buying, selling, wages, daily P&L, persisted |
| Satisfaction + reviews | 5% | 🔨 15% — tips scale with waiting, nothing else |
| Manual gameplay | 3% | ❌ |

### Onboarding and a winnable opening ✅

A player dropped on an empty plot with thirteen buildables and a running clock
has no way to know that bread needs *two* stations, that haulers need somewhere
to put a delivery, or that a chair is only a seat when it sits beside a table.
`Objectives` says it, in order, one hint at a time, then removes itself.

Objectives are **derived, never tracked** — each asks the world a question on
the HUD's existing cadence. Same decision as `JobGenerator`, same payoff: they
cannot desynchronise, cannot complete twice, survive save/load with zero
serialisation, and *un-tick* when you demolish the oven. That last one is
asserted in the regression suite.

**The opening was unwinnable, and only measuring it showed that.** A guided
player builds ~288g of tavern — the easy-to-forget part being forty-eight floor
tiles at 2g. Plus a 107g delivery and 30g of day-one wages, the opening costs
~425g before a loaf is sold. At the old 250g purse the delivery was never
affordable: four measured days served **zero** customers and lost forty.

Starting gold is now 500g, and the guided opening measures as:

| Day | Served | Lost | Profit | Purse |
|---|---|---|---|---|
| 1 | 0 | 4 | −425g (building the tavern) | 75g |
| 2 | 6 | 0 | **+41g** | 116g |
| 3 | 10 | 1 | **+88g** | 204g |
| 4 | 3 | 5 | 0g | 204g |

Day 4 stalls because water hit exactly zero — the cue to reorder. Ordering a
full delivery *every* morning instead ends the same four days on 4g rather than
204g, so over-buying still costs you. That is the lesson the loop is meant to
teach.

Reproduce with `demo=starter` (a player-scale build that charges the purse,
unlike the 199-piece systems demo).

> ⚠️ **Floors currently have no mechanical effect** — they are a third of the
> opening spend and buy nothing but appearance. Either give them a purpose
> (§23 room quality) or reconsider the price.

### Work priorities ✅

The matrix from §16: staff down the side, kinds of work across the top, a number
in every cell. **Staff [K]**.

A matrix rather than a per-person menu, because the question a tavern keeper
actually asks is comparative — *who is on serving?*, *is anybody hauling?* — and
that is unanswerable if you have to open five people in turn to find out. Lower
wins; a blank cell means they refuse that work. Clicking a cell cycles it, so
the whole crew is rebalanced without a dialogue.

Edited priorities are saved, and the regression suite asserts a *non-default*
pair survives the round trip — a default-valued test would pass even if nothing
were persisted at all.

### Crowd separation ✅

Five staff sent to the same shelf used to stand in exactly the same spot,
rendering as one body. They now give each other room.

Deliberately **cosmetic**: it nudges the body, never `tile` or the path. Real
avoidance means re-pathing around other pawns, which in a tile game buys jitter
and doorway deadlocks for a problem that is purely visual — five people fetching
from one shelf genuinely *are* going to the same tile, and should read as a
queue rather than as one person.

Pawns register in a static list rather than gaining collision shapes; the counts
are in the dozens and a physics layer would be a lot of machinery for a
shuffle.

### Selection and inspection ✅

Click anything and ask what it is. A management game is unplayable without it:
you can watch five identical figures cross a room, but until you can click one
and read *"Hilda Fairbrook — baking (40%)"* you cannot tell a busy tavern from a
stuck one, and diagnosing the machine is the whole appeal of the genre.

- **Staff** — name, live status, what they are carrying, and their work
  priorities *in the order they will pick jobs up*, which is the question being
  asked.
- **Patrons** — what they are waiting for and how much patience is left.
- **Stations** — what they make, the recipe, and the standing order's state.
- **Storage** — what is actually on the shelf.
- **Loose goods** — what and how many.

It refreshes live rather than snapshotting; a panel showing what a pawn *was*
doing would actively mislead. Picking prefers people over buildings over items,
because people stand on the floor you would otherwise select.

> Left-click used to order every pawn to walk to the clicked tile. That was a
> pathfinding-test crutch from before the job system existed, and "all staff
> drop everything and walk here" is not something a tavern keeper should be able
> to do by accident. It is now selection.

### Save / load ✅

Writing a tavern to disk, and reading it back.

The notable thing is **how little needs saving**. Terrain, forest and plot are
pure functions of the world seed, so they are regenerated rather than stored.
The job board is **not saved at all** — `JobGenerator` derives every job from
world state on a timer, so restoring the buildings and the goods is enough for
the same work to be re-derived on the first scan. That falls straight out of the
"derive, do not track" decision: an event-driven job system would have needed
serialising, and half-finished jobs are exactly what corrupts a save.

Customers are deliberately dropped — a patron teleporting back to a half-eaten
meal is worse than one who left while you were away. Goods in a worker's hands
are put down at their feet, and the hauler picks them up again next scan.

Autosaves at close of business, when the books are ruled off and nothing is
half-done. Verified by round trip in `dev/regressions.tscn`: save, build a fresh
world from the file, and assert buildings, stock, purse, name and staff all
match. Writing a file proves nothing; only the round trip does.

## The loop, end to end

What actually happens now, unattended:

```
order supplies  →  cart unloads at the roadside
                →  haulers carry it to the shelves
                →  cook fetches flour + water + yeast to the prep table
                →  makes dough, carries it to the oven, bakes bread
                →  brewer fetches malt + hops + water, brews beer
                →  standing orders stop production at the target
customers       →  arrive on the footfall curve, midday and evening rushes
                →  claim a chair beside a table, read the menu
                →  order only what is in stock
                →  waiter fetches it and puts it on their table
                →  they eat, pay, tip by how fast they were served, leave
                →  or run out of patience and walk out
close of day    →  wages charged, books ruled off, profit or loss
```

Every step is physical: nothing is a counter being incremented.

## How close is a demo?

Two different questions, two different answers.

**Against the design notes' own first playable target (§41): ~85%.**
Eighteen of its twenty-one beats work. Missing: a **host** who seats people
(currently self-service), **reviews** (§19 — tips exist, the diagnostic does
not), and **manual play** (§22 — the player cannot step in during a rush).

**As something you could hand to a stranger: ~60%.** The gap is not features:

| Blocker | Why it matters |
|---|---|
| ~~No save/load~~ | ✅ Done, round-trip tested. |
| **Never built for Android** | The whole point is PC *and* Android, and this has only ever run on Windows. No JDK, no Android SDK, no export templates installed. Touch controls exist but are untested on a device. |
| **No onboarding** | A player dropped on an empty plot with a build menu will not know a tavern needs a prep table before an oven. |
| **Balance swings wildly** | Day totals ranged from −224g to +147g across runs. Playable, not yet judgeable. |
| **Work priorities invisible** | The §16 matrix exists in code and cannot be seen or changed. |

## Plan to a demo

Ordered by what unblocks the most:

1. **Android export, end to end.** Install JDK + SDK, build an APK, run it on a
   device. This is first because it is the only item that could still invalidate
   an architectural choice — if GL Compatibility 3D or 500 draw calls do not hold
   up on a phone, better to learn it now than after another month of content.
2. **Save/load.** `GameState`, `BuildGrid`, `ItemWorld`, `BillBook` and `Ledger`
   are all already plain data; the pawns are the only awkward part.
3. **A balance pass**, now that a day can be measured. Bread's labour-to-price
   ratio (below) is the main lever.
4. **Onboarding** — a scripted first day that tells the player what to build.
5. **Reviews and reputation** (§19), then **dirty dishes** to give `CLEAN` work.
6. **Work priority UI** (§16).
7. **Manual play** (§22) — the one genuinely large remaining feature.

Deferred and still true: room detection, pawn collision avoidance (a group given
one order walks as a clump), wall occlusion for the free camera.

Worth doing alongside: **wall occlusion** so the free camera stops hiding
interiors, **room detection** from enclosed wall loops, and **pawn collision
avoidance** — five pawns given the same order currently walk as one clump.

---

## Launching it

A desktop shortcut (**Mobile Tavern**) runs the game directly. It is equivalent to:

```bash
"../_tools/godot/Godot_v4.7.2-stable_win64.exe" --path .
```

The shortcut's icon is `dist/mobile_tavern.ico`, generated by hand from `zlib`
alone (no image library is installed here) so the launcher shows the tavern mug
rather than the Godot logo. It is a launcher for the *project*, not a built
game — packaging an executable is a separate step.

## Packaging a Windows build

For friends to play without Godot. Needs the official 4.7.2 export templates
(installed at `%APPDATA%\Godot\export_templates\4.7.2.stable`) and a
`export_presets.cfg`, which is gitignored: recreate it with one preset named
`Windows Desktop`, platform `Windows Desktop`, `binary_format/embed_pck=true`,
`binary_format/architecture="x86_64"`, `application/modify_resources=false`
(no rcedit here), and `exclude_filter="dev/*, scenes/_screenshot_harness*, docs/*"`.
Then:

```bash
"../_tools/godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" build/MobileTavern.exe
```

One ~105 MB exe with the game inside (the engine is most of it). Zip it with
`build/README.txt` (how to run it, getting past SmartScreen, the controls) and
attach the zip to a GitHub release. Check it boots before sending:
`build/MobileTavern.exe --headless --quit-after 900` should print no errors.
