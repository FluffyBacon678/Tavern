extends Node

## Windowed, sandboxed art fixture; posed growth stages are not simulation evidence.
func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Farm showcase requires a windowed renderer.")
		get_tree().quit(2)
		return
	SimWait.seed_run()
	GameState.full_house_start = true
	GameState.start_new_run("Farm art", 493774, GameState.MAX_SLOTS - 1, true)
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	world.hud._hud.hide()
	world.rig.set_process(false)
	world.clock.day = 3
	world.clock.fraction = 13.0 / 24.0
	world.atmosphere.refresh()
	var targets: Dictionary = {}
	var plot_number: int = 0
	for entry in world.build.grid.placements:
		if entry == null:
			continue
		var id: StringName = entry["def"].id
		if id == &"farm_plot":
			entry["growth"] = [0.1, 0.6, 1.0, 1.0][plot_number % 4]
			plot_number += 1
			if not targets.has("field"):
				targets["field"] = Vector2(entry["origin"]) + Vector2(4, 2)
		elif id == &"well" or id == &"river_pump":
			targets[String(id)] = Vector2(entry["origin"]) + Vector2(entry["def"].size) * 0.5
	world.farm._show_crops()
	world.rig.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if not args.is_empty() else "res://.verification/farm"
	var failed: bool = false
	for key in targets:
		var centre := Vector3(targets[key].x, world.terrain.plot_height, targets[key].y)
		world.rig.camera.size = 10.0 if key == "field" else 4.5
		world.rig.camera.global_position = centre + Vector3(6, 7, 9)
		world.rig.camera.look_at(centre)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = "%s_%s.png" % [prefix, key]
		var result: int = get_viewport().get_texture().get_image().save_png(path)
		failed = failed or result != OK
		print("CAPTURE: %s (%d)" % [path, result])
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failed else 0)
