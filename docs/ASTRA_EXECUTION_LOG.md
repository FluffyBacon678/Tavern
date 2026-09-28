# Ordered demo polish: execution record

Plan: [ASTRA_IMPROVEMENT_PLAN.md](ASTRA_IMPROVEMENT_PLAN.md). Started 2026-09-22.

## Step 1 — reliability and baseline (in progress)

The pre-change source/assets/docs archive is `.verification/plan_start_20260922/workspace_before.zip`. Existing player saves were copied into the adjacent `player_saves_before` folder and SHA-256 hashes recorded before testing. Verification must use isolated save directories.

Fresh baseline evidence:

- Godot 4.7.2 headless editor parse passed: `.verification/step1_baseline_parse.log`.
- Original regression suite: **111 assertions passed** in the backed-up project with save paths redirected to a workspace-only directory: `.verification/step1_baseline_regressions.log`.
- Three-day seed-12345 accelerated economy run: all nine goods reconciled with difference zero, and gold **435 = expected 435**. Log: `.verification/step1_baseline_economy.log`. Historical captures used a slightly earlier simulation revision; compare measurements within this pass.
- The closing-save reproduction failed six checks before fixes: reloading charged another 30g payroll and added another day-1 ledger entry; duplicate close signals charged again; workers and job generation continued behind the summary. Log: `.verification/step1_day_before.log`.
- A real JSON round-trip into a fresh world confirmed that partially served customers disappear under the original save format: `.verification/step1_visit_before.log`. Applying into the same live world is insufficient to test persistence.

Current feature inventory includes physical bread/beer production, deliveries, production bills, staff priorities, hosting, customer reviews/reputation, dirty dishes/cleaning, quality, manual cooking, building/demolition, objectives, saving and wall cutaway. Older README/handoff feature lists are historical.

Independent work is split between save safety, goods/manual-work conservation, and a whole-tavern rendering profile/toolchain audit. Integration acceptance remains pending. No design-note prices, recipe yields or wages are being changed.

Early platform audit: no Android SDK/adb/Java or Godot export templates/presets were found in the standard locations checked. Android device acceptance remains an explicit external dependency. The existing `dist` folder contains an icon, not a verified game export.

## Later steps

2. Physical placement and crowd readability — pending step 1 acceptance.
3. Activity animation — pending.
4. Controls and feedback — pending.
5. Art and sound — pending.
6. Opening and balance evidence — pending.
7. Performance and release acceptance — pending; actual Android device and fresh-player checks require available hardware/people.
