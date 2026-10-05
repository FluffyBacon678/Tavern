extends Node

## Plays the demo level twice: once badly, once well.
##
## A designed level makes two claims, and both can be wrong independently.
##
##   * That its faults *bite*. The Wayfarer's Rest is built around three gaps --
##     no prep table, one shelf, no wash basin -- and if a player can ignore all
##     three and still hit the target, the level teaches nothing.
##   * That it is *winnable*. If a player who fixes them cannot reach the goal
##     by its deadline, the target is a lie.
##
## Options after `--`: `realday` (the 180s day; the only length to tune the goal
## against), `playedonly`, `latefix` (repair on day 3, like a first-time player)
## and `unfixed` (keep the larder full, never repair; must *not* win).
##
## So: run it untouched and check the faults show, then run it again fixing them
## and check the goal comes in. Neither run alone would tell you the level works.

## The real 180-second day, always. It used to be shortened to 45s to keep the
## suite to minutes, which made the goal unmeasurable -- wages are per day and
## production per second, so a short day reads far poorer than the tavern is.
## The suite now runs on the SimClock at turbo speed (see SimWait), so the real
## day costs seconds. `shortday` keeps the old length for comparison; `realday`
## is still accepted and changes nothing.
const DAY_LENGTH: float = 45.0
## The game's own day, so the goal is always judged at the length players get.
const REAL_DAY_LENGTH: float = DayClock.DEFAULT_DAY_LENGTH
## Long enough for the faults to show in the neglected run.
const NEGLECT_DAYS: float = 2.7
## Six full days plus the morning ramp, for the run that is actually played.
const PLAY_DAYS: float = 6.4
## Share of day_length a day actually lasts: it opens just before 08:00 and ends
## at midnight, so a "day" is about 16.5 of its 24 hours.
const DAY_FRACTION_OPEN: float = 16.5 / 24.0

var day_length: float = REAL_DAY_LENGTH
## What SimWait set the clock to, for the banner and the report.
var _time_mode: String = ""
## Gold at each close of business, so the goal is judged on the day it names.
var _closes: Dictionary = {}
## Every close of every played branch, in order, so a replay can be compared.
var _close_log: Array = []
var _stranded_at_close: PackedStringArray = PackedStringArray()

var holes: PackedStringArray = PackedStringArray()
## Jobs finished and jobs abandoned, so a stall can be told apart from a crawl.
var _completed: int = 0
var _cancelled: int = 0
## Completions split by job key prefix, because "47 jobs finished" hides the one
## thing that matters: whether any of them were the ones feeding a bench.
var _by_key: Dictionary = {}


func hole(condition: bool, what: String) -> bool:
	if not condition:
		holes.append(what)
	return condition


func note(text: String) -> void:
	# Brief: each branch's name and its day-6 purse, which is the whole verdict.
	if TestOutput.brief and not text.begins_with("---") and not text.begins_with("Purse at the close"):
		return
	print("  · %s" % text)


func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().quit(1)
		return
	if not GameState.begin_test_session():
		push_error("Level smoke could not isolate its save slot")
		get_tree().quit(2)
		return
	if OS.get_cmdline_user_args().has("shortday"):
		day_length = DAY_LENGTH
	SimWait.seed_run()
	print("=== LEVEL SMOKE: The Wayfarer's Rest (%.0fs days, %s) ===" % [day_length,
		"real time" if OS.get_cmdline_user_args().has("realtime") else "turbo"])

	var level: LevelDef = LevelCatalog.get_level(&"wayfarers_rest")
	if not hole(level != null, "the demo level is not in the catalog"):
		_report()
		return

	_check_the_design(level)
	# `playedonly` skips the neglected branch, for long real-day measurements of
	# the goal. The faults it checks do not depend on the day length.
	# `unfixed` runs only the supplied-but-unrepaired branch, which is what shows
	# whether the goal actually depends on the lesson.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("unfixed"):
		await _run_unfixed(level)
		_report()
		return
	if args.has("playedonly"):
		await _run_played(level, args.has("latefix"))
		_report()
		return
	# All four by default, now that the real day costs seconds: the faults must
	# show when neglected, and the goal must fall to a player who repairs at
	# once, to one who repairs on day 3, and never to one who does not repair
	# at all. The goal's tuning is enforced here rather than measured once.
	note("--- neglected ---")
	await _run_neglected(level)
	note("--- repaired at once ---")
	await _run_played(level, false)
	note("--- repaired on day 3, like a first-time player ---")
	await _run_played(level, true)
	note("--- supplied but never repaired ---")
	await _run_unfixed(level)
	# The same branch twice must agree to the coin. Every suite leans on runs
	# being repeatable; anything that brings real time or unseeded chance into
	# the simulation shows up here first, as two different purses.
	note("--- repaired at once, replayed ---")
	_close_log.clear()
	await _run_played(level, false)
	var first: Array = _close_log.duplicate()
	_close_log.clear()
	await _run_played(level, false)
	hole(first == _close_log, "the same run played twice came out differently: %s against %s" % [first, _close_log])
	_report()


