class_name AutoSupply
extends RefCounted

## Orders ingredients by itself, so a player who forgets does not stall.
##
## Driven by the stock targets in Production ("keep 10 bread"): whatever a
## target still wants made, worked back through its recipes to what the
## merchant sells, less what is already in the tavern, is bought. Dough is
## made from flour, yeast and water, so a bread target buys those; a fish
## target buys nothing, because nobody sells fish. The player can mark any
## ingredient "never order" -- the well draws the water, say -- and switch the
## whole thing off.
##
## It keeps tonight's wages in the purse, waits a while between deliveries so
## a slow afternoon is not ten delivery fees, and says why when it holds back.

## Game seconds between looks at the larder: about half an hour of clock.
const CHECK_EVERY: float = 20.0
## Game seconds a delivery must be apart: about two hours of clock.
const COOLDOWN: float = 70.0
## How far an intermediate (dough) is traced back to what it is made of.
const DEPTH: int = 3

var enabled: bool = true
## item id -> true: never bought automatically.
var never: Dictionary = {}
## The last automatic order: id -> count, and when and what it cost.
var last_order: Dictionary = {}
var last_cost: int = 0
var last_time_text: String = ""
## Why the last look did not order, or "" if it did or had no need to.
var note: String = ""

var world  ## TavernWorld
var _timer: float = 0.0
var _since_order: float = COOLDOWN


func setup(p_world) -> void:
	world = p_world


func step(delta: float) -> void:
	_since_order += delta
	if not enabled or world == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_EVERY
	check()


## Look at the larder now, and order if the targets want it. Returns the order
## placed ({} if none).
func check() -> Dictionary:
	if not enabled or world == null:
		return {}
	# Not before the first delivery: the opening checklist teaches ordering,
	# and a delivery arriving while the first room is still blueprints has the
	# porter hauling instead of building it.
	if not started():
		return {}
	var order: Dictionary = shortfall()
	if order.is_empty():
		note = ""
		return {}
	if _since_order < COOLDOWN:
		return {}
	var wanted_cost: int = world.order_cost(order)
	order = _fit(order)
	if order.is_empty():
		# Tonight's wages stay in the purse: an order that eats them trades a
		# stall for a debt. A yard too full for even a little is the other cause.
		if GameState.gold - world.order_cost({_first(shortfall()): 1}) < world.wage_bill():
			_say("Auto-order is waiting: %dg of supplies would leave less than tonight's %dg of wages." % [
				wanted_cost, world.wage_bill()])
		else:
			_say("Auto-order could not deliver: %s." % world.order_problem(shortfall()).trim_suffix("."))
		return {}
	var cost: int = world.order_cost(order)
	if not world.order_supplies(order, true):
		return {}
	_since_order = 0.0
	last_order = order
	last_cost = cost
	last_time_text = world.clock.clock_text() if world.clock != null else ""
	note = ""
	if world.hud != null:
		world.hud.flash("Auto-ordered %s (%dg)" % [describe(order), cost], 3.0)
	return order


## As much of the order as the yard can take and the purse can pay for while
## keeping tonight's wages: halved until it fits. A big target used to ask for
## more than the yard holds, and got nothing at all.
func _fit(order: Dictionary) -> Dictionary:
	var trial: Dictionary = order.duplicate()
	for i in range(10):
		if world.order_problem(trial).is_empty() and GameState.gold - world.order_cost(trial) >= world.wage_bill():
			return trial
		var smaller: bool = false
		for id in trial:
			if int(trial[id]) > 1:
				trial[id] = int(trial[id]) / 2
				smaller = true
		if not smaller:
			break
	return {}


static func _first(order: Dictionary) -> StringName:
	for id in order:
		return id
	return &""


func started() -> bool:
	return world != null and not world.delivered.is_empty()


## What the targets still want, as merchant goods not already in the tavern.
func shortfall() -> Dictionary:
	var need: Dictionary = {}
	var drawn: Dictionary = {}  # intermediate id -> stock already counted towards a target
	for recipe in RecipeCatalog.all():
		if recipe.outputs.is_empty() or recipe.inputs.is_empty() or not world.bills.has_bill(recipe.id):
			continue
		var bill: Dictionary = world.bills.get_bill(recipe.id)
		if not bill.get("enabled", true) or int(bill.get("target", 0)) <= 0 or not _can_make(recipe):
			continue
		var missing: int = int(bill["target"]) - world.stock_of(recipe.outputs[0]["id"])
		if missing <= 0:
			continue
		var per_batch: int = maxi(1, int(recipe.outputs[0]["count"]))
		_add_inputs(recipe, ceili(float(missing) / float(per_batch)), need, drawn, 0)
	var buy: Dictionary = {}
	for id in need:
		if never.has(id):
			continue
		var short: int = int(need[id]) - world.stock_of(id)
		if short > 0:
			buy[id] = short
	return buy


func _add_inputs(recipe: Recipe, batches: int, need: Dictionary, drawn: Dictionary, depth: int) -> void:
	for input in recipe.inputs:
		var id: StringName = input["id"]
		var count: int = int(input["count"]) * batches
		var def: ItemDef = ItemCatalog.get_def(id)
		if def == null:
			continue
		if def.purchase_price > 0:
			need[id] = int(need.get(id, 0)) + count
			continue
		if depth >= DEPTH:
			continue
		# Made here (dough): what is on hand counts first, the rest is traced
		# back to its own ingredients.
		var maker: Recipe = _maker_of(id)
		if maker == null:
			continue
		var spare: int = maxi(0, world.stock_of(id) - int(drawn.get(id, 0)))
		var used: int = mini(spare, count)
		drawn[id] = int(drawn.get(id, 0)) + used
		var still: int = count - used
		if still > 0:
			var per_batch: int = maxi(1, int(maker.outputs[0]["count"]))
			_add_inputs(maker, ceili(float(still) / float(per_batch)), need, drawn, depth + 1)


func _maker_of(id: StringName) -> Recipe:
	for recipe in RecipeCatalog.all():
		if not recipe.outputs.is_empty() and recipe.outputs[0]["id"] == id and _can_make(recipe):
			return recipe
	return null


func _can_make(recipe: Recipe) -> bool:
	return world.build.grid.count_built([StringName(recipe.station_id)]) > 0


## Every ingredient a recipe in the game buys, for the "never order" boxes.
static func buyable_ingredients() -> Array[StringName]:
	var out: Array[StringName] = []
	for recipe in RecipeCatalog.all():
		for input in recipe.inputs:
			var def: ItemDef = ItemCatalog.get_def(input["id"])
			if def != null and def.purchase_price > 0 and not out.has(def.id):
				out.append(def.id)
	return out


static func describe(order: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for id in order:
		var def: ItemDef = ItemCatalog.get_def(id)
		parts.append("%d %s" % [int(order[id]), def.display_name.to_lower() if def != null else String(id)])
	return ", ".join(parts)


func set_never(id: StringName, on: bool) -> void:
	if on:
		never[id] = true
	else:
		never.erase(id)


func _say(text: String) -> void:
	if text != note and world != null and world.hud != null:
		world.hud.flash(text, 4.0)
	note = text


func capture() -> Dictionary:
	var never_ids: Array = []
	for id in never:
		never_ids.append(String(id))
	return {"enabled": enabled, "never": never_ids}


func restore(data: Dictionary) -> void:
	enabled = bool(data.get("enabled", true))
	never.clear()
	for id in data.get("never", []):
		if ItemCatalog.get_def(StringName(id)) != null:
			never[StringName(id)] = true
