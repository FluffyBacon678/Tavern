class_name KeeperWardrobeArt
extends RefCounted

## Cosmetic keeper garments use the same local pivots and six rigid parts as
## KeeperMesh. Contours replace the covered body, rather than stacking complete
## clothes meshes; every combination is baked into PawnMesh's single surface.
const CORNERS: Array[Vector2] = [Vector2(-0.65, -1), Vector2(-1, -0.65),
	Vector2(-1, 0.65), Vector2(-0.65, 1), Vector2(0.65, 1),
	Vector2(1, 0.65), Vector2(1, -0.65), Vector2(0.65, -1)]
const LEATHER := Color("71503a")
const BELT := Color("493327")
const BRASS := Color("c59c52")
const COPPER := Color("ba7848")
const LINEN := Color("ddd7bd")
const STAFF_HATS: Array[String] = ["server_cap", "work_cap", "host_hat", "headscarf", "fishing_hat", "straw_hat"]
const COVERED_HATS: Array[String] = ["felt_hat", "cook_hat", "server_cap", "work_cap", "host_hat", "headscarf", "fishing_hat", "straw_hat"]


static func torso(mb: MeshBuilder, height: float, outfit: Dictionary) -> void:
	var garment: String = String(outfit.get("body_item", ""))
	var apron: bool = String(outfit.get("outer_item", "")) == "linen_apron"
	var waist_apron: bool = String(outfit.get("outer_item", "")) == "waist_apron"
	var pendant: bool = String(outfit.get("neck_item", "")) == "copper_pendant"
	var cloth: Color = outfit["body"]
	var skin: Color = outfit["skin"]
	if not _dressed(outfit):
		KeeperMesh.tunic(mb, height, cloth, skin, BELT, BRASS)
		return
	var vest: bool = garment in ["leather_vest", "house_waistcoat"]
	if garment == "leather_vest":
		cloth = LEATHER
	# Keep the base tunic's chest, waist and shoulder contour even when a small
	# accessory is worn. Separate shallow cloth folds and hidden belt caps are
	# unnecessary under equipment, making room for an independent apron/jewelry.
	_shell(mb, [-0.026, 0.085, 0.145, 0.280, height - 0.016, height],
		[Vector2(0.156, 0.110), Vector2(0.133, 0.102), Vector2(0.139, 0.106),
		Vector2(0.173, 0.119), Vector2(0.156, 0.107), Vector2(0.066, 0.069)],
		[Vector2.ZERO, Vector2.ZERO, Vector2(0, 0.002), Vector2(0, 0.004), Vector2.ZERO, Vector2.ZERO],
		[cloth.darkened(0.045), cloth, cloth, cloth, cloth])
	_front(mb, Vector3(-0.045, height + 0.002, 0.071), Vector3(-0.035, height - 0.016, 0.110),
		Vector3(0.035, height - 0.016, 0.110), Vector3(0.045, height + 0.002, 0.071), skin)
	mb.add_tri(Vector3(-0.035, height - 0.016, 0.110), Vector3(0, height - 0.093, 0.126),
		Vector3(0.035, height - 0.016, 0.110), outfit["sleeve"] if vest else skin, 1e-12)
	for side in [-1.0, 1.0]:
		_front(mb, Vector3(side * 0.061, height + 0.003, 0.075), Vector3(side * 0.021, height - 0.096, 0.131),
			Vector3(side * 0.004, height - 0.089, 0.130), Vector3(side * 0.042, height + 0.003, 0.076),
			cloth.lightened(0.12 if vest else 0.05))
	if vest and not apron:
		_front(mb, Vector3(-0.002, 0.121, 0.114), Vector3(0.002, 0.121, 0.114),
			Vector3(0.002, height - 0.093, 0.127), Vector3(-0.002, height - 0.093, 0.127), cloth.darkened(0.25))
		if garment == "house_waistcoat":
			for button in range(2 if pendant else 3):
				var y: float = 0.167 + button * 0.040
				var z: float = 0.116 + button * 0.004
				_front(mb, Vector3(0, y - 0.005, z), Vector3(0.004, y, z),
					Vector3(0, y + 0.005, z), Vector3(-0.004, y, z), BRASS)
	if apron or waist_apron:
		_apron(mb, height, not waist_apron)
	else:
		_shell(mb, [0.079, 0.110], [Vector2(0.139, 0.110), Vector2(0.138, 0.110)],
			[Vector2.ZERO, Vector2.ZERO], [BELT], false)
		_front(mb, Vector3(-0.027, 0.075, 0.124), Vector3(0.027, 0.075, 0.124),
			Vector3(0.027, 0.117, 0.124), Vector3(-0.027, 0.117, 0.124), BRASS)
		_front(mb, Vector3(-0.016, 0.083, 0.125), Vector3(0.016, 0.083, 0.125),
			Vector3(0.016, 0.108, 0.125), Vector3(-0.016, 0.108, 0.125), BELT)
	if pendant:
		_pendant(mb, height, apron)


