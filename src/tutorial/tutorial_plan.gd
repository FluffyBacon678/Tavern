class_name TutorialPlan
extends RefCounted

## The tutorial: every feature, in the order a new tavern needs it, as a list
## of TutorialSteps. Plain instructions, no story. See docs/tutorial_design.md.
##
## The same list is the game's end-to-end smoke test (dev/tutorial_smoke.tscn):
## each step's `perform` is what the player would do, and `done` is checked
## against the world either way. So a feature that breaks fails the lesson that
## teaches it, and a new feature is not finished until it has a lesson here.
##
## The layout is fixed so the lessons can point at the ground: a 12 x 7 room by
## the road, dining on the west, kitchen on the east, a counter between, and a
## lane down the middle to the door. Coordinates are relative to the room's
## floor, whose north-west corner is room().position.

const LESSONS: Array[String] = [
	"Looking around", "Building a room", "Kitchen and storage",
	"Supplies and production", "Staff", "Service", "Money and reputation", "Fishing", "Growing", "Farming and water",
	"The bar",
	"Your keeper",
]

const TABLES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 2), Vector2i(1, 4)]
const SHELVES: Array[Vector2i] = [Vector2i(5, 2), Vector2i(5, 4)]
const BARRELS: Array[Vector2i] = [Vector2i(11, 0), Vector2i(11, 2), Vector2i(11, 4)]
const PREP := Vector2i(8, 0)
const OVEN := Vector2i(8, 2)
const VAT := Vector2i(8, 4)
const BASIN := Vector2i(5, 0)
const COUNTER := Vector2i(5, 6)
const SPARE_CHAIR := Vector2i(0, 6)
const DOOR := Vector2i(4, 7)
const HOST_STAND := Vector2i(3, 6)
## Outside the front door: a short path south, and a flower bed beside it.
const GARDEN_PATH := Vector2i(4, 8)
const GARDEN_BED := Vector2i(2, 8)


# --- layout ---------------------------------------------------------------------

## The floor: 12 x 7, its south wall three rows above the unloading yard.
static func room(world) -> Rect2i:
	return Rect2i(world.plot.position + Vector2i(8, world.plot.size.y - 13), Vector2i(12, 7))


## The walls go round the floor.
static func ring(world) -> Rect2i:
	var r: Rect2i = room(world)
	return Rect2i(r.position - Vector2i.ONE, r.size + Vector2i(2, 2))


static func at(world, spot: Vector2i) -> Vector2i:
	return room(world).position + spot


static func chairs() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t in TABLES:
		out.append(t + Vector2i(-1, 0))
		out.append(t + Vector2i(2, 0))
	return out


