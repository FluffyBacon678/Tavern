extends "res://dev/regression_group.gd"

## Supplies, goods and the work that moves them: deliveries, dishes,
## quality, hauling, benches, storage and the well.


func run() -> void:
	var world: TavernWorld = fixture_world
	var scenario: Node = fixture_scenario
	await _check_opening_delivery(world, scenario)
	_check_dirty_dishes(world, scenario)
	_check_quality(world)
	_check_stale_jobs(world, scenario)
	_check_dead_pickups(world, scenario)
	_check_already_there(world, scenario)
	_check_going_underfoot(world)
	_check_well(world, scenario)
	_check_storage_filters(world)
	_check_planned_storage_filters()
	_check_bench_surplus(world, scenario)
	_check_hands_on(world, scenario)
	_check_custom_orders(world, scenario)
	_check_fishing(world, scenario)
	_check_blocked_pass(world, scenario)
	_check_auto_supply(world, scenario)


## The opening delivery: the unloading area refuses what it cannot hold,
## charges nothing for a refusal, and goods in a worker's hands still count.
func _check_opening_delivery(world: TavernWorld, scenario: Node) -> void:
	var flour: ItemDef = ItemCatalog.get_def(&"flour")
	var spots: Array[Vector2i] = world.delivery_tiles()
	for tile in spots:
		world.items.place_near(flour, flour.stack_size, tile, 0)
	var before: int = GameState.gold
	check(not world.order_supplies(), "full unloading area refuses delivery")
	check(GameState.gold == before and world.ledger.outgoings() == 0, "refusal charges nothing")
	check(world.items.total_of(&"flour") == spots.size() * flour.stack_size, "refusal preserves existing stock")
	world.items.take(spots[0], flour.stack_size)
	check(not world.order_supplies(), "partial room refuses whole order")
	check(world.items.count_at(spots[0]) == 0 and GameState.gold == before, "no partial delivery or charge")
	world.items.clear()
	check(world.order_supplies(), "empty unloading area accepts order")
	check(GameState.gold == before - 115, "delivery costs exactly 115g")
	check(scenario.reconcile(), "accepted delivery reconciles every ingredient")
	# Two immediate orders need nine stacks but there are only eight slots.
	check(not world.order_supplies(), "repeat order refuses insufficient capacity")
	check(GameState.gold == before - 115 and scenario.reconcile(), "repeat refusal loses neither money nor goods")
	# Force a real haul to exercise stock while in a worker's hands.
	# A porter and a cook: which of them has something to carry depends on
	# whether the shelves or the benches want the delivery first, and since
	# positions only those two carry goods at all.
	world.generator.scan()
	var carriers: Array[Worker] = []
	for role_id in [&"porter", &"cook"]:
		for worker in world.workers:
			if worker.role != null and worker.role.id == role_id:
				carriers.append(worker)
				break
	for worker in carriers:
		worker.set_process(true)
		worker.pawn.set_process(true)
	var found_carry: bool = false
	for attempt in range(2000):
		await get_tree().process_frame
		for worker in carriers:
			if worker.carried_count() > 0:
				found_carry = true
		if found_carry:
			break
	check(found_carry, "worker physically picks up stock")
	check(scenario.reconcile(), "in-transit goods reconcile")


