class_name Farm
extends Node3D

## Farm plots, and the rain that fills the wells.
##
## A plot is a floor piece holding one crop: bare, planted, growing, ripe. A
## farmer plants a bare plot, it grows by itself over about two trading days,
## and a farmer harvests it when ripe, leaving it bare again. Wheat is ground
## to flour at the prep table; hops go straight to the vat. Slow on purpose:
## a field supplements the merchant, it does not replace him overnight.
##
## The well no longer makes water when worked. Rain fills it, slowly, and it
## keeps any water carried to it. Both run on game time from the SimClock.

## Game seconds from planting to ripe: a little over two trading days.
const GROW_SECONDS: float = 1300.0
const PLANT_WORK: float = 2.0
const HARVEST_WORK: float = 3.0
## What a ripe plot gives.
const YIELD: Dictionary = {&"wheat": 3, &"hops": 2}
const CROPS: Array[StringName] = [&"wheat", &"hops"]
## Game seconds between one barrel of rain landing in each well: about an hour.
const RAIN_EVERY: float = 36.0
## How often the jobs and the crop pictures are brought up to date.
const SCAN_EVERY: float = 1.0

var world  ## TavernWorld
var _rain: float = RAIN_EVERY
var _scan: float = 0.0
## crop/stage -> shared MultiMesh: at most six crop batches.
var _views: Dictionary = {}



func setup(p_world) -> void:
	world = p_world


func step(delta: float) -> void:
	if world == null or world.build == null:
		return
	for entry in _plots():
		if float(entry.get("growth", -1.0)) >= 0.0 and float(entry["growth"]) < 1.0:
			entry["growth"] = minf(1.0, float(entry["growth"]) + delta / GROW_SECONDS)
	# Sample the same saved clock/seed as the sky, including in headless play.
	var weather: Dictionary = AtmospherePalette.sample(world._world_seed, world.clock.day, world.clock.fraction)
	_rain -= delta * float(weather["rain"])
	while _rain <= 0.0:
		_rain += RAIN_EVERY
		_rain_on_wells()
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_EVERY
		_post_jobs()
		_show_crops()


func _plots() -> Array:
	var out: Array = []
	for entry in world.build.grid.placements:
		if entry != null and entry["built"] and entry["def"].id == &"farm_plot":
			out.append(entry)
	return out


static func crop_of(entry: Dictionary) -> StringName:
	return StringName(entry.get("crop", &"wheat"))


## -1 bare, 0..1 growing, 1 ripe.
static func growth_of(entry: Dictionary) -> float:
	return float(entry.get("growth", -1.0))


func set_crop(index: int, crop: StringName) -> void:
	if index < 0 or index >= world.build.grid.placements.size():
		return
	var entry = world.build.grid.placements[index]
	if entry == null or entry["def"].id != &"farm_plot" or not CROPS.has(crop):
		return
	if crop_of(entry) != crop:
		entry["crop"] = crop
		# A change of crop turns the bed over: whatever was growing is lost.
		entry["growth"] = -1.0
		entry.erase("harvest_remaining")
		var tile: Vector2i = entry["tiles"][0]
		world.board.cancel_key("farm:%d,%d" % [tile.x, tile.y])
		_show_crops()


# --- work -------------------------------------------------------------------------

func _post_jobs() -> void:
	var board: JobBoard = world.board
	var grid: BuildGrid = world.build.grid
	for i in range(grid.placements.size()):
		var entry = grid.placements[i]
		if entry == null or not entry["built"] or entry["def"].id != &"farm_plot":
			continue
		var tile: Vector2i = entry["tiles"][0]
		var key: String = "farm:%d,%d" % [tile.x, tile.y]
		var growth: float = growth_of(entry)
		var wants: String = "plant" if growth < 0.0 else ("harvest" if growth >= 1.0 else "")
		var existing: Job = board.job_with_key(key)
		if wants.is_empty():
			if existing != null and existing.claimant == null:
				board.cancel_key(key)
			continue
		if existing != null:
			continue
		var job := Job.new()
		job.kind = WorkType.Kind.FARM
		job.target = tile
		job.key = key
		job.subject = i
		if wants == "plant":
			job.work_amount = PLANT_WORK
			job.label = "Plant %s" % crop_of(entry)
			job.on_complete = func(_j: Job) -> void: _planted(i)
		else:
			job.work_amount = HARVEST_WORK
			job.label = "Harvest %s" % crop_of(entry)
			job.on_complete = func(_j: Job) -> void: _harvested(i)
		board.post(job)


