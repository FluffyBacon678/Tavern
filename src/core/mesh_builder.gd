class_name MeshBuilder
extends RefCounted

## Accumulates flat-shaded, vertex-coloured geometry and commits it as one
## ArrayMesh.
##
## Everything in this game's 3D look is faceted: terrain tiles, tree canopies,
## rocks. That means no shared vertices and no smoothed normals -- each triangle
## carries its own three vertices and a single face normal, which is what gives
## the hard-edged, low-poly read. Sharing vertices would average the normals and
## round everything off.
##
## Colour lives in the vertex stream rather than in textures, so a whole forest
## of differently-tinted trees is still one mesh, one material, one draw call.

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
## Opt in only for props: terrain/trees keep their smaller vertex streams.
var use_textures: bool = false
var surface_style: int = 0
var texture_scale := Vector2.ONE
var _uvs := PackedVector2Array()
var _styles := PackedVector2Array()


func clear() -> void:
	_verts.clear()
	_normals.clear()
	_colors.clear()
	_uvs.clear()
	_styles.clear()


func triangle_count() -> int:
	return _verts.size() / 3


## Add a triangle. Pass the vertices counter-clockwise as seen from the side that
## should be visible; the outward face normal is derived from that winding.
##
## The vertices are then emitted in reversed order, because Godot culls by
## screen-space winding and treats *clockwise* as front-facing. Supplying the
## normal separately means lighting still uses the true outward direction, so
## this reversal only affects which side survives culling. Getting it wrong is
## quietly disastrous: a terrain surface simply stops existing when viewed from
## above, while closed shapes like tree canopies still look roughly correct.
func add_tri(a: Vector3, b: Vector3, c: Vector3, col: Color, min_normal_squared: float = 0.0000001) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	# Small authored face marks opt into a finer cutoff. Keep the established
	# threshold for terrain/props, while still rejecting truly collapsed faces.
	if n.length_squared() < min_normal_squared:
		return  # degenerate; contributes nothing but a bad normal
	n = n.normalized()
	_verts.push_back(a)
	_verts.push_back(c)
	_verts.push_back(b)
	for i in 3:
		_normals.push_back(n)
		_colors.push_back(col)
	if use_textures:
		for point in [a, c, b]:
			_uvs.push_back(_surface_uv(point, n) * texture_scale)
			_styles.push_back(Vector2(surface_style, 0.0))


## Local planar coordinates keep grain stable when an instance is moved or
## rotated. The dominant face avoids stretching texture across a box edge.
func _surface_uv(point: Vector3, normal: Vector3) -> Vector2:
	var axis: Vector3 = normal.abs()
	if axis.y >= axis.x and axis.y >= axis.z:
		return Vector2(point.x, point.z)
	if axis.z >= axis.x:
		return Vector2(point.x, -point.y)
	return Vector2(point.z, -point.y)


## Add a quad as two triangles, wound consistently with add_tri.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, min_normal_squared: float = 0.0000001) -> void:
	add_tri(a, b, c, col, min_normal_squared)
	add_tri(a, c, d, col, min_normal_squared)


## An axis-aligned box from its minimum corner. The workhorse for built
## structures: walls, table tops, counters, shelves.
##
## Face windings were each derived from the cross product rather than guessed;
## a box with one reversed face shows a hole from exactly one angle, which is a
## miserable thing to chase down later.
func add_box(origin: Vector3, size: Vector3, col: Color) -> void:
	var x0: float = origin.x
	var y0: float = origin.y
	var z0: float = origin.z
	var x1: float = origin.x + size.x
	var y1: float = origin.y + size.y
	var z1: float = origin.z + size.z

	# top (+Y) and bottom (-Y)
	add_quad(Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), col)
	add_quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), col)
	# front (+Z) and back (-Z)
	add_quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), col)
	add_quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), col)
	# right (+X) and left (-X)
	add_quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), col)
	add_quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), col)


## A box given its centre on the ground plane, which is how furniture is easier
## to reason about: "a table top 0.9 wide, 0.08 thick, at height 0.75".
func add_box_centred(centre_xz: Vector2, y: float, size: Vector3, col: Color) -> void:
	add_box(Vector3(centre_xz.x - size.x * 0.5, y, centre_xz.y - size.z * 0.5), size, col)


