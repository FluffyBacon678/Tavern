class_name TavernWorld
extends Node3D

## Coordinates world state, player actions and the trading day.
## Presentation and initial wiring live in WorldHUD and WorldBootstrap.

signal land_bought(direction: int, price: int)

## Sides the plot can grow towards.
enum { SIDE_NORTH, SIDE_EAST, SIDE_SOUTH, SIDE_WEST }

## How deep a bought parcel is, in tiles.
const PARCEL_DEPTH: int = 6
## Gold per tile of new land, and how much dearer each parcel is than the last.
## Rising on purpose: the first field is a decision, the fifth is an ambition.
const LAND_PRICE_PER_TILE: float = 2.5
const LAND_PRICE_GROWTH: float = 1.45

## Staff on the opening day.
##
## Five, measured rather than guessed. Three looked right on paper -- 18g of
## wages instead of 30 against a small dining room -- and five simulated days
## said otherwise: the kitchen fell behind, patrons left because there was
## nothing to sell, and the 12g saved cost several times that in trade. The
## bottleneck in a small tavern is hands, not payroll.
const STARTING_STAFF: int = 5
## Who the tavern opens with, one position each: somebody to carry, cook,
## serve and wash. Two cooks because the kitchen was the ceiling -- measured on
## the demo level against two waiters, two porters and a busser, this crew
## earned the most (2026-09-28). Five, for 29g a day, near the old 30g.
const STARTING_CREW: Array[StringName] = [&"porter", &"cook", &"cook", &"waiter", &"cleaner"]
const MAIN_MENU_SCENE := "res://src/ui/main_menu/main_menu.tscn"

## Map size in tiles. Square, and independent of the window -- unlike the 2D
## backdrop, a 3D world should not change size with the viewport.
const MAP_TILES: int = 96
## Test runs with `-- --brief` keep the game's own log lines to themselves.
static var QUIET: bool = OS.get_cmdline_user_args().has("--brief")

## The starting plot: a roadside site, per the design notes' opening fantasy.
## Expansion later buys neighbouring land by growing this rect. Doubled in area
## from 26 x 20 (2026-09-28): room for a real kitchen, a counter and a well
## without buying land first.
const PLOT_SIZE := Vector2i(37, 28)
## The plot the designed levels were laid out on. They are placed the same
## distance from the southern road on a bigger plot, so the walk from the cart
## to the door -- which the level's numbers were measured with -- is unchanged.
const LEVEL_AUTHORED_PLOT := Vector2i(26, 20)

## Enclosed spaces, derived from what is built. See Rooms.
var rooms := Rooms.new()
var room_overlay: RoomOverlay
## The designed situation this run was started into, or null for a bare plot.
var level: LevelDef
var terrain := TerrainMeshBuilder.new()
var grid := TerrainGrid.new()
var rig: CameraRig
var build: BuildController
var nav: NavGrid
var board := JobBoard.new()
var items: ItemWorld
var generator: JobGenerator
var customers: CustomerDirector
var clock: DayClock
var ledger := Ledger.new()
## The simulation's own dice: who is hired, when guests turn up. Seeded from the
## world seed when the world is generated, so a seeded run repeats exactly --
## nothing outside the simulation may draw from it, and it draws from nothing
## outside.
var sim_rng := RandomNumberGenerator.new()
var bills := BillBook.new()
var objectives := Objectives.new()
var plot: Rect2i
var pawns: Array[Pawn] = []
var workers: Array[Worker] = []
var simulation_paused: bool = false
## Accepted supplier quantities, independent of subsequent hauling and cooking.
var delivered: Dictionary = {}

var _trees: TreeMeshLibrary
## Pointer, keyboard, selection and the hover card. See WorldInput.
var input: WorldInput
## Game time: pause, speed, and the steps every simulated system runs on.
var sim: SimClock
var _world_seed: int
## Parcels bought so far, which is what makes the next one dearer.
var _parcels_bought: int = 0
## Where the back river runs, fixed when the world is made.
##
## Deliberately *not* derived from the plot. It used to be, and the moment land
## could be bought that meant the river marched north with every purchase --
## which would have moved the one landscape feature the game has a rule about.
var river_row: int = 0
var _tri_count: int = 0
var _tree_count: int = 0

var _opaque_material: ShaderMaterial
var _forest_material: ShaderMaterial
var _water_material: ShaderMaterial
var _pawn_material: StandardMaterial3D
var atmosphere: WorldAtmosphere


var hud := WorldHUD.new()
var bootstrap := WorldBootstrap.new()
var cutaway := WorldCutaway.new()


