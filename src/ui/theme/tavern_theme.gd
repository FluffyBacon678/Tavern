class_name TavernTheme
extends RefCounted

## The prototype UI skin: dark timber panels, warm candlelight accents and
## parchment text.
##
## Built in code rather than authored as a .tres because at this stage the
## palette is still moving, and one place to change a colour beats hunting
## through a binary resource. The design notes call for plain, quick prototype
## UI that gets replaced wholesale later -- so this stays small on purpose, and
## everything it exposes is a token other screens reference by name.

# --- palette -------------------------------------------------------------
const NIGHT := Color("11160d")          ## deepest background, behind everything
const TIMBER := Color("2b2016")         ## panel body
const TIMBER_LIGHT := Color("3d2d1f")   ## hovered panel body
const TIMBER_DARK := Color("1a120b")    ## pressed panel body
const IRON := Color("6b5a44")           ## panel borders and rules
const CANDLE := Color("e8b45a")         ## primary accent, focus, highlights
const CANDLE_DIM := Color("b98c42")
const PARCHMENT := Color("efe4c8")      ## body text
const PARCHMENT_DIM := Color("a9977a")  ## secondary text, captions
const INK := Color("1a120b")
const DANGER := Color("b4543c")

# --- metrics -------------------------------------------------------------
const CORNER: int = 3
const BORDER: int = 2


## Build the shared theme. `ui_scale` lets a phone-sized viewport request
## chunkier text and taller touch targets from the same definition.
static func build(ui_scale: float = 1.0) -> Theme:
	var theme := Theme.new()

	var base_font: int = int(round(17.0 * ui_scale))
	theme.default_font_size = base_font

	_style_buttons(theme, ui_scale)
	_style_labels(theme, base_font)
	_style_panels(theme)
	_style_sliders(theme, ui_scale)
	_style_checkbox(theme, base_font)
	_style_option_button(theme, ui_scale, base_font)

	return theme


static func _flat(bg: Color, border: Color, border_width: int = BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(CORNER)
	return sb


static func _style_buttons(theme: Theme, ui_scale: float) -> void:
	# Touch targets need real height on a phone; 48dp is the usual floor.
	var pad_v: int = int(round(13.0 * ui_scale))
	var pad_h: int = int(round(26.0 * ui_scale))

	var normal := _flat(TIMBER, IRON)
	var hover := _flat(TIMBER_LIGHT, CANDLE_DIM)
	var pressed := _flat(TIMBER_DARK, CANDLE)
	var focus := _flat(Color(CANDLE.r, CANDLE.g, CANDLE.b, 0.10), CANDLE)
	var disabled := _flat(Color(TIMBER.r, TIMBER.g, TIMBER.b, 0.5), Color(IRON.r, IRON.g, IRON.b, 0.4))

	for sb in [normal, hover, pressed, focus, disabled]:
		sb.content_margin_top = pad_v
		sb.content_margin_bottom = pad_v
		sb.content_margin_left = pad_h
		sb.content_margin_right = pad_h

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("disabled", "Button", disabled)

	theme.set_color("font_color", "Button", PARCHMENT)
	theme.set_color("font_hover_color", "Button", CANDLE)
	theme.set_color("font_pressed_color", "Button", CANDLE)
	theme.set_color("font_focus_color", "Button", CANDLE)
	theme.set_color("font_disabled_color", "Button", Color(PARCHMENT.r, PARCHMENT.g, PARCHMENT.b, 0.35))
	theme.set_font_size("font_size", "Button", int(round(18.0 * ui_scale)))


static func _style_labels(theme: Theme, base_font: int) -> void:
	theme.set_color("font_color", "Label", PARCHMENT)
	theme.set_font_size("font_size", "Label", base_font)


static func _style_panels(theme: Theme) -> void:
	var panel := _flat(Color(TIMBER.r, TIMBER.g, TIMBER.b, 0.92), IRON)
	panel.content_margin_left = 22
	panel.content_margin_right = 22
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)


static func _style_sliders(theme: Theme, ui_scale: float) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = TIMBER_DARK
	track.border_color = IRON
	track.set_border_width_all(1)
	track.set_corner_radius_all(2)
	track.content_margin_top = int(round(4.0 * ui_scale))
	track.content_margin_bottom = int(round(4.0 * ui_scale))

	var fill := StyleBoxFlat.new()
	fill.bg_color = CANDLE_DIM
	fill.set_corner_radius_all(2)
	fill.content_margin_top = int(round(4.0 * ui_scale))
	fill.content_margin_bottom = int(round(4.0 * ui_scale))

	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)


static func _style_checkbox(theme: Theme, base_font: int) -> void:
	# CheckBox derives from Button, so without this it inherits the bordered
	# timber panel above and reads as a button with a tick glued to it. Blank
	# styleboxes put the checkbox back to a mark plus a label.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 2
		empty.content_margin_right = 2
		empty.content_margin_top = 5
		empty.content_margin_bottom = 5
		theme.set_stylebox(state, "CheckBox", empty)

	theme.set_color("font_color", "CheckBox", PARCHMENT)
	theme.set_color("font_hover_color", "CheckBox", CANDLE)
	# For a checkbox "pressed" means *checked*, not being clicked -- so a ticked
	# box must keep the normal label colour or it reads as permanently highlighted.
	theme.set_color("font_pressed_color", "CheckBox", PARCHMENT)
	theme.set_color("font_hover_pressed_color", "CheckBox", CANDLE)
	theme.set_color("font_focus_color", "CheckBox", PARCHMENT)
	theme.set_font_size("font_size", "CheckBox", base_font)
	theme.set_constant("h_separation", "CheckBox", 10)

	# Drawn marks rather than the engine's: its default box is a faint outline
	# on a dark panel, and the storage filter is a list the player is meant to
	# scan for what is ticked. Candle-filled with a dark tick when checked, an
	# empty timber well when not -- readable at a glance, and no font needed.
	var size: int = maxi(12, int(round(float(base_font) * 1.05)))
	var icons: Array = _checkbox_icons(size)
	theme.set_icon("checked", "CheckBox", icons[0])
	theme.set_icon("unchecked", "CheckBox", icons[1])
	theme.set_icon("checked_disabled", "CheckBox", icons[0])
	theme.set_icon("unchecked_disabled", "CheckBox", icons[1])


