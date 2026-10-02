class_name PawnEquipment
extends RefCounted

## Cosmetic kit is baked into the torso's existing skinned surface. A sword,
## bow or staff here is stowed luggage, never a gameplay item or an extra draw.
const LEATHER := Color("67452f")
const EDGE := Color("bf9b61")
const STEEL := Color("9fabb3")


## MeshBuilder's limbs are open tubes. Cloth rolls and hat undersides need
## explicit end faces when a low or side camera can see into them.
static func cap(mb: MeshBuilder, centre: Vector3, normal: Vector3, radius: float, segments: int, col: Color) -> void:
	var tangent: Vector3 = normal.cross(Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT).normalized()
	var bitangent: Vector3 = normal.cross(tangent)
	for i in range(segments):
		var a: float = TAU * i / float(segments)
		var b: float = TAU * (i + 1) / float(segments)
		mb.add_tri(centre, centre + (tangent * cos(a) + bitangent * sin(a)) * radius,
			centre + (tangent * cos(b) + bitangent * sin(b)) * radius, col)


static func sling(mb: MeshBuilder, col: Color) -> void:
	# The centre is proud of the jerkin: a flat strip otherwise disappears
	# through the raised chest panels. Two sections follow the chest profile.
	mb.add_quad(Vector3(-0.13, 0.345, 0.137), Vector3(-0.015, 0.235, 0.164),
		Vector3(0.015, 0.26, 0.164), Vector3(-0.10, 0.368, 0.137), col)
	mb.add_quad(Vector3(-0.015, 0.235, 0.164), Vector3(0.115, 0.11, 0.139),
		Vector3(0.145, 0.135, 0.139), Vector3(0.015, 0.26, 0.164), col)
	mb.add_box(Vector3(0.027, 0.185, 0.162), Vector3(0.044, 0.037, 0.014), EDGE)
	mb.add_box(Vector3(0.039, 0.194, 0.177), Vector3(0.020, 0.019, 0.006), col.darkened(0.3))


## Broad staggered links read as mail at close zoom without dozens of boxes.
static func mail(mb: MeshBuilder, origin: Vector3, columns: int, rows: int, pitch: float, col: Color) -> void:
	for row in range(rows):
		for column in range(columns):
			var p: Vector3 = origin + Vector3((column + 0.25 * (row % 2)) * pitch, row * pitch, 0)
			mb.add_tri(p + Vector3(-pitch * 0.36, pitch * 0.15, 0), p + Vector3(0, -pitch * 0.3, 0),
				p + Vector3(pitch * 0.36, pitch * 0.15, 0), col.darkened(0.35))
			mb.add_tri(p + Vector3(-pitch * 0.26, pitch * 0.15, 0.001), p + Vector3(0, -pitch * 0.1, 0.001),
				p + Vector3(pitch * 0.26, pitch * 0.15, 0.001), col.lightened(0.16))


## A bevelled silhouette in the XY plane, with both faces and a closed rim.
## Points wind counter-clockwise, as required by MeshBuilder's authoring API.
static func panel(mb: MeshBuilder, points: Array[Vector2], z: float, thickness: float, col: Color, tilt: float = 0.0) -> void:
	var centre := Vector2.ZERO
	for point in points:
		centre += point / float(points.size())
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var mid := Vector3(centre.x, centre.y, z + centre.y * tilt)
		var va := Vector3(a.x, a.y, z + a.y * tilt)
		var vb := Vector3(b.x, b.y, z + b.y * tilt)
		var front := Vector3(0, 0, thickness)
		mb.add_tri(mid + front, va + front, vb + front, col)
		mb.add_tri(mid, vb, va, col)
		mb.add_quad(va, vb, vb + front, va + front, col.darkened(0.22))


