class_name CustomerDirector
extends Node3D

## Brings customers in off the road, and turns what they order into work.
##
## Serving is generated here rather than in JobGenerator for one reason: a
## serving job only exists because a person is sitting at a table waiting, and
## it should stop existing the moment they leave. Tying it to the customer keeps
## that lifetime obvious.
##
## The job itself is an ordinary haul -- fetch this from wherever it is, put it
## on that table -- which is why no new machinery was needed to support it.

## Seconds between arrivals at average footfall; the day curve scales it.
const SPAWN_INTERVAL: float = 5.0
## The fewest guests the tavern will hold at once; see max_customers().
const MAX_CUSTOMERS: int = 10
## Seconds a host spends on the door before the queue counts as welcomed.
const GREET_WORK: float = 1.6

signal customer_served(paid: int)
signal customer_lost
signal reviewed(review: Review)

## Game time, for the patrons this director brings in. Set by the world.
var sim: SimClock
var seating := Seating.new()
var board: JobBoard
var items: ItemWorld
var nav: NavGrid
var terrain: TerrainMeshBuilder
var plot: Rect2i
## Kept so the host job can find a stand. The seating already follows the
## grid; this is the same grid, not a second source of truth.
var build_grid: BuildGrid
var pawn_material: Material
var ledger: Ledger
var clock: DayClock
## What the town thinks of the place. Owned here because every review starts
## with a customer leaving.
var reputation := Reputation.new()
## Today's booked tables, taken by a host each morning.
var bookings := Bookings.new()

var customers: Array[CustomerBrain] = []
## Running tallies, so the day can be judged rather than guessed at.
var served_count: int = 0
var lost_count: int = 0
## Why the lost ones left. "Five customers walked out" is not actionable; "five
## walked out because there was nowhere to sit" names the thing to build. The
## three causes have three different fixes -- more seating, faster staff, more
## stock -- so they are counted apart rather than lumped together.
var lost_no_seat: int = 0
var lost_no_service: int = 0
var lost_no_menu: int = 0
## Today's takings from booked guests, premium included (also in `takings`).
var booked_takings: int = 0
var takings: int = 0
## Includes partial meals even when a patron subsequently leaves dissatisfied.
var consumed: Dictionary = {}
## Dishes created by departing customers. Counted so the books still balance:
## they are goods that came into existence, exactly like a baked loaf.
var dishes_left: int = 0
## Today's verdicts, newest first, for the end-of-day reckoning.
var day_reviews: Array[Review] = []

var _spawn_timer: float = SPAWN_INTERVAL
var _rng := RandomNumberGenerator.new()
var _holder: Node3D
## Set false while the tavern is not trading, so a half-built kitchen is not
## immediately full of people.
var open_for_business: bool = true


func setup(p_board: JobBoard, p_items: ItemWorld, p_nav: NavGrid, p_terrain: TerrainMeshBuilder, p_build: BuildGrid, p_plot: Rect2i, p_material: Material, rng_seed: int) -> void:
	board = p_board
	items = p_items
	nav = p_nav
	terrain = p_terrain
	plot = p_plot
	pawn_material = p_material
	_rng.seed = rng_seed

	# Seating consults the item world so a table still holding dirty dishes
	# stops counting as somewhere to sit.
	# A fresh world is an unknown tavern. A load restores the standing straight
	# afterwards, so this only ever wipes a genuinely new one.
	reputation.clear()
	build_grid = p_build
	seating.items = p_items
	seating.setup(p_build)
	# All three, not just placement_built: a piece placed as a finished item --
	# scripted setups, and anything the game builds on the player's behalf --
	# never emits `built`, so listening for that alone leaves the tavern with no
	# seats and no customers, silently.
	p_build.placement_added.connect(func(_i: int) -> void: seating.refresh())
	p_build.placement_built.connect(func(_i: int) -> void: seating.refresh())
	p_build.placement_removed.connect(func(_i: int, _d: BuildingDef) -> void: seating.refresh())

	clear()
	if _holder == null:
		_holder = Node3D.new()
		_holder.name = "Customers"
		add_child(_holder)


func clear() -> void:
	for brain in customers:
		if is_instance_valid(brain) and is_instance_valid(brain.pawn):
			brain.pawn.queue_free()
	customers.clear()
	seating.refresh()


## Game time arrives here from the world's SimClock, in fixed steps, rather
## than per frame. The processing flag stays the switch that freezes one node --
## tests and letting staff go both use it -- and the summary's hold disables
## the node outright.
func _ready() -> void:
	set_process(true)


func sim_step(delta: float) -> void:
	if not is_processing() or not can_process():
		return
	if board == null or not open_for_business:
		return

	# Arrivals follow the day's footfall rather than a flat timer, so midday and
	# evening genuinely are rushes and the quiet stretch between them is a chance
	# to catch up. Serving jobs keep being generated after closing time -- people
	# already at a table still want feeding.
	# Reputation decides how many people bother coming. This is the line that
	# turns service quality from a number in the corner into the thing that
	# fills or empties the room tomorrow.
	var rate: float = clock.footfall() if clock != null else 1.0
	rate *= reputation.footfall_multiplier()
	if rate > 0.0:
		_spawn_timer -= delta * rate
		if _spawn_timer <= 0.0:
			_spawn_timer = SPAWN_INTERVAL
			_try_spawn()

	# Four times a game-second is as fast as anyone would notice a job appear,
	# and every pass re-reads every placement and patron. Sixty times a second
	# was a third of a big tavern's frame.
	_service_timer -= delta
	if _service_timer > 0.0:
		return
	_service_timer = SERVICE_SCAN_INTERVAL
	_generate_serve_jobs()
	_generate_host_jobs()
	_generate_booking_job()
	_seat_bookings()


const SERVICE_SCAN_INTERVAL: float = 0.25
var _service_timer: float = 0.0


## Seconds at the table taking an order, and bringing and settling a bill.
const TAKE_ORDER_WORK: float = 2.0
const BILL_WORK: float = 1.5


## The counter: every built serving counter's tiles. With one, the kitchen plates
## each order there and waiters collect from it; without, waiters fetch from
## wherever the stock is, as they always did.
func pass_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if build_grid == null:
		return out
	for entry in build_grid.placements:
		if entry == null or not entry["built"] or entry["def"].id != &"serving_counter":
			continue
		for tile in entry["tiles"]:
			out.append(tile)
	return out


## A waiter to every raised hand, and somebody with the bill to every empty
## plate. Keys are per chair, since two patrons can share one table.
func _generate_table_jobs(wanted: Dictionary) -> void:
	for brain in customers:
		if not is_instance_valid(brain) or brain.seat == Seating.NO_SEAT:
			continue
		var table: Vector2i = brain.seating.table_for(brain.seat)
		if table == Seating.NO_SEAT:
			continue
		var chair: Vector2i = brain.seat
		var job: Job = null
		match brain.state:
			CustomerBrain.State.READY_TO_ORDER:
				var key: String = "take:%d,%d" % [chair.x, chair.y]
				wanted[key] = true
				if board.has_key(key):
					continue
				job = Job.new()
				job.kind = WorkType.Kind.SERVE
				job.work_amount = TAKE_ORDER_WORK
				job.label = "Take an order"
				job.key = key
				var asked: CustomerBrain = brain
				job.on_complete = func(_j: Job) -> void:
					if is_instance_valid(asked):
						asked.take_order()
			CustomerBrain.State.WAITING_FOR_BILL:
				var key: String = "bill:%d,%d" % [chair.x, chair.y]
				wanted[key] = true
				if board.has_key(key):
					continue
				job = Job.new()
				job.kind = WorkType.Kind.BILL
				job.work_amount = BILL_WORK
				job.label = "Bring the bill"
				job.key = key
				var paying: CustomerBrain = brain
				job.on_complete = func(_j: Job) -> void:
					if is_instance_valid(paying):
						paying.settle()
		if job != null:
			job.target = table
			# A raised hand is somebody the tavern is already keeping waiting.
			job.urgency = 1
			board.post(job)


## Plate taken orders onto the counter, one run per kind of goods at a time. The
## cooks' work: the kitchen sends the order out, the waiters carry it to the
## table. Only what has been ordered and not yet reached a table is plated.
func _generate_plating(counter: Array[Vector2i], wanted: Dictionary) -> void:
	# Each counter plates for the tables nearest it. One pool for every counter
	# sent a big hall's orders to whichever counter was built first, rooms away
	# from the guest, and the waiters spent the evening walking between them.
	var counters: Array = _counters()
	if counters.is_empty():
		return
	var demand: Dictionary = {}  # "counter:id" -> [counter, id, count]
	for brain in customers:
		if not is_instance_valid(brain):
			continue
		var lines: Array = brain.unserved()
		if lines.is_empty():
			continue
		var table: Vector2i = brain.seating.table_for(brain.seat)
		if table == Seating.NO_SEAT:
			continue
		var nearest: Dictionary = _nearest_counter(counters, table)
		for line in lines:
			var key: String = "%d:%s" % [int(nearest["index"]), line["id"]]
			if not demand.has(key):
				demand[key] = [nearest, StringName(line["id"]), 0]
			demand[key][2] += int(line["count"])
	var tables: Dictionary = {}
	for seat in seating.seats:
		tables[seat["table"]] = true
	for key in demand:
		var here: Dictionary = demand[key][0]
		var id: StringName = demand[key][1]
		var def: ItemDef = ItemCatalog.get_def(id)
		if def == null:
			continue
		var job_key: String = "plate:%s" % key
		var on_pass: int = 0
		for tile in here["tiles"]:
			if items.def_at(tile) == def:
				on_pass += items.count_at(tile)
		var need: int = int(demand[key][2]) - on_pass
		if need <= 0:
			continue
		wanted[job_key] = true
		if board.has_key(job_key):
			continue
		var target := Vector2i(-1, -1)
		for tile in here["tiles"]:
			if items.accepts(tile, def):
				target = tile
				break
		if target == Vector2i(-1, -1):
			_clear_the_pass(here, demand, wanted)
			continue
		var source := Vector2i(-1, -1)
		for tile in items.tiles_with(id, target):
			if counter.has(tile) or tables.has(tile) or board.has_pickup(tile) or items.available_at(tile) <= 0:
				continue
			source = tile
			break
		if source == Vector2i(-1, -1):
			continue
		var job := Job.new()
		job.kind = WorkType.Kind.COOK
		job.pickup_tile = source
		job.target = target
		job.carry_def = def
		job.carry_count = mini(need, mini(items.available_at(source), def.stack_size))
		job.work_amount = 0.0
		job.label = "Plate %s" % def.display_name.to_lower()
		job.urgency = 1
		job.key = job_key
		board.post(job)


## An order with nowhere on the counter to go: take off a plate that nobody
## at these tables is waiting for. Guests who give up leave their order on
## the pass, and with four dishes on the menu and two tiles to the counter,
## a grilled fish and a loaf were enough to stop every beer in the house.
func _clear_the_pass(here: Dictionary, demand: Dictionary, wanted: Dictionary) -> void:
	for tile in here["tiles"]:
		var def: ItemDef = items.def_at(tile)
		if def == null or demand.has("%d:%s" % [int(here["index"]), def.id]):
			continue
		var key: String = "plate:clear:%d,%d" % [tile.x, tile.y]
		wanted[key] = true
		if board.has_key(key) or board.has_pickup(tile) or items.available_at(tile) <= 0:
			return
		var destination: Vector2i = _off_the_pass(def, tile, here["tiles"])
		if destination == Vector2i(-1, -1):
			continue
		var job := Job.new()
		job.kind = WorkType.Kind.COOK
		job.pickup_tile = tile
		job.target = destination
		job.carry_def = def
		job.carry_count = items.available_at(tile)
		job.work_amount = 0.0
		job.label = "Clear the pass"
		job.urgency = 1
		job.key = key
		board.post(job)
		return


## Back to storage if any will take it, or else the nearest free floor.
func _off_the_pass(def: ItemDef, from: Vector2i, counter: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance: int = 1 << 30
	for entry in build_grid.placements:
		if entry == null or not entry["built"] or not entry["def"].is_storage:
			continue
		for tile in entry["tiles"]:
			var d: int = ItemWorld._chebyshev(tile, from)
			if d < best_distance and items.accepts(tile, def):
				best = tile
				best_distance = d
	if best != Vector2i(-1, -1):
		return best
	for radius in range(1, 5):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile: Vector2i = from + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) != radius or counter.has(tile):
					continue
				if nav != null and nav.is_walkable(tile) and not items.has_stack(tile) and items.accepts(tile, def):
					return tile
	return Vector2i(-1, -1)


## Every built serving counter: {index, tiles}.
func _counters() -> Array:
	var out: Array = []
	if build_grid == null:
		return out
	for i in range(build_grid.placements.size()):
		var entry = build_grid.placements[i]
		if entry != null and entry["built"] and entry["def"].id == &"serving_counter":
			out.append({"index": i, "tiles": entry["tiles"]})
	return out


static func _nearest_counter(counters: Array, table: Vector2i) -> Dictionary:
	var best: Dictionary = counters[0]
	var best_distance: int = 1 << 30
	for c in counters:
		var d: int = ItemWorld._chebyshev(c["tiles"][0], table)
		if d < best_distance:
			best_distance = d
			best = c
	return best


## As many guests as the seating can take, and a queue's worth more. A fixed
## ten left a ninety-six-seat hall nine-tenths empty, the cap filled by people
## still walking up a long plot.
func max_customers() -> int:
	var seats: int = seating.seats.size()
	return clampi(seats + seats / 4 + 4, MAX_CUSTOMERS, 160)


## Customers arrive from the road outside the plot, so they have to walk in
## through whatever entrance the player actually built.
## An end of the high road: guests walk in along it from one side of the map
## or the other, and turn up the lane.
var road_row: int = -1


func _road_tile() -> Vector2i:
	var row: int = road_row if road_row >= 0 else plot.end.y + 1
	for attempt in range(20):
		var x: int = 1 if _rng.randf() < 0.5 else nav.cols - 2
		var tile := Vector2i(x, row + _rng.randi_range(-1, 1))
		if road_row < 0:
			tile = Vector2i(_rng.randi_range(plot.position.x, plot.end.x - 1), row)
		if nav.is_walkable(tile):
			return tile
	return Vector2i(-1, -1)


func _try_spawn(booked: bool = false) -> CustomerBrain:
	if customers.size() >= max_customers():
		return null
	# Nobody comes to a tavern with nowhere to sit. Without this the road fills
	# with people who walk in, wait, and trudge out again.
	if seating.seats.is_empty():
		return null
	# Nor to one with nothing to sell. The same argument, and it matters most on
	# the opening day: the kitchen starts empty by design, and without this the
	# player spends their first morning collecting one-star reviews for a
	# situation the rules gave them. A larder that empties mid-service still
	# strands everybody already inside, which is the part that should hurt.
	if items != null and menu_stock() <= 0:
		return null

	var start: Vector2i = _road_tile()
	if start == Vector2i(-1, -1):
		return null

	var pawn := Pawn.new()
	_holder.add_child(pawn)
	pawn.setup(nav, terrain, start, pawn_material, _rng.randi(), true)

	var brain := CustomerBrain.new()
	brain.name = "Brain"
	pawn.add_child(brain)
	brain.setup(pawn, self, seating, items, nav, _rng.randi())
	if booked:
		brain.mark_booked()
	# Out the way they came, or on along the road the other way.
	var onward: Vector2i = _road_tile()
	brain.exit_tile = onward if onward.x >= 0 else start
	brain.left.connect(_on_customer_left)
	attach_to_clock(pawn, brain)

	# Walk to the middle of the plot to begin with; the seat search takes over
	# once they are inside.
	var inside: Vector2i = nav.random_walkable_in(plot, _rng)
	if inside != Vector2i(-1, -1):
		pawn.goto(inside)

	customers.append(brain)
	return brain


## Feet first, then the head: a patron's pawn steps before its brain decides,
## the same order the scene tree used to process them in.
func attach_to_clock(pawn: Pawn, brain: CustomerBrain) -> void:
	if sim != null:
		sim.attach(pawn)
		sim.attach(brain)


func _on_customer_left(_brain: CustomerBrain, satisfied: bool, bill: int, tip: int) -> void:
	# Everybody reviews, including -- especially -- the ones who walked out. A
	# reputation built only from the people who stayed would be flattering and
	# useless.
	var review: Review = _brain.write_review(satisfied, bill + tip)
	reputation.add(review)
	day_reviews.push_front(review)
	reviewed.emit(review)

	if not satisfied:
		lost_count += 1
		# Read the state the customer gave up *in*: it has not walked out yet, so
		# this still says what it was waiting for when it ran out of patience.
		match _brain.state:
			CustomerBrain.State.SEEKING_SEAT:
				lost_no_seat += 1
			CustomerBrain.State.ORDERING:
				lost_no_menu += 1
			_:
				lost_no_service += 1
		customer_lost.emit()
		return

	served_count += 1
	# A booked guest's meal is the host's book, 2% dearer, on its own line; a
	# walk-in's is ordinary takings.
	var booked: bool = is_instance_valid(_brain) and _brain.booked
	if booked:
		bill += bookings.premium_on(bill)
		booked_takings += bill
	takings += bill + tip
	if ledger != null:
		ledger.earn(Ledger.Line.BOOKINGS if booked else Ledger.Line.TAKINGS, bill)
		ledger.earn(Ledger.Line.TIPS, tip)
	else:
		GameState.gold += bill + tip
	customer_served.emit(bill + tip)


## Reset the day's trade tallies. The ledger keeps the money; this keeps the
## headcount.
func reset_day_tallies() -> void:
	served_count = 0
	lost_count = 0
	lost_no_seat = 0
	lost_no_service = 0
	lost_no_menu = 0
	takings = 0
	booked_takings = 0
	day_reviews.clear()


func remove_customer(brain: CustomerBrain) -> void:
	customers.erase(brain)
	if is_instance_valid(brain.pawn):
		brain.pawn.queue_free()


## One serving job per outstanding line, fetched from wherever the goods are.
##
## Re-derived every frame from who is actually sitting there, in the same spirit
## as JobGenerator: the board should say what the room *is*, not what it was.
func _generate_serve_jobs() -> void:
	var wanted: Dictionary = {}
	_generate_table_jobs(wanted)
	var counter: Array[Vector2i] = pass_tiles()
	if not counter.is_empty():
		_generate_plating(counter, wanted)
	for brain in customers:
		if not is_instance_valid(brain):
			continue
		var table: Vector2i = brain.seating.table_for(brain.seat)
		if table == Seating.NO_SEAT:
			continue

		for line in brain.unserved():
			var def: ItemDef = ItemCatalog.get_def(line["id"])
			if def == null:
				continue

			var key: String = "serve:%d,%d:%s" % [table.x, table.y, def.id]
			# Wanted even when it cannot be posted yet, so a line still waiting
			# on the kitchen is not mistaken below for an abandoned one.
			wanted[key] = true
			if board.has_key(key):
				continue
			if not items.accepts(table, def):
				continue

			# Take from anywhere but the table itself, or a waiter would pick up
			# the meal it just delivered. With a counter, only from the counter: what
			# is there has been plated for the tables, and the shelves are the
			# kitchen's business.
			var source := Vector2i(-1, -1)
			for tile in items.tiles_with(def.id, table):
				if tile == table or (not counter.is_empty() and not counter.has(tile)):
					continue
				source = tile
				break
			if source == Vector2i(-1, -1):
				continue

			var job := Job.new()
			job.kind = WorkType.Kind.SERVE
			job.pickup_tile = source
			job.target = table
			job.carry_def = def
			job.carry_count = mini(line["count"], items.count_at(source))
			job.work_amount = 0.0
			job.label = "Serve %s" % def.display_name
			job.key = key
			board.post(job)

	_cancel_stale_serve_jobs(wanted)


## A serving job outlives its reason the moment the patron gives up and walks
## out, and nothing was clearing them away.
##
## The damage is out of all proportion to the cause. Serving outranks every
## other kind of work, so a board slowly filling with deliveries to tables
## nobody is sitting at eventually pins the whole staff on errands for people
## who left hours ago: the kitchen stops, the washing-up stops, and the tavern
## dies of politeness. Four simulated days of it before the job-kind tally made
## it obvious, and none of it visible in a screenshot.
func _cancel_stale_serve_jobs(wanted: Dictionary) -> void:
	for job in board.jobs.duplicate():
		if wanted.has(job.key):
			continue
		var mine: bool = job.kind == WorkType.Kind.SERVE or job.key.begins_with("bill:")
		# A cook already carrying a plate finishes the run: it is on the counter
		# for the next order, not dropped on the floor.
		if job.key.begins_with("plate:") and job.claimant == null:
			mine = true
		if mine:
			board.cancel_key(job.key)


