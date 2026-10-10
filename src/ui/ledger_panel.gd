class_name LedgerPanel
extends VBoxContainer

## The Ledger: today's money line by line, what sold, who came, what is in the
## larder, and the days before.
##
## It used to be a developer's readout -- "stock: flour 1, ... fish 4, fish 3,
## dirty 1", a list of every worker's job, frames per second -- behind the
## button the tutorial sends a newcomer to for "today's money". The money is
## first now, goods are pictures, and the readout lives on F3 in a debug build.

const WIDTH: float = 300.0
## Days shown under "Past days", newest first.
const PAST_DAYS: int = 5
const STOCK_COLUMNS: int = 6

var world  ## TavernWorld
var _key: String = ""


func setup(p_world) -> void:
	world = p_world
	add_theme_constant_override("separation", 5)
	custom_minimum_size.x = WIDTH


## Rebuilt only when something on it changed: the HUD asks four times a second.
func refresh() -> void:
	if world == null or world.ledger == null:
		return
	var key: String = _content_key()
	if key == _key:
		return
	_key = key
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()


func _content_key() -> String:
	var parts: PackedStringArray = PackedStringArray([str(world.clock.day if world.clock != null else 0),
		str(world.ledger.today), str(world.wage_bill()), str(world.ledger.history.size())])
	if world.customers != null:
		var c: CustomerDirector = world.customers
		parts.append("%d/%d/%d/%d/%d/%d" % [c.customers.size(), c.served_count, c.lost_count,
			c.lost_no_seat, c.lost_no_service, c.lost_no_menu])
		parts.append(str(c.consumed_today))
	for entry in _stock():
		parts.append("%s%d" % [entry[0], entry[1]])
	return "|".join(parts)


