class_name PriorityPanel
extends PanelContainer

## The work matrix from design notes section 16: staff down the side, kinds of
## work across the top, a number in every cell.
##
## A matrix rather than a per-person menu, because the question a tavern keeper
## actually asks is comparative — "who is on serving?", "is anybody hauling?" —
## and that is unanswerable if you have to click five people in turn to find out.
##
## Lower number wins, and a blank cell means the person refuses that work
## entirely. Clicking a cell cycles it, so the whole crew can be rebalanced
## without a single dialogue.

signal closed

## Cells cycle off → 1 → 2 → 3 → 4 → off.
const CYCLE: Array[int] = [
	WorkType.PRIORITY_OFF, 1, 2, 3, 4,
]

var world  ## TavernWorld

var _grid: GridContainer
var _staff_shown: int = -1
## [worker, label] for the live "doing" line under each name.
var _status_lines: Array = []
var _status_timer: float = 0.0
## The worker whose "Let go" has been clicked once, awaiting the second click.
var _confirming: Worker = null
## [role, button] for the hire row, re-checked against the purse as it changes.
var _hire_buttons: Array = []


func setup(p_world) -> void:
	world = p_world
	_build()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(560, 0)
	visible = false

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	add_child(rows)

	# Hiring first, as in Prison Architect's staff menu: a card per position,
	# what it costs to take on, and what it costs every day after.
	var hire_heading := Label.new()
	hire_heading.text = "HIRE"
	hire_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hire_heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	hire_heading.add_theme_font_size_override("font_size", 18)
	rows.add_child(hire_heading)
	var hire_row := HFlowContainer.new()
	hire_row.add_theme_constant_override("h_separation", 6)
	hire_row.add_theme_constant_override("v_separation", 6)
	rows.add_child(hire_row)
	for role in StaffRole.hireable_roles():
		var card := Button.new()
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(118, 50)
		card.text = "%s\n%dg · %dg a day" % [role.title, role.fee, role.wage]
		card.add_theme_font_size_override("font_size", 12)
		var work: PackedStringArray = PackedStringArray()
		for kind in role.kinds:
			work.append(WorkType.display_name(kind).to_lower())
		card.tooltip_text = "%s\nWorks at: %s.\n%dg to hire, then %dg at every close." % [
			role.blurb, ", ".join(work), role.fee, role.wage]
		var hired: StaffRole = role
		card.pressed.connect(func() -> void:
			var refusal: String = world.hire(hired.id)
			if not refusal.is_empty():
				AudioDirector.play("ui_back")
				if world.hud != null:
					world.hud.flash(refusal)
				return
			AudioDirector.play("ui_click")
			rebuild()
		)
		hire_row.add_child(card)
		_hire_buttons.append([role, card])

	var heading := Label.new()
	heading.text = "STAFF"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	heading.add_theme_font_size_override("font_size", 18)
	rows.add_child(heading)

	var note := Label.new()
	note.text = "Lower numbers are done first. A blank cell means they will not do that work; a crossed one, that their position does not allow it."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	note.add_theme_font_size_override("font_size", 12)
	rows.add_child(note)

	_grid = GridContainer.new()
	_grid.columns = WorkType.COUNT + 2
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 4)
	rows.add_child(_grid)

	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void:
		AudioDirector.play("ui_back")
		visible = false
		closed.emit()
	)
	rows.add_child(close)


func rebuild() -> void:
	if world == null or _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	_status_lines.clear()
	_staff_shown = world.workers.size()

	# Header row: an empty corner, then one column per kind of work.
	_grid.add_child(_header(""))
	for kind in range(WorkType.COUNT):
		_grid.add_child(_header(WorkType.display_name(kind)))
	_grid.add_child(_header(""))

	for i in range(world.workers.size()):
		var worker: Worker = world.workers[i]
		if not is_instance_valid(worker) or not is_instance_valid(worker.pawn):
			continue
		_grid.add_child(_name_cell(worker))
		for kind in range(WorkType.COUNT):
			_grid.add_child(_priority_cell(worker, kind))
		_grid.add_child(_dismiss_cell(worker))

	if world.workers.is_empty():
		_grid.add_child(_header("No staff hired."))
	_refresh_hire_cards()


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(62, 0)
	l.add_theme_color_override("font_color", TavernTheme.IRON)
	l.add_theme_font_size_override("font_size", 12)
	return l


