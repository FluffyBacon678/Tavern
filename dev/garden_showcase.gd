extends Node

## The garden tile set, shown two ways. Run windowed:
##   godot --path . --resolution 1600x1200 res://dev/garden_showcase.tscn -- sheet <out.png>
##   godot --path . --resolution 1600x1200 res://dev/garden_showcase.tscn -- park <out.png>
##   godot --path . --resolution 1600x1200 res://dev/garden_showcase.tscn -- stand <out.png>
##
## sheet: every tile on a soil block, labelled, in the reference sheet's rows
##        (grass, flower plots, high grass), the path and the park props, and
##        the lemonade stand's pieces.
## park:  a small park beside the sandbox's tavern, laid with the real build
##        system exactly as a player would, seen from the management camera.
## stand: a fenced lemonade garden the same way: a stall on a paved square,
##        parasol tables on the lawn, lanterns, flower borders.

const SHEET_ROWS: Array = [
	["GRASS TILES", [&"lawn_trimmed", &"lawn_meadow", &"lawn_worn"]],
	["FLOWER PLOTS", [&"bed_daisy", &"bed_mixed", &"bed_border"]],
	["HIGH GRASS PLOTS", [&"grass_tall", &"grass_tall_flowers", &"grass_overgrown"]],
	["PATH & PROPS", [&"garden_path", &"garden_bench", &"garden_rocks", &"garden_tree", &"garden_pine", &"lantern_post"]],
	["LEMONADE STAND", [&"market_stall", &"parasol_table", &"garden_fence"]],
]

## The lemonade garden, 12 x 8, the tavern side along the bottom row; fenced
## round the other three sides.
const STAND: Array[String] = [
	"FFBBBBBBBBFF",
	"DTTTTTTTTTTD",
	"DTTTTPPTTTTD",
	"XTTTPPPPTTTX",
	"XTTTPPPPTTTX",
	"DTTTTPPTTTTD",
	"DTTTTPPTTTTD",
	"TTTTTPPTTTTT",
]
## [id, x, y, quarter turns]. The stall faces the camera, across the square.
const STAND_PROPS: Array = [
	[&"market_stall", 5, 3, 2],
	[&"parasol_table", 2, 2, 0], [&"chair", 1, 2, 0], [&"chair", 4, 2, 0],
	[&"parasol_table", 8, 2, 0], [&"chair", 7, 2, 0], [&"chair", 10, 2, 0],
	[&"parasol_table", 2, 5, 0], [&"chair", 1, 5, 0], [&"chair", 4, 5, 0],
	[&"parasol_table", 8, 5, 0], [&"chair", 7, 5, 0], [&"chair", 10, 5, 0],
	[&"lantern_post", 4, 6, 0], [&"lantern_post", 7, 6, 0],
	[&"garden_tree", 0, 7, 0], [&"garden_pine", 11, 7, 0],
]

## The park, 12 x 8, the tavern side along the bottom row.
## T trimmed, M meadow, W worn, P path, D daisies, X mixed, B border,
## G tall grass, F tall grass with flowers, O overgrown.
const PARK: Array[String] = [
	"FFGGMMMMGGOO",
	"FMMTTTTTTMGO",
	"BTTTPPPPPPPW",
	"BTTWPPWTTTTT",
	"BTTTPPTTXXTT",
	"DDTTPPTTXXTG",
	"DDTWPPWTTTTG",
	"TTTTPPTTBBBB",
]
const KEYS: Dictionary = {
	"T": &"lawn_trimmed", "M": &"lawn_meadow", "W": &"lawn_worn", "P": &"garden_path",
	"D": &"bed_daisy", "X": &"bed_mixed", "B": &"bed_border",
	"G": &"grass_tall", "F": &"grass_tall_flowers", "O": &"grass_overgrown",
}
## [id, x, y, quarter turns]
const PROPS: Array = [
	[&"garden_bench", 6, 1, 0],
	[&"garden_bench", 2, 4, 3],
	[&"lantern_post", 3, 2, 0],
	[&"lantern_post", 7, 6, 0],
	[&"garden_rocks", 9, 6, 0],
	[&"garden_tree", 1, 1, 0],
	[&"garden_pine", 11, 5, 0],
	[&"garden_pine", 10, 3, 0],
]

var out_path: String = ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "sheet"
	out_path = args[1] if args.size() > 1 else "user://garden_%s.png" % mode
	if mode == "park":
		await _park()
	elif mode == "stand":
		await _stand()
	else:
		await _sheet()
	get_tree().quit()


# --- the tile sheet -------------------------------------------------------------