## The gaps have to be real, and the level has to be self-consistent.
func _check_the_design(level: LevelDef) -> void:
	var counts: Dictionary = {}
	for piece in level.pieces:
		counts[piece.id] = int(counts.get(piece.id, 0)) + 1
	note("Level ships %d pieces: %d floor, %d wall, %d table, %d chair" % [
		level.pieces.size(), int(counts.get(&"wood_floor", 0)),
		int(counts.get(&"timber_wall", 0)), int(counts.get(&"table", 0)),
		int(counts.get(&"chair", 0))])

	hole(int(counts.get(&"prep_table", 0)) == 0, "the level's missing prep table is not missing")
	hole(int(counts.get(&"sink", 0)) == 0, "the level's missing wash basin is not missing")
	hole(int(counts.get(&"storage_shelf", 0)) == 1, "the level should ship exactly one shelf")
	hole(int(counts.get(&"oven", 0)) >= 1, "there is no oven to pair with the missing prep table")
	hole(int(counts.get(&"brewing_vat", 0)) >= 1, "there is nothing to sell from minute one")
	hole(int(counts.get(&"door", 0)) >= 1, "the tavern has no way in")

	# The player must be able to afford at least two of the three fixes, and
	# not all three plus seating -- that is the decision the level is made of.
	var prep: int = BuildingCatalog.get_def(&"prep_table").cost
	var sink: int = BuildingCatalog.get_def(&"sink").cost
	var shelf: int = BuildingCatalog.get_def(&"storage_shelf").cost
	note("Fixes cost prep %dg + basin %dg + shelf %dg = %dg, against %dg in the purse" % [
		prep, sink, shelf, prep + sink + shelf, level.starting_gold])
	hole(level.starting_gold >= prep + sink, "the two most important fixes are unaffordable")
	hole(level.goal_gold > level.starting_gold, "the target is already met on opening")


## Left exactly as inherited. The faults should be visible within two days.
func _run_neglected(level: LevelDef) -> void:
	var world: TavernWorld = await _open(level)
	await _wait(NEGLECT_DAYS * day_length, world)

	var bread: int = int(world.generator.produced.get(&"bread", 0))
	var beer: int = int(world.generator.produced.get(&"beer", 0))
	var dishes: int = world.customers.dishes_left - int(world.generator.consumed.get(&"dirty_dishes", 0))
	note("Neglected: %d bread, %d beer, %d dishes left standing, %s" % [
		bread, beer, dishes, world.customers.summary()])

	if not hole(beer > 0, "the inherited tavern cannot even sell the ale it starts with"):
		_diagnose(world)
	hole(bread == 0, "bread was baked with no prep table, so the two-stage chain is not being taught")
	hole(dishes > 0, "no dishes piled up, so the missing wash basin teaches nothing")
	note("Storage: %s" % _storage(world))
	world.queue_free()
	await get_tree().process_frame


