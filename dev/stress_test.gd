extends Node

## The biggest tavern the game allows, run at full speed, measured.
##
##   godot --path . --resolution 1600x900 res://dev/stress_test.tscn     rendered: frame times
##   godot --headless --path . res://dev/stress_test.tscn               simulation cost only
##
## Buys land on every side until none is left, tiles the plot with copies of
## the tutorial's room (tables, kitchen, counter, storage), hires a crew per
## room, keeps the shelves stocked, and runs at 5x. Prints one report.

const RUN_SECONDS: float = 120.0  ## real seconds measured
const WARMUP: float = 8.0

var world: TavernWorld


func _ready() -> void:
	if not GameState.begin_test_session():
		get_tree().quit(2)
		return
	GameState.start_new_run("Stress Hall", 493774, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	GameState.gold = 10_000_000
	var bought: int = 0
	# `--small`: a normal first tavern -- one room, the starting crew -- for the
	# everyday frame time on the minimum machine.
	var small: bool = OS.get_cmdline_user_args().has("--small")
	for round in range(0 if small else 40):
		var any: bool = false
		for side in [TavernWorld.SIDE_EAST, TavernWorld.SIDE_WEST, TavernWorld.SIDE_SOUTH, TavernWorld.SIDE_NORTH]:
			if world.parcel_problem(side) == "" and world.buy_land(side):
				bought += 1
				any = true
		if not any:
			break
	var rooms: int = _fill_one() if small else _fill()
	for i in range(0 if small else rooms):
		for role in [&"porter", &"cook", &"cook", &"waiter", &"waiter", &"cleaner", &"busser"]:
			world.hire(role)
	world.customers.reputation.score = 95.0
	world.sim.speed = 4
	print("STRESS plot %dx%d (%d parcels), %d rooms, %d seats, %d staff, %d placements" % [
		world.plot.size.x, world.plot.size.y, bought, rooms, world.customers.seating.seats.size(),
		world.workers.size(), world.build.grid.live_count()])
	if OS.get_cmdline_user_args().has("--profile"):
		_profile()
	else:
		await _measure()
	get_tree().quit()


## Time each system's own step, a game-second's worth, with the clock stopped.
func _profile() -> void:
	world.sim.speed = 0
	_restock()
	var dt: float = 1.0 / 60.0
	var groups: Dictionary = {"generator": [world.generator], "customers": [world.customers],
		"workers": world.workers, "pawns": world.pawns, "clock": [world.clock]}
	for name in groups:
		var t0: int = Time.get_ticks_usec()
		for i in range(60):
			for node in groups[name]:
				if is_instance_valid(node) and node.has_method("sim_step"):
					node.sim_step(dt)
		print("STRESS profile %-10s %7.2f ms per game-second (%d nodes)" % [
			name, float(Time.get_ticks_usec() - t0) / 1000.0, groups[name].size()])
	# The two passes that re-derive work, warm (the first builds the layout
	# caches), then ten times each on the same tavern.
	var passes: Dictionary = {
		"job scan": func() -> void: world.generator.scan(),
		"serve pass": func() -> void: world.customers._generate_serve_jobs(),
	}
	for name in passes:
		passes[name].call()
		var t: int = Time.get_ticks_usec()
		for i in range(10):
			passes[name].call()
		print("STRESS profile %-10s %7.2f ms each" % [name, float(Time.get_ticks_usec() - t) / 10000.0])
	var t1: int = Time.get_ticks_usec()
	for i in range(10):
		world.hud.refresh_stats()
	print("STRESS profile hud refresh %.2f ms each" % (float(Time.get_ticks_usec() - t1) / 10000.0))
	var parts: Dictionary = {
		"trouble": func() -> void: Trouble.diagnose(world),
		"purse tip": func() -> void: WorldStats.purse_breakdown(world),
		"stock tip": func() -> void: WorldStats.stock_breakdown(world, &"bread"),
		"people tip": func() -> void: WorldStats.people_breakdown(world),
		"objectives": func() -> void: world.objectives.refresh(world),
		"stock line": func() -> void: world.hud._stock_summary(),
		"summary": func() -> void: world.customers.summary(),
		"stock_of": func() -> void: world.stock_of(&"bread"),
	}
	for name in parts:
		var t: int = Time.get_ticks_usec()
		for i in range(10):
			parts[name].call()
		print("STRESS profile   %-12s %.2f ms" % [name, float(Time.get_ticks_usec() - t) / 10000.0])


## Copies of the tutorial's 12 x 7 room, walls and all, across the plot.
func _fill() -> int:
	var rooms: int = 0
	var step := Vector2i(15, 10)
	for oy in range(world.plot.position.y + 2, world.plot.end.y - 10, step.y):
		for ox in range(world.plot.position.x + 12, world.plot.end.x - 14, step.x):
			var r := Vector2i(ox, oy)
			if _room(r):
				rooms += 1
	for def in BuildingCatalog.all():
		world.build._rebuild_instances(def)
	world.nav.refresh_all()
	world.customers.seating.refresh()
	return rooms


func _fill_one() -> int:
	var ok: bool = _room(TutorialPlan.room(world).position)
	for def in BuildingCatalog.all():
		world.build._rebuild_instances(def)
	world.nav.refresh_all()
	world.customers.seating.refresh()
	return 1 if ok else 0


func _put(id: StringName, tile: Vector2i, rot: int = 0) -> bool:
	return world.build.place_programmatic(BuildingCatalog.get_def(id), tile, rot, false) >= 0


func _room(r: Vector2i) -> bool:
	for y in range(-1, 8):
		for x in range(-1, 13):
			if world.build.grid.placement_at(r + Vector2i(x, y)) >= 0 or not world.build.grid.in_plot(r + Vector2i(x, y)):
				return false
	for y in range(7):
		for x in range(12):
			_put(&"wood_floor", r + Vector2i(x, y))
	for y in range(-1, 8):
		for x in range(-1, 13):
			if x == -1 or x == 12 or y == -1 or y == 7:
				_put(&"door" if (x == 4 and y == 7) else &"timber_wall", r + Vector2i(x, y))
	for t in TutorialPlan.TABLES:
		_put(&"table", r + t)
		_put(&"chair", r + t + Vector2i(-1, 0))
		_put(&"chair", r + t + Vector2i(2, 0))
	_put(&"prep_table", r + TutorialPlan.PREP)
	_put(&"oven", r + TutorialPlan.OVEN)
	_put(&"brewing_vat", r + TutorialPlan.VAT)
	_put(&"sink", r + TutorialPlan.BASIN)
	_put(&"serving_counter", r + TutorialPlan.COUNTER)
	for t in TutorialPlan.SHELVES:
		_put(&"storage_shelf", r + t)
	for t in TutorialPlan.BARRELS:
		_put(&"barrel", r + t)
	return true


## Keep every kitchen supplied, as a well-run supply chain would.
var _restocked: int = 0
var _turn: int = 0


func _restock() -> void:
	for entry in world.build.grid.placements:
		if entry == null or not entry["def"].is_storage:
			continue
		var tile: Vector2i = entry["tiles"][0]
		if world.items.has_stack(tile):
			continue
		var id: StringName = [&"flour", &"yeast", &"water", &"malt", &"hops"][_turn % 5]
		_turn += 1
		var def: ItemDef = ItemCatalog.get_def(id)
		var n: int = world.items.add(def, def.stack_size, tile, ItemWorld.BASE_QUALITY)
		world.delivered[id] = world.delivered.get(id, 0) + n
		_restocked += n


func _measure() -> void:
	var frames: Array[float] = []
	var peak_guests: int = 0
	var peak_jobs: int = 0
	var started: int = Time.get_ticks_msec()
	var sim_started: float = 0.0
	var last: int = Time.get_ticks_usec()
	var restock_at: float = 0.0
	while float(Time.get_ticks_msec() - started) / 1000.0 < RUN_SECONDS + WARMUP:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var elapsed: float = float(Time.get_ticks_msec() - started) / 1000.0
		if world.simulation_paused:
			PlayerActions.press(world.hud._day_summary, "Open tomorrow")
		if world.sim.sim_time > restock_at:
			restock_at = world.sim.sim_time + 30.0
			_restock()

		if elapsed > WARMUP:
			if sim_started == 0.0:
				sim_started = world.sim.sim_time
			frames.append(float(now - last) / 1000.0)
			peak_guests = maxi(peak_guests, world.customers.customers.size())
			peak_jobs = maxi(peak_jobs, world.board.jobs.size())
		last = now
	frames.sort()
	var game: float = world.sim.sim_time - sim_started
	print("STRESS %d frames: median %.1f ms, p95 %.1f ms, worst %.1f ms; %.0f game-s in %.0f s (%.1fx real, asked 5x)" % [
		frames.size(), frames[frames.size() / 2], frames[int(frames.size() * 0.95)], frames[frames.size() - 1],
		game, RUN_SECONDS, game / RUN_SECONDS])
	# The day's tallies reset at midnight: say which day they are for, and what
	# the closed days served, or a fast run that crossed midnight reads as idle.
	var closed: PackedStringArray = PackedStringArray()
	for entry in world.ledger.history:
		closed.append("day %d served %d" % [int(entry["day"]), int(entry["served"])])
	print("STRESS peak %d guests, %d jobs on the board; served %d; %s; now %s%s" % [
		peak_guests, peak_jobs, world.customers.served_count, world.customers.summary(),
		world.hud._clock_summary(), "; closed: " + ", ".join(closed) if not closed.is_empty() else ""])
	print("STRESS restocked %d units; storage placements %d" % [_restocked,
		world.build.grid.placements.filter(func(e) -> bool: return e != null and e["def"].is_storage).size()])
	print("STRESS made bread %d beer %d dough %d; stock bread %d beer %d flour %d; route: '%s'; staff: %s" % [
		int(world.generator.produced.get(&"bread", 0)), int(world.generator.produced.get(&"beer", 0)),
		int(world.generator.produced.get(&"dough", 0)), world.stock_of(&"bread"), world.stock_of(&"beer"),
		world.stock_of(&"flour"), world.route_warning(),
		" | ".join(world.workers.slice(0, 8).map(func(w) -> String: return w.status_text()))])
	var guests: PackedStringArray = PackedStringArray()
	for brain in world.customers.customers:
		if is_instance_valid(brain):
			guests.append(brain.status_text())
	print("STRESS guests: %s" % " | ".join(guests))
	var busy: Dictionary = {}
	for w in world.workers:
		var st: String = w.status_text()
		busy[st] = int(busy.get(st, 0)) + 1
	print("STRESS staff doing: %s" % str(busy))
	var open: Dictionary = {}
	for job in world.board.jobs:
		var k: String = "%s %s%s" % [WorkType.display_name(job.kind), "taken" if job.claimant != null else "open",
			" refused-by-%d" % job.failed_for.size() if not job.failed_for.is_empty() else ""]
		open[k] = int(open.get(k, 0)) + 1
	print("STRESS board: %s" % str(open))
	print("STRESS draws %d, primitives %d, static memory %.0f MB" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
