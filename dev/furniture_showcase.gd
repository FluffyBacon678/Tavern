extends Node3D

## Render the production meshes, with the same atlas as the tavern. Windowed
## only; the first user argument is the output prefix for front/back PNGs.
const FURNITURE := ["table", "chair", "serving_counter", "prep_table", "oven", "brewing_vat", "storage_shelf", "sink", "barrel"]


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Furniture showcase needs a windowed renderer.")
		get_tree().quit(2)
		return
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if not args.is_empty() else "res://.verification/furniture"
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("252f30")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c9d4e0")
	environment.environment.ambient_light_energy = 0.45
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("ffe9c9")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 14.0
	add_child(camera)
	camera.position = Vector3(0, 18, 14)
	camera.look_at(Vector3(0, 0.45, 0))
	camera.current = true
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var library := BuildingMeshLibrary.new()
	var models: Array[Node3D] = []
	for i in range(FURNITURE.size()):
		var def: BuildingDef = BuildingCatalog.get_def(FURNITURE[i])
		var mesh: ArrayMesh = library.mesh_for(def)
		var pivot := Node3D.new()
		pivot.position = Vector3((i % 3 - 1) * 3.9, 0, (i / 3 - 1) * 3.4)
		pivot.rotation.y = -0.20
		add_child(pivot)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = TavernMaterials.shared()
		instance.position = Vector3(-def.size.x * 0.5, 0, -def.size.y * 0.5)
		pivot.add_child(instance)
		models.append(pivot)
		var label := Label.new()
		label.text = def.display_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = camera.unproject_position(pivot.position + Vector3(0, 0, 1.18)) - Vector2(145, 0)
		label.size = Vector2(290, 28)
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", Color("e1d8c1"))
		overlay.add_child(label)
		print("FURNITURE id=%s surfaces=%d triangles=%d bounds=%s" % [def.id, mesh.get_surface_count(), mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3, mesh.get_aabb()])
	var plane := MeshInstance3D.new()
	var ground := PlaneMesh.new()
	ground.size = Vector2(100, 100)
	plane.mesh = ground
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("414d48")
	material.roughness = 1
	plane.material_override = material
	plane.position.y = -0.006
	add_child(plane)
	await get_tree().create_timer(0.5).timeout
	var ok: bool = await _capture(prefix + "_front.png")
	print("FURNITURE_RENDER draws=%d primitives=%d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	for pivot in models:
		pivot.rotation.y += PI
	await get_tree().process_frame
	ok = await _capture(prefix + "_back.png") and ok
	get_tree().quit(0 if ok else 1)


func _capture(path: String) -> bool:
	await RenderingServer.frame_post_draw
	var result: int = get_viewport().get_texture().get_image().save_png(path)
	print("%s: %s" % ["Screenshot" if result == OK else "FAIL: screenshot", path])
	return result == OK