## A closed faceted pelvis joins the moving thighs beneath the higher hem.
## Its clipped corners contain the thigh caps at rest and at full stride.
static func hips(mb: MeshBuilder, trouser: Color) -> void:
	_shell(mb, [-0.022, 0.085], [Vector2(0.138, 0.076), Vector2(0.138, 0.073)],
		[Vector2(0, 0.006), Vector2(0, 0.006)], [trouser])


static func arm(mb: MeshBuilder, height: float, outfit: Dictionary, thumb_side: float) -> void:
	var short: bool = String(outfit.get("body_item", "")) == "short_sleeve_shirt"
	var gloves: bool = String(outfit.get("hands_item", "")) == "work_gloves"
	var sleeve: Color = outfit["sleeve"]
	var cuff: Color = outfit["cuff"]
	var skin: Color = outfit["skin"]
	if not short and not gloves:
		KeeperMesh.arm(mb, height, sleeve, cuff, skin, thumb_side)
	else:
		# A connected hand/forearm/sleeve surface. The rolled short cuff ends on
		# the upper arm; gloves replace the skin colour of the closed hand.
		var levels: Array[float] = [-height, -height * 0.89, -height * 0.81,
			-height * (0.54 if short else 0.72), -height * (0.36 if short else 0.62),
			-height * 0.32 if short else -0.025, 0.002]
		var radii: Array[Vector2] = [Vector2(0.027, 0.018), Vector2(0.035, 0.027),
			Vector2(0.028, 0.029), Vector2(0.040, 0.043), Vector2(0.050, 0.052),
			Vector2(0.053, 0.055), Vector2(0.039, 0.043)]
		var offsets: Array[Vector2] = [Vector2(0, 0.038), Vector2(0, 0.032), Vector2(0, 0.022),
			Vector2(0, 0.012), Vector2(0, 0.007), Vector2(thumb_side * 0.004, 0),
			Vector2(thumb_side * 0.015, 0)]
		var hand: Color = LEATHER.darkened(0.06) if gloves else skin
		var colours: Array[Color] = [hand, hand, skin if short else hand,
			skin if short else cuff, sleeve.lightened(0.08) if short else sleeve, sleeve]
		_shell(mb, levels, radii, offsets, colours)
		_thumb(mb, height, thumb_side, hand)
	# A ring belongs to one hand. Its small raised band crosses one finger,
	# rather than adding a torus or turning the whole wrist into a bracelet.
	if thumb_side > 0 and String(outfit.get("ring_item", "")) == "copper_ring":
		_front(mb, Vector3(-0.016, -height + 0.010, 0.061), Vector3(-0.005, -height + 0.010, 0.061),
			Vector3(-0.005, -height + 0.017, 0.061), Vector3(-0.016, -height + 0.017, 0.061), COPPER)
		_front(mb, Vector3(-0.013, -height + 0.012, 0.062), Vector3(-0.008, -height + 0.012, 0.062),
			Vector3(-0.008, -height + 0.015, 0.062), Vector3(-0.013, -height + 0.015, 0.062), COPPER.lightened(0.16))


static func leg(mb: MeshBuilder, height: float, outfit: Dictionary) -> void:
	var rolled: bool = String(outfit.get("legs_item", "")) == "rolled_trousers"
	var shoes: bool = String(outfit.get("feet_item", "")) == "work_shoes"
	var trouser: Color = outfit["legs"]
	var boot: Color = outfit["boots"]
	if not rolled and not shoes:
		KeeperMesh.leg(mb, height, trouser, boot)
		return
	var skin: Color = outfit["skin"]
	# The sole, toe, ankle and trousers share one contour with no overlapping
	# foot caps. Short work shoes expose the ankle; rolls are a colour/contour
	# transition under the knee. The bottom is still exactly -height.
	_shell(mb, [-height, -height + 0.016, -height + 0.056,
		-height * (0.83 if shoes else 0.62), -height * 0.54, -height * 0.49,
		-height * 0.29, 0.015],
		[Vector2(0.056, 0.084), Vector2(0.055, 0.083), Vector2(0.048, 0.069),
		Vector2(0.037 if shoes else 0.053, 0.041 if shoes else 0.055),
		Vector2(0.043, 0.043), Vector2(0.054, 0.052), Vector2(0.060, 0.058), Vector2(0.059, 0.061)],
		[Vector2(0, 0.022), Vector2(0, 0.022), Vector2(0, 0.025), Vector2(0, 0.006),
		Vector2(0, 0.006), Vector2(0, 0.006), Vector2(0, 0.003), Vector2.ZERO],
		[boot.darkened(0.14), boot, boot.lightened(0.045), skin if rolled else trouser,
		trouser.lightened(0.10) if rolled else trouser, trouser, trouser])


