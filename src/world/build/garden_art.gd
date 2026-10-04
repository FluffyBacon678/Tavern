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
const TULIP_PINK := Color("e27aa0")
const ROSE_RED := Color("b8323d")
const ROSE_PINK := Color("e48aa6")
const LAVENDER := Color("8e78c8")
const LAVENDER_LEAF := Color("7d9466")
const SUNFLOWER := Color("f2b72e")
const SUNFLOWER_EYE := Color("5a3a1c")
const KERB := Color("8c877d")


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
		&"stone_path", &"garden_path":
			# On its own (menu, placing ghost): edged all round.
			path(mb, id, 0, 0)
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
		&"bed_tulips":
			_base(mb, BED)
			_ground_cover(mb, rng, 8)
			var tulips: Array[Color] = [PETAL_RED, PETAL_YELLOW, TULIP_PINK]
			var k: int = 0
			for p in _grid_spots(3, 0.17):
				_tulip(mb, p + _jitter(rng, 0.04), 0.15 + rng.randf() * 0.05, tulips[k % tulips.size()])
				k += 1
		&"bed_lavender":
			_base(mb, BED)
			for p in [Vector2(0.27, 0.27), Vector2(0.73, 0.3), Vector2(0.3, 0.72), Vector2(0.72, 0.72)]:
				_lavender(mb, rng, p + _jitter(rng, 0.03))
		&"bed_roses":
			_base(mb, BED)
			_ground_cover(mb, rng, 6)
			_rose_bush(mb, rng, Vector2(0.3, 0.3), ROSE_RED)
			_rose_bush(mb, rng, Vector2(0.7, 0.36), ROSE_PINK)
			_rose_bush(mb, rng, Vector2(0.45, 0.72), ROSE_RED)
		&"bed_sunflowers":
			_base(mb, BED)
			_ground_cover(mb, rng, 6)
			for p in [Vector2(0.26, 0.26), Vector2(0.72, 0.3), Vector2(0.3, 0.72), Vector2(0.74, 0.74)]:
				_sunflower(mb, p + _jitter(rng, 0.03), 0.48 + rng.randf() * 0.12)
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
		&"bar_table":
			_bar(mb, w)
		&"parasol_table":
			_parasol_table(mb, w)
		&"garden_fence":
			# Shown on its own (menu, placing ghost) as a straight run.
			fence(mb, 2 | 8, main, accent)


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
static func _flower(mb: MeshBuilder, at: Vector2, tall: float, petals: Color, radius: float, count: int,
		eye: Color = EYE) -> void:
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
	mb.add_blob(top + Vector3(0, 0.01, 0), Vector3(radius * 0.32, radius * 0.22, radius * 0.32), 2, 5, eye)
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


## A tulip: a stem, two strap leaves, and a closed cup of a flower.
static func _tulip(mb: MeshBuilder, at: Vector2, tall: float, colour: Color) -> void:
	var base := Vector3(at.x, TILE_HEIGHT, at.y)
	var top: Vector3 = base + Vector3(0, tall, 0)
	mb.add_limb(base, top, 0.008, 0.006, 3, BLADE_DARK)
	_leaf(mb, base + Vector3(0, 0.01, 0), base + Vector3(0.05, tall * 0.55, 0.02), 0.035, BLADE)
	_leaf(mb, base + Vector3(0, 0.01, 0), base + Vector3(-0.04, tall * 0.45, -0.03), 0.03, BLADE)
	mb.add_blob(top + Vector3(0, 0.024, 0), Vector3(0.032, 0.045, 0.032), 2, 6, colour)
	mb.add_cone(top + Vector3(0, 0.05, 0), 0.025, 0.028, 5, colour.lightened(0.12), false)


## A lavender clump: grey-green leaves and purple spikes fanning out.
static func _lavender(mb: MeshBuilder, rng: RandomNumberGenerator, at: Vector2) -> void:
	var base := Vector3(at.x, TILE_HEIGHT, at.y)
	mb.add_blob(base + Vector3(0, 0.03, 0), Vector3(0.1, 0.04, 0.1), 2, 6, LAVENDER_LEAF)
	for i in range(6):
		var a: float = TAU * float(i) / 6.0 + rng.randf_range(-0.3, 0.3)
		var lean: float = rng.randf_range(0.04, 0.09)
		var tip := Vector3(clampf(at.x + cos(a) * lean, 0.04, 0.96), TILE_HEIGHT + rng.randf_range(0.2, 0.3),
			clampf(at.y + sin(a) * lean, 0.04, 0.96))
		mb.add_limb(base + Vector3(0, 0.03, 0), tip, 0.005, 0.004, 3, LAVENDER_LEAF)
		mb.add_blob(tip.lerp(base, 0.14), Vector3(0.017, 0.045, 0.017), 2, 4, LAVENDER.lerp(Color.WHITE, rng.randf() * 0.15))


