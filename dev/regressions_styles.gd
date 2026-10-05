extends "res://dev/regression_group.gd"

## Styles: one piece, several looks. A look shares its piece's id, so it does
## exactly what the piece does; keeps the price and preferences it had as a
## piece of its own; survives a save, including an old save that names it by
## its old id; and can be changed where it stands. The build bar offers one
## button per piece with the looks above it. Run:
##   godot --headless --path . res://dev/regressions.tscn -- group=styles


func run() -> void:
	var world: TavernWorld = fixture_world
	_check_catalogue()
	_check_cutaway(world)
	_check_save(world)
	_check_restyle(world)
	_check_build_bar(world)


func _check_catalogue() -> void:
	var stone: BuildingDef = BuildingCatalog.get_def(&"stone_wall")
	check(stone != null and stone.id == &"timber_wall" and stone.skin == &"stone" and stone.cost == 8 and stone.encloses,
		"a stone wall is the wall's stone look, still 8g, and still encloses rooms")
	var paving: BuildingDef = BuildingCatalog.get_def(&"stone_floor")
	check(paving != null and paving.id == &"wood_floor" and paving.cost == 4 and paving.art_id() == &"stone_floor",
		"a stone floor is the floor's stone look, still 4g, drawn as stone")
	var parasol: BuildingDef = BuildingCatalog.get_def(&"parasol_table")
	check(parasol != null and parasol.id == &"table" and parasol.furniture_role == &"table" and parasol.cost == 16
		and is_equal_approx(parasol.item_surface_height, 0.78), "a parasol table is the table's parasol look: seats guests, 16g, plates at 0.78")
	check(is_equal_approx(BuildingCatalog.get_def(&"grass_overgrown").keep_off, 1.6)
		and is_equal_approx(BuildingCatalog.get_def(&"grass_tall").keep_off, 1.4),
		"overgrown grass is still skirted a little more than tall grass")
	check(BuildingCatalog.get_def(&"bed_roses").cost == 6 and BuildingCatalog.get_def(&"bed_daisy").cost == 4,
		"each flower bed keeps its own price")
	var bars: Array[BuildingDef] = BuildingCatalog.styles_of(BuildingCatalog.get_def(&"bar_table"))
	check(bars.size() == 2 and bars[1].art_id() == &"lemon_stall", "the bar comes as a timber bar or a lemonade stall")
	var stool: BuildingDef = BuildingCatalog.style(&"chair", &"stool")
	check(stool.skin == &"stool" and stool.furniture_role == &"chair", "a stool is a chair's look, and a seat")
	# Whatever the look, the piece does the same: same id, footprint, role,
	# solidity, till, storage and walls, and the same recipes.
	var same: bool = true
	var drawn: bool = true
	var library := BuildingMeshLibrary.new()
	for def in BuildingCatalog.all():
		for look in BuildingCatalog.styles_of(def):
			same = same and look.id == def.id and look.size == def.size and look.layer == def.layer \
				and look.furniture_role == def.furniture_role and look.blocks_movement == def.blocks_movement \
				and look.takes_payments == def.takes_payments and look.is_storage == def.is_storage \
				and look.encloses == def.encloses and look.links == def.links and look.category == def.category
			var mesh: Mesh = library.mesh_for(look)
			drawn = drawn and mesh != null and mesh.get_surface_count() > 0
	check(same, "no look changes what its piece does")
	check(drawn, "every look draws")
	check(BuildingCatalog.styles_of(BuildingCatalog.get_def(&"oven")).size() == 1, "a piece with one look is just itself")
	var paths: Array[BuildingDef] = BuildingCatalog.variants(BuildingCatalog.get_def(&"stone_path"))
	check(paths.size() == 2 and paths[0].id != paths[1].id, "dirt and stone paths share a button but stay separate pieces: their paces differ")


## The cutaway reaches into the builder's batches by the same key, and each
## look's batch holds exactly that look's pieces, in the order the cutaway
## walks them. (Headless runs cannot read a batch's transforms back, so the
## lowering itself is checked by eye in dev/picture_ui_check.)
func _check_cutaway(world: TavernWorld) -> void:
	var timber: BuildingDef = BuildingCatalog.style(&"timber_wall", &"timber")
	var walls: MultiMeshInstance3D = world.build._instances.get(BuildController.batch_key(timber))
	check(walls != null, "the tavern's walls are drawn in the timber look's batch")
	if walls == null:
		return
	check(walls.multimesh.instance_count == world.build.batch_entries(timber, true).size(),
		"the batch holds exactly the timber walls the cutaway walks (%d)" % walls.multimesh.instance_count)


