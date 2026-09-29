extends "res://dev/regression_group.gd"

## Building and the ground: floors, rooms, the overlay, doorways, sealed
## pockets and buying land.


func run() -> void:
	var world: TavernWorld = fixture_world
	var scenario: Node = fixture_scenario
	_check_area_fill(world)
	_check_build_money(world)
	_check_take_back_and_sell(world, scenario)
	_check_rooms(world)
	_check_room_overlay(world)
	_check_doorway(world)
	_check_sealed_pocket(world)
	_check_land(world, scenario)


## Flooring is painted over an area, and only flooring.
##
## The rectangle has to skip ground that is already covered rather than refuse
## the whole drag, and it has to stop at what the player can pay for instead of
## quietly overdrawing the purse. Objects must not get the behaviour at all --
## dragging out a rectangle of ovens is not a thing anybody means to do.
func _check_area_fill(world: TavernWorld) -> void:
	var floor_def: BuildingDef = BuildingCatalog.get_def(&"wood_floor")
	var oven: BuildingDef = BuildingCatalog.get_def(&"oven")

	world.build.mode = BuildController.Mode.PLACE
	world.build.select(oven)
	check(not world.build.supports_area(), "a workstation is placed one at a time")
	check(not world.build.begin_drag(world.plot.position + Vector2i(1, 1)), "a workstation cannot be dragged out")

	world.build.select(floor_def)
	check(world.build.supports_area(), "flooring can be painted over an area")

	var corner: Vector2i = world.plot.position + Vector2i(1, 1)
	check(world.build.begin_drag(corner), "a drag opens on the floor")
	world.build.update_hover(corner + Vector2i(3, 3), true)
	check(world.build.drag_tiles().size() == 16, "a four by four drag covers sixteen tiles")

	# Only as much as the purse allows, laid from one corner rather than scattered.
	var before: int = world.build.grid.live_count()
	check(world.build.finish_drag(6) == 6, "an unaffordable drag lays what it can")
	check(world.build.grid.live_count() == before + 6, "six pieces reach the grid")
	check(not world.build.is_dragging(), "the drag ends when it is committed")

	# Same rectangle again: the six already down are skipped, not refused.
	check(world.build.begin_drag(corner), "a second drag opens over the same ground")
	world.build.update_hover(corner + Vector2i(3, 3), true)
	check(world.build.drag_tiles().size() == 10, "ground already floored is skipped")
	check(world.build.finish_drag(99) == 10, "the rest of the area fills")
	check(world.build.grid.live_count() == before + 16, "the whole rectangle is floored")

	world.build.begin_drag(corner)
	world.build.update_hover(corner + Vector2i(3, 3), true)
	check(world.build.drag_tiles().is_empty(), "a fully floored area has nothing left to lay")
	world.build.cancel_drag()
	world.build.mode = BuildController.Mode.OFF


## A room is what happens when you finish a wall, and stops being one when you
## knock a hole in it.
##
## Derived, never tracked -- the same argument the seating and the job board
## make. The test that matters is the un-making: a system that notices rooms
## appearing but not disappearing looks correct for an entire play session and
## is wrong the first time somebody demolishes a wall.
func _check_rooms(world: TavernWorld) -> void:
	var found: Array[Dictionary] = world.rooms.current()
	check(found.size() == 1, "the walled demo tavern is one enclosed room")
	if found.is_empty():
		return

	var room: Dictionary = found[0]
	check(room["tiles"].size() > 50, "the room is the whole interior")
	check(room["kind"] != null, "a furnished room earns a name")
	check(room["doors"] >= 1, "and the door it is entered by is counted")
	# Identity is data: this space holds an oven and a prep table, so whatever the
	# catalog calls that is what it is.
	check(
		room["kind"] != null and room["kind"].id == &"kitchen",
		"a room with a cooking station and a prep surface is a kitchen"
	)

	# A tile inside is in it; the open ground outside the walls is not.
	var inside: Vector2i = room["tiles"][0]
	check(world.rooms.room_at(inside) == 0, "a tile inside belongs to the room")
	check(
		world.rooms.room_at(world.plot.position + Vector2i(1, 1)) == -1,
		"open ground inside your land is not a room"
	)

	# Now knock a hole in it -- in a wall that is actually holding the room in.
	# A corner post has interior on neither side, so pulling one out proves
	# nothing; the first attempt at this test picked one and passed for the
	# wrong reason.
	var wall_index: int = -1
	var wall_def: BuildingDef = null
	var wall_tile := Vector2i(-1, -1)
	var wall_rot: int = 0
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry == null or not entry["def"].encloses:
			continue
		if entry["def"].shape == BuildingDef.Shape.DOOR:
			continue
		var touches_inside: bool = false
		for step in Rooms.NEIGHBOURS:
			if world.rooms.room_at(entry["origin"] + step) >= 0:
				touches_inside = true
				break
		if not touches_inside:
			continue
		wall_index = i
		wall_def = entry["def"]
		wall_tile = entry["origin"]
		wall_rot = entry["rotation"]
		break
	check(wall_index >= 0, "the tavern has a load-bearing wall to demolish")
	if wall_index < 0:
		return

	world.build.grid.remove(wall_index)
	check(world.rooms.current().is_empty(), "a room with a hole in it is not a room")
	check(world.rooms.room_at(inside) == -1, "and the tiles inside are outdoors again")

	# Put it back and the room returns, with nothing having been remembered.
	world.build.place_programmatic(wall_def, wall_tile, wall_rot, false)
	world.build._rebuild_instances(wall_def)
	check(world.rooms.current().size() == 1, "mending the wall makes the room again")