func _ready() -> void:
	# First, before anything that lives in game time is made and attached to it.
	sim = SimClock.new()
	sim.name = "SimClock"
	add_child(sim)
	bootstrap.world = self
	hud.world = self
	add_child(hud)
	bootstrap._build_materials()
	bootstrap._build_environment()
	hud._build_hud()

	# Slot ownership and load intent are separate: a confirmed replacement is
	# still a new tavern, even while the old slot remains safely on disk.
	var saved: Dictionary = {}
	# Neither intent, yet a saved tavern in the slot: somebody forgot to ask.
	# Every Continue and Open in the main menu did exactly that, so each one
	# started a fresh tavern in the player's slot and the first save wiped the
	# old one. Loading is the only safe reading of a missing intent.
	var forgot: bool = not GameState.load_requested and not GameState.new_run_pending
	if forgot and GameState.active_slot >= 0 and GameState.has_save(GameState.active_slot):
		push_warning("World entered slot %d with no load or new-run intent; loading it rather than overwriting." % GameState.active_slot)
		GameState.load_requested = true
	GameState.new_run_pending = false
	if GameState.load_requested:
		saved = SaveGame.read(GameState.active_slot)
		GameState.load_requested = false
		if saved.is_empty():
			GameState.active_slot = -1
			SceneRouter.change_scene(MAIN_MENU_SCENE)
			return

	if saved.is_empty():
		_world_seed = GameState.world_seed if GameState.world_seed > 0 else randi() % 1_000_000
		generate(_world_seed)
	else:
		_world_seed = int(saved["world_seed"])
		generate(_world_seed)
		SaveGame.apply(self, saved)
		mark_saved()
	# A new tavern opens paused: building and ordering come first, and the
	# clock used to be running from the first frame, before anything was done.
	if GameState.start_paused:
		GameState.start_paused = false
		sim.speed = 0
		hud.flash("Paused while you plan. Press Space or 1 when you are ready to open.", 6.0)


func generate(world_seed: int) -> void:
	var started: int = Time.get_ticks_msec()
	_world_seed = world_seed
	sim_rng.seed = hash(world_seed) ^ 0x5eed
	for child in [_find("Terrain"), _find("Water"), _find("Forest")]:
		if child != null:
			child.queue_free()

	var config := ForestConfig.new()
	# The 2D backdrop wants a dense canopy because it is seen from directly above
	# and the trees *are* the picture. In 3D the same density becomes a wall of
	# foliage with no visible ground, which is useless for a game about placing
	# buildings on that ground.
	config.tree_density = 0.24
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	# No ground atlas: ground-cover sprite variants are meaningless in 3D.
	grid.generate(MAP_TILES, MAP_TILES, world_seed, config, rng, null)

	plot = Rect2i(
		Vector2i((MAP_TILES - PLOT_SIZE.x) / 2, (MAP_TILES - PLOT_SIZE.y) / 2),
		PLOT_SIZE
	)
	# Three tiles clear of the opening boundary, and it stays there whatever the
	# plot does afterwards.
	river_row = plot.position.y - 3
	_reshape_land(rng)
	if input == null:
		input = WorldInput.new()
		add_child(input)
		# First child, so the camera rig sees a right-click before this does.
		move_child(input, 0)
		input.setup(self)
		hud.inspector.subject_changed.connect(input.on_inspected)
	bootstrap._setup_camera()
	bootstrap._setup_build()
	bootstrap._setup_nav()
	bootstrap._setup_economy()
	bootstrap._spawn_pawns(rng, _opening_crew())
	_open_level()
	atmosphere.refresh_world()
	hud.refresh_stats()

	# Worth watching: this is all GDScript mesh building, and it is the number
	# that decides whether world generation needs to move off the main thread
	# before maps get any bigger.
	if not QUIET:
		print("World %d generated in %d ms (%d tiles, %d trees, %d triangles)" % [
			world_seed, Time.get_ticks_msec() - started, MAP_TILES * MAP_TILES, _tree_count, _tri_count
		])


## Where a supplier's cart unloads: just inside the plot's south edge, so goods
## always arrive somewhere reachable and hauling has a real distance to cover.
## The unloading yard: packed dirt just inside the southern boundary, at the top
## of the supplier's road.
##
## Three rows deep but goods only land on the middle one. The spare rows are
## standing room -- for the cart itself, and for whoever is carrying sacks off
## it -- so a full delivery never boxes in the people unloading it.
## The row the high road runs along: three rows south of the yard, so the lane
## from the yard meets it at a right angle.
func high_road_row() -> int:
	return mini(unloading_yard().end.y + 4, MAP_TILES - 3)


func unloading_yard() -> Rect2i:
	return Rect2i(plot.position.x + 2, plot.end.y - 4, 8, 3)


