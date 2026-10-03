extends "res://dev/regression_group.gd"

## The game around the tavern: objectives, the trouble line, stats
## cards, level outcomes, game time, saving and continuing.


func run() -> void:
	var world: TavernWorld = fixture_world
	var scenario: Node = fixture_scenario
	open_for_trade(world)
	_check_objectives(world)
	_check_trouble(world, scenario)
	_check_world_stats(world, scenario)
	_check_level_outcome(world)
	_check_sim_clock(world)
	await _check_menus(world)
	await _check_key_bindings(world)
	_check_save_round_trip(world)
	await _check_continue_loads(world)


func _check_objectives(world: TavernWorld) -> void:
	world.objectives.refresh(world)
	var done: Dictionary = {}
	for objective in world.objectives.list:
		done[String(objective.id)] = objective.done

	check(done["floor"], "flooring objective notices the floor")
	check(done["kitchen"], "kitchen objective notices prep table and oven")
	check(done["seating"], "seating objective notices chairs beside tables")
	check(done["storage"], "storage objective notices the shelving")
	check(done["supplies"], "supplies objective notices the delivery")
	check(done["washing_up"], "washing-up objective notices the basin")
	# A milestone must survive the night. served_count is a daily tally, and the
	# first-sale objective used to read it and un-tick at every rollover.
	var served_today: int = world.customers.served_count
	world.customers.served_count = 1
	world.objectives.refresh(world)
	var ticked: bool = world.objectives.list[5].done
	world.ledger.history.append({"day": 99, "served": 1, "lost": 0, "profit": 0, "purse": GameState.gold})
	world.customers.served_count = 0
	world.objectives.refresh(world)
	check(ticked and world.objectives.list[5].done, "the first-sale objective stays ticked across a new day")
	world.ledger.history.pop_back()
	world.customers.served_count = served_today
	world.objectives.refresh(world)
	check(not done["first_sale"], "first-sale objective stays open until someone is served")
	check(not done["profit"], "profit objective stays open until a day closes in profit")

	# Derived, not tracked: removing the oven must un-tick the kitchen.
	var oven_index: int = -1
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["def"].id == &"oven":
			oven_index = i
			break
	if oven_index >= 0:
		world.build.grid.remove(oven_index)
		world.objectives.refresh(world)
		check(not world.objectives.list[1].done, "demolishing the oven re-opens the kitchen objective")


