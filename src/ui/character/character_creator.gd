class_name CharacterCreator
extends Control

## Shared by new games and the owner's wardrobe. Changes stay in a private
## draft until accepted; closing this screen never writes a save or starts a run.
signal accepted(profile: CharacterProfile)
signal cancelled
signal closed

var draft: CharacterProfile
var editing: bool = false
var accept_button: Button
var name_field: LineEdit
var preview: CharacterPreview
var _finished: bool = false
var _s: float = 1.0
var _frame: PanelContainer
var _form_frame: PanelContainer
var _heading: Label
var _subtitle: Label
var _preview_name: Label
var _view_buttons: Dictionary = {}
var _form_labels: Array[Label] = []
var _choices: Dictionary = {}
var _swatches: Dictionary = {}
var _buttons: Array[Button] = []
var _rng := RandomNumberGenerator.new()


static func open(host: Node, profile: CharacterProfile, existing_owner: bool = false) -> CharacterCreator:
	var screen := CharacterCreator.new()
	screen.name = "CharacterCreator"
	screen.draft = profile.clone() if profile != null else CharacterProfile.default_owner(0)
	screen.editing = existing_owner
	host.add_child(screen)
	return screen


func _ready() -> void:
	if draft == null:
		draft = CharacterProfile.default_owner(0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	_build()
	get_viewport().size_changed.connect(_layout)
	GameSettings.changed.connect(_layout)
	_layout()
	_refresh_choices()
	preview.set_character(draft.appearance, draft.equipped)
	name_field.call_deferred("grab_focus")


func _build() -> void:
	add_child(UiKit.dim(0.82))
	_frame = PanelContainer.new()
	_frame.name = "CharacterFrame"
	add_child(_frame)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_frame.add_child(column)
	_heading = UiKit.heading("Your tavern keeper" if editing else "Create your tavern keeper", 1.0, 26, TavernTheme.PARCHMENT)
	column.add_child(_heading)
	_subtitle = UiKit.caption("Make a face for your story. You can revisit your look from Keeper.", 1.0, 14)
	column.add_child(_subtitle)
	column.add_child(UiKit.rule(1.0))
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	column.add_child(content)
	_form_frame = PanelContainer.new()
	_form_frame.add_theme_stylebox_override("panel", _inset_style())
	content.add_child(_form_frame)
	var scroll := ScrollContainer.new()
	scroll.name = "AppearanceScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form_frame.add_child(scroll)
	var form := VBoxContainer.new()
	form.name = "AppearanceChoices"
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)
	form.add_child(_section("IDENTITY"))
	form.add_child(_label("Character name"))
	name_field = LineEdit.new()
	name_field.name = "CharacterName"
	name_field.text = draft.name
	name_field.placeholder_text = "Your name, separate from the tavern's"
	name_field.max_length = 32
	name_field.text_changed.connect(func(value: String) -> void:
		draft.name = value
		_refresh_name()
	)
	form.add_child(name_field)
	form.add_child(UiKit.rule(1.0))
	_option(form, "body_type", "Build", ["Broad", "Slender"])
	_palette(form, "skin", "Skin tone", CharacterAppearance.SKIN_COLORS)
	_option(form, "hair_style", "Hair style", ["Cropped fringe", "Swept", "Tied back", "Close crop"])
	_palette(form, "hair", "Hair colour", CharacterAppearance.HAIR_COLORS)
	form.add_child(UiKit.rule(1.0))
	form.add_child(_section("STARTER CLOTHING"))
	_palette(form, "top", "Shirt colour", CharacterAppearance.TOP_COLORS)
	_palette(form, "trousers", "Trouser colour", CharacterAppearance.TROUSER_COLORS)
	_palette(form, "boots", "Boot leather", CharacterAppearance.BOOT_COLORS)
	if editing:
		_build_wardrobe(form)
	var preview_frame := PanelContainer.new()
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_frame.add_theme_stylebox_override("panel", _inset_style())
	content.add_child(preview_frame)
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 6)
	preview_frame.add_child(preview_column)
	_preview_name = Label.new()
	_preview_name.clip_text = true
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_name.add_theme_color_override("font_color", TavernTheme.CANDLE)
	preview_column.add_child(_preview_name)
	var view_row := HBoxContainer.new()
	view_row.name = "CharacterFraming"
	view_row.alignment = BoxContainer.ALIGNMENT_CENTER
	view_row.add_theme_constant_override("separation", 6)
	preview_column.add_child(view_row)
	for entry in [[CharacterPreview.Framing.FULL_BODY, "Full body", "FullBodyView"], [CharacterPreview.Framing.FACE, "Face", "FaceView"], [CharacterPreview.Framing.HANDS, "Hands", "HandsView"]]:
		var view_button: Button = _button(String(entry[1]), Vector2(110, 34))
		view_button.name = String(entry[2])
		view_button.toggle_mode = true
		var mode: int = int(entry[0])
		match mode:
			CharacterPreview.Framing.FULL_BODY: view_button.tooltip_text = "Review the whole outfit"
			CharacterPreview.Framing.FACE: view_button.tooltip_text = "Review the face, hair and headwear"
			CharacterPreview.Framing.HANDS: view_button.tooltip_text = "Review hands, cuffs and lower clothing"
		view_button.pressed.connect(func() -> void:
			preview.set_framing(mode)
			_refresh_view_buttons()
		)
		view_row.add_child(view_button)
		_view_buttons[mode] = view_button
	preview = CharacterPreview.new()
	preview.name = "LiveCharacterPreview"
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.add_child(preview)
	preview.framing_changed.connect(func(_mode: int) -> void: _refresh_view_buttons())
	var turn_row := HBoxContainer.new()
	turn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_column.add_child(turn_row)
	var left: Button = _button("↶", Vector2(44, 34))
	left.tooltip_text = "Turn left; you can also drag the character"
	left.pressed.connect(func() -> void: preview.rotate_step(-PI / 4.0))
	turn_row.add_child(left)
	var hint := UiKit.caption("Drag to turn", 1.0, 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_row.add_child(hint)
	var right: Button = _button("↷", Vector2(44, 34))
	right.tooltip_text = "Turn right"
	right.pressed.connect(func() -> void: preview.rotate_step(PI / 4.0))
	turn_row.add_child(right)
	column.add_child(UiKit.rule(1.0))
	var footer := HBoxContainer.new()
	footer.name = "CharacterActions"
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	var random: Button = _button("Randomize", Vector2(126, 40))
	random.pressed.connect(randomize_appearance)
	footer.add_child(random)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var back: Button = _button("Cancel" if editing else "Back", Vector2(100, 40))
	back.pressed.connect(cancel_changes)
	footer.add_child(back)
	accept_button = _button("Keep changes" if editing else "Create character", Vector2(174, 40))
	accept_button.name = "AcceptCharacter"
	accept_button.pressed.connect(accept_changes)
	footer.add_child(accept_button)
	_refresh_name()
	_refresh_view_buttons()


func _build_wardrobe(form: VBoxContainer) -> void:
	var available: Array = [
		["head", "Head", "felt_hat", "Felt travelling hat"],
		["cape", "Cape", "travel_cape", "Traveller's cape"],
		["backpack", "Backpack", "travel_pack", "Road pack"],
	]
	var any_owned: bool = false
	for entry in available:
		if not draft.owned.has(String(entry[2])):
			continue
		if not any_owned:
			form.add_child(UiKit.rule(1.0))
			form.add_child(_section("YOUR WARDROBE"))
			any_owned = true
		var slot: String = String(entry[0])
		var item: String = String(entry[2])
		var selector := OptionButton.new()
		selector.add_item("%s: none" % String(entry[1]))
		selector.add_item(String(entry[3]))
		selector.selected = 1 if draft.equipped.get(slot, "") == item else 0
		selector.item_selected.connect(func(index: int) -> void:
			if index == 0:
				draft.equipped.erase(slot)
			else:
				draft.equipped[slot] = item
			preview.set_character(draft.appearance, draft.equipped)
		)
		form.add_child(selector)


func _option(form: VBoxContainer, field: String, title: String, values: Array[String]) -> void:
	form.add_child(_label(title))
	var choice := OptionButton.new()
	choice.name = field.capitalize().replace(" ", "")
	for value in values:
		choice.add_item(value)
	choice.item_selected.connect(func(index: int) -> void: select_choice(field, index))
	form.add_child(choice)
	_choices[field] = choice


func _palette(form: VBoxContainer, field: String, title: String, colors: Array[Color]) -> void:
	form.add_child(_label(title))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 7)
	row.add_theme_constant_override("v_separation", 7)
	form.add_child(row)
	var buttons: Array[Button] = []
	for i in range(colors.size()):
		var button: Button = _button("", Vector2(32, 32))
		button.name = "%s%d" % [field.capitalize(), i]
		button.tooltip_text = "%s %d" % [title, i + 1]
		button.toggle_mode = true
		var index: int = i
		button.pressed.connect(func() -> void: select_choice(field, index))
		button.set_meta("swatch", colors[i])
		row.add_child(button)
		buttons.append(button)
	_swatches[field] = buttons


