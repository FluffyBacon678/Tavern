extends Node

var world: TavernWorld
var _auto_days: int = 0
var expected_days: int = 0
var expected_built: int = 0


## Place a small starter tavern programmatically.
##
## Doubles as the only automated test the build system has: it exercises every
## shape in the catalog, both layers, rotation, and the footprint maths, and
## reports anything the grid refused. A layout that silently loses pieces shows
## up here as a non-zero refusal count.
func build_demo_tavern(as_blueprints: bool = false) -> Dictionary:
	if world.build == null:
		return {}
	var o: Vector2i = world.plot.position + Vector2i(6, 5)
	var w: int = 14
	var h: int = 10
	# Counters live in an Array because GDScript lambdas capture local variables
	# *by value* -- incrementing a plain int inside the closure updates the
	# closure's own copy and the outer one stays at zero, which is exactly the
	# bug this line replaces. Arrays and Dictionaries are references, so they
	# mutate as expected.
	var tally: PackedInt32Array = PackedInt32Array([0, 0])  # placed, refused

	var attempt := func(id: String, tile: Vector2i, rot: int) -> void:
		var def: BuildingDef = BuildingCatalog.get_def(StringName(id))
		if def == null or world.build.place_programmatic(def, tile, rot, as_blueprints) < 0:
			tally[1] += 1
		else:
			tally[0] += 1

	# Floor first: objects sit on top, so order does not matter to the grid, but
	# it matches how a player would actually do it.
	for y in range(h):
		for x in range(w):
			attempt.call("wood_floor", o + Vector2i(x, y), 0)

	# Perimeter walls, with a doorway in the middle of the south side.
	var door_x: int = w / 2
	for x in range(w):
		attempt.call("timber_wall", o + Vector2i(x, 0), 0)
		if x == door_x:
			attempt.call("door", o + Vector2i(x, h - 1), 0)
		else:
			attempt.call("timber_wall", o + Vector2i(x, h - 1), 0)
	for y in range(1, h - 1):
		attempt.call("timber_wall", o + Vector2i(0, y), 0)
		attempt.call("timber_wall", o + Vector2i(w - 1, y), 0)

	# Dining room, left half: tables with a chair either side.
	for spot in [Vector2i(2, 2), Vector2i(2, 5), Vector2i(5, 7)]:
		attempt.call("table", o + spot, 0)
		attempt.call("chair", o + spot + Vector2i(-1, 0), 0)
		attempt.call("chair", o + spot + Vector2i(2, 0), 0)

	# Serving counter divides dining from kitchen, with the host's stand by the
	# door so arrivals are met before they wander in.
	attempt.call("serving_counter", o + Vector2i(7, 4), 1)
	attempt.call("host_stand", o + Vector2i(door_x + 1, h - 2), 0)

	# Kitchen, right half.
	attempt.call("oven", o + Vector2i(9, 1), 0)
	attempt.call("prep_table", o + Vector2i(9, 3), 0)
	attempt.call("brewing_vat", o + Vector2i(9, 5), 0)
	attempt.call("sink", o + Vector2i(11, 1), 0)
	attempt.call("storage_shelf", o + Vector2i(11, 8), 0)
	attempt.call("barrel", o + Vector2i(9, 8), 0)
	attempt.call("barrel", o + Vector2i(10, 8), 0)

	# One rebuild per definition at the end, rather than per placement.
	for def in BuildingCatalog.all():
		world.build._rebuild_instances(def)
	world.hud.refresh_stats()

	print("Demo tavern: %d placed, %d refused, %d gold of value%s" % [
		tally[0], tally[1], world.build.grid.total_value(),
		" (%d build jobs queued)" % world.board.open_count() if as_blueprints else ""
	])
	return {"placed": tally[0], "refused": tally[1]}