## The HUD's "what is going wrong" line names the cause, and drops it the moment
## the cause is fixed.
##
## The demo level's lesson was invisible without it: every table under dirty
## plates, guests milling on the grass, +0g for the day, and not a word on
## screen to say why.
func _check_trouble(world: TavernWorld, scenario: Node) -> void:
	var seating: Seating = world.customers.seating
	seating.refresh()
	check(seating.seats.size() > 0, "the trouble check has seats to work with")
	check(not Trouble.diagnose(world).contains("plates"), "clean tables are not reported as dirty")

	# Every table under plates, a basin built, and nobody on Clean.
	var dishes: ItemDef = ItemCatalog.get_def(&"dirty_dishes")
	var put: Dictionary = {}
	for seat in seating.seats:
		var table: Vector2i = seat["table"]
		if put.has(table) or world.items.has_stack(table):
			continue
		put[table] = world.items.add(dishes, 1, table, ItemWorld.BASE_QUALITY)
		world.delivered[&"dirty_dishes"] = world.delivered.get(&"dirty_dishes", 0) + int(put[table])
	var clean: Array = []
	for worker in world.workers:
		clean.append(worker.priorities.get(WorkType.Kind.CLEAR, WorkType.PRIORITY_OFF))
		worker.priorities[WorkType.Kind.CLEAR] = WorkType.PRIORITY_OFF
	var said: String = Trouble.diagnose(world)
	check(said.contains("Clear"), "plates nobody is set to clear are named: '%s'" % said)
	for i in range(world.workers.size()):
		world.workers[i].priorities[WorkType.Kind.CLEAR] = clean[i]
	check(not Trouble.diagnose(world).contains("plates"),
		"with someone on Clean and a basin built, plates are just work in progress")
	for table in put:
		var n: int = world.items.count_at(table)
		world.items.take(table, n)
		world.generator.consumed[&"dirty_dishes"] = world.generator.consumed.get(&"dirty_dishes", 0) + n

	# Out of an ingredient a finished bench uses. Put back exactly as found.
	var hops: ItemDef = ItemCatalog.get_def(&"hops")
	var carried: bool = false
	for worker in world.workers:
		if worker.carried_def() == hops:
			carried = true
	var brewing: bool = Trouble._ingredients_in_use(world).has(&"hops")
	check(brewing, "the regression tavern has a bench that uses hops")
	if brewing and not carried:
		var stash: Array = []
		for tile in world.items.tiles_with(&"hops", world.plot.position):
			stash.append({"tile": tile, "count": world.items.count_at(tile), "quality": world.items.quality_at(tile)})
		for entry in stash:
			world.items.take(entry["tile"], entry["count"])
		# Ordering by hand: the advice is to order.
		world.auto_supply.enabled = false
		said = Trouble.diagnose(world)
		check(said.contains("Out of") and said.contains("hops"), "running out of hops is named: '%s'" % said)
		# With auto-order on it is in hand, unless hops are marked never-buy.
		world.auto_supply.enabled = true
		check(not Trouble.diagnose(world).contains("hops"), "with auto-order on, the shortage is left to it")
		world.auto_supply.set_never(&"hops", true)
		check(Trouble.diagnose(world).contains("never to buy"), "unless hops are marked never to buy")
		world.auto_supply.set_never(&"hops", false)
		for entry in stash:
			world.items.add(hops, entry["count"], entry["tile"], entry["quality"])
		check(not Trouble.diagnose(world).contains("hops"), "and restocking clears it")

	# Guests leaving unserved, once nothing earlier in the list applies.
	var before: String = Trouble.diagnose(world)
	var unserved: int = world.customers.lost_no_service
	world.customers.lost_no_service = Trouble.LOSSES_WORTH_NAMING
	if before.is_empty():
		check(Trouble.diagnose(world).contains("waiter"), "guests leaving unserved are named")
		# A kitchen that cannot keep up outranks a few slow tables.
		var no_menu: int = world.customers.lost_no_menu
		world.customers.lost_no_menu = Trouble.LOSSES_WORTH_NAMING * 4
		var said_menu: String = Trouble.diagnose(world)
		check(said_menu.contains("nothing left to order") or said_menu.contains("Nothing to sell"),
			"the day's biggest loss is the one named: '%s'" % said_menu)
		world.customers.lost_no_menu = no_menu
	world.customers.lost_no_service = unserved
	check(scenario.reconcile(), "diagnosing trouble moves no goods")


