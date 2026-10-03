class_name GardenArt
extends RefCounted

## Garden tiles and park props: original low-poly meshes, built in code.
##
## Simple crisp shapes that read from the management camera: flat grass beds
## with a soil edge, blade tufts, flower heads as upward discs, lupin spikes,
## faceted rocks and trees. Each kind is one shared mesh (decorations come from
## a seeded generator, so every bench or daisy bed is identical); the builder
## turns 1 x 1 tiles a random quarter per tile, so a lawn does not repeat.
##
## Tiles sit on the floor layer, 0.05 high like the other floors, with every
## decoration kept inside the tile's border so neighbours join cleanly.

const TILE_HEIGHT: float = 0.05
const SOIL := Color("6b4a2e")
const SOIL_DARK := Color("54391f")
const DIRT := Color("9c7b55")
const DIRT_DARK := Color("86684a")
const PEBBLE := Color("8f8c84")
const LAWN := Color("66933d")
const MEADOW := Color("5b8a38")
const BED := Color("4f7930")
const BLADE := Color("5d9637")
const BLADE_LIGHT := Color("7cae45")
const BLADE_DARK := Color("467a2c")
const LEAF := Color("3f6f2a")
const PETAL_WHITE := Color("f2efe6")
const PETAL_RED := Color("c8413a")
const PETAL_YELLOW := Color("f0c63a")
const LUPIN := Color("7a5cc0")
const LUPIN_LIGHT := Color("9a80d8")
const EYE := Color("f0b72e")
const ROCK := Color("8e8c86")
const ROCK_DARK := Color("6f6d68")


