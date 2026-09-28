extends Node

## Plays the opening the way a new player would, and reports where it breaks.
##
## Every other suite tests a system. This one tests the *game*: it starts a run
## with the real starting purse, builds only what the on-screen objectives ask
## for, pays for all of it through the same code path the mouse uses, orders
## supplies from the merchant, and then lets the tavern trade until a day closes.
##
## The point is to find holes the unit tests cannot see by construction -- an
## objective that can never tick, an opening that cannot be afforded, a first
## sale that never happens -- because those are all *emergent* and every piece
## involved passes its own tests.
##
## Deliberately uses `commit_build_action` and `order_supplies` rather than
## `place_programmatic`: the scripted layouts build for free, and an opening that
## is only affordable when the buildings are free is exactly the hole this is
## looking for.

const DAY_LENGTH: float = 60.0
## How long to wait for the staff to put the tavern up. A guided player does
## wait for this, so the smoke test does too.
const BUILD_SECONDS: float = 150.0
## How long to let the tavern trade afterwards. Long enough for the ramp of
## getting the first loaf out of an empty kitchen and then selling it.
const TRADE_SECONDS: float = 240.0
## Keep enough observation time to see several payrolls with real-length days.
var trade_seconds: float = TRADE_SECONDS

var world: TavernWorld
var holes: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()
var _days_closed: int = 0


func hole(condition: bool, what: String) -> bool:
	if not condition:
		holes.append(what)
	return condition


func note(text: String) -> void:
	notes.append(text)
	# Brief: the figures that say whether the opening works at all.
	if TestOutput.brief and not text.begins_with("Purse bottomed") and not text.begins_with("First customer"):
		return
	print("  · %s" % text)


