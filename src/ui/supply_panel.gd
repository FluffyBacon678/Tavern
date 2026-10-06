class_name SupplyPanel
extends PanelContainer

## The tavern's stores, laid out like a game shop, in two tabs.
##
## Restock: one stock target per meal. The targets drive the kitchen and buy
## the missing ingredients by themselves, in shared carts that keep tonight's
## wages aside. Each meal shows its dish, what it needs, and a gauge of how
## near the shelves are to the target.
##
## Merchant: the supplier's wares as picture slots, priced, with how many the
## tavern already has. Choose how many a click buys, click a ware to put it on
## the cart (right-click, or the yard space it would land in, takes it off),
## and see the cart land in the unloading yard before paying. The yard is what
## limits an order, so it is drawn here, as RuneScape draws an inventory,
## rather than explained in an error after the fact.

signal closed

## What one click on a ware adds; 0 is a whole stack.
const QUANTITIES: Array[int] = [1, 5, 10, 0]
## A ware's picture, and a yard space's.
const SLOT: float = 54.0
const WIDTH: float = 560.0
const GOOD := Color("8fb46a")
const WARN := Color("e0a050")

var world  ## TavernWorld
## Item id -> how many are on the cart.
var order: Dictionary = {}
## What a click on a ware adds; 0 for a whole stack.
var quantity: int = 5

var _restock_tab: Button
var _merchant_tab: Button
## The Restock tab: meal targets. (Named for the meal list it first held.)
var _meals: VBoxContainer
## The Merchant tab: the one-off cart.
var _manual: VBoxContainer
var _meal_widgets: Dictionary = {}
var _auto_toggle: CheckBox
var _auto_note: Label
var _next_cart: HBoxContainer
var _next_cart_key: String = ""
var _clear_blocks: Button
## id -> {"have": Label, "ordered": Label}
var _wares: Dictionary = {}
var _quantity_buttons: Array[Button] = []
var _ware_info: Label
var _yard_caption: Label
var _yard_row: HBoxContainer
var _yard_key: String = ""
var _total_label: Label
var _purse_label: Label
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
	custom_minimum_size = Vector2(WIDTH, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	column.add_child(head)
	var heading := Label.new()
	heading.text = "STORES"
	heading.add_theme_color_override("font_color", TavernTheme.CANDLE)
	heading.add_theme_font_size_override("font_size", 17)
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(heading)
	var gap := Control.new()
	gap.custom_minimum_size.x = 12
	head.add_child(gap)
	var tabs := ButtonGroup.new()
	_restock_tab = _tab("Restock", "What to keep in stock. The ingredients are bought by themselves.", tabs, show_meals)
	head.add_child(_restock_tab)
	_merchant_tab = _tab("Merchant", "Buy ingredients now: one cart, unloaded in the yard", tabs, show_manual)
	head.add_child(_merchant_tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_button("×", "Close", func() -> void:
		AudioDirector.play("ui_back")
		hide()
		closed.emit()
	))

	_build_restock(column)
	_build_merchant(column)
	_restock_tab.set_pressed_no_signal(true)


# --- Restock -----------------------------------------------------------------

func _build_restock(column: VBoxContainer) -> void:
	_meals = VBoxContainer.new()
	_meals.add_theme_constant_override("separation", 6)
	_meals.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_meals)
	_auto_toggle = CheckBox.new()
	_auto_toggle.text = "Auto restock"
	_auto_toggle.custom_minimum_size.y = 32
	_auto_toggle.add_theme_font_size_override("font_size", 14)
	_auto_toggle.tooltip_text = "Buys what the meals below are short of, in shared carts. Stock and home-grown goods count first, and tonight's wages stay in the purse."
	_auto_toggle.toggled.connect(func(on: bool) -> void:
		world.auto_supply.enabled = on
		world.auto_supply.configured = true
		refresh()
	)
	_meals.add_child(_auto_toggle)
	_auto_note = _caption("", 12)
	_meals.add_child(_auto_note)
	# The next cart, as the goods it will bring.
	_next_cart = HBoxContainer.new()
	_next_cart.add_theme_constant_override("separation", 6)
	_meals.add_child(_next_cart)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_meals.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for recipe in MealSupplyPlan.meals():
		list.add_child(_meal_row(recipe))
	_clear_blocks = _button("Allow all ingredients", "Clear ingredient exclusions carried over from old settings", func() -> void:
		world.auto_supply.never.clear()
		refresh()
	)
	list.add_child(_clear_blocks)
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 6)
	_meals.add_child(links)
	links.add_child(_button("Kitchen details…", "Every recipe's standing order, and what each bench is doing", func() -> void:
		hide()
		world.hud._production_panel.toggle()
	))
	links.add_child(_button("Buy something now…", "The merchant: one cart, delivered at once", show_manual))


