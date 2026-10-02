class_name TerrainMeshBuilder
extends RefCounted

## Turns a TerrainGrid into low-poly 3D terrain.
##
## The grid already knows where water, paths, rock and forest are -- that work is
## shared with the 2D menu backdrop. What this adds is elevation, and the key
## trick is that height is *carved by* the grid rather than generated
## independently: vertices touching a water cell get pushed below the waterline,
## then the whole field is smoothed, so the rivers the grid drew as winding noise
## bands become actual valleys with sloped banks. Generating height separately
## would leave rivers running up hillsides.
##
## Geometry is deliberately faceted: every tile is two triangles with their own
## face normals, and colour lives in the vertex stream. One mesh, one material,
## one draw call for the whole landscape.

## One grid cell is one world unit.
const TILE: float = 1.0

const SEED_HEIGHT: int = 9000
const HEIGHT_FREQ: float = 0.028
const HEIGHT_SCALE: float = 4.2

## Waterline, and how far below it a riverbed sits.
const WATER_LEVEL: float = -0.35
const WATER_DEPTH: float = 0.62
## Passes of neighbour-averaging. This is what turns carved water cells into
## sloped banks instead of vertical shafts.
const SMOOTH_PASSES: int = 2

const COLOR_GRASS := Color("4b5d32")
const COLOR_GRASS_DRY := Color("6a6840")
const COLOR_FOREST_FLOOR := Color("3d4a2b")
const COLOR_PATH := Color("887048")
const COLOR_DIRT := Color("685136")
const COLOR_ROCK := Color("746f60")
const COLOR_RIVERBED := Color("544932")

var grid: TerrainGrid
var vcols: int = 0
var vrows: int = 0
## The buildable plot, levelled flat. Empty means no plot.
var plot: Rect2i = Rect2i()
## Height the plot was levelled to. Everything built sits on this plane.
var plot_height: float = 0.0
## Corner heights, (cols+1) x (rows+1), indexed vy * vcols + vx. Tiles share
## corners so the surface is continuous.
var heights: PackedFloat32Array


func build_from(p_grid: TerrainGrid, p_plot: Rect2i = Rect2i()) -> void:
	grid = p_grid
	plot = p_plot
	vcols = grid.cols + 1
	vrows = grid.rows + 1
	_generate_heights()
	if plot.size.x > 0 and plot.size.y > 0:
		_flatten_plot()


func _generate_heights() -> void:
	heights = PackedFloat32Array()
	heights.resize(vcols * vrows)

	for vy in range(vrows):
		for vx in range(vcols):
			var n: float = ValueNoise.fbm(
				float(vx) * HEIGHT_FREQ, float(vy) * HEIGHT_FREQ, grid.seed_value + SEED_HEIGHT, 3
			)
			heights[vy * vcols + vx] = (n - 0.5) * HEIGHT_SCALE

	# A corner is wet if any tile touching it is water.
	var wet := PackedByteArray()
	wet.resize(vcols * vrows)
	for vy in range(vrows):
		for vx in range(vcols):
			var is_wet: bool = (
				grid.cell_at(vx - 1, vy - 1) == TerrainGrid.Cell.WATER
				or grid.cell_at(vx, vy - 1) == TerrainGrid.Cell.WATER
				or grid.cell_at(vx - 1, vy) == TerrainGrid.Cell.WATER
				or grid.cell_at(vx, vy) == TerrainGrid.Cell.WATER
			)
			wet[vy * vcols + vx] = 1 if is_wet else 0

	_carve_water(wet)
	for p in range(SMOOTH_PASSES):
		_smooth()
		# Re-carve after each smoothing pass, otherwise averaging with the
		# surrounding land lifts the riverbed back above the waterline.
		_carve_water(wet)


## Level the buildable plot and ease the surrounding ground into it.
##
## Placement assumes a single flat plane, and a tavern on a lumpy heightfield
## would need per-tile height handling for every wall and table -- a lot of
## complexity to buy nothing, since the player flattens a building site anyway.
## The falloff ring matters as much as the levelling: without it the plot sits
## on a mesa with vertical sides.
const PLOT_FALLOFF: float = 6.0

func _flatten_plot() -> void:
	# Level to the average of the region, so the plot settles into the landscape
	# rather than cutting or filling more than it has to.
	var total: float = 0.0
	var count: int = 0
	for vy in range(plot.position.y, plot.end.y + 1):
		for vx in range(plot.position.x, plot.end.x + 1):
			if vx < 0 or vy < 0 or vx >= vcols or vy >= vrows:
				continue
			total += heights[vy * vcols + vx]
			count += 1
	if count == 0:
		return
	plot_height = total / float(count)

	for vy in range(vrows):
		for vx in range(vcols):
			var d: float = _distance_outside_plot(vx, vy)
			if d > PLOT_FALLOFF:
				continue
			# 1.0 inside the plot, easing to 0.0 at the edge of the falloff ring.
			var t: float = 1.0 - smoothstep(0.0, PLOT_FALLOFF, d)
			var i: int = vy * vcols + vx
			heights[i] = lerpf(heights[i], plot_height, t)


func _distance_outside_plot(vx: int, vy: int) -> float:
	var dx: float = maxf(maxf(float(plot.position.x - vx), 0.0), float(vx - plot.end.x))
	var dy: float = maxf(maxf(float(plot.position.y - vy), 0.0), float(vy - plot.end.y))
	return Vector2(dx, dy).length()


func _carve_water(wet: PackedByteArray) -> void:
	var bed: float = WATER_LEVEL - WATER_DEPTH
	for i in range(heights.size()):
		if wet[i] == 1:
			heights[i] = minf(heights[i], bed)