## Dirty dishes have to cost the player something and then be destroyed for
## good.
##
## Three separate claims, and all three have been wrong at some point in a
## system like this: that a dirty table stops being seating, that the generator
## finds a basin to send the mess to, and that washing up removes the goods
## *and* books them. The last is the one worth guarding -- destroying items
## without recording it is invisible in play and only surfaces later as a
## reconciliation that will not close.
func _check_dirty_dishes(world: TavernWorld, scenario: Node) -> void:
	var seating: Seating = world.customers.seating
	if seating.seats.is_empty():
		check(false, "demo layout provides seating to dirty")
		return

	var table: Vector2i = seating.seats[0]["table"]
	var at_that_table: int = 0
	for seat in seating.seats:
		if seat["table"] == table:
			at_that_table += 1

	var dishes: ItemDef = ItemCatalog.get_def(&"dirty_dishes")

	# The basin is for refuse and nothing else. Measured, because the failure is
	# so quiet: a cook spilling a tray of bread onto the basin fills the only
	# place a dirty plate can go, cleaning stops entirely, and what the player
	# sees is a tavern that has mysteriously run out of seats.
	var basin_tiles: Array[Vector2i] = world.generator._wash_tiles()
	check(not basin_tiles.is_empty(), "the demo layout has a wash basin")
	if not basin_tiles.is_empty():
		check(world.items.accepts(basin_tiles[0], dishes), "a basin takes dishes")
		check(
			not world.items.accepts(basin_tiles[0], ItemCatalog.get_def(&"bread")),
			"a basin refuses stock, so it cannot be clogged"
		)

	var usable_before: int = seating.usable_free_count()
	var placed: int = world.items.add(dishes, 3, table)
	# Stand in for the customer who would have left them. Dishes are goods that
	# came into existence; the books have to see them arrive as well as go.
	world.customers.dishes_left += placed
	check(placed == 3, "dishes land on the table")
	check(
		seating.usable_free_count() == usable_before - at_that_table,
		"a dirty table stops being seating"
	)

	var claimed: Vector2i = seating.claim(self, table)
	check(claimed == Seating.NO_SEAT or seating.table_for(claimed) != table, "nobody is seated at the dirty table")
	seating.release(claimed)

	world.generator.scan()
	var clear: Job = null
	for job in world.board.jobs:
		if job.kind == WorkType.Kind.CLEAR and job.pickup_tile == table:
			clear = job
			break
	check(clear != null, "the generator posts a job to clear the table")
	var basins: Array = world.generator._wash_tiles()
	check(clear != null and basins.has(clear.target), "the dishes are sent to a wash basin")

	# Drive the outcome rather than the walk: the worker's carry cycle is
	# exercised elsewhere. Clearing ends with the dishes standing in the basin;
	# washing them there is a second job, which a different person may take.
	if clear != null:
		world.items.take(table, placed)
		world.items.add(dishes, placed, clear.target)
		world.board.complete(clear)
		world.generator.scan()
		var wash: Job = null
		for job in world.board.jobs:
			if job.kind == WorkType.Kind.CLEAN and job.target == clear.target:
				wash = job
				break
		check(wash != null and not wash.needs_pickup(), "dishes standing in the basin are washed where they are")
		check(seating.usable_free_count() == usable_before, "a table is seating again once cleared, before the washing")
		if wash != null:
			wash.apply_work(wash.work_amount)
			world.board.complete(wash)

	check(world.items.total_of(&"dirty_dishes") == 0, "washing up destroys the dishes")
	check(
		world.generator.consumed.get(&"dirty_dishes", 0) == placed,
		"washing up is booked, not silently deleted"
	)
	check(seating.usable_free_count() == usable_before, "a cleared table is seating again")
	check(scenario.reconcile(), "dishes made and washed still reconcile")

	# Stock already spoken for is not on anybody else's menu.
	var beer: ItemDef = ItemCatalog.get_def(&"beer")
	var counter: Vector2i = seating.seats[0]["chair"] + Vector2i(0, 1)
	var put: int = world.items.place_near(beer, 1, counter, 4)
	world.generator.produced[&"beer"] = world.generator.produced.get(&"beer", 0) + put
	check(put == 1, "there is one beer in the house")
	check(world.customers.unpromised(&"beer") == 1, "an unclaimed beer is sellable")

	var thirsty := CustomerBrain.new()
	thirsty.state = CustomerBrain.State.WAITING_FOR_ORDER
	thirsty.order = [{"id": &"beer", "count": 1, "served": 0}]
	world.customers.customers.append(thirsty)
	check(world.customers.promised(&"beer") == 1, "a waiting patron has claimed it")
	check(
		world.customers.unpromised(&"beer") == 0,
		"the last drink in the house is not offered to a second table"
	)
	world.customers.customers.clear()
	thirsty.free()
	for t in world.items.tiles_with(&"beer", counter):
		world.items.take(t, world.items.count_at(t))
	world.generator.consumed[&"beer"] = world.generator.consumed.get(&"beer", 0) + put
	check(scenario.reconcile(), "the promised-stock test leaves the books straight")

	# A serving job has to die with the patron who wanted it. Left behind they
	# are indistinguishable from real work, and serving outranks everything.
	var dining := CustomerBrain.new()
	dining.seating = seating
	dining.seat = seating.chair_of(0)
	dining.state = CustomerBrain.State.WAITING_FOR_ORDER
	dining.order = [{"id": &"beer", "count": 1, "served": 0}]
	world.customers.customers.append(dining)
	var mug: int = world.items.place_near(beer, 2, counter, 4)
	world.generator.produced[&"beer"] = world.generator.produced.get(&"beer", 0) + mug

	world.customers._generate_serve_jobs()
	# With a serving counter the kitchen plates the order first, and the
	# waiter only has something to carry once it is on the counter.
	var pass_tiles: Array[Vector2i] = world.customers.pass_tiles()
	if not pass_tiles.is_empty():
		var plating: bool = false
		for job in world.board.jobs:
			plating = plating or (job.key.begins_with("plate:") and job.key.ends_with(":beer"))
		check(plating, "with a counter, the kitchen is asked to plate the order")
		check(world.board.count_of_kind(WorkType.Kind.SERVE) == 0, "and the waiter waits for it to be plated")
		var plated: int = 0
		for t in world.items.tiles_with(&"beer", counter):
			if plated == 0 and not pass_tiles.has(t):
				plated = world.items.take(t, 1)
		world.items.add(beer, plated, pass_tiles[0])
		for job in world.board.jobs.duplicate():
			if job.key.begins_with("plate:"):
				world.board.cancel_key(job.key)
		world.customers._generate_serve_jobs()
	var serving: int = world.board.count_of_kind(WorkType.Kind.SERVE)
	check(serving == 1, "a seated patron raises a serving job")

	# Now they walk out, and the board has to notice on the very next pass.
	world.customers.customers.clear()
	world.customers._generate_serve_jobs()
	check(
		world.board.count_of_kind(WorkType.Kind.SERVE) == 0,
		"the serving job leaves with the patron who ordered it"
	)

	dining.free()
	for t in world.items.tiles_with(&"beer", counter):
		world.items.take(t, world.items.count_at(t))
	world.generator.consumed[&"beer"] = world.generator.consumed.get(&"beer", 0) + mug
	check(scenario.reconcile(), "the stale-job test leaves the books straight")


## Quality has to travel with the goods.
##
## It is a number attached to a pile of things that get split, merged, carried
## and cooked, and every one of those is a chance to lose it. Losing it is
## invisible -- everything still works, the tavern just quietly serves average
## bread forever and manual cooking stops being worth doing.
func _check_quality(world: TavernWorld) -> void:
	var bread: ItemDef = ItemCatalog.get_def(&"bread")
	var tile: Vector2i = world.plot.position + Vector2i(1, 1)
	while world.items.has_stack(tile):
		tile += Vector2i(1, 0)

	check(is_equal_approx(world.items.quality_at(tile), ItemWorld.BASE_QUALITY), "an empty tile reports ordinary quality")
	world.items.add(bread, 2, tile, 1.0)
	check(is_equal_approx(world.items.quality_at(tile), 1.0), "goods remember how good they are")

	# Two excellent loaves and two dreadful ones make four middling ones, not
	# four excellent ones.
	world.items.add(bread, 2, tile, 0.0)
	var blended: float = world.items.quality_at(tile)
	check(is_equal_approx(blended, 0.5), "mixing batches averages the quality by count")

	world.items.add(bread, 1, tile)
	check(is_equal_approx(world.items.quality_at(tile), blended), "moving goods about does not change them")

	world.items.take(tile, 5)
	check(not world.items.has_stack(tile), "the test stack is cleared away")