## Played properly: close the three gaps, then trade.
func _run_played(level: LevelDef, late: bool = false) -> void:
	var world: TavernWorld = await _open(level)
	# The level's own origin: it moved when the plot grew, and repairs placed
	# from the old one landed outside the building.
	var o: Vector2i = world.plot.position + level.origin
	# `latefix` plays the way a first-time player does: trade the tavern as
	# inherited for two days, notice what is wrong, then repair it. The goal is
	# tuned against this run, not against a fixture that repairs in the first
	# second -- a player has to find the faults before fixing them.
	if late:
		world.order_supplies()
		await _wait(2.0 * day_length * DAY_FRACTION_OPEN, world)
		note("Repairing late, on day %d with %dg" % [world.clock.day, GameState.gold])

	# What a player who has read the room would buy first. Tiles picked clear of
	# what the level already ships -- the first attempt put the prep table
	# inside the brewing vat, the purchase failed, and the run then measured a
	# tavern that had never been fixed at all.
	_buy(world, "prep_table", o + Vector2i(1, 3))
	# Not o + (5, 7): as a 2x1 it covers (6, 7), the only tile inside the door.
	# That placement sealed the tavern and cost five straight days of "no seat"
	# with every seat free. Not (7, 7) either: that boxes in the two tiles beside
	# the level's shelf, and anything spilled there is lost to the kitchen.
	_buy(world, "sink", o + Vector2i(3, 7))
	_buy(world, "storage_shelf", o + Vector2i(1, 7))
	note("After fixing the faults: %dg left" % GameState.gold)
	hole(GameState.gold >= 0, "fixing the level's faults overdraws the purse")
	var blocked: String = world.route_warning()
	hole(blocked == "", "the player's repairs cut the tavern off: %s" % blocked)

	var by_deadline: int = await _trade(world, level)
	var met: bool = by_deadline >= level.goal_gold
	note("Played: day %d, %dg in the purse, %s" % [
		world.clock.day, GameState.gold, world.customers.summary()])
	note("Kitchen: %d bread, %d beer, %d dishes washed" % [
		int(world.generator.produced.get(&"bread", 0)),
		int(world.generator.produced.get(&"beer", 0)),
		int(world.generator.consumed.get(&"dirty_dishes", 0))])
	_diagnose(world)
	hole(int(world.generator.produced.get(&"bread", 0)) > 0, "a prep table did not unblock bread")
	# Only at the real day. A shortened day charges the same wages for a third of
	# the trading, so it always reads as a loss -- a hole it would report forever.
	if is_equal_approx(day_length, REAL_DAY_LENGTH):
		hole(met, "%s cannot win: %dg of %dg by day %d" % [
			"a player who repairs on day 3" if late else "a player who repairs at once",
			by_deadline, level.goal_gold, level.goal_days])
	else:
		note("Goal not judged at a %.0fs day; pass `realday` for that" % day_length)

	# Without quitting on failure, so a bad reconciliation is reported as a hole
	# alongside everything else rather than ending the run mid-report. The
	# playtest review pointed out this fixture never checked the books at all,
	# which meant its abandonment counts could not be told apart from lost goods.
	var scenario: Node = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	add_child(scenario)
	hole(scenario.reconcile(false), "the books do not balance after playing the level")
	scenario.queue_free()
	world.queue_free()
	await get_tree().process_frame


## Supplied and restocked, but never repaired: the player who keeps the larder
## full and never reads the room. If this wins, the goal teaches nothing -- the
## three faults are the whole lesson of the level.
func _run_unfixed(level: LevelDef) -> void:
	var world: TavernWorld = await _open(level)
	var by_deadline: int = await _trade(world, level)
	note("Unfixed: %d bread, %d beer, %s" % [
		int(world.generator.produced.get(&"bread", 0)),
		int(world.generator.produced.get(&"beer", 0)),
		world.customers.summary()])
	hole(by_deadline < level.goal_gold,
		"the goal is met without fixing anything: %dg of %dg by day %d" % [
			by_deadline, level.goal_gold, level.goal_days])
	world.queue_free()
	await get_tree().process_frame


## Order, then reorder the way a player managing their stock would: when an
## ingredient is down to its last couple. A fixture that orders once measures
## how long one delivery lasts, not whether the tavern can hit a target -- the
## review of this level made exactly that point. Returns the purse at the close
## of the goal's deadline day.
func _trade(world: TavernWorld, level: LevelDef) -> int:
	world.order_supplies()
	world.clock.day_started.connect(func(_day: int) -> void:
		# Down to the last batch's worth: one unit, now that goods come in bulk
		# (at two, the usual order of two would be bought again every morning).
		for id in [&"flour", &"water", &"yeast", &"malt", &"hops"]:
			if world.items.total_of(id) <= 1:
				world.order_supplies()
				return
	)
	await _wait(PLAY_DAYS * day_length * DAY_FRACTION_OPEN, world)

	var closes: PackedStringArray = PackedStringArray()
	for day in _closes:
		closes.append("d%d %dg" % [day, int(_closes[day])])
	note("Purse at close: %s" % ", ".join(closes))
	var by_deadline: int = int(_closes.get(level.goal_days, GameState.gold))
	note("Purse at the close of day %d: %dg (goal %dg)" % [level.goal_days, by_deadline, level.goal_gold])
	return by_deadline


