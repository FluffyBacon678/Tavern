class_name ItemWorld
extends Node3D

## Every physical item stack in the world, and the nodes that draw them.
##
## The design notes are emphatic that goods must be *physical*: bread is not
## "+1 bread" in a global counter, it is an object sitting on a tile that a pawn
## has to walk to and carry. This is the registry that makes that true.
##
## One stack per tile, of one kind, RimWorld-style. That constraint is what
## keeps hauling meaningful -- a full storage tile is genuinely full, and
## distance to the nearest free one is a real cost.

signal stack_changed(tile: Vector2i)

## Visual copies drawn for a stack, to suggest quantity without a number.
const MAX_VISUAL_COPIES: int = 3
## What a thing is worth when nobody has done anything special to it: bought
## stock, and anything an unremarkable cook turns out. 0 is inedible, 1 is the
## best a pair of hands can manage.
const BASE_QUALITY: float = 0.5
## Passed to take() to mean "this is not a job collecting reserved goods".
const IGNORE_CLAIMS: int = -1

var terrain: TerrainMeshBuilder

## Tiles that will only take one category of goods, kept in step with what is
## built. Derived from BuildingDef.accepts_category rather than hardcoded here,
## so a future piece with the same need is a data change.
## Two separate rules share this map, because they come from different places
## and mean different things. `category` comes from the definition and is fixed
## -- a wash basin is for refuse and no player setting changes that. `ids` comes
## from the placement and is the player's own filing decision, per design notes
## section 11.
var _filters: Dictionary = {}  ## Vector2i -> { category: int, ids: Dictionary }
var _grid: BuildGrid
## Can somebody walking from the road stand beside a tile? Set by the world from
## the job generator's reach map. Unset means "do not ask", which is what a
## world with no staff and no road wants.
var standable: Callable = Callable()
var _bound: bool = false

var _stacks: Dictionary = {}  ## Vector2i -> { def: ItemDef, count: int, quality: float, node: Node3D }
var _library := ItemMeshLibrary.new()
var _material: Material
## Claims leave ingredients on the ground: saving or cancelling a manual batch
## must never need to reconstruct goods that only existed inside a panel.
var _reservations: Dictionary = {}
var _next_reservation: int = 1


func setup(p_terrain: TerrainMeshBuilder) -> void:
	terrain = p_terrain
	clear()
	if _material == null:
		_material = TavernMaterials.shared()


func clear() -> void:
	for tile in _stacks:
		var node: Node3D = _stacks[tile]["node"]
		if is_instance_valid(node):
			node.queue_free()
	_stacks.clear()
	_reservations.clear()


## Will this tile take this kind of thing at all, ignoring what is on it?
##
## Shared by accepts() and plan_placement() on purpose. They had drifted: the
## planner still compared against the old shape of `_filters`, so the moment a
## per-item whitelist was added it refused everything on a filtered tile and
## failed loudly. Two readers of one rule is exactly the seam where that happens,
## so now there is one reader.
func filter_allows(tile: Vector2i, def: ItemDef) -> bool:
	if def == null:
		return false
	if not _filters.has(tile):
		return true
	var rule: Dictionary = _filters[tile]
	# The definition's category is fixed -- a basin is for refuse whatever the
	# player ticks -- and the whitelist narrows within it. Both must pass.
	if int(rule["category"]) >= 0 and def.category != int(rule["category"]):
		return false
	var ids: Dictionary = rule["ids"]
	return ids.is_empty() or ids.has(def.id)


## Follow the build grid, so restricted tiles appear and disappear with the
## pieces that impose them. Connected rather than polled for the same reason the
## seating does it: furniture changes are rare and a stale map would silently
## misroute goods.
func bind_build(p_grid: BuildGrid) -> void:
	if p_grid == null:
		return
	# Tracked with a flag rather than is_connected(): the signals carry
	# arguments this method does not want, so what is actually connected is an
	# unbound *copy* of the callable, and is_connected would never recognise it.
	if _grid != p_grid or not _bound:
		_grid = p_grid
		_grid.placement_added.connect(_refresh_filters.unbind(1))
		_grid.placement_built.connect(_refresh_filters.unbind(1))
		_grid.placement_changed.connect(_refresh_filters.unbind(1))
		_grid.placement_removed.connect(_refresh_filters.unbind(2))
		_bound = true
	_refresh_filters()


func _refresh_filters() -> void:
	_filters.clear()
	if _grid == null:
		return
	for entry in _grid.placements:
		if entry == null:
			continue
		var category: int = entry["def"].accepts_category
		var ids: Dictionary = entry.get("filter", {})
		if not entry["def"].stores_only.is_empty():
			ids = {}
			for id in entry["def"].stores_only:
				ids[id] = true
		if category < 0 and ids.is_empty():
			continue
		for tile in entry["tiles"]:
			_filters[tile] = {"category": category, "ids": ids}
	# A completed or removed shelf/table changes where a pile rests, even if
	# nobody has touched its inventory. Move the existing visual only: filters,
	# reservations, item counts and cached mesh instances stay untouched.
	for tile in _stacks:
		var node: Node3D = _stacks[tile]["node"]
		if is_instance_valid(node):
			node.position = _visual_stack_position(tile)


func has_stack(tile: Vector2i) -> bool:
	return _stacks.has(tile)


func def_at(tile: Vector2i) -> ItemDef:
	return _stacks[tile]["def"] if _stacks.has(tile) else null


func count_at(tile: Vector2i) -> int:
	return _stacks[tile]["count"] if _stacks.has(tile) else 0


## How good the goods on this tile are. One figure for the stack, not per item:
## a stack is a pile of interchangeable things, and tracking each loaf would buy
## nothing a player could ever see.
func quality_at(tile: Vector2i) -> float:
	return _stacks[tile]["quality"] if _stacks.has(tile) else BASE_QUALITY


## Can this tile take at least one more of `def`? Either empty, or already
## holding the same kind below its stack limit.
func accepts(tile: Vector2i, def: ItemDef) -> bool:
	if def == null or (_grid != null and not _grid.in_bounds(tile)):
		return false
	if not filter_allows(tile, def):
		return false
	if not _stacks.has(tile):
		return true
	var entry: Dictionary = _stacks[tile]
	return entry["def"].id == def.id and entry["count"] < def.stack_size


## Add items to a tile, merging with what is there. Returns how many actually
## fit -- the caller is responsible for the remainder.
##
## A negative `quality` means "whatever this already is", which is what every
## caller that is merely moving goods about wants. Only the things that bring
## quality into being -- a recipe finishing, a delivery arriving -- name it.
func add(def: ItemDef, count: int, tile: Vector2i, quality: float = -1.0) -> int:
	if count <= 0 or not accepts(tile, def):
		return 0
	if _stacks.has(tile):
		var entry: Dictionary = _stacks[tile]
		if entry["def"].id != def.id:
			return 0
		var space: int = def.stack_size - entry["count"]
		var added: int = mini(space, count)
		if added <= 0:
			return 0
		# Mixing a good batch into a bad one gives a merely middling pile,
		# weighted by how much of each there is. Anything else would let a
		# single excellent loaf launder a shelf of stale ones.
		if quality >= 0.0:
			var before: int = entry["count"]
			entry["quality"] = (entry["quality"] * float(before) + quality * float(added)) / float(before + added)
		entry["count"] += added
		_refresh_visual(tile)
		stack_changed.emit(tile)
		return added

	var placed: int = mini(count, def.stack_size)
	_insert_stack(def, placed, tile, quality)
	return placed


## Loading restores existing stock, not a new delivery. A changed whitelist
## may prohibit future deliveries while goods already on the shelf remain.
func restore_stack(def: ItemDef, count: int, tile: Vector2i, quality: float) -> bool:
	if def == null or count <= 0 or count > def.stack_size or _stacks.has(tile) \
			or (_grid != null and not _grid.in_bounds(tile)):
		return false
	_insert_stack(def, count, tile, quality)
	return true


func _insert_stack(def: ItemDef, count: int, tile: Vector2i, quality: float) -> void:
	_stacks[tile] = {
		"def": def,
		"count": count,
		"quality": quality if quality >= 0.0 else BASE_QUALITY,
		"node": null,
	}
	_refresh_visual(tile)
	stack_changed.emit(tile)


## Remove up to `count` from a tile. Returns what was actually taken.
## Pass a reservation token to take *against* a claim; the default ignores
## claims entirely.
##
## Ignoring is the right default because a claim exists to stop two jobs being
## sent for the same sack, not to stop the world using its own goods. With the
## strict default, a hauler's claim made a customer unable to eat the meal on
## their own table and a cook unable to use the flour in front of them -- both
## silently, both taking zero.
func take(tile: Vector2i, count: int, reservation: int = IGNORE_CLAIMS) -> int:
	if not _stacks.has(tile):
		return 0
	var entry: Dictionary = _stacks[tile]
	var room: int = count_at(tile) if reservation == IGNORE_CLAIMS else available_at(tile, reservation)
	var taken: int = mini(maxi(count, 0), room)
	if taken <= 0:
		return 0
	if _reservations.has(reservation):
		var claimed: Dictionary = _reservations[reservation]
		claimed[tile] = maxi(0, int(claimed.get(tile, 0)) - taken)
	entry["count"] -= taken
	if entry["count"] <= 0:
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			node.queue_free()
		_stacks.erase(tile)
	else:
		_refresh_visual(tile)
	_clamp_claims(tile)
	stack_changed.emit(tile)
	return taken


