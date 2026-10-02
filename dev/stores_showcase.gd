extends Node

func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Stores showcase requires a windowed renderer.")
		get_tree().quit(2)
		return
	SimWait.seed_run()
	GameState.full_house_start = true
	GameState.start_new_run("The Full House", 493774, GameState.MAX_SLOTS - 1, true)
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	world.hud._supply_panel.toggle()
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if not args.is_empty() else "res://.verification/stores"
	var failures: int = 0
	for shape in [Vector2i(1280, 720), Vector2i(1024, 768)]:
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = shape
		for frame in range(6):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = "%s_%dx%d.png" % [prefix, shape.x, shape.y]
		var result: int = get_viewport().get_texture().get_image().save_png(path)
		if result != OK:
			failures += 1
		print("CAPTURE: %s (window %s, viewport %s, result %d)" % [path, get_window().size, get_viewport().get_visible_rect().size, result])
	world.hud._supply_panel.show_manual()
	for frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var manual_path: String = prefix + "_manual.png"
	if get_viewport().get_texture().get_image().save_png(manual_path) != OK:
		failures += 1
	print("CAPTURE: %s" % manual_path)
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)
