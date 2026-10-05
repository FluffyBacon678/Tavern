extends Node

## Playing the keeper, shown on the sandbox house. Run windowed:
##   godot --path . --resolution 1600x900 res://dev/keeper_showcase.tscn -- <out dir>
##
## 1 the keeper called in and the view following them, 2 the options menu open
## on the bar, 3 the keeper carrying lemons to the bar, which takes payments.

var out_dir: String = "user://keeper_showcase"
var world: TavernWorld


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	GameState.full_house_start = true
	GameState.start_new_run("Keeper Show", 493774, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	GameSettings.thought_bubbles = true
	world.sim.speed = 1

	var bar: int = -1
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["def"].id == &"bar_table":
			bar = i
	var bar_tile: Vector2i = world.build.grid.placements[bar]["tiles"][0]
	world.rig.focus_on(Vector3(bar_tile.x + 0.5, world.terrain.plot_height, bar_tile.y - 2.0))
	world.keeper_controls.start()
	world.keeper.pawn.position = world.keeper.pawn.world_position_of(world.keeper.pawn.tile)
	await _frames(90)
	await _shot("1_keeper_in", "Take control: the keeper appears and the view follows them")

	world.set_till(bar, true)
	await _frames(30)
	var at: Vector2 = world.rig.camera.unproject_position(Vector3(bar_tile.x + 0.5, world.terrain.plot_height + 1.0, bar_tile.y + 0.5))
	world.keeper_controls.open_menu(at)
	await _frames(20)
	await _shot("2_menu", "Right-click on the bar: %s" % ", ".join(world.keeper_controls.menu.options().map(
		func(o: Dictionary) -> String: return String(o["text"]))))
	world.keeper_controls.close_menu()

	# Lemons from the shelf to the bar.
	for tile in world.items.tiles_with(&"lemons", world.keeper.pawn.tile):
		world.keeper.take(tile)
		break
	var waited: int = 0
	while world.keeper.carry_count == 0 and waited < 1800:
		await get_tree().process_frame
		waited += 1
	world.keeper.put(bar_tile)
	await _frames(120)
	await _shot("3_carrying", "Carrying the lemons to the bar, which takes payments (the coin): %s" % world.keeper.status_text())
	# Wait for the real delivery, then start a real fishing task. Freeze only
	# after arriving, so the shot shows the actual keeper's working state.
	var deadline: int = Time.get_ticks_msec() + 20000
	while world.keeper.carry_count > 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var spot: int = -1
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["built"] and entry["def"].id == &"fishing_spot":
			spot = i
			break
	if spot >= 0 and world.keeper.work(spot, RecipeCatalog.get_recipe(&"catch_fish")):
		world.sim.speed = 5
		deadline = Time.get_ticks_msec() + 30000
		while world.keeper.pawn.is_busy() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if world.keeper.pawn.is_busy():
			push_error("Keeper showcase did not reach the fishing spot")
			get_tree().quit(1)
			return
		world.keeper.pawn._process(0)
		SimWait.hold(world)
		world.rig._distance_target = 5.5
		await _frames(60)
		await _shot("4_fishing", "Real fishing task, with a basic rod and the keeper's ground marker")
	else:
		push_error("Keeper showcase could not start fishing")
		get_tree().quit(1)
		return
	print("KEEPER SHOWCASE: done")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("%s: %s" % [name, note])
