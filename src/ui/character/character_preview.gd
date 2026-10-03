class_name CharacterPreview
extends Control

## An isolated, original 3D fitting room. Render only when a choice, the view,
## or its size changes; it never runs the tavern or advances simulation RNG.
signal framing_changed(mode: int)

enum Framing { FULL_BODY, FACE, HANDS }

var rig: PawnMesh.Rig
var redraw_count: int = 0
var stage: Node3D
var viewport: SubViewport
var camera: Camera3D
var framing: Framing = Framing.FULL_BODY
var _picture: TextureRect
var _material: StandardMaterial3D
var _angle: float = 0.12
var _dragging: bool = false
var _short_sleeves: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(220, 220)
	viewport = SubViewport.new()
	viewport.name = "FittingRoom"
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	_picture = TextureRect.new()
	_picture.texture = viewport.get_texture()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_room()
	resized.connect(_resize_view)
	visibility_changed.connect(_request_draw)
	_resize_view()


func set_character(appearance: CharacterAppearance, equipped: Dictionary = {}) -> void:
	if viewport == null:
		return
	if rig != null and is_instance_valid(rig.root):
		rig.root.get_parent().remove_child(rig.root)
		rig.root.queue_free()
	rig = PawnMesh.build_appearance(appearance, _material, equipped)
	_short_sleeves = equipped.get("body", "") == "short_sleeve_shirt"
	stage.add_child(rig.root)
	rig.root.rotation.y = _angle
	# A static, slightly asymmetric keeper stance keeps the cuffs and fingers
	# clear of the tunic. Previewing an NPC preset retains its authored rest pose.
	if appearance.family < 0:
		rig.arm_l.rotation.z = -0.03
		rig.arm_r.rotation.z = 0.05
		rig.arm_l.rotation.x = -0.04
		rig.arm_r.rotation.x = -0.015
	rig.sync_pose()
	_update_camera()
	_request_draw()


func rotate_step(amount: float) -> void:
	_angle += amount
	if rig != null:
		rig.root.rotation.y = _angle
	_request_draw()


func set_framing(mode: int) -> void:
	var next: Framing = Framing.FULL_BODY
	match mode:
		Framing.FACE: next = Framing.FACE
		Framing.HANDS: next = Framing.HANDS
	if framing == next:
		return
	framing = next
	_update_camera()
	_request_draw()
	framing_changed.emit(framing)


func get_framing() -> Framing:
	return framing


func _resize_view() -> void:
	if viewport == null:
		return
	# Keep face details sharp on wide desktop layouts. This is rendered only on
	# changes, and both its longest edge and total pixel count remain bounded.
	var factor: float = minf(1.0, 1280.0 / maxf(1.0, maxf(size.x, size.y)))
	factor = minf(factor, sqrt(921600.0 / maxf(1.0, size.x * size.y)))
	viewport.size = Vector2i(maxi(32, int(size.x * factor)), maxi(32, int(size.y * factor)))
	_update_camera()
	_request_draw()


func _update_camera() -> void:
	if camera == null or viewport == null:
		return
	var aspect: float = float(viewport.size.x) / float(maxi(1, viewport.size.y))
	var target := Vector3(0, 0.535, 0)
	var vertical_span: float = 1.18
	var horizontal_span: float = 1.05
	var offset := Vector3(0.65, 0.25, 3.1)
	# A tall cook's hat is still part of the character. Keep the usual close-up
	# for bare heads and extend its top only when actual head geometry needs it.
	var extra_height: float = maxf(0.0, _head_top() - 1.075)
	target.y += extra_height * 0.5
	vertical_span += extra_height
	if framing == Framing.FACE:
		target = Vector3(0, 0.885 + extra_height * 0.5, 0)
		vertical_span = 0.43 + extra_height
		horizontal_span = 0.47
		offset = Vector3(0.52, 0.055, 3.1)
	elif framing == Framing.HANDS:
		target = Vector3(0, 0.55 if _short_sleeves else 0.46, 0)
		vertical_span = 0.42 if _short_sleeves else 0.39
		horizontal_span = 0.62
		offset = Vector3(0.45, 0.09, 3.1)
	# Keep a useful vertical portrait, then widen only when a narrow panel would
	# crop its sides. Recompute after containers settle on every window resize.
	camera.size = maxf(vertical_span, horizontal_span / aspect)
	camera.position = target + offset
	camera.look_at(target)


