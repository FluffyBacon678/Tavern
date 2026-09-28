class_name Rooms
extends RefCounted

## Enclosed spaces, found by looking at what is built rather than declared.
##
## Design notes section 23. A room is not a thing the player draws -- it is what
## happens when they finish a wall. Deriving it means knocking a hole in a wall
## un-makes the room with no bookkeeping, which is the same argument the seating
## and the job board make, and it buys the same thing.
##
## The rule: a maximal patch of floored tiles whose every edge is a wall or a
## door. Reach open ground or the edge of your land and the patch is outdoors,
## not a room. That single rule is what makes an unfinished wall read correctly
## -- a room with a gap in it simply is not a room yet.
##
## Rebuilt lazily. A flood fill over the plot is cheap but not free, and during
## a drag of forty floor tiles it would run forty times for a result nobody
## looks at until the drag ends.

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## Each entry: {
##   tiles: Array[Vector2i], kind: RoomCatalog.RoomKind (may be null),
##   counts: Dictionary, value: int, seats: int, doors: int
## }
var rooms: Array[Dictionary] = []

var _grid: BuildGrid
var _plot: Rect2i
var _dirty: bool = true
var _bound: bool = false
## tile -> index into `rooms`, rebuilt with them.
var _at: Dictionary = {}


func setup(p_grid: BuildGrid, p_plot: Rect2i) -> void:
	_grid = p_grid
	_plot = p_plot
	_dirty = true
	if _grid == null:
		return
	# Any change to what is built can make or unmake a room, including one that
	# only *finishes* a wall somebody else started.
	#
	# Connected one at a time rather than by name in a loop: signals are not
	# properties, so Object.get("placement_added") hands back nothing and the
	# connection is silently never made. The symptom was rooms that appeared
	# correctly and never went away.
	if not _bound:
		_bound = true
		_grid.placement_added.connect(mark_dirty.unbind(1))
		_grid.placement_built.connect(mark_dirty.unbind(1))
		_grid.placement_changed.connect(mark_dirty.unbind(1))
		_grid.placement_removed.connect(mark_dirty.unbind(2))


func set_plot(p_plot: Rect2i) -> void:
	_plot = p_plot
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


## Rooms as of now, recomputing only if something has changed since last time.
func current() -> Array[Dictionary]:
	if _dirty:
		_rebuild()
	return rooms


## Which room a tile belongs to, or -1 for outdoors.
func room_at(tile: Vector2i) -> int:
	if _dirty:
		_rebuild()
	return int(_at.get(tile, -1))


func named(tile: Vector2i) -> String:
	var index: int = room_at(tile)
	if index < 0:
		return ""
	return describe(rooms[index])


static func describe(room: Dictionary) -> String:
	var kind = room["kind"]
	var name: String = kind.display_name if kind != null else "Room"
	return "%s · %d tiles" % [name, room["tiles"].size()]


func _rebuild() -> void:
	_dirty = false
	rooms.clear()
	_at.clear()
	if _grid == null or _plot.size.x <= 0:
		return

	var seen: Dictionary = {}
	for y in range(_plot.position.y, _plot.end.y):
		for x in range(_plot.position.x, _plot.end.x):
			var tile := Vector2i(x, y)
			if seen.has(tile) or not _is_inside(tile):
				continue
			_flood(tile, seen)


## Can this tile be the inside of a room? Floored, and nothing walling it.
func _is_inside(tile: Vector2i) -> bool:
	if not _plot.has_point(tile):
		return false
	if _grid.encloses_at(tile):
		return false
	return _grid.floor_index_at(tile) >= 0


## Grow one region and keep it only if nothing leaked out.
##
## Every tile is marked seen whether the region turns out to be a room or not,
## so open ground is walked once for the whole plot rather than once per tile.
func _flood(start: Vector2i, seen: Dictionary) -> void:
	var region: Array[Vector2i] = []
	var frontier: Array[Vector2i] = [start]
	seen[start] = true
	var enclosed: bool = true
	var doors: int = 0
	var counted_doors: Dictionary = {}

	while not frontier.is_empty():
		var tile: Vector2i = frontier.pop_back()
		region.append(tile)
		for step in NEIGHBOURS:
			var next: Vector2i = tile + step
			if _grid.encloses_at(next) and _plot.has_point(next):
				var index: int = _grid.object_index_at(next)
				if index >= 0 and not counted_doors.has(index):
					counted_doors[index] = true
					if _grid.placements[index]["def"].shape == BuildingDef.Shape.DOOR:
						doors += 1
				continue
			if not _is_inside(next):
				# Open ground, bare earth, or the edge of the plot. Whatever it
				# is, this patch is outdoors.
				enclosed = false
				continue
			if seen.has(next):
				continue
			seen[next] = true
			frontier.append(next)

	if not enclosed or region.is_empty():
		return

	var index: int = rooms.size()
	var room: Dictionary = _measure(region)
	room["doors"] = doors
	rooms.append(room)
	for tile in region:
		_at[tile] = index


## Tally what is standing in a region, and what that makes it.
func _measure(region: Array[Vector2i]) -> Dictionary:
	var counts: Dictionary = {}
	var value: int = 0
	var seen_pieces: Dictionary = {}
	for tile in region:
		for layer in [_grid.object_index_at(tile), _grid.floor_index_at(tile)]:
			if layer < 0 or seen_pieces.has(layer) or _grid.placements[layer] == null:
				continue
			seen_pieces[layer] = true
			var def: BuildingDef = _grid.placements[layer]["def"]
			counts[def.id] = int(counts.get(def.id, 0)) + 1
			value += def.cost

	return {
		"tiles": region,
		"counts": counts,
		"kind": RoomCatalog.identify(counts),
		"value": value,
	}


## One line per room, for the dev report and the ledger panel.
func summary() -> String:
	var found: Array[Dictionary] = current()
	if found.is_empty():
		return "No enclosed rooms."
	var parts: PackedStringArray = PackedStringArray()
	for room in found:
		parts.append(describe(room))
	return ", ".join(parts)