static func cape(mb: MeshBuilder, col: Color, trim: Color, short: bool = false, pattern: int = 0) -> void:
	# Five folded strips cast their own little creases. The cut hem is uneven;
	# the shoulders stay narrow so plate and leather remain visible from above.
	var length: float = 0.36 if short else 0.64
	for i in range(5):
		var left: float = float(i) / 5.0
		var right: float = float(i + 1) / 5.0
		var x0: float = lerpf(-0.22, 0.22, left)
		var x1: float = lerpf(-0.22, 0.22, right)
		var y0: float = 0.36 - length + (0.024 if i % 2 == 0 else 0.0)
		var y1: float = 0.36 - length + (0.024 if i % 2 != 0 else 0.0)
		var z0: float = -0.23 + (0.027 if i % 2 == 0 else 0.0)
		var z1: float = -0.23 + (0.027 if i % 2 != 0 else 0.0)
		var a := Vector3(x0, y0, z0)
		var b := Vector3(x1, y1, z1)
		var c := Vector3(lerpf(-0.17, 0.17, right), 0.36, -0.135)
		var d := Vector3(lerpf(-0.17, 0.17, left), 0.36, -0.135)
		var cloth: Color = col.lightened(0.06) if i % 2 == 0 else col.darkened(0.12)
		if (pattern == 1 and i == 2) or (pattern == 3 and (i == 0 or i == 4)):
			cloth = col.lerp(trim, 0.6)
		mb.add_quad(a, b, c, d, cloth.darkened(0.12))
		mb.add_quad(d, c, b, a, cloth)
		mb.add_quad(a, a + Vector3(0, 0.025, -0.002), b + Vector3(0, 0.025, -0.002), b, trim)
	# Two actual clasps, instead of a solid cape block across the chest.
	for side in [-1.0, 1.0]:
		mb.add_box(Vector3(side * 0.11 - 0.018, 0.29, 0.12), Vector3(0.036, 0.035, 0.023), trim)


static func shield(mb: MeshBuilder, col: Color, heraldry: Color, emblem: int = 0) -> void:
	var shape: Array[Vector2] = [Vector2(-0.15, 0.35), Vector2(-0.17, 0.19), Vector2(0, -0.17), Vector2(0.17, 0.19), Vector2(0.15, 0.35)]
	# Follow the cape's slope instead of hanging a vertical shield in empty
	# space. Geometry, rim and device share the tilt, so the normals stay honest.
	panel(mb, shape, -0.219, 0.03, col.darkened(0.25), 0.14)
	var inset: Array[Vector2] = []
	for p in shape:
		inset.append((p - Vector2(0, 0.14)) * 0.82 + Vector2(0, 0.14))
	panel(mb, inset, -0.228, 0.012, heraldry, 0.14)
	# Large original devices survive the management zoom. Each polygon is
	# convex; a concave chevron cannot use the panel builder's centre fan.
	var ink: Color = col.lightened(0.26)
	match emblem:
		1:
			panel(mb, [Vector2(-0.095, 0.215), Vector2(-0.095, 0.17), Vector2(0, 0.075), Vector2(0, 0.12)], -0.243, 0.013, ink, 0.14)
			panel(mb, [Vector2(0, 0.12), Vector2(0, 0.075), Vector2(0.095, 0.17), Vector2(0.095, 0.215)], -0.243, 0.013, ink, 0.14)
		2:
			var sun: Array[Vector2] = []
			for i in range(8):
				sun.append(Vector2(cos(TAU * i / 8.0) * 0.068, 0.15 + sin(TAU * i / 8.0) * 0.068))
			panel(mb, sun, -0.243, 0.013, ink, 0.14)
			for side in [-1.0, 1.0]:
				panel(mb, [Vector2(side * 0.11, 0.15), Vector2(side * 0.11 - 0.019, 0.135), Vector2(side * 0.11, 0.12), Vector2(side * 0.11 + 0.019, 0.135)], -0.243, 0.013, ink, 0.14)
		3:
			panel(mb, [Vector2(-0.026, 0.28), Vector2(-0.026, -0.035), Vector2(0, -0.065), Vector2(0.026, -0.035), Vector2(0.026, 0.28)], -0.243, 0.013, ink, 0.14)
		_:
			panel(mb, [Vector2(0, 0.28), Vector2(-0.065, 0.14), Vector2(0, 0.02), Vector2(0.065, 0.14)], -0.243, 0.013, ink, 0.14)
	mb.add_limb(Vector3(-0.12, 0.31, -0.201), Vector3(0.12, 0.31, -0.201), 0.009, 0.009, 4, EDGE)


