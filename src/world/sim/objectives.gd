class_name Objectives
extends RefCounted

## The opening sequence: what to do, in the order that works.
##
## A player dropped onto an empty plot with thirteen buildables and a running
## clock has no way to know that bread needs *two* stations, that haulers need
## somewhere to put things, or that a chair is only a seat if it is beside a
## table. None of that is discoverable by clicking; it has to be said.
##
## Objectives are **derived, never tracked** -- each one asks the world a
## question every refresh rather than listening for an event. That is the same
## decision `JobGenerator` makes, and it buys the same thing: an objective
## cannot desynchronise, cannot be completed twice, and survives save/load with
## no serialisation at all.

signal changed

class Objective:
	extends RefCounted
	var id: StringName
	var text: String
	var hint: String
	## Takes the world, returns whether it is done.
	var test: Callable
	var done: bool = false

	func _init(p_id: String, p_text: String, p_hint: String, p_test: Callable) -> void:
		id = StringName(p_id)
		text = p_text
		hint = p_hint
		test = p_test


var list: Array[Objective] = []
var _last_done_count: int = -1


func _init() -> void:
	list = [
		Objective.new(
			"floor", "Lay some flooring",
			"Press " + KeyBindings.first("build") + ", pick Wood Floor, then drag a room about 10 x 8 inside the gold boundary. Watch the cost in the build bar: keep enough for a kitchen, supplies and tonight's wages.",
			func(w) -> bool: return w.build.grid.count_built([&"wood_floor", &"stone_floor"]) >= 4
		),
		Objective.new(
			"kitchen", "Build a prep table and an oven",
			"Bread takes two steps: dough at the prep table, then baked at the oven.",
			func(w) -> bool: return w.build.grid.count_built([&"prep_table"]) >= 1 and w.build.grid.count_built([&"oven"]) >= 1
		),
		Objective.new(
			"seating", "Put in a table with chairs beside it",
			"A chair only becomes a seat when it sits directly next to a table.",
			func(w) -> bool: return w.customers != null and w.customers.seating.seats.size() >= 2
		),
		Objective.new(
			"storage", "Put up four tiles of storage",
			"One tile holds one kind of goods. Too little storage and deliveries end up heaped round the benches, where they block the very ingredient the kitchen is waiting for.",
			func(w) -> bool: return _storage_tiles(w) >= 4
		),
		Objective.new(
			"supplies", "Order supplies from the merchant",
			"The cart unloads by the road. Your staff will carry it to the shelves.",
			func(w) -> bool: return not w.delivered.is_empty()
		),
		Objective.new(
			"first_sale", "Serve your first customer",
			"Customers arrive on the road and seat themselves. They only order what you have in stock.",
			func(w) -> bool: return _served_ever(w) >= 1
		),
		Objective.new(
			"washing_up", "Build a wash basin",
			"Used plates stay on the table, and nobody will sit at a dirty one until a worker has cleared it.",
			func(w) -> bool: return w.build.grid.count_built([&"sink"]) >= 1
		),
		Objective.new(
			"profit", "Finish a day in profit",
			"Takings must beat wages and supplies. Watch today's total beside the purse.",
			func(w) -> bool: return _any_profitable_day(w)
		),
	]


## Re-evaluate everything. Cheap enough to run on a timer; nothing here is
## kept between calls, because a demolished oven should un-tick its objective
## (the grid's own counts are kept only until the grid changes).
func refresh(world) -> void:
	var done_count: int = 0
	for objective in list:
		objective.done = objective.test.call(world)
		if objective.done:
			done_count += 1
	if done_count != _last_done_count:
		_last_done_count = done_count
		changed.emit()


## The next thing to do, or null when the opening sequence is finished.
func current() -> Objective:
	for objective in list:
		if not objective.done:
			return objective
	return null


func completed_count() -> int:
	var n: int = 0
	for objective in list:
		if objective.done:
			n += 1
	return n


func all_done() -> bool:
	return completed_count() == list.size()


## Counted in tiles rather than pieces, because that is what actually limits a
## tavern: a shelf is two tiles and a barrel one, and "one shelf" was measured
## to be nowhere near enough for nine kinds of goods.
static func _storage_tiles(world) -> int:
	if world.generator != null:
		return world.generator._storage_tiles().size()
	var n: int = 0
	for entry in world.build.grid.placements:
		if entry == null or not entry["built"] or not entry["def"].is_storage:
			continue
		n += entry["tiles"].size()
	return n


## Everyone ever served, not just today.
##
## The director's served_count is a *daily* tally and resets every morning, so
## "serve your first customer" used to un-tick itself at every rollover unless
## somebody else was served that same day. A milestone is something that has
## happened; it cannot un-happen overnight.
static func _served_ever(world) -> int:
	if world.customers == null:
		return 0
	var n: int = world.customers.served_count
	if world.ledger != null:
		for entry in world.ledger.history:
			n += int(entry.get("served", 0))
	return n


static func _any_profitable_day(world) -> bool:
	for entry in world.ledger.history:
		if int(entry.get("profit", 0)) > 0:
			return true
	return false
