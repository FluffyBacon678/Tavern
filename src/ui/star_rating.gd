class_name StarRating
extends Control

## Five stars, drawn rather than typed.
##
## Ratings were ASCII (`***--`) because the bundled font has no star glyph. On
## Windows a system fallback font would quietly have supplied one, and on a
## phone nothing would -- so a typed star would have worked on this machine and
## become a box on the platform the game is actually aimed at. Polygons draw
## the same everywhere.

const POINTS: int = 5
## Inner radius as a share of the outer: the classic five-pointed star.
const INNER: float = 0.45

@export var stars: int = 3:
	set(value):
		stars = clampi(value, 0, POINTS)
		queue_redraw()
@export var star_size: float = 14.0:
	set(value):
		star_size = value
		_resize()
@export var filled: Color = TavernTheme.CANDLE
@export var empty: Color = Color(TavernTheme.IRON, 0.85)

const GAP: float = 2.0

var _shape: PackedVector2Array


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_resize()


## A rating with a label after it, which is how every rating in the game reads.
static func row(count: int, text: String, size: float = 14.0, text_colour: Color = TavernTheme.PARCHMENT, font_size: int = 13) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rating := StarRating.new()
	rating.star_size = size
	rating.stars = count
	rating.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(rating)
	if not text.is_empty():
		var label := Label.new()
		label.text = text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", text_colour)
		label.add_theme_font_size_override("font_size", font_size)
		box.add_child(label)
	return box


func _resize() -> void:
	custom_minimum_size = Vector2(POINTS * star_size + (POINTS - 1) * GAP, star_size)
	_shape = PackedVector2Array()
	var outer: float = star_size * 0.5
	for i in range(POINTS * 2):
		var r: float = outer if i % 2 == 0 else outer * INNER
		# Point up: start at -90 degrees.
		var a: float = -PI / 2.0 + PI * float(i) / float(POINTS)
		_shape.append(Vector2(cos(a), sin(a)) * r)
	queue_redraw()


func _draw() -> void:
	var half: float = star_size * 0.5
	for i in range(POINTS):
		var centre := Vector2(half + float(i) * (star_size + GAP), half + star_size * 0.04)
		var points := PackedVector2Array()
		for p in _shape:
			points.append(centre + p)
		if i < stars:
			draw_colored_polygon(points, filled)
		else:
			draw_colored_polygon(points, Color(empty, 0.25))
			points.append(points[0])
			draw_polyline(points, empty, 1.0, true)