## Move every pawn outside the demo tavern and order them to a tile deep inside
## its kitchen.
##
## This is the pathfinding test: the only route in is the single door gap in the
## south wall, so a pawn that arrives has demonstrably routed around the walls
## rather than walked through them. Reports how many found a route and how long
## the routes were -- a sudden drop in either is how a broken walkability rule
## will show up.
func run_path_test() -> Dictionary:
	if world.nav == null or world.pawns.is_empty():
		return {}

	# Matches the layout build_demo_tavern() uses.
	var o: Vector2i = world.plot.position + Vector2i(6, 5)
	var inside: Vector2i = o + Vector2i(11, 4)
	var outside: Vector2i = o + Vector2i(7, 12)

	for i in range(world.pawns.size()):
		var spot: Vector2i = outside + Vector2i(i - world.pawns.size() / 2, 0)
		if not world.nav.is_walkable(spot):
			spot = outside
		world.pawns[i].tile = spot
		world.pawns[i].position = world.pawns[i].world_position_of(spot)

	var routed: int = 0
	var total_length: int = 0
	for pawn in world.pawns:
		var route: Array[Vector2i] = world.nav.find_path(pawn.tile, inside)
		if route.is_empty():
			continue
		routed += 1
		total_length += route.size()
		pawn.goto(inside)

	var average: int = int(float(total_length) / float(maxi(routed, 1)))
	print("Path test: %d/%d pawns routed into the kitchen, average %d tiles" % [
		routed, world.pawns.size(), average
	])
	return {"routed": routed, "total": world.pawns.size(), "average": average}


## Hook for the screenshot harness, so camera comparisons can be captured
## reproducibly instead of by hand. Not used by the game itself.
func screenshot_setup(opts: Dictionary) -> void:
	if not OS.is_debug_build():
		return
	if world.rig == null:
		return
	if opts.has("camera"):
		world.rig.mode = CameraRig.Mode.FREE if String(opts["camera"]) == "free" else CameraRig.Mode.LOCKED
	if opts.has("distance"):
		world.rig._distance_target = float(opts["distance"])
		world.rig._distance = world.rig._distance_target
	if opts.has("pitch"):
		world.rig._pitch_target = float(opts["pitch"])
		world.rig._pitch = world.rig._pitch_target
	if opts.has("yaw"):
		world.rig._yaw_target = float(opts["yaw"])
		world.rig._yaw = world.rig._yaw_target
	if opts.has("demo"):
		match String(opts["demo"]):
			"tavern":
				build_demo_tavern(false)
			"blueprint":
				build_demo_tavern(true)
				expected_built = 202
			"starter":
				build_starter_tavern()
	if opts.has("buyland"):
		# Fund it first: the purchase goes through the purse like the player's
		# would, and a capture should not be refused for being poor.
		for i in range(int(opts["buyland"])):
			world.ledger.earn(Ledger.Line.TAKINGS, world.parcel_price(TavernWorld.SIDE_EAST))
			if not world.buy_land(TavernWorld.SIDE_EAST):
				push_warning("Scenario: could not buy parcel %d." % i)
				break
		print("Land: plot is now %d x %d, %d gold left" % [
			world.plot.size.x, world.plot.size.y, GameState.gold])
	if opts.has("well") and String(opts["well"]) == "on":
		build_back_well()
	if opts.has("level"):
		# Open a designed level from the harness, so a capture or a soak run can
		# start from the same situation a player would.
		GameState.pending_level = StringName(opts["level"])
		world._open_level()
	# `pause=on`, or `pause=settings` with `tab=N`: the pause menu, for captures.
	if opts.has("pause") and world.hud != null:
		world.hud.open_pause_menu()
		if String(opts["pause"]) == "settings":
			var screen := SettingsScreen.open(world.hud.pause_menu)
			screen._show_tab(int(opts.get("tab", "0")))
	# `tutstep=N`: the tutorial at its Nth step (1-based), for captures.
	if opts.has("tutstep") and world.hud != null and world.hud.tutorial != null:
		world.hud.tutorial.index = clampi(int(opts["tutstep"]) - 1, 0, world.hud.tutorial.steps.size() - 1)
		world.hud.tutorial._begin()
	# `hud=off`: the world alone, for the title screen's backdrop.
	if opts.has("hud") and String(opts["hud"]) == "off" and world.hud != null:
		world.hud._hud.visible = false
	if opts.has("rooms") and String(opts["rooms"]) == "on":
		world.toggle_room_overlay()
	if opts.has("panel"):
		_open_panel(String(opts["panel"]))
	# `verdict=won|lost` poses a level's ending on the day summary, staged from a
	# made-up ledger, since reaching one for real takes six game days.
	if opts.has("verdict") and world.level != null:
		_pose_verdict(String(opts["verdict"]) == "won")
	# `lineup=on` stands a row of every look in front of the camera, for judging
	# the outfits side by side rather than hunting for them in a crowd.
	if opts.has("lineup") and String(opts["lineup"]) == "on":
		_pose_lineup()
	# `speed=0..3` sets game speed; 0 captures the paused state.
	if opts.has("speed"):
		world.sim.speed = int(opts["speed"])
	# `livehover=off` stops the real pointer raising cards over the capture.
	if opts.has("livehover") and String(opts["livehover"]) == "off":
		world.input.hover_enabled = false
	# `poseat=<seconds>` holds the inspector and hover poses until just before a
	# capture, when there are patrons and work in progress to show.
	if opts.has("poseat"):
		_pose_later(float(opts["poseat"]), String(opts.get("inspect", "")), String(opts.get("hover", "")))
	else:
		if opts.has("inspect"):
			_inspect_something(String(opts["inspect"]))
		if opts.has("hover"):
			_hover_something(String(opts["hover"]))
	if opts.has("pathtest") and String(opts["pathtest"]) == "on":
		run_path_test()
	if opts.has("economy") and String(opts["economy"]) == "on":
		world.order_supplies()
	if opts.has("daylength") and world.clock != null:
		world.clock.day_length = float(opts["daylength"])
	if opts.has("autodays"):
		# Dismiss the reckoning automatically, so a headless run can measure
		# several days in a row instead of stopping at the first one.
		_auto_days = int(opts["autodays"])
		expected_days = _auto_days + 1
		world.clock.day_ended.connect(_advance_test_day, CONNECT_DEFERRED)
	if opts.has("restock") and String(opts["restock"]) == "on":
		# Stand-in for the player reordering each morning, so a multi-day run
		# measures the economy rather than measuring running out of flour.
		world.clock.day_started.connect(func(day: int) -> void:
			if day <= 1:
				return
			# Order the way a player would: when the larder is actually low, not
			# every morning regardless. A blind daily order buries the tavern in
			# stock it has nowhere to put, which measures the warehouse instead
			# of the business.
			for id in [&"flour", &"water", &"yeast", &"malt", &"hops"]:
				if world.items.total_of(id) <= 2:
					world.order_supplies()
					return
		)
	if opts.has("buildbar") and world.hud._build_bar != null:
		world.hud._build_bar.visible = String(opts["buildbar"]) == "on"
	if opts.has("report"):
		_report_after(float(opts["report"]))
	world.rig._apply_transform(true)