## The mesh for a garden tile or prop, by its id.
static func build(mb: MeshBuilder, id: StringName, w: float, d: float, h: float, main: Color, accent: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(id))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	match id:
		&"lawn_trimmed":
			_base(mb, LAWN)
			_patches(mb, rng, LAWN, 3)
			for i in range(4):
				_tuft(mb, rng, _spot(rng), 3, 0.05, 0.07)
		&"lawn_meadow":
			_base(mb, MEADOW)
			_patches(mb, rng, MEADOW, 2)
			for i in range(10):
				_tuft(mb, rng, _spot(rng), 4, 0.09, 0.17)
			for i in range(3):
				_flower(mb, _spot(rng), 0.06, PETAL_WHITE, 0.05, 6)
		&"lawn_worn":
			_base(mb, MEADOW)
			# A trodden swathe across one corner: two overlapping bare patches.
			_blob_patch(mb, rng, Vector2(0.62, 0.38), 0.3, DIRT, 0.004)
			_blob_patch(mb, rng, Vector2(0.38, 0.66), 0.24, DIRT, 0.005)
			for i in range(4):
				_pebble(mb, rng, Vector2(rng.randf_range(0.35, 0.75), rng.randf_range(0.3, 0.75)))
			for spot in [Vector2(0.14, 0.16), Vector2(0.86, 0.86), Vector2(0.16, 0.86), Vector2(0.86, 0.12)]:
				_tuft(mb, rng, spot, 4, 0.08, 0.14)
		&"garden_path":
			_base(mb, DIRT, SOIL_DARK)
			for i in range(5):
				_blob_patch(mb, rng, Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85)), 0.07, DIRT_DARK, 0.003)
			for i in range(6):
				_pebble(mb, rng, Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9)))
		&"bed_daisy":
			_base(mb, BED)
			_ground_cover(mb, rng, 9)
			for p in _grid_spots(3, 0.17):
				_flower(mb, p + _jitter(rng, 0.05), 0.13, PETAL_WHITE, 0.095, 8)
		&"bed_mixed":
			_base(mb, BED)
			_ground_cover(mb, rng, 8)
			for i in range(3):
				_lupin(mb, Vector2(0.6 + 0.13 * i, 0.16 + 0.05 * float(i % 2)), 0.36 + 0.05 * float(i % 2))
			var colours: Array[Color] = [PETAL_WHITE, PETAL_YELLOW, PETAL_RED, PETAL_RED, PETAL_WHITE, PETAL_YELLOW, PETAL_RED]
			var spots: Array[Vector2] = [Vector2(0.18, 0.2), Vector2(0.36, 0.3), Vector2(0.2, 0.5), Vector2(0.5, 0.55),
				Vector2(0.75, 0.55), Vector2(0.32, 0.8), Vector2(0.66, 0.82)]
			for i in range(spots.size()):
				_flower(mb, spots[i] + _jitter(rng, 0.03), 0.12, colours[i], 0.085, 7)
		&"bed_border":
			_base(mb, BED)
			_ground_cover(mb, rng, 8)
			# Lupins at the back, red and white in front: a classic border.
			for i in range(4):
				_lupin(mb, Vector2(0.15 + 0.23 * i, 0.16), 0.42 + 0.04 * float(i % 2))
			for i in range(4):
				_flower(mb, Vector2(0.14 + 0.24 * i, 0.5), 0.12, PETAL_RED if i % 2 == 0 else PETAL_WHITE, 0.09, 7)
				_flower(mb, Vector2(0.22 + 0.19 * i, 0.78), 0.1, PETAL_WHITE if i % 2 == 0 else PETAL_RED, 0.085, 7)
		&"grass_tall":
			_base(mb, MEADOW)
			for p in _grid_spots(4, 0.12):
				_tuft(mb, rng, p + _jitter(rng, 0.05), 6, 0.28, 0.44)
		&"grass_tall_flowers":
			_base(mb, MEADOW)
			for p in _grid_spots(4, 0.12):
				_tuft(mb, rng, p + _jitter(rng, 0.05), 5, 0.24, 0.38)
			for p in [Vector2(0.3, 0.3), Vector2(0.62, 0.4), Vector2(0.42, 0.66), Vector2(0.72, 0.72), Vector2(0.2, 0.7)]:
				_flower(mb, p, 0.36, PETAL_WHITE, 0.07, 7)
		&"grass_overgrown":
			_base(mb, BED)
			for p in [Vector2(0.15, 0.2), Vector2(0.5, 0.12), Vector2(0.85, 0.2), Vector2(0.85, 0.55),
					Vector2(0.15, 0.85), Vector2(0.5, 0.88), Vector2(0.85, 0.88)]:
				_tuft(mb, rng, p + _jitter(rng, 0.03), 6, 0.26, 0.42)
			_rock(mb, Vector3(0.3, TILE_HEIGHT, 0.55), Vector3(0.17, 0.12, 0.14))
			_rock(mb, Vector3(0.18, TILE_HEIGHT, 0.4), Vector3(0.08, 0.06, 0.07))
			_bush(mb, Vector3(0.66, TILE_HEIGHT, 0.6), 0.2)
			_bush(mb, Vector3(0.5, TILE_HEIGHT, 0.35), 0.14)
		&"garden_bench":
			_bench(mb, w, d)
		&"garden_rocks":
			_rock(mb, Vector3(0.42, 0.0, 0.5), Vector3(0.3, 0.24, 0.26))
			_rock(mb, Vector3(0.72, 0.0, 0.62), Vector3(0.16, 0.12, 0.14))
			_rock(mb, Vector3(0.68, 0.0, 0.28), Vector3(0.09, 0.07, 0.08))
		&"garden_tree":
			_round_tree(mb)
		&"garden_pine":
			_pine(mb)
		&"lantern_post":
			_lantern_post(mb)


# --- tiles ------------------------------------------------------------------------

## A low bed: grass (or dirt) on top, soil on the sides, like a laid tile.
static func _base(mb: MeshBuilder, top: Color, side: Color = SOIL) -> void:
	mb.add_box(Vector3.ZERO, Vector3(1.0, TILE_HEIGHT, 1.0), side)
	_flat(mb, [Vector3(0, TILE_HEIGHT + 0.001, 0), Vector3(0, TILE_HEIGHT + 0.001, 1),
		Vector3(1, TILE_HEIGHT + 0.001, 1), Vector3(1, TILE_HEIGHT + 0.001, 0)], top)


## Faint mown patches, a shade either side of the lawn.
static func _patches(mb: MeshBuilder, rng: RandomNumberGenerator, top: Color, n: int) -> void:
	for i in range(n):
		var shade: Color = top.lightened(0.07) if i % 2 == 0 else top.darkened(0.06)
		_blob_patch(mb, rng, Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8)), rng.randf_range(0.1, 0.16), shade, 0.002)


