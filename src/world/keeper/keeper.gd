class_name Keeper
extends Node

## The keeper the player made, in the tavern in person: walked and set to work by
## the player's own clicks, RuneScape-style, instead of by the job board.
##
## Optional. A tavern runs without one; the player calls them in, and from then
## they stand in the world and are saved with it. They draw no wage and take no
## jobs. Everything they do goes through the same goods and recipes as the
## staff, so the books and the larder always reconcile: what they carry counts
## as stock, what they make is made by `perform_by_hand`, what they catch is a
## catch. That is what lets a keeper with no money and no staff still trade:
## buy lemons, carry them to the bar, press the lemonade, take the payments.

enum Do { NOTHING, WALK, TAKE, PUT, WORK, WASH }

## Seconds of work put in per second: the same as a member of staff.
const WORK_SPEED: float = 1.0
## How good the keeper's own batches are, 0..1: a touch better than ordinary
## hands, since they care.
const PERFORMANCE: float = 0.6
## Give up on reaching something after this long stood still short of it.
const STUCK_TIMEOUT: float = 4.0

## Something to tell the player ("Your hands are full").
signal said(text: String)

var world  ## TavernWorld
var pawn: Pawn
var carry_def: ItemDef = null
var carry_count: int = 0
var carry_quality: float = ItemWorld.BASE_QUALITY
## Batches made by hand, fish caught and dishes washed, for lessons and tests.
var batches: int = 0
var catches: int = 0
var washed: int = 0

var _do: int = Do.NOTHING
## The tile acted on, and the tile of it to stand beside.
var _target := Vector2i(-1, -1)
var _near := Vector2i(-1, -1)
var _index: int = -1
var _recipe: Recipe = null
var _work_left: float = 0.0
var _stuck: float = 0.0
## Run once this task is done: "press lemonade" while holding the lemons puts
## them down at the bar first.
var _then: Callable = Callable()


## Stand the keeper on `at`, dressed as the player made them.
func spawn(p_world, at: Vector2i) -> void:
	world = p_world
	name = "Keeper"
	pawn = Pawn.new()
	pawn.name = "KeeperBody"
	var holder: Node = world._find("Pawns")
	(holder if holder != null else world).add_child(pawn)
	# Its own fixed seed: calling the keeper in takes nothing from the dice the
	# simulation runs on.
	pawn.setup(world.nav, world.terrain, at, world._pawn_material, 0x6b656570)
	var profile: CharacterProfile = GameState.owner_profile
	if profile != null:
		pawn.set_appearance(profile.appearance, profile.equipped)
		if not profile.name.is_empty():
			pawn.pawn_name = profile.name
	pawn.autonomous_idle = false
	pawn.wander_area = world.plot
	pawn.set_meta("keeper", true)
	world.sim.attach(pawn)
	world.sim.attach(self)


## Leave the world, putting down whatever is held first.
func despawn() -> void:
	_drop_at_feet()
	if is_instance_valid(pawn):
		pawn.queue_free()
	pawn = null


# --- what the player asks for ------------------------------------------------------

func walk_to(tile: Vector2i) -> bool:
	_clear_task()
	if tile == pawn.tile:
		return true
	if not world.nav.is_walkable(tile):
		var near: Vector2i = world.nav.adjacent_walkable(tile, pawn.tile)
		if near == Vector2i(-1, -1):
			said.emit("You can't get there.")
			return false
		tile = near
	if not pawn.goto(tile):
		said.emit("You can't get there.")
		return false
	_do = Do.WALK
	return true


## Pick up the goods on `tile`.
func take(tile: Vector2i) -> bool:
	var def: ItemDef = world.items.def_at(tile)
	if def == null:
		return false
	if carry_count > 0 and carry_def != def:
		said.emit("Your hands are full: put down the %s first." % carry_def.display_name.to_lower())
		return false
	if carry_count >= def.stack_size:
		said.emit("You can't carry any more %s." % def.display_name.to_lower())
		return false
	return _begin(Do.TAKE, tile, [tile])


## Put what is held on `tile`: a bench, a shelf, the bar's counter, the ground.
func put(tile: Vector2i) -> bool:
	if carry_count <= 0:
		return false
	return _begin(Do.PUT, tile, _piece_tiles(tile))


## Work a recipe at the piece `index` by hand.
func work(index: int, recipe: Recipe) -> bool:
	var entry = world.build.grid.placements[index] if index >= 0 and index < world.build.grid.placements.size() else null
	if entry == null or not entry["built"]:
		return false
	# Holding one of its ingredients: put it down there first, then work.
	if carry_count > 0:
		for need in recipe.inputs:
			if need["id"] == carry_def.id:
				var first: Vector2i = entry["tiles"][0]
				if not put(first):
					return false
				_then = func() -> void: work(index, recipe)
				return true
	if not world.generator.can_perform(index, recipe):
		said.emit("%s needs %s here first." % [recipe.display_name, _ingredients_text(recipe)])
		return false
	if not _begin(Do.WORK, entry["tiles"][0], entry["tiles"]):
		return false
	_index = index
	_recipe = recipe
	_work_left = recipe.work_amount
	return true


