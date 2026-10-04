class_name KeeperMesh
extends RefCounted

## The ordinary base body, authored in the same local coordinates as PawnMesh.
## Continuous contours replace stacked closed blocks. Clothing can follow these
## sections later without changing pivots, saved appearances or the six bones.
const CORNERS: Array[Vector2] = [Vector2(-0.65, -1), Vector2(-1, -0.65),
	Vector2(-1, 0.65), Vector2(-0.65, 1), Vector2(0.65, 1),
	Vector2(1, 0.65), Vector2(1, -0.65), Vector2(0.65, -1)]
const FACE_Y: Array[float] = [0.022, 0.066, 0.114, 0.151, 0.201]
const FACE_W: Array[float] = [0.056, 0.079, 0.097, 0.095, 0.084]
const FACE_FRONT: Array[float] = [0.080, 0.095, 0.105, 0.104, 0.078]
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
	_loft(mb, [-height + 0.032, -height * 0.62, -height * 0.57, -height * 0.48, -height * 0.29, 0.015],
		[Vector2(0.046, 0.049), Vector2(0.053, 0.055), Vector2(0.056, 0.058),
		Vector2(0.045, 0.046), Vector2(0.060, 0.058), Vector2(0.059, 0.061)],
		[Vector2(0, 0.008), Vector2(0, 0.004), Vector2(0, 0.003), Vector2(0, 0.010), Vector2(0, 0.003), Vector2.ZERO],
		[boot, boot.lightened(0.10), trouser.darkened(0.025), trouser, trouser])
	_loft(mb, [-height + 0.014, -height + 0.045, -height + 0.074],
		[Vector2(0.055, 0.083), Vector2(0.052, 0.078), Vector2(0.045, 0.060)],
		[Vector2(0, 0.022), Vector2(0, 0.024), Vector2(0, 0.018)], [boot, boot.lightened(0.025)])
	_loft(mb, [-height, -height + 0.016], [Vector2(0.056, 0.084), Vector2(0.055, 0.083)],
		[Vector2(0, 0.022), Vector2(0, 0.022)], [boot.darkened(0.14)])