## The opening checklist has to answer to the world, not to a counter.
##
## By this point the scenario has built a full tavern and taken a delivery, so
## the five build-and-buy objectives must read as done while the two that need
## actual trade must not. A panel that ticks everything, or nothing, is worse
## than no panel at all.
## The hover card and inspector say something true about everything a player
## can point at, and looking never changes what is looked at.
func _check_world_stats(world: TavernWorld, scenario: Node) -> void:
	# A worker: the headline must say what they are doing.
	var worker_rows: Array = WorldStats.pawn_rows(world, world.pawns[0])
	check(_row_value(worker_rows, "Doing") != "", "a worker's card says what they are doing")
	check(_row_value(worker_rows, "Done today") != "", "and what they have finished today")
	world.workers[0].done_today = {WorkType.Kind.HAUL: 3, WorkType.Kind.COOK: 1}
	check(_row_value(WorldStats.pawn_rows(world, world.pawns[0]), "Done today") == "3 haul, 1 cook",
		"the day's work reads busiest first")
	world.workers[0].reset_day_tally()

	# Every kind of subject answers, and the card is a subset of the inspector.
	var shelf: int = -1
	var oven: int = -1
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry == null or not entry["built"]:
			continue
		if entry["def"].is_storage and shelf < 0:
			shelf = i
		# Any bench: an earlier check demolishes the oven to prove the
		# checklist un-ticks, so this cannot count on one being there.
		if oven < 0 and not RecipeCatalog.for_station(entry["def"].id).is_empty():
			oven = i
	var shelf_rows: Array = WorldStats.building_rows(world, shelf)
	check(_row_value(shelf_rows, "In use").contains("tiles"), "a shelf says how full it is")
	var oven_rows: Array = WorldStats.building_rows(world, oven)
	check(_row_value(oven_rows, "Next") != "", "a bench says who is working at it")
	var headline: Array = WorldStats.headline(oven_rows)
	check(headline.size() < oven_rows.size() and headline[0]["t"] == "title", "the card is the headline, not the whole story")
	var ground: Vector2i = world.plot.position + Vector2i(1, 1)
	check(_row_value(WorldStats.ground_rows(world, ground), "Pace").ends_with("pace"), "ground says how quick it is underfoot")
	check(WorldStats.pace_text(NavGrid.FLOOR_COST) == "100% pace", "laid floor is the full pace")
	check(WorldStats.quality_word(ItemWorld.BASE_QUALITY) == "Ordinary", "bought stock is ordinary")

	var flour: ItemDef = ItemCatalog.get_def(&"flour")
	# Somewhere genuinely loose: not built on, not in the yard, not beside a bench.
	var near_bench: Dictionary = {}
	for station in world.generator.built_stations():
		for t in station["input_tiles"]:
			near_bench[t] = true
	var loose := Vector2i(-1, -1)
	for y in range(world.plot.position.y + 1, world.plot.end.y - 1):
		for x in range(world.plot.position.x + 1, world.plot.end.x - 1):
			var t := Vector2i(x, y)
			if loose == Vector2i(-1, -1) and world.build.grid.placement_at(t) < 0 and not world.items.has_stack(t) 					and not world.unloading_yard().has_point(t) and not near_bench.has(t):
				loose = t
	var put: int = world.items.add(flour, 2, loose, 0.9)
	world.delivered[&"flour"] = world.delivered.get(&"flour", 0) + put
	var item_rows: Array = WorldStats.item_rows(world, loose)
	check(_row_value(item_rows, "Quality") == "Excellent", "a stack says how good it is")
	check(_row_value(item_rows, "Where").begins_with("loose"), "and where it is")
	world.items.take(loose, put)
	world.generator.consumed[&"flour"] = world.generator.consumed.get(&"flour", 0) + put

	# A patron, seated and part-served. Looking at them must not move them on.
	var beer: ItemDef = ItemCatalog.get_def(&"beer")
	world.customers._try_spawn()
	check(not world.customers.customers.is_empty(), "the stats fixture has a patron")
	if not world.customers.customers.is_empty():
		var brain: CustomerBrain = world.customers.customers[world.customers.customers.size() - 1]
		brain.set_process(false)
		brain.pawn.set_process(false)
		brain.pawn.stop()
		brain.order = [{"id": &"beer", "count": 2, "served": 1}]
		brain.state = CustomerBrain.State.WAITING_FOR_ORDER
		brain._did_order = true
		# Half of the patience this kind of guest was given.
		brain._patience = CustomerBrain.PATIENCE_FOR_ORDER * brain.guest_type.patience * 0.5
		brain._waited_for_order = CustomerBrain.PATIENCE_FOR_ORDER * 0.5
		var before: String = var_to_str([brain.state, brain.order, brain._patience, brain._waited_for_order])
		var rows: Array = WorldStats.pawn_rows(world, brain.pawn)
		check(_row_value(rows, "Order") == "beer 1/2", "a patron's card shows the order as served so far")
		check(_row_value(rows, "Bill so far").begins_with("%dg" % beer.sell_value), "and what they owe for it")
		check(_row_value(rows, "Mood").contains("/100"), "and how they feel")
		var patience: float = -1.0
		for row in rows:
			if row["t"] == "bar" and row["label"] == "Patience":
				patience = row["fraction"]
		check(is_equal_approx(patience, 0.5), "patience reads as the share left")
		check(var_to_str([brain.state, brain.order, brain._patience, brain._waited_for_order]) == before,
			"reading a patron's mood changes nothing about their visit")
		# The mood preview is the review they would write, not a second opinion.
		var preview: Review = brain.mood_preview()
		check(preview.satisfaction == brain.write_review(true, brain.bill_so_far()).satisfaction,
			"the mood is the same scoring as the review")

		# Clicking selects the same thing the hover card describes.
		world.hud.inspector.show_subject({"kind": WorldStats.Kind.PAWN, "pawn": brain.pawn})
		check(WorldStats.same(world.hud.inspector.subject(), {"kind": WorldStats.Kind.PAWN, "pawn": brain.pawn}),
			"the inspector reports what it is showing")
		check(world.input.selection_marker.visible, "and the selection ring appears under them")
		world.hud.inspector.clear()
		check(not world.input.selection_marker.visible, "closing the inspector takes the ring away")
		world.customers.remove_customer(brain)

	world.hud.inspector.show_building(oven)
	check(world.hud.inspector.visible and world.input.selection_marker.visible, "a building can be inspected and framed")
	# Escape closes what is open before it ever leaves the game.
	check(world.hud.close_top_panel() and not world.hud.inspector.visible, "Escape closes the inspector first")
	var open_bar: bool = world.hud._build_bar.visible
	if open_bar:
		world.hud._toggle_build_bar()
	check(not world.hud.close_top_panel(), "with nothing open, Escape goes on to the pause menu")
	if open_bar:
		world.hud._toggle_build_bar()

	# Follow: on for the inspected person, off at the first pan or a new choice.
	world.hud.inspector.show_pawn(world.pawns[0])
	world.input.toggle_follow()
	check(world.rig.follow == world.pawns[0], "F follows the person being inspected")
	world.rig._process(0.016)
	check(world.rig._focus_target.distance_to(Vector3(world.pawns[0].global_position.x, world.rig._focus_target.y,
		world.pawns[0].global_position.z)) < 0.01, "and the view centres on them")
	world.rig._pan(Vector2(1, 0))
	check(world.rig.follow == null, "a pan hands the camera back")
	world.input.toggle_follow()
	world.hud.inspector.show_building(oven)
	check(world.rig.follow == null, "choosing something else stops following")
	world.hud.inspector.clear()

	# Stack counts: one label per stack worth numbering, derived afresh.
	var labels: StackLabels = world.get_node_or_null("StackLabels")
	check(labels != null, "the world numbers its stacks")
	if labels != null:
		labels._resync()
		var numbered: int = 0
		for tile in world.items.all_tiles():
			var def: ItemDef = world.items.def_at(tile)
			if def != null and world.items.count_at(tile) >= 2 and def.category != ItemDef.Category.REFUSE:
				numbered += 1
		check(labels._labels.size() == numbered, "every stack of two or more has a number, and nothing else does")

	# Something made, not bought, is never sent to the merchant.
	check(not WorldStats._feed_words("no source outside the bench", 0, world, &"dough").contains("order supplies"),
		"dough is never sent to the merchant")
	check(WorldStats._feed_words("no source outside the bench", 0, world, &"hops").contains("order supplies"),
		"hops are")

	# The production panel says what each recipe is up to.
	for recipe in RecipeCatalog.all():
		check(not WorldStats.recipe_activity(world, recipe).is_empty(), "%s reports what it is doing" % recipe.display_name)

	# The build bar says what each piece is for, from its data.
	check(WorldStats.building_blurb(BuildingCatalog.get_def(&"sink")).contains("wash"), "the basin says it is for washing up")
	check(WorldStats.building_blurb(BuildingCatalog.get_def(&"oven")).contains("makes bread"), "the oven says what it makes")
	check(WorldStats.building_blurb(BuildingCatalog.get_def(&"wood_floor")).contains("quickest"), "floor says it is quicker underfoot")
	check(WorldStats.building_blurb(BuildingCatalog.get_def(&"well")).contains("water"), "the well says it needs water nearby")
	check(scenario.reconcile(), "looking at things moves no goods")


