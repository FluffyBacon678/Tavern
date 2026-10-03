extends Node3D

## Windowed, sandboxed character art QA. Run with -- prefix=res://.../reference.
## The two people are production PawnMesh geometry, not an image mockup. Dyes
## are local fixture copies and never replace the keeper's stored profile.
## Walking/carrying use the production rigid-bone angles. The seated picture
## is labelled a clearance diagnostic: the current rig has no knee bones or
## gameplay sitting animation, so it cannot honestly demonstrate either.
const WINDOW_SIZE := Vector2i(1600, 1000)
const POSITIONS: Array[Vector3] = [Vector3(-0.45, 0, 0), Vector3(0.45, 0, 0)]
const WAITER_KIT := {"head": "server_cap", "body": "house_waistcoat", "outer": "waist_apron"}
const COLOUR_QUANTIZATION_TOLERANCE: float = 1.0 / 255.0 + 0.00001

var failures: int = 0
var _prefix: String = ""
var _camera: Camera3D
var _material: StandardMaterial3D
var _rigs: Array[PawnMesh.Rig] = []
var _title: Label
var _caption: Label
var _labels: Array[Label] = []
var _tray: Node3D
var _chairs: Array[Node3D] = []


func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("ERROR: Reference character showcase requires a windowed renderer; remove --headless.")
		get_tree().quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("prefix="):
			_prefix = argument.trim_prefix("prefix=")
	if _prefix.is_empty():
		printerr("ERROR: Provide an explicit screenshot prefix after --, for example prefix=res://.verification/reference_character.")
		get_tree().quit(2)
		return
	var made: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_prefix).get_base_dir())
	if made != OK:
		printerr("ERROR: Cannot create reference character output directory (%d)." % made)
		get_tree().quit(1)
		return
	var window: Window = get_window()
	window.mode = Window.MODE_WINDOWED
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_size = Vector2i.ZERO
	window.size = WINDOW_SIZE
	window.title = "Reference character art · development"
	await _frames(3)
	print("REFERENCE CHARACTER WINDOW: requested=%s actual=%s viewport=%s" % [WINDOW_SIZE, window.size, get_viewport().get_visible_rect().size])
	if window.size.x < WINDOW_SIZE.x or window.size.y < WINDOW_SIZE.y:
		print("NOTE: Window was clamped; all screenshots and framing checks use the actual viewport.")
	var owner_before: Dictionary = GameState.owner_profile.to_save()
	_build_stage()
	_build_characters()
	_build_labels()
	await _capture("front", "Front", 0.0)
	await _capture("three_quarter", "Three-quarter", -0.55)
	await _capture("side", "Side", PI * 0.5)
	await _capture("back", "Back", PI)
	_build_tray()
	_set_pose("carry")
	await _capture("carrying", "Carrying · actual beer mugs on a tray fixture", -0.4)
	_set_pose("walk")
	await _capture("walking", "Walking · opposite legs, counter-swing and held tray", -0.55)
	await _capture("walking_side", "Walking · side clearance", PI * 0.5)
	_set_pose("seated")
	_build_clearance_chairs()
	print("NOTE: Seated captures are a static rigid-leg clearance fixture, not an implemented sitting animation.")
	await _capture("seated_clearance", "Seated clearance · static rigid-leg diagnostic", -0.55)
	await _capture("seated_side", "Seated clearance · profile", PI * 0.5)
	check(GameState.owner_profile.to_save() == owner_before, "fixture palettes, garments and poses leave the stored keeper profile unchanged")
	print("REFERENCE CHARACTER SHOWCASE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _build_stage() -> void:
	var surroundings := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("343a36")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("c4d0d3")
	atmosphere.ambient_light_energy = 0.20
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	surroundings.environment = atmosphere
	add_child(surroundings)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32, -32, 0)
	key.light_color = Color("fff5e7")
	key.light_energy = 0.47
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 48, 0)
	fill.light_color = Color("c4dcf0")
	fill.light_energy = 0.10
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 155, 0)
	rim.light_color = Color("f0c19a")
	rim.light_energy = 0.24
	add_child(rim)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = maxf(1.36, 1.85 / get_viewport().get_visible_rect().size.aspect())
	add_child(_camera)
	_camera.position = Vector3(0, 0.55, 4)
	_camera.look_at(Vector3(0, 0.55, 0))
	_camera.current = true
	get_viewport().msaa_3d = Viewport.MSAA_2X
	var floor_builder := MeshBuilder.new()
	floor_builder.add_box(Vector3(-3, -0.055, -3), Vector3(6, 0.05, 6), Color("4d5148"))
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = floor_builder.commit()
	floor_mesh.material_override = _material
	add_child(floor_mesh)


