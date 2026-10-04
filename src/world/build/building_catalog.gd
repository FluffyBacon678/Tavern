class_name BuildingCatalog
extends RefCounted

## Everything the player can build, as data.
##
## This is the Demo 1 content lock from the design notes: floors, walls, a door,
## seating, and the four workstations the bread-and-beer economy needs. Prices
## are placeholders and meant to be argued with.
##
## Defined in code today, but as BuildingDef resources rather than hardcoded
## branches, so moving the catalog to .tres files (or to a spreadsheet export)
## later touches this one function and nothing else.

const TIMBER := Color("936c3d")
const TIMBER_DARK := Color("503b27")
const TIMBER_LIGHT := Color("b18b50")
const STONE := Color("918d7b")
const STONE_DARK := Color("626353")
const IRON := Color("4b504b")
const PLASTER := Color("c8bf9a")
const WORKTOP := Color("c3b9a1")
const THATCH := Color("b09040")
const COPPER := Color("a17a43")

static var _catalog: Array[BuildingDef] = []
static var _by_id: Dictionary = {}


static func all() -> Array[BuildingDef]:
	if _catalog.is_empty():
		_build()
	return _catalog


## Pieces renamed since a save could have been made: the old name still loads.
const RENAMED: Dictionary = {&"market_stall": &"bar_table"}


static func get_def(id: StringName) -> BuildingDef:
	if _catalog.is_empty():
		_build()
	return _by_id.get(RENAMED.get(id, id), null)


## Distinct categories, in catalog order, for grouping the build bar.
static func categories() -> Array[String]:
	var out: Array[String] = []
	for d in all():
		if not out.has(d.category):
			out.append(d.category)
	return out


static func in_category(category: String) -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []
	for d in all():
		if d.category == category:
			out.append(d)
	return out