## Workers standing where nobody walking from the road could get to. A worker
## there can reach nothing, so every job it looks at reads "nowhere to stand"
## and it idles for the rest of the run -- invisible except as a board that
## never empties.
func _stranded(world: TavernWorld) -> PackedStringArray:
	world.generator.invalidate_reach()
	world.generator.scan()
	var out: PackedStringArray = PackedStringArray()
	for pawn in world.pawns:
		if not world.generator._reach.is_empty() and not world.generator._reach.has(pawn.tile):
			out.append("%s" % pawn.tile)
	return out


## Everything needed to say *why* a kitchen has stopped, in one place.
##
## Printed rather than asserted: a stall has several possible causes that want
## completely different fixes, and a boolean would only tell you it happened.
func _diagnose(world: TavernWorld) -> void:
	var kitchen: PackedStringArray = PackedStringArray()
	for station in world.generator.built_stations():
		for recipe in station["recipes"]:
			var missing: PackedStringArray = PackedStringArray()
			for need in recipe.inputs:
				var have: int = world.generator.count_at_station(station, need["id"])
				if have < int(need["count"]):
					missing.append("%s %d/%d (%s)" % [
						need["id"], have, need["count"],
						world.generator.feed_problem(station, need["id"])])
			var stock: int = 0
			if not recipe.outputs.is_empty():
				stock = world.items.total_of(recipe.outputs[0]["id"])
			kitchen.append("%s [%s]%s" % [
				recipe.display_name, world.bills.status_text(recipe.id, stock),
				"" if missing.is_empty() else " waiting on " + ", ".join(missing)])
	note("Kitchen: %s" % " | ".join(kitchen))

	var goods: PackedStringArray = PackedStringArray()
	for def in ItemCatalog.all():
		var total: int = world.items.total_of(def.id)
		if total > 0:
			goods.append("%s %d" % [def.id, total])
	note("On the ground: %s" % (", ".join(goods) if goods.size() > 0 else "nothing"))
	note("Storage: %s" % _storage(world))

	var kinds: PackedStringArray = PackedStringArray()
	for kind in range(WorkType.COUNT):
		kinds.append("%s=%d" % [WorkType.display_name(kind), world.board.count_of_kind(kind)])
	note("Board: %d open, %d active (%s)" % [
		world.board.open_count(), world.board.active_count(), " ".join(kinds)])

	var staff: PackedStringArray = PackedStringArray()
	for worker in world.workers:
		staff.append(worker.status_text())
	note("Staff: %s" % " | ".join(staff))
	var stranded: PackedStringArray = _stranded(world)
	note("Staff off the road's reach: %s; at the closes: %s" % [
		"none" if stranded.is_empty() else ", ".join(stranded),
		"none" if _stranded_at_close.is_empty() else ", ".join(_stranded_at_close)])
	var split: PackedStringArray = PackedStringArray()
	for kind in _by_key:
		split.append("%s %d" % [kind, int(_by_key[kind])])
	note("Ingredients filed away from a bench that wanted them: %d" % world.generator.stolen_from_benches)
	note("Dead pickup jobs withdrawn: %d" % world.generator.dead_pickups_withdrawn)
	note("No route to a job: %d" % Worker.gave_up_no_route)
	note("Abandoned: %d nowhere to stand, %d goods gone, %d could not walk, %d could not deliver" % [
		Worker.gave_up_nowhere_to_stand, Worker.gave_up_goods_gone,
		Worker.gave_up_could_not_walk, Worker.gave_up_cannot_deliver])
	note("Jobs: %d completed (%s), %d cancelled" % [
		_completed, ", ".join(split), _cancelled])

	# Where the goods actually are, against where a bench would take them. A
	# kitchen that is "waiting on yeast" with twelve yeast in the world is either
	# unable to reach them or unable to put them down, and the two look identical
	# from the job board.
	for station in world.generator.built_stations():
		var tiles: Array = station["input_tiles"]
		var free: int = 0
		for tile in tiles:
			if not world.items.has_stack(tile):
				free += 1
		var reachable: int = 0
		for tile in tiles:
			if world.nav.is_walkable(tile):
				reachable += 1
		note("  %s at %s: %d input tiles, %d empty, %d walkable" % [
			station["def"].id, station["centre"], tiles.size(), free, reachable])
	# A stack on a shelf sits on a solid tile and is taken from beside it, so
	# "not walkable" is not "unreachable": only no way to stand next to it is.
	var reach: Dictionary = world.nav.reachable_from(world.workers[0].pawn.tile) if not world.workers.is_empty() else {}
	for id in [&"yeast", &"water"]:
		var where: PackedStringArray = PackedStringArray()
		for tile in world.items.tiles_with(id, world.plot.position):
			var standable: bool = reach.has(tile)
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				standable = standable or reach.has(tile + step)
			where.append("%s x%d%s" % [tile, world.items.count_at(tile),
				"" if world.nav.is_walkable(tile) else (" on a shelf" if standable else " UNREACHABLE")])
		note("  %s sits at: %s" % [id, ", ".join(where)])

	var untaken: PackedStringArray = PackedStringArray()
	for job in world.board.jobs:
		if job.claimant == null:
			untaken.append("%s refused by %d" % [job.label, job.failed_for.size()])
	if not untaken.is_empty():
		note("Untaken: %s" % " | ".join(untaken))