## One meal: its dish, the switch and the target, a gauge of the stock against
## it, and what it is made from.
func _meal_row(recipe: Recipe) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(IconStudio.rect(IconStudio.recipe(recipe), 44.0))
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 2)
	row.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	body.add_child(top)
	var toggle := CheckBox.new()
	toggle.text = ItemCatalog.get_def(recipe.outputs[0]["id"]).display_name
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.custom_minimum_size.y = 32
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.tooltip_text = "Keep this meal in stock and buy its missing ingredients. Off stops making it."
	toggle.toggled.connect(func(on: bool) -> void:
		world.auto_supply.set_meal(recipe.id, on, int(world.bills.get_bill(recipe.id)["target"]))
		refresh()
	)
	top.add_child(toggle)
	var keep := Label.new()
	keep.text = "Keep"
	keep.add_theme_font_size_override("font_size", 12)
	keep.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	keep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(keep)
	top.add_child(_button("−", "Keep one fewer", _adjust_meal.bind(recipe.id, -1)))
	var amount := Label.new()
	amount.custom_minimum_size.x = 28
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.add_theme_font_size_override("font_size", 14)
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(amount)
	top.add_child(_button("+", "Keep one more", _adjust_meal.bind(recipe.id, 1)))

	var second := HBoxContainer.new()
	second.add_theme_constant_override("separation", 8)
	body.add_child(second)
	var track := Panel.new()
	track.custom_minimum_size = Vector2(110, 10)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = TavernTheme.TIMBER_DARK
	track_style.border_color = TavernTheme.IRON
	track_style.set_border_width_all(1)
	track.add_theme_stylebox_override("panel", track_style)
	second.add_child(track)
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_bottom = 1.0
	fill.offset_left = 1
	fill.offset_top = 1
	fill.offset_bottom = -1
	track.add_child(fill)
	var stock := Label.new()
	stock.add_theme_font_size_override("font_size", 12)
	stock.custom_minimum_size.x = 84
	stock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	second.add_child(stock)
	var needs := HBoxContainer.new()
	needs.add_theme_constant_override("separation", 6)
	needs.tooltip_text = "Needs: " + MealSupplyPlan.ingredients(recipe)
	needs.mouse_filter = Control.MOUSE_FILTER_PASS
	needs.add_child(_inline("Needs"))
	var kinds: Array = []
	for id in MealSupplyPlan.ingredient_ids(recipe):
		kinds.append([id, -1])
	needs.add_child(GoodsStrip.of(kinds, 24.0, 11, TavernTheme.PARCHMENT_DIM, 6))
	second.add_child(needs)

	# One short sentence, only when something stands in the way: unwrapped,
	# so it measures its true width on the first frame.
	var status := _inline("")
	status.add_theme_font_size_override("font_size", 11)
	body.add_child(status)
	_meal_widgets[recipe.id] = {"toggle": toggle, "amount": amount, "stock": stock, "fill": fill, "status": status}
	return card


func _adjust_meal(id: StringName, delta: int) -> void:
	var bill: Dictionary = world.bills.get_bill(id)
	world.auto_supply.set_meal(id, bool(bill["enabled"]), int(bill["target"]) + delta)
	refresh()


# --- Merchant ----------------------------------------------------------------

