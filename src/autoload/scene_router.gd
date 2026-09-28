extends Node

## Scene changes with a fade, plus a shared overlay the rest of the game can
## borrow for transitions.
##
## Kept as an autoload so no scene needs to own the fade rectangle, and so a
## transition survives the scene swap that happens in the middle of it.

const FADE_DURATION: float = 0.35

signal transition_finished(scene_path: String)

var _layer: CanvasLayer
var _fade: ColorRect
var _busy: bool = false


func _ready() -> void:
	_layer = CanvasLayer.new()
	# Above ordinary UI, below anything that deliberately claims a higher layer.
	_layer.layer = 100
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.02, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Must not eat clicks while transparent.
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade.visible = false
	_layer.add_child(_fade)


## Fade out, swap scene, fade back in. Ignores re-entrant calls so a double-tap
## on a menu button cannot start two transitions at once.
func change_scene(scene_path: String) -> void:
	if _busy:
		return
	_busy = true

	await fade_out()

	var err: int = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneRouter: could not load '%s' (error %d)." % [scene_path, err])
		await fade_in()
		_busy = false
		return

	# Let the new scene finish entering the tree before revealing it, otherwise
	# the first frame can show an unbuilt layout.
	await get_tree().process_frame
	await fade_in()

	_busy = false
	transition_finished.emit(scene_path)


func fade_out(duration: float = FADE_DURATION) -> void:
	_fade.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, duration)
	await tween.finished


func fade_in(duration: float = FADE_DURATION) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, duration)
	await tween.finished
	_fade.visible = false


func quit_game() -> void:
	await fade_out()
	get_tree().quit()
