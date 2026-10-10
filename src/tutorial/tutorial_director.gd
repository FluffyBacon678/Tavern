class_name TutorialDirector
extends Node

## Runs the tutorial in a live game: one instruction at a time from
## TutorialPlan, a highlight on what to use, time paused or running as the step
## needs, and the next step the moment the world says this one is done.
##
## Nothing is ticked by pressing Next. Done-conditions read the world, so a
## player who does things their own way still moves on, and one who has not
## done the thing does not.

signal finished

## How often the world is asked whether the step is done, in real seconds.
const CHECK_EVERY: float = 0.25

var world  ## TavernWorld
var steps: Array[TutorialStep] = []
var index: int = 0
var ctx: Dictionary = {}

var _panel: PanelContainer
var _lesson: Label
var _text: Label
var _why: Label
var _progress: Label
var _show: Button
var _skip: Button
var _tiles_marker: SelectionMarker
var _pawn_marker: SelectionMarker
var _pulse: Tween
var _pulsed: Button
var _check_timer: float = 0.0
var _complete: bool = false


func setup(p_world, start_at: int = 0) -> void:
	world = p_world
	steps = TutorialPlan.steps()
	index = clampi(start_at, 0, steps.size())
	_tiles_marker = SelectionMarker.new()
	_tiles_marker.name = "TutorialArea"
	_tiles_marker.set_colour(Color(TavernTheme.CANDLE, 0.9))
	world.add_child(_tiles_marker)
	_pawn_marker = SelectionMarker.new()
	_pawn_marker.name = "TutorialPerson"
	_pawn_marker.set_colour(Color(TavernTheme.CANDLE, 0.95))
	world.add_child(_pawn_marker)
	_build_panel()
	_begin()


func current() -> TutorialStep:
	return steps[index] if index < steps.size() else null


func is_complete() -> bool:
	return _complete


# --- the panel ------------------------------------------------------------------

func _build_panel() -> void:
	var hud_root: Control = world.hud._hud
	var s: float = TavernTheme.scale_for_control(hud_root) * 0.8
	_panel = PanelContainer.new()
	_panel.name = "TutorialPanel"
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(s / 0.8 * 0.7, 0.96))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.custom_minimum_size = Vector2(380.0 * s / 0.8, 0.0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -16.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(_panel)
	# Beneath the day summary and the pause menu, over the working panels.
	var summary: Node = world.hud._day_summary
	if summary != null:
		hud_root.move_child(_panel, summary.get_index())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(6.0 * s))
	_panel.add_child(box)
	_lesson = UiKit.heading("", s, 15.0)
	box.add_child(_lesson)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 340.0 * s / 0.8
	_text.add_theme_font_size_override("font_size", int(17.0 * s / 0.8))
	_text.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	box.add_child(_text)
	_why = UiKit.caption("", s / 0.8, 13.0)
	box.add_child(_why)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8.0 * s))
	box.add_child(row)
	_progress = UiKit.caption("", s / 0.8, 12.0)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_progress)
	_show = UiKit.button("Show me", s / 0.8 * 0.8)
	_show.pressed.connect(show_me)
	row.add_child(_show)
	_skip = UiKit.button("Skip", s / 0.8 * 0.8)
	_skip.tooltip_text = "Move on without doing this step"
	_skip.pressed.connect(skip)
	row.add_child(_skip)


## Keep the panel where the checklist would be: under the top bar.
func _place_panel() -> void:
	if _panel != null:
		_panel.offset_top = world.hud._below_top


# --- steps -------------------------------------------------------------------------