static func tabard(mb: MeshBuilder, cloth: Color, trim: Color) -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * 0.052
		# Leave the waist clear for the leather belt and buckle; split skirts
		# flare below it instead of hiding the waist behind a flat apron.
		panel(mb, [Vector2(x - 0.048, 0.31), Vector2(x - 0.042, 0.128), Vector2(x + 0.042, 0.128), Vector2(x + 0.048, 0.31)], 0.183, 0.007, cloth)
		panel(mb, [Vector2(x - 0.042, 0.064), Vector2(x - 0.05, -0.16), Vector2(x + 0.05, -0.16), Vector2(x + 0.042, 0.064)], 0.183, 0.007, cloth.darkened(0.06))
		mb.add_box(Vector3(x - 0.05, -0.16, 0.192), Vector3(0.10, 0.018, 0.006), trim)


static func sword(mb: MeshBuilder, side: float = -1.0) -> void:
	# A sheathed blade hangs clear of the front of the thighs.
	var tip := Vector3(side * 0.27, -0.27, -0.01)
	var grip := Vector3(side * 0.205, 0.23, 0.02)
	mb.add_limb(tip, grip, 0.012, 0.032, 4, LEATHER.darkened(0.36))
	mb.add_limb(tip, tip.lerp(grip, 0.10), 0.017, 0.022, 4, STEEL)
	mb.add_limb(grip - Vector3(0.078, 0, 0), grip + Vector3(0.078, 0, 0), 0.015, 0.015, 4, EDGE)
	mb.add_limb(grip, grip + Vector3(-side * 0.018, 0.105, 0), 0.019, 0.017, 6, LEATHER)
	mb.add_blob(grip + Vector3(-side * 0.018, 0.115, 0), Vector3(0.027, 0.025, 0.024), 2, 6, EDGE)


static func quiver_and_bow(mb: MeshBuilder, feathers: Color = Color("e4d8bd")) -> void:
	mb.add_limb(Vector3(0.10, -0.08, -0.23), Vector3(0.17, 0.34, -0.23), 0.057, 0.065, 6, LEATHER)
	mb.add_limb(Vector3(0.159, 0.275, -0.23), Vector3(0.173, 0.35, -0.23), 0.073, 0.073, 6, EDGE.darkened(0.2))
	for i in range(3):
		var at := Vector3(0.12 + i * 0.038, 0.34, -0.23)
		mb.add_limb(at, at + Vector3(0.012, 0.22 + i * 0.018, 0), 0.007, 0.007, 4, Color("c0a67b"))
		mb.add_box(at + Vector3(-0.008, 0.13 + i * 0.018, -0.013), Vector3(0.034, 0.07, 0.026), feathers)
	var points: Array[Vector3] = [Vector3(-0.04, -0.28, -0.27), Vector3(-0.24, -0.12, -0.29), Vector3(-0.29, 0.10, -0.29), Vector3(-0.21, 0.35, -0.27), Vector3(0.0, 0.55, -0.23)]
	for i in range(points.size() - 1):
		mb.add_limb(points[i], points[i + 1], 0.017, 0.016, 5, Color("ac7746"))
	mb.add_limb(points[0], points[-1], 0.0035, 0.0035, 4, Color("d0c8a5"))
	mb.add_limb(points[1].lerp(points[2], 0.65), points[2].lerp(points[3], 0.25), 0.023, 0.023, 5, LEATHER.darkened(0.25))


