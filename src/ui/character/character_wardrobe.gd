class_name CharacterWardrobe
extends VBoxContainer

## A compact equipment paper doll. The creator owns its private draft and
## validates changes; this widget presents owned choices and requests edits.
signal equipment_requested(slot: String, id: String)
signal slot_selected(slot: String)

const GRID_SLOTS: Array[String] = [
	"", "head", "", "cape", "neck", "backpack",
	"hands", "body", "outer", "ring", "legs", "feet",
]

var active_slot: String = "body"
var choice: OptionButton
var _profile: CharacterProfile
var _slot_buttons: Dictionary = {}
var _slot_heading: Label
var _hint: Label
var _s: float = 1.0


func setup(profile: CharacterProfile) -> void:
	_profile = profile
	name = "WardrobeSlots"
	add_theme_constant_override("separation", 8)
	var grid := GridContainer.new()
	grid.name = "EquipmentSlots"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	for slot in GRID_SLOTS:
		if slot.is_empty():
			var gap := Control.new()
			gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(gap)
			continue
		var button := Button.new()
		button.name = "Slot%s" % slot.capitalize()
		button.text = "Outerwear" if slot == "outer" else WardrobeCatalog.label(slot)
		button.clip_text = true
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("slot", slot)
		button.pressed.connect(func() -> void: select_slot(slot))
		UiKit.wire(button)
		grid.add_child(button)
		_slot_buttons[slot] = button
	_slot_heading = Label.new()
	_slot_heading.name = "ActiveEquipmentSlot"
	_slot_heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	add_child(_slot_heading)
	choice = OptionButton.new()
	choice.name = "EquipmentChoice"
	choice.item_selected.connect(func(index: int) -> void:
		var id: String = String(choice.get_item_metadata(index))
		equipment_requested.emit(active_slot, id)
	)
	add_child(choice)
	_hint = Label.new()
	_hint.name = "EquipmentHint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	add_child(_hint)
	set_ui_scale(1.0)
	refresh()


func select_slot(slot: String) -> bool:
	if not WardrobeCatalog.SLOTS.has(slot):
		return false
	active_slot = slot
	refresh()
	slot_selected.emit(slot)
	return true


func refresh() -> void:
	if choice == null:
		return
	for slot in _slot_buttons:
		var button: Button = _slot_buttons[slot]
		var worn: String = String(_profile.equipped.get(slot, ""))
		button.tooltip_text = "%s · %s" % [WardrobeCatalog.label(slot), WardrobeCatalog.item_name(worn) if not worn.is_empty() else _empty_name(slot)]
		button.set_pressed_no_signal(slot == active_slot)
		_style_slot(button, slot == active_slot, not worn.is_empty())
	_slot_heading.text = WardrobeCatalog.label(active_slot)
	choice.clear()
	choice.add_item(_empty_name(active_slot))
	choice.set_item_metadata(0, "")
	var equipped: String = String(_profile.equipped.get(active_slot, ""))
	var selected: int = 0
	for id in WardrobeCatalog.items_for_slot(active_slot):
		if not _profile.owned.has(id):
			continue
		var index: int = choice.item_count
		choice.add_item(WardrobeCatalog.item_name(id))
		choice.set_item_metadata(index, id)
		if id == equipped:
			selected = index
	# Keep an unavailable saved cosmetic visible without silently unequipping it.
	if not equipped.is_empty() and selected == 0:
		selected = choice.item_count
		choice.add_item("Saved item unavailable")
		choice.set_item_metadata(selected, equipped)
		choice.set_item_disabled(selected, true)
	choice.select(selected)
	if active_slot in ["body", "legs", "feet"]:
		_hint.text = "Base clothing stays on when this slot is empty. Change its colour below."
	elif active_slot == "outer":
		_hint.text = "Aprons layer over your shirt. Cape and backpack use their own slots."
	elif active_slot in ["cape", "backpack"]:
		_hint.text = "Cape and backpack can be worn together. Drag the preview to see the back."
	elif active_slot == "ring":
		_hint.text = "A small personal detail. Use Hands to inspect it more closely."
	else:
		_hint.text = "Choose an item from your wardrobe, or leave this slot empty."


func set_ui_scale(value: float) -> void:
	_s = value
	for button in _slot_buttons.values():
		(button as Button).custom_minimum_size = Vector2(82, 42) * _s
		(button as Button).add_theme_font_size_override("font_size", int(13.0 * _s))
		var slot: String = String(button.get_meta("slot"))
		_style_slot(button, slot == active_slot, not String(_profile.equipped.get(slot, "")).is_empty())
	if choice != null:
		choice.custom_minimum_size.y = 36.0 * _s
		choice.add_theme_font_size_override("font_size", int(15.0 * _s))
	if _slot_heading != null:
		_slot_heading.add_theme_font_size_override("font_size", int(16.0 * _s))
	if _hint != null:
		_hint.add_theme_font_size_override("font_size", int(12.0 * _s))


func _empty_name(slot: String) -> String:
	match slot:
		"body": return "Default base shirt"
		"legs": return "Default base trousers"
		"feet": return "Default base footwear"
		_: return "None"


func _style_slot(button: Button, selected: bool, worn: bool) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("3d4d40") if worn else Color("202b2c")
		if selected:
			style.bg_color = Color("4a4935")
		style.border_color = TavernTheme.CANDLE if selected or state in ["hover", "focus"] else Color("526364")
		style.set_border_width_all(2 if selected else 1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 6.0 * _s
		style.content_margin_right = 6.0 * _s
		style.content_margin_top = 5.0 * _s
		style.content_margin_bottom = 5.0 * _s
		button.add_theme_stylebox_override(state, style)
