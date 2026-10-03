extends "res://dev/regression_group.gd"

## The garden tile set: every piece builds, sits in the Garden tab, faces the
## sky, stays inside its triangle budget, and changes how people walk. Run:
##   godot --headless --path . res://dev/regressions.tscn -- group=garden

const TILES: Array[StringName] = [&"lawn_trimmed", &"lawn_meadow", &"lawn_worn", &"garden_path",
	&"bed_daisy", &"bed_mixed", &"bed_border", &"grass_tall", &"grass_tall_flowers", &"grass_overgrown"]
const PROPS: Array[StringName] = [&"garden_bench", &"garden_rocks", &"garden_tree", &"garden_pine", &"lantern_post"]
## The lemonade stand: a stall that is a pass and a press, a table under a
## parasol, and a fence that joins its neighbours.
const STAND: Array[StringName] = [&"market_stall", &"parasol_table", &"garden_fence"]
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
	_check_stand(world)


func _check_catalogue() -> void:
	var garden: Array[BuildingDef] = BuildingCatalog.in_category("Garden")
	check(BuildingCatalog.categories().has("Garden"), "the build bar has a Garden tab")
	var pieces: int = TILES.size() + PROPS.size() + STAND.size()
	check(garden.size() == pieces, "with all %d garden pieces" % pieces)
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
	for id in TILES + PROPS + STAND:
		var def: BuildingDef = BuildingCatalog.get_def(id)
		var mesh: Mesh = library.mesh_for(def)
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tris: int = vertices.size() / 3
		counts.append("%s %d" % [id, tris])
		check(tris > 0 and tris <= (TILE_BUDGET if TILES.has(id) else PROP_BUDGET),
			"%s stays inside its budget (%d triangles)" % [id, tris])
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
	check(fence_most <= PROP_BUDGET, "every shape of fence joint stays inside the budget (%d)" % fence_most)
	TestOutput.detail("  triangles: %s" % ", ".join(counts))


## Paths are quickest, flower beds are walked round.
func _check_walking(world: TavernWorld) -> void:
	var pace: Dictionary = {}
	for id in TILES:
		pace[id] = BuildingCatalog.get_def(id).walk_cost
	check(pace[&"garden_path"] <= pace[&"lawn_trimmed"] and pace[&"lawn_trimmed"] < pace[&"grass_tall"]
		and pace[&"grass_tall"] < pace[&"bed_daisy"], "paths are quickest, then lawns, then tall grass, then flower beds")

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
	check(is_equal_approx(world.nav.cost_at(bed), pace[&"bed_daisy"] * NavGrid.FLOOR_COST), "a flower bed is slow going underfoot")
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


