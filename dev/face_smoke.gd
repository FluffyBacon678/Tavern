extends Node

## Sandboxed face geometry/profile/creator regression. Headless is supported.
## Optional windowed -- capture-prefix=res://.../face writes actual rendered
## production heads, skin variants and a deliberately small management sample.
## Screenshots require manual art inspection; geometry checks do not claim that
## a viewer can recognize a smile at the management camera's distance.
const FACE_NAMES: Array[String] = ["Balanced", "Soft", "Angular", "Broad"]
const EXPRESSION_NAMES: Array[String] = ["Warm smile", "Grin", "Calm", "Smirk", "Stern"]
const TRAVEL_KIT := {"head": "felt_hat", "cape": "travel_cape", "backpack": "travel_pack"}
const COLOUR_TOLERANCE: float = 1.0 / 255.0 + 0.00001
const WINDOW_SHAPES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1440, 900), Vector2i(2560, 1080)]

var failures: int = 0
var largest_triangles: int = 0
var _capture_prefix: String = ""
var _material: StandardMaterial3D
var _accepted: CharacterProfile
var _capture_root: Control
var _capture_viewports: Array[SubViewport] = []


func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("capture-prefix="):
			_capture_prefix = argument.trim_prefix("capture-prefix=")
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_check_profiles()
	_check_geometry()
	await _check_creator()
	if not _capture_prefix.is_empty():
		if DisplayServer.get_name() == "headless":
			print("NOTE: capture-prefix ignored under --headless; rendered face sheets require a windowed run.")
		else:
			await _capture_faces()
	print("FACE SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check_profiles() -> void:
	check(CharacterAppearance.VERSION == 1 and CharacterProfile.VERSION == 1, "face choices remain optional fields in version-one appearances and profiles")
	var round_trips := true
	for face in range(FACE_NAMES.size()):
		for expression in range(EXPRESSION_NAMES.size()):
			var round_trip_profile: CharacterProfile = CharacterProfile.default_owner(12345)
			round_trip_profile.appearance.face_type = face
			round_trip_profile.appearance.expression = expression
			var round_trip_data: Variant = JSON.parse_string(JSON.stringify(round_trip_profile.to_save()))
			var restored: CharacterProfile = CharacterProfile.from_save(round_trip_data, 12345)
			round_trips = round_trips and restored.to_save() == round_trip_profile.to_save()
	check(round_trips, "all twenty face/expression pairs survive profile JSON round trips without changing identity or wardrobe")
	var source := CharacterAppearance.new()
	source.face_type = 2
	source.expression = 4
	source.skin = CharacterAppearance.SKIN_COLORS[4]
	source.hair_style = 2
	var legacy: Dictionary = source.to_save()
	legacy.erase("face_type")
	legacy.erase("expression")
	var restored_legacy: CharacterAppearance = CharacterAppearance.from_save(legacy)
	var legacy_other_fields: Dictionary = restored_legacy.to_save()
	legacy_other_fields.erase("face_type")
	legacy_other_fields.erase("expression")
	check(restored_legacy.face_type == 0 and restored_legacy.expression == 0 and legacy_other_fields == legacy, "legacy appearances without either optional field receive the default face/expression and preserve all prior choices")
	var missing_with_fallback: CharacterAppearance = CharacterAppearance.from_save(legacy, source)
	check(missing_with_fallback.face_type == 2 and missing_with_fallback.expression == 4, "absent optional face fields retain an explicit fallback")
	var invalid: Array = [-1, 99, 1.5, "1", null, true, [], {}]
	var malformed_safe := true
	for value in invalid:
		var data: Dictionary = source.to_save()
		data["face_type"] = value
		data["expression"] = value
		var fallback: CharacterAppearance = CharacterAppearance.from_save(data, source)
		malformed_safe = malformed_safe and fallback.face_type == 2 and fallback.expression == 4 and fallback.skin == source.skin and fallback.hair_style == source.hair_style
	check(malformed_safe, "negative, out-of-range, fractional and malformed face choices retain their fallback without damaging unrelated appearance")
	var mixed: Dictionary = source.to_save()
	mixed["face_type"] = 3.0
	mixed["expression"] = -9
	var mixed_restored: CharacterAppearance = CharacterAppearance.from_save(mixed, source)
	check(mixed_restored.face_type == 3 and mixed_restored.expression == 4, "valid JSON numeric face choices parse independently of an invalid expression")
	var profile := CharacterProfile.default_owner(12345)
	profile.appearance = source
	var draft: CharacterProfile = profile.clone()
	draft.appearance.face_type = 1
	draft.appearance.expression = 1
	check(profile.appearance.face_type == 2 and profile.appearance.expression == 4, "cloned face choices are independent of the original person")


func _look(face: int, expression: int, skin: int = 1, body: int = 0) -> CharacterAppearance:
	var look := CharacterAppearance.new()
	look.face_type = face
	look.expression = expression
	look.skin = CharacterAppearance.SKIN_COLORS[skin]
	look.body_type = body
	look.hair_style = 2
	return look


func _check_geometry() -> void:
	seed(58137)
	var expected_random: int = randi()
	seed(58137)
	var signatures: Dictionary = {}
	var count: int = 0
	var unrelated_unchanged := true
	var baseline: Array = []
	for face in range(FACE_NAMES.size()):
		for expression in range(EXPRESSION_NAMES.size()):
			var row_contract := true
			var local_face_ok := true
			var smiles_ok := true
			var mouth_low: float = INF
			var corner_rise_low: float = INF
			for skin in range(CharacterAppearance.SKIN_COLORS.size()):
				for body in range(2):
					for equipped in [{}, TRAVEL_KIT]:
						var look: CharacterAppearance = _look(face, expression, skin, body)
						var before: Dictionary = look.to_save()
						var rig: PawnMesh.Rig = PawnMesh.build_appearance(look, _material, equipped)
						var contract: bool = _rig_contract(rig)
						row_contract = row_contract and contract and look.to_save() == before
						var measured: Dictionary = _face_geometry(rig, look)
						local_face_ok = local_face_ok and measured["bounds"] and measured["pupils"] and measured["mouth_count"] > 0
						if expression in [0, 1]:
							mouth_low = minf(mouth_low, measured["mouth_width"])
							corner_rise_low = minf(corner_rise_low, measured["corner_rise"])
							smiles_ok = smiles_ok and measured["mouth_width"] > 0.03 * PawnMesh.ORDINARY_HEAD_SCALE.x * 1.5 and measured["corner_rise"] > 0.001 * PawnMesh.ORDINARY_HEAD_SCALE.y
						if skin == 1 and body == 0 and equipped.is_empty():
							var head_signature: int = _bone_signature(rig, 1)
							signatures[head_signature] = true
							if baseline.is_empty():
								for bone in [0, 2, 3, 4, 5]:
									baseline.append(_bone_signature(rig, bone))
							else:
								var part: int = 0
								for bone in [0, 2, 3, 4, 5]:
									unrelated_unchanged = unrelated_unchanged and baseline[part] == _bone_signature(rig, bone)
									part += 1
						count += 1
						rig.root.free()
			check(row_contract, "%s / %s: both builds, five skins and bare/travel kits keep floor/carry/rig/budget/normals and saved appearance" % [FACE_NAMES[face], EXPRESSION_NAMES[expression]])
			check(local_face_ok, "%s / %s: actual head and mouth stay within facial bounds and retain eye-band pupils" % [FACE_NAMES[face], EXPRESSION_NAMES[expression]])
			if expression in [0, 1]:
				check(smiles_ok, "%s / %s: mouth exceeds historical width by 50%% and corners rise above centre (min width %.5f, rise %.5f)" % [FACE_NAMES[face], EXPRESSION_NAMES[expression], mouth_low, corner_rise_low])
	check(signatures.size() == 20, "all twenty face/expression pairs produce distinct actual head meshes (%d measured)" % signatures.size())
	check(unrelated_unchanged, "changing only face/expression leaves torso, hands, legs and clothing geometry identical")
	check(randi() == expected_random, "building every face/expression leaves the global simulation RNG stream untouched")
	print("FACE BUDGET: combinations=%d largest=%d triangles (four faces × five expressions × five skins × two builds × bare/worst hair-two travel kit)" % [count, largest_triangles])


func _rig_contract(rig: PawnMesh.Rig) -> bool:
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var count: int = vertices.size() / 3
	largest_triangles = maxi(largest_triangles, count)
	var ok: bool = rig.body.mesh.get_surface_count() == 1 and rig.skeleton.get_bone_count() == 6 and count <= 1400
	ok = ok and rig.root.find_children("*", "MeshInstance3D", true, false).size() == 1 and normals.size() == vertices.size()
	for bone in range(6):
		ok = ok and rig.skeleton.get_bone_rest(bone).basis.get_scale().is_equal_approx(Vector3.ONE)
	var floor_y: float = INF
	for vertex in vertices:
		floor_y = minf(floor_y, vertex.y)
		ok = ok and vertex.is_finite() and vertex.y >= -0.001 and vertex.y < 1.6 and absf(vertex.x) < 0.5 and absf(vertex.z) < 0.5
	for normal in normals:
		ok = ok and normal.is_finite() and absf(normal.length() - 1.0) < 0.001
	return ok and is_zero_approx(floor_y) and rig.carry_anchor.position.is_equal_approx(Vector3(0, PawnMesh.LEG_H + PawnMesh.TORSO_H * 0.55, PawnMesh.BODY_D * 0.5 + 0.12))


func _face_geometry(rig: PawnMesh.Rig, look: CharacterAppearance) -> Dictionary:
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var inverse_head: Transform3D = rig.skeleton.get_bone_rest(1).affine_inverse()
	var lip: Color = look.skin.darkened(0.25).lerp(Color("4d2c25"), 0.65)
	var mouth: Array[Vector3] = []
	var pupil_sides: Dictionary = {}
	var bounds := true
	for i in range(vertices.size()):
		if bones[i * 4] != 1:
			continue
		var local: Vector3 = inverse_head * vertices[i]
		var authored: Vector3 = local / PawnMesh.ORDINARY_HEAD_SCALE
		bounds = bounds and authored.is_finite() and absf(authored.x) < 0.20 and authored.y > -0.025 and authored.y < 0.38 and absf(authored.z) < 0.20
		if _colour_matches(colours[i], PawnMesh.VISOR) and authored.y >= 0.138 and authored.y <= 0.157 and absf(authored.x) > 0.025 and absf(authored.x) < 0.065 and authored.z > 0.075:
			pupil_sides[-1 if authored.x < 0 else 1] = true
		if _colour_matches(colours[i], lip) and authored.y >= 0.070 and authored.y <= 0.110 and authored.z > 0.060:
			mouth.append(local)
			bounds = bounds and absf(authored.x) < 0.070 and authored.z < 0.145
	var mouth_width: float = 0.0
	var corner_rise: float = -INF
	if not mouth.is_empty():
		var half_width: float = 0.0
		var low_x: float = INF
		var high_x: float = -INF
		for point in mouth:
			half_width = maxf(half_width, absf(point.x))
			low_x = minf(low_x, point.x)
			high_x = maxf(high_x, point.x)
		mouth_width = high_x - low_x
		var centre_y: float = 0.0
		var corner_y: float = 0.0
		var centre_count: int = 0
		var corner_count: int = 0
		for point in mouth:
			if absf(point.x) <= half_width * 0.25:
				centre_y += point.y
				centre_count += 1
			if absf(point.x) >= half_width * 0.75:
				corner_y += point.y
				corner_count += 1
		if centre_count > 0 and corner_count > 0:
			corner_rise = corner_y / corner_count - centre_y / centre_count
	return {"bounds": bounds, "pupils": pupil_sides.size() == 2, "mouth_count": mouth.size(), "mouth_width": mouth_width, "corner_rise": corner_rise}


func _colour_matches(actual: Color, expected: Color) -> bool:
	# Mesh colour channels truncate to RGBA8, as measured by the reference
	# harness. One encoded step accommodates packing while separating palettes.
	return absf(actual.r - expected.r) <= COLOUR_TOLERANCE and absf(actual.g - expected.g) <= COLOUR_TOLERANCE and absf(actual.b - expected.b) <= COLOUR_TOLERANCE and absf(actual.a - expected.a) <= COLOUR_TOLERANCE


func _bone_signature(rig: PawnMesh.Rig, bone: int) -> int:
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var points := PackedVector3Array()
	var paints := PackedColorArray()
	for i in range(vertices.size()):
		if bones[i * 4] == bone:
			points.append(vertices[i])
			paints.append(colours[i])
	return hash([points, paints])


func _check_creator() -> void:
	var original: CharacterProfile = CharacterProfile.default_owner(12345)
	original.appearance.face_type = 1
	original.appearance.expression = 2
	var original_before: Dictionary = original.to_save()
	var global_before: Dictionary = GameState.owner_profile.to_save()
	var save_directory: String = ProjectSettings.globalize_path(GameState.slot_path(0)).get_base_dir()
	var disk_before: PackedStringArray = DirAccess.get_files_at(save_directory)
	get_window().size = Vector2i(1280, 720)
	var creator: CharacterCreator = CharacterCreator.open(self, original, true)
	await _frames(5)
	var face_choice: OptionButton = creator.find_child("FaceType", true, false)
	var expression_choice: OptionButton = creator.find_child("Expression", true, false)
	check(face_choice != null and expression_choice != null and face_choice.item_count == 4 and expression_choice.item_count == 5, "real creator exposes all four FaceType and five Expression choices")
	if face_choice == null or expression_choice == null:
		creator.cancel_changes()
		await _frames(2)
		return
	var previous_head: int = _bone_signature(creator.preview.rig, 1)
	face_choice.select(3)
	face_choice.item_selected.emit(3)
	expression_choice.select(1)
	expression_choice.item_selected.emit(1)
	await _frames(3)
	check(creator.draft.appearance.face_type == 3 and creator.draft.appearance.expression == 1 and _bone_signature(creator.preview.rig, 1) != previous_head, "real dropdown signals change the private draft and rebuild its visible face")
	check(original.to_save() == original_before and GameState.owner_profile.to_save() == global_before, "face dropdowns leave the original person and global keeper profile unchanged")
	var scroll: ScrollContainer = creator.find_child("AppearanceScroll", true, false)
	for shape in WINDOW_SHAPES:
		get_window().size = shape
		await _frames(5)
		var actual: Vector2i = get_window().size
		print("FACE CREATOR WINDOW: requested=%s actual=%s viewport=%s" % [shape, actual, get_viewport().get_visible_rect().size])
		if actual.x < shape.x or actual.y < shape.y:
			print("SKIP: face creator shape %s clamped to %s" % [shape, actual])
			continue
		check(creator.draft.appearance.face_type == 3 and creator.draft.appearance.expression == 1 and face_choice.selected == 3 and expression_choice.selected == 1, "face/expression choices survive resize to %s" % shape)
		check(get_viewport().get_visible_rect().encloses(creator.accept_button.get_global_rect()), "face editor confirmation remains on screen at %s" % shape)
		for choice in [face_choice, expression_choice]:
			if scroll != null:
				scroll.ensure_control_visible(choice)
			await _frames(2)
			check(get_viewport().get_visible_rect().encloses(choice.get_global_rect()) and choice.get_global_rect().size.x >= 24 and choice.get_global_rect().size.y >= 24, "%s can be brought into view with a usable click target at %s" % [choice.name, shape])
		if DisplayServer.get_name() != "headless":
			creator.preview.set_framing(CharacterPreview.Framing.FACE)
			await _frames(3)
			check(_head_fits_preview(creator.preview), "Broad Grin head fits the actual Face preview at %s" % shape)
	var redraws: int = creator.preview.redraw_count
	await _frames(6)
	check(creator.preview.redraw_count == redraws, "an idle face editor does not continuously rebuild or redraw its character")
	creator.cancel_changes()
	await _frames(3)
	check(original.to_save() == original_before and GameState.owner_profile.to_save() == global_before and DirAccess.get_files_at(save_directory) == disk_before, "cancel keeps original/global faces and sandbox save files unchanged")
	creator = CharacterCreator.open(self, original, true)
	creator.accepted.connect(func(profile: CharacterProfile) -> void: _accepted = profile)
	await _frames(3)
	face_choice = creator.find_child("FaceType", true, false)
	expression_choice = creator.find_child("Expression", true, false)
	face_choice.select(2)
	face_choice.item_selected.emit(2)
	expression_choice.select(0)
	expression_choice.item_selected.emit(0)
	creator.accept_button.pressed.emit()
	await _frames(3)
	check(_accepted != null and _accepted.appearance.face_type == 2 and _accepted.appearance.expression == 0 and original.to_save() == original_before, "real confirmation emits an independent selected face/expression profile")
	if DisplayServer.get_name() == "headless":
		print("NOTE: rendered Face-preview projection requires a windowed run; creator state/layout checks still ran headless.")


func _head_fits_preview(preview: CharacterPreview) -> bool:
	var arrays: Array = preview.rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var view := Rect2(Vector2(2, 2), Vector2(preview.viewport.size) - Vector2(4, 4))
	for i in range(vertices.size()):
		if bones[i * 4] != 1:
			continue
		var local: Vector3 = preview.rig.skeleton.get_bone_rest(1).affine_inverse() * vertices[i]
		var posed: Vector3 = preview.rig.joints[1].transform * local
		if not view.has_point(preview.camera.unproject_position(preview.rig.root.global_transform * posed)):
			return false
	return true


func _capture_faces() -> void:
	var made: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_capture_prefix).get_base_dir())
	check(made == OK, "face screenshot destination can be created")
	if made != OK:
		return
	get_window().mode = Window.MODE_WINDOWED
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	get_window().size = Vector2i(1600, 1000)
	await _frames(4)
	print("FACE CAPTURE WINDOW: requested=(1600, 1000) actual=%s viewport=%s" % [get_window().size, get_viewport().get_visible_rect().size])
	var fixtures: Array[Dictionary] = []
	for face in range(4):
		for expression in range(5):
			fixtures.append({"look": _look(face, expression), "label": "%s · %s" % [FACE_NAMES[face], EXPRESSION_NAMES[expression]]})
	await _capture_sheet("faces_expressions", "Four faces · five expressions", fixtures, 4, false)
	fixtures.clear()
	for skin in range(5):
		fixtures.append({"look": _look(0, 1, skin), "label": "Grin · skin %d" % (skin + 1)})
	await _capture_sheet("grin_skin_tones", "Grin · every skin tone", fixtures, 1, false)
	fixtures.clear()
	for expression in range(5):
		fixtures.append({"look": _look(0, expression), "label": EXPRESSION_NAMES[expression]})
	await _capture_sheet("management_sample", "Expressions · small management view", fixtures, 1, true)
	print("NOTE: management_sample renders production people at a deliberately small scale; inspect readability manually. Geometry tests do not prove expression recognition.")


func _capture_sheet(label: String, title: String, fixtures: Array[Dictionary], rows: int, management: bool) -> void:
	if _capture_root != null:
		_capture_root.queue_free()
		await _frames(2)
	_capture_viewports.clear()
	_capture_root = Control.new()
	add_child(_capture_root)
	_capture_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("27332f")
	_capture_root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var heading := Label.new()
	heading.text = "Character faces · %s" % title
	heading.position = Vector2(24, 18)
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", Color("eee0bc"))
	_capture_root.add_child(heading)
	var caption := Label.new()
	caption.text = "Actual shared PawnMesh geometry · local fixture copies · no player saves changed"
	if management:
		caption.text = "Small-size sample at an elevated camera angle · manual readability review, not an automated recognition test"
	caption.position = Vector2(26, 56)
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color("bdc5bb"))
	_capture_root.add_child(caption)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	grid.position = Vector2(24, 86 if rows > 1 else (310 if management else 170))
	_capture_root.add_child(grid)
	var visible: Vector2 = get_viewport().get_visible_rect().size
	var cell_width: float = (visible.x - 88) / 5.0
	var cell_height: float = (visible.y - 110 - float(rows - 1) * 8) / rows if rows > 1 else (270.0 if management else minf(600.0, visible.y - 225.0))
	for fixture in fixtures:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.custom_minimum_size = Vector2(cell_width, cell_height)
		grid.add_child(cell)
		var name_label := Label.new()
		name_label.text = fixture["label"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.add_theme_color_override("font_color", Color("e0d6bf"))
		cell.add_child(name_label)
		var viewport_size := Vector2i(int(cell_width), int(cell_height - 28))
		var viewport: SubViewport = _face_viewport(fixture["look"], viewport_size, management, String(fixture["label"]))
		_capture_root.add_child(viewport)
		_capture_viewports.append(viewport)
		var picture := TextureRect.new()
		picture.custom_minimum_size = Vector2(viewport_size)
		picture.texture = viewport.get_texture()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		cell.add_child(picture)
	await _frames(3)
	for viewport in _capture_viewports:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await _frames(3)
	for viewport in _capture_viewports:
		_check_capture_projection(viewport, management)
	await RenderingServer.frame_post_draw
	var pixels: Image = get_viewport().get_texture().get_image()
	var destination: String = "%s_%s.png" % [_capture_prefix, label]
	var result: int = pixels.save_png(destination)
	check(result == OK, "CAPTURE %s size=%s cells=%d draws=%d primitives=%d" % [destination, pixels.get_size(), fixtures.size(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _face_viewport(look: CharacterAppearance, viewport_size: Vector2i, management: bool, subject: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var stage := Node3D.new()
	viewport.add_child(stage)
	var surroundings := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("343e38")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("c4d0d3")
	atmosphere.ambient_light_energy = 0.20
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	surroundings.environment = atmosphere
	stage.add_child(surroundings)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, -25, 0)
	key.light_color = Color("fff5e7")
	key.light_energy = 0.47
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 55, 0)
	fill.light_color = Color("c4dcf0")
	fill.light_energy = 0.13
	stage.add_child(fill)
	var rig: PawnMesh.Rig = PawnMesh.build_appearance(look, _material)
	rig.root.rotation.y = -0.10
	stage.add_child(rig.root)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 4.4 if management else maxf(0.31, 0.25 / Vector2(viewport_size).aspect())
	camera.current = true
	stage.add_child(camera)
	var target := Vector3(0, 0.53 if management else PawnMesh.LEG_H + PawnMesh.TORSO_H + 0.11 * PawnMesh.ORDINARY_HEAD_SCALE.y, 0)
	camera.position = target + (Vector3(0, 2.5, 3.5) if management else Vector3(0, 0.012, 2.5))
	# The viewport enters the tree after this function returns; look_at is
	# deferred to avoid requesting a global transform before that happens.
	camera.call_deferred("look_at", target)
	viewport.set_meta("face_subject", subject)
	viewport.set_meta("face_rig", rig)
	return viewport


func _check_capture_projection(viewport: SubViewport, management: bool) -> void:
	var rig: PawnMesh.Rig = viewport.get_meta("face_rig")
	var subject: String = viewport.get_meta("face_subject")
	var camera: Camera3D = viewport.get_camera_3d()
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var head_low := Vector2(INF, INF)
	var head_high := Vector2(-INF, -INF)
	for i in range(vertices.size()):
		var bone: int = bones[i * 4]
		if not management and bone != 1:
			continue
		var relative: Vector3 = rig.skeleton.get_bone_rest(bone).affine_inverse() * vertices[i]
		var posed: Vector3 = rig.joints[bone].transform * relative
		var pixel: Vector2 = camera.unproject_position(rig.root.global_transform * posed)
		low = low.min(pixel)
		high = high.max(pixel)
		if bone == 1:
			head_low = head_low.min(pixel)
			head_high = head_high.max(pixel)
	var bounds := Rect2(low, high - low)
	check(Rect2(Vector2(2, 2), Vector2(viewport.size) - Vector2(4, 4)).encloses(bounds), "%s %s geometry fits its actual rendered cell" % [subject, "whole person" if management else "head"])
	if management:
		print("FACE MANAGEMENT SAMPLE: %s body_pixels=%.1f head_pixels=%.1f viewport=%s" % [subject, bounds.size.y, (head_high - head_low).y, viewport.size])


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame
