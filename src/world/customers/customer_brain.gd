class_name CustomerBrain
extends Node

## The customer state machine from the design notes, section 12.
##
## Attaches to an ordinary Pawn, exactly as Worker does. A customer is not a
## different kind of creature -- it is the same body with a different mind, which
## is why the pawn, the pathfinding and the animation all came for free.
##
## Patience is the whole game here. A customer that waits too long for a seat or
## for food leaves, and leaves unhappy, which is what turns layout and staffing
## into decisions rather than decoration.

enum State {
	ARRIVING,
	SEEKING_SEAT,
	WALKING_TO_SEAT,
	ORDERING,
	WAITING_FOR_ORDER,
	EATING,
	PAYING,
	LEAVING,
	GONE,
	## Menu read, hand up: waiting for a waiter to come and take the order.
	## Added after GONE so saved states keep their numbers.
	READY_TO_ORDER,
	## Eaten, and waiting for somebody to bring the bill.
	WAITING_FOR_BILL,
	## Drinks only, and in no mood to wait: walking to a bar to fetch them.
	GOING_TO_BAR,
	## Back to the table from the bar: drinks in hand, or none if it had run dry.
	BACK_FROM_BAR,
}

## Seconds before a customer gives up and goes elsewhere.
const PATIENCE_FOR_SEAT: float = 30.0
## Extra seconds a greeted guest will wait. Being acknowledged is most of what
## makes a queue bearable, which is the whole reason a host is a job at all --
## they seat nobody faster, they make the waiting cost less.
const HOST_PATIENCE_BONUS: float = 30.0
const PATIENCE_FOR_ORDER: float = 60.0
## How long a raised hand stays up before they give up on being served at all.
const PATIENCE_FOR_WAITER: float = 45.0
## How long they sit over an empty plate waiting for the bill. They pay either
## way -- at the door, without a tip, if nobody comes -- but the table is held
## the whole time, and that is the real cost of nobody collecting.
const PATIENCE_FOR_BILL: float = 30.0
## How long spent reading the menu before ordering, and eating once served.
const BROWSE_TIME: float = 2.5
const EAT_TIME: float = 8.0
## Tip as a fraction of the bill when served instantly, falling to nothing by
## the time patience runs out.
const MAX_TIP: float = 0.25
## Seconds between glances around the room. Cleanliness is judged over the whole
## visit rather than at the moment of leaving, so a table cleared a second
## before the patron stands up does not erase the hour they spent looking at it.
const OBSERVE_INTERVAL: float = 1.0

## Reports the bill and the tip separately rather than adding them to the purse
## itself. Money is the ledger's business; a customer's job is to say what it
## owed and what it thought of the service.
signal left(brain: CustomerBrain, satisfied: bool, bill: int, tip: int)
signal ordered(brain: CustomerBrain)

var pawn: Pawn
var director: Object          ## CustomerDirector, kept loose to avoid a cycle
var seating: Seating
var items: ItemWorld
var nav: NavGrid

var state: int = State.ARRIVING
## Met at the door by a host. Not a cosmetic flag: it buys real patience, and
## a greeted guest judges the wait against a longer fuse.
var greeted: bool = false
## The chair they are sitting at (or heading for), by its tile -- never by its
## place in the seat list, which is rebuilt whenever furniture changes.
var seat: Vector2i = Seating.NO_SEAT
var order: Array = []          ## [{ id: StringName, count: int, served: int }]
var exit_tile := Vector2i(-1, -1)

var _timer: float = 0.0
var _patience: float = 0.0
var _waited_for_order: float = 0.0
## Seconds spent waiting for the bill. Counts against the tip with the rest.
var _waited_for_bill: float = 0.0
## Nobody came with the bill, so they paid on the way out and tipped nothing.
var _paid_at_door: bool = false
var _waited_for_seat: float = 0.0
## What this guest will put up with before leaving, which a greeting raises.
## The review divides by this rather than by the constant, so being welcomed
## genuinely softens the complaint instead of merely delaying it.
var _seat_tolerance: float = PATIENCE_FOR_SEAT
## How many things were actually on the menu when they ordered. -1 until they
## have looked, so a patron who left before reading it is not recorded as having
## seen an empty board.
var _menu_breadth: int = -1
## Fetched their own drinks from a bar and paid for them there: no waiter, no
## bill to wait for, and so no tip.
var at_bar: bool = false
var _did_order: bool = false
## What the food was actually like, weighted by how much of it they ate.
var _food_quality_sum: float = 0.0
var _food_eaten: int = 0
var _dirt_sum: float = 0.0
var _dirt_samples: int = 0
var _observe_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _held_visual_id: StringName = &""


## A purchase is counted as consumed at the bar. This node only represents it
## on the walk back: never add a second item or include it in physical cargo.
## Deriving it from saved state also restores the mug after a mid-walk load.
func _process(_delta: float) -> void:
	if not is_instance_valid(pawn) or items == null:
		return
	var id: StringName = &""
	if state == State.BACK_FROM_BAR and at_bar:
		for line in order:
			if int(line.get("served", 0)) > 0:
				id = StringName(line["id"])
				break
	if id == _held_visual_id:
		return
	_held_visual_id = id
	var def: ItemDef = ItemCatalog.get_def(id) if not id.is_empty() else null
	pawn.show_carried(items.make_carry_node(def) if def != null else null)


## Came on a booking: they have a table to come to, so they will wait for it.
var booked: bool = false


## A booked guest waits twice as long for their table, and the wait counts
## half as much in their review (it is measured against the longer patience).
func mark_booked() -> void:
	booked = true
	_patience *= 2.0
	_seat_tolerance *= 2.0


## What kind of adventurer they are, and so what they want. See GuestType.
var guest_type: GuestType = GuestType.of(-1)


func setup(p_pawn: Pawn, p_director: Object, p_seating: Seating, p_items: ItemWorld, p_nav: NavGrid, rng_seed: int) -> void:
	pawn = p_pawn
	director = p_director
	seating = p_seating
	items = p_items
	nav = p_nav
	_rng.seed = rng_seed
	# Customers never wander off on their own; their state machine owns the body.
	pawn.autonomous_idle = false
	guest_type = GuestType.of(pawn.adventurer if pawn != null else -1)
	_patience = PATIENCE_FOR_SEAT * guest_type.patience
	_seat_tolerance = PATIENCE_FOR_SEAT * guest_type.patience


## Met at the door. Tops up patience once, and only once.
func greet() -> bool:
	if not wants_greeting():
		return false
	greeted = true
	_patience += HOST_PATIENCE_BONUS
	_seat_tolerance += HOST_PATIENCE_BONUS
	return true


## Somebody a host still has a reason to walk over to.
func wants_greeting() -> bool:
	return not greeted and (state == State.ARRIVING or state == State.SEEKING_SEAT)


## Game time arrives here from the world's SimClock, in fixed steps, rather
## than per frame. The processing flag stays the switch that freezes one node --
## tests and letting staff go both use it -- and the summary's hold disables
## the node outright.
func _ready() -> void:
	set_process(true)


func sim_step(delta: float) -> void:
	if not is_processing() or not can_process():
		return
	_observe_room(delta)
	match state:
		State.ARRIVING, State.WALKING_TO_SEAT, State.LEAVING:
			_process_walking(delta)
		State.SEEKING_SEAT:
			_process_seeking_seat(delta)
		State.ORDERING:
			_process_ordering(delta)
		State.READY_TO_ORDER:
			_process_ready_to_order(delta)
		State.WAITING_FOR_ORDER:
			_process_waiting(delta)
		State.EATING:
			_process_eating(delta)
		State.WAITING_FOR_BILL:
			_process_waiting_for_bill(delta)
		State.PAYING:
			_pay_and_go()
		State.GOING_TO_BAR:
			_process_going_to_bar()
		State.BACK_FROM_BAR:
			_process_back_from_bar()