## The room overlay has to actually put something on screen.
##
## A diagnostic view that draws nothing is worse than none, because the player
## reads "no rooms" instead of "the overlay is broken". The height check is the
## bug that happened: the wash was lifted 0.045 above the plot plane and a wood
## floor slab is 0.06 tall, so it was drawn *inside* the boards and the whole
## feature appeared to do nothing.
func _check_room_overlay(world: TavernWorld) -> void:
	check(world.room_overlay != null, "the world has a room overlay")
	if world.room_overlay == null:
		return
	check(not world.room_overlay.visible, "the overlay starts hidden")

	var tallest: float = 0.0
	for def in BuildingCatalog.all():
		if def.layer == BuildingDef.Layer.FLOOR:
			tallest = maxf(tallest, def.height)
	check(tallest > 0.0, "there is flooring with a thickness to clear")
	check(
		RoomOverlay.LIFT > tallest,
		"the overlay is lifted clear of the thickest floor piece"
	)

	var shown: bool = world.room_overlay.toggle(world.rooms, world.terrain.plot_height)
	check(shown and world.room_overlay.visible, "the overlay opens")
	var mesh: ArrayMesh = world.room_overlay._mesh.mesh
	check(mesh != null and mesh.get_surface_count() > 0, "an enclosed room draws a wash")
	check(world.room_overlay._labels.get_child_count() == world.rooms.current().size(),
		"every room gets a caption")

	check(not world.room_overlay.toggle(world.rooms, world.terrain.plot_height), "the overlay closes again")


## Blocking the only way in has to be noticed at the moment it is placed.
##
## The demo level lost five straight days to this: a wash basin on the tile
## inside the only door, built without complaint, after which every arrival
## stood at the wall until they gave up while the ledger reported every seat
## free and clean. The check has to see *blueprints* -- by the time the builder
## finishes, the player has moved on.
func _check_doorway(world: TavernWorld) -> void:
	check(world.route_warning() == "", "the demo tavern starts with a way in")

	var door: Vector2i = Vector2i(-1, -1)
	for entry in world.build.grid.placements:
		if entry != null and entry["built"] and entry["def"].shape == BuildingDef.Shape.DOOR:
			door = entry["origin"]
			break
	check(door != Vector2i(-1, -1), "the demo tavern has a door")
	if door == Vector2i(-1, -1):
		return

	# The tile on the room side of the door: whichever neighbour is in a room.
	var inside: Vector2i = Vector2i(-1, -1)
	for step in Rooms.NEIGHBOURS:
		if world.rooms.room_at(door + step) >= 0:
			inside = door + step
	check(inside != Vector2i(-1, -1), "the door opens into the room")
	if inside == Vector2i(-1, -1):
		return

	var barrel: BuildingDef = BuildingCatalog.get_def(&"barrel")
	var index: int = world.build.place_programmatic(barrel, inside, 0, true)
	check(index >= 0, "a barrel can be planned in the doorway")
	if index < 0:
		return
	var warning: String = world.route_warning()
	check(warning.contains("seats"), "planning to block the only door warns about the seats: '%s'" % warning)

	world.board.cancel_for_subject(index)
	world.build.grid.remove(index)
	check(world.route_warning() == "", "clearing the doorway clears the warning")


