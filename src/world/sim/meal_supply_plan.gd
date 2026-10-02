class_name MealSupplyPlan
extends RefCounted

## A dry run of the recipe graph. All dishes share one virtual pantry, including
## intermediate stock and co-products. Nothing here mutates physical inventory.
var world
var never: Dictionary

static func meals() -> Array[Recipe]:
	var out: Array[Recipe] = []
	for recipe in RecipeCatalog.all():
		if not recipe.outputs.is_empty() and ItemCatalog.get_def(recipe.outputs[0]["id"]).category == ItemDef.Category.PRODUCT:
			out.append(recipe)
	return out

func calculate(p_world, excluded: Dictionary) -> Dictionary:
	world = p_world
	never = excluded
	var state: Dictionary = {"stock": {}, "buy": {}}
	for item in ItemCatalog.all():
		state["stock"][item.id] = world.stock_of(item.id)
	var blocked: Array[String] = []
	for recipe in meals():
		var bill: Dictionary = world.bills.get_bill(recipe.id)
		if not bill.get("enabled", true) or int(bill.get("target", 0)) <= 0:
			continue
		var output: StringName = recipe.outputs[0]["id"]
		var missing: int = maxi(0, int(bill["target"]) - int(state["stock"][output]))
		if missing == 0:
			continue
		# Reserve ready meals once; they are not raw inputs to another menu row.
		var batches: int = ceili(float(missing) / int(recipe.outputs[0]["count"]))
		for batch in range(batches):
			var trial: Dictionary = state.duplicate(true)
			if not _produce(recipe, trial, []):
				blocked.append(ItemCatalog.get_def(output).display_name)
				break
			state = trial
	return {"buy": state["buy"], "blocked": blocked}

func _produce(recipe: Recipe, state: Dictionary, path: Array) -> bool:
	var bill: Dictionary = world.bills.get_bill(recipe.id)
	if path.has(recipe.id) or path.size() >= 8 or recipe.inputs.is_empty() \
			or world.build.grid.count_built([recipe.station_id]) <= 0 \
			or not bill.get("enabled", true) or int(bill.get("target", 1)) <= 0:
		return false
	var next: Array = path.duplicate()
	next.append(recipe.id)
	for input in recipe.inputs:
		if not _take(input["id"], int(input["count"]), state, next):
			return false
	for output in recipe.outputs:
		state["stock"][output["id"]] = int(state["stock"].get(output["id"], 0)) + int(output["count"])
	return true

func _take(id: StringName, count: int, state: Dictionary, path: Array) -> bool:
	var have: int = int(state["stock"].get(id, 0))
	var taken: int = mini(have, count)
	state["stock"][id] = have - taken
	count -= taken
	while count > 0:
		var made: bool = false
		for recipe in RecipeCatalog.all():
			var produces: bool = false
			for output in recipe.outputs:
				produces = produces or output["id"] == id
			if not produces:
				continue
			var trial: Dictionary = state.duplicate(true)
			if _produce(recipe, trial, path):
				state["stock"] = trial["stock"]
				state["buy"] = trial["buy"]
				made = true
				break
		if not made:
			var def: ItemDef = ItemCatalog.get_def(id)
			if def == null or def.purchase_price <= 0 or never.has(id):
				return false
			state["buy"][id] = int(state["buy"].get(id, 0)) + count
			return true
		taken = mini(int(state["stock"][id]), count)
		state["stock"][id] -= taken
		count -= taken
	return true

static func ingredients(recipe: Recipe) -> String:
	var names: PackedStringArray = PackedStringArray()
	for input in recipe.inputs:
		var def: ItemDef = ItemCatalog.get_def(input["id"])
		if def.id == &"dough":
			names.append(ingredients(RecipeCatalog.get_recipe(&"make_dough")))
		else:
			names.append(def.display_name)
	return " · ".join(names)