func _head_top() -> float:
	if rig == null or rig.body == null:
		return 0.0
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var top: float = 0.0
	for i in range(vertices.size()):
		if bones[i * 4] == 1:
			top = maxf(top, vertices[i].y)
	return top


func _request_draw() -> void:
	if viewport != null and is_visible_in_tree():
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		redraw_count += 1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		rotate_step(event.relative.x * 0.012)
		accept_event()
	elif event is InputEventScreenDrag:
		rotate_step(event.relative.x * 0.012)
		accept_event()


func _build_room() -> void:
	stage = Node3D.new()
	stage.name = "CharacterStage"
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("1c292d")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("c4d0d3")
	atmosphere.ambient_light_energy = 0.20
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = atmosphere
	stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff5e7")
	key.light_energy = 0.47
	key.rotation_degrees = Vector3(-32, -32, 0)
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("c4dcf0")
	fill.light_energy = 0.10
	fill.rotation_degrees = Vector3(-12, 48, 0)
	stage.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("f0c19a")
	rim.light_energy = 0.24
	rim.rotation_degrees = Vector3(-25, 155, 0)
	stage.add_child(rim)
	camera = Camera3D.new()
	camera.name = "PortraitCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	stage.add_child(camera)
	camera.current = true
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var ground := PlaneMesh.new()
	ground.size = Vector2(6, 6)
	_mesh(ground, Vector3(0, -0.075, 0), Color("283436"))
	var plinth := CylinderMesh.new()
	plinth.top_radius = 0.44
	plinth.bottom_radius = 0.47
	plinth.height = 0.065
	plinth.radial_segments = 16
	_mesh(plinth, Vector3(0, -0.0325, 0), Color("403b32"))
	for i in range(-3, 4):
		var x: float = float(i) * 0.13
		var half_length: float = sqrt(maxf(0.0, 0.43 * 0.43 - x * x))
		var board := BoxMesh.new()
		board.size = Vector3(0.122, 0.009, half_length * 2.0)
		_mesh(board, Vector3(x, -0.0045, 0), Color("78664c").darkened(float(posmod(i, 3)) * 0.035))
	# Muted blue plaster separates the cream tunic and warm face from the room.
	# Broad quiet panels leave the character as the focus; this is not a game
	# world, and none of its lanterns advance or request another render.
	_box(Vector3(5, 3.2, 0.08), Vector3(0, 1.15, -1.3), Color("273b42"))
	_box(Vector3(1.48, 2.25, 0.05), Vector3(0, 1.00, -1.24), Color("2d464f"))
	for x in [-0.78, 0.78]:
		_box(Vector3(0.07, 2.25, 0.10), Vector3(x, 1.00, -1.19), Color("313c3e"))
	_box(Vector3(1.63, 0.08, 0.10), Vector3(0, 2.09, -1.19), Color("313c3e"))
	_build_lantern(Vector3(-0.95, 0.76, -1.1))
	_build_lantern(Vector3(0.95, 0.76, -1.1))


func _build_lantern(at: Vector3) -> void:
	_box(Vector3(0.06, 0.14, 0.06), at, Color("3d372b"))
	var glow := BoxMesh.new()
	glow.size = Vector3(0.028, 0.085, 0.035)
	var glass: MeshInstance3D = _mesh(glow, at + Vector3(0, 0, 0.025), Color("9c7541"))
	var lamp_material: StandardMaterial3D = glass.material_override
	lamp_material.emission_enabled = true
	lamp_material.emission = Color("b28b52")
	lamp_material.emission_energy_multiplier = 0.16
	_box(Vector3(0.08, 0.015, 0.075), at + Vector3(0, 0.077, 0), Color("494335"))
	_box(Vector3(0.08, 0.015, 0.075), at - Vector3(0, 0.077, 0), Color("494335"))


func _box(dimensions: Vector3, at: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = dimensions
	_mesh(box, at, color)


func _mesh(shape: PrimitiveMesh, at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	instance.material_override = material
	stage.add_child(instance)
	return instance
