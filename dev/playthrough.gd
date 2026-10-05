extends Node

## A first session, played the way a new player would: from the title screen,
## through the real buttons, one decision at a time, with a screenshot and a
## note of what the game was saying at every step.
##
## Not a test -- it asserts nothing. It is a recording, for designing the
## tutorial and finding where a newcomer gets stuck. Run windowed:
##   godot --path . --resolution 1600x900 res://dev/playthrough.tscn -- <out dir>
##
## Buttons are pressed through their own `pressed` signal and keys are sent as
## real key events. Clicks on the world make the same calls the input layer
## makes for a click on a tile, so the run never takes over the real mouse.

var out_dir: String = "res://.verification/playthrough"
var world: TavernWorld
var _step: int = 0
var _log: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(540.0).timeout.connect(func() -> void:
		_note("!! Gave up after 9 minutes.")
		_write_log()
		get_tree().quit(1))
	if not GameState.begin_test_session():
		get_tree().quit(2)
		return
	# Outlive the scene changes: the title screen and the world replace the
	# current scene, and this node has to watch both.
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	await get_tree().process_frame
	await get_tree().process_frame
	await _play()
	_write_log()
	get_tree().quit()


# --- the session ---------------------------------------------------------------

func _play() -> void:
	get_tree().change_scene_to_file("res://src/ui/main_menu/main_menu.tscn")
	await _frames(20)
	var menu: Node = get_tree().current_scene
	await _shot("title", "The title screen. Entries: %s" % ", ".join(_button_texts(menu)))
	_press(menu, "New game")
	await _frames(15)
	await _shot("new_game", "New game page, demo scenario selected by default.")
	_press(menu, "Sandbox")
	await _frames(10)
	await _shot("sandbox", "Sandbox chosen: name, seed and slot appear.")
	_press(menu, "Open the doors")
	await _frames(10)
	await _shot("character", "Choose the tavern keeper before opening a new tavern.")
	_press(menu, "Create character")
	for i in range(240):
		await get_tree().process_frame
		if get_tree().current_scene is TavernWorld:
			break
	world = get_tree().current_scene as TavernWorld
	if world == null:
		_note("!! The world never opened.")
		return
	await _frames(30)
	await _shot("arrival", "First look at the plot.")

	# The checklist says: floors first.
	_press(world.hud._hud, "Build")
	await _frames(10)
	await _shot("build_bar", "The build bar is open.")
	var o: Vector2i = world.plot.position + Vector2i(3, world.plot.size.y - 14)
	# The hint now says "a room about 10 x 8": do what it says.
	_select("wood_floor")
	world.build.update_hover(o, true)
	world.build.begin_drag(o)
	world.build.update_hover(o + Vector2i(9, 7), true)
	_note("  while dragging, the build bar says: %s" % _last_status())
	world.commit_area_build()
	await _frames(10)
	await _shot("floor_laid", "Dragged a 10 x 8 wood floor, as the hint now suggests.")

	# Walls: one drag round the room, then a door clicked into the wall.
	_select("timber_wall")
	var before: int = world.build.grid.live_count()
	world.build.update_hover(o, true)
	world.build.begin_drag(o)
	world.build.update_hover(o + Vector2i(9, 7), true)
	_note("  while dragging, the build bar says: %s" % _last_status())
	world.commit_area_build()
	_note("Walls went down in one drag: %d pieces." % (world.build.grid.live_count() - before))
	_select("door")
	_click(o + Vector2i(4, 7))
	await _frames(10)
	await _shot("walls", "Walls dragged round the room, and a door clicked into the south wall.")

	# Dining.
	for spot in [Vector2i(2, 2), Vector2i(2, 5)]:
		_select("table")
		_click(o + spot)
		_select("chair")
		_click(o + spot + Vector2i(-1, 0))
		_click(o + spot + Vector2i(2, 0))
	# Kitchen and storage.
	_select("prep_table")
	_click(o + Vector2i(7, 1))
	_select("oven")
	_click(o + Vector2i(7, 3))
	_select("brewing_vat")
	_click(o + Vector2i(6, 5))
	_select("storage_shelf")
	_click(o + Vector2i(1, 6))
	_click(o + Vector2i(6, 1))
	_select("sink")
	_click(o + Vector2i(4, 1))
	world.build.mode = BuildController.Mode.OFF
	world.hud._toggle_build_bar()
	await _frames(10)
	await _shot("furnished", "Everything placed. Gold left: %dg." % GameState.gold)

	# Let the porter build it, at the fastest speed.
	_key(KEY_4)
	await _frames(2)
	var started: float = world.sim.sim_time
	await _until(func() -> bool: return _blueprints() == 0, 900.0)
	_note("Construction by one porter took %.0f game seconds (%s)." % [world.sim.sim_time - started, world.clock.clock_text()])
	_key(KEY_SPACE)
	await _frames(10)
	await _shot("built", "The building is up. Paused with Space.")

	# Supplies through the order screen.
	_press(world.hud._hud, "Stores")
	world.hud._supply_panel.show_manual()
	await _frames(10)
	await _shot("order_screen", "The order screen with the standard bundle.")
	_press(world.hud._supply_panel, "Buy cart")
	await _frames(10)
	await _shot("delivered", "Delivery arrived in the yard.")

	# Staff panel.
	_key(KEY_K)
	await _frames(10)
	await _shot("staff", "Staff panel: hire cards and the priority grid.")
	_key(KEY_K)

	# Production.
	_key(KEY_P)
	await _frames(10)
	await _shot("production", "Production panel: standing orders for each recipe.")
	_key(KEY_P)

	# Run the day and watch.
	_key(KEY_1)
	await _seconds(60.0)
	await _shot("opening_hour", "An hour of trade at 1x.")
	_key(KEY_4)
	await _seconds(120.0)
	await _shot("midday", "Midday at 5x.")
	_hover_first_guest()
	await _frames(20)
	await _shot("hover_guest", "Pointing at a guest.")
	_inspect_first(&"waiter")
	await _frames(10)
	await _shot("inspect_waiter", "The waiter in the inspector.")
	world.hud.inspector.clear()
	await _until(func() -> bool: return world.simulation_paused, 900.0)
	await _frames(20)
	await _shot("day_summary", "The day summary.")
	_press(world.hud._day_summary, "Open tomorrow")
	await _frames(10)

	# Leave through the pause menu.
	_key(KEY_ESCAPE)
	await _frames(10)
	await _shot("pause", "Esc: the pause menu.")
	_press(world.hud.pause_menu, "Save game")
	await _frames(10)
	await _shot("saved", "Saved from the pause menu.")