static func tiles(world, spots: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for spot in spots:
		out.append(at(world, spot))
	return out


static func area(world, spot: Vector2i, size: Vector2i) -> Rect2i:
	return Rect2i(at(world, spot), size)


## Somewhere a well is allowed: near the river, inside the plot.
static func well_spot(world) -> Vector2i:
	var def: BuildingDef = BuildingCatalog.get_def(&"well")
	for y in range(world.plot.position.y, world.plot.position.y + 6):
		for x in range(world.plot.position.x + 2, world.plot.end.x - 2):
			var tile := Vector2i(x, y)
			if world.build.grid.placement_problem(def, tile, 0) == "":
				return tile
	return Vector2i(-1, -1)


## Somewhere to fish from: at the water's edge inside the plot, as near the
## kitchen as the bank allows, since every fish is carried there.
static func fishing_spot(world) -> Vector2i:
	var def: BuildingDef = BuildingCatalog.get_def(&"fishing_spot")
	var kitchen: Vector2i = at(world, PREP)
	var best := Vector2i(-1, -1)
	var best_distance: int = 1 << 30
	for y in range(world.plot.position.y, world.plot.end.y):
		for x in range(world.plot.position.x, world.plot.end.x - 1):
			var tile := Vector2i(x, y)
			var distance: int = absi(tile.x - kitchen.x) + absi(tile.y - kitchen.y)
			# On the bank itself beats a step back from it, however much nearer.
			if not _touches_water(world, tile, def.size):
				distance += 1000
			if distance >= best_distance or world.build.grid.placement_problem(def, tile, 0) != "":
				continue
			best = tile
			best_distance = distance
	return best


static func _touches_water(world, tile: Vector2i, size: Vector2i) -> bool:
	var grid: TerrainGrid = world.build.grid.terrain_grid
	if grid == null:
		return true
	for y in range(tile.y - 1, tile.y + size.y + 1):
		for x in range(tile.x - 1, tile.x + size.x + 1):
			if x >= 0 and y >= 0 and x < grid.cols and y < grid.rows \
					and grid.cells[y * grid.cols + x] == TerrainGrid.Cell.WATER:
				return true
	return false


# --- reading the world ------------------------------------------------------------

## How many of `ids` the kitchen (or the river) has turned out so far.
static func made(world, ids: Array) -> int:
	var n: int = 0
	for id in ids:
		n += int(world.generator.produced.get(id, 0))
	return n


## Placements of any of `ids` with a tile inside `rect` (built or blueprint).
static func placed_in(world, ids: Array, rect: Rect2i) -> int:
	var n: int = 0
	for entry in world.build.grid.placements:
		if entry == null or not ids.has(entry["def"].id):
			continue
		for tile in entry["tiles"]:
			if rect.has_point(tile):
				n += 1
				break
	return n


static func blueprints(world) -> int:
	var n: int = 0
	for entry in world.build.grid.placements:
		if entry != null and not entry["built"]:
			n += 1
	return n


static func placed_at(world, tile: Vector2i, id: StringName) -> bool:
	var index: int = world.build.grid.placement_at(tile)
	return index >= 0 and world.build.grid.placements[index]["def"].id == id


static func ring_closed(world) -> bool:
	var r: Rect2i = ring(world)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x != r.position.x and x != r.end.x - 1 and y != r.position.y and y != r.end.y - 1:
				continue
			var index: int = world.build.grid.placement_at(Vector2i(x, y))
			if index < 0:
				return false
			var shape: int = world.build.grid.placements[index]["def"].shape
			if shape != BuildingDef.Shape.WALL and shape != BuildingDef.Shape.DOOR:
				return false
	return true


static func any_guest(world, test: Callable) -> bool:
	for brain in world.customers.customers:
		if is_instance_valid(brain) and test.call(brain):
			return true
	return false


# --- the lessons --------------------------------------------------------------------

static func steps() -> Array[TutorialStep]:
	var out: Array[TutorialStep] = []
	out.append_array(_looking_around())
	out.append_array(_building_a_room())
	out.append_array(_kitchen_and_storage())
	out.append_array(_supplies_and_production())
	out.append_array(_staff())
	out.append_array(_service())
	out.append_array(_money())
	out.append_array(_fishing())
	out.append_array(_growing())
	out.append_array(TutorialFarming.steps())
	out.append_array(TutorialBar.steps())
	out.append_array(TutorialKeeper.steps())
	# A furnished test start must not silently tick off construction practice.
	var practice: Dictionary = {
		"floor": [[&"wood_floor", &"stone_floor"]], "walls": [[&"timber_wall", &"stone_wall"]],
		"door": [[&"door"]], "tables": [[&"table"], [&"chair"]],
		"kitchen": [[&"prep_table"], [&"oven"], [&"brewing_vat"]],
		"storage": [[&"storage_shelf"], [&"barrel"]], "basin": [[&"sink"]],
		"counter": [[&"serving_counter"]], "host_stand": [[&"host_stand"]],
		"fishing_spot": [[&"fishing_spot"]], "well": [[&"well"]],
		"farm_beds": [[&"farm_plot"]], "river_pump": [[&"river_pump"]],
		"garden": [[&"garden_path"], [&"bed_daisy", &"bed_mixed", &"bed_border", &"bed_tulips", &"bed_lavender", &"bed_roses", &"bed_sunflowers"]],
		"stand": [[&"bar_table"], [&"parasol_table"]],
	}
	for step in out:
		if practice.has(step.id):
			_require_construction_practice(step, practice[step.id])
	return out


## Preserve the normal lesson for an empty start. When its layout already
## satisfies the lesson, require one newly placed piece of each requested kind.
## Capture callables, not the RefCounted step itself (which would form a cycle).
static func _require_construction_practice(step: TutorialStep, groups: Array) -> void:
	var original_begin: Callable = step.begin
	var original_done: Callable = step.done
	var key: String = "practice_" + step.id
	step.begin = func(w, ctx: Dictionary) -> void:
		if original_begin.is_valid():
			original_begin.call(w, ctx)
		ctx[key] = w.build.grid.placements.size() if original_done.call(w, ctx) else -1
		ctx["construction_practice"] = groups if int(ctx[key]) >= 0 else []
	step.done = func(w, ctx: Dictionary) -> bool:
		if not original_done.call(w, ctx):
			return false
		var start: int = int(ctx.get(key, -1))
		if start < 0:
			return true
		for alternatives in groups:
			var found: bool = false
			for i in range(start, w.build.grid.placements.size()):
				var entry = w.build.grid.placements[i]
				if entry != null and alternatives.has(entry["def"].id):
					found = true
					break
			if not found:
				return false
		return true


static func _looking_around() -> Array[TutorialStep]:
	var L: String = LESSONS[0]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("cam_move", L,
		"Move the view with %s." % (KeyBindings.move_keys(0) + (" or " + KeyBindings.move_keys(1) if not KeyBindings.move_keys(1).is_empty() else "")),
		"Time is paused. Nothing happens in the tavern until you run it.",
		func(w, ctx) -> bool: return w.rig._focus_target.distance_to(ctx["focus"]) >= 4.0,
		func(w, _ctx) -> void: w.rig.focus_on(w.rig._focus_target + Vector3(6, 0, 0))
	).starting(func(w, ctx) -> void: ctx["focus"] = w.rig._focus_target))
	out.append(TutorialStep.make("cam_zoom", L,
		"Zoom in and out with the mouse wheel.",
		"Close up for detail, far out to see the whole plot.",
		func(w, ctx) -> bool: return absf(w.rig._distance_target - ctx["distance"]) >= 2.0,
		func(w, _ctx) -> void: w.rig.zoom_by(3.0)
	).starting(func(w, ctx) -> void: ctx["distance"] = w.rig._distance_target))
	out.append(TutorialStep.make("cam_turn", L,
		"Turn the view with %s and %s, or the arrow buttons at the top." % [KeyBindings.first("cam_turn_left"), KeyBindings.first("cam_turn_right")],
		"Walls between you and the room fade so you can see inside.",
		func(w, ctx) -> bool: return absf(w.rig._yaw_target - ctx["yaw"]) >= 10.0,
		func(w, _ctx) -> void: w.rig.rotate_step(1)
	).starting(func(w, ctx) -> void: ctx["yaw"] = w.rig._yaw_target).pointing_at({"button": "↷"}))
	out.append(TutorialStep.make("time_speed", L,
		"Run time with %s, speed it up with %s, %s or %s (5x), then pause again with %s." % [KeyBindings.first("speed_1"), KeyBindings.first("speed_2"), KeyBindings.first("speed_3"), KeyBindings.first("speed_4"), KeyBindings.first("pause")],
		"The clock and speed buttons are at the top left. Pause whenever you want to plan.",
		func(w, ctx) -> bool: return ctx.get("ran", false) and w.sim.speed == 0,
		func(w, _ctx) -> void:
			w.sim.speed = 1
			w.sim.speed = 0
	).starting(_watch_speed).pointing_at({"button": "▶"}))
	out.append(TutorialStep.make("inspect", L,
		"Click your porter to see who they are and what they are doing.",
		"Anyone and anything can be clicked; pointing at it shows a short card.",
		func(w, _ctx) -> bool:
			var subject: Dictionary = w.hud.inspector.subject()
			return int(subject.get("kind", -1)) == WorldStats.Kind.PAWN and is_instance_valid(subject.get("pawn")) \
				and subject["pawn"].get_node_or_null("Worker") != null,
		func(w, _ctx) -> void: w.hud.inspector.show_pawn(PlayerActions.staff(w, &"porter").pawn)
	).pointing_at({"role": &"porter"}))
	return out