func _advance_test_day(_day: int) -> void:
	if _auto_days <= 0:
		return
	_auto_days -= 1
	world.hud._day_summary.hide()
	world._begin_next_day()


## Print a production reconciliation after a delay, so a headless run can be
## checked against what the recipes should have yielded.
func _report_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	reconcile()


## Check the goods and the gold add up. By default a failure ends the process,
## which is what a harness run wants; a suite with its own report passes false,
## or the failure would swallow the very report that explains it.
func reconcile(quit_on_failure: bool = true) -> bool:
	var lines: PackedStringArray = PackedStringArray()
	var passed: bool = true
	var built: int = 0
	for entry in world.build.grid.placements:
		if entry != null and entry["built"]:
			built += 1
	if expected_built > 0:
		passed = passed and built == expected_built
		lines.append("Construction: %d/%d built, %d open jobs, %d active jobs" % [
			built, expected_built, world.board.open_count(), world.board.active_count()])
	if expected_days > 0 and world.ledger.history.size() != expected_days:
		passed = false
		lines.append("Expected %d completed days, got %d" % [expected_days, world.ledger.history.size()])
	for def in ItemCatalog.all():
		var on_ground: int = world.items.total_of(def.id)
		var carried: int = 0
		for worker in world.workers:
			if worker.carried_def() == def:
				carried += worker.carried_count()
		var made: int = world.generator.produced.get(def.id, 0)
		# Dishes are not baked, they are left behind -- but they are still goods
		# that came into existence, so they belong on the same side of the books
		# as a loaf. Leave them out and washing up reads as leakage.
		if world.customers != null and def.category == ItemDef.Category.REFUSE:
			made += world.customers.dishes_left
		var received: int = world.delivered.get(def.id, 0)
		# Covers both destructions: recipe inputs, and refuse washed at a basin.
		var used: int = world.generator.consumed.get(def.id, 0)
		var eaten: int = world.customers.consumed.get(def.id, 0)
		var difference: int = received + made - used - eaten - on_ground - carried
		passed = passed and difference == 0
		lines.append("%s: delivered=%d made=%d used=%d eaten=%d ground=%d carried=%d difference=%d" % [
			def.id, received, made, used, eaten, on_ground, carried, difference])
	# A level opens with its own purse, not the sandbox's.
	var opening: int = world.level.starting_gold if world.level != null else GameState.STARTING_GOLD
	var expected_gold: int = opening + world.ledger.profit()
	for entry in world.ledger.history:
		expected_gold += entry["profit"]
	passed = passed and expected_gold == GameState.gold
	# Trade and board composition alongside the goods. A run can reconcile
	# perfectly and still be failing at the thing the player cares about, and
	# "0 served, 6 lost" needs the seating and job figures beside it to be
	# diagnosable at all.
	if world.customers != null:
		lines.append("Trade: %s" % world.customers.summary())
		# Patrons served is a treacherous headline on its own. A tavern with only
		# beer sells one item a head; one with bread as well sells two or three,
		# so identical production serves half as many people and looks like a
		# collapse. This is the ratio that tells the two apart.
		var eaten: int = 0
		for id in [&"bread", &"beer"]:
			eaten += int(world.customers.consumed.get(id, 0))
		var heads: int = world.customers.served_count
		for entry in world.ledger.history:
			heads += int(entry.get("served", 0))
		lines.append("Service: %d items to %d patrons (%.2f each)" % [
			eaten, heads, float(eaten) / float(maxi(heads, 1))])
		lines.append("Standing: %s" % world.customers.reputation.summary())
		lines.append("Dishes: %d left by customers, %d washed" % [
			world.customers.dishes_left,
			world.generator.consumed.get(&"dirty_dishes", 0),
		])
	# Who is doing what, at the moment of the report. A board full of serving
	# jobs and a room full of unserved patrons is a contradiction that only
	# these two lines can resolve.
	if world.customers != null:
		var who: PackedStringArray = PackedStringArray()
		for brain in world.customers.customers:
			if is_instance_valid(brain):
				who.append(brain.status_text())
		lines.append("Patrons: %s" % ("; ".join(who) if who.size() > 0 else "none"))
	var staff: PackedStringArray = PackedStringArray()
	for worker in world.workers:
		staff.append(worker.status_text())
	lines.append("Staff: %s" % " | ".join(staff))
	# What every bench is doing, or what it is waiting for. "Sixteen loaves and
	# eighty-eight beers" says bread is starved; only this says whether that is
	# the bill pausing it, a missing ingredient, or nobody free to cook.
	if world.generator != null and world.bills != null:
		var kitchen: PackedStringArray = PackedStringArray()
		for station in world.generator.built_stations():
			for recipe in station["recipes"]:
				var missing: PackedStringArray = PackedStringArray()
				for need in recipe.inputs:
					var have: int = world.generator.count_at_station(station, need["id"])
					if have < need["count"]:
						missing.append("%s %d/%d (%s)" % [
							need["id"], have, need["count"],
							world.generator.feed_problem(station, need["id"]),
						])
				var stock: int = 0
				if not recipe.outputs.is_empty():
					stock = world.items.total_of(recipe.outputs[0]["id"])
				kitchen.append("%s [%s]%s" % [
					recipe.display_name,
					world.bills.status_text(recipe.id, stock),
					"" if missing.is_empty() else " waiting on " + ", ".join(missing),
				])
		lines.append("Kitchen: %s" % " | ".join(kitchen))
	# Where the goods physically are. A kitchen that cannot be fed is usually a
	# kitchen with nowhere to put anything, and that is invisible in the item
	# totals -- "16 flour on the ground" reads the same whether it is filed on a
	# shelf or heaped in the doorway.
	var shelf_tiles: int = 0
	var shelf_free: int = 0
	for entry in world.build.grid.placements:
		if entry == null or not entry["built"] or not entry["def"].is_storage:
			continue
		for tile in entry["tiles"]:
			shelf_tiles += 1
			if not world.items.has_stack(tile):
				shelf_free += 1
	var loose: int = 0
	for tile in world.items.all_tiles():
		loose += 1
	lines.append("Storage: %d tiles, %d empty; %d stacks in the world" % [
		shelf_tiles, shelf_free, loose])
	if world.rooms != null:
		lines.append("Rooms: %s" % world.rooms.summary())
	# Work nobody will take is the most confusing state the game has: idle staff
	# and a board that is not empty. Name the jobs and say who has written them
	# off, because "2 open, 0 active" is not something you can act on.
	var stuck: PackedStringArray = PackedStringArray()
	for job in world.board.jobs:
		if job.claimant != null:
			continue
		stuck.append("%s [%s] refused by %d" % [job.label, job.key, job.failed_for.size()])
	if not stuck.is_empty():
		lines.append("Untaken: %s" % " | ".join(stuck))
	# Frame rate matters to throughput, not just to looks: a worker advances at
	# most one step of its state machine per frame, so a slow build starves the
	# kitchen in a way that looks exactly like a logic bug.
	lines.append("Engine: %d fps, %d frames drawn" % [
		Engine.get_frames_per_second(), Engine.get_frames_drawn()])
	var kinds: PackedStringArray = PackedStringArray()
	for kind in range(WorkType.COUNT):
		kinds.append("%s=%d" % [WorkType.display_name(kind), world.board.count_of_kind(kind)])
	lines.append("Board: %d open, %d active (%s)" % [
		world.board.open_count(), world.board.active_count(), " ".join(kinds)])
	# The report is for finding out why the books are wrong; brief runs print
	# it only when they are.
	if not passed or not TestOutput.brief:
		print("--- production report ---\n%s" % "\n".join(lines))
		print("RECONCILIATION %s: days=%d gold=%d expected=%d" % [
			"PASS" if passed else "FAIL", world.ledger.history.size(), GameState.gold, expected_gold])
	if not passed:
		push_error("Physical inventory or ledger does not reconcile")
		if quit_on_failure:
			get_tree().quit(1)
	return passed