func _build_characters() -> void:
	var ordinary := CharacterAppearance.new()
	ordinary.body_type = 0
	ordinary.hair_style = 0
	ordinary.skin = Color("c6a27b")
	ordinary.hair = Color("614127")
	ordinary.top = Color("ddd7bd")
	ordinary.trousers = Color("586044")
	ordinary.boots = Color("67452f")
	var waiter: CharacterAppearance = ordinary.clone()
	# Body identity is identical; only the waistcoat/cap dye differs. White
	# undersleeves and independent apron remain the production garment palette.
	waiter.top = Color("853c42")
	waiter.family = PawnMesh.Look.STAFF
	var looks: Array[CharacterAppearance] = [ordinary, waiter]
	for i in range(2):
		var before: Dictionary = looks[i].to_save()
		var explicit_kit: Dictionary = {} if i == 0 else WAITER_KIT.duplicate()
		if i == 1:
			# A real waiter receives the red role cap. Explicit garment IDs keep
			# the local burgundy waistcoat dye while retaining its ordinary cut.
			explicit_kit.erase("head")
		var rig: PawnMesh.Rig = PawnMesh.build_appearance(looks[i], _material, explicit_kit, &"" if i == 0 else &"waiter")
		add_child(rig.root)
		rig.root.position = POSITIONS[i]
		_rigs.append(rig)
		_validate_rest(rig, "ordinary keeper" if i == 0 else "waiter")
		_report_proportions(rig, "keeper" if i == 0 else "waiter", i == 1)
		check(looks[i].to_save() == before, "building %s does not mutate its fixture appearance" % ["keeper" if i == 0 else "waiter"])
	_set_pose("rest")


func _validate_rest(rig: PawnMesh.Rig, subject: String) -> void:
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var rig_ok: bool = rig.body.mesh.get_surface_count() == 1 and rig.skeleton.get_bone_count() == 6 and rig.root.find_children("*", "MeshInstance3D", true, false).size() == 1
	for bone in range(rig.skeleton.get_bone_count()):
		rig_ok = rig_ok and rig.skeleton.get_bone_rest(bone).basis.get_scale().is_equal_approx(Vector3.ONE)
	check(rig_ok, "%s retains one production surface and six unit-scale bones" % subject)
	var floor_y: float = INF
	var finite := true
	for vertex in vertices:
		floor_y = minf(floor_y, vertex.y)
		finite = finite and vertex.is_finite() and vertex.y >= -0.001 and vertex.y < 1.6 and absf(vertex.x) < 0.5 and absf(vertex.z) < 0.5
	check(finite and is_zero_approx(floor_y), "%s has finite walking bounds and exact standing floor contact" % subject)
	var normals_ok: bool = normals.size() == vertices.size()
	for normal in normals:
		normals_ok = normals_ok and normal.is_finite() and absf(normal.length() - 1.0) < 0.001
	check(normals_ok, "%s keeps finite unit normals after body proportions are baked into geometry" % subject)
	check(rig.carry_anchor.position.is_equal_approx(Vector3(0, PawnMesh.LEG_H + PawnMesh.TORSO_H * 0.55, PawnMesh.BODY_D * 0.5 + 0.12)), "%s keeps the production carry anchor" % subject)
	check(vertices.size() / 3 < 1400, "%s stays below 1400 triangles (%d measured)" % [subject, vertices.size() / 3])


func _report_proportions(rig: PawnMesh.Rig, subject: String, apron: bool) -> void:
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var bottom: float = INF
	var top: float = -INF
	var head_bottom: float = INF
	var head_top: float = -INF
	var waist_low: float = INF
	var waist_high: float = -INF
	var waist_vertices: int = 0
	for i in range(vertices.size()):
		var vertex: Vector3 = vertices[i]
		bottom = minf(bottom, vertex.y)
		top = maxf(top, vertex.y)
		if bones[i * 4] == 1:
			head_bottom = minf(head_bottom, vertex.y)
			head_top = maxf(head_top, vertex.y)
		if bones[i * 4] == 0:
			var waist_vertex: bool = _colour_matches(colours[i], KeeperWardrobeArt.LINEN.darkened(0.10)) and vertex.z < 0 if apron else _colour_matches(colours[i], KeeperWardrobeArt.BRASS)
			if waist_vertex:
				waist_vertices += 1
				waist_low = minf(waist_low, vertex.y)
				waist_high = maxf(waist_high, vertex.y)
	var measured: bool = waist_vertices > 0 and is_finite(waist_low) and is_finite(waist_high)
	check(measured, "%s exposes measurable %s geometry (%d vertices)" % [subject, "rear apron waistband" if apron else "belt buckle", waist_vertices])
	if not measured:
		_report_missing_waist_colour(arrays, subject, apron)
		print("REFERENCE PROPORTIONS: %s triangles=%d visual_height=%.4f head_part_height=%.4f waist_y=unavailable waist_ratio=unavailable" % [subject, vertices.size() / 3, top - bottom, head_top - head_bottom])
		return
	var waist: float = (waist_low + waist_high) * 0.5
	print("REFERENCE PROPORTIONS: %s triangles=%d visual_height=%.4f head_part_height=%.4f waist_y=%.4f waist_ratio=%.3f (head part includes neck/hair/headwear; ratio uses full visual height)" % [subject, vertices.size() / 3, top - bottom, head_top - head_bottom, waist, (waist - bottom) / (top - bottom)])