func _begin() -> void:
	_clear_highlight()
	_place_panel()
	var step: TutorialStep = current()
	if step == null:
		_finish()
		return
	ctx["construction_practice"] = []
	if step.begin.is_valid():
		step.begin.call(world, ctx)
	var lesson_number: int = TutorialPlan.LESSONS.find(step.lesson) + 1
	var in_lesson: Array = steps.filter(func(s: TutorialStep) -> bool: return s.lesson == step.lesson)
	_lesson.text = "TUTORIAL  ·  %d of %d  ·  %s" % [lesson_number, TutorialPlan.LESSONS.size(), step.lesson.to_upper()]
	_text.text = step.text
	if not ctx["construction_practice"].is_empty():
		var names: PackedStringArray = PackedStringArray()
		for alternatives in ctx["construction_practice"]:
			names.append(BuildingCatalog.get_def(alternatives[0]).display_name)
		_text.text = "These are already in place. Practise by placing one more of each anywhere on your land: %s." % ", ".join(names)
	_why.text = step.why
	_progress.text = "Step %d of %d in this lesson" % [in_lesson.find(step) + 1, in_lesson.size()]
	# Paused while there is something to do; running while there is something
	# to watch. The player can still change the speed; this only sets the start.
	if step.pace == TutorialStep.Pace.PAUSED:
		world.sim.speed = 0
	elif world.sim.speed == 0:
		world.sim.speed = 1
		world.hud.flash("Time is running. Press %s for 5x, %s to pause." % [KeyBindings.text_for("speed_4").split(" / ")[0], KeyBindings.text_for("pause").split(" / ")[0]], 3.0)
	_highlight(step.resolved_highlight(world))
	_show.visible = not step.resolved_highlight(world).is_empty()


func advance() -> void:
	if current() == null:
		return
	AudioDirector.play("ui_start")
	index += 1
	_begin()


func skip() -> void:
	AudioDirector.play("ui_back")
	index += 1
	_begin()


func _finish() -> void:
	_complete = true
	_clear_highlight()
	_lesson.text = "TUTORIAL COMPLETE"
	_text.text = "You have used every part of the tavern. Keep playing here, or start your own from the main menu."
	_why.text = "Esc opens the pause menu at any time."
	_progress.text = ""
	_show.visible = false
	_skip.text = "Close"
	for connection in _skip.pressed.get_connections():
		_skip.pressed.disconnect(connection["callable"])
	_skip.pressed.connect(func() -> void: _panel.visible = false)
	finished.emit()


func _process(delta: float) -> void:
	if world == null or _complete:
		return
	_place_panel()
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CHECK_EVERY
	var step: TutorialStep = current()
	if step != null and step.done.is_valid() and step.done.call(world, ctx):
		world.hud.flash("Done: %s" % step.text.split(".")[0], 1.6)
		advance()
		return
	# Gone ahead: building straight away left a newcomer reading "Move the
	# view" for as long as they never touched the camera. Every step the player
	# has outgrown is passed together, before the next one sets the pace.
	if step != null and step.moved_on.is_valid() and step.moved_on.call(world, ctx):
		while current() != null and current().moved_on.is_valid() and current().moved_on.call(world, ctx):
			index += 1
		_begin()


# --- highlights ----------------------------------------------------------------------

func _highlight(target: Dictionary) -> void:
	if target.has("tiles"):
		var rect: Rect2i = target["tiles"]
		var cells: Array = []
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
		_tiles_marker.frame_tiles(cells, world.terrain.plot_height)
	if target.has("role"):
		var worker: Worker = PlayerActions.staff(world, target["role"])
		if worker != null:
			_pawn_marker.follow_pawn(worker.pawn)
	if target.has("button"):
		_pulsed = PlayerActions.find_button(world.hud._hud, String(target["button"]))
		if _pulsed != null:
			_pulse = create_tween().set_loops()
			_pulse.tween_property(_pulsed, "modulate", Color(1.6, 1.35, 0.8), 0.45)
			_pulse.tween_property(_pulsed, "modulate", Color.WHITE, 0.45)


func _clear_highlight() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	if is_instance_valid(_pulsed):
		_pulsed.modulate = Color.WHITE
	_pulsed = null
	if _tiles_marker != null:
		_tiles_marker.clear()
	if _pawn_marker != null:
		_pawn_marker.clear()


## Point the camera at what this step is about.
func show_me() -> void:
	var target: Dictionary = current().resolved_highlight(world) if current() != null else {}
	if target.has("tiles"):
		var rect: Rect2i = target["tiles"]
		var middle: Vector2 = Vector2(rect.position) + Vector2(rect.size) * 0.5
		world.rig.focus_on(Vector3(middle.x, world.terrain.plot_height, middle.y))
	elif target.has("role"):
		var worker: Worker = PlayerActions.staff(world, target["role"])
		if worker != null:
			world.rig.focus_on(worker.pawn.global_position)
	elif target.has("button") and is_instance_valid(_pulsed) and _pulsed.focus_mode != Control.FOCUS_NONE:
		# Toolbar buttons already pulse. They opt out of keyboard focus so
		# Space keeps pausing time instead of activating the last clicked button.
		_pulsed.grab_focus()
