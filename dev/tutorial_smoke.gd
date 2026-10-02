extends Node

## The tutorial, played by an automated player: the game's end-to-end smoke
## test. Every step's `perform` is what a player does; its `done` is checked
## against the world, as the in-game tutorial checks it. A step that cannot be
## finished by the player's own actions is a bug in the game.
##
##   godot --headless --path . res://dev/tutorial_smoke.tscn [-- --verbose] [--days N]
##
## `--days N` keeps the finished tavern trading for N more days, ordering the
## standard supplies each morning as a player would, one line a day: a soak of
## everything the tutorial built, fishing included.
##
## Output is one line a step, and detail only for a step that fails:
##   TUT 07 wait_build      ok    96s  day 1 09:10  1182g
##   TUT 19 first_bread     FAIL 480s  day 1 17:40   412g
##        why: Make Dough waiting on water 0/1 (no source outside the bench)
##   TUTORIAL 39/40 ok, 1 failed  in 3140 game-s / 41 real-s

## How long a paused step may take to come true after its action, in frames.
## Paused steps are UI and building: they are done at once or not at all.
const PAUSED_FRAMES: int = 30

var world: TavernWorld
var verbose: bool = false
## `-- --shots <dir>`, windowed: a screenshot after every step, for looking.
var shots_dir: String = ""
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	verbose = OS.get_cmdline_user_args().has("--verbose")
	print("AUDIO: %s driver" % AudioServer.get_driver_name())
	var args := OS.get_cmdline_user_args()
	var at: int = args.find("--shots")
	if at >= 0 and at + 1 < args.size():
		shots_dir = args[at + 1]
		DirAccess.make_dir_recursive_absolute(shots_dir)
	SimWait.seed_run()
	var level: LevelDef = LevelCatalog.tutorial()
	GameState.pending_level = level.id
	GameState.start_new_run(level.tavern_name, level.world_seed, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.configure(world)
	await get_tree().process_frame
	# The world made its own director on opening the level; this run drives the
	# steps itself, so the director only watches.
	var director: TutorialDirector = world.hud.tutorial
	if director == null:
		print("TUTORIAL FAIL: the tutorial level opened without its director")
		get_tree().quit(1)
		return
	director.set_process(false)
	await _play(director)


func _play(director: TutorialDirector) -> void:
	var real_start: int = Time.get_ticks_msec()
	var sim_start: float = world.sim.sim_time
	var ok: int = 0
	var steps: Array[TutorialStep] = director.steps
	for i in range(steps.size()):
		var step: TutorialStep = steps[i]
		director.index = i
		director._begin()
		var started: float = world.sim.sim_time
		await _dismiss_summary_if_needed(step)
		if step.perform.is_valid():
			await step.perform.call(world, director.ctx)
		var passed: bool = await _wait_for(step, director.ctx)
		var line: String = "TUT %02d %-14s %s %5.0fs  day %d %s  %5dg" % [
			i + 1, step.id, "ok  " if passed else "FAIL", world.sim.sim_time - started,
			world.clock.day, world.clock.clock_text(), GameState.gold]
		print(line)
		if not shots_dir.is_empty():
			# Drawing a report must not advance test time and change later rolls.
			# Leave presentation/camera processing on and preserve the chosen speed.
			var clock_processing: bool = world.sim.is_processing()
			world.sim.set_process(false)
			# Looking at what the step is about, as its Show me button would.
			director.show_me()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots_dir.path_join("%02d_%s.png" % [i + 1, step.id]))
			world.sim.set_process(clock_processing)
		if passed:
			ok += 1
		else:
			_failures.append(step.id)
			_explain(step)
		elif_verbose(step)
	print("TUTORIAL %d/%d ok%s  in %.0f game-s / %.0f real-s" % [
		ok, steps.size(), "" if _failures.is_empty() else ", %d failed: %s" % [_failures.size(), ", ".join(_failures)],
		world.sim.sim_time - sim_start, float(Time.get_ticks_msec() - real_start) / 1000.0])
	var at: int = OS.get_cmdline_user_args().find("--days")
	if at >= 0 and at + 1 < OS.get_cmdline_user_args().size():
		if not await _trade_on(int(OS.get_cmdline_user_args()[at + 1])):
			_failures.append("soak")
	var report: Node = load("res://dev/world_scenario.gd").new()
	report.world = world
	add_child(report)
	if not report.reconcile(false):
		_failures.append("reconciliation")
	report.queue_free()
	# Let queued jobs, patrons and UI callbacks retire before engine shutdown.
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