## Nobody is sent to stand somewhere they cannot get to.
##
## A walkable tile boxed in on four sides is a pocket: diagonal moves need both
## corners open, so it cannot be entered at all. adjacent_walkable() used to
## return it anyway whenever it was the nearest free neighbour, and the worker
## then set off, failed, and abandoned the job -- 164 times in one measured run
## of the demo level.
func _check_sealed_pocket(world: TavernWorld) -> void:
	var pocket: Vector2i = world.plot.position + Vector2i(22, 15)
	var barrel: BuildingDef = BuildingCatalog.get_def(&"barrel")
	var walls: Array[int] = []
	for step in Rooms.NEIGHBOURS:
		var index: int = world.build.place_programmatic(barrel, pocket + step, 0, false)
		if index >= 0:
			walls.append(index)
	world.nav.refresh_area(Rect2i(pocket - Vector2i(2, 2), Vector2i(5, 5)))
	check(walls.size() == 4, "four barrels box a tile in")
	check(world.nav.is_walkable(pocket), "the boxed-in tile is still walkable in itself")

	var yard: Rect2i = world.unloading_yard()
	var road := Vector2i(yard.position.x + yard.size.x / 2, yard.position.y + 1)
	check(not world.nav.reachable_from(road).has(pocket), "but nothing can reach it from the road")

	# Approach the east barrel from the west, so the pocket is its nearest free
	# neighbour -- exactly the case that used to be returned.
	var far_west: Vector2i = pocket + Vector2i(-3, 0)
	var stand: Vector2i = world.nav.adjacent_walkable(pocket + Vector2i(1, 0), far_west)
	check(stand != Vector2i(-1, -1), "the barrel can still be reached from another side")
	check(stand != pocket, "a worker is never sent to stand in the sealed pocket")

	# And goods spilled nearby are put where somebody can stand beside them.
	# Note the pocket itself qualifies: a worker on a reachable diagonal can
	# collect from it, so this is about reach, not about the pocket.
	world.generator.invalidate_reach()
	world.generator.scan()
	var flour: ItemDef = ItemCatalog.get_def(&"flour")
	var before: Dictionary = {}
	for tile in world.items.tiles_with(&"flour", pocket):
		before[tile] = world.items.count_at(tile)
	var spilled: int = world.items.place_near(flour, 1, pocket + Vector2i(1, 0), 3)
	world.delivered[&"flour"] = world.delivered.get(&"flour", 0) + spilled
	check(spilled == 1, "the spilled sack is put down somewhere")
	var landed := Vector2i(-1, -1)
	for tile in world.items.tiles_with(&"flour", pocket):
		if world.items.count_at(tile) > int(before.get(tile, 0)):
			landed = tile
	check(landed != Vector2i(-1, -1) and world.generator._standable(landed),
		"spilled goods land where a worker can get alongside them")
	if landed != Vector2i(-1, -1):
		world.items.take(landed, 1)
		world.generator.consumed[&"flour"] = world.generator.consumed.get(&"flour", 0) + 1

	for index in walls:
		world.build.grid.remove(index)
	world.build._rebuild_instances(barrel)
	world.nav.refresh_area(Rect2i(pocket - Vector2i(2, 2), Vector2i(5, 5)))


