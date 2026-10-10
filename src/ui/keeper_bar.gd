class_name KeeperBar
extends PanelContainer

## While playing the keeper: what they hold and what they are doing, at the
## bottom of the screen, with the two things a player reaches for most -- put
## it down, and stop -- as buttons. A right-click on the keeper offers both
## too, but a phone has no right-click, and nobody should have to find the
## keeper on screen to learn what is in their hands.

const REFRESH: float = 0.2

var world  ## TavernWorld
var _picture: TextureRect
var _held: Label
var _doing: Label
var _drop: Button
var _stop: Button
var _timer: float = 0.0


func setup(p_world) -> void:
	world = p_world
	name = "KeeperBar"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -58
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_picture = IconStudio.rect(null, 30.0)
	row.add_child(_picture)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.custom_minimum_size.x = 190
	row.add_child(words)
	_held = Label.new()
	_held.add_theme_font_size_override("font_size", 14)
	_held.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	words.add_child(_held)
	_doing = Label.new()
	_doing.add_theme_font_size_override("font_size", 12)
	_doing.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	words.add_child(_doing)
	_drop = _button("Put down", "Put what you are holding down where you stand",
		func() -> void: world.keeper.drop())
	row.add_child(_drop)
	_stop = _button("Stop", "Stop what you are doing", func() -> void: world.keeper.stop())
	row.add_child(_stop)


func _process(delta: float) -> void:
	var playing: bool = world != null and world.keeper_controls != null and world.keeper_controls.playing \
		and world.keeper != null and is_instance_valid(world.keeper.pawn)
	if visible != playing:
		visible = playing
		_timer = 0.0
	if not playing:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	refresh()


func refresh() -> void:
	var keeper: Keeper = world.keeper
	if keeper == null:
		return
	var held: ItemDef = keeper.carry_def
	_picture.visible = held != null
	if held != null:
		_picture.texture = IconStudio.item(held.id)
		_held.text = "%d %s" % [keeper.carry_count, held.display_name]
	else:
		_held.text = "Hands free"
	var doing: String = keeper.status_text()
	_doing.text = doing.left(1).to_upper() + doing.substr(1)
	_drop.visible = held != null
	_stop.visible = keeper.is_busy()
	reset_size()


func _button(text: String, hint: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = hint
	# Out of the focus chain: Space must keep pausing time.
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(func() -> void:
		AudioDirector.play("ui_click")
		pressed.call()
		refresh())
	return b
