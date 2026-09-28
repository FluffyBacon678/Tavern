class_name ForestBackground
extends Node2D

## Live procedural forest, ported from ForestFirewallpaper and used as the main
## menu backdrop.
##
## Two layers:
##   * Ground -- baked once into a single texture. Grass, flowers and clutter are
##     blitted in from the ground atlas with Image.blend_rect(), which runs in
##     engine code, so ~20k cells bake in a fraction of a second. It never needs
##     redrawing, so it costs one sprite draw per frame.
##   * Trees -- one MultiMesh, instances ordered back-to-front so nearer trees
##     overlap the ones behind. A vertex shader sways each canopy on its own
##     phase, so thousands of trees animate in a single draw call.
##
## The whole thing is generated larger than the screen and drifts slowly, which
## is what keeps a still menu feeling alive.
##
## This is deliberately more than menu decoration: the terrain grid, atlases and
## instanced renderer are the same pieces the tavern world map will need.

const TREE_SWAY_SHADER := preload("res://src/world/forest/tree_sway.gdshader")

## Base ground colour beneath the cover -- a mossy forest floor rather than bare
## brown, so gaps between tufts still read as woodland.
const COLOR_GROUND := Color("2f3d1e")
const COLOR_DIRT_PATH := Color("5c4a2e")
const COLOR_WATER_DEEP := Color("2a5e96")
const COLOR_WATER_SHALLOW := Color("5aa6c8")
## Water under overhanging trees picks up a green cast from the canopy.
const COLOR_WATER_REFLECT := Color("2f6e72")

## Mature tree height as a multiple of one grid cell.
const TREE_HEIGHT_CELLS: float = 3.0
## Ceiling on baked ground pixels. A large world_scale at 4K would otherwise
## allocate hundreds of megabytes; past this the drift range shrinks instead.
const MAX_GROUND_PIXELS: int = 12_000_000

signal generation_finished

@export var config: ForestConfig

var grid: TerrainGrid
var world_size: Vector2i = Vector2i.ZERO

var _tree_atlas: TreeAtlas
var _ground_atlas: GroundAtlas
var _ground_sprite: Sprite2D
var _trees: MultiMeshInstance2D
var _rng := RandomNumberGenerator.new()

var _drift_time: float = 0.0
var _drift_range: Vector2 = Vector2.ZERO
var _sway_amplitude_mesh: float = 0.0
var _resize_timer: Timer

## When false the forest still renders, it just stops moving -- the drift and
## the canopy sway are the only ongoing cost once the world is baked, and they
## are what drains a phone battery sitting on the title screen.
var animated: bool = true:
	set = set_animated


func _ready() -> void:
	if config == null:
		config = ForestConfig.new()
	_build_nodes()

	# Regenerating mid-drag would rebuild the whole world on every pixel of a
	# window resize, so coalesce a burst of resizes into one rebuild.
	_resize_timer = Timer.new()
	_resize_timer.wait_time = 0.25
	_resize_timer.one_shot = true
	_resize_timer.timeout.connect(func() -> void: regenerate())
	add_child(_resize_timer)

	regenerate()
	get_viewport().size_changed.connect(_on_viewport_resized)


func set_animated(value: bool) -> void:
	animated = value
	_apply_animation_state()


func _apply_animation_state() -> void:
	set_process(animated)
	if _trees == null or _trees.material == null:
		return
	var mat := _trees.material as ShaderMaterial
	mat.set_shader_parameter("sway_amplitude", _sway_amplitude_mesh if animated else 0.0)


func _build_nodes() -> void:
	_ground_sprite = Sprite2D.new()
	_ground_sprite.centered = false
	_ground_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_ground_sprite)

	_trees = MultiMeshInstance2D.new()
	_trees.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = TREE_SWAY_SHADER
	_trees.material = mat
	add_child(_trees)


## Throw the world away and grow a new one. Safe to call at runtime.
func regenerate(new_seed: int = -1) -> void:
	var world_seed: int = new_seed if new_seed >= 0 else int(Time.get_unix_time_from_system() * 1000.0) % 1_000_000
	_rng.seed = world_seed

	var cell: int = config.cell_size
	var view: Vector2 = get_viewport_rect().size
	var scale_factor: float = config.world_scale

	# Clamp the world area before it can allocate an unreasonable ground image.
	var want: float = view.x * scale_factor * view.y * scale_factor
	if want > float(MAX_GROUND_PIXELS):
		scale_factor *= sqrt(float(MAX_GROUND_PIXELS) / want)

	var cols: int = int(ceil(view.x * scale_factor / float(cell))) + 1
	var rows: int = int(ceil(view.y * scale_factor / float(cell))) + 1
	world_size = Vector2i(cols * cell, rows * cell)
	_drift_range = Vector2(
		maxf(0.0, float(world_size.x) - view.x),
		maxf(0.0, float(world_size.y) - view.y)
	)

	_tree_atlas = TreeAtlas.new()
	_tree_atlas.build(_rng)
	_ground_atlas = GroundAtlas.new()
	_ground_atlas.build(_rng, cell)

	grid = TerrainGrid.new()
	grid.generate(cols, rows, world_seed, config, _rng, _ground_atlas)

	_bake_ground(cell)
	_build_trees(cell)

	generation_finished.emit()


