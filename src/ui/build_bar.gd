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
var _item_buttons: Dictionary = {}  ## family (a piece's id, or "path") -> Button
## family -> the look last picked for it, so a button remembers its style.
var _chosen: Dictionary = {}
## The strip of looks above the bar, and its row of buttons.
var _styles: PanelContainer
var _styles_row: HBoxContainer
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
	offset_top = -206
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

	# A picture of each piece, so the row reads at a glance. Scrolls sideways
	# when a category holds more than the window is wide.
	var items_scroll := ScrollContainer.new()
	items_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	items_scroll.custom_minimum_size.y = 100
	rows.add_child(items_scroll)
	_item_row = HBoxContainer.new()
	_item_row.add_theme_constant_override("separation", 6)
	items_scroll.add_child(_item_row)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	rows.add_child(_status)

	# The looks strip floats above the bar, outside its layout.
	_styles = PanelContainer.new()
	_styles.name = "Styles"
	_styles.visible = false
	_styles.top_level = true
	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = Color(TavernTheme.TIMBER, 0.97)
	strip_style.border_color = TavernTheme.CANDLE_DIM
	strip_style.set_border_width_all(1)
	strip_style.set_corner_radius_all(5)
	strip_style.set_content_margin_all(6)
	_styles.add_theme_stylebox_override("panel", strip_style)
	add_child(_styles)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	_styles.add_child(strip)
	var label := Label.new()
	label.text = "Style"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TavernTheme.CANDLE)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(label)
	_styles_row = HBoxContainer.new()
	_styles_row.add_theme_constant_override("separation", 4)
	strip.add_child(_styles_row)
	visibility_changed.connect(_show_styles)

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

	# One button per piece, however many looks it comes in: the looks open in
	# a strip above the bar when the piece is picked, so a lawn, seven flower
	# beds and three wild grasses take three buttons, not thirteen.
	for def in BuildingCatalog.in_category(category):
		var family: StringName = BuildingCatalog.family_of(def)
		if _item_buttons.has(family):
			continue
		var b := Button.new()
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_constant_override("line_spacing", -2)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(104, 92)
		var looks: int = BuildingCatalog.variants(def).size()
		if looks > 1:
			# How many looks, in the corner, as a stack shows its count.
			var badge := Label.new()
			badge.text = str(looks)
			badge.tooltip_text = "%d styles" % looks
			badge.add_theme_font_size_override("font_size", 12)
			badge.add_theme_color_override("font_color", TavernTheme.CANDLE)
			badge.add_theme_color_override("font_outline_color", TavernTheme.INK)
			badge.add_theme_constant_override("outline_size", 4)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.position = Vector2(8, 4)
			b.add_child(badge)
		b.pressed.connect(func() -> void:
			AudioDirector.play("ui_click")
			_pick(_chosen_for(family, def))
		)
		# What it is for, in the status line: on hover with a mouse, and again
		# on selection, which is the only way a touch player will ever see it.
		b.mouse_entered.connect(func() -> void: _set_status(WorldStats.building_blurb(_chosen_for(family, def))))
		b.mouse_exited.connect(func() -> void:
			if _controller.mode == BuildController.Mode.DEMOLISH:
				_on_mode_changed(BuildController.Mode.DEMOLISH)
			else:
				_on_selection_changed(_selected)
		)
		_item_row.add_child(b)
		_item_buttons[family] = b
		_dress(b, _chosen_for(family, def))
	_show_styles()


## The look last picked for a piece's button, or its own.
func _chosen_for(family: StringName, fallback: BuildingDef) -> BuildingDef:
	return _chosen.get(family, fallback)


## A piece's button shows the look that a click on it will place.
func _dress(b: Button, look: BuildingDef) -> void:
	# Cost on the button rather than in a tooltip: on touch there is no hover,
	# so anything only reachable by tooltip is invisible on a phone.
	b.text = "%s\n%dg" % [BuildingCatalog.family_name(look), look.cost]
	b.icon = IconStudio.building(look)
	b.tooltip_text = look.full_name()