## A rose bush: a leafy mound dotted with blooms.
static func _rose_bush(mb: MeshBuilder, rng: RandomNumberGenerator, at: Vector2, colour: Color) -> void:
	var c := Vector3(at.x, TILE_HEIGHT, at.y)
	mb.add_blob(c + Vector3(0, 0.1, 0), Vector3(0.15, 0.11, 0.15), 2, 6, LEAF)
	mb.add_blob(c + Vector3(0.04, 0.16, -0.03), Vector3(0.1, 0.08, 0.1), 2, 5, BLADE_DARK)
	for i in range(6):
		var a: float = TAU * float(i) / 6.0 + rng.randf_range(-0.3, 0.3)
		var r: float = rng.randf_range(0.05, 0.11)
		var p: Vector3 = c + Vector3(cos(a) * r, 0.16 + rng.randf() * 0.06, sin(a) * r)
		mb.add_blob(p, Vector3(0.03, 0.024, 0.03), 2, 5, colour.lightened(rng.randf() * 0.1))


## A sunflower: a tall stem, broad leaves, and a big face turned to the sky.
static func _sunflower(mb: MeshBuilder, at: Vector2, tall: float) -> void:
	var base := Vector3(at.x, TILE_HEIGHT, at.y)
	_leaf(mb, base + Vector3(0, tall * 0.35, 0), base + Vector3(0.1, tall * 0.42, 0.04), 0.06, BLADE)
	_leaf(mb, base + Vector3(0, tall * 0.55, 0), base + Vector3(-0.09, tall * 0.6, -0.05), 0.055, BLADE)
	_flower(mb, at, tall, SUNFLOWER, 0.11, 12, SUNFLOWER_EYE)
	mb.add_blob(base + Vector3(0, tall + 0.012, 0), Vector3(0.05, 0.012, 0.05), 2, 6, SUNFLOWER_EYE)


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


# --- the bar and the garden table ------------------------------------------------

const STRIPE_YELLOW := Color("f0c63a")
const STRIPE_CREAM := Color("f4ecd8")
const STALL_WOOD := Color("8a6239")
const STALL_DARK := Color("5a3d24")
const STALL_TOP := Color("a77c4a")
const LEMON := Color("f2cf3b")


