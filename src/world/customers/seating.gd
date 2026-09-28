class_name Seating
extends RefCounted

## Where customers can sit, derived from what has been built.
##
## A seat is not a thing the player places -- it is a chair that happens to be
## next to a table. Deriving it rather than storing it means rearranging
## furniture rearranges the seating with no extra bookkeeping, and a chair
## dragged away from its table simply stops being a seat.
##
## The table tile matters as much as the chair: it is where a waiter puts the
## food down, and where the customer reaches for it.

## Orthogonal only. A chair on a table's diagonal is beside the corner, not at
## the table, and seating someone there would look wrong.
const ADJACENT: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
## "No seat". A seat is known by its chair's tile, never by its place in the
## list: the list is rebuilt whenever furniture changes, and a place in it is
## only good until then.
const NO_SEAT := Vector2i(-1, -1)

var build: BuildGrid
## Optional. When set, a table still holding dirty dishes stops being a seat.
var items: ItemWorld

## Each entry: { chair: Vector2i, table: Vector2i, taken_by: Object }. Iterate
## it freely; never keep a position in it -- see NO_SEAT.
var seats: Array = []
## chair tile -> its entry in `seats`, rebuilt alongside it.
var _by_chair: Dictionary = {}


func setup(p_build: BuildGrid) -> void:
	build = p_build
	refresh()


## Rebuild the seat list from the grid. Cheap enough to run whenever furniture
## changes rather than trying to patch the list incrementally.
func refresh() -> void:
	# Remember who was sitting where, so a refresh mid-service does not evict
	# everyone already at a table.
	var previous: Dictionary = {}
	for seat in seats:
		if seat["taken_by"] != null:
			previous[seat["chair"]] = seat["taken_by"]

	seats.clear()
	_by_chair.clear()
	if build == null:
		return

	var tables: Dictionary = {}
	var chairs: Array[Vector2i] = []
	for entry in build.placements:
		if entry == null or not entry["built"]:
			continue
		match String(entry["def"].id):
			"table":
				for tile in entry["tiles"]:
					tables[tile] = true
			"chair":
				for tile in entry["tiles"]:
					chairs.append(tile)

	for chair in chairs:
		for d in ADJACENT:
			var table: Vector2i = chair + d
			if not tables.has(table):
				continue
			var seat: Dictionary = {
				"chair": chair,
				"table": table,
				"taken_by": previous.get(chair, null),
			}
			seats.append(seat)
			_by_chair[chair] = seat
			break
	_tell_the_sitters(previous)


## Anyone whose chair or table has gone is told so. Everyone else keeps their
## seat without being told anything, because they hold it by its chair.
##
## They used to hold it by its place in the list. Knocking down one chair
## shifted every later seat by one: patrons waited at the wrong table, food went
## to strangers, and leaving freed someone else's seat. Found by the chaos test.
func _tell_the_sitters(previous: Dictionary) -> void:
	for seat in seats:
		if seat["taken_by"] != null and not is_instance_valid(seat["taken_by"]):
			seat["taken_by"] = null
	for chair in previous:
		var who = previous[chair]
		if not is_instance_valid(who):
			continue
		var kept: Dictionary = _by_chair.get(chair, {})
		if kept.is_empty() or kept["taken_by"] != who:
			if who.has_method("lose_seat"):
				who.lose_seat()


## Claim a free seat for a customer. Returns its chair, or NO_SEAT if the house
## is full.
func claim(customer: Object, near: Vector2i, nav: NavGrid = null) -> Vector2i:
	var best: int = -1
	var best_distance: int = 1 << 30
	for i in range(seats.size()):
		if seats[i]["taken_by"] != null:
			continue
		if not is_usable(i):
			continue
		var delta: Vector2i = seats[i]["chair"] - near
		var distance: int = maxi(absi(delta.x), absi(delta.y))
		if distance < best_distance:
			# A clean chair behind a wall must not hide every farther chair.
			# Recheck routes on each claim so opening a doorway restores capacity.
			var chair: Vector2i = seats[i]["chair"]
			if nav != null and (not nav.is_walkable(chair) or (chair != near and nav.find_path(near, chair).is_empty())):
				continue
			best = i
			best_distance = distance
	if best < 0:
		return NO_SEAT
	seats[best]["taken_by"] = customer
	return seats[best]["chair"]


## Put somebody in a particular chair -- restoring a save, or a test. False if
## that chair is not a seat or somebody else has it.
func take(customer: Object, chair: Vector2i) -> bool:
	var seat: Dictionary = _by_chair.get(chair, {})
	if seat.is_empty() or (seat["taken_by"] != null and seat["taken_by"] != customer):
		return false
	seat["taken_by"] = customer
	return true


func release(chair: Vector2i) -> void:
	var seat: Dictionary = _by_chair.get(chair, {})
	if not seat.is_empty():
		seat["taken_by"] = null


## Free every seat held by a customer, wherever it is. What a leaving patron
## uses: by who they are, so there is nothing to get stale.
func release_for(customer: Object) -> void:
	for seat in seats:
		if seat["taken_by"] == customer:
			seat["taken_by"] = null


## The table a chair sits at, which is where its sitter is served; NO_SEAT if
## the chair is not (or is no longer) a seat.
func table_for(chair: Vector2i) -> Vector2i:
	var seat: Dictionary = _by_chair.get(chair, {})
	return seat["table"] if not seat.is_empty() else NO_SEAT


func holder_of(chair: Vector2i) -> Object:
	var seat: Dictionary = _by_chair.get(chair, {})
	return seat["taken_by"] if not seat.is_empty() else null


## For walking the list: the chair and table at a position in it right now.
func chair_of(index: int) -> Vector2i:
	return seats[index]["chair"] if index >= 0 and index < seats.size() else NO_SEAT


func table_of(index: int) -> Vector2i:
	return seats[index]["table"] if index >= 0 and index < seats.size() else NO_SEAT


## Is this seat's table clear enough to sit at?
##
## Design notes section 12: a dirty table is one customers refuse. That is what
## turns cleaning from cosmetic upkeep into capacity -- an unclean dining room
## has fewer usable seats, and the shortfall is felt immediately as lost custom
## rather than noticed later as untidiness.
func is_usable(index: int) -> bool:
	if index < 0 or index >= seats.size():
		return false
	if items == null:
		return true
	var on_table: ItemDef = items.def_at(seats[index]["table"])
	return on_table == null or on_table.category != ItemDef.Category.REFUSE


## Seats a customer could actually take: free *and* clean.
func usable_free_count() -> int:
	var n: int = 0
	for i in range(seats.size()):
		if seats[i]["taken_by"] == null and is_usable(i):
			n += 1
	return n


func free_count() -> int:
	var n: int = 0
	for seat in seats:
		if seat["taken_by"] == null:
			n += 1
	return n