## No claim on a tile may outlast the goods on it.
##
## Claims shrink when their own job collects, but a cook, a diner or the washer
## takes without a token -- correctly, since a claim exists to stop two workers
## being sent for one sack, not to stop the world using its own goods. Those
## takes used to leave the claims standing, so a tile could stay "spoken for"
## after its stock was eaten. Every later job was then refused a reservation,
## post() declined it without a word, and the kitchen sat waiting on an
## ingredient the diagnostics called ready to post.
func _clamp_claims(tile: Vector2i) -> void:
	var left: int = count_at(tile)
	for token in _reservations:
		var claim: Dictionary = _reservations[token]
		if not claim.has(tile):
			continue
		var held: int = mini(int(claim[tile]), left)
		if held <= 0:
			claim.erase(tile)
		else:
			claim[tile] = held
		left -= held


## Put goods down at or near a tile, spreading outward until they fit.
##
## The blunt version -- add() at one tile and hope -- silently destroys anything
## that does not fit, because a tile already holding a different kind accepts
## nothing. That leak is invisible in play and only shows up as ingredients
## going in and products not coming out, so every path that puts goods down
## goes through here.
func place_near(def: ItemDef, count: int, around: Vector2i, max_radius: int = 6, quality: float = -1.0, warn_if_full: bool = true) -> int:
	var remaining: int = count
	# Two passes: first only where somebody can stand beside the stack, then
	# anywhere. Goods put where no worker can get alongside them are not
	# destroyed, but they are lost to the kitchen for good -- behind a wall, or
	# in a room that has been closed off. Falling back to anywhere at all keeps
	# the older promise that nothing put down ever simply vanishes.
	for reachable_only in [true, false]:
		if remaining <= 0:
			break
		if reachable_only and not standable.is_valid():
			continue
		remaining = _spread(def, remaining, around, max_radius, quality, reachable_only)

	if remaining > 0 and warn_if_full:
		push_warning("Nowhere within %d tiles of %s to put %d %s." % [
			max_radius, around, remaining, def.display_name
		])
	return count - remaining


## One outward sweep of place_near. Returns how many are still to be placed.
func _spread(def: ItemDef, count: int, around: Vector2i, max_radius: int, quality: float, reachable_only: bool) -> int:
	var remaining: int = count
	if accepts(around, def) and (not reachable_only or standable.call(around)):
		remaining -= add(def, remaining, around, quality)

	var radius: int = 1
	while remaining > 0 and radius <= max_radius:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if remaining <= 0:
					break
				# Ring only; inner rings were covered by earlier iterations.
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var tile: Vector2i = around + Vector2i(dx, dy)
				if reachable_only and not standable.call(tile):
					continue
				if accepts(tile, def):
					remaining -= add(def, remaining, tile, quality)
		radius += 1
	return remaining


## Unclaimed stock is available to AI; a claim holder may take its own portion.
func available_at(tile: Vector2i, reservation: int = 0) -> int:
	var available: int = count_at(tile)
	for token in _reservations:
		if token != reservation:
			available -= int(_reservations[token].get(tile, 0))
	return maxi(0, available)


## Atomically claim exact physical counts. No goods move and no ledger changes.
func reserve(requests: Array) -> int:
	var claim: Dictionary = {}
	for request in requests:
		var tile: Vector2i = request["tile"]
		claim[tile] = int(claim.get(tile, 0)) + int(request["count"])
	for tile in claim:
		if claim[tile] <= 0 or available_at(tile) < claim[tile]:
			return 0
	var token: int = _next_reservation
	_next_reservation += 1
	_reservations[token] = claim
	return token


func release_reservation(token: int) -> void:
	_reservations.erase(token)