func _build_merchant(column: VBoxContainer) -> void:
	_manual = VBoxContainer.new()
	_manual.visible = false
	_manual.add_theme_constant_override("separation", 6)
	_manual.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_manual)
	# No scroll: the shop, the yard and the bill fit any screen the game runs
	# at, and the panel shrinks to them rather than leaving a gap.
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	_manual.add_child(body)

	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 4)
	body.add_child(buy_row)
	buy_row.add_child(_inline("A click buys"))
	var counts := ButtonGroup.new()
	for q in QUANTITIES:
		var chosen: int = q
		var b: Button = _tab("Stack" if q == 0 else str(q),
			"A whole stack per click" if q == 0 else "%d per click" % q, counts, func() -> void:
				quantity = chosen
				refresh())
		b.custom_minimum_size = Vector2(44, 32)
		b.set_pressed_no_signal(q == quantity)
		_quantity_buttons.append(b)
		buy_row.add_child(b)
	var take_off := _inline("· right-click takes off")
	take_off.add_theme_color_override("font_color", TavernTheme.IRON.lightened(0.3))
	buy_row.add_child(take_off)

	var shelf := HBoxContainer.new()
	shelf.add_theme_constant_override("separation", 6)
	body.add_child(shelf)
	for def in ItemCatalog.purchasable():
		shelf.add_child(_ware(def))
	_ware_info = _caption("Click a ware to put it on the cart.", 12)
	body.add_child(_ware_info)

	body.add_child(_rule())
	_yard_caption = _caption("", 12)
	body.add_child(_yard_caption)
	_yard_row = HBoxContainer.new()
	_yard_row.add_theme_constant_override("separation", 4)
	body.add_child(_yard_row)

	_manual.add_child(_rule())
	_total_label = Label.new()
	_total_label.add_theme_font_size_override("font_size", 14)
	_manual.add_child(_total_label)
	_purse_label = _caption("", 12)
	_manual.add_child(_purse_label)
	_problem_label = _caption("", 12)
	_problem_label.add_theme_color_override("font_color", TavernTheme.DANGER)
	_manual.add_child(_problem_label)
	var fills := HBoxContainer.new()
	fills.add_theme_constant_override("separation", 6)
	_manual.add_child(fills)
	fills.add_child(_button("Usual order", "Flour, yeast, water, malt and hops: two batches of bread and two brews of beer", reset_to_standard))
	fills.add_child(_button("What the meals need", "Exactly what the Restock targets are short of", fill_for_meals))
	fills.add_child(_button("Empty", "Take everything off the cart", func() -> void:
		order.clear()
		refresh()
	))
	_confirm = _button("Buy cart", "", _buy)
	_confirm.custom_minimum_size.y = 40
	_confirm.add_theme_font_size_override("font_size", 15)
	var lit: StyleBoxFlat = _confirm.get_theme_stylebox("normal").duplicate()
	lit.border_color = TavernTheme.CANDLE
	lit.bg_color = TavernTheme.TIMBER_LIGHT
	_confirm.add_theme_stylebox_override("normal", lit)
	_confirm.add_theme_color_override("font_color", TavernTheme.CANDLE)
	_manual.add_child(_confirm)


## A ware on the merchant's shelf: its picture and price, how many the tavern
## has (top left) and how many are on the cart (top right, in gold).
func _ware(def: ItemDef) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(SLOT + 22, SLOT + 26)
	b.tooltip_text = "%s, %dg each" % [def.display_name, def.purchase_price]
	_compact_style(b)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(stack)
	var picture: TextureRect = IconStudio.rect(IconStudio.item(def.id), SLOT - 8.0)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(picture)
	var price := Label.new()
	price.text = "%dg" % def.purchase_price
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_size_override("font_size", 12)
	price.add_theme_color_override("font_color", TavernTheme.CANDLE)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(price)
	var have: Label = _badge(TavernTheme.PARCHMENT_DIM)
	have.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	have.position = Vector2(5, 2)
	b.add_child(have)
	var ordered: Label = _badge(TavernTheme.CANDLE)
	ordered.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ordered.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ordered.offset_left = -40
	ordered.offset_right = -5
	ordered.offset_top = 2
	ordered.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_child(ordered)
	var id: StringName = def.id
	b.pressed.connect(func() -> void: add_ware(id, 1))
	b.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			add_ware(id, -1)
			b.accept_event()
	)
	b.mouse_entered.connect(func() -> void: _ware_info.text = _describe_ware(def))
	_wares[id] = {"have": have, "ordered": ordered}
	return b


## Put a click's worth of a ware on the cart (or take it off, direction -1).
## The yard decides how much an order can be: past that, only what fits goes
## on, and the line under the shelf says so.
func add_ware(id: StringName, direction: int) -> void:
	var def: ItemDef = ItemCatalog.get_def(id)
	if def == null:
		return
	var step: int = def.stack_size if quantity == 0 else quantity
	var before: int = int(order.get(id, 0))
	if direction < 0:
		_set_line(id, before - step)
		AudioDirector.play("ui_back")
		_ware_info.text = _describe_ware(def)
		refresh()
		return
	var short_before: int = _short_total()
	var added: int = step
	while added > 0:
		_set_line(id, before + added)
		if _short_total() <= short_before:
			break
		added -= 1
	if added <= 0:
		_set_line(id, before)
		if world.delivery_tiles().is_empty():
			_ware_info.text = "Nowhere to unload: something blocks the yard. Clear the path to it."
		else:
			_ware_info.text = "No room in the yard for more %s: haul the waiting goods in, or take something off." % def.display_name.to_lower()
		AudioDirector.play("ui_back")
	elif added < step:
		_ware_info.text = "Only %d more %s fit in the yard." % [added, def.display_name.to_lower()]
		AudioDirector.play("ui_click")
	else:
		_ware_info.text = _describe_ware(def)
		AudioDirector.play("ui_click")
	refresh()


func _set_line(id: StringName, count: int) -> void:
	if count > 0:
		order[id] = count
	else:
		order.erase(id)


func _short_total() -> int:
	var total: int = 0
	var short: Dictionary = world.delivery_preview(order)["short"]
	for id in short:
		total += int(short[id])
	return total


func _describe_ware(def: ItemDef) -> String:
	var dishes: PackedStringArray = PackedStringArray()
	for recipe in MealSupplyPlan.meals():
		if MealSupplyPlan.ingredient_ids(recipe).has(def.id):
			dishes.append(ItemCatalog.get_def(recipe.outputs[0]["id"]).display_name.to_lower())
	return "%s · %dg each · comes in stacks of %d · you have %d%s" % [def.display_name, def.purchase_price,
		def.stack_size, world.stock_of(def.id), " · for " + ", ".join(dishes) if not dishes.is_empty() else ""]


## The cart filled with exactly what the meal targets are short of.
func fill_for_meals() -> void:
	var wanted: Dictionary = world.auto_supply.shortfall()
	order.clear()
	for id in wanted:
		_set_line(id, int(wanted[id]))
	# Trimmed to what the yard can take now, as the automatic cart is.
	var trimmed: bool = false
	for i in range(4):
		var short: Dictionary = world.delivery_preview(order)["short"]
		if short.is_empty():
			break
		trimmed = true
		for id in short:
			_set_line(id, int(order.get(id, 0)) - int(short[id]))
	if wanted.is_empty():
		_ware_info.text = "The meals have what they need right now."
	elif trimmed:
		_ware_info.text = "On the cart: as much of what the meals are short of as the yard can take."
	else:
		_ware_info.text = "On the cart: what the meals are short of."
	AudioDirector.play("ui_click")
	refresh()


func reset_to_standard() -> void:
	order.clear()
	for id in world.STANDARD_ORDER:
		_set_line(id, int(world.STANDARD_ORDER[id]))
	if _ware_info != null:
		# Twenty of each, not "a day": a busy first day sells more than that.
		_ware_info.text = "On the cart: the usual order, about twenty loaves and twenty beers."
	refresh()


## Paid for and unloaded: the cart empties, and Stores reopens on Restock,
## where the meals are, rather than on a cart already bought.
func _buy() -> void:
	if world.order_supplies(order):
		order.clear()
		show_meals()
		hide()
		closed.emit()
	refresh()


## The unloading yard's spaces with this cart in them: goods already waiting
## there (dimmed), what this cart puts down (gold count), free spaces, and in
## red whatever would be left on the cart. Clicking a space takes its share of
## the cart off.
func _draw_yard(preview: Dictionary) -> void:
	var tiles: Array[Vector2i] = world.delivery_tiles()
	var adding: Dictionary = {}
	for line in preview["plan"]:
		adding[line["tile"]] = line
	var key: String = str(order) + str(preview["short"])
	for tile in tiles:
		key += "|%s%d" % [world.items.def_at(tile).id if world.items.def_at(tile) != null else &"", world.items.count_at(tile)]
	if key == _yard_key:
		return
	_yard_key = key
	for child in _yard_row.get_children():
		_yard_row.remove_child(child)
		child.queue_free()
	var free: int = 0
	for tile in tiles:
		var held: ItemDef = world.items.def_at(tile)
		var there: int = world.items.count_at(tile) if held != null else 0
		var line: Dictionary = adding.get(tile, {})
		var def: ItemDef = held if held != null else line.get("def", null)
		var coming: int = int(line.get("count", 0))
		if def == null:
			free += 1
		_yard_row.add_child(_yard_space(def, there, coming))
	# What would be left on the cart: two spaces' worth at most, so the row
	# never runs past the panel; the caption counts the rest.
	var left_over: Array = preview["short"].keys()
	for i in range(mini(left_over.size(), 2)):
		var id: StringName = left_over[i]
		_yard_row.add_child(_yard_space(ItemCatalog.get_def(id), 0, int(preview["short"][id]), true))
	_yard_caption.text = "Unloading yard · %d of %d spaces free with this cart" % [free, tiles.size()]
	if not left_over.is_empty():
		_yard_caption.text = "Unloading yard · full: %d kind%s will not fit (red)" % [left_over.size(), "" if left_over.size() == 1 else "s"]
	if tiles.is_empty():
		_yard_caption.text = "Unloading yard · nowhere to unload: clear the path to it"


