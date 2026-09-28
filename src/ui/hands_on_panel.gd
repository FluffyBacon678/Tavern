class_name HandsOnPanel
extends Control

## Doing it yourself, from design notes section 22.
##
## The rush starts, the cook has five loaves queued, and the player clicks the
## oven. A short timing game opens, they do it faster and better than the staff
## would have, and they are back to managing within seconds. That "within
## seconds" is the whole design: anything that holds the player at the bench
## while the dining room falls apart has missed the point.
##
## The steps are read off the recipe rather than written per dish, because the
## notes forbid a BakeBread() and this would be the sneaky way to end up with
## one. A new recipe gets a hands-on version for free.
##
## Deliberately one mechanic, not five. A sweeping marker and a target band is
## legible in a single glance, works with a mouse, a key or a thumb, and leaves
## the interesting decision where it belongs -- whether to be at the oven at all
## while the room needs waiting on.

signal finished(performance: float)
signal closed

## How fast the marker sweeps, in bar-widths per second. Rises with each step so
## a four-stage recipe gets harder rather than longer.
const BASE_SPEED: float = 0.85
const SPEED_STEP: float = 0.16
## Half-width of the target band, as a fraction of the bar. Narrows as it goes.
const BASE_BAND: float = 0.13
const BAND_STEP: float = 0.018
const MIN_BAND: float = 0.055
## Steps in the game, whatever the recipe's length.
const MIN_STEPS: int = 2
const MAX_STEPS: int = 4

var world  ## TavernWorld
var recipe: Recipe
var placement_index: int = -1

var _steps: Array[Dictionary] = []
var _step: int = 0
var _marker: float = 0.0
var _direction: float = 1.0
var _running: bool = false
var _elapsed: float = 0.0
var _scores: Array[float] = []

var _panel: PanelContainer
var _rows: VBoxContainer
var _heading: Label
var _step_label: Label
var _bar: Control
var _tally: Label
var _action: Button
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.02, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(440, 0)
	centre.add_child(_panel)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	_panel.add_child(_rows)

	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", 20)
	_heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	_rows.add_child(_heading)

	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	_rows.add_child(_step_label)

	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 46)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_rows.add_child(_bar)

	_tally = Label.new()
	_tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tally.add_theme_font_size_override("font_size", 13)
	_tally.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	_rows.add_child(_tally)

	_action = Button.new()
	_action.pressed.connect(_on_action)
	_rows.add_child(_action)
	set_process(false)


## Open the bench. Returns false when there is nothing to do here, which the
## caller should treat as "do not show the button in the first place".
func begin(p_world, p_index: int, p_recipe: Recipe) -> bool:
	world = p_world
	placement_index = p_index
	recipe = p_recipe
	if world == null or recipe == null:
		return false
	if not world.generator.can_perform(placement_index, recipe):
		return false

	theme = TavernTheme.build(TavernTheme.scale_for_control(self) * 0.95)
	_rng.randomize()
	_build_steps()
	_step = 0
	_scores.clear()
	_elapsed = 0.0
	_marker = 0.0
	_direction = 1.0
	_running = true

	_heading.text = recipe.display_name.to_upper()
	_tally.text = "Hit the band. %d steps." % _steps.size()
	_action.text = "Now  [Space]"
	_refresh_step()
	visible = true
	set_process(true)
	_action.call_deferred("grab_focus")
	return true


## Steps read off the recipe: one per ingredient, then the working itself.
##
## The notes' example -- select ingredients, mix, prepare dough, place in oven --
## is exactly this shape, and deriving it means a stew added next month gets its
## own sensible sequence without anyone writing one.
func _build_steps() -> void:
	_steps.clear()
	for need in recipe.inputs:
		var def: ItemDef = ItemCatalog.get_def(need["id"])
		_steps.append({"text": "Measure the %s" % (def.display_name.to_lower() if def else "ingredients")})
		if _steps.size() >= MAX_STEPS - 1:
			break
	_steps.append({"text": recipe.display_name})
	while _steps.size() < MIN_STEPS:
		_steps.append({"text": "Work it"})

	# Each step gets its own band: a sweep that always stopped in the middle
	# would be a reflex test rather than a judgement.
	for i in range(_steps.size()):
		var band: float = maxf(BASE_BAND - BAND_STEP * float(i), MIN_BAND)
		_steps[i]["band"] = band
		_steps[i]["target"] = _rng.randf_range(band + 0.06, 1.0 - band - 0.06)
		_steps[i]["speed"] = BASE_SPEED + SPEED_STEP * float(i)


func _refresh_step() -> void:
	if _step >= _steps.size():
		return
	_step_label.text = "%d of %d — %s" % [_step + 1, _steps.size(), _steps[_step]["text"]]
	_marker = 0.0
	_direction = 1.0
	_bar.queue_redraw()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_marker += _direction * float(_steps[_step]["speed"]) * delta
	# Bounce rather than wrap. A marker that jumps from one edge to the other is
	# impossible to track and makes the timing feel arbitrary.
	if _marker >= 1.0:
		_marker = 1.0
		_direction = -1.0
	elif _marker <= 0.0:
		_marker = 0.0
		_direction = 1.0
	_bar.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		_on_action()
		get_viewport().set_input_as_handled()


func _on_action() -> void:
	if not _running:
		_close()
		return

	var step: Dictionary = _steps[_step]
	var band: float = float(step["band"])
	var miss: float = absf(_marker - float(step["target"]))
	# Inside the band is a good hit, shading to perfect dead centre. Outside it
	# falls away over twice the band's width, so a near miss still counts for
	# something and a wild one does not.
	var score: float = 0.0
	if miss <= band:
		score = 1.0 - (miss / band) * 0.35
	else:
		score = maxf(0.0, 0.65 - (miss - band) / (band * 2.0) * 0.65)
	_scores.append(score)

	_step += 1
	if _step < _steps.size():
		_refresh_step()
		_tally.text = "%s so far" % _verdict(_average())
		return
	_complete()


func _average() -> float:
	if _scores.is_empty():
		return 0.0
	var total: float = 0.0
	for s in _scores:
		total += s
	return total / float(_scores.size())


func _complete() -> void:
	_running = false
	set_process(false)
	var performance: float = _average()

	# The world is the authority on whether this can still happen: the player
	# has been staring at a bar, and a cook may have got there first.
	var done: bool = world.generator.perform_by_hand(placement_index, recipe, performance)
	if done:
		_heading.text = "DONE"
		_step_label.text = "Quality: %s      Time: %.1fs" % [_verdict(performance), _elapsed]
		_tally.text = "A cook would have taken %.0fs, and turned out ordinary work." % recipe.work_amount
		finished.emit(performance)
	else:
		_heading.text = "COULD NOT FINISH"
		_step_label.text = "Somebody else finished, ingredients moved, or there is no room for the goods."
		_tally.text = ""
	_action.text = "Back to it"
	_bar.queue_redraw()


static func _verdict(performance: float) -> String:
	if performance >= 0.92:
		return "Exceptional"
	if performance >= 0.78:
		return "Excellent"
	if performance >= 0.6:
		return "Good"
	if performance >= 0.4:
		return "Passable"
	return "Poor"


func _close() -> void:
	_running = false
	set_process(false)
	visible = false
	closed.emit()


func _draw_bar() -> void:
	var size: Vector2 = _bar.size
	if size.x <= 0.0:
		return
	var track := Rect2(0.0, size.y * 0.32, size.x, size.y * 0.36)
	_bar.draw_rect(track, TavernTheme.IRON)

	if _step < _steps.size():
		var step: Dictionary = _steps[_step]
		var band: float = float(step["band"])
		var target: float = float(step["target"])
		var zone := Rect2(
			(target - band) * size.x, track.position.y,
			band * 2.0 * size.x, track.size.y
		)
		_bar.draw_rect(zone, TavernTheme.CANDLE_DIM)
		# The exact centre, so "dead on" is a thing the player can aim at rather
		# than a hidden bonus.
		_bar.draw_rect(Rect2(target * size.x - 1.0, track.position.y, 2.0, track.size.y), TavernTheme.CANDLE)

	if _running:
		var x: float = _marker * size.x
		_bar.draw_rect(Rect2(x - 2.0, size.y * 0.18, 4.0, size.y * 0.64), TavernTheme.PARCHMENT)
