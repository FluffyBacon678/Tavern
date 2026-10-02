extends Node

## Save on disk -> separate engine process -> Continue. Player files are only
## read; each process owns a begin_test_session() sandbox and cleans it on exit.
var failures: int = 0
var world: TavernWorld

func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("read="):
			await _load_copy(arg.trim_prefix("read="))
			_finish()
			return
	SimWait.seed_run()
	GameState.full_house_start = true
	GameState.start_new_run("Persistence Test House", 493774, 0, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	# Player decisions beyond the starting fixture, including unfinished work.
	PlayerActions.place_all(world, &"chair", [world.plot.position + Vector2i(2, 2)])
	world.auto_supply.set_meal(&"bake_bread", true, 17)
	world.workers[0].restore_cargo(ItemCatalog.get_def(&"water"), 3, 0.8)
	world.delivered[&"water"] = int(world.delivered.get(&"water", 0)) + 3
	# Changing a shelf whitelist does not remove stock already on that shelf.
	# Filling its surroundings proves loading must restore, not deliver nearby.
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry == null or entry["def"].id != &"storage_shelf":
			continue
		var tile: Vector2i = entry["origin"]
		var flour: ItemDef = ItemCatalog.get_def(&"flour")
		world.items.add(flour, 4, tile, 0.7)
		for y in range(-6, 7):
			for x in range(-6, 7):
				if Vector2i(x, y) != Vector2i.ZERO:
					world.items.add(ItemCatalog.get_def(&"yeast"), 10, tile + Vector2i(x, y))
		world.build.grid.set_filter(i, ["yeast"])
		break
	for entry in world.build.grid.placements:
		if entry != null and entry["def"].id == &"farm_plot":
			entry["crop"] = &"hops"
			entry["growth"] = 1.0
			entry["harvest_remaining"] = 1
			break
	check(world.save_now(), "populated tavern saves to sandbox disk")
	check(not world.has_unsaved_progress(), "saved state is clean")
	world.auto_supply.set_meal(&"bake_bread", true, 18)
	check(world.has_unsaved_progress(), "changing a meal target while paused counts as unsaved progress")
	world.auto_supply.set_meal(&"bake_bread", true, 17)
	var own_path: String = ProjectSettings.globalize_path(GameState.slot_path(0))
	GameState.active_slot = 1
	world.clock.fraction = 1.0
	world.clock.paused = true
	world._on_day_ended(world.clock.day)
	check(world.save_now(), "closed-day autosave fixture writes")
	var closed_path: String = ProjectSettings.globalize_path(GameState.slot_path(1))
	world.queue_free()
	await get_tree().process_frame
	world = null
	_restart(own_path)
	_restart(closed_path)
	for arg in args:
		if arg.begins_with("source="):
			_restart(ProjectSettings.globalize_path(arg.trim_prefix("source=")))
	_failure_cases()
	_finish()

func _failure_cases() -> void:
	var path: String = GameState.slot_path(0)
	var first: Dictionary = SaveGame.read(0)
	var second: Dictionary = first.duplicate(true)
	second["gold"] = int(first["gold"]) + 1
	check(SaveGame.write(0, second), "second save commits")
	check(int(SaveGame._read_json(path + ".bak")["gold"]) == int(first["gold"]), "previous complete save retained as backup")
	check(SaveGame.write(0, second), "third save safely replaces an existing backup")
	var contents: String = FileAccess.get_file_as_string(path)
	var incomplete: Dictionary = second.duplicate(true)
	incomplete.erase("items")
	check(not SaveGame.write(0, incomplete) and FileAccess.get_file_as_string(path) == contents,
		"incomplete snapshot is rejected without overwriting a valid save")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"version":2,"world_seed":493774}')
	file.close()
	check(not SaveGame.read(0).is_empty() and SaveGame.recovered_backup,
		"valid JSON missing buildings/items recovers the previous full save")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"version":')
	file.close()
	check(not SaveGame.read(0).is_empty() and SaveGame.recovered_backup,
		"interrupted/truncated primary recovers the backup")
	_restart(ProjectSettings.globalize_path(path + ".bak"))
	check(SaveGame.write(0, second) and not SaveGame._read_json(path + ".bak").is_empty(),
		"saving after recovery retains the good backup instead of corrupt primary")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(not SaveGame.read(0).is_empty() and SaveGame.recovered_backup,
		"interruption between backup rotation and commit remains recoverable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"version":2,"world_seed":493774}')
	file.close()
	check(SaveGame.read(0).is_empty() and not GameState.request_continue(0),
		"unrecoverable incomplete save cannot open an empty replacement world")

func _restart(path: String) -> void:
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://dev/save_resume_smoke.tscn", "--", "read=" + path], output, true)
	for line in output:
		print(String(line).strip_edges())
	var clean: bool = true
	for line in output:
		clean = clean and not String(line).contains("ERROR:")
	check(code == 0 and clean, "fresh engine process restores %s (exit %d, no engine errors)" % [path.get_file(), code])

func _load_copy(path: String) -> void:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(expected is Dictionary, "%s parses" % path.get_file())
	if not expected is Dictionary:
		return
	check(DirAccess.copy_absolute(path, ProjectSettings.globalize_path(GameState.slot_path(0))) == OK,
		"source copied into isolated save slot")
	check(GameState.request_continue(0), "Continue accepts the disk save")
	if not GameState.load_requested:
		return
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	# Compare JSON values on both sides (JSON decodes integer numbers as floats).
	var actual: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world)))
	_compare_rows(expected.get("buildings", []), actual["buildings"], "buildings", ["def", "x", "y", "rot", "built", "filter", "crop", "growth", "harvest_remaining"])
	_compare_rows(expected.get("items", []), actual["items"], "item stacks", ["id", "x", "y", "count", "quality"])
	_compare_rows(expected.get("pawns", []), actual["pawns"], "staff and cargo", ["name", "seed", "role", "priorities", "cargo"])
	check(int(expected["gold"]) == GameState.gold, "gold preserved: %d" % GameState.gold)
	check(expected["plot"] == actual["plot"], "purchased plot preserved")
	check(int(expected["world_seed"]) == world._world_seed, "world seed preserved")
	var bills_kept: bool = true
	for id in expected.get("bills", {}):
		# Older wells had a draw-water recipe. Rain collection replaced that
		# obsolete bill; preserving its toggle cannot create a current recipe.
		if id == "draw_water" and not actual["bills"].has(id):
			continue
		if not actual["bills"].has(id):
			print("DIFFERENCE: missing production bill '%s'" % id)
			bills_kept = false
			continue
		for field in ["target", "enabled"]:
			bills_kept = bills_kept and expected["bills"][id][field] == actual["bills"][id][field]
	check(bills_kept, "production targets and toggles preserved (legacy restart thresholds may migrate)")
	if float(expected.get("clock_fraction", 0.0)) >= 1.0:
		check(world.simulation_paused and world.sim.held and world.hud._day_summary.visible,
			"closed-day resume holds ALL simulation behind its summary")
		var gold: int = GameState.gold
		world._begin_next_day()
		check(world.clock.day == int(expected["day"]) + 1 and not world.simulation_paused,
			"resumed summary opens exactly the next day")
		check(GameState.gold == gold, "resume does not charge wages twice")
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	world = null

func _compare_rows(before: Array, after: Array, label: String, fields: Array) -> void:
	check(before.size() == after.size(), "%s count %d -> %d" % [label, before.size(), after.size()])
	var same: bool = before.size() == after.size()
	for i in range(mini(before.size(), after.size())):
		for field in fields:
			if before[i].has(field) and not _equivalent(before[i][field], after[i].get(field)):
				print("DIFFERENCE: %s[%d].%s: %s -> %s" % [label, i, field, before[i][field], after[i].get(field)])
				same = false
	check(same, "every saved %s field restored" % label)

func _equivalent(before: Variant, after: Variant) -> bool:
	if before is Dictionary and after is Dictionary:
		# New work kinds may gain default priorities; saved choices must survive.
		for key in before:
			if not after.has(key) or not _equivalent(before[key], after[key]):
				return false
		return true
	return before == after

func _finish() -> void:
	print("SAVE RESUME SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