## Flatten the grid into one ground texture. Called once per world.
func _bake_ground(cell: int) -> void:
	var img := Image.create_empty(world_size.x, world_size.y, false, Image.FORMAT_RGBA8)
	img.fill(COLOR_GROUND)

	var tile_images: Array[Image] = _ground_atlas.tile_images
	var tile_rect := Rect2i(0, 0, cell, cell)

	for y in range(grid.rows):
		for x in range(grid.cols):
			var i: int = y * grid.cols + x
			var px: int = x * cell
			var py: int = y * cell
			var state: int = grid.cells[i]

			match state:
				TerrainGrid.Cell.WATER:
					var flags: int = grid.water_flags[i]
					var water: Color = COLOR_WATER_DEEP
					if flags & TerrainGrid.FLAG_SHORELINE:
						water = COLOR_WATER_REFLECT
					elif _touches_land(x, y):
						water = COLOR_WATER_SHALLOW
					img.fill_rect(Rect2i(px, py, cell, cell), water)

				TerrainGrid.Cell.DIRT:
					if grid.water_flags[i] & TerrainGrid.FLAG_PATH:
						img.fill_rect(Rect2i(px, py, cell, cell), COLOR_DIRT_PATH)

				TerrainGrid.Cell.ROCK:
					_blit_cover(img, tile_images, GroundAtlas.BOULDER, px, py, i, tile_rect)

				_:
					# Grass, and the ground beneath every tree.
					_blit_cover(img, tile_images, int(grid.grass_variant[i]), px, py, i, tile_rect)

	_ground_sprite.texture = ImageTexture.create_from_image(img)


func _blit_cover(img: Image, tile_images: Array[Image], variant: int, px: int, py: int, i: int, tile_rect: Rect2i) -> void:
	if variant < 0 or variant >= tile_images.size():
		return
	# Jitter breaks the lattice so ground cover does not read as a visible grid.
	var j: Vector2 = grid.jitter_offset(i)
	img.blend_rect(tile_images[variant], tile_rect, Vector2i(px + int(j.x), py + int(j.y)))


func _touches_land(x: int, y: int) -> bool:
	for d in TerrainGrid.NEIGHBOURS:
		if grid.cell_at(x + d.x, y + d.y) != TerrainGrid.Cell.WATER:
			return true
	return false


## Build the tree MultiMesh. Instances are emitted in ascending Y so the
## MultiMesh renders them back-to-front and nearer trees overlap correctly.
func _build_trees(cell: int) -> void:
	var tree_cells: PackedInt32Array = PackedInt32Array()
	for i in range(grid.cells.size()):
		if grid.cells[i] == TerrainGrid.Cell.TREE:
			tree_cells.append(i)
	# Index order is already row-major, i.e. ascending Y, so no sort is needed.

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _make_tree_quad()
	mm.instance_count = tree_cells.size()

	var mature_h: float = float(cell) * TREE_HEIGHT_CELLS
	var typical_scale: float = mature_h / float(TreeAtlas.TILE_H)

	for n in range(tree_cells.size()):
		var i: int = tree_cells[n]
		var x: int = i % grid.cols
		var y: int = i / grid.cols
		var j: Vector2 = grid.jitter_offset(i)

		# Anchor the trunk base at the bottom-centre of its cell.
		var pos := Vector2(float(x) * cell + cell * 0.5 + j.x, float(y + 1) * cell + j.y)
		var growth: float = grid.tree_growth[i]
		var s: float = typical_scale * growth

		mm.set_instance_transform_2d(n, Transform2D(0.0, Vector2(s, s), 0.0, pos))
		# Both channels normalised to 0..1 -- see the note in tree_sway.gdshader.
		var uv_offset: float = float(grid.tree_variant[i]) / float(TreeAtlas.VARIANT_COUNT)
		mm.set_instance_custom_data(n, Color(uv_offset, _rng.randf(), 0.0, 0.0))
		# Slight per-tree brightness variation stops the canopy reading as a
		# single flat mass.
		var v: float = 0.88 + _rng.randf() * 0.24
		mm.set_instance_color(n, Color(v, v, v, 1.0))

	_trees.multimesh = mm
	_trees.texture = _tree_atlas.texture

	var mat := _trees.material as ShaderMaterial
	mat.set_shader_parameter("atlas_slices", float(TreeAtlas.VARIANT_COUNT))
	mat.set_shader_parameter("tile_height", float(TreeAtlas.TILE_H))
	mat.set_shader_parameter("sway_speed", config.sway_speed)
	# Amplitude is authored in screen pixels but applied in mesh space, so divide
	# it back out by the typical instance scale.
	_sway_amplitude_mesh = config.sway_amplitude / maxf(0.01, typical_scale)
	_apply_animation_state()


## A quad whose origin is its bottom-centre, built explicitly rather than with
## QuadMesh so the vertex winding and UV orientation are unambiguous in 2D
## (QuadMesh is authored for 3D, where +Y is up, and renders flipped here).
func _make_tree_quad() -> ArrayMesh:
	var hw: float = float(TreeAtlas.TILE_W) * 0.5
	var th: float = float(TreeAtlas.TILE_H)

	var verts := PackedVector3Array([
		Vector3(-hw, -th, 0.0),
		Vector3(hw, -th, 0.0),
		Vector3(hw, 0.0, 0.0),
		Vector3(-hw, 0.0, 0.0),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _process(delta: float) -> void:
	if _drift_range == Vector2.ZERO:
		return
	_drift_time += delta * config.drift_speed * 0.01
	# Two slow sines at different rates trace a slowly wandering path rather than
	# a loop the eye can learn.
	var t: float = _drift_time
	var ox: float = (sin(t * 0.6) * 0.5 + 0.5) * _drift_range.x
	var oy: float = (sin(t * 0.37 + 1.3) * 0.5 + 0.5) * _drift_range.y
	position = Vector2(-ox, -oy)


func _on_viewport_resized() -> void:
	# The baked ground is sized to the viewport, so a resize needs a new world --
	# but only once the player has stopped dragging.
	_resize_timer.start()