## Plan the entire output batch against the space left after consuming inputs.
## Sharing one virtual map across all products prevents two outputs both being
## promised the same last free tile. Callers commit synchronously after success.
func plan_placement(products: Array, removals: Array = []) -> Dictionary:
	var virtual: Dictionary = {}
	for tile in _stacks:
		virtual[tile] = {"def": _stacks[tile]["def"], "count": count_at(tile)}
	for removal in removals:
		var tile: Vector2i = removal["tile"]
		if virtual.has(tile):
			virtual[tile]["count"] -= int(removal["count"])
			if virtual[tile]["count"] <= 0:
				virtual.erase(tile)
	var placements: Array = []
	for product in products:
		var def: ItemDef = product["def"]
		var remaining: int = int(product["count"])
		var candidates: Array = product.get("preferred", []).duplicate()
		var around: Vector2i = product["around"]
		for radius in range(int(product.get("radius", 6)) + 1):
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if maxi(absi(dx), absi(dy)) == radius:
						var tile: Vector2i = around + Vector2i(dx, dy)
						if not candidates.has(tile):
							candidates.append(tile)
		# Preserve reachable-first spilling when a caller needs an atomic plan,
		# rather than trading the old goods-loss bug for inaccessible output.
		if product.get("prefer_reachable", false) and standable.is_valid():
			var reachable: Array = []
			var fallback: Array = []
			for tile in candidates:
				if standable.call(tile):
					reachable.append(tile)
				else:
					fallback.append(tile)
			candidates = reachable + fallback
		# Top up stacks of the same thing before claiming empty tiles. Taking
		# tiles strictly in ring order let the first product grab the only free
		# tile while a half-full stack of it sat one step further out -- and the
		# second product then had nowhere, so the batch waited "for space" that
		# was there. It also spent storage tiles the kitchen needed.
		for merging in [true, false]:
			for tile in candidates:
				if remaining <= 0:
					break
				if _grid != null and not _grid.in_bounds(tile):
					continue
				if not filter_allows(tile, def):
					continue
				var occupied: Dictionary = virtual.get(tile, {})
				if occupied.is_empty() == merging:
					continue
				if not occupied.is_empty() and occupied["def"].id != def.id:
					continue
				var count: int = int(occupied.get("count", 0))
				var placed: int = mini(remaining, def.stack_size - count)
				if placed <= 0:
					continue
				placements.append({"def": def, "count": placed, "tile": tile})
				virtual[tile] = {"def": def, "count": count + placed}
				remaining -= placed
		if remaining > 0:
			return {"ok": false, "placements": []}
	return {"ok": true, "placements": placements}


## A detached node for a pawn to carry. Built fresh rather than reparenting the
## world node, which keeps ownership simple: the world owns what is on the
## ground, the pawn owns what is in its hands.
func make_carry_node(def: ItemDef) -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _library.mesh_for(def)
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	return holder


## Tiles holding a given kind, nearest first.
func tiles_with(def_id: StringName, from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tile in _stacks:
		if _stacks[tile]["def"].id == def_id:
			out.append(tile)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chebyshev(a, from) < _chebyshev(b, from)
	)
	return out


func total_of(def_id: StringName) -> int:
	var n: int = 0
	for tile in _stacks:
		if _stacks[tile]["def"].id == def_id:
			n += _stacks[tile]["count"]
	return n


func all_tiles() -> Array:
	return _stacks.keys()


static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _refresh_visual(tile: Vector2i) -> void:
	if not _stacks.has(tile):
		return
	var entry: Dictionary = _stacks[tile]
	var node: Node3D = entry["node"]
	if is_instance_valid(node):
		node.queue_free()

	node = Node3D.new()
	node.position = _visual_stack_position(tile)

	var def: ItemDef = entry["def"]
	var mesh: ArrayMesh = _library.mesh_for(def)
	# One copy per few items, so a big stack visibly is a big stack.
	var copies: int = clampi(int(ceil(float(entry["count"]) / 4.0)), 1, MAX_VISUAL_COPIES)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = copies
	for i in range(copies):
		# Fan the copies out slightly rather than stacking them vertically, so
		# nothing floats and the pile reads from directly above.
		var a: float = float(i) * 2.2
		var offset := Vector3(cos(a) * 0.13 * float(i), 0.0, sin(a) * 0.13 * float(i))
		multi.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a), offset))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = multi
	mi.material_override = _material
	node.add_child(mi)

	add_child(node)
	entry["node"] = node


func _visual_stack_position(tile: Vector2i) -> Vector3:
	var x: float = (float(tile.x) + 0.5) * TerrainMeshBuilder.TILE
	var z: float = (float(tile.y) + 0.5) * TerrainMeshBuilder.TILE
	var support: float = _grid.visual_item_height(tile) if _grid != null else 0.0
	return Vector3(x, terrain.sample_height(x, z) + support, z)
