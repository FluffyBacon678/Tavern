extends Node

## Pictures of goods and buildings for the menus, photographed from the same
## low-poly models the world draws, so a flour sack in the stores list is the
## flour sack on the shelf, and new content gets its picture for free.
##
## Asking for a picture returns a texture straight away: a dot in the thing's
## colour. The real picture replaces it in place a frame or two later, so every
## menu showing it updates without knowing. Requests made in the same frame are
## shot together on one sheet, then given a dark outline and a soft shadow so
## they read on any panel, as inventory pictures do in RuneScape.
##
## Headless runs (the test suites) have no renderer and keep the dots.

## Pixels per picture, on a side. Menus show them at 24 to 64 points, and
## phones are 2-3x, so this is the most any of them will need.
const SIZE: int = 128
const COLUMNS: int = 8
const MAX_PER_SHEET: int = 64
## How much of its square a picture fills, leaving room for the outline.
const FILL: float = 0.90
## The camera's height and turn: a three-quarter view from the front right.
const PITCH_DEG: float = 32.0
const YAW_DEG: float = 30.0

const OUTLINE_SHADER := """
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform vec4 outline : source_color = vec4(0.09, 0.06, 0.035, 1.0);

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV);
	float near = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		near = max(near, texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px * 2.2).a);
	}
	float shadow = texture(TEXTURE, UV - vec2(-2.5, -4.0) * px).a * 0.32;
	// Picture over its outline over its shadow, in premultiplied alpha.
	vec4 under = vec4(0.0, 0.0, 0.0, shadow);
	vec4 ring = vec4(outline.rgb * near, near);
	under = ring + under * (1.0 - ring.a);
	vec3 rgb = c.rgb * c.a;
	COLOR = vec4(rgb, c.a) + under * (1.0 - c.a);
}
"""

var _textures: Dictionary = {}  ## key -> ImageTexture
var _queue: Array = []  ## [key, mesh]
var _flush_queued: bool = false
var _busy: bool = false
var _items := ItemMeshLibrary.new()
var _buildings := BuildingMeshLibrary.new()
var _headless: bool = false

var _scene_view: SubViewport
var _ink_view: SubViewport
var _camera: Camera3D
var _stage: Node3D
var _sheet: TextureRect


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"


## The picture of a kind of goods, by item id.
func item(id: StringName) -> Texture2D:
	var key := "item:%s" % id
	if _textures.has(key):
		return _textures[key]
	var def: ItemDef = ItemCatalog.get_def(id)
	if def == null:
		return _dot(key, Color("8a7a60"))
	var tex: ImageTexture = _dot(key, def.palette[0] if not def.palette.is_empty() else Color.WHITE)
	_shoot(key, _items.mesh_for(def))
	return tex


## The picture of a buildable piece.
func building(def: BuildingDef) -> Texture2D:
	var key := "building:%s" % def.id
	if _textures.has(key):
		return _textures[key]
	var tex: ImageTexture = _dot(key, def.palette[0] if not def.palette.is_empty() else Color.WHITE)
	_shoot(key, _buildings.mesh_for(def))
	return tex


## What a recipe makes: its first product, or for a catch, the first fish.
func recipe(r: Recipe) -> Texture2D:
	if not r.outputs.is_empty():
		return item(StringName(r.outputs[0]["id"]))
	if not r.pick_from.is_empty():
		var first = r.pick_from[0]
		return item(StringName(first["id"] if first is Dictionary else first))
	return _dot("recipe:%s" % r.id, Color("8a7a60"))