## A level is won or lost at a close of business, once, and stays that way.
func _check_level_outcome(world: TavernWorld) -> void:
	var level: LevelDef = LevelCatalog.get_level(&"wayfarers_rest")
	var real_history: Array = world.ledger.history
	var goal: int = level.goal_gold
	var closes := func(purses: Array) -> Array:
		var out: Array = []
		for i in range(purses.size()):
			out.append({"day": i + 1, "served": 0, "lost": 0, "profit": 0, "purse": purses[i]})
		return out

	world.ledger.history = closes.call([300, 500])
	check(level.outcome(world) == LevelDef.Outcome.OPEN, "a level in progress is neither won nor lost")
	world.ledger.history = closes.call([300, 500, goal + 10, goal - 200])
	check(level.outcome(world) == LevelDef.Outcome.WON and level.decided_on(world) == 3,
		"reaching the goal at a close wins, and a poor day after does not take it back")
	check(bool(level.verdict_for(world, 3).get("won", false)), "the winning close announces it")
	check(level.verdict_for(world, 4).is_empty(), "and only that close, not every evening after")
	var short: Array = []
	for i in range(level.goal_days):
		short.append(goal - 100)
	world.ledger.history = closes.call(short)
	check(level.outcome(world) == LevelDef.Outcome.LOST and level.decided_on(world) == level.goal_days,
		"the deadline's close falling short loses")
	check(not bool(level.verdict_for(world, level.goal_days).get("won", true)), "and says so on that close")
	short.append(goal + 500)
	world.ledger.history = closes.call(short)
	check(level.outcome(world) == LevelDef.Outcome.LOST, "a fortune after the deadline does not win it back")
	world.ledger.history = real_history


