class_name WorldBootstrap
extends RefCounted

## Constructs rendering and wires simulation dependencies in startup order.
var world: TavernWorld


func _build_materials() -> void:
	# Shared vertex-colour shaders keep landscape batches intact. Trees use a
	# second material instance so only their crowns receive wind displacement.
	world._opaque_material = ShaderMaterial.new()
	world._opaque_material.shader = preload("res://src/world/world3d/landscape_atmosphere.gdshader")
	world._forest_material = world._opaque_material.duplicate()
	world._forest_material.set_shader_parameter("foliage", true)
	world._water_material = ShaderMaterial.new()
	world._water_material.shader = preload("res://src/world/world3d/river_atmosphere.gdshader")


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.91, 0.75)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.68
	sun.directional_shadow_max_distance = 90.0
	world.add_child(sun)

	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://src/world/world3d/tavern_sky.gdshader")

	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# A warm fill keeps aprons and oak readable behind walls. Sky-only ambient
	# gave every shaded surface a cold grey tint and hid the workers indoors.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5bc9d")
	env.ambient_light_sky_contribution = 0.15
	env.ambient_light_energy = 0.7
	# Distance fog does a lot of work on a low-poly scene: it hides the map edge
	# and gives depth that flat-shaded geometry does not provide on its own.
	env.fog_enabled = true
	env.fog_light_color = Color("a5ae8a")
	env.fog_density = 0.003

	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	world.atmosphere = WorldAtmosphere.new()
	world.atmosphere.name = "Atmosphere"
	world.add_child(world.atmosphere)
	world.atmosphere.setup(world, sun, env, sky_material)


## Clear the plot before the terrain is meshed: no trees, no rock, and above all
## no water, since flattening a river tile would leave a pond sitting on the
## level building site. Margin of one tile so the boundary is not flush with
## standing forest.
func _clear_plot() -> void:
	var margin: int = 1
	for y in range(world.plot.position.y - margin, world.plot.end.y + margin):
		for x in range(world.plot.position.x - margin, world.plot.end.x + margin):
			if x < 0 or y < 0 or x >= world.grid.cols or y >= world.grid.rows:
				continue
			var i: int = y * world.grid.cols + x
			if world.grid.cells[i] != TerrainGrid.Cell.DIRT:
				world.grid.cells[i] = TerrainGrid.Cell.GRASS
			world.grid.water_flags[i] = 0


## Packed dirt from the map's edge up to an unloading yard inside the boundary.
##
## Deliveries used to materialise on an arbitrary row of grass, which said
## nothing about where they came from. A road makes the supply line a *place*:
## the cart comes up it, stops in the yard, and the sacks that appear there are
## obviously something that arrived rather than something that was conjured.
## Customers walk in the same way, so the approach reads as the front of the
## house without any of it being scripted.
##
## Carved after _clear_plot(), which wipes the terrain flags it sets.
func _carve_approach() -> void:
	var yard: Rect2i = world.unloading_yard()
	for y in range(yard.position.y, yard.end.y):
		for x in range(yard.position.x, yard.end.x):
			_pave(x, y)

	# The road out: four tiles wide, from the yard's near edge to the map's
	# southern border. Anything standing in the way is cleared -- a road with a
	# tree in it is not a road.
	var road_x0: int = yard.position.x + 2
	var road_x1: int = road_x0 + 4
	for y in range(yard.end.y, world.grid.rows):
		for x in range(road_x0, road_x1):
			_pave(x, y)
		# A verge either side. Without it the canopy closes over the road and
		# the approach reads as forest with a stripe in it rather than a way in.
		for x in [road_x0 - 2, road_x0 - 1, road_x1, road_x1 + 1]:
			_clear_to_grass(x, y)

	# The high road: east to west across the whole map, a little south of the
	# plot, crossing the lane up to the yard. Adventurers come along it from
	# either end and turn up the lane to the tavern -- one entrance, and a
	# place for a player-built path to join later.
	var row: int = world.high_road_row()
	for x in range(world.grid.cols):
		for y in range(row - 1, row + 2):
			_pave(x, y)
		_clear_to_grass(x, row - 2)
		_clear_to_grass(x, row + 2)


