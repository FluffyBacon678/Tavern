extends "res://dev/regression_group.gd"

## Patrons and staff: the host, reviews, seats that move under diners,
## reloading with people at table, and letting staff go.


func run() -> void:
	var world: TavernWorld = fixture_world
	var scenario: Node = fixture_scenario
	open_for_trade(world)
	_check_host(world)
	_check_reviews(world)
	_check_seat_shuffle(world)
	await _check_reload_with_diners(world)
	_check_dismissal(world, scenario)
	_check_positions(world)
	_check_fisherman(world)
	_check_service_loop(world)
	_check_fish_menu(world)
	_check_guest_types(world)


## A host has to be worth their wage, and has to stop existing when the stand
## does.
##
## The thing worth guarding is the "one job for the doorway" rule. Posted per
## guest instead, a busy door would pull every worker out of the kitchen to
## greet the same queue, and the tavern would starve while being extremely
## polite about it.
func _check_host(world: TavernWorld) -> void:
	var director: CustomerDirector = world.customers
	var stand: Vector2i = director._host_stand()
	check(stand != Vector2i(-1, -1), "the demo layout has a host's stand")

	var pretend := CustomerBrain.new()
	pretend.state = CustomerBrain.State.SEEKING_SEAT
	check(pretend.wants_greeting(), "an unwelcomed guest wants greeting")
	var patience_before: float = pretend._patience
	check(pretend.greet(), "a guest can be greeted")
	check(pretend._patience > patience_before, "being greeted buys real patience")
	check(not pretend.greet(), "nobody is greeted twice")
	check(not pretend.wants_greeting(), "a welcomed guest is left alone")

	# Somebody already eating is not a candidate, however long they have been in.
	var seated := CustomerBrain.new()
	seated.state = CustomerBrain.State.EATING
	check(not seated.wants_greeting(), "a guest already eating does not want greeting")

	# One job for the whole door, not one per head.
	var queued := CustomerBrain.new()
	queued.state = CustomerBrain.State.SEEKING_SEAT
	var before: int = world.board.count_of_kind(WorkType.Kind.HOST)
	director.customers.append(pretend)
	director.customers.append(queued)
	director._generate_host_jobs()
	director._generate_host_jobs()
	var posted: int = world.board.count_of_kind(WorkType.Kind.HOST) - before
	check(posted == 1, "a queue at the door raises one greeting job, not one each")

	world.board.cancel_key("host:%d,%d" % [stand.x, stand.y])
	director.customers.clear()
	pretend.free()
	seated.free()
	queued.free()