func delivery_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var yard: Rect2i = unloading_yard()
	var row: int = yard.position.y + 1
	for x in range(yard.position.x, yard.end.x):
		var tile := Vector2i(x, row)
		if nav != null and nav.is_walkable(tile):
			out.append(tile)
	return out


## The merchant's standard bundle: everything the bread and beer recipes need.
## Fourteen water, not ten: eight loaves and six brews want a barrel each, and
## a short delivery stalls the kitchen a day later in a way that reads as a
## broken cook rather than a bad order.
const STANDARD_ORDER: Dictionary = {&"flour": 8, &"water": 14, &"yeast": 8, &"malt": 6, &"hops": 6}
## The cart's fee, per delivery whatever is on it.
const DELIVERY_FEE: int = 5


## What an order costs, fee included. Nothing ordered costs nothing.
func order_cost(order: Dictionary) -> int:
	var cost: int = 0
	for id in order:
		var def: ItemDef = ItemCatalog.get_def(id)
		if def != null and int(order[id]) > 0:
			cost += def.purchase_price * int(order[id])
	return cost + DELIVERY_FEE if cost > 0 else 0


## Why this order cannot be delivered now, or "" if it can: the order screen
## greys out Confirm and says this, rather than letting the click fail.
func order_problem(order: Dictionary) -> String:
	var cost: int = order_cost(order)
	if cost <= 0:
		return "Nothing on the order yet"
	if GameState.gold < cost:
		return "Not enough gold for this delivery (%dg, the purse has %dg)" % [cost, GameState.gold]
	if delivery_tiles().is_empty():
		return "Nowhere to unload"
	if _plan_delivery(order).is_empty():
		return "The unloading yard cannot hold all of it. Clear the delivery area, or order less"
	return ""


## Buy an order (the standard bundle if none is given) and unload it in the
## yard. All or nothing: refused, it charges nothing and places nothing.
func order_supplies(order: Dictionary = {}) -> bool:
	if order.is_empty():
		order = STANDARD_ORDER
	var problem: String = order_problem(order)
	if not problem.is_empty():
		hud.flash(problem)
		return false
	var plan: Array = _plan_delivery(order)
	var cost: int = order_cost(order)
	if not ledger.spend(Ledger.Line.SUPPLIES, cost):
		return false
	# No await between reservation and placement: capacity cannot change here.
	for line in plan:
		items.place_near(line["def"], line["count"], line["tile"], 0)
		delivered[line["def"].id] = delivered.get(line["def"].id, 0) + line["count"]

	hud.flash("Delivery arrived — %dg" % cost)
	hud.refresh_stats()
	return true


## Where each part of the order would be put down, or [] if the yard cannot
## take all of it. Reserved in full before anything is charged: a full
## unloading area must refuse the purchase, never charge for goods that cannot
## be placed. Goods go in the catalogue's order, so the same order always lands
## on the same tiles.
func _plan_delivery(order: Dictionary) -> Array:
	var spots: Array[Vector2i] = delivery_tiles()
	var plan: Array = []
	var reserved: Dictionary = {}
	for id in _order_sequence(order):
		var def: ItemDef = ItemCatalog.get_def(id)
		if def == null:
			return []
		var remaining: int = int(order[id])
		for tile in spots:
			var held: ItemDef = items.def_at(tile)
			if held != null and held.id != def.id:
				continue
			if reserved.has(tile) and reserved[tile]["id"] != def.id:
				continue
			var allocated: int = reserved[tile]["count"] if reserved.has(tile) else 0
			var amount: int = mini(remaining, def.stack_size - items.count_at(tile) - allocated)
			if amount <= 0:
				continue
			plan.append({"def": def, "count": amount, "tile": tile})
			reserved[tile] = {"id": def.id, "count": allocated + amount}
			remaining -= amount
			if remaining == 0:
				break
		if remaining > 0:
			return []
	return plan


## The standard bundle's order first (it decides which tile gets what), then
## anything else the merchant sells.
func _order_sequence(order: Dictionary) -> Array:
	var out: Array = []
	for id in STANDARD_ORDER:
		if int(order.get(id, 0)) > 0:
			out.append(id)
	for id in order:
		if not out.has(id) and int(order[id]) > 0:
			out.append(id)
	return out


func _find(node_name: String) -> Node:
	return get_node_or_null(NodePath(node_name))


func _process(delta: float) -> void:
	if rig != null and rig.camera != null:
		cutaway.update(delta, build, rig.camera.global_position, rig._focus)


# --- HUD -----------------------------------------------------------------