func select_choice(field: String, index: int) -> void:
	var previous: Variant = draft.appearance.get(field)
	match field:
		"body_type": draft.appearance.body_type = clampi(index, 0, 1)
		"hair_style": draft.appearance.hair_style = clampi(index, 0, 3)
		"skin": draft.appearance.skin = CharacterAppearance.SKIN_COLORS[posmod(index, CharacterAppearance.SKIN_COLORS.size())]
		"hair": draft.appearance.hair = CharacterAppearance.HAIR_COLORS[posmod(index, CharacterAppearance.HAIR_COLORS.size())]
		"top": draft.appearance.top = CharacterAppearance.TOP_COLORS[posmod(index, CharacterAppearance.TOP_COLORS.size())]
		"trousers": draft.appearance.trousers = CharacterAppearance.TROUSER_COLORS[posmod(index, CharacterAppearance.TROUSER_COLORS.size())]
		"boots": draft.appearance.boots = CharacterAppearance.BOOT_COLORS[posmod(index, CharacterAppearance.BOOT_COLORS.size())]
		_: return
	_refresh_choices()
	if previous == draft.appearance.get(field):
		return
	preview.set_character(draft.appearance, draft.equipped)


func randomize_appearance() -> void:
	draft.appearance.body_type = _rng.randi_range(0, 1)
	draft.appearance.hair_style = _rng.randi_range(0, 3)
	for field in ["skin", "hair", "top", "trousers", "boots"]:
		var buttons: Array = _swatches[field]
		var button: Button = buttons[_rng.randi_range(0, buttons.size() - 1)]
		draft.appearance.set(field, button.get_meta("swatch"))
	_refresh_choices()
	preview.set_character(draft.appearance, draft.equipped)