func _build() -> void:
	var ledger: Ledger = world.ledger
	var head := HBoxContainer.new()
	add_child(head)
	var title: Label = _label("LEDGER", 17, TavernTheme.CANDLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if world.clock != null:
		var day: Label = _label("Day %d" % world.clock.day, 13, TavernTheme.PARCHMENT_DIM)
		day.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(day)

	add_child(_label("Today so far", 12, TavernTheme.CANDLE_DIM))
	var any: bool = false
	for line in Ledger.ORDER:
		var amount: int = int(ledger.today.get(line, 0))
		if amount == 0:
			continue
		any = true
		var income: bool = Ledger.is_income(line)
		add_child(money_row(line_icon(line), Ledger.line_name(line), ("+%dg" if income else "-%dg") % amount,
			TavernTheme.PARCHMENT if income else TavernTheme.PARCHMENT_DIM))
	if not any:
		add_child(_label("Nothing in or out yet.", 12, TavernTheme.PARCHMENT_DIM))
	add_child(_rule())
	var profit: int = ledger.profit()
	add_child(money_row(null, "Profit so far", "%s%dg" % ["+" if profit >= 0 else "", profit],
		TavernTheme.CANDLE if profit >= 0 else TavernTheme.DANGER, 15))
	# Wages are paid at close, so today's figure is not the day's until then.
	var wages: int = world.wage_bill()
	if wages > 0:
		add_child(money_row(line_icon(Ledger.Line.WAGES), "Wages at close", "-%dg" % wages, TavernTheme.PARCHMENT_DIM))
		var after: int = profit - wages
		add_child(money_row(null, "If the day ended now", "%s%dg" % ["+" if after >= 0 else "", after],
			TavernTheme.PARCHMENT if after >= 0 else TavernTheme.DANGER))

	if world.customers != null:
		add_child(_rule())
		var c: CustomerDirector = world.customers
		var sold: Array = GoodsStrip.entries_from(c.consumed_today)
		if not sold.is_empty():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var label: Label = _label("Sold today", 12, TavernTheme.PARCHMENT_DIM)
			label.custom_minimum_size.x = 76
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(label)
			row.add_child(GoodsStrip.of(sold, 24.0, 12, TavernTheme.PARCHMENT, 5))
			add_child(row)
		add_child(money_row(ThoughtBubble.icon("seat"), "Guests",
			"%d in · %d served · %d left" % [c.customers.size(), c.served_count, c.lost_count],
			TavernTheme.PARCHMENT))
		if c.lost_count > 0:
			var why: PackedStringArray = PackedStringArray()
			if c.lost_no_seat > 0:
				why.append("%d for a seat" % c.lost_no_seat)
			if c.lost_no_service > 0:
				why.append("%d waiting on service" % c.lost_no_service)
			if c.lost_no_menu > 0:
				why.append("%d with nothing to order" % c.lost_no_menu)
			var reasons: Label = _label("Left: " + ", ".join(why), 11, TavernTheme.DANGER.lightened(0.25))
			reasons.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reasons.custom_minimum_size.x = WIDTH
			add_child(reasons)

	var stock: Array = _stock()
	add_child(_rule())
	add_child(_label("In stock", 12, TavernTheme.CANDLE_DIM))
	if stock.is_empty():
		add_child(_label("Nothing in the larder.", 12, TavernTheme.PARCHMENT_DIM))
	else:
		# A grid, not a flowing row: a grid knows its height on the frame it is
		# built, and the panel sizes itself from that.
		var grid := GridContainer.new()
		grid.columns = STOCK_COLUMNS
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 2)
		for entry in stock:
			grid.add_child(GoodsStrip.chip(entry[0], str(entry[1]), 22.0, 12, TavernTheme.PARCHMENT))
		add_child(grid)

	if not ledger.history.is_empty():
		add_child(_rule())
		add_child(_label("Past days", 12, TavernTheme.CANDLE_DIM))
		var shown: int = 0
		for i in range(ledger.history.size() - 1, -1, -1):
			if shown >= PAST_DAYS:
				break
			shown += 1
			var entry: Dictionary = ledger.history[i]
			var gained: int = int(entry.get("profit", 0))
			add_child(money_row(null, "Day %d · %d served" % [int(entry.get("day", 0)), int(entry.get("served", 0))],
				"%s%dg" % ["+" if gained >= 0 else "", gained],
				TavernTheme.PARCHMENT if gained >= 0 else TavernTheme.DANGER, 12))


## Every good the tavern holds, carried goods included, most first.
func _stock() -> Array:
	var counts: Dictionary = {}
	for def in ItemCatalog.all():
		var n: int = world.stock_of(def.id)
		if n > 0:
			counts[def.id] = n
	return GoodsStrip.entries_from(counts)


## A picture for each line of the books, shared with the day summary.
static func line_icon(line: int) -> Texture2D:
	match line:
		Ledger.Line.TAKINGS, Ledger.Line.BOOKINGS, Ledger.Line.TIPS, Ledger.Line.SOLD:
			return load("res://assets/prototype/ui/game_icons/coins.svg")
		Ledger.Line.SUPPLIES:
			return IconStudio.item(&"flour")
		Ledger.Line.WAGES, Ledger.Line.HIRING:
			return ThoughtBubble.icon("hand")
		Ledger.Line.CONSTRUCTION, Ledger.Line.REFUNDS:
			return ThoughtBubble.icon("build")
		Ledger.Line.LAND:
			return ThoughtBubble.icon("farm")
	return null


## A line of money: a picture, what it is, how much. Shared with the day summary.
static func money_row(icon: Texture2D, text: String, amount: String, colour: Color, size: int = 13) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(size + 5, size + 5)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != null:
		picture.texture = icon
		# The pixel icons are eleven pixels square: blurred, they are smudges.
		if icon.get_width() <= 16:
			picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if icon.resource_path.ends_with(".svg"):
			picture.modulate = Color("d7b568")
	row.add_child(picture)
	var name_label: Label = _label(text, size, colour)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_label(amount, size, colour))
	return row


static func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


static func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = TavernTheme.IRON
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule
