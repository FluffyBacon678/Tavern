extends "res://dev/regression_group.gd"

## The keeper the player plays: called in, stepped in and out of, walked,
## carrying goods to a bench, making a recipe by hand, fishing with the basic
## rod, taking payments at a till, offering the right options on a click, and
## saved. Run:
##   godot --headless --path . res://dev/regressions.tscn -- group=keeper


func run() -> void:
	var world: TavernWorld = fixture_world
	_check_spawn(world)
	_check_carry(world)
	_check_work(world)
	_check_fish(world)
	_check_till(world)
	_check_save(world)
	await load("res://dev/keeper_visual_checks.gd").new().run(self, world)
	world.clear_keeper()


## Advance game time for everything on the clock, the keeper included.
func _until(world: TavernWorld, done: Callable, most_seconds: float) -> bool:
	var steps: int = int(most_seconds / SimClock.STEP)
	for i in range(steps):
		if done.call():
			return true
		world.sim.ticked.emit(SimClock.STEP)
	return done.call()


## A clear, walkable patch of the fixture, or (-1, -1).
func _clear_patch(world: TavernWorld, size: Vector2i) -> Vector2i:
	for y in range(world.plot.position.y + 2, world.plot.end.y - size.y - 1):
		for x in range(world.plot.position.x + 2, world.plot.end.x - size.x - 1):
			var free: bool = true
			for dy in range(size.y):
				for dx in range(size.x):
					var t := Vector2i(x + dx, y + dy)
					free = free and world.build.grid.placement_at(t) < 0 and world.nav.is_walkable(t) \
						and not world.items.has_stack(t)
			if free:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _check_spawn(world: TavernWorld) -> void:
	var staff: int = world.workers.size()
	var wages: int = world.wage_bill()
	check(world.spawn_keeper(), "the keeper can be called into the tavern")
	var keeper: Keeper = world.keeper
	check(keeper != null and is_instance_valid(keeper.pawn) and keeper.pawn.is_inside_tree(), "and stands in it")
	check(world.workers.size() == staff and world.wage_bill() == wages and not world.pawns.has(keeper.pawn),
		"drawing no wage, and not one of the staff")
	var profile: CharacterProfile = GameState.owner_profile
	check(profile == null or profile.name.is_empty() or keeper.pawn.pawn_name == profile.name, "named as the player made them")
	check(world.input.pawn_near(keeper.pawn.position) == keeper.pawn, "and can be clicked on like anyone else")

	var controls: KeeperControls = world.keeper_controls
	var focus: Vector3 = world.rig._focus_target
	check(controls.start() and controls.playing and world.rig.play and world.rig.follow == keeper.pawn,
		"Take control steps in: the view follows the keeper")
	controls.stop()
	check(not controls.playing and not world.rig.play and world.rig.follow == null
		and world.rig._focus_target.distance_to(focus) < 0.01, "and back out, the management view as it was")


func _check_carry(world: TavernWorld) -> void:
	var keeper: Keeper = world.keeper
	var at: Vector2i = _clear_patch(world, Vector2i(5, 3))
	check(at.x >= 0, "the fixture has room to carry things about")
	if at.x < 0:
		return
	var lemons: ItemDef = ItemCatalog.get_def(&"lemons")
	var stock: int = world.stock_of(&"lemons")
	world.items.add(lemons, 4, at)
	var options: Array = world.keeper_controls.options_for(at)
	check(not options.is_empty() and String(options[0]["text"]) == "Take Lemons",
		"a left-click on goods takes them (%s)" % (options[0]["text"] if not options.is_empty() else "nothing"))
	keeper.take(at)
	check(_until(world, func() -> bool: return keeper.carry_count > 0, 40.0) and keeper.carry_count == 4
		and keeper.carry_def == lemons and not world.items.has_stack(at), "the keeper walks over and picks them up")
	check(world.stock_of(&"lemons") == stock + 4, "and what they hold still counts as stock")
	var ground: Array = world.keeper_controls.options_for(at + Vector2i(4, 2))
	check(String(ground[0]["text"]) == "Walk here" and ground.any(func(o: Dictionary) -> bool: return String(o["text"]).begins_with("Put Lemons")),
		"a left-click on open ground walks; holding goods offers to put them down")
	keeper.put(at + Vector2i(4, 2))
	check(_until(world, func() -> bool: return keeper.carry_count == 0, 40.0) and world.items.count_at(at + Vector2i(4, 2)) == 4,
		"and puts them down where asked")
	world.items.take(at + Vector2i(4, 2), 4)


func _check_work(world: TavernWorld) -> void:
	var keeper: Keeper = world.keeper
	var at: Vector2i = _clear_patch(world, Vector2i(5, 4))
	if at.x < 0:
		return
	var bar: int = world.build.place_programmatic(BuildingCatalog.get_def(&"bar_table"), at + Vector2i(1, 1), 0, false)
	world.nav.refresh_all()
	var press: Recipe = RecipeCatalog.get_recipe(&"press_lemonade")
	var options: Array = world.keeper_controls.options_for(at + Vector2i(1, 1))
	var texts: Array = options.map(func(o: Dictionary) -> String: return String(o["text"]))
	check(texts.has(press.display_name) and texts.has("Take payments here") and texts.has("Examine Bar"),
		"the bar offers its recipe, the till and examine (%s)" % ", ".join(texts))
	check(not keeper.work(bar, press), "a recipe without its ingredients is refused, and the keeper says why")

	# Lemons in hand, water beside the bar: the keeper puts the lemons down and presses.
	world.items.add(ItemCatalog.get_def(&"water"), 1, at + Vector2i(1, 2))
	keeper.restore_carry({"id": "lemons", "count": 1, "quality": 0.5})
	var made: int = world.stock_of(&"lemonade")
	keeper.work(bar, press)
	check(_until(world, func() -> bool: return keeper.batches >= 1, 60.0), "holding the lemons, Press lemonade puts them down and presses")
	check(world.stock_of(&"lemonade") == made + 10 and world.stock_of(&"lemons") == 0 and keeper.carry_count == 0,
		"ten jugs from a crate of lemons and a barrel, by the keeper's own hand")
	set_meta("bar", bar)
	set_meta("bar_tile", at + Vector2i(1, 1))


func _check_fish(world: TavernWorld) -> void:
	var keeper: Keeper = world.keeper
	var spot: int = -1
	for tile in TestHouse._bank_spots(world, &"fishing_spot"):
		spot = world.build.place_programmatic(BuildingCatalog.get_def(&"fishing_spot"), tile, 0, false)
		if spot >= 0:
			break
	check(spot >= 0, "the fixture has a bank to fish from")
	if spot < 0:
		return
	world.nav.refresh_all()
	var tile: Vector2i = world.build.grid.placements[spot]["tiles"][0]
	var options: Array = world.keeper_controls.options_for(tile)
	check(not options.is_empty() and String(options[0]["text"]) == "Fish (basic rod)", "a left-click on a fishing spot fishes")
	keeper.work(spot, RecipeCatalog.get_recipe(&"catch_fish"))
	check(_until(world, func() -> bool: return not keeper.pawn.is_busy(), 120.0), "the keeper reaches the fishing spot before posing")
	var work_left: float = keeper._work_left
	var dice: int = world.sim_rng.state
	keeper.pawn._process(0)
	check(keeper.pawn._work_rod != null and keeper.pawn._work_rod.visible and keeper.pawn._work_mode == &"fish",
		"working the fishing spot shows a basic rod")
	check(keeper._work_left == work_left and world.sim_rng.state == dice, "showing the rod does not advance work or simulation dice")
	keeper.walk_to(keeper.pawn.tile)
	keeper.pawn._process(0)
	check(not keeper.pawn._work_rod.visible, "cancelling fishing hides the rod even while paused")
	keeper.work(spot, RecipeCatalog.get_recipe(&"catch_fish"))
	check(_until(world, func() -> bool: return keeper.catches >= 1, 120.0), "the keeper fishes with the basic rod")
	check(keeper.carry_def != null and keeper.carry_def.id in [&"trout", &"perch"], "and the catch comes into their hands")
	world.items.place_near(keeper.carry_def, keeper.carry_count, keeper.pawn.tile, 6, -1.0, false)
	keeper._clear_cargo()
	world.build.grid.remove(spot)
	world.build._rebuild_instances(BuildingCatalog.get_def(&"fishing_spot"))
	world.nav.refresh_all()


func _check_till(world: TavernWorld) -> void:
	if not has_meta("bar"):
		return
	var bar: int = get_meta("bar")
	var director: CustomerDirector = world.customers
	world.set_till(bar, true)
	check(bool(world.build.grid.placements[bar].get("till", false)) and director.tills().has(get_meta("bar_tile")),
		"Take payments here makes the bar a till")
	check(director.walkup_goods().has(&"lemonade") and director.has_bar_drinks(), "and its lemonade is for sale there")
	var table: int = -1
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["def"].furniture_role == &"table":
			table = i
			break
	if table >= 0:
		world.set_till(table, true)
		check(not world.build.grid.placements[table].has("till"), "a dining table cannot be made a till")

	# With nobody to take orders, guests buy at the till; with waiters, they are waited on.
	check(director.takes_orders(), "the fixture's waiters take orders")
	var staff: Array = director.staff
	director.staff = []
	check(not director.takes_orders(), "with nobody on the books, nobody takes orders")
	var stand: Vector2i = director.bar_stand([{"id": &"lemonade", "count": 1, "served": 0}], world.plot.position)
	check(stand.x >= 0 and director.bar_tiles_at(stand, &"lemonade").size() > 0, "and a guest goes up to the till for lemonade")
	director.staff = staff
	world.set_till(bar, false)
	check(not world.build.grid.placements[bar].has("till"), "and the till can be put away again")


func _check_save(world: TavernWorld) -> void:
	if not has_meta("bar"):
		return
	var keeper: Keeper = world.keeper
	var bar: int = get_meta("bar")
	world.set_till(bar, true)
	keeper.restore_carry({"id": "water", "count": 3, "quality": 0.5})
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world)))
	check(SaveGame._validation_error(data) == "", "a save with the keeper in it is valid: '%s'" % SaveGame._validation_error(data))
	var tilled: bool = false
	for row in data["buildings"]:
		tilled = tilled or bool(row.get("till", false))
	check(not data["keeper"].is_empty() and tilled, "and keeps the keeper and the till")
	var at := Vector2i(int(data["keeper"]["tile"][0]), int(data["keeper"]["tile"][1]))
	world.clear_keeper()
	SaveGame._apply_keeper(world, data["keeper"])
	check(world.keeper != null and world.keeper.pawn.tile == at and world.keeper.carry_count == 3
		and world.keeper.carry_def.id == &"water", "loading puts the keeper back where they stood, holding what they held")
	world.keeper._clear_cargo()
	world.set_till(bar, false)