## Work has to leave the board when its reason leaves the world.
##
## This is the single most expensive bug the project has had. Jobs were
## re-derived every scan but never withdrawn, so a haul whose goods somebody
## else had already taken stayed on the board forever -- failing for each worker
## in turn, and making has_pickup() lie about that tile for the rest of the run.
## Four simulated days went from sixteen patrons served to none, and every
## screenshot of it looked completely normal.
func _check_stale_jobs(world: TavernWorld, scenario: Node) -> void:
	# Park the one live worker: a claimed job is deliberately left alone, and a
	# hauler wandering into this test would make it say nothing.
	world.workers[0].set_process(false)
	world.pawns[0].set_process(false)

	var flour: ItemDef = ItemCatalog.get_def(&"flour")
	var tile: Vector2i = _free_tile(world, world.plot.position + Vector2i(3, 3))
	var dropped: int = world.items.add(flour, 2, tile, ItemWorld.BASE_QUALITY)
	world.delivered[&"flour"] = world.delivered.get(&"flour", 0) + dropped
	check(dropped == 2, "a loose sack is put down")

	var key: String = "haul:%d,%d" % [tile.x, tile.y]
	world.generator.scan()
	check(world.board.has_key(key), "loose goods raise a hauling job")

	# Somebody else gets there first -- a cook, another hauler, the player.
	world.items.take(tile, dropped)
	world.generator.consumed[&"flour"] = world.generator.consumed.get(&"flour", 0) + dropped
	world.generator.scan()
	check(not world.board.has_key(key), "the hauling job leaves with the goods")

	check(scenario.reconcile(), "the stale-haul test leaves the books straight")


## A waiting job whose goods have gone must leave the board.
##
## It used to stay, because its bench was still hungry and so its key was still
## wanted. Every worker in turn walked over and found nothing; the key then
## blocked a replacement with a live source from ever being posted. That is
## "Fetch Hops refused by 5", and it stopped all brewing in the demo level.
func _check_dead_pickups(world: TavernWorld, scenario: Node) -> void:
	var malt: ItemDef = ItemCatalog.get_def(&"malt")
	var tile: Vector2i = _free_tile(world, world.plot.position + Vector2i(2, 12))
	var put: int = world.items.add(malt, 3, tile, ItemWorld.BASE_QUALITY)
	world.delivered[&"malt"] = world.delivered.get(&"malt", 0) + put

	var job := Job.new()
	job.kind = WorkType.Kind.HAUL
	job.pickup_tile = tile
	job.target = tile + Vector2i(1, 0)
	job.carry_def = malt
	job.carry_count = 2
	job.key = "test:dead-pickup"
	world.board.post(job)
	check(world.board.has_key(job.key), "a pickup job is posted against a stack")
	check(job.reservation != 0, "and holds a claim on it")
	check(world.items.available_at(tile) == put - 2, "the claim hides what it holds from other jobs")

	# The stack is used by something that does not hold the claim -- a cook, a
	# diner -- and the claim must not outlive the goods.
	world.items.take(tile, put)
	world.generator.consumed[&"malt"] = world.generator.consumed.get(&"malt", 0) + put
	check(world.items.available_at(tile) == 0, "an emptied tile has nothing available")
	world.items.add(malt, 1, tile, ItemWorld.BASE_QUALITY)
	world.delivered[&"malt"] = world.delivered.get(&"malt", 0) + 1
	check(
		world.items.available_at(tile) == 1,
		"new goods on a tile are not hidden by a claim on goods that have gone"
	)
	world.items.take(tile, 1)
	world.generator.consumed[&"malt"] = world.generator.consumed.get(&"malt", 0) + 1

	check(world.board.withdraw_dead_pickups() >= 1, "a job whose goods have gone is withdrawn")
	check(not world.board.has_key(job.key), "and its key is freed for a replacement")
	check(scenario.reconcile(), "withdrawing a dead job leaves the books straight")


## A worker already standing where a job wants it does not give the job up.
##
## find_path from a tile to itself has no steps, and goto() reported that as
## "no route". So a worker beside a shelf abandoned the fetch from it, and one
## that picked up beside the bench it was feeding abandoned the delivery: 298
## and 131 times across nine real days of the demo level.
func _check_already_there(world: TavernWorld, scenario: Node) -> void:
	var worker: Worker = world.workers[0]
	var pawn: Pawn = world.pawns[0]
	worker.set_process(false)
	pawn.set_process(false)
	if worker.current != null:
		worker.abandon_job()
	pawn.stop()

	var here: Vector2i = pawn.tile
	var pickup: Vector2i = here + Vector2i(1, 0)
	var target: Vector2i = here + Vector2i(-1, 0)
	if not world.nav.is_walkable(here) or world.items.has_stack(pickup) or world.items.has_stack(target):
		# Wherever the worker stands, move it somewhere that has room either side.
		here = _free_tile(world, world.plot.position + Vector2i(4, 14))
		while world.items.has_stack(here + Vector2i(1, 0)) or world.items.has_stack(here + Vector2i(-1, 0)) 				or not world.nav.is_walkable(here):
			here += Vector2i(0, 1)
		pickup = here + Vector2i(1, 0)
		target = here + Vector2i(-1, 0)
		pawn.tile = here
		pawn.position = pawn.world_position_of(here)

	var hops: ItemDef = ItemCatalog.get_def(&"hops")
	var put: int = world.items.add(hops, 1, pickup, ItemWorld.BASE_QUALITY)
	world.delivered[&"hops"] = world.delivered.get(&"hops", 0) + put
	var job := Job.new()
	job.kind = WorkType.Kind.HAUL
	job.pickup_tile = pickup
	job.target = target
	job.carry_def = hops
	job.carry_count = 1
	job.key = "test:already-there"
	job.work_amount = 0.0  # a plain haul: arriving is the job
	world.board.post(job)

	var no_route: int = Worker.gave_up_no_route
	var undelivered: int = Worker.gave_up_cannot_deliver
	check(world.nav.adjacent_walkable(pickup, here) == here, "the worker is already beside the goods")
	check(worker.start(job, here), "a worker standing beside a job takes it")
	check(Worker.gave_up_no_route == no_route, "being there already is not 'no route'")
	# One step of the pickup: arrive, lift, and turn for a target also beside it.
	worker._process_going_pickup(0.1)
	check(worker.carried_count() == 1, "and it lifts the goods without walking")
	check(Worker.gave_up_cannot_deliver == undelivered,
		"delivering to a tile beside where it stands is not 'could not deliver'")
	worker._process_going(0.1)
	check(world.items.count_at(target) == 1 and worker.current == null, "and it puts them down where asked")
	world.items.take(target, world.items.count_at(target))
	world.generator.consumed[&"hops"] = world.generator.consumed.get(&"hops", 0) + 1
	check(scenario.reconcile(), "a job done on the spot leaves the books straight")


