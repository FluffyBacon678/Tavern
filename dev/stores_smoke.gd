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
	# Bulk units: a dough batch bakes ten loaves and a brew makes ten beers.
	check(need == {&"flour": 1, &"yeast": 1, &"water": 3, &"malt": 2, &"hops": 2}, "10 bread and 12 beer buy exactly one dough batch plus two brews; no duplicate intermediate target (%s)" % need)
	stock(&"wheat", 4)
	stock(&"flour", 1)
	stock(&"dough", 1)
	# Thirty loaves, three batches: one from the ready dough, one from the
	# flour in stock, one from flour ground from the wheat; only the water and
	# yeast for two doughs, and the two brews, are bought.
	world.bills.set_target(&"bake_bread", 30)
	need = auto.shortfall()
	check(need == {&"yeast": 2, &"water": 4, &"malt": 2, &"hops": 2}, "ready dough, flour and harvested wheat reduce shopping exactly once (%s)" % need)
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
	check(ordered == {&"flour": 1, &"water": 1, &"yeast": 1}, "meal setting actually purchases the required ingredients (%s)" % ordered)
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
	_check_merchant(panel)
	auto.set_meal(&"bake_bread", false, 11)
	auto.set_meal(&"fish_soup", true, 6)
	world.items.clear()
	auto.note = ""
	panel.refresh()
	check(panel._auto_note.text.contains("Waiting on the kitchen or a local catch"), "unavailable local fish is explained instead of claiming restock is satisfied")
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


## The merchant tab as a shop: a click buys the chosen amount, the yard's
## spaces cap the cart before paying, and buying empties the cart.
func _check_merchant(panel: SupplyPanel) -> void:
	world.items.clear()
	GameState.gold = 2000
	panel.show_manual()
	check(panel._manual.visible and not panel._meals.visible, "the Merchant tab shows the shop and hides the meals")
	panel.order.clear()
	panel.quantity = 5
	panel.add_ware(&"flour", 1)
	check(int(panel.order.get(&"flour", 0)) == 5, "a click on a ware puts the chosen five on the cart")
	panel.add_ware(&"flour", -1)
	check(not panel.order.has(&"flour"), "a right-click takes them off again")
	panel.quantity = 0
	for i in range(30):
		for def in ItemCatalog.purchasable():
			panel.add_ware(def.id, 1)
	check(world.delivery_preview(panel.order)["short"].is_empty(), "stack clicks stop at what the yard can hold")
	var spaces: int = 0
	for line in world.delivery_preview(panel.order)["plan"]:
		spaces += 1
	check(spaces == world.delivery_tiles().size(), "and fill every space in the yard (%d of %d)" % [spaces, world.delivery_tiles().size()])
	check(panel._ware_info.text.begins_with("No room in the yard"), "a click past that says the yard is full")
	panel.fill_for_meals()
	check(panel.order == auto_shortfall(), "What the meals need fills the cart with the restock shortfall")
	panel.reset_to_standard()
	var before: int = GameState.gold
	var cost: int = world.order_cost(panel.order)
	panel.refresh()
	check(PlayerActions.press(panel, "Buy cart"), "Buy cart is pressable with the usual order")
	check(GameState.gold == before - cost and panel.order.is_empty() and not world.delivered.is_empty(),
		"buying pays %dg, unloads the cart and empties it" % cost)
	world.items.clear()
	world.delivered.clear()
	# Buying closes the panel; open it again on Restock for the checks after.
	panel.show_meals()
	panel.toggle()


func auto_shortfall() -> Dictionary:
	var out: Dictionary = {}
	var wanted: Dictionary = world.auto_supply.shortfall()
	for id in wanted:
		if int(wanted[id]) > 0:
			out[id] = int(wanted[id])
	return out
