extends Control

## Entry point.
##
## Exists so that platform setup happens in exactly one place before any screen
## draws, and so the first thing the player sees is a deliberate fade-in rather
## than a scene popping into existence. Autoloads have already run by the time
## this is ready, so settings are applied and audio buses exist.

const MAIN_MENU_SCENE := "res://src/ui/main_menu/main_menu.tscn"


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = TavernTheme.NIGHT
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	_configure_platform()

	# One frame so the backdrop is actually on screen before the transition
	# starts; otherwise the fade has nothing to fade from.
	await get_tree().process_frame
	SceneRouter.change_scene(MAIN_MENU_SCENE)


func _configure_platform() -> void:
	if OS.has_feature("mobile"):
		# Handle the Android back gesture ourselves -- screens decide what it
		# means, and the default behaviour of quitting from anywhere is wrong.
		get_tree().set_auto_accept_quit(false)
		get_tree().set_quit_on_go_back(false)
		DisplayServer.screen_set_keep_on(false)
	else:
		DisplayServer.window_set_min_size(Vector2i(800, 480))


func _notification(what: int) -> void:
	# On desktop this covers the window close button; on Android, the system
	# back gesture at the root. Either way, route it through the fade.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		SceneRouter.quit_game()