## Close of business: pay the staff, rule off the books, and show the reckoning.
##
## Wages are charged here rather than continuously, so payroll lands as a single
## visible decision at the end of the day. The clock has already paused itself;
## it stays paused until the player dismisses the summary.
func _on_day_ended(day: int) -> void:
	if day != clock.day:
		return
	var closed: Dictionary = _closed_day_entry(day)
	if not closed.is_empty():
		_show_closed_day(closed)
		return
	set_simulation_paused(true)
	ledger.charge_wages(wage_bill())
	var entry: Dictionary = ledger.close_day(day, customers.served_count, customers.lost_count)
	if not QUIET:
		print("Day %d: %d served, %d lost (%d no seat, %d unserved, %d nothing to sell), profit %dg, purse %dg" % [
			day, entry["served"], entry["lost"],
			customers.lost_no_seat, customers.lost_no_service, customers.lost_no_menu,
			entry["profit"], entry["purse"]
		])
	# The closing save restores this same summary. Payroll belongs to the
	# archived day; loading or showing it a second time must never charge again.
	if GameSettings.autosave:
		save_now()
	_show_closed_day(entry)


func _closed_day_entry(day: int) -> Dictionary:
	for entry in ledger.history:
		if int(entry.get("day", -1)) == day:
			return entry
	return {}


func _show_closed_day(entry: Dictionary) -> void:
	set_simulation_paused(true)
	# Nothing half-done left open behind the summary: the order form sat there
	# with the whole reckoning drawn over it.
	hud.close_for_summary()

	if hud._day_summary != null:
		var verdict: Dictionary = level.verdict_for(self, int(entry["day"])) if level != null else {}
		hud._day_summary.show_day(entry, hud._tavern_name(), customers.reputation, customers.day_reviews, verdict)
	else:
		_begin_next_day()


## Keep simulation local to this world: pausing the SceneTree would also stop
## camera movement, UI and verification timers, and could leak into the menu.
func set_simulation_paused(value: bool) -> void:
	simulation_paused = value
	clock.paused = value
	if sim != null:
		sim.held = value
	var mode: ProcessMode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
	generator.process_mode = mode
	customers.process_mode = mode
	for pawn in pawns:
		pawn.process_mode = mode
	if value:
		build.cancel_drag()
		if hud.hover != null:
			hud.hover.dismiss()
		if hud._hands_on != null and hud._hands_on.visible:
			hud._hands_on._close()
		if generator.has_method("release_all_manual"):
			generator.call("release_all_manual")


## Level the plot, carve the fixed features, and rebuild everything that is
## drawn from the landscape.
##
## Factored out of generate() because buying land has to do all of it again and
## none of the rest: the noise grid, the buildings, the staff and the goods all
## survive a purchase untouched. The river is re-carved each time so a plot that
## grows towards it cannot swallow the bank.
func _reshape_land(rng: RandomNumberGenerator) -> void:
	for child in [_find("Terrain"), _find("Water"), _find("Forest")]:
		if child != null:
			child.queue_free()

	bootstrap._clear_plot()
	# Deterministic features, carved after the plot is levelled and before the
	# ground is meshed: the supplier's road and unloading yard to the south, and
	# the river along the back boundary.
	bootstrap._carve_approach()
	bootstrap._carve_river()
	terrain.build_from(grid, plot)

	bootstrap._build_terrain()
	bootstrap._build_forest(rng)
	bootstrap._build_plot_marker()
	bootstrap._build_yard()


## What the next parcel in a direction would be, or an empty rect if there is
## none to be had.
##
## Parcels are strips off the side of the plot rather than free-form selection.
## A tavern keeper buys the field next door; they do not draw a polygon.
func parcel(direction: int) -> Rect2i:
	var grown: Rect2i = plot
	match direction:
		SIDE_NORTH:
			grown = Rect2i(plot.position - Vector2i(0, PARCEL_DEPTH), plot.size + Vector2i(0, PARCEL_DEPTH))
		SIDE_SOUTH:
			grown = Rect2i(plot.position, plot.size + Vector2i(0, PARCEL_DEPTH))
		SIDE_WEST:
			grown = Rect2i(plot.position - Vector2i(PARCEL_DEPTH, 0), plot.size + Vector2i(PARCEL_DEPTH, 0))
		SIDE_EAST:
			grown = Rect2i(plot.position, plot.size + Vector2i(PARCEL_DEPTH, 0))
		_:
			return Rect2i()
	return grown


