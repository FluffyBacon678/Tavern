extends Node

var failures: int = 0


func check(ok: bool, message: String) -> void:
	TestOutput.check_line(ok, message)
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	SimWait.seed_run()
	GameState.world_seed = 12345
	GameState.pending_level = &"wayfarers_rest"
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	var fx: WorldAtmosphere = world.atmosphere
	var before: Dictionary = SaveGame.capture(world)
	before.erase("saved_at")
	seed(9537)
	var expected_random: int = randi()
	seed(9537)
	for i in range(20):
		fx.refresh()
	check(randi() == expected_random, "atmosphere never advances gameplay RNG")
	var after: Dictionary = SaveGame.capture(world)
	after.erase("saved_at")
	check(before == after, "visual refresh leaves the complete gameplay snapshot unchanged")
	var time: float = fx.effect_time
	await get_tree().process_frame
	await get_tree().process_frame
	check(is_equal_approx(fx.effect_time, time), "pause freezes fire, rain, wind and water shader time")
	var all_weather: Dictionary = {}
	var bounded: bool = true
	var continuous: bool = true
	for day in range(1, 8):
		for hour in range(24):
			var state: Dictionary = AtmospherePalette.sample(12345, day, hour / 24.0)
			all_weather[state.name] = true
			for key in ["rain", "wind", "cloud", "daylight"]:
				bounded = bounded and state[key] >= 0.0 and state[key] <= 1.0
			if hour > 0:
				var prior: Dictionary = AtmospherePalette.sample(12345, day, (hour - 0.0001) / 24.0)
				continuous = continuous and absf(prior.rain - state.rain) < 0.001 and absf(prior.cloud - state.cloud) < 0.001
	check(all_weather.size() == 3 and bounded, "clear, overcast and rain occur with bounded strengths")
	check(continuous, "weather fronts blend continuously across hour boundaries")
	check(AtmospherePalette.sample(12345, 4, 0.75) == AtmospherePalette.sample(12345, 4, 0.75), "weather repeats from saved seed, day and clock")
	world.clock.fraction = 0.5
	fx.refresh()
	var noon: float = fx.sun.light_energy
	world.clock.fraction = 22.0 / 24.0
	fx.refresh()
	check(fx.sun.light_energy < noon and fx.environment.ambient_light_energy >= 0.38, "night changes lighting while retaining readable ambient fill")
	world.clock.fraction = float(before.clock_fraction)
	fx.refresh()
	var sheltered: int = 0
	for room in world.rooms.current():
		for tile in room.tiles:
			if fx.shelter_image.get_pixel(tile.x, tile.y).r > 0.5:
				sheltered += 1
	check(sheltered > 0, "completed tavern rooms mask rain even with cutaway walls")
	check(fx.hearths.lanterns.fixtures.multimesh.visible_instance_count > 0 and fx.hearths.lanterns.fixtures.multimesh.visible_instance_count <= 4, "completed rooms receive a bounded batch of wall lanterns")
	var yard: Vector2i = world.unloading_yard().position
	check(fx.shelter_image.get_pixel(yard.x, yard.y).r < 0.5, "the outdoor delivery yard remains exposed to rain")
	var ovens: int = world.build.grid.live_of(&"oven", true).size()
	check(fx.hearths.hearth_count == mini(ovens, WorldHearths.MAX_HEARTHS), "finished ovens have batched fire effects")
	var tile := world.plot.position + Vector2i(1, 1)
	var added: int = world.build.place_programmatic(BuildingCatalog.get_def(&"oven"), tile, 1, true)
	fx.refresh()
	check(added >= 0 and fx.hearths.hearth_count == ovens, "oven blueprints do not emit fire or smoke")
	world.build.grid.mark_built(added)
	fx.refresh()
	check(fx.hearths.hearth_count == ovens + 1, "completing a rotated oven creates its hearth")
	if DisplayServer.get_name() != "headless":
		var placement: Dictionary = world.build.grid.placements[added]
		var expected: Transform3D = world.build._placement_transform(placement.def, placement.origin, 1) * Transform3D(Basis.IDENTITY, Vector3(1, 0.56, 0.975))
		check(fx.hearths.flames.multimesh.get_instance_transform(ovens).is_equal_approx(expected), "rotated flame follows the oven mouth")
	world.build.grid.remove(added)
	fx.refresh()
	check(fx.hearths.hearth_count == ovens, "demolishing an oven removes its fire and light")
	fx.hearths.update_effects(time, 0.8, 0.0, GameSettings.Quality.LOW)
	var light_count: int = 0
	for light in fx.hearths.lights:
		if light.visible:
			light_count += 1
	check(not fx.hearths.smoke.visible and light_count <= 2, "low quality disables smoke and caps local lights")
	# Removing even one completed boundary exposes its room; a replacement
	# blueprint must not act as a roof until the wall is actually finished.
	var room_tile: Vector2i = world.rooms.current()[0].tiles[0]
	var boundary: int = -1
	for room in world.rooms.current():
		for inside in room.tiles:
			for direction in Rooms.NEIGHBOURS:
				var index: int = world.build.grid.object_index_at(inside + direction)
				if index >= 0 and world.build.grid.placements[index].def.shape == BuildingDef.Shape.WALL:
					boundary = index
					room_tile = inside
					break
			if boundary >= 0:
				break
		if boundary >= 0:
			break
	check(boundary >= 0, "shelter fixture has a removable boundary wall")
	if boundary >= 0:
		var wall: Dictionary = world.build.grid.placements[boundary].duplicate()
		world.build.grid.remove(boundary)
		fx.refresh()
		check(fx.shelter_image.get_pixel(room_tile.x, room_tile.y).r < 0.5, "opening a room boundary exposes its floor to weather")
		var replacement: int = world.build.place_programmatic(wall.def, wall.origin, wall.rotation, true)
		fx.refresh()
		check(fx.shelter_image.get_pixel(room_tile.x, room_tile.y).r < 0.5, "an unfinished wall does not shelter its room")
		world.build.grid.mark_built(replacement)
		fx.refresh()
		check(fx.shelter_image.get_pixel(room_tile.x, room_tile.y).r > 0.5, "finishing the boundary restores weather shelter")
	var weather_before: Dictionary = fx.state.duplicate()
	world.clock.day += 3
	world.clock.fraction = 22.0 / 24.0
	fx.refresh()
	var weather_changed: bool = fx.state != weather_before
	SaveGame.apply(world, before)
	fx.refresh()
	check(weather_changed and fx.state == weather_before, "restoring a saved world restores its weather without extra save fields")
	SimWait.configure(world)
	var held_time: float = fx.effect_time
	SimWait.release(world)
	await SimWait.seconds(world, 1.0)
	SimWait.hold(world)
	fx.refresh()
	check(fx.effect_time > held_time, "resuming simulation advances the shared effect clock")
	print("ATMOSPHERE SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