## A review has to name the thing that went wrong, and reputation has to move
## the only number it exists to move.
##
## The scoring table is easy to get subtly backwards -- a sign flipped, a
## component blaming the wrong department -- and the symptom would be a player
## told to hire waiters when what they need is chairs. So each component is
## exercised on its own, with everything else held perfect.
func _check_reviews(world: TavernWorld) -> void:
	var perfect: Review = Review.write("Test", true, 18, 0.0, 0.0, 2, 0.0, 1.0)
	check(perfect.satisfaction >= 90, "a faultless visit scores near full marks")
	check(perfect.stars == 5, "a faultless visit is five stars")

	var plain: Review = Review.write("Test", true, 18, 0.0, 0.0, 2, 0.0, ItemWorld.BASE_QUALITY)
	check(plain.satisfaction < perfect.satisfaction, "better cooking earns a better review")
	check(
		int(plain.parts[Review.Part.FOOD]) > int(Review.SWING[Review.Part.FOOD][1]),
		"ordinary cooking is unremarkable rather than a complaint"
	)

	var bad_food: Review = Review.write("Test", true, 18, 0.0, 0.0, 2, 0.0, 0.0)
	check(bad_food.worst_part() == Review.Part.FOOD, "bad cooking is blamed on the food")

	var slow: Review = Review.write("Test", true, 18, 0.0, 1.0, 2, 0.0, 1.0)
	check(slow.satisfaction < perfect.satisfaction, "a long wait for food costs satisfaction")
	check(slow.worst_part() == Review.Part.SERVICE, "a long wait is blamed on service")

	var dirty: Review = Review.write("Test", true, 18, 0.0, 0.0, 2, 1.0, 1.0)
	check(dirty.worst_part() == Review.Part.CLEANLINESS, "a filthy room is blamed on cleanliness")

	# The distinction that matters most: somebody who never found a table must
	# not be recorded as a complaint about the waiting staff.
	var turned_away: Review = Review.write("Test", false, 0, 1.0, -1.0, 2, 0.0)
	check(turned_away.worst_part() == Review.Part.SEATING, "a patron with no table blames the seating")
	check(int(turned_away.parts[Review.Part.SERVICE]) == 0, "an unseated patron does not blame the waiters")

	var empty_larder: Review = Review.write("Test", false, 0, 0.0, -1.0, 0, 0.0)
	check(empty_larder.worst_part() == Review.Part.FOOD, "nothing to sell is blamed on the menu")

	# Reputation: a fresh house is middling, and praise and complaints move it in
	# the directions their names suggest.
	var standing := Reputation.new()
	var fresh: float = standing.score
	check(is_equal_approx(fresh, Reputation.NEUTRAL), "an unknown tavern starts neutral")
	for i in range(Reputation.MEMORY):
		standing.add(perfect)
	check(standing.score > fresh, "praise raises the standing")
	var praised: float = standing.footfall_multiplier()
	for i in range(Reputation.MEMORY):
		standing.add(turned_away)
	check(standing.score < fresh, "complaints sink the standing")
	check(standing.footfall_multiplier() < praised, "a sunk standing thins the footfall")
	check(standing.window.size() == Reputation.MEMORY, "the town only remembers the last few visits")

	# Round trip: the score has to come back, because it decides tomorrow.
	var restored := Reputation.new()
	restored.from_save(standing.to_save())
	check(is_equal_approx(restored.score, standing.score), "standing survives a save")

	check(world.customers.reputation != null, "the tavern has a standing to lose")