func _process_walking(_delta: float) -> void:
	if pawn.is_busy():
		return
	match state:
		State.ARRIVING:
			state = State.SEEKING_SEAT
		State.WALKING_TO_SEAT:
			state = State.ORDERING
			_timer = BROWSE_TIME
		State.LEAVING:
			_finish()


## Take in the state of the room. Cheap, and sampled rather than judged once,
## because a visit is an average and not a snapshot.
func _observe_room(delta: float) -> void:
	_observe_timer -= delta
	if _observe_timer > 0.0:
		return
	_observe_timer = OBSERVE_INTERVAL
	if seating == null or seating.seats.is_empty():
		return
	var dirty: int = 0
	for i in range(seating.seats.size()):
		if not seating.is_usable(i):
			dirty += 1
	_dirt_sum += float(dirty) / float(seating.seats.size())
	_dirt_samples += 1


func _process_seeking_seat(delta: float) -> void:
	_patience -= delta
	_waited_for_seat += delta
	if _patience <= 0.0:
		# No table in a reasonable time. Leaves without ordering, and unhappy.
		_give_up()
		return

	seat = seating.claim(self, pawn.tile, nav)
	if seat == Seating.NO_SEAT:
		return

	var chair: Vector2i = seat
	if chair != pawn.tile and not pawn.goto(chair):
		# Claimed a seat it cannot reach -- hand it straight back rather than
		# holding a table nobody can use.
		seating.release(seat)
		seat = Seating.NO_SEAT
		return
	if chair == pawn.tile:
		pawn.stop()
	state = State.WALKING_TO_SEAT