## A ready-made picture box for a menu row: square, `points` on a side, and
## smoothly scaled, since the canvas default is nearest-neighbour.
func rect(texture: Texture2D, points: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture
	r.custom_minimum_size = Vector2(points, points)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Shoot every good and every buildable now, so menus open with pictures.
func prewarm() -> void:
	for def in ItemCatalog.all():
		item(def.id)
	for def in BuildingCatalog.all():
		building(def)


## Whether every picture asked for so far is a real one, not a dot.
func settled() -> bool:
	return _headless or (_queue.is_empty() and not _busy)


func _dot(key: String, colour: Color) -> ImageTexture:
	# A small disc: cheap to make even for a whole catalogue in a headless run.
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(16):
		for x in range(16):
			var d: float = Vector2(x - 7.5, y - 7.5).length()
			if d < 5.5:
				img.set_pixel(x, y, colour if d < 4.5 else colour.darkened(0.5))
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


func _shoot(key: String, mesh: Mesh) -> void:
	if _headless or mesh == null:
		return
	_queue.append([key, mesh])
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_flush_queued = false
	if _busy or _queue.is_empty():
		return
	_busy = true
	while not _queue.is_empty():
		var batch: Array = _queue.slice(0, MAX_PER_SHEET)
		_queue = _queue.slice(MAX_PER_SHEET)
		await _shoot_sheet(batch)
	_busy = false


func _shoot_sheet(batch: Array) -> void:
	_ensure_studio()
	var rows: int = int(ceil(float(batch.size()) / COLUMNS))
	var sheet := Vector2i(COLUMNS * SIZE, rows * SIZE)
	_scene_view.size = sheet
	_ink_view.size = sheet
	_sheet.size = Vector2(sheet)
	# One world unit per picture square, centred on the origin.
	_camera.size = float(rows)
	var right: Vector3 = _camera.global_transform.basis.x
	var up: Vector3 = _camera.global_transform.basis.y
	var shown: Array[MeshInstance3D] = []
	for i in range(batch.size()):
		var mesh: Mesh = batch[i][1]
		var box: AABB = mesh.get_aabb()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in range(8):
			var p: Vector3 = box.get_endpoint(c)
			var flat := Vector2(p.dot(right), p.dot(up))
			lo = lo.min(flat)
			hi = hi.max(flat)
		var extent: float = maxf(maxf(hi.x - lo.x, hi.y - lo.y), 0.001)
		var fit: float = FILL / extent
		var column: int = i % COLUMNS
		var row: int = i / COLUMNS
		var cell := Vector2(column - COLUMNS * 0.5 + 0.5, rows * 0.5 - row - 0.5)
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = TavernMaterials.shared()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.scale = Vector3.ONE * fit
		m.position = right * cell.x + up * cell.y - box.get_center() * fit
		_stage.add_child(m)
		shown.append(m)
	_scene_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_ink_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	# The outline pass reads the scene pass, so give it a frame of its own.
	_ink_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img: Image = _ink_view.get_texture().get_image()
	for m in shown:
		m.queue_free()
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	for i in range(batch.size()):
		var region: Image = img.get_region(Rect2i((i % COLUMNS) * SIZE, (i / COLUMNS) * SIZE, SIZE, SIZE))
		region.generate_mipmaps()
		var tex: ImageTexture = _textures.get(batch[i][0])
		if tex != null:
			tex.set_image(region)


func _ensure_studio() -> void:
	if _scene_view != null:
		return
	_scene_view = SubViewport.new()
	_scene_view.own_world_3d = true
	_scene_view.transparent_bg = true
	_scene_view.msaa_3d = Viewport.MSAA_4X
	_scene_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_scene_view)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff1dc")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_scene_view.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.05
	key.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	_scene_view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.3
	rim.light_color = Color("c9d8ff")
	rim.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	_scene_view.add_child(rim)
	_stage = Node3D.new()
	_scene_view.add_child(_stage)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.05
	_camera.far = 200.0
	var pitch: float = deg_to_rad(PITCH_DEG)
	var yaw: float = deg_to_rad(YAW_DEG)
	var away := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_scene_view.add_child(_camera)
	_camera.look_at_from_position(away * 60.0, Vector3.ZERO)
	_camera.current = true

	_ink_view = SubViewport.new()
	_ink_view.transparent_bg = true
	_ink_view.disable_3d = true
	_ink_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_ink_view)
	_sheet = TextureRect.new()
	_sheet.texture = _scene_view.get_texture()
	_sheet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var ink := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = OUTLINE_SHADER
	ink.shader = shader
	_sheet.material = ink
	_ink_view.add_child(_sheet)
