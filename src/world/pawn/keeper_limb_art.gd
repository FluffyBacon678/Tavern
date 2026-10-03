class_name KeeperLimbArt
extends RefCounted

## Ordinary keeper arms remain a single rigid part of the existing six-bone
## pawn. The hand is a continuous closed contour, with a shallow finger edge
## and a bent thumb instead of separate finger boxes or a pointed thumb peg.
const CORNERS: Array[Vector2] = [Vector2(-0.65, -1), Vector2(-1, -0.65),
	Vector2(-1, 0.65), Vector2(-0.65, 1), Vector2(0.65, 1),
	Vector2(1, 0.65), Vector2(1, -0.65), Vector2(0.65, -1)]
## The covered shoulder end needs six corners. Coincident front/back pairs
## give the octagonal lower section a closed transition without hidden facets.
const SHOULDER_END: Array[Vector2] = [Vector2(0, -1), Vector2(-1, -0.65),
	Vector2(-1, 0.65), Vector2(0, 1), Vector2(0, 1),
	Vector2(1, 0.65), Vector2(1, -0.65), Vector2(0, -1)]
const FINGER_EDGE: Array[float] = [0.006, 0.004, 0.005, 0.0015, 0.003,
	0.0, 0.003, 0.0025, 0.005]


static func arm(mb: MeshBuilder, height: float, sleeve: Color, cuff: Color,
		skin: Color, thumb_side: float) -> void:
	# Shorter, thinner fingertips and a narrow wrist make an open resting hand
	# rather than a bulbous mitten. The palm curves gently forward beneath the
	# forearm, so it also reads from the side when carrying or walking.
	var levels: Array[float] = [-height, -height * 0.89, -height * 0.81,
		-height * 0.72, -height * 0.62, -0.025, 0.002]
	var radii: Array[Vector2] = [Vector2(0.027, 0.018), Vector2(0.032, 0.027),
		Vector2(0.026, 0.028), Vector2(0.046, 0.047), Vector2(0.049, 0.052),
		Vector2(0.055, 0.056), Vector2(0.039, 0.043)]
	var offsets: Array[Vector2] = [Vector2(0, 0.038), Vector2(0, 0.032),
		Vector2(0, 0.022), Vector2(0, 0.015), Vector2(0, 0.010),
		Vector2(thumb_side * 0.004, 0), Vector2(thumb_side * 0.015, 0)]
	var colours: Array[Color] = [skin, skin, skin, cuff, sleeve, sleeve]
	var bottom: Array[Vector3] = []
	var tip_centre := Vector3(0, -height + 0.004, offsets[0].y)
	# Seven rings, capped only at the two exposed ends. The upper shoulder
	# narrows into its cap; the cuff stays at the established .62-.72 arm span.
	for band in range(levels.size() - 1):
		var interior := Vector3((offsets[band].x + offsets[band + 1].x) * 0.5,
			(levels[band] + levels[band + 1]) * 0.5,
			(offsets[band].y + offsets[band + 1].y) * 0.5)
		for i in range(CORNERS.size()):
			var j: int = (i + 1) % CORNERS.size()
			var a: Vector3 = _point(i, band, levels, radii, offsets, thumb_side)
			var b: Vector3 = _point(j, band, levels, radii, offsets, thumb_side)
			var c: Vector3 = _point(j, band + 1, levels, radii, offsets, thumb_side)
			var d: Vector3 = _point(i, band + 1, levels, radii, offsets, thumb_side)
			if band == 0 and i == 3:
				# The front edge has four slight finger curves. Subdividing only
				# this band gives their tips a silhouette without adding hidden
				# rings, projecting creases or independently animated fingers.
				for finger in range(4):
					var t0: float = float(finger) / 4.0
					var t1: float = float(finger + 1) / 4.0
					var lower0: Vector3 = a.lerp(b, t0)
					var lower1: Vector3 = a.lerp(b, t1)
					lower0.y = -height + _finger_height(finger * 2, thumb_side)
					lower1.y = -height + _finger_height((finger + 1) * 2, thumb_side)
					_quad(mb, lower0, lower1, d.lerp(c, t1), d.lerp(c, t0), interior, skin)
					bottom.append(lower0)
			else:
				_quad(mb, a, b, c, d, interior, colours[band])
				if band == 0:
					bottom.append(a)
	var top: Array[Vector3] = []
	for corner in [0, 1, 2, 3, 5, 6]:
		top.append(_point(corner, levels.size() - 1, levels, radii, offsets, thumb_side))
	var shoulder_interior := Vector3(offsets[-1].x, levels[-1] - 0.025, offsets[-1].y)
	for i in range(1, top.size() - 1):
		_triangle(mb, top[0], top[i], top[i + 1], shoulder_interior, sleeve)
	var cap_interior: Vector3 = tip_centre + Vector3(0, 0.025, 0)
	for i in range(bottom.size()):
		_triangle(mb, tip_centre, bottom[i], bottom[(i + 1) % bottom.size()],
			cap_interior, skin.darkened(0.015))
	_thumb(mb, height, thumb_side, skin)
	# Four broad finger-edge facets avoid unnecessary sub-pixel scalloping.
	# 115 arm/hand triangles plus 20 thumb triangles: 135 emitted in total.
	# Two coincident shoulder edges emit no area; the six-corner cap needs four
	# triangles. Hand contours retain their original detail and closed surfaces.