## Game time: paused is no steps, speed multiplies them, and the summary's
## hold never touches the player's own pause.
func _check_sim_clock(world: TavernWorld) -> void:
	var sim: SimClock = world.sim
	var ticks: Array[int] = [0]
	var count := func(_dt: float) -> void: ticks[0] += 1
	sim.ticked.connect(count)
	var steps_for := func(speed: int, real_seconds: float) -> int:
		sim.speed = speed
		sim._accumulated = 0.0
		ticks[0] = 0
		sim._process(real_seconds)
		return ticks[0]

	check(steps_for.call(1, 0.1) == 6, "a tenth of a second at 1x is six steps")
	check(steps_for.call(2, 0.1) == 12, "and twelve at 2x")
	check(steps_for.call(0, 0.1) == 0, "and none while paused")
	check(steps_for.call(4, 1.0 / 30.0) == 10, "5x is the top speed: ten steps in a 30 fps frame")
	check(steps_for.call(4, 0.5) == SimClock.MAX_STEPS_PER_FRAME, "a slow frame is capped, not made up in one burst")
	sim.turbo_steps = 5
	check(steps_for.call(0, 0.1) == 0, "paused stays paused at test speed too")
	check(steps_for.call(1, 0.0) == 5, "and test speed runs its fixed steps whatever the frame took")
	sim.turbo_steps = 0
	sim.speed = 1
	sim.held = true
	check(steps_for.call(1, 0.1) == 0, "the day summary holds time")
	sim.held = false

	sim.speed = 3
	sim.toggle_pause()
	check(sim.is_paused(), "Space pauses")
	sim.toggle_pause()
	check(sim.speed == 3, "and resumes at the speed it was paused at")

	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	world.input._unhandled_input(key)
	check(sim.is_paused(), "the Space key pauses the world")
	key.keycode = KEY_2
	world.input._unhandled_input(key)
	check(sim.speed == 2, "and 2 sets double speed")
	sim.ticked.disconnect(count)
	sim.speed = 1


## Save the tavern, rebuild a fresh world from the file, and prove the two
## match.
##
## Round-tripping is the only honest test of a save: writing a file proves
## nothing, and inspecting the JSON proves only that the writer agrees with
## itself. This asserts that what comes back has the same buildings, the same
## goods and the same purse.
##
## Deliberately synchronous. An earlier version awaited a frame here, which split
## the coroutine and let the caller print its summary -- reporting PASS -- while
## three assertions had not run yet. add_child() already calls _ready() inline,
## so the frame was never needed. A suite that can green-light itself before
## finishing is worse than no suite.
func _check_save_round_trip(world: TavernWorld) -> void:
	var slot: int = GameState.MAX_SLOTS - 1  # inside this fixture's isolated directory
	GameState.active_slot = slot
	GameState.tavern_name = "Round Trip Arms"

	# Change a work priority away from its default, so the round trip has to
	# carry something that is not simply what a fresh Worker would be born with.
	world.workers[0].priorities[WorkType.Kind.SERVE] = WorkType.PRIORITY_OFF
	world.workers[0].priorities[WorkType.Kind.COOK] = 1

	var plot_before: Rect2i = world.plot
	var built_before: int = world.build.grid.live_count()
	var flour_before: int = world.items.total_of(&"flour")
	var gold_before: int = GameState.gold
	var pawns_before: int = world.pawns.size()
	# Goods in somebody's arms at the moment of saving. These were written to
	# every save and never read back: the chaos test lost six barrels of water
	# by saving mid-haul.
	var water: ItemDef = ItemCatalog.get_def(&"water")
	var had_cargo: bool = world.workers[1].carried_count() > 0
	if not had_cargo:
		world.workers[1].restore_cargo(water, 3, 0.8)
		world.delivered[&"water"] = world.delivered.get(&"water", 0) + 3
	var cargo_def: ItemDef = world.workers[1].carried_def()
	var cargo_count: int = world.workers[1].carried_count()

	# Which level this is. Not saved, it came back a plain sandbox: no goal, no
	# deadline, no ending. Set only for the save, since the level also decides
	# what opening purse the books are checked against.
	world.level = LevelCatalog.get_level(&"wayfarers_rest")
	check(world.save_now(), "tavern writes to its slot")
	world.level = null

	# Deliberately disturb every field the save is supposed to restore, so a
	# no-op loader cannot pass by leaving things as they were.
	GameState.gold = 1
	GameState.tavern_name = "Wrong"

	var restored: Dictionary = SaveGame.read(slot)
	check(not restored.is_empty(), "saved slot reads back")

	# The way the menu's Continue does it: ask to load, and the world loads
	# itself as it enters -- not a bare world with a second load pressed on it.
	check(GameState.request_continue(slot), "the saved slot can be continued")
	var reloaded: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(reloaded)
	reloaded.set_process(false)
	reloaded.generator.set_process(false)
	reloaded.customers.set_process(false)
	reloaded.clock.paused = true
	for worker in reloaded.workers:
		worker.set_process(false)
		worker.pawn.set_process(false)

	check(reloaded.plot == plot_before, "bought land survives the round trip")
	check(reloaded.build.grid.plot == plot_before, "and the builder knows about it")
	check(reloaded.build.grid.live_count() == built_before, "every building survives the round trip")
	check(reloaded.items.total_of(&"flour") == flour_before, "stock survives the round trip")
	check(GameState.gold == gold_before, "the purse survives the round trip")
	check(GameState.tavern_name == "Round Trip Arms", "the tavern's name survives the round trip")
	check(reloaded.pawns.size() == pawns_before, "staff survive the round trip")
	check(reloaded.level != null and reloaded.level.id == &"wayfarers_rest", "a level's rules survive the round trip")
	check(reloaded.workers[1].carried_def() == cargo_def and reloaded.workers[1].carried_count() == cargo_count,
		"what staff were carrying survives the round trip")
	check(reloaded.workers[1].state == Worker.State.HOLDING, "and they go on to put it down")
	check(
		reloaded.workers[0].priorities[WorkType.Kind.SERVE] == WorkType.PRIORITY_OFF
		and reloaded.workers[0].priorities[WorkType.Kind.COOK] == 1,
		"edited work priorities survive the round trip"
	)
	var positions_kept: bool = reloaded.workers.size() == world.workers.size()
	for i in range(mini(reloaded.workers.size(), world.workers.size())):
		positions_kept = positions_kept and reloaded.workers[i].role == world.workers[i].role
	check(positions_kept, "everybody keeps their position across the round trip")
	var looks_kept: bool = reloaded.pawns.size() == world.pawns.size()
	for i in range(mini(reloaded.pawns.size(), world.pawns.size())):
		looks_kept = looks_kept and reloaded.pawns[i]._rng.seed == world.pawns[i]._rng.seed
	check(looks_kept, "and their looks: a reload brings back the same people")

	_check_new_run_slots(slot)
	_check_stale_slot_visibility(slot)

	reloaded.queue_free()
	GameState.delete_slot(slot)
	GameState.active_slot = -1


