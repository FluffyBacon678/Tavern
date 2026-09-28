extends Node

## Plays a tavern badly and at random, checking after every move that the world
## still makes sense.
##
## Every other suite plays the game the way it is meant to be played. Players do
## not: they knock down a table with somebody eating at it, save in the middle
## of the rush, untick the only shelf that takes flour, hire three people at
## once and switch everybody off serving. The bugs this project has found have
## all been emergent -- invisible to any one system's tests -- and the likeliest
## place for the next one is an order of events nobody thought to try.
##
## So: a seeded stream of random player actions, through the same code paths
## the mouse uses, and after each one a set of invariants that should hold
## whatever the player has done. A broken invariant is reported with the seed
## and the actions leading up to it, so it can be replayed.
##
##   Godot --headless --path . res://dev/chaos_test.tscn -- seed=7 seconds=1800
##
## Runs in game time at turbo speed (see SimWait), so it is fast, and the same
## seed plays out the same way every time: it ends by printing a FINGERPRINT of
## the final state, and two runs of one seed must print the same one. `seconds`
## is game seconds. `realtime` runs it at ordinary speed to watch.

const DAY_LENGTH: float = 60.0
## Game seconds: about forty short days.
const DEFAULT_SECONDS: float = 1800.0
## A state that is briefly inconsistent while a frame finishes is not a bug;
## one that persists for this many checks in a row is.
const PERSIST_CHECKS: int = 3
const CHECK_INTERVAL: float = 1.0
## Carrying goods with nowhere to go, or standing somewhere nobody can reach,
## for this long is stuck rather than busy.
const STUCK_SECONDS: float = 25.0

var world: TavernWorld
var scenario: Node
var rng := RandomNumberGenerator.new()
var seed_value: int = 1
var seconds: float = DEFAULT_SECONDS
## `level=<id>` starts from a designed level instead of the sandbox starter.
var level_id: StringName = &""