static func staff(mb: MeshBuilder, jewel: Color, variant: int = 0) -> void:
	var base := Vector3(-0.23, -0.30, -0.22)
	var top := Vector3(-0.31, 0.61, -0.22)
	mb.add_limb(base, top, 0.018, 0.025, 6, LEATHER)
	mb.add_limb(top - Vector3(0, 0.08, 0), top + Vector3(0, 0.02, 0), 0.031, 0.031, 6, EDGE)
	if variant % 2 == 1:
		mb.add_blob(top + Vector3(0, 0.075, 0), Vector3(0.064, 0.07, 0.064), 3, 6, jewel)
	else:
		mb.add_blob(top + Vector3(0, 0.075, 0), Vector3(0.057, 0.10, 0.045), 2, 5, jewel)
	for side in [-1.0, 1.0]:
		mb.add_limb(top, top + Vector3(side * 0.055, 0.075, 0), 0.014, 0.01, 5, EDGE)


static func pack(mb: MeshBuilder, cloth: Color, back_offset: float = 0.0) -> void:
	# Cape and bag are separate slots. The bag moves behind a worn cape while
	# chest straps stay anchored to the same shirt and shoulders.
	mb.add_box(Vector3(-0.14, -0.07, -0.31 + back_offset), Vector3(0.28, 0.36, 0.15), LEATHER)
	panel(mb, [Vector2(-0.14, 0.25), Vector2(-0.11, 0.12), Vector2(0, 0.085), Vector2(0.11, 0.12), Vector2(0.14, 0.25)], -0.322 + back_offset, 0.015, LEATHER.lightened(0.19))
	mb.add_limb(Vector3(-0.20, 0.33, -0.23 + back_offset), Vector3(0.20, 0.33, -0.23 + back_offset), 0.079, 0.079, 8, cloth)
	for side in [-1.0, 1.0]:
		var end := Vector3(side * 0.20, 0.33, -0.23 + back_offset)
		cap(mb, end, Vector3.RIGHT * side, 0.079, 8, cloth.lightened(0.12))
		cap(mb, end + Vector3(side * 0.001, 0, 0), Vector3.RIGHT * side, 0.046, 8, cloth.darkened(0.35))
		cap(mb, end + Vector3(side * 0.002, 0.004, 0), Vector3.RIGHT * side, 0.025, 6, cloth.lightened(0.05))
		mb.add_box(Vector3(side * 0.095 - 0.015, -0.065, -0.327 + back_offset), Vector3(0.03, 0.42, 0.018), LEATHER.darkened(0.35))
		mb.add_box(Vector3(side * 0.095 - 0.024, 0.11, -0.339 + back_offset), Vector3(0.048, 0.043, 0.012), EDGE)
		mb.add_box(Vector3(side * 0.105 - 0.018, 0.12, 0.119), Vector3(0.036, 0.245, 0.016), LEATHER)
		mb.add_limb(Vector3(side * 0.11, 0.348, 0.13), Vector3(side * 0.11, 0.346, -0.17 + back_offset),
			0.012, 0.012, 4, LEATHER)