static func _point(corner: int, ring: int, levels: Array[float],
		radii: Array[Vector2], offsets: Array[Vector2], thumb_side: float) -> Vector3:
	var contour: Vector2 = SHOULDER_END[corner] if ring == levels.size() - 1 else CORNERS[corner]
	var point := Vector3(contour.x * radii[ring].x + offsets[ring].x,
		levels[ring], contour.y * radii[ring].y + offsets[ring].y)
	if ring == 0:
		# Outer fingers are shorter; the palm's back slopes into the fingertips.
		var heights: Array[float] = [0.010, 0.009, 0.008, FINGER_EDGE[0],
			FINGER_EDGE[-1], 0.007, 0.009, 0.010]
		var mirrored: int = 7 - corner if thumb_side < 0 else corner
		point.y += heights[mirrored]
	return point


static func _finger_height(index: int, thumb_side: float) -> float:
	return FINGER_EDGE[index if thumb_side > 0 else FINGER_EDGE.size() - 1 - index]


static func _thumb(mb: MeshBuilder, height: float, side: float, skin: Color) -> void:
	# Two gently bending segments with a tapered, flat end. The root is buried
	# in the palm, but remains capped so this authored part stays closed.
	var centres: Array[Vector3] = [Vector3(side * 0.024, -height * 0.845, 0.038),
		Vector3(side * 0.049, -height * 0.89, 0.054),
		Vector3(side * 0.047, -height * 0.935, 0.060)]
	var radii: Array[Vector2] = [Vector2(0.010, 0.010), Vector2(0.010, 0.009),
		Vector2(0.006, 0.006)]
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(-1, 1),
		Vector2(1, 1), Vector2(1, -1)]
	var rings: Array = []
	for i in range(centres.size()):
		var tangent: Vector3 = centres[mini(i + 1, centres.size() - 1)] - centres[maxi(i - 1, 0)]
		tangent = tangent.normalized()
		var across: Vector3 = Vector3.FORWARD.cross(tangent).normalized()
		var depth: Vector3 = tangent.cross(across).normalized()
		var ring: Array[Vector3] = []
		for corner in corners:
			ring.append(centres[i] + across * corner.x * radii[i].x + depth * corner.y * radii[i].y)
		rings.append(ring)
	for band in range(centres.size() - 1):
		var interior: Vector3 = centres[band].lerp(centres[band + 1], 0.5)
		for i in range(4):
			var j: int = (i + 1) % 4
			_quad(mb, rings[band][i], rings[band][j], rings[band + 1][j],
				rings[band + 1][i], interior, skin)
	for end in [0, 2]:
		var interior: Vector3 = centres[1]
		_quad(mb, rings[end][0], rings[end][1], rings[end][2], rings[end][3],
			interior, skin.darkened(0.01))


static func _quad(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, interior: Vector3, colour: Color) -> void:
	_triangle(mb, a, b, c, interior, colour)
	_triangle(mb, a, c, d, interior, colour)


static func _triangle(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3,
		interior: Vector3, colour: Color) -> void:
	# Finger edges and closed thumb caps include small valid facets. Opt into
	# the local art cutoff; the common terrain/prop threshold is unchanged.
	if (b - a).cross(c - a).dot(interior - a) > 0:
		mb.add_tri(a, c, b, colour, 1e-12)
	else:
		mb.add_tri(a, b, c, colour, 1e-12)
