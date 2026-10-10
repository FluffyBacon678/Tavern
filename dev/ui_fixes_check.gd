extends Node

## The interface fixes of the 2026-10-07 bug hunt, checked headless:
##   a finger held on a picture or a button shows its name (touch has no hover);
##   a ware comes off the cart with a button, not only a right click;
##   the Ledger is the books and the larder in pictures, not a debug readout;
##   the day summary and the keeper's options carry pictures.
##   godot --headless --path . res://dev/ui_fixes_check.tscn

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
	# A real window size: headless starts at 64 x 64 with a stretched viewport.
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	for i in range(3):
		await get_tree().process_frame
	await _touch_tips()
	GameState.full_house_start = true
	GameState.start_new_run("UI Check Arms", 493774, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	for i in range(10):
		await get_tree().process_frame
	await _cart_minus()
	await _ledger()
	_day_summary()
	_keeper_menu()
	print("UI FIXES CHECK: %d failure(s)" % failures)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)


func _touch_tips() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var button := Button.new()
	button.text = "Hi"
	button.tooltip_text = "Says hello"
	button.position = Vector2(100, 100)
	button.size = Vector2(80, 40)
	layer.add_child(button)
	var row := HBoxContainer.new()
	row.position = Vector2(300, 100)
	layer.add_child(row)
	row.add_child(GoodsStrip.chip(&"flour", "3"))
	await get_tree().process_frame
	await get_tree().process_frame
	check(TouchTips.tooltip_at(Vector2(120, 115)) == "Says hello", "a button's tip is found under a finger")
	var chip: Control = row.get_child(0)
	var on_picture: Vector2 = chip.get_global_rect().position + Vector2(6, 6)
	check(TouchTips.tooltip_at(on_picture) == ItemCatalog.get_def(&"flour").display_name,
		"a picture of goods gives its name ('%s')" % TouchTips.tooltip_at(on_picture))
	check(TouchTips.tooltip_at(Vector2(700, 500)).is_empty(), "open space has no tip")
	# Held down: the tip shows. Lifted early: it does not.
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = Vector2(120, 115)
	press.pressed = true
	get_tree().root.push_input(press, true)
	await _real(0.75)
	check(TouchTips.is_showing() and TouchTips.shown_text() == "Says hello", "holding a finger on it shows the tip")
	var lift := InputEventScreenTouch.new()
	lift.index = 0
	lift.position = Vector2(120, 115)
	lift.pressed = false
	get_tree().root.push_input(lift, true)
	await _real(3.0)
	check(not TouchTips.is_showing(), "and it goes again")
	get_tree().root.push_input(press, true)
	await _real(0.2)
	get_tree().root.push_input(lift, true)
	await _real(0.6)
	check(not TouchTips.is_showing(), "a tap is not a long press")
	# Through the engine's own touch handling, with the mouse it emulates: a
	# long press reads the button and does not press it; a tap still presses.
	var presses: Array = [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	Input.parse_input_event(press)
	await _real(0.75)
	Input.parse_input_event(lift)
	await _real(0.2)
	check(presses[0] == 0, "a long press on a button does not press it (%d)" % presses[0])
	Input.parse_input_event(press)
	await _real(0.1)
	Input.parse_input_event(lift)
	await _real(0.2)
	check(presses[0] == 1, "a tap on it still does (%d)" % presses[0])
	layer.queue_free()


func _cart_minus() -> void:
	var panel: SupplyPanel = world.hud._supply_panel
	if not panel.visible:
		panel.toggle()
	panel.show_manual()
	panel.order.clear()
	panel.quantity = 1
	panel.add_ware(&"flour", 1)
	panel.add_ware(&"flour", 1)
	panel.refresh()
	var minus: Button = panel._wares[&"flour"]["minus"]
	check(minus.visible, "a ware on the cart shows its take-off button")
	check(not panel._wares[&"yeast"]["minus"].visible, "and one that is not, does not")
	minus.pressed.emit()
	check(int(panel.order.get(&"flour", 0)) == 1, "the button takes one off (%d left)" % int(panel.order.get(&"flour", 0)))
	minus.pressed.emit()
	panel.refresh()
	check(int(panel.order.get(&"flour", 0)) == 0 and not minus.visible, "and the last, and then hides")
	panel.toggle()
	await get_tree().process_frame


func _ledger() -> void:
	var hud: WorldHUD = world.hud
	world.customers.note_consumed(&"bread", 4)
	world.customers.note_consumed(&"beer", 2)
	hud.toggle_ledger()
	for i in range(3):
		await get_tree().process_frame
	var text: String = _texts(hud._details_panel)
	check(hud._details_panel.visible and text.contains("Profit so far"), "the Ledger opens on the money")
	check(not text.contains("fps") and not text.contains("draw calls") and not text.contains("stock:"),
		"with no developer readout in it")
	check(_count(hud._details_panel, "GoodsStrip") >= 1, "what sold today is pictured")
	var grid: GridContainer = _first(hud._details_panel, "GridContainer")
	check(grid != null and grid.get_child_count() > 0, "the larder is a grid of pictures (%d)" % (grid.get_child_count() if grid != null else 0))
	var bottom: float = hud._details_panel.get_global_rect().end.y
	var screen: float = get_viewport().get_visible_rect().size.y
	check(bottom <= screen + 1.0, "and it fits on the screen (bottom %.0f of %.0f)" % [bottom, screen])
	hud.toggle_ledger()
	check(not hud._dev_panel.visible, "the developer figures are not shown by default")
	hud.toggle_developer_figures()
	hud.refresh_stats()
	check(hud._dev_panel.visible and hud._stats_label.text.contains("fps"), "F3 shows them in a debug build")
	hud.toggle_developer_figures()


func _day_summary() -> void:
	var summary: DaySummary = world.hud._day_summary
	var entry: Dictionary = {"day": 1, "served": 6, "lost": 1, "purse": 2100, "profit": 100,
		"lines": {Ledger.Line.TAKINGS: 160, Ledger.Line.SUPPLIES: 60}}
	summary.show_day(entry, "UI Check Arms", null, [] as Array[Review], {}, {&"bread": 4, &"beer": 2})
	check(_count(summary, "GoodsStrip") >= 1, "the day summary pictures what sold")
	var pictured: int = 0
	for rect in _all(summary, "TextureRect"):
		if rect.texture != null:
			pictured += 1
	check(pictured >= 2 + 2, "and its money lines have pictures (%d pictures)" % pictured)
	summary.visible = false


func _keeper_menu() -> void:
	world.spawn_keeper()
	var bar: int = -1
	for i in range(world.build.grid.placements.size()):
		var e = world.build.grid.placements[i]
		if e != null and e["def"].id == &"bar_table" and e["built"]:
			bar = i
			break
	check(bar >= 0, "the house has a bar")
	if bar < 0:
		return
	var options: Array = world.keeper_controls.options_for(world.build.grid.placements[bar]["origin"])
	var missing: PackedStringArray = PackedStringArray()
	for option in options:
		if option["text"] != "Walk here" and not option.get("icon") is Texture2D:
			missing.append(option["text"])
	check(not options.is_empty() and missing.is_empty(), "every keeper option but walking has a picture%s" % (
		"" if missing.is_empty() else " (missing: %s)" % ", ".join(missing)))
	var menu := KeeperMenu.new()
	world.hud._hud.add_child(menu)
	menu.open(options, Vector2(400, 300), func(_o: Dictionary) -> void: pass)
	var drawn: int = 0
	for rect in _all(menu, "TextureRect"):
		if rect.texture != null:
			drawn += 1
	check(drawn == options.size() - 1, "and the menu draws them (%d of %d)" % [drawn, options.size() - 1])
	menu.queue_free()
	world.keeper_controls.close_menu()


func _texts(node: Node) -> String:
	var out: PackedStringArray = PackedStringArray()
	for label in _all(node, "Label"):
		out.append(label.text)
	return "\n".join(out)


func _all(node: Node, kind: String) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child.is_class(kind) or (child.get_script() != null and child.get_script().get_global_name() == kind):
			out.append(child)
		out.append_array(_all(child, kind))
	return out


func _count(node: Node, kind: String) -> int:
	return _all(node, kind).size()


func _first(node: Node, kind: String) -> Node:
	var found: Array = _all(node, kind)
	return found[0] if not found.is_empty() else null


func _real(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
