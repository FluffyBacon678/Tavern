# Tutorial design — and the tutorial as the smoke test (2026-09-28)

**Status (2026-09-28):** findings 1-3 and 5-8 fixed; the tutorial (9 lessons,
46 steps, fishing included) is playable from New Game > Tutorial and passes as
the smoke test (`dev/tutorial_smoke.tscn`: 46/46 in about 10 real seconds;
`-- --shots <dir>` windowed saves a picture of each step, the camera on what
the step is about). Every suite takes `-- --brief`, and `bash dev/run_tests.sh`
runs them all. Still open: finding 4 (who is building a blueprint), highlights
for hover-only steps, and the phase 3 lesson.

Goal for 1.0: the first demo opens with a tutorial that teaches **every feature
and how to use it**, with no lore or story. The same list of steps is run by an
automated player as the game's end-to-end smoke test, so a feature that breaks
fails the step that teaches it.

## 1. What a first session actually looks like

Recorded by `dev/playthrough.tscn`, which plays from the title screen through
the real buttons, as a newcomer following the current checklist. Screenshots
and notes go to the folder given after `--`.

| # | Finding | Severity | Fix for 1.0 |
|---|---|---|---|
| 1 | **Soft-lock in two minutes.** Following "lay some flooring", a 14 x 10 floor cost 280g of 600g, the walls took the rest, and the kitchen, tables and supplies were all refused. No guests all day, 58g of wages, day 1 closed at -58g with no way back. | Blocker | The tutorial gives a fixed plan and budget; build steps show a **running cost against the purse** before committing; warn when a purchase would leave less than a delivery plus a day's wages. |
| 2 | **Walls are one click per tile** (40 clicks for one small room; doors too). Floors can be dragged, walls cannot. | High | Drag walls as a line, or drag a rectangle's outline ("room tool": floor + walls + a door gap in one drag). |
| 3 | **No warning before debt.** The trouble line only speaks once the purse is already negative. | High | Warn at the moment of spending, and in the trouble line when the purse falls below one day's wages. |
| 4 | **Construction is slow with one porter**: 188 game seconds (five game hours) for one room. Nothing says why or how to speed it up. | Medium | The tutorial teaches "hire a second porter to build faster"; the blueprint tooltip says who is building it and the queue length. |
| 5 | **The day summary says "Sell up or serve more"**, but nothing can be sold. | Medium | Replace with real advice from `Trouble` (let staff go, order supplies, fix the named fault). |
| 6 | **Panels stay open across the day's end** (the order screen sat behind the summary). | Low | Close the transient panels when the summary opens. |
| 7 | **Time runs from the first frame**, at 07:32, before the player has done anything. | Low | The tutorial starts paused and says so; the sandbox could too. |
| 8 | The floor hint says boards "pay for themselves", which invites the oversized floor of finding 1. | Low | Hint the size: "a room about 10 x 8". |

## 2. Shape of the tutorial

A third entry on the New Game page, above the demo scenario: **Tutorial**. It is a
prepared situation, not a sandbox, so each lesson starts from a known state:

- A plot with the road, the river and the cart; **enough gold for the plan and
  no more room for mistakes** (a fixed purse per lesson, topped up by the
  tutorial where a lesson needs it).
- **Time is paused** during every "do this" step and resumes only when a step
  needs time to pass ("watch the porter build it"). The player is told when and
  why time is running.
- One instruction at a time in a panel at the top right, where the checklist is
  now: **what to do**, **why** in one line, and a **Show me** button that points
  at the control or the tile.
- **Highlights**: the HUD button to press pulses; the tile area to build on is
  outlined on the ground; a person to click gets a ring.
- **Done-conditions are derived from the world**, the same way the checklist's
  are (`Objectives`): the step completes when the thing is true, however the
  player got there. Nothing is ticked by pressing Next.
- **Skip lesson** and **Replay lesson** in the pause menu; the whole tutorial can
  be left at any time, and the lessons list shows which are done.
- No story, no characters speaking: plain instructions.

## 3. The lessons and steps

Each step lists: the instruction, what is highlighted, and the done-condition.
The `id` is what the smoke test reports.

