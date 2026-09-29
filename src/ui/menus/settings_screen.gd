class_name SettingsScreen
extends Control

## Settings, in tabs: Gameplay, Video, Audio, Controls. The same screen opens
## from the title screen and from the pause menu, over whatever is behind it.
##
## Changes apply at once and are kept (GameSettings saves on every change), so
## there is no Apply button to forget. A line along the bottom explains
## whatever the pointer or the keyboard is on, and each tab can be put back to
## its defaults.

signal closed

const TABS: Array[String] = ["Gameplay", "Video", "Audio", "Controls"]
const SECTIONS: Array[String] = ["gameplay", "video", "audio", "controls"]
## Controls that cannot be rebound, listed on the Controls tab under the
## ones that can (KeyBindings.ACTIONS).
const FIXED_CONTROLS: Array = [
	["Zoom", "Mouse wheel"],
	["Turn the view (free camera)", "Right mouse drag"],
	["Inspect", "Left click"],
	["Show every stack's count", "Hold Alt"],
	["Close a panel, or open the pause menu", "Esc"],
]

var _s: float = 1.0
var _tab: int = 0
var _tab_buttons: Array[Button] = []
var _page_holder: VBoxContainer
var _description: Label
var _reset: Button
var _back: Button
var _scale_timer: Timer
## [action id, slot, button] while waiting for the key to bind; empty otherwise.
var _capture: Array = []
## id -> [primary button, spare button] on the Controls page.
var _slot_buttons: Dictionary = {}


## Open over `host`. Await `closed` to know when the player is done.
static func open(host: Control) -> SettingsScreen:
	var screen := SettingsScreen.new()
	host.add_child(screen)
	screen._rebuild()
	return screen


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_tab_buttons.clear()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_s = TavernTheme.scale_for_control(self)
	theme = TavernTheme.build(_s)
	add_child(UiKit.dim(0.62))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(_s))
	var view: Vector2 = get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(980.0 * _s, view.x - 40.0), minf(640.0 * _s, view.y - 40.0))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(12.0 * _s))
	panel.add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	top.add_child(UiKit.heading("Settings", _s, 28.0))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var note := UiKit.caption("Changes apply at once and are kept.", _s, 13.0)
	note.autowrap_mode = TextServer.AUTOWRAP_OFF
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(note)
	column.add_child(UiKit.rule(_s))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(20.0 * _s))
	column.add_child(body)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", int(4.0 * _s))
	body.add_child(tabs)
	for i in range(TABS.size()):
		var b: Button = UiKit.menu_button(TABS[i], _s * 0.85)
		b.custom_minimum_size = Vector2(190.0, 44.0) * _s
		b.toggle_mode = true
		var index: int = i
		b.pressed.connect(func() -> void: _show_tab(index))
		tabs.add_child(b)
		_tab_buttons.append(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	# A gutter on the right, so values never sit under the scrollbar.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", int(18.0 * _s))
	scroll.add_child(gutter)
	_page_holder = VBoxContainer.new()
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_holder.add_theme_constant_override("separation", int(10.0 * _s))
	gutter.add_child(_page_holder)

	column.add_child(UiKit.rule(_s))
	_description = UiKit.caption("", _s, 14.0)
	_description.custom_minimum_size.y = 40.0 * _s
	column.add_child(_description)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", int(10.0 * _s))
	column.add_child(footer)
	_reset = UiKit.button("Reset to defaults", _s)
	_reset.pressed.connect(_on_reset)
	footer.add_child(_reset)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)
	_back = UiKit.button("Back", _s, true)
	_back.pressed.connect(close)
	footer.add_child(_back)

	_scale_timer = Timer.new()
	_scale_timer.one_shot = true
	_scale_timer.wait_time = 0.35
	_scale_timer.timeout.connect(_rebuild_keep_tab)
	add_child(_scale_timer)
	_show_tab(_tab)
	(func() -> void:
		if _tab < _tab_buttons.size() and is_instance_valid(_tab_buttons[_tab]):
			_tab_buttons[_tab].grab_focus()).call_deferred()


func _rebuild_keep_tab() -> void:
	_rebuild()