static func _build() -> void:
	var L := BuildingDef.Layer
	var S := BuildingDef.Shape
	_catalog = [
		# --- Structure ---
		BuildingDef.make("wood_floor", "Wood Floor", "Structure", L.FLOOR, S.FLOOR_SLAB,
			Vector2i.ONE, 2, false, 0.06, [TIMBER, TIMBER_DARK] as Array[Color]),
		BuildingDef.make("stone_floor", "Stone Floor", "Structure", L.FLOOR, S.FLOOR_SLAB,
			Vector2i.ONE, 4, false, 0.06, [STONE, STONE_DARK] as Array[Color]),
		BuildingDef.make("farm_plot", "Farm Plot", "Kitchen", L.FLOOR, S.FARM,
			Vector2i.ONE, 3, false, 0.08, [Color("5a3d24"), Color("3f2a18")] as Array[Color]),
		# Walls priced for a whole room, not a tile: a 10 x 8 room is 32 of them.
		# At 8g each the walls alone were 43% of the opening purse, and the first
		# scripted player to build a room could not then afford a kitchen.
		BuildingDef.make("timber_wall", "Timber Wall", "Structure", L.OBJECT, S.WALL,
			Vector2i.ONE, 4, true, 1.5, [TIMBER, TIMBER_DARK, PLASTER] as Array[Color]),
		BuildingDef.make("stone_wall", "Stone Wall", "Structure", L.OBJECT, S.WALL,
			Vector2i.ONE, 8, true, 1.5, [STONE, STONE_DARK] as Array[Color]),
		# Passable on purpose: a door is an opening a pawn walks through, and the
		# job system will care about that distinction long before it looks right.
		BuildingDef.make("door", "Door", "Structure", L.OBJECT, S.DOOR,
			Vector2i.ONE, 10, false, 1.5, [TIMBER_LIGHT, IRON] as Array[Color]),

		# --- Dining ---
		BuildingDef.make("table", "Table", "Dining", L.OBJECT, S.TABLE,
			Vector2i(2, 1), 15, true, 0.78, [TIMBER_LIGHT, TIMBER_DARK] as Array[Color]),
		BuildingDef.make("chair", "Chair", "Dining", L.OBJECT, S.CHAIR,
			Vector2i.ONE, 6, false, 0.9, [TIMBER, TIMBER_DARK] as Array[Color]),
		BuildingDef.make("serving_counter", "Serving Counter", "Dining", L.OBJECT, S.COUNTER,
			Vector2i(2, 1), 20, true, 1.0, [TIMBER, TIMBER_LIGHT] as Array[Color]),
		BuildingDef.make("host_stand", "Host's Stand", "Dining", L.OBJECT, S.LECTERN,
			Vector2i.ONE, 16, true, 1.15, [TIMBER_LIGHT, IRON] as Array[Color]),

		# --- Kitchen ---
		BuildingDef.make("prep_table", "Prep Table", "Kitchen", L.OBJECT, S.COUNTER,
			Vector2i(2, 1), 25, true, 0.95, [TIMBER, WORKTOP] as Array[Color]),
		BuildingDef.make("oven", "Oven", "Kitchen", L.OBJECT, S.OVEN,
			Vector2i(2, 1), 40, true, 1.5, [STONE, IRON] as Array[Color]),
		BuildingDef.make("sink", "Wash Basin", "Kitchen", L.OBJECT, S.SINK,
			Vector2i(2, 1), 22, true, 1.0, [STONE, IRON] as Array[Color]),
		BuildingDef.make("river_pump", "River Pump", "Kitchen", L.OBJECT, S.PUMP,
			Vector2i.ONE, 45, true, 1.3, [IRON, TIMBER_DARK] as Array[Color]),
		BuildingDef.make("well", "Well", "Kitchen", L.OBJECT, S.WELL,
			Vector2i(2, 2), 60, true, 1.4, [STONE, TIMBER_DARK] as Array[Color]),
		BuildingDef.make("fishing_spot", "Fishing Spot", "Kitchen", L.OBJECT, S.JETTY,
			Vector2i(2, 1), 30, true, 0.9, [TIMBER_LIGHT, TIMBER_DARK] as Array[Color]),
		BuildingDef.make("brewing_vat", "Brewing Vat", "Kitchen", L.OBJECT, S.VAT,
			Vector2i(2, 2), 55, true, 1.5, [COPPER, IRON] as Array[Color]),

		# --- Storage ---
		BuildingDef.make("storage_shelf", "Storage Shelf", "Storage", L.OBJECT, S.SHELF,
			Vector2i(2, 1), 18, true, 1.2, [TIMBER, TIMBER_DARK] as Array[Color]),
		BuildingDef.make("barrel", "Barrel", "Storage", L.OBJECT, S.BARREL,
			Vector2i.ONE, 10, true, 0.95, [TIMBER_LIGHT, IRON] as Array[Color]),

		# --- Garden: tiles and props for parks and paths by the tavern ---
		BuildingDef.make("lawn_trimmed", "Trimmed Lawn", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 1, false, 0.05, [Color("6c9b3f"), Color("6b4a2e")] as Array[Color]),
		BuildingDef.make("lawn_meadow", "Meadow Grass", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 1, false, 0.05, [Color("5f9139"), Color("6b4a2e")] as Array[Color]),
		BuildingDef.make("lawn_worn", "Worn Grass", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 1, false, 0.05, [Color("a27b4b"), Color("5f9139")] as Array[Color]),
		BuildingDef.make("garden_path", "Dirt Path", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 1, false, 0.05, [Color("a27b4b"), Color("54391f")] as Array[Color]),
		BuildingDef.make("stone_path", "Stone Path", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 3, false, 0.05, [Color("b3ada1"), Color("8a8478")] as Array[Color]),
		BuildingDef.make("bed_daisy", "Daisy Bed", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 4, false, 0.05, [Color("f2efe6"), Color("547f33")] as Array[Color]),
		BuildingDef.make("bed_mixed", "Mixed Flower Bed", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 5, false, 0.05, [Color("c8413a"), Color("547f33")] as Array[Color]),
		BuildingDef.make("bed_border", "Border Flower Bed", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 5, false, 0.05, [Color("7a5cc0"), Color("547f33")] as Array[Color]),
		BuildingDef.make("bed_tulips", "Tulip Bed", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 5, false, 0.05, [Color("c8413a"), Color("547f33")] as Array[Color]),
		BuildingDef.make("bed_lavender", "Lavender Bed", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 5, false, 0.05, [Color("8e78c8"), Color("547f33")] as Array[Color]),
		BuildingDef.make("bed_roses", "Rose Bed", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 6, false, 0.05, [Color("b8323d"), Color("3f6f2a")] as Array[Color]),
		BuildingDef.make("bed_sunflowers", "Sunflower Bed", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 5, false, 0.05, [Color("f2b72e"), Color("547f33")] as Array[Color]),
		BuildingDef.make("grass_tall", "Tall Grass", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 2, false, 0.05, [Color("5d9637"), Color("5f9139")] as Array[Color]),
		BuildingDef.make("grass_tall_flowers", "Tall Grass with Flowers", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 2, false, 0.05, [Color("f2efe6"), Color("5d9637")] as Array[Color]),
		BuildingDef.make("grass_overgrown", "Overgrown Plot", "Garden", L.FLOOR, S.GARDEN_TILE,
			Vector2i.ONE, 2, false, 0.05, [Color("8e8c86"), Color("3f6f2a")] as Array[Color]),
		BuildingDef.make("garden_bench", "Park Bench", "Garden", L.OBJECT, S.GARDEN_PROP,
			Vector2i(2, 1), 12, true, 0.72, [Color("8a6239"), Color("5a3d24")] as Array[Color]),
		BuildingDef.make("garden_rocks", "Rocks", "Garden", L.OBJECT, S.GARDEN_PROP,
			Vector2i.ONE, 6, true, 0.5, [Color("8e8c86"), Color("6f6d68")] as Array[Color]),
		BuildingDef.make("garden_tree", "Leafy Tree", "Garden", L.OBJECT, S.GARDEN_PROP,
			Vector2i.ONE, 15, true, 1.9, [Color("4f8a30"), Color("5e3f25")] as Array[Color]),
		BuildingDef.make("garden_pine", "Pine", "Garden", L.OBJECT, S.GARDEN_PROP,
			Vector2i.ONE, 15, true, 1.8, [Color("468636"), Color("5e3f25")] as Array[Color]),
		BuildingDef.make("lantern_post", "Lantern Post", "Garden", L.OBJECT, S.GARDEN_PROP,
			Vector2i.ONE, 10, true, 1.7, [Color("ffd27a"), Color("5a3d24")] as Array[Color]),
		# --- the bar: drinks on its counter, inside or out, its own lemonade
		# pressed behind it ---
		BuildingDef.make("bar_table", "Bar Table", "Dining", L.OBJECT, S.GARDEN_PROP,
			Vector2i(2, 1), 30, true, 1.9, [Color("f0c63a"), Color("8a6239")] as Array[Color]),
		BuildingDef.make("parasol_table", "Parasol Table", "Garden", L.OBJECT, S.GARDEN_PROP,
			Vector2i(2, 1), 16, true, 1.8, [Color("f0c63a"), Color("8a6239")] as Array[Color]),
		BuildingDef.make("garden_fence", "Garden Fence", "Garden", L.OBJECT, S.GARDEN_PROP,
			Vector2i.ONE, 2, true, 0.6, [Color("7a5634"), Color("5a3d24")] as Array[Color]),
	] as Array[BuildingDef]

	_by_id.clear()
	for d in _catalog:
		_by_id[d.id] = d

	# Match actual mesh support surfaces. The shelf uses its upper board, not
	# the taller posts; basin dishes sit inside the rim, not on the ground.
	var surfaces: Dictionary = {
		&"table": 0.78, &"serving_counter": 1.0, &"prep_table": 0.95,
		&"storage_shelf": 1.092, &"barrel": 0.95, &"sink": 0.76,
		&"oven": 1.14, &"brewing_vat": 1.30, &"well": 0.448,
		&"fishing_spot": 0.21, &"bar_table": 0.95, &"parasol_table": 0.78,
	}
	for id in surfaces:
		_by_id[id].item_surface_height = surfaces[id]

	# Garden tiles are for looks: lawns, flower beds and grass are walked like
	# the open ground they are laid on. Only the paths are quicker, and the
	# dearer path the quicker: a dirt path like the road, stone like a floor.
	var ground: float = NavGrid.ROUGH_COST / NavGrid.FLOOR_COST
	var paces: Dictionary = {
		&"garden_path": NavGrid.PATH_COST / NavGrid.FLOOR_COST, &"stone_path": 1.0,
		&"lawn_trimmed": ground, &"lawn_meadow": ground, &"lawn_worn": ground,
		&"grass_tall": ground, &"grass_tall_flowers": ground, &"grass_overgrown": ground,
		&"bed_daisy": ground, &"bed_mixed": ground, &"bed_border": ground,
		&"bed_tulips": ground, &"bed_lavender": ground, &"bed_roses": ground, &"bed_sunflowers": ground,
	}
	for id in paces:
		if _by_id.has(id):
			_by_id[id].walk_cost = paces[id]
			_by_id[id].vary_rotation = true
	# Nobody tramples a flower bed when there is a way round, which is a matter
	# of where they walk, not how fast.
	var keep_off: Dictionary = {
		&"bed_daisy": 2.5, &"bed_mixed": 2.5, &"bed_border": 2.5,
		&"bed_tulips": 2.5, &"bed_lavender": 2.5, &"bed_roses": 2.5, &"bed_sunflowers": 2.5,
		&"grass_tall": 1.4, &"grass_tall_flowers": 1.4, &"grass_overgrown": 1.6,
	}
	for id in keep_off:
		if _by_id.has(id):
			_by_id[id].keep_off = keep_off[id]

	# What the guests and the service make of each piece.
	var roles: Dictionary = {
		&"table": &"table", &"parasol_table": &"table", &"chair": &"chair",
		&"serving_counter": &"counter", &"bar_table": &"bar",
	}
	for id in roles:
		if _by_id.has(id):
			_by_id[id].furniture_role = roles[id]
	if _by_id.has(&"garden_fence"):
		_by_id[&"garden_fence"].drag_outline = true
		_by_id[&"garden_fence"].links = true
	# Where the keeper can take payments: a bench to sell from, or the bar.
	for id in [&"prep_table", &"bar_table"]:
		if _by_id.has(id):
			_by_id[id].takes_payments = true
	# Paths join any path, and are edged where they meet anything else.
	for id in [&"garden_path", &"stone_path"]:
		if _by_id.has(id):
			_by_id[id].links = true
			_by_id[id].link_group = &"path"

	for id in [&"storage_shelf", &"barrel"]:
		if _by_id.has(id):
			_by_id[id].is_storage = true

	# What counts as the edge of a room.
	for id in [&"timber_wall", &"stone_wall", &"door"]:
		if _by_id.has(id):
			_by_id[id].encloses = true

	# The basin takes dirty crockery and nothing else.
	if _by_id.has(&"sink"):
		_by_id[&"sink"].accepts_category = ItemDef.Category.REFUSE

	# A well has to reach water. Six tiles puts the back few rows of the plot in
	# range of the river and nothing else, which is the point.
	if _by_id.has(&"well"):
		_by_id[&"well"].needs_water_within = 6
		# It fills with rain, and keeps water brought to it: water storage.
		_by_id[&"well"].is_storage = true
		_by_id[&"well"].stores_only = [&"water"] as Array[StringName]
	if _by_id.has(&"river_pump"):
		_by_id[&"river_pump"].needs_water_within = 1
	# Fishing is done from the bank itself.
	if _by_id.has(&"fishing_spot"):
		_by_id[&"fishing_spot"].needs_water_within = 2
