class_name ItemCatalog
extends RefCounted

## The Demo 1 resource list from the design notes: the five bought ingredients,
## the two intermediates, the two sellable products, and dirty dishes.
##
## Prices are the notes' placeholder economy. Bought goods come in bulk: a
## flour sack, a water barrel and a jar of yeast make a batch of dough that
## bakes ten loaves, so the merchant charges for ten loaves' worth (30g of
## inputs, 3g a loaf, about what two-loaf batches cost). Fewer, bigger units
## are fewer trips for the kitchen; a loaf costs the same to make.

const GRAIN := Color("c9b072")
const FLOUR_WHITE := Color("e8dfc4")
const MALT_BROWN := Color("9c7440")
const HOPS_GREEN := Color("6e8f42")
const WATER_BLUE := Color("4a8fc4")
const DOUGH_PALE := Color("e3d2ad")
const CRUST := Color("b07838")
const ALE := Color("c08a2e")
const CLAY := Color("8a6a52")
const STEEL := Color("7f8288")

static var _catalog: Array[ItemDef] = []
static var _by_id: Dictionary = {}


static func all() -> Array[ItemDef]:
	if _catalog.is_empty():
		_build()
	return _catalog


static func get_def(id: StringName) -> ItemDef:
	if _catalog.is_empty():
		_build()
	return _by_id.get(id, null)


## Everything a supplier will sell, for the ordering screen.
static func purchasable() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for d in all():
		if d.purchase_price > 0:
			out.append(d)
	return out


static func _build() -> void:
	var C := ItemDef.Category
	var S := ItemDef.Shape
	_catalog = [
		# --- bought ingredients ---
		ItemDef.make("flour", "Flour Sack", C.INGREDIENT, S.SACK, 10, 20, 0,
			["grain", "baking"] as Array[String], [FLOUR_WHITE, GRAIN] as Array[Color]),
		ItemDef.make("yeast", "Yeast", C.INGREDIENT, S.JAR, 10, 5, 0,
			["baking", "brewing"] as Array[String], [CLAY, DOUGH_PALE] as Array[Color]),
		# A coin a barrel: water is common, and dear water made fish soup the
		# dearest dish to make.
		ItemDef.make("water", "Water Barrel", C.INGREDIENT, S.CASK, 20, 1, 0,
			["liquid"] as Array[String], [WATER_BLUE, CLAY] as Array[Color]),
		ItemDef.make("malt", "Malt Sack", C.INGREDIENT, S.SACK, 8, 12, 0,
			["grain", "brewing"] as Array[String], [MALT_BROWN, GRAIN] as Array[Color]),
		ItemDef.make("hops", "Hops", C.INGREDIENT, S.BUNDLE, 8, 5, 0,
			["brewing"] as Array[String], [HOPS_GREEN, GRAIN] as Array[Color]),
		# Bought by the crate; a crate and a barrel press ten lemonades at the bar.
		ItemDef.make("lemons", "Lemons", C.INGREDIENT, S.FRUIT, 12, 10, 0,
			["fruit"] as Array[String], [Color("f2cf3b"), Color("8a6239")] as Array[Color]),
		ItemDef.make("lemonade", "Lemonade", C.PRODUCT, S.JUG, 20, 0, 7,
			["drink"] as Array[String], [Color("f6dc63"), Color("e9e4d6")] as Array[Color]),
		# Grown on a farm plot; ground to flour at the prep table.
		ItemDef.make("wheat", "Wheat Sheaf", C.INGREDIENT, S.BUNDLE, 12, 0, 0,
			["grain", "crop"] as Array[String], [Color("d9b45a"), Color("a8802e")] as Array[Color]),

		# --- made on the premises ---
		ItemDef.make("dough", "Dough", C.INTERMEDIATE, S.DOUGH, 6, 0, 0,
			["baking"] as Array[String], [DOUGH_PALE, FLOUR_WHITE] as Array[Color]),
		ItemDef.make("bread", "Bread", C.PRODUCT, S.LOAF, 20, 0, 10,
			["food"] as Array[String], [CRUST, DOUGH_PALE] as Array[Color]),
		ItemDef.make("beer", "Beer", C.PRODUCT, S.MUG, 20, 0, 8,
			["drink"] as Array[String], [ALE, CLAY] as Array[Color]),

		# --- caught on the river: free, and the first food the tavern does not buy ---
		ItemDef.make("trout", "Trout", C.INGREDIENT, S.FISH, 6, 0, 0,
			["fish", "catch"] as Array[String], [Color("8a9a86"), Color("c7b98f")] as Array[Color]),
		ItemDef.make("perch", "Perch", C.INGREDIENT, S.FISH, 6, 0, 0,
			["fish", "catch"] as Array[String], [Color("7f8a4c"), Color("c9713c")] as Array[Color]),
		ItemDef.make("fish_head", "Fish Head", C.INTERMEDIATE, S.FISH_HEAD, 8, 0, 0,
			["fish"] as Array[String], [Color("8f9486"), Color("d8d0b8")] as Array[Color]),
		ItemDef.make("fillet", "Fish Fillet", C.INTERMEDIATE, S.FILLET, 8, 0, 0,
			["fish"] as Array[String], [Color("e6b9a0"), Color("f1dccb")] as Array[Color]),
		ItemDef.make("fish_soup", "Fish Soup", C.PRODUCT, S.BOWL, 8, 0, 9,
			["food"] as Array[String], [Color("c9a86a"), Color("8a6a4a")] as Array[Color]),
		ItemDef.make("grilled_fish", "Grilled Fish", C.PRODUCT, S.FISH_PLATE, 8, 0, 14,
			["food"] as Array[String], [Color("b9804a"), Color("e8e0cc")] as Array[Color]),

		# --- cleared away ---
		ItemDef.make("dirty_dishes", "Dirty Dishes", C.REFUSE, S.DISHES, 6, 0, 0,
			["refuse"] as Array[String], [STEEL, CLAY] as Array[Color]),
	] as Array[ItemDef]

	_by_id.clear()
	for d in _catalog:
		_by_id[d.id] = d