## Wash the dirty dishes standing in the basin at `tile`.
func wash(tile: Vector2i) -> bool:
	var def: ItemDef = world.items.def_at(tile)
	if def == null or def.category != ItemDef.Category.REFUSE:
		return false
	if not _begin(Do.WASH, tile, _piece_tiles(tile)):
		return false
	_work_left = JobGenerator.WASH_WORK_PER_ITEM * float(world.items.count_at(tile))
	return true


## What the keeper is doing, for their card and the bubble.
func status_text() -> String:
	match _do:
		Do.WALK:
			return "walking"
		Do.TAKE:
			return "fetching %s" % (world.items.def_at(_target).display_name.to_lower() if world.items.def_at(_target) != null else "goods")
		Do.PUT:
			return "carrying %s" % carry_def.display_name.to_lower() if carry_def != null else "carrying"
		Do.WASH:
			return "washing up"
		Do.WORK:
			if _recipe != null:
				return "%s (%d%%)" % [_recipe.display_name.to_lower(), int(100.0 * (1.0 - _work_left / maxf(_recipe.work_amount, 0.001)))] \
					if not pawn.is_busy() else "going to %s" % _recipe.display_name.to_lower()
	return "standing by"


# --- the simulation ----------------------------------------------------------------

func sim_step(delta: float) -> void:
	if pawn == null or not is_instance_valid(pawn) or _do == Do.NOTHING:
		return
	if pawn.is_busy():
		_stuck = 0.0
		return
	if _do == Do.WALK:
		_clear_task()
		return
	# Beside it yet? Stood short (the way was blocked): try again for a while.
	if ItemWorld._chebyshev(pawn.tile, _near) > 1:
		_stuck += delta
		if _stuck < STUCK_TIMEOUT and _approach():
			return
		said.emit("You can't reach that.")
		_clear_task()
		return
	match _do:
		Do.TAKE:
			_take_now()
			_finish_task()
		Do.PUT:
			_put_now()
			_finish_task()
		Do.WORK:
			pawn.think("cook")
			_work_left -= WORK_SPEED * delta
			if _work_left <= 0.0:
				_work_now()
				_finish_task()
		Do.WASH:
			pawn.think("clean")
			_work_left -= WORK_SPEED * delta
			if _work_left <= 0.0:
				pawn.think("")
				var def: ItemDef = world.items.def_at(_target)
				if def != null and def.category == ItemDef.Category.REFUSE:
					var count: int = world.items.count_at(_target)
					world.generator._wash_up(_target, def, count)
					washed += count
				_finish_task()


func _take_now() -> void:
	var def: ItemDef = world.items.def_at(_target)
	world.board.yield_to_keeper(_target)
	var available: int = world.items.available_at(_target)
	if def == null or available <= 0:
		said.emit("There's nothing left to take there.")
		return
	if carry_count > 0 and def != carry_def:
		said.emit("Your hands are full.")
		return
	var quality: float = world.items.quality_at(_target)
	var taken: int = world.items.take(_target, mini(def.stack_size - carry_count, available))
	if taken <= 0:
		return
	carry_quality = (carry_quality * float(carry_count) + quality * float(taken)) / float(carry_count + taken)
	carry_def = def
	carry_count += taken
	pawn.carry(world.items.make_carry_node(def))


func _put_now() -> void:
	if carry_count <= 0 or carry_def == null:
		return
	var put_down: int = 0
	for tile in _put_tiles(_target):
		if carry_count <= 0:
			break
		var n: int = world.items.add(carry_def, carry_count, tile, carry_quality)
		carry_count -= n
		put_down += n
	if put_down == 0:
		said.emit("There's no room for the %s there." % carry_def.display_name.to_lower())
		return
	if carry_count <= 0:
		_clear_cargo()