## An irregular flat patch: a star-shaped polygon round `centre`.
static func _blob_patch(mb: MeshBuilder, rng: RandomNumberGenerator, centre: Vector2, radius: float, colour: Color, lift: float) -> void:
	var points: Array = []
	var sides: int = 9
	for i in range(sides):
		var a: float = TAU * float(i) / float(sides)
		var r: float = radius * rng.randf_range(0.7, 1.15)
		var x: float = clampf(centre.x + cos(a) * r, 0.02, 0.98)
		var z: float = clampf(centre.y + sin(a) * r, 0.02, 0.98)
		points.append(Vector3(x, TILE_HEIGHT + lift, z))
	_flat(mb, points, colour, Vector3(centre.x, TILE_HEIGHT + lift, centre.y))


static func _pebble(mb: MeshBuilder, rng: RandomNumberGenerator, at: Vector2) -> void:
	var s: float = rng.randf_range(0.025, 0.045)
	mb.add_blob(Vector3(at.x, TILE_HEIGHT + s * 0.3, at.y), Vector3(s, s * 0.55, s * 0.8), 2, 5, PEBBLE)


## A tuft of grass blades leaning out from one spot.
static func _tuft(mb: MeshBuilder, rng: RandomNumberGenerator, at: Vector2, blades: int, low: float, high: float) -> void:
	for i in range(blades):
		var a: float = TAU * float(i) / float(blades) + rng.randf_range(-0.4, 0.4)
		var tall: float = rng.randf_range(low, high)
		var lean: float = tall * rng.randf_range(0.18, 0.4)
		var base := Vector3(at.x + cos(a) * 0.012, TILE_HEIGHT, at.y + sin(a) * 0.012)
		# Kept inside the tile: a blade leaning over the edge would poke into
		# the neighbouring tile, and a lawn has to tile cleanly.
		var tip := Vector3(clampf(at.x + cos(a) * lean, 0.03, 0.97), TILE_HEIGHT + tall,
			clampf(at.y + sin(a) * lean, 0.03, 0.97))
		var colour: Color = BLADE_DARK.lerp(BLADE_LIGHT, rng.randf())
		_blade(mb, base, tip, maxf(0.034, tall * 0.2), colour)


## Low leaves under a flower bed, so it reads as planted, not as lawn.
static func _ground_cover(mb: MeshBuilder, rng: RandomNumberGenerator, n: int) -> void:
	for p in _grid_spots(3, 0.17):
		for i in range(3):
			var a: float = TAU * float(i) / 3.0 + rng.randf_range(0.0, 1.0)
			var tip := Vector3(p.x + cos(a) * 0.12, TILE_HEIGHT + 0.05, p.y + sin(a) * 0.12)
			_leaf(mb, Vector3(p.x, TILE_HEIGHT + 0.01, p.y), tip, 0.06, LEAF.lerp(BLADE_DARK, rng.randf() * 0.5))


## A flower: a stem, and a flat ring of petals facing the sky, with an eye.
static func _flower(mb: MeshBuilder, at: Vector2, tall: float, petals: Color, radius: float, count: int) -> void:
	var top := Vector3(at.x, TILE_HEIGHT + tall, at.y)
	mb.add_limb(Vector3(at.x, TILE_HEIGHT, at.y), top, 0.008, 0.006, 3, BLADE_DARK)
	for i in range(count):
		var a0: float = TAU * (float(i) - 0.32) / float(count)
		var a1: float = TAU * (float(i) + 0.32) / float(count)
		var am: float = TAU * float(i) / float(count)
		_flat(mb, [top + Vector3(0, 0.002, 0),
			top + Vector3(cos(a0) * radius * 0.55, 0.004, sin(a0) * radius * 0.55),
			top + Vector3(cos(am) * radius, 0.006, sin(am) * radius),
			top + Vector3(cos(a1) * radius * 0.55, 0.004, sin(a1) * radius * 0.55)], petals)
	mb.add_blob(top + Vector3(0, 0.01, 0), Vector3(radius * 0.32, radius * 0.22, radius * 0.32), 2, 5, EYE)
	_leaf(mb, Vector3(at.x, TILE_HEIGHT + tall * 0.25, at.y), Vector3(at.x + radius, TILE_HEIGHT + tall * 0.45, at.y + radius * 0.4), 0.03, BLADE)