## Pick a look to place: remembered for its button, shown on it, and handed
## to the builder.
func _pick(look: BuildingDef) -> void:
	var family: StringName = BuildingCatalog.family_of(look)
	_chosen[family] = look
	if _item_buttons.has(family):
		_dress(_item_buttons[family], look)
	item_chosen.emit(look)


## Choose a piece in a given look as a player would: its category, its
## button, its style. For scripted players (the tutorial) and tests.
func choose(def: BuildingDef) -> void:
	if def.category != _active_category:
		_show_category(def.category)
	_pick(def)


## T: the next look of what is being placed.
func next_style() -> void:
	if _selected == null:
		return
	var looks: Array[BuildingDef] = BuildingCatalog.variants(_selected)
	if looks.size() < 2:
		return
	AudioDirector.play("ui_click")
	_pick(looks[(looks.find(_selected) + 1) % looks.size()])


## The looks of the picked piece, in a strip floating just above the bar by
## its button, so picking a look never pushes the bar about. Hidden for a
## piece with one look.
func _show_styles() -> void:
	if _styles == null:
		return
	for child in _styles_row.get_children():
		_styles_row.remove_child(child)
		child.queue_free()
	var looks: Array[BuildingDef] = []
	var button: Button = null
	if _selected != null:
		looks = BuildingCatalog.variants(_selected)
		button = _item_buttons.get(BuildingCatalog.family_of(_selected), null)
	if looks.size() < 2 or button == null or not is_visible_in_tree():
		_styles.visible = false
		return
	var paces: bool = false
	for look in looks:
		paces = paces or not is_equal_approx(look.walk_cost, looks[0].walk_cost)
	var group := ButtonGroup.new()
	for look in looks:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		b.icon = IconStudio.building(look)
		var name: String = look.skin_name if not look.skin_name.is_empty() else look.display_name
		# A pace only where the looks differ in it: a path, not a flower bed.
		var pace: String = ""
		if paces:
			pace = " · " + WorldStats.pace_text(look.walk_cost * NavGrid.FLOOR_COST).trim_suffix(" pace")
		b.text = "%s\n%dg%s" % [name, look.cost, pace]
		b.tooltip_text = WorldStats.building_blurb(look)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_constant_override("line_spacing", -2)
		b.custom_minimum_size = Vector2(86, 82)
		UiKit.snug(b)
		b.set_pressed_no_signal(look == _selected)
		var chosen: BuildingDef = look
		b.pressed.connect(func() -> void:
			AudioDirector.play("ui_click")
			_pick(chosen)
		)
		_styles_row.add_child(b)
	_styles.visible = true
	_styles.reset_size()
	_place_styles(button)


## Just above the bar, centred on the piece's button, kept over the bar.
func _place_styles(button: Button) -> void:
	if not is_instance_valid(button) or not _styles.visible:
		return
	_styles.reset_size()
	var bar: Rect2 = get_global_rect()
	var at: Rect2 = button.get_global_rect()
	var box: Vector2 = _styles.get_combined_minimum_size()
	var x: float = clampf(at.position.x + at.size.x * 0.5 - box.x * 0.5, bar.position.x, maxf(bar.position.x, bar.end.x - box.x))
	_styles.global_position = Vector2(x, bar.position.y - box.y - 6.0)


func _on_selection_changed(def: BuildingDef) -> void:
	_selected = def
	var family: StringName = BuildingCatalog.family_of(def) if def != null else &""
	for id in _item_buttons:
		_item_buttons[id].button_pressed = def != null and id == family
	if def != null:
		_chosen[family] = def
		if _item_buttons.has(family):
			_dress(_item_buttons[family], def)
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
		if BuildingCatalog.variants(def).size() > 1:
			how += " %s for the next style." % KeyBindings.first("build_style")
		_set_status("%s. %s" % [WorldStats.building_blurb(def), how])
	elif _status_timer <= 0.0:
		_set_status("")
	_show_styles()


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
	# Kept over its button every frame: the bar lays new buttons out a frame
	# after they are made, and the window can be resized under it.
	if _styles != null and _styles.visible and _selected != null:
		_place_styles(_item_buttons.get(BuildingCatalog.family_of(_selected), null))
	# Refusal messages clear themselves; instructional ones stay put.
	if _status_timer <= 0.0:
		return
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status.text = ""
