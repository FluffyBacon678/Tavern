class_name RecipeCatalog
extends RefCounted

## The Demo 1 recipes: bread in two stages, beer in one.
##
## Bread is deliberately split across two stations rather than collapsed into a
## single "flour goes in, bread comes out" step, because the design notes call
## for the *physical* flow: ingredients are fetched, dough is made at the prep
## table, the dough is carried to the oven, and bread comes out. That carrying
## step between stations is the gameplay -- it is what makes kitchen layout and
## walking distance matter at all.

static var _catalog: Array[Recipe] = []
static var _by_station: Dictionary = {}


static func all() -> Array[Recipe]:
	if _catalog.is_empty():
		_build()
	return _catalog


## Recipes that can be performed at a given building definition.
static func for_station(station_id: StringName) -> Array:
	if _catalog.is_empty():
		_build()
	return _by_station.get(station_id, [])


static func get_recipe(id: StringName) -> Recipe:
	for r in all():
		if r.id == id:
			return r
	return null


static func _build() -> void:
	_catalog = [
		Recipe.make("make_dough", "Make Dough", "prep_table", 3.5, WorkType.Kind.COOK,
			[
				Recipe.ingredient("flour", 1),
				Recipe.ingredient("water", 1),
				Recipe.ingredient("yeast", 1),
			],
			[Recipe.ingredient("dough", 1)]),

		Recipe.make("bake_bread", "Bake Bread", "oven", 5.0, WorkType.Kind.COOK,
			[Recipe.ingredient("dough", 1)],
			[Recipe.ingredient("bread", 2)]),

		# No inputs at all: the point of the well is that water stops costing
		# money and starts costing time. Everything else in the catalog turns
		# goods into other goods; this one turns labour into goods.
		Recipe.make("draw_water", "Draw Water", "well", 9.0, WorkType.Kind.GATHER,
			[],
			[Recipe.ingredient("water", 3)]),

		Recipe.make("brew_beer", "Brew Beer", "brewing_vat", 7.0, WorkType.Kind.COOK,
			[
				Recipe.ingredient("malt", 1),
				Recipe.ingredient("hops", 1),
				Recipe.ingredient("water", 1),
			],
			[Recipe.ingredient("beer", 4)]),

		# Fishing: labour into food, like the well is labour into water. Each
		# catch is a trout or a perch, one or two of them, on the day's luck.
		Recipe.make("catch_fish", "Catch Fish", "fishing_spot", 12.0, WorkType.Kind.FISH,
			[],
			[Recipe.ingredient("trout", 1)]),

		# Scaled and cut at the prep table: the head for the pot, the fillet
		# for the grill. Fillet first, so the order counts fillets.
		Recipe.make("clean_trout", "Clean Trout", "prep_table", 2.5, WorkType.Kind.COOK,
			[Recipe.ingredient("trout", 1)],
			[Recipe.ingredient("fillet", 1), Recipe.ingredient("fish_head", 1)]),
		Recipe.make("clean_perch", "Clean Perch", "prep_table", 2.5, WorkType.Kind.COOK,
			[Recipe.ingredient("perch", 1)],
			[Recipe.ingredient("fillet", 1), Recipe.ingredient("fish_head", 1)]),

		Recipe.make("fish_soup", "Boil Fish Soup", "oven", 4.0, WorkType.Kind.COOK,
			[Recipe.ingredient("fish_head", 1), Recipe.ingredient("water", 1)],
			[Recipe.ingredient("fish_soup", 2)]),
		Recipe.make("grill_fish", "Grill Fish", "oven", 3.5, WorkType.Kind.COOK,
			[Recipe.ingredient("fillet", 1)],
			[Recipe.ingredient("grilled_fish", 1)]),
	] as Array[Recipe]
	var catch: Recipe = null
	for r in _catalog:
		if r.id == &"catch_fish":
			catch = r
	if catch != null:
		catch.pick_from = [&"trout", &"perch"]
		catch.pick_most = 2

	_by_station.clear()
	for r in _catalog:
		if not _by_station.has(r.station_id):
			_by_station[r.station_id] = []
		_by_station[r.station_id].append(r)