## A timber bar with brass taps, a foot rail and a bottle shelf. The two
## stock centres (x .5/1.5, z .5, y .95) stay clear; everything decorative is
## at the rear or below the counter. Same footprint and serving height.
static func _bar(mb: MeshBuilder, w: float) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	var dark := Color("513826")
	var oak := Color("805b3c")
	var brass := Color("bf9653")
	mb.add_box(Vector3(0.10, 0.02, 0.24), Vector3(w - 0.20, 0.87, 0.62), dark)
	# Framed inset panels, quieter than the old striped market canopy.
	for i in range(3):
		var panel_w: float = (w - 0.38) / 3.0
		mb.add_box(Vector3(0.16 + float(i) * (panel_w + 0.03), 0.20, 0.86),
			Vector3(panel_w, 0.56, 0.025), oak.lightened(0.025 * float(i)))
	mb.add_box(Vector3(0.08, 0.09, 0.85), Vector3(w - 0.16, 0.08, 0.06), dark)
	mb.add_box(Vector3(0.08, 0.80, 0.85), Vector3(w - 0.16, 0.08, 0.06), dark)
	mb.add_box(Vector3(0.03, 0.89, 0.18), Vector3(w - 0.06, 0.06, 0.77), STALL_TOP)
	# Rear posts and open shelf do not hide the counter from the guest side.
	for x in [0.06, w - 0.14]:
		mb.add_box(Vector3(x, 0.95, 0.04), Vector3(0.08, 0.51, 0.09), dark)
	mb.add_box(Vector3(0.06, 1.28, 0.03), Vector3(w - 0.12, 0.045, 0.18), oak)
	mb.add_box(Vector3(0.06, 1.43, 0.04), Vector3(w - 0.12, 0.04, 0.06), dark)
	mb.surface_style = TavernMaterials.Surface.METAL
	mb.add_limb(Vector3(0.18, 0.18, 0.95), Vector3(w - 0.18, 0.18, 0.95), 0.025, 0.025, 6, brass)
	for x in [0.24, w - 0.24]:
		mb.add_limb(Vector3(x, 0.18, 0.87), Vector3(x, 0.18, 0.95), 0.02, 0.02, 5, brass)
	# Twin taps in the central gap between the two sale piles.
	for x in [w * 0.5 - 0.09, w * 0.5 + 0.09]:
		mb.add_cylinder(Vector3(x, 0.95, 0.23), 0.025, 0.025, 0.23, 6, brass)
		mb.add_limb(Vector3(x, 1.13, 0.23), Vector3(x, 1.13, 0.33), 0.022, 0.022, 5, brass)
		mb.add_box(Vector3(x - 0.025, 1.15, 0.21), Vector3(0.05, 0.09, 0.04), dark)
	mb.surface_style = TavernMaterials.Surface.PLAIN
	for i in range(5):
		var x: float = 0.27 + float(i) * (w - 0.54) / 4.0
		var bottle := Color("426552") if i % 2 == 0 else Color("835537")
		var p := Vector3(x, 1.325, 0.12)
		mb.add_cylinder(p, 0.035, 0.035, 0.10, 6, bottle)
		mb.add_cylinder(p + Vector3(0, 0.10, 0), 0.035, 0.014, 0.035, 6, bottle)
		mb.add_cylinder(p + Vector3(0, 0.135, 0), 0.014, 0.014, 0.04, 6, bottle)
		mb.add_cone(p + Vector3(0, 0.175, 0), 0.017, 0.01, 6, brass)
	# A pewter tankard emblem identifies the bar from a distance.
	mb.surface_style = TavernMaterials.Surface.METAL
	mb.add_box(Vector3(w * 0.5 - 0.065, 0.40, 0.89), Vector3(0.13, 0.19, 0.02), brass)
	mb.add_box(Vector3(w * 0.5 + 0.065, 0.44, 0.89), Vector3(0.055, 0.025, 0.02), brass)
	mb.add_box(Vector3(w * 0.5 + 0.095, 0.44, 0.89), Vector3(0.025, 0.105, 0.02), brass)
	mb.add_box(Vector3(w * 0.5 + 0.065, 0.52, 0.89), Vector3(0.055, 0.025, 0.02), brass)
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.add_box(Vector3(w * 0.5 - 0.07, 0.57, 0.89), Vector3(0.14, 0.025, 0.025), STRIPE_CREAM)


## A table for the garden under a striped parasol. The pole stands between
## the two places, so a plate sits either side of it (each tile's centre, at
## 0.78) and the canopy shades both.
static func _parasol_table(mb: MeshBuilder, w: float) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	for x in [0.16, w - 0.23]:
		for z in [0.2, 0.73]:
			mb.add_box(Vector3(x, 0.0, z), Vector3(0.07, 0.72, 0.07), STALL_DARK)
	mb.add_box(Vector3(0.08, 0.72, 0.12), Vector3(w - 0.16, 0.06, 0.76), STALL_TOP)
	mb.surface_style = TavernMaterials.Surface.METAL
	var centre := Vector3(w * 0.5, 0.0, 0.5)
	mb.add_cylinder(centre, 0.03, 0.025, 1.9, 5, Color("e9e4d6"))
	mb.surface_style = TavernMaterials.Surface.PLAIN
	mb.surface_style = TavernMaterials.Surface.CLOTH
	var apex: Vector3 = centre + Vector3(0.0, 1.88, 0.0)
	var panels: int = 8
	var rim: Array = []
	for i in range(panels):
		var angle: float = TAU * float(i) / float(panels)
		rim.append(centre + Vector3(cos(angle) * 1.05, 1.56, sin(angle) * 0.74))
	for i in range(panels):
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i + 1) % panels]
		var colour: Color = STRIPE_YELLOW if i % 2 == 0 else STRIPE_CREAM
		_up_tri(mb, apex, a, b, colour)
		_down_tri(mb, apex, a, b, colour.darkened(0.25))
		_both_sides(mb, a, b, (a + b) * 0.5 + Vector3(0.0, -0.08, 0.0), colour)
	mb.surface_style = TavernMaterials.Surface.WOOD
	mb.add_cone(apex, 0.05, 0.08, 4, STALL_DARK)


