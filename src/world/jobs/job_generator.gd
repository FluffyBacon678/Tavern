class_name JobGenerator
extends Node

## Looks at the world and decides what work exists.
##
## Nothing else posts hauling or production jobs. Keeping the decision in one
## periodic scan -- rather than firing jobs from item and building callbacks --
## means the board reflects what the world *is* rather than the order things
## happened in, so a job cancelled or failed anywhere gets re-derived on the
## next pass without any bookkeeping.
##
## Two rules produce everything:
##   * Loose goods that are not where they belong become hauling jobs.
##   * A station whose recipe has all its inputs to hand becomes a cooking job;
##     one that is missing inputs becomes hauling jobs to bring them.
##   * Refuse becomes a trip to a wash basin, where it is destroyed.

## Seconds between scans. Frequent enough to feel responsive, rare enough that
## the O(items x storage) search never shows up in a frame.
const SCAN_INTERVAL: float = 0.7
## Most of one kind a hauler will move to storage in a single trip.
const HAUL_BATCH: int = 6
## Most dishes carried to the basin in one trip, and the seconds of scrubbing
## each one costs. Washing is deliberately not instant: if it were, one worker
## could keep any number of tables clear and the basin would be decoration.
const WASH_BATCH: int = 4
const WASH_WORK_PER_ITEM: float = 0.8

var board: JobBoard
var items: ItemWorld
var build: BuildController
var nav: NavGrid
## Standing orders. Without one, every recipe runs unlimited.
var bills: BillBook

var _timer: float = 0.0
## tile -> { item id -> true }, rebuilt each scan: goods a station is waiting for.
var _wanted: Dictionary = {}
## Job keys this scan found a reason for. Anything of ours not in here has lost
## its reason and comes off the board.
var _wanted_keys: Dictionary = {}
## Running total of everything the tavern has ever made, for reconciling the
## books against what is physically present.
## Times the hauling rule has filed away an ingredient standing on a bench that
## wants that very ingredient. Should be zero: anything above it is a tug of war
## between feeding and filing, and the kitchen is what loses.
var stolen_from_benches: int = 0
## Waiting jobs taken off the board because their goods had gone. Not an error in
## itself -- goods move -- but a large number says sources are chosen badly.
var dead_pickups_withdrawn: int = 0

## Where the staff can get to, measured from the road. Work posted anywhere else
## can never be done, and every worker who tries it wastes a trip and writes it
## off -- which is how a corner of the brewing vat with walls on two sides and
## vat on the other two collected 197 failed deliveries in one run.
##
## Rebuilt only when something is built or demolished, since nothing else
## changes who can walk where. An unset road means "do not filter", so a world
## without one behaves exactly as before.
var road_tile := Vector2i(-1, -1)
var _reach: Dictionary = {}
var _reach_dirty: bool = true
var reach_bound: bool = false
## The stations the current scan found, so the hauling pass can ask about them
## without building the list twice.
var _stations_this_scan: Array = []
## Batches the player has made by hand, for the tutorial's "do one yourself".
var manual_batches: int = 0
## The world's sim_rng: what a catch brings in. Set by the bootstrap.
var rng: RandomNumberGenerator
## Serving counter tiles, where plated orders wait for a waiter. Never hauled from.
var _pass_tiles_this_scan: Dictionary = {}
## Every item's total during a scan; see _in_stock().
var _stock_this_scan: Dictionary = {}
## Round the fishing spots. Goods picked up here are the catch, and carrying
## it in is the fisherman's job: cooks and porters stay in the tavern.
var _bank_tiles_this_scan: Dictionary = {}
var produced: Dictionary = {}
var consumed: Dictionary = {}
## Last synchronous completion failure, shown on the worker instead of losing
## the batch or pretending that a full bench has finished its work.
var completion_problem: String = ""


func setup(p_board: JobBoard, p_items: ItemWorld, p_build: BuildController, p_nav: NavGrid) -> void:
	board = p_board
	items = p_items
	build = p_build
	nav = p_nav