func _sheet() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("d9d3c8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c8c4bb")
	env.environment.ambient_light_energy = 0.42
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.82
	sun.shadow_enabled = true
	add_child(sun)

	var library := BuildingMeshLibrary.new()
	var material: Material = TavernMaterials.shared()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.0
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	add_child(cam)
	# Laid out in screen directions, so each row reads straight across the
	# picture while every tile is still seen at the management angle.
	var right: Vector3 = Vector3(cam.transform.basis.x.x, 0, cam.transform.basis.x.z).normalized()
	var down: Vector3 = Vector3(cam.transform.basis.z.x, 0, cam.transform.basis.z.z).normalized()
	var foreshorten: float = sin(deg_to_rad(35.264))
	var labels: Array = []  # [world point, text, is heading]
	for r in range(SHEET_ROWS.size()):
		var ids: Array = SHEET_ROWS[r][1]
		var gap: float = (3.0 if r == SHEET_ROWS.size() - 1 else 2.6) if ids.size() <= 3 else 1.95
		var first: float = -gap * float(ids.size() - 1) * 0.5
		# The stand's pieces stand tall: their row is given more room above it.
		var row_at: Vector3 = down * (_row_offset(r) * 2.45 / foreshorten)
		labels.append([row_at + right * (first - 2.4), SHEET_ROWS[r][0], true])
		for c in range(ids.size()):
			var def: BuildingDef = BuildingCatalog.get_def(ids[c])
			var centre: Vector3 = row_at + right * (first + gap * float(c))
			var origin: Vector3 = centre - Vector3(float(def.size.x), 0, float(def.size.y)) * 0.5
			var block := MeshInstance3D.new()
			block.mesh = _soil_block(def.size)
			block.material_override = material
			block.position = origin
			add_child(block)
			var piece := MeshInstance3D.new()
			piece.mesh = library.mesh_for(def)
			piece.material_override = material
			piece.position = origin
			add_child(piece)
			labels.append([centre + down * 0.9 + Vector3(0, -0.5, 0), "%d. %s" % [c + 1, def.display_name], false])
	cam.size = 10.0 + 4.8 * float(SHEET_ROWS.size() - 4)
	var middle: float = _row_offset(SHEET_ROWS.size() - 1) * 0.5 + 0.2
	cam.position = down * (middle * 2.45 / foreshorten) + cam.transform.basis.z * 30.0 + right * 0.6
	cam.make_current()
	await get_tree().process_frame

	var layer := CanvasLayer.new()
	add_child(layer)
	for entry in labels:
		var l := Label.new()
		l.text = entry[1]
		var heading: bool = entry[2]
		l.add_theme_font_size_override("font_size", 17 if heading else 12)
		l.add_theme_color_override("font_color", Color("4a4540"))
		var p: Vector2 = cam.unproject_position(entry[0])
		l.position = p - Vector2(60 if heading else 0, 10)
		if not heading:
			l.custom_minimum_size.x = 160
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.position = p - Vector2(80, 0)
		layer.add_child(l)
	for i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)


## Where a sheet row sits, in rows: the last (the stand's tall pieces) a
## little further down.
func _row_offset(r: int) -> float:
	return float(r) + (0.75 if r == SHEET_ROWS.size() - 1 else 0.0)


## The display block a tile sits on in the sheet: soil, with stones in its face.
func _soil_block(size: Vector2i) -> Mesh:
	var mb := MeshBuilder.new()
	mb.surface_style = TavernMaterials.Surface.PLAIN
	var w: float = float(size.x)
	var d: float = float(size.y)
	mb.add_box(Vector3(0, -0.45, 0), Vector3(w, 0.45, d), GardenArt.SOIL)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(int(3 * w)):
		mb.add_blob(Vector3(rng.randf_range(0.1, w - 0.1), rng.randf_range(-0.38, -0.1), d + 0.005),
			Vector3(0.07, 0.045, 0.03), 2, 5, Color("8c8a84"))
	for i in range(3):
		mb.add_blob(Vector3(w + 0.005, rng.randf_range(-0.38, -0.1), rng.randf_range(0.1, d - 0.1)),
			Vector3(0.03, 0.045, 0.07), 2, 5, Color("8c8a84"))
	return mb.commit()


# --- the park ---------------------------------------------------------------------

func _park() -> void:
	if not GameState.begin_test_session():
		return
	GameState.full_house_start = true
	GameState.start_new_run("Garden Show", 493774, GameState.MAX_SLOTS - 1, true)
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	GameSettings.thought_bubbles = false

	var at: Vector2i = _park_site(world)
	if at.x < 0:
		print("GARDEN: no room for the park")
		return
	var laid: int = 0
	for y in range(PARK.size()):
		for x in range(PARK[y].length()):
			var def: BuildingDef = BuildingCatalog.get_def(KEYS[PARK[y][x]])
			if world.build.place_programmatic(def, at + Vector2i(x, y), 0, false) >= 0:
				laid += 1
	for p in PROPS:
		if world.build.place_programmatic(BuildingCatalog.get_def(p[0]), at + Vector2i(p[1], p[2]), p[3], false) >= 0:
			laid += 1
	# A back door where the path meets the hall, so the garden leads inside.
	var hall: Rect2i = TestHouse.hall(world)
	for x in [at.x + 4, at.x + 5]:
		var wall := Vector2i(x, hall.position.y - 1)
		if at.y + PARK.size() == wall.y and world.build.grid.placement_at(wall) >= 0:
			world.demolish_at(wall, true)
			world.build.place_programmatic(BuildingCatalog.get_def(&"door"), wall, 0, false)
			break
	for def in BuildingCatalog.all():
		world.build._rebuild_instances(def)
	world.nav.refresh_all()
	print("GARDEN: park at %s, %d pieces laid" % [at, laid])

	world.hud._hud.visible = false
	var rig: CameraRig = world.rig
	# From the river side, so the park fills the view and the tavern is only
	# its back wall and door at the far edge.
	rig._distance = 12.0
	rig._distance_target = 12.0
	rig._pitch = 44.0
	rig._pitch_target = 44.0
	rig._yaw = 205.0
	rig._yaw_target = 205.0
	rig.focus_on(Vector3(at.x + 6.0, world.terrain.plot_height, at.y + 2.6))
	world.sim.speed = 1
	for i in range(240):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)