func _refresh_choices() -> void:
	for field in _choices:
		var choice: OptionButton = _choices[field]
		choice.select(int(draft.appearance.get(field)))
	for field in _swatches:
		for button in _swatches[field]:
			var selected: bool = (draft.appearance.get(field) as Color).is_equal_approx(button.get_meta("swatch"))
			button.set_pressed_no_signal(selected)
			_style_swatch(button, selected)


func _refresh_name() -> void:
	if _preview_name != null:
		var clean: String = draft.name.strip_edges()
		_preview_name.text = clean if not clean.is_empty() else "Your tavern keeper"


func _refresh_view_buttons() -> void:
	if preview == null:
		return
	for mode in _view_buttons:
		var button: Button = _view_buttons[mode]
		var selected: bool = preview.get_framing() == mode
		button.set_pressed_no_signal(selected)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("34484b") if selected else Color("202b2c")
			style.border_color = TavernTheme.CANDLE_DIM if selected or state in ["hover", "focus"] else Color("526364")
			style.set_border_width_all(1)
			style.set_corner_radius_all(4)
			style.content_margin_left = 12.0 * _s
			style.content_margin_right = 12.0 * _s
			style.content_margin_top = 6.0 * _s
			style.content_margin_bottom = 6.0 * _s
			button.add_theme_stylebox_override(state, style)