## Continuing a saved tavern loads it, and never starts a fresh one over it.
##
## Both ways back in from the main menu -- Continue and Open -- set the slot
## without asking to load, so the world started a new tavern there and the
## first save wiped the player's own.
func _check_continue_loads(world: TavernWorld) -> void:
	var slot: int = GameState.MAX_SLOTS - 1  # inside this fixture's isolated directory
	GameState.active_slot = slot
	GameState.tavern_name = "The Continued Arms"
	world.save_now()
	var saved: Dictionary = SaveGame.read(slot)
	check(not saved.is_empty(), "the continue fixture has a saved tavern")
	if saved.is_empty():
		return
	var saved_name: String = String(saved.get("tavern_name", ""))

	var enter := func() -> TavernWorld:
		var w: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
		add_child(w)
		w.set_process(false)
		return w

	check(GameState.request_continue(slot), "Continue asks to load an occupied slot")
	var continued: TavernWorld = enter.call()
	check(GameState.tavern_name == saved_name and continued.build.grid.live_count() > 0,
		"and the saved tavern is what opens")
	continued.queue_free()

	# The mistake the menu made: a slot and no intent. Must load, not overwrite.
	# (The safeguard's warning in this suite's output is this check, on purpose.)
	GameState.active_slot = slot
	GameState.load_requested = false
	GameState.new_run_pending = false
	GameState.tavern_name = "Somebody Else's"
	var forgot: TavernWorld = enter.call()
	check(GameState.tavern_name == saved_name, "a slot entered with no intent loads its tavern rather than overwriting it")
	forgot.queue_free()

	# A confirmed new game in the same slot is still a new game.
	check(GameState.start_new_run("A Fresh Start", 12345, slot, true), "a new tavern may replace a saved one when confirmed")
	var fresh: TavernWorld = enter.call()
	check(GameState.tavern_name == "A Fresh Start", "and it opens fresh, not as the old one")
	fresh.queue_free()
	await get_tree().process_frame

	var menu_source: String = FileAccess.get_file_as_string("res://src/ui/main_menu/main_menu.gd")
	check(not menu_source.contains("GameState.active_slot = slot"), "the main menu never sets a slot without saying what it wants")
	GameState.delete_slot(slot)
	GameState.active_slot = -1