func _colour_matches(actual: Color, expected: Color) -> bool:
	# Measured ArrayMesh RGBA8 packing truncates fractional channels: darkened
	# linen's red .77999997 became .77647060 (198.9 -> 198/255), an error of
	# .00352937. Accept at most one encoded colour step plus float epsilon;
	# Color.is_equal_approx's float-only tolerance cannot identify this stream.
	# The rear-Z filter still excludes the same-colour front apron hem.
	var tolerance: float = COLOUR_QUANTIZATION_TOLERANCE
	return absf(actual.r - expected.r) <= tolerance and absf(actual.g - expected.g) <= tolerance and absf(actual.b - expected.b) <= tolerance and absf(actual.a - expected.a) <= tolerance


func _report_missing_waist_colour(arrays: Array, subject: String, apron: bool) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var expected: Color = KeeperWardrobeArt.LINEN.darkened(0.10) if apron else KeeperWardrobeArt.BRASS
	var nearest := Color()
	var nearest_vertex := Vector3.ZERO
	var nearest_distance: float = INF
	var candidates: int = 0
	for i in range(vertices.size()):
		if bones[i * 4] != 0 or (apron and vertices[i].z >= 0):
			continue
		candidates += 1
		var actual: Color = colours[i]
		var distance: float = maxf(maxf(absf(actual.r - expected.r), absf(actual.g - expected.g)), maxf(absf(actual.b - expected.b), absf(actual.a - expected.a)))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = actual
			nearest_vertex = vertices[i]
	print("WAIST COLOUR DETAIL: %s candidates=%d nearest_vertex=%s expected_rgba=(%.8f,%.8f,%.8f,%.8f) actual_rgba=(%.8f,%.8f,%.8f,%.8f) channel_errors=(%.8f,%.8f,%.8f,%.8f) max_error=%.8f current_tolerance=%.8f" % [subject, candidates, nearest_vertex, expected.r, expected.g, expected.b, expected.a, nearest.r, nearest.g, nearest.b, nearest.a, absf(nearest.r - expected.r), absf(nearest.g - expected.g), absf(nearest.b - expected.b), absf(nearest.a - expected.a), nearest_distance, COLOUR_QUANTIZATION_TOLERANCE])


func _build_labels() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_title = Label.new()
	_title.position = Vector2(28, 20)
	_title.add_theme_font_size_override("font_size", 27)
	_title.add_theme_color_override("font_color", Color("eee0bc"))
	overlay.add_child(_title)
	_caption = Label.new()
	_caption.position = Vector2(30, 57)
	_caption.add_theme_font_size_override("font_size", 16)
	_caption.add_theme_color_override("font_color", Color("bac1b8"))
	overlay.add_child(_caption)
	for i in range(2):
		var label := Label.new()
		label.text = "Ordinary keeper" if i == 0 else "Waiter staff uniform · same body"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(400, 28)
		label.position = _camera.unproject_position(POSITIONS[i] + Vector3(0, -0.072, 0)) - Vector2(200, 0)
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color("e0d6bf"))
		overlay.add_child(label)
		_labels.append(label)


func _build_tray() -> void:
	_tray = Node3D.new()
	_tray.name = "PoseFixtureTray"
	_rigs[1].carry_anchor.add_child(_tray)
	var tray_builder := MeshBuilder.new()
	tray_builder.add_box(Vector3(-0.20, -0.012, -0.11), Vector3(0.40, 0.024, 0.27), Color("67452f"))
	var tray_mesh := MeshInstance3D.new()
	tray_mesh.mesh = tray_builder.commit()
	tray_mesh.material_override = _material
	_tray.add_child(tray_mesh)
	var mugs := ItemMeshLibrary.new()
	for side in [-1.0, 1.0]:
		var mug := MeshInstance3D.new()
		mug.mesh = mugs.mesh_for(ItemCatalog.get_def(&"beer"))
		mug.material_override = TavernMaterials.shared()
		mug.scale = Vector3.ONE * 0.65
		mug.position = Vector3(side * 0.095, 0.012, 0.035)
		mug.rotation.y = 0 if side > 0 else PI
		_tray.add_child(mug)
	check(_tray.get_parent() == _rigs[1].carry_anchor and _tray.get_child_count() == 3, "tray fixture carries two real in-game beer meshes on the established anchor")
	print("NOTE: Tray is an original showcase-only pose fixture; beer mugs reuse ItemMeshLibrary and TavernMaterials.shared.")