func accept_changes() -> void:
	if _finished:
		return
	_finished = true
	draft.name = name_field.text
	# Use the same validation as save loading, including a sensible blank name.
	var result: CharacterProfile = CharacterProfile.from_save(draft.to_save())
	accepted.emit(result)
	closed.emit()
	queue_free()


func cancel_changes() -> void:
	if _finished:
		return
	_finished = true
	cancelled.emit()
	closed.emit()
	queue_free()


func _layout() -> void:
	if _frame == null:
		return
	_s = TavernTheme.scale_for_control(self)
	theme = TavernTheme.build(_s)
	var margin: float = 20.0 * _s
	_frame.offset_left = margin
	_frame.offset_top = margin
	_frame.offset_right = -margin
	_frame.offset_bottom = -margin
	var style: StyleBoxFlat = UiKit.panel_style(_s, 0.98)
	style.bg_color = Color("232b29")
	style.border_color = Color("8c7859")
	style.set_border_width_all(2)
	style.content_margin_top = 14.0 * _s
	style.content_margin_bottom = 12.0 * _s
	_frame.add_theme_stylebox_override("panel", style)
	_form_frame.custom_minimum_size.x = clampf(get_viewport_rect().size.x * 0.33, 280.0 * _s, 420.0 * _s)
	_heading.add_theme_font_size_override("font_size", int(26.0 * _s))
	_subtitle.add_theme_font_size_override("font_size", int(13.0 * _s))
	_preview_name.add_theme_font_size_override("font_size", int(20.0 * _s))
	name_field.custom_minimum_size.y = 36.0 * _s
	for label in _form_labels:
		label.add_theme_font_size_override("font_size", int((12.0 if label.has_meta("section") else 15.0) * _s))
	for button in _buttons:
		button.custom_minimum_size = (button.get_meta("base_size") as Vector2) * _s
		button.add_theme_font_size_override("font_size", int(16.0 * _s))
	for choice in _choices.values():
		(choice as OptionButton).custom_minimum_size.y = 36.0 * _s
	_refresh_choices()
	_refresh_view_buttons()
	_style_primary()


func _button(text: String, base_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta("base_size", base_size)
	UiKit.wire(button)
	_buttons.append(button)
	return button


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	_form_labels.append(label)
	return label


func _section(text: String) -> Label:
	var label: Label = _label(text)
	label.set_meta("section", true)
	label.add_theme_color_override("font_color", TavernTheme.CANDLE_DIM)
	return label


func _inset_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c2422")
	style.border_color = Color("626550")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _style_swatch(button: Button, selected: bool) -> void:
	var color: Color = button.get_meta("swatch")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.border_color = TavernTheme.CANDLE if selected or state in ["hover", "focus"] else Color("6b5740")
		style.set_border_width_all(3 if selected else 2)
		style.set_corner_radius_all(4)
		style.content_margin_left = 0
		style.content_margin_right = 0
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		button.add_theme_stylebox_override(state, style)


func _style_primary() -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("3b5532") if state == "normal" else Color("4a683e")
		style.border_color = TavernTheme.CANDLE if state in ["hover", "focus"] else Color("a58a54")
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		style.content_margin_left = 18.0 * _s
		style.content_margin_right = 18.0 * _s
		accept_button.add_theme_stylebox_override(state, style)
	accept_button.add_theme_color_override("font_color", TavernTheme.PARCHMENT)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		cancel_changes()