## Flooring has to be worth laying.
##
## It was a third of the opening spend and bought nothing but a colour. Now a
## laid floor is quicker underfoot than a beaten path, and a path quicker than
## grass -- and staff prefer routes over it, because the same figure feeds both
## the pawn's speed and A*'s weights. Weighting alone would route people over
## floors without rewarding them; speed alone would leave them cutting across
## the mud.
func _check_going_underfoot(world: TavernWorld) -> void:
	# Inside the tavern, on laid boards.
	var floored := Vector2i(-1, -1)
	for room in world.rooms.current():
		if not room["tiles"].is_empty():
			floored = room["tiles"][0]
			break
	check(floored != Vector2i(-1, -1), "there is laid flooring to walk on")
	if floored == Vector2i(-1, -1):
		return

	# The supplier's road is packed dirt; the open plot is grass.
	var yard: Rect2i = world.unloading_yard()
	var path_tile := Vector2i(yard.position.x, yard.position.y + 1)
	var rough := Vector2i(world.plot.end.x - 2, world.plot.position.y + 1)

	var on_floor: float = world.nav.cost_at(floored)
	var on_path: float = world.nav.cost_at(path_tile)
	var on_grass: float = world.nav.cost_at(rough)

	check(on_floor < on_path, "boards are quicker than a beaten path")
	check(on_path < on_grass, "and a beaten path quicker than open ground")
	check(is_equal_approx(world.nav.weight_at(floored), 1.0), "flooring is the ground A* measures against")
	check(world.nav.weight_at(rough) > 1.0, "and rough ground costs it more")

	# Still passable, though -- a table out on the grass has to keep working.
	check(world.nav.is_walkable(rough), "rough ground is slower, not forbidden")


## The well has to be worth building, and has to need the river.
##
## Two claims. The placement rule is what makes the back of the plot mean
## something -- without it the river is scenery and the well is just a slower
## way of buying water. And a recipe with no inputs at all is a shape nothing
## else in the catalog has, so the production rules have to cope with it: an
## average over zero ingredients would score every bucket as filthy.
func _check_well(world: TavernWorld, scenario: Node) -> void:
	var well: BuildingDef = BuildingCatalog.get_def(&"well")
	check(well != null and well.needs_water_within > 0, "the well has to reach water")
	if well == null:
		return

	# The middle of the plot is as far from the river as it gets.
	var middle: Vector2i = world.plot.position + world.plot.size / 2
	check(
		world.build.grid.placement_problem(well, middle, 0) == "Must be built near water",
		"a well in the middle of the plot is refused"
	)

	# The back row is not: that is what the river along the boundary is for.
	var bank: Vector2i = Vector2i(world.plot.position.x + 1, world.plot.position.y)
	check(
		world.build.grid.placement_problem(well, bank, 0) == "",
		"a well against the back boundary reaches the river"
	)

	var index: int = world.build.place_programmatic(well, bank, 0, false)
	check(index >= 0, "the well is built")
	if index < 0:
		return

	var draw: Recipe = null
	for recipe in RecipeCatalog.for_station(&"well"):
		draw = recipe
		break
	check(draw != null and draw.inputs.is_empty(), "drawing water takes nothing but time")
	check(draw != null and draw.work_kind == WorkType.Kind.GATHER, "drawing water is gathering, not cooking")
	if draw == null:
		return

	# No ingredients, so it can always be worked -- that is the whole point.
	check(world.generator.can_perform(index, draw), "a built well can always be worked")
	var before: int = world.items.total_of(&"water")
	check(world.generator.perform_by_hand(index, draw, ItemWorld.BASE_QUALITY), "the well yields water")
	var drawn: int = world.items.total_of(&"water") - before
	check(drawn == 3, "a turn at the well draws three barrels")

	# Free water still has to appear in the books, and must not be born filthy.
	var station: Dictionary = world.generator.station_at(index)
	var worst: float = 2.0
	for tile in station["input_tiles"]:
		var here: ItemDef = world.items.def_at(tile)
		if here != null and here.id == &"water":
			worst = minf(worst, world.items.quality_at(tile))
	check(worst >= ItemWorld.BASE_QUALITY, "water drawn by hand is not born spoiled")
	check(scenario.reconcile(), "water out of the ground reconciles like water off a cart")

	world.build.grid.remove(index)
	world.build._rebuild_instances(well)


