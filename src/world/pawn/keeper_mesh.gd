class_name KeeperMesh
extends RefCounted

## The ordinary base body, authored in the same local coordinates as PawnMesh.
## Continuous contours replace stacked closed blocks. Clothing can follow these
## sections later without changing pivots, saved appearances or the six bones.
const CORNERS: Array[Vector2] = [Vector2(-0.65, -1), Vector2(-1, -0.65),
	Vector2(-1, 0.65), Vector2(-0.65, 1), Vector2(0.65, 1),
	Vector2(1, 0.65), Vector2(1, -0.65), Vector2(0.65, -1)]
const FACE_Y: Array[float] = [0.022, 0.066, 0.114, 0.151, 0.201]
const FACE_W: Array[float] = [0.060, 0.083, 0.101, 0.097, 0.086]
const FACE_FRONT: Array[float] = [0.084, 0.099, 0.104, 0.094, 0.079]
const FACE_BACK: Array[float] = [-0.058, -0.079, -0.097, -0.100, -0.090]


static func tunic(mb: MeshBuilder, height: float, cloth: Color, skin: Color, belt: Color, buckle: Color) -> void:
	# Shoulder-to-neck slope, a fuller chest, and a belted waist. Only the end
	# rings are capped; hidden faces between cloth sections are unnecessary.
	_loft(mb, [-0.026, 0.085, 0.145, 0.280, height - 0.016, height],
		[Vector2(0.156, 0.110), Vector2(0.133, 0.102), Vector2(0.139, 0.106),
		Vector2(0.173, 0.119), Vector2(0.156, 0.107), Vector2(0.066, 0.069)],
		[Vector2(0, 0), Vector2(0, 0), Vector2(0, 0.002), Vector2(0, 0.004), Vector2(0, 0), Vector2(0, 0)],
		[cloth.darkened(0.045), cloth, cloth, cloth, cloth])
	# The opening follows the chest rather than painting a collar on a flat wall.
	mb.add_quad(Vector3(-0.045, height + 0.002, 0.071), Vector3(-0.035, height - 0.016, 0.110),
		Vector3(0.035, height - 0.016, 0.110), Vector3(0.045, height + 0.002, 0.071), skin)
	mb.add_tri(Vector3(-0.035, height - 0.016, 0.110), Vector3(0, height - 0.093, 0.126),
		Vector3(0.035, height - 0.016, 0.110), skin)
	for side in [-1.0, 1.0]:
		_front_quad(mb, Vector3(side * 0.063, height + 0.003, 0.074), Vector3(side * 0.050, height - 0.016, 0.113),
			Vector3(side * 0.035, height - 0.016, 0.113), Vector3(side * 0.045, height + 0.003, 0.075), cloth.lightened(0.055))
		_front_quad(mb, Vector3(side * 0.050, height - 0.016, 0.113), Vector3(side * 0.016, height - 0.095, 0.131),
			Vector3(side * 0.004, height - 0.088, 0.130), Vector3(side * 0.035, height - 0.016, 0.114), cloth.lightened(0.04))
	# Broad, shallow folds are part of the cloth shape rather than floating trim.
	for side in [-1.0, 1.0]:
		mb.add_tri(Vector3(side * 0.115, 0.247, 0.118), Vector3(side * 0.085, 0.139, 0.110),
			Vector3(side * 0.098, 0.225, 0.123), cloth.darkened(0.065))
		mb.add_tri(Vector3(side * 0.080, 0.075, 0.109), Vector3(side * 0.120, -0.024, 0.111),
			Vector3(side * 0.068, -0.024, 0.116), cloth.lightened(0.025))
	_loft(mb, [0.079, 0.110], [Vector2(0.139, 0.110), Vector2(0.138, 0.110)],
		[Vector2.ZERO, Vector2.ZERO], [belt])
	mb.add_box(Vector3(-0.027, 0.075, 0.120), Vector3(0.054, 0.042, 0.013), buckle)
	mb.add_box(Vector3(-0.016, 0.083, 0.134), Vector3(0.032, 0.025, 0.006), belt.darkened(0.05))


static func arm(mb: MeshBuilder, height: float, sleeve: Color, cuff: Color, skin: Color, thumb_side: float) -> void:
	KeeperLimbArt.arm(mb, height, sleeve, cuff, skin, thumb_side)