## Knocking down a chair renumbers every seat after it. Patrons used to hold
## their seat by that number; now they hold it by its chair, and a renumbering
## must leave them exactly where they were -- while the patron whose chair it
## was gets up rather than sitting on in a seat that no longer exists.
func _check_seat_shuffle(world: TavernWorld) -> void:
	var seating: Seating = world.customers.seating
	seating.refresh()
	if seating.seats.size() < 3:
		check(false, "the seat fixture needs three seats")
		return
	var patrons: Array = []
	for i in range(2):
		world.customers._try_spawn()
		var brain: CustomerBrain = world.customers.customers[world.customers.customers.size() - 1]
		brain.set_process(false)
		brain.pawn.set_process(false)
		patrons.append(brain)
	var early: CustomerBrain = patrons[0]
	var late: CustomerBrain = patrons[1]
	var last: int = seating.seats.size() - 1
	for pair in [[early, 0], [late, last]]:
		var brain: CustomerBrain = pair[0]
		var i: int = pair[1]
		brain.seat = seating.chair_of(i)
		check(seating.take(brain, brain.seat), "the fixture seats its patron")
		brain.state = CustomerBrain.State.ORDERING
	var late_chair: Vector2i = late.seat
	var late_table: Vector2i = seating.table_of(last)

	# Knock down the first seat's chair, the way the demolish tool does.
	var chair_tile: Vector2i = seating.chair_of(0)
	var chair_index: int = world.build.grid.placement_at(chair_tile)
	var chair_entry: Dictionary = world.build.grid.placements[chair_index]
	var chair_def: BuildingDef = chair_entry["def"]
	var chair_rotation: int = chair_entry["rotation"]
	world.build.mode = BuildController.Mode.DEMOLISH
	world.build.update_hover(chair_tile, true)
	check(world.build.try_demolish(), "the chair can be knocked down")
	world.build.mode = BuildController.Mode.OFF

	check(late.seat == late_chair and seating.holder_of(late_chair) == late,
		"a patron whose seat was renumbered keeps their own chair")
	check(seating.table_for(late.seat) == late_table, "and still waits at their own table")
	check(early.seat == Seating.NO_SEAT and early.state == CustomerBrain.State.SEEKING_SEAT,
		"the patron whose chair went gets up and looks for another")

	# After ordering there is no table to be served at: they pay and go.
	late.order = [{"id": &"beer", "count": 1, "served": 1}]
	late.state = CustomerBrain.State.WAITING_FOR_ORDER
	var table_index: int = world.build.grid.placement_at(seating.table_for(late.seat))
	var served_before: int = world.customers.served_count
	world.build.mode = BuildController.Mode.DEMOLISH
	world.build.update_hover(seating.table_for(late.seat), true)
	var table_entry: Dictionary = world.build.grid.placements[table_index]
	var table_def: BuildingDef = table_entry["def"]
	var table_origin: Vector2i = table_entry["origin"]
	var table_rotation: int = table_entry["rotation"]
	world.build.try_demolish()
	world.build.mode = BuildController.Mode.OFF
	check(late.state == CustomerBrain.State.LEAVING or late.state == CustomerBrain.State.GONE,
		"a patron whose table goes after ordering pays for what they had and leaves")
	check(world.customers.served_count == served_before + 1, "and is counted as served, having been")

	# Put the room back as it was for the checks that follow.
	world.build.place_programmatic(chair_def, chair_tile, chair_rotation, true)
	world.build.place_programmatic(table_def, table_origin, table_rotation, true)
	for brain in patrons:
		if is_instance_valid(brain):
			world.customers.seating.release_for(brain)
			world.customers.remove_customer(brain)
	seating.refresh()


## Loading on top of a live room must not make anyone pay.
##
## The furniture is rebuilt piece by piece on load, and a patron still seated
## lost their chair mid-way -- and a patron who has eaten pays on the way out,
## crediting money the save never held. The chaos test caught it once a load
## could land on a world that had already loaded itself.
func _check_reload_with_diners(world: TavernWorld) -> void:
	var data: Dictionary = SaveGame.capture(world)
	var slot: int = GameState.active_slot
	GameState.active_slot = -1
	var room: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(room)
	room.set_process(false)
	SaveGame.apply(room, data)
	room.sim.speed = 0
	room.customers._try_spawn()
	check(not room.customers.customers.is_empty(), "the reload fixture has a diner")
	if not room.customers.customers.is_empty():
		var brain: CustomerBrain = room.customers.customers[room.customers.customers.size() - 1]
		brain.set_process(false)
		brain.pawn.set_process(false)
		brain.seat = room.customers.seating.claim(brain, brain.pawn.tile)
		brain.order = [{"id": &"beer", "count": 1, "served": 1}]
		brain.state = CustomerBrain.State.WAITING_FOR_ORDER
		var purse: int = GameState.gold
		SaveGame.apply(room, SaveGame.capture(room))
		check(GameState.gold == purse, "reloading a room with diners in it credits nothing")
	room.queue_free()
	await get_tree().process_frame
	GameState.active_slot = slot


