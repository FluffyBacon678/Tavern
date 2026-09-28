class_name ModalDialog
extends Control

## A question the player has to answer before anything else happens: leave
## without saving, delete a tavern, quit. Dims what is behind it, takes focus,
## and answers Esc with its last choice (by convention, "Cancel").
##
##   var dialog := ModalDialog.ask(self, "Leave?", "Unsaved progress...", [
##       ["save", "Save and leave", "primary"], ["leave", "Leave", "danger"],
##       ["cancel", "Cancel", ""]])
##   var answer: String = await dialog.chosen

signal chosen(id: String)

var _buttons: Array[Button] = []
var _cancel_id: String = "cancel"


## Open a dialog over `host`. Each option is [id, text, style], style being
## "primary", "danger" or "".
static func ask(host: Control, title: String, body: String, options: Array) -> ModalDialog:
	var dialog := ModalDialog.new()
	host.add_child(dialog)
	dialog._build(title, body, options)
	return dialog


func _build(title: String, body: String, options: Array) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var s: float = TavernTheme.scale_for_control(self)
	theme = TavernTheme.build(s)
	add_child(UiKit.dim(0.55))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(s))
	panel.custom_minimum_size = Vector2(460.0, 0.0) * s
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(14.0 * s))
	panel.add_child(box)
	box.add_child(UiKit.heading(title, s, 22.0))
	var text := UiKit.caption(body, s, 16.0)
	text.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	text.custom_minimum_size.x = 400.0 * s
	box.add_child(text)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", int(10.0 * s))
	box.add_child(row)
	for option in options:
		var id: String = String(option[0])
		var style: String = String(option[2]) if option.size() > 2 else ""
		var b: Button = UiKit.button(String(option[1]), s, style == "primary", style == "danger")
		b.pressed.connect(func() -> void: _answer(id))
		row.add_child(b)
		_buttons.append(b)
	if not options.is_empty():
		_cancel_id = String(options[options.size() - 1][0])
	# The safe choice has focus, so a stray Enter never deletes anything.
	if not _buttons.is_empty():
		_buttons[_buttons.size() - 1].call_deferred("grab_focus")


func _answer(id: String) -> void:
	chosen.emit(id)
	queue_free()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		AudioDirector.play("ui_back")
		_answer(_cancel_id)