## The value of a stat row by its label, or "" if there is none.
func _row_value(rows: Array, label: String) -> String:
	for row in rows:
		if (row["t"] == "stat" or row["t"] == "stars") and row["label"] == label:
			return row["value"]
	return ""


## A slot holding a save this build cannot read is not the same as an empty one.
##
## The menu hangs both a button and a label on that distinction: a player whose
## slots all predate a format change cannot Continue, so they are exactly the
## people who need a way to see and clear them. Treating unreadable as empty
## hides the only route out and invites them to overwrite a slot believing it
## was free.
func _check_stale_slot_visibility(scratch: int) -> void:
	var path: String = GameState.slot_path(scratch)
	GameState.delete_slot(scratch)
	check(not GameState.has_slot_data(scratch), "the scratch slot starts clear")

	# A save from a format this build no longer accepts.
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "a stale save can be written for the test")
	if file == null:
		return
	file.store_string(JSON.stringify({"version": SaveGame.FORMAT_VERSION - 1, "tavern_name": "Ghost"}))
	file.close()

	check(GameState.has_slot_data(scratch), "a stale save still counts as a file on disk")
	check(not GameState.has_save(scratch), "but not as something that can be loaded")
	check(GameState.slot_summary(scratch).is_empty(), "and it reports no summary")
	check(GameState.has_any_slot_data(), "so the menu can still offer to clear it")

	GameState.delete_slot(scratch)
	check(not GameState.has_slot_data(scratch), "deleting a stale save removes it")


## Starting a new run must not quietly land on somebody else's save.
##
## start_new_run() refuses an occupied slot unless told to replace it, and the
## main menu used to drop that refusal on the floor and change scene anyway --
## so with all three slots full, "Open the doors" opened a world carrying the
## previous run's name, seed and purse, pointed at a save it did not own. Runs
## against the suite's scratch slot only; slots the player might actually be
## using are left alone.
func _check_new_run_slots(scratch: int) -> void:
	var gold_before: int = GameState.gold
	var name_before: String = GameState.tavern_name
	var slot_before: int = GameState.active_slot

	check(GameState.has_slot_data(scratch), "the scratch slot holds a saved tavern")
	check(
		not GameState.start_new_run("Interloper", 7, scratch, false),
		"a new run refuses an occupied slot"
	)
	check(GameState.tavern_name == name_before, "a refused run changes nothing")
	check(GameState.gold == gold_before, "and does not reset the purse")

	check(
		GameState.start_new_run("Interloper", 7, scratch, true),
		"a new run takes the slot when told to replace it"
	)
	check(GameState.active_slot == scratch, "the run owns the slot it asked for")
	check(GameState.gold == GameState.STARTING_GOLD, "a new run starts with the opening purse")
	check(GameState.world_seed == 7, "and the seed it was given")

	GameState.gold = gold_before
	GameState.tavern_name = name_before
	GameState.active_slot = slot_before


## The pause menu, the settings and what they promise. Esc used to leave the
## game outright, unsaved; now it pauses, and leaving asks first.
func _check_menus(world: TavernWorld) -> void:
	var hud: WorldHUD = world.hud
	var sim: SimClock = world.sim
	sim.speed = 2
	hud.close_top_panel()
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	world.input._unhandled_input(escape)
	check(hud.pause_menu_open(), "Esc with nothing open pauses the game rather than leaving it")
	check(sim.menu_held and sim.speed == 2, "the pause menu holds time without touching the chosen speed")
	check(world.rig.locked, "and the camera does not pan underneath it")
	hud.pause_menu.close()
	check(not sim.menu_held and not world.rig.locked and sim.speed == 2, "closing it resumes at the same speed")
	sim.speed = 1

	# Presentation never rolls the simulation's dice. Menu sounds drew from the
	# generator hiring and guests use, and a seeded run stopped repeating.
	var dice_before: int = world.sim_rng.state
	for i in range(20):
		AudioDirector.play("ui_click")
		AudioDirector.play("ui_hover")
	check(world.sim_rng.state == dice_before, "interface sounds leave the simulation's dice alone")

	# Unsaved progress: what the pause menu asks about before leaving.
	world.mark_saved()
	check(not world.has_unsaved_progress(), "just saved, nothing is unsaved")
	GameState.gold += 1
	check(world.has_unsaved_progress(), "a change to the purse is unsaved progress")
	GameState.gold -= 1

	# Settings: saved to the test's own folder, never the player's file.
	check(GameSettings.settings_path() != GameSettings.SAVE_PATH,
		"a test run keeps its settings away from the player's own file")
	var speed_before: float = GameSettings.camera_speed
	GameSettings.set_value("camera_speed", 1.7)
	GameSettings.reset_section("gameplay")
	check(is_equal_approx(GameSettings.camera_speed, 1.0), "resetting gameplay puts the camera speed back")
	GameSettings.set_value("camera_speed", speed_before)
	var scale_before: float = TavernTheme.scale_for_control(hud._hud)
	GameSettings.ui_scale = 1.2
	check(TavernTheme.scale_for_control(hud._hud) > scale_before * 1.15, "interface size scales the interface")
	GameSettings.ui_scale = 1.0

	# The settings screen opens over the game, and Back closes it.
	var screen := SettingsScreen.open(hud.pause_menu)
	check(screen.is_inside_tree() and screen._tab_buttons.size() == SettingsScreen.TABS.size(),
		"the settings screen opens with all its tabs")
	for tab in range(SettingsScreen.TABS.size()):
		screen._show_tab(tab)
	check(screen._page_holder.get_child_count() > 0, "every tab has something on it")
	screen.close()
	await get_tree().process_frame
	check(not is_instance_valid(screen), "Back closes it")