## Game time arrives here from the world's SimClock, in fixed steps, rather
## than per frame. The processing flag stays the switch that freezes one node --
## tests and letting staff go both use it -- and the summary's hold disables
## the node outright.
func _ready() -> void:
	set_process(true)


func sim_step(delta: float) -> void:
	if not is_processing() or not can_process():
		return
	if board == null or items == null or build == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = SCAN_INTERVAL
	scan()


func scan() -> void:
	var storage: Array[Vector2i] = _storage_tiles()
	var stations: Array = built_stations()
	_wanted.clear()
	_wanted_keys.clear()
	# Production first: it decides which loose goods are already where they are
	# wanted, which the hauling pass then leaves alone.
	_stations_this_scan = stations
	_bank_tiles_this_scan.clear()
	for station in stations:
		for recipe in station["recipes"]:
			if recipe.work_kind == WorkType.Kind.FISH:
				for tile in station["input_tiles"]:
					_bank_tiles_this_scan[tile] = true
	_pass_tiles_this_scan.clear()
	for entry in build.grid.placements:
		if entry != null and entry["built"] and entry["def"].id == &"serving_counter":
			for tile in entry["tiles"]:
				_pass_tiles_this_scan[tile] = true
	if _reach_dirty:
		_reach_dirty = false
		_reach = nav.reachable_from(road_tile) if nav != null and road_tile.x >= 0 else {}
	# Before generating anything: a job pointing at goods that have gone has to
	# come off first, or its key blocks the live replacement this scan would post.
	board.release_orphans()
	dead_pickups_withdrawn += board.withdraw_dead_pickups()
	_stock_this_scan.clear()
	for tile in items.all_tiles():
		var def: ItemDef = items.def_at(tile)
		if def != null:
			_stock_this_scan[def.id] = int(_stock_this_scan.get(def.id, 0)) + items.count_at(tile)
	_generate_production(stations)
	# Cleaning before hauling, for the same reason production comes first: a
	# stack already claimed by a wash job should not also be filed away.
	_generate_cleaning()
	_generate_hauls(storage)
	_cancel_stale_jobs()
	_stock_this_scan.clear()


## Take off the board anything this generator posted that the world no longer
## justifies.
##
## The note at the top of this file claims the board reflects what the world
## *is* rather than the order things happened in. That was only half true:
## posting was re-derived every scan, but nothing ever took a job away when its
## reason disappeared. A haul whose goods a cook had already used sat there for
## the rest of the game, failing for each worker in turn -- and worse, made
## has_pickup() lie about that tile forever, so the cleaning and feeding rules
## quietly stopped being able to use it.
##
## Claimed jobs are left alone. Somebody is partway through one, possibly with
## the goods in their hands, and they give up on their own within seconds if it
## has genuinely gone; cancelling underneath them would drop stock on the floor
## for no reason.
func _cancel_stale_jobs() -> void:
	for job in board.jobs.duplicate():
		if job.claimant != null or job.key.is_empty():
			continue
		# Plating is the customer director's, posted as cooking work; it keeps
		# its own books.
		if job.key.begins_with("plate:"):
			continue
		match job.kind:
			WorkType.Kind.HAUL, WorkType.Kind.COOK, WorkType.Kind.CLEAN, WorkType.Kind.CLEAR, \
					WorkType.Kind.GATHER, WorkType.Kind.FISH:
				if not _wanted_keys.has(job.key):
					board.cancel_key(job.key)


# --- world queries -------------------------------------------------------

func _storage_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for entry in build.grid.placements:
		if entry == null or not entry["built"] or not entry["def"].is_storage:
			continue
		for tile in entry["tiles"]:
			out.append(tile)
	return out