## Remember whether time has been run since the step began: the step is done
## when it has, and is paused again.
static func _watch_speed(w, ctx: Dictionary) -> void:
	ctx["ran"] = false
	if ctx.has("watching_speed"):
		return
	ctx["watching_speed"] = true
	w.sim.speed_changed.connect(func(speed: int) -> void: _note_speed(ctx, speed))


static func _note_speed(ctx: Dictionary, speed: int) -> void:
	if speed > 0:
		ctx["ran"] = true


static func _building_a_room() -> Array[TutorialStep]:
	var L: String = LESSONS[1]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("build_open", L,
		"Press %s, or the Build button, to open the build bar." % KeyBindings.first("build"),
		"Everything you build is paid for when you place it.",
		func(w, _ctx) -> bool: return w.hud._build_bar.visible,
		func(w, _ctx) -> void:
			if not w.hud._build_bar.visible:
				w.hud._toggle_build_bar()
	).pointing_at({"button": "Build"}))
	out.append(TutorialStep.make("floor", L,
		"Pick Wood Floor and drag across the outlined ground to lay the floor.",
		"The build bar shows what a drag costs, and what it leaves in the purse.",
		func(w, _ctx) -> bool: return placed_in(w, [&"wood_floor", &"stone_floor"], room(w)) >= 84,
		func(w, _ctx) -> void:
			PlayerActions.select(w, &"wood_floor")
			PlayerActions.drag(w, room(w).position, room(w).end - Vector2i.ONE)
	).pointing_at(func(w) -> Dictionary: return {"tiles": room(w)}))
	out.append(TutorialStep.make("walls", L,
		"Pick Timber Wall and drag from one corner of the outline to the opposite corner.",
		"A drag walls in the whole rectangle; a drag one tile wide makes a straight run.",
		func(w, _ctx) -> bool: return ring_closed(w),
		func(w, _ctx) -> void:
			PlayerActions.select(w, &"timber_wall")
			PlayerActions.drag(w, ring(w).position, ring(w).end - Vector2i.ONE)
	).pointing_at(func(w) -> Dictionary: return {"tiles": ring(w)}))
	out.append(TutorialStep.make("door", L,
		"Pick Door and click the marked wall to put a door in it.",
		"Guests and staff come and go through doors; a room needs one.",
		func(w, _ctx) -> bool: return placed_at(w, at(w, DOOR), &"door"),
		func(w, _ctx) -> void: PlayerActions.place_all(w, &"door", [at(w, DOOR)])
	).pointing_at(func(w) -> Dictionary: return {"tiles": Rect2i(at(w, DOOR), Vector2i.ONE)}))
	out.append(TutorialStep.make("wait_build", L,
		"Run time (1, or 4 for 5x) and watch your porter build it.",
		"Placing makes blueprints; porters build them one at a time. A second porter halves the wait.",
		func(w, _ctx) -> bool: return blueprints(w) == 0,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(420.0).pointing_at({"role": &"porter"}))
	out.append(TutorialStep.make("tables", L,
		"Place three Tables in the dining corner, and a Chair at each end of every table.",
		"A chair is only a seat when it is right beside a table. R turns a piece before you place it.",
		func(w, _ctx) -> bool:
			return placed_in(w, [&"table"], room(w)) >= 3 and placed_in(w, [&"chair"], room(w)) >= 6,
		func(w, _ctx) -> void:
			PlayerActions.place_all(w, &"table", tiles(w, TABLES))
			PlayerActions.place_all(w, &"chair", tiles(w, chairs()))
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, Vector2i(0, 0), Vector2i(4, 5))}))
	out.append(TutorialStep.make("take_back", L,
		"Place a chair on the marked tile, then press %s to take it back." % KeyBindings.first("build_undo"),
		"%s in the build bar undoes your last placement, a whole drag at once, and refunds it." % KeyBindings.first("build_undo"),
		func(w, ctx) -> bool:
			return int(w.ledger.today.get(Ledger.Line.REFUNDS, 0)) > int(ctx["refunds"]) 				and not placed_at(w, at(w, SPARE_CHAIR), &"chair"),
		func(w, _ctx) -> void:
			PlayerActions.place_all(w, &"chair", [at(w, SPARE_CHAIR)])
			PlayerActions.undo(w)
	).starting(func(w, ctx) -> void: ctx["refunds"] = int(w.ledger.today.get(Ledger.Line.REFUNDS, 0))
	).pointing_at(func(w) -> Dictionary: return {"tiles": Rect2i(at(w, SPARE_CHAIR), Vector2i.ONE)}))
	out.append(TutorialStep.make("demolish", L,
		"Place one more chair on the marked tile, then press Demolish and click it.",
		"Unbuilt blueprints refund in full; finished pieces give half back. Loose goods sell for half.",
		func(w, ctx) -> bool: return int(w.ledger.today.get(Ledger.Line.REFUNDS, 0)) > int(ctx["refunds"]),
		func(w, _ctx) -> void:
			PlayerActions.place_all(w, &"chair", [at(w, SPARE_CHAIR)])
			PlayerActions.demolish(w, at(w, SPARE_CHAIR))
			PlayerActions.stop_building(w)
	).starting(func(w, ctx) -> void: ctx["refunds"] = int(w.ledger.today.get(Ledger.Line.REFUNDS, 0))
	).pointing_at(func(w) -> Dictionary: return {"tiles": Rect2i(at(w, SPARE_CHAIR), Vector2i.ONE)}))
	out.append(TutorialStep.make("rooms", L,
		"Press %s, or Rooms, to see what the game counts as a room." % KeyBindings.first("rooms"),
		"Walls all the way round and a door make a room. Rooms are what the kitchen and hall bonuses read.",
		func(w, _ctx) -> bool:
			return w.room_overlay != null and w.room_overlay.visible and not w.rooms.current().is_empty(),
		func(w, _ctx) -> void:
			if w.room_overlay != null and not w.room_overlay.visible:
				w.toggle_room_overlay()
	).pointing_at({"button": "Rooms"}))
	return out


