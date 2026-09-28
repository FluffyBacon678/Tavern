class_name ObjectivesPanel
extends PanelContainer

## The opening checklist, top-right.
##
## Shows the current task with its hint spelled out, and the rest as a ticked
## list. Only the current one carries a hint: seven hints at once is a manual,
## and nobody reads a manual in a demo.
##
## It removes itself once the list is finished rather than lingering as a ticked
## trophy case — the point is to get the player playing, then get out of the way.

const FADE_OUT_AFTER: float = 6.0

var objectives: Objectives

var _rows: VBoxContainer
var _dismiss_timer: float = -1.0
var _expanded: bool = false


func setup(p_objectives: Objectives) -> void:
	objectives = p_objectives
	objectives.changed.connect(rebuild)
	_build()
	rebuild()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -330
	offset_right = -16
	offset_top = 70
	custom_minimum_size = Vector2(314, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)


func rebuild() -> void:
	if objectives == null or _rows == null:
		return
	for child in _rows.get_children():
		child.queue_free()

	var heading_row := HBoxContainer.new()
	_rows.add_child(heading_row)
	var heading := Label.new()
	heading.text = "GETTING STARTED  %d/%d" % [objectives.completed_count(), objectives.list.size()]
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	heading.add_theme_font_size_override("font_size", 13)
	heading_row.add_child(heading)
	var expand := Button.new()
	expand.text = "−" if _expanded else "+"
	expand.tooltip_text = "Hide completed and future steps" if _expanded else "Show the full checklist"
	expand.focus_mode = Control.FOCUS_NONE
	expand.add_theme_font_size_override("font_size", 13)
	expand.pressed.connect(func() -> void:
		_expanded = not _expanded
		rebuild()
	)
	heading_row.add_child(expand)

	var current: Objectives.Objective = objectives.current()
	for objective in objectives.list:
		var is_current: bool = current != null and objective.id == current.id
		if not _expanded and not is_current:
			continue
		var row := Label.new()
		row.text = "%s %s" % ["✓" if objective.done else "•", objective.text]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 13)
		if objective.done:
			row.add_theme_color_override("font_color", TavernTheme.IRON)
		elif is_current:
			row.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
		else:
			row.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
		_rows.add_child(row)

		# Only the task in hand explains itself.
		if is_current and not objective.hint.is_empty():
			var hint := Label.new()
			hint.text = objective.hint
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_color_override("font_color", TavernTheme.CANDLE_DIM)
			hint.add_theme_font_size_override("font_size", 11)
			_rows.add_child(hint)

	if objectives.all_done() and _dismiss_timer < 0.0:
		var done := Label.new()
		done.text = "The tavern is yours. Good luck."
		done.add_theme_color_override("font_color", TavernTheme.CANDLE)
		done.add_theme_font_size_override("font_size", 12)
		_rows.add_child(done)
		_dismiss_timer = FADE_OUT_AFTER


func _process(delta: float) -> void:
	if _dismiss_timer < 0.0:
		return
	_dismiss_timer -= delta
	if _dismiss_timer <= 0.0:
		var tween: Tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 1.2)
		tween.tween_callback(queue_free)
		_dismiss_timer = -1.0
		set_process(false)