## Staff can be let go: paid for the day, and never taking goods with them.
func _check_dismissal(world: TavernWorld, scenario: Node) -> void:
	world.bootstrap._add_pawn(world._find("Pawns"), 4242)
	var worker: Worker = world.workers[world.workers.size() - 1]
	var pawn: Pawn = worker.pawn
	worker.set_process(false)
	pawn.set_process(false)
	var flour: ItemDef = ItemCatalog.get_def(&"flour")
	worker.restore_cargo(flour, 2, ItemWorld.BASE_QUALITY)
	world.delivered[&"flour"] = world.delivered.get(&"flour", 0) + 2
	var staff: int = world.workers.size()
	var wages: int = int(world.ledger.today.get(Ledger.Line.WAGES, 0))

	var owed: int = worker.wage()
	check(world.dismiss_worker(worker) == "", "a member of staff can be let go")
	check(world.workers.size() == staff - 1 and not world.pawns.has(pawn), "and is gone from the roster")
	check(int(world.ledger.today.get(Ledger.Line.WAGES, 0)) == wages + owed,
		"and is paid for the day, so hiring and dismissing is never free labour")
	check(scenario.reconcile(), "what they were carrying is put down, not taken with them")
	check(world.dismiss_worker(worker) != "", "letting go somebody already gone is refused")
	check(not worker.is_processing(), "and they stop looking for work the moment they are let go")

	# A job whose claimant is freed must come back. A freed object compares
	# equal to null, so it read as unclaimed while its state said CLAIMED, and
	# was never offered to anyone again -- found by the chaos test after a
	# dismissal, with idle staff standing beside the work.
	var ghost := Node.new()
	var job := Job.new()
	job.kind = WorkType.Kind.HAUL
	job.target = world.plot.position + Vector2i(2, 2)
	job.key = "test:orphan"
	world.board.post(job)
	job.claim(ghost)
	ghost.free()
	check(job.claimant == null and job.state == Job.State.CLAIMED, "the fixture reproduces a freed claimant")
	check(world.board.release_orphans() >= 1 and job.state == Job.State.PENDING, "the board reopens work its claimant took with them")
	check(job.can_be_offered_to(world.workers[0]), "and offers it again")
	world.board.cancel_key(job.key)