func _set_pose(kind: String) -> void:
	for i in range(_rigs.size()):
		var rig: PawnMesh.Rig = _rigs[i]
		for bone in range(6):
			rig.joints[bone].position = rig.skeleton.get_bone_rest(bone).origin
			rig.joints[bone].rotation = Vector3.ZERO
		rig.root.position = POSITIONS[i]
		rig.arm_l.rotation.z = -0.03
		rig.arm_r.rotation.z = 0.03
		if kind in ["carry", "walk"] and i == 1:
			rig.arm_l.rotation.x = -1.15
			rig.arm_r.rotation.x = -1.15
		if kind == "walk":
			var swing: float = Pawn.SWING
			rig.leg_l.rotation.x = swing
			rig.leg_r.rotation.x = -swing
			rig.torso.position.y += 0.02
			if i == 0:
				rig.arm_l.rotation.x = -swing * 0.7
				rig.arm_r.rotation.x = swing * 0.7
		elif kind == "seated":
			# The rigid-leg preview is deliberately labelled, rather than inventing
			# a bent knee the production six-bone rig cannot currently express.
			rig.root.position.y = -0.10
			rig.leg_l.rotation.x = -0.55
			rig.leg_r.rotation.x = -0.55
			rig.arm_l.rotation.x = -0.35
			rig.arm_r.rotation.x = -0.35
		rig.sync_pose()
	if _tray != null:
		_tray.visible = kind in ["carry", "walk"]


func _build_clearance_chairs() -> void:
	# Simple original fixture stools show the hip/apron clearance without
	# implying that NPCs already have a gameplay seated skeletal animation.
	for anchor in POSITIONS:
		var builder := MeshBuilder.new()
		builder.add_box(Vector3(-0.17, 0.268, -0.15), Vector3(0.34, 0.032, 0.31), Color("67452f"))
		for x in [-0.135, 0.135]:
			for z in [-0.12, 0.12]:
				builder.add_box(Vector3(x - 0.018, 0, z - 0.018), Vector3(0.036, 0.268, 0.036), Color("493327"))
		var stool := MeshInstance3D.new()
		stool.mesh = builder.commit()
		stool.material_override = _material
		var holder := Node3D.new()
		holder.position = anchor
		holder.add_child(stool)
		add_child(holder)
		_chairs.append(holder)


func _capture(label: String, title: String, angle: float) -> void:
	for rig in _rigs:
		rig.root.rotation.y = angle
	for chair in _chairs:
		chair.rotation.y = angle
	_title.text = "Reference character art · %s" % title
	_caption.text = "Production shared mesh · local cream / burgundy / olive / brown palette · unchanged keeper profile"
	if label.begins_with("seated"):
		_caption.text = "Static rigid-leg clearance diagnostic · current rig has no knees or gameplay sitting animation"
	await _frames(3)
	for i in range(_rigs.size()):
		_validate_pose(_rigs[i], "%s %s" % [label, "keeper" if i == 0 else "waiter"])
	await RenderingServer.frame_post_draw
	var path: String = "%s_%s.png" % [_prefix, label]
	var pixels: Image = get_viewport().get_texture().get_image()
	var result: int = pixels.save_png(path)
	check(result == OK, "CAPTURE %s size=%s draws=%d primitives=%d" % [path, pixels.get_size(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _validate_pose(rig: PawnMesh.Rig, subject: String) -> void:
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var finite := true
	var inside := true
	var view: Rect2 = get_viewport().get_visible_rect().grow(-8)
	for i in range(vertices.size()):
		var bone: int = bones[i * 4]
		var relative: Vector3 = rig.skeleton.get_bone_rest(bone).affine_inverse() * vertices[i]
		var posed: Vector3 = rig.joints[bone].transform * relative
		finite = finite and posed.is_finite() and absf(posed.x) < 1.0 and absf(posed.z) < 1.0 and posed.y > -0.6 and posed.y < 1.6
		inside = inside and view.has_point(_camera.unproject_position(rig.root.global_transform * posed))
	check(finite, "%s has finite geometry through the posed skeleton" % subject)
	check(inside, "%s remains fully visible in the actual screenshot viewport" % subject)


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame
