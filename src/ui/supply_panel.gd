class_name SupplyPanel
extends PanelContainer

## Meals first: one stock target buys the missing ingredients and drives the kitchen.
## The one-off ingredient cart remains available behind a secondary action.

signal closed

## Each click of - or + moves a line by this much; with Shift, by a whole stack.
const STEP: int = 2

var world  ## TavernWorld
## Ingredient id -> how many are on the order.
var order: Dictionary = {}

var _meals: VBoxContainer
var _manual: VBoxContainer
var _meal_widgets: Dictionary = {}
var _auto_toggle: CheckBox
var _auto_note: Label
var _clear_blocks: Button
var _rows: VBoxContainer
## id -> [count label, stock label, line total label]
var _row_labels: Dictionary = {}
var _total_label: Label
var _problem_label: Label
var _confirm: Button
var _refresh_timer: float = 0.0
var _theme_scale: float = -1.0


func setup(p_world) -> void:
	world = p_world
	_build()
	reset_to_standard()


func _build() -> void:
	visible = false
	# Canvas stretch can render at fractional scale (0.8 at 1024x768).
	# Nearest filtering drops rows of small glyphs; UI text needs interpolation.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	custom_minimum_size = Vector2(420, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var heading := Label.new()
	heading.text = "STORES"
	heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	heading.add_theme_font_size_override("font_size", 17)
	column.add_child(heading)
	_auto_toggle = CheckBox.new()
	_auto_toggle.text = "Auto restock"
	_auto_toggle.custom_minimum_size.y = 32
	_auto_toggle.add_theme_font_size_override("font_size", 13)
	_auto_toggle.toggled.connect(func(on: bool) -> void:
		world.auto_supply.enabled = on
		world.auto_supply.configured = true
		refresh()
	)
	column.add_child(_auto_toggle)
	_auto_note = _caption("", 12)
	column.add_child(_auto_note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_meals = VBoxContainer.new()
	_meals.add_theme_constant_override("separation", 8)
	body.add_child(_meals)
	for recipe in MealSupplyPlan.meals():
		_meals.add_child(_meal_row(recipe))
	_auto_toggle.tooltip_text = "Uses stock and harvested ingredients first. Orders share one cart and keep tonight's wages aside."
	var links := HBoxContainer.new()
	column.add_child(links)
	links.add_child(_button("Order ingredients manually…", "A one-off cart, with a price preview", show_manual))
	links.add_child(_button("Kitchen details…", "Advanced recipe controls and station activity", func() -> void:
		hide()
		world.hud._production_panel.toggle()
	))
	_clear_blocks = _button("Allow all ingredients", "Clear ingredient exclusions carried over from old settings", func() -> void:
		world.auto_supply.never.clear()
		refresh()
	)
	_meals.add_child(_clear_blocks)
	_manual = VBoxContainer.new()
	_manual.visible = false
	_manual.add_theme_constant_override("separation", 6)
	body.add_child(_manual)
	_manual.add_child(_button("‹ Back to meals", "", func() -> void:
		_manual.hide()
		_meals.show()
	))
	_manual.add_child(_caption("One-off delivery. Nothing is paid until Confirm.", 12))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_manual.add_child(_rows)
	for def in ItemCatalog.purchasable():
		_rows.add_child(_row(def))
	_total_label = _caption("", 12)
	_manual.add_child(_total_label)
	_problem_label = _caption("", 12)
	_problem_label.add_theme_color_override("font_color", TavernTheme.DANGER)
	_manual.add_child(_problem_label)
	var buttons := HBoxContainer.new()
	_manual.add_child(buttons)
	buttons.add_child(_button("Standard", "The usual opening ingredients", reset_to_standard))
	buttons.add_child(_button("Clear", "Empty this cart", func() -> void:
		order.clear()
		refresh()
	))
	_confirm = _button("Confirm", "", func() -> void:
		if world.order_supplies(order):
			AudioDirector.play("ui_click")
			hide()
			closed.emit()
		refresh()
	)
	buttons.add_child(_confirm)
	column.add_child(_button("Close", "", func() -> void:
		hide()
		closed.emit()
	))


func _caption(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 18
	label.add_theme_font_size_override("font_size", maxi(12, font_size))
	label.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	return label


func _meal_row(recipe: Recipe) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	row.add_child(IconStudio.rect(IconStudio.recipe(recipe), 34.0))
	var toggle := CheckBox.new()
	toggle.text = ItemCatalog.get_def(recipe.outputs[0]["id"]).display_name
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.custom_minimum_size.y = 32
	toggle.add_theme_font_size_override("font_size", 13)
	toggle.tooltip_text = "Keep this meal in stock and buy its missing ingredients. Turning it off stops making it."
	toggle.toggled.connect(func(on: bool) -> void:
		world.auto_supply.set_meal(recipe.id, on, int(world.bills.get_bill(recipe.id)["target"]))
		refresh()
	)
	row.add_child(toggle)
	var below := Label.new()
	below.text = "Restock below"
	below.add_theme_font_size_override("font_size", 12)
	row.add_child(below)
	row.add_child(_button("−", "Lower target by 1", _adjust_meal.bind(recipe.id, -1)))
	var amount := Label.new()
	amount.custom_minimum_size.x = 26
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.add_theme_font_size_override("font_size", 13)
	row.add_child(amount)
	row.add_child(_button("+", "Raise target by 1", _adjust_meal.bind(recipe.id, 1)))
	# What it is made from, as pictures: the names are the tooltips.
	var needs := HBoxContainer.new()
	needs.add_theme_constant_override("separation", 6)
	needs.tooltip_text = "Needs: " + MealSupplyPlan.ingredients(recipe)
	needs.mouse_filter = Control.MOUSE_FILTER_PASS
	var label := _caption("Needs", 11)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	needs.add_child(label)
	var kinds: Array = []
	for id in MealSupplyPlan.ingredient_ids(recipe):
		kinds.append([id, -1])
	needs.add_child(GoodsStrip.of(kinds, 24.0, 11, TavernTheme.PARCHMENT_DIM, 6))
	box.add_child(needs)
	var stock := _caption("", 11)
	stock.add_theme_color_override("font_color", TavernTheme.CANDLE)
	box.add_child(stock)
	box.add_child(HSeparator.new())
	_meal_widgets[recipe.id] = {"toggle": toggle, "amount": amount, "stock": stock}
	return box


func _adjust_meal(id: StringName, delta: int) -> void:
	var bill: Dictionary = world.bills.get_bill(id)
	world.auto_supply.set_meal(id, bool(bill["enabled"]), int(bill["target"]) + delta)
	refresh()


func show_manual() -> void:
	_manual.show()
	_meals.hide()
	refresh()


func _fit_screen() -> void:
	var area: Vector2 = get_viewport().get_visible_rect().size
	var wanted_scale: float = TavernTheme.scale_for_control(self) * 0.8
	if not is_equal_approx(wanted_scale, _theme_scale):
		_theme_scale = wanted_scale
		theme = TavernTheme.build(wanted_scale)
	custom_minimum_size.x = minf(420.0, area.x - 24.0)
	size = Vector2(custom_minimum_size.x, minf(535.0, maxf(120.0, area.y - position.y - 12.0)))

func _row(def: ItemDef) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(IconStudio.rect(IconStudio.item(def.id), 28.0))
	var name := Label.new()
	name.text = "%s  ·  %dg" % [def.display_name, def.purchase_price]
	name.custom_minimum_size.x = 112
	row.add_child(name)
	var stock := Label.new()
	stock.custom_minimum_size.x = 52
	stock.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	stock.add_theme_font_size_override("font_size", 12)
	stock.tooltip_text = "How many the tavern has now, on shelves, benches and in hands"
	stock.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(stock)
	var id: StringName = def.id
	row.add_child(_step_button("−", id, -1, def.stack_size))
	var count := Label.new()
	count.custom_minimum_size.x = 24
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count)
	row.add_child(_step_button("+", id, 1, def.stack_size))
	var line := Label.new()
	line.custom_minimum_size.x = 38
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(line)
	_row_labels[id] = [count, stock, line]
	return row


func _step_button(text: String, id: StringName, direction: int, stack: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(32, 32)
	b.add_theme_font_size_override("font_size", 12)
	_compact_style(b)
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
	b.custom_minimum_size = Vector2(32, 32)
	b.add_theme_font_size_override("font_size", 12)
	_compact_style(b)
	b.pressed.connect(handler)
	return b


func _compact_style(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = TavernTheme.TIMBER_DARK.lightened(0.08 if state == "hover" else 0.0)
		style.border_color = TavernTheme.CANDLE_DIM if state == "hover" else TavernTheme.IRON
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		style.content_margin_left = 7
		style.content_margin_right = 7
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		button.add_theme_stylebox_override(state, style)


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
		_manual.hide()
		_meals.show()
	if visible:
		refresh()


## Re-read the purse, the stock and the yard. Cheap, so it runs while open:
## the answer to "can I afford it" changes as the tavern trades.
func refresh() -> void:
	if world == null or world.build == null or _total_label == null:
		return
	_fit_screen()
	_auto_toggle.set_pressed_no_signal(world.auto_supply.enabled)
	_clear_blocks.visible = not world.auto_supply.never.is_empty()
	for recipe in MealSupplyPlan.meals():
		var bill: Dictionary = world.bills.get_bill(recipe.id)
		var widgets: Dictionary = _meal_widgets[recipe.id]
		widgets["toggle"].set_pressed_no_signal(bool(bill["enabled"]))
		widgets["amount"].text = str(bill["target"])
		var stock: int = world.stock_of(recipe.outputs[0]["id"])
		var status: String = "%d in stock" % stock
		if not bill["enabled"]:
			status += " · off"
		elif world.build.grid.count_built([recipe.station_id]) == 0:
			status += " · needs " + BuildingCatalog.get_def(recipe.station_id).display_name
		elif recipe.id == &"bake_bread" and world.build.grid.count_built([&"prep_table"]) == 0:
			status += " · needs Prep Table"
		elif recipe.id == &"fish_soup" or recipe.id == &"grill_fish":
			status += " · fish must be caught locally"
		widgets["stock"].text = status
	var auto: AutoSupply = world.auto_supply
	_auto_note.tooltip_text = ""
	if not auto.enabled:
		_auto_note.text = "Auto restock paused. Existing kitchen orders still run."
	elif not auto.started():
		_auto_note.text = "Set a meal target or enable a meal to start restocking."
	elif not auto.note.is_empty():
		_auto_note.text = auto.note
	else:
		var plan: Dictionary = MealSupplyPlan.new().calculate(world, auto.never)
		var wanted: Dictionary = plan["buy"]
		_auto_note.text = "Next cart: %dg · keeping %dg for wages" % [world.order_cost(wanted), world.wage_bill()] if not wanted.is_empty() else "No ingredients to buy right now."
		_auto_note.tooltip_text = AutoSupply.describe(wanted)
		if not plan["blocked"].is_empty():
			var waiting: String = "Waiting on kitchen or local ingredients: " + ", ".join(plan["blocked"])
			if wanted.is_empty():
				_auto_note.text = waiting
			_auto_note.tooltip_text += "\n" + waiting + ". Check the meal rows and Kitchen details."
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