## Take whatever is standing here down to open grass, leaving the ground type
## alone if it is already bare.
func _clear_to_grass(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= world.grid.cols or y >= world.grid.rows:
		return
	var i: int = y * world.grid.cols + x
	if world.grid.cells[i] == TerrainGrid.Cell.TREE or world.grid.cells[i] == TerrainGrid.Cell.ROCK:
		world.grid.cells[i] = TerrainGrid.Cell.GRASS


func _pave(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= world.grid.cols or y >= world.grid.rows:
		return
	var i: int = y * world.grid.cols + x
	world.grid.cells[i] = TerrainGrid.Cell.DIRT
	world.grid.water_flags[i] = TerrainGrid.FLAG_PATH


## A river along the back boundary.
##
## Placed rather than left to the noise, because it has a job: it is what a
## water-drawing building has to be near, so the back of the plot becomes worth
## something and "where do I put the well" becomes a question with an answer.
## Kept outside the cleared margin so it survives the levelling, and given a
## gentle wander so it does not read as a canal.
func _carve_river() -> void:
	var base: int = world.river_row
	for x in range(world.grid.cols):
		var wander: int = int(round(sin(float(x) * 0.17) * 1.6 + sin(float(x) * 0.41) * 0.7))
		for d in range(RIVER_WIDTH):
			var y: int = base + wander - d
			if y < 0 or y >= world.grid.rows:
				continue
			var i: int = y * world.grid.cols + x
			world.grid.cells[i] = TerrainGrid.Cell.WATER
			world.grid.water_flags[i] = 0


## A thin outline on the ground marking the land the player owns. Without it the
## buildable region is invisible until a placement is refused.
## How many tiles across the back river runs.
const RIVER_WIDTH: int = 3

const CART_TIMBER := Color("8a6438")
const CART_TIMBER_DARK := Color("5d4326")
const CART_IRON := Color("46484a")


## The yard, marked out and with the supplier's cart standing in it.
##
## A cart that never moves, deliberately. It is a signpost, not a simulation:
## the player needs to know at a glance where goods will appear and which way
## the road runs, and an animated wagon that arrives and leaves would be state
## to save, restore and get wrong for no gain the player can act on.
func _build_yard() -> void:
	var existing: Node = world._find("Yard")
	if existing != null:
		existing.queue_free()

	var yard: Rect2i = world.unloading_yard()
	var mb := MeshBuilder.new()
	var y: float = world.terrain.plot_height + 0.035

	# A dashed edge rather than a solid outline: the yard is a place to leave
	# things, not a boundary, and a hard line would read as a wall.
	var col := Color(0.78, 0.66, 0.40, 0.45)
	var t: float = 0.1
	for x in range(yard.position.x, yard.end.x):
		if x % 2 == 1:
			continue
		mb.add_quad(
			Vector3(float(x) + 0.1, y, float(yard.position.y)),
			Vector3(float(x) + 0.1, y, float(yard.position.y) + t),
			Vector3(float(x) + 0.9, y, float(yard.position.y) + t),
			Vector3(float(x) + 0.9, y, float(yard.position.y)),
			col
		)

	_add_cart(mb, Vector2(float(yard.end.x) + 0.6, float(yard.position.y) + 1.5), world.terrain.plot_height)

	var node := MeshInstance3D.new()
	node.name = "Yard"
	node.mesh = mb.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = mat
	world.add_child(node)


## A flat-bed wagon, parked across the road so its long side faces the yard --
## the side you would actually unload from.
func _add_cart(mb: MeshBuilder, centre: Vector2, ground: float) -> void:
	var bed_y: float = ground + 0.42
	var half_w: float = 0.55
	var half_l: float = 1.15

	# Bed and the boards around it.
	mb.add_box(Vector3(centre.x - half_w, bed_y, centre.y - half_l), Vector3(half_w * 2.0, 0.09, half_l * 2.0), CART_TIMBER)
	for side in [-1.0, 1.0]:
		mb.add_box(
			Vector3(centre.x + side * half_w - 0.06, bed_y + 0.09, centre.y - half_l),
			Vector3(0.12, 0.34, half_l * 2.0),
			CART_TIMBER_DARK
		)
	mb.add_box(
		Vector3(centre.x - half_w, bed_y + 0.09, centre.y - half_l),
		Vector3(half_w * 2.0, 0.34, 0.11),
		CART_TIMBER_DARK
	)

	# Four wheels, each a short cylinder lying on its side across the axle.
	for sx in [-1.0, 1.0]:
		for sz in [-0.72, 0.72]:
			var hub := Vector3(centre.x + sx * (half_w + 0.02), ground + 0.3, centre.y + sz)
			mb.add_limb(
				hub - Vector3(sx * 0.05, 0.0, 0.0),
				hub + Vector3(sx * 0.07, 0.0, 0.0),
				0.3, 0.3, 10, CART_TIMBER_DARK
			)
			mb.add_limb(
				hub - Vector3(sx * 0.02, 0.0, 0.0),
				hub + Vector3(sx * 0.09, 0.0, 0.0),
				0.09, 0.09, 8, CART_IRON
			)

	# Shafts, pointing back down the road towards wherever the horse went.
	for sx in [-0.34, 0.34]:
		mb.add_limb(
			Vector3(centre.x + sx, bed_y, centre.y + half_l - 0.1),
			Vector3(centre.x + sx * 0.8, ground + 0.5, centre.y + half_l + 1.2),
			0.06, 0.05, 6, CART_TIMBER
		)


func _build_plot_marker() -> void:
	var existing: Node = world._find("PlotMarker")
	if existing != null:
		existing.queue_free()

	var mb := MeshBuilder.new()
	var y: float = world.terrain.plot_height + 0.03
	var col := Color(0.92, 0.78, 0.42, 0.5)
	var t: float = 0.12
	var x0: float = float(world.plot.position.x)
	var z0: float = float(world.plot.position.y)
	var x1: float = float(world.plot.end.x)
	var z1: float = float(world.plot.end.y)
	# Four thin quads rather than an outlined box: cheaper, and it lies flat.
	mb.add_quad(Vector3(x0, y, z0), Vector3(x0, y, z0 + t), Vector3(x1, y, z0 + t), Vector3(x1, y, z0), col)
	mb.add_quad(Vector3(x0, y, z1 - t), Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z1 - t), col)
	mb.add_quad(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x0 + t, y, z1), Vector3(x0 + t, y, z0), col)
	mb.add_quad(Vector3(x1 - t, y, z0), Vector3(x1 - t, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), col)

	var marker := MeshInstance3D.new()
	marker.name = "PlotMarker"
	marker.mesh = mb.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(marker)