static func _kitchen_and_storage() -> Array[TutorialStep]:
	var L: String = LESSONS[2]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("kitchen", L,
		"In the kitchen corner, place a Prep Table, an Oven and a Brewing Vat on the marked spots.",
		"Bread is two steps: dough at the prep table, then the oven. Beer comes from the vat.",
		func(w, _ctx) -> bool:
			return placed_in(w, [&"prep_table"], room(w)) >= 1 and placed_in(w, [&"oven"], room(w)) >= 1 \
				and placed_in(w, [&"brewing_vat"], room(w)) >= 1,
		func(w, _ctx) -> void:
			if w.room_overlay != null and w.room_overlay.visible:
				w.toggle_room_overlay()
			PlayerActions.place_all(w, &"prep_table", [at(w, PREP)])
			PlayerActions.place_all(w, &"oven", [at(w, OVEN)])
			PlayerActions.place_all(w, &"brewing_vat", [at(w, VAT)])
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, Vector2i(8, 0), Vector2i(2, 6))}))
	out.append(TutorialStep.make("storage", L,
		"Place two Storage Shelves and three Barrels on the marked spots.",
		"Each storage tile holds one kind of goods. Too little, and deliveries pile up round the benches.",
		func(w, _ctx) -> bool:
			return placed_in(w, [&"storage_shelf"], room(w)) >= 2 and placed_in(w, [&"barrel"], room(w)) >= 3,
		func(w, _ctx) -> void:
			PlayerActions.place_all(w, &"storage_shelf", tiles(w, SHELVES))
			PlayerActions.place_all(w, &"barrel", tiles(w, BARRELS))
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, Vector2i(5, 2), Vector2i(2, 3))}))
	out.append(TutorialStep.make("basin", L,
		"Place a Wash Basin on the marked spot.",
		"Guests leave plates on the table, and nobody sits at a dirty one until they are washed.",
		func(w, _ctx) -> bool: return placed_in(w, [&"sink"], room(w)) >= 1,
		func(w, _ctx) -> void: PlayerActions.place_all(w, &"sink", [at(w, BASIN)])
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, BASIN, Vector2i(2, 1))}))
	out.append(TutorialStep.make("counter", L,
		"Place a Serving Counter on the marked spot, between the kitchen and the tables.",
		"The kitchen puts each order on the counter, and waiters carry it from there.",
		func(w, _ctx) -> bool: return placed_in(w, [&"serving_counter"], room(w)) >= 1,
		func(w, _ctx) -> void:
			PlayerActions.place_all(w, &"serving_counter", [at(w, COUNTER)])
			PlayerActions.stop_building(w)
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, COUNTER, Vector2i(2, 1))}))
	out.append(TutorialStep.make("wait_build2", L,
		"Run time until everything is built.",
		"Blueprints show as pale ghosts until a porter finishes them.",
		func(w, _ctx) -> bool: return blueprints(w) == 0,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(420.0).pointing_at({"role": &"porter"}))
	out.append(TutorialStep.make("filter", L,
		"Click a shelf, then untick all but flour and yeast.",
		"Filters decide what a storage tile holds, so the right goods sit by the right bench.",
		func(w, _ctx) -> bool:
			# Exactly what it asks for. Any filter at all once passed, so a
			# flour-only shelf -- which then refuses the yeast -- was taught as right.
			for entry in w.build.grid.placements:
				var filter: Dictionary = entry.get("filter", {}) if entry != null else {}
				if entry != null and entry["def"].is_storage and filter.size() == 2 \
						and filter.has(&"flour") and filter.has(&"yeast"):
					return true
			return false,
		func(w, _ctx) -> void:
			var index: int = w.build.grid.placement_at(at(w, SHELVES[0]))
			w.hud.inspector.show_subject({"kind": WorldStats.Kind.BUILDING, "index": index})
			w.build.grid.toggle_filter(index, &"flour")
			w.build.grid.toggle_filter(index, &"yeast")
			w.hud.inspector.clear()
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, SHELVES[0], Vector2i(2, 1))}))
	return out