func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().quit(1)
		return
	if not GameState.begin_test_session():
		push_error("Smoke test could not isolate its save slot")
		get_tree().quit(2)
		return
	# The real day, always: at turbo speed it costs seconds, and a shortened day
	# was only ever there to save waiting. `shortday` keeps the old length.
	var short: bool = OS.get_cmdline_user_args().has("shortday")
	trade_seconds = TRADE_SECONDS if short else 720.0

	SimWait.seed_run()
	print("=== SMOKE TEST: the guided opening ===")
	GameState.start_new_run("The Smoke House", 493774, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	world.clock.day_length = DAY_LENGTH if short else DayClock.DEFAULT_DAY_LENGTH
	note("Game time: %s" % SimWait.configure(world))
	SimWait.hold(world)
	# Stand in for the player clicking "Open tomorrow". Without it the tavern
	# correctly stops dead at close of business and the rest of the test measures
	# a paused game -- which is exactly what the first run of this did.
	world.clock.day_ended.connect(func(_day: int) -> void:
		_days_closed += 1
		world.hud._day_summary.hide()
		world._begin_next_day()
	, CONNECT_DEFERRED)
	await get_tree().process_frame

	note("Opened with %dg on a %dx%d plot" % [
		GameState.gold, world.plot.size.x, world.plot.size.y])

	_objectives_in_order()
	_build_the_guided_tavern()
	SimWait.release(world)
	await _wait_for_the_builders()
	_order_supplies()
	await _trade()
	_check_save_midrun()

	_report()


## The checklist has to be completable in the order it is given.
##
## A list whose third item cannot be done until the fifth is worse than no list,
## and nothing else would catch it: each objective's test passes in isolation.
func _objectives_in_order() -> void:
	var ids: PackedStringArray = PackedStringArray()
	for objective in world.objectives.list:
		ids.append(String(objective.id))
	note("Objectives: %s" % ", ".join(ids))
	hole(world.objectives.list.size() >= 5, "the opening checklist is too short to guide anybody")
	world.objectives.refresh(world)
	hole(world.objectives.completed_count() == 0, "an objective is already ticked on an empty plot")


## Build exactly what the objectives ask for, paying for all of it.
func _build_the_guided_tavern() -> void:
	var o: Vector2i = world.plot.position + Vector2i(8, 7)
	var spent_before: int = GameState.gold

	# "Lay some flooring" -- dragged out, as the hint now tells the player to.
	_drag_floor(o, o + Vector2i(9, 5))

	# "Build a prep table and an oven", then seating, storage and a basin.
	_place("prep_table", o + Vector2i(7, 0))
	_place("oven", o + Vector2i(7, 2))
	_place("brewing_vat", o + Vector2i(7, 4))
	for row in [0, 2, 4]:
		_place("table", o + Vector2i(1, row))
		_place("chair", o + Vector2i(0, row))
		_place("chair", o + Vector2i(3, row))
	_place("storage_shelf", o + Vector2i(5, 2))
	_place("storage_shelf", o + Vector2i(5, 4))
	for row in [0, 2, 4]:
		_place("barrel", o + Vector2i(9, row))
	_place("sink", o + Vector2i(5, 0))

	var spent: int = spent_before - GameState.gold
	note("Guided build cost %dg, leaving %dg" % [spent, GameState.gold])
	hole(GameState.gold > 0, "following the objectives spends the whole purse")

	world.build.mode = BuildController.Mode.OFF


func _drag_floor(from: Vector2i, to: Vector2i) -> void:
	var def: BuildingDef = BuildingCatalog.get_def(&"wood_floor")
	world.build.mode = BuildController.Mode.PLACE
	world.build.select(def)
	hole(world.build.begin_drag(from), "flooring cannot be dragged out")
	world.build.update_hover(to, true)
	var wanted: int = world.build.drag_tiles().size()
	world.commit_area_build()
	var laid: int = 0
	for entry in world.build.grid.placements:
		if entry != null and entry["def"].id == &"wood_floor":
			laid += 1
	hole(laid == wanted, "a floor drag laid %d of %d tiles" % [laid, wanted])
	note("Floored %d tiles by dragging" % laid)


func _place(id: String, tile: Vector2i) -> void:
	var def: BuildingDef = BuildingCatalog.get_def(StringName(id))
	if not hole(def != null, "the catalog has no '%s'" % id):
		return
	world.build.mode = BuildController.Mode.PLACE
	world.build.select(def)
	world.build.update_hover(tile, true)
	var before: int = world.build.grid.live_count()
	world.commit_build_action()
	hole(
		world.build.grid.live_count() == before + 1,
		"a player following the objectives cannot place '%s' at %s" % [id, tile]
	)


func _order_supplies() -> void:
	var before: int = GameState.gold
	hole(world.order_supplies(), "the merchant refuses the opening order")
	note("Supplies cost %dg, leaving %dg" % [before - GameState.gold, GameState.gold])
	hole(GameState.gold >= 0, "the opening order overdraws the purse")
	var delivered: int = 0
	for id in world.delivered:
		delivered += int(world.delivered[id])
	hole(delivered > 0, "the delivery arrived empty")


## Wait for the staff to finish putting it up, as a player would.
##
## Faking the buildings into existence was the first version, and it produced a
## far worse bug than it avoided: marking a placement built without completing
## its job left the job on the board forever, so all five staff spent the whole
## run building things that were already there and nothing was ever cooked.
func _wait_for_the_builders() -> void:
	# Game seconds throughout: see SimWait.
	var started: float = world.sim.sim_time
	while world.sim.sim_time - started < BUILD_SECONDS:
		await get_tree().process_frame
		if world.board.count_of_kind(WorkType.Kind.CONSTRUCT) == 0:
			break
	var outstanding: int = world.board.count_of_kind(WorkType.Kind.CONSTRUCT)
	var unbuilt: int = 0
	for entry in world.build.grid.placements:
		if entry != null and not entry["built"]:
			unbuilt += 1
	note("Built in %.0fs, %d pieces still up in the air" % [
		world.sim.sim_time - started, unbuilt])
	hole(outstanding == 0 and unbuilt == 0,
		"%d pieces were never built in %ds" % [unbuilt, int(BUILD_SECONDS)])

	world.objectives.refresh(world)
	for objective in world.objectives.list:
		if objective.id in [&"first_sale", &"profit", &"supplies"]:
			continue
		hole(objective.done, "objective '%s' cannot be completed by following it" % objective.id)
	hole(world.customers.seating.seats.size() >= 6, "the guided build does not produce six seats")


## Let it run, and see whether a tavern actually happens.
func _trade() -> void:
	world.build.mode = BuildController.Mode.OFF
	var started: float = world.sim.sim_time
	var first_sale_at: float = -1.0
	# Watched every frame rather than at day boundaries. Going broke is the one
	# failure a player cannot recover from, and it can happen between them.
	var lowest: int = GameState.gold
	var lowest_day: int = world.clock.day
	while world.sim.sim_time - started < trade_seconds:
		await get_tree().process_frame
		if GameState.gold < lowest:
			lowest = GameState.gold
			lowest_day = world.clock.day
		if first_sale_at < 0.0 and world.customers.served_count > 0:
			first_sale_at = world.sim.sim_time - started
			note("First customer served after %.0fs" % first_sale_at)

	note("Purse bottomed out at %dg on day %d" % [lowest, lowest_day])
	hole(lowest >= 0, "a player following the objectives goes broke")
	if lowest < 40:
		note("WARNING: only %dg of headroom at the worst point" % lowest)

	note("Traded: %s" % world.customers.summary())
	note("Kitchen produced: %s" % _made())
	hole(first_sale_at >= 0.0, "nobody was served in %ds of trading" % int(trade_seconds))
	note("Days closed while trading: %d" % _days_closed)
	hole(world.ledger.history.size() >= 1, "no day ever closed")
	hole(world.generator.produced.get(&"beer", 0) + world.generator.produced.get(&"bread", 0) > 0,
		"the kitchen produced nothing at all")
	hole(world.customers.reputation.window.size() > 0, "nobody left a review")

	world.objectives.refresh(world)
	hole(world.objectives.list[5].done, "the first-sale objective never ticked")

	var scenario: Node = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	add_child(scenario)
	hole(scenario.reconcile(), "the books do not balance after a day's trading")


func _made() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for id in [&"dough", &"bread", &"beer"]:
		parts.append("%s %d" % [id, int(world.generator.produced.get(id, 0))])
	# Dishes are left by patrons, not turned out by a recipe, so they are not in
	# the generator's tally at all.
	parts.append("dishes %d" % world.customers.dishes_left)
	return ", ".join(parts)


## Mid-run save and reload, which is what a player actually does.
func _check_save_midrun() -> void:
	var gold: int = GameState.gold
	var built: int = world.build.grid.live_count()
	var served: int = world.customers.served_count
	hole(world.save_now(), "the tavern cannot be saved mid-run")

	var raw: Dictionary = SaveGame.read(GameState.active_slot)
	if not hole(not raw.is_empty(), "a saved tavern cannot be read back"):
		return
	# Continue, as the player does it: the world loads itself as it enters.
	hole(GameState.request_continue(GameState.active_slot), "a saved tavern cannot be continued")
	var reloaded: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(reloaded)

	hole(GameState.gold == gold, "the purse changes across a reload")
	hole(reloaded.build.grid.live_count() == built, "buildings are lost across a reload")
	hole(reloaded.customers.served_count == served, "the day's trade is lost across a reload")
	note("Reload kept %d buildings, %dg and %d served" % [built, gold, served])
	reloaded.queue_free()
	GameState.delete_slot(GameState.active_slot)
	GameState.active_slot = -1


func _report() -> void:
	print("--- smoke test ---")
	for line in notes:
		print("  %s" % line)
	if holes.is_empty():
		print("SMOKE TEST PASS: no holes in the guided opening")
	else:
		print("SMOKE TEST: %d hole(s)" % holes.size())
		for line in holes:
			print("  HOLE: %s" % line)
	get_tree().quit(1 if holes.size() > 0 else 0)