func _setup_build() -> void:
	if world.build == null:
		world.build = BuildController.new()
		world.build.name = "Build"
		world.add_child(world.build)
		world.build.placed.connect(func(_def: BuildingDef) -> void: world.hud.refresh_stats())
		# Say how much ground is being painted, and what it will cost, while the
		# drag is still going -- afterwards is too late to change your mind.
		world.build.drag_changed.connect(func(tiles: int, cost: int) -> void:
			if tiles <= 0 or world.hud._build_bar == null:
				return
			# Against the purse, and against what the tavern must keep in hand:
			# the drag that emptied the purse on the first morning said only
			# "140 tiles - 280g".
			var note: Array = world.cost_note(cost, tiles)
			var colours: Array = [TavernTheme.PARCHMENT, TavernTheme.CANDLE, TavernTheme.DANGER]
			world.hud._build_bar._set_status(note[0], colours[int(note[1])])
		)
	world.board.clear()
	world.build.board = world.board
	world.build.setup(world.grid.cols, world.grid.rows, world.plot, world.terrain, world.terrain.plot_height)
	if world.hud._build_bar != null:
		world.hud._build_bar.setup(world.build)
	# Anything built or demolished changes what is walkable, so the nav grid has
	# to follow. Refreshing only the affected footprint keeps this cheap enough
	# to run on every single placement.
	world.build.grid.placement_added.connect(_on_grid_changed)
	world.build.grid.placement_removed.connect(func(index: int, _def: BuildingDef) -> void: _on_grid_changed(index))
	# A new look can bring its own preferences (overgrown grass is skirted
	# more than tall grass), so a restyle refreshes the ground under it too.
	world.build.grid.placement_restyled.connect(_on_grid_changed)


func _on_grid_changed(index: int) -> void:
	if world.nav == null:
		return
	var entry = world.build.grid.placements[index] if index < world.build.grid.placements.size() else null
	if entry == null:
		# Removed: the tiles are gone from the entry, so refresh the whole plot.
		world.nav.refresh_area(world.plot.grow(1))
		return
	var tiles: Array = entry["tiles"]
	var area := Rect2i(tiles[0], Vector2i.ONE)
	for t in tiles:
		area = area.expand(t).expand(t + Vector2i.ONE)
	world.nav.refresh_area(area)


func _setup_nav() -> void:
	if world.nav == null:
		world.nav = NavGrid.new()
	world.nav.setup(world.grid, world.build.grid)


