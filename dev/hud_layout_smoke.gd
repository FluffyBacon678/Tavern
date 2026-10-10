extends Node

## Layout-only smoke test. Headless resizing works in Godot 4.7.2 on Windows;
## both Window size and viewport aspect are still probed before testing.
## Fresh worlds test initial layout. The final case deliberately keeps one HUD
## alive across a resize. No production controls are repositioned by this test.
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1440, 900),
	Vector2i(1280, 800), Vector2i(1024, 768), Vector2i(2560, 1080),
]
const WORLD_SCENE := "res://src/world/world3d/world_3d.tscn"
var failures: int = 0
var skipped: int = 0
var world: TavernWorld


func check(ok: bool, message: String) -> void:
	TestOutput.check_line(ok, message)
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	GameState.world_seed = 12345
	var started: int = Time.get_ticks_msec()
	get_window().mode = Window.MODE_WINDOWED
	if DisplayServer.get_name() == "headless":
		for size in [Vector2i(1280, 720), Vector2i(1024, 768)]:
			get_window().size = size
			await _settle()
			if not _size_honoured(size):
				print("ERROR: HUD layout resizing is not honoured headless; run this scene windowed.")
				print("Requested %s, actual window %s, viewport %s" % [size, get_window().size, get_viewport().get_visible_rect()])
				get_tree().quit(2)
				return
		print("NOTE: headless Window and viewport resizing verified at 16:9 and 4:3.")
	for level in [false, true]:
		for size in SIZES:
			var label: String = "%dx%d%s" % [size.x, size.y, " level briefing" if level else ""]
			if await _new_world(size, level, label):
				_measure(label, level)
	# The empty opening hides fish and has a short staff line. The populated
	# test house must fit too, including every stock and reputation caption.
	for size in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1920, 1080)]:
		var label: String = "%dx%d full house" % [size.x, size.y]
		if await _new_world(size, false, label, true):
			_measure(label, false)
			await _busiest_header(label)
	if await _new_world(Vector2i(1920, 1080), false, "live resize source"):
		_measure("live resize source 1920x1080", false)
		if await _resize(Vector2i(1024, 768), "live resize 1920x1080 -> 1024x768"):
			_measure("live resize 1920x1080 -> 1024x768", false)
	await _free_world()
	print("NOTE: %d shape(s) skipped; elapsed %.2fs." % [skipped, float(Time.get_ticks_msec() - started) / 1000.0])
	print("HUD LAYOUT SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _settle() -> void:
	for frame in range(5):
		await get_tree().process_frame


func _size_honoured(requested: Vector2i) -> bool:
	var view: Vector2 = get_viewport().get_visible_rect().size
	return get_window().size == requested and view.y > 0.0 and absf(view.x / view.y - float(requested.x) / requested.y) < 0.002


func _resize(size: Vector2i, label: String) -> bool:
	get_window().size = size
	await _settle()
	print("SIZE: %s requested=%s actual=%s viewport=%s" % [label, size, get_window().size, get_viewport().get_visible_rect()])
	if not _size_honoured(size):
		skipped += 1
		print("SKIP: %s: requested shape was not honoured; no layout pass claimed." % label)
		return false
	return true


func _free_world() -> void:
	if is_instance_valid(world):
		world.queue_free()
		world = null
		await get_tree().process_frame


func _new_world(size: Vector2i, level: bool, label: String, full_house: bool = false) -> bool:
	await _free_world()
	if not await _resize(size, label):
		return false
	GameState.world_seed = 12345
	GameState.pending_level = &"wayfarers_rest" if level else &""
	GameState.full_house_start = full_house
	GameState.start_new_run("Layout test", 12345, GameState.MAX_SLOTS - 1, true)
	SimWait.seed_run()
	world = load(WORLD_SCENE).instantiate()
	add_child(world)
	SimWait.hold(world)
	await _settle()
	return true


## Ancestors identify the anonymous header and bar without assuming child order.
## The header with the longest figures a big tavern reaches stays one row. With
## the people line and the standing side by side, "3 waiting" at lunchtime
## pushed the stars onto a second row at 1280 x 720.
func _busiest_header(label: String) -> void:
	var hud: WorldHUD = world.hud
	hud.set_physics_process(false)
	hud._title_label.text = "The Prancing Pony of the Western Marches"
	hud._staff_label.text = "120 staff, 99 idle\n120 guests, 99 waiting"
	hud._gold_label.text = "123456g"
	hud._today_label.text = "-12345g today"
	hud._reputation_label.text = "Respectable"
	for i in range(3):
		await get_tree().process_frame
	var rows: Dictionary = {}
	for child in hud._header.get_child(0).get_children():
		if child is Control and child.visible:
			rows[int(child.position.y) / 40] = true
	check(rows.size() == 1, "%s: the busiest header stays one row (%d rows, %.0f tall)" % [label, rows.size(), hud._header.size.y])
	hud.set_physics_process(true)
	hud.refresh_stats()


## Some other visible panel of the opening layout sits on this point.
func _covered_by_other(hud: WorldHUD, point: Vector2) -> bool:
	for child in hud._hud.get_children():
		if child is Control and child.is_visible_in_tree() and child.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and child != hud._priority_panel and child.get_global_rect().has_point(point):
			return true
	return false


func _top_control(control: Control, root: Control) -> Control:
	while control.get_parent() != root and control.get_parent() is Control:
		control = control.get_parent()
	return control


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button and child.is_visible_in_tree():
			result.append(child)
		result.append_array(_buttons(child))
	return result


func _button_name(button: Button) -> String:
	if button is SpeedButton:
		return "pause" if button.speed == 0 else "%dx" % button.speed
	return button.text if not button.text.is_empty() else button.tooltip_text


func _header_labels(node: Node) -> Array[Label]:
	var result: Array[Label] = []
	for child in node.get_children():
		if child is Label and child.is_visible_in_tree() and not child.text.is_empty():
			result.append(child)
		result.append_array(_header_labels(child))
	return result


func _inside(control: Control, view: Rect2) -> bool:
	return control != null and control.is_visible_in_tree() and control.get_global_rect().has_area() and view.encloses(control.get_global_rect())


func _measure(label: String, level: bool) -> void:
	var hud: WorldHUD = world.hud
	var root: Control = hud._hud
	var view: Rect2 = get_viewport().get_visible_rect()
	# Rects are canvas coordinates. Convert extents to actual window pixels for
	# click targets; canvas_items/expand may render a logical 1280-wide viewport.
	var pixels_per_unit: Vector2 = Vector2(get_window().size) / view.size
	var buttons: Array[Button] = _buttons(root)
	for caption in _header_labels(hud._header):
		check(view.encloses(caption.get_global_rect()) and hud._header.get_global_rect().encloses(caption.get_global_rect()),
			"%s: header text '%s' fits inside the header and viewport" % [label, caption.text])
	check(not buttons.is_empty(), "%s: HUD contains visible buttons" % label)
	for button in buttons:
		var rect: Rect2 = button.get_global_rect()
		var pixels: Vector2 = rect.size * pixels_per_unit
		check(view.encloses(rect), "%s: '%s' button %s (x %.1f..%.1f, y %.1f..%.1f, view %.1fx%.1f)" % [
			label, _button_name(button), "fits" if view.encloses(rect) else "is off screen",
			rect.position.x, rect.end.x, rect.position.y, rect.end.y, view.size.x, view.size.y])
		check(pixels.x >= 24.0 and pixels.y >= 24.0, "%s: '%s' button target %.1fx%.1f px >= 24x24" % [label, _button_name(button), pixels.x, pixels.y])
	check(_inside(hud._paused_label, view), "%s: paused label visible and on screen" % label)
	check(_inside(hud._clock_label, view) and not hud._clock_label.text.is_empty(), "%s: clock text visible and on screen" % label)
	check(hud._speed_buttons.size() == SimClock.SPEEDS.size(), "%s: every speed control exists (pause and %d speeds)" % [label, SimClock.SPEEDS.size() - 1])
	for button in hud._speed_buttons:
		check(_inside(button, view), "%s: '%s' speed control visible and on screen" % [label, _button_name(button)])
	# The hover card asks the HUD, not Godot's hovered control, which only
	# changes when the mouse moves: a panel opened from the keyboard under a
	# resting pointer let the card for the field behind it draw over the panel.
	if not level:
		var staff: Control = hud._priority_panel
		var was_open: bool = staff.visible
		if not was_open:
			staff.toggle()
		var inside: Vector2 = staff.get_global_rect().get_center()
		check(hud.covers_point(inside), "%s: the open staff window stops the hover card" % label)
		staff.toggle()
		check(not staff.visible and (not hud.covers_point(inside) or _covered_by_other(hud, inside)),
			"%s: closed again, the same spot is open ground" % label)
		if was_open:
			staff.toggle()
		check(hud.covers_point(hud._header.get_global_rect().get_center()), "%s: the header stops the hover card" % label)
	var panels: Dictionary = {
		"header": _top_control(hud._clock_label, root),
		"button bar": _top_control(hud._mode_button, root),
		"checklist": hud._objectives_panel,
		"paused label": hud._paused_label,
	}
	if level:
		check(_inside(hud._briefing_panel, view), "%s: level briefing visible and on screen" % label)
		panels["briefing"] = hud._briefing_panel
	# Include any other visible top-level panels without comparing a panel to
	# its own children. Modal/closed panels are not part of the opening layout.
	for child in root.get_children():
		if child is PanelContainer and child.is_visible_in_tree() and not panels.values().has(child):
			panels["trouble" if child == hud._trouble_panel else String(child.name)] = child
	var names: Array = panels.keys()
	for i in range(names.size()):
		var a: Control = panels[names[i]]
		if a == null or not a.is_visible_in_tree():
			continue
		for j in range(i + 1, names.size()):
			var b: Control = panels[names[j]]
			if b == null or not b.is_visible_in_tree():
				continue
			var overlap: Rect2 = a.get_global_rect().intersection(b.get_global_rect())
			check(not overlap.has_area(), "%s: '%s' and '%s' %s" % [label, names[i], names[j],
				"overlap at %s" % overlap if overlap.has_area() else "do not overlap"])