## Positions, as in Prison Architect: each hire has a fee, a wage and a rule
## about which work they may do. The rule is the point -- a cook never hauls,
## however idle -- so it is checked where work is actually chosen, not just
## where it is displayed.
func _check_positions(world: TavernWorld) -> void:
	for kind in range(WorkType.COUNT):
		check(StaffRole.for_kind(kind) != null,
			"some position can be hired to %s" % WorkType.display_name(kind).to_lower())
	var crew: PackedStringArray = PackedStringArray()
	for worker in world.workers:
		crew.append(String(worker.role.id) if worker.role != null else "?")
	check(crew.has("porter") and crew.has("cook") and crew.has("waiter") and crew.has("cleaner"),
		"the tavern opens with a porter, a cook, waiters and a cleaner: %s" % ", ".join(crew))

	# The rule holds whatever the grid says.
	var cook: Worker = null
	for worker in world.workers:
		if worker.role != null and worker.role.id == &"cook":
			cook = worker
	if cook != null:
		var kept: int = int(cook.priorities.get(WorkType.Kind.HAUL, WorkType.PRIORITY_OFF))
		cook.priorities[WorkType.Kind.HAUL] = 1
		check(cook.priority_for(WorkType.Kind.HAUL) == WorkType.PRIORITY_OFF,
			"a cook set to haul in the grid still does not haul")
		var haul := Job.new()
		haul.kind = WorkType.Kind.HAUL
		haul.target = cook.pawn.tile
		haul.key = "test:cook-haul"
		world.board.post(haul)
		check(world.board.best_for(cook, cook.effective_priorities(), cook.pawn.tile) != haul,
			"and is never offered a haul job")
		world.board.cancel_key(haul.key)
		cook.priorities[WorkType.Kind.HAUL] = kept

	# Hiring: the fee now, the wage from today, the position's uniform.
	var busser: StaffRole = StaffRole.of(&"busser")
	var gold: int = GameState.gold
	var staff: int = world.workers.size()
	var bill: int = world.wage_bill()
	var hiring_before: int = int(world.ledger.today.get(Ledger.Line.HIRING, 0))
	check(world.hire(&"busser") == "", "a busser can be hired")
	check(world.workers.size() == staff + 1, "and joins the staff")
	var hired: Worker = world.workers[world.workers.size() - 1]
	check(hired.role == busser and hired.pawn.uniform == busser.uniform, "as a busser, in a busser's colours")
	check(GameState.gold == gold - busser.fee, "the fee comes out of the purse at once")
	check(int(world.ledger.today.get(Ledger.Line.HIRING, 0)) == hiring_before + busser.fee,
		"and is booked under Hiring")
	check(world.wage_bill() == bill + busser.wage, "the wage bill grows by the busser's wage")
	var summed: int = 0
	for worker in world.workers:
		summed += worker.wage()
	check(world.wage_bill() == summed, "the wage bill is every position's own rate")

	# Refused, and nothing taken, when the purse cannot cover the fee.
	GameState.gold = 1
	check(world.hire(&"cook") != "", "a cook is refused when the purse cannot cover the fee")
	check(GameState.gold == 1 and world.workers.size() == staff + 1, "and nothing is taken or added")
	check(world.hire(&"hand") != "", "the old all-rounder cannot be hired")
	GameState.gold = gold - busser.fee

	# Let go on the busser's own wage, not a flat rate.
	var wages_before: int = int(world.ledger.today.get(Ledger.Line.WAGES, 0))
	check(world.dismiss_worker(hired) == "", "the busser can be let go")
	check(int(world.ledger.today.get(Ledger.Line.WAGES, 0)) == wages_before + busser.wage,
		"and is paid a busser's wage for the day")
	GameState.gold += busser.fee + busser.wage
	world.ledger.today[Ledger.Line.HIRING] = hiring_before
	world.ledger.today[Ledger.Line.WAGES] = wages_before

	# Work nobody's position allows is named, with who to hire.
	var cooks: Array = []
	for worker in world.workers:
		if worker.allows(WorkType.Kind.COOK):
			cooks.append([worker, worker.role, worker.priorities.duplicate()])
			worker.role = StaffRole.of(&"porter")
	var stew := Job.new()
	stew.kind = WorkType.Kind.COOK
	stew.target = world.plot.position
	stew.key = "test:nobody-cooks"
	world.board.post(stew)
	var said: String = Trouble.diagnose(world)
	check(said.contains("can cook") and said.contains("Hire a cook"),
		"work nobody may do is named, with who to hire: '%s'" % said)
	world.board.cancel_key(stew.key)
	for entry in cooks:
		entry[0].role = entry[1]
		entry[0].priorities = entry[2]
	check(not Trouble.diagnose(world).contains("can cook"), "and a cook on the books clears it")


