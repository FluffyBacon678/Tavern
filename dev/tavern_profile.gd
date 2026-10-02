extends Node

## Whole-tavern rendering baseline. This freezes simulation deliberately: the
## result measures scene rendering, not pathfinding, jobs or customer throughput.
## Run with a real display, never --headless. The first user argument is an
## output directory (default: res://.verification/tavern_profile).
const WORLD_SEED: int = 12345
const WARMUP_MSEC: int = 2000
const SAMPLE_MSEC: int = 5000
const POPULATIONS: Array[int] = [5, 15, 30]

var world: TavernWorld
var output_dir: String


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("TavernProfile requires a debug build and real rendered display.")
		get_tree().quit(1)
		return
	var args := OS.get_cmdline_user_args()
	output_dir = args[0] if not args.is_empty() else "res://.verification/tavern_profile"
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Cannot create profile output directory: %s" % output_dir)
		get_tree().quit(1)
		return
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	OS.low_processor_usage_mode = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	seed(WORLD_SEED)
	# Do not call start_new_run: that allocates a real player save slot.
	GameState.active_slot = -1
	GameState.load_requested = false
	GameState.world_seed = WORLD_SEED
	GameState.tavern_name = "The Render Baseline"
	GameState.gold = GameState.STARTING_GOLD
	world = TavernWorld.new()
	add_child(world)
	var scenario: Node = load("res://dev/world_scenario.gd").new()
	add_child(scenario)
	scenario.world = world
	scenario.screenshot_setup({"demo": "tavern", "distance": "25", "pitch": "52", "yaw": "45", "buildbar": "off"})
	world.order_supplies()
	world.cutaway.update(1.0, world.build, world.rig.camera.global_position, world.rig._focus)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var populations: Array = []
	for count in POPULATIONS:
		_pose_population(count)
		await _warm_up()
		var sample: Dictionary = await _measure(count)
		populations.append(sample)
		var capture_path := output_dir.path_join("tavern_%02d.png" % count)
		get_viewport().get_texture().get_image().save_png(capture_path)
		print("TAVERN_PROFILE population=%d frames=%d median_ms=%.3f p95_ms=%.3f draws=%.0f primitives=%.0f static_mb=%.1f video_mb=%.1f" % [
			count, sample.frames, sample.frame_ms_median, sample.frame_ms_p95,
			sample.draw_calls_median, sample.primitives_median,
			sample.static_memory_bytes / 1048576.0, sample.video_memory_bytes / 1048576.0])
	var report := {
		"scenario": "frozen full tavern; no simulation or animation throughput measured",
		"world_seed": WORLD_SEED,
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"processor": OS.get_processor_name(),
		"viewport": str(get_viewport().get_visible_rect().size),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
		"warmup_ms_per_population": WARMUP_MSEC,
		"sample_ms_per_population": SAMPLE_MSEC,
		"camera": {"distance": 25, "pitch_degrees": 52, "yaw_degrees": 45},
		"measurement": "wall-clock frame_post_draw intervals; includes presentation/OS scheduling, not GPU time",
		"memory": "Godot static allocations and reported rendering memory; not process working set",
		"populations": populations,
	}
	var output := FileAccess.open(output_dir.path_join("report.json"), FileAccess.WRITE)
	if output == null:
		push_error("Could not write profile report")
		get_tree().quit(1)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	get_tree().quit()


func _pose_population(count: int) -> void:
	while world.pawns.size() < count:
		var pawn := Pawn.new()
		world.add_child(pawn)
		pawn.setup(world.nav, world.terrain, world.plot.position + Vector2i(7, 7), world._pawn_material, WORLD_SEED + world.pawns.size(), true)
		world.pawns.append(pawn)
	var origin: Vector2i = world.plot.position + Vector2i(7, 6)
	for i in range(world.pawns.size()):
		var pawn: Pawn = world.pawns[i]
		pawn.stop()
		pawn.autonomous_idle = false
		pawn.tile = origin + Vector2i((i % 6) * 2, i / 6)
		pawn.position = pawn.world_position_of(pawn.tile)
		pawn._rig.root.rotation.y = -PI / 4.0
		pawn._rig.leg_l.rotation.x = 0.35
		pawn._rig.leg_r.rotation.x = -0.35
		pawn._rig.arm_l.rotation.x = -0.45
		pawn._rig.arm_r.rotation.x = 0.45
		pawn._rig.sync_pose()


func _warm_up() -> void:
	var until: int = Time.get_ticks_msec() + WARMUP_MSEC
	while Time.get_ticks_msec() < until:
		await RenderingServer.frame_post_draw


func _measure(population: int) -> Dictionary:
	var intervals: Array[float] = []
	var draws: Array[float] = []
	var primitives: Array[float] = []
	await RenderingServer.frame_post_draw
	var previous: int = Time.get_ticks_usec()
	var until: int = previous + SAMPLE_MSEC * 1000
	while Time.get_ticks_usec() < until:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		intervals.append((now - previous) / 1000.0)
		previous = now
		draws.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
	intervals.sort()
	draws.sort()
	primitives.sort()
	return {
		"population": population,
		"frames": intervals.size(),
		"frame_ms_median": _percentile(intervals, 0.5),
		"frame_ms_p95": _percentile(intervals, 0.95),
		"draw_calls_median": _percentile(draws, 0.5),
		"primitives_median": _percentile(primitives, 0.5),
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"video_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
	}


func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	return sorted_values[clampi(int(ceil(sorted_values.size() * fraction)) - 1, 0, sorted_values.size() - 1)]
