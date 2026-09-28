extends Node3D

## Debug-only studio for comparing every catalogue item at one scale and light.
## Capture through scenes/_screenshot_harness.tscn; no tavern, jobs or save slot.
const GOODS: Array[StringName] = [
	&"flour", &"yeast", &"water", &"malt", &"hops", &"dough", &"bread", &"beer", &"dirty_dishes",
]


func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().quit(1)
		return
	GameState.active_slot = -1
	GameState.load_requested = false
	_build_studio()
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.2
	camera.position = Vector3(0.0, 18.0, 16.0)
	camera.look_at(Vector3(0.0, 0.8, 0.0))
	camera.current = true
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_add_text(overlay, "TAVERN GOODS", Vector2(0.0, 24.0), Vector2(1280.0, 42.0), 28, Color("f0dfb5"))
	_add_text(overlay, "Original low-poly props  /  shared material atlas", Vector2(0.0, 66.0), Vector2(1280.0, 28.0), 16, Color("bbbca7"))
	var library := ItemMeshLibrary.new()
	var podium_mesh := _podium_mesh()
	var podium_material := StandardMaterial3D.new()
	podium_material.vertex_color_use_as_albedo = true
	podium_material.roughness = 1.0
	for i in range(GOODS.size()):
		var def: ItemDef = ItemCatalog.get_def(GOODS[i])
		var mesh: ArrayMesh = library.mesh_for(def)
		var centre := Vector3(float(i % 3 - 1) * 4.0, 0.0, float(i / 3 - 1) * 3.4)
		var podium := MeshInstance3D.new()
		podium.mesh = podium_mesh
		podium.material_override = podium_material
		podium.position = centre
		add_child(podium)
		var item := MeshInstance3D.new()
		item.mesh = mesh
		item.material_override = TavernMaterials.shared()
		item.position = centre + Vector3(0.0, 0.20, 0.0)
		item.rotation_degrees.y = -22.0
		item.scale = Vector3.ONE * 2.8
		add_child(item)
		var caption: Vector2 = camera.unproject_position(centre + Vector3(0.0, 0.0, 1.20))
		_add_text(overlay, def.display_name, caption + Vector2(-130.0, -2.0), Vector2(260.0, 30.0), 19, Color("eee0c0"))
		var triangles: int = _triangle_count(mesh)
		print("ITEM_GALLERY id=%s triangles=%d surfaces=%d" % [def.id, triangles, mesh.get_surface_count()])
	_add_text(overlay, "FLOUR  ·  YEAST  ·  WATER  ·  MALT  ·  HOPS  ·  DOUGH  ·  BREAD  ·  BEER  ·  DISHES", Vector2(0.0, 678.0), Vector2(1280.0, 24.0), 12, Color("b5baa5"))


func _build_studio() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("202724")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c3cad1")
	environment.ambient_light_energy = 0.40
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment.environment = environment
	add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	key.light_color = Color("fff3df")
	key.light_energy = 0.65
	key.shadow_enabled = true
	key.shadow_opacity = 0.45
	add_child(key)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("202724")
	floor_material.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = plane
	floor_instance.material_override = floor_material
	floor_instance.position.y = -0.01
	add_child(floor_instance)


func _podium_mesh() -> ArrayMesh:
	var builder := MeshBuilder.new()
	builder.add_box(Vector3(-1.07, 0.0, -0.87), Vector3(2.14, 0.08, 1.74), Color("565c4c"))
	builder.add_box(Vector3(-1.0, 0.08, -0.80), Vector3(2.0, 0.12, 1.60), Color("626758"))
	return builder.commit()


func _add_text(parent: Node, text: String, origin: Vector2, extent: Vector2, font_size: int, tint: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = origin
	label.size = extent
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color(0.1, 0.13, 0.09, 0.75))
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)


func _triangle_count(mesh: ArrayMesh) -> int:
	var total: int = 0
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index_count: int = 0
		if arrays[Mesh.ARRAY_INDEX] != null:
			index_count = arrays[Mesh.ARRAY_INDEX].size()
		total += (index_count if index_count > 0 else vertices.size()) / 3
	return total