## A cone, used for conifer canopies. `segments` controls chunkiness -- keep it
## low, the faceting is the point.
func add_cone(base_centre: Vector3, radius: float, height: float, segments: int, col: Color, cap: bool = true) -> void:
	var apex: Vector3 = base_centre + Vector3(0.0, height, 0.0)
	var step: float = TAU / float(segments)
	for i in range(segments):
		var a0: float = float(i) * step
		var a1: float = float(i + 1) * step
		var p0: Vector3 = base_centre + Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1: Vector3 = base_centre + Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		# Wound p1-before-p0 so the side faces outward; the cap is reversed again
		# so it faces down. Both were verified by working the cross product out
		# by hand rather than by eye -- an inward normal here lights the whole
		# canopy from inside and is easy to miss.
		add_tri(p1, p0, apex, col)
		if cap:
			add_tri(base_centre, p0, p1, col)


## A prism, used for trunks and rock slabs.
func add_cylinder(base_centre: Vector3, radius_bottom: float, radius_top: float, height: float, segments: int, col: Color) -> void:
	var step: float = TAU / float(segments)
	var top_centre: Vector3 = base_centre + Vector3(0.0, height, 0.0)
	for i in range(segments):
		var a0: float = float(i) * step
		var a1: float = float(i + 1) * step
		var b0: Vector3 = base_centre + Vector3(cos(a0) * radius_bottom, 0.0, sin(a0) * radius_bottom)
		var b1: Vector3 = base_centre + Vector3(cos(a1) * radius_bottom, 0.0, sin(a1) * radius_bottom)
		var t0: Vector3 = top_centre + Vector3(cos(a0) * radius_top, 0.0, sin(a0) * radius_top)
		var t1: Vector3 = top_centre + Vector3(cos(a1) * radius_top, 0.0, sin(a1) * radius_top)
		add_quad(b0, t0, t1, b1, col)
		add_tri(top_centre, t1, t0, col)


## A squashed low-poly sphere for broadleaf canopies and boulders. Deliberately
## coarse: `rings` and `segments` in the 3-6 range give the chunky silhouette.
func add_blob(centre: Vector3, radius: Vector3, rings: int, segments: int, col: Color) -> void:
	for r in range(rings):
		var phi0: float = PI * float(r) / float(rings)
		var phi1: float = PI * float(r + 1) / float(rings)
		for s in range(segments):
			var th0: float = TAU * float(s) / float(segments)
			var th1: float = TAU * float(s + 1) / float(segments)
			var p00: Vector3 = centre + _sphere_point(phi0, th0, radius)
			var p01: Vector3 = centre + _sphere_point(phi0, th1, radius)
			var p10: Vector3 = centre + _sphere_point(phi1, th0, radius)
			var p11: Vector3 = centre + _sphere_point(phi1, th1, radius)
			# Poles collapse to a point, so emit a triangle instead of a quad.
			if r == 0:
				add_tri(p00, p11, p10, col)
			elif r == rings - 1:
				add_tri(p00, p01, p10, col)
			else:
				add_quad(p00, p01, p11, p10, col)


## A prism between two arbitrary points, for branches and anything else that is
## not axis-aligned. Builds its own basis around the segment.
func add_limb(a: Vector3, b: Vector3, r_a: float, r_b: float, segments: int, col: Color) -> void:
	var axis: Vector3 = b - a
	var length: float = axis.length()
	if length < 0.0001:
		return
	axis /= length
	# Any vector not parallel to the axis works as a seed for the basis.
	var seed_up: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var t1: Vector3 = seed_up.cross(axis).normalized()
	var t2: Vector3 = axis.cross(t1).normalized()

	var step: float = TAU / float(segments)
	for i in range(segments):
		var a0: float = float(i) * step
		var a1: float = float(i + 1) * step
		var d0: Vector3 = t1 * cos(a0) + t2 * sin(a0)
		var d1: Vector3 = t1 * cos(a1) + t2 * sin(a1)
		add_quad(a + d0 * r_a, a + d1 * r_a, b + d1 * r_b, b + d0 * r_b, col)


func _sphere_point(phi: float, theta: float, radius: Vector3) -> Vector3:
	return Vector3(
		sin(phi) * cos(theta) * radius.x,
		cos(phi) * radius.y,
		sin(phi) * sin(theta) * radius.z
	)


## Commit to an ArrayMesh. Returns null if nothing was added, so callers can
## skip creating empty MeshInstances.
func commit() -> ArrayMesh:
	if _verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	if use_textures:
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_TEX_UV2] = _styles

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