## The tavern a *guided* player would actually build on day one.
##
## The 199-piece demo layout is 885g of buildings and proves the systems work;
## it says nothing about whether somebody following the on-screen objectives
## with a starting purse can get trading at all. This is that build and only
## that build: a floor, the two bread stations, a brewing vat, seven tiles of
## storage, a wash basin and three tables with chairs. It comes to about 410g,
## of which a third is flooring -- and with the 115g delivery on top, it is what
## the opening purse is sized against.
func build_starter_tavern() -> Dictionary:
	if world.build == null:
		return {}
	var o: Vector2i = world.plot.position + Vector2i(8, 7)
	var tally: PackedInt32Array = PackedInt32Array([0, 0])

	var attempt := func(id: String, tile: Vector2i, rot: int) -> void:
		var def: BuildingDef = BuildingCatalog.get_def(StringName(id))
		if def == null or world.build.place_programmatic(def, tile, rot, false) < 0:
			tally[1] += 1
		else:
			tally[0] += 1

	for y in range(6):
		for x in range(10):
			attempt.call("wood_floor", o + Vector2i(x, y), 0)

	# Dining on the left, three tables of two. Two tables was the earlier shape
	# and it measured badly: four seats meant a single unwashed table halved the
	# room, and days ended with more patrons turned away than served.
	for row in [0, 2, 4]:
		attempt.call("table", o + Vector2i(1, row), 0)
		attempt.call("chair", o + Vector2i(0, row), 0)
		attempt.call("chair", o + Vector2i(3, row), 0)

	# Middle column: the things that have to be near both halves.
	#
	# Seven storage tiles, not three. Three was measured and it is not enough
	# for nine kinds of goods: the shelves fill on the first delivery, every
	# later sack ends up heaped around the benches, and the kitchen eventually
	# cannot be given the one ingredient it is short of because there is nowhere
	# to put it. The report line reads "Storage: 3 tiles, 0 empty" and the
	# symptom is a tavern that stops cooking for no visible reason.
	attempt.call("sink", o + Vector2i(5, 0), 0)
	attempt.call("storage_shelf", o + Vector2i(5, 2), 0)
	attempt.call("storage_shelf", o + Vector2i(5, 4), 0)
	for row in [0, 2, 4]:
		attempt.call("barrel", o + Vector2i(9, row), 0)

	# Kitchen on the right, one clear aisle away from the storage.
	attempt.call("prep_table", o + Vector2i(7, 0), 0)
	attempt.call("oven", o + Vector2i(7, 2), 0)
	attempt.call("brewing_vat", o + Vector2i(7, 4), 0)

	for def in BuildingCatalog.all():
		world.build._rebuild_instances(def)

	# place_programmatic does not touch the purse -- the player-facing path
	# charges separately. A winnability test that built for free would flatter
	# the economy by exactly the cost of the tavern, so bill it here.
	var bill: int = world.build.grid.total_value()
	world.ledger.spend(Ledger.Line.CONSTRUCTION, bill)
	world.hud.refresh_stats()

	print("Starter tavern: %d placed, %d refused, %d gold of buildings, %d gold left" % [
		tally[0], tally[1], bill, GameState.gold
	])
	return {"placed": tally[0], "refused": tally[1], "cost": bill}