## Built pieces that have at least one recipe, with the tiles their ingredients
## may sit on: their own footprint plus the walkable tiles around it.
func built_stations() -> Array:
	var out: Array = []
	for i in range(build.grid.placements.size()):
		var entry = build.grid.placements[i]
		if entry == null or not entry["built"]:
			continue
		var recipes: Array = RecipeCatalog.for_station(entry["def"].id)
		if recipes.is_empty():
			continue

		var input_tiles: Array[Vector2i] = []
		for tile in entry["tiles"]:
			input_tiles.append(tile)
		for tile in entry["tiles"]:
			for d in TerrainGrid.NEIGHBOURS:
				var n: Vector2i = tile + d
				if nav != null and nav.is_walkable(n) and not input_tiles.has(n):
					input_tiles.append(n)

		out.append({
			"index": i,
			"def": entry["def"],
			"recipes": recipes,
			"tiles": entry["tiles"],
			"input_tiles": input_tiles,
			"centre": entry["tiles"][entry["tiles"].size() / 2],
		})
	return out


func count_at_station(station: Dictionary, id: StringName) -> int:
	var total: int = 0
	for tile in station["input_tiles"]:
		var def: ItemDef = items.def_at(tile)
		if def != null and def.id == id:
			total += items.count_at(tile)
	return total


# --- production ----------------------------------------------------------

func _generate_production(stations: Array) -> void:
	for station in stations:
		for recipe in station["recipes"]:
			_consider_recipe(station, recipe)


func _consider_recipe(station: Dictionary, recipe: Recipe) -> void:
	# Claim the bench's ingredients *before* consulting the bill. A paused recipe
	# should keep what is already in front of it: releasing those tiles would
	# have the hauling pass carry the flour back to storage, only to walk it out
	# again the moment the bill resumes.
	if not _makeable(station, recipe):
		return
	var missing: Array = []
	for need in recipe.inputs:
		var have: int = count_at_station(station, need["id"])
		_claim_working_set(station, need["id"], need["count"])
		if have < need["count"]:
			missing.append({"id": need["id"], "count": need["count"] - have})

	# Standing order. Bailing here stops both the cooking and the ingredient
	# hauls, which is the real saving -- a paused recipe should not have goods
	# walked across the tavern to a bench that is not going to use them.
	if bills != null and not bills.should_produce(recipe.id, _output_stock(recipe)):
		return

	if missing.is_empty():
		_post_cook_job(station, recipe)
		return

	for need in missing:
		_post_ingredient_haul(station, recipe, need["id"], need["count"])


## Could this bench make this, with what is in the tavern right now? Not if an
## ingredient is nowhere but already in front of it. A recipe that cannot be
## made fetches nothing and holds nothing: fish soup, with no fish heads in the
## house, had the oven calling for water and keeping it from the brewing vat,
## and the tavern sold no ale until a fisherman was hired.
func _makeable(station: Dictionary, recipe: Recipe) -> bool:
	for need in recipe.inputs:
		var have: int = count_at_station(station, need["id"])
		if have < int(need["count"]) and _in_stock(need["id"]) <= have:
			return false
	return true


## The tavern's whole stock of one thing. Counted once a scan: benches ask for
## every ingredient they lack, and walking every stack each time is most of a
## scan in a big hall. Outside a scan it counts live.
func _in_stock(id: StringName) -> int:
	if _stock_this_scan.is_empty():
		return items.total_of(id)
	return int(_stock_this_scan.get(id, 0))


## Protect what the bench is working with, and nothing beyond it.
##
## This used to mark *every* input tile as wanted for *every* ingredient, which
## quietly starved the station it was meant to protect. Surplus that an early
## delivery dumped around a bench became unhaulable, the free tiles filled up,
## and eventually there was nowhere to put the one ingredient the recipe was
## actually short of -- so no feed job could be posted at all.
##
## The symptom was a kitchen standing idle beside a yard full of stock, with
## every bench reporting "waiting on water" while twenty-eight barrels lay on
## the ground. Nobody would read that as "the hauling rule is being too polite",
## which is what it was.
##
## So: hold back up to what the recipe needs and let the rest be filed away.
func _claim_working_set(station: Dictionary, id: StringName, required: int) -> void:
	var held: int = 0
	for tile in station["input_tiles"]:
		if held >= required:
			return
		var def: ItemDef = items.def_at(tile)
		if def == null or def.id != id:
			continue
		if not _wanted.has(tile):
			_wanted[tile] = {}
		_wanted[tile][id] = true
		held += items.count_at(tile)


