extends Node

## Load a save file the way the game does and compare what comes back with
## what the file holds: pieces placed, pieces drawn, goods restored, the land.
## The file is copied into a test session's own folder first, so the player's
## real slots are never touched. Run:
##   godot --headless --path . res://dev/save_load_check.tscn -- <path to slot_N.json>

var failures: int = 0


func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not GameState.begin_test_session():
		print("SAVE LOAD CHECK: give a save file path")
		get_tree().quit(2)
		return
	var source: String = args[0]
	var text: String = FileAccess.get_file_as_string(source)
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		print("SAVE LOAD CHECK: %s is not a save" % source)
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GameState.save_dir()))
	var copy := FileAccess.open(GameState.slot_path(0), FileAccess.WRITE)
	copy.store_string(text)
	copy.close()
	print("SAVE LOAD CHECK: %s (level %s, day %s, %d buildings, %d stacks)" % [source.get_file(),
		data.get("level", ""), data.get("day", ""), data.get("buildings", []).size(), data.get("items", []).size()])
	print("  validation: '%s'" % SaveGame._validation_error(data))

	GameState.active_slot = 0
	GameState.load_requested = true
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	for i in range(10):
		await get_tree().process_frame

	var placed: int = 0
	var by_id: Dictionary = {}
	for entry in world.build.grid.placements:
		if entry != null:
			placed += 1
			var key: String = String(entry["def"].id)
			by_id[key] = int(by_id.get(key, 0)) + 1
	var wanted: Dictionary = {}
	for row in data.get("buildings", []):
		var def: BuildingDef = BuildingCatalog.get_def(StringName(row["def"]))
		var key: String = String(def.id) if def != null else "?" + String(row["def"])
		wanted[key] = int(wanted.get(key, 0)) + 1
	check(placed == data.get("buildings", []).size(), "every saved piece is placed (%d of %d)" % [placed, data.get("buildings", []).size()])
	for key in wanted:
		if int(by_id.get(key, 0)) != int(wanted[key]):
			check(false, "%s: %d saved, %d loaded" % [key, wanted[key], int(by_id.get(key, 0))])
	# Drawn: every placement in some batch (linked pieces in their joints).
	var drawn: int = 0
	for store in [world.build._instances, world.build._blueprints]:
		for key in store:
			var mmi: MultiMeshInstance3D = store[key]
			if is_instance_valid(mmi) and mmi.multimesh != null:
				drawn += mmi.multimesh.instance_count
	check(drawn == placed, "every placed piece is drawn (%d drawn, %d placed)" % [drawn, placed])
	var stacks: int = 0
	var goods: int = 0
	for tile in world.items.all_tiles():
		stacks += 1
		goods += world.items.count_at(tile)
	var saved_goods: int = 0
	for row in data.get("items", []):
		saved_goods += int(row.get("count", 0))
	check(stacks == data.get("items", []).size() and goods == saved_goods,
		"every saved stack is restored (%d stacks / %d goods of %d / %d)" % [stacks, goods, data.get("items", []).size(), saved_goods])
	check(world.plot == Rect2i(int(data["plot"][0]), int(data["plot"][1]), int(data["plot"][2]), int(data["plot"][3])),
		"the land is restored (%s)" % world.plot)
	# Windowed, with a second argument: a picture of the loaded tavern.
	if args.size() > 1 and DisplayServer.get_name() != "headless":
		var middle: Vector2 = Vector2(world.plot.position) + Vector2(world.plot.size) * 0.5
		world.rig.focus_on(Vector3(middle.x, world.terrain.plot_height, middle.y))
		for i in range(30):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[1])
		print("  picture: %s" % args[1])
	print("SAVE LOAD CHECK: %d failure(s)" % failures)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
