extends Node

var failures: int = 0


func check(ok: bool, message: String) -> void:
	TestOutput.check_line(ok, message)
	failures += int(not ok)


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	SimWait.seed_run()
	GameState.world_seed = 12345
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	var scenery: WorldScenery = world.get_node("Scenery")
	var before: Dictionary = SaveGame.capture(world)
	before.erase("saved_at")
	seed(4567)
	var expected: int = randi()
	seed(4567)
	var copy := WorldScenery.new()
	world.add_child(copy)
	copy.setup(world)
	check(randi() == expected, "scenery does not consume gameplay RNG")
	check(copy.positions == scenery.positions, "same seed reproduces every scenery position")
	var after: Dictionary = SaveGame.capture(world)
	after.erase("saved_at")
	check(before == after, "decorative rebuild leaves complete gameplay snapshot unchanged")
	copy.queue_free()
	await get_tree().process_frame
	check(_clear_of_play(world, scenery), "all scenery stays outside buildable land and roads")
	var triangles: int = 0
	var correct_colours: bool = true
	var capped: bool = scenery.batches.size() == 4
	for i in range(scenery.batches.size()):
		var batch: MultiMeshInstance3D = scenery.batches[i]
		var count: int = batch.multimesh.instance_count
		if DisplayServer.get_name() != "headless" and count > 0:
			correct_colours = correct_colours and batch.multimesh.get_instance_color(0).is_equal_approx(Color.WHITE)
		capped = capped and count <= WorldScenery.CAPS[i]
		triangles += batch.multimesh.mesh.get_faces().size() / 3 * count
		print("SCENERY %s: instances=%d triangles=%d" % [batch.name, count, batch.multimesh.mesh.get_faces().size() / 3 * count])
	check(capped and triangles < 35000, "four bounded batches stay below 35000 added triangles")
	if DisplayServer.get_name() != "headless":
		check(correct_colours, "rendered instances preserve mesh colours with white modulation")
	scenery.apply_quality(GameSettings.Quality.LOW)
	var low: int = 0
	for batch in scenery.batches:
		low += batch.multimesh.visible_instance_count
	scenery.apply_quality(GameSettings.Quality.HIGH)
	var high: int = 0
	for batch in scenery.batches:
		high += batch.multimesh.visible_instance_count
	check(low < high * 0.31, "low quality renders only thirty percent of decoration")
	scenery.apply_quality(GameSettings.quality)
	var no_plot_water: bool = true
	var faces: PackedVector3Array = world.get_node("Water").mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var centre: Vector3 = (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		no_plot_water = no_plot_water and not world.plot.has_point(Vector2i(floori(centre.x), floori(centre.z)))
	check(no_plot_water, "shore water never covers a buildable plot tile")
	# Consecutive purchases catch deferred-name collisions and stale scenery.
	# Fund this geometry fixture; parcel affordability is covered elsewhere.
	GameState.gold = 10000
	for direction in [TavernWorld.SIDE_WEST, TavernWorld.SIDE_EAST]:
		var bought: bool = world.buy_land(direction)
		await get_tree().process_frame
		scenery = world.get_node_or_null("Scenery")
		check(bought and scenery != null and _clear_of_play(world, scenery), "land purchase rebuilds scenery clear of the expanded plot")
		var batches: int = 0
		for child in world.get_children():
			batches += int(child is WorldScenery)
		check(batches == 1 and world.get_node_or_null("Terrain") != null and world.get_node_or_null("Forest") != null, "land purchase keeps one named scenery/terrain/forest set")
	print("SCENERY SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _clear_of_play(world: TavernWorld, scenery: WorldScenery) -> bool:
	for group in scenery.positions:
		for point in group:
			var tile := Vector2i(floori(point.x), floori(point.z))
			if world.plot.grow(1).has_point(tile) or (world.grid.water_flags[world.grid.index(tile.x, tile.y)] & TerrainGrid.FLAG_PATH) != 0:
				return false
	return true