## The stand works as one: guests sit at the parasol table, the kitchen plates
## onto the stall, waiters press its lemonade with the lemons on the ground
## beside it, the fence turns its corners, and a seat among flowers is enjoyed.
func _check_stand(world: TavernWorld) -> void:
	var stall: BuildingDef = BuildingCatalog.get_def(&"market_stall")
	var parasol: BuildingDef = BuildingCatalog.get_def(&"parasol_table")
	var fence: BuildingDef = BuildingCatalog.get_def(&"garden_fence")
	check(parasol.furniture_role == &"table" and stall.furniture_role == &"counter",
		"a parasol table seats guests like a table, a stall is a pass like a counter")
	var press: Recipe = RecipeCatalog.get_recipe(&"press_lemonade")
	check(press != null and press.station_id == &"market_stall" and press.work_kind == WorkType.Kind.COOK,
		"the stall presses lemonade, as kitchen work")
	check(ItemCatalog.get_def(&"lemons") != null and ItemCatalog.get_def(&"lemons").purchase_price > 0
		and ItemCatalog.get_def(&"lemonade").sell_value > 0, "lemons are bought, lemonade is sold")
	check(fence.drag_outline and fence.links, "a fence drags like a wall and joins its neighbours")

	var at: Vector2i = _clear_patch(world, Vector2i(8, 7))
	check(at.x >= 0, "the fixture has room for a garden stand")
	if at.x < 0:
		return
	var placed: Array[int] = []
	var put := func(id: StringName, offset: Vector2i) -> void:
		placed.append(world.build.place_programmatic(BuildingCatalog.get_def(id), at + offset, 0, false))
	put.call(&"parasol_table", Vector2i(3, 1))
	put.call(&"chair", Vector2i(2, 1))
	put.call(&"chair", Vector2i(5, 1))
	put.call(&"market_stall", Vector2i(3, 4))
	world.nav.refresh_all()
	world.customers.seating.refresh()
	var chair: Vector2i = at + Vector2i(2, 1)
	check(world.customers.seating.table_for(chair) != Seating.NO_SEAT, "a chair beside a parasol table is a seat")
	var counter: Array[Vector2i] = world.customers.pass_tiles()
	var as_counter: Dictionary = {}
	for c in world.customers._counters():
		if int(c["index"]) == placed[3]:
			as_counter = c
	check(counter.has(at + Vector2i(3, 4)) and counter.has(at + Vector2i(4, 4)) and bool(as_counter.get("stall", false)),
		"the stall is the garden's own counter, plated onto and served from")

	var station: Dictionary = world.generator.station_at(placed[3])
	var lemons_go := Vector2i(-1, -1)
	var jugs_go: Array = []
	if not station.is_empty():
		lemons_go = world.generator._feed_destination(station, ItemCatalog.get_def(&"lemons"))
		jugs_go = world.generator._output_tiles(station)
	check(lemons_go.x >= 0 and not station["tiles"].has(lemons_go),
		"the stall's lemons wait on the ground beside it, so its top stays free for jugs and plates")
	check(not jugs_go.is_empty() and jugs_go[0] == at + Vector2i(3, 4) and not jugs_go.has(at + Vector2i(4, 4)),
		"its jugs go on its first tile, keeping the rest of its top for the kitchen's plates")

	# The view: something lovely near the seat counts, more of it counts more.
	var bare: float = CustomerBrain.view_from(world.build.grid, chair)
	for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 2), Vector2i(1, 2)]:
		put.call(&"bed_mixed", offset)
	var planted: float = CustomerBrain.view_from(world.build.grid, chair)
	check(planted > bare and bare > 0.0, "flower beds near a seat make a lovelier view (%.2f -> %.2f)" % [bare, planted])
	var indoors: Vector2i = Seating.NO_SEAT
	for seat in world.customers.seating.seats:
		if Rect2i(at - Vector2i(4, 4), Vector2i(16, 15)).has_point(seat["chair"]):
			continue
		indoors = seat["chair"]
		break
	check(indoors != Seating.NO_SEAT and CustomerBrain.view_from(world.build.grid, indoors) == 0.0,
		"a seat with nothing lovely near it has no view to speak of")

	# Surroundings only ever add: nothing to look at scores exactly as before.
	var plain: Review = Review.write("Ada", true, 10, 0.5, 0.5, 2, 0.5)
	var lovely: Review = Review.write("Ada", true, 10, 0.5, 0.5, 2, 0.5, -1.0, {}, 1.0)
	check(not plain.parts.has(Review.Part.SURROUNDINGS) and lovely.satisfaction - plain.satisfaction == 10,
		"a garden adds up to ten points to a visit and takes nothing away (%d -> %d)" % [plain.satisfaction, lovely.satisfaction])
	# And it saves: a review naming the new part once failed the load check,
	# and every guest in the save went with it.
	world.customers.day_reviews.append(lovely)
	var saved: Variant = JSON.parse_string(JSON.stringify(CustomerSnapshot.capture(world.customers)))
	world.customers.day_reviews.erase(lovely)
	check(CustomerSnapshot.valid(saved), "a day's reviews with Surroundings in them pass the save's load check")

	# A fence run with a corner: each piece shows an arm toward its neighbours.
	for offset in [Vector2i(0, 6), Vector2i(1, 6), Vector2i(1, 5)]:
		put.call(&"garden_fence", offset)
	check(world.build.link_mask(fence, at + Vector2i(0, 6)) == 2 and world.build.link_mask(fence, at + Vector2i(1, 6)) == 1 | 8
		and world.build.link_mask(fence, at + Vector2i(1, 5)) == 4, "a fence's corner joins both ways, its ends one way")

	for index in placed:
		if index >= 0:
			world.build.grid.remove(index)
	for id in [&"parasol_table", &"chair", &"market_stall", &"bed_mixed", &"garden_fence"]:
		world.build._rebuild_instances(BuildingCatalog.get_def(id))
	world.nav.refresh_all()
	world.customers.seating.refresh()
