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
	# No slot is owned: this lifecycle test never writes a player save.
	GameState.active_slot = -1
	GameState.world_seed = 12345
	GameState.tavern_name = "Day Boundary Arms"
	GameState.gold = 600
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	var scenario: Node = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	add_child(scenario)
	scenario.build_demo_tavern()
	world.items.add(ItemCatalog.get_def(&"beer"), 4, world.plot.position + Vector2i(17, 13))
	world.customers._try_spawn()
	check(world.customers.customers.size() == 1, "fixture has a live customer at closing")
	world.clock.fraction = 1.0
	world.clock.paused = true
	world._on_day_ended(1)
	var guest: CustomerBrain = world.customers.customers[0]
	var guest_position: Vector3 = guest.pawn.position
	var guest_state: int = guest.state
	await get_tree().create_timer(0.15).timeout
	check(guest.pawn.position.is_equal_approx(guest_position) and guest.state == guest_state,
		"customer movement and decisions pause behind the summary")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world)))
	var purse: int = GameState.gold
	check(world.ledger.history.size() == 1, "closing creates one ledger entry")
	check(purse == 600 - world.wage_bill(), "closing charges wages once")
	var original: TavernWorld = world
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SaveGame.apply(world, saved)
	original.free()
	check(world.clock.paused and world.hud._day_summary.visible, "loading a closed day restores its paused summary")
	check(world.simulation_paused and world.sim.held, "freshly loaded summary holds the whole simulation before any close signal")
	world.clock.sim_step(0.1)
	check(GameState.gold == purse, "loading a closed day does not charge wages again")
	check(world.ledger.history.size() == 1, "loading a closed day does not close the ledger again")
	world._on_day_ended(1)
	check(GameState.gold == purse and world.ledger.history.size() == 1, "duplicate close signal is harmless")
	# Actual process dispatch, not a paused clock alone, must hold workers still.
	var pawn: Pawn = world.pawns[0]
	pawn.goto(world.nav.random_walkable_in(world.plot, RandomNumberGenerator.new()))
	var position_before: Vector3 = pawn.position
	var generator_timer: float = world.generator._timer
	await get_tree().create_timer(0.2).timeout
	check(pawn.position.is_equal_approx(position_before), "workers stay still behind the summary")
	check(is_equal_approx(world.generator._timer, generator_timer), "job generation pauses with the summary")
	check(world.rig.can_process() and world.hud.can_process(), "camera and summary UI remain active")
	world._begin_next_day()
	check(world.clock.day == 2 and not world.clock.paused, "continue advances exactly one day")
	check(pawn.can_process() and world.generator.can_process(), "continue resumes the simulation")
	check(GameState.gold == purse, "continuing does not charge a second payroll")
	world._begin_next_day()
	check(world.clock.day == 2, "duplicate summary dismissal does not skip a day")
	var starts: Array[int] = [0]
	world.clock.day_started.connect(func(_day: int) -> void: starts[0] += 1)
	world.clock.sim_step(0.01)
	check(starts[0] == 0, "first resumed tick does not emit day-start a second time")
	world.queue_free()
	print("DAY REGRESSIONS: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