## A shelf holds what the player told it to, and hauling obeys without being
## told anything.
##
## The point of design notes section 11 is that there is no pantry *type* -- a
## pantry is a shelf with boxes ticked. So the test that matters is not that the
## checkbox works, it is that `accepts()` changes and the rest of the game
## follows from that alone.
func _check_storage_filters(world: TavernWorld) -> void:
	var shelf_index: int = -1
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["built"] and entry["def"].id == &"storage_shelf":
			shelf_index = i
			break
	if shelf_index < 0:
		check(false, "the demo layout has a shelf to filter")
		return

	var tile: Vector2i = world.build.grid.placements[shelf_index]["tiles"][0]
	var bread: ItemDef = ItemCatalog.get_def(&"bread")
	var flour: ItemDef = ItemCatalog.get_def(&"flour")
	# Clear it, so what accepts() says is about the filter and not about a stack
	# that happens to be sitting there.
	var cleared: int = world.items.count_at(tile)
	var was: ItemDef = world.items.def_at(tile)
	if cleared > 0:
		world.items.take(tile, cleared)

	check(world.build.grid.allows(shelf_index, &"flour"), "a new shelf holds anything")
	check(world.items.accepts(tile, flour), "an unfiltered shelf takes flour")

	world.build.grid.toggle_filter(shelf_index, &"bread")
	check(world.build.grid.allows(shelf_index, &"bread"), "a dedicated shelf holds what was ticked")
	check(not world.build.grid.allows(shelf_index, &"flour"), "and stops holding everything else")
	check(world.items.accepts(tile, bread), "the goods it was dedicated to still fit")
	check(not world.items.accepts(tile, flour), "hauling is turned away without being told about filters")

	# Unticking the last box means "anything" again, not "nothing" -- a shelf that
	# silently became useless would read as broken storage.
	world.build.grid.toggle_filter(shelf_index, &"bread")
	check(world.build.grid.filter_of(shelf_index).is_empty(), "unticking the last box clears the filter")
	check(world.items.accepts(tile, flour), "a cleared shelf takes anything again")

	if cleared > 0 and was != null:
		world.items.add(was, cleared, tile)


## Preflight must agree with physical placement on both kinds of filter.
## A zero search radius makes each refusal meaningful: no neighbouring tile
## can quietly rescue an invalid planned destination. This isolated fixture
## does not open a save slot or alter the running tavern's inventory.
func _check_planned_storage_filters() -> void:
	var grid := BuildGrid.new()
	grid.setup(6, 6, Rect2i(0, 0, 6, 6))
	var shelf_tile := Vector2i(1, 1)
	var sink_tile := Vector2i(4, 4)
	var shelf: int = grid.place(BuildingCatalog.get_def(&"storage_shelf"), shelf_tile, 0, true)
	var sink: int = grid.place(BuildingCatalog.get_def(&"sink"), sink_tile, 0, true)
	check(shelf >= 0 and sink >= 0, "storage-plan fixture builds a shelf and wash basin")
	var items := ItemWorld.new()
	items.bind_build(grid)
	var flour: ItemDef = ItemCatalog.get_def(&"flour")
	var bread: ItemDef = ItemCatalog.get_def(&"bread")
	var beer: ItemDef = ItemCatalog.get_def(&"beer")
	var dishes: ItemDef = ItemCatalog.get_def(&"dirty_dishes")
	_check_storage_plan(items, flour, shelf_tile, true, "unfiltered shelf accepts planned flour")
	grid.set_filter(shelf, [&"bread"])
	_check_storage_plan(items, bread, shelf_tile, true, "bread-only shelf accepts planned bread")
	_check_storage_plan(items, flour, shelf_tile, false, "bread-only shelf refuses planned flour")
	_check_storage_plan(items, beer, shelf_tile, false, "bread-only shelf refuses beer despite matching bread's category")
	_check_storage_plan(items, dishes, sink_tile, true, "refuse-only basin accepts planned dishes")
	_check_storage_plan(items, bread, sink_tile, false, "refuse-only basin refuses planned food")
	grid.set_filter(sink, [&"bread"])
	_check_storage_plan(items, bread, sink_tile, false, "item whitelist cannot override basin's refuse category")
	_check_storage_plan(items, dishes, sink_tile, false, "matching category cannot override an item whitelist")
	grid.set_filter(sink, [&"dirty_dishes"])
	_check_storage_plan(items, dishes, sink_tile, true, "matching category and item whitelist accept dishes")
	grid.set_filter(shelf, [])
	_check_storage_plan(items, flour, shelf_tile, true, "cleared whitelist restores unrestricted planning")
	_check_storage_plan(items, flour, Vector2i(-1, 1), false, "planning refuses a tile outside the map")
	check(items.all_tiles().is_empty(), "storage preflight never creates physical stock")
	items.free()