## Buying land grows the plot without disturbing the tavern standing on it.
##
## The thing that would be easy to get wrong and hard to notice: BuildGrid.setup
## clears every placement, so reusing it to change the boundary would silently
## demolish the whole tavern the moment the player bought a field. Hence
## set_plot, and hence this test.
func _check_land(world: TavernWorld, scenario: Node) -> void:
	var before_plot: Rect2i = world.plot
	var before_built: int = world.build.grid.live_count()

	# The purse is genuinely short at this point in the suite, so the refusal is
	# real rather than staged -- and money moves through the ledger throughout,
	# because a test that pokes GameState.gold directly leaves the books crooked
	# and the reconciliation is the thing actually worth protecting.
	var price: int = world.parcel_price(TavernWorld.SIDE_EAST)
	check(price > 0, "land has a price")

	# Empty the purse through the books rather than by poking GameState, so the
	# refusal is real *and* the reconciliation still closes afterwards.
	var purse: int = GameState.gold
	world.ledger.spend(Ledger.Line.SUPPLIES, purse)
	check(GameState.gold == 0, "the purse is empty for the refusal")
	check(world.parcel_problem(TavernWorld.SIDE_EAST) == "Not enough gold", "a pauper cannot buy land")
	check(not world.buy_land(TavernWorld.SIDE_EAST), "and the purchase is refused")
	check(world.plot == before_plot, "a refused purchase leaves the plot alone")
	world.ledger.earn(Ledger.Line.TAKINGS, purse)

	# The river is not for sale, whatever the purse says.
	check(
		world.parcel_problem(TavernWorld.SIDE_NORTH) == "The river is in the way",
		"the plot cannot be grown over the river"
	)

	world.ledger.earn(Ledger.Line.TAKINGS, price + 40)
	var funded: int = GameState.gold
	check(world.parcel_problem(TavernWorld.SIDE_EAST) == "", "a funded tavern may buy the east field")
	check(world.buy_land(TavernWorld.SIDE_EAST), "the parcel is bought")

	check(world.plot.size.x == before_plot.size.x + TavernWorld.PARCEL_DEPTH, "the plot grew east")
	check(world.plot.size.y == before_plot.size.y, "and did not grow any other way")
	check(world.plot.position == before_plot.position, "growing east leaves the near corner where it was")
	check(GameState.gold == funded - price, "the land is paid for exactly once")

	# The bug this exists for: BuildGrid.setup() clears every placement, so
	# reusing it to move the boundary would demolish the tavern the instant the
	# player bought a field.
	check(world.build.grid.live_count() == before_built, "every building survives the purchase")
	check(world.build.grid.plot == world.plot, "the builder agrees about what is yours now")

	var again: int = world.parcel_price(TavernWorld.SIDE_EAST)
	check(again > price, "the next parcel is dearer than the last")

	var floor_def: BuildingDef = BuildingCatalog.get_def(&"wood_floor")
	var fresh := Vector2i(world.plot.end.x - 2, world.plot.position.y + 2)
	check(world.build.grid.placement_problem(floor_def, fresh, 0) == "", "the new land can be built on")
	var beyond := Vector2i(world.plot.end.x + 1, world.plot.position.y + 2)
	check(
		world.build.grid.placement_problem(floor_def, beyond, 0) == "Outside your land",
		"and the land past it still cannot"
	)

	check(scenario.reconcile(), "buying land leaves the books straight")


