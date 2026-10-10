extends CanvasLayer

## A finger held on anything with a tooltip shows the tooltip.
##
## Every name in the game -- what the sack and the barrel are, what a button
## does, whose figure that is -- lives in a tooltip, and a phone has no pointer
## to rest anywhere: a player on one could never learn what a picture meant.
## A long press does there what resting the mouse does here. Touch only; a
## mouse has tooltips already, and nothing here runs for one.
##
## The world has its own long press (the keeper's options), so this answers
## only for presses that land on the interface.

## Off every control, for cancelling the press a long press began.
const AWAY := Vector2(-100000, -100000)

## Seconds a finger must stay down, and how far it may drift, to count.
const HOLD: float = 0.5
const SLOP: float = 14.0
## Seconds the tip stays up once the finger lifts.
const SHOWN_FOR: float = 2.6
const MAX_WIDTH: float = 320.0

var _panel: PanelContainer
var _label: Label
var _press_at := Vector2.ZERO
var _press_index: int = -1
var _held: float = -1.0
var _left: float = 0.0


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(TavernTheme.INK, 0.96)
	style.border_color = TavernTheme.CANDLE_DIM
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_corner_radius_all(3)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 9
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	_panel.add_child(_label)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press_at = event.position
			_press_index = event.index
			_held = 0.0
			_panel.visible = false
		elif event.index == _press_index:
			_held = -1.0
	elif event is InputEventScreenDrag and event.index == _press_index and _held >= 0.0:
		if event.position.distance_to(_press_at) > SLOP:
			_held = -1.0


func _process(delta: float) -> void:
	if _held >= 0.0:
		_held += delta
		if _held >= HOLD:
			_held = -1.0
			if not show_at(_press_at).is_empty():
				_cancel_press()
	if _panel.visible:
		_left -= delta
		if _left <= 0.0:
			_panel.visible = false


## A long press is for reading, not pressing: the button under the finger
## would otherwise fire when it lifts. The pointer is moved off it first, and a
## button let go of away from itself does nothing.
func _cancel_press() -> void:
	var away := InputEventMouseMotion.new()
	away.position = AWAY
	away.global_position = AWAY
	away.button_mask = MOUSE_BUTTON_MASK_LEFT
	away.device = InputEvent.DEVICE_ID_EMULATION
	get_viewport().push_input(away, true)


func is_showing() -> bool:
	return _panel.visible


func shown_text() -> String:
	return _label.text if _panel.visible else ""


## Show the tooltip of whatever is under `point`, above it. Returns the text,
## or "" when nothing there has one (the world, or a bare panel).
func show_at(point: Vector2) -> String:
	var text: String = tooltip_at(point)
	if text.is_empty():
		return ""
	_label.text = text
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size.x = 0.0
	if _label.get_minimum_size().x > MAX_WIDTH:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.custom_minimum_size.x = MAX_WIDTH
	_panel.reset_size()
	var size: Vector2 = _panel.get_combined_minimum_size()
	var screen: Vector2 = get_viewport().get_visible_rect().size
	# Above the finger, which would hide anything under it.
	var at := Vector2(point.x - size.x * 0.5, point.y - size.y - 48.0)
	if at.y < 4.0:
		at.y = point.y + 48.0
	at.x = clampf(at.x, 4.0, maxf(4.0, screen.x - size.x - 4.0))
	at.y = clampf(at.y, 4.0, maxf(4.0, screen.y - size.y - 4.0))
	_panel.position = at
	_panel.visible = true
	_left = SHOWN_FOR
	return text


## The tooltip of the topmost control under the point, or of the nearest
## parent that has one: a picture's name is on the chip around it.
func tooltip_at(point: Vector2) -> String:
	var node: Node = control_at(point)
	while node != null:
		if node is Control and not String(node.tooltip_text).is_empty():
			return String(node.tooltip_text)
		node = node.get_parent()
	return ""


## The control drawn on top at this point, of those that take the mouse.
## Godot's hovered control follows the mouse, which a finger does not move
## until it lifts, so this looks for itself: later in the tree and on a higher
## canvas layer is on top.
func control_at(point: Vector2) -> Control:
	var found: Array = [null, -1000000, -1]
	_search(get_tree().root, point, 0, [0], found)
	return found[0]


func _search(node: Node, point: Vector2, canvas: int, order: Array, found: Array) -> void:
	for child in node.get_children():
		if child == self or child is SubViewport or child is Window:
			continue
		var layer_here: int = canvas
		if child is CanvasLayer:
			if not child.visible:
				continue
			layer_here = child.layer
		if child is Control:
			if not child.visible:
				continue
			order[0] += 1
			if child.mouse_filter != Control.MOUSE_FILTER_IGNORE and child.get_global_rect().has_point(point):
				if layer_here > found[1] or (layer_here == found[1] and order[0] > found[2]):
					found[0] = child
					found[1] = layer_here
					found[2] = order[0]
		_search(child, point, layer_here, order, found)