static func leg(mb: MeshBuilder, height: float, trouser: Color, boot: Color) -> void:
	# Full thigh, narrower knee, then a calf/boot transition. The bottom remains
	# exactly at the old floor contact so chairs and walking keep their contract.
	_loft(mb, [-height + 0.032, -height * 0.70, -height * 0.66, -height * 0.48, -height * 0.29, 0.015],
		[Vector2(0.046, 0.049), Vector2(0.053, 0.055), Vector2(0.056, 0.058),
		Vector2(0.045, 0.046), Vector2(0.060, 0.058), Vector2(0.059, 0.061)],
		[Vector2(0, 0.008), Vector2(0, 0.004), Vector2(0, 0.003), Vector2(0, 0.010), Vector2(0, 0.003), Vector2.ZERO],
		[boot, boot.lightened(0.07), trouser.darkened(0.025), trouser, trouser])
	_loft(mb, [-height + 0.014, -height + 0.045, -height + 0.074],
		[Vector2(0.055, 0.083), Vector2(0.052, 0.078), Vector2(0.045, 0.060)],
		[Vector2(0, 0.022), Vector2(0, 0.024), Vector2(0, 0.018)], [boot, boot.lightened(0.025)])
	_loft(mb, [-height, -height + 0.016], [Vector2(0.056, 0.084), Vector2(0.055, 0.083)],
		[Vector2(0, 0.022), Vector2(0, 0.022)], [boot.darkened(0.14)])


static func head(skin: Color, hair: Color, style: int, hat: bool, hat_colour: Color, ink: Color) -> ArrayMesh:
	var mb := MeshBuilder.new()
	_loft(mb, [-0.014, 0.045], [Vector2(0.035, 0.034), Vector2(0.038, 0.037)],
		[Vector2(0, -0.002), Vector2(0, -0.002)], [skin.darkened(0.035)])
	var radii: Array[Vector2] = []
	var offsets: Array[Vector2] = []
	for i in range(FACE_Y.size()):
		radii.append(Vector2(FACE_W[i], (FACE_FRONT[i] - FACE_BACK[i]) * 0.5))
		offsets.append(Vector2(0, (FACE_FRONT[i] + FACE_BACK[i]) * 0.5))
	_loft(mb, FACE_Y, radii, offsets, [skin.darkened(0.015), skin, skin, skin])
	# Five broad nose facets give a bridge, tip and underside, rather than a spike.
	var nl := Vector3(-0.013, 0.111, 0.106)
	var nr := Vector3(0.013, 0.111, 0.106)
	var bl := Vector3(-0.011, 0.151, 0.097)
	var br := Vector3(0.011, 0.151, 0.097)
	var tip := Vector3(0, 0.118, 0.123)
	mb.add_tri(nl, tip, bl, skin.darkened(0.045), 1e-12)
	mb.add_tri(bl, tip, br, skin.lightened(0.015), 1e-12)
	mb.add_tri(br, tip, nr, skin, 1e-12)
	mb.add_tri(nl, nr, tip, skin.darkened(0.10), 1e-12)
	for side in [-1.0, 1.0]:
		var x: float = side * 0.044
		_ink(mb, [Vector2(x - 0.017, 0.139), Vector2(x - 0.012, 0.135),
			Vector2(x + 0.013, 0.136), Vector2(x + 0.018, 0.144), Vector2(x + 0.008, 0.152),
			Vector2(x - 0.009, 0.152)], Color("c6c0ad"), 0.0015)
		# Warm iris and a small glint read more naturally than a vertical ink bar.
		_ink(mb, [Vector2(x - 0.009, 0.140), Vector2(x - 0.006, 0.136), Vector2(x + 0.006, 0.136),
			Vector2(x + 0.009, 0.144), Vector2(x + 0.004, 0.151), Vector2(x - 0.006, 0.150)], Color("55432e"), 0.0023)
		_ink(mb, [Vector2(x - 0.0055, 0.139), Vector2(x + 0.0055, 0.139),
			Vector2(x + 0.0045, 0.150), Vector2(x - 0.0045, 0.150)], ink, 0.0031)
		_ink(mb, [Vector2(x - 0.004, 0.148), Vector2(x - 0.001, 0.148),
			Vector2(x - 0.003, 0.151)], Color("e8dfc9"), 0.0040)
		# Author inner-to-outer arches, then mirror and reverse their winding.
		var brow_inner: Array[Vector2] = [Vector2(-0.017, 0.164), Vector2(-0.004, 0.166),
			Vector2(-0.002, 0.171), Vector2(-0.015, 0.169)]
		var brow_outer: Array[Vector2] = [Vector2(-0.004, 0.166), Vector2(0.017, 0.161),
			Vector2(0.014, 0.167), Vector2(-0.002, 0.171)]
		for patch in [brow_inner, brow_outer]:
			var mirrored: Array[Vector2] = []
			for point in patch:
				mirrored.append(Vector2(x + point.x * side, point.y))
			if side < 0:
				mirrored.reverse()
			_ink(mb, mirrored, hair.darkened(0.10), 0.0015)
		mb.add_blob(Vector3(side * 0.101, 0.111, 0.003), Vector3(0.018, 0.027, 0.021), 2, 5, skin.darkened(0.025))
	# A closed, relaxed smile. The edge stays thin at close range and remains
	# quieter than the eyes when viewed at the management camera's distance.
	_ink(mb, [Vector2(-0.022, 0.083), Vector2(0, 0.078),
		Vector2(0, 0.081), Vector2(-0.022, 0.085)], skin.darkened(0.23), 0.0015)
	_ink(mb, [Vector2(0, 0.078), Vector2(0.022, 0.083),
		Vector2(0.022, 0.085), Vector2(0, 0.081)], skin.darkened(0.23), 0.0015)
	_ink(mb, [Vector2(-0.011, 0.076), Vector2(0.011, 0.076),
		Vector2(0, 0.078)], skin.lightened(0.035), 0.0015)
	_hair(mb, hair, style, hat)
	if hat:
		mb.add_cylinder(Vector3(0, 0.20, 0), 0.167, 0.156, 0.021, 8, hat_colour.darkened(0.12))
		PawnEquipment.cap(mb, Vector3(0, 0.20, 0), Vector3.DOWN, 0.167, 8, hat_colour.darkened(0.24))
		mb.add_cylinder(Vector3(0, 0.221, -0.006), 0.115, 0.091, 0.074, 8, hat_colour)
		mb.add_cylinder(Vector3(0, 0.222, -0.006), 0.117, 0.112, 0.024, 8, Color("493327"))
		mb.add_box(Vector3(0.072, 0.228, 0.077), Vector3(0.025, 0.018, 0.008), Color("c59c52"))
	return mb.commit()