## Phase 2: a waiter takes the order at the table, and somebody brings the
## bill. A patron who has read the menu waits with a hand up; one who has eaten
## waits for the bill, and pays at the door without a tip if nobody comes.
func _check_service_loop(world: TavernWorld) -> void:
	var director: CustomerDirector = world.customers
	var seating: Seating = director.seating
	seating.refresh()
	var seated: Array = []
	for i in range(3):
		director._try_spawn()
		if director.customers.size() <= i:
			break
		var brain: CustomerBrain = director.customers[director.customers.size() - 1]
		brain.set_process(false)
		brain.pawn.set_process(false)
		brain.pawn.stop()
		brain.seat = seating.claim(brain, brain.pawn.tile)
		seated.append(brain)
	check(seated.size() == 3 and seated.all(func(b) -> bool: return b.seat != Seating.NO_SEAT),
		"the service fixture seats three patrons")
	if seated.size() < 3:
		return
	var first: CustomerBrain = seated[0]

	# Menu read: the hand goes up, and a waiter is sent for.
	first.state = CustomerBrain.State.ORDERING
	first._timer = 0.0
	first._process_ordering(0.0)
	check(first.state == CustomerBrain.State.READY_TO_ORDER and first.order.is_empty(),
		"a patron who has read the menu waits for a waiter rather than ordering alone")
	director._generate_serve_jobs()
	var take_key: String = "take:%d,%d" % [first.seat.x, first.seat.y]
	var take: Job = _job_with_key(world, take_key)
	check(take != null and take.kind == WorkType.Kind.SERVE, "a waiter is sent to take the order")
	var cook: Worker = null
	var waiter: Worker = null
	for worker in world.workers:
		if worker.role != null and worker.role.id == &"cook":
			cook = worker
		if worker.role != null and worker.role.id == &"waiter":
			waiter = worker
	check(cook != null and not cook.allows(WorkType.Kind.SERVE), "a cook does not take orders")
	if take != null:
		take.apply_work(take.work_amount)
		world.board.complete(take)
	check(first.state == CustomerBrain.State.WAITING_FOR_ORDER and not first.order.is_empty(),
		"once the order is taken, the kitchen has something to make")
	director._generate_serve_jobs()
	check(_job_with_key(world, take_key) == null, "and nobody is sent to take it twice")

	# Nobody comes: the hand goes down and they leave, counted as unserved.
	var second: CustomerBrain = seated[1]
	var lost: int = director.lost_no_service
	second.state = CustomerBrain.State.READY_TO_ORDER
	second._patience = 1.0
	second._process_ready_to_order(2.0)
	check(second.state in [CustomerBrain.State.LEAVING, CustomerBrain.State.GONE] and director.lost_no_service == lost + 1,
		"a patron nobody comes to leaves unserved")

	# Eaten: they wait for the bill, and whoever brings it earns the tip.
	for line in first.order:
		line["served"] = line["count"]
	first.state = CustomerBrain.State.EATING
	first._process_eating(CustomerBrain.EAT_TIME + 0.1)
	check(first.state == CustomerBrain.State.WAITING_FOR_BILL, "a patron who has eaten waits for the bill")
	director._generate_serve_jobs()
	var bill_key: String = "bill:%d,%d" % [first.seat.x, first.seat.y]
	var bill_job: Job = _job_with_key(world, bill_key)
	check(bill_job != null and bill_job.kind == WorkType.Kind.BILL, "somebody is sent with the bill")
	check(waiter != null and waiter.allows(WorkType.Kind.BILL) and StaffRole.of(&"busser").allows(WorkType.Kind.BILL)
		and not StaffRole.of(&"cook").allows(WorkType.Kind.BILL), "waiters and bussers bring bills; cooks do not")
	var owed: int = first.bill_so_far()
	var tip: int = first.tip_so_far()
	var gold: int = GameState.gold
	var served: int = director.served_count
	if bill_job != null:
		bill_job.apply_work(bill_job.work_amount)
		world.board.complete(bill_job)
	check(GameState.gold == gold + owed + tip and tip > 0 and director.served_count == served + 1,
		"a bill brought promptly is paid with a tip (%dg + %dg)" % [owed, tip])

	# Left waiting for the bill: they pay at the door, and tip nothing.
	var third: CustomerBrain = seated[2]
	third.order = [{"id": &"beer", "count": 1, "served": 1}]
	third._did_order = true
	third.state = CustomerBrain.State.WAITING_FOR_BILL
	third._patience = 1.0
	var tips: int = int(world.ledger.today.get(Ledger.Line.TIPS, 0))
	gold = GameState.gold
	third._process_waiting_for_bill(2.0)
	check(third.state == CustomerBrain.State.PAYING, "nobody came with the bill, so they get up to pay")
	var at_door: int = third.bill_so_far()
	third._pay_and_go()
	check(GameState.gold == gold + at_door and int(world.ledger.today.get(Ledger.Line.TIPS, 0)) == tips,
		"a patron left waiting for the bill pays at the door, without a tip")

	for brain in seated:
		if is_instance_valid(brain):
			seating.release_for(brain)
			director.remove_customer(brain)
	director._generate_serve_jobs()


func _job_with_key(world: TavernWorld, key: String) -> Job:
	for job in world.board.jobs:
		if job.key == key:
			return job
	return null


