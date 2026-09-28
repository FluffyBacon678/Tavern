class_name DaySummary
extends Control

## The end-of-day reckoning.
##
## Deliberately a full-screen stop rather than a toast in the corner. The day
## ending is the moment the player is supposed to think -- did that delivery pay
## for itself, is the third cook earning their wage -- and a panel that can be
## ignored while the tavern keeps running would waste it.

## The player chose to leave for the main menu from a settled level's verdict.
signal leave_requested
signal dismissed

var _panel: PanelContainer
var _rows: VBoxContainer


func _ready() -> void:
	# ...and_offsets_, not just set_anchors_preset. The latter rewrites the
	# offsets to preserve the control's current rect, and a freshly constructed
	# Control has a zero rect -- so it anchors to full screen and stays 0x0,
	# collapsing to its content in the top-left corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks so the world beneath cannot be built on while the day is
	# being totted up.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.02, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(420, 0)
	centre.add_child(_panel)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	_panel.add_child(_rows)


## How many of the day's verdicts to print. Enough to see a pattern, few enough
## that the panel stays a summary.
const REVIEWS_SHOWN: int = 3


## `verdict` is the level's result on the close that settled it -- {won, title,
## text} from LevelDef.verdict_for() -- or empty on every other evening.
func show_day(entry: Dictionary, tavern_name: String, standing: Reputation = null, reviews: Array[Review] = [], verdict: Dictionary = {}) -> void:
	theme = TavernTheme.build(TavernTheme.scale_for_control(self) * 0.95)
	for child in _rows.get_children():
		child.queue_free()

	var heading := Label.new()
	heading.text = "DAY %d AT %s" % [entry["day"], tavern_name.to_upper()]
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	heading.add_theme_font_size_override("font_size", 22)
	_rows.add_child(heading)
	if not verdict.is_empty():
		_rows.add_child(_verdict_banner(verdict))

	var trade := Label.new()
	trade.text = "%d served · %d walked out" % [entry["served"], entry["lost"]]
	trade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trade.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	_rows.add_child(trade)

	if standing != null:
		var rep: HBoxContainer = StarRating.row(standing.stars(), standing.label(), 15.0, TavernTheme.CANDLE, 15)
		rep.alignment = BoxContainer.ALIGNMENT_CENTER
		_rows.add_child(rep)

	_rows.add_child(_rule())

	var lines: Dictionary = entry["lines"]
	# Every line the day used, so the rows always add up to the profit under
	# them. Land and hiring were left off, and the sum did not.
	for line in Ledger.ORDER:
		var amount: int = int(lines.get(line, lines.get(str(line), 0)))
		if amount == 0:
			continue
		var income: bool = Ledger.is_income(line)
		_rows.add_child(_money_row(
			Ledger.line_name(line),
			("+%dg" % amount) if income else ("-%dg" % amount),
			TavernTheme.PARCHMENT if income else TavernTheme.PARCHMENT_DIM
		))

	_rows.add_child(_rule())

	var profit: int = entry["profit"]
	_rows.add_child(_money_row(
		"Profit" if profit >= 0 else "Loss",
		"%s%dg" % ["+" if profit >= 0 else "", profit],
		TavernTheme.CANDLE if profit >= 0 else TavernTheme.DANGER,
		20
	))
	# A day of building reads as a heavy loss even when trade went well, and a
	# new player takes that to mean the tavern is failing. Trade on its own line.
	var spent_building: int = int(lines.get(Ledger.Line.CONSTRUCTION, lines.get(str(Ledger.Line.CONSTRUCTION), 0))) 		+ int(lines.get(Ledger.Line.LAND, lines.get(str(Ledger.Line.LAND), 0))) 		+ int(lines.get(Ledger.Line.HIRING, lines.get(str(Ledger.Line.HIRING), 0))) 		- int(lines.get(Ledger.Line.REFUNDS, lines.get(str(Ledger.Line.REFUNDS), 0)))
	if spent_building > 0:
		var from_trade: int = profit + spent_building
		_rows.add_child(_money_row("From trade alone", "%s%dg" % ["+" if from_trade >= 0 else "", from_trade],
			TavernTheme.PARCHMENT if from_trade >= 0 else TavernTheme.DANGER))
	_rows.add_child(_money_row("In the purse", "%dg" % entry["purse"], TavernTheme.PARCHMENT_DIM))

	# What people actually said, in their words. The notes are firm that a
	# satisfaction number the player cannot explain is no use to them, so the
	# panel spends its space on the reasons rather than on more figures.
	if not reviews.is_empty():
		_rows.add_child(_rule())
		var heard := Label.new()
		heard.text = "What they said"
		heard.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
		heard.add_theme_font_size_override("font_size", 13)
		_rows.add_child(heard)
		# One fewer on the night of a verdict, so the panel still fits a small
		# screen with the banner above it.
		for review in reviews.slice(0, REVIEWS_SHOWN - (1 if not verdict.is_empty() else 0)):
			_rows.add_child(_review_row(review))

	if entry["purse"] < 0:
		var warning := Label.new()
		# Things that can actually be done: there is nothing to sell up.
		warning.text = "You are in debt. Let staff go under Staff (K), cancel unbuilt blueprints for a full refund, or demolish for half back."
		warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.add_theme_color_override("font_color", TavernTheme.DANGER)
		_rows.add_child(warning)

	var button := Button.new()
	button.text = "Open tomorrow" if verdict.is_empty() else "Keep trading"
	button.pressed.connect(func() -> void:
		AudioDirector.play("ui_click")
		visible = false
		dismissed.emit()
	)
	if verdict.is_empty():
		_rows.add_child(button)
	else:
		# The level is settled either way, so leaving is a real choice now and
		# earns a button of its own; the day is already saved.
		var choices := HBoxContainer.new()
		choices.add_theme_constant_override("separation", 10)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices.add_child(button)
		var leave := Button.new()
		leave.text = "Main menu"
		leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		leave.pressed.connect(func() -> void:
			AudioDirector.play("ui_back")
			leave_requested.emit()
		)
		choices.add_child(leave)
		_rows.add_child(choices)
	button.call_deferred("grab_focus")
	visible = true