static func head(skin: Color, hair: Color, style: int, hat: bool, hat_colour: Color,
		ink: Color, hat_kind: String = "felt_hat", face_type: int = 0,
		expression: int = 0) -> ArrayMesh:
	var mb := MeshBuilder.new()
	face_type = clampi(face_type, 0, 3)
	expression = clampi(expression, 0, 4)
	# The lower three rings distinguish jaw, chin and cheeks. The upper skull
	# keeps the exact shared hair/cap fit, with no saved or global mesh state.
	var widths: Array[float] = FACE_W.duplicate()
	var fronts: Array[float] = FACE_FRONT.duplicate()
	var levels: Array[float] = FACE_Y.duplicate()
	if face_type == 1:  # Soft: rounded jaw, quieter cheek projection.
		levels[0] = 0.038
		widths[0] = 0.060
		widths[1] = 0.085
		widths[2] = 0.094
		fronts[0] = 0.084
		fronts[1] = 0.099
		fronts[2] = 0.103
	elif face_type == 2:  # Angular: square chin and stronger cheek planes.
		levels[0] = 0.019
		widths[0] = 0.069
		widths[1] = 0.089
		widths[2] = 0.099
		fronts[0] = 0.081
		fronts[1] = 0.093
		fronts[2] = 0.108
	elif face_type == 3:  # Broad: wider chin, jaw and cheek line.
		widths[0] = 0.077
		widths[1] = 0.095
		widths[2] = 0.103
		fronts[1] = 0.096
		fronts[2] = 0.106
	_loft(mb, [-0.014, 0.045], [Vector2(0.035, 0.034), Vector2(0.038, 0.037)],
		[Vector2(0, -0.002), Vector2(0, -0.002)], [skin.darkened(0.035)])
	var radii: Array[Vector2] = []
	var offsets: Array[Vector2] = []
	for i in range(FACE_Y.size()):
		radii.append(Vector2(widths[i], (fronts[i] - FACE_BACK[i]) * 0.5))
		offsets.append(Vector2(0, (fronts[i] + FACE_BACK[i]) * 0.5))
	# Chin height varies below .066; all facial ink begins above .075 and
	# therefore still uses the common upper-band heights in _face_point.
	_loft(mb, levels, radii, offsets, [skin.darkened(0.015), skin, skin, skin])
	# Broad cheek planes, a narrower jaw and a straight bridge give the face an
	# adult silhouette. The bridge roots remain outside the skull at both ends.
	var base_width: float = [0.011, 0.010, 0.0105, 0.014][face_type]
	var root_width: float = [0.008, 0.0075, 0.008, 0.010][face_type]
	var tip_width: float = [0.0055, 0.005, 0.0053, 0.0068][face_type]
	var tip_z: float = [0.128, 0.124, 0.132, 0.129][face_type]
	var nl := _face_point(Vector2(-base_width, 0.104), 0.0045, widths, fronts)
	var nr := _face_point(Vector2(base_width, 0.104), 0.0045, widths, fronts)
	var bl := _face_point(Vector2(-root_width, 0.160), 0.0045, widths, fronts)
	var br := _face_point(Vector2(root_width, 0.160), 0.0045, widths, fronts)
	var tl := Vector3(-tip_width, 0.111, tip_z)
	var tr := Vector3(tip_width, 0.111, tip_z)
	var ul := Vector3(-tip_width, 0.120, tip_z)
	var ur := Vector3(tip_width, 0.120, tip_z)
	mb.add_quad(nl, tl, ul, bl, skin.darkened(0.07), 1e-12)
	_front_quad(mb, bl, ul, ur, br, skin.lightened(0.045))
	mb.add_quad(br, ur, tr, nr, skin.darkened(0.015), 1e-12)
	_front_quad(mb, ul, tl, tr, ur, skin.lightened(0.015))
	_front_quad(mb, nl, nr, tr, tl, skin.darkened(0.12))
	var brow_colour: Color = hair.darkened(0.18).lerp(skin.darkened(0.55), 0.30)
	for side in [-1.0, 1.0]:
		_expression_eye(mb, side, face_type, expression, brow_colour, ink, widths, fronts)
		# Each cheek patch stays within one face band so it follows the surface.
		var cheek: Array[Vector2] = [Vector2(side * 0.024, 0.111),
			Vector2(side * 0.061, 0.111), Vector2(side * 0.044, 0.076)]
		if side > 0:
			cheek.reverse()
		var cheek_colour: Color = skin.darkened(0.025)
		if expression in [0, 1]:
			cheek_colour = skin.darkened(0.015).lerp(Color("b86650"), 0.055)
		_ink(mb, cheek, cheek_colour, 0.0005, widths, fronts)
		mb.add_blob(Vector3(side * (widths[2] + 0.001), 0.113, 0.008),
			Vector3(0.012, 0.021, 0.014), 2, 5, skin.darkened(0.025))
	_expression_mouth(mb, skin, expression, widths, fronts)
	_hair(mb, hair, style, hat, widths[2])
	if hat and hat_kind == "cook_hat":
		KeeperWardrobeArt.cook_hat(mb)
	elif hat and hat_kind in KeeperWardrobeArt.STAFF_HATS:
		KeeperWardrobeArt.staff_hat(mb, hat_kind, hat_colour)
	elif hat:
		mb.add_cylinder(Vector3(0, 0.20, 0), 0.167, 0.156, 0.021, 8, hat_colour.darkened(0.12))
		PawnEquipment.cap(mb, Vector3(0, 0.20, 0), Vector3.DOWN, 0.167, 8, hat_colour.darkened(0.24))
		mb.add_cylinder(Vector3(0, 0.221, -0.006), 0.115, 0.091, 0.074, 8, hat_colour)
		mb.add_cylinder(Vector3(0, 0.222, -0.006), 0.117, 0.112, 0.024, 8, Color("493327"))
		mb.add_box(Vector3(0.072, 0.228, 0.077), Vector3(0.025, 0.018, 0.008), Color("c59c52"))
	return mb.commit()