## Put a draw well against the back boundary, where the river is.
##
## Its own flag rather than part of a layout, so the effect of free water can be
## measured against the same tavern with and without one. A well is an upgrade
## the player chooses, not part of the opening build.
func build_back_well() -> Dictionary:
	var def: BuildingDef = BuildingCatalog.get_def(&"well")
	if def == null or world.build == null:
		return {}
	# Walk along the back row until the water rule and the grid both agree.
	for x in range(world.plot.position.x + 1, world.plot.end.x - 2):
		var tile := Vector2i(x, world.plot.position.y + 1)
		if world.build.place_programmatic(def, tile, 0, false) >= 0:
			world.build._rebuild_instances(def)
			world.ledger.spend(Ledger.Line.CONSTRUCTION, def.cost)
			print("Draw well: built at %s for %dg" % [tile, def.cost])
			return {"tile": tile}
	push_warning("Scenario: nowhere along the back boundary would take a well.")
	return {}


## Pose the inspector for a capture. The harness has no cursor, so selection --
## normally a click -- has to be driven directly.
##
## Written as plain branches rather than a match: an earlier match-based version
## resolved the inspector to null inside branches that also declared a loop
## variable, while the branch without one worked. Not worth diagnosing in a dev
## helper -- if/elif has no such subtlety.
func _pose_lineup() -> void:
	world.sim.speed = 0
	var holder := Node3D.new()
	holder.name = "Lineup"
	world.add_child(holder)
	var centre: Vector3 = Vector3(float(world.plot.get_center().x), 0.0, float(world.plot.get_center().y)) * TerrainMeshBuilder.TILE
	var rng := RandomNumberGenerator.new()
	# Patrons behind, three staff in the front row where the uniform shows.
	var seeds: Array = []
	for s in range(1, 33):
		seeds.append(s)
	seeds.append_array([101, 202, 303])
	for i in range(seeds.size()):
		rng.seed = seeds[i] * 7919 + 17
		var rig: PawnMesh.Rig = PawnMesh.build(rng, world._pawn_material, i < seeds.size() - 3)
		holder.add_child(rig.root)
		var row: int = i / 7
		var col: int = i % 7
		rig.root.position = centre + Vector3((float(col) - 3.0) * 1.05, world.terrain.plot_height, (float(row) - 2.5) * 1.9)
		# Face the default camera, which looks from the south-east.
		rig.root.rotation.y = PI * 0.25
	world.rig.focus_on(centre + Vector3(0.0, world.terrain.plot_height, 0.0))