func _setup_economy() -> void:
	if world._pawn_material == null:
		world._pawn_material = StandardMaterial3D.new()
		world._pawn_material.vertex_color_use_as_albedo = true
		world._pawn_material.roughness = 1.0
		world._pawn_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if world.items == null:
		world.items = ItemWorld.new()
		world.items.name = "Items"
		world.add_child(world.items)
	world.items.setup(world.terrain)
	# Restricted tiles -- the wash basin, so far -- follow what is built.
	world.items.bind_build(world.build.grid)
	# The builder needs to see the landscape, not just the grid: a well has to
	# reach the river.
	world.build.grid.terrain_grid = world.grid
	world.rooms.setup(world.build.grid, world.plot)
	if world.room_overlay == null:
		world.room_overlay = RoomOverlay.new()
		world.room_overlay.name = "RoomOverlay"
		world.add_child(world.room_overlay)
	world.room_overlay.follow(world.build.grid, world.rooms, world.terrain.plot_height)
	if world.get_node_or_null("StackLabels") == null:
		var labels := StackLabels.new()
		labels.setup(world)
		world.add_child(labels)

	if world.generator == null:
		world.generator = JobGenerator.new()
		world.generator.name = "JobGenerator"
		world.add_child(world.generator)
		world.sim.attach(world.generator)
	# The board holds claims on stock, so it needs to know where the stock is.
	world.board.items = world.items
	# Where the staff are reckoned to be reachable from: the middle of the yard,
	# which is where every supply arrives and where the road meets the plot.
	var yard: Rect2i = world.unloading_yard()
	world.generator.road_tile = Vector2i(yard.position.x + yard.size.x / 2, yard.position.y + 1)
	world.generator.invalidate_reach()
	# Goods put down anywhere prefer somewhere the staff can come and get them.
	world.items.standable = world.generator._standable
	# A flag, not is_connected(): an unbound copy of a callable never matches.
	if not world.generator.reach_bound:
		world.generator.reach_bound = true
		world.build.grid.placement_built.connect(world.generator.invalidate_reach.unbind(1))
		world.build.grid.placement_removed.connect(world.generator.invalidate_reach.unbind(2))
	world.generator.setup(world.board, world.items, world.build, world.nav)
	world.generator.bills = world.bills
	if world.hud._production_panel != null and world.hud._production_panel.bills == null:
		world.hud._production_panel.world = world
		world.hud._production_panel.setup(world.bills, world.items)

	if world.customers == null:
		world.customers = CustomerDirector.new()
		world.customers.name = "CustomerDirector"
		world.add_child(world.customers)
		world.customers.sim = world.sim
		world.sim.attach(world.customers)
	# Who is on the books, so guests know whether anybody will take their order.
	world.customers.staff = world.workers
	if world.clock == null:
		world.clock = DayClock.new()
		world.clock.name = "DayClock"
		world.add_child(world.clock)
		world.sim.attach(world.clock)
		world.clock.day_ended.connect(world._on_day_ended)
	world.auto_supply.setup(world)
	if world.farm == null:
		world.farm = Farm.new()
		world.farm.name = "Farm"
		world.add_child(world.farm)
		world.farm.setup(world)
		world.sim.ticked.connect(world.farm.step)
	if world.thoughts == null:
		world.thoughts = ThoughtDirector.new()
		world.thoughts.name = "Thoughts"
		world.add_child(world.thoughts)
		world.thoughts.setup(world)
	if not world.sim.ticked.is_connected(world.auto_supply.step):
		world.sim.ticked.connect(world.auto_supply.step)
	world.customers.setup(world.board, world.items, world.nav, world.terrain, world.build.grid, world.plot, world._pawn_material, world.sim_rng.randi())
	world.customers.road_row = world.high_road_row()
	world.generator.rng = world.sim_rng
	world.customers.ledger = world.ledger
	world.customers.clock = world.clock


func _spawn_pawns(rng: RandomNumberGenerator, crew: Array[StringName]) -> void:
	world.clear_keeper()
	for p in world.pawns:
		p.queue_free()
	world.pawns.clear()
	world.workers.clear()

	# Out of the tree first, so the replacement keeps the name (see SaveGame).
	var holder: Node = world._find("Pawns")
	if holder != null:
		world.remove_child(holder)
		holder.queue_free()
	holder = Node3D.new()
	holder.name = "Pawns"
	world.add_child(holder)

	for role_id in crew:
		_add_pawn(holder, rng.randi(), StaffRole.of(role_id))


func _add_pawn(holder: Node, rng_seed: int, role: StaffRole = null) -> void:
	if role == null:
		role = StaffRole.of(&"hand")
	var spawn_rng := RandomNumberGenerator.new()
	spawn_rng.seed = rng_seed
	var start: Vector2i = world.nav.random_walkable_in(world.plot, spawn_rng)
	if start == Vector2i(-1, -1):
		return
	var pawn := Pawn.new()
	holder.add_child(pawn)
	pawn.uniform = role.uniform
	pawn.staff_role_id = role.id
	pawn.setup(world.nav, world.terrain, start, world._pawn_material, rng_seed)
	pawn.wander_area = world.plot
	world.pawns.append(pawn)
	world.sim.attach(pawn)

	# The Worker is what turns a body into a labourer. A customer will be the
	# same Pawn with no Worker attached.
	var worker := Worker.new()
	worker.name = "Worker"
	pawn.add_child(worker)
	worker.setup(pawn, world.board, world.nav, world.items)
	worker.put_away = world.generator.put_away_job
	worker.set_role(role)
	world.workers.append(worker)
	world.sim.attach(worker)


