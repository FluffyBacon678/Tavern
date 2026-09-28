extends Control

## Settings as a scene of its own: the shared SettingsScreen over a plain
## background, returning to the title screen when closed. The title screen and
## the pause menu open SettingsScreen directly, over themselves; this scene is
## kept for anything that still changes scene to it.

const MAIN_MENU_SCENE := "res://src/ui/main_menu/main_menu.tscn"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = TavernTheme.NIGHT
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var screen := SettingsScreen.open(self)
	screen.closed.connect(func() -> void: SceneRouter.change_scene(MAIN_MENU_SCENE))