var _holes: Dictionary = {}       ## message -> {count, first_at, context}
var _recent: PackedStringArray = PackedStringArray()
var _counts: Dictionary = {}      ## action -> times
var _persist: Dictionary = {}     ## invariant key -> consecutive failures
var _stuck_for: Dictionary = {}   ## worker id -> seconds stuck
var _state_since: Dictionary = {}  ## patron id -> [state, seconds in it]
var _job_seen: Dictionary = {}     ## job id -> first seen at
var _idle_for: Dictionary = {}     ## worker id -> seconds idle
var _elapsed: float = 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			seed_value = int(arg.substr(5))
		elif arg.begins_with("seconds="):
			seconds = float(arg.substr(8))
		elif arg.begins_with("level="):
			level_id = StringName(arg.substr(6))
	rng.seed = seed_value
	SimWait.seed_run(seed_value)
	if not GameState.begin_test_session():
		push_error("Chaos test could not isolate its save slot")
		get_tree().quit(2)
		return

	print("=== CHAOS TEST: seed %d, %.0fs%s ===" % [seed_value, seconds,
		"" if level_id == &"" else ", level " + String(level_id)])
	if level_id != &"":
		GameState.pending_level = level_id
	GameState.start_new_run("The Chaos Arms", 493774, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	world.clock.day_length = DAY_LENGTH
	var mode: String = SimWait.configure(world)
	SimWait.hold(world)
	# A player reads the reckoning for a while before carrying on, and the game
	# sits paused all that time -- so dismiss it after a random pause, not at
	# once, and let the checks run against a paused tavern too. Counted in
	# frames: game time does not pass while the summary holds it.
	world.clock.day_ended.connect(func(_day: int) -> void:
		_check_books("close of day %d" % _day)
		for i in range(rng.randi_range(0, 40)):
			await get_tree().process_frame
		if is_instance_valid(world) and world.simulation_paused:
			world.hud._day_summary.hide()
			world._begin_next_day()
	, CONNECT_DEFERRED)
	await get_tree().process_frame

	scenario = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	add_child(scenario)
	if level_id == &"":
		scenario.build_starter_tavern()
	else:
		world.hud._briefing_panel.visible = false
	world.order_supplies()
	SimWait.release(world)

	print("  Game time: %s" % mode)
	var next_action: float = 2.0
	var next_check: float = CHECK_INTERVAL
	var began: float = world.sim.sim_time
	while _elapsed < seconds:
		await get_tree().process_frame
		var now: float = world.sim.sim_time - began
		var delta: float = now - _elapsed
		_elapsed = now
		next_action -= delta
		next_check -= delta
		if next_action <= 0.0:
			next_action = rng.randf_range(1.5, 4.5)
			await _act()
		if next_check <= 0.0:
			next_check = CHECK_INTERVAL
			_check_invariants(CHECK_INTERVAL)

	_check_books("the end")
	_report()


# --- actions ------------------------------------------------------------------

const ACTIONS: Dictionary = {
	"place": 5.0, "demolish": 2.0, "order": 2.0, "hire": 0.4, "priority": 2.0,
	"bill": 1.0, "filter": 1.0, "save_load": 0.5, "buy_land": 0.3, "inspect": 1.5,
	"hover": 2.0, "follow": 0.5, "dismiss": 0.4, "hands_on": 0.8, "drag_floor": 0.6,
	"panels": 1.0, "escape": 0.6, "camera": 0.6,
}


func _act() -> void:
	var total: float = 0.0
	for key in ACTIONS:
		total += ACTIONS[key]
	var roll: float = rng.randf() * total
	var chosen: String = "hover"
	for key in ACTIONS:
		roll -= ACTIONS[key]
		if roll <= 0.0:
			chosen = key
			break
	_counts[chosen] = int(_counts.get(chosen, 0)) + 1
	match chosen:
		"place": _place_random()
		"demolish": _demolish_random()
		"order": _log("order supplies -> %s" % world.order_supplies())
		"hire":
			if world.workers.size() < 9:
				var roles: Array[StaffRole] = StaffRole.hireable_roles()
				var role: StaffRole = roles[rng.randi() % roles.size()]
				var refusal: String = world.hire(role.id)
				_log("hire %s -> %s, now %d staff" % [role.id, refusal if refusal != "" else "ok", world.workers.size()])
		"priority": _toggle_priority()
		"bill": _tweak_bill()
		"filter": _toggle_filter()
		"save_load": await _save_and_reload()
		"buy_land": _buy_land()
		"inspect": _inspect_random()
		"hover": _hover_random()
		"dismiss":
			if not world.workers.is_empty():
				var leaving: Worker = world.workers[rng.randi() % world.workers.size()]
				var name: String = leaving.pawn.pawn_name
				var refusal: String = world.dismiss_worker(leaving)
				_log("let %s go -> %s" % [name, "done" if refusal.is_empty() else refusal])
		"hands_on": _hands_on_random()
		"drag_floor": _drag_floor_random()
		"panels":
			var which: int = rng.randi() % 4
			match which:
				0: world.hud._production_panel.toggle()
				1: world.hud._priority_panel.toggle()
				2: world.hud._land_panel.visible = not world.hud._land_panel.visible
				3: world.toggle_room_overlay()
			_log("toggle panel %d" % which)
		"escape":
			# The first half of what Escape does in play; leaving the game is the
			# other half, and would end the run.
			if world.build.mode != BuildController.Mode.OFF:
				world.build.mode = BuildController.Mode.OFF
			var closed: bool = world.hud.close_top_panel()
			_log("escape -> closed %s" % closed)
			# Nothing to close: Esc opens the pause menu, which holds time. Open
			# and resume it, so random play covers the hold and its release.
			if not closed:
				world.hud.open_pause_menu()
				await get_tree().process_frame
				world.hud.pause_menu.close()
		"camera":
			if rng.randf() < 0.3:
				world.input.toggle_camera_mode()
			else:
				world.rig.rotate_step([-1, 1][rng.randi() % 2])
			world.rig.zoom_by(rng.randf_range(-3.0, 3.0))
			_log("camera -> mode %d" % world.rig.mode)
		"follow":
			world.input.toggle_follow()
			_log("toggle follow -> %s" % (world.rig.follow.name if world.rig.follow != null else "off"))


func _log(text: String) -> void:
	var line: String = "[%.1fs day %d] %s" % [_elapsed, world.clock.day, text]
	_recent.append(line)
	if _recent.size() > 8:
		_recent.remove_at(0)


func _random_tile() -> Vector2i:
	return world.plot.position + Vector2i(rng.randi_range(1, world.plot.size.x - 2), rng.randi_range(1, world.plot.size.y - 2))


func _place_random() -> void:
	var ids: Array = ["chair", "chair", "table", "table", "storage_shelf", "barrel", "wood_floor", "wood_floor",
		"timber_wall", "oven", "prep_table", "brewing_vat", "sink", "well", "serving_counter", "host_stand"]
	var id: String = ids[rng.randi() % ids.size()]
	var def: BuildingDef = BuildingCatalog.get_def(StringName(id))
	var tile: Vector2i = _random_tile()
	world.build.mode = BuildController.Mode.PLACE
	world.build.select(def)
	if rng.randf() < 0.3:
		world.build.rotate_selection()
	world.build.update_hover(tile, true)
	var before: int = world.build.grid.live_count()
	world.commit_build_action()
	world.build.mode = BuildController.Mode.OFF
	_log("place %s at %s -> %s" % [id, tile, "placed" if world.build.grid.live_count() > before else "refused"])


func _demolish_random() -> void:
	var live: Array[int] = []
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry == null:
			continue
		# Mostly leave the way in alone, or every run ends as a sealed box and
		# measures nothing after the first hour.
		if entry["def"].id == &"door" and rng.randf() < 0.9:
			continue
		live.append(i)
	if live.is_empty():
		return
	var index: int = live[rng.randi() % live.size()]
	var entry: Dictionary = world.build.grid.placements[index]
	var tile: Vector2i = entry["tiles"][0]
	var sitting: String = ""
	for seat in world.customers.seating.seats:
		if entry["tiles"].has(seat["chair"]) or entry["tiles"].has(seat["table"]):
			if seat["taken_by"] != null:
				sitting = " (somebody sitting there)"
	# Demolish takes whatever stands on top: pointing at a floor under a chair
	# removes the chair. Log what actually went, not what was aimed at.
	var target: int = world.build.grid.placement_at(tile)
	var went: StringName = world.build.grid.placements[target]["def"].id if target >= 0 else &"nothing"
	world.build.mode = BuildController.Mode.DEMOLISH
	world.build.update_hover(tile, true)
	var removed: bool = world.build.try_demolish()
	world.build.mode = BuildController.Mode.OFF
	_log("demolish %s at %s%s -> %s" % [went, tile, sitting, removed])


## Do a batch by hand at a random bench that has its ingredients, the way the
## inspector's "Do it yourself" button does.
func _hands_on_random() -> void:
	var stations: Array = world.generator.built_stations()
	if stations.is_empty():
		return
	var station: Dictionary = stations[rng.randi() % stations.size()]
	for recipe in station["recipes"]:
		if world.generator.can_perform(station["index"], recipe):
			var done: bool = world.generator.perform_by_hand(station["index"], recipe, rng.randf())
			_log("by hand: %s at #%d -> %s" % [recipe.id, station["index"], done])
			return


## Drag out an area of floor, as the build bar does.
func _drag_floor_random() -> void:
	var from: Vector2i = _random_tile()
	var to: Vector2i = from + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
	world.build.mode = BuildController.Mode.PLACE
	world.build.select(BuildingCatalog.get_def([&"wood_floor", &"stone_floor"][rng.randi() % 2]))
	var before: int = world.build.grid.live_count()
	if world.build.begin_drag(from):
		world.build.update_hover(to, true)
		world.commit_area_build()
	world.build.mode = BuildController.Mode.OFF
	_log("drag floor %s..%s -> %d laid" % [from, to, world.build.grid.live_count() - before])


func _toggle_priority() -> void:
	if world.workers.is_empty():
		return
	var worker: Worker = world.workers[rng.randi() % world.workers.size()]
	var kind: int = rng.randi() % WorkType.COUNT
	var value: int = [WorkType.PRIORITY_OFF, 1, 2, 3, 4][rng.randi() % 5]
	worker.priorities[kind] = value
	_log("%s: %s -> %d" % [worker.pawn.pawn_name, WorkType.display_name(kind), value])


func _tweak_bill() -> void:
	var recipes: Array = RecipeCatalog.all()
	var recipe: Recipe = recipes[rng.randi() % recipes.size()]
	if not world.bills.has_bill(recipe.id):
		return
	var bill: Dictionary = world.bills.get_bill(recipe.id)
	match rng.randi() % 3:
		0:
			world.bills.set_target(recipe.id, int(bill["target"]) + [-2, 2][rng.randi() % 2])
		1:
			world.bills.set_resume_below(recipe.id, int(bill["resume_below"]) + [-2, 2][rng.randi() % 2])
		2:
			# Switching a recipe off is rare and then put back, or the run turns
			# into a study of a tavern that has stopped cooking.
			world.bills.set_enabled(recipe.id, not bool(bill["enabled"]) or rng.randf() < 0.3)
	_log("bill %s -> %s" % [recipe.id, var_to_str(world.bills.get_bill(recipe.id)).replace("\n", " ")])


func _toggle_filter() -> void:
	var shelves: Array[int] = []
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["def"].is_storage:
			shelves.append(i)
	if shelves.is_empty():
		return
	var index: int = shelves[rng.randi() % shelves.size()]
	if rng.randf() < 0.35:
		world.build.grid.set_filter(index, [])
		_log("clear filter on #%d" % index)
		return
	var items: Array = ItemCatalog.all()
	var item: ItemDef = items[rng.randi() % items.size()]
	world.build.grid.toggle_filter(index, item.id)
	_log("toggle filter %s on #%d" % [item.id, index])


func _save_and_reload() -> void:
	var goods: Dictionary = _goods_everywhere(world)
	var gold: int = GameState.gold
	var built: int = world.build.grid.live_count()
	if not world.save_now():
		_hole("the tavern could not be saved")
		return
	var raw: Dictionary = SaveGame.read(GameState.active_slot)
	if raw.is_empty():
		_hole("a save could not be read back")
		return
	# Through the player's own path: ask to continue, and let the new world load
	# itself. Loading by hand on top of that loaded it twice.
	GameState.request_continue(GameState.active_slot)
	var copy: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(copy)
	# Nothing may run in the copy: it shares GameState with the real world.
	copy.process_mode = Node.PROCESS_MODE_DISABLED
	var restored: Dictionary = _goods_everywhere(copy)
	if GameState.gold != gold:
		_hole("the purse changed across a reload")
		GameState.gold = gold
	if copy.build.grid.live_count() != built:
		_hole("buildings changed across a reload (%d -> %d)" % [built, copy.build.grid.live_count()])
	for id in goods:
		if int(goods[id]) != int(restored.get(id, 0)):
			_hole("%s changed across a reload (%d -> %d)" % [id, goods[id], restored.get(id, 0)])
	_log("save and reload: %d buildings, %dg" % [built, gold])
	copy.queue_free()
	await get_tree().process_frame


## Every good in a world: on the ground and in anyone's hands.
func _goods_everywhere(w: TavernWorld) -> Dictionary:
	var out: Dictionary = {}
	for tile in w.items.all_tiles():
		var def: ItemDef = w.items.def_at(tile)
		out[def.id] = int(out.get(def.id, 0)) + w.items.count_at(tile)
	for worker in w.workers:
		if worker.carried_def() != null:
			out[worker.carried_def().id] = int(out.get(worker.carried_def().id, 0)) + worker.carried_count()
	return out


func _buy_land() -> void:
	var sides: Array = [TavernWorld.SIDE_EAST, TavernWorld.SIDE_WEST, TavernWorld.SIDE_NORTH]
	var side: int = sides[rng.randi() % sides.size()]
	if not world.parcel_problem(side).is_empty() or GameState.gold < world.parcel_price(side) + 200:
		return
	_log("buy land %d -> %s" % [side, world.buy_land(side)])


func _random_subject() -> Dictionary:
	match rng.randi() % 4:
		0:
			if not world.pawns.is_empty():
				return {"kind": WorldStats.Kind.PAWN, "pawn": world.pawns[rng.randi() % world.pawns.size()]}
		1:
			var guests: Array = world.customers.customers
			if not guests.is_empty():
				var brain = guests[rng.randi() % guests.size()]
				if is_instance_valid(brain) and is_instance_valid(brain.pawn):
					return {"kind": WorldStats.Kind.PAWN, "pawn": brain.pawn}
		2:
			var tiles: Array = world.items.all_tiles()
			if not tiles.is_empty():
				return {"kind": WorldStats.Kind.ITEMS, "tile": tiles[rng.randi() % tiles.size()]}
	var tile: Vector2i = _random_tile()
	var index: int = world.build.grid.placement_at(tile)
	if index >= 0:
		return {"kind": WorldStats.Kind.BUILDING, "index": index, "tile": tile}
	return {"kind": WorldStats.Kind.GROUND, "tile": tile}


func _inspect_random() -> void:
	var subject: Dictionary = _random_subject()
	world.hud.inspector.show_subject(subject)
	_log("inspect %s" % _describe(subject))


func _hover_random() -> void:
	var subject: Dictionary = _random_subject()
	var rows: Array = WorldStats.rows_for(world, subject)
	if rows.is_empty() and int(subject["kind"]) != WorldStats.Kind.NONE:
		_hole("nothing to say about a %s" % _describe(subject))
	for id in [&"bread", &"beer"]:
		WorldStats.stock_breakdown(world, id)
	WorldStats.purse_breakdown(world)
	WorldStats.people_breakdown(world)
	Trouble.diagnose(world)
	for recipe in RecipeCatalog.all():
		WorldStats.recipe_activity(world, recipe)


func _describe(subject: Dictionary) -> String:
	match int(subject.get("kind", -1)):
		WorldStats.Kind.PAWN:
			return "person %s" % (subject["pawn"].pawn_name if is_instance_valid(subject["pawn"]) else "(gone)")
		WorldStats.Kind.BUILDING:
			var entry = world.build.grid.placements[subject["index"]]
			return "building %s" % (entry["def"].id if entry != null else "(gone)")
		WorldStats.Kind.ITEMS:
			return "stack at %s" % subject["tile"]
		WorldStats.Kind.GROUND:
			return "ground at %s" % subject["tile"]
	return "nothing"


# --- invariants -----------------------------------------------------------------

func _check_invariants(dt: float) -> void:
	# Paused at the reckoning: nothing moves, and no card may be up over it.
	# Counted only across one hold: evaluated only while paused, the tally used
	# to carry from one day's close to the next and add up to a hole.
	if world.simulation_paused:
		_persistent(not world.hud.hover.visible, "paused-card", "a hover card is up while the day summary holds the game")
	else:
		_persist.erase("paused-card")
		return

	# Every number over a stack names a stack that is there, with that count.
	var labels: StackLabels = world.get_node_or_null("StackLabels")
	if labels != null and labels.visible:
		for tile in labels._labels:
			var text: String = labels._labels[tile].text
			# Three checks in a row is three seconds: well past the half-second
			# resync, so only a label that has really gone stale fails.
			_persistent(world.items.has_stack(tile) and str(world.items.count_at(tile)) == text,
				"label:%s" % tile, "a stack number at %s says %s over %d" % [tile, text, world.items.count_at(tile)])

	# The inspector never describes a building that has been knocked down.
	var shown: Dictionary = world.hud.inspector.subject()
	if int(shown.get("kind", -1)) == WorldStats.Kind.BUILDING:
		var index: int = shown["index"]
		_persistent(index < world.build.grid.placements.size() and world.build.grid.placements[index] != null,
			"inspect-gone", "the inspector is showing a building that no longer exists")
	var board: JobBoard = world.board

	# Claims point both ways: a job's claimant is working on it, and a worker's
	# job is on the board.
	var keys: Dictionary = {}
	for job in board.jobs:
		if not job.key.is_empty():
			_persistent(not keys.has(job.key), "dup:" + job.key, "two jobs share the key %s" % job.key)
			keys[job.key] = true
		# By state and validity, not `claimant != null`: a freed claimant compares
		# equal to null, which is exactly how the first orphan hid from this check.
		if job.state == Job.State.CLAIMED or job.state == Job.State.ACTIVE:
			var ok: bool = is_instance_valid(job.claimant) and job.claimant.get("current") == job
			_persistent(ok, "orphan:%d" % job.get_instance_id(), "a job is claimed by somebody not working on it (%s)" % job.label)
	for worker in world.workers:
		if worker.current != null:
			_persistent(board.jobs.has(worker.current) or worker.current.state == Job.State.DONE,
				"forgotten:%d" % worker.get_instance_id(),
				"%s is working on a job the board no longer has (%s)" % [worker.pawn.pawn_name, worker.current.label])
		_check_stuck(worker, dt)

	# Seats and sitters agree: whoever holds a chair thinks it is theirs, and
	# whoever thinks they have a chair holds it.
	var seating: Seating = world.customers.seating
	for i in range(seating.seats.size()):
		var sitter = seating.seats[i]["taken_by"]
		if sitter == null:
			continue
		var chair: Vector2i = seating.chair_of(i)
		var present: bool = is_instance_valid(sitter) and world.customers.customers.has(sitter)
		_persistent(present, "ghost-seat:%s" % chair, "a seat is held by a patron who has gone")
		if present:
			_persistent(sitter.seat == chair, "seat-mismatch:%s" % chair,
				"%s holds the chair at %s but thinks theirs is at %s" % [sitter.pawn.pawn_name, chair, sitter.seat])
	for brain in world.customers.customers:
		if is_instance_valid(brain) and brain.seat != Seating.NO_SEAT:
			_persistent(seating.holder_of(brain.seat) == brain, "lost-seat:%d" % brain.get_instance_id(),
				"%s thinks they have the chair at %s, which is not held for them" % [brain.pawn.pawn_name, brain.seat])

	# Patience ends every stage of a visit except eating. A patron in any other
	# state for minutes is walking into a wall or waiting on nothing.
	var alive: Dictionary = {}
	for brain in world.customers.customers:
		if not is_instance_valid(brain):
			continue
		var pid: int = brain.get_instance_id()
		alive[pid] = true
		var was: Array = _state_since.get(pid, [brain.state, 0.0])
		if int(was[0]) != brain.state:
			was = [brain.state, 0.0]
		was[1] = float(was[1]) + dt
		_state_since[pid] = was
		if float(was[1]) >= 150.0 and float(was[1]) - dt < 150.0 and brain.state != CustomerBrain.State.EATING:
			_hole("%s has been %s for over two minutes" % [brain.pawn.pawn_name, brain.status_text()])
	for pid in _state_since.keys():
		if not alive.has(pid):
			_state_since.erase(pid)

	# Idle hands beside work nobody takes: an open job two minutes old while a
	# worker who does that kind of work stands about.
	var now_jobs: Dictionary = {}
	for job in board.jobs:
		var jid: int = job.get_instance_id()
		now_jobs[jid] = true
		if not _job_seen.has(jid):
			_job_seen[jid] = _elapsed
	for jid in _job_seen.keys():
		if not now_jobs.has(jid):
			_job_seen.erase(jid)
	for worker in world.workers:
		var wid: int = worker.get_instance_id()
		_idle_for[wid] = float(_idle_for.get(wid, 0.0)) + dt if worker.current == null and worker.state == Worker.State.SEEKING else 0.0
		if float(_idle_for[wid]) < 30.0:
			continue
		for job in board.jobs:
			if job.claimant != null or _elapsed - float(_job_seen.get(job.get_instance_id(), _elapsed)) < 120.0:
				continue
			if int(worker.priorities.get(job.kind, WorkType.PRIORITY_OFF)) == WorkType.PRIORITY_OFF:
				continue
			var approach: Vector2i = job.pickup_tile if job.needs_pickup() else job.target
			var stand: Vector2i = world.nav.adjacent_walkable(approach, worker.pawn.tile)
			_persistent(false, "idle:%d:%s" % [wid, job.key],
				"%s stands idle beside an untaken %s job (%s at %s) two minutes old: %s" % [
					worker.pawn.pawn_name, WorkType.display_name(job.kind).to_lower(), job.label, approach,
					"nowhere they can stand beside it" if stand == Vector2i(-1, -1) else (
						"refused by %d, blocked: '%s', valid: %s" % [job.failed_for.size(), job.blocked_reason, job.is_valid()])]
				+ " | best offer now: %s" % _best_offer(worker))
			break

	# Claims on goods never exceed the goods.
	var claimed: Dictionary = {}
	for token in world.items._reservations:
		for tile in world.items._reservations[token]:
			claimed[tile] = int(claimed.get(tile, 0)) + int(world.items._reservations[token][tile])
	for tile in claimed:
		_persistent(int(claimed[tile]) <= world.items.count_at(tile), "overclaim:%s" % tile,
			"%d claimed on %s, which holds %d" % [claimed[tile], tile, world.items.count_at(tile)])

	# The selection ring marks what the inspector shows, and nothing when closed.
	var inspected: Dictionary = world.hud.inspector.subject()
	var ringed: bool = world.input.selection_marker.visible
	_persistent(inspected.is_empty() != ringed, "ring",
		"the selection ring is %s but the inspector is %s" % [
			"up" if ringed else "down", "closed" if inspected.is_empty() else "showing " + _describe(inspected)])


## What the board would hand this worker right now, and whether they could act on it.
func _best_offer(worker: Worker) -> String:
	var best: Job = world.board.best_for(worker, worker.priorities, worker.pawn.tile)
	if best == null:
		return "nothing (seek timer %.2f, state %d)" % [worker._seek_timer, worker.state]
	var approach: Vector2i = best.pickup_tile if best.needs_pickup() else best.target
	return "%s at %s, stand %s, pawn at %s walkable %s, process %s" % [
		best.label, approach, world.nav.adjacent_walkable(approach, worker.pawn.tile), worker.pawn.tile,
		world.nav.is_walkable(worker.pawn.tile), worker.is_processing()]


func _check_stuck(worker: Worker, dt: float) -> void:
	var id: int = worker.get_instance_id()
	var tile: Vector2i = worker.pawn.tile
	var reach: Dictionary = world.generator._reach
	var stuck: bool = worker.state == Worker.State.HOLDING or (worker.carried_count() > 0 and worker.current == null)
	# Only walkable ground counts: a pawn standing on a piece just built under
	# it is allowed to walk out, and pathing already handles that.
	var off_reach: bool = not reach.is_empty() and world.nav.is_walkable(tile) and not reach.has(tile)
	if not (stuck or off_reach):
		_stuck_for[id] = 0.0
		return
	var before: float = float(_stuck_for.get(id, 0.0))
	_stuck_for[id] = before + dt
	# Reported once, on the check that crosses the line.
	if before < STUCK_SECONDS and before + dt >= STUCK_SECONDS:
		_hole("%s has been %s for %ds" % [worker.pawn.pawn_name,
			"holding goods with nowhere to put them" if stuck else "standing where nobody can reach",
			int(STUCK_SECONDS)])


func _check_books(when: String) -> void:
	if not scenario.reconcile(false):
		_hole("the books do not balance at %s" % when)


## Fail only if the same thing is wrong several checks running.
func _persistent(ok: bool, key: String, message: String) -> void:
	if ok:
		_persist.erase(key)
		return
	_persist[key] = int(_persist.get(key, 0)) + 1
	if int(_persist[key]) == PERSIST_CHECKS:
		_hole(message)


func _hole(message: String) -> void:
	if not _holes.has(message):
		_holes[message] = {"count": 0, "at": _elapsed, "context": _recent.duplicate()}
		print("  HOLE at %.1fs: %s" % [_elapsed, message])
	_holes[message]["count"] += 1


## The final state in one line, hashed. The same seed must always print the
## same fingerprint; if two runs differ, something reads the wall clock or an
## unseeded random number, and the run cannot be replayed.
func _fingerprint() -> String:
	var goods: Dictionary = _goods_everywhere(world)
	var ids: Array = goods.keys()
	ids.sort()
	var parts: PackedStringArray = PackedStringArray()
	for id in ids:
		parts.append("%s=%d" % [id, goods[id]])
	var served: int = world.customers.served_count
	for entry in world.ledger.history:
		served += int(entry.get("served", 0))
	var state: String = "day %d gold %d built %d staff %d served %d | %s" % [
		world.clock.day, GameState.gold, world.build.grid.live_count(), world.workers.size(),
		served, " ".join(parts)]
	return "%08x (%s)" % [state.hash(), state]


func _report() -> void:
	print("--- chaos test (seed %d) ---" % seed_value)
	var acts: PackedStringArray = PackedStringArray()
	for key in _counts:
		acts.append("%s %d" % [key, _counts[key]])
	TestOutput.detail("  Actions: %s" % ", ".join(acts))
	print("  Ended on day %d with %dg, %d buildings, %d staff" % [
		world.clock.day, GameState.gold, world.build.grid.live_count(), world.workers.size()])
	print("  FINGERPRINT %s" % _fingerprint())
	if _holes.is_empty():
		print("CHAOS TEST PASS: nothing broke")
	else:
		print("CHAOS TEST: %d hole(s)" % _holes.size())
		for message in _holes:
			var h: Dictionary = _holes[message]
			print("  HOLE: %s (x%d, first at %.1fs)" % [message, h["count"], h["at"]])
			for line in h["context"]:
				print("      %s" % line)
	GameState.delete_slot(GameState.MAX_SLOTS - 1)
	GameState.active_slot = -1
	get_tree().quit(1 if _holes.size() > 0 else 0)