# --- player actions ------------------------------------------------------------

func _select(id: StringName) -> void:
	var def: BuildingDef = BuildingCatalog.get_def(id)
	if world.hud._build_bar != null and world.hud._build_bar._item_buttons.has(id):
		var category: String = def.category
		world.hud._build_bar._show_category(category)
		world.hud._build_bar._item_buttons[id].pressed.emit()
	else:
		world.build.select(def)


## A click on a tile in build mode, as the input layer makes it. Judged by
## what now stands on the tile: a door replacing a wall leaves the count alone.
func _click(tile: Vector2i) -> bool:
	var before: int = world.build.grid.placement_at(tile)
	var id_before: StringName = world.build.grid.placements[before]["def"].id if before >= 0 else &""
	world.build.update_hover(tile, true)
	world.commit_build_action()
	var after: int = world.build.grid.placement_at(tile)
	var placed: bool = after >= 0 and (after != before or world.build.grid.placements[after]["def"].id != id_before)
	if not placed:
		_note("  refused at %s: %s" % [tile, _last_status()])
	return placed


func _drag(from: Vector2i, to: Vector2i) -> void:
	world.build.update_hover(from, true)
	world.build.begin_drag(from)
	world.build.update_hover(to, true)
	world.commit_area_build()


func _key(code: int) -> void:
	for pressed in [true, false]:
		var event: InputEvent
		if code == KEY_ESCAPE:
			var action := InputEventAction.new()
			action.action = "ui_cancel"
			action.pressed = pressed
			event = action
		else:
			var key := InputEventKey.new()
			key.keycode = code
			key.physical_keycode = code
			key.pressed = pressed
			event = key
		Input.parse_input_event(event)
		await get_tree().process_frame


