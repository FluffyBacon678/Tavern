extends Node

func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Scenery showcase requires a windowed renderer.")
		get_tree().quit(2)
		return
	SimWait.seed_run()
	GameState.world_seed = 12345
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	world.hud._hud.hide()
	world.rig.set_process(false)
	world.clock.day = 3
	world.clock.fraction = 13.0 / 24.0
	world.atmosphere.refresh()
	world.rig.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.rig.camera.size = 5
	var scenery: WorldScenery = world.get_node("Scenery")
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if not args.is_empty() else "res://.verification/scenery"
	var failed: bool = false
	for kind in range(scenery.positions.size()):
		var centre: Vector3 = scenery.positions[kind][0]
		world.rig.camera.global_position = centre + Vector3(3, 4, 5)
		world.rig.camera.look_at(centre + Vector3(0, 0.3, 0))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = "%s_%s.png" % [prefix, scenery.batches[kind].name]
		var result: int = get_viewport().get_texture().get_image().save_png(path)
		failed = failed or result != OK
		print("%s: %s" % ["CAPTURE" if result == OK else "FAIL", path])
	get_tree().quit(1 if failed else 0)