func close() -> void:
	AudioDirector.play("ui_back")
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not _capture.is_empty():
		_capture_key(event)
		return
	# An open dropdown answers Esc itself.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _show_tab(index: int) -> void:
	_tab = index
	var focus_was_on_tabs: bool = false
	for b in _tab_buttons:
		focus_was_on_tabs = focus_was_on_tabs or b.has_focus()
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].set_pressed_no_signal(i == index)
		# The open tab stays lit whatever has focus.
		_tab_buttons[i].add_theme_color_override("font_color", TavernTheme.CANDLE if i == index else TavernTheme.PARCHMENT)
	if focus_was_on_tabs:
		_tab_buttons[index].grab_focus()
	for child in _page_holder.get_children():
		child.queue_free()
	_reset.visible = not SECTIONS[index].is_empty()
	_reset.text = "Reset %s to defaults" % TABS[index].to_lower()
	match index:
		0: _page_gameplay()
		1: _page_video()
		2: _page_audio()
		3: _page_controls()
	_describe("")


func _on_reset() -> void:
	var section: String = SECTIONS[_tab]
	if section.is_empty():
		return
	var dialog := ModalDialog.ask(self, "Reset %s?" % TABS[_tab].to_lower(),
		"Every %s setting goes back to how the game came." % TABS[_tab].to_lower(),
		[["reset", "Reset", "danger"], ["cancel", "Cancel", ""]])
	if await dialog.chosen == "reset":
		GameSettings.reset_section(section)
		_rebuild_keep_tab()


# --- pages ----------------------------------------------------------------------

func _page_gameplay() -> void:
	_group("Saving")
	_add_row("Autosave at close of day", _toggle(GameSettings.autosave, func(on: bool) -> void:
		GameSettings.set_value("autosave", on)),
		"Save automatically every time the tavern closes for the night. Off, it saves only when you choose Save.")
	_group("Camera")
	_add_row("Edge scrolling", _toggle(GameSettings.edge_scroll, func(on: bool) -> void:
		GameSettings.set_value("edge_scroll", on)),
		"Move the view when the pointer rests against the edge of the screen.")
	_add_row("Camera speed", _slider(GameSettings.camera_speed, 0.5, 2.0, 0.1,
		func(v: float) -> String: return "x%.1f" % v,
		func(v: float) -> void: GameSettings.set_value("camera_speed", v)),
		"How fast the keys and the screen edge move the view.")
	_group("Interface")
	_add_row("Interface size", _slider(GameSettings.ui_scale, 0.8, 1.4, 0.05,
		func(v: float) -> String: return "%d%%" % int(round(v * 100.0)),
		func(v: float) -> void:
			GameSettings.set_value("ui_scale", v)
			_scale_timer.start()),
		"Makes every panel, button and label bigger or smaller, on top of the automatic sizing for your screen.")
	_add_row("Tutorial hints", _toggle(GameSettings.show_hints, func(on: bool) -> void:
		GameSettings.set_value("show_hints", on)),
		"The getting-started checklist and the level's goal line on the right of the screen.")