## Why this parcel cannot be bought, or "" if it can.
##
## Order matters: the reasons a player can do something about come last, so the
## message they see is the useful one.
func parcel_problem(direction: int) -> String:
	var grown: Rect2i = parcel(direction)
	if grown.size == Vector2i.ZERO:
		return "No such direction"
	# A margin off the map edge, because the plot is levelled with a falloff ring
	# around it and that ring has to fit somewhere.
	var margin: int = 6
	if (
		grown.position.x < margin or grown.position.y < margin
		or grown.end.x > MAP_TILES - margin or grown.end.y > MAP_TILES - margin
	):
		return "The land runs out that way"
	# The river is the one piece of landscape with a rule attached -- a well has
	# to reach it -- so the plot is not allowed to swallow it. Ponds elsewhere
	# are fair game and get levelled like everything else.
	if direction == SIDE_NORTH and grown.position.y <= river_row + 2:
		return "The river is in the way"
	if GameState.gold < parcel_price(direction):
		return "Not enough gold"
	return ""


## Priced by area, and dearer each time. The first field is a decision; the
## fifth should be an ambition.
func parcel_price(direction: int) -> int:
	var grown: Rect2i = parcel(direction)
	if grown.size == Vector2i.ZERO:
		return 0
	var added: int = grown.size.x * grown.size.y - plot.size.x * plot.size.y
	return int(round(float(added) * LAND_PRICE_PER_TILE * pow(LAND_PRICE_GROWTH, float(_parcels_bought))))


## Buy the next parcel on one side and fold it into the plot.
func buy_land(direction: int) -> bool:
	var problem: String = parcel_problem(direction)
	if problem != "":
		hud.flash(problem)
		return false

	var price: int = parcel_price(direction)
	var grown: Rect2i = parcel(direction)
	var added: int = grown.size.x * grown.size.y - plot.size.x * plot.size.y
	plot = grown
	_parcels_bought += 1
	ledger.spend(Ledger.Line.LAND, price)

	var rng := RandomNumberGenerator.new()
	rng.seed = _world_seed + _parcels_bought
	_reshape_land(rng)
	build.grid.set_plot(plot)
	rooms.set_plot(plot)
	# Buying land to the south moves the yard, and with it the road the staff
	# are measured from.
	var yard: Rect2i = unloading_yard()
	generator.road_tile = Vector2i(yard.position.x + yard.size.x / 2, yard.position.y + 1)
	generator.invalidate_reach()
	build.plot_height = terrain.plot_height
	nav.refresh_all()
	# Seating and the item filters both follow the grid, but the new ground has
	# no furniture on it yet; what has changed is where people may walk.
	if customers != null:
		customers.plot = plot
	hud.flash("Bought %d tiles of land for %dg" % [added, price])
	hud.refresh_stats()
	land_bought.emit(direction, price)
	return true


## Build the level this run was started into, if it was started into one.
##
## Charged against the purse like anything else -- the level sets the gold it
## wants the player to have *after* inheriting the building, so the arithmetic
## stays in the level definition rather than being split between here and there.
func _open_level() -> void:
	if GameState.pending_level.is_empty():
		return
	level = LevelCatalog.get_level(GameState.pending_level)
	GameState.pending_level = &""
	if level == null:
		return

	GameState.tavern_name = level.tavern_name
	# Counted and reported: a level that quietly loses half its walls to a
	# collision looks like a design choice rather than a mistake.
	var placed: int = 0
	var refused: int = 0
	for piece in level.pieces:
		var def: BuildingDef = BuildingCatalog.get_def(piece.id)
		if def == null:
			push_warning("Level '%s' wants a '%s', which is not in the catalog." % [level.id, piece.id])
			refused += 1
			continue
		if build.place_programmatic(def, plot.position + piece.tile, piece.rotation, false) < 0:
			refused += 1
		else:
			placed += 1
	if not QUIET:
		print("Level '%s': %d placed, %d refused" % [level.id, placed, refused])
	if refused > 0:
		push_warning("Level '%s' could not place %d of its pieces." % [level.id, refused])
	for def in BuildingCatalog.all():
		build._rebuild_instances(def)
	nav.refresh_all()
	customers.seating.refresh()
	# Open looking at the building the player has inherited, not at the middle
	# of a plot that is mostly empty field.
	if rig != null and not level.pieces.is_empty():
		var lo: Vector2i = level.pieces[0].tile
		var hi: Vector2i = lo
		for piece in level.pieces:
			lo = Vector2i(mini(lo.x, piece.tile.x), mini(lo.y, piece.tile.y))
			hi = Vector2i(maxi(hi.x, piece.tile.x), maxi(hi.y, piece.tile.y))
		var middle: Vector2 = Vector2(plot.position) + Vector2(lo + hi) * 0.5 + Vector2(0.5, 0.5)
		rig.focus_on(Vector3(middle.x, terrain.plot_height, middle.y))

	# Stock goes on the shelves where there is room and by the door where there
	# is not, which is exactly what the player will see happen to their own
	# deliveries later.
	var shelf: Vector2i = _first_storage_tile()
	for id in level.stock:
		var item: ItemDef = ItemCatalog.get_def(id)
		if item == null:
			continue
		var stocked: int = items.place_near(item, int(level.stock[id]), shelf)
		delivered[id] = delivered.get(id, 0) + stocked

	GameState.gold = level.starting_gold
	hud.show_briefing(level)
	if level.is_tutorial:
		var room: Rect2i = TutorialPlan.room(self)
		var middle: Vector2 = Vector2(room.position) + Vector2(room.size) * 0.5
		if rig != null:
			rig.focus_on(Vector3(middle.x, terrain.plot_height, middle.y))
		hud.start_tutorial(0)
	hud.refresh_stats()