func _work_now() -> void:
	pawn.think("")
	if _recipe == null:
		return
	var fish: bool = not _recipe.pick_from.is_empty()
	if not world.generator.perform_by_hand(_index, _recipe, PERFORMANCE):
		said.emit("You couldn't finish: %s." % (world.generator.completion_problem if not world.generator.completion_problem.is_empty()
			else "the ingredients are gone"))
		return
	batches += 1
	if not fish:
		said.emit("Done: %s." % _recipe.display_name.to_lower())
		return
	# The catch comes straight into empty hands; a full basket leaves it on the bank.
	catches += 1
	var station: Dictionary = world.generator.station_at(_index)
	for tile in station.get("input_tiles", []):
		var def: ItemDef = world.items.def_at(tile)
		if def != null and _recipe.pick_from.has(def.id) and (carry_count == 0 or carry_def == def):
			_target = tile
			_take_now()
			said.emit("You caught a %s." % def.display_name.to_lower())
			return
	said.emit("You caught a fish. It's on the bank.")


# --- getting there -----------------------------------------------------------------

## Start a task on `tile`, standing beside the nearest of `tiles`.
func _begin(what: int, tile: Vector2i, tiles: Array) -> bool:
	_clear_task()
	_do = what
	_target = tile
	_near = tile
	var best: int = 1 << 30
	for t in tiles:
		var d: int = ItemWorld._chebyshev(t, pawn.tile)
		if d < best:
			best = d
			_near = t
	if not _approach():
		said.emit("You can't reach that.")
		_clear_task()
		return false
	return true


## Walk to beside `_near`, or nowhere if already there.
func _approach() -> bool:
	if ItemWorld._chebyshev(pawn.tile, _near) <= 1:
		return true
	var stand: Vector2i = world.nav.adjacent_walkable(_near, pawn.tile)
	if stand == Vector2i(-1, -1) and world.nav.is_walkable(_near):
		stand = _near
	return stand != Vector2i(-1, -1) and pawn.goto(stand)


## Every tile of the piece on `tile`, or just `tile`.
func _piece_tiles(tile: Vector2i) -> Array:
	var index: int = world.build.grid.object_index_at(tile)
	if index >= 0 and world.build.grid.placements[index] != null:
		return world.build.grid.placements[index]["tiles"]
	return [tile]


## Where held goods go when put on `tile`, best first. On a bench, an
## ingredient goes where the bench uses it; on a bar, a till or a counter, a
## dish or a drink goes on the counter, for sale; anything else on the piece.
func _put_tiles(tile: Vector2i) -> Array:
	var index: int = world.build.grid.object_index_at(tile)
	if index < 0 or world.build.grid.placements[index] == null:
		return [tile]
	var entry: Dictionary = world.build.grid.placements[index]
	var def: BuildingDef = entry["def"]
	var for_sale: bool = carry_def.category == ItemDef.Category.PRODUCT and carry_def.sell_value > 0
	var counter: bool = def.furniture_role in [&"counter", &"bar"] or bool(entry.get("till", false))
	if counter and for_sale:
		return entry["tiles"]
	var station: Dictionary = world.generator.station_at(index)
	if not station.is_empty():
		var out: Array = []
		for t in station["input_tiles"]:
			if counter and entry["tiles"].has(t):
				continue
			out.append(t)
		return out
	return entry["tiles"]


func _ingredients_text(recipe: Recipe) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for need in recipe.inputs:
		var def: ItemDef = ItemCatalog.get_def(need["id"])
		parts.append("%d %s" % [int(need["count"]), def.display_name.to_lower() if def != null else String(need["id"])])
	return " and ".join(parts)


func _finish_task() -> void:
	var next: Callable = _then
	_clear_task()
	if next.is_valid():
		next.call()


func _clear_task() -> void:
	if (_do == Do.WORK or _do == Do.WASH) and pawn != null:
		pawn.think("")
	_do = Do.NOTHING
	_index = -1
	_recipe = null
	_stuck = 0.0
	_then = Callable()


func _clear_cargo() -> void:
	carry_count = 0
	carry_def = null
	carry_quality = ItemWorld.BASE_QUALITY
	if is_instance_valid(pawn):
		pawn.carry(null)


func _drop_at_feet() -> void:
	if carry_count > 0 and carry_def != null and is_instance_valid(pawn):
		carry_count -= world.items.place_near(carry_def, carry_count, pawn.tile, 6, carry_quality, false)
	if carry_count <= 0:
		_clear_cargo()


# --- saving ------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"tile": [pawn.tile.x, pawn.tile.y],
		"carry": {"id": String(carry_def.id) if carry_def != null else "", "count": carry_count, "quality": carry_quality},
	}


func restore_carry(data: Dictionary) -> void:
	var def: ItemDef = ItemCatalog.get_def(StringName(String(data.get("id", ""))))
	var count: int = clampi(int(data.get("count", 0)), 0, def.stack_size if def != null else 0)
	if def == null or count <= 0:
		return
	carry_def = def
	carry_count = count
	carry_quality = clampf(float(data.get("quality", ItemWorld.BASE_QUALITY)), 0.0, 1.0)
	pawn.carry(world.items.make_carry_node(def))
