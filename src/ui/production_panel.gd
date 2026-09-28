class_name ProductionPanel
extends PanelContainer

## Standing orders, one row per recipe.
##
## Shows what a bill is actually doing rather than just its settings -- "7 of 10"
## and "resumes below 4" answer the question the player has, which is why the
## kitchen has stopped. A panel that only showed the target would leave them
## guessing.

signal closed

const STEP: int = 2

var bills: BillBook
var items: ItemWorld
## Set by the HUD. Optional: without it the panel shows settings only, which is
## all it did before it could say what each recipe was actually up to.
var world

var _rows: VBoxContainer
## recipe id -> { status: Label, target: Label, resume: Label }
var _widgets: Dictionary = {}


func setup(p_bills: BillBook, p_items: ItemWorld) -> void:
	bills = p_bills
	items = p_items
	_build()
	bills.changed.connect(refresh)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	custom_minimum_size = Vector2(420, 0)
	offset_left = -436
	offset_right = -16
	offset_top = 134
	offset_bottom = -16
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	visible = false

	var layout := VBoxContainer.new()
	add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 12)
	scroll.add_child(_rows)

	var heading := Label.new()
	heading.text = "STANDING ORDERS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	heading.add_theme_font_size_override("font_size", 18)
	_rows.add_child(heading)

	for recipe in RecipeCatalog.all():
		if not bills.has_bill(recipe.id):
			continue
		_rows.add_child(_recipe_row(recipe))

	var note := Label.new()
	note.text = "Kitchens make up to the target, then wait until stock falls to the resume line."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	note.add_theme_font_size_override("font_size", 12)
	_rows.add_child(note)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void:
		AudioDirector.play("ui_back")
		visible = false
		closed.emit()
	)
	layout.add_child(close)


func _recipe_row(recipe: Recipe) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	box.add_child(header)

	var toggle := CheckBox.new()
	toggle.text = recipe.display_name
	toggle.button_pressed = bills.get_bill(recipe.id).get("enabled", true)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.toggled.connect(func(on: bool) -> void:
		AudioDirector.play("ui_click")
		bills.set_enabled(recipe.id, on)
	)
	header.add_child(toggle)

	var status := Label.new()
	status.add_theme_color_override("font_color", TavernTheme.CANDLE)
	status.add_theme_font_size_override("font_size", 13)
	header.add_child(status)

	var ingredients := Label.new()
	ingredients.text = recipe.summary()
	ingredients.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	ingredients.add_theme_font_size_override("font_size", 11)
	box.add_child(ingredients)

	# What it is doing right now, one line per bench that can make it.
	var activity := VBoxContainer.new()
	activity.add_theme_constant_override("separation", 1)
	box.add_child(activity)

	var target_label := Label.new()
	var resume_label := Label.new()
	box.add_child(_stepper("Keep", target_label, recipe.id, true))
	box.add_child(_stepper("Resume below", resume_label, recipe.id, false))

	_widgets[recipe.id] = {"status": status, "target": target_label, "resume": resume_label, "activity": activity}
	return box


func _stepper(label_text: String, value_label: Label, recipe_id: StringName, is_target: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 13)
	row.add_child(name_label)

	var minus := Button.new()
	minus.text = "−"
	minus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(_adjust.bind(recipe_id, is_target, -STEP))
	row.add_child(minus)

	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	row.add_child(value_label)

	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(_adjust.bind(recipe_id, is_target, STEP))
	row.add_child(plus)
	return row


func _adjust(recipe_id: StringName, is_target: bool, delta: int) -> void:
	AudioDirector.play("ui_click")
	var bill: Dictionary = bills.get_bill(recipe_id)
	if is_target:
		bills.set_target(recipe_id, bill.get("target", 0) + delta)
	else:
		bills.set_resume_below(recipe_id, bill.get("resume_below", 0) + delta)


func refresh() -> void:
	if bills == null or items == null:
		return
	for recipe in RecipeCatalog.all():
		if not _widgets.has(recipe.id):
			continue
		var bill: Dictionary = bills.get_bill(recipe.id)
		var stock: int = items.total_of(recipe.outputs[0]["id"]) if not recipe.outputs.is_empty() else 0
		var w: Dictionary = _widgets[recipe.id]
		w["status"].text = bills.status_text(recipe.id, stock)
		w["target"].text = str(bill.get("target", 0))
		w["resume"].text = str(bill.get("resume_below", 0))
		if world != null and world.generator != null:
			_show_activity(w["activity"], WorldStats.recipe_activity(world, recipe))


func _show_activity(box: VBoxContainer, lines: Array) -> void:
	# Reuse the labels already there: this runs every few frames while the
	# panel is open, and rebuilding them would make the text flicker.
	while box.get_child_count() > lines.size():
		var extra: Node = box.get_child(box.get_child_count() - 1)
		box.remove_child(extra)
		extra.queue_free()
	while box.get_child_count() < lines.size():
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# A known width, so a wrapped second line is measured and given room;
		# without it the line under was drawn over the row that follows.
		l.custom_minimum_size = Vector2(custom_minimum_size.x - 56.0, 0)
		l.add_theme_font_size_override("font_size", 12)
		box.add_child(l)
	for i in range(lines.size()):
		var l: Label = box.get_child(i)
		l.text = lines[i][0]
		l.add_theme_color_override("font_color", lines[i][1])


func toggle() -> void:
	visible = not visible
	if visible:
		theme = TavernTheme.build(TavernTheme.scale_for_control(self) * 0.85)
		refresh()