## Reading the menu. Once read, a hand goes up and a waiter has to come: the
## order is taken at the table, not placed by the patron on their own.
func _process_ordering(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_menu_breadth = _menu_on_offer()
	if _menu_breadth == 0:
		# Nothing on the menu. Leaving now is both more truthful and better for
		# the tavern than sitting for a minute waiting for bread that does not
		# exist -- it frees the table for somebody who can actually be served.
		_give_up()
		return
	if _to_the_bar():
		return
	state = State.READY_TO_ORDER
	_patience = PATIENCE_FOR_WAITER * guest_type.patience
	_waited_for_order = 0.0


func _process_ready_to_order(delta: float) -> void:
	_patience -= delta
	_waited_for_order += delta
	if _patience <= 0.0:
		_give_up()


## A waiter has come to the table. The order is decided now, from what the
## kitchen can serve at this moment -- not from what it had when the menu was
## read, which may have sold since. Returns false if the patron left instead.
func take_order() -> bool:
	if state != State.READY_TO_ORDER:
		return false
	_menu_breadth = _menu_on_offer()
	if not _place_order():
		# Sold out between the hand going up and the waiter arriving: that is
		# "nothing to sell", not slow service, and is counted as such.
		state = State.ORDERING
		_give_up()
		return false
	state = State.WAITING_FOR_ORDER
	_did_order = true
	_patience = PATIENCE_FOR_ORDER * guest_type.patience
	ordered.emit(self)
	return true


## Order from what the tavern can actually serve.
##
## The design notes call for "no stock -> unavailable product", and ordering
## blind is worse than it sounds: a customer asking for bread in a tavern with
## no bread occupies a seat for its whole patience and then leaves angry, having
## blocked a table the entire time.
##
## Returns false when there is nothing to sell at all.
## How many products the tavern could actually sell at this moment. The patron
## judges the board they were offered, not the one they ordered from.
func _menu_on_offer() -> int:
	if items == null:
		return 0
	var n: int = 0
	for id in CustomerDirector.menu_ids():
		if _sellable(id) > 0:
			n += 1
	return n


## Stock nobody else is already waiting on.
func _sellable(id: StringName) -> int:
	if items == null:
		return 0
	if director != null and director.has_method("unpromised"):
		return director.unpromised(id)
	return items.total_of(id)


## `only`, when given, is all they may choose from: what is on the counters.
func _place_order(only: Dictionary = {}) -> bool:
	order.clear()
	# One dish and a drink or two, from whatever the kitchen has. With only
	# bread and beer on, the dice are rolled exactly as they always were.
	var foods: Array[StringName] = []
	var drinks: Array[StringName] = []
	for id in CustomerDirector.menu_ids():
		if _sellable(id) <= 0 or (not only.is_empty() and not only.has(id)):
			continue
		var def: ItemDef = ItemCatalog.get_def(id)
		if def.tags.has("drink"):
			drinks.append(id)
		else:
			foods.append(id)
	if foods.is_empty() and drinks.is_empty():
		return false

	# Each kind of guest leans its own way; the ordinary traveller's numbers
	# are the ones every guest used before there were kinds.
	var t: GuestType = guest_type
	var roll: float = _rng.randf()
	var wants_food: bool = not foods.is_empty() and (roll < t.food_chance or drinks.is_empty())
	var wants_drink: bool = not drinks.is_empty() and (roll > 1.0 - t.drink_chance or foods.is_empty())

	if wants_food:
		var dish: StringName = foods[0]
		if t.dearest:
			for id in foods:
				if ItemCatalog.get_def(id).sell_value > ItemCatalog.get_def(dish).sell_value:
					dish = id
		elif foods.size() > 1:
			dish = foods[_rng.randi() % foods.size()]
		var plates: int = _rng.randi_range(1, t.most_dishes) if t.most_dishes > 1 else 1
		order.append({"id": dish, "count": mini(plates, _sellable(dish)), "served": 0})
	if wants_drink:
		var drink: StringName = drinks[0] if drinks.size() == 1 else drinks[_rng.randi() % drinks.size()]
		var cups: int = _rng.randi_range(1, t.most_drinks) if wants_food else 1
		order.append({"id": drink, "count": mini(cups, _sellable(drink)), "served": 0})
	return not order.is_empty()


func _process_waiting(delta: float) -> void:
	_patience -= delta
	_waited_for_order += delta

	# Food is delivered physically, onto the table. Rather than being told it
	# has arrived, the customer looks: anything on the table that it ordered and
	# has not yet been given counts as served.
	var table: Vector2i = seating.table_for(seat)
	var on_table: ItemDef = items.def_at(table)
	if on_table != null:
		for line in order:
			if line["id"] != on_table.id or line["served"] >= line["count"]:
				continue
			var wanted: int = line["count"] - line["served"]
			# Judge it before eating it: taking the last of a stack leaves the
			# tile reporting nothing at all.
			var was: float = items.quality_at(table)
			var eaten: int = items.take(table, wanted)
			_food_quality_sum += was * float(eaten)
			_food_eaten += eaten
			line["served"] += eaten
			director.consumed[on_table.id] = director.consumed.get(on_table.id, 0) + eaten
			break

	if _order_complete():
		state = State.EATING
		_timer = EAT_TIME
		return

	if _patience <= 0.0:
		_give_up()


func _order_complete() -> bool:
	for line in order:
		if line["served"] < line["count"]:
			return false
	return true


func _process_eating(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		if at_bar:
			# Paid at the bar: up and away, with no bill to wait for.
			_paid_at_door = true
			state = State.PAYING
			return
		state = State.WAITING_FOR_BILL
		_patience = PATIENCE_FOR_BILL * guest_type.patience
		_waited_for_bill = 0.0


func _process_waiting_for_bill(delta: float) -> void:
	_patience -= delta
	_waited_for_bill += delta
	if _patience <= 0.0:
		# Nobody came. They pay what they owe on the way out, and no more.
		_paid_at_door = true
		state = State.PAYING


## Somebody brought the bill. Returns false if there was nothing to settle.
func settle() -> bool:
	if state != State.WAITING_FOR_BILL:
		return false
	state = State.PAYING
	_pay_and_go()
	return true


## Waiting on the tavern, 0 (served at once) to 1 (every wait ran out). Tips
## and the review's service mark both read this, so they can never disagree.
func service_wait() -> float:
	return clampf((_waited_for_order + _waited_for_bill) / (PATIENCE_FOR_WAITER + PATIENCE_FOR_ORDER), 0.0, 1.0)


func _pay_and_go() -> void:
	var bill: int = 0
	for line in order:
		var def: ItemDef = ItemCatalog.get_def(line["id"])
		if def != null:
			bill += def.sell_value * line["served"]

	# Tip falls off with how long they waited -- for a waiter, for the food and
	# for the bill. Prompt service is the only thing the player controls here,
	# so it is the only thing that moves the number.
	var tip: int = 0 if _paid_at_door else int(round(float(bill) * MAX_TIP * guest_type.tip * (1.0 - service_wait())))

	_leave_dishes()
	_release_seat()
	left.emit(self, true, bill, tip)
	_walk_out()


## Somebody has to clear up after them.
##
## Dishes are left on the table as a real item, which is what makes cleaning a
## job rather than a housekeeping flag -- and what makes a neglected dining room
## visibly fill up. A table holding dishes is not a seat until they are gone, so
## an understaffed tavern loses capacity rather than merely looking untidy.
func _leave_dishes() -> void:
	if items == null or seat == Seating.NO_SEAT:
		return
	var table: Vector2i = seating.table_for(seat)
	if table == Seating.NO_SEAT:
		return
	var def: ItemDef = ItemCatalog.get_def(&"dirty_dishes")
	if def == null:
		return
	# Straight onto the table, not place_near: dishes spreading to the floor
	# would be a mess the cleaner then has to chase around the room.
	if items.accepts(table, def):
		var added: int = items.add(def, 1, table)
		if added > 0 and director != null:
			director.dishes_left += added


## The patron's verdict, assembled as they leave.
##
## Lives on the brain rather than the director because the brain owns the
## patience constants. The review is written in fractions of what *this* patron
## would tolerate, so a future impatient noble will score the same wait more
## harshly with no change to the scoring table at all.
func write_review(satisfied: bool, spend: int) -> Review:
	# Never read the menu: judge the board that was actually there as they left,
	# rather than recording a blank one they never saw.
	var menu: int = _menu_breadth if _menu_breadth >= 0 else _menu_on_offer()
	var order_wait: float = -1.0
	if _did_order or state == State.READY_TO_ORDER:
		order_wait = service_wait()
	# Below zero means they never ate, and food goes unjudged. A patron cannot
	# have an opinion on bread they were never brought.
	var food: float = -1.0
	if _food_eaten > 0:
		food = _food_quality_sum / float(_food_eaten)
	return Review.write(
		pawn.pawn_name if pawn != null else "A stranger",
		satisfied,
		spend,
		clampf(_waited_for_seat / maxf(_seat_tolerance, 1.0), 0.0, 1.0),
		order_wait,
		menu,
		_dirt_sum / float(maxi(_dirt_samples, 1)),
		food,
		guest_type.cares
	)


## Left without being served, or without ever sitting down.
func _give_up() -> void:
	_release_seat()
	left.emit(self, false, 0, 0)
	_walk_out()


## By identity, never by number: a number can be stale, and releasing a stale
## one freed a stranger's seat while leaving this patron's own still held.
func _release_seat() -> void:
	seating.release_for(self)
	seat = Seating.NO_SEAT


func _walk_out() -> void:
	state = State.LEAVING
	if exit_tile == Vector2i(-1, -1) or not pawn.goto(exit_tile):
		_finish()


func _finish() -> void:
	state = State.GONE
	if director != null and director.has_method("remove_customer"):
		director.remove_customer(self)


func status_text() -> String:
	match state:
		State.ARRIVING:
			return "arriving"
		State.SEEKING_SEAT:
			return "%s for a table (%ds)" % [
				"waiting to be seated" if greeted else "looking", int(maxf(_patience, 0.0))
			]
		State.WALKING_TO_SEAT:
			return "heading to a table"
		State.ORDERING:
			return "reading the menu"
		State.READY_TO_ORDER:
			return "waiting to order (%ds)" % int(maxf(_patience, 0.0))
		State.WAITING_FOR_ORDER:
			return "waiting for %s (%ds)" % [_order_text(), int(maxf(_patience, 0.0))]
		State.EATING:
			return "eating"
		State.WAITING_FOR_BILL:
			return "waiting for the bill (%ds)" % int(maxf(_patience, 0.0))
		State.PAYING:
			return "paying"
		State.GOING_TO_BAR:
			return "going to the bar for %s" % _order_text()
		State.BACK_FROM_BAR:
			return "bringing drinks back from the bar" if at_bar else "back from an empty bar"
		State.LEAVING:
			return "leaving"
	return "gone"


func _order_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for line in order:
		var def: ItemDef = ItemCatalog.get_def(line["id"])
		parts.append("%dx %s" % [line["count"] - line["served"], def.display_name.to_lower() if def else "?"])
	return ", ".join(parts)


## Their chair or table has been taken away from under them.
##
## Before ordering, they simply look for another table. After, there is no
## table to be served at any more: they pay for whatever reached them and go,
## or leave unhappy if nothing had.
func lose_seat() -> void:
	seat = Seating.NO_SEAT
	match state:
		State.WALKING_TO_SEAT, State.ORDERING, State.READY_TO_ORDER, State.GOING_TO_BAR:
			pawn.stop()
			# An order not yet fetched from the bar is simply dropped.
			if state == State.GOING_TO_BAR:
				order.clear()
				at_bar = false
				_did_order = false
			state = State.SEEKING_SEAT
			_patience = _seat_tolerance * 0.5
		State.WAITING_FOR_ORDER, State.EATING, State.WAITING_FOR_BILL, State.PAYING, State.BACK_FROM_BAR:
			if bill_so_far() > 0:
				_pay_and_go()
			else:
				_give_up()


## How much patience is left for what they are waiting on, 0..1, or -1 when
## they are not waiting on anything the tavern could be blamed for.
func patience_fraction() -> float:
	match state:
		State.SEEKING_SEAT:
			return clampf(_patience / maxf(_seat_tolerance, 1.0), 0.0, 1.0)
		State.READY_TO_ORDER:
			return clampf(_patience / (PATIENCE_FOR_WAITER * guest_type.patience), 0.0, 1.0)
		State.WAITING_FOR_ORDER:
			return clampf(_patience / (PATIENCE_FOR_ORDER * guest_type.patience), 0.0, 1.0)
		State.WAITING_FOR_BILL:
			return clampf(_patience / (PATIENCE_FOR_BILL * guest_type.patience), 0.0, 1.0)
	return -1.0


## What they would pay if they left happy now: only what reached the table.
func bill_so_far() -> int:
	var bill: int = 0
	for line in order:
		var def: ItemDef = ItemCatalog.get_def(line["id"])
		if def != null:
			bill += def.sell_value * int(line["served"])
	return bill


## The tip on that bill, by the same rule _pay_and_go uses.
func tip_so_far() -> int:
	if _paid_at_door:
		return 0
	return int(round(float(bill_so_far()) * MAX_TIP * guest_type.tip * (1.0 - service_wait())))


## The review they would write if they were served and left this minute.
##
## The same scoring as the real one, so the inspector's mood can never disagree
## with the review that follows it. Pure: it reads the visit, it changes nothing.
func mood_preview() -> Review:
	return write_review(true, bill_so_far())


## Outstanding lines, for the director to turn into serving jobs.
func unserved() -> Array:
	var out: Array = []
	if state != State.WAITING_FOR_ORDER:
		return out
	for line in order:
		if line["served"] < line["count"]:
			out.append({"id": line["id"], "count": line["count"] - line["served"]})
	return out


## Drinks and nothing to eat, and in no mood to wait: rather than put a hand
## up for a waiter, they walk to a bar, take their drinks off its counter and
## carry them back to the table. Decided as the menu is read. Anyone who wants
## a meal after all is waited on as ever, the order rolled again when the
## waiter comes; and in a tavern with no drink on a bar, nothing is rolled here.
func _to_the_bar() -> bool:
	if director == null or not director.has_method("bar_stand"):
		return false
	# Nobody on the books to take an order: everyone goes up to the bar or the
	# till, and buys from what is on it. Otherwise only the hurried, for drinks.
	var no_waiter: bool = director.has_method("takes_orders") and not director.takes_orders()
	if not no_waiter and not guest_type.prefers_bar():
		return false
	if not director.has_bar_drinks() or not _place_order(director.walkup_goods() if no_waiter else {}):
		return false
	for line in order:
		var def: ItemDef = ItemCatalog.get_def(line["id"])
		if def == null or (not no_waiter and not def.tags.has("drink")):
			order.clear()
			return false
	var stand: Vector2i = director.bar_stand(order, pawn.tile)
	if stand == Vector2i(-1, -1) or (stand != pawn.tile and not pawn.goto(stand)):
		order.clear()
		return false
	at_bar = true
	_did_order = true
	state = State.GOING_TO_BAR
	ordered.emit(self)
	return true


## At the bar: take what was ordered off the counter, as far as it has it, and
## pay for exactly that. With nothing there at all they go back to the table
## and put a hand up after all.
func _process_going_to_bar() -> void:
	if pawn.is_busy():
		return
	var got: int = 0
	for line in order:
		for tile in director.bar_tiles_at(pawn.tile, line["id"]):
			var wanted: int = int(line["count"]) - int(line["served"])
			if wanted <= 0:
				break
			# Judged before it is taken: the last of a stack reports nothing.
			var was: float = items.quality_at(tile)
			var taken: int = items.take(tile, mini(wanted, items.available_at(tile)))
			if taken <= 0:
				continue
			_food_quality_sum += was * float(taken)
			_food_eaten += taken
			line["served"] = int(line["served"]) + taken
			got += taken
			director.consumed[line["id"]] = int(director.consumed.get(line["id"], 0)) + taken
	# The bill is what they carried away.
	var kept: Array = []
	for line in order:
		if int(line["served"]) > 0:
			line["count"] = line["served"]
			kept.append(line)
	order = kept
	if got == 0:
		at_bar = false
		_did_order = false
	elif director.has_method("count_bar_visit"):
		director.count_bar_visit()
	state = State.BACK_FROM_BAR
	if seat != Seating.NO_SEAT and seat != pawn.tile:
		pawn.goto(seat)


func _process_back_from_bar() -> void:
	if pawn.is_busy():
		return
	if not at_bar:
		state = State.READY_TO_ORDER
		_patience = PATIENCE_FOR_WAITER * guest_type.patience
		_waited_for_order = 0.0
		return
	state = State.EATING
	_timer = EAT_TIME


## What is still to come to them, from a waiter or from the bar: stock that is
## spoken for. A guest on their way to the bar has a claim on it too.
func owed() -> Array:
	if state != State.GOING_TO_BAR:
		return unserved()
	var out: Array = []
	for line in order:
		if line["served"] < line["count"]:
			out.append({"id": line["id"], "count": line["count"] - line["served"]})
	return out
