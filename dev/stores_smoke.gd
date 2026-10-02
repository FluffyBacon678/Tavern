extends Node

var failures: int = 0
var world: TavernWorld

func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1

func stock(id: StringName, count: int) -> void:
	var placed: int = world.items.place_near(ItemCatalog.get_def(id), count, world.plot.position + Vector2i(9, 10))
	world.delivered[id] = int(world.delivered.get(id, 0)) + placed

func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	SimWait.seed_run()
	GameState.world_seed = 12345
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	for i in range(3):
		world.build.place_programmatic(BuildingCatalog.get_def([&"prep_table", &"oven", &"brewing_vat"][i]), world.plot.position + Vector2i(10 + i * 3, 12), 0, false)
	var auto: AutoSupply = world.auto_supply
	var need: Dictionary = auto.shortfall()
	check(need == {&"flour": 5, &"yeast": 5, &"water": 8, &"malt": 3, &"hops": 3}, "10 bread and 12 beer buy exactly five dough batches plus three brews; no duplicate intermediate target")
	stock(&"wheat", 4)
	stock(&"flour", 1)
	stock(&"dough", 1)
	need = auto.shortfall()
	check(need == {&"flour": 1, &"yeast": 4, &"water": 7, &"malt": 3, &"hops": 3}, "ready dough, flour and harvested wheat reduce shopping exactly once")
	check(world.stock_of(&"wheat") == 4 and world.stock_of(&"flour") == 1, "planning never consumes real farm goods")
	world.items.clear()
	world.delivered.clear()
	auto.set_meal(&"bake_bread", false, 10)
	auto.set_meal(&"brew_beer", false, 12)
	check(auto.shortfall().is_empty(), "without a catch, fish targets do not buy unusable soup water")
	stock(&"perch", 3)
	auto.set_meal(&"grill_fish", true, 3)
	need = auto.shortfall()
	check(need == {&"water": 3}, "three perch supply six soup and three grilled fish through shared heads and fillets")
	auto.set_never(&"water", true)
	check(auto.shortfall().is_empty(), "legacy never-buy restrictions remain respected")
	auto.never.clear()
	world.items.clear()
	world.delivered.clear()
	auto.set_meal(&"fish_soup", false, 6)
	auto.set_meal(&"grill_fish", false, 3)
	auto.set_meal(&"bake_bread", true, 10)
	check(auto.started() and int(world.bills.get_bill(&"bake_bread")["resume_below"]) == 9, "setting a meal starts automatic ordering without a manual cart and resumes below its single target")
	GameState.gold = GameState.STARTING_GOLD
	auto._since_order = AutoSupply.COOLDOWN
	var ordered: Dictionary = auto.check()
	check(ordered == {&"flour": 5, &"water": 5, &"yeast": 5}, "meal setting actually purchases the required ingredients")
	check(auto.shortfall().is_empty() and auto.check().is_empty(), "delivered stock prevents a duplicate cart")
	var data: Dictionary = SaveGame.capture(world)
	SaveGame.apply(world, data)
	check(auto.configured and auto._since_order < 1.0 and int(world.bills.get_bill(&"bake_bread")["target"]) == 10, "meal policy and delivery cooldown survive save/load")
	var scenario: Node = load("res://dev/world_scenario.gd").new()
	scenario.world = world
	add_child(scenario)
	check(scenario.reconcile(false), "automatic meal shopping reconciles goods and gold")
	var panel: SupplyPanel = world.hud._supply_panel
	panel.toggle()
	check(panel._meal_widgets.size() == MealSupplyPlan.meals().size() and not panel._manual.visible, "Stores shows every meal and hides manual order options initially")
	panel._meal_widgets[&"bake_bread"]["toggle"].button_pressed = false
	check(not world.bills.get_bill(&"bake_bread")["enabled"], "the visible meal toggle controls its production bill")
	panel._meal_widgets[&"bake_bread"]["toggle"].button_pressed = true
	panel._adjust_meal(&"bake_bread", 1)
	check(world.bills.get_bill(&"bake_bread")["target"] == 11, "the visible plus control changes the shared meal target")
	auto.set_meal(&"bake_bread", false, 11)
	auto.set_meal(&"fish_soup", true, 6)
	world.items.clear()
	auto.note = ""
	panel.refresh()
	check(panel._auto_note.text.contains("Waiting on kitchen or local ingredients"), "unavailable local fish is explained instead of claiming restock is satisfied")
	check(panel._auto_note.tooltip_text.contains("Kitchen details"), "blocked restock offers an actionable hint")
	for dimensions in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1440, 900)]:
		get_window().size = dimensions
		for frame in range(4):
			await get_tree().process_frame
		panel.refresh()
		await get_tree().process_frame
		var viewport: Rect2 = get_viewport().get_visible_rect()
		check(viewport.encloses(panel.get_global_rect()), "Stores fits inside %s (actual %s)" % [dimensions, viewport.size])
		for widgets in panel._meal_widgets.values():
			var pixels: float = widgets["toggle"].size.y * float(get_window().size.y) / viewport.size.y
			check(pixels >= 24.0 and panel.get_global_rect().encloses(widgets["toggle"].get_global_rect()), "%s at %s: %.1fpx click height, bounds %s inside %s" % [widgets["toggle"].text, dimensions, pixels, widgets["toggle"].get_global_rect(), panel.get_global_rect()])
	world.queue_free()
	scenario.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("STORES SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
