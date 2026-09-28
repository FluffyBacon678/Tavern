class_name RoomOverlay
extends Node3D

## Draws the rooms the game has worked out, on a toggle.
##
## Room detection was built and then left entirely invisible: the only sign of
## it anywhere was one line in the inspector when you happened to click a piece
## of furniture standing inside one. A system that decides what a space *is* and
## never says so is indistinguishable from one that does not exist.
##
## Off by default and toggled from the bar, because it is a diagnostic view
## rather than decoration -- the same shape as the wall cutaway. When it is on
## the player is asking a question ("what counts as my kitchen?"), and when it is
## off they want to look at their tavern.
##
## Built on demand from Rooms.current(), which is itself lazy, so an overlay that
## nobody has opened costs nothing at all.

## How far above the plot plane the wash sits.
##
## Has to clear the floor pieces themselves, not just the ground: a wood floor
## slab is 0.06 tall, so the first attempt at 0.045 drew the overlay *inside*
## the boards and nothing appeared at all. Still far below anything standing on
## the floor, so furniture is not tinted.
const LIFT: float = 0.10
## Fill and border alpha. The fill is deliberately faint -- it has to name the
## room without hiding the floor the player is judging.
const FILL_ALPHA: float = 0.45
const EDGE_ALPHA: float = 0.95
const EDGE_WIDTH: float = 0.09

var _mesh: MeshInstance3D
var _labels: Node3D
var _material: StandardMaterial3D
var _following: bool = false


func _ready() -> void:
	visible = false

	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Drawn over the floor rather than fighting it for depth. The wash is a
	# readout, not a thing in the world, so it should not be shadowed or
	# z-fight with the boards underneath.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh = MeshInstance3D.new()
	_mesh.name = "Fill"
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	_labels = Node3D.new()
	_labels.name = "Labels"
	add_child(_labels)


## Show or hide, rebuilding from the current rooms on the way up.
func toggle(rooms: Rooms, floor_height: float) -> bool:
	visible = not visible
	if visible:
		rebuild(rooms, floor_height)
	return visible


## Keep the picture honest while it is open.
##
## A player who knocks a wall through with the overlay up is asking precisely
## about the result, and a cached picture of the room it used to be is worse
## than no overlay at all.
func follow(grid: BuildGrid, rooms: Rooms, floor_height: float) -> void:
	if grid == null or _following:
		return
	_following = true
	var restack := func() -> void:
		if visible:
			rebuild(rooms, floor_height)
	grid.placement_added.connect(restack.unbind(1))
	grid.placement_built.connect(restack.unbind(1))
	grid.placement_removed.connect(restack.unbind(2))


func rebuild(rooms: Rooms, floor_height: float) -> void:
	for child in _labels.get_children():
		child.queue_free()

	var mb := MeshBuilder.new()
	var y: float = floor_height + LIFT
	for room in rooms.current():
		var kind = room["kind"]
		# Lightened before it is laid down. At full saturation a warm room tint
		# over warm floorboards is the same colour twice and reads as nothing.
		var base: Color = kind.tint if kind != null else Color(0.75, 0.75, 0.75)
		var tint: Color = base.lightened(0.18)
		var tiles: Array = room["tiles"]
		var inside: Dictionary = {}
		for tile in tiles:
			inside[tile] = true

		for tile in tiles:
			_fill_tile(mb, tile, y, Color(tint.r, tint.g, tint.b, FILL_ALPHA))
			# An edge only where the room actually ends. Drawing all four sides
			# of every tile would draw a grid, which says nothing about where
			# one room stops and the next begins.
			_edge_tile(mb, tile, y, inside, Color(tint.r, tint.g, tint.b, EDGE_ALPHA))

		_add_label(room, tiles, floor_height, tint)

	_mesh.mesh = mb.commit()


func _fill_tile(mb: MeshBuilder, tile: Vector2i, y: float, col: Color) -> void:
	var x: float = float(tile.x)
	var z: float = float(tile.y)
	mb.add_quad(
		Vector3(x, y, z), Vector3(x, y, z + 1.0),
		Vector3(x + 1.0, y, z + 1.0), Vector3(x + 1.0, y, z),
		col
	)


func _edge_tile(mb: MeshBuilder, tile: Vector2i, y: float, inside: Dictionary, col: Color) -> void:
	var x: float = float(tile.x)
	var z: float = float(tile.y)
	var w: float = EDGE_WIDTH
	# Slightly higher than the fill so the border stays crisp where they meet.
	var ey: float = y + 0.004
	if not inside.has(tile + Vector2i(0, -1)):
		mb.add_quad(Vector3(x, ey, z), Vector3(x, ey, z + w), Vector3(x + 1.0, ey, z + w), Vector3(x + 1.0, ey, z), col)
	if not inside.has(tile + Vector2i(0, 1)):
		mb.add_quad(Vector3(x, ey, z + 1.0 - w), Vector3(x, ey, z + 1.0), Vector3(x + 1.0, ey, z + 1.0), Vector3(x + 1.0, ey, z + 1.0 - w), col)
	if not inside.has(tile + Vector2i(-1, 0)):
		mb.add_quad(Vector3(x, ey, z), Vector3(x, ey, z + 1.0), Vector3(x + w, ey, z + 1.0), Vector3(x + w, ey, z), col)
	if not inside.has(tile + Vector2i(1, 0)):
		mb.add_quad(Vector3(x + 1.0 - w, ey, z), Vector3(x + 1.0 - w, ey, z + 1.0), Vector3(x + 1.0, ey, z + 1.0), Vector3(x + 1.0, ey, z), col)


## The room's name, standing in the middle of it.
##
## Placed at the centre of mass and nudged to a tile that is actually in the
## room, so an L-shaped space does not caption itself out in the courtyard.
func _add_label(room: Dictionary, tiles: Array, floor_height: float, tint: Color) -> void:
	if tiles.is_empty():
		return
	var sum := Vector2.ZERO
	for tile in tiles:
		sum += Vector2(float(tile.x), float(tile.y))
	var centre: Vector2 = sum / float(tiles.size())

	var best: Vector2i = tiles[0]
	var best_distance: float = 1e20
	for tile in tiles:
		var d: float = Vector2(float(tile.x), float(tile.y)).distance_squared_to(centre)
		if d < best_distance:
			best_distance = d
			best = tile

	var kind = room["kind"]
	var label := Label3D.new()
	label.text = "%s\n%d tiles · %dg" % [
		kind.display_name if kind != null else "Unnamed room",
		tiles.size(),
		int(room["value"]),
	]
	label.font_size = 48
	label.pixel_size = 0.012
	label.modulate = tint.lightened(0.55)
	label.outline_size = 14
	label.outline_modulate = Color(0.05, 0.05, 0.05, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Drawn on top of the furniture: a caption behind an oven is no caption.
	label.no_depth_test = true
	label.position = Vector3(float(best.x) + 0.5, floor_height + 1.6, float(best.y) + 0.5)
	_labels.add_child(label)