## How much of a recipe's product already exists, counted across the whole
## tavern. Multi-output recipes are judged on their first product, which is the
## one the bill is really about.
func _output_stock(recipe: Recipe) -> int:
	if not recipe.pick_from.is_empty():
		var n: int = 0
		for id in recipe.pick_from:
			n += items.total_of(id)
		return n
	if recipe.outputs.is_empty():
		return 0
	return items.total_of(recipe.outputs[0]["id"])


func _post_cook_job(station: Dictionary, recipe: Recipe) -> void:
	var key: String = "cook:%d:%s" % [station["index"], recipe.id]
	_wanted_keys[key] = true
	if board.has_key(key):
		return

	var job := Job.new()
	job.kind = recipe.work_kind
	job.target = station["centre"]
	job.work_amount = recipe.work_amount
	job.label = recipe.display_name
	job.key = key
	job.subject = station["index"]
	job.on_complete = func(j: Job) -> bool:
		var done: bool = _complete_recipe(station, recipe)
		j.blocked_reason = "" if done else completion_problem
		return done
	board.post(job)


## Consume the inputs from around the station and put the outputs down on it.
##
## Re-checked at completion rather than trusting the check made when the job was
## posted: a cook can be working for seconds while another worker walks off with
## an ingredient, and producing bread from flour that is no longer there would
## be a quiet duplication bug.
func _complete_recipe(station: Dictionary, recipe: Recipe, performance: float = -1.0) -> bool:
	completion_problem = ""
	var removals: Array = []
	var allocated: Dictionary = {}
	var quality_sum: float = 0.0
	var quality_count: int = 0
	# Plan the entire conversion before touching physical goods. Merely spilling
	# outward still loses output when every nearby tile is full.
	for need in recipe.inputs:
		var remaining: int = need["count"]
		for tile in station["input_tiles"]:
			if remaining <= 0:
				break
			var def: ItemDef = items.def_at(tile)
			if def == null or def.id != need["id"]:
				continue
			var taken: int = mini(remaining, items.count_at(tile) - int(allocated.get(tile, 0)))
			if taken <= 0:
				continue
			removals.append({"tile": tile, "count": taken, "id": def.id})
			allocated[tile] = int(allocated.get(tile, 0)) + taken
			quality_sum += items.quality_at(tile) * float(taken)
			quality_count += taken
			remaining -= taken
		if remaining > 0:
			completion_problem = "waiting for ingredients"
			return false
	var products: Array = []
	var outputs: Array = recipe.outputs
	# A catch: which fish, and how many, by the simulation's own dice.
	if not recipe.pick_from.is_empty():
		var roll: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
		var id: StringName = recipe.pick_from[roll.randi() % recipe.pick_from.size()]
		outputs = [{"id": id, "count": roll.randi_range(1, maxi(1, recipe.pick_most))}]
	for product in outputs:
		var def: ItemDef = ItemCatalog.get_def(product["id"])
		if def == null:
			completion_problem = "unknown recipe output"
			return false
		products.append({"def": def, "count": product["count"], "around": station["centre"],
			"preferred": station["input_tiles"], "prefer_reachable": true})
	var plan: Dictionary = items.plan_placement(products, removals)
	if not plan["ok"]:
		completion_problem = "waiting for space for finished goods"
		return false

	# Nothing went in, so nothing drags the result down: a recipe that gathers
	# from the world is judged on the hands alone. Averaging over zero
	# ingredients would otherwise score every bucket of water as filthy.
	var ingredients: float = ItemWorld.BASE_QUALITY
	if quality_count > 0:
		ingredients = quality_sum / float(quality_count)
	var hands: float = performance if performance >= 0.0 else ItemWorld.BASE_QUALITY
	var quality: float = clampf(ingredients * 0.5 + hands * 0.5, 0.0, 1.0)

	# No await or world mutation separates validation and commit. Cooking keeps
	# its existing precedence over haul claims; take() trims invalidated claims.
	for removal in removals:
		items.take(removal["tile"], removal["count"])
		consumed[removal["id"]] = int(consumed.get(removal["id"], 0)) + int(removal["count"])
	for placement in plan["placements"]:
		items.add(placement["def"], placement["count"], placement["tile"], quality)
	for product in outputs:
		produced[product["id"]] = int(produced.get(product["id"], 0)) + int(product["count"])
	return true