static func _supplies_and_production() -> Array[TutorialStep]:
	var L: String = LESSONS[3]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("order_open", L,
		"Open Stores to manage meals and their ingredients.",
		"Flour, yeast and water make bread; malt, hops and water make beer.",
		func(w, _ctx) -> bool: return w.hud._supply_panel.visible,
		func(w, _ctx) -> void: PlayerActions.press(w.hud._hud, "Stores")
	).pointing_at({"button": "Stores"}))
	out.append(TutorialStep.make("order", L,
		"Open the Merchant tab, click the flour sack to put more on the cart, then press Buy cart.",
		"The yard below the wares shows where the cart unloads. Nothing is paid until you buy.",
		func(w, _ctx) -> bool: return not w.delivered.is_empty(),
		func(w, _ctx) -> void:
			var panel: SupplyPanel = w.hud._supply_panel
			panel.show_manual()
			panel.order[&"flour"] = int(panel.order.get(&"flour", 0)) + 2
			panel.refresh()
			PlayerActions.press(panel, "Buy cart")
	).pointing_at({"button": "Merchant"}))
	out.append(TutorialStep.make("haul", L,
		"Run time while your porter carries the delivery in.",
		"Porters move goods from the yard to storage; cooks fetch what their bench needs.",
		func(w, _ctx) -> bool:
			for tile in w.delivery_tiles():
				if w.items.has_stack(tile):
					return false
			return true,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(360.0).pointing_at({"role": &"porter"}))
	out.append(TutorialStep.make("production", L,
		"Open Stores and set Bread to keep 6.",
		"One meal target controls cooking and the ingredients to buy. Existing stock and home-grown goods count first.",
		func(w, _ctx) -> bool:
			return w.hud._supply_panel.visible and int(w.bills.get_bill(&"bake_bread").get("target", 0)) == 6,
		func(w, _ctx) -> void:
			if not w.hud._supply_panel.visible:
				w.hud._supply_panel.toggle()
			w.hud._supply_panel._adjust_meal(&"bake_bread", 6 - int(w.bills.get_bill(&"bake_bread")["target"]))
	).pointing_at({"button": "Stores"}))
	out.append(TutorialStep.make("auto_order", L,
		"Keep Auto restock enabled in Stores.",
		"Meal targets buy their missing ingredients in shared carts, keeping tonight's wages aside. Fish still needs a local catch.",
		func(w, _ctx) -> bool: return w.auto_supply.enabled,
		func(w, _ctx) -> void:
			w.hud._supply_panel._auto_toggle.button_pressed = true
			w.hud._supply_panel.hide()
	).pointing_at({"button": "Stores"}))
	out.append(TutorialStep.make("first_bread", L,
		"Run time until the first bread comes out of the oven.",
		"Cooks make dough at the prep table, then bake it. Beer brews at the vat meanwhile.",
		func(w, _ctx) -> bool: return int(w.generator.produced.get(&"bread", 0)) >= 1,
		func(w, _ctx) -> void:
			if w.hud._production_panel.visible:
				w.hud._production_panel.toggle()
			w.sim.speed = 4
	).running(480.0).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, OVEN, Vector2i(2, 1))}))
	out.append(TutorialStep.make("hands_on", L,
		"When the prep table has its ingredients, click it and choose Do it yourself.",
		"A batch by hand is quicker, and good timing makes better goods.",
		func(w, ctx) -> bool: return w.generator.manual_batches > int(ctx["manual"]),
		func(w, _ctx) -> void:
			var index: int = w.build.grid.placement_at(at(w, PREP))
			var recipe: Recipe = RecipeCatalog.get_recipe(&"make_dough")
			for i in range(900):
				if w.generator.can_perform(index, recipe):
					w.generator.perform_by_hand(index, recipe, 0.8)
					return
				await w.get_tree().process_frame
	).running(300.0).starting(func(w, ctx) -> void: ctx["manual"] = w.generator.manual_batches
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, PREP, Vector2i(2, 1))}))
	return out