func _press(root: Node, text: String) -> bool:
	var b: Button = _find_button(root, text)
	if b == null:
		_note("!! No button '%s' to press." % text)
		return false
	if b.disabled:
		_note("!! '%s' is disabled: %s" % [text, b.tooltip_text])
		return false
	b.pressed.emit()
	return true


func _hover_first_guest() -> void:
	for brain in world.customers.customers:
		if is_instance_valid(brain):
			world.hud.hover.show_subject({"kind": WorldStats.Kind.PAWN, "pawn": brain.pawn})
			world.hud.hover.pin_at(world.rig.camera.unproject_position(brain.pawn.global_position))
			return
	_note("No guest to point at.")


func _inspect_first(role_id: StringName) -> void:
	for worker in world.workers:
		if worker.role != null and worker.role.id == role_id:
			world.hud.inspector.show_pawn(worker.pawn)
			return


# --- observing -----------------------------------------------------------------

func _shot(name: String, what: String) -> void:
	await RenderingServer.frame_post_draw
	_step += 1
	var file: String = "%02d_%s.png" % [_step, name]
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	_note("[%s] %s" % [file, what])
	if world != null and is_instance_valid(world):
		_note("    clock %s day %d  gold %dg  speed %d  staff %d  guests %d" % [
			world.clock.clock_text(), world.clock.day, GameState.gold, world.sim.speed,
			world.workers.size(), world.customers.customers.size()])
		var current: String = _current_objective()
		if not current.is_empty():
			_note("    checklist: %s" % current)
		var trouble: String = Trouble.diagnose(world)
		if not trouble.is_empty():
			_note("    trouble line: %s" % trouble)
		if world.hud._flash_label != null and world.hud._flash_label.modulate.a > 0.05:
			_note("    flash: %s" % world.hud._flash_label.text)
		var doing: PackedStringArray = PackedStringArray()
		for worker in world.workers:
			doing.append("%s: %s" % [worker.role.title if worker.role else "?", worker.status_text()])
		_note("    staff: %s" % " | ".join(doing))
		var guests: PackedStringArray = PackedStringArray()
		for brain in world.customers.customers:
			if is_instance_valid(brain):
				guests.append(brain.status_text())
		if not guests.is_empty():
			_note("    guests: %s" % " | ".join(guests))


func _current_objective() -> String:
	if world.objectives == null:
		return ""
	for objective in world.objectives.list:
		if not objective.done:
			return "%s -- %s" % [objective.text, objective.hint]
	return "(all done)"


func _last_status() -> String:
	var bar: BuildBar = world.hud._build_bar
	return bar._status.text if bar != null and bar.get("_status") != null else "?"


func _blueprints() -> int:
	var n: int = 0
	for entry in world.build.grid.placements:
		if entry != null and not entry["built"]:
			n += 1
	return n


func _note(text: String) -> void:
	_log.append(text)
	print(text)


func _write_log() -> void:
	var f := FileAccess.open(out_dir.path_join("log.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log))


# --- helpers -------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## Game seconds, at whatever speed the player has chosen.
func _seconds(amount: float) -> void:
	var until: float = world.sim.sim_time + amount
	while world.sim.sim_time < until and not world.simulation_paused:
		await get_tree().process_frame


func _until(done: Callable, max_game_seconds: float) -> void:
	var limit: float = world.sim.sim_time + max_game_seconds
	# Fast-forward while waiting, the way a player holds 5x through the dull bits.
	world.sim.turbo_steps = 20
	while not done.call() and world.sim.sim_time < limit:
		await get_tree().process_frame
		if world.simulation_paused and not done.call():
			break
	world.sim.turbo_steps = 0


func _find_button(root: Node, text: String) -> Button:
	if root is Button and (root.text == text or root.text.begins_with(text)) and root.is_visible_in_tree():
		return root
	for child in root.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null


func _button_texts(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if root is Button and root.is_visible_in_tree() and not root.text.is_empty():
		out.append(root.text.replace("\n", " "))
	for child in root.get_children():
		out.append_array(_button_texts(child))
	return out