func _build_terrain() -> void:
	# Deferred frees still reserve node names. Retire old render nodes now so
	# successive land purchases find and replace exactly one scenery set.
	for node_name in ["Terrain", "Water", "Scenery"]:
		_retire_visual(node_name)
	world._water_material.set_shader_parameter("ground_height", world.terrain.water_height_texture())
	world._water_material.set_shader_parameter("height_size", Vector2(world.terrain.vcols, world.terrain.vrows))
	var ground := MeshInstance3D.new()
	ground.name = "Terrain"
	ground.mesh = world.terrain.build_terrain_mesh()
	ground.material_override = world._opaque_material
	world.add_child(ground)
	world._tri_count = ground.mesh.get_faces().size() / 3 if ground.mesh != null else 0

	var water_mesh: ArrayMesh = world.terrain.build_water_mesh()
	if water_mesh != null:
		var water := MeshInstance3D.new()
		water.name = "Water"
		water.mesh = water_mesh
		water.material_override = world._water_material
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(water)
	var scenery := WorldScenery.new()
	world.add_child(scenery)
	scenery.setup(world)


func _retire_visual(node_name: String) -> void:
	var old: Node = world.get_node_or_null(NodePath(node_name))
	if old != null:
		world.remove_child(old)
		old.queue_free()


## One MultiMesh per tree variant: eighteen draw calls for the whole forest,
## however many thousand trees it contains.
func _build_forest(rng: RandomNumberGenerator) -> void:
	_retire_visual("Forest")
	if world._trees == null:
		world._trees = TreeMeshLibrary.new()
		world._trees.build()

	var forest := Node3D.new()
	forest.name = "Forest"
	world.add_child(forest)

	# Bucket cells by variant first so each MultiMesh can be sized exactly.
	var buckets: Array[PackedInt32Array] = []
	for v in range(TreeSpecies.VARIANT_COUNT):
		buckets.append(PackedInt32Array())
	for i in range(world.grid.cells.size()):
		if world.grid.cells[i] == TerrainGrid.Cell.TREE:
			buckets[int(world.grid.tree_variant[i]) % TreeSpecies.VARIANT_COUNT].append(i)

	world._tree_count = 0
	for v in range(TreeSpecies.VARIANT_COUNT):
		var cells: PackedInt32Array = buckets[v]
		if cells.is_empty() or world._trees.meshes[v] == null:
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = world._trees.meshes[v]
		mm.instance_count = cells.size()

		for n in range(cells.size()):
			var i: int = cells[n]
			var x: int = i % world.grid.cols
			var y: int = i / world.grid.cols
			# Jitter within the tile so the forest does not sit on a visible lattice.
			var jx: float = (rng.randf() - 0.5) * 0.7
			var jz: float = (rng.randf() - 0.5) * 0.7
			var wx: float = (float(x) + 0.5 + jx) * TerrainMeshBuilder.TILE
			var wz: float = (float(y) + 0.5 + jz) * TerrainMeshBuilder.TILE

			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			basis = basis.scaled(Vector3.ONE * (0.82 + world.grid.tree_growth[i] * 0.3))
			mm.set_instance_transform(n, Transform3D(basis, Vector3(wx, world.terrain.sample_height(wx, wz), wz)))

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = world._forest_material
		forest.add_child(mmi)

		world._tree_count += cells.size()
		world._tri_count += (world._trees.meshes[v].get_faces().size() / 3) * cells.size()


func _setup_camera() -> void:
	if world.rig == null:
		world.rig = CameraRig.new()
		world.rig.name = "CameraRig"
		world.add_child(world.rig)
		world.rig.mode_changed.connect(world.hud._on_camera_mode_changed)
	world.rig.terrain = world.terrain
	# Open looking at the plot: that is where the game is, and the middle of a
	# 96-tile wilderness is not.
	var centre := Vector3(
		float(world.plot.position.x) + float(world.plot.size.x) * 0.5,
		world.terrain.plot_height,
		float(world.plot.position.y) + float(world.plot.size.y) * 0.5
	)
	world.rig.focus_on(centre)
	if world.rig.camera != null:
		world.rig.camera.current = true