func _yard_space(def: ItemDef, there: int, coming: int, overflow: bool = false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(SLOT, SLOT)
	_compact_style(b, TavernTheme.DANGER if overflow else Color(0, 0, 0, 0))
	if def == null:
		b.tooltip_text = "A free space"
		b.disabled = true
		return b
	var side: float = SLOT - 14.0
	var picture: TextureRect = IconStudio.rect(IconStudio.item(def.id), side)
	picture.anchor_left = 0.5
	picture.anchor_right = 0.5
	picture.offset_left = -side * 0.5
	picture.offset_right = side * 0.5
	picture.offset_top = 3
	picture.offset_bottom = 3 + side
	b.add_child(picture)
	var count: Label = _badge(TavernTheme.PARCHMENT)
	count.anchor_left = 0.0
	count.anchor_right = 1.0
	count.anchor_top = 1.0
	count.anchor_bottom = 1.0
	count.offset_left = 2
	count.offset_right = -4
	count.offset_top = -19
	count.offset_bottom = -1
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_child(count)
	var name: String = def.display_name.to_lower()
	if overflow:
		count.text = "+%d" % coming
		count.add_theme_color_override("font_color", TavernTheme.DANGER)
		b.tooltip_text = "%d %s will not fit. Click to take it off the cart." % [coming, name]
	elif coming > 0:
		count.text = "+%d" % coming if there == 0 else "%d+%d" % [there, coming]
		count.add_theme_color_override("font_color", TavernTheme.CANDLE)
		b.tooltip_text = "%d %s from this cart%s. Click to take it off." % [coming, name,
			", on %d already waiting" % there if there > 0 else ""]
	else:
		count.text = str(there)
		picture.modulate = Color(1, 1, 1, 0.5)
		b.tooltip_text = "%d %s waiting to be carried in" % [there, name]
	if coming > 0:
		var id: StringName = def.id
		var amount: int = coming
		b.pressed.connect(func() -> void:
			_set_line(id, int(order.get(id, 0)) - amount)
			AudioDirector.play("ui_back")
			refresh()
		)
	else:
		b.mouse_filter = Control.MOUSE_FILTER_PASS
	return b


# --- shared ------------------------------------------------------------------

## Both tabs set by hand: a button set without its signal does not release
## the rest of its group, and both tabs stayed lit.
func show_manual() -> void:
	_merchant_tab.set_pressed_no_signal(true)
	_restock_tab.set_pressed_no_signal(false)
	_meals.hide()
	_manual.show()
	refresh()


func show_meals() -> void:
	_restock_tab.set_pressed_no_signal(true)
	_merchant_tab.set_pressed_no_signal(false)
	_manual.hide()
	_meals.show()
	refresh()


## Opens on the tab last used; the first time, on Restock.
func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func _fit_screen() -> void:
	var area: Vector2 = get_viewport().get_visible_rect().size
	var wanted_scale: float = TavernTheme.scale_for_control(self) * 0.8
	if not is_equal_approx(wanted_scale, _theme_scale):
		_theme_scale = wanted_scale
		theme = TavernTheme.build(wanted_scale)
	custom_minimum_size.x = minf(WIDTH, area.x - 24.0)
	var tallest: float = minf(600.0, maxf(120.0, area.y - position.y - 12.0))
	if _manual != null and _manual.visible:
		size = Vector2(custom_minimum_size.x, 0)
		size = Vector2(custom_minimum_size.x, minf(get_combined_minimum_size().y, tallest))
	else:
		size = Vector2(custom_minimum_size.x, tallest)


## Re-read the purse, the stock and the yard. Cheap, so it runs while open:
## the answer to "can I afford it" changes as the tavern trades.
func refresh() -> void:
	if world == null or world.build == null or _total_label == null:
		return
	_fit_screen()
	_refresh_restock()
	_refresh_merchant()


func _refresh_restock() -> void:
	_auto_toggle.set_pressed_no_signal(world.auto_supply.enabled)
	_clear_blocks.visible = not world.auto_supply.never.is_empty()
	for recipe in MealSupplyPlan.meals():
		var bill: Dictionary = world.bills.get_bill(recipe.id)
		var widgets: Dictionary = _meal_widgets[recipe.id]
		var on: bool = bool(bill["enabled"])
		var target: int = int(bill["target"])
		widgets["toggle"].set_pressed_no_signal(on)
		widgets["amount"].text = str(target)
		var stock: int = world.stock_of(recipe.outputs[0]["id"])
		var fraction: float = clampf(float(stock) / maxf(1.0, float(target)), 0.0, 1.0)
		widgets["fill"].anchor_right = fraction
		widgets["fill"].color = GOOD if fraction >= 1.0 else (TavernTheme.CANDLE if fraction >= 0.4 else WARN)
		widgets["stock"].text = "%d of %d" % [stock, target]
		widgets["stock"].add_theme_color_override("font_color", TavernTheme.PARCHMENT if on else TavernTheme.IRON.lightened(0.2))
		var status: String = ""
		var colour: Color = TavernTheme.DANGER
		if not on:
			status = "Off: not made, and nothing bought for it"
			colour = TavernTheme.IRON.lightened(0.3)
		elif world.build.grid.count_built([recipe.station_id]) == 0:
			status = "Build a %s to make it" % BuildingCatalog.get_def(recipe.station_id).display_name
		elif recipe.id == &"bake_bread" and world.build.grid.count_built([&"prep_table"]) == 0:
			status = "Build a Prep Table to make the dough"
		elif recipe.id == &"fish_soup" or recipe.id == &"grill_fish":
			if world.build.grid.count_built([&"fishing_spot"]) == 0:
				status = "Fish is caught, never bought: build a Fishing Spot"
			else:
				status = "Fish comes from your fishing spot"
				colour = TavernTheme.PARCHMENT_DIM
		widgets["status"].text = status
		widgets["status"].visible = not status.is_empty()
		widgets["status"].add_theme_color_override("font_color", colour)

	var auto: AutoSupply = world.auto_supply
	_auto_note.tooltip_text = ""
	var wanted: Dictionary = {}
	if not auto.enabled:
		_auto_note.text = "Auto restock is off. The targets still tell the kitchen what to make."
	elif not auto.started():
		_auto_note.text = "Turn a meal on or change its target to start restocking."
	elif not auto.note.is_empty():
		_auto_note.text = auto.note
	else:
		var plan: Dictionary = MealSupplyPlan.new().calculate(world, auto.never)
		wanted = plan["buy"]
		if wanted.is_empty():
			_auto_note.text = "The shelves hold what the meals need."
		else:
			_auto_note.text = "Next cart %s: %dg, keeping %dg for tonight's wages." % [
				_when(auto.wait_left()), world.order_cost(wanted), world.wage_bill()]
		_auto_note.tooltip_text = AutoSupply.describe(wanted)
		if not plan["blocked"].is_empty():
			var waiting: String = "Waiting on the kitchen or a local catch for: " + ", ".join(plan["blocked"])
			if wanted.is_empty():
				_auto_note.text = waiting
			_auto_note.tooltip_text += "\n" + waiting + ". Check the meals below and Kitchen details."
	_show_next_cart(wanted)


## What the next automatic cart brings, as pictures.
func _show_next_cart(wanted: Dictionary) -> void:
	var key: String = str(wanted)
	if key == _next_cart_key:
		return
	_next_cart_key = key
	for child in _next_cart.get_children():
		_next_cart.remove_child(child)
		child.queue_free()
	_next_cart.visible = not wanted.is_empty()
	if wanted.is_empty():
		return
	_next_cart.add_child(_inline("Brings"))
	_next_cart.add_child(GoodsStrip.of(GoodsStrip.entries_from(wanted), 24.0, 12, TavernTheme.PARCHMENT, 6))


## "in about 1h 10m", from game seconds.
func _when(seconds: float) -> String:
	if world.clock == null:
		return "soon"
	var minutes: int = int(round(seconds / maxf(world.clock.day_length, 1.0) * 1440.0))
	if minutes < 10:
		return "within a few minutes"
	if minutes < 60:
		return "in about %d min" % (int(round(minutes / 10.0)) * 10)
	var hours: int = minutes / 60
	var rest: int = int(round((minutes % 60) / 10.0)) * 10
	return "in about %dh" % hours if rest == 0 else "in about %dh %dm" % [hours, rest]


func _refresh_merchant() -> void:
	for id in _wares:
		var badges: Dictionary = _wares[id]
		badges["have"].text = str(world.stock_of(id))
		var n: int = int(order.get(id, 0))
		badges["ordered"].text = "+%d" % n if n > 0 else ""
	for b in _quantity_buttons:
		b.set_pressed_no_signal(b.text == ("Stack" if quantity == 0 else str(quantity)))
	if not _manual.visible:
		return
	var preview: Dictionary = world.delivery_preview(order)
	_draw_yard(preview)
	var cost: int = world.order_cost(order)
	var fee: int = world.DELIVERY_FEE if cost > 0 else 0
	if cost > 0:
		_total_label.text = "Goods %dg  +  cart %dg  =  %dg" % [cost - fee, fee, cost]
	else:
		_total_label.text = "The cart is empty"
	var left: int = GameState.gold - cost
	_purse_label.text = "Purse %dg  →  %dg after" % [GameState.gold, left]
	_purse_label.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	if cost > 0 and left >= 0 and left < world.spending_reserve():
		_purse_label.text += " · less than tonight's wages and a delivery (%dg)" % world.spending_reserve()
		_purse_label.add_theme_color_override("font_color", WARN)
	var problem: String = world.order_problem(order) if cost > 0 else ""
	_problem_label.text = problem
	_problem_label.visible = not problem.is_empty()
	_confirm.disabled = cost <= 0 or not problem.is_empty()
	_confirm.text = "Buy cart — %dg" % cost if cost > 0 else "Buy cart"
	_confirm.tooltip_text = problem if not problem.is_empty() else "Pay %dg and have it unloaded in the yard" % cost


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		refresh()


# --- pieces ------------------------------------------------------------------

func _caption(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH - 60.0, 18)
	label.add_theme_font_size_override("font_size", maxi(11, font_size))
	label.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	return label


## A short label for the middle of a row: never wraps.
func _inline(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TavernTheme.PARCHMENT_DIM)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _badge(colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", TavernTheme.INK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = TavernTheme.IRON
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


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


## A tab or a quantity: lit gold while chosen.
func _tab(text: String, hint: String, group: ButtonGroup, handler: Callable) -> Button:
	var b: Button = _button(text, hint, func() -> void:
		AudioDirector.play("ui_click")
		handler.call())
	b.toggle_mode = true
	b.button_group = group
	b.add_theme_font_size_override("font_size", 13)
	var chosen := StyleBoxFlat.new()
	chosen.bg_color = TavernTheme.TIMBER_LIGHT
	chosen.border_color = TavernTheme.CANDLE
	chosen.set_border_width_all(1)
	chosen.set_corner_radius_all(3)
	chosen.content_margin_left = 7
	chosen.content_margin_right = 7
	chosen.content_margin_top = 3
	chosen.content_margin_bottom = 3
	b.add_theme_stylebox_override("pressed", chosen)
	b.add_theme_stylebox_override("hover_pressed", chosen)
	b.add_theme_color_override("font_pressed_color", TavernTheme.CANDLE)
	b.add_theme_color_override("font_hover_pressed_color", TavernTheme.CANDLE)
	return b


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(TavernTheme.TIMBER_DARK, 0.55)
	style.border_color = Color(TavernTheme.IRON, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _compact_style(button: Button, edge: Color = Color(0, 0, 0, 0)) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = TavernTheme.TIMBER_DARK.lightened(0.08 if state == "hover" else 0.0)
		style.border_color = edge if edge.a > 0.0 else (TavernTheme.CANDLE_DIM if state == "hover" else TavernTheme.IRON)
		if state == "disabled":
			style.bg_color = Color(TavernTheme.TIMBER_DARK, 0.6)
			style.border_color = Color(style.border_color, 0.5)
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		style.content_margin_left = 7
		style.content_margin_right = 7
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		button.add_theme_stylebox_override(state, style)