## Where a bench should fetch an ingredient from, or (-1, -1) for nowhere.
##
## Shared by posting and by feed_problem() on purpose. They had diverged: the
## diagnostic lacked two of these checks, so it reported "ready to post" for jobs
## the board would refuse, and the report said the kitchen could be fed while
## nothing was being sent.
##
## Three things disqualify a stack:
##   * It is this bench's own supply, or a cook would shuffle it round forever.
##   * Somebody is already on their way to collect it, or it is all claimed.
##   * It is another bench's working stock. Water sitting on the prep table is
##     that table's next loaf; the vat taking it meant the table then used what
##     was left, and the vat's job was left pointing at nothing. Goods a bench
##     *makes* are fair game -- dough on the prep table is exactly what the oven
##     is supposed to come and fetch.
## Can a worker coming from the road stand beside this tile?
func _standable(tile: Vector2i) -> bool:
	if _reach.is_empty():
		return true
	if _reach.has(tile):
		return true
	for d in TerrainGrid.NEIGHBOURS:
		if _reach.has(tile + d):
			return true
	return false


## The road moves when land is bought towards it, and walls change who can walk
## where. Either way the reach has to be measured again.
func invalidate_reach() -> void:
	_reach_dirty = true


func _feed_source(station: Dictionary, id: StringName) -> Vector2i:
	for tile in items.tiles_with(id, station["centre"]):
		if station["input_tiles"].has(tile) or board.has_pickup(tile):
			continue
		if items.available_at(tile) <= 0 or not _standable(tile):
			continue
		if _is_working_stock(tile, id, station):
			continue
		return tile
	return Vector2i(-1, -1)


## Is this stack an ingredient some other bench is standing ready to use?
func _is_working_stock(tile: Vector2i, id: StringName, asking: Dictionary) -> bool:
	for other in _stations_this_scan:
		if int(other["index"]) == int(asking["index"]):
			continue
		if not other["input_tiles"].has(tile):
			continue
		for recipe in other["recipes"]:
			for need in recipe.inputs:
				if need["id"] == id and _makeable(other, recipe):
					return true
	return false


func _post_ingredient_haul(station: Dictionary, recipe: Recipe, id: StringName, count: int) -> void:
	var key: String = "feed:%d:%s" % [station["index"], id]
	_wanted_keys[key] = true
	if board.has_key(key):
		return

	var def: ItemDef = ItemCatalog.get_def(id)
	if def == null:
		return

	# Take from anywhere that is not already part of this station's own supply,
	# so a cook does not shuffle ingredients around its own bench forever.
	#
	# And not from a stack somebody is already on their way to collect. The
	# hauling rule has always checked this; the feeding rule never did, so two
	# stations and a hauler would all set off for the same sack and two of them
	# would arrive to find it gone. Measured at 128 abandoned trips in a single
	# run -- the kitchen never assembled three ingredients at once and the
	# tavern starved beside a full larder.
	var source: Vector2i = _feed_source(station, id)
	if source == Vector2i(-1, -1):
		return

	var destination := Vector2i(-1, -1)
	for tile in station["input_tiles"]:
		if items.accepts(tile, def) and _standable(tile):
			destination = tile
			break
	if destination == Vector2i(-1, -1):
		return

	var job := Job.new()
	# Kitchen work, not portering: as in Prison Architect, porters bring the
	# goods in and the cooks fetch their own ingredients to the bench. With one
	# porter doing both, the cook stood idle beside a full larder.
	job.kind = WorkType.Kind.COOK
	job.pickup_tile = source
	job.target = destination
	job.carry_def = def
	job.carry_count = mini(count, items.available_at(source))
	job.work_amount = 0.0
	job.label = "Fetch %s" % def.display_name
	_if_from_the_bank(job)
	# Ahead of filing goods away. A bench that cannot cook stops the tavern; a
	# shelf that is not yet tidy does not.
	job.urgency = 1
	job.key = key
	board.post(job)