static func _expression_eye(mb: MeshBuilder, side: float, face_type: int,
		expression: int, brow_colour: Color, ink: Color, widths: Array[float],
		fronts: Array[float]) -> void:
	var x: float = side * [0.043, 0.042, 0.043, 0.045][face_type]
	var lower: float = [0.141, 0.143, 0.141, 0.142, 0.141][expression]
	var upper: float = [0.149, 0.1485, 0.149, 0.1485, 0.1475][expression]
	var tilt: float = side * 0.0015 if expression == 4 else 0.0
	# Every opening/lid stays below the brow ring at .151; eyebrows stay above
	# it. Marks therefore follow one actual skull plane instead of crossing it.
	var white: Array[Vector2] = [Vector2(x - 0.012, (lower + upper) * 0.5),
		Vector2(x - 0.007, lower), Vector2(x + 0.007, lower),
		Vector2(x + 0.012, (lower + upper) * 0.5),
		Vector2(x + 0.009, upper), Vector2(x - 0.009, upper)]
	var pupil: Array[Vector2] = [Vector2(x - 0.0038, lower + 0.0006),
		Vector2(x + 0.0038, lower + 0.0006),
		Vector2(x + 0.0034, upper - 0.0003), Vector2(x - 0.0034, upper - 0.0003)]
	var lid: Array[Vector2] = [Vector2(x - 0.011, upper - 0.0005),
		Vector2(x + 0.011, upper - 0.0005),
		Vector2(x + 0.009, upper + 0.002), Vector2(x - 0.009, upper + 0.002)]
	for patch in [white, pupil, lid]:
		for i in range(patch.size()):
			patch[i].y += tilt * (patch[i].x - x) / 0.012
	_ink(mb, white, Color("aea68f"), 0.0013, widths, fronts)
	_ink(mb, pupil, ink, 0.0023, widths, fronts)
	_ink(mb, lid, brow_colour, 0.0028, widths, fronts)
	var inner_low: float = [0.1605, 0.164, 0.159, 0.159, 0.154][expression]
	var inner_high: float = [0.1665, 0.169, 0.166, 0.166, 0.1595][expression]
	var outer_low: float = [0.1585, 0.161, 0.156, 0.156, 0.161][expression]
	var outer_high: float = [0.1635, 0.166, 0.162, 0.162, 0.1665][expression]
	if expression == 3 and side > 0:
		inner_low = 0.164
		inner_high = 0.171
		outer_low = 0.163
		outer_high = 0.169
	var brow: Array[Vector2] = [Vector2(-0.014, inner_low), Vector2(0.015, outer_low),
		Vector2(0.013, outer_high), Vector2(-0.014, inner_high)]
	for i in range(brow.size()):
		brow[i].x = x + brow[i].x * side
	if side < 0:
		brow.reverse()
	_ink(mb, brow, brow_colour, 0.0013, widths, fronts)


static func _expression_mouth(mb: MeshBuilder, skin: Color, expression: int,
		widths: Array[float], fronts: Array[float]) -> void:
	# A warm dark seam reads on all skin tones. These facets fit entirely in
	# the .066..114 lower-face band, including the raised smile corners.
	var lip: Color = skin.darkened(0.25).lerp(Color("4d2c25"), 0.65)
	var lower_lip_y: float = 0.075
	if expression == 2:
		_ink(mb, [Vector2(-0.0225, 0.080), Vector2(0.0225, 0.080),
			Vector2(0.021, 0.084), Vector2(-0.021, 0.084)], lip, 0.0013, widths, fronts)
	else:
		var half_width: float = [0.031, 0.035, 0.0225, 0.030, 0.025][expression]
		var centre_low: float = [0.079, 0.084, 0.080, 0.079, 0.085][expression]
		var centre_high: float = [0.083, 0.091, 0.084, 0.083, 0.089][expression]
		var left_low: float = [0.088, 0.092, 0.080, 0.081, 0.078][expression]
		var right_low: float = [0.088, 0.092, 0.080, 0.093, 0.078][expression]
		var thickness: float = 0.007 if expression == 1 else 0.004
		# A short level centre makes the smile a broad curve rather than a sharp
		# chevron. The stern mouth keeps its deliberate downturned apex.
		var middle: float = 0.008 if expression in [0, 1] else (0.006 if expression == 3 else 0.0)
		_ink(mb, [Vector2(-half_width, left_low), Vector2(-middle, centre_low),
			Vector2(-middle, centre_high), Vector2(-half_width + 0.002, left_low + thickness)],
			lip, 0.0013, widths, fronts)
		_ink(mb, [Vector2(middle, centre_low), Vector2(half_width, right_low),
			Vector2(half_width - 0.002, right_low + thickness), Vector2(middle, centre_high)],
			lip, 0.0013, widths, fronts)
		if middle > 0.0:
			_ink(mb, [Vector2(-middle, centre_low), Vector2(middle, centre_low),
				Vector2(middle, centre_high), Vector2(-middle, centre_high)], lip, 0.0013, widths, fronts)
		if expression == 1:
			# One shallow continuous cream band; no separate teeth or dark cavern.
			var tooth := Color("d9c8a1")
			_ink(mb, [Vector2(-0.026, 0.092), Vector2(-0.007, 0.085),
				Vector2(-0.007, 0.089), Vector2(-0.025, 0.096)], tooth, 0.0022, widths, fronts)
			_ink(mb, [Vector2(0.007, 0.085), Vector2(0.026, 0.092),
				Vector2(0.025, 0.096), Vector2(0.007, 0.089)], tooth, 0.0022, widths, fronts)
			_ink(mb, [Vector2(-0.007, 0.085), Vector2(0.007, 0.085),
				Vector2(0.007, 0.089), Vector2(-0.007, 0.089)], tooth, 0.0022, widths, fronts)
			lower_lip_y = 0.080
		elif expression in [0, 3]:
			var crease_y: float = 0.094 if expression == 3 else 0.090
			for side in [-1.0, 1.0]:
				if expression == 3 and side < 0:
					continue
				var crease: Array[Vector2] = [Vector2(side * 0.031, crease_y),
					Vector2(side * 0.035, crease_y + 0.001),
					Vector2(side * 0.036, crease_y + 0.008)]
				if side < 0:
					crease.reverse()
				_ink(mb, crease, lip, 0.0013, widths, fronts)
		elif expression == 4:
			lower_lip_y = 0.079
	_ink(mb, [Vector2(-0.012, lower_lip_y), Vector2(0.012, lower_lip_y),
		Vector2(0, lower_lip_y + 0.003)], skin.lightened(0.035), 0.0013, widths, fronts)