func _smooth() -> void:
	var out := PackedFloat32Array()
	out.resize(heights.size())
	for vy in range(vrows):
		for vx in range(vcols):
			var total: float = 0.0
			var count: int = 0
			for d in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var nx: int = vx + d.x
				var ny: int = vy + d.y
				if nx < 0 or ny < 0 or nx >= vcols or ny >= vrows:
					continue
				total += heights[ny * vcols + nx]
				count += 1
			out[vy * vcols + vx] = total / float(count)
	heights = out


func height_at_corner(vx: int, vy: int) -> float:
	var cx: int = clampi(vx, 0, vcols - 1)
	var cy: int = clampi(vy, 0, vrows - 1)
	return heights[cy * vcols + cx]


## Bilinear height sample in world space. Used to sit trees and the tile cursor
## on the surface.
func sample_height(world_x: float, world_z: float) -> float:
	var fx: float = clampf(world_x / TILE, 0.0, float(vcols - 1) - 0.001)
	var fz: float = clampf(world_z / TILE, 0.0, float(vrows - 1) - 0.001)
	var x0: int = int(fx)
	var z0: int = int(fz)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)

	var h00: float = height_at_corner(x0, z0)
	var h10: float = height_at_corner(x0 + 1, z0)
	var h01: float = height_at_corner(x0, z0 + 1)
	var h11: float = height_at_corner(x0 + 1, z0 + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _tile_color(x: int, y: int) -> Color:
	var i: int = y * grid.cols + x
	var base: Color
	match grid.cells[i]:
		TerrainGrid.Cell.WATER:
			base = COLOR_RIVERBED
		TerrainGrid.Cell.TREE:
			base = COLOR_FOREST_FLOOR
		TerrainGrid.Cell.GRASS:
			# Meadow colour follows broad patches, so the construction grid does
			# not compete visually with the room, furniture and moving workers.
			var patch: float = ValueNoise.value_noise(float(x) * 0.095, float(y) * 0.095, grid.seed_value + 4242)
			base = COLOR_GRASS.lerp(COLOR_GRASS_DRY, smoothstep(0.25, 0.85, patch) * 0.5)
		TerrainGrid.Cell.ROCK:
			base = COLOR_ROCK
		_:
			base = COLOR_PATH if (grid.water_flags[i] & TerrainGrid.FLAG_PATH) else COLOR_DIRT

	# Keep a little grain, but most variation spans several tiles. Independent
	# high-contrast tile colours made even level grass look like a checkerboard.
	var broad: float = ValueNoise.value_noise(float(x) * 0.16, float(y) * 0.16, grid.seed_value + 4243)
	var grain: float = ValueNoise.hash2(x, y, grid.seed_value + 4244)
	var j: float = 0.955 + broad * 0.06 + grain * 0.03
	return Color(base.r * j, base.g * j, base.b * j)


## Build the ground surface. Returns null for an empty grid.
func build_terrain_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	for y in range(grid.rows):
		for x in range(grid.cols):
			var fx: float = float(x) * TILE
			var fz: float = float(y) * TILE
			var v00 := Vector3(fx, height_at_corner(x, y), fz)
			var v10 := Vector3(fx + TILE, height_at_corner(x + 1, y), fz)
			var v11 := Vector3(fx + TILE, height_at_corner(x + 1, y + 1), fz + TILE)
			var v01 := Vector3(fx, height_at_corner(x, y + 1), fz + TILE)
			# Wound so the face normal points up; see MeshBuilder.add_tri.
			mb.add_quad(v00, v01, v11, v10, _tile_color(x, y))
	return mb.commit()


## Build the water surface as a flat quad over each water tile, rather than one
## plane across the whole map -- so a dip in the terrain elsewhere does not
## silently fill with water.
func build_water_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var col := Color(0.15, 0.30, 0.32, 0.78)
	for y in range(grid.rows):
		for x in range(grid.cols):
			var near_water: bool = grid.cell_at(x, y) == TerrainGrid.Cell.WATER
			for offset in TerrainGrid.NEIGHBOURS:
				near_water = near_water or grid.cell_at(x + offset.x, y + offset.y) == TerrainGrid.Cell.WATER
			# Extend only into neighbouring low banks. The shader clips this
			# fringe to the actual heightfield; unrelated depressions stay dry.
			if not near_water or plot.has_point(Vector2i(x, y)):
				continue
			if minf(minf(height_at_corner(x, y), height_at_corner(x + 1, y)), minf(height_at_corner(x, y + 1), height_at_corner(x + 1, y + 1))) >= WATER_LEVEL:
				continue
			var fx: float = float(x) * TILE
			var fz: float = float(y) * TILE
			mb.add_quad(
				Vector3(fx, WATER_LEVEL, fz),
				Vector3(fx, WATER_LEVEL, fz + TILE),
				Vector3(fx + TILE, WATER_LEVEL, fz + TILE),
				Vector3(fx + TILE, WATER_LEVEL, fz),
				col
			)
	return mb.commit()


## Corner-aligned linear texture for shore depth, independent of scene depth
## buffers so it also works in Compatibility and at low graphics settings.
func water_height_texture() -> ImageTexture:
	var image := Image.create(vcols, vrows, false, Image.FORMAT_RF)
	for z in range(vrows):
		for x in range(vcols):
			image.set_pixel(x, z, Color(height_at_corner(x, z), 0, 0))
	return ImageTexture.create_from_image(image)


## Centre of the map in world space, for the camera to start looking at.
func world_centre() -> Vector3:
	var cx: float = float(grid.cols) * TILE * 0.5
	var cz: float = float(grid.rows) * TILE * 0.5
	return Vector3(cx, sample_height(cx, cz), cz)
