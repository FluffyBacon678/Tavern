extends Control

## Every picture IconStudio makes, on one sheet with names, against the HUD's
## panel colour. Run windowed:
##   godot --path . --resolution 1600x1000 res://dev/icon_sheet.tscn -- <png>

var out_path: String = "user://icon_sheet.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = TavernTheme.TIMBER
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var grid := GridContainer.new()
	grid.columns = 12
	grid.position = Vector2(16, 16)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	for def in ItemCatalog.all():
		grid.add_child(_cell(IconStudio.item(def.id), def.display_name))
	for def in BuildingCatalog.all():
		grid.add_child(_cell(IconStudio.building(def), def.display_name))
	var waited: int = 0
	while not IconStudio.settled() and waited < 600:
		await get_tree().process_frame
		waited += 1
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("ICON SHEET: %d pictures -> %s" % [grid.get_child_count(), out_path])
	get_tree().quit()


func _cell(texture: Texture2D, name: String) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(124, 0)
	box.add_theme_constant_override("separation", 0)
	var picture: TextureRect = IconStudio.rect(texture, 56)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(picture)
	var label := Label.new()
	label.text = name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	label.clip_text = true
	box.add_child(label)
	return box