static func belt_kit(mb: MeshBuilder, accent: Color, book: bool = false, cover: Color = Color("38635c")) -> void:
	mb.add_box(Vector3(-0.158, 0.082, -0.12), Vector3(0.316, 0.035, 0.26), LEATHER.darkened(0.4))
	mb.add_box(Vector3(-0.03, 0.078, 0.145), Vector3(0.06, 0.045, 0.016), EDGE)
	mb.add_box(Vector3(-0.018, 0.086, 0.162), Vector3(0.036, 0.028, 0.008), LEATHER)
	mb.add_box(Vector3(0.13, -0.05, 0.06), Vector3(0.10, 0.135, 0.075), LEATHER)
	mb.add_box(Vector3(0.125, 0.018, 0.068), Vector3(0.11, 0.060, 0.077), LEATHER.lightened(0.15))
	mb.add_box(Vector3(0.165, 0.015, 0.148), Vector3(0.027, 0.034, 0.009), EDGE)
	if book:
		# Pages sit inside two actual covers; the old paper block was wider than
		# its cover and looked like a white slab from the side.
		mb.add_box(Vector3(-0.239, -0.07, 0.035), Vector3(0.077, 0.16, 0.12), Color("daccaa"))
		for x in [-0.251, -0.162]:
			mb.add_box(Vector3(x, -0.085, 0.02), Vector3(0.012, 0.19, 0.15), cover)
		mb.add_box(Vector3(-0.251, -0.085, 0.02), Vector3(0.101, 0.19, 0.014), cover.darkened(0.24))
		mb.add_box(Vector3(-0.257, -0.032, 0.028), Vector3(0.113, 0.023, 0.136), LEATHER)
		cap(mb, Vector3(-0.252, 0.035, 0.10), Vector3.LEFT, 0.027, 6, EDGE)
	else:
		mb.add_blob(Vector3(0.14, -0.028, -0.09), Vector3(0.055, 0.064, 0.055), 3, 6, accent)
		mb.add_cylinder(Vector3(0.14, 0.02, -0.09), 0.023, 0.023, 0.034, 6, EDGE)


static func robe(mb: MeshBuilder, cloth: Color, trim: Color) -> void:
	# An ankle-length skirt with a dark opening; alternating facets suggest
	# heavy cloth. It is attached to the torso, clear of the boot tips.
	for i in range(8):
		var a: float = TAU * i / 8.0 + PI / 8.0
		var b: float = TAU * (i + 1) / 8.0 + PI / 8.0
		var lo0 := Vector3(cos(a) * 0.235, -0.30, sin(a) * 0.18)
		var lo1 := Vector3(cos(b) * 0.235, -0.30, sin(b) * 0.18)
		var hi0 := Vector3(cos(a) * 0.151, 0.12, sin(a) * 0.12)
		var hi1 := Vector3(cos(b) * 0.151, 0.12, sin(b) * 0.12)
		var col: Color = cloth.darkened(0.12) if i % 2 == 0 else cloth
		mb.add_quad(lo0, hi0, hi1, lo1, col)
		mb.add_quad(lo0, lo0 + Vector3(0, 0.026, 0), lo1 + Vector3(0, 0.026, 0), lo1, trim)
	panel(mb, [Vector2(-0.043, 0.1), Vector2(-0.06, -0.24), Vector2(0.06, -0.24), Vector2(0.043, 0.1)], 0.176, 0.009, trim.darkened(0.05))


static func pointed_hat(mb: MeshBuilder, bottom: float, col: Color, trim: Color) -> void:
	mb.add_cylinder(Vector3(0, bottom, 0), 0.205, 0.19, 0.026, 8, col.darkened(0.13))
	cap(mb, Vector3(0, bottom, 0), Vector3.DOWN, 0.205, 8, col.darkened(0.3))
	mb.add_cylinder(Vector3(0, bottom + 0.027, 0), 0.114, 0.11, 0.035, 8, trim)
	# Offset rings make a bent cloth hat, rather than a rigid traffic cone.
	var centres: Array[Vector3] = [Vector3(0, bottom + 0.06, 0), Vector3(0.015, bottom + 0.19, -0.012), Vector3(0.075, bottom + 0.30, -0.035), Vector3(0.14, bottom + 0.29, -0.04)]
	var radii: Array[float] = [0.11, 0.068, 0.022, 0.0]
	for r in range(3):
		for i in range(8):
			var a := Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0))
			var b := Vector3(cos(TAU * (i + 1) / 8.0), 0, sin(TAU * (i + 1) / 8.0))
			mb.add_quad(centres[r] + a * radii[r], centres[r + 1] + a * radii[r + 1], centres[r + 1] + b * radii[r + 1], centres[r] + b * radii[r], col.lightened(0.04) if i % 3 == 0 else col)