## After the lessons: trade on, as a player who has finished the tutorial would.
func _trade_on(days: int) -> bool:
	world.sim.speed = 4
	var purse: int = GameState.gold
	var served: int = 0
	var lost_service: int = 0
	var lost_seat: int = 0
	var last: int = world.clock.day
	var until: int = world.clock.day + days
	# A script error in here would leave the run waiting forever.
	get_tree().create_timer(60.0 * days).timeout.connect(func() -> void:
		print("TRADE FAIL: day %d still open after %d real seconds" % [world.clock.day, 60 * days])
		get_tree().quit(1))
	var made_before: Dictionary = world.generator.produced.duplicate()
	var eaten_before: Dictionary = world.customers.consumed.duplicate()
	while world.clock.day < until:
		await get_tree().process_frame
		if not world.simulation_paused:
			continue
		# The summary is up: that day is done. Guest tallies are the day's own;
		# they reset when the next day opens.
		var line: PackedStringArray = PackedStringArray()
		for id in [&"trout", &"perch", &"fillet", &"grilled_fish", &"fish_soup", &"bread", &"beer", &"wheat", &"hops", &"water"]:
			var made: int = int(world.generator.produced.get(id, 0)) - int(made_before.get(id, 0))
			if made > 0:
				line.append("%s %d" % [id, made])
		var ate: PackedStringArray = PackedStringArray()
		for id in CustomerDirector.menu_ids():
			var n: int = int(world.customers.consumed.get(id, 0)) - int(eaten_before.get(id, 0))
			if n > 0:
				ate.append("%s %d" % [id, n])
		var c: CustomerDirector = world.customers
		if not TestOutput.brief:
			print("DAY %d  %5dg  served %d, lost %d seat/%d service/%d menu  made: %s  sold: %s" % [
				world.clock.day, GameState.gold, c.served_count, c.lost_no_seat, c.lost_no_service, c.lost_no_menu,
				", ".join(line), ", ".join(ate)])
			var trouble: String = Trouble.diagnose(world)
			if not trouble.is_empty():
				print("     trouble: %s" % trouble)
		if verbose:
			print("     pass: %s" % _pass_line())
		served += c.served_count
		lost_service += c.lost_no_service
		lost_seat += c.lost_no_seat
		# A player reads the advice panel: told to hire a waiter, they do.
		if Trouble.diagnose(world).contains("hire a waiter") and world.hire(&"waiter") == "":
			if verbose:
				print("     (hired a waiter, as the advice said)")
		made_before = world.generator.produced.duplicate()
		eaten_before = world.customers.consumed.duplicate()
		PlayerActions.press(world.hud._day_summary, "Open tomorrow")
		PlayerActions.press(world.hud._day_summary, "Keep trading")
		await get_tree().process_frame
		if world.clock.day != last:
			last = world.clock.day
			# A player with auto-order on leaves the larder to it.
			if not world.auto_supply.enabled and world.order_problem(TavernWorld.STANDARD_ORDER) == "":
				world.order_supplies()
	# Guests given up on for want of service are the thing to watch: a pass
	# jammed with abandoned plates lost 15-27 a day before it was fixed.
	var ok: bool = lost_service <= 3 * days and GameState.gold > purse
	print("SOAK %s  %d days after the tutorial: served %d, lost %d to service, %d for a seat; purse %dg -> %dg" % [
		"ok" if ok else "FAIL", days, served, lost_service, lost_seat, purse, GameState.gold])
	return ok


## A day can close in the middle of the lessons -- building and hauling take a
## good part of one. A player reads the summary and opens tomorrow; so does this,
## except on the lesson that is about the summary.
func _dismiss_summary_if_needed(step: TutorialStep) -> void:
	if world.simulation_paused and step.id != "reviews":
		if verbose:
			print("     (day %d closed during the lessons; opening tomorrow)" % world.clock.day)
		PlayerActions.press(world.hud._day_summary, "Open tomorrow")
		PlayerActions.press(world.hud._day_summary, "Keep trading")
		await get_tree().process_frame


func _wait_for(step: TutorialStep, ctx: Dictionary) -> bool:
	if step.pace == TutorialStep.Pace.PAUSED:
		for f in range(PAUSED_FRAMES):
			if step.done.call(world, ctx):
				return true
			await get_tree().process_frame
		return step.done.call(world, ctx)
	if world.sim.speed == 0:
		world.sim.speed = 1
	var limit: float = world.sim.sim_time + step.budget
	while world.sim.sim_time < limit:
		if step.done.call(world, ctx):
			return true
		if world.simulation_paused and step.id != "day_end":
			await _dismiss_summary_if_needed(step)
		await get_tree().process_frame
	return step.done.call(world, ctx)


## Why a step did not come true, from the world's own account of itself.
func _explain(step: TutorialStep) -> void:
	var trouble: String = Trouble.diagnose(world)
	if not trouble.is_empty():
		print("     trouble: %s" % trouble)
	var doing: PackedStringArray = PackedStringArray()
	for worker in world.workers:
		if is_instance_valid(worker):
			doing.append("%s: %s" % [worker.role.title if worker.role != null else "?", worker.status_text()])
	print("     staff: %s" % " | ".join(doing))
	var guests: PackedStringArray = PackedStringArray()
	for brain in world.customers.customers:
		if is_instance_valid(brain):
			guests.append(brain.status_text())
	if not guests.is_empty():
		print("     guests: %s" % " | ".join(guests.slice(0, 6)))
	print("     board: %d open, %d taken; %d blueprints; kitchen: %s" % [
		world.board.open_count(), world.board.active_count(), TutorialPlan.blueprints(world),
		_kitchen_line()])
	var refused: String = world.hud._build_bar._status.text if world.hud._build_bar != null else ""
	if not refused.is_empty():
		print("     build bar: %s" % refused)


func elif_verbose(step: TutorialStep) -> void:
	if verbose:
		print("     %s" % step.text)


func _kitchen_line() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for station in world.generator.built_stations():
		for recipe in station["recipes"]:
			parts.append("%s %s" % [recipe.display_name,
				world.bills.status_text(recipe.id, world.generator._output_stock(recipe))])
	return "; ".join(parts) if not parts.is_empty() else "no benches built"


## What is standing on the serving counters: plates nobody collects block it.
func _pass_line() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for tile in world.customers.pass_tiles():
		var def: ItemDef = world.items.def_at(tile)
		parts.append("%s %d" % [def.id, world.items.count_at(tile)] if def != null else "empty")
	return ", ".join(parts)