## Why a station cannot be brought an ingredient it is short of.
##
## Diagnostic only, for the dev report. "Waiting on water" with water on the
## ground has three possible causes and they want completely different fixes:
## nothing to fetch, nowhere to put it, or the job is already out.
func feed_problem(station: Dictionary, id: StringName) -> String:
	var def: ItemDef = ItemCatalog.get_def(id)
	if def == null:
		return "no such item"
	if board.has_key("feed:%d:%s" % [int(station["index"]), id]):
		return "job already posted"

	if _stations_this_scan.is_empty():
		_stations_this_scan = built_stations()
	if _feed_source(station, id) == Vector2i(-1, -1):
		# Say which reason it was, because they want different fixes.
		var anywhere: bool = false
		var claimed: bool = false
		var benched: bool = false
		for tile in items.tiles_with(id, station["centre"]):
			if station["input_tiles"].has(tile):
				continue
			anywhere = true
			if board.has_pickup(tile) or items.available_at(tile) <= 0:
				claimed = true
			elif _is_working_stock(tile, id, station):
				benched = true
		if not anywhere:
			return "no source outside the bench"
		if claimed and not benched:
			return "every source is already claimed"
		return "only other benches have any"

	for tile in station["input_tiles"]:
		if items.accepts(tile, def) and _standable(tile):
			return "ready to post"
	return "nowhere on the bench accepts it"


# --- doing it yourself ---------------------------------------------------

## The station record for one placement, or an empty Dictionary.
##
## Rebuilt on demand rather than cached: the scan already throws these away
## every pass, and a stale one would point at a bench that has since been
## demolished.
func station_at(index: int) -> Dictionary:
	for station in built_stations():
		if int(station["index"]) == index:
			return station
	return {}


## Are the ingredients for this recipe actually on the bench?
##
## Design notes section 22: the player steps in during a rush. Stepping in
## should mean doing the work faster and better than the cook would have, not
## conjuring bread out of an empty kitchen -- so the same check the AI has to
## pass applies here.
func can_perform(index: int, recipe: Recipe) -> bool:
	var station: Dictionary = station_at(index)
	if station.is_empty():
		return false
	for need in recipe.inputs:
		if count_at_station(station, need["id"]) < need["count"]:
			return false
	return true


## Do a recipe by hand. `performance` is 0..1 and becomes half of the output's
## quality, the other half being what the ingredients were worth.
func perform_by_hand(index: int, recipe: Recipe, performance: float) -> bool:
	var station: Dictionary = station_at(index)
	if station.is_empty():
		return false
	for need in recipe.inputs:
		if count_at_station(station, need["id"]) < need["count"]:
			return false

	# Keep the waiting cook's completed work if the manual attempt cannot fit.
	if not _complete_recipe(station, recipe, clampf(performance, 0.0, 1.0)):
		return false
	board.cancel_key("cook:%d:%s" % [index, recipe.id])
	manual_batches += 1
	return true


# --- cleaning ------------------------------------------------------------

## Every tile of every built wash basin.
func _wash_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for entry in build.grid.placements:
		if entry == null or not entry["built"] or entry["def"].id != &"sink":
			continue
		for tile in entry["tiles"]:
			out.append(tile)
	return out


