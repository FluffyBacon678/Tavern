# Tutorial play attempt and compact monitoring — 2026-09-28

## What was actually played

The existing headless tutorial player completed **40/40 steps**, twice, in
approximately five seconds per run (597 simulated seconds). A separate
windowed player also reached **TUTORIAL COMPLETE** with the real tutorial
director processing normally. Neither its index nor its completion results
were forced. Screenshots were inspected at the opening, building, filtering
and production lessons; the filter defect below was reproduced through its
actual checkbox signal.

This was **script-assisted play**, not a completed physical mouse/keyboard
playthrough. Windows computer-use first timed out awaiting app approval, then
failed to capture the window with `FrameArrived timed out`. Manual input was
not performed. The existing `TutorialStep.perform` actions include direct
gameplay calls, so their success does not prove every hit target or interaction
works. The observer's default manual mode leaves real controls enabled.

No production files were changed for this task. Test saves use
`GameState.begin_test_session()`; evidence lives in
`.verification/tutorial_20260928/`.

## Findings, in suggested repair order

1. **Shelf-filter lesson teaches the wrong operation and finishes early.**
   Step 19 says “untick all but flour and yeast.” Opening the shelf inspector
   shows **zero ticked boxes**, meaning accept anything. Ticking only the
   Flour Sack checkbox advances to `order_open`, even though the shelf still
   rejects yeast. Evidence: `filter_checked/filter_before.png`,
   `filter_checked/filter_after_one_tick.png`, and `filter_checked.txt`:

   ```text
   FILTER PROBE: initially ticked=0
   FILTER PROBE: after ticking only Flour: allows_yeast=false advanced=true current=order_open
   ```

   Recommend saying “tick Flour Sack and Yeast” and requiring precisely the
   intended filter before advancing. The probe intentionally exits 1 while
   this defect exists; it does not repair the shelf or skip the lesson.

2. **Six lessons can finish before the player learns them.** In the windowed
   live run, these conditions were already true on entering the lesson:
   `first_bread`, `open_doors`, `take_order`, `plate`, `bill`, and `wash`.
   The director checks every 0.25 real seconds, so an already-satisfied lesson
   can disappear at its next check. The stock smoke test also records zero
   simulated seconds for first bread and four service lessons. This is not a
   crash, but “watch this happen” instructions are ineffective when the event
   already happened. Recommend a readable acknowledgment for observational
   lessons, or measure a new event after entry while retaining a recovery path.
   Evidence: `live_checked/events.jsonl` (`already_done: true`) and `baseline.txt`.

3. **Hands-on lesson needs a supply recovery path; stress observation.**
   A headless run of the live director stalled at step 25 after 302.4 simulated
   seconds. It reached day 2, 10:00 with zero guests and reported missing water,
   yeast, malt and hops. The windowed live run completed this step. The live
   director polls in wall time while the test accelerates simulation; differing
   frame rates change the gameplay time between lessons. Therefore this is a
   useful timing/recovery warning, not proof that ordinary-speed play always
   blocks. Reproduce with `auto` headless, then verify manually at normal speed.
   Recommend a contextual restock prompt/recovery action rather than leaving
   “Do it yourself” as the only instruction when ingredients are unavailable.
   Evidence: `headless_watch.txt` and `headless_watch/state.json`.

4. **Intermittent exit warning, unconfirmed cause.** The first stock smoke run
   printed `6 ObjectDB instances were leaked at exit`. A second run with
   `--verbose` completed identically without that warning. Keep the first log;
   do not call this a proven accumulating gameplay leak. Evidence: `baseline.txt`
   and `leak_detail.txt`.

One initial live-player stall at `hover_guest` was an automation limitation:
the selected guest could leave before the director's wall-time poll. Auto mode
now keeps pointing at an actual guest when necessary and isolates unrelated
OS-pointer input. Manual hover behaviour is unchanged. That initial failure
is retained in `live.txt`, but is not counted as a confirmed player bug.

## Low-token play/observe loop

New files: `dev/tutorial_watch.gd`, `dev/tutorial_watch.tscn`, and
`dev/read_tutorial_watch.ps1`.

```powershell
$engine = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . --import

# Fast deterministic coverage first; read only the ending and failures.
& $engine --headless --path . res://dev/tutorial_smoke.tscn

# Real controls, sandboxed saves; play in the window.
& $engine --path . res://dev/tutorial_watch.tscn

# From a second terminal/tool call: a compact current-state read.
./dev/read_tutorial_watch.ps1

# Script-assisted live director, milestone screenshots, bounded timeout.
& $engine --path . res://dev/tutorial_watch.tscn -- auto

# Reproduce the filter problem. Expected exit 1 until fixed.
& $engine --path . res://dev/tutorial_watch.tscn -- probe_filter
```

Pass `out=res://.verification/<unique-run>` after `--` to retain separate runs;
pass that directory to the reader using `-OutDir`. Defaults use
`.verification/tutorial_watch`. Headless auto mode is supported for stress
observation, but screenshots require the windowed renderer. Its timing is not
equivalent to the deterministic stock smoke player.

- `state.json` is overwritten once per second with the current instruction,
  step, clock, pause state, purse, staff/guests, blueprints and trouble. The
  reader normally emits just two or three lines; `-Details` returns full JSON.
  Snapshots include timestamp/process id; stale running snapshots are flagged.
- `events.jsonl` and stdout record **transitions and final outcomes**, not
  every frame. `already_done` identifies lessons satisfied before scripted input.
- Screenshots are saved on step changes and termination. Read one only when
  placement, layout or a stall needs visual investigation; do not reload all
  40 images into the conversation.
- Auto mode exits on a step-budget stall, a frozen step, or a 180-second wall
  watchdog. Manual sessions have a 30-minute watchdog. The final state records
  `COMPLETE`, `STALLED`, `STOPPED`, or the failure reason.
- A completed automatic session reconciles items and gold using the existing
  reconciliation harness; failure changes the exit code and expands diagnostics.
- To end a manual session cleanly from a tool, create `<out>/stop`. The observer
  consumes that file, saves its final snapshot, and exits normally, allowing
  sandbox-save cleanup. Closing the game normally also cleans its test saves.

Recommended agent workflow: run the stock smoke, read the two-line watch
snapshot, perform one decision/action, and inspect the next meaningful state.
Use a screenshot for a new screen or suspected visual fault. Expand the
diagnostic log only when a step stalls or a state contradicts the instruction.
This preserves evidence while avoiding repeated full-screen observations and
large code/log dumps.
