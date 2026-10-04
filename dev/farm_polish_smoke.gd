extends Node

var failures: int = 0
var world: TavernWorld

func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1

func weather(raining: bool) -> void:
	for hour in range(240):
		var day: int = 1 + floori(float(hour) / 24.0)
		var fraction: float = float(hour % 24) / 24.0
		var rain: float = AtmospherePalette.sample(world._world_seed, day, fraction)["rain"]
		if (raining and rain > 0.99) or (not raining and rain == 0.0):
			world.clock.day = day
			world.clock.fraction = fraction
			return
	check(false, "weather fixture found")

func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	SimWait.seed_run()
	GameState.world_seed = 12345
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	var bank: Vector2i = TutorialPlan.well_spot(world)
	for x in range(world.plot.position.x + 2, world.plot.end.x - 3):
		var candidate := Vector2i(x, world.plot.position.y + 2)
		if world.build.grid.placement_problem(BuildingCatalog.get_def(&"well"), candidate, 0) == "":
			bank = candidate
			break
	var well: int = world.build.place_programmatic(BuildingCatalog.get_def(&"well"), bank, 0, false)
	check(well >= 0, "rain collector fixture built")
	weather(false)
	var before: int = world.items.total_of(&"water")
	world.farm.step(Farm.RAIN_EVERY * 3.0)
	check(world.items.total_of(&"water") == before, "clear weather makes no water")
	weather(true)
	world.farm.step(Farm.RAIN_EVERY * 2.5)
	check(world.items.total_of(&"water") == before + 2, "two complete rainfall intervals produce exactly two barrels")
	check(is_equal_approx(world.farm._rain, Farm.RAIN_EVERY * 0.5), "fractional rainfall is retained")
	check(int(world.generator.produced.get(&"water", 0)) == 2, "rainwater production reconciles")
	var cover: Array[int] = []
	for y in range(-1, 3):
		for x in range(-1, 3):
			var edge: bool = x == -1 or x == 2 or y == -1 or y == 2
			cover.append(world.build.place_programmatic(BuildingCatalog.get_def(&"timber_wall" if edge else &"wood_floor"), bank + Vector2i(x, y), 0, false))
	check(not cover.has(-1) and world.rooms.room_at(bank) >= 0, "completed room shelters the well fixture")
	before = world.items.total_of(&"water")
	world.farm.step(Farm.RAIN_EVERY)
	check(world.items.total_of(&"water") == before, "a roofed well does not collect rain")
	for i in cover:
		world.build.grid.remove(i)
	var water: ItemDef = ItemCatalog.get_def(&"water")
	for t in world.build.grid.placements[well]["tiles"]:
		world.items.add(water, water.stack_size, t)
	before = world.items.total_of(&"water")
	var made_water: int = int(world.generator.produced.get(&"water", 0))
	world.farm.step(Farm.RAIN_EVERY)
	check(world.items.total_of(&"water") == before and int(world.generator.produced.get(&"water", 0)) == made_water, "a full well neither overflows nor books phantom production")
	var tile: Vector2i = world.plot.position + Vector2i(10, 10)
	var index: int = world.build.place_programmatic(BuildingCatalog.get_def(&"farm_plot"), tile, 0, false)
	check(index >= 0, "harvest fixture built")
	if index < 0:
		get_tree().quit(1)
		return
	var entry: Dictionary = world.build.grid.placements[index]
	entry["growth"] = 1.0
	var wheat: ItemDef = ItemCatalog.get_def(&"wheat")
	for y in range(-6, 7):
		for x in range(-6, 7):
			world.items.add(wheat, wheat.stack_size, tile + Vector2i(x, y))
	before = world.items.total_of(&"wheat")
	world.farm._harvested(index)
	check(Farm.growth_of(entry) == 1.0 and int(entry.get("harvest_remaining", -1)) == 3, "blocked harvest stays ripe with its full yield")
	check(world.items.total_of(&"wheat") == before, "blocked harvest creates no invisible goods")
	world.items.take(tile, 1)
	world.farm._harvested(index)
	check(Farm.growth_of(entry) == 1.0 and int(entry.get("harvest_remaining", -1)) == 2, "partially accepted harvest keeps exactly two wheat standing")
	var data: Dictionary = SaveGame.capture(world)
	SaveGame.apply(world, data)
	index = world.build.grid.floor_index_at(tile)
	entry = world.build.grid.placements[index]
	check(int(entry.get("harvest_remaining", -1)) == 2 and Farm.growth_of(entry) == 1.0, "partial harvest survives a full save restore")
	check(is_equal_approx(world.farm._rain, Farm.RAIN_EVERY * 0.5), "rainfall progress survives a full save restore")
	world.items.take(tile, 2)
	world.farm._harvested(index)
	check(Farm.growth_of(entry) < 0.0 and world.items.total_of(&"wheat") == before, "freed space recovers the remaining harvest")
	check(int(world.generator.produced.get(&"wheat", 0)) == 3, "partial harvest retries produce exactly three wheat in total")
	entry["growth"] = 1.0
	world.farm._post_jobs()
	world.farm.set_crop(index, &"hops")
	check(world.board.job_with_key("farm:%d,%d" % [tile.x, tile.y]) == null and Farm.growth_of(entry) < 0.0, "changing crop cancels obsolete harvest work")
	world.farm.set_crop(-1, &"wheat")
	world.farm.set_crop(999999, &"wheat")
	check(Farm.crop_of(entry) == &"hops", "stale crop selections are harmless")
	entry["growth"] = 1.0
	world.farm._show_crops()
	check(world.farm.get_child_count() <= 6, "crop visuals use at most six shared batches")
	for lesson in TutorialPlan.steps():
		if lesson.id != "well":
			continue
		var ctx: Dictionary = {}
		lesson.begin.call(world, ctx)
		check(not lesson.done.call(world, ctx), "an existing well does not complete tutorial construction practice")
		PlayerActions.place_all(world, &"well", [TutorialPlan.well_spot(world)])
		check(lesson.done.call(world, ctx), "placing a new well through player controls completes practice")
	# The shelf lesson asks for flour and yeast, and only that completes it.
	for lesson in TutorialPlan.steps():
		if lesson.id != "filter":
			continue
		var shelf: int = -1
		for i in range(world.build.grid.placements.size()):
			var piece = world.build.grid.placements[i]
			if piece != null and piece["def"].is_storage:
				shelf = i
				break
		if shelf < 0:
			for x in range(world.plot.position.x + 2, world.plot.end.x - 2):
				var spot := Vector2i(x, world.plot.position.y + 4)
				shelf = world.build.place_programmatic(BuildingCatalog.get_def(&"storage_shelf"), spot, 0, false)
				if shelf >= 0:
					break
		var saved_filters: Dictionary = {}
		for i in range(world.build.grid.placements.size()):
			var piece = world.build.grid.placements[i]
			if piece != null and piece["def"].is_storage:
				saved_filters[i] = world.build.grid.filter_of(i).keys()
				world.build.grid.set_filter(i, [])
		var ctx: Dictionary = {}
		world.build.grid.set_filter(shelf, [&"flour"])
		check(shelf >= 0 and not lesson.done.call(world, ctx), "a flour-only shelf does not pass the flour-and-yeast lesson")
		world.build.grid.set_filter(shelf, [&"flour", &"yeast", &"water"])
		check(not lesson.done.call(world, ctx), "nor does a shelf that also takes water")
		world.build.grid.set_filter(shelf, [&"flour", &"yeast"])
		check(lesson.done.call(world, ctx), "flour and yeast, and nothing else, completes it")
		for i in saved_filters:
			world.build.grid.set_filter(i, saved_filters[i])
	# A prior close must not skip the lesson and strand morning-only bookings
	# after noon. Reviews also refer to this particular summary, on any day.
	for lesson in TutorialPlan.steps():
		if lesson.id == "day_end":
			world.ledger.history.append({"day": 1})
			var ctx: Dictionary = {}
			lesson.begin.call(world, ctx)
			check(not lesson.done.call(world, ctx), "an earlier closed day does not complete the day-close lesson")
			world.ledger.history.append({"day": 2})
			check(lesson.done.call(world, ctx), "a fresh day close completes its tutorial lesson")
		elif lesson.id == "reviews":
			world.clock.day = 3
			world.simulation_paused = true
			var ctx: Dictionary = {}
			lesson.begin.call(world, ctx)
			check(not lesson.done.call(world, ctx), "day-three reviews wait for the current summary to be acknowledged")
			world.clock.day = 4
			world.simulation_paused = false
			check(lesson.done.call(world, ctx), "opening the next day completes current reviews")
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("FARM POLISH SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