## The first position the tavern grows into: refused on day 1, hired from day
## 2, and allowed the river and the carrying, nothing else.
func _check_fisherman(world: TavernWorld) -> void:
	var fisher: StaffRole = StaffRole.of(&"fisherman")
	check(fisher != null and fisher.hireable and fisher.unlock_day == 2, "the fisherman can be hired from day 2")
	if fisher == null:
		return
	var day: int = world.clock.day
	var gold: int = GameState.gold
	var staff: int = world.workers.size()
	var hiring: int = int(world.ledger.today.get(Ledger.Line.HIRING, 0))
	var wages: int = int(world.ledger.today.get(Ledger.Line.WAGES, 0))
	world.clock.day = 1
	check(world.hire(&"fisherman") != "" and world.workers.size() == staff and GameState.gold == gold,
		"on day 1 a fisherman is refused, and nothing is taken")
	world.clock.day = 2
	check(world.hire(&"fisherman") == "", "on day 2 a fisherman can be hired")
	if world.workers.size() == staff + 1:
		var hired: Worker = world.workers[world.workers.size() - 1]
		check(hired.role == fisher and hired.allows(WorkType.Kind.FISH) and hired.allows(WorkType.Kind.HAUL)
			and not hired.allows(WorkType.Kind.COOK) and not hired.allows(WorkType.Kind.SERVE),
			"a fisherman fishes and carries, and neither cooks nor waits at table")
		world.dismiss_worker(hired)
	world.clock.day = day
	GameState.gold = gold
	world.ledger.today[Ledger.Line.HIRING] = hiring
	world.ledger.today[Ledger.Line.WAGES] = wages


## Guests order from whatever food and drink is in stock, not from a fixed
## list of two: put soup in the larder and somebody orders soup.
func _check_fish_menu(world: TavernWorld) -> void:
	var menu: Array[StringName] = CustomerDirector.menu_ids()
	check(menu.has(&"bread") and menu.has(&"beer") and menu.has(&"fish_soup") and menu.has(&"grilled_fish"),
		"the menu is every dish with a price: %s" % ", ".join(menu))
	var director: CustomerDirector = world.customers
	var soup: ItemDef = ItemCatalog.get_def(&"fish_soup")
	var added: int = world.items.place_near(soup, 4, world.plot.position + world.plot.size / 2)
	world.delivered[&"fish_soup"] = int(world.delivered.get(&"fish_soup", 0)) + added
	var before: int = director.customers.size()
	director._try_spawn()
	check(director.customers.size() == before + 1, "the menu fixture has a guest")
	if director.customers.size() == before + 1:
		var brain: CustomerBrain = director.customers[director.customers.size() - 1]
		brain.set_process(false)
		brain.pawn.set_process(false)
		brain.pawn.stop()
		var ordered_soup: bool = false
		var on_menu: bool = true
		for i in range(40):
			if not brain._place_order():
				on_menu = false
				break
			for line in brain.order:
				ordered_soup = ordered_soup or line["id"] == &"fish_soup"
				on_menu = on_menu and menu.has(line["id"]) and brain._sellable(line["id"]) >= int(line["count"])
		check(ordered_soup, "with soup in the larder, somebody orders soup")
		check(on_menu, "and every order is for something on the menu and in stock")
		check(brain._menu_on_offer() >= 3, "soup counts towards a longer menu")
		brain.order.clear()
		director.remove_customer(brain)
	for tile in world.items.tiles_with(&"fish_soup", world.plot.position):
		world.items.take(tile, world.items.count_at(tile))
	world.delivered[&"fish_soup"] = int(world.delivered.get(&"fish_soup", 0)) - added