static func _ink(mb: MeshBuilder, points: Array[Vector2], colour: Color, lift: float,
		widths: Array[float] = FACE_W, fronts: Array[float] = FACE_FRONT) -> void:
	for i in range(1, points.size() - 1):
		mb.add_tri(_face_point(points[0], lift, widths, fronts),
			_face_point(points[i], lift, widths, fronts),
			_face_point(points[i + 1], lift, widths, fronts), colour, 1e-12)


static func _face_point(point: Vector2, lift: float, widths: Array[float] = FACE_W,
		fronts: Array[float] = FACE_FRONT) -> Vector3:
	for i in range(FACE_Y.size() - 1):
		if point.y <= FACE_Y[i + 1]:
			var t: float = clampf(inverse_lerp(FACE_Y[i], FACE_Y[i + 1], point.y), 0, 1)
			var width: float = lerpf(widths[i], widths[i + 1], t)
			var front: float = lerpf(fronts[i], fronts[i + 1], t)
			var back: float = lerpf(FACE_BACK[i], FACE_BACK[i + 1], t)
			var side_plane: float = maxf(absf(point.x) / width - 0.65, 0.0)
			return Vector3(point.x, point.y, front - side_plane * (front - back) * 0.5 + lift)
	return Vector3(point.x, point.y, fronts[-1] + lift)


static func _hair(mb: MeshBuilder, colour: Color, style: int, covered: bool,
		cheek_width: float = 0.097) -> void:
	# A single crown with a shaped hairline. Broad overlapping locks flow in one
	# direction; their tips are cut, so the silhouette no longer forms three spikes.
	var lower: Array[Vector3] = []
	var middle: Array[Vector3] = []
	var upper: Array[Vector3] = []
	var hairline: Array[float] = [0.092, 0.140, 0.156, 0.184, 0.179, 0.158, 0.140, 0.095]
	var crest: float = 0.213 if covered or style == 3 else 0.224
	for i in range(8):
		var nape: bool = i in [0, 7]
		# Keep the nape shell outside the cheek-to-brow rear skull profile; a
		# shallower end briefly crossed it and exposed a horizontal scalp band.
		var nape_width: float = (0.088 if covered else 0.079) + maxf(0.0, cheek_width - 0.097) * 1.5
		lower.append(Vector3(CORNERS[i].x * (nape_width if nape else 0.108), hairline[i], CORNERS[i].y * (0.091 if nape else 0.104) - 0.009))
		middle.append(Vector3(CORNERS[i].x * 0.106, 0.204 if i in [2, 3, 4, 5] else 0.196, CORNERS[i].y * 0.100 - 0.012))
		var upper_y: float = crest + [0.0, 0.003, 0.005, 0.003, 0.009, 0.008, 0.003, -0.003][i]
		# Covered hair skips the middle ring. Keep its upper cross-section wider
		# than the .097 cheek / .100 rear skull bounds, centred on both sides;
		# the bare crown's offset and taper would cross the scalp near the cap.
		var upper_depth: float = (0.097 if nape else 0.094) if covered else 0.061
		upper.append(Vector3(CORNERS[i].x * (0.104 if covered else 0.063) + (0.0 if covered else 0.012), upper_y,
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
		_lock(mb, -0.103, 0.019, 0.220, 0.175, 0.191, colour)
		_lock(mb, 0.004, 0.096, 0.212, 0.191, 0.179, colour.lightened(0.025))
	elif style == 1:
		_lock(mb, -0.108, 0.017, 0.225, 0.163, 0.190, colour)
		_lock(mb, -0.016, 0.095, 0.219, 0.187, 0.179, colour.lightened(0.03))
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