static func head(skin: Color, hair: Color, style: int, outfit: Dictionary,
		ink: Color = Color("252b29")) -> ArrayMesh:
	var gear: String = String(outfit.get("headgear", ""))
	var covered: bool = gear in COVERED_HATS
	var colour: Color = outfit.get("headgear_colour", Color("65513e"))
	return KeeperMesh.head(skin, hair, style, covered, colour, ink, gear,
		int(outfit.get("face_type", 0)), int(outfit.get("expression", 0)))


static func cook_hat(mb: MeshBuilder) -> void:
	# A tall, eight-sided cloth crown with a firm turned band and a gently
	# slanted top. This is an original silhouette, not a copied game asset.
	var rings: Array = []
	for ring in range(3):
		var points: Array[Vector3] = []
		var radius: Vector2 = [Vector2(0.111, 0.105), Vector2(0.127, 0.116), Vector2(0.116, 0.107)][ring]
		for corner in CORNERS:
			var y: float = [0.194, 0.226, 0.360][ring]
			if ring == 2:
				y += corner.x * 0.013 + corner.y * 0.004
			points.append(Vector3(corner.x * radius.x + (0.011 if ring == 2 else 0.0), y,
				corner.y * radius.y - (0.011 if ring == 2 else 0.0)))
		rings.append(points)
	for band in range(2):
		for i in range(8):
			var j: int = (i + 1) % 8
			mb.add_quad(rings[band][i], rings[band][j], rings[band + 1][j], rings[band + 1][i],
				LINEN.darkened(0.03) if band == 0 else LINEN.lightened(0.05))
	for i in range(1, 7):
		mb.add_tri(rings[0][0], rings[0][i + 1], rings[0][i], LINEN.darkened(0.05))
		mb.add_tri(rings[2][0], rings[2][i], rings[2][i + 1], LINEN.lightened(0.08))


static func _dressed(outfit: Dictionary) -> bool:
	for key in ["body_item", "outer_item", "legs_item", "feet_item", "hands_item", "neck_item", "ring_item"]:
		if String(outfit.get(key, "")) in ["short_sleeve_shirt", "leather_vest", "linen_apron",
				"rolled_trousers", "work_shoes", "work_gloves", "copper_pendant", "copper_ring",
				"house_waistcoat", "waist_apron"]:
			return true
	return String(outfit.get("headgear", "")) == "cook_hat" or String(outfit.get("headgear", "")) in STAFF_HATS