static func _staff() -> Array[TutorialStep]:
	var L: String = LESSONS[4]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("staff_open", L,
		"Open Staff%s." % KeyBindings.hint("staff"),
		"Each person has a position: it decides what work they may do and what they cost.",
		func(w, _ctx) -> bool: return w.hud._priority_panel.visible,
		func(w, _ctx) -> void:
			if not w.hud._priority_panel.visible:
				w.hud._priority_panel.toggle()
	).pointing_at({"button": "Staff"}))
	out.append(TutorialStep.make("hire", L,
		"Hire a Busser.",
		"The fee is paid now, the wage every evening. Bussers clear tables, bring bills and carry goods.",
		func(w, _ctx) -> bool: return PlayerActions.staff(w, &"busser") != null,
		func(w, _ctx) -> void: PlayerActions.press(w.hud._priority_panel, "Busser")
	).pointing_at({"button": "Busser"}))
	out.append(TutorialStep.make("priority", L,
		"Click your waiter's Bill cell until it reads 1.",
		"Lower numbers are done first. A crossed cell is work the position does not allow.",
		func(w, _ctx) -> bool:
			var waiter: Worker = PlayerActions.staff(w, &"waiter")
			return waiter != null and int(waiter.priorities.get(WorkType.Kind.BILL, 0)) == 1,
		func(w, _ctx) -> void:
			PlayerActions.staff(w, &"waiter").priorities[WorkType.Kind.BILL] = 1
			w.hud._priority_panel.toggle()
	))
	return out


static func _service() -> Array[TutorialStep]:
	var L: String = LESSONS[5]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("open_doors", L,
		"Run time. Guests come up the road and sit wherever a chair is free.",
		"More come at lunch and in the evening, and more still when your reputation is good.",
		func(w, _ctx) -> bool: return any_guest(w, func(b) -> bool: return b.seat != Seating.NO_SEAT),
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(600.0))
	out.append(TutorialStep.make("take_order", L,
		"A guest who has read the menu raises a hand. Your waiter goes over and takes the order.",
		"Nobody orders on their own: no waiter, no order, and they leave.",
		func(w, _ctx) -> bool: return any_guest(w, func(b) -> bool: return b._did_order),
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(400.0))
	out.append(TutorialStep.make("plate", L,
		"Watch the order go out: the cooks plate it on the counter, the waiter carries it to the table.",
		"Anything on the menu has to be in stock; guests only order what you have.",
		func(w, _ctx) -> bool:
			return int(w.customers.consumed.get(&"bread", 0)) + int(w.customers.consumed.get(&"beer", 0)) >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(400.0).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, COUNTER, Vector2i(2, 1))}))
	out.append(TutorialStep.make("bill", L,
		"After eating, a guest waits for the bill. Whoever brings it quickly earns a tip.",
		"Left waiting, they pay at the door without a tip, and hold the table all the while.",
		func(w, _ctx) -> bool: return w.customers.served_count >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(500.0))
	out.append(TutorialStep.make("wash", L,
		"Plates go to the basin to be washed, and the table is free again.",
		"A busser or waiter clears the table; the cleaner washes up.",
		func(w, _ctx) -> bool: return int(w.generator.consumed.get(&"dirty_dishes", 0)) >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(500.0).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, BASIN, Vector2i(2, 1))}))
	out.append(TutorialStep.make("hover_guest", L,
		"Point at a guest to see their mood, their patience and what they owe.",
		"Their mood is the review they would write if they left now.",
		func(w, _ctx) -> bool:
			var subject: Dictionary = w.hud.hover._subject
			return w.hud.hover.visible and int(subject.get("kind", -1)) == WorldStats.Kind.PAWN \
				and is_instance_valid(subject.get("pawn")) and subject["pawn"].get_node_or_null("Brain") != null,
		func(w, _ctx) -> void:
			for brain in w.customers.customers:
				if is_instance_valid(brain):
					w.hud.hover.show_subject({"kind": WorldStats.Kind.PAWN, "pawn": brain.pawn})
					w.hud.hover.pin_at(Vector2(200, 200))
					return
	).running(300.0))
	out.append(TutorialStep.make("guest_type", L,
		"Every kind of adventurer wants something different. Point at guests to see who they are.",
		"Warriors drink hard, rangers hate waiting, wizards want a long menu, pilgrims a clean table.",
		func(w, _ctx) -> bool:
			var subject: Dictionary = w.hud.hover._subject
			if not w.hud.hover.visible or not is_instance_valid(subject.get("pawn")):
				return false
			var brain = subject["pawn"].get_node_or_null("Brain")
			if brain == null or brain.guest_type.wants.is_empty():
				return false
			for row in WorldStats._patron_rows(w, subject["pawn"], brain):
				if String(row.get("label", "")) == brain.guest_type.title:
					return true
			return false,
		func(w, _ctx) -> void:
			for brain in w.customers.customers:
				if is_instance_valid(brain) and not brain.guest_type.wants.is_empty():
					w.hud.hover.show_subject({"kind": WorldStats.Kind.PAWN, "pawn": brain.pawn})
					w.hud.hover.pin_at(Vector2(200, 200))
					return
	).running(300.0))
	return out