## A low fence: a post in the middle of its tile and, toward each side with
## more fence, two rails and a picket -- so runs join and corners turn
## cleanly. `mask` bits: 1 north (-z), 2 east (+x), 4 south (+z), 8 west (-x).
static func fence(mb: MeshBuilder, mask: int, main: Color, accent: Color) -> void:
	mb.surface_style = TavernMaterials.Surface.WOOD
	mb.add_box(Vector3(0.45, 0.0, 0.45), Vector3(0.1, 0.6, 0.1), accent)
	mb.add_cone(Vector3(0.5, 0.6, 0.5), 0.075, 0.09, 4, accent)
	var sides: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for i in range(sides.size()):
		if mask & (1 << i) == 0:
			continue
		var dir: Vector2 = sides[i]
		var along_x: bool = dir.y == 0.0
		# From the post's face to the tile's edge.
		var lo: float = 0.55 if (dir.x > 0.0 or dir.y > 0.0) else 0.0
		for y in [0.17, 0.4]:
			if along_x:
				mb.add_box(Vector3(lo, y, 0.48), Vector3(0.45, 0.06, 0.04), main)
			else:
				mb.add_box(Vector3(0.48, y, lo), Vector3(0.04, 0.06, 0.45), main)
		var at: Vector2 = Vector2(0.5, 0.5) + dir * 0.27
		if along_x:
			mb.add_box(Vector3(at.x - 0.04, 0.04, 0.52), Vector3(0.08, 0.46, 0.03), main.lightened(0.06))
			mb.add_cone(Vector3(at.x, 0.5, 0.535), 0.05, 0.07, 4, main.lightened(0.06))
		else:
			mb.add_box(Vector3(0.52, 0.04, at.y - 0.04), Vector3(0.03, 0.46, 0.08), main.lightened(0.06))
			mb.add_cone(Vector3(0.535, 0.5, at.y), 0.05, 0.07, 4, main.lightened(0.06))


## A sloping sheet seen from both sides: the colour on top, darker beneath.
static func _canopy_quad(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	_up_tri(mb, a, b, c, colour)
	_up_tri(mb, a, c, d, colour)
	_down_tri(mb, a, b, c, colour.darkened(0.25))
	_down_tri(mb, a, c, d, colour.darkened(0.25))


## A hanging scallop, visible from in front and behind.
static func _both_sides(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	mb.add_tri(a, b, c, colour)
	mb.add_tri(a, c, b, colour.darkened(0.12))


# --- paths ----------------------------------------------------------------------

## A path tile drawn for its neighbours: open toward more path, and edged where
## it meets anything else -- a grass verge on a dirt path, kerb stones on a
## stone one. `mask` bits as for fences (1 north, 2 east, 4 south, 8 west);
## `variant` varies the detail, so a long path does not repeat.
static func path(mb: MeshBuilder, id: StringName, mask: int, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(id)) + variant * 7919 + mask * 104729
	mb.surface_style = TavernMaterials.Surface.PLAIN
	if id == &"stone_path":
		_stone_path(mb, rng)
		mb.surface_style = TavernMaterials.Surface.STONE
		for side in range(4):
			if mask & (1 << side) == 0:
				_kerb(mb, rng, side)
		mb.surface_style = TavernMaterials.Surface.PLAIN
		return
	_base(mb, DIRT, SOIL_DARK)
	for i in range(4):
		_blob_patch(mb, rng, Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8)), 0.07, DIRT_DARK, 0.003)
	# Cart ruts where the way runs straight on.
	var along_z: bool = mask & 5 != 0 and mask & 10 == 0
	var along_x: bool = mask & 10 != 0 and mask & 5 == 0
	if along_z or along_x:
		for at in [0.33, 0.67]:
			var a := Vector3(at - 0.03, TILE_HEIGHT + 0.004, 0.0) if along_z else Vector3(0.0, TILE_HEIGHT + 0.004, at - 0.03)
			var b := Vector3(at + 0.03, TILE_HEIGHT + 0.004, 1.0) if along_z else Vector3(1.0, TILE_HEIGHT + 0.004, at + 0.03)
			_flat(mb, [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)],
				DIRT_DARK.darkened(0.06))
	for i in range(5):
		_pebble(mb, rng, Vector2(rng.randf_range(0.18, 0.82), rng.randf_range(0.18, 0.82)))
	for side in range(4):
		if mask & (1 << side) == 0:
			_verge(mb, rng, side)


