class_name KeeperMenu
extends Control

## RuneScape's "Choose option": a small box at the pointer listing what can be
## done with the thing clicked, the first being what a left-click would have
## done. Clicking anywhere else closes it. Rows are big enough for a finger.

const ROW_HEIGHT: float = 48.0

var _panel: PanelContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _heading: Label
var _last_at := Vector2.ZERO
var _options: Array = []
var _runner: Callable


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_panel = PanelContainer.new()
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	_heading = Label.new()
	_heading.text = "Choose option"
	column.add_child(_heading)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


func _ready() -> void:
	resized.connect(func() -> void:
		if visible:
			_layout.call_deferred())


func open(options: Array, at: Vector2, runner: Callable) -> void:
	_options = options
	_runner = runner
	_last_at = at
	var s: float = TavernTheme.scale_for_control(self)
	theme = TavernTheme.build(s)
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(s))
	_heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	_heading.add_theme_font_size_override("font_size", int(round(16.0 * s)))
	_list.add_theme_constant_override("separation", int(round(3.0 * s)))
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for i in range(options.size()):
		var b: Button = UiKit.menu_button(String(options[i]["text"]), s)
		b.add_theme_font_size_override("font_size", int(round(17.0 * s)))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var screen_scale: float = maxf(get_global_transform_with_canvas().x.length(), 0.01)
		b.custom_minimum_size = Vector2(0, maxf(ROW_HEIGHT * s, ROW_HEIGHT / screen_scale))
		b.add_theme_color_override("font_color", TavernTheme.PARCHMENT if i > 0 else TavernTheme.CANDLE)
		var chosen: Dictionary = options[i]
		b.pressed.connect(func() -> void:
			close()
			_runner.call(chosen))
		_list.add_child(b)
	visible = true
	_scroll.scroll_vertical = 0
	_layout()
	_layout.call_deferred()


func _layout() -> void:
	if not visible or size.x <= 0 or size.y <= 0:
		return
	var s: float = TavernTheme.scale_for_control(self)
	var style: StyleBox = _panel.get_theme_stylebox("panel")
	var margin: Vector2 = style.get_minimum_size()
	var available: Vector2 = size - Vector2(16, 16)
	var width: float = minf(400.0 * s, available.x)
	_scroll.custom_minimum_size = Vector2(maxf(0, width - margin.x),
		minf(_list.get_combined_minimum_size().y, maxf(0, available.y - margin.y - _heading.get_combined_minimum_size().y - 8)))
	_panel.custom_minimum_size.x = width
	_panel.reset_size()
	# Opens at the pointer, kept on screen.
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * _last_at
	var area: Vector2 = size
	var box: Vector2 = _panel.get_combined_minimum_size()
	_panel.position = Vector2(clampf(local.x - box.x * 0.5, 8.0, maxf(area.x - box.x - 8.0, 8.0)),
		clampf(local.y - 10.0, 8.0, maxf(area.y - box.y - 8.0, 8.0)))


func close() -> void:
	visible = false


func options() -> Array:
	return _options


func _gui_input(event: InputEvent) -> void:
	# A click outside the box closes it, as moving off it does in RuneScape.
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		close()
		accept_event()