## A bench holds back what it needs and no more.
##
## The rule that stops haulers carrying a cook's flour back to the shelf has to
## stop at the amount the recipe actually wants. Protecting everything nearby
## looks harmless and is not: surplus dumped around a bench becomes unhaulable,
## the free tiles fill, and the station can no longer be given the one thing it
## is short of. That is a kitchen standing idle beside a full yard, and nothing
## in the game would tell you why.
func _check_bench_surplus(world: TavernWorld, scenario: Node) -> void:
	var prep_index: int = -1
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["built"] and entry["def"].id == &"prep_table":
			prep_index = i
			break
	if prep_index < 0:
		check(false, "the demo layout has a prep table")
		return

	var station: Dictionary = world.generator.station_at(prep_index)
	var flour: ItemDef = ItemCatalog.get_def(&"flour")

	# Two separate tiles of an ingredient the recipe only wants one of.
	var placed: Array[Vector2i] = []
	for tile in station["input_tiles"]:
		if placed.size() >= 2:
			break
		if world.items.has_stack(tile) or not world.items.accepts(tile, flour):
			continue
		if world.items.add(flour, 1, tile, ItemWorld.BASE_QUALITY) > 0:
			world.delivered[&"flour"] = world.delivered.get(&"flour", 0) + 1
			placed.append(tile)
	check(placed.size() == 2, "two sacks are set down at the bench")
	if placed.size() < 2:
		return

	world.generator.scan()
	var held: int = 0
	var free: int = 0
	for tile in placed:
		if world.generator._wanted.has(tile) and world.generator._wanted[tile].has(&"flour"):
			held += 1
		else:
			free += 1
	check(held >= 1, "the bench keeps the sack it is working with")
	check(free >= 1, "and lets the surplus be filed away")

	for tile in placed:
		var n: int = world.items.count_at(tile)
		if n > 0 and world.items.def_at(tile) == flour:
			world.items.take(tile, n)
			world.generator.consumed[&"flour"] = world.generator.consumed.get(&"flour", 0) + n
	check(scenario.reconcile(), "the bench surplus test leaves the books straight")


## Doing it yourself has to be worth doing, and has to play by the same rules.
##
## The failure that would matter is the one where stepping in is free: a bench
## that hands over bread without taking the flour, or a hand-baked loaf that is
## no better than the cook's. Either one turns section 22 from a decision into a
## button you press whenever it is visible.
func _check_hands_on(world: TavernWorld, scenario: Node) -> void:
	var oven_index: int = -1
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["built"] and entry["def"].id == &"oven":
			oven_index = i
			break
	if oven_index < 0:
		check(false, "the demo layout has an oven to work at")
		return

	var bake: Recipe = null
	for recipe in RecipeCatalog.for_station(&"oven"):
		bake = recipe
		break
	check(bake != null, "the oven has something to bake")
	if bake == null:
		return

	check(not world.generator.can_perform(oven_index, bake), "an empty oven cannot be worked by hand")

	var station: Dictionary = world.generator.station_at(oven_index)
	var bench: Vector2i = station["tiles"][0]
	var dough: ItemDef = ItemCatalog.get_def(&"dough")
	var bread: ItemDef = ItemCatalog.get_def(&"bread")

	# Ordinary dough on the bench, as a hauler would have left it. Counted as
	# produced, standing in for the prep table that would have made it -- the
	# books have to balance at the end of this like any other batch.
	_stock_bench(world, dough, bench, 1)
	check(world.generator.can_perform(oven_index, bake), "a stocked oven can be worked by hand")

	var dough_before: int = world.items.total_of(&"dough")
	var bread_before: int = world.items.total_of(&"bread")
	check(world.generator.perform_by_hand(oven_index, bake, 1.0), "a faultless turn at the oven produces something")
	check(world.items.total_of(&"dough") == dough_before - 1, "working by hand still uses the ingredients")
	check(world.items.total_of(&"bread") > bread_before, "working by hand yields the recipe's output")
	check(not world.generator.can_perform(oven_index, bake), "the bench is empty again afterwards")

	# Move the good loaves off the bench before baking a bad batch. Left where
	# they are, the two would merge into one middling stack and the comparison
	# below would quietly measure nothing.
	var excellent: float = _clear_bench(world, station, bread, _free_tile(world, world.plot.position + Vector2i(2, 2)))
	check(excellent > ItemWorld.BASE_QUALITY, "a good pair of hands turns out better than ordinary bread")

	_stock_bench(world, dough, bench, 1)
	check(world.generator.perform_by_hand(oven_index, bake, 0.0), "a clumsy turn still produces something")
	var dreadful: float = _clear_bench(world, station, bread, _free_tile(world, world.plot.position + Vector2i(4, 2)))
	check(dreadful < ItemWorld.BASE_QUALITY, "a clumsy pair of hands turns out worse than ordinary bread")
	check(dreadful < excellent, "how well the player does is what decides the difference")

	check(scenario.reconcile(), "hand-made goods reconcile like any other")


func _check_storage_plan(items: ItemWorld, def: ItemDef, tile: Vector2i,
		allowed: bool, message: String) -> void:
	var plan: Variant = items.plan_placement([{"def": def, "count": 1, "around": tile, "radius": 0}])
	var valid: bool = plan is Dictionary and plan.has("ok") and plan.has("placements")
	check(valid, "%s returns a valid plan" % message)
	if not valid:
		return
	check(items.accepts(tile, def) == allowed and bool(plan["ok"]) == allowed, message)
	if allowed:
		var placements: Array = plan["placements"]
		check(placements.size() == 1 and placements[0]["tile"] == tile
			and placements[0]["count"] == 1 and placements[0]["def"] == def,
			"accepted plan preserves the requested item, count and destination")
	else:
		check(plan["placements"].is_empty(), "refused plan commits no partial output")


## Put ingredients on a bench and book them as though a station had made them.
func _stock_bench(world: TavernWorld, def: ItemDef, tile: Vector2i, count: int) -> void:
	var placed: int = world.items.add(def, count, tile, ItemWorld.BASE_QUALITY)
	world.generator.produced[def.id] = world.generator.produced.get(def.id, 0) + placed


## Take everything of one kind off a station and park it elsewhere, returning
## what it was worth. Nothing is destroyed, so the reconciliation is untouched.
func _clear_bench(world: TavernWorld, station: Dictionary, def: ItemDef, parked: Vector2i) -> float:
	var quality: float = -1.0
	for tile in station["input_tiles"]:
		var here: ItemDef = world.items.def_at(tile)
		if here == null or here.id != def.id:
			continue
		quality = world.items.quality_at(tile)
		var n: int = world.items.count_at(tile)
		world.items.take(tile, n)
		world.items.place_near(def, n, parked, 6, quality)
	return quality