## A lupin spike: purple bells stacked up a stem, narrowing to the tip.
static func _lupin(mb: MeshBuilder, at: Vector2, tall: float) -> void:
	var base := Vector3(at.x, TILE_HEIGHT, at.y)
	mb.add_limb(base, base + Vector3(0, tall, 0), 0.01, 0.007, 3, BLADE_DARK)
	var bells: int = 5
	for i in range(bells):
		var t: float = float(i) / float(bells - 1)
		var y: float = tall * (0.45 + 0.5 * t)
		var r: float = lerpf(0.06, 0.026, t)
		mb.add_blob(base + Vector3(0, y, 0), Vector3(r, r * 1.3, r), 2, 5, LUPIN.lerp(LUPIN_LIGHT, t))
	for side in [-1.0, 1.0]:
		_leaf(mb, base + Vector3(0, 0.02, 0), base + Vector3(side * 0.09, 0.07, 0.03), 0.04, BLADE)


static func _bush(mb: MeshBuilder, at: Vector3, size: float) -> void:
	mb.add_blob(at + Vector3(0, size * 0.55, 0), Vector3(size, size * 0.7, size), 2, 6, LEAF)
	mb.add_blob(at + Vector3(size * 0.25, size * 0.75, -size * 0.2), Vector3(size * 0.6, size * 0.5, size * 0.6), 2, 5, BLADE_DARK)


static func _rock(mb: MeshBuilder, at: Vector3, size: Vector3) -> void:
	mb.add_blob(at + Vector3(0, size.y * 0.55, 0), size, 2, 6, ROCK)
	mb.add_blob(at + Vector3(size.x * 0.15, size.y * 0.95, -size.z * 0.1), size * Vector3(0.6, 0.35, 0.6), 2, 5, ROCK.lightened(0.08))


# --- props ---------------------------------------------------------------------------

## A slatted park bench, two tiles long, facing +z.
static func _bench(mb: MeshBuilder, w: float, d: float) -> void:
	var wood := Color("8a6239")
	var dark := Color("5a3d24")
	mb.surface_style = TavernMaterials.Surface.WOOD
	for x in [0.25, w - 0.33]:
		mb.add_box(Vector3(x, 0.0, 0.32), Vector3(0.08, 0.32, 0.08), dark)
		mb.add_box(Vector3(x, 0.0, 0.62), Vector3(0.08, 0.32, 0.08), dark)
		mb.add_box(Vector3(x, 0.32, 0.26), Vector3(0.08, 0.38, 0.06), dark)
		mb.add_box(Vector3(x - 0.02, 0.44, 0.3), Vector3(0.12, 0.04, 0.42), dark)
	for i in range(3):
		mb.add_box(Vector3(0.2, 0.32, 0.36 + 0.105 * i), Vector3(w - 0.4, 0.04, 0.09), wood.lightened(0.04 * float(i % 2)))
	for i in range(2):
		mb.add_box(Vector3(0.2, 0.46 + 0.13 * i, 0.27), Vector3(w - 0.4, 0.09, 0.035), wood)


## A broad leafy tree: a short trunk under three faceted crowns.
static func _round_tree(mb: MeshBuilder) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	mb.add_cylinder(Vector3(0.5, 0.0, 0.5), 0.12, 0.08, 0.95, 6, Color("5e3f25"))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_blob(Vector3(0.5, 1.25, 0.5), Vector3(0.62, 0.48, 0.62), 3, 7, Color("4f8a30"))
	mb.add_blob(Vector3(0.24, 1.1, 0.62), Vector3(0.36, 0.3, 0.36), 2, 6, Color("5d9a37"))
	mb.add_blob(Vector3(0.72, 1.5, 0.4), Vector3(0.38, 0.32, 0.38), 2, 6, Color("6aa83e"))


## A pine: a trunk and three stacked faceted cones.
static func _pine(mb: MeshBuilder) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	mb.add_cylinder(Vector3(0.5, 0.0, 0.5), 0.1, 0.07, 0.5, 6, Color("5e3f25"))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	var tiers: Array = [[0.4, 0.56, 0.7, Color("3f7a32")], [0.85, 0.46, 0.62, Color("468636")], [1.27, 0.34, 0.55, Color("4f913b")]]
	for t in tiers:
		mb.add_cone(Vector3(0.5, t[0], 0.5), t[1], t[2], 7, t[3])


