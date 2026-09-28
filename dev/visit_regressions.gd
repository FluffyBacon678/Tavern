extends Node

var failures: int = 0


func check(condition: bool, message: String) -> void:
	TestOutput.check_line(condition, message)
	if not condition:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(1)
		return
	GameState.world_seed = 12345
	GameState.tavern_name = "Visit Round Trip Arms"
	GameState.gold = 600
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	var scenario: Node = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	add_child(scenario)
	scenario.build_demo_tavern()
	var beer: ItemDef = ItemCatalog.get_def(&"beer")
	var storage: Vector2i = world.plot.position + Vector2i(17, 13)
	world.items.add(beer, 2, storage, 0.8)
	world.generator.produced[&"beer"] = 2
	world.customers._try_spawn()
	check(world.customers.customers.size() == 1, "fixture creates one diner")
	var brain: CustomerBrain = world.customers.customers[0]
	brain.pawn.stop()
	brain.seat = brain.seating.claim(brain, brain.pawn.tile)
	brain.pawn.tile = brain.seat
	brain.pawn.position = brain.pawn.world_position_of(brain.pawn.tile)
	brain.order = [{"id": &"beer", "count": 2, "served": 0}]
	brain.state = CustomerBrain.State.WAITING_FOR_ORDER
	brain._did_order = true
	brain._patience = CustomerBrain.PATIENCE_FOR_ORDER
	var table: Vector2i = brain.seating.table_for(brain.seat)
	world.items.take(storage, 1)
	world.items.add(beer, 1, table, 0.8)
	brain._process_waiting(0.0)
	check(brain.order[0]["served"] == 1, "fixture has a partially served order")
	var purse: int = GameState.gold
	world = _reload(world)
	check(world.customers.customers.size() == 1, "partially served diner survives save/load")
	if world.customers.customers.size() != 1:
		_finish(world)
		return
	brain = world.customers.customers[0]
	check(brain.state == CustomerBrain.State.WAITING_FOR_ORDER and brain.order[0]["served"] == 1,
		"partial order restores its outstanding quantity")
	check(brain._food_eaten == 1 and is_equal_approx(brain._food_quality_sum, 0.8), "food already consumed retains quantity and quality")
	check(world.customers.consumed.get(&"beer", 0) == 1 and world.items.total_of(&"beer") == 1,
		"one consumed and one physical beer remain accounted for")
	check(GameState.gold == purse and world.customers.served_count == 0, "save/load does not prematurely bill a diner")
	table = brain.seating.table_for(brain.seat)
	var remaining: Vector2i = world.items.all_tiles()[0]
	world.items.take(remaining, 1)
	world.items.add(beer, 1, table, 0.8)
	brain._process_waiting(0.0)
	check(brain.state == CustomerBrain.State.EATING, "remaining delivery completes the order")
	world = _reload(world)
	brain = world.customers.customers[0]
	check(brain.state == CustomerBrain.State.EATING and brain._food_eaten == 2, "eating diner survives reload")
	brain._process_eating(CustomerBrain.EAT_TIME + 0.1)
	check(brain.state == CustomerBrain.State.WAITING_FOR_BILL and GameState.gold == purse,
		"a diner who has eaten waits for the bill rather than paying on their own")
	world = _reload(world)
	brain = world.customers.customers[0]
	check(brain.state == CustomerBrain.State.WAITING_FOR_BILL and GameState.gold == purse,
		"a diner waiting for the bill survives reload, still unpaid")
	# 16g of beer; the tip is by this guest's own kind (4g for an ordinary one).
	var owed: int = brain.bill_so_far() + brain.tip_so_far()
	check(brain.bill_so_far() == 16, "the restored diner owes for two beers")
	check(brain.settle(), "bringing the bill settles it")
	check(GameState.gold == purse + owed and world.customers.served_count == 1,
		"restored diner pays the 16g bill and a %s's %dg tip, once" % [brain.guest_type.title.to_lower(), owed - 16])
	check(world.customers.dishes_left == 1 and world.items.total_of(&"dirty_dishes") == 1,
		"restored visit creates exactly one set of dishes")
	world = _reload(world)
	brain = world.customers.customers[0]
	brain.sim_step(0.0)
	check(GameState.gold == purse + owed and world.customers.served_count == 1, "leaving diner is not billed again after reload")
	check(world.customers.day_reviews.size() == 1 and world.customers.consumed.get(&"beer", 0) == 2,
		"review and lifetime consumption survive reload")
	var invalid: Dictionary = CustomerSnapshot.capture(world.customers)
	invalid["guests"][0]["order"][0]["served"] = 999
	check(not CustomerSnapshot.valid(invalid), "malformed served quantities are rejected")
	_finish(world)


func _finish(world: TavernWorld) -> void:
	world.queue_free()
	print("VISIT REGRESSIONS: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _reload(old: TavernWorld) -> TavernWorld:
	# A fresh world and JSON conversion are essential: applying into the same
	# world would let unsaved customers survive in memory and falsely pass.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(old)))
	var restored: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(restored)
	SaveGame.apply(restored, saved)
	old.free()
	return restored
