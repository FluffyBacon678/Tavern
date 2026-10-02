class_name TestHouse
extends RefCounted

## The sandbox's starting tavern, for now: a big finished house with one of
## everything, so every building and every position can be tried from the
## first minute. A 24 x 10 hall -- dining west, kitchen east, the counter and
## host's stand by the door -- with a well, a river pump, a fishing spot and a
## field outside, one of each position on the staff, and a stocked larder.
##
## Everything is placed finished and free. Pieces that do not fit on a given
## map (no river bank in the plot, say) are simply left out.

const SIZE := Vector2i(24, 10)
## Offsets inside the hall's floor.
const TABLES: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 4), Vector2i(1, 7), Vector2i(6, 1), Vector2i(6, 4), Vector2i(6, 7)]
const COUNTER := Vector2i(14, 4)
const HOST := Vector2i(10, 8)
const PREP := Vector2i(17, 0)
const OVEN := Vector2i(17, 3)
const VAT := Vector2i(17, 6)
const SINK := Vector2i(21, 0)
const SHELVES: Array[Vector2i] = [Vector2i(21, 3), Vector2i(21, 5)]
const BARRELS: Array[Vector2i] = [Vector2i(23, 7), Vector2i(23, 8), Vector2i(21, 8)]
## Water barrels beside the vat and the prep table. Without them every barrel
## ended up in the well by the river, and the cooks walked there for each one.
const WATER_BARRELS: Array[Vector2i] = [Vector2i(23, 1), Vector2i(23, 3), Vector2i(23, 5)]
const DOOR_X: int = 12
## The rest of a full crew, on top of the opening five.
const EXTRA_CREW: Array[StringName] = [&"porter", &"cook", &"waiter", &"waiter", &"busser", &"host", &"fisherman", &"farmer"]
const STOCK: Dictionary = {&"flour": 10, &"yeast": 10, &"water": 12, &"malt": 8, &"hops": 8}
const GOLD: int = 2000


## The hall's floor: its south wall sits where the tutorial room's does, three
## rows above the unloading yard.
static func hall(world) -> Rect2i:
	return Rect2i(world.plot.position + Vector2i(5, world.plot.size.y - 16), SIZE)


static func build(world) -> void:
	var h: Rect2i = hall(world)
	var at := func(spot: Vector2i) -> Vector2i: return h.position + spot
	for y in range(h.size.y):
		for x in range(h.size.x):
			_put(world, &"wood_floor", h.position + Vector2i(x, y))
	for y in range(-1, h.size.y + 1):
		for x in range(-1, h.size.x + 1):
			if x == -1 or y == -1 or x == h.size.x or y == h.size.y:
				var door: bool = y == h.size.y and x == DOOR_X
				_put(world, &"door" if door else &"timber_wall", h.position + Vector2i(x, y))
	for t in TABLES:
		_put(world, &"table", at.call(t))
		_put(world, &"chair", at.call(t + Vector2i(-1, 0)))
		_put(world, &"chair", at.call(t + Vector2i(2, 0)))
	_put(world, &"serving_counter", at.call(COUNTER))
	_put(world, &"host_stand", at.call(HOST))
	_put(world, &"prep_table", at.call(PREP))
	_put(world, &"oven", at.call(OVEN))
	_put(world, &"brewing_vat", at.call(VAT))
	_put(world, &"sink", at.call(SINK))
	for t in SHELVES:
		_put(world, &"storage_shelf", at.call(t))
	for t in BARRELS:
		_put(world, &"barrel", at.call(t))
	for t in WATER_BARRELS:
		var index: int = _put(world, &"barrel", at.call(t))
		if index >= 0:
			world.build.grid.set_filter(index, [&"water"])

	# Outside: water, fish and a field.
	_put_first(world, &"fishing_spot", _bank_spots(world, &"fishing_spot"))
	_put_first(world, &"river_pump", _bank_spots(world, &"river_pump"))
	var well: Vector2i = TutorialPlan.well_spot(world)
	if well.x >= 0:
		_put(world, &"well", well)
	var field := Rect2i(h.position + Vector2i(2, -8), Vector2i(8, 4))
	for y in range(field.size.y):
		for x in range(field.size.x):
			_put(world, &"farm_plot", field.position + Vector2i(x, y))
	# Hops on one row, wheat on the rest.
	for x in range(field.size.x):
		var index: int = world.build.grid.floor_index_at(field.position + Vector2i(x, 0))
		if index >= 0 and world.build.grid.placements[index]["def"].id == &"farm_plot":
			world.build.grid.placements[index]["crop"] = &"hops"

	for def in BuildingCatalog.all():
		world.build._rebuild_instances(def)
	world.nav.refresh_all()
	world.customers.seating.refresh()

	# Everyone, and a stocked larder.
	for role_id in EXTRA_CREW:
		world.bootstrap._add_pawn(world._find("Pawns"), world.sim_rng.randi(), StaffRole.of(role_id))
	var shelf: Vector2i = at.call(SHELVES[0])
	for id in STOCK:
		var def: ItemDef = ItemCatalog.get_def(id)
		var n: int = world.items.place_near(def, int(STOCK[id]), shelf)
		world.delivered[id] = int(world.delivered.get(id, 0)) + n
	GameState.gold = GOLD
	if world.rig != null:
		var middle: Vector2 = Vector2(h.position) + Vector2(h.size) * 0.5
		world.rig.focus_on(Vector3(middle.x, world.terrain.plot_height, middle.y))


static func _put(world, id: StringName, tile: Vector2i) -> int:
	return world.build.place_programmatic(BuildingCatalog.get_def(id), tile, 0, false)


static func _put_first(world, id: StringName, tiles: Array) -> void:
	for tile in tiles:
		if _put(world, id, tile) >= 0:
			return


## Tiles where a riverside piece fits, nearest the hall first.
static func _bank_spots(world, id: StringName) -> Array:
	var def: BuildingDef = BuildingCatalog.get_def(id)
	var middle: Vector2i = hall(world).position + hall(world).size / 2
	var out: Array = []
	for y in range(world.plot.position.y, world.plot.end.y):
		for x in range(world.plot.position.x, world.plot.end.x):
			var tile := Vector2i(x, y)
			if world.build.grid.placement_problem(def, tile, 0) == "":
				out.append(tile)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - middle).length_squared() < (b - middle).length_squared())
	return out