static func _money() -> Array[TutorialStep]:
	var L: String = LESSONS[6]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("ledger", L,
		"Open the Ledger to see today's money: takings, tips, supplies, wages.",
		"The figure beside the purse is today's profit so far.",
		func(w, _ctx) -> bool: return w.hud._details_panel.visible,
		func(w, _ctx) -> void:
			w.hud.hover._pinned_at = Vector2(-1, -1)
			PlayerActions.press(w.hud._hud, "Ledger")
	).pointing_at({"button": "Ledger"}))
	out.append(TutorialStep.make("day_end", L,
		"Run time to midnight. The day closes, wages are paid and reviews are read.",
		"A red panel on the right names whatever is costing you most, whenever something is.",
		func(w, ctx) -> bool: return w.ledger.history.size() > int(ctx["closed_days_before"]),
		func(w, _ctx) -> void:
			if w.hud._details_panel.visible:
				w.hud._details_panel.visible = false
			w.sim.speed = 4
	).starting(func(w, ctx) -> void: ctx["closed_days_before"] = w.ledger.history.size()).running(900.0))
	out.append(TutorialStep.make("reviews", L,
		"Read the reviews, then open tomorrow.",
		"Stars bring more guests. Slow service, dirty tables and a short menu cost stars.",
		func(w, ctx) -> bool: return w.clock.day > int(ctx["reviews_day"]) and not w.simulation_paused,
		func(w, _ctx) -> void: PlayerActions.press(w.hud._day_summary, "Open tomorrow")
	).starting(func(w, ctx) -> void:
		ctx["reviews_day"] = w.clock.day if w.simulation_paused else w.clock.day - 1
	).pointing_at({"button": "Open tomorrow"}))
	out.append(TutorialStep.make("host_stand", L,
		"Place a Host's Stand on the marked spot, by the door.",
		"A good name brings bookings, and bookings need someone to take them.",
		func(w, _ctx) -> bool: return placed_in(w, [&"host_stand"], room(w)) >= 1,
		func(w, _ctx) -> void:
			PlayerActions.place_all(w, &"host_stand", [at(w, HOST_STAND)])
			PlayerActions.stop_building(w)
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, HOST_STAND, Vector2i.ONE)}))
	out.append(TutorialStep.make("hire_host", L,
		"Hire a Host%s." % KeyBindings.hint("staff"),
		"A host greets the queue, so guests wait longer, and takes the day's bookings each morning.",
		func(w, _ctx) -> bool: return PlayerActions.staff(w, &"host") != null,
		func(w, _ctx) -> void:
			if not w.hud._priority_panel.visible:
				w.hud._priority_panel.toggle()
			PlayerActions.press(w.hud._priority_panel, "Host")
			w.hud._priority_panel.toggle()
	).pointing_at({"button": "Staff"}))
	out.append(TutorialStep.make("bookings", L,
		"Run time. The host takes bookings before 11:00. If it is later, open tomorrow at the day summary and wait for morning.",
		"The better your stars, the more tables are booked. Point at the stand to see who is coming when.",
		func(w, _ctx) -> bool: return w.customers.bookings.taken_day == w.clock.day,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(1200.0).pointing_at({"role": &"host"}))
	return out


static func _fishing() -> Array[TutorialStep]:
	var L: String = LESSONS[7]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("hire_fisher", L,
		"Open Staff%s and hire a Fisherman. The position opens on day 2." % KeyBindings.hint("staff"),
		"Fish costs nothing to buy: the first food the tavern brings in for itself.",
		func(w, _ctx) -> bool: return PlayerActions.staff(w, &"fisherman") != null,
		func(w, _ctx) -> void:
			if not w.hud._priority_panel.visible:
				w.hud._priority_panel.toggle()
			PlayerActions.press(w.hud._priority_panel, "Fisherman")
			w.hud._priority_panel.toggle()
	).pointing_at({"button": "Staff"}))
	out.append(TutorialStep.make("fishing_spot", L,
		"Build a Fishing Spot on the marked stretch of river bank.",
		"It has to stand at the water's edge. A porter builds it; the fisherman works it.",
		func(w, _ctx) -> bool: return placed_in(w, [&"fishing_spot"], w.plot) >= 1,
		func(w, _ctx) -> void:
			PlayerActions.place_all(w, &"fishing_spot", [fishing_spot(w)])
			PlayerActions.stop_building(w)
	).pointing_at(func(w) -> Dictionary: return {"tiles": Rect2i(fishing_spot(w), Vector2i(2, 1))}))
	out.append(TutorialStep.make("catch", L,
		"Run time. Once the spot is built, the fisherman fishes from it and carries the catch in.",
		"Each catch is a trout or a perch, one or two at a time: that part is luck.",
		func(w, _ctx) -> bool: return made(w, [&"trout", &"perch"]) >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(700.0).pointing_at({"role": &"fisherman"}))
	out.append(TutorialStep.make("clean_fish", L,
		"Wait for a cook to clean a fish at the prep table.",
		"Scaled and cut, each fish gives a fillet for the grill and a head for the soup pot.",
		func(w, _ctx) -> bool: return made(w, [&"fillet"]) >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(600.0).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, PREP, Vector2i(2, 1))}))
	out.append(TutorialStep.make("fish_dish", L,
		"Wait for the oven's first fish dish: grilled fish from a fillet, or soup from a head.",
		"Soup takes water as well, and one head makes two bowls.",
		func(w, _ctx) -> bool: return made(w, [&"grilled_fish", &"fish_soup"]) >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(600.0).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, OVEN, Vector2i(2, 1))}))
	out.append(TutorialStep.make("sell_fish", L,
		"Fish is on the menu now. Watch a guest order some and eat it.",
		"Guests order from whatever is in stock, and a longer menu earns better reviews.",
		func(w, _ctx) -> bool:
			return int(w.customers.consumed.get(&"grilled_fish", 0)) + int(w.customers.consumed.get(&"fish_soup", 0)) >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(900.0))
	return out


static func _growing() -> Array[TutorialStep]:
	var L: String = LESSONS[8]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("land", L,
		"Open Buy land to see what more ground would cost.",
		"The plot grows a strip at a time, and each strip costs more than the last.",
		func(w, _ctx) -> bool: return w.hud._land_panel.visible,
		func(w, _ctx) -> void: PlayerActions.press(w.hud._hud, "Buy land")
	).pointing_at({"button": "Buy land"}))
	out.append(TutorialStep.make("well", L,
		"Build a Well on the marked spot, near the river.",
		"It fills slowly with rain and stores water, so you buy less. A River Pump on the bank adds more, slowly.",
		func(w, _ctx) -> bool: return placed_in(w, [&"well"], w.plot) >= 1,
		func(w, _ctx) -> void:
			w.hud._land_panel.visible = false
			PlayerActions.place_all(w, &"well", [well_spot(w)])
			PlayerActions.stop_building(w)
	).pointing_at(func(w) -> Dictionary: return {"tiles": Rect2i(well_spot(w), Vector2i(2, 2))}))
	out.append(TutorialStep.make("booked_guest", L,
		"Watch for the first booked party. They come at their hour, on top of the walk-ins.",
		"Booked guests wait twice as long for their table, and mind the wait less.",
		func(w, _ctx) -> bool: return w.customers.bookings.arrived_guests() >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(700.0))
	out.append(TutorialStep.make("garden", L,
		"In the Garden tab, lay a Dirt Path out from the front door and a Daisy Bed beside it.",
		"Garden tiles are floors: paths are the quickest ground, and people step round flower beds. Benches, trees and lanterns are there too.",
		func(w, _ctx) -> bool:
			return placed_in(w, [&"garden_path"], w.plot) >= 1 and placed_in(w, [&"bed_daisy", &"bed_mixed", &"bed_border", &"bed_tulips", &"bed_lavender", &"bed_roses", &"bed_sunflowers"], w.plot) >= 1,
		func(w, _ctx) -> void:
			PlayerActions.select(w, &"garden_path")
			PlayerActions.drag(w, at(w, GARDEN_PATH), at(w, GARDEN_PATH + Vector2i(0, 1)))
			PlayerActions.place_all(w, &"bed_daisy", [at(w, GARDEN_BED)])
			PlayerActions.stop_building(w)
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w, GARDEN_BED, Vector2i(4, 2))}))
	out.append(TutorialStep.make("save", L,
		"Press Esc for the pause menu, and choose Save game.",
		"The game also saves itself at every close of day. Settings are in the same menu.",
		func(w, ctx) -> bool: return w.saved_at_msec > int(ctx["saved"]),
		func(w, _ctx) -> void:
			w.hud.open_pause_menu()
			PlayerActions.press(w.hud.pause_menu, "Save game")
			w.hud.pause_menu.close()
	).starting(func(w, ctx) -> void: ctx["saved"] = w.saved_at_msec).pointing_at({"button": "Menu"}))
	return out