func _page_video() -> void:
	_group("Display")
	_add_row("Window mode", _choice(["Windowed", "Borderless", "Fullscreen"], GameSettings.display_mode,
		func(i: int) -> void:
			GameSettings.set_display_mode(i)
			_show_tab(_tab)),
		"Borderless fills the screen but lets you switch windows instantly. Fullscreen takes the display for the game alone. F11 toggles.")
	var sizes: Array[Vector2i] = GameSettings.available_window_sizes()
	var labels: Array[String] = []
	var chosen: int = 0
	for i in range(sizes.size()):
		labels.append("%d x %d" % [sizes[i].x, sizes[i].y])
		if sizes[i] == GameSettings.window_size:
			chosen = i
	var size_choice: OptionButton = _choice(labels, chosen, func(i: int) -> void:
		GameSettings.set_window_size(sizes[i]))
	size_choice.disabled = GameSettings.display_mode != GameSettings.DisplayMode.WINDOWED
	_add_row("Window size", size_choice, "The window's size in windowed mode. The game's text and panels resize with it.")
	_add_row("Vertical sync", _toggle(GameSettings.vsync, func(on: bool) -> void:
		GameSettings.set_value("vsync", on)),
		"Waits for the screen before drawing: no tearing, at the cost of a little responsiveness.")
	var caps: Array[String] = []
	var cap_index: int = GameSettings.FRAME_CAPS.size() - 1
	for i in range(GameSettings.FRAME_CAPS.size()):
		var cap: int = GameSettings.FRAME_CAPS[i]
		caps.append("Unlimited" if cap == 0 else "%d fps" % cap)
		if cap == GameSettings.max_fps:
			cap_index = i
	_add_row("Frame rate limit", _choice(caps, cap_index, func(i: int) -> void:
		GameSettings.set_value("max_fps", GameSettings.FRAME_CAPS[i])),
		"The most frames drawn each second. A limit keeps a laptop cooler and quieter.")
	_group("Graphics")
	_add_row("Quality", _choice(["Low", "Medium", "High"], GameSettings.quality, func(i: int) -> void:
		GameSettings.quality = i),
		"Forest density and atmosphere detail. The forest follows it on the next tavern you open.")
	_add_row("Animated title screen", _toggle(GameSettings.animated_background, func(on: bool) -> void:
		GameSettings.set_value("animated_background", on)),
		"The slow drift of the picture behind the title screen.")
	_group("People")
	_add_row("Outline staff and guests", _toggle(GameSettings.outline_people, func(on: bool) -> void:
		GameSettings.set_value("outline_people", on)),
		"A faint outline round everyone: gold for your staff, blue for guests.")
	_add_row("Thought bubbles", _toggle(GameSettings.thought_bubbles, func(on: bool) -> void:
		GameSettings.set_value("thought_bubbles", on)),
		"A tiny bubble over each head: what they are doing, or waiting for. Red when a guest is losing patience.")


func _page_audio() -> void:
	_group("Volume")
	var percent := func(v: float) -> String: return "%d%%" % int(round(v * 100.0))
	_add_row("Master", _slider(GameSettings.master_volume, 0.0, 1.0, 0.01, percent,
		func(v: float) -> void: GameSettings.master_volume = v),
		"Everything the game plays.")
	_add_row("Music", _slider(GameSettings.music_volume, 0.0, 1.0, 0.01, percent,
		func(v: float) -> void: GameSettings.music_volume = v),
		"Music. This build has none yet; the setting is kept for when it does.")
	_add_row("Effects", _slider(GameSettings.sfx_volume, 0.0, 1.0, 0.01, percent,
		func(v: float) -> void:
			GameSettings.sfx_volume = v
			AudioDirector.play("ui_click")),
		"Sounds from the tavern itself.")
	_add_row("Interface", _slider(GameSettings.interface_volume, 0.0, 1.0, 0.01, percent,
		func(v: float) -> void:
			GameSettings.set_value("interface_volume", v)
			AudioDirector.play("ui_click")),
		"Clicks and menu sounds.")
	_group("Behaviour")
	_add_row("Mute in the background", _toggle(GameSettings.mute_unfocused, func(on: bool) -> void:
		GameSettings.set_value("mute_unfocused", on)),
		"Go quiet while another window is in front of the game.")


func _page_controls() -> void:
	_slot_buttons.clear()
	var group: String = ""
	for entry in KeyBindings.ACTIONS:
		if entry[1] != group:
			group = entry[1]
			_group(group)
		var id: String = entry[0]
		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", int(6.0 * _s))
		for slot in range(2):
			var b := UiKit.button(_slot_text(id, slot), _s)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.x = 140.0 * _s
			b.custom_minimum_size.y = 32.0 * _s
			var which: int = slot
			b.pressed.connect(func() -> void: _begin_capture(id, which, b))
			slots.add_child(b)
			if not _slot_buttons.has(id):
				_slot_buttons[id] = []
			_slot_buttons[id].append(b)
		_add_row(entry[2], slots, "Click a key, then press the new one. Esc cancels; Backspace clears it.")
	_group("Fixed")
	for entry in FIXED_CONTROLS:
		var keys := Label.new()
		keys.text = String(entry[1])
		keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		keys.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
		_add_row(String(entry[0]), keys, "")


