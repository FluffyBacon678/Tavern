class_name KeeperMenu
extends Control

## RuneScape's "Choose option": a small box at the pointer listing what can be
## done with the thing clicked, the first being what a left-click would have
## done. Clicking anywhere else closes it. Rows are big enough for a finger.

const ROW_HEIGHT: float = 34.0

var _panel: PanelContainer
var _list: VBoxContainer
var _options: Array = []
var _runner: Callable


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a120bf2")
	style.border_color = TavernTheme.IRON
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_panel.add_child(_list)


func open(options: Array, at: Vector2, runner: Callable) -> void:
	_options = options
	_runner = runner
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "Choose option"
	title.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	title.add_theme_font_size_override("font_size", 13)
	_list.add_child(title)
	for i in range(options.size()):
		var b := Button.new()
		b.text = String(options[i]["text"])
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = ROW_HEIGHT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", TavernTheme.PARCHMENT if i > 0 else TavernTheme.CANDLE)
		b.add_theme_color_override("font_hover_color", TavernTheme.CANDLE)
		b.add_theme_font_size_override("font_size", 15)
		var chosen: Dictionary = options[i]
		b.pressed.connect(func() -> void:
			close()
			_runner.call(chosen))
		_list.add_child(b)
	visible = true
	_panel.reset_size()
	# Opens at the pointer, kept on screen.
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * at
	var area: Vector2 = size
	var box: Vector2 = _panel.get_combined_minimum_size()
	_panel.position = Vector2(clampf(local.x - box.x * 0.5, 0.0, maxf(area.x - box.x, 0.0)),
		clampf(local.y - 10.0, 0.0, maxf(area.y - box.y, 0.0)))


func close() -> void:
	visible = false


func options() -> Array:
	return _options


func _gui_input(event: InputEvent) -> void:
	# A click outside the box closes it, as moving off it does in RuneScape.
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()
