extends Node

## One group of the regression suite, run on a tavern of its own.
##
## The suite used to be one 1,800-line file with thirty checks sharing a single
## world, each inheriting whatever the one before it left behind -- stock on the
## ground, a demolished chair, a moved pawn. A check could pass only because of
## an earlier one, and fail for reasons nowhere near it. Now each group builds
## the same fresh fixture, and anything a check needs it must set up itself.
##
## A group overrides run(); `dev/regressions.gd` builds the fixture, runs the
## groups in turn and adds up their failures.

var failures: int = 0
## The fixture: the demo tavern, simulation stopped, pawns routed once.
var fixture_world: TavernWorld
var fixture_scenario: Node


func check(condition: bool, message: String) -> void:
	TestOutput.check_line(condition, message)
	if not condition:
		failures += 1


## Override. May await.
func run() -> void:
	pass


## The same starting point for every group: seed 12345, the 202-piece demo
## tavern, nothing ticking unless a check starts it.
func build_fixture() -> void:
	GameState.world_seed = 12345
	GameState.active_slot = -1
	GameState.load_requested = false
	GameState.new_run_pending = false
	GameState.pending_level = &""
	GameState.gold = GameState.STARTING_GOLD
	seed(12345)
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	world.set_process(false)
	world.generator.set_process(false)
	world.customers.set_process(false)
	world.clock.paused = true
	for worker in world.workers:
		worker.set_process(false)
		worker.pawn.set_process(false)
	var scenario: Node = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	add_child(scenario)
	var layout: Dictionary = scenario.build_demo_tavern(false)
	check(layout["placed"] == 202 and layout["refused"] == 0, "202-piece layout")
	var paths: Dictionary = scenario.run_path_test()
	# All of them, however many there are: the claim is that the doorway is the
	# only way in and everybody found it, not that the tavern employs five.
	check(paths["routed"] == paths["total"] and paths["total"] > 0, "every pawn routes through the doorway")
	fixture_world = world
	fixture_scenario = scenario


func free_fixture() -> void:
	if is_instance_valid(fixture_world):
		fixture_world.queue_free()
	if is_instance_valid(fixture_scenario):
		fixture_scenario.queue_free()
	fixture_world = null
	fixture_scenario = null
	await get_tree().process_frame


## Open for trade: one supply delivery, and a little bread and beer to sell.
## Patrons do not come to a tavern with nothing to sell, and the objectives and
## trouble checks read the delivery. These used to arrive as leftovers from the
## goods checks run before them; a group that needs them now says so.
func open_for_trade(world: TavernWorld) -> void:
	check(world.order_supplies(), "the fixture takes a supply delivery")
	var yard: Vector2i = world.plot.position + Vector2i(2, 2)
	for id in [&"bread", &"beer"]:
		var def: ItemDef = ItemCatalog.get_def(id)
		var tile: Vector2i = _free_tile(world, yard)
		world.items.add(def, 4, tile, ItemWorld.BASE_QUALITY)
		world.delivered[id] = world.delivered.get(id, 0) + 4
		yard = tile + Vector2i(0, 1)
	check(world.stock_of(&"bread") > 0 and world.stock_of(&"beer") > 0, "and has bread and beer to sell")


## Somewhere with nothing on it, for parking test goods out of the way.
func _free_tile(world: TavernWorld, from: Vector2i) -> Vector2i:
	var tile: Vector2i = from
	for step in range(200):
		if not world.items.has_stack(tile):
			return tile
		tile += Vector2i(1, 0)
	return from
