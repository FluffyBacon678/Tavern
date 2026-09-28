class_name SupplyPanel
extends PanelContainer

## The merchant's order form: pick how much of each ingredient, see what it
## costs and whether the yard can take it, then confirm.
##
## The Supplies button used to buy one fixed bundle on the spot. With a
## ten-minute day a kitchen goes through several of those, and runs short of
## one thing long before the rest -- so the player chooses the order, and the
## money only moves on Confirm.

signal closed

## Each click of - or + moves a line by this much; with Shift, by a whole stack.
const STEP: int = 2

var world  ## TavernWorld
## Ingredient id -> how many are on the order.
var order: Dictionary = {}

var _rows: VBoxContainer
## id -> [count label, stock label, line total label]
var _row_labels: Dictionary = {}
var _total_label: Label
var _problem_label: Label
var _confirm: Button
var _refresh_timer: float = 0.0


func setup(p_world) -> void:
	world = p_world
	_build()
	reset_to_standard()


func _build() -> void:
	custom_minimum_size = Vector2(430, 0)
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var heading := Label.new()
	heading.text = "ORDER SUPPLIES"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	heading.add_theme_font_size_override("font_size", 18)
	column.add_child(heading)

	var note := Label.new()
	note.text = "Pick what the cart brings. Nothing is paid until you confirm. Shift-click moves a whole stack."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 400
	note.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	note.add_theme_font_size_override("font_size", 12)
	column.add_child(note)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	column.add_child(_rows)
	for def in ItemCatalog.purchasable():
		_rows.add_child(_row(def))

	_total_label = Label.new()
	_total_label.add_theme_color_override("font_color", TavernTheme.CANDLE)
	column.add_child(_total_label)
	_problem_label = Label.new()
	_problem_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problem_label.custom_minimum_size.x = 400
	_problem_label.add_theme_color_override("font_color", TavernTheme.DANGER)
	_problem_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_problem_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	column.add_child(buttons)
	buttons.add_child(_button("Standard", "The merchant's usual bundle: enough for eight loaves and six brews", func() -> void:
		reset_to_standard()
	))
	buttons.add_child(_button("Clear", "Take everything off the order", func() -> void:
		for id in order:
			order[id] = 0
		refresh()
	))
	_confirm = _button("Confirm", "", func() -> void:
		if world.order_supplies(order):
			AudioDirector.play("ui_click")
			visible = false
			closed.emit()
		else:
			AudioDirector.play("ui_back")
			refresh()
	)
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_confirm)
	buttons.add_child(_button("Close", "Close without ordering", func() -> void:
		AudioDirector.play("ui_back")
		visible = false
		closed.emit()
	))


func _row(def: ItemDef) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name := Label.new()
	name.text = "%s  ·  %dg" % [def.display_name, def.purchase_price]
	name.custom_minimum_size.x = 150
	row.add_child(name)
	var stock := Label.new()
	stock.custom_minimum_size.x = 80
	stock.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	stock.add_theme_font_size_override("font_size", 12)
	stock.tooltip_text = "How many the tavern has now, on shelves, benches and in hands"
	stock.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(stock)
	var id: StringName = def.id
	row.add_child(_step_button("−", id, -1, def.stack_size))
	var count := Label.new()
	count.custom_minimum_size.x = 34
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count)
	row.add_child(_step_button("+", id, 1, def.stack_size))
	var line := Label.new()
	line.custom_minimum_size.x = 50
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(line)
	_row_labels[id] = [count, stock, line]
	return row


func _step_button(text: String, id: StringName, direction: int, stack: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 30)
	b.tooltip_text = "%s %d (Shift: %d)" % ["Add" if direction > 0 else "Remove", STEP, stack]
	b.pressed.connect(func() -> void:
		AudioDirector.play("ui_click")
		var amount: int = stack if Input.is_key_pressed(KEY_SHIFT) else STEP
		order[id] = maxi(0, int(order.get(id, 0)) + direction * amount)
		refresh()
	)
	return b


func _button(text: String, hint: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = hint
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	return b


func reset_to_standard() -> void:
	order.clear()
	for def in ItemCatalog.purchasable():
		order[def.id] = 0
	for id in world.STANDARD_ORDER:
		order[id] = int(world.STANDARD_ORDER[id])
	refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		theme = TavernTheme.build(TavernTheme.scale_for_control(self) * 0.8)
		refresh()


## Re-read the purse, the stock and the yard. Cheap, so it runs while open:
## the answer to "can I afford it" changes as the tavern trades.
func refresh() -> void:
	if world == null or _total_label == null:
		return
	for id in _row_labels:
		var labels: Array = _row_labels[id]
		var n: int = int(order.get(id, 0))
		var def: ItemDef = ItemCatalog.get_def(id)
		labels[0].text = str(n)
		labels[1].text = "have %d" % world.stock_of(id)
		labels[2].text = "%dg" % (def.purchase_price * n) if n > 0 else "—"
	var cost: int = world.order_cost(order)
	_total_label.text = "Cart fee %dg  ·  Total %dg  ·  Purse %dg" % [
		world.DELIVERY_FEE if cost > 0 else 0, cost, GameState.gold]
	var problem: String = world.order_problem(order)
	_problem_label.text = problem
	_problem_label.visible = not problem.is_empty()
	_confirm.disabled = not problem.is_empty()
	_confirm.text = "Confirm — %dg" % cost if cost > 0 else "Confirm"
	_confirm.tooltip_text = problem if not problem.is_empty() else "Pay %dg and have it unloaded in the yard" % cost


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		refresh()
