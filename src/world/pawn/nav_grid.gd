class_name NavGrid
extends RefCounted

## Walkability and pathfinding over the tile grid.
##
## Wraps Godot's AStarGrid2D rather than hand-rolling A*: it is engine-side,
## handles diagonals and solid points natively, and is far faster than anything
## GDScript would manage over a 96x96 grid.
##
## Walkability has two independent sources and both matter:
##   * terrain -- water is impassable, everything else is not
##   * construction -- walls block, doors and furniture-on-floor do not
##
## `BuildGrid.blocks_movement()` is the authority for the second, which is why
## that method exists on the grid rather than being inferred from meshes here.

## Diagonal movement is allowed, but not through a corner gap between two solid
## tiles -- otherwise pawns slip diagonally between two walls that meet, which
## looks wrong and lets them leave a sealed room.
const DIAGONAL_MODE := AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES

var astar := AStarGrid2D.new()
var cols: int = 0
var rows: int = 0

## Seconds-per-tile multipliers. Deliberately a narrow spread: flooring should
## be worth laying, not compulsory.
const FLOOR_COST: float = 1.0
const PATH_COST: float = 1.12
const ROUGH_COST: float = 1.28

var _terrain: TerrainGrid
var _build: BuildGrid


func setup(terrain: TerrainGrid, build: BuildGrid) -> void:
	_terrain = terrain
	_build = build
	cols = terrain.cols
	rows = terrain.rows

	astar.region = Rect2i(0, 0, cols, rows)
	astar.cell_size = Vector2(TerrainMeshBuilder.TILE, TerrainMeshBuilder.TILE)
	astar.diagonal_mode = DIAGONAL_MODE
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	refresh_all()


## Recompute every tile. Cheap enough at this size to just do on a world rebuild.
func refresh_all() -> void:
	_floors_dirty = true
	for y in range(rows):
		for x in range(cols):
			var tile := Vector2i(x, y)
			astar.set_point_solid(tile, not is_walkable(tile))
			astar.set_point_weight_scale(tile, weight_at(tile))


## Recompute a small area, for when something is built or demolished.
func refresh_area(area: Rect2i) -> void:
	_floors_dirty = true
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var tile := Vector2i(x, y)
			if tile.x < 0 or tile.y < 0 or tile.x >= cols or tile.y >= rows:
				continue
			astar.set_point_solid(tile, not is_walkable(tile))
			astar.set_point_weight_scale(tile, weight_at(tile))


## How much slower than a laid floor this tile is to cross.
##
## Flooring had no mechanical effect at all until now -- it was a third of the
## opening spend and bought nothing but a colour. Making it quicker underfoot
## fixes that without forcing anyone's hand: a table out on the grass still
## works, it is just a longer walk to serve.
##
## Fed to A* as a weight *and* to the pawn as a speed, so staff both prefer laid
## floors and genuinely move faster on them. Weighting alone would route people
## over floors without rewarding them; speed alone would leave them cutting
## across the mud.
func cost_at(tile: Vector2i) -> float:
	if _build != null and _build.floor_index_at(tile) >= 0:
		# Each floor its own pace: 1.0 for the house floors, slower through a
		# flower bed or tall grass, so people keep to paths and lawns.
		var entry = _build.placements[_build.floor_index_at(tile)]
		return entry["def"].walk_cost * FLOOR_COST if entry != null else FLOOR_COST
	if _terrain != null and (_terrain.water_flags[_terrain.index(tile.x, tile.y)] & TerrainGrid.FLAG_PATH) != 0:
		return PATH_COST
	return ROUGH_COST


## The same figure in the form A* wants: 1.0 on the quickest ground.
func weight_at(tile: Vector2i) -> float:
	return cost_at(tile) / FLOOR_COST


## Every tile reachable on foot from `start`, treating `also_solid` as walls.
##
## Four-way on purpose. The pathfinder allows diagonals, but only past corners
## with nothing on them, so four-way is the cautious answer: anything it calls
## reachable really is. `also_solid` lets a caller ask about the tavern as it
## *will* be once the blueprints are built, which is the question a player needs
## answered at the moment they place one.
func reachable_from(start: Vector2i, also_solid: Dictionary = {}) -> Dictionary:
	var seen: Dictionary = {}
	if not is_walkable(start) or also_solid.has(start):
		return seen
	var frontier: Array[Vector2i] = [start]
	seen[start] = true
	while not frontier.is_empty():
		var tile: Vector2i = frontier.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = tile + step
			if seen.has(next) or also_solid.has(next) or not is_walkable(next):
				continue
			seen[next] = true
			frontier.append(next)
	return seen