## Turn refuse into work at a basin.
##
## Kept as its own rule rather than folded into hauling, because the destination
## differs in kind: dishes are not stock being filed away, they are a mess being
## destroyed, and only a basin destroys them. With no basin built there is no
## job at all -- which is the point. Dirty tables then accumulate and the dining
## room quietly runs out of usable seats until the player puts one in.
func _generate_cleaning() -> void:
	var basins: Array[Vector2i] = _wash_tiles()
	if basins.is_empty():
		return

	for tile in items.all_tiles():
		var def: ItemDef = items.def_at(tile)
		if def == null or def.category != ItemDef.Category.REFUSE:
			continue

		var key: String = "wash:%d,%d" % [tile.x, tile.y]
		_wanted_keys[key] = true
		if board.has_key(key) or board.has_pickup(tile):
			continue

		# Dishes already standing in a basin are washed where they are. Without
		# this they would be carried in a circle -- and a stack left behind by a
		# worker that was interrupted after putting them down but before
		# finishing would never be picked up again.
		var at_basin: bool = basins.has(tile)
		var destination: Vector2i = tile
		if not at_basin:
			destination = Vector2i(-1, -1)
			var best: int = 1 << 30
			for candidate in basins:
				if not items.accepts(candidate, def):
					continue
				var distance: int = ItemWorld._chebyshev(candidate, tile)
				if distance < best:
					best = distance
					destination = candidate
			if destination == Vector2i(-1, -1):
				continue

		var count: int = mini(WASH_BATCH, items.count_at(tile))
		var job := Job.new()
		job.target = destination
		job.key = key
		# Two jobs, not one: clearing carries the dishes to the basin and leaves
		# them there; the next scan finds them standing in it and posts the
		# washing. So a busser can clear and a cleaner wash, and neither has to
		# be able to do the other's half.
		if not at_basin:
			job.kind = WorkType.Kind.CLEAR
			job.pickup_tile = tile
			job.carry_def = def
			job.carry_count = count
			job.work_amount = 0.0
			job.label = "Clear %s" % def.display_name
			board.post(job)
			continue
		job.kind = WorkType.Kind.CLEAN
		job.work_amount = WASH_WORK_PER_ITEM * float(count)
		job.label = "Wash %s" % def.display_name
		var washed_def: ItemDef = def
		var washed_tile: Vector2i = destination
		var washed_count: int = count
		job.on_complete = func(_j: Job) -> void:
			_wash_up(washed_tile, washed_def, washed_count)
		board.post(job)


## Destroy what was washed, and book it.
##
## Re-reads the basin rather than trusting the count the job was posted with. A
## worker that could not put the dishes down drops them at its feet instead, and
## deleting goods that are not there is exactly how a reconciliation starts to
## drift -- so this counts what it actually removed, and nothing else.
func _wash_up(tile: Vector2i, def: ItemDef, count: int) -> void:
	var present: ItemDef = items.def_at(tile)
	if present == null or present.id != def.id:
		return
	var removed: int = items.take(tile, count)
	if removed > 0:
		consumed[def.id] = consumed.get(def.id, 0) + removed


# --- hauling -------------------------------------------------------------

func _generate_hauls(storage: Array[Vector2i]) -> void:
	if storage.is_empty():
		return
	_generate_restock(storage)

	for tile in items.all_tiles():
		var def: ItemDef = items.def_at(tile)
		if def == null:
			continue
		# Refuse has its own rule and its own destination. Filing dirty plates
		# onto the good shelving would be both daft and a way for them to sit
		# there forever, since nothing ever hauls anything *out* of storage.
		if def.category == ItemDef.Category.REFUSE:
			continue
		# Already in storage, or already sitting where a station wants it.
		if storage.has(tile):
			continue
		# Plated on the pass for a table. Filing it back onto a shelf would
		# undo the kitchen's work and leave the order waiting forever.
		if _pass_tiles_this_scan.has(tile):
			continue
		if _wanted.has(tile) and _wanted[tile].has(def.id):
			continue

		# Standing on a bench that uses this very ingredient, and about to be
		# filed away anyway. Counted, because the feeding rule will then bring it
		# straight back and the two will pass each other in the doorway forever.
		for station in _stations_this_scan:
			if not station["input_tiles"].has(tile):
				continue
			for recipe in station["recipes"]:
				for need in recipe.inputs:
					if need["id"] == def.id and count_at_station(station, def.id) < int(need["count"]):
						stolen_from_benches += 1

		var key: String = "haul:%d,%d" % [tile.x, tile.y]
		_wanted_keys[key] = true
		if board.has_key(key):
			continue
		# A station may already have claimed this stack as an ingredient. Feeding
		# a workstation beats filing goods away, and production is generated
		# first precisely so it gets first refusal.
		# Wholly spoken-for stacks are skipped here rather than being posted and
		# silently refused by the board every single scan.
		if board.has_pickup(tile) or items.available_at(tile) <= 0 or not _standable(tile):
			continue

		var destination := Vector2i(-1, -1)
		var best: int = 1 << 30
		for candidate in storage:
			if not items.accepts(candidate, def) or not _standable(candidate):
				continue
			var distance: int = ItemWorld._chebyshev(candidate, tile)
			if distance < best:
				best = distance
				destination = candidate
		if destination == Vector2i(-1, -1):
			continue

		var job := Job.new()
		job.kind = WorkType.Kind.HAUL
		job.pickup_tile = tile
		job.target = destination
		job.carry_def = def
		job.carry_count = mini(HAUL_BATCH, items.count_at(tile))
		job.work_amount = 0.0
		job.label = "Store %s" % def.display_name
		job.key = key
		_if_from_the_bank(job)
		board.post(job)


