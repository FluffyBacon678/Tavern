class_name UiKit
extends RefCounted

## The pieces every menu is built from, so the title screen, the pause menu and
## the settings all look and behave alike.
##
## The conventions, which is most of what makes a menu feel finished:
##   * Pointing at a menu entry focuses it, so mouse and keyboard share one
##     highlight and Enter always does what is lit.
##   * Focus is always visible: a candle bar on the left and candle text.
##   * Every entry sounds when it lights and when it is pressed.
##   * Esc (or the pad's back button) backs out one level, everywhere.
##   * Sizes take the screen's UI scale `s`, so nothing is a fixed pixel size.


## A large, left-aligned entry for a main list: title screen, pause menu.
static func menu_button(text: String, s: float, hint: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = hint
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(320.0, 50.0) * s
	b.add_theme_font_size_override("font_size", int(round(21.0 * s)))
	b.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, TavernTheme.CANDLE)
	b.add_theme_color_override("font_disabled_color", TavernTheme.IRON)
	var rest := _entry_box(Color(0, 0, 0, 0), 0, s)
	var lit := _entry_box(Color(TavernTheme.TIMBER_LIGHT, 0.88), 4, s)
	var down := _entry_box(Color(TavernTheme.TIMBER_DARK, 0.92), 4, s)
	b.add_theme_stylebox_override("normal", rest)
	b.add_theme_stylebox_override("disabled", rest)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("focus", lit)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("hover_pressed", down)
	wire(b)
	return b


## An ordinary dialog button: Back, Apply, Delete. `primary` for the one the
## dialog is really about; `danger` for anything that cannot be undone.
static func button(text: String, s: float, primary: bool = false, danger: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(120.0, 42.0) * s
	b.add_theme_font_size_override("font_size", int(round(17.0 * s)))
	if primary or danger:
		var edge: Color = TavernTheme.DANGER if danger else TavernTheme.CANDLE
		var box: StyleBoxFlat = TavernTheme._flat(TavernTheme.TIMBER_LIGHT, edge)
		box.content_margin_left = 20.0 * s
		box.content_margin_right = 20.0 * s
		b.add_theme_stylebox_override("normal", box)
		b.add_theme_color_override("font_color", edge.lightened(0.15))
	wire(b)
	return b


## A button for a picture: the theme's padding is sized for words, and on a
## small square it leaves the picture a speck. Lit gold while pressed.
static func snug(b: Button, margin: float = 4.0) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = TavernTheme.TIMBER_LIGHT if state == "hover" else (
			TavernTheme.TIMBER_DARK if state in ["pressed", "hover_pressed"] else TavernTheme.TIMBER)
		box.border_color = TavernTheme.CANDLE if state in ["pressed", "hover_pressed"] else (
			TavernTheme.CANDLE_DIM if state == "hover" else TavernTheme.IRON)
		if state == "focus":
			box.draw_center = false
			box.border_color = Color(0, 0, 0, 0)
		box.set_border_width_all(1)
		box.set_corner_radius_all(TavernTheme.CORNER)
		box.set_content_margin_all(margin)
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_pressed_color", TavernTheme.CANDLE)
	b.add_theme_color_override("font_hover_pressed_color", TavernTheme.CANDLE)


## Hover focuses, focus sounds, press sounds.
static func wire(b: BaseButton) -> void:
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and b.is_visible_in_tree() and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
	)
	b.focus_entered.connect(func() -> void: AudioDirector.play("ui_hover", 0.02))
	b.pressed.connect(func() -> void: AudioDirector.play("ui_click"))


static func _entry_box(bg: Color, accent: int, s: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_width_left = int(round(float(accent) * s))
	box.border_color = TavernTheme.CANDLE
	box.content_margin_left = 20.0 * s
	box.content_margin_right = 16.0 * s
	box.content_margin_top = 8.0 * s
	box.content_margin_bottom = 8.0 * s
	box.set_corner_radius_all(3)
	return box


## A menu panel: dark timber, soft shadow, generous margins.
static func panel_style(s: float, alpha: float = 0.97) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(TavernTheme.TIMBER, alpha)
	box.border_color = TavernTheme.IRON
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = int(round(14.0 * s))
	box.content_margin_left = 28.0 * s
	box.content_margin_right = 28.0 * s
	box.content_margin_top = 22.0 * s
	box.content_margin_bottom = 22.0 * s
	return box


static func heading(text: String, s: float, size: float = 26.0, color: Color = TavernTheme.CANDLE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(round(size * s)))
	l.add_theme_color_override("font_color", color)
	return l


static func caption(text: String, s: float, size: float = 14.0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", int(round(size * s)))
	l.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	return l


## A thin rule between groups.
static func rule(s: float) -> HSeparator:
	var line := HSeparator.new()
	var box := StyleBoxLine.new()
	box.color = Color(TavernTheme.IRON, 0.6)
	box.thickness = maxi(1, int(round(s)))
	line.add_theme_stylebox_override("separator", box)
	line.add_theme_constant_override("separation", int(round(10.0 * s)))
	return line


## Whatever sits behind a menu, darkened, and blocking clicks to it.
static func dim(alpha: float = 0.6) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.025, 0.02, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## How long ago a unix time was, the way a save list says it.
static func ago(unix_time: int) -> String:
	if unix_time <= 0:
		return "a while ago"
	var seconds: int = maxi(0, int(Time.get_unix_time_from_system()) - unix_time)
	if seconds < 60:
		return "just now"
	if seconds < 3600:
		return "%d min ago" % (seconds / 60)
	if seconds < 86400:
		return "%d h ago" % (seconds / 3600)
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%d-%02d-%02d" % [date["year"], date["month"], date["day"]]