## The order screen: the player picks the order, and the money moves only on
## confirm -- or not at all, with the reason, when it cannot be delivered.
func _check_custom_orders(world: TavernWorld, scenario: Node) -> void:
	check(world.order_cost(TavernWorld.STANDARD_ORDER) == 115, "the standard bundle still costs 115g")
	check(world.order_cost({&"yeast": 2}) == 2 + TavernWorld.DELIVERY_FEE, "a small order is its goods plus the cart fee")
	check(world.order_cost({}) == 0 and world.order_problem({}) != "", "an empty order costs nothing and cannot be confirmed")
	var gold: int = GameState.gold
	GameState.gold = 100000
	check(world.order_problem({&"water": 1000}).contains("yard"), "an order the yard cannot hold says so")
	GameState.gold = 3
	check(world.order_problem({&"malt": 2}).contains("gold"), "an order the purse cannot cover says so")
	check(not world.order_supplies({&"malt": 2}) and GameState.gold == 3, "and is refused without charge")
	GameState.gold = gold
	var yeast_before: int = int(world.delivered.get(&"yeast", 0))
	if world.order_problem({&"yeast": 2}) == "":
		check(world.order_supplies({&"yeast": 2}), "a small custom order is delivered")
		check(int(world.delivered.get(&"yeast", 0)) == yeast_before + 2, "exactly what was ordered arrives")
		check(GameState.gold == gold - 7, "and exactly its price is paid")
		check(scenario.reconcile(), "a custom order reconciles")
	else:
		check(false, "the fixture yard could take two jars of yeast: %s" % world.order_problem({&"yeast": 2}))


## Fishing: a spot on the bank, a catch the simulation's dice decide, and a
## fish that becomes two things at the prep table. Free food still has to
## balance the books, and a catch is booked as the fish it actually was.
func _check_fishing(world: TavernWorld, scenario: Node) -> void:
	var spot: BuildingDef = BuildingCatalog.get_def(&"fishing_spot")
	check(spot != null and spot.needs_water_within > 0 and spot.needs_water_within < 6,
		"a fishing spot has to stand nearer the water than a well")
	if spot == null:
		return
	var middle: Vector2i = world.plot.position + world.plot.size / 2
	check(world.build.grid.placement_problem(spot, middle, 0) == "Must be built near water",
		"a fishing spot in the middle of the plot is refused")
	var bank := Vector2i(-1, -1)
	for x in range(world.plot.position.x, world.plot.end.x - 1):
		var tile := Vector2i(x, world.plot.position.y)
		if world.build.grid.placement_problem(spot, tile, 0) == "":
			bank = tile
			break
	check(bank != Vector2i(-1, -1), "somewhere on the back boundary is near enough the river to fish")
	if bank == Vector2i(-1, -1):
		return
	var index: int = world.build.place_programmatic(spot, bank, 0, false)
	check(index >= 0, "the fishing spot is built")
	if index < 0:
		return

	var catch: Recipe = RecipeCatalog.get_recipe(&"catch_fish")
	check(catch != null and catch.inputs.is_empty() and catch.work_kind == WorkType.Kind.FISH,
		"fishing takes nothing but a fisherman's time")
	check(StaffRole.for_kind(WorkType.Kind.FISH) == StaffRole.of(&"fisherman"), "and it is the fisherman's work")
	if catch != null:
		var fish: Array[StringName] = [&"trout", &"perch"]
		var held: int = 0
		var booked: int = 0
		for id in fish:
			held += world.items.total_of(id)
			booked += int(world.generator.produced.get(id, 0))
		var dice: int = world.sim_rng.state
		check(world.generator.perform_by_hand(index, catch, ItemWorld.BASE_QUALITY), "the river gives up a catch")
		var caught: int = -held
		var counted: int = -booked
		for id in fish:
			caught += world.items.total_of(id)
			counted += int(world.generator.produced.get(id, 0))
		check(caught >= 1 and caught <= catch.pick_most, "a catch is one or two fish (%d)" % caught)
		check(counted == caught, "and is booked as the fish it was, not as the recipe's placeholder")
		check(world.sim_rng.state != dice, "the catch is rolled on the simulation's own dice")
		check(_output_counts_catch(world, catch), "a standing order for fish counts trout and perch alike")

	# Cleaned at the prep table: one fish in, a fillet and a head out.
	var prep: Dictionary = {}
	for station in world.generator.built_stations():
		if station["def"].id == &"prep_table":
			prep = station
	check(not prep.is_empty(), "the fixture has a prep table to clean fish at")
	if not prep.is_empty():
		var trout: ItemDef = ItemCatalog.get_def(&"trout")
		var put: Vector2i = Vector2i(-1, -1)
		for tile in prep["input_tiles"]:
			if not world.items.has_stack(tile) and world.items.accepts(tile, trout):
				put = tile
				break
		check(put != Vector2i(-1, -1), "the prep table has room for a fish")
		if put != Vector2i(-1, -1):
			world.items.add(trout, 1, put, ItemWorld.BASE_QUALITY)
			world.delivered[&"trout"] = int(world.delivered.get(&"trout", 0)) + 1
			var fillets: int = world.items.total_of(&"fillet")
			var heads: int = world.items.total_of(&"fish_head")
			var trouts: int = world.items.total_of(&"trout")
			var clean: Recipe = RecipeCatalog.get_recipe(&"clean_trout")
			check(world.generator.perform_by_hand(prep["index"], clean, ItemWorld.BASE_QUALITY),
				"a trout can be cleaned at the prep table")
			check(world.items.total_of(&"fillet") == fillets + 1 and world.items.total_of(&"fish_head") == heads + 1
				and world.items.total_of(&"trout") == trouts - 1,
				"one fish makes a fillet for the grill and a head for the pot")
	check(scenario.reconcile(), "fish out of the river reconcile like goods off a cart")

	world.build.grid.remove(index)
	world.build._rebuild_instances(spot)