### Lesson 1 — Looking around
| id | Instruction | Highlight | Done when |
|---|---|---|---|
| cam_move | Move the view with W A S D (or the screen edge). | — | camera focus moved 4+ tiles |
| cam_zoom | Zoom with the mouse wheel. | — | distance changed |
| cam_turn | Turn the view with Q and E. | turn buttons | yaw changed |
| time_speed | Time is paused. Press 1 to run it, 4 for 5x, Space to pause again. | speed buttons | speed was set above 0, then back to 0 |
| inspect | Click a member of staff to see who they are and what they do. | a porter's ring | inspector shows a worker |

### Lesson 2 — Building a room
| id | Instruction | Highlight | Done when |
|---|---|---|---|
| build_open | Press B to open the build bar. | Build button | build bar visible |
| floor | Pick Wood Floor and drag a 10 x 8 rectangle on the outline. | outline on the ground; cost shown while dragging | 80 floor tiles placed in the outline |
| walls | Pick Timber Wall and drag along the outline's edge. | edge outline | walls placed on the outline edge (needs finding 2) |
| door | Leave a gap on the road side and put a Door in it. | the gap | a door on the south wall |
| wait_build | Blueprints are built by your porter. Run time (1 or 4) and watch. | the porter | no blueprints left |
| rotate | Pick a Table; press R to turn it; place it. Chairs go right beside it. | table spots | 2 tables, 4 seats |
| demolish | Knock down the spare chair with Demolish. You get half back. | Demolish | a chair removed |
| rooms | Press O to see what the game counts as a room. | Rooms button | room overlay shown with a Dining Hall |

### Lesson 3 — The kitchen and storage
| id | Instruction | Highlight | Done when |
|---|---|---|---|
| kitchen | Build a Prep Table, an Oven and a Brewing Vat in the kitchen corner. | outline | all three built |
| shelves | Build two Storage Shelves. One tile holds one kind of goods. | outline | 4 storage tiles |
| filter | Click a shelf and set it to hold only flour and yeast. | shelf ring | a storage filter set |
| basin | Build a Wash Basin. Dirty plates block tables until they are washed. | outline | sink built |
| counter | Build a Serving Counter between kitchen and dining: the kitchen plates orders there for the waiter. | outline | counter built |

### Lesson 4 — Supplies and production
| id | Instruction | Highlight | Done when |
|---|---|---|---|
| order_open | Open Supplies. | Supplies button | order screen visible |
| order_edit | Change an amount with - and +, then Confirm. | Confirm | a delivery arrived |
| haul | Your porter carries it to the shelves. Run time. | the yard | yard empty |
| production | Open Production (P). Each recipe keeps a number in stock. Set bread to 6. | the bread row | bread bill target 6 |
| first_bread | Wait for the cooks: dough, then bread. | prep table, oven | 1+ bread made |
| hands_on | Click the oven and choose "Bake by hand" to do one batch yourself: quality depends on your timing. | oven | a manual bake finished |

### Lesson 5 — Staff
| id | Instruction | Highlight | Done when |
|---|---|---|---|
| staff_open | Open Staff (K). Each person has a position that decides their work. | Staff button | staff panel visible |
| hire | Hire a Busser: fee now, wage every evening. | Busser card | a busser on the staff |
| priority | Set your waiter's Bill priority to 1. | that cell | waiter BILL priority 1 |
| dismiss | (Optional) Letting someone go pays them for the day. | — | — |

### Lesson 6 — Service
| id | Instruction | Highlight | Done when |
|---|---|---|---|
| open_doors | Run time. Guests arrive on the road from 08:00. | clock | first guest seated |
| take_order | A raised hand means they are ready to order: a waiter takes it at the table. | the guest | an order taken |
| plate | The cooks plate it on the counter; the waiter carries it over. | counter | first item served |
| bill | After eating they wait for the bill. Prompt bills earn tips. | the guest | first bill paid with a tip |
| clear_wash | The busser clears the plates to the basin; the cleaner washes them. | basin | first dishes washed |
| hover_guest | Point at a guest to see their mood, patience and bill. | a guest | hover card shown for a guest |

### Lesson 7 — Money and reputation
| id | Instruction | Highlight | Done when |
|---|---|---|---|
| ledger | Open the Ledger: today's takings, tips, supplies, wages. | Ledger button | ledger visible |
| trouble | The red panel names the one thing most costing you money. | trouble panel | (shown when present) |
| day_end | At midnight the day closes: wages are paid and reviews are read. | clock | day summary shown |
| reviews | Stars bring more guests; slow service, dirty tables and a short menu cost stars. | stars | summary dismissed |