## The catch is carried in by whoever caught it, before they cast again. As a
## cook's fetch or a porter's haul, it had the kitchen walking to the river.
## Dedicated storage beats general storage. A barrel the player set to hold
## only water, with room, is filled from the well or from unfiltered shelves.
## Without it, rain and pumped water stayed in the well by the river and the
## cooks walked there for every barrel while the porters stood idle.
## Dedicated tiles never give their goods up, so nothing ping-pongs.
func _generate_restock(storage: Array[Vector2i]) -> void:
	var wanting: Dictionary = {}  # id -> [tiles dedicated to it with room]
	for tile in storage:
		var index: int = build.grid.object_index_at(tile)
		if index < 0:
			continue
		var entry: Dictionary = build.grid.placements[index]
		var filter: Dictionary = entry.get("filter", {})
		if filter.is_empty() or not entry["def"].stores_only.is_empty():
			continue
		for id in filter:
			var def: ItemDef = ItemCatalog.get_def(id)
			if def != null and items.accepts(tile, def) and _standable(tile):
				if not wanting.has(id):
					wanting[id] = []
				wanting[id].append(tile)
	if wanting.is_empty():
		return
	for tile in storage:
		var def: ItemDef = items.def_at(tile)
		if def == null or not wanting.has(def.id):
			continue
		var index: int = build.grid.object_index_at(tile)
		if index < 0:
			continue
		var entry: Dictionary = build.grid.placements[index]
		var dedicated: bool = not entry.get("filter", {}).is_empty() and entry["def"].stores_only.is_empty()
		if dedicated:
			continue
		var key: String = "restock:%d,%d" % [tile.x, tile.y]
		_wanted_keys[key] = true
		if board.has_key(key) or board.has_pickup(tile) or items.available_at(tile) <= 0 or not _standable(tile):
			continue
		var best := Vector2i(-1, -1)
		var best_distance: int = 1 << 30
		for target in wanting[def.id]:
			var d: int = ItemWorld._chebyshev(target, tile)
			if d < best_distance and items.accepts(target, def):
				best = target
				best_distance = d
		if best == Vector2i(-1, -1):
			continue
		var job := Job.new()
		job.kind = WorkType.Kind.HAUL
		job.pickup_tile = tile
		job.target = best
		job.carry_def = def
		job.carry_count = mini(HAUL_BATCH, items.available_at(tile))
		job.work_amount = 0.0
		job.label = "Restock %s" % def.display_name.to_lower()
		job.key = key
		board.post(job)


func _if_from_the_bank(job: Job) -> void:
	if not _bank_tiles_this_scan.has(job.pickup_tile):
		return
	job.kind = WorkType.Kind.FISH
	job.urgency = 1
	job.label = "Carry in %s" % job.carry_def.display_name.to_lower()
