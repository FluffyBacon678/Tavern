class_name HoverCard
extends PanelContainer

## The headline about whatever the pointer rests on: a person, a bench, a
## stack of goods, a patch of ground.
##
## Clicking still opens the inspector with the whole story. The card is for the
## question a player asks forty times a minute -- "what is that one doing?" --
## which should not cost a click, and should not cost the inspector either.
##
## Never takes the mouse: it sits under the pointer, and a card that swallowed
## clicks would make the thing it describes impossible to select.

## How long the pointer rests on something before the card appears. Short
## enough to feel immediate, long enough that sweeping the camera across a busy
## room does not flicker a card over every patron in its path.
const SETTLE_TIME: float = 0.28
## Bare ground waits longer. Every tile has a card, so at the normal settle the
## pointer could not cross a field without one flickering up at each pause.
const GROUND_SETTLE_TIME: float = 0.9
const REFRESH_INTERVAL: float = 0.25
## Gap between the pointer and the card's corner.
const OFFSET := Vector2(20, 22)
const WIDTH: float = 300.0
## What the value column gets: the card, less its margins and the label column.
const VALUE_WIDTH: float = WIDTH - 24.0 - StatRows.LABEL_WIDTH - 8.0

var world  ## TavernWorld

var _rows: VBoxContainer
var _subject: Dictionary = {}
var _pending: Dictionary = {}
var _settle: float = 0.0
var _refresh: float = 0.0
## Held in place by pin_at() for a capture, ignoring the real pointer.
var _pinned_at := Vector2(-1, -1)


func setup(p_world) -> void:
	world = p_world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1d1a14f0")
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.border_color = TavernTheme.CANDLE_DIM
	style.set_corner_radius_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 9
	add_theme_stylebox_override("panel", style)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 3)
	add_child(_rows)


## Called every frame by the world with whatever is under the pointer, or an
## empty subject when the card should not show at all.
func track(subject: Dictionary, delta: float) -> void:
	if _pinned_at.x >= 0.0:
		_refresh -= delta
		if _refresh <= 0.0:
			_refresh = REFRESH_INTERVAL
			show_subject(_subject)
		_place(_pinned_at)
		return
	if subject.is_empty() or int(subject.get("kind", WorldStats.Kind.NONE)) == WorldStats.Kind.NONE:
		_pending = {}
		_subject = {}
		visible = false
		return

	if not WorldStats.same(subject, _pending):
		_pending = subject
		_settle = GROUND_SETTLE_TIME if int(subject["kind"]) == WorldStats.Kind.GROUND else SETTLE_TIME
		# Moving onto something new hides the old card at once. Leaving it up
		# while the next settles reads as the card describing the wrong thing.
		if visible and not WorldStats.same(subject, _subject):
			visible = false
		return

	if _settle > 0.0:
		_settle -= delta
		if _settle > 0.0:
			return
		_subject = subject
		_refresh = 0.0

	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_INTERVAL
		show_subject(_subject)
	_place()


## Show a card at once, with no settle. The capture harness uses this, and so
## does track() once the pointer has rested.
func show_subject(subject: Dictionary) -> void:
	_subject = subject
	var rows: Array = WorldStats.headline(WorldStats.rows_for(world, subject))
	if rows.is_empty():
		visible = false
		return
	StatRows.render(_rows, rows, true, VALUE_WIDTH)
	visible = true
	reset_size()


## Beside the pointer, flipped to the other side near the edges of the screen
## so it is never cut off.
func _place(at: Vector2 = Vector2(-1, -1)) -> void:
	var pointer: Vector2 = at if at.x >= 0.0 else get_viewport().get_mouse_position()
	var screen: Vector2 = get_viewport_rect().size
	# Shrink to fit every frame: rows change length as figures tick over, and a
	# container only ever grows on its own.
	reset_size()
	var card: Vector2 = get_combined_minimum_size()
	var pos: Vector2 = pointer + OFFSET
	if pos.x + card.x > screen.x - 8.0:
		pos.x = pointer.x - OFFSET.x - card.x
	if pos.y + card.y > screen.y - 8.0:
		pos.y = pointer.y - OFFSET.y - card.y
	position = Vector2(maxf(pos.x, 8.0), maxf(pos.y, 8.0))


## Put the card away now, rather than on the next frame's tracking. The day
## summary holds the game on whichever step the day ends, and a card drawn
## earlier in that frame otherwise sat over the reckoning until the next one.
func dismiss() -> void:
	_pending = {}
	_subject = {}
	visible = false


## For captures: pin the card to a screen point, as if the pointer were there.
func pin_at(at: Vector2) -> void:
	_pinned_at = at
	_place(at)