## Every shortcut can be rebound, a key does one thing, and whatever names a
## key follows the player's choice: the shortcut, the button label, the advice.
func _check_key_bindings(world: TavernWorld) -> void:
	GameSettings.reset_section("controls")
	check(InputMap.has_action("build") and KeyBindings.keys_of("build")[0] == KEY_B,
		"shortcuts start on their default keys")
	for entry in KeyBindings.ACTIONS:
		check(InputMap.has_action(entry[0]), "the %s shortcut exists" % entry[0])

	# Taking a key moves it: K goes from Staff to Build.
	var lost: String = GameSettings.bind_key("build", 0, KEY_K)
	check(lost == "staff" and KeyBindings.keys_of("staff")[0] == 0,
		"binding a key already in use takes it from the other action")
	var press := InputEventKey.new()
	press.keycode = KEY_K
	press.pressed = true
	check(press.is_action_pressed("build") and not press.is_action_pressed("staff"), "and the key now does the new thing")
	var labelled: bool = false
	for b in world.hud._keyed:
		labelled = labelled or b.text == "Build [K]"
	check(labelled, "the Build button's label follows the new key")
	check(Trouble._hire_advice(WorkType.Kind.COOK).find("(K)") < 0, "advice stops naming a key Staff no longer has")
	check(KeyBindings.bind("build", 0, KEY_ESCAPE) == "" and KeyBindings.keys_of("build")[0] == KEY_K,
		"Esc cannot be bound")

	# Kept across a restart: only the changes are written, and read back.
	var kept: Dictionary = KeyBindings.overrides()
	check(kept.has("build") and kept.has("staff") and not kept.has("pause"), "only changed shortcuts are saved")
	KeyBindings.install()
	check(KeyBindings.keys_of("build")[0] == KEY_B, "(a fresh start is back on the defaults)")
	KeyBindings.install(kept)
	check(KeyBindings.keys_of("build")[0] == KEY_K, "and the saved changes come back")

	# Rebinding through the Controls page, as the player does it.
	var screen := SettingsScreen.open(world.hud.pause_menu)
	screen._show_tab(3)
	var slot: Button = screen._slot_buttons["ledger"][0]
	screen._begin_capture("ledger", 0, slot)
	check(slot.text == "Press a key…", "a slot waits for the key")
	var key := InputEventKey.new()
	key.keycode = KEY_N
	key.pressed = true
	screen._capture_key(key)
	check(KeyBindings.keys_of("ledger")[0] == KEY_N and slot.text == "N", "pressing a key binds it there")
	screen._begin_capture("ledger", 1, screen._slot_buttons["ledger"][1])
	var clear := InputEventKey.new()
	clear.keycode = KEY_BACKSPACE
	clear.pressed = true
	screen._capture_key(clear)
	check(KeyBindings.keys_of("ledger")[1] == 0, "Backspace clears a slot")
	screen.close()
	await get_tree().process_frame

	GameSettings.reset_section("controls")
	check(KeyBindings.keys_of("staff")[0] == KEY_K and KeyBindings.keys_of("ledger")[0] == KEY_L,
		"resetting controls puts every key back")
	var restored: bool = false
	for b in world.hud._keyed:
		restored = restored or b.text == "Build [B]"
	check(restored, "and the labels with them")

