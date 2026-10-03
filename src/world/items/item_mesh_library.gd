class_name ItemMeshLibrary
extends RefCounted

## Procedural low-poly meshes for items, cached by definition id.
##
## Items are small and there will be a lot of them, so every shape here is a
## handful of boxes and prisms, kept to a single cached surface. They are
## authored centred on the origin at ground level, so a stack can be dropped on
## a tile or parented to a pawn's carry anchor without any per-shape offsets.

const SCALE: float = 0.42
const Surface := TavernMaterials.Surface

var _meshes: Dictionary = {}


func mesh_for(def: ItemDef) -> ArrayMesh:
	if _meshes.has(def.id):
		return _meshes[def.id]
	var mesh: ArrayMesh = _build(def)
	_meshes[def.id] = mesh
	return mesh


func _build(def: ItemDef) -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.use_textures = true
	# Goods are small: a complete weave/crust motif should fit on a sack or
	# loaf, rather than looking like a tiny crop from furniture-size grain.
	mb.texture_scale = Vector2(3.0, 3.0)
	var main: Color = def.palette[0] if def.palette.size() > 0 else Color.WHITE
	var accent: Color = def.palette[1] if def.palette.size() > 1 else main

	match def.shape:
		ItemDef.Shape.SACK:
			_sack(mb, main, accent, def.id == &"malt")
		ItemDef.Shape.JAR:
			_jar(mb, main, accent)
		ItemDef.Shape.CASK:
			_cask(mb, main, accent)
		ItemDef.Shape.BUNDLE:
			_bundle(mb, main, accent)
		ItemDef.Shape.DOUGH:
			_dough(mb, main, accent)
		ItemDef.Shape.LOAF:
			_loaf(mb, main, accent)
		ItemDef.Shape.MUG:
			_mug(mb, main, accent)
		ItemDef.Shape.DISHES:
			_dishes(mb, main, accent)
		ItemDef.Shape.FISH:
			_fish(mb, main, accent)
		ItemDef.Shape.FILLET:
			_fillet(mb, main, accent)
		ItemDef.Shape.FISH_HEAD:
			_fish_head(mb, main, accent)
		ItemDef.Shape.BOWL:
			_bowl(mb, main, accent)
		ItemDef.Shape.FISH_PLATE:
			_fish_plate(mb, main, accent)
		ItemDef.Shape.FRUIT:
			_fruit(mb, main, accent)
		ItemDef.Shape.JUG:
			_jug(mb, main, accent)
	return mb.commit()


## A sack: a tapered prism with a pinched, tied neck.
func _sack(mb: MeshBuilder, main: Color, accent: Color, malt: bool) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.CLOTH
	mb.add_cylinder(Vector3.ZERO, s * 0.39, s * 0.53, s * 0.36, 6, main.darkened(0.08))
	mb.add_cylinder(Vector3(0.0, s * 0.36, 0.0), s * 0.53, s * 0.20, s * 0.49, 6, main)
	mb.add_cylinder(Vector3(0.0, s * 0.82, 0.0), s * 0.19, s * 0.30, s * 0.16, 6, main)
	mb.add_cylinder(Vector3(0.0, s * 0.80, 0.0), s * 0.23, s * 0.23, s * 0.055, 6, accent.darkened(0.3))
	# An oatmeal label against dark malt cloth, or a dark mill stamp on flour.
	# These are printed marks on one bag, never extra visual ingredient units.
	var patch: Color = Color("d5c49b") if malt else Color("aa895a")
	var ink: Color = Color("76552d") if malt else Color("ede1bd")
	mb.add_quad(_sack_mark(-0.145, 0.41), _sack_mark(0.145, 0.41),
		_sack_mark(0.13, 0.69), _sack_mark(-0.13, 0.69), patch)
	mb.surface_style = Surface.PLAIN
	mb.add_quad(_sack_mark(-0.012, 0.455, 0.004), _sack_mark(0.012, 0.455, 0.004),
		_sack_mark(0.012, 0.65, 0.004), _sack_mark(-0.012, 0.65, 0.004), ink)
	for i in range(3):
		var y: float = 0.49 + float(i) * 0.052
		var width: float = 0.098 if malt else 0.072
		mb.add_tri(_sack_mark(-width, y + 0.04, 0.004), _sack_mark(0.0, y, 0.004),
			_sack_mark(0.0, y + 0.045, 0.004), ink)
		mb.add_tri(_sack_mark(0.0, y, 0.004), _sack_mark(width, y + 0.04, 0.004),
			_sack_mark(0.0, y + 0.045, 0.004), ink)
	for side in [-1.0, 1.0]:
		for y in [0.46, 0.55, 0.64]:
			var x: float = side * 0.125
			mb.add_quad(_sack_mark(x - 0.011, y, 0.005), _sack_mark(x + 0.011, y, 0.005),
				_sack_mark(x + 0.011, y + 0.027, 0.005), _sack_mark(x - 0.011, y + 0.027, 0.005), ink)