func _check_save(world: TavernWorld) -> void:
	var table: int = _place(world, BuildingCatalog.get_def(&"parasol_table"))
	var wall: int = _place(world, BuildingCatalog.get_def(&"stone_wall"))
	check(table >= 0 and wall >= 0, "a parasol table and a stone wall go down")
	var data: Dictionary = SaveGame.capture(world)
	SaveGame.apply(world, data)
	check(_count(world, &"table", &"parasol") >= 1 and _count(world, &"timber_wall", &"stone") >= 1,
		"saved and loaded, they keep their looks")
	# A save from before styles names the old pieces, with no look.
	var old: Dictionary = data.duplicate(true)
	for row in old["buildings"]:
		if row["def"] == "table" and row.get("skin", "") == "parasol":
			row["def"] = "parasol_table"
			row.erase("skin")
		elif row["def"] == "timber_wall" and row.get("skin", "") == "stone":
			row["def"] = "stone_wall"
			row.erase("skin")
	check(SaveGame._validation_error(old).is_empty(), "an older save still validates")
	SaveGame.apply(world, old)
	check(_count(world, &"table", &"parasol") >= 1 and _count(world, &"timber_wall", &"stone") >= 1,
		"an older save's parasol table and stone wall load as those looks")


func _check_restyle(world: TavernWorld) -> void:
	var index: int = _place(world, BuildingCatalog.get_def(&"table"))
	if index < 0:
		check(false, "a plain table goes down for restyling")
		return
	GameState.gold = 100
	check(world.restyle_piece(index, BuildingCatalog.style(&"table", &"parasol")) and GameState.gold == 99,
		"a dearer look costs the difference: plain to parasol is 1g")
	check(world.build.grid.placements[index]["def"].skin == &"parasol", "and the table now stands as the parasol look")
	check(world.build._instances.has(BuildController.batch_key(BuildingCatalog.style(&"table", &"parasol"))), "each look is drawn in a batch of its own")
	check(world.restyle_piece(index, BuildingCatalog.style(&"table", &"plain")) and GameState.gold == 99,
		"a cheaper look costs nothing and gives nothing back")
	check(not world.restyle_piece(index, BuildingCatalog.get_def(&"stone_wall")), "a table cannot become a wall")
	# No round trip pays back more than was paid. The table cost 15g, the
	# parasol 1g more each time; taken down it returns its current look's price
	# (all of it as a blueprint, half once built), never more than was spent.
	var built: bool = world.build.grid.placements[index]["built"]
	world.restyle_piece(index, BuildingCatalog.style(&"table", &"parasol"))
	var parasol_back: int = TavernWorld.demolish_refund(world.build.grid.placements[index])
	world.restyle_piece(index, BuildingCatalog.style(&"table", &"plain"))
	var plain_back: int = TavernWorld.demolish_refund(world.build.grid.placements[index])
	check(parasol_back == (8 if built else 16) and plain_back == (7 if built else 15) and GameState.gold == 98,
		"restyling up and down never returns more than it cost (paid 17g; back %dg as parasol, %dg as plain)" % [parasol_back, plain_back])
	GameState.gold = 99
	world.restyle_piece(index, BuildingCatalog.style(&"table", &"plain"))
	GameState.gold = 0
	check(not world.restyle_piece(index, BuildingCatalog.style(&"table", &"parasol"))
		and world.build.grid.placements[index]["def"].skin == &"plain", "an empty purse cannot pay for a dearer look")
	GameState.gold = GameState.STARTING_GOLD


func _check_build_bar(world: TavernWorld) -> void:
	var bar: BuildBar = world.hud._build_bar
	if not bar.visible:
		world.hud._toggle_build_bar()
	bar._show_category("Garden")
	check(bar._item_buttons.size() == 9, "the Garden tab is nine buttons, not twenty-two (%d)" % bar._item_buttons.size())
	bar.choose(BuildingCatalog.get_def(&"bed_roses"))
	check(world.build.selected == BuildingCatalog.get_def(&"bed_roses"), "choosing a look selects it to place")
	check(bar._styles.visible and bar._styles_row.get_child_count() == 7, "the flower bed's seven looks show above the bar")
	bar.next_style()
	check(world.build.selected.skin == &"sunflowers", "T goes on to the next look")
	check(bar._item_buttons[&"bed_daisy"].tooltip_text == "Flower Bed (Sunflowers)", "the button shows the look it will place")
	bar.choose(BuildingCatalog.get_def(&"garden_rocks"))
	check(not bar._styles.visible, "a piece with one look shows no styles")
	world.hud._toggle_build_bar()


func _place(world: TavernWorld, def: BuildingDef) -> int:
	for y in range(world.plot.position.y + 1, world.plot.end.y - 1):
		for x in range(world.plot.position.x + 1, world.plot.end.x - 1):
			var tile := Vector2i(x, y)
			if world.build.grid.can_place(def, tile, 0) and not world.unloading_yard().has_point(tile):
				return world.build.place_programmatic(def, tile, 0, false)
	return -1


func _count(world: TavernWorld, id: StringName, skin: StringName) -> int:
	var n: int = 0
	for entry in world.build.grid.placements:
		if entry != null and entry["def"].id == id and entry["def"].skin == skin:
			n += 1
	return n