### Lesson 8 — Fishing (day 2)
| id | Instruction | Highlight | Done when |
|---|---|---|---|
| hire_fisher | Hire a Fisherman; the position opens on day 2. | Staff button | a fisherman on the staff |
| fishing_spot | Build a Fishing Spot at the water's edge. | a bank tile touching the river | spot placed |
| catch | The fisherman fishes and carries the catch in: trout or perch, 1-2 a time. | the fisherman | first fish caught |
| clean_fish | A cook cleans each fish at the prep table: a fillet and a head. | prep table | first fillet |
| fish_dish | The oven grills fillets, and boils heads with water into soup. | oven | first fish dish |
| sell_fish | Fish is on the menu: guests order from whatever is in stock. | | a guest eats fish |

### Lesson 9 — Growing
| id | Instruction | Highlight | Done when |
|---|---|---|---|
| land | Buy land (Buy land) to grow the plot. Each parcel costs more. | Buy land button | panel opened (buying optional) |
| well | A Draw Well by the river gives free water, drawn by porters. | river edge | well built |
| save | Esc opens the pause menu. Save your tavern. | Save game | saved |

### Future lessons, added with their features
- **Guest types (phase 3):** read a guest's preferences on the hover card; add
  a menu item a group asks for; take a reservation at the host's stand.

Each future feature is not done until its lesson exists and passes the smoke test.

## 4. The tutorial is the smoke test

One data list, two runners:

- `src/tutorial/tutorial_step.gd`: `id`, `lesson`, `instruction`, `why`,
  `highlight` (a HUD path, a tile rect or a pawn role), `done: Callable(world)`,
  and **`perform: Callable(world)`**: what the automated player does for this
  step, through the same calls the input layer makes (as `dev/playthrough.gd`
  does), never by setting results directly.
- `TutorialDirector` (in game): shows the current step, highlights, checks
  `done` every half second, pauses and resumes time.
- `dev/tutorial_smoke.tscn` (headless, turbo): for each step, call `perform`,
  then wait up to the step's time budget for `done`. A step that cannot be
  completed by the player's own actions is a bug in the game, not the test.

## 5. Streamed, compact test output

Every suite gets a `--brief` flag (default for the tutorial smoke):

```
TUT 01 cam_move      ok   0.4s
TUT 07 wait_build    ok  96.2s  gold=182 day=1 09:10
TUT 19 first_bread   FAIL 300.0s  done-when: 1+ bread made
     cause: Make Dough waiting on water 0/1 (no source outside the bench)
     staff: Porter: idle | Cook: fetching flour ...
TUTORIAL 31/32 ok  1 fail  in 412s game / 38s real
```

- One line per step; detail **only on failure** (the step's own
  "why not" from the world: Trouble, feed_problem, staff statuses).
- A final one-line total. Nothing else is printed unless `--verbose`.
- The same `--brief` for the regression suites: failures and the total only,
  instead of 400 PASS lines.

## 5b. What was built

- Soft-lock fixes: drag cost shown against the purse and the reserve (a
  delivery plus tonight's wages) in the build bar; red ghosts for what the
  purse cannot cover; a one-time "Careful" warning on crossing the reserve;
  the trouble panel warns when the purse is below tonight's wages; walls drag
  as a rectangle outline (or a line); a door clicked onto a wall replaces it;
  demolishing refunds a blueprint in full and a finished piece by half
  (ledger line "Refunds"); walls 4g, doors 10g; sandbox purse 800g; new games
  from the title screen open paused; panels close when the day's summary
  opens; the summary's debt advice is something a player can do; the summary
  lists every ledger line.
- `src/tutorial/`: TutorialStep (text, why, highlight, pace, budget, done,
  begin, perform), TutorialPlan (the 40 steps and the room layout),
  TutorialDirector (the in-game panel, highlights, time), PlayerActions (the
  player's actions, shared by the smoke test and `dev/playthrough.tscn`).
- The tutorial is a level (`LevelCatalog.tutorial()`): no goal, 1500g, the
  demo's seed. Saves keep the step (`tutorial_step`).

## 6. From demo to 1.0 (order of work)

1. Fix findings 1–3 (cost preview and spending warning, line/rectangle walls,
   early debt warning).
2. Step list + `tutorial_smoke` with `--brief`, lessons 1–8 above.
3. `TutorialDirector` UI: instruction panel, highlights, time control,
   skip/replay, Tutorial entry on New Game.
4. Findings 4–8.
5. Then phase 3 and 4 features, each landing with its lesson.