## Follow the front facet of the upper sack taper, with a tiny decal offset.
func _sack_mark(x: float, y: float, lift: float = 0.0) -> Vector3:
	return Vector3(x, y, 0.459 - (y - 0.36) * 0.583 + 0.004 + lift) * SCALE


func _jar(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.CERAMIC
	# A foot, rounded shoulder and narrow neck give the yeast crock a pottery
	# silhouette. The tied cloth is a complete lid, not a cork in a pale ring.
	mb.add_cylinder(Vector3.ZERO, s * 0.27, s * 0.32, s * 0.09, 8, main.darkened(0.18))
	mb.add_cylinder(Vector3(0, s * 0.09, 0), s * 0.32, s * 0.38, s * 0.29, 8, main)
	mb.add_cylinder(Vector3(0, s * 0.38, 0), s * 0.38, s * 0.26, s * 0.17, 8, main.lightened(0.06))
	mb.surface_style = Surface.CLOTH
	mb.add_cylinder(Vector3(0, s * 0.515, 0), s * 0.32, s * 0.275, s * 0.12, 8, accent)
	mb.add_cylinder(Vector3(0, s * 0.565, 0), s * 0.303, s * 0.297, s * 0.022, 8, Color("836945"))
	mb.surface_style = Surface.PLAIN
	# A broad glazed band and a pale stamp distinguish the crock even
	# when the top is hidden behind a hauler's hands.
	mb.add_cylinder(Vector3(0, s * 0.24, 0), s * 0.354, s * 0.37, s * 0.075, 8, Color("5d7770"))
	var stamp: Array[Vector3] = []
	for point in [Vector2(-0.05, 0.2775), Vector2(0, 0.2425), Vector2(0.05, 0.2775), Vector2(0, 0.3125)]:
		var radius: float = 0.354 + (point.y - 0.24) * 0.016 / 0.075
		stamp.append(Vector3(point.x, point.y, radius - absf(point.x) * (sqrt(2.0) - 1.0) + 0.004) * s)
	mb.add_tri(stamp[0], stamp[1], stamp[3], accent)
	mb.add_tri(stamp[1], stamp[2], stamp[3], accent)


func _cask(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.WOOD
	# Two opposed tapers give the barrel bulge without extra geometry.
	mb.add_cylinder(Vector3.ZERO, s * 0.38, s * 0.46, s * 0.35, 7, accent)
	mb.add_cylinder(Vector3(0.0, s * 0.35, 0.0), s * 0.46, s * 0.38, s * 0.35, 7, accent)
	mb.surface_style = Surface.METAL
	mb.add_cylinder(Vector3(0.0, s * 0.10, 0.0), s * 0.425, s * 0.44, s * 0.08, 7, Color("57544a"))
	mb.add_cylinder(Vector3(0.0, s * 0.52, 0.0), s * 0.44, s * 0.425, s * 0.08, 7, Color("57544a"))
	# The catalogue's blue remains a stock-identification mark on the timber.
	mb.surface_style = Surface.PLAIN
	mb.add_cylinder(Vector3(0.0, s * 0.30, 0.0), s * 0.469, s * 0.469, s * 0.065, 7, main)
	mb.surface_style = Surface.WOOD
	mb.add_box(Vector3(-s * 0.09, s * 0.69, -s * 0.07), Vector3(s * 0.18, s * 0.03, s * 0.14), accent.darkened(0.3))
	# Lid joints and dark stave seams break the smooth cylinder into timber.
	# Use the same seven-sided profile so the marks sit on its actual facets.
	for i in range(7):
		var a: float = TAU * i / 7.0
		var b: float = a + 0.018
		for half in range(2):
			var y: float = half * s * 0.35
			var lower: float = s * (0.383 if half == 0 else 0.463)
			var upper: float = s * (0.463 if half == 0 else 0.383)
			mb.add_quad(Vector3(cos(a) * lower, y, sin(a) * lower), Vector3(cos(a) * upper, y + s * 0.35, sin(a) * upper), Vector3(cos(b) * upper, y + s * 0.35, sin(b) * upper), Vector3(cos(b) * lower, y, sin(b) * lower), accent.darkened(0.30))
	for x in [-0.15, 0.13]:
		mb.add_quad(Vector3(x, 0.701, -0.28) * s, Vector3(x, 0.701, 0.28) * s, Vector3(x + 0.012, 0.701, 0.28) * s, Vector3(x + 0.012, 0.701, -0.28) * s, accent.darkened(0.38))


## Three overlapping leafy hop cones on tied stalks. Their scalloped silhouette
## distinguishes brewing hops from a sheaf of grain even without an inspector.
func _bundle(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.PLAIN
	for i in range(3):
		var a: float = TAU * float(i) / 3.0
		var off := Vector3(cos(a) * s * 0.20, 0.0, sin(a) * s * 0.20)
		var top: Vector3 = off + Vector3(0.0, s * (0.60 + float(i % 2) * 0.12), 0.0)
		mb.add_limb(off * 0.3, top, s * 0.035, s * 0.025, 4, accent.darkened(0.2))
		for tier in range(3):
			var base: Vector3 = top + Vector3(0.0, s * (-0.28 + float(tier) * 0.115), 0.0)
			mb.add_cone(base, s * (0.19 - float(tier) * 0.035), s * 0.23, 5,
				main.lightened(float(tier) * 0.085))
	mb.surface_style = Surface.CLOTH
	mb.add_cylinder(Vector3(0.0, s * 0.34, 0.0), s * 0.26, s * 0.26, s * 0.08, 6, accent)


func _dough(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.PLAIN
	# Four latitude rings avoid the vertical middle band that made the old
	# dough look like a hexagonal block. An offset fold reads as kneaded dough.
	mb.add_blob(Vector3(0.0, s * 0.25, 0.0), Vector3(s * 0.47, s * 0.25, s * 0.39), 4, 8, main.darkened(0.06))
	mb.add_blob(Vector3(-s * 0.09, s * 0.37, s * 0.015), Vector3(s * 0.26, s * 0.13, s * 0.21), 4, 6, accent.darkened(0.08))


## A faceted oval loaf with pale scores following its actual crust facets.
func _loaf(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	var profile: Array[Vector2] = [Vector2(-0.28, 0.08), Vector2(-0.28, 0.27),
		Vector2(-0.16, 0.46), Vector2(0.0, 0.50), Vector2(0.16, 0.46),
		Vector2(0.28, 0.27), Vector2(0.28, 0.08), Vector2(0.0, 0.0)]
	var xs: Array[float] = [-0.48, -0.33, 0.33, 0.48]
	var widths: Array[float] = [0.56, 1.0, 1.0, 0.56]
	mb.surface_style = Surface.CRUST
	for section in range(3):
		for i in range(profile.size()):
			var j: int = (i + 1) % profile.size()
			var a := Vector3(xs[section], profile[i].y * widths[section], profile[i].x * widths[section]) * s
			var b := Vector3(xs[section + 1], profile[i].y * widths[section + 1], profile[i].x * widths[section + 1]) * s
			var c := Vector3(xs[section + 1], profile[j].y * widths[section + 1], profile[j].x * widths[section + 1]) * s
			var d := Vector3(xs[section], profile[j].y * widths[section], profile[j].x * widths[section]) * s
			mb.add_quad(a, d, c, b, main.darkened(0.12) if i >= 5 else main)
	for end in [0, 3]:
		var centre := Vector3(xs[end], 0.22 * widths[end], 0.0) * s
		for i in range(profile.size()):
			var j: int = (i + 1) % profile.size()
			var a := Vector3(xs[end], profile[i].y * widths[end], profile[i].x * widths[end]) * s
			var b := Vector3(xs[end], profile[j].y * widths[end], profile[j].x * widths[end]) * s
			if end == 0:
				mb.add_tri(centre, b, a, main.darkened(0.06))
			else:
				mb.add_tri(centre, a, b, main.darkened(0.06))
	mb.surface_style = Surface.PLAIN
	for x in [-0.21, 0.0, 0.21]:
		for i in range(1, 5):
			var a: Vector2 = profile[i]
			var b: Vector2 = profile[i + 1]
			# Taper toward the sides so scores read as cuts in crust, not straps.
			var wa: float = 0.020 * (1.0 - absf(a.x) * 2.3)
			var wb: float = 0.020 * (1.0 - absf(b.x) * 2.3)
			mb.add_quad(Vector3(x - wa + a.x * 0.22, a.y + 0.004, a.x) * s,
				Vector3(x - wb + b.x * 0.22, b.y + 0.004, b.x) * s,
				Vector3(x + wb + b.x * 0.22, b.y + 0.004, b.x) * s,
				Vector3(x + wa + a.x * 0.22, a.y + 0.004, a.x) * s, accent.lerp(main, 0.32))


func _mug(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.CERAMIC
	mb.add_cylinder(Vector3.ZERO, s * 0.25, s * 0.29, s * 0.09, 8, accent.darkened(0.15))
	mb.add_cylinder(Vector3(0, s * 0.09, 0), s * 0.29, s * 0.31, s * 0.53, 8, accent)
	mb.add_cylinder(Vector3(0, s * 0.18, 0), s * 0.299, s * 0.307, s * 0.21, 8, Color("3e6666"))
	_rim(mb, Vector3(0.0, s * 0.58, 0.0), s * 0.33, s * 0.26, s * 0.07, 8, accent.lightened(0.16))
	mb.surface_style = Surface.PLAIN
	mb.add_cylinder(Vector3(0.0, s * 0.621, 0.0), s * 0.26, s * 0.26, s * 0.012, 8, main)
	# One irregular crest leaves amber ale visible inside the pale pottery rim.
	mb.add_blob(Vector3(-s * 0.065, s * 0.65, s * 0.065),
		Vector3(s * 0.20, s * 0.075, s * 0.16), 3, 5, Color("f0dfb8"))
	# A faceted D handle retains its open centre without the three chunky
	# rectangular bars. Ends intersect the vessel, closing the tube naturally.
	mb.surface_style = Surface.CERAMIC
	var handle: Array[Vector2] = [Vector2(0.27, 0.49), Vector2(0.42, 0.50), Vector2(0.51, 0.43), Vector2(0.51, 0.24), Vector2(0.43, 0.16), Vector2(0.27, 0.17)]
	for i in range(handle.size() - 1):
		mb.add_limb(Vector3(handle[i].x, handle[i].y, 0) * s, Vector3(handle[i + 1].x, handle[i + 1].y, 0) * s, s * 0.047, s * 0.047, 5, accent.lightened(0.07))


## One used place setting: a broad dish, stained centre and wooden spoon.
## The count stays in ItemWorld; the mesh does not invent a stack of four plates.
func _dishes(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.CERAMIC
	mb.add_cylinder(Vector3.ZERO, s * 0.34, s * 0.46, s * 0.09, 8, main.lightened(0.2))
	_rim(mb, Vector3(0.0, s * 0.08, 0.0), s * 0.46, s * 0.34, s * 0.055, 8, main.lightened(0.34))
	mb.surface_style = Surface.PLAIN
	mb.add_blob(Vector3(-s * 0.08, s * 0.105, -s * 0.04),
		Vector3(s * 0.23, s * 0.023, s * 0.16), 2, 6, accent.darkened(0.32))
	mb.surface_style = Surface.WOOD
	mb.add_limb(Vector3(s * 0.1, s * 0.15, s * 0.02),
		Vector3(s * 0.44, s * 0.15, s * 0.27), s * 0.025, s * 0.032, 4, accent)
	mb.add_blob(Vector3(s * 0.085, s * 0.15, s * 0.015),
		Vector3(s * 0.075, s * 0.025, s * 0.065), 2, 5, accent)


## Open pottery rim, with outward faces and a visible dark inner wall. No
## transparent material or second mesh surface is needed for hollow vessels.
func _rim(mb: MeshBuilder, base: Vector3, outer: float, inner: float,
		height: float, segments: int, color: Color) -> void:
	for i in range(segments):
		var angle_a: float = TAU * float(i) / float(segments)
		var angle_b: float = TAU * float(i + 1) / float(segments)
		var a := Vector3(cos(angle_a), 0.0, sin(angle_a))
		var b := Vector3(cos(angle_b), 0.0, sin(angle_b))
		var top: Vector3 = base + Vector3(0.0, height, 0.0)
		mb.add_quad(base + a * outer, top + a * outer, top + b * outer, base + b * outer, color)
		mb.add_quad(base + b * inner, top + b * inner, top + a * inner, base + a * inner, color.darkened(0.14))
		mb.add_quad(top + a * outer, top + a * inner, top + b * inner, top + b * outer, color)


## A whole fish lying on its side, so the camera above sees its outline: the
## body, a lighter belly, a flat forked tail, a fin along the back, an eye.
func _fish(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.PLAIN
	mb.add_blob(Vector3(0.0, s * 0.07, 0.0), Vector3(s * 0.46, s * 0.07, s * 0.17), 3, 10, main)
	mb.add_blob(Vector3(s * 0.03, s * 0.08, s * 0.06), Vector3(s * 0.34, s * 0.06, s * 0.09), 3, 8, accent)
	var y: float = s * 0.08
	var fin: Color = main.darkened(0.18)
	_flat_tri(mb, Vector3(-s * 0.40, y, 0.0), Vector3(-s * 0.68, y, s * 0.17), Vector3(-s * 0.68, y, -s * 0.17), fin)
	_flat_tri(mb, Vector3(-s * 0.12, y, -s * 0.15), Vector3(s * 0.14, y, -s * 0.15), Vector3(-s * 0.04, y, -s * 0.27), fin)
	mb.add_blob(Vector3(s * 0.33, s * 0.135, -s * 0.03), Vector3(s * 0.035, s * 0.02, s * 0.035), 2, 5, Color("1a120b"))


## A fin or tail: one triangle, seen from either side.
func _flat_tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	mb.add_tri(a, b, c, color)
	mb.add_tri(a, c, b, color)


## A pink fillet, flat and a little curled at the edges.
func _fillet(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.PLAIN
	mb.add_blob(Vector3(0.0, s * 0.05, 0.0), Vector3(s * 0.36, s * 0.05, s * 0.16), 3, 8, main)
	mb.add_blob(Vector3(s * 0.05, s * 0.085, 0.0), Vector3(s * 0.24, s * 0.02, s * 0.08), 2, 6, accent)


## The head, for the soup pot: on its side like the whole fish, the pale cut
## face behind, the eye on top and the mouth open at the front.
func _fish_head(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.PLAIN
	mb.add_blob(Vector3(0.0, s * 0.08, 0.0), Vector3(s * 0.22, s * 0.08, s * 0.17), 3, 8, main)
	mb.add_blob(Vector3(-s * 0.17, s * 0.08, 0.0), Vector3(s * 0.05, s * 0.07, s * 0.14), 2, 6, accent)
	mb.add_blob(Vector3(s * 0.08, s * 0.15, -s * 0.03), Vector3(s * 0.04, s * 0.02, s * 0.04), 2, 5, Color("1a120b"))
	mb.add_blob(Vector3(s * 0.21, s * 0.08, s * 0.04), Vector3(s * 0.03, s * 0.03, s * 0.05), 2, 5, main.darkened(0.5))


## A bowl of fish soup, with a crust of bread resting on the rim.
func _bowl(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.CERAMIC
	mb.add_cylinder(Vector3.ZERO, s * 0.22, s * 0.32, s * 0.16, 8, accent)
	_rim(mb, Vector3(0.0, s * 0.16, 0.0), s * 0.34, s * 0.28, s * 0.05, 8, accent.lightened(0.12))
	mb.surface_style = Surface.PLAIN
	mb.add_cylinder(Vector3(0.0, s * 0.19, 0.0), s * 0.28, s * 0.28, s * 0.012, 8, main)
	mb.add_blob(Vector3(s * 0.08, s * 0.21, -s * 0.05), Vector3(s * 0.07, s * 0.02, s * 0.05), 2, 5, main.lightened(0.25))


## Grilled fish on a plate, with char stripes along the body.
func _fish_plate(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.CERAMIC
	mb.add_cylinder(Vector3.ZERO, s * 0.36, s * 0.44, s * 0.06, 8, accent)
	mb.surface_style = Surface.PLAIN
	mb.add_blob(Vector3(0.0, s * 0.12, 0.0), Vector3(s * 0.32, s * 0.07, s * 0.12), 3, 8, main)
	for x in [-0.14, 0.0, 0.14]:
		mb.add_box(Vector3(x * s - s * 0.012, s * 0.185, -s * 0.09), Vector3(s * 0.024, s * 0.01, s * 0.18), main.darkened(0.45))
	mb.add_tri(Vector3(-s * 0.30, s * 0.12, 0.0), Vector3(-s * 0.46, s * 0.20, 0.0), Vector3(-s * 0.46, s * 0.06, 0.0), main.darkened(0.2))


## A shallow crate heaped with lemons.
func _fruit(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.WOOD
	mb.add_box(Vector3(-s * 0.32, 0.0, -s * 0.24), Vector3(s * 0.64, s * 0.16, s * 0.48), accent)
	mb.surface_style = Surface.PLAIN
	for p in [Vector2(-0.16, -0.08), Vector2(0.0, -0.1), Vector2(0.16, -0.06), Vector2(-0.1, 0.1),
			Vector2(0.08, 0.09), Vector2(0.0, 0.0)]:
		var lift: float = 0.22 if p == Vector2(0.0, 0.0) else 0.17
		mb.add_blob(Vector3(p.x * s, lift * s, p.y * s), Vector3(s * 0.1, s * 0.085, s * 0.085), 2, 6,
			main.lightened(0.06) if int(p.x * 100.0) % 2 == 0 else main)


## A jug of lemonade: a pale pitcher, yellow to the brim, with a handle.
func _jug(mb: MeshBuilder, main: Color, accent: Color) -> void:
	var s: float = SCALE
	mb.surface_style = Surface.CERAMIC
	mb.add_cylinder(Vector3.ZERO, s * 0.17, s * 0.13, s * 0.42, 8, accent)
	_rim(mb, Vector3(0.0, s * 0.42, 0.0), s * 0.15, s * 0.12, s * 0.04, 8, accent.lightened(0.08))
	mb.surface_style = Surface.PLAIN
	mb.add_cylinder(Vector3(0.0, s * 0.38, 0.0), s * 0.12, s * 0.12, s * 0.05, 8, main)
	mb.add_limb(Vector3(s * 0.16, s * 0.34, 0.0), Vector3(s * 0.26, s * 0.22, 0.0), s * 0.025, s * 0.025, 4, accent)
	mb.add_limb(Vector3(s * 0.26, s * 0.22, 0.0), Vector3(s * 0.16, s * 0.1, 0.0), s * 0.025, s * 0.025, 4, accent)
	mb.add_blob(Vector3(-s * 0.05, s * 0.47, s * 0.04), Vector3(s * 0.05, s * 0.02, s * 0.05), 2, 5, Color("f2cf3b"))