func _verdict_banner(verdict: Dictionary) -> PanelContainer:
	var won: bool = bool(verdict.get("won", false))
	var banner := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(TavernTheme.CANDLE, 0.12) if won else Color(TavernTheme.DANGER, 0.14)
	style.border_color = TavernTheme.CANDLE if won else TavernTheme.DANGER
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	banner.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	banner.add_child(column)
	var title := Label.new()
	title.text = String(verdict.get("title", "")).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TavernTheme.CANDLE if won else TavernTheme.DANGER)
	column.add_child(title)
	var text := Label.new()
	text.text = String(verdict.get("text", ""))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(360, 0)
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_color_override("font_color", TavernTheme.PARCHMENT)
	column.add_child(text)
	return banner


## One verdict: who, how many stars, and the sentence that explains it.
func _review_row(review: Review) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var head: HBoxContainer = StarRating.row(review.stars, review.patron, 12.0,
		TavernTheme.CANDLE if review.stars >= 4 else (
			TavernTheme.DANGER if review.stars <= 2 else TavernTheme.PARCHMENT
		), 13)
	box.add_child(head)

	var quote := Label.new()
	quote.text = "\"%s\"" % review.quote
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.add_theme_font_size_override("font_size", 12)
	quote.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	box.add_child(quote)
	return box


func _money_row(label_text: String, amount_text: String, colour: Color, size: int = 15) -> HBoxContainer:
	var row := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", colour)
	name_label.add_theme_font_size_override("font_size", size)
	row.add_child(name_label)

	var value := Label.new()
	value.text = amount_text
	value.add_theme_color_override("font_color", colour)
	value.add_theme_font_size_override("font_size", size)
	row.add_child(value)
	return row


func _rule() -> Control:
	var line := ColorRect.new()
	line.color = TavernTheme.IRON
	line.custom_minimum_size = Vector2(0, 1)
	return line