## The first scripted session soft-locked on its first morning: a big floor and
## forty wall clicks emptied the purse, demolishing gave nothing back, and
## nothing warned until midnight. Each of those is checked here.
func _check_build_money(world: TavernWorld) -> void:
	var build: BuildController = world.build
	# The purse is set by hand below, so the books are put back with it at the
	# end: the checks after this one reconcile against them.
	var gold_before: int = GameState.gold
	var books_before: Dictionary = world.ledger.today.duplicate()
	GameState.gold = 5000
	# Free ground inside the plot, clear of the fixture's tavern.
	var corner: Vector2i = world.plot.position + Vector2i(24, 2)
	var wall: BuildingDef = BuildingCatalog.get_def(&"timber_wall")
	build.mode = BuildController.Mode.PLACE
	build.select(wall)
	check(build.drag_shape() == BuildController.DragShape.OUTLINE, "walls are dragged, round the edge of a rectangle")
	build.update_hover(corner, true)
	check(build.begin_drag(corner), "a wall drag opens")
	build.update_hover(corner + Vector2i(4, 3), true)
	check(build.drag_tiles().size() == 14, "a five by four drag walls its edge: fourteen tiles, not twenty")
	build.update_hover(corner + Vector2i(4, 0), true)
	check(build.drag_tiles().size() == 5, "a drag one tile wide is a straight run")
	check(world.hud._build_bar._status.text.contains("leaves"), "the build bar prices the drag against the purse")
	build.cancel_drag()

	# A door goes into a wall and replaces it, refunding the unbuilt wall.
	var spot: Vector2i = corner + Vector2i(2, 6)
	build.update_hover(spot, true)
	world.commit_build_action()
	check(build.grid.placement_at(spot) >= 0 and build.grid.placements[build.grid.placement_at(spot)]["def"] == wall,
		"a single wall piece still goes down with a click")
	var after_wall: int = GameState.gold
	var door: BuildingDef = BuildingCatalog.get_def(&"door")
	build.select(door)
	build.update_hover(spot, true)
	world.commit_build_action()
	var there: int = build.grid.placement_at(spot)
	check(there >= 0 and build.grid.placements[there]["def"] == door, "a door placed on a wall replaces it")
	check(GameState.gold == after_wall + wall.cost - door.cost, "the wall it replaced is refunded in full, as a blueprint")

	# Demolishing pays back: all of a blueprint, half of a finished piece.
	var chair: BuildingDef = BuildingCatalog.get_def(&"chair")
	var seat: Vector2i = corner + Vector2i(6, 6)
	build.select(chair)
	build.update_hover(seat, true)
	world.commit_build_action()
	var refunds: int = int(world.ledger.today.get(Ledger.Line.REFUNDS, 0))
	var paid: int = GameState.gold
	check(world.demolish_at(seat) == chair.cost and GameState.gold == paid + chair.cost,
		"cancelling a blueprint refunds all of it")
	check(int(world.ledger.today.get(Ledger.Line.REFUNDS, 0)) == refunds + chair.cost, "and books it under Refunds")
	build.select(chair)
	build.update_hover(seat, true)
	world.commit_build_action()
	build.grid.mark_built(build.grid.placement_at(seat))
	check(world.demolish_at(seat) == chair.cost / 2, "demolishing a finished piece gives half back")
	world.demolish_at(spot, true)

	# The readout's three levels, and the warning said once as the purse crosses
	# what the tavern must keep in hand.
	var reserve: int = world.spending_reserve()
	check(reserve == world.order_cost(TavernWorld.STANDARD_ORDER) + world.wage_bill(),
		"the reserve is a delivery plus tonight's wages")
	GameState.gold = reserve + 100
	check(int(world.cost_note(10)[1]) == 0, "a small purchase is fine")
	check(int(world.cost_note(150)[1]) == 1, "one that leaves less than the reserve is flagged")
	check(int(world.cost_note(reserve + 200)[1]) == 2, "one the purse cannot cover is refused in the readout")
	# One gold above the line after the wall is paid for, whatever walls cost.
	GameState.gold = reserve + wall.cost - 1
	build.select(wall)
	build.update_hover(spot, true)
	world.commit_build_action()
	check(world.hud._flash_label.text.begins_with("Careful"), "spending below the reserve warns at once")
	world.demolish_at(spot, true)

	# Before the debt, not after it.
	GameState.gold = world.wage_bill() - 1
	var said: String = Trouble.diagnose(world)
	check(not said.is_empty(), "a purse short of tonight's wages is named before midnight: '%s'" % said)
	var named: bool = false
	for line in Ledger.ORDER:
		named = named or line == Ledger.Line.HIRING
	check(Ledger.ORDER.size() == Ledger.Line.size() and named, "the day's books list every line, hiring and land included")

	build.mode = BuildController.Mode.OFF
	GameState.gold = gold_before
	world.ledger.today = books_before


