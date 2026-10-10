extends Node

## Save in awkward states and load back through the game's own path: the keeper
## in play mode holding goods, staff mid-haul, guests, a blueprint, a restyled
## piece, a till, mid-day. Then the things a player does next: hire, call the
## keeper. Part of dev/run_tests.sh.
##   godot --headless --path . res://dev/save_edge_check.tscn

var failures: int = 0


func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _ready() -> void:
	if not GameState.begin_test_session():
		get_tree().quit(2)
		return
	GameState.full_house_start = true
	GameState.start_new_run("Edge Save", 493774, 0, true)
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	await _frames(5)
	world.sim.speed = 4
	await _frames(1200)  # trade until guests are seated and eating
	# Restyle, a till, a blueprint, the keeper holding goods in play mode.
	var bar: int = _first(world, &"bar_table")
	world.restyle_piece(bar, BuildingCatalog.style(&"bar_table", &"stall"))
	world.set_till(bar, true)
	var bp: int = -1
	for y in range(world.plot.position.y + 1, world.plot.end.y - 1):
		for x in range(world.plot.position.x + 1, world.plot.end.x - 1):
			if bp < 0 and world.build.grid.can_place(BuildingCatalog.get_def(&"parasol_table"), Vector2i(x, y), 0):
				bp = world.build.place_programmatic(BuildingCatalog.get_def(&"parasol_table"), Vector2i(x, y), 0, true)
	world.keeper_controls.start()
	await _frames(10)
	world.keeper.restore_carry({"id": "beer", "count": 3, "quality": 0.6})
	world.sim.speed = 0
	await _frames(5)
	var guests: int = world.customers.customers.size()
	var before: Dictionary = SaveGame.capture(world)
	check(world.save_now(), "saves mid-day with %d guests, keeper playing and carrying" % guests)
	world.queue_free()
	await _frames(3)

	GameState.active_slot = 0
	GameState.load_requested = true
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	# Held still: the load is what is being compared, and a loaded tavern left
	# running for ten real frames moved a stack under a busy machine.
	SimWait.hold(world)
	await _frames(10)
	var after: Dictionary = SaveGame.capture(world)
	# Goods restored to someone's hands go to a shelf, not onto the floor:
	# the first steps after the load set them off.
	for i in range(3):
		world.sim.ticked.emit(SimClock.STEP)
	var carriers: int = 0
	var to_storage: int = 0
	var storage: Array[Vector2i] = world.generator._storage_tiles()
	for w in world.workers:
		if w.carried_count() > 0:
			carriers += 1
			if w.current != null and w.current.kind == WorkType.Kind.HAUL and storage.has(w.current.target):
				to_storage += 1
	check(carriers == to_storage, "restored cargo is carried to storage (%d of %d)" % [to_storage, carriers])
	# A load renamed the staff's node, so anything that looked it up by name
	# afterwards (hiring, calling the keeper in) found nothing.
	check(world._find("Pawns") != null, "the staff node keeps its name after a load")
	var staff_before: int = world.workers.size()
	var hired: String = world.hire(&"waiter")
	check(world.workers.size() == staff_before + 1, "hiring works after a load ('%s')" % hired)
	world.clear_keeper()
	world.spawn_keeper()
	await _frames(3)
	check(world.keeper != null and is_instance_valid(world.keeper.pawn), "the keeper can be called in after a load")
	for r in before["pawns"]:
		if not r.get("cargo", {}).is_empty():
			print("  saved cargo %s: %s" % [r.get("name"), r["cargo"]])
	for key in ["gold", "day", "plot", "tavern_name"]:
		check(str(before.get(key)) == str(after.get(key)), "%s kept (%s / %s)" % [key, before.get(key), after.get(key)])
	check(before["buildings"].size() == after["buildings"].size(), "pieces %d -> %d" % [before["buildings"].size(), after["buildings"].size()])
	check(before["items"].size() == after["items"].size(), "stacks %d -> %d" % [before["items"].size(), after["items"].size()])
	check(before["pawns"].size() == after["pawns"].size(), "staff %d -> %d" % [before["pawns"].size(), after["pawns"].size()])
	check(str(before.get("keeper")) == str(after.get("keeper")), "keeper kept (%s / %s)" % [before.get("keeper"), after.get("keeper")])
	var b_guests: int = before.get("customers", {}).get("guests", []).size() if before.get("customers") is Dictionary else -1
	var a_guests: int = after.get("customers", {}).get("guests", []).size() if after.get("customers") is Dictionary else -1
	check(b_guests == a_guests, "guests %d -> %d" % [b_guests, a_guests])
	var bar2: int = _first(world, &"bar_table")
	check(bar2 >= 0 and world.build.grid.placements[bar2]["def"].skin == &"stall" and world.build.grid.placements[bar2].get("till", false),
		"the bar stays a lemonade stall and a till")
	var drawn: int = 0
	var placed: int = 0
	for entry in world.build.grid.placements:
		if entry != null:
			placed += 1
	for store in [world.build._instances, world.build._blueprints]:
		for k in store:
			if is_instance_valid(store[k]) and store[k].multimesh != null:
				drawn += store[k].multimesh.instance_count
	check(drawn == placed, "everything drawn (%d / %d)" % [drawn, placed])
	# Which stacks differ, for the report.
	var b_items: Dictionary = {}
	var a_items: Dictionary = {}
	for r in before["items"]:
		b_items["%s@%s,%s" % [r["id"], r["x"], r["y"]]] = r["count"]
	for r in after["items"]:
		a_items["%s@%s,%s" % [r["id"], r["x"], r["y"]]] = r["count"]
	for k in a_items:
		if not b_items.has(k) or int(b_items[k]) != int(a_items[k]):
			print("  stack after load: %s x%s (before: %s)" % [k, a_items[k], b_items.get(k, "none")])
	for k in b_items:
		if not a_items.has(k):
			print("  stack lost: %s x%s" % [k, b_items[k]])
	print("SAVE EDGE CHECK: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _first(world: TavernWorld, id: StringName) -> int:
	for i in range(world.build.grid.placements.size()):
		var e = world.build.grid.placements[i]
		if e != null and e["def"].id == id:
			return i
	return -1


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