## Cached per size: the theme is rebuilt every time a panel opens, and
## redrawing two images each time would be waste.
static var _checkbox_cache: Dictionary = {}


static func _checkbox_icons(size: int) -> Array:
	if _checkbox_cache.has(size):
		return _checkbox_cache[size]
	var checked := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var unchecked := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var border: int = maxi(1, size / 9)
	for y in range(size):
		for x in range(size):
			var edge: bool = x < border or y < border or x >= size - border or y >= size - border
			unchecked.set_pixel(x, y, IRON.lightened(0.15) if edge else TIMBER_DARK)
			checked.set_pixel(x, y, CANDLE_DIM if edge else CANDLE)
	# The tick: two strokes, stamped as small squares along each segment.
	var s: float = float(size)
	var stroke: int = maxi(2, size / 6)
	var points: Array[Vector2] = [Vector2(0.22, 0.52) * s, Vector2(0.42, 0.72) * s, Vector2(0.78, 0.28) * s]
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var steps: int = int(a.distance_to(b) * 2.0)
		for k in range(steps + 1):
			var p: Vector2 = a.lerp(b, float(k) / float(maxi(steps, 1)))
			for dy in range(stroke):
				for dx in range(stroke):
					var px: int = int(p.x) + dx - stroke / 2
					var py: int = int(p.y) + dy - stroke / 2
					if px >= 0 and py >= 0 and px < size and py < size:
						checked.set_pixel(px, py, INK)
	var pair: Array = [ImageTexture.create_from_image(checked), ImageTexture.create_from_image(unchecked)]
	_checkbox_cache[size] = pair
	return pair


static func _style_option_button(theme: Theme, ui_scale: float, base_font: int) -> void:
	var normal := _flat(TIMBER, IRON)
	var hover := _flat(TIMBER_LIGHT, CANDLE_DIM)
	var pressed := _flat(TIMBER_DARK, CANDLE)
	for sb in [normal, hover, pressed]:
		sb.content_margin_top = int(round(9.0 * ui_scale))
		sb.content_margin_bottom = int(round(9.0 * ui_scale))
		sb.content_margin_left = int(round(16.0 * ui_scale))
		sb.content_margin_right = int(round(16.0 * ui_scale))

	theme.set_stylebox("normal", "OptionButton", normal)
	theme.set_stylebox("hover", "OptionButton", hover)
	theme.set_stylebox("pressed", "OptionButton", pressed)
	theme.set_stylebox("focus", "OptionButton", _flat(Color(CANDLE.r, CANDLE.g, CANDLE.b, 0.10), CANDLE))
	theme.set_color("font_color", "OptionButton", PARCHMENT)
	theme.set_color("font_hover_color", "OptionButton", CANDLE)
	theme.set_font_size("font_size", "OptionButton", base_font)


## UI scale for the current window.
##
## The project stretches with mode "canvas_items" and aspect "expand", so the
## virtual viewport grows when the window is a different shape to the 1280x720
## base -- a portrait phone can report a viewport over 2000 units tall while the
## screen is only 960 pixels. Sizing type against the viewport alone therefore
## makes the UI render physically *smaller* the narrower the screen gets, which
## is exactly backwards.
##
## So: work out how much the canvas is being scaled on its way to the screen,
## pick a target on-screen size for body text, and divide the scaling back out.
## Text then stays legible at any window shape, on a phone or a dragged-about
## desktop window.
static func scale_for_viewport(viewport_size: Vector2, window_size: Vector2 = Vector2.ZERO) -> float:
	if window_size == Vector2.ZERO or viewport_size.x <= 0.0:
		# No window reference available: fall back to sizing off the viewport.
		return clampf(minf(viewport_size.x, viewport_size.y) / 720.0, 0.85, 1.45) * GameSettings.ui_scale

	var render_scale: float = maxf(window_size.x / viewport_size.x, 0.01)
	var shortest_px: float = minf(window_size.x, window_size.y)

	# Desired body-text height in real screen pixels. Phones are held closer and
	# get tapped rather than clicked, so they want a chunkier baseline.
	var divisor: float = 34.0 if OS.has_feature("mobile") else 46.0
	var target_px: float = clampf(shortest_px / divisor, 14.0, 30.0)

	# The player's own preference, on top: Settings > Gameplay > Interface size.
	return clampf((target_px / 17.0) / render_scale, 0.75, 4.0) * GameSettings.ui_scale


## Convenience for a Control: reads both sizes off the node.
static func scale_for_control(node: Control) -> float:
	var win: Window = node.get_window()
	return scale_for_viewport(
		node.get_viewport_rect().size,
		Vector2(win.size) if win != null else Vector2.ZERO
	)