static func _apron(mb: MeshBuilder, height: float, bib: bool = true) -> void:
	# The apron is independent of the shirt/vest. Its neck ribbon follows the
	# shoulder slope; bib and pleated skirt sit just ahead of the base cloth.
	if bib:
		_front(mb, Vector3(-0.070, 0.125, 0.130), Vector3(0.070, 0.125, 0.130),
			Vector3(0.078, height - 0.065, 0.135), Vector3(-0.078, height - 0.065, 0.135), LINEN)
		for side in [-1.0, 1.0]:
			_front(mb, Vector3(side * 0.066, height - 0.067, 0.138), Vector3(side * 0.079, height - 0.067, 0.138),
				Vector3(side * 0.059, height + 0.003, 0.077), Vector3(side * 0.047, height + 0.003, 0.077), LINEN.darkened(0.03))
	_shell(mb, [0.075, 0.113], [Vector2(0.146, 0.118), Vector2(0.143, 0.116)],
		[Vector2.ZERO, Vector2.ZERO], [LINEN.darkened(0.10)], false)
	var skirt_top: Array[Vector3] = [Vector3(-0.118, 0.114, 0.132), Vector3(-0.040, 0.114, 0.144),
		Vector3(0.040, 0.114, 0.144), Vector3(0.118, 0.114, 0.132)]
	var skirt_bottom: Array[Vector3] = [Vector3(-0.149, -0.186, 0.147), Vector3(-0.050, -0.190, 0.169),
		Vector3(0.050, -0.190, 0.169), Vector3(0.149, -0.186, 0.147)]
	if not bib:
		for point in range(skirt_bottom.size()):
			skirt_bottom[point].y += 0.065
	for i in range(3):
		_front(mb, skirt_bottom[i], skirt_bottom[i + 1], skirt_top[i + 1], skirt_top[i],
			LINEN.darkened(0.025) if i == 1 else LINEN)
		_front(mb, skirt_bottom[i] - Vector3(0, 0.011, 0), skirt_bottom[i + 1] - Vector3(0, 0.011, 0),
			skirt_bottom[i + 1] + Vector3(0, 0, 0.001), skirt_bottom[i] + Vector3(0, 0, 0.001), LINEN.darkened(0.10))
	# The rear knot and two ties make the waist read from behind even without
	# a cape. They face backward and stay clear of the torso's rear contour.
	mb.add_tri(Vector3(0, 0.096, -0.122), Vector3(-0.035, 0.082, -0.123), Vector3(-0.041, 0.111, -0.123), LINEN, 1e-12)
	mb.add_tri(Vector3(0, 0.096, -0.122), Vector3(0.041, 0.111, -0.123), Vector3(0.035, 0.082, -0.123), LINEN, 1e-12)
	mb.add_quad(Vector3(-0.012, 0.092, -0.125), Vector3(-0.017, -0.011, -0.120),
		Vector3(-0.029, -0.003, -0.120), Vector3(-0.022, 0.092, -0.125), LINEN.darkened(0.035), 1e-12)
	mb.add_quad(Vector3(0.022, 0.092, -0.125), Vector3(0.037, -0.004, -0.120),
		Vector3(0.025, -0.013, -0.120), Vector3(0.012, 0.092, -0.125), LINEN.darkened(0.035), 1e-12)


static func staff_hat(mb: MeshBuilder, kind: String, colour: Color) -> void:
	if kind in ["straw_hat", "fishing_hat"]:
		var straw: bool = kind == "straw_hat"
		var brim := Vector2(0.185, 0.160) if straw else Vector2(0.160, 0.143)
		_shell(mb, [0.183 if not straw else 0.195, 0.205],
			[brim, brim * 0.90], [Vector2.ZERO, Vector2.ZERO], [colour.darkened(0.045)])
		_shell(mb, [0.204, 0.225, 0.274 if straw else 0.265],
			[Vector2(0.112, 0.108), Vector2(0.111, 0.105), Vector2(0.080, 0.078)],
			[Vector2.ZERO, Vector2.ZERO, Vector2(-0.005, -0.009)],
			[BELT if straw else colour.darkened(0.18), colour])
	elif kind == "headscarf":
		_shell(mb, [0.173, 0.211, 0.248],
			[Vector2(0.110, 0.107), Vector2(0.112, 0.105), Vector2(0.088, 0.082)],
			[Vector2(0, -0.004), Vector2(0, -0.006), Vector2(0, -0.007)],
			[colour.darkened(0.025), colour])
		# A diagonal folded edge reads as tied cloth rather than another cap.
		_front(mb, Vector3(-0.068, 0.189, 0.105), Vector3(0.050, 0.214, 0.103),
			Vector3(0.050, 0.219, 0.101), Vector3(-0.066, 0.195, 0.105), colour.lightened(0.10))
		mb.add_box(Vector3(-0.018, 0.168, -0.137), Vector3(0.036, 0.026, 0.025), colour.darkened(0.07))
		for side in [-1.0, 1.0]:
			_outward(mb, Vector3(side * 0.004, 0.178, -0.139), Vector3(side * 0.018, 0.106, -0.139),
				Vector3(side * 0.033, 0.113, -0.138), Vector3(side * 0.018, 0.181, -0.138), Vector3(0, 0.16, -0.10), colour)
	else:
		var host: bool = kind == "host_hat"
		_shell(mb, [0.189, 0.210, 0.268 if host else 0.245],
			[Vector2(0.110, 0.105), Vector2(0.117, 0.110), Vector2(0.096, 0.092)],
			[Vector2.ZERO, Vector2.ZERO, Vector2(-0.007, -0.009)],
			[BRASS.darkened(0.12) if host else colour.darkened(0.20), colour])
		if kind == "work_cap":
			mb.add_box(Vector3(-0.086, 0.192, 0.077), Vector3(0.172, 0.012, 0.067), colour.darkened(0.12))
		elif kind == "server_cap":
			_front(mb, Vector3(-0.010, 0.204, 0.114), Vector3(0.010, 0.204, 0.114),
				Vector3(0.008, 0.220, 0.112), Vector3(-0.008, 0.220, 0.112), BRASS)