func _planted(index: int) -> void:
	var entry = world.build.grid.placements[index] if index >= 0 and index < world.build.grid.placements.size() else null
	if entry != null and entry["built"] and entry["def"].id == &"farm_plot" and growth_of(entry) < 0.0:
		entry["growth"] = 0.0


func _harvested(index: int) -> void:
	var entry = world.build.grid.placements[index] if index >= 0 and index < world.build.grid.placements.size() else null
	if entry == null or not entry["built"] or entry["def"].id != &"farm_plot" or growth_of(entry) < 1.0:
		return
	var crop: StringName = crop_of(entry)
	var def: ItemDef = ItemCatalog.get_def(crop)
	var count: int = int(entry.get("harvest_remaining", YIELD.get(crop, 1)))
	# A full yard leaves the uncollected crop standing; a retry must not produce
	# a second full yield after a partially accepted harvest.
	var placed: int = world.items.place_near(def, count, entry["tiles"][0], 6, ItemWorld.BASE_QUALITY, false)
	world.generator.produced[crop] = int(world.generator.produced.get(crop, 0)) + placed
	entry["harvest_remaining"] = count - placed
	if placed == count:
		entry["growth"] = -1.0
		entry.erase("harvest_remaining")


func _rain_on_wells() -> void:
	var water: ItemDef = ItemCatalog.get_def(&"water")
	var sheltered: Dictionary = {}
	for room in world.rooms.current():
		if world.rooms.is_sheltered(room):
			for tile in room["tiles"]:
				sheltered[tile] = true
	for entry in world.build.grid.placements:
		if entry == null or not entry["built"] or entry["def"].id != &"well":
			continue
		for tile in entry["tiles"]:
			if sheltered.has(tile):
				continue
			if world.items.add(water, 1, tile, ItemWorld.BASE_QUALITY) > 0:
				world.generator.produced[&"water"] = int(world.generator.produced.get(&"water", 0)) + 1
				break


# --- what the crops look like ----------------------------------------------------

func _show_crops() -> void:
	var groups: Dictionary = {}
	var grid: BuildGrid = world.build.grid
	for entry in _plots():
		var growth: float = growth_of(entry)
		if growth < 0.0:
			continue
		var stage: int = 3 if growth >= 1.0 else (1 if growth < 0.4 else 2)
		var crop: StringName = crop_of(entry)
		var key: String = "%s:%d" % [crop, stage]
		if not groups.has(key):
			groups[key] = []
			if not _views.has(key):
				var view := MultiMeshInstance3D.new()
				view.name = "Crop_" + key.replace(":", "_")
				view.material_override = world._pawn_material
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = true
				mm.mesh = crop_mesh(crop, stage)
				view.multimesh = mm
				add_child(view)
				_views[key] = view
		var tile: Vector2i = entry["tiles"][0]
		groups[key].append(Vector3(float(tile.x), grid.visual_floor_height(tile), float(tile.y)))
	for key in _views:
		var view: MultiMeshInstance3D = _views[key]
		var positions: Array = groups.get(key, [])
		view.multimesh.instance_count = positions.size()
		for i in range(positions.size()):
			view.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
			view.multimesh.set_instance_color(i, Color.WHITE)
		view.visible = not positions.is_empty()


static func crop_mesh(crop: StringName, stage: int) -> Mesh:
	return FarmCropArt.mesh(crop, stage)
