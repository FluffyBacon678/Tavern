extends Node3D

## Windowed art QA, not a player feature or simulation fixture. First argument
## after -- is the output prefix (also accepts prefix=...). Captures production
## character geometry directly: front, back, side, and combined travelling kit.
## Rows are separated vertically instead of in depth so faces never overlap.
const WINDOW_SIZE := Vector2i(1600, 1100)
const HAIR_NAMES: Array[String] = ["Cropped fringe", "Swept", "Tied back", "Close crop"]

var failures: int = 0
var _prefix: String = "res://.verification/character_art"
var _camera: Camera3D
var _material: StandardMaterial3D
var _rigs: Array[PawnMesh.Rig] = []
var _appearances: Array[CharacterAppearance] = []
var _title: Label
var _caption: Label


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("ERROR: Character showcase requires a windowed renderer; remove --headless.")
		get_tree().quit(2)
		return
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_prefix = arguments[0].trim_prefix("prefix=")
	if _prefix.is_empty():
		printerr("ERROR: Character showcase needs a non-empty output prefix.")
		get_tree().quit(2)
		return
	var output_directory: String = ProjectSettings.globalize_path(_prefix).get_base_dir()
	var made: int = DirAccess.make_dir_recursive_absolute(output_directory)
	if made != OK:
		printerr("ERROR: Cannot create character showcase directory: %s (%d)." % [output_directory, made])
		get_tree().quit(1)
		return
	var window: Window = get_window()
	window.mode = Window.MODE_WINDOWED
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_size = Vector2i.ZERO
	window.size = WINDOW_SIZE
	window.title = "Character art showcase · development"
	await _frames(3)
	print("CHARACTER SHOWCASE WINDOW: requested=%s actual=%s viewport=%s" % [WINDOW_SIZE, window.size, get_viewport().get_visible_rect().size])
	if window.size.x < WINDOW_SIZE.x or window.size.y < WINDOW_SIZE.y:
		print("NOTE: Showcase window was clamped; captures use the actual size above.")
	_build_stage()
	_build_characters()
	_build_labels()
	await _frames(5)
	await _capture("front", "Front", 0.0)
	await _capture("back", "Back", PI)
	await _capture("side", "Side", PI * 0.5)
	_build_travel_kit()
	# Columns show front three-quarter, profile, rear, and rear three-quarter.
	var angles: Array[float] = [-0.35, PI * 0.5, PI, PI * 1.25]
	for i in range(_rigs.size()):
		_rigs[i].root.rotation.y = angles[i % 4]
	_title.text = "Character art · Travelling kit"
	_caption.text = "Hat, cape and backpack together · front three-quarter / side / back / rear three-quarter"
	await _frames(3)
	await _capture_image("travel_kit")
	print("CHARACTER SHOWCASE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _build_stage() -> void:
	var surroundings := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("20292b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d3dbe1")
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	surroundings.environment = environment
	add_child(surroundings)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -32, 0)
	key.light_color = Color("fff4dd")
	key.light_energy = 0.65
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22, 145, 0)
	fill.light_color = Color("d6e3ef")
	fill.light_energy = 0.25
	add_child(fill)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = 3.35
	add_child(_camera)
	_camera.position = Vector3(0, 1.5, 10)
	_camera.look_at(Vector3(0, 1.5, 0))
	_camera.current = true
	get_viewport().msaa_3d = Viewport.MSAA_2X
	# Match the production pawn material, including its vertex-colour pipeline.
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var background := MeshBuilder.new()
	background.add_box(Vector3(-3, -0.5, -1), Vector3(6, 4, 0.04), Color("3a413d"))
	var wall := MeshInstance3D.new()
	wall.mesh = background.commit()
	wall.material_override = _material
	add_child(wall)