## The lemonade garden, laid like the park, with a fence dragged round it.
func _stand() -> void:
	if not GameState.begin_test_session():
		return
	GameState.full_house_start = true
	GameState.start_new_run("Garden Show", 493774, GameState.MAX_SLOTS - 1, true)
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	GameSettings.thought_bubbles = false

	var ring: Vector2i = _park_site(world, Vector2i(14, 9))
	if ring.x < 0:
		print("GARDEN: no room for the stand")
		return
	var at: Vector2i = ring + Vector2i(1, 1)
	var laid: int = 0
	for y in range(STAND.size()):
		for x in range(STAND[y].length()):
			var def: BuildingDef = BuildingCatalog.get_def(KEYS[STAND[y][x]])
			if world.build.place_programmatic(def, at + Vector2i(x, y), 0, false) >= 0:
				laid += 1
	for p in STAND_PROPS:
		if world.build.place_programmatic(BuildingCatalog.get_def(p[0]), at + Vector2i(p[1], p[2]), p[3], false) >= 0:
			laid += 1
	var fence: BuildingDef = BuildingCatalog.get_def(&"garden_fence")
	for x in range(14):
		laid += int(world.build.place_programmatic(fence, ring + Vector2i(x, 0), 0, false) >= 0)
	for y in range(1, 9):
		laid += int(world.build.place_programmatic(fence, ring + Vector2i(0, y), 0, false) >= 0)
		laid += int(world.build.place_programmatic(fence, ring + Vector2i(13, y), 0, false) >= 0)
	var hall: Rect2i = TestHouse.hall(world)
	for x in [at.x + 5, at.x + 6]:
		var wall := Vector2i(x, hall.position.y - 1)
		if at.y + STAND.size() == wall.y and world.build.grid.placement_at(wall) >= 0:
			world.demolish_at(wall, true)
			world.build.place_programmatic(BuildingCatalog.get_def(&"door"), wall, 0, false)
			break
	for def in BuildingCatalog.all():
		world.build._rebuild_instances(def)
	world.nav.refresh_all()
	world.customers.seating.refresh()
	# Jugs on the stall, lemons in a crate beside it, a jug on two tables.
	var stall_index: int = world.build.grid.object_index_at(at + Vector2i(5, 3))
	if stall_index >= 0:
		var tiles: Array = world.build.grid.placements[stall_index]["tiles"]
		world.items.add(ItemCatalog.get_def(&"lemonade"), 8, tiles[0])
		world.items.add(ItemCatalog.get_def(&"lemons"), 6, at + Vector2i(4, 4))
	world.items.add(ItemCatalog.get_def(&"lemonade"), 1, at + Vector2i(2, 2))
	world.items.add(ItemCatalog.get_def(&"lemonade"), 2, at + Vector2i(9, 5))
	print("GARDEN: stand at %s, %d pieces laid" % [at, laid])

	world.hud._hud.visible = false
	var rig: CameraRig = world.rig
	rig._distance = 13.0
	rig._distance_target = 13.0
	rig._pitch = 42.0
	rig._pitch_target = 42.0
	rig._yaw = 205.0
	rig._yaw_target = 205.0
	rig.focus_on(Vector3(at.x + 6.0, world.terrain.plot_height, at.y + 3.4))
	world.sim.speed = 1
	for i in range(240):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)


## A clear stretch beside the hall, the nearer the better.
func _park_site(world, size: Vector2i = Vector2i(12, 8)) -> Vector2i:
	var hall: Rect2i = TestHouse.hall(world)
	var best := Vector2i(-1, -1)
	var best_gap: int = 1 << 30
	for y in range(world.plot.position.y, world.plot.end.y - size.y + 1):
		for x in range(world.plot.position.x, world.plot.end.x - size.x + 1):
			var rect := Rect2i(Vector2i(x, y), size)
			if rect.intersects(hall.grow(1)):
				continue
			var clear: bool = true
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					var t := Vector2i(tx, ty)
					if world.build.grid.placement_at(t) >= 0 or not world.nav.is_walkable(t) or not world.build.grid.in_plot(t):
						clear = false
						break
				if not clear:
					break
			if not clear:
				continue
			var gap: int = maxi(maxi(hall.position.x - rect.end.x, rect.position.x - hall.end.x),
				maxi(hall.position.y - rect.end.y, rect.position.y - hall.end.y))
			if gap < best_gap:
				best_gap = gap
				best = rect.position
	return best
