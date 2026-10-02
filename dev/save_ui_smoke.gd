extends Node

## Actual Load backup -> scene router -> pause-menu Save -> Continue.
## Root-owned observer survives scene changes. Optional shots=<prefix> windowed.
var failures: int = 0
var shots: String = ""

func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	get_tree().current_scene = null
	get_tree().create_timer(45.0).timeout.connect(func() -> void: get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			shots = arg.trim_prefix("shots=")
	SimWait.seed_run()
	GameState.full_house_start = true
	GameState.start_new_run("The Adventurers' Rest — a very long saved tavern name", 493774, 0, true)
	var fixture: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(fixture)
	SimWait.hold(fixture)
	fixture.hud.open_pause_menu()
	check(PlayerActions.press(fixture.hud.pause_menu, "Save game"), "real pause-menu Save button pressed")
	check(GameState.has_save(0), "Save button writes a readable disk snapshot")
	var data: Dictionary = SaveGame.read(0)
	check(SaveGame.write(0, data), "previous save preserved for recovery fixture")
	# All cards have distinct provenance, including a designed tutorial.
	var tutorial: Dictionary = data.duplicate(true)
	tutorial["level"] = String(LevelCatalog.tutorial().id)
	tutorial["tavern_name"] = "The Practice House"
	SaveGame.write(1, tutorial)
	var file := FileAccess.open(GameState.slot_path(0), FileAccess.WRITE)
	file.store_string('{"version":')
	file.close()
	await _finish_render()
	fixture.queue_free()
	await get_tree().process_frame
	var recovered: Dictionary = GameState.slot_summary(0)
	GameState.slot_summary(1)
	check(recovered.get("backup_recovered", false), "backup provenance survives reading another slot")
	check(SaveSlotDetails.kind(tutorial) == "Tutorial", "tutorial saves are labelled Tutorial")
	var menu: Control = load("res://src/ui/main_menu/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	menu._open_page(menu.Page.LOAD, false)
	for shape in [Vector2i(1280, 720), Vector2i(1024, 768)]:
		get_window().size = shape
		for frame in range(6):
			await get_tree().process_frame
		check(get_viewport().get_visible_rect().encloses(menu._page_panel.get_global_rect()), "Load page fits %s" % shape)
		var button: Button = PlayerActions.find_button(menu, "Load backup")
		check(button != null and get_viewport().get_visible_rect().encloses(button.get_global_rect()), "Load backup control fits %s" % shape)
		check(menu._menu_title.get_global_rect().end.x <= menu._page_panel.get_global_rect().position.x, "title stays beside Load page at %s" % shape)
		await _shot("load_%dx%d" % [shape.x, shape.y])
	check(PlayerActions.press(menu, "Load backup"), "actual Load backup button initiates resume")
	await SceneRouter.transition_finished
	var world: TavernWorld = get_tree().current_scene
	SimWait.hold(world)
	check(world.restored_backup and world.build.grid.live_count() == data["buildings"].size(), "menu transition restores the recovered populated world")
	world.hud.open_pause_menu()
	check(world.hud.pause_menu._status.text.contains("previous backup"), "pause menu retains the recovery reminder")
	check(world.hud.pause_menu._where.text.contains("Slot 1") and world.hud.pause_menu._where.text.contains("stock piles"), "pause menu identifies the slot and its contents")
	await _shot("pause_recovered")
	PlayerActions.press(world.hud.pause_menu, "Save game")
	check(not world.restored_backup and not world.hud.pause_menu._status.text.contains("previous backup"), "successful Save clears recovery reminder")
	var saved: Dictionary = SaveGame.read(0)
	check(not saved.is_empty() and not SaveGame.recovered_backup, "saved recovery now has a valid primary")
	world.hud.pause_menu.close()
	SceneRouter.change_scene("res://src/ui/main_menu/main_menu.tscn")
	await SceneRouter.transition_finished
	menu = get_tree().current_scene
	# Make this the most recent slot, deterministically, without wall-clock ties.
	saved["saved_at"] = int(Time.get_unix_time_from_system()) + 2
	SaveGame.write(0, saved)
	check(PlayerActions.press(menu, "Continue"), "actual Continue button pressed")
	await SceneRouter.transition_finished
	world = get_tree().current_scene
	SimWait.hold(world)
	check(world.build.grid.live_count() == saved["buildings"].size() and GameState.tavern_name == saved["tavern_name"], "Continue returns to the same saved tavern")
	await _finish_render()
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	print("SAVE UI SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _finish_render() -> void:
	# A windowed fixture must finish its first sky render before teardown.
	# Deleting a newly-created sky before that draw leaves pending GLES work.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _shot(label: String) -> void:
	if shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(shots + "_" + label + ".png") == OK, "capture %s" % label)
