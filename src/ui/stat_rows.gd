class_name StatRows
extends RefCounted

## Draws WorldStats rows into a box. Shared by the hover card and the
## inspector, so a figure looks the same wherever it is read.

## Width of the label column, so values line up down the card.
const LABEL_WIDTH: float = 92.0


## `value_width` is the room the value column will actually get. Wrapping
## labels measure themselves at zero width on their first frame, and a panel
## sized from that measurement comes out several screens tall.
static func render(box: VBoxContainer, rows: Array, compact: bool = false, value_width: float = 0.0) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for row in rows:
		match String(row["t"]):
			"title":
				var title: Label = _label(row["text"], 16 if compact else 17, TavernTheme.PARCHMENT)
				if row.get("icon") is Texture2D:
					var head := HBoxContainer.new()
					head.mouse_filter = Control.MOUSE_FILTER_IGNORE
					head.add_theme_constant_override("separation", 6)
					head.add_child(IconStudio.rect(row["icon"], 30.0 if compact else 36.0))
					title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					head.add_child(title)
					box.add_child(head)
				else:
					box.add_child(title)
			"sub":
				box.add_child(_label(row["text"], 11, TavernTheme.CANDLE_DIM))
			"stat":
				if not row.get("goods", []).is_empty():
					box.add_child(_goods(row["label"], row["goods"], row.get("colour", TavernTheme.PARCHMENT_DIM), value_width))
				else:
					box.add_child(_stat(row["label"], row["value"], row.get("colour", TavernTheme.PARCHMENT_DIM), value_width))
			"bar":
				box.add_child(_bar(row["label"], row["fraction"], row["text"], row["colour"]))
			"stars":
				box.add_child(_stars(row["label"], int(row["stars"]), row["text"], row["colour"]))
			"line":
				if row.get("recipe") is Recipe:
					var made: GoodsStrip = GoodsStrip.recipe(row["recipe"], 24.0, 12, row.get("colour", TavernTheme.PARCHMENT_DIM))
					made.tooltip_text = row["text"]
					box.add_child(made)
				else:
					var line: Label = _label(row["text"], 12, row.get("colour", TavernTheme.PARCHMENT_DIM))
					line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					if value_width > 0.0:
						line.custom_minimum_size.x = value_width + LABEL_WIDTH + 8.0
					box.add_child(line)
			"rule":
				if not compact:
					var rule := ColorRect.new()
					rule.color = TavernTheme.IRON
					rule.custom_minimum_size = Vector2(0, 1)
					rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
					box.add_child(rule)
	# The hover card never takes the mouse: it sits under the pointer, and a
	# picture holding its tooltip would swallow the click meant for the world.
	if compact:
		for child in box.get_children():
			_let_mouse_through(child)


static func _let_mouse_through(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_let_mouse_through(child)


static func _stat(label_text: String, value: String, colour: Color, value_width: float = 0.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var label: Label = _label(label_text, 12, TavernTheme.IRON.lightened(0.25))
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(label)
	var shown: Label = _label(value, 13, colour)
	shown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if value_width > 0.0:
		shown.custom_minimum_size.x = value_width
	row.add_child(shown)
	return row


## A labelled row of goods: pictures with counts where the words would be.
## The words stay on the row, for tests and anything else reading it as text.
static func _goods(label_text: String, goods: Array, colour: Color, value_width: float = 0.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var label: Label = _label(label_text, 12, TavernTheme.IRON.lightened(0.25))
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var strip: GoodsStrip = GoodsStrip.of(goods, 26.0, 13, colour)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if value_width > 0.0:
		strip.custom_minimum_size.x = value_width
	row.add_child(strip)
	return row


## A labelled gauge: patience draining, a loaf baking. Drawn with two flat
## rectangles rather than a ProgressBar, whose theme would need restyling to
## sit on a timber panel and whose percentage text cannot say "restless".
static func _bar(label_text: String, fraction: float, text: String, colour: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var label: Label = _label(label_text, 12, TavernTheme.IRON.lightened(0.25))
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(label)

	var track := Panel.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.custom_minimum_size = Vector2(70, 10)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = TavernTheme.TIMBER_DARK
	track_style.border_color = TavernTheme.IRON
	track_style.set_border_width_all(1)
	track.add_theme_stylebox_override("panel", track_style)
	row.add_child(track)
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = colour
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(fraction, 0.0, 1.0)
	fill.offset_left = 1
	fill.offset_top = 1
	fill.offset_bottom = -1
	track.add_child(fill)

	var shown: Label = _label(text, 12, colour)
	shown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shown.clip_text = true
	row.add_child(shown)
	return row


static func _stars(label_text: String, count: int, text: String, colour: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var label: Label = _label(label_text, 12, TavernTheme.IRON.lightened(0.25))
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(label)
	var rating: HBoxContainer = StarRating.row(count, text, 13.0, colour, 13)
	row.add_child(rating)
	return row


static func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l
