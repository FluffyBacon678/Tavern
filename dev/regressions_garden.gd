extends "res://dev/regression_group.gd"

## The garden tile set: every piece builds, sits in the Garden tab, faces the
## sky, stays inside its triangle budget, and changes how people walk. Run:
##   godot --headless --path . res://dev/regressions.tscn -- group=garden

const TILES: Array[StringName] = [&"lawn_trimmed", &"lawn_meadow", &"lawn_worn", &"garden_path",
	&"bed_daisy", &"bed_mixed", &"bed_border", &"grass_tall", &"grass_tall_flowers", &"grass_overgrown"]
const PROPS: Array[StringName] = [&"garden_bench", &"garden_rocks", &"garden_tree", &"garden_pine", &"lantern_post"]
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


func _check_catalogue() -> void:
	var garden: Array[BuildingDef] = BuildingCatalog.in_category("Garden")
	check(BuildingCatalog.categories().has("Garden"), "the build bar has a Garden tab")
	check(garden.size() == TILES.size() + PROPS.size(), "with all %d garden pieces" % (TILES.size() + PROPS.size()))
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
	for id in TILES + PROPS:
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