static func _pendant(mb: MeshBuilder, height: float, apron: bool) -> void:
	var z: float = 0.146 if apron else 0.135
	# Clear the bib's upper edge along the entire cord, not just at its tip.
	# The ordinary necklace remains close to the unlayered tunic neckline.
	var collar_z: float = 0.125 if apron else 0.112
	for side in [-1.0, 1.0]:
		_front(mb, Vector3(side * 0.044, height - 0.012, collar_z), Vector3(side * 0.041, height - 0.012, collar_z + 0.002),
			Vector3(side * 0.001, height - 0.107, z), Vector3(side * 0.005, height - 0.107, z), BELT)
	var centre := Vector3(0, height - 0.123, z + 0.006)
	var diamond: Array[Vector3] = [Vector3(0, height - 0.107, z + 0.002), Vector3(-0.012, height - 0.123, z + 0.002),
		Vector3(0, height - 0.141, z + 0.002), Vector3(0.012, height - 0.123, z + 0.002)]
	for i in range(4):
		mb.add_tri(centre, diamond[i], diamond[(i + 1) % 4], COPPER.lightened(0.07) if i < 2 else COPPER, 1e-12)


static func _shell(mb: MeshBuilder, levels: Array[float], radii: Array[Vector2],
		offsets: Array[Vector2], colours: Array[Color], caps: bool = true) -> void:
	var rings: Array = []
	for ring in range(levels.size()):
		var points: Array[Vector3] = []
		for corner in CORNERS:
			points.append(Vector3(corner.x * radii[ring].x + offsets[ring].x, levels[ring],
				corner.y * radii[ring].y + offsets[ring].y))
		rings.append(points)
	for band in range(levels.size() - 1):
		for i in range(8):
			var j: int = (i + 1) % 8
			mb.add_quad(rings[band][i], rings[band][j], rings[band + 1][j], rings[band + 1][i], colours[band], 1e-12)
	if caps:
		for i in range(1, 7):
			mb.add_tri(rings[0][0], rings[0][i + 1], rings[0][i], colours[0].darkened(0.015), 1e-12)
			mb.add_tri(rings[-1][0], rings[-1][i], rings[-1][i + 1], colours[-1], 1e-12)


static func _thumb(mb: MeshBuilder, height: float, side: float, colour: Color) -> void:
	var centres: Array[Vector3] = [Vector3(side * 0.024, -height * 0.845, 0.038),
		Vector3(side * 0.049, -height * 0.89, 0.054), Vector3(side * 0.047, -height * 0.935, 0.060)]
	var radii: Array[Vector2] = [Vector2(0.010, 0.010), Vector2(0.010, 0.009), Vector2(0.006, 0.006)]
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]
	var rings: Array = []
	for i in range(3):
		var tangent: Vector3 = (centres[mini(i + 1, 2)] - centres[maxi(i - 1, 0)]).normalized()
		var across: Vector3 = Vector3.FORWARD.cross(tangent).normalized()
		var depth: Vector3 = tangent.cross(across).normalized()
		var ring: Array[Vector3] = []
		for corner in corners:
			ring.append(centres[i] + across * corner.x * radii[i].x + depth * corner.y * radii[i].y)
		rings.append(ring)
	for band in range(2):
		for i in range(4):
			var j: int = (i + 1) % 4
			_outward(mb, rings[band][i], rings[band][j], rings[band + 1][j], rings[band + 1][i],
				centres[band].lerp(centres[band + 1], 0.5), colour)
	for end in [0, 2]:
		_outward(mb, rings[end][0], rings[end][1], rings[end][2], rings[end][3], centres[1], colour)


static func _outward(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, interior: Vector3, colour: Color) -> void:
	if (b - a).cross(c - a).dot(interior - a) > 0:
		mb.add_quad(d, c, b, a, colour, 1e-12)
	else:
		mb.add_quad(a, b, c, d, colour, 1e-12)


static func _front(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	if (b - a).cross(c - a).z < 0:
		mb.add_quad(d, c, b, a, colour, 1e-12)
	else:
		mb.add_quad(a, b, c, d, colour, 1e-12)