func _output_counts_catch(world: TavernWorld, catch: Recipe) -> bool:
	var both: int = world.items.total_of(&"trout") + world.items.total_of(&"perch")
	return world.generator._output_stock(catch) == both


## A counter full of plates nobody wants any more still has to take the next
## order: a cook carries one off. Found by the tutorial soak -- guests who gave
## up left bread and grilled fish on both tiles, and no beer was served again.
func _check_blocked_pass(world: TavernWorld, scenario: Node) -> void:
	var pass_tiles: Array[Vector2i] = world.customers.pass_tiles()
	check(not pass_tiles.is_empty(), "the fixture has a serving counter")
	if pass_tiles.is_empty():
		return
	var bread: ItemDef = ItemCatalog.get_def(&"bread")
	var beer: ItemDef = ItemCatalog.get_def(&"beer")
	for tile in pass_tiles:
		world.items.add(bread, 1, tile)
	world.delivered[&"bread"] = int(world.delivered.get(&"bread", 0)) + pass_tiles.size()
	var mug: int = world.items.place_near(beer, 1, pass_tiles[0], 4)
	world.delivered[&"beer"] = int(world.delivered.get(&"beer", 0)) + mug
	var seating: Seating = world.customers.seating
	seating.refresh()
	var thirsty := CustomerBrain.new()
	thirsty.seating = seating
	thirsty.seat = seating.chair_of(0)
	thirsty.state = CustomerBrain.State.WAITING_FOR_ORDER
	thirsty.order = [{"id": &"beer", "count": 1, "served": 0}]
	world.customers.customers.append(thirsty)
	world.customers._generate_serve_jobs()
	var clearing: Job = null
	for job in world.board.jobs:
		if job.key.begins_with("plate:clear:"):
			clearing = job
	check(clearing != null and clearing.kind == WorkType.Kind.COOK and clearing.carry_def == bread,
		"with the pass full of bread nobody ordered, a cook is sent to clear a tile for the beer")
	check(clearing != null and not pass_tiles.has(clearing.target), "and the bread goes somewhere off the counter")
	for job in world.board.jobs.duplicate():
		if job.key.begins_with("plate:"):
			world.board.cancel_key(job.key)
	world.customers.customers.clear()
	thirsty.free()
	for id in [&"bread", &"beer"]:
		for tile in world.items.tiles_with(id, pass_tiles[0]):
			var n: int = world.items.take(tile, world.items.count_at(tile))
			world.delivered[id] = int(world.delivered.get(id, 0)) - n
	check(scenario.reconcile(), "the blocked-pass test leaves the books straight")


## Auto-order: the stock targets buy their own ingredients, traced back through
## dough to flour, never what the player marked, never tonight's wages, and not
## every half hour.
func _check_auto_supply(world: TavernWorld, scenario: Node) -> void:
	var auto: AutoSupply = world.auto_supply
	var bills: BillBook = world.bills
	var gold: int = GameState.gold
	var supplies: int = int(world.ledger.today.get(Ledger.Line.SUPPLIES, 0))
	auto.enabled = true
	auto.never.clear()
	bills.set_target(&"bake_bread", world.stock_of(&"bread") + 20)
	bills.set_target(&"brew_beer", world.stock_of(&"beer") + 200)
	var wanted: Dictionary = auto.shortfall()
	check(wanted.has(&"flour") and wanted.has(&"yeast") and wanted.has(&"malt") and wanted.has(&"hops"),
		"a bread and a beer target want flour and yeast (through dough), malt and hops: %s" % AutoSupply.describe(wanted))
	check(not wanted.has(&"trout") and not wanted.has(&"dough"), "nothing the merchant does not sell is wanted")
	auto.set_never(&"water", true)
	check(not auto.shortfall().has(&"water"), "an ingredient marked never-buy is left out")
	auto.set_never(&"water", false)

	# Ordered, once, then not again until the cooldown has passed.
	GameState.gold = 100000
	auto._since_order = AutoSupply.COOLDOWN
	var order: Dictionary = auto.check()
	check(not order.is_empty() and auto.last_order == order and GameState.gold < 100000,
		"when the larder is short it orders by itself: %s" % AutoSupply.describe(order))
	check(auto.check().is_empty(), "and not again straight away")

	# The wages stay in the purse.
	auto._since_order = AutoSupply.COOLDOWN
	bills.set_target(&"bake_bread", world.stock_of(&"bread") + 40)
	GameState.gold = world.wage_bill() + 1
	check(auto.check().is_empty() and auto.note.contains("wages"), "an order that would eat tonight's wages waits, and says so")

	# Targets met, nothing to buy; switched off, nothing at all.
	bills.set_target(&"bake_bread", 0)
	bills.set_target(&"brew_beer", 0)
	check(auto.shortfall().is_empty(), "with the targets met there is nothing to buy")
	auto.enabled = false
	auto._since_order = AutoSupply.COOLDOWN
	bills.set_target(&"bake_bread", 40)
	GameState.gold = 100000
	check(auto.check().is_empty(), "switched off, it never orders")

	var saved: Dictionary = auto.capture()
	var copy := AutoSupply.new()
	auto.set_never(&"water", true)
	copy.restore(auto.capture())
	check(not copy.enabled and copy.never.has(&"water"), "the switch and the never-buy marks survive a save")
	auto.set_never(&"water", false)

	# Leave the fixture as found: its larder has the delivery in it now, which
	# the books count as delivered.
	auto.enabled = true
	auto.note = ""
	bills.reset_to_defaults()
	var spent: int = int(world.ledger.today.get(Ledger.Line.SUPPLIES, 0)) - supplies
	GameState.gold = gold - spent
	check(scenario.reconcile(), "auto-ordered goods reconcile like any delivery")

