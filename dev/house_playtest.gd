extends Node

## A play-test of the sandbox's full test house, the way a player meets it:
## title screen, New game, Sandbox, the character creator, then a day and a
## half at full speed with every panel opened and every kind of thing
## inspected. A screenshot and a note at each step, and frame times at the end.
## Not a pass/fail test: a recording to look at. Run windowed:
##   godot --path . --resolution 1920x1080 res://dev/house_playtest.tscn -- <out dir>

var out_dir: String = "res://.verification/house_playtest"
var world: TavernWorld
var _log: PackedStringArray = PackedStringArray()
var _step: int = 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		_note("!! Gave up after 10 minutes.")
		_finish(1))
	if not GameState.begin_test_session():
		get_tree().quit(2)
		return
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	await get_tree().process_frame
	await get_tree().process_frame
	await _play()
	_finish(0)


func _play() -> void:
	get_tree().change_scene_to_file("res://src/ui/main_menu/main_menu.tscn")
	await _frames(20)
	var menu: Node = get_tree().current_scene
	await _shot("title", "Title screen")
	_press(menu, "New game")
	await _frames(15)
	_press(menu, "Sandbox")
	await _frames(10)
	await _shot("sandbox_card", "Sandbox chosen")
	_press(menu, "Create character")
	await _frames(20)
	await _shot("character", "Character creator before the tavern opens")
	var creator = menu.get("_character_creator")
	if creator == null or creator.accept_button == null:
		_note("!! The character creator did not open; buttons: %s" % ", ".join(_texts(menu)))
		return
	creator.accept_button.pressed.emit()
	for i in range(300):
		await get_tree().process_frame
		if get_tree().current_scene is TavernWorld:
			break
	world = get_tree().current_scene as TavernWorld
	if world == null:
		_note("!! The world never opened.")
		return
	await _frames(40)
	await _shot("arrival", "First look at the test house: %d staff, %dg" % [world.workers.size(), GameState.gold])

	# Close the briefing / checklist noise a player would close, then run.
	world.sim.speed = 4
	await _game_seconds(120.0)
	await _shot("morning", "Mid-morning at 5x: %s" % world.customers.summary())

	for panel in [["Staff", "staff"], ["Stores", "stores"], ["Ledger", "ledger"]]:
		if not _press(world.hud._hud, panel[0]):
			_note("!! No '%s' button on the bar" % panel[0])
		await _frames(12)
		await _shot("panel_" + panel[1], "%s panel open" % panel[0])
		world.hud.close_top_panel()
		await _frames(5)
	world.hud._production_panel.toggle()
	await _frames(12)
	await _shot("panel_production", "Production panel (P)")
	world.hud._production_panel.toggle()

	# Inspect one of each kind of thing.
	for role in [&"cook", &"waiter", &"farmer", &"fisherman"]:
		var w: Worker = PlayerActions.staff(world, role)
		if w != null:
			world.hud.inspector.show_pawn(w.pawn)
			world.rig.focus_on(w.pawn.global_position)
			await _frames(10)
			await _shot("inspect_" + String(role), "%s: %s" % [role, w.status_text()])
	for brain in world.customers.customers:
		if is_instance_valid(brain):
			world.hud.inspector.show_pawn(brain.pawn)
			world.rig.focus_on(brain.pawn.global_position)
			await _frames(10)
			await _shot("inspect_guest", "A guest: %s" % brain.status_text())
			break
	for id in [&"farm_plot", &"well", &"river_pump"]:
		for i in range(world.build.grid.placements.size()):
			var entry = world.build.grid.placements[i]
			if entry != null and entry["def"].id == id:
				world.hud.inspector.show_building(i)
				var t: Vector2i = entry["tiles"][0]
				world.rig.focus_on(Vector3(t.x, world.terrain.plot_height, t.y))
				await _frames(10)
				await _shot("inspect_" + String(id), "%s card" % id)
				break
	world.hud.inspector.clear()

	# Frame times over a stretch of the evening rush, camera on the hall.
	var hall: Rect2i = TestHouse.hall(world)
	var middle: Vector2 = Vector2(hall.position) + Vector2(hall.size) * 0.5
	world.rig.focus_on(Vector3(middle.x, world.terrain.plot_height, middle.y))
	await _game_seconds(300.0)
	var frames: Array[float] = []
	var last: int = Time.get_ticks_usec()
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
		if world.simulation_paused:
			PlayerActions.press(world.hud._day_summary, "Open tomorrow")
	frames.sort()
	_note("FRAMES %d over 20 s at 5x: median %.1f ms, p95 %.1f ms, worst %.1f ms; %d guests, %d staff" % [
		frames.size(), frames[frames.size() / 2], frames[int(frames.size() * 0.95)], frames[frames.size() - 1],
		world.customers.customers.size(), world.workers.size()])
	await _shot("evening", "Evening: %s" % world.customers.summary())

	# Through the night into day 2.
	var day: int = world.clock.day
	while world.clock.day == day:
		await get_tree().process_frame
		if world.simulation_paused:
			await _shot("day_summary", "Day %d closes" % world.clock.day)
			PlayerActions.press(world.hud._day_summary, "Open tomorrow")
			PlayerActions.press(world.hud._day_summary, "Keep trading")
	await _game_seconds(200.0)
	await _shot("day2", "Day 2 morning: %s; trouble: '%s'" % [world.customers.summary(), Trouble.diagnose(world)])
	var made: PackedStringArray = PackedStringArray()
	for id in world.generator.produced:
		made.append("%s %d" % [id, world.generator.produced[id]])
	_note("Made so far: %s" % ", ".join(made))
	_note("Purse %dg; ledger history %s" % [GameState.gold, str(world.ledger.history.map(func(e): return e["profit"]))])


func _game_seconds(amount: float) -> void:
	var until: float = world.sim.sim_time + amount
	while world.sim.sim_time < until:
		await get_tree().process_frame
		if world.simulation_paused:
			PlayerActions.press(world.hud._day_summary, "Open tomorrow")
			PlayerActions.press(world.hud._day_summary, "Keep trading")


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _press(root: Node, text: String) -> bool:
	return PlayerActions.press(root, text)


func _texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for b in root.find_children("*", "Button", true, false):
		if b.is_visible_in_tree():
			out.append(b.text)
	return out


func _shot(name: String, what: String) -> void:
	_step += 1
	await RenderingServer.frame_post_draw
	var path: String = out_dir.path_join("%02d_%s.png" % [_step, name])
	get_viewport().get_texture().get_image().save_png(path)
	var trouble: String = Trouble.diagnose(world) if world != null else ""
	_note("%02d %s: %s%s" % [_step, name, what, "" if trouble.is_empty() else "  [advice: %s]" % trouble])


func _note(text: String) -> void:
	print(text)
	_log.append(text)


func _finish(code: int) -> void:
	var f := FileAccess.open(out_dir.path_join("log.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log))
	get_tree().quit(code)
