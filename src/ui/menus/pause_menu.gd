class_name PauseMenu
extends Control

## Esc in the tavern: the game stops, and the player can resume, save, change
## settings, or leave -- and is asked before leaving with unsaved progress.
##
## It used to be that Esc with nothing open went straight to the title screen,
## unsaved, with no question asked. One key from losing an evening's work.

var world  ## TavernWorld
var _s: float = 1.0
var _where: Label
var _status: Label
var _save: Button
var _resume: Button
var _busy: bool = false


func setup(p_world) -> void:
	world = p_world
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameSettings.changed.connect(func() -> void:
		if visible:
			_build()
	)


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_build()
	visible = true
	world.sim.menu_held = true
	if world.rig != null:
		world.rig.locked = true
	if world.hud != null and world.hud.hover != null:
		world.hud.hover.dismiss()
	AudioDirector.play("ui_back")
	_resume.call_deferred("grab_focus")


func close() -> void:
	if not visible:
		return
	visible = false
	world.sim.menu_held = false
	if world.rig != null:
		world.rig.locked = false
	AudioDirector.play("ui_click")


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_s = TavernTheme.scale_for_control(self)
	theme = TavernTheme.build(_s)
	add_child(UiKit.dim(0.5))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(_s))
	panel.custom_minimum_size = Vector2(420.0, 0.0) * _s
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(6.0 * _s))
	panel.add_child(column)

	column.add_child(UiKit.heading("Paused", _s, 30.0))
	_where = UiKit.caption("", _s, 15.0)
	column.add_child(_where)
	column.add_child(UiKit.rule(_s))

	_resume = UiKit.menu_button("Resume", _s, "Back to the tavern (Esc)")
	_resume.pressed.connect(close)
	column.add_child(_resume)
	_save = UiKit.menu_button("Save game", _s)
	_save.pressed.connect(_on_save)
	column.add_child(_save)
	var settings: Button = UiKit.menu_button("Settings", _s)
	settings.pressed.connect(_on_settings)
	column.add_child(settings)
	var menu: Button = UiKit.menu_button("Main menu", _s)
	menu.pressed.connect(func() -> void: _leave(false))
	column.add_child(menu)
	var quit: Button = UiKit.menu_button("Quit to desktop", _s)
	quit.pressed.connect(func() -> void: _leave(true))
	column.add_child(quit)

	column.add_child(UiKit.rule(_s))
	_status = UiKit.caption("", _s, 13.0)
	column.add_child(_status)
	_refresh()


func _refresh() -> void:
	if world == null or _where == null:
		return
	_where.text = "%s  ·  Day %d, %s  ·  %dg" % [GameState.tavern_name, world.clock.day,
		world.clock.clock_text(), GameState.gold]
	var can_save: bool = GameState.active_slot >= 0
	_save.disabled = not can_save
	_save.tooltip_text = "Save to slot %d" % (GameState.active_slot + 1) if can_save else "This tavern has no save slot"
	if not can_save:
		_status.text = "This tavern cannot be saved."
	elif world.saved_at_msec <= 0:
		_status.text = "Not saved yet."
	elif world.has_unsaved_progress():
		_status.text = "Unsaved progress since %s." % _minutes_ago(world.saved_at_msec)
	else:
		_status.text = "Saved %s. Nothing unsaved." % _minutes_ago(world.saved_at_msec)


func _minutes_ago(msec: int) -> String:
	var minutes: int = (Time.get_ticks_msec() - msec) / 60000
	return "just now" if minutes < 1 else "%d min ago" % minutes


func _on_save() -> void:
	if world.save_now():
		world.hud.flash("Saved")
		AudioDirector.play("ui_start")
	_refresh()


func _on_settings() -> void:
	var screen := SettingsScreen.open(self)
	await screen.closed
	if is_instance_valid(_resume) and visible:
		_resume.grab_focus()


## To the title screen, or out of the game. Asks first if anything would be lost.
func _leave(quit: bool) -> void:
	if _busy:
		return
	var where: String = "quit" if quit else "leave"
	if GameState.active_slot >= 0 and world.has_unsaved_progress():
		_busy = true
		var dialog := ModalDialog.ask(self, "Save before you %s?" % where,
			"%s has progress since the last save. It will be lost if you %s without saving." % [
				GameState.tavern_name, where],
			[["save", "Save and %s" % where, "primary"], ["discard", "Don't save", "danger"],
			["cancel", "Cancel", ""]])
		var answer: String = await dialog.chosen
		_busy = false
		if answer == "cancel":
			if is_instance_valid(_resume):
				_resume.grab_focus()
			return
		if answer == "save" and not world.save_now():
			_refresh()
			return
	elif quit:
		_busy = true
		var dialog := ModalDialog.ask(self, "Quit to desktop?", "Your tavern is saved.",
			[["quit", "Quit", "primary"], ["cancel", "Cancel", ""]])
		var answer: String = await dialog.chosen
		_busy = false
		if answer != "quit":
			if is_instance_valid(_resume):
				_resume.grab_focus()
			return
	if quit:
		SceneRouter.quit_game()
	else:
		world._go_back()


func _input(event: InputEvent) -> void:
	if not visible or _busy:
		return
	# Settings and dialogs are children, and see Esc first.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	if visible and Engine.get_process_frames() % 30 == 0:
		_refresh()
