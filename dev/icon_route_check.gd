extends Node

## Pictures on the player's route: title screen, New game, Sandbox, the
## character creator, then the tavern. Prints what the goods' pictures hold
## once there, and fails if any is still a dot or came out empty. Run windowed:
##   godot --path . res://dev/icon_route_check.tscn -- <png>

var out_path: String = "user://icon_route_check.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	if not GameState.begin_test_session():
		get_tree().quit(2)
		return
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://src/ui/main_menu/main_menu.tscn")
	await _frames(20)
	var menu: Node = get_tree().current_scene
	PlayerActions.press(menu, "New game")
	await _frames(15)
	PlayerActions.press(menu, "Sandbox")
	await _frames(10)
	PlayerActions.press(menu, "Create character")
	await _frames(20)
	var creator = menu.get("_character_creator")
	if creator == null or creator.accept_button == null:
		print("ICON ROUTE: the character creator did not open")
		get_tree().quit(1)
		return
	creator.accept_button.pressed.emit()
	for i in range(300):
		await get_tree().process_frame
		if get_tree().current_scene is TavernWorld:
			break
	var world := get_tree().current_scene as TavernWorld
	if world == null:
		print("ICON ROUTE: the world never opened")
		get_tree().quit(1)
		return
	var waited: int = 0
	while not IconStudio.settled() and waited < 600:
		await get_tree().process_frame
		waited += 1
	await _frames(10)
	var failures: int = 0
	for id in [&"bread", &"beer", &"lemonade", &"grilled_fish", &"flour"]:
		var tex: Texture2D = IconStudio.item(id)
		var img: Image = tex.get_image()
		var used: Rect2i = img.get_used_rect() if img != null else Rect2i()
		var ok: bool = tex.get_width() == IconStudio.SIZE and used.size.x > 8
		failures += 0 if ok else 1
		print("ICON ROUTE %s: %dx%d, used %s %s" % [id, tex.get_width(), tex.get_height(), used, "ok" if ok else "BAD"])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	# The studio's last sheets, both passes, for when a picture is wrong.
	if IconStudio._scene_view != null:
		IconStudio._scene_view.get_texture().get_image().save_png(out_path.get_basename() + "_scene.png")
		IconStudio._ink_view.get_texture().get_image().save_png(out_path.get_basename() + "_ink.png")
		print("ICON ROUTE: studio sheet %s, camera size %.2f, viewport %s" % [
			IconStudio._scene_view.size, IconStudio._camera.size, IconStudio._scene_view.get_visible_rect()])
	print("ICON ROUTE: %d bad picture(s), settled after %d frames" % [failures, waited])
	get_tree().quit(1 if failures > 0 else 0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
