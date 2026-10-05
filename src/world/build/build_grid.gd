class_name BuildGrid
extends RefCounted

## What the player has built, and where.
##
## Two independent layers per tile, mirroring how these things actually behave:
## a FLOOR layer (one covering per tile) and an OBJECT layer (walls, furniture,
## workstations). A table stands *on* a floor, so both can occupy the same tile;
## two tables cannot.
##
## Occupancy stores placement index + 1, so 0 reads as empty without needing a
## parallel "is occupied" array.
##
## This is the structure the job system, room detection and pathfinding will all
## query later, so it deliberately answers questions ("what blocks this tile?")
## rather than just holding meshes.

signal placement_added(index: int)
signal placement_removed(index: int, def: BuildingDef)
signal placement_built(index: int)
## Something about an existing placement changed that other systems care about
## -- so far, what a shelf is willing to hold.
signal placement_changed(index: int)
## A placed piece took another look (BuildController.restyle).
signal placement_restyled(index: int)

var cols: int = 0
var rows: int = 0
## Buildable region, in tiles. Placement outside it is refused.
var plot: Rect2i = Rect2i()

## Each entry: { def: BuildingDef, origin: Vector2i, rotation: int, tiles: Array[Vector2i] }
## Removed entries become null rather than being erased, so stored indices stay
## valid; `compact_count` tracks how many are live.
var placements: Array = []

var _floor_at: PackedInt32Array
var _object_at: PackedInt32Array


func setup(p_cols: int, p_rows: int, p_plot: Rect2i) -> void:
	cols = p_cols
	rows = p_rows
	plot = p_plot
	placements.clear()
	_floor_at = PackedInt32Array()
	_floor_at.resize(cols * rows)
	_object_at = PackedInt32Array()
	_object_at.resize(cols * rows)


## Move the boundary without disturbing what is built inside it.
##
## `setup()` clears every placement, which is right when a world is being made
## and catastrophic when the player has just bought the next field along. The
## occupancy arrays are indexed by map tile, not by plot tile, so growing the
## plot needs nothing rebuilt -- only the rule about what counts as "your land".
func set_plot(p_plot: Rect2i) -> void:
	plot = p_plot


func _index(tile: Vector2i) -> int:
	return tile.y * cols + tile.x


func in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < cols and tile.y < rows


func in_plot(tile: Vector2i) -> bool:
	return plot.has_point(tile)


## Tiles a definition would cover if placed at `origin` with `rotation`
## quarter-turns.
func footprint(def: BuildingDef, origin: Vector2i, rotation: int) -> Array[Vector2i]:
	var size: Vector2i = def.rotated_size(rotation)
	var out: Array[Vector2i] = []
	for dz in range(size.y):
		for dx in range(size.x):
			out.append(origin + Vector2i(dx, dz))
	return out


## Why a placement would fail, or an empty string if it would succeed. Returning
## the reason rather than a bare bool lets the UI say what is wrong instead of
## just refusing.
## The landscape the grid is laid over, so a placement can ask what is actually
## out there. Optional -- without it, landscape rules simply do not apply.
var terrain_grid: TerrainGrid


func placement_problem(def: BuildingDef, origin: Vector2i, rotation: int) -> String:
	if def.needs_water_within > 0 and not _water_near(origin, def, rotation):
		return "Must be built near water"
	for tile in footprint(def, origin, rotation):
		if not in_bounds(tile):
			return "Outside the map"
		if not in_plot(tile):
			return "Outside your land"
		var layer: PackedInt32Array = _floor_at if def.layer == BuildingDef.Layer.FLOOR else _object_at
		if layer[_index(tile)] != 0:
			return "Something is already here"
	return ""


## Is there open water within reach of this footprint?
##
## Chebyshev distance from any tile of the piece, which is the same measure the
## hauling uses, so "near" means the same thing everywhere in the game.
func _water_near(origin: Vector2i, def: BuildingDef, rotation: int) -> bool:
	if terrain_grid == null:
		return true
	var reach: int = def.needs_water_within
	for tile in footprint(def, origin, rotation):
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var x: int = tile.x + dx
				var y: int = tile.y + dy
				if x < 0 or y < 0 or x >= terrain_grid.cols or y >= terrain_grid.rows:
					continue
				if terrain_grid.cells[y * terrain_grid.cols + x] == TerrainGrid.Cell.WATER:
					return true
	return false


func can_place(def: BuildingDef, origin: Vector2i, rotation: int) -> bool:
	return placement_problem(def, origin, rotation) == ""


## What this piece is willing to hold, as a set of item ids. Empty means
## everything.
##
## Design notes section 11: storage is generic filters, never hardcoded
## furniture. So "pantry", "cellar" and "granary" are not types -- they are the
## same shelf with different boxes ticked, and nothing in the code knows the
## difference.
func filter_of(index: int) -> Dictionary:
	if index < 0 or index >= placements.size() or placements[index] == null:
		return {}
	return placements[index].get("filter", {})


func allows(index: int, id: StringName) -> bool:
	var filter: Dictionary = filter_of(index)
	return filter.is_empty() or filter.has(id)


## Replace a piece's filter. An empty list means "anything", not "nothing" --
## unticking the last box would otherwise silently make a shelf useless, and the
## player would read that as the storage being broken.
func set_filter(index: int, ids: Array) -> void:
	if index < 0 or index >= placements.size() or placements[index] == null:
		return
	var filter: Dictionary = {}
	for id in ids:
		filter[StringName(id)] = true
	placements[index]["filter"] = filter
	placement_changed.emit(index)