func _pose_verdict(won: bool) -> void:
	var level: LevelDef = world.level
	var purses: Array = [210, 430, 610, 790, level.goal_gold + 112] if won else [190, 330, 420, 520, 600, level.goal_gold - 160]
	world.ledger.history.clear()
	for i in range(purses.size()):
		world.ledger.history.append({"day": i + 1, "served": 20, "lost": 1, "profit": 180, "purse": purses[i],
			"lines": {Ledger.Line.TAKINGS: 190, Ledger.Line.TIPS: 26, Ledger.Line.WAGES: 30, Ledger.Line.SUPPLIES: 6}})
	var entry: Dictionary = world.ledger.history.back()
	world.set_simulation_paused(true)
	world.hud._day_summary.show_day(entry, world.hud._tavern_name(), world.customers.reputation, [],
		level.verdict_for(world, int(entry["day"])))


func _pose_later(seconds: float, inspect: String, hover: String) -> void:
	await get_tree().create_timer(seconds).timeout
	if not inspect.is_empty():
		_inspect_something(inspect)
	if not hover.is_empty():
		_hover_something(hover)


## Pose the hover card over something, pinned where the pointer would be.
## The harness has no cursor, so the card is shown directly and held there.
func _hover_something(what: String) -> void:
	if world == null or world.hud == null or world.hud.hover == null:
		return
	var subject: Dictionary = _pick_subject(what)
	if subject.is_empty():
		push_warning("Scenario: nothing to hover for '%s'." % what)
		return
	var at := Vector3.ZERO
	if subject["kind"] == WorldStats.Kind.PAWN:
		at = subject["pawn"].global_position
	else:
		var t: Vector2i = subject["tile"]
		at = Vector3((t.x + 0.5) * TerrainMeshBuilder.TILE, world.terrain.plot_height, (t.y + 0.5) * TerrainMeshBuilder.TILE)
	world.hud.hover.show_subject(subject)
	world.hud.hover.pin_at(world.rig.camera.unproject_position(at))