## A lantern on a post, for paths after dark: lit glass between a dark cap
## and base, hanging from an arm.
static func _lantern_post(mb: MeshBuilder) -> void:
	var iron := Color("2f2c28")
	mb.surface_style = TavernMaterials.Surface.STONE
	mb.add_box(Vector3(0.36, 0.0, 0.36), Vector3(0.28, 0.16, 0.28), Color("8e8a80"))
	mb.surface_style = TavernMaterials.Surface.WOOD
	mb.add_box(Vector3(0.45, 0.16, 0.45), Vector3(0.1, 1.5, 0.1), Color("5a3d24"))
	mb.add_box(Vector3(0.45, 1.56, 0.47), Vector3(0.42, 0.07, 0.06), Color("5a3d24"))
	mb.surface_style = TavernMaterials.Surface.METAL
	mb.add_box(Vector3(0.815, 1.5, 0.495), Vector3(0.02, 0.06, 0.02), iron)
	mb.add_box(Vector3(0.73, 1.26, 0.41), Vector3(0.18, 0.03, 0.18), iron)
	mb.add_cone(Vector3(0.82, 1.47, 0.5), 0.13, 0.07, 4, iron)
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_box(Vector3(0.75, 1.29, 0.43), Vector3(0.14, 0.18, 0.14), Color("ffd27a"))


# --- geometry helpers -------------------------------------------------------------

## A flat polygon facing up, fanned from `centre` (or from its first point).
## Every triangle is checked to face the sky whichever way the points were
## listed: a surface wound the other way simply vanishes from above.
static func _flat(mb: MeshBuilder, points: Array, colour: Color, centre: Variant = null) -> void:
	var n: int = points.size()
	if centre == null:
		for i in range(1, n - 1):
			_up_tri(mb, points[0], points[i], points[i + 1], colour)
	else:
		for i in range(n):
			_up_tri(mb, centre, points[i], points[(i + 1) % n], colour)


## MeshBuilder shows a triangle from the side its (b - a) x (c - a) normal
## points to; this one always points up.
static func _up_tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	if (b - a).cross(c - a).y >= 0.0:
		mb.add_tri(a, b, c, colour)
	else:
		mb.add_tri(a, c, b, colour)


## A grass blade: one triangle, seen from both sides.
static func _blade(mb: MeshBuilder, base: Vector3, tip: Vector3, width: float, colour: Color) -> void:
	var along: Vector3 = Vector3(tip.x - base.x, 0, tip.z - base.z)
	var across: Vector3 = Vector3(-along.z, 0, along.x).normalized() if along.length() > 0.001 else Vector3.RIGHT
	var a: Vector3 = base - across * width * 0.5
	var b: Vector3 = base + across * width * 0.5
	mb.add_tri(a, b, tip, colour)
	mb.add_tri(b, a, tip, colour.darkened(0.08))


## A leaf: a narrow two-sided diamond from `base` to `tip`.
static func _leaf(mb: MeshBuilder, base: Vector3, tip: Vector3, width: float, colour: Color) -> void:
	var along: Vector3 = tip - base
	var flat: Vector3 = Vector3(along.x, 0, along.z)
	var across: Vector3 = Vector3(-flat.z, 0, flat.x).normalized() * width if flat.length() > 0.001 else Vector3.RIGHT * width
	var mid: Vector3 = base + along * 0.45
	for side in [across, -across]:
		mb.add_tri(base, mid + side, tip, colour)
		mb.add_tri(base, tip, mid + side, colour.darkened(0.1))


static func _grid_spots(n: int, margin: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for row in range(n):
		for col in range(n):
			var x: float = margin + (1.0 - 2.0 * margin) * float(col) / float(n - 1)
			var z: float = margin + (1.0 - 2.0 * margin) * float(row) / float(n - 1)
			out.append(Vector2(x, z))
	return out


static func _spot(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(rng.randf_range(0.12, 0.88), rng.randf_range(0.12, 0.88))


static func _jitter(rng: RandomNumberGenerator, amount: float) -> Vector2:
	return Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))
