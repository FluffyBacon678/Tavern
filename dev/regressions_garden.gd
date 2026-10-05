extends "res://dev/regression_group.gd"

## The garden tile set and the bar: every piece builds, sits in its tab, faces
## the sky, stays inside its triangle budget, and is walked as it should be;
## the bar keeps its drinks and lets guests fetch their own. Run:
##   godot --headless --path . res://dev/regressions.tscn -- group=garden

const TILES: Array[StringName] = [&"lawn_trimmed", &"lawn_meadow", &"lawn_worn", &"garden_path", &"stone_path",
	&"bed_daisy", &"bed_mixed", &"bed_border", &"bed_tulips", &"bed_lavender", &"bed_roses", &"bed_sunflowers",
	&"grass_tall", &"grass_tall_flowers", &"grass_overgrown"]
const PROPS: Array[StringName] = [&"garden_bench", &"garden_rocks", &"garden_tree", &"garden_pine", &"lantern_post"]
## A table under a parasol, and a fence that joins its neighbours.
const GARDEN_FURNITURE: Array[StringName] = [&"parasol_table", &"garden_fence"]
## Triangles a piece may use: a park of a hundred tiles has to stay cheap.
const TILE_BUDGET: int = 900
const PROP_BUDGET: int = 900


func run() -> void:
	var world: TavernWorld = fixture_world
	_check_catalogue()
	_check_meshes()
	_check_walking(world)
	_check_idle(world)
	_check_variety()
	_check_bar(world)
	_check_paths(world)


func _check_catalogue() -> void:
	var garden: Array[BuildingDef] = BuildingCatalog.in_category("Garden")
	check(BuildingCatalog.categories().has("Garden"), "the build bar has a Garden tab")
	# Every garden piece is still offered, as a piece or as a look of one; the
	# parasol table is a look of the table now, in the Dining tab.
	var looks: int = 0
	var buttons: Dictionary = {}
	for def in garden:
		looks += BuildingCatalog.styles_of(def).size()
		buttons[BuildingCatalog.family_of(def)] = true
	var pieces: int = TILES.size() + PROPS.size() + GARDEN_FURNITURE.size() - 1
	check(looks == pieces, "with all %d garden pieces, as pieces or looks (%d)" % [pieces, looks])
	check(buttons.size() == 9, "in 9 buttons: lawn, path, flower bed, wild grass, bench, rocks, tree, lantern, fence (%d)" % buttons.size())
	check(BuildingCatalog.styles_of(BuildingCatalog.get_def(&"bed_daisy")).size() == 7, "the flower bed comes in seven looks")
	check(BuildingCatalog.get_def(&"parasol_table").id == &"table" and BuildingCatalog.get_def(&"parasol_table").category == "Dining",
		"the parasol table is a look of the table")
	for id in TILES + PROPS + GARDEN_FURNITURE:
		check(BuildingCatalog.get_def(id) != null, "%s still loads by its old name" % id)
	check(BuildingCatalog.get_def(&"bar_table").category == "Dining", "the bar table is in the Dining tab: it serves inside and out")
	check(BuildingCatalog.get_def(&"market_stall") == BuildingCatalog.get_def(&"bar_table"),
		"a save naming the old market stall loads it as the bar table")
	for id in TILES:
		var def: BuildingDef = BuildingCatalog.get_def(id)
		check(def != null and def.layer == BuildingDef.Layer.FLOOR and not def.blocks_movement and def.vary_rotation
			and def.size == Vector2i.ONE, "%s is a 1 x 1 floor tile" % id)
		# A floor's height is its slab: a bench or a crate placed on a flower bed
		# sits on the bed, not up among the lupins.
		check(def != null and def.height <= GardenArt.TILE_HEIGHT + 0.001, "%s is a thin bed, so things placed on it sit on it" % id)
	for id in PROPS:
		var def: BuildingDef = BuildingCatalog.get_def(id)
		check(def != null and def.layer == BuildingDef.Layer.OBJECT and def.blocks_movement, "%s is a solid prop" % id)


