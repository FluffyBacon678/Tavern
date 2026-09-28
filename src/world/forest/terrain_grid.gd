class_name TerrainGrid
extends RefCounted

## The forest's cell grid: what each tile is, and which sprite variant it wears.
##
## Ported from ForestFirewallpaper's rebuildGrid(). Generation is a single pass
## of layered noise -- water first (ponds as blobs, rivers as a narrow noise
## band), then dirt paths, then vegetation modulated by two independent biome
## fields so the forest gets clearings and dense pockets instead of uniform
## scatter -- followed by a second pass that flags shoreline cells.
##
## Everything is stored in packed arrays indexed y * cols + x. This grid is the
## same shape the tavern's own tile map will need later, so the generator and
## the renderer that consumes it are both reusable beyond the menu backdrop.

enum Cell {
	DIRT = 0,
	GRASS = 1,
	TREE = 2,
	WATER = 3,
	ROCK = 4,
}

## Bit flags packed into `water_flags`, matching the original's layout.
const FLAG_SHORELINE: int = 0x10  ## water cell touching vegetation: tints green
const FLAG_PATH: int = 0x80       ## dirt cell that is part of a trail

## Noise channels are offset from the world seed so each feature varies
## independently. These offsets are the original's and are kept verbatim.
const SEED_TREE_BIOME: int = 1000
const SEED_GRASS_BIOME: int = 2000
const SEED_WATER: int = 5000
const SEED_PATH: int = 7000
const SEED_RIVER: int = 8000

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

var cols: int = 0
var rows: int = 0
var seed_value: int = 0

var cells: PackedByteArray
var tree_variant: PackedByteArray
var grass_variant: PackedByteArray
var water_flags: PackedByteArray
## Sub-cell offset in pixels, so sprites do not sit on a visible lattice.
var jitter_x: PackedByteArray
var jitter_y: PackedByteArray
## 0..1 sapling to mature. Established forest starts mostly grown.
var tree_growth: PackedFloat32Array


func index(x: int, y: int) -> int:
	return y * cols + x


func cell_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return Cell.DIRT
	return cells[index(x, y)]


## Generate a forest. `rng` seeds the per-cell rolls (variant, jitter, growth);
## `seed_value` seeds the coherent noise that shapes biomes, water and paths.
## They are separate so the same landscape can be re-dressed with different
## vegetation, and so a given seed reproduces exactly.
##
## `ground` is optional and purely 2D: ground-cover variants only mean anything
## to the sprite renderer. The 3D world passes null and the grid stays usable,
## which is the whole reason species selection lives in TreeSpecies rather than
## in either renderer.
func generate(p_cols: int, p_rows: int, p_seed: int, config: ForestConfig, rng: RandomNumberGenerator, ground: GroundAtlas = null) -> void:
	cols = p_cols
	rows = p_rows
	seed_value = p_seed

	var n: int = cols * rows
	cells = PackedByteArray()
	cells.resize(n)
	tree_variant = PackedByteArray()
	tree_variant.resize(n)
	grass_variant = PackedByteArray()
	grass_variant.resize(n)
	water_flags = PackedByteArray()
	water_flags.resize(n)
	jitter_x = PackedByteArray()
	jitter_x.resize(n)
	jitter_y = PackedByteArray()
	jitter_y.resize(n)
	tree_growth = PackedFloat32Array()
	tree_growth.resize(n)

	var jitter_range: int = maxi(1, int(float(config.cell_size) * 0.25))

	for y in range(rows):
		for x in range(cols):
			var i: int = y * cols + x

			# Stored biased into a byte; read back as value - 128.
			jitter_x[i] = clampi(rng.randi_range(-jitter_range, jitter_range) + 128, 0, 255)
			jitter_y[i] = clampi(rng.randi_range(-jitter_range, jitter_range) + 128, 0, 255)

			# --- Water: broad noise blobs form ponds, a narrow band forms rivers ---
			var water_n: float = ValueNoise.fbm(
				float(x) * config.water_freq, float(y) * config.water_freq, seed_value + SEED_WATER, 3
			)
			var is_pond: bool = water_n > config.water_threshold
			if is_pond or _is_river(x, y, config):
				cells[i] = Cell.WATER
				continue

			# --- Path: a narrow band on its own channel winds dirt trails through ---
			if config.show_paths and _is_path(x, y, config):
				cells[i] = Cell.DIRT
				water_flags[i] |= FLAG_PATH
				continue

			# --- Vegetation, modulated by two independent biome fields ---
			var t_biome: float = ValueNoise.fbm(
				float(x) * config.tree_biome_freq, float(y) * config.tree_biome_freq, seed_value + SEED_TREE_BIOME, 3
			)
			var g_biome: float = ValueNoise.fbm(
				float(x) * config.grass_biome_freq, float(y) * config.grass_biome_freq, seed_value + SEED_GRASS_BIOME, 2
			)
			# Biome scales density roughly 0.2x to 1.8x, which is what carves
			# clearings and dense pockets out of an otherwise even scatter.
			var local_tree: float = config.tree_density * (0.20 + t_biome * 1.60)
			var local_grass: float = config.grass_density * (0.40 + g_biome * 1.10)

			if rng.randf() < local_tree:
				cells[i] = Cell.TREE
				tree_variant[i] = TreeSpecies.pick_variant(rng)
				if ground != null:
					grass_variant[i] = ground.pick_variant(rng)
				tree_growth[i] = 0.7 + rng.randf() * 0.3
			elif rng.randf() < local_grass:
				cells[i] = Cell.GRASS
				if ground != null:
					grass_variant[i] = ground.pick_variant(rng)
			elif config.show_rocks and rng.randf() < config.rock_density:
				cells[i] = Cell.ROCK
			else:
				cells[i] = Cell.DIRT

	_flag_shorelines()


## Water touching a tree gets a reflection tint, so shorelines pick up the green
## of the canopy overhanging them instead of cutting a hard blue edge.
func _flag_shorelines() -> void:
	for y in range(rows):
		for x in range(cols):
			var i: int = y * cols + x
			if cells[i] != Cell.WATER:
				continue
			for d in NEIGHBOURS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or nx >= cols or ny < 0 or ny >= rows:
					continue
				if cells[index(nx, ny)] == Cell.TREE:
					water_flags[i] |= FLAG_SHORELINE
					break


func _is_river(x: int, y: int, config: ForestConfig) -> bool:
	if not config.show_rivers:
		return false
	var n: float = ValueNoise.fbm(
		float(x) * config.river_freq, float(y) * config.river_freq, seed_value + SEED_RIVER, 2
	)
	return n > config.river_band_low and n < config.river_band_high


func _is_path(x: int, y: int, config: ForestConfig) -> bool:
	var n: float = ValueNoise.fbm(
		float(x) * config.path_freq, float(y) * config.path_freq, seed_value + SEED_PATH, 2
	)
	return n > config.path_band_low and n < config.path_band_high


func jitter_offset(i: int) -> Vector2:
	return Vector2(float(int(jitter_x[i]) - 128), float(int(jitter_y[i]) - 128))
