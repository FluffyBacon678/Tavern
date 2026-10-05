extends Node

## Reproduce whole-system edge cases with real navigation, item meshes and jobs.
## No player slot is used; the small fixtures make failures deterministic.
var failures: int = 0


func check(ok: bool, message: String) -> void:
	TestOutput.check_line(ok, message)
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	GameState.world_seed = 12345
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	_check_full_kitchen(world)
	_check_seating(world)
	print("POLISH REGRESSIONS: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check_full_kitchen(world: TavernWorld) -> void:
	var stock := ItemWorld.new()
	add_child(stock)
	stock.setup(world.terrain)
	var generator := JobGenerator.new()
	add_child(generator)
	generator.set_process(false)
	generator.items = stock
	generator.board = JobBoard.new()
	var centre := Vector2i(40, 40)
	var water: ItemDef = ItemCatalog.get_def(&"water")
	var dough: ItemDef = ItemCatalog.get_def(&"dough")
	for y in range(-6, 7):
		for x in range(-6, 7):
			var tile: Vector2i = centre + Vector2i(x, y)
			stock.add(dough if tile == centre else water, 2 if tile == centre else 20, tile, 0.8)
	var station: Dictionary = {"index": 0, "centre": centre, "input_tiles": [centre]}
	var recipe: Recipe = RecipeCatalog.get_recipe(&"bake_bread")
	# However many loaves a batch bakes (ten, since goods came in bulk).
	var loaves: int = int(recipe.outputs[0]["count"])
	generator._post_cook_job(station, recipe)
	var job: Job = generator.board.jobs[0]
	job.apply_work(recipe.work_amount)
	check(stock.total_of(&"dough") == 2, "a full kitchen retains every ingredient")
	check(stock.total_of(&"bread") == 0 and generator.produced.is_empty(), "a blocked batch creates no phantom output")
	check(job.state != Job.State.DONE, "a full kitchen retains the finished work for retry")
	# Releasing one tile must finish the same batch once, without repeating work.
	stock.take(centre + Vector2i(1, 0), 20)
	job.apply_work(0.5)
	check(stock.total_of(&"dough") == 1 and stock.total_of(&"bread") == loaves, "making space completes exactly one batch")
	check(job.state == Job.State.DONE, "the waiting cook finishes when space appears")
	check(is_equal_approx(stock.quality_at(centre + Vector2i(1, 0)), 0.65), "deferred output preserves ingredient quality")
	check(int(generator.consumed.get(&"dough", 0)) == 2 - stock.total_of(&"dough") and int(generator.produced.get(&"bread", 0)) == stock.total_of(&"bread"), "deferred batch reconciles physical stock and production counters")
	# The first product can merge into existing bread, but the second cannot
	# fit. No half-batch may commit merely because its first output has room.
	stock.add(dough, 1, centre, 0.8)
	var dual := Recipe.make("fixture_dual", "Fixture", "oven", 1.0, WorkType.Kind.COOK,
		[Recipe.ingredient("dough", 1)], [Recipe.ingredient("bread", 2), Recipe.ingredient("beer", 4)])
	check(not generator._complete_recipe(station, dual), "a multi-output batch waits until every product fits")
	check(stock.total_of(&"dough") == 2 and stock.total_of(&"bread") == loaves and stock.total_of(&"beer") == 0,
		"a blocked second output does not consume or produce a partial batch")
	stock.take(centre + Vector2i(-1, 0), 20)
	var resumed: bool = generator._complete_recipe(station, dual)
	if not resumed:
		print("DUAL BLOCK: %s; dough=%d bread=%d cleared=%d" % [generator.completion_problem,
			stock.total_of(&"dough"), stock.total_of(&"bread"), stock.count_at(centre + Vector2i(-1, 0))])
	check(resumed, "a multi-output batch resumes after capacity is freed")
	check(stock.total_of(&"dough") == 1 and stock.total_of(&"bread") == loaves + 2 and stock.total_of(&"beer") == 4,
		"all products commit together with exact recipe quantities")
	stock.queue_free()
	generator.queue_free()


func _check_seating(world: TavernWorld) -> void:
	var terrain := TerrainGrid.new()
	terrain.cols = 10
	terrain.rows = 10
	terrain.cells.resize(100)
	terrain.cells.fill(TerrainGrid.Cell.GRASS)
	terrain.water_flags.resize(100)
	# A walkable chair stranded inside a ring of blocked terrain, plus a farther
	# reachable chair. Choosing the nearest chair forever starves the second one.
	for step in TerrainGrid.NEIGHBOURS:
		var tile: Vector2i = Vector2i(3, 3) + step
		terrain.cells[terrain.index(tile.x, tile.y)] = TerrainGrid.Cell.WATER
	var grid := BuildGrid.new()
	grid.setup(10, 10, Rect2i(0, 0, 10, 10))
	var nav := NavGrid.new()
	nav.setup(terrain, grid)
	var seats := Seating.new()
	seats.seats = [
		{"chair": Vector2i(3, 3), "table": Vector2i(3, 4), "taken_by": null},
		{"chair": Vector2i(1, 7), "table": Vector2i(2, 7), "taken_by": null},
	]
	var pawn: Pawn = world.pawns[0]
	pawn.stop()
	pawn.nav = nav
	pawn.tile = Vector2i(1, 3)
	var brain := CustomerBrain.new()
	brain.pawn = pawn
	brain.nav = nav
	brain.seating = seats
	brain._patience = 60.0
	brain._process_seeking_seat(0.1)
	check(brain.seat == seats.chair_of(1), "a customer skips an unreachable nearest seat")
	seats.release_for(brain)
	pawn.stop()
	pawn.tile = Vector2i(1, 7)
	brain._process_seeking_seat(0.1)
	check(brain.seat == seats.chair_of(1), "a customer already at a chair can take it")
	seats.release_for(brain)
	pawn.stop()
	pawn.tile = Vector2i(1, 3)
	terrain.cells.fill(TerrainGrid.Cell.GRASS)
	nav.refresh_all()
	brain._process_seeking_seat(0.1)
	check(brain.seat == seats.chair_of(0), "opening access makes the nearer chair available again")
	seats.release_for(brain)
	pawn.stop()
	brain.free()