func is_walkable(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= cols or tile.y >= rows:
		return false
	if _terrain.cell_at(tile.x, tile.y) == TerrainGrid.Cell.WATER:
		return false
	return not _build.blocks_movement(tile)


## Tile path from `from` to `to`, excluding the starting tile. Empty if there is
## no route. If the destination itself is solid, the nearest walkable neighbour
## is used instead -- a pawn told to go to a wall should walk up to it rather
## than refuse.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var goal: Vector2i = to
	if not is_walkable(goal):
		goal = _nearest_walkable(to)
		if goal == Vector2i(-1, -1):
			return []

	# A pawn can end up standing on a solid tile: it walks through a doorway and
	# a wall is finished under its feet the same instant. Pathing from a solid
	# point returns nothing, which would strand it permanently. So open the
	# start tile for the search and close it again afterwards -- the pawn is
	# allowed to walk *out* of somewhere it should not be.
	var start_was_solid: bool = not is_walkable(from)
	if start_was_solid:
		if from.x < 0 or from.y < 0 or from.x >= cols or from.y >= rows:
			return []
		astar.set_point_solid(from, false)

	var raw: Array[Vector2i] = astar.get_id_path(from, goal)

	if start_was_solid:
		astar.set_point_solid(from, true)

	if raw.size() <= 1:
		return []
	raw.remove_at(0)  # drop the tile the pawn is already standing on
	return raw


## Spiral outward for a walkable tile. Bounded, so an unreachable target in the
## middle of a lake fails fast instead of scanning the whole map.
func _nearest_walkable(around: Vector2i, max_radius: int = 6) -> Vector2i:
	for r in range(1, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				# Only the ring at this radius; inner rings were already checked.
				if absi(dx) != r and absi(dy) != r:
					continue
				var t: Vector2i = around + Vector2i(dx, dy)
				if is_walkable(t):
					return t
	return Vector2i(-1, -1)


## The walkable tile next to `target` that is closest to `from`, or (-1,-1).
##
## Workers always stand *beside* what they are working on, never on top of it.
## Standing on the tile would be fine for a floor but disastrous for a wall --
## the pawn would be sealed inside it the moment the work finished.
func adjacent_walkable(target: Vector2i, from: Vector2i) -> Vector2i:
	# Nearest first, but only somewhere there is actually a way to. This used to
	# return the nearest walkable neighbour and stop there, so a shelf with one
	# side facing a sealed pocket would sometimes send a worker to the pocket:
	# the walk failed, the job was abandoned, and it happened 164 times in one
	# measured run. A candidate is kept only if a route to it exists.
	var candidates: Array = []
	for d in TerrainGrid.NEIGHBOURS:
		var t: Vector2i = target + d
		if not is_walkable(t):
			continue
		var delta: Vector2i = t - from
		candidates.append({"tile": t, "distance": maxi(absi(delta.x), absi(delta.y))})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["distance"] < b["distance"]
	)
	for candidate in candidates:
		var tile: Vector2i = candidate["tile"]
		if tile == from or not find_path(from, tile).is_empty():
			return tile
	return Vector2i(-1, -1)


## A random walkable tile inside a region, for spawning and for idle wandering.
## Somewhere with a built floor to stand on, the better floors likelier: stone
## counts twice what wood does. For where idle staff hang about -- inside the
## tavern, mostly. (-1, -1) if there is no floor in `area`.
func random_floor_in(area: Rect2i, rng: RandomNumberGenerator) -> Vector2i:
	if _floors_dirty:
		_floors_dirty = false
		_floors.clear()
		if _build != null:
			for entry in _build.placements:
				if entry == null or not entry["built"] or entry["def"].layer != BuildingDef.Layer.FLOOR \
						or entry["def"].category != "Structure":
					continue
				var weight: int = 2 if entry["def"].id == &"stone_floor" else 1
				for tile in entry["tiles"]:
					for i in range(weight):
						_floors.append(tile)
	var choices: Array[Vector2i] = []
	for tile in _floors:
		if area.has_point(tile) and is_walkable(tile):
			choices.append(tile)
	if choices.is_empty():
		return Vector2i(-1, -1)
	return choices[rng.randi() % choices.size()]


var _floors: Array[Vector2i] = []
var _floors_dirty: bool = true


func random_walkable_in(area: Rect2i, rng: RandomNumberGenerator, attempts: int = 40) -> Vector2i:
	for i in range(attempts):
		var t := Vector2i(
			rng.randi_range(area.position.x, area.end.x - 1),
			rng.randi_range(area.position.y, area.end.y - 1)
		)
		if is_walkable(t):
			return t
	return Vector2i(-1, -1)