## Somebody on the door, from design notes section 14.
##
## The host does not conjure tables -- the room holds what it holds. What
## they do is meet people, which buys the tavern time it would otherwise not
## have: an acknowledged guest waits twice as long and holds it against the
## house far less if they do leave. That makes the stand a real decision at a
## rush rather than another thing to build.
##
## One job for the whole doorway rather than one per guest. A host greeting
## the queue is a single act, and ten separate jobs would have four staff
## abandoning the kitchen to say hello to the same four people.
func _generate_host_jobs() -> void:
	var stand: Vector2i = _host_stand()
	if stand == Vector2i(-1, -1):
		return
	var key: String = "host:%d,%d" % [stand.x, stand.y]
	if _ungreeted_count() <= 0:
		# Everybody has been met. The same rule as the serving jobs: an errand
		# with nobody left to run it for has no business on the board.
		board.cancel_key(key)
		return
	if board.has_key(key):
		return

	var job := Job.new()
	job.kind = WorkType.Kind.HOST
	job.target = stand
	job.work_amount = GREET_WORK
	job.label = "Greet the guests"
	job.key = key
	job.on_complete = func(_j: Job) -> void: _greet_everyone()
	board.post(job)


## The first built stand. More than one is the player's business; the job
## only needs somewhere for the host to be standing.
func _host_stand() -> Vector2i:
	if build_grid == null:
		return Vector2i(-1, -1)
	for entry in build_grid.placements:
		if entry == null or not entry["built"] or entry["def"].id != &"host_stand":
			continue
		return entry["tiles"][0]
	return Vector2i(-1, -1)


## The morning's bookings: one job at the stand, for whoever may host, until
## the book closes at 11:00. No host, no bookings -- that is what a host is for.
func _generate_booking_job() -> void:
	var key: String = "host:book"
	var stand: Vector2i = _host_stand()
	if stand == Vector2i(-1, -1) or clock == null or not clock.is_open() \
			or not bookings.wants_taking(clock.day, clock.hour()):
		if board.has_key(key) and board.job_with_key(key) != null and board.job_with_key(key).claimant == null:
			board.cancel_key(key)
		return
	if board.has_key(key):
		return
	var job := Job.new()
	job.kind = WorkType.Kind.HOST
	job.target = stand
	job.work_amount = Bookings.WORK
	job.label = "Take today's bookings"
	job.key = key
	job.on_complete = func(_j: Job) -> void: take_bookings()
	board.post(job)


func take_bookings() -> int:
	return bookings.take(clock.day if clock != null else 1, _rng, seating.seats.size(), reputation.score)


## A booked party whose hour has come walks up the road, one guest a pass.
func _seat_bookings() -> void:
	if clock == null:
		return
	var due: Dictionary = bookings.due(clock.hour())
	if due.is_empty():
		return
	if _try_spawn(true) != null:
		due["arrived"] = int(due["arrived"]) + 1


func _ungreeted_count() -> int:
	var n: int = 0
	for brain in customers:
		if is_instance_valid(brain) and brain.wants_greeting():
			n += 1
	return n


func _greet_everyone() -> void:
	for brain in customers:
		if is_instance_valid(brain):
			brain.greet()


## How much of something is already spoken for by people sitting at tables.
##
## Without this every patron in the room orders the same last loaf: each one
## sees a stock of one when they open the menu, all of them ask for it, one gets
## fed and the rest sit out their patience waiting for bread that was never
## going to arrive. It reads as slow staff and is nothing of the kind, which is
## the worst sort of bug -- the diagnosis the game offers is wrong.
func promised(id: StringName) -> int:
	var n: int = 0
	for brain in customers:
		if not is_instance_valid(brain):
			continue
		for line in brain.unserved():
			if line["id"] == id:
				n += int(line["count"])
	return n


## What a newcomer could actually be sold.
func unpromised(id: StringName) -> int:
	return maxi(items.total_of(id) - promised(id), 0)


func summary() -> String:
	return "%d in · %d served · %d lost (%d no seat, %d unserved, %d nothing to sell) · %dg taken · %d/%d seats free · %d dirty" % [
		customers.size(), served_count, lost_count,
		lost_no_seat, lost_no_service, lost_no_menu, takings,
		seating.usable_free_count(), seating.seats.size(),
		seating.free_count() - seating.usable_free_count()
	]


## Everything a guest can order: the products with a price, in catalogue order.
## Asked for on every order, so worked out once.
static var _menu: Array[StringName] = []


static func menu_ids() -> Array[StringName]:
	if _menu.is_empty():
		for def in ItemCatalog.all():
			if def.category == ItemDef.Category.PRODUCT and def.sell_value > 0:
				_menu.append(def.id)
	return _menu


## How much of the menu is on the premises.
func menu_stock() -> int:
	var n: int = 0
	if items == null:
		return 0
	for id in menu_ids():
		n += items.total_of(id)
	return n