func _open(level: LevelDef) -> TavernWorld:
	# Seeded afresh for every world, so a branch plays out the same whether it
	# runs alone or after the others -- it used to depend on what ran before.
	SimWait.seed_run()
	GameState.pending_level = level.id
	GameState.start_new_run(level.tavern_name, level.world_seed, GameState.MAX_SLOTS - 1, true)
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	world.clock.day_length = day_length
	_time_mode = SimWait.configure(world)
	SimWait.hold(world)
	_completed = 0
	_cancelled = 0
	_by_key.clear()
	_closes.clear()
	_stranded_at_close.clear()
	# The worker's counters are static, so without a reset the played run's
	# report silently included everything that went wrong in the neglected one.
	Worker.gave_up_nowhere_to_stand = 0
	Worker.gave_up_goods_gone = 0
	Worker.gave_up_could_not_walk = 0
	Worker.gave_up_cannot_deliver = 0
	Worker.gave_up_no_route = 0
	world.board.job_completed.connect(func(j: Job) -> void:
		_completed += 1
		var kind: String = j.key.split(":")[0] if not j.key.is_empty() else "build"
		_by_key[kind] = int(_by_key.get(kind, 0)) + 1
	)
	world.board.job_cancelled.connect(func(_j: Job) -> void: _cancelled += 1)
	world.clock.day_ended.connect(func(day: int) -> void:
		_closes[day] = GameState.gold
		_close_log.append([day, GameState.gold])
		for tile in _stranded(world):
			_stranded_at_close.append("d%d %s" % [day, tile])
		world.hud._day_summary.hide()
		world._begin_next_day()
	, CONNECT_DEFERRED)
	await get_tree().process_frame
	# The branch's opening moves happen synchronously after this returns, so
	# they all land at game time zero, whatever ran before this world.
	SimWait.release(world)
	return world


func _buy(world: TavernWorld, id: String, tile: Vector2i) -> void:
	var def: BuildingDef = BuildingCatalog.get_def(StringName(id))
	world.build.mode = BuildController.Mode.PLACE
	world.build.select(def)
	world.build.update_hover(tile, true)
	var before: int = world.build.grid.live_count()
	world.commit_build_action()
	hole(world.build.grid.live_count() == before + 1, "a player cannot put a '%s' at %s" % [id, tile])
	world.build.mode = BuildController.Mode.OFF


## Game seconds, not wall-clock ones: see SimWait.
func _wait(seconds: float, world: TavernWorld) -> void:
	await SimWait.seconds(world, seconds)


func _storage(world: TavernWorld) -> String:
	var tiles: int = 0
	var empty: int = 0
	for entry in world.build.grid.placements:
		if entry == null or not entry["built"] or not entry["def"].is_storage:
			continue
		for tile in entry["tiles"]:
			tiles += 1
			if not world.items.has_stack(tile):
				empty += 1
	return "%d tiles, %d empty" % [tiles, empty]


func _report() -> void:
	if holes.is_empty():
		print("LEVEL SMOKE PASS: the level teaches its lessons and can be won")
	else:
		print("LEVEL SMOKE: %d hole(s)" % holes.size())
		for line in holes:
			print("  HOLE: %s" % line)
	GameState.delete_slot(GameState.MAX_SLOTS - 1)
	GameState.active_slot = -1
	get_tree().quit(1 if holes.size() > 0 else 0)