static func _ink(mb: MeshBuilder, points: Array[Vector2], colour: Color, lift: float) -> void:
	for i in range(1, points.size() - 1):
		mb.add_tri(_face_point(points[0], lift), _face_point(points[i], lift), _face_point(points[i + 1], lift), colour, 1e-12)


static func _face_point(point: Vector2, lift: float) -> Vector3:
	for i in range(FACE_Y.size() - 1):
		if point.y <= FACE_Y[i + 1]:
			var t: float = clampf(inverse_lerp(FACE_Y[i], FACE_Y[i + 1], point.y), 0, 1)
			return Vector3(point.x, point.y, lerpf(FACE_FRONT[i], FACE_FRONT[i + 1], t) + lift)
	return Vector3(point.x, point.y, FACE_FRONT[-1] + lift)


static func _hair(mb: MeshBuilder, colour: Color, style: int, covered: bool) -> void:
	# A single crown with a shaped hairline. Broad overlapping locks flow in one
	# direction; their tips are cut, so the silhouette no longer forms three spikes.
	var lower: Array[Vector3] = []
	var middle: Array[Vector3] = []
	var upper: Array[Vector3] = []
	var hairline: Array[float] = [0.092, 0.140, 0.156, 0.184, 0.179, 0.158, 0.140, 0.095]
	var crest: float = 0.213 if covered or style == 3 else 0.230
	for i in range(8):
		var nape: bool = i in [0, 7]
		# Keep the nape shell outside the cheek-to-brow rear skull profile; a
		# shallower end briefly crossed it and exposed a horizontal scalp band.
		lower.append(Vector3(CORNERS[i].x * (0.079 if nape else 0.108), hairline[i], CORNERS[i].y * (0.091 if nape else 0.104) - 0.009))
		middle.append(Vector3(CORNERS[i].x * 0.106, 0.204 if i in [2, 3, 4, 5] else 0.196, CORNERS[i].y * 0.100 - 0.012))
		var upper_y: float = crest + [0.0, 0.003, 0.008, 0.003, 0.014, 0.013, 0.003, -0.005][i]
		# Covered hair skips the middle ring, so its rear upper edge also needs
		# clearance from the brow-height skull rather than tapering inside it.
		var upper_depth: float = 0.093 if covered and nape else (0.082 if covered else 0.061)
		upper.append(Vector3(CORNERS[i].x * (0.088 if covered else 0.063) + 0.012, upper_y,
			CORNERS[i].y * upper_depth - 0.011))
	for i in range(8):
		var j: int = (i + 1) % 8
		if covered:
			mb.add_quad(lower[i], lower[j], upper[j], upper[i], colour)
		else:
			mb.add_quad(lower[i], lower[j], middle[j], middle[i], colour.darkened(0.015) if i in [0, 1, 6, 7] else colour)
			mb.add_quad(middle[i], middle[j], upper[j], upper[i], colour.lightened(0.015) if i in [3, 4] else colour)
		mb.add_tri(Vector3(0.020, crest + 0.016, -0.002), upper[i], upper[j], colour.lightened(0.025) if i % 2 == 0 else colour)
		mb.add_tri(Vector3(0, 0.156, -0.018), lower[j], lower[i], colour.darkened(0.07))
	if style == 0 or covered:
		_lock(mb, -0.106, -0.027, 0.215, 0.179, 0.162, colour)
		_lock(mb, -0.043, 0.040, 0.223, 0.173, 0.179, colour.lightened(0.025))
		_lock(mb, 0.025, 0.096, 0.211, 0.177, 0.189, colour.darkened(0.01))
	elif style == 1:
		_lock(mb, -0.108, 0.017, 0.231, 0.154, 0.183, colour)
		_lock(mb, -0.016, 0.095, 0.225, 0.182, 0.174, colour.lightened(0.03))
	elif style == 2:
		_lock(mb, -0.102, -0.035, 0.215, 0.166, 0.196, colour)
		_lock(mb, 0.026, 0.100, 0.214, 0.195, 0.165, colour)
	if style == 2:
		mb.add_blob(Vector3(0.012, 0.129, -0.126), Vector3(0.037, 0.039, 0.029), 2, 6, colour)
		mb.add_limb(Vector3(0.012, 0.110, -0.143), Vector3(0.027, -0.020, -0.150), 0.027, 0.012, 6, colour)
		mb.add_box(Vector3(-0.017, 0.099, -0.166), Vector3(0.055, 0.011, 0.031), Color("493327"))


