extends Node3D

## Original character art contact sheet; no player save or simulation is used.
## Run windowed, with an output prefix after --. Captures front and back views.
var capture_failed: bool = false


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Adventurer showcase needs a windowed renderer.")
		get_tree().quit(2)
		return
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if not args.is_empty() else "res://.verification/adventurers"
	var variants: bool = args.has("variants")
	if args.has("tavern"):
		await _tavern_capture(prefix)
		get_tree().quit(1 if capture_failed else 0)
		return
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("222c35")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c9d4e0")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("ffe2ba")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 10.6 if variants else 8.5
	add_child(camera)
	camera.position = Vector3(0, 10 if variants else 4.7, 12)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.current = true
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.85
	var floor_builder := MeshBuilder.new()
	floor_builder.add_box(Vector3(-7, -0.12, -6), Vector3(14, 0.1, 12), Color("535853"))
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_builder.commit()
	floor_instance.material_override = material
	add_child(floor_instance)
	var rigs: Array[PawnMesh.Rig] = []
	# Style comes from the production builder's two RNG draws. Find matching
	# seeds instead of bypassing the real appearance path for a prettier fixture.
	for i in range(24 if variants else 12):
		# Columns retain the six professions; cycle base styles as well so
		# the sheet shows the full dye range instead of monochrome rows.
		var wanted: int = i % 6 + 6 * ((i / 6 + i % 6) % 5) if variants else [0, 1, 2, 3, 4, 5, 12, 13, 14, 15, 20, -1][i]
		var wanted_variant: int = i / 6 if variants else -1
		var rng := RandomNumberGenerator.new()
		var found: bool = false
		for candidate in range(10000):
			rng.seed = candidate
			var style: int = rng.randi_range(0, 7) + rng.randi_range(0, 3) * 8
			var variation: int = PawnWardrobe.variant_for_state(rng.state)
			if (style == wanted or wanted == -1) and (wanted_variant == -1 or variation == wanted_variant):
				rng.seed = candidate
				found = true
				break
		if not found:
			push_error("No production seed found for style %d variant %d" % [wanted, wanted_variant])
			get_tree().quit(1)
			return
		var rig := PawnMesh.build(rng, material, wanted != -1)
		add_child(rig.root)
		rig.root.position = Vector3((i % 6 - 2.5) * (1.5 if variants else 1.27), 0, (i / 6 - (1.5 if variants else 0.5)) * 2.15)
		rig.root.rotation.y = -0.20
		rigs.append(rig)
		print("LOOK %d: %s" % [wanted, rig.description])
	await get_tree().create_timer(0.5).timeout
	await _capture(prefix + "_front.png")
	for rig in rigs:
		rig.root.rotation.y = PI + 0.35
	await get_tree().process_frame
	await _capture(prefix + "_back.png")
	print("ADVENTURERS count=%d draw_calls=%d primitives=%d" % [rigs.size(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	for rig in rigs:
		rig.root.rotation.y = 0.6
		rig.leg_l.rotation.x = 0.65
		rig.leg_r.rotation.x = -0.65
		rig.arm_l.rotation.x = -0.45
		rig.arm_r.rotation.x = 0.45
		rig.sync_pose()
	await get_tree().process_frame
	await _capture(prefix + "_stride.png")
	# Side views reveal open roll ends and headgear/shoulder intersections that
	# the front contact sheet hides. Reset the limbs to isolate those shapes.
	for rig in rigs:
		rig.root.rotation.y = PI * 0.5
		rig.leg_l.rotation.x = 0
		rig.leg_r.rotation.x = 0
		rig.arm_l.rotation.x = 0
		rig.arm_r.rotation.x = 0
		rig.sync_pose()
	await get_tree().process_frame
	await _capture(prefix + "_side.png")
	get_tree().quit(1 if capture_failed else 0)


func _tavern_capture(prefix: String) -> void:
	SimWait.seed_run()
	GameState.world_seed = 12345
	GameState.pending_level = &"wayfarers_rest"
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	SimWait.configure(world)
	world.input.hover_enabled = false
	# The inherited level intentionally has no sink or prep table. Repair the
	# same three gaps as level_smoke before judging the seated character art;
	# otherwise every seat becomes dirty and a late capture can contain nobody.
	var level: LevelDef = LevelCatalog.get_level(&"wayfarers_rest")
	var origin: Vector2i = world.plot.position + level.origin
	for entry in [["prep_table", Vector2i(1, 3)], ["sink", Vector2i(3, 7)], ["storage_shelf", Vector2i(1, 7)]]:
		var def: BuildingDef = BuildingCatalog.get_def(StringName(entry[0]))
		world.build.mode = BuildController.Mode.PLACE
		world.build.select(def)
		world.build.update_hover(origin + entry[1], true)
		var before: int = world.build.grid.live_count()
		world.commit_build_action()
		if world.build.grid.live_count() != before + 1:
			push_error("Showcase could not repair %s" % entry[0])
			capture_failed = true
			return
	world.build.mode = BuildController.Mode.OFF
	world.order_supplies()
	SimWait.release(world)
	# Capture real seated guests instead of relying on a wall-clock offset:
	# day-length tuning otherwise gives an empty opening or a cleared room.
	var seated: int = 0
	while world.sim.sim_time < world.clock.day_length * 0.5 and seated < 4:
		await SimWait.seconds(world, 1.0)
		seated = 0
		for brain in world.customers.customers:
			if brain.state in [CustomerBrain.State.ORDERING, CustomerBrain.State.WAITING_FOR_ORDER, CustomerBrain.State.EATING]:
				seated += 1
	var elapsed: float = world.sim.sim_time
	print("Capture: %d seated guests at %.1f game seconds" % [seated, elapsed])
	SimWait.hold(world)
	if seated < 4:
		push_error("Showcase did not reach four real seated guests; not a valid seating capture")
		capture_failed = true
		return
	if world.hud._briefing_panel != null:
		world.hud._briefing_panel.hide()
	var scenario: Node = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	add_child(scenario)
	scenario.screenshot_setup({"distance": "17", "pitch": "52", "yaw": "45"})
	await get_tree().create_timer(0.5).timeout
	await _capture(prefix + "_tavern.png")
	scenario.screenshot_setup({"distance": "11", "pitch": "38", "yaw": "25"})
	await get_tree().create_timer(0.5).timeout
	await _capture(prefix + "_tavern_close.png")
	print("Repaired live level at %.1fs: %s" % [elapsed, world.customers.summary()])


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var result: int = get_viewport().get_texture().get_image().save_png(path)
	if result != OK:
		push_error("Cannot save showcase: %s" % path)
		capture_failed = true
	else:
		print("Screenshot: %s" % path)
