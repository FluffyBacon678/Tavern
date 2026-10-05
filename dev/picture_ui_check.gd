extends Node

## The menus with pictures, on the sandbox house: the build bar, the stores,
## the kitchen's standing orders, a bench's card, a shelf's card and a guest's
## order. Not pass/fail: screenshots to look at. Run windowed:
##   godot --path . --resolution 1600x900 res://dev/picture_ui_check.tscn -- <out dir>

var out_dir: String = "user://picture_ui_check"
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
	GameState.start_new_run("Picture Check", 493774, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	world.sim.speed = 4
	# Let the house trade for a while, so benches and shelves hold something.
	await _frames(900)
	world.sim.speed = 0
	await _settle()

	world.hud._toggle_build_bar()
	for category in BuildingCatalog.categories():
		world.hud._build_bar._show_category(category)
		await _settle()
		await _shot("build_" + category.to_lower(), "Build bar, %s" % category)
	world.hud._toggle_build_bar()

	world.hud.toggle_supplies()
	await _settle()
	await _shot("stores_meals", "Stores: meals and what they need")
	world.hud._supply_panel.show_manual()
	await _settle()
	await _shot("stores_manual", "Stores: a one-off cart")
	world.hud.toggle_supplies()
	world.hud._production_panel.toggle()
	await _settle()
	await _shot("kitchen_details", "Kitchen details: standing orders")
	world.hud._production_panel.toggle()

	for id in [&"prep_table", &"oven", &"storage_shelf", &"barrel", &"bar_table"]:
		var index: int = _first(id)
		if index < 0:
			continue
		world.hud.inspector.show_building(index)
		await _settle()
		await _shot("card_" + String(id), "%s card" % id)
	for brain in world.customers.customers:
		if not brain.order.is_empty():
			world.hud.inspector.show_pawn(brain.pawn)
			await _settle()
			await _shot("card_guest", "A guest's order")
			break
	print("PICTURE UI CHECK: done")
	get_tree().quit()


func _first(id: StringName) -> int:
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["built"] and entry["def"].id == id:
			return i
	return -1


func _settle() -> void:
	await _frames(6)
	var waited: int = 0
	while not IconStudio.settled() and waited < 300:
		await get_tree().process_frame
		waited += 1
	await _frames(4)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("%s: %s" % [name, note])
