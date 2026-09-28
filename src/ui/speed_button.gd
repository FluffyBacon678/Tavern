class_name SpeedButton
extends Button

## One of the game-speed buttons: pause, or one to three arrowheads.
##
## Drawn rather than typed, like the star ratings: the bundled font has no
## pause or play glyph, and a system fallback that happens to supply one on
## this machine would not on a phone.

## 0 draws the pause bars; 1 to 3 draw that many arrowheads.
var speed: int = 1


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(34, 24)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var colour: Color = TavernTheme.CANDLE if button_pressed else TavernTheme.PARCHMENT_DIM
	if is_hovered() and not button_pressed:
		colour = TavernTheme.PARCHMENT
	var h: float = size.y * 0.42
	var centre: Vector2 = size * 0.5
	if speed == 0:
		var w: float = h * 0.3
		var gap: float = h * 0.28
		draw_rect(Rect2(centre.x - gap - w, centre.y - h * 0.5, w, h), colour)
		draw_rect(Rect2(centre.x + gap, centre.y - h * 0.5, w, h), colour)
		return
	var width: float = h * 0.62
	var total: float = width * float(speed) - width * 0.25 * float(speed - 1)
	var x: float = centre.x - total * 0.5
	for i in range(speed):
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, centre.y - h * 0.5),
			Vector2(x + width, centre.y),
			Vector2(x, centre.y + h * 0.5),
		]), colour)
		x += width * 0.75