## C in the build bar takes back the last placement -- a whole drag at once --
## and removing anything returns half its value, goods included.
func _check_take_back_and_sell(world: TavernWorld, scenario: Node) -> void:
	var build: BuildController = world.build
	var floor_def: BuildingDef = BuildingCatalog.get_def(&"wood_floor")
	var chair: BuildingDef = BuildingCatalog.get_def(&"chair")
	# Somewhere clear: a row of four free tiles in the plot.
	var at := Vector2i(-1, -1)
	for y in range(world.plot.position.y + 1, world.plot.end.y - 1):
		for x in range(world.plot.position.x + 1, world.plot.end.x - 5):
			var free: bool = true
			for dx in range(5):
				var t := Vector2i(x + dx, y)
				free = free and build.grid.placement_at(t) < 0 and not world.items.has_stack(t) and world.nav.is_walkable(t)
			if free:
				at = Vector2i(x, y)
				break
		if at.x >= 0:
			break
	check(at.x >= 0, "the fixture has clear ground to build on")
	if at.x < 0:
		return
	# Only this check's placements: earlier checks built in the same fixture.
	build.history.clear()
	var gold: int = GameState.gold
	PlayerActions.select(world, &"wood_floor")
	var laid: int = PlayerActions.drag(world, at, at + Vector2i(2, 0))
	PlayerActions.select(world, &"chair")
	PlayerActions.click(world, at + Vector2i(4, 0))
	check(laid == 3 and GameState.gold == gold - 3 * floor_def.cost - chair.cost, "a drag of three floors and a chair go down")
	check(PlayerActions.undo(world) == chair.cost and build.grid.placement_at(at + Vector2i(4, 0)) < 0
		and build.grid.placement_at(at) >= 0, "taking back removes only the last placement, the chair, in full")
	check(PlayerActions.undo(world) == 3 * floor_def.cost and build.grid.placement_at(at) < 0
		and build.grid.placement_at(at + Vector2i(2, 0)) < 0, "and the one before it, the whole drag at once")
	check(GameState.gold == gold, "every blueprint taken back is refunded in full")
	check(PlayerActions.undo(world) == -1 and GameState.gold == gold, "with nothing left to take back, nothing more is refunded")

	# A finished piece comes back at half, as any demolition does.
	PlayerActions.click(world, at)
	build.grid.mark_built(build.grid.placement_at(at))
	check(PlayerActions.undo(world) == chair.cost / 2, "taking back a finished piece gives half back")
	# Something already gone cannot be taken back twice.
	PlayerActions.click(world, at)
	world.demolish_at(at, true)
	var before: int = GameState.gold
	PlayerActions.undo(world)
	check(GameState.gold == before and build.grid.placement_at(at) < 0, "a placement already demolished is skipped, not refunded again")
	PlayerActions.stop_building(world)

	# C is taking back in the build bar and the camera everywhere else.
	check(KeyBindings.keys_of("build_undo")[0] == KEY_C and KeyBindings.keys_of("cam_mode")[0] == KEY_C,
		"C takes back while building and switches the camera otherwise")

	# Selling goods: half the merchant's price, on its own line, off the books.
	var flour: ItemDef = ItemCatalog.get_def(&"flour")
	world.items.add(flour, 6, at, ItemWorld.BASE_QUALITY)
	world.delivered[&"flour"] = int(world.delivered.get(&"flour", 0)) + 6
	var sold_line: int = int(world.ledger.today.get(Ledger.Line.SOLD, 0))
	gold = GameState.gold
	var value: int = world.sell_stack(at)
	check(value == flour.purchase_price * 6 / 2 and GameState.gold == gold + value
		and int(world.ledger.today.get(Ledger.Line.SOLD, 0)) == sold_line + value and not world.items.has_stack(at),
		"six flour sell for half their price (%dg), under Sold stock" % value)
	check(scenario.reconcile(), "sold goods leave the books straight")
	var dishes: ItemDef = ItemCatalog.get_def(&"dirty_dishes")
	check(TavernWorld.sale_value(dishes, 4) == 0, "nobody buys dirty plates")

	# Demolish on goods lying on a floor sells the goods and leaves the floor.
	PlayerActions.select(world, &"wood_floor")
	PlayerActions.click(world, at + Vector2i(1, 0))
	var malt: ItemDef = ItemCatalog.get_def(&"malt")
	world.items.add(malt, 4, at + Vector2i(1, 0), ItemWorld.BASE_QUALITY)
	world.delivered[&"malt"] = int(world.delivered.get(&"malt", 0)) + 4
	gold = GameState.gold
	PlayerActions.demolish(world, at + Vector2i(1, 0))
	check(not world.items.has_stack(at + Vector2i(1, 0)) and build.grid.placement_at(at + Vector2i(1, 0)) >= 0
		and GameState.gold == gold + malt.purchase_price * 4 / 2,
		"demolishing loose goods sells them and leaves the floor they lay on")
	world.demolish_at(at + Vector2i(1, 0), true)
	PlayerActions.stop_building(world)
	check(scenario.reconcile(), "and the books still balance")