## A point on a tile from (along an edge, in from it), for one side.
static func _edge_point(side: int, u: float, v: float, y: float) -> Vector3:
	match side:
		0: return Vector3(u, y, v)
		1: return Vector3(1.0 - v, y, u)
		2: return Vector3(u, y, 1.0 - v)
	return Vector3(v, y, u)


## Grass coming down to a dirt path's edge, its inner line uneven, with tufts.
static func _verge(mb: MeshBuilder, rng: RandomNumberGenerator, side: int) -> void:
	var y: float = TILE_HEIGHT + 0.005 + 0.0006 * float(side)
	var steps: int = 6
	var depth: Array[float] = []
	for i in range(steps + 1):
		depth.append(rng.randf_range(0.09, 0.17))
	for i in range(steps):
		var u0: float = float(i) / float(steps)
		var u1: float = float(i + 1) / float(steps)
		var colour: Color = LAWN.darkened(0.04 + 0.05 * float(i % 2))
		_up_tri(mb, _edge_point(side, u0, 0.0, y), _edge_point(side, u1, 0.0, y), _edge_point(side, u1, depth[i + 1], y), colour)
		_up_tri(mb, _edge_point(side, u0, 0.0, y), _edge_point(side, u1, depth[i + 1], y), _edge_point(side, u0, depth[i], y), colour)
	for i in range(3):
		var p: Vector3 = _edge_point(side, rng.randf_range(0.12, 0.88), 0.05, 0.0)
		_tuft(mb, rng, Vector2(p.x, p.z), 3, 0.06, 0.11)


## Kerb stones along a stone path's edge.
static func _kerb(mb: MeshBuilder, rng: RandomNumberGenerator, side: int) -> void:
	for k in range(4):
		var u: float = 0.015 + 0.245 * float(k)
		var length: float = 0.23
		var depth: float = 0.07
		var height: float = 0.03 + rng.randf() * 0.008
		var colour: Color = KERB.darkened(rng.randf() * 0.12)
		var y: float = TILE_HEIGHT - 0.004
		match side:
			0: mb.add_box(Vector3(u, y, 0.0), Vector3(length, height, depth), colour)
			2: mb.add_box(Vector3(u, y, 1.0 - depth), Vector3(length, height, depth), colour)
			3: mb.add_box(Vector3(0.0, y, u), Vector3(depth, height, length), colour)
			_: mb.add_box(Vector3(1.0 - depth, y, u), Vector3(depth, height, length), colour)


# --- the stone path ---------------------------------------------------------------

## Flagstones in a bed of grit: the dearer path, and as quick underfoot as a
## laid floor. Stones stay inside the tile, so a path joins its neighbours.
static func _stone_path(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	_base(mb, Color("8a8478"), SOIL_DARK)
	var stones: Array = [
		Rect2(0.06, 0.06, 0.4, 0.38), Rect2(0.52, 0.06, 0.42, 0.26), Rect2(0.52, 0.38, 0.42, 0.28),
		Rect2(0.06, 0.5, 0.28, 0.44), Rect2(0.4, 0.72, 0.54, 0.22), Rect2(0.4, 0.5, 0.06, 0.16),
	]
	mb.surface_style = TavernMaterials.Surface.STONE
	for r in stones:
		var inset := Vector2(rng.randf_range(0.0, 0.015), rng.randf_range(0.0, 0.015))
		var shade: Color = Color("b3ada1").darkened(rng.randf() * 0.14)
		# Set a little into the grit, so a stone's underside is never on show.
		mb.add_box(Vector3(r.position.x + inset.x, TILE_HEIGHT - 0.004, r.position.y + inset.y),
			Vector3(r.size.x - inset.x * 2.0, 0.016 + rng.randf() * 0.006, r.size.y - inset.y * 2.0), shade)
	mb.surface_style = TavernMaterials.Surface.PLAIN


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


## The same, facing the ground: the underside of an awning or a parasol.
static func _down_tri(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	if (b - a).cross(c - a).y <= 0.0:
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