## The name, which selects them -- ring and inspector -- so "who is Hilda?"
## has an answer from here, and a line under it saying what they are doing,
## which is what a priority change is usually trying to fix.
func _name_cell(worker: Worker) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(170, 0)
	cell.add_theme_constant_override("separation", 0)
	var name_button := Button.new()
	name_button.text = worker.pawn.pawn_name
	name_button.flat = true
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.focus_mode = Control.FOCUS_NONE
	name_button.tooltip_text = "Show %s in the inspector" % worker.pawn.pawn_name
	name_button.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	name_button.add_theme_color_override("font_hover_color", TavernTheme.CANDLE)
	name_button.add_theme_font_size_override("font_size", 13)
	# No padding, so the name lines up with the status line under it; a flat
	# button's default margin left the two a ragged few pixels apart.
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var bare := StyleBoxEmpty.new()
		bare.content_margin_top = 2
		name_button.add_theme_stylebox_override(state, bare)
	var pawn: Pawn = worker.pawn
	name_button.pressed.connect(func() -> void:
		AudioDirector.play("ui_click")
		if world.hud != null and world.hud.inspector != null and is_instance_valid(pawn):
			world.hud.inspector.show_pawn(pawn)
	)
	cell.add_child(name_button)
	var doing := Label.new()
	doing.clip_text = true
	doing.custom_minimum_size = Vector2(170, 0)
	doing.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	doing.add_theme_font_size_override("font_size", 11)
	doing.text = worker.status_text()
	cell.add_child(doing)
	var position := Label.new()
	position.text = "%s · %dg a day" % [worker.role.title if worker.role != null else "Staff", worker.wage()]
	position.add_theme_color_override("font_color", TavernTheme.CANDLE_DIM)
	position.add_theme_font_size_override("font_size", 11)
	cell.add_child(position)
	_status_lines.append([worker, doing])
	return cell


## Two clicks, like deleting a saved tavern: the first asks, the second acts.
## Letting somebody go by accident would be as irreversible as the hire it
## exists to undo.
func _dismiss_cell(worker: Worker) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(74, 28)
	var asking: bool = _confirming == worker
	b.text = "Sure?" if asking else "Let go"
	b.tooltip_text = "Dismiss %s. They are paid %dg for today." % [worker.pawn.pawn_name, worker.wage()]
	b.add_theme_color_override("font_color", TavernTheme.DANGER if asking else TavernTheme.PARCHMENT_DIM)
	b.disabled = world.workers.size() <= 1
	b.pressed.connect(func() -> void:
		if _confirming != worker:
			AudioDirector.play("ui_click")
			_confirming = worker
			rebuild()
			return
		_confirming = null
		var refusal: String = world.dismiss_worker(worker)
		if not refusal.is_empty() and world.hud != null:
			world.hud.flash(refusal)
		AudioDirector.play("ui_back")
		rebuild()
	)
	return b


func _priority_cell(worker: Worker, kind: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(62, 28)
	if not worker.allows(kind):
		# The position's rule, not a setting: shown, but not clickable.
		b.text = "×"
		b.disabled = true
		b.tooltip_text = "A %s does not %s." % [
			worker.role.title.to_lower() if worker.role != null else "worker", WorkType.display_name(kind).to_lower()]
		return b
	_style_cell(b, worker.priorities.get(kind, WorkType.PRIORITY_OFF))
	b.pressed.connect(func() -> void:
		AudioDirector.play("ui_click")
		var current: int = worker.priorities.get(kind, WorkType.PRIORITY_OFF)
		var index: int = CYCLE.find(current)
		var next: int = CYCLE[(index + 1) % CYCLE.size()] if index >= 0 else CYCLE[0]
		worker.priorities[kind] = next
		_style_cell(b, next)
	)
	return b


## Colour carries the same information as the number, so the matrix can be read
## as a shape at a glance rather than parsed cell by cell.
func _style_cell(b: Button, priority: int) -> void:
	if priority == WorkType.PRIORITY_OFF:
		b.text = "—"
		b.add_theme_color_override("font_color", TavernTheme.IRON)
		return
	b.text = str(priority)
	b.add_theme_color_override(
		"font_color",
		TavernTheme.CANDLE if priority <= 2 else TavernTheme.PARCHMENT_DIM
	)


func toggle() -> void:
	_confirming = null
	visible = not visible
	if not visible:
		return
	theme = TavernTheme.build(TavernTheme.scale_for_control(self) * 0.8)
	# Over the checklist and the goal, which were added later and drew across
	# the hire cards; still under the day summary, which is modal.
	var summary: Node = get_parent().get_node_or_null("DaySummary") if get_parent() != null else null
	if summary != null:
		get_parent().move_child(self, summary.get_index() - 1)
	rebuild()


func _process(delta: float) -> void:
	if not visible or world == null:
		return
	# Hiring mid-session adds a row; nothing else changes the shape of the grid.
	if world.workers.size() != _staff_shown:
		rebuild()
		return
	_status_timer -= delta
	if _status_timer > 0.0:
		return
	_status_timer = 0.5
	_refresh_hire_cards()
	for pair in _status_lines:
		if is_instance_valid(pair[0]) and is_instance_valid(pair[1]):
			pair[1].text = pair[0].status_text()


## Greyed out when the purse is short. A position the tavern grows into says
## which day it opens, on its face, until that day comes.
func _refresh_hire_cards() -> void:
	for pair in _hire_buttons:
		var role: StaffRole = pair[0]
		var card: Button = pair[1]
		var locked: bool = world.clock != null and world.clock.day < role.unlock_day
		card.disabled = GameState.gold < role.fee or locked
		if locked == card.has_meta("open_text"):
			continue
		if locked:
			card.set_meta("open_text", card.text)
			card.set_meta("open_tip", card.tooltip_text)
			card.text = "%s\nfrom day %d" % [role.title, role.unlock_day]
			card.tooltip_text = "%s\nOpens on day %d." % [role.blurb, role.unlock_day]
		else:
			card.text = card.get_meta("open_text")
			card.tooltip_text = card.get_meta("open_tip")
			card.remove_meta("open_text")
			card.remove_meta("open_tip")
