class_name BuildBar
extends PanelContainer

## Build palette: category tabs, the items in the active category, and demolish.
##
## Driven entirely off BuildingCatalog, so adding a buildable is a catalog edit
## and this needs no change. Sits at the bottom of the screen and can be collapsed,
## because on a phone in landscape it would otherwise eat a third of the view.

signal item_chosen(def: BuildingDef)
signal demolish_toggled(on: bool)

var _controller: BuildController
var _category_row: HBoxContainer
var _item_row: HBoxContainer
var _status: Label
var _demolish_button: Button
var _active_category: String = ""
var _item_buttons: Dictionary = {}  ## def id -> Button
var _status_timer: float = 0.0
## What is picked, so the status line can go back to it when the pointer
## leaves a button it was describing.
var _selected: BuildingDef = null


func setup(controller: BuildController) -> void:
	_controller = controller
	_controller.refused.connect(_on_refused)
	_controller.selection_changed.connect(_on_selection_changed)
	_controller.mode_changed.connect(_on_mode_changed)
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 12
	offset_right = -12
	offset_top = -168
	offset_bottom = -12

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	add_child(rows)

	_category_row = HBoxContainer.new()
	_category_row.add_theme_constant_override("separation", 6)
	rows.add_child(_category_row)

	for category in BuildingCatalog.categories():
		var b := Button.new()
		b.text = category
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(_show_category.bind(category))
		b.pressed.connect(func() -> void: AudioDirector.play("ui_click"))
		_category_row.add_child(b)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_row.add_child(spacer)

	_demolish_button = Button.new()
	_demolish_button.text = "Demolish"
	_demolish_button.toggle_mode = true
	_demolish_button.focus_mode = Control.FOCUS_NONE
	_demolish_button.add_theme_color_override("font_pressed_color", TavernTheme.DANGER)
	_demolish_button.toggled.connect(func(on: bool) -> void:
		AudioDirector.play("ui_click")
		demolish_toggled.emit(on)
	)
	_category_row.add_child(_demolish_button)

	_item_row = HBoxContainer.new()
	_item_row.add_theme_constant_override("separation", 6)
	rows.add_child(_item_row)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	rows.add_child(_status)

	var first: Array[String] = BuildingCatalog.categories()
	if not first.is_empty():
		_show_category(first[0])


func _show_category(category: String) -> void:
	_active_category = category
	for child in _category_row.get_children():
		if child is Button and child != _demolish_button:
			child.button_pressed = child.text == category

	for child in _item_row.get_children():
		child.queue_free()
	_item_buttons.clear()

	for def in BuildingCatalog.in_category(category):
		var b := Button.new()
		# Cost on the button rather than in a tooltip: on touch there is no hover,
		# so anything only reachable by tooltip is invisible on a phone.
		b.text = "%s\n%dg" % [def.display_name, def.cost]
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(112, 56)
		b.pressed.connect(func() -> void:
			AudioDirector.play("ui_click")
			item_chosen.emit(def)
		)
		# What it is for, in the status line: on hover with a mouse, and again
		# on selection, which is the only way a touch player will ever see it.
		b.mouse_entered.connect(func() -> void: _set_status(WorldStats.building_blurb(def)))
		b.mouse_exited.connect(func() -> void:
			if _controller.mode == BuildController.Mode.DEMOLISH:
				_on_mode_changed(BuildController.Mode.DEMOLISH)
			else:
				_on_selection_changed(_selected)
		)
		_item_row.add_child(b)
		_item_buttons[def.id] = b


func _on_selection_changed(def: BuildingDef) -> void:
	_selected = def
	for id in _item_buttons:
		_item_buttons[id].button_pressed = def != null and def.id == id
	if def != null:
		_demolish_button.button_pressed = false
		var how: String = "Click to place, %s to rotate, %s to take back the last." % [
			KeyBindings.first("rotate"), KeyBindings.first("build_undo")]
		match _controller.drag_shape():
			BuildController.DragShape.FILL:
				how = "Drag to fill a rectangle."
			BuildController.DragShape.OUTLINE:
				how = "Drag a rectangle to wall it in; drag in a line for a straight run."
		if def.shape == BuildingDef.Shape.DOOR:
			how = "Click a wall to put the door in it."
		_set_status("%s. %s" % [WorldStats.building_blurb(def), how])
	elif _status_timer <= 0.0:
		_set_status("")


func _on_mode_changed(mode: int) -> void:
	if mode == BuildController.Mode.DEMOLISH:
		_set_status("Demolish: click a piece to remove it. Blueprints refund in full, finished pieces half.")
	elif mode == BuildController.Mode.OFF:
		_demolish_button.button_pressed = false
		_set_status("")


func _on_refused(reason: String) -> void:
	_set_status(reason, TavernTheme.DANGER)


func _set_status(text: String, col: Color = TavernTheme.PARCHMENT_DIM) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", col)
	_status_timer = 2.5 if col == TavernTheme.DANGER else 0.0


func _process(delta: float) -> void:
	# Refusal messages clear themselves; instructional ones stay put.
	if _status_timer <= 0.0:
		return
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status.text = ""