func _check_meshes() -> void:
	var library := BuildingMeshLibrary.new()
	var counts: PackedStringArray = PackedStringArray()
	for id in TILES + PROPS + GARDEN_FURNITURE + [&"bar_table"]:
		var def: BuildingDef = BuildingCatalog.get_def(id)
		var mesh: Mesh = library.mesh_for(def)
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tris: int = vertices.size() / 3
		counts.append("%s %d" % [id, tris])
		check(tris > 0 and tris <= (TILE_BUDGET if TILES.has(id) else PROP_BUDGET),
			"%s stays inside its budget (%d triangles)" % [id, tris])
		if id == &"bar_table":
			var bar_box: AABB = mesh.get_aabb()
			check(bar_box.position.x >= 0 and bar_box.end.x <= 2.001 and bar_box.position.z >= 0
				and bar_box.end.z <= 1.001, "bar fittings stay inside the unchanged 2 x 1 footprint")
			var clear: bool = true
			for v in vertices:
				if v.y > 0.951:
					for x in [0.5, 1.5]:
						clear = clear and Vector2(v.x - x, v.z - 0.5).length() >= 0.18
			check(clear, "bar taps and bottles leave both drink centres clear above the .95 counter")
		# Seen from the management camera, the top of a tile has to face up: a
		# flat face wound the wrong way vanishes from above.
		if TILES.has(id):
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var down_on_top: int = 0
			for i in range(0, vertices.size(), 3):
				var flat: bool = absf(vertices[i].y - vertices[i + 1].y) < 0.001 and absf(vertices[i].y - vertices[i + 2].y) < 0.001
				if flat and vertices[i].y >= GardenArt.TILE_HEIGHT - 0.0005 and normals[i].y < -0.5:
					down_on_top += 1
			check(down_on_top == 0, "%s: every flat face on top faces the sky" % id)
			var box: AABB = mesh.get_aabb()
			check(box.position.x >= -0.001 and box.end.x <= 1.001 and box.position.z >= -0.001 and box.end.z <= 1.001,
				"%s keeps inside its tile, so neighbours join cleanly" % id)
	var fence_most: int = 0
	for mask in range(16):
		var arrays: Array = library.linked_mesh_for(BuildingCatalog.get_def(&"garden_fence"), mask).surface_get_arrays(0)
		fence_most = maxi(fence_most, (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
	counts.append("fence joints up to %d" % fence_most)
	# Every shape of path joint, in each of its four looks: inside its tile,
	# facing the sky, and cheap.
	for id in [&"garden_path", &"stone_path"]:
		var most: int = 0
		var bad: PackedStringArray = PackedStringArray()
		for mask in range(16):
			for variant in range(4):
				var mesh: Mesh = library.linked_mesh_for(BuildingCatalog.get_def(id), mask, variant)
				var arrays: Array = mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				most = maxi(most, vertices.size() / 3)
				for i in range(0, vertices.size(), 3):
					var flat: bool = absf(vertices[i].y - vertices[i + 1].y) < 0.001 and absf(vertices[i].y - vertices[i + 2].y) < 0.001
					if flat and vertices[i].y >= GardenArt.TILE_HEIGHT - 0.0005 and normals[i].y < -0.5:
						bad.append("%d/%d faces down" % [mask, variant])
						break
				var box: AABB = mesh.get_aabb()
				if box.position.x < -0.001 or box.end.x > 1.001 or box.position.z < -0.001 or box.end.z > 1.001:
					bad.append("%d/%d outside" % [mask, variant])
		counts.append("%s joints up to %d" % [id, most])
		check(bad.is_empty() and most <= TILE_BUDGET, "every %s joint stays in its tile, faces the sky and in budget (%d)%s" % [
			id, most, "" if bad.is_empty() else ": " + ", ".join(bad)])
	check(fence_most <= PROP_BUDGET, "every shape of fence joint stays inside the budget (%d)" % fence_most)
	TestOutput.detail("  triangles: %s" % ", ".join(counts))


## Garden tiles are for looks: lawns, beds and grass walk like open ground,
## and only the paths are quicker, the dearer path the quicker. People still
## go round a flower bed when the lawn goes round it.
func _check_walking(world: TavernWorld) -> void:
	var pace: Dictionary = {}
	for id in TILES:
		pace[id] = BuildingCatalog.get_def(id).walk_cost * NavGrid.FLOOR_COST
	var looks: bool = true
	for id in TILES:
		if not (id in [&"garden_path", &"stone_path"]):
			looks = looks and is_equal_approx(pace[id], NavGrid.ROUGH_COST)
	check(looks, "lawns, flower beds and tall grass walk like open ground: they are for looks")
	check(is_equal_approx(pace[&"garden_path"], NavGrid.PATH_COST) and is_equal_approx(pace[&"stone_path"], NavGrid.FLOOR_COST)
		and BuildingCatalog.get_def(&"stone_path").cost > BuildingCatalog.get_def(&"garden_path").cost,
		"a dirt path walks like the road, and the dearer stone path like a laid floor")

	# A 5 x 3 lawn with a bed across the middle of the straight line: the way
	# through goes round the bed.
	var origin := Vector2i(-1, -1)
	for y in range(world.plot.position.y + 2, world.plot.end.y - 4):
		for x in range(world.plot.position.x + 2, world.plot.end.x - 6):
			var free: bool = true
			for dy in range(3):
				for dx in range(5):
					var t := Vector2i(x + dx, y + dy)
					free = free and world.build.grid.placement_at(t) < 0 and world.nav.is_walkable(t)
			if free:
				origin = Vector2i(x, y)
				break
		if origin.x >= 0:
			break
	check(origin.x >= 0, "the fixture has a clear patch for a lawn")
	if origin.x < 0:
		return
	var placed: Array[int] = []
	for dy in range(3):
		for dx in range(5):
			var id: StringName = &"bed_daisy" if dx == 2 and dy == 1 else &"lawn_trimmed"
			placed.append(world.build.place_programmatic(BuildingCatalog.get_def(id), origin + Vector2i(dx, dy), 0, false))
	world.nav.refresh_all()
	var bed: Vector2i = origin + Vector2i(2, 1)
	check(is_equal_approx(world.nav.cost_at(bed), world.nav.cost_at(origin)), "a step on a flower bed is no slower than one on the lawn")
	var route: Array[Vector2i] = world.nav.find_path(origin + Vector2i(0, 1), origin + Vector2i(4, 1))
	check(not route.is_empty() and not route.has(bed), "people walk round a flower bed when the lawn goes round it")
	for index in placed:
		if index >= 0:
			world.build.grid.remove(index)
	for id in [&"lawn_trimmed", &"bed_daisy"]:
		world.build._rebuild_instances(BuildingCatalog.get_def(id))
	world.nav.refresh_all()


## Idle staff hang about the house's floors, not the park.
func _check_idle(world: TavernWorld) -> void:
	var tile := Vector2i(-1, -1)
	for y in range(world.plot.position.y + 1, world.plot.end.y - 1):
		for x in range(world.plot.position.x + 1, world.plot.end.x - 1):
			var t := Vector2i(x, y)
			if world.build.grid.placement_at(t) < 0 and world.nav.is_walkable(t):
				tile = t
				break
		if tile.x >= 0:
			break
	var index: int = world.build.place_programmatic(BuildingCatalog.get_def(&"lawn_trimmed"), tile, 0, false)
	world.nav.refresh_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var picked_lawn: bool = false
	for i in range(200):
		picked_lawn = picked_lawn or world.nav.random_floor_in(Rect2i(tile, Vector2i.ONE), rng) == tile
	check(not picked_lawn, "idle staff do not wander off to stand on the lawn")
	if index >= 0:
		world.build.grid.remove(index)
	world.build._rebuild_instances(BuildingCatalog.get_def(&"lawn_trimmed"))
	world.nav.refresh_all()


func _check_variety() -> void:
	var turns: Dictionary = {}
	for x in range(8):
		for y in range(8):
			turns[BuildController.tile_turn(Vector2i(x, y))] = true
	check(turns.size() == 4, "a lawn's tiles take all four turns, so it does not repeat")
	check(BuildController.tile_turn(Vector2i(5, 9)) == BuildController.tile_turn(Vector2i(5, 9)),
		"and each tile always the same one")


## A clear, walkable patch of the fixture, or (-1, -1).
func _clear_patch(world: TavernWorld, size: Vector2i) -> Vector2i:
	for y in range(world.plot.position.y + 2, world.plot.end.y - size.y - 1):
		for x in range(world.plot.position.x + 2, world.plot.end.x - size.x - 1):
			var free: bool = true
			for dy in range(size.y):
				for dx in range(size.x):
					var t := Vector2i(x + dx, y + dy)
					free = free and world.build.grid.placement_at(t) < 0 and world.nav.is_walkable(t)
			if free:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## The bar works as one: guests sit at the parasol table; the bar keeps its
## own lemonade on one tile of its counter and beer on the next; its lemons
## wait beside it; porters stock its beer; a guest beside it can take a drink;
## and the fence turns its corners.
func _check_bar(world: TavernWorld) -> void:
	var bar: BuildingDef = BuildingCatalog.get_def(&"bar_table")
	var parasol: BuildingDef = BuildingCatalog.get_def(&"parasol_table")
	var fence: BuildingDef = BuildingCatalog.get_def(&"garden_fence")
	check(parasol.furniture_role == &"table" and bar.furniture_role == &"bar",
		"a parasol table seats guests like a table, and the bar keeps drinks")
	var press: Recipe = RecipeCatalog.get_recipe(&"press_lemonade")
	check(press != null and press.station_id == &"bar_table" and press.work_kind == WorkType.Kind.COOK,
		"the bar presses its own lemonade, as kitchen work")
	check(ItemCatalog.get_def(&"lemons") != null and ItemCatalog.get_def(&"lemons").purchase_price > 0
		and ItemCatalog.get_def(&"lemonade").sell_value > 0, "lemons are bought, lemonade is sold")
	var drinks: Array[StringName] = CustomerDirector.bar_drinks(bar)
	check(drinks.size() >= 2 and drinks[0] == &"lemonade" and drinks.has(&"beer"),
		"a bar keeps its own lemonade first and the beer beside it (%s)" % ", ".join(drinks))
	check(fence.drag_outline and fence.links, "a fence drags like a wall and joins its neighbours")
	check(GuestType.of(PawnMesh.Look.RANGER).prefers_bar() and not GuestType.of(PawnMesh.Look.WIZARD).prefers_bar(),
		"a ranger in a hurry fetches a drink from the bar; a patient wizard waits to be served")

	var at: Vector2i = _clear_patch(world, Vector2i(8, 7))
	check(at.x >= 0, "the fixture has room for a garden and a bar")
	if at.x < 0:
		return
	var placed: Array[int] = []
	var put := func(id: StringName, offset: Vector2i) -> void:
		placed.append(world.build.place_programmatic(BuildingCatalog.get_def(id), at + offset, 0, false))
	put.call(&"parasol_table", Vector2i(3, 1))
	put.call(&"chair", Vector2i(2, 1))
	put.call(&"chair", Vector2i(5, 1))
	put.call(&"bar_table", Vector2i(3, 4))
	world.nav.refresh_all()
	world.customers.seating.refresh()
	check(world.customers.seating.table_for(at + Vector2i(2, 1)) != Seating.NO_SEAT, "a chair beside a parasol table is a seat")
	var lemonade_tile: Vector2i = at + Vector2i(3, 4)
	var beer_tile: Vector2i = at + Vector2i(4, 4)
	var plated_onto: Array = []
	for c in world.customers._counters():
		plated_onto.append(int(c["index"]))
	check(world.customers.pass_tiles().has(lemonade_tile) and world.customers.pass_tiles().has(beer_tile)
		and not plated_onto.has(placed[3]), "waiters can fetch from the bar, and the kitchen plates nothing onto it")

	var station: Dictionary = world.generator.station_at(placed[3])
	var lemons_go := Vector2i(-1, -1)
	var jugs_go: Array = []
	if not station.is_empty():
		lemons_go = world.generator._feed_destination(station, ItemCatalog.get_def(&"lemons"))
		jugs_go = world.generator._output_tiles(station, &"lemonade")
	check(lemons_go.x >= 0 and not station["tiles"].has(lemons_go),
		"the bar's lemons wait on the ground beside it, so its counter stays free for drinks")
	check(not jugs_go.is_empty() and jugs_go[0] == lemonade_tile and not jugs_go.has(beer_tile),
		"its lemonade goes on its own tile, leaving the next for the beer")

	# Porters keep the beer on it.
	var beer: ItemDef = ItemCatalog.get_def(&"beer")
	var cellar: Vector2i = at + Vector2i(7, 6)
	world.items.add(beer, 4, cellar)
	world.generator.scan()
	var stocking: Job = world.board.job_with_key("bar:%d,%d" % [beer_tile.x, beer_tile.y])
	check(stocking != null and stocking.carry_def == beer and stocking.target == beer_tile and stocking.kind == WorkType.Kind.HAUL,
		"porters are sent to stock the bar with beer")
	if stocking != null:
		world.board.cancel_key(stocking.key)

	# A guest wanting lemonade is sent to stand beside the bar, where it is to hand.
	var lemonade: ItemDef = ItemCatalog.get_def(&"lemonade")
	world.items.add(lemonade, 2, lemonade_tile)
	check(world.customers.has_bar_drinks(), "a bar with lemonade on its counter has a drink to be had")
	var stand: Vector2i = world.customers.bar_stand([{"id": &"lemonade", "count": 1, "served": 0}], at + Vector2i(2, 1))
	check(stand.x >= 0 and world.nav.is_walkable(stand) and world.customers.bar_tiles_at(stand, &"lemonade").has(lemonade_tile),
		"a guest wanting lemonade stands at the bar, where its lemonade is to hand")
	check(world.customers.bar_stand([{"id": &"bread", "count": 1, "served": 0}], at) == Vector2i(-1, -1),
		"nobody is sent to a bar for something it does not keep")
	_check_guest_purchase(world, stand, at + Vector2i(2, 1))

	# A review part the game no longer scores (a garden's Surroundings, for a
	# while) loads without it, rather than costing the save its guests.
	var review: Review = Review.write("Ada", true, 10, 0.5, 0.5, 2, 0.5)
	world.customers.day_reviews.append(review)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(CustomerSnapshot.capture(world.customers)))
	world.customers.day_reviews.erase(review)
	saved["reviews"].back()["parts"]["4"] = 5
	check(CustomerSnapshot.valid(saved), "a saved review with a part the game no longer scores still loads")

	# A fence run with a corner: each piece shows an arm toward its neighbours.
	for offset in [Vector2i(0, 6), Vector2i(1, 6), Vector2i(1, 5)]:
		put.call(&"garden_fence", offset)
	check(world.build.link_mask(fence, at + Vector2i(0, 6)) == 2 and world.build.link_mask(fence, at + Vector2i(1, 6)) == 1 | 8
		and world.build.link_mask(fence, at + Vector2i(1, 5)) == 4, "a fence's corner joins both ways, its ends one way")

	for tile in [lemonade_tile, beer_tile, cellar]:
		if world.items.count_at(tile) > 0:
			world.items.take(tile, world.items.count_at(tile))
	for index in placed:
		if index >= 0:
			world.build.grid.remove(index)
	for id in [&"parasol_table", &"chair", &"bar_table", &"garden_fence"]:
		world.build._rebuild_instances(BuildingCatalog.get_def(id))
	world.nav.refresh_all()
	world.customers.seating.refresh()


func _check_guest_purchase(world: TavernWorld, stand: Vector2i, chair: Vector2i) -> void:
	if stand.x < 0:
		return
	var pawn := Pawn.new()
	world.add_child(pawn)
	pawn.setup(world.nav, world.terrain, stand, world._pawn_material, 804, true)
	pawn.autonomous_idle = false
	var brain := CustomerBrain.new()
	brain.setup(pawn, world.customers, world.customers.seating, world.items, world.nav, 806)
	brain.state = CustomerBrain.State.GOING_TO_BAR
	brain.seat = chair
	brain.at_bar = true
	brain.order = [{"id": &"lemonade", "count": 1, "served": 0}]
	var before: int = world.items.total_of(&"lemonade")
	var eaten: int = world.customers.consumed.get(&"lemonade", 0)
	brain._process_going_to_bar()
	brain._process(0)
	var dice: int = world.sim_rng.state
	for i in range(20):
		brain._process(0)
	check(brain.state == CustomerBrain.State.BACK_FROM_BAR and pawn.is_busy() and is_instance_valid(pawn._display_carried),
		"a real walk-up purchase shows its drink while the guest walks back to the chair")
	check(world.items.total_of(&"lemonade") == before - 1 and world.customers.consumed.get(&"lemonade", 0) == eaten + 1
		and world.sim_rng.state == dice and not pawn.is_carrying(),
		"twenty rendered purchase frames still debit exactly one drink, with no physical cargo or dice")
	brain.free()
	pawn.free()


## Paths join any path and are edged where they meet anything else.
func _check_paths(world: TavernWorld) -> void:
	var at: Vector2i = _clear_patch(world, Vector2i(4, 3))
	check(at.x >= 0, "the fixture has room for a path")
	if at.x < 0:
		return
	var dirt: BuildingDef = BuildingCatalog.get_def(&"garden_path")
	var stone: BuildingDef = BuildingCatalog.get_def(&"stone_path")
	var placed: Array[int] = []
	placed.append(world.build.place_programmatic(dirt, at + Vector2i(0, 1), 0, false))
	placed.append(world.build.place_programmatic(dirt, at + Vector2i(1, 1), 0, false))
	placed.append(world.build.place_programmatic(stone, at + Vector2i(2, 1), 0, false))
	placed.append(world.build.place_programmatic(BuildingCatalog.get_def(&"lawn_trimmed"), at + Vector2i(1, 0), 0, false))
	check(world.build.link_mask(dirt, at + Vector2i(1, 1)) == 2 | 8, "a dirt path joins the path either side of it, edged where it meets lawn")
	check(world.build.link_mask(stone, at + Vector2i(2, 1)) == 8, "a stone path runs on from a dirt one with no verge between them")
	for index in placed:
		if index >= 0:
			world.build.grid.remove(index)
	for def in [dirt, stone, BuildingCatalog.get_def(&"lawn_trimmed")]:
		world.build._rebuild_instances(def)
	world.nav.refresh_all()