## Something worth showing for each pose name, preferring the busiest example.
func _pick_subject(what: String) -> Dictionary:
	match what:
		"worker":
			for worker in world.workers:
				if worker.current != null:
					return {"kind": WorldStats.Kind.PAWN, "pawn": worker.pawn}
			if not world.pawns.is_empty():
				return {"kind": WorldStats.Kind.PAWN, "pawn": world.pawns[0]}
		"patron":
			var best: CustomerBrain = null
			for brain in world.customers.customers:
				if is_instance_valid(brain) and (best == null or not brain.order.is_empty()):
					best = brain
			if best != null:
				return {"kind": WorldStats.Kind.PAWN, "pawn": best.pawn}
		"items":
			for tile in world.items.all_tiles():
				if world.build.grid.placement_at(tile) < 0:
					return {"kind": WorldStats.Kind.ITEMS, "tile": tile}
		"ground":
			var t: Vector2i = world.plot.position + Vector2i(2, 2)
			return {"kind": WorldStats.Kind.GROUND, "tile": t}
		_:
			for i in range(world.build.grid.placements.size()):
				var entry = world.build.grid.placements[i]
				if entry == null or not entry["built"]:
					continue
				var def: BuildingDef = entry["def"]
				var matches: bool = def.id == StringName(what)
				if what == "storage":
					matches = def.is_storage
				if matches:
					return {"kind": WorldStats.Kind.BUILDING, "index": i, "tile": entry["tiles"][0]}
	return {}


func _inspect_something(what: String) -> void:
	if world == null or world.hud == null or world.hud.inspector == null:
		push_warning("Scenario: no inspector to pose.")
		return
	var picked: Dictionary = _pick_subject(what)
	if not picked.is_empty():
		world.hud.inspector.show_subject(picked)
		return

	if what == "worker":
		if not world.pawns.is_empty():
			world.hud.inspector.show_pawn(world.pawns[0])
		return

	if what == "patron":
		if world.customers != null and not world.customers.customers.is_empty():
			world.hud.inspector.show_pawn(world.customers.customers[0].pawn)
		return

	var want_storage: bool = what == "storage"
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry == null or not entry["built"]:
			continue
		var matches: bool = entry["def"].is_storage if want_storage else entry["def"].id == &"oven"
		if matches:
			world.hud.inspector.show_building(i)
			return


## Open a HUD panel for a capture. The harness has no cursor, so panels that a
## player would click or hotkey open have to be driven directly.
func _open_panel(which: String) -> void:
	if world == null or world.hud == null:
		return
	if which == "staff" and world.hud._priority_panel != null:
		world.hud._priority_panel.toggle()
	elif which == "production" and world.hud._production_panel != null:
		world.hud._production_panel.toggle()
	elif which == "supplies" and world.hud._supply_panel != null:
		world.hud._supply_panel.toggle()
	elif which == "handson":
		_open_hands_on()


## Pose the hands-on bench for a capture. The harness has no cursor, so the
## bench is stocked and the panel opened directly -- the same two things a
## player's click would have arranged.
func _open_hands_on() -> void:
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry == null or not entry["built"]:
			continue
		var recipes: Array = RecipeCatalog.for_station(entry["def"].id)
		if recipes.is_empty():
			continue
		var recipe: Recipe = recipes[0]
		var station: Dictionary = world.generator.station_at(i)
		if station.is_empty():
			continue
		for need in recipe.inputs:
			var def: ItemDef = ItemCatalog.get_def(need["id"])
			if def == null:
				continue
			var short: int = need["count"] - world.generator.count_at_station(station, need["id"])
			if short > 0:
				var placed: int = world.items.place_near(def, short, station["tiles"][0], 1)
				world.generator.produced[def.id] = world.generator.produced.get(def.id, 0) + placed
		if world.hud.open_hands_on(i, recipe):
			print("Hands-on: opened %s at placement %d" % [recipe.display_name, i])
			return
	push_warning("Scenario: no bench could be opened by hand.")