func _build_characters() -> void:
	for body in range(2):
		for hair in range(4):
			var index: int = body * 4 + hair
			var appearance := CharacterAppearance.new()
			appearance.body_type = body
			appearance.hair_style = hair
			appearance.skin = CharacterAppearance.SKIN_COLORS[index % CharacterAppearance.SKIN_COLORS.size()]
			appearance.hair = CharacterAppearance.HAIR_COLORS[(index + 1) % CharacterAppearance.HAIR_COLORS.size()]
			appearance.top = CharacterAppearance.TOP_COLORS[index % CharacterAppearance.TOP_COLORS.size()]
			appearance.trousers = CharacterAppearance.TROUSER_COLORS[(hair + body) % CharacterAppearance.TROUSER_COLORS.size()]
			appearance.boots = CharacterAppearance.BOOT_COLORS[hair % CharacterAppearance.BOOT_COLORS.size()]
			_appearances.append(appearance)
			var rig: PawnMesh.Rig = PawnMesh.build_appearance(appearance, _material)
			add_child(rig.root)
			rig.root.position = _position_for(index)
			_relax(rig)
			_rigs.append(rig)
			_validate(rig, "%s / %s" % ["Broad" if body == 0 else "Slender", HAIR_NAMES[hair]])
			var plinth_mesh := MeshBuilder.new()
			plinth_mesh.add_cylinder(Vector3(0, -0.065, 0), 0.405, 0.39, 0.06, 16, Color("735338"))
			plinth_mesh.add_cylinder(Vector3(0, -0.065, 0), 0.407, 0.407, 0.01, 16, Color("9e8654"))
			var plinth := MeshInstance3D.new()
			plinth.mesh = plinth_mesh.commit()
			plinth.material_override = _material
			plinth.position = rig.root.position
			add_child(plinth)


func _position_for(index: int) -> Vector3:
	return Vector3((float(index % 4) - 1.5) * 1.14, 1.72 if index < 4 else 0.12, 0)


func _relax(rig: PawnMesh.Rig) -> void:
	rig.arm_l.rotation.z = -0.045
	rig.arm_r.rotation.z = 0.045
	rig.sync_pose()


func _build_labels() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_title = Label.new()
	_title.position = Vector2(28, 18)
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color("eee0bc"))
	overlay.add_child(_title)
	_caption = Label.new()
	_caption.position = Vector2(30, 58)
	_caption.add_theme_font_size_override("font_size", 17)
	_caption.add_theme_color_override("font_color", Color("b4bdb7"))
	overlay.add_child(_caption)
	for i in range(_rigs.size()):
		var label := Label.new()
		label.text = "%s · %s" % ["Broad" if i < 4 else "Slender", HAIR_NAMES[i % 4]]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = _camera.unproject_position(_position_for(i) + Vector3(0, -0.12, 0)) - Vector2(160, 0)
		label.size = Vector2(320, 30)
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color("ded6c1"))
		overlay.add_child(label)


func _build_travel_kit() -> void:
	var kit: Dictionary = {"head": "felt_hat", "cape": "travel_cape", "backpack": "travel_pack"}
	for i in range(_rigs.size()):
		var old: Node3D = _rigs[i].root
		remove_child(old)
		old.queue_free()
		var rig: PawnMesh.Rig = PawnMesh.build_appearance(_appearances[i], _material, kit)
		add_child(rig.root)
		rig.root.position = _position_for(i)
		_relax(rig)
		_rigs[i] = rig
		_validate(rig, "travel kit %d" % i)


func _validate(rig: PawnMesh.Rig, description: String) -> void:
	var one_surface: bool = rig.body.mesh.get_surface_count() == 1 and rig.skeleton.get_bone_count() == 6
	var vertices: PackedVector3Array = rig.body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var finite: bool = true
	for vertex in vertices:
		finite = finite and vertex.is_finite() and vertex.y >= -0.001 and vertex.y < 1.6 and absf(vertex.x) < 0.5 and absf(vertex.z) < 0.5
	if not one_surface or not finite:
		failures += 1
	print("%s: CHARACTER %s surfaces=%d bones=%d triangles=%d finite_bounds=%s" % ["PASS" if one_surface and finite else "FAIL", description, rig.body.mesh.get_surface_count(), rig.skeleton.get_bone_count(), vertices.size() / 3, finite])


func _capture(label: String, title: String, angle: float) -> void:
	for rig in _rigs:
		rig.root.rotation.y = angle
	_title.text = "Character art · %s" % title
	_caption.text = "Two body builds × four hair styles · existing skin, hair and clothing palettes"
	await _frames(3)
	await _capture_image(label)


func _capture_image(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "%s_%s.png" % [_prefix, label]
	var pixels: Image = get_viewport().get_texture().get_image()
	var result: int = pixels.save_png(path)
	if result != OK:
		failures += 1
	print("%s: CAPTURE %s size=%s draws=%d primitives=%d" % ["PASS" if result == OK else "FAIL", path, pixels.get_size(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame
