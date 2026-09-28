extends Node

## Windowed, sandboxed atmosphere poses. The tavern is populated normally,
## then only its presentation clock is posed while simulation stays held.
var failed: bool = false


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Atmosphere showcase requires a windowed renderer.")
		get_tree().quit(2)
		return
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if not args.is_empty() else "res://.verification/atmosphere"
	SimWait.seed_run()
	GameState.world_seed = 12345
	GameState.pending_level = &"wayfarers_rest"
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	SimWait.configure(world)
	world.input.hover_enabled = false
	SimWait.release(world)
	await SimWait.seconds(world, 128)
	SimWait.hold(world)
	world.atmosphere.set_process(false)
	world.hud._briefing_panel.hide()
	var scenario: Node = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	add_child(scenario)
	scenario.screenshot_setup({"distance": "19", "pitch": "48", "yaw": "35"})
	var poses := {"morning": 7.5, "day": 13.0, "dusk": 19.0, "night": 22.0, "rain": 13.0}
	for label in poses:
		var hour: float = poses[label]
		var wet: bool = label == "rain"
		var found: bool = false
		for day in range(1, 40):
			var weather: Dictionary = AtmospherePalette.sample(world._world_seed, day, hour / 24.0)
			if (weather.rain > 0.95) if wet else (weather.cloud < 0.10):
				world.clock.day = day
				found = true
				break
		if not found:
			push_error("No matching atmosphere pose: %s" % label)
			failed = true
			continue
		world.clock.fraction = hour / 24.0
		world.atmosphere.refresh()
		world.hud.refresh_stats()
		await get_tree().create_timer(0.3).timeout
		await _capture(prefix + "_" + label + ".png", world)
		if label == "night":
			world.atmosphere.hearths.hide()
			await _capture(prefix + "_night_effects_hidden.png", world)
			world.atmosphere.hearths.show()
		if label == "rain" and args.has("diagnose"):
			world.atmosphere.rain_batch.hide()
			await _capture(prefix + "_rain_hidden.png", world)
			for light in world.atmosphere.hearths.lights:
				light.hide()
			await _capture(prefix + "_lights_hidden.png", world)
	# A low view is essential: the management camera never sees the sky.
	world.hud._hud.hide()
	world.rig.set_process(false)
	world.rig.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	world.rig.camera.fov = 62.0
	world.rig.camera.global_position = Vector3(48, world.terrain.plot_height + 5.5, 29)
	world.rig.camera.look_at(Vector3(50, world.terrain.plot_height + 6.5, 57))
	for sky_pose in ["sky_day", "sky_night"]:
		world.clock.day = 3 if sky_pose == "sky_day" else 1
		world.clock.fraction = 13.0 / 24.0 if sky_pose == "sky_day" else 22.0 / 24.0
		world.atmosphere.refresh()
		world.hud.refresh_stats()
		await get_tree().create_timer(0.3).timeout
		await _capture(prefix + "_" + sky_pose + ".png", world)
	world.clock.day = 3
	world.clock.fraction = 13.0 / 24.0
	world.rig.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.rig.camera.size = 21.0
	var river := Vector3(world.plot.get_center().x, 0, world.river_row)
	world.rig.camera.global_position = river + Vector3(6, 14, 12)
	world.rig.camera.look_at(river)
	world.atmosphere.refresh()
	await _capture(prefix + "_river.png", world)
	var river_pixels: PackedByteArray = get_viewport().get_texture().get_image().get_data()
	world.clock.fraction += 2.0 / world.clock.day_length
	world.atmosphere.refresh()
	await _capture(prefix + "_river_motion.png", world)
	var moved: bool = river_pixels != get_viewport().get_texture().get_image().get_data()
	print("%s: advancing the visual clock changes the rendered river scene" % ("PASS" if moved else "FAIL"))
	failed = failed or not moved
	get_tree().quit(1 if failed else 0)


func _capture(path: String, world: TavernWorld) -> void:
	await RenderingServer.frame_post_draw
	var result: int = get_viewport().get_texture().get_image().save_png(path)
	failed = failed or result != OK
	print("%s: %s day=%d hour=%.2f weather=%s draws=%d primitives=%d" % ["CAPTURE" if result == OK else "FAIL", path, world.clock.day, world.clock.hour(), world.atmosphere.state.name,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