func toggle_filter(index: int, id: StringName) -> void:
	var filter: Dictionary = filter_of(index).duplicate()
	if filter.has(id):
		filter.erase(id)
	else:
		# The first tick turns a general shelf into a dedicated one, so it starts
		# from "only this" rather than "everything except".
		filter[id] = true
	placements[index]["filter"] = filter
	placement_changed.emit(index)


## Another look for a placed piece: same piece, tiles and state, so only the
## drawing (and a look's own price and preferences) changes.
func restyle(index: int, look: BuildingDef) -> void:
	if index < 0 or index >= placements.size() or placements[index] == null:
		return
	placements[index]["def"] = look
	placement_restyled.emit(index)
	placement_changed.emit(index)


## Place a piece. By default it lands as a *blueprint*: it occupies the tile so
## nothing else can be put there, but it does not block movement and does not
## render as solid until a worker has built it.
func place(def: BuildingDef, origin: Vector2i, rotation: int, built: bool = false) -> int:
	if not can_place(def, origin, rotation):
		return -1
	var tiles: Array[Vector2i] = footprint(def, origin, rotation)
	placements.append({
		"def": def, "origin": origin, "rotation": rotation, "tiles": tiles, "built": built,
		# Which goods this piece will hold. Empty means anything, which is what
		# a shelf you have never touched should do.
		"filter": {},
	})
	var index: int = placements.size() - 1

	var layer: PackedInt32Array = _floor_at if def.layer == BuildingDef.Layer.FLOOR else _object_at
	for tile in tiles:
		layer[_index(tile)] = index + 1
	# PackedArrays are value types in GDScript, so the mutated copy has to be
	# written back. Missing this silently discards every placement.
	if def.layer == BuildingDef.Layer.FLOOR:
		_floor_at = layer
	else:
		_object_at = layer

	placement_added.emit(index)
	return index


## The placement occupying a tile, preferring the object layer -- demolishing
## should take the table before the floor under it.
## What is on a tile, by layer. Rooms need to ask about the two separately --
## a floor with nothing on it is the inside of a room, a wall on that same tile
## is its edge -- and placement_at() collapses them.
func floor_index_at(tile: Vector2i) -> int:
	return _floor_at[_index(tile)] - 1 if in_bounds(tile) else -1


func object_index_at(tile: Vector2i) -> int:
	return _object_at[_index(tile)] - 1 if in_bounds(tile) else -1


## Visual support above the ground plane. Blueprints have no physical surface.
func visual_floor_height(tile: Vector2i) -> float:
	var index: int = floor_index_at(tile)
	if not is_built(index):
		return 0.0
	return maxf(0.0, placements[index]["def"].height)


func visual_item_height(tile: Vector2i) -> float:
	var floor_height: float = visual_floor_height(tile)
	var index: int = object_index_at(tile)
	if not is_built(index):
		return floor_height
	var def: BuildingDef = placements[index]["def"]
	return maxf(floor_height, def.item_surface_height)


## Does this tile close a room off? Walls do, doors do, tables do not.
func encloses_at(tile: Vector2i) -> bool:
	var index: int = object_index_at(tile)
	if index < 0 or placements[index] == null:
		return false
	return placements[index]["def"].encloses


func placement_at(tile: Vector2i) -> int:
	if not in_bounds(tile):
		return -1
	var i: int = _object_at[_index(tile)]
	if i > 0:
		return i - 1
	i = _floor_at[_index(tile)]
	return i - 1 if i > 0 else -1


func remove(index: int) -> BuildingDef:
	if index < 0 or index >= placements.size() or placements[index] == null:
		return null
	var entry: Dictionary = placements[index]
	var def: BuildingDef = entry["def"]

	var layer: PackedInt32Array = _floor_at if def.layer == BuildingDef.Layer.FLOOR else _object_at
	for tile in entry["tiles"]:
		layer[_index(tile)] = 0
	if def.layer == BuildingDef.Layer.FLOOR:
		_floor_at = layer
	else:
		_object_at = layer

	placements[index] = null
	placement_removed.emit(index, def)
	return def


## Live placements of one definition, split by build state so the renderer can
## draw finished pieces solid and blueprints translucent.
func live_of(def_id: StringName, built: bool) -> Array:
	var out: Array = []
	for entry in placements:
		if entry != null and entry["def"].id == def_id and entry["built"] == built:
			out.append(entry)
	return out


func mark_built(index: int) -> void:
	if index < 0 or index >= placements.size() or placements[index] == null:
		return
	placements[index]["built"] = true
	placement_built.emit(index)


func is_built(index: int) -> bool:
	if index < 0 or index >= placements.size() or placements[index] == null:
		return false
	return placements[index]["built"]


## A blueprint occupies its tile but does not block movement -- workers have to
## be able to walk up to it, and a half-built wall is not yet a wall.
func blocks_movement(tile: Vector2i) -> bool:
	if not in_bounds(tile):
		return true
	var i: int = _object_at[_index(tile)]
	if i <= 0:
		return false
	var entry = placements[i - 1]
	if entry == null or not entry["built"]:
		return false
	return entry["def"].blocks_movement


func live_count() -> int:
	var n: int = 0
	for entry in placements:
		if entry != null:
			n += 1
	return n


## Finished pieces of any of these kinds. The checklist, the warning line and
## the inspector each counted this for themselves until they were made to share.
func count_built(ids: Array) -> int:
	var n: int = 0
	for entry in placements:
		if entry != null and entry["built"] and ids.has(entry["def"].id):
			n += 1
	return n


func total_value() -> int:
	var v: int = 0
	for entry in placements:
		if entry != null:
			v += entry["def"].cost
	return v
