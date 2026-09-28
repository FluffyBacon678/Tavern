# Ordered demo improvement plan

Prepared 2026-09-22 against the current workspace. Planning only: no game code or balance values were changed for this review.

The aim is a reliable, readable 20–30 minute tavern demo with an original RuneScape-inspired low-poly feel, and code that can support later additions. Preserve the work already present: saving, staff priorities, storage filters, objectives, hosting, reviews/reputation, cleaning, quality, hands-on cooking and the delivery yard.

## What Astra can contribute, and how much

The strongest use here is investigating interactions across systems, implementing bounded changes, and checking the result against repeatable scenarios and screenshots. OpenAI describes GPT-6 Astra as suited to complex reasoning, coding and end-to-end work: [official model documentation](https://developers.openai.com/api/docs/models/gpt-6-astra). That does not establish a percentage improvement for this game.

The impact estimates below are project judgments. The targets are acceptance criteria, not promised results. A focused iteration means one bounded implementation followed by its relevant checks; it is not a guaranteed number of hours. Expect roughly **14–24 iterations** for the complete pass, with the first substantial visual improvement in steps 2–3. Revise estimates after step 1. Physical Android testing and fresh-player feedback depend on access to devices and people.

## Current evidence

- The latest saved three-day reconciliation, `.verification/visual_latest_economy.log`, reports **zero discrepancy for all nine item types**, including cargo and dirty dishes; **433g actual = 433g expected**. This is a valuable baseline, not proof that save/reload and saturated layouts are correct.
- The isolated 15-pawn renderer previously fell from **352 to 65 draw calls**. Richer art retained 65 calls but increased submitted primitives from **7,930 to 22,046**. These are historical measurements of a small benchmark, not whole-game FPS or Android results.
- `.verification/visual_latest.png` shows a coherent warm palette and working wall cutaway. More convincing activity and object placement will now help more than another broad increase in mesh detail.
- Code inspection finds items drawn at terrain height even where furniture or flooring supports them. Pawns have walking/idle/carry presentation but lack visible seated, eating and workstation activity poses.
- The inspector recreates its controls every 0.25 seconds. The toolbar is a fixed row; world placement/selection handles mouse and keyboard while the camera also handles touch.
- Audio has an event API and mixer but currently registers four synthesized UI sounds.
- Code inspection identifies a closing-save path that restores fraction 1.0 with the clock unpaused, allowing another day-end event and wage charge. A full-slots New Tavern also falls back to slot 0, which world initialization can treat as Continue. Reproduce these before fixing them.
- The regression save-round-trip currently writes and deletes the last real slot. Isolate test user data before running that suite. Save capture and full-storage fallback also need targeted boundary tests.
- Some worker, recipe-output and save-restore calls ignore partial placement from `ItemWorld.place_near`. Hands-on work checks ingredients at entry but does not reserve the batch while the player performs it. These paths need conservation/cancellation reproductions despite the passing ordinary three-day run.
- The README and older handoff lists contain historical statements contradicted by current code. Update the current inventory before using either as an execution checklist.

These are existing artifacts and code observations. This planning review did not rerun the engine or validate an Android device.

## Execution order

| Step | Work | Expected improvement | Estimate |
|---|---|---|---|
| 1 | Establish the current baseline and harden save/day/job boundaries | Critical reliability; protects all later work | 3–5 iterations |
| 2 | Correct physical placement and crowd readability | High visual gain with limited new art | 1–2 |
| 3 | Animate existing tavern activities | Very high perceived liveliness; strongest visual priority | 2–3 |
| 4 | Make controls and feedback clear on PC and touch | High usability gain | 2–3 |
| 5 | Finish the RuneScape-inspired art and sound direction | High atmosphere gain | 2–4 |
| 6 | Tune the opening and evaluate economic pacing | High demo/playability gain | 2–3 |
| 7 | Optimize measured bottlenecks and verify release builds | Essential confidence in a shareable demo | 2–4 |

### 1. Baseline and reliability

Start by recording a recoverable snapshot of the current workspace and updating the feature inventory. **Before running regressions, isolate test save data:** the current round-trip fixture uses and deletes `MAX_SLOTS - 1`. Then run the existing parse check, regressions, three-day reconciliation and fixed visual captures. Profile a whole tavern with 5, 15 and 30 pawns now, so later art has a measured budget. Make an early Android export/toolchain check; do not leave discovery of missing prerequisites until release.

Prioritize targeted reproductions for:

- Saving and loading while hauling, cooking, serving, washing and performing hands-on work. Track ground goods, cargo, committed recipe inputs and delivered meals through the transition.
- Closing a day, remaining on the summary, saving there, loading it, and continuing. Payroll and ledger closure must each happen once, with a clear policy for simulation during the summary.
- Starting a new tavern when all three save slots are occupied. Distinguish New Game from Continue, and present a clear slot choice before replacing a tavern.
- A full receiving area, blocked station, demolished destination and failed job. Goods must remain accounted for and recoverable, and stale reservations must not prevent valid work.
- Hands-on work competing with an AI worker for the same station/ingredients. Claim a batch when the player starts; completing the exercise should not discover that another worker took it. Cancellation and invalidation must release the claim without creating or losing goods.
- An interrupted or invalid save. Write to a temporary file, validate success, and replace the owned slot only when safe; preserve the last good save and give useful failure feedback.

**Done when:** existing tests pass; each reproduced defect has a focused regression; every tested transition has zero unexplained item/gold discrepancy; one closing event produces one wage charge and one history entry; failed saves preserve the last good slot. Keep game data and user saves out of disposable test fixtures.

Refactor only where these fixes reveal a concrete ownership problem. Keep simulation, presentation and save responsibilities distinct without rewriting the working job system.

### 2. Physical placement and crowd readability

Define visual support heights/anchors for floors, tables, shelves and counters. Show food and dishes on their actual supporting surfaces, and feet on floors. Refresh presentation when furniture changes. Refine existing cosmetic crowd separation and facing at shared work spots; preserve tile occupancy, paths and item ownership.

**Done when:** four camera directions plus a low angle show no buried goods or feet in the reference tavern; five workers at a pickup point remain individually readable; furniture removal leaves sensible visuals; path checks and reconciliation still pass. Compare before/after captures using the same seed, camera and simulation moment.

### 3. Existing activity animation

Add simple, deliberately stylized poses through the existing rig: sitting toward the table, eating/drinking, kneading, tending the oven, stirring, washing and building. Carrying should have an obvious pose and an appropriate held object. Let jobs and customer states drive presentation; animations must not become a second simulation or determine whether goods are produced.

**Done when:** every current work/customer activity has appropriate facing and a readable pose; interruption, demolition, cancellation and departure restore normal movement; a busy-room recording lets the viewer identify at least four workers' activities without opening a status panel. Preserve the single-surface pawn approach and report the new render cost against step 1.

### 4. Controls, selection and actionable feedback

Keep a visible selection marker and an inspector whose controls remain stable while values update. Make blocked work explain the immediate cause: missing ingredient, no eligible worker, blocked access, full output or unmet production threshold. Adapt toolbar and panel layouts to small/wide screens. Complete touch placement, rotation and cancellation, with gesture handling that distinguishes camera dragging from building/selecting. Keep existing keyboard shortcuts.

**Done when:** build, rotate, cancel, inspect, order supplies, production settings, staff priorities, hands-on work and save can be completed with each supported input method. No clipped controls at 960×540, 1280×720, 1920×1080 or the selected Android aspect ratio. Inspector actions remain clickable across refreshes. Touch targets are checked physically on the device, and camera gestures do not trigger unwanted placement.

### 5. Art direction and sound

Use bold low-poly silhouettes, restrained earth colours, readable props and simple animation as the style rules. Refine the oversized-looking wall caps and dominant repeated floor detail seen in the current capture. Add only a few useful decorative accents: an original hanging sign, restrained wall/entry dressing and clearer work-station details. Give morning and evening a modest lighting difference while keeping the interior readable. Recheck the shared 2D menu after terrain/material changes.

Add a small sound palette through the existing audio event API: room ambience, fire, footsteps, work, serving and transactions. Rate-limit repeated sounds; scale ambience with existing activity without altering gameplay randomness. Music is optional and lower priority than clear work feedback.

Prefer existing procedural art and a small number of carefully matched free assets. Before import, verify each individual source and licence, record attribution, and assess its render cost. Neither the OSRS cache/exporter nor `seraphile/rimshare` may ship. Do not import a large mismatched pack just because it is free.

**Done when:** fixed morning/evening and quiet/busy captures retain clear people, food and selections; sounds correspond to real actions, honour mixer settings and stop cleanly on scene changes; every imported asset has a recorded shippable licence. The 2D menu still renders correctly and the whole-tavern performance comparison is recorded.

### 6. Opening flow and economic pacing

Improve the existing objectives around the real player opening, rather than relying on the fully built test tavern. Preserve completed milestones across a new day and save/reload: the current first-sale objective reads a daily counter that resets. Show the next useful action and why a process is waiting. Test the 20–30 minute demo from New Game through building, delivery, production, first sale, cleaning, a day summary and save/continue.

Run a controlled economic comparison using three seeds and two plausible layouts over ten game days. Report first-sale time, ingredient spending, stock value, wages, sales, tips, refusals, service wait, worker activity and cash. Separate operating results from construction costs and unsold inventory; show how layout affects labour.

Current recipe arithmetic, before hauling, washing, quality and tips:

| Product | Batch input cost | Yield | Base sale price/unit | Gross margin/unit | Direct recipe time/unit |
|---|---:|---:|---:|---:|---:|
| Bread | 7g | 2 | 10g | 6.50g | 4.25s across both stages |
| Beer | 9g | 4 | 8g | 5.75g | 1.75s |

Bread takes **2.43× the direct recipe time per unit for 1.13× the gross margin**, before its extra transport. This supports measuring the imbalance; it does not establish that the game is unwinnable or which value should change. Preserve the two-stage physical bread chain. Bring price/batch recommendations with measured outcomes to the owner before changing design-note values.

**Done when:** the guided opening is affordable, progress is explainable, and the player can complete a 20–30 minute session without a dead end. Proposed target: first sale within five real minutes of the guided opening, to be confirmed by playtesting. Have three fresh players attempt the opening without live coaching and record where they get stuck; revise confusing instructions. Show balance evidence separately from any approved tuning.

### 7. Performance, exports and final acceptance

Use step 1's whole-tavern profiles to choose optimizations: geometry, shadows, distant trees, item batching, crowd scans, UI rebuilding or generation stalls only where they are measured bottlenecks. Keep quality settings honest: each setting should change something meaningful. Avoid adopting a new renderer or replacing the art pipeline without evidence.

Proposed normal-play targets on named test hardware: **60 FPS desktop** and **stable 30 FPS Android**. Report median and 95th-percentile frame times, draw calls, submitted primitives and memory for the same 5/15/30-pawn scenarios; aim for p95 frame times within 16.7ms/33.3ms for the normal demo load. Treat 30 pawns as a stress case with separately reported results. Android readiness requires an actual sustained 20-minute device run, including touch, background/resume and save/continue.

Build a Windows release and an Android test package. Smoke-test the exported builds, check that development fixtures are excluded, include required asset notices, and update the README/handoff with current facts and remaining limits.

**Done when:** the relevant exported build completes the full demo loop, the final reconciliation and save/day regressions pass, art and controls are visually checked, and device results support each advertised platform. If device access is unavailable, clearly mark Android as unverified rather than treating desktop measurements as proof.

## How execution should proceed

Work in the numbered order. At the end of each step, record what changed, relevant test results, a before/after capture when visual, measured cost, and any remaining issue. Continue only after its acceptance checks pass or a dependency is explicitly recorded. Performance is checked throughout, not deferred to step 7.

Keep the scope to this demo: no extra food chains, farming, larger maps or new progression systems during this pass. Existing features are retained and improved. Prefer reusable presentation metadata and clear state boundaries so later content can be added without undoing this work.

**Next execution task:** step 1, beginning with test-save isolation, a fresh baseline and the closing/save lifecycle reproduction. No implementation step has been started by this planning document.