func _first_storage_tile() -> Vector2i:
	for entry in build.grid.placements:
		if entry != null and entry["def"].is_storage:
			return entry["tiles"][0]
	return plot.position + plot.size / 2


## Write the tavern to its slot.
##
## Only saves when a slot is actually owned. Scenario and benchmark runs never
## call start_new_run, so their active_slot stays -1 and they cannot overwrite a
## real save while testing.
func save_now() -> bool:
	if GameState.active_slot < 0:
		return false
	if not SaveGame.write(GameState.active_slot, SaveGame.capture(self)):
		hud.flash("Could not save")
		return false
	mark_saved()
	return true


## What the tavern looked like at the last save or load, for "you have unsaved
## progress" -- game time, the purse and the building count between them catch
## anything a player would mind losing, including building while paused.
var _saved_mark: Array = []
## Real time of the last save or load, for "saved 3 min ago". 0 if never.
var saved_at_msec: int = 0


func mark_saved() -> void:
	_saved_mark = _progress_mark()
	saved_at_msec = Time.get_ticks_msec()


func has_unsaved_progress() -> bool:
	return _saved_mark != _progress_mark()


func _progress_mark() -> Array:
	return [snappedf(sim.sim_time if sim != null else 0.0, 0.5), GameState.gold,
		build.grid.live_count() if build != null else 0, workers.size()]


func _begin_next_day() -> void:
	if not simulation_paused or _closed_day_entry(clock.day).is_empty():
		return
	if hud._day_summary != null:
		hud._day_summary.hide()
	customers.reset_day_tallies()
	for worker in workers:
		worker.reset_day_tally()
	set_simulation_paused(false)
	clock.advance_day()
	hud.refresh_stats()


## Show or hide the room overlay, and say which it is on the button.
##
## Rebuilt every time it is opened rather than kept in step with the grid: the
## rooms themselves are already lazy, and a player who has just knocked a wall
## through wants to see the result, not a cached picture of the room it used to
## be.
func toggle_room_overlay() -> void:
	if room_overlay == null:
		return
	AudioDirector.play("ui_click")
	var shown: bool = room_overlay.toggle(rooms, terrain.plot_height)
	if hud._rooms_button != null:
		hud._rooms_button.text = "Rooms: on" if shown else "Rooms [O]"
	if shown and rooms.current().is_empty():
		hud.flash("No enclosed rooms yet — finish a wall around one")


func _go_back() -> void:
	AudioDirector.play("ui_back")
	SceneRouter.change_scene(MAIN_MENU_SCENE)


## Everything of one kind in the tavern: on the ground and in anyone's arms.
##
## One definition, used by the header, the warning line and the inspector. It
## was written out three times, and a count that forgets the sack being carried
## tells the player they are out of flour while somebody walks it to the oven.
func stock_of(id: StringName) -> int:
	var n: int = items.total_of(id) if items != null else 0
	for worker in workers:
		var def: ItemDef = worker.carried_def()
		if def != null and def.id == id:
			n += worker.carried_count()
	return n


## Let a member of staff go. Returns "" on success, or why not.
##
## There was a Hire button and no way back: one misclick added a wage for
## ever, and a tavern sliding into debt could not shed the cost that was
## sinking it. They are paid for the day on leaving -- otherwise hiring at
## dawn and dismissing before close would be a day's work for nothing -- and
## whatever they were carrying is put down first, because a worker freed with
## goods in their arms takes the goods out of the world with them.
func dismiss_worker(worker: Worker) -> String:
	if not workers.has(worker) or not is_instance_valid(worker):
		return "They have already gone"
	if workers.size() <= 1:
		return "Keep at least one pair of hands"
	worker._give_up()
	if worker.carried_count() > 0:
		return "%s has nowhere to put down what they are carrying" % worker.pawn.pawn_name
	# Stop them thinking before they go. _give_up() leaves them ready to seek at
	# once, and the node is not freed until the frame ends -- long enough to
	# claim a fresh job and take the claim with them, leaving it stranded.
	worker.set_process(false)
	worker.board = null
	var pawn: Pawn = worker.pawn
	var paid: int = worker.wage()
	ledger.charge_wages(paid)
	if rig != null and rig.follow == pawn:
		rig.follow = null
	var shown: Dictionary = hud.inspector.subject() if hud != null and hud.inspector != null else {}
	if int(shown.get("kind", -1)) == WorldStats.Kind.PAWN and shown["pawn"] == pawn:
		hud.inspector.clear()
	workers.erase(worker)
	pawns.erase(pawn)
	pawn.queue_free()
	hud.flash("%s has been let go, paid %dg for the day" % [pawn.pawn_name, paid])
	hud.refresh_stats()
	return ""