func _slot_text(id: String, slot: int) -> String:
	var k: int = int(KeyBindings.keys_of(id)[slot])
	return KeyBindings.key_name(k) if k != 0 else "—"


func _begin_capture(id: String, slot: int, button: Button) -> void:
	if not _capture.is_empty() and is_instance_valid(_capture[2]):
		_capture[2].text = _slot_text(_capture[0], _capture[1])
	_capture = [id, slot, button]
	button.text = "Press a key…"
	_describe("Press the key for “%s”. Esc cancels; Backspace clears the slot." % KeyBindings.label_of(id))


## The key the player pressed while a slot was waiting for one.
func _capture_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		# Clicks still reach the page; only keys are taken.
		return
	get_viewport().set_input_as_handled()
	var id: String = _capture[0]
	var slot: int = _capture[1]
	var button: Button = _capture[2]
	_capture = []
	var key: int = event.keycode
	if key == KEY_ESCAPE:
		button.text = _slot_text(id, slot)
		_describe("")
		return
	if key in [KEY_BACKSPACE, KEY_DELETE]:
		key = 0
	elif KeyBindings.RESERVED.has(key):
		button.text = _slot_text(id, slot)
		_describe("%s is kept for something else and cannot be bound." % KeyBindings.key_name(key))
		AudioDirector.play("ui_back")
		return
	var lost: String = GameSettings.bind_key(id, slot, key)
	AudioDirector.play("ui_click")
	# In place: rebuilding the page would scroll back to the top.
	for action in _slot_buttons:
		for i in range(_slot_buttons[action].size()):
			if is_instance_valid(_slot_buttons[action][i]):
				_slot_buttons[action][i].text = _slot_text(action, i)
	if not lost.is_empty() and lost != id:
		_describe("%s now does “%s”; “%s” has lost it." % [
			KeyBindings.key_name(key), KeyBindings.label_of(id), KeyBindings.label_of(lost)])
	elif key == 0:
		_describe("“%s” slot cleared." % KeyBindings.label_of(id))


# --- rows -----------------------------------------------------------------------

func _group(title: String) -> void:
	var l := UiKit.heading(title.to_upper(), _s, 13.0, TavernTheme.PARCHMENT_DIM)
	if _page_holder.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 6.0 * _s
		_page_holder.add_child(gap)
	_page_holder.add_child(l)


## A setting: its name on the left, its control on the right, and what it does
## on the description line whenever either is pointed at or focused.
func _add_row(title: String, control: Control, description: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(16.0 * _s))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var name := Label.new()
	name.text = title
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 300.0 * _s)
	row.add_child(control)
	_page_holder.add_child(row)
	if description.is_empty():
		return
	row.mouse_entered.connect(func() -> void: _describe(description))
	name.mouse_entered.connect(func() -> void: _describe(description))
	for node in [control] + control.get_children():
		if node is Control:
			node.mouse_entered.connect(func() -> void: _describe(description))
			node.focus_entered.connect(func() -> void: _describe(description))


func _describe(text: String) -> void:
	if _description != null:
		_description.text = text if not text.is_empty() else "Point at a setting to see what it does."


func _toggle(value: bool, on_change: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.button_pressed = value
	box.text = "On" if value else "Off"
	box.focus_mode = Control.FOCUS_ALL
	box.toggled.connect(func(on: bool) -> void:
		box.text = "On" if on else "Off"
		AudioDirector.play("ui_click")
		on_change.call(on)
	)
	return box


func _slider(value: float, lo: float, hi: float, step: float, shown: Callable, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10.0 * _s))
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.focus_mode = Control.FOCUS_ALL
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var readout := Label.new()
	readout.text = shown.call(value)
	readout.custom_minimum_size.x = 64.0 * _s
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_color_override("font_color", TavernTheme.CANDLE)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = shown.call(v)
		on_change.call(v)
	)
	return row


func _choice(items: Array[String], selected: int, on_change: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	option.select(clampi(selected, 0, items.size() - 1))
	option.focus_mode = Control.FOCUS_ALL
	option.item_selected.connect(func(i: int) -> void:
		AudioDirector.play("ui_click")
		on_change.call(i)
	)
	return option