## Each kind of adventurer wants its own thing (phase 3), and the ordinary
## traveller is still exactly the guest the game had before kinds.
func _check_guest_types(world: TavernWorld) -> void:
	var ordinary: GuestType = GuestType.of(-1)
	check(ordinary.food_chance == 0.7 and ordinary.drink_chance == 0.7 and ordinary.most_drinks == 2
		and ordinary.tip == 1.0 and ordinary.patience == 1.0 and ordinary.cares.is_empty(),
		"the ordinary traveller keeps the old numbers")
	check(GuestType.of(PawnMesh.Look.STAFF) == ordinary, "staff looks map to no kind of guest")
	for look in [PawnMesh.Look.WARRIOR, PawnMesh.Look.WIZARD, PawnMesh.Look.RANGER,
			PawnMesh.Look.ADVENTURER, PawnMesh.Look.DUELIST, PawnMesh.Look.PILGRIM]:
		var t: GuestType = GuestType.of(look)
		check(t != ordinary and not t.wants.is_empty(), "every outfit is a kind of guest that wants something: %s" % t.title)
		check(t.food_chance + t.drink_chance >= 1.0, "a %s always orders something" % t.title.to_lower())

	# A pilgrim's dirty table counts double; nothing else about the review moves.
	var plain: Review = Review.write("A", true, 10, 0.0, 0.0, 2, 1.0, ItemWorld.BASE_QUALITY)
	var fussy: Review = Review.write("A", true, 10, 0.0, 0.0, 2, 1.0, ItemWorld.BASE_QUALITY,
		GuestType.of(PawnMesh.Look.PILGRIM).cares)
	check(int(fussy.parts[Review.Part.CLEANLINESS]) == 2 * int(plain.parts[Review.Part.CLEANLINESS])
		and fussy.parts[Review.Part.SERVICE] == plain.parts[Review.Part.SERVICE],
		"a pilgrim minds a filthy room twice as much, and only that")

	# Ordering, with bread, beer and grilled fish on.
	var director: CustomerDirector = world.customers
	var fish: ItemDef = ItemCatalog.get_def(&"grilled_fish")
	var added: int = world.items.place_near(fish, 4, world.plot.position + world.plot.size / 2)
	world.delivered[&"grilled_fish"] = int(world.delivered.get(&"grilled_fish", 0)) + added
	var before: int = director.customers.size()
	director._try_spawn()
	if director.customers.size() == before + 1:
		var brain: CustomerBrain = director.customers[director.customers.size() - 1]
		brain.set_process(false)
		brain.pawn.set_process(false)
		brain.pawn.stop()
		check(brain.guest_type == GuestType.of(brain.pawn.adventurer), "a guest is the kind their outfit says")
		brain.guest_type = GuestType.of(PawnMesh.Look.DUELIST)
		var dearest: bool = true
		for i in range(10):
			brain._place_order()
			for line in brain.order:
				if not ItemCatalog.get_def(line["id"]).tags.has("drink"):
					dearest = dearest and line["id"] == &"grilled_fish"
		check(dearest, "a duelist orders the dearest dish on the menu")
		var drinks: Dictionary = {}
		for kind in [PawnMesh.Look.WARRIOR, PawnMesh.Look.PILGRIM]:
			brain.guest_type = GuestType.of(kind)
			var n: int = 0
			for i in range(60):
				brain._place_order()
				for line in brain.order:
					if ItemCatalog.get_def(line["id"]).tags.has("drink"):
						n += int(line["count"])
			drinks[kind] = n
		check(int(drinks[PawnMesh.Look.WARRIOR]) > 3 * int(drinks[PawnMesh.Look.PILGRIM]),
			"a warrior drinks far more than a pilgrim (%d cups to %d)" % [drinks[PawnMesh.Look.WARRIOR], drinks[PawnMesh.Look.PILGRIM]])
		brain.order.clear()
		director.remove_customer(brain)
	for tile in world.items.tiles_with(&"grilled_fish", world.plot.position):
		var n: int = world.items.take(tile, world.items.count_at(tile))
		world.delivered[&"grilled_fish"] = int(world.delivered.get(&"grilled_fish", 0)) - n