## Take somebody on as `role_id`. Returns "" or why not. The fee comes out of
## the purse now; the wage at every close from today.
func hire(role_id: StringName) -> String:
	var role: StaffRole = StaffRole.of(role_id)
	if role == null or not role.hireable:
		return "Nobody is hired as that"
	if clock != null and clock.day < role.unlock_day:
		return "A %s can be hired from day %d" % [role.title.to_lower(), role.unlock_day]
	if not ledger.spend(Ledger.Line.HIRING, role.fee):
		return "A %s costs %dg to take on; the purse has %dg" % [role.title.to_lower(), role.fee, GameState.gold]
	var before: int = workers.size()
	bootstrap._add_pawn(_find("Pawns"), sim_rng.randi(), role)
	if workers.size() == before:
		# Nowhere on the plot to stand. Give the fee back rather than keep it.
		ledger.today[Ledger.Line.HIRING] = int(ledger.today.get(Ledger.Line.HIRING, 0)) - role.fee
		GameState.gold += role.fee
		return "There is nowhere on the plot for a new %s to stand" % role.title.to_lower()
	if hud != null:
		hud.flash("Hired %s as %s: %dg paid, %dg a day" % [
			pawns[pawns.size() - 1].pawn_name, role.title.to_lower(), role.fee, role.wage])
		hud.refresh_stats()
	return ""


## STARTING_CREW, or in a debug build `-- crew=porter,cook,...` for measuring
## other crews against the level without editing the constant.
func _opening_crew() -> Array[StringName]:
	var crew: Array[StringName] = STARTING_CREW.duplicate()
	if OS.is_debug_build():
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("crew="):
				crew.clear()
				for id in arg.trim_prefix("crew=").split(",", false):
					if StaffRole.of(StringName(id)) != null:
						crew.append(StringName(id))
	return crew


## The day's wages if the tavern closed now: every position's own rate.
func wage_bill() -> int:
	var total: int = 0
	for worker in workers:
		if is_instance_valid(worker):
			total += worker.wage()
	return total


## Placement has to clear the purse before it clears the grid, so affordability
## is checked here rather than inside BuildController -- the builder knows about
## space, not economy.
func commit_build_action() -> void:
	if build.mode == BuildController.Mode.DEMOLISH:
		demolish_at(build.hover_tile())
		return

	if build.selected == null:
		return
	var cost: int = build.selected.cost
	if GameState.gold < cost:
		build.refused.emit("Not enough gold: %s costs %dg, the purse has %dg" % [
			build.selected.display_name, cost, GameState.gold])
		return
	var before: int = GameState.gold
	# A door goes into a wall: the wall comes out (refunded as any demolition
	# is) and the door takes its place. Putting a door in used to mean finding
	# Demolish, removing the wall, and coming back.
	if build.selected.shape == BuildingDef.Shape.DOOR:
		var there: int = build.grid.placement_at(build.hover_tile())
		if there >= 0 and build.grid.placements[there]["def"].shape == BuildingDef.Shape.WALL:
			demolish_at(build.hover_tile(), true)
	if build.try_place():
		ledger.spend(Ledger.Line.CONSTRUCTION, cost)
		if build.selected != null and build.selected.blocks_movement:
			var cut_off: String = route_warning()
			if not cut_off.is_empty():
				hud.flash(cut_off)
		_warn_if_spent_low(before)
		hud.refresh_stats()


## Take down whatever stands on `tile`, and pay back for it: all of it for a
## blueprint nobody had started, half for a finished piece. Returns the refund,
## or -1 if there was nothing there. `quiet` skips the message, for a wall a
## door is replacing.
##
## Demolishing gave nothing back, so a player who overbuilt on the first
## morning had no way out: the purse was empty and every piece was sunk.
func demolish_at(tile: Vector2i, quiet: bool = false) -> int:
	var index: int = build.grid.placement_at(tile)
	if index < 0:
		return -1
	var entry: Dictionary = build.grid.placements[index]
	var def: BuildingDef = entry["def"]
	var refund: int = demolish_refund(entry)
	if not build.demolish_index(index):
		return -1
	if refund > 0:
		ledger.earn(Ledger.Line.REFUNDS, refund)
	if not quiet:
		hud.flash("%s %s: %dg back" % ["Cancelled" if not entry["built"] else "Demolished",
			def.display_name.to_lower(), refund])
	hud.refresh_stats()
	return refund


