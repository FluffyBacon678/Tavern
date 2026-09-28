class_name SelectionMarker
extends MeshInstance3D

## A ring under a person, or a frame round a building's footprint, so the
## player can see which thing the inspector or the hover card is talking about.
##
## Without it, clicking one of five identical figures in a busy room and reading
## "Hilda Fairbrook, baking" leaves the question of *which* figure is Hilda.
##
## Drawn unshaded and double-sided: it has to read in shadow as well as in sun,
## and double-siding sidesteps the clockwise-winding trap that has already
## swallowed one procedural mesh in this project.

const RING_RADIUS: float = 0.42
const RING_WIDTH: float = 0.07
const RING_SEGMENTS: int = 28
const FRAME_WIDTH: float = 0.06
## Clear of the floor slab (0.06 tall) and of the tile cursor (0.04).
const LIFT: float = 0.09

var _pawn: Pawn = null
## Tracked separately from `_pawn`: once the pawn is freed, `_pawn != null` is
## false, and the ring would have stayed where they last stood instead of going.
var _following: bool = false
var _ring: Mesh
var _material := StandardMaterial3D.new()


func _init() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = false
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring = _build_ring()
	visible = false


func set_colour(colour: Color) -> void:
	_material.albedo_color = colour


func follow_pawn(pawn: Pawn) -> void:
	_pawn = pawn
	_following = true
	mesh = _ring
	visible = is_instance_valid(pawn)
	_track()


## A frame round a rectangle of tiles, at a given height.
func frame_tiles(tiles: Array, height: float) -> void:
	_pawn = null
	_following = false
	if tiles.is_empty():
		clear()
		return
	var lo: Vector2i = tiles[0]
	var hi: Vector2i = tiles[0]
	for t in tiles:
		lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
		hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
	var tile_size: float = TerrainMeshBuilder.TILE
	var x0: float = float(lo.x) * tile_size + 0.03
	var z0: float = float(lo.y) * tile_size + 0.03
	var x1: float = float(hi.x + 1) * tile_size - 0.03
	var z1: float = float(hi.y + 1) * tile_size - 0.03
	var w: float = FRAME_WIDTH
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, x0, z0, x1, z0 + w)
	_quad(st, x0, z1 - w, x1, z1)
	_quad(st, x0, z0 + w, x0 + w, z1 - w)
	_quad(st, x1 - w, z0 + w, x1, z1 - w)
	mesh = st.commit()
	position = Vector3(0.0, height + LIFT, 0.0)
	visible = true


func clear() -> void:
	_pawn = null
	_following = false
	visible = false


func _process(_delta: float) -> void:
	if _following:
		_track()


func _track() -> void:
	if not is_instance_valid(_pawn):
		clear()
		return
	position = _pawn.global_position + Vector3(0.0, LIFT, 0.0)


func _build_ring() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: float = RING_RADIUS - RING_WIDTH
	for i in range(RING_SEGMENTS):
		var a0: float = TAU * float(i) / float(RING_SEGMENTS)
		var a1: float = TAU * float(i + 1) / float(RING_SEGMENTS)
		var o0 := Vector3(cos(a0) * RING_RADIUS, 0.0, sin(a0) * RING_RADIUS)
		var o1 := Vector3(cos(a1) * RING_RADIUS, 0.0, sin(a1) * RING_RADIUS)
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		for v in [o0, o1, i1, o0, i1, i0]:
			st.add_vertex(v)
	return st.commit()


func _quad(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float) -> void:
	for v in [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1),
			Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]:
		st.add_vertex(v)
