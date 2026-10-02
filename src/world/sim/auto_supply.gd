class_name AutoSupply
extends RefCounted

## Orders ingredients by itself, so a player who forgets does not stall.
##
## Finished meal targets share a virtual pantry through MealSupplyPlan. Existing
## dough, harvested wheat, and the heads/fillets from each fish count once.
## Only missing merchant ingredients are bought; no speculative local catches.
##
## It keeps tonight's wages in the purse, waits a while between deliveries so
## a slow afternoon is not ten delivery fees, and says why when it holds back.

## Game seconds between looks at the larder: about half an hour of clock.
const CHECK_EVERY: float = 20.0
## Game seconds a delivery must be apart: about two hours of clock.
const COOLDOWN: float = 70.0

var enabled: bool = true
## Explicit meal controls can start ordering without a manual first cart.
var configured: bool = false
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
	return world != null and (configured or not world.delivered.is_empty())


## What the targets still want, as merchant goods not already in the tavern.
func shortfall() -> Dictionary:
	return MealSupplyPlan.new().calculate(world, never)["buy"]


## One control per finished meal. Intermediate production stays available,
## while only menu targets buy ingredients (no separate dough shopping list).
func set_meal(recipe_id: StringName, on: bool, amount: int) -> void:
	var recipe: Recipe = RecipeCatalog.get_recipe(recipe_id)
	if recipe == null or not MealSupplyPlan.meals().has(recipe):
		return
	world.bills.set_target(recipe_id, clampi(amount, 1, 200))
	world.bills.set_resume_below(recipe_id, clampi(amount, 1, 200) - 1)
	world.bills.set_enabled(recipe_id, on)
	if on:
		enabled = true
		configured = true
		# A deliberately disabled prep recipe must not silently defeat the
		# simple meal control. Restore the necessary kitchen chain.
		if recipe_id == &"bake_bread":
			world.bills.set_enabled(&"make_dough", true)
			if int(world.bills.get_bill(&"make_dough").get("target", 0)) == 0:
				world.bills.set_target(&"make_dough", 3)
		elif recipe_id == &"fish_soup" or recipe_id == &"grill_fish":
			for prep in [&"clean_trout", &"clean_perch"]:
				world.bills.set_enabled(prep, true)
				if int(world.bills.get_bill(prep).get("target", 0)) == 0:
					world.bills.set_target(prep, 4)
	note = ""

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
	return {"enabled": enabled, "never": never_ids, "configured": configured, "since_order": _since_order, "menu_version": 1}


func restore(data: Dictionary) -> void:
	enabled = bool(data.get("enabled", true))
	configured = bool(data.get("configured", false))
	_since_order = clampf(float(data.get("since_order", COOLDOWN)), 0.0, COOLDOWN)
	# Preserve old targets and on/off choices, upgrade only the hidden restart
	# line to the single number now shown by Stores.
	if world != null and int(data.get("menu_version", 0)) < 1:
		for recipe in MealSupplyPlan.meals():
			world.bills.set_resume_below(recipe.id, int(world.bills.get_bill(recipe.id)["target"]) - 1)
	never.clear()
	for id in data.get("never", []):
		if ItemCatalog.get_def(StringName(id)) != null:
			never[StringName(id)] = true