## What demolishing this placement pays back.
static func demolish_refund(entry: Dictionary) -> int:
	var def: BuildingDef = entry["def"]
	return def.cost if not entry["built"] else def.cost / 2


## Gold to keep in hand: tonight's wages and one standard delivery. Spending
## below it is where a new tavern soft-locks -- nothing to sell, nothing to buy
## ingredients with, and wages still due at midnight.
func spending_reserve() -> int:
	return order_cost(STANDARD_ORDER) + wage_bill()


## What paying `cost` now would mean, for the build bar's readout while
## dragging: [text, level], level 0 fine, 1 leaves too little, 2 unaffordable.
func cost_note(cost: int, count: int = 1) -> Array:
	var left: int = GameState.gold - cost
	var reserve: int = spending_reserve()
	var what: String = "%d tiles · %dg" % [count, cost] if count > 1 else "%dg" % cost
	if cost > GameState.gold:
		return ["%s — the purse has %dg" % [what, GameState.gold], 2]
	if left < reserve:
		return ["%s — leaves %dg; tonight's wages and a delivery need %dg" % [what, left, reserve], 1]
	return ["%s — leaves %dg" % [what, left], 0]


## Said once, as the purse crosses the reserve, rather than on every click after.
func _warn_if_spent_low(before: int) -> void:
	var reserve: int = spending_reserve()
	if before >= reserve and GameState.gold < reserve:
		hud.flash("Careful: %dg left. Tonight's wages are %dg and a delivery costs %dg." % [
			GameState.gold, wage_bill(), order_cost(STANDARD_ORDER)], 4.0)


## Would a patron walking up from the road still reach every seat, and could the
## staff still get to every bench? Returns "" if so, or what has been cut off.
##
## Asked about the tavern as it will be once its blueprints are built, because
## that is when the damage lands -- and by then the player has moved on. The
## case that prompted it: a wash basin placed on the one tile inside the only
## door. Nothing refused it. The staff built it, the tavern sealed itself, and
## for five straight days every arrival stood at the wall until they gave up,
## while the ledger showed every seat free and clean.
##
## A warning, not a refusal. Walling a room in is a normal step on the way to
## putting a door in it.
func route_warning() -> String:
	var yard: Rect2i = unloading_yard()
	var road := Vector2i(yard.position.x + yard.size.x / 2, yard.position.y + 1)
	var planned: Dictionary = {}
	for entry in build.grid.placements:
		if entry == null or entry["built"] or not entry["def"].blocks_movement:
			continue
		for tile in entry["tiles"]:
			planned[tile] = true
	var reach: Dictionary = nav.reachable_from(road, planned)
	if reach.is_empty():
		return ""

	var stranded_seats: int = 0
	for seat in customers.seating.seats:
		if not reach.has(seat["chair"]):
			stranded_seats += 1
	if stranded_seats > 0:
		return "Nobody can reach %d of your seats from the road" % stranded_seats

	for entry in build.grid.placements:
		if entry == null or RecipeCatalog.for_station(entry["def"].id).is_empty():
			continue
		var reachable: bool = false
		for tile in entry["tiles"]:
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if reach.has(tile + step):
					reachable = true
		if not reachable:
			return "Your staff can no longer reach the %s" % entry["def"].display_name.to_lower()
	return ""


## Commit a dragged area of flooring, paying for as much of it as the purse
## allows.
##
## Capped rather than refused: dragging across more ground than you can afford
## should lay what you can afford, starting from one corner, instead of doing
## nothing and making you guess how much less to drag.
func commit_area_build() -> void:
	var def: BuildingDef = build.selected
	if def == null:
		build.cancel_drag()
		return
	var before: int = GameState.gold
	var wanted: int = build.drag_tiles().size()
	var affordable: int = GameState.gold / maxi(def.cost, 1)
	var done: int = build.finish_drag(affordable)
	if done > 0:
		ledger.spend(Ledger.Line.CONSTRUCTION, done * def.cost)
	if done < wanted:
		hud.flash("Laid %d of %d - not enough gold for the rest" % [done, wanted], 3.0)
	elif done > 0:
		hud.flash("%d x %s - %dg" % [done, def.display_name, done * def.cost])
	_warn_if_spent_low(before)
	hud.refresh_stats()
