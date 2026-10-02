extends Node

## The sandbox's full test house (TestHouse), opened as the main menu opens it,
## checked for one of everything, then run for three days with every position
## at work. One line of result; `--verbose` adds the day lines.
##
##   godot --headless --path . res://dev/house_smoke.tscn [-- --brief] [--verbose]

const DAYS: int = 3

var world: TavernWorld
var holes: PackedStringArray = PackedStringArray()


func _ready() -> void:
	if not GameState.begin_test_session():
		get_tree().quit(2)
		return
	var verbose: bool = OS.get_cmdline_user_args().has("--verbose")
	SimWait.seed_run()
	GameState.full_house_start = true
	GameState.start_new_run("Test House", 493774, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.configure(world)
	await get_tree().process_frame

	# One of everything built, and one of every position hired.
	var built: Dictionary = {}
	for entry in world.build.grid.placements:
		if entry != null and entry["built"]:
			built[entry["def"].id] = int(built.get(entry["def"].id, 0)) + 1
	for id in [&"wood_floor", &"timber_wall", &"door", &"table", &"chair", &"serving_counter", &"host_stand",
			&"prep_table", &"oven", &"brewing_vat", &"sink", &"storage_shelf", &"barrel", &"well",
			&"fishing_spot", &"river_pump", &"farm_plot"]:
		if not built.has(id):
			holes.append("the test house has no %s" % id)
	var roles: Dictionary = {}
	for worker in world.workers:
		roles[worker.role.id] = true
	for role in StaffRole.hireable_roles():
		if not roles.has(role.id):
			holes.append("nobody on the staff is a %s" % role.id)

	# Three days of trade, the summary dismissed each night.
	world.sim.speed = 4
	var until: int = world.clock.day + DAYS
	var real_start: int = Time.get_ticks_msec()
	while world.clock.day < until and Time.get_ticks_msec() - real_start < 240000:
		await get_tree().process_frame
		if world.simulation_paused:
			if verbose:
				print("DAY %d  %dg  %s" % [world.clock.day, GameState.gold, world.customers.summary()])
			PlayerActions.press(world.hud._day_summary, "Open tomorrow")
			PlayerActions.press(world.hud._day_summary, "Keep trading")
			await get_tree().process_frame
	if world.clock.day < until:
		holes.append("three days did not pass in four real minutes")

	var made: Dictionary = world.generator.produced
	for id in [&"bread", &"beer", &"water", &"flour"]:
		if int(made.get(id, 0)) <= 0:
			holes.append("the test house made no %s in %d days" % [id, DAYS])
	var fish: int = int(made.get(&"trout", 0)) + int(made.get(&"perch", 0))
	if fish <= 0:
		holes.append("nobody caught a fish")
	var planted: int = 0
	for entry in world.build.grid.placements:
		if entry != null and entry["def"].id == &"farm_plot" and Farm.growth_of(entry) >= 0.0:
			planted += 1
	if planted == 0 and int(made.get(&"wheat", 0)) + int(made.get(&"hops", 0)) == 0:
		holes.append("the farmer planted nothing")

	if verbose or not holes.is_empty():
		for station in world.generator.built_stations():
			for recipe in station["recipes"]:
				var missing: PackedStringArray = PackedStringArray()
				for need in recipe.inputs:
					if world.generator.count_at_station(station, need["id"]) < int(need["count"]):
						missing.append("%s (%s)" % [need["id"], world.generator.feed_problem(station, need["id"])])
				print("  kitchen: %s [%s]%s" % [recipe.display_name,
					world.bills.status_text(recipe.id, world.generator._output_stock(recipe)),
					"" if missing.is_empty() else " waiting on " + ", ".join(missing)])
		for worker in world.workers:
			print("  staff: %s %s" % [worker.role.id, worker.status_text()])
		var where: PackedStringArray = PackedStringArray()
		for tile in world.items.tiles_with(&"water", TestHouse.hall(world).position):
			var at: int = world.build.grid.object_index_at(tile)
			where.append("%d at %s%s" % [world.items.count_at(tile), tile,
				" on " + String(world.build.grid.placements[at]["def"].id) if at >= 0 else ""])
		print("  water: %s" % ", ".join(where))
		print("  stock: flour %d, wheat %d, hops %d, water %d; auto-order: %s" % [world.stock_of(&"flour"),
			world.stock_of(&"wheat"), world.stock_of(&"hops"), world.stock_of(&"water"), world.auto_supply.note])
	var line: String = "made bread %d, beer %d, water %d, fish %d, wheat %d; %d plots growing; %dg" % [
		int(made.get(&"bread", 0)), int(made.get(&"beer", 0)), int(made.get(&"water", 0)), fish,
		int(made.get(&"wheat", 0)), planted, GameState.gold]
	var scenario: Node = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	scenario.opening_gold_override = TestHouse.GOLD
	add_child(scenario)
	if not scenario.reconcile(false):
		holes.append("the full-house goods or gold failed reconciliation")
	if holes.is_empty():
		print("HOUSE SMOKE PASS: one of everything, three days traded; %s" % line)
	else:
		print("HOUSE SMOKE: %d hole(s); %s" % [holes.size(), line])
		for hole in holes:
			print("  HOLE: %s" % hole)
	world.queue_free()
	scenario.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if holes.is_empty() else 1)