static func _lock(mb: MeshBuilder, left: float, right: float, top: float, left_tip: float, right_tip: float, colour: Color) -> void:
	var vertices: Array[Vector3] = [
		Vector3(left, top, 0.051), Vector3(right, top - 0.006, 0.051),
		Vector3(right, top - 0.010, 0.018), Vector3(left, top - 0.004, 0.018),
		Vector3(left + 0.018, left_tip, 0.104), Vector3(right + 0.011, right_tip, 0.103),
		Vector3(right + 0.010, right_tip + 0.011, 0.074), Vector3(left + 0.017, left_tip + 0.011, 0.075)]
	var centre := Vector3.ZERO
	for point in vertices:
		centre += point / 8.0
	for face in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [0, 3, 2, 1], [4, 5, 6, 7]]:
		var a: Vector3 = vertices[face[0]]
		var b: Vector3 = vertices[face[1]]
		var c: Vector3 = vertices[face[2]]
		var d: Vector3 = vertices[face[3]]
		if (b - a).cross(c - a).dot(centre - a) > 0:
			mb.add_quad(d, c, b, a, colour)
		else:
			mb.add_quad(a, b, c, d, colour)


static func _loft(mb: MeshBuilder, levels: Array[float], radii: Array[Vector2], offsets: Array[Vector2], colours: Array[Color]) -> void:
	for band in range(levels.size() - 1):
		for i in range(8):
			var j: int = (i + 1) % 8
			var a := _ring_point(i, band, levels, radii, offsets)
			var b := _ring_point(j, band, levels, radii, offsets)
			var c := _ring_point(j, band + 1, levels, radii, offsets)
			var d := _ring_point(i, band + 1, levels, radii, offsets)
			mb.add_quad(a, b, c, d, colours[band])
			if band == 0:
				mb.add_tri(Vector3(offsets[0].x, levels[0], offsets[0].y), b, a, colours[0].darkened(0.05))
			if band == levels.size() - 2:
				var last: int = levels.size() - 1
				mb.add_tri(Vector3(offsets[last].x, levels[last], offsets[last].y), d, c, colours[-1])


static func _ring_point(corner: int, ring: int, levels: Array[float], radii: Array[Vector2], offsets: Array[Vector2]) -> Vector3:
	return Vector3(CORNERS[corner].x * radii[ring].x + offsets[ring].x, levels[ring],
		CORNERS[corner].y * radii[ring].y + offsets[ring].y)


static func _front_quad(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	if (b - a).cross(c - a).z < 0:
		mb.add_quad(d, c, b, a, colour, 1e-12)
	else:
		mb.add_quad(a, b, c, d, colour, 1e-12)
