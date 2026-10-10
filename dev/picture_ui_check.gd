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
	# A piece with looks: its styles above the bar.
	for id in [&"bed_roses", &"parasol_table", &"stone_path"]:
		world.hud._build_bar.choose(BuildingCatalog.get_def(id))
		await _settle()
		await _shot("styles_" + String(id), "Styles of %s" % BuildingCatalog.get_def(id).display_name)
	world.build.select(null)
	world.hud._toggle_build_bar()

	# The bar dressed as a lemonade stall, where it stands, and its card.
	var bar_index: int = _first(&"bar_table")
	if bar_index >= 0:
		world.restyle_piece(bar_index, BuildingCatalog.style(&"bar_table", &"stall"))
		var tile: Vector2i = world.build.grid.placements[bar_index]["origin"]
		world.rig.focus_on(Vector3(tile.x + 1.0, world.terrain.plot_height, tile.y + 0.5))
		world.hud.inspector.show_building(bar_index)
		await _frames(30)
		await _settle()
		await _shot("stall_in_world", "The bar restyled as a lemonade stall, and its card's Style row")
		world.hud.inspector.clear()

	world.hud.toggle_supplies()
	await _settle()
	await _shot("stores_meals", "Stores: meals and what they need")
	world.hud._supply_panel.show_manual()
	await _settle()
	await _shot("stores_manual", "Stores: a one-off cart")
	var panel: SupplyPanel = world.hud._supply_panel
	panel.quantity = 0
	for i in range(3):
		for def in ItemCatalog.purchasable():
			panel.add_ware(def.id, 1)
	await _settle()
	await _shot("stores_full", "Stores: stack clicks until the yard is full")
	panel.reset_to_standard()
	panel.quantity = 5
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
	world.hud.inspector.clear()

	# The Ledger, the day's close, the keeper's options and a finger's tip.
	world.hud.toggle_ledger()
	await _settle()
	await _shot("ledger", "The Ledger: money, sales, guests and the larder in pictures")
	world.hud.toggle_ledger()
	var entry: Dictionary = {"day": world.clock.day, "served": world.customers.served_count,
		"lost": world.customers.lost_count, "purse": GameState.gold, "profit": world.ledger.profit(),
		"lines": world.ledger.today.duplicate()}
	world.hud._day_summary.show_day(entry, world.hud._tavern_name(), world.customers.reputation,
		world.customers.day_reviews, {}, world.customers.consumed_today)
	await _settle()
	await _shot("day_summary", "The day's close, with what sold")
	world.hud._day_summary.visible = false
	world.spawn_keeper()
	var bar: int = _first(&"bar_table")
	if bar >= 0:
		var menu := KeeperMenu.new()
		world.hud._hud.add_child(menu)
		menu.open(world.keeper_controls.options_for(world.build.grid.placements[bar]["origin"]),
			get_viewport().get_visible_rect().size * 0.5, func(_o: Dictionary) -> void: pass)
		await _settle()
		await _shot("keeper_menu", "The keeper's options at the bar, with pictures")
		menu.queue_free()
	world.hud.toggle_supplies()
	world.hud._supply_panel.show_manual()
	world.hud._supply_panel.order.clear()
	world.hud._supply_panel.add_ware(&"flour", 1)
	await _settle()
	var flour: Control = world.hud._supply_panel._wares[&"flour"]["minus"].get_parent()
	TouchTips.show_at(flour.get_global_rect().get_center())
	await _frames(3)
	await _shot("touch_tip", "A finger held on the flour: its name, and the cart's minus button")
	world.hud.toggle_supplies()

	# Playing the keeper: the bar at the bottom, and waiting on a guest.
	world.keeper_controls.start()
	world.keeper.restore_carry({"id": "beer", "count": 3, "quality": 0.6})
	await _settle()
	await _frames(20)
	await _shot("keeper_bar", "Playing the keeper: what they hold, with Put down")
	world.keeper._clear_cargo()
	for brain in world.customers.customers:
		var options: Array = world.keeper_controls._guest_options(brain)
		if options.is_empty():
			continue
		var all: Array = world.keeper_controls.options_for(brain.pawn.tile, brain.pawn)
		var menu := KeeperMenu.new()
		world.hud._hud.add_child(menu)
		menu.open(all, get_viewport().get_visible_rect().size * 0.5, func(_o: Dictionary) -> void: pass)
		await _settle()
		await _shot("keeper_guest", "The keeper's options on a guest: %s" % String(all[0]["text"]))
		menu.queue_free()
		break
	world.keeper_controls.stop()
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
