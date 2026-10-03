class_name WorldStats
extends RefCounted

## What to say about anything the player can point at.
##
## The hover card and the inspector both read from here, and nothing else does.
## They are two views of one answer -- the card is the headline, the inspector
## the whole story -- and if each worked it out for itself they would drift
## apart, the way the job generator's `feed_problem` once disagreed with what it
## actually posted.
##
## Each answer is a list of rows. A row marked `hover` also appears on the card;
## everything appears in the inspector. Every figure is read live from the world
## at the moment of asking, so neither view can show what *was* true.
##
## Row shapes, by "t":
##   title  {text}                 the thing's name
##   sub    {text}                 what kind of thing it is
##   stat   {label, value, colour} one labelled figure
##   bar    {label, fraction, text, colour}
##   line   {text, colour}         a sentence
##   stars  {label, stars, text, colour, value}  a drawn rating; `value` is
##          the same thing in words, for anything reading rows as text
##   rule   {}                     a divider, inspector only

enum Kind { NONE, PAWN, BUILDING, ITEMS, GROUND }

const GOOD := Color("8fb46a")


## Whatever is under a point on the ground, in the order a player means it:
## people first, because they stand on everything else; then what is built on
## the tile; then loose goods; then the ground itself.
static func subject_at(world, point: Vector3) -> Dictionary:
	var person: Pawn = world.input.pawn_near(point)
	if person != null:
		return {"kind": Kind.PAWN, "pawn": person}
	var t := Vector2i(int(floor(point.x / TerrainMeshBuilder.TILE)), int(floor(point.z / TerrainMeshBuilder.TILE)))
	if world.grid != null and (t.x < 0 or t.y < 0 or t.x >= world.grid.cols or t.y >= world.grid.rows):
		return {"kind": Kind.NONE}
	var placement: int = world.build.grid.placement_at(t) if world.build != null else -1
	if placement >= 0:
		return {"kind": Kind.BUILDING, "index": placement, "tile": t}
	if world.items != null and world.items.has_stack(t):
		return {"kind": Kind.ITEMS, "tile": t}
	return {"kind": Kind.GROUND, "tile": t}


## Two subjects are the same thing -- so the card need not be rebuilt.
static func same(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("kind", Kind.NONE)) != int(b.get("kind", Kind.NONE)):
		return false
	match int(a.get("kind", Kind.NONE)):
		Kind.PAWN:
			return a["pawn"] == b["pawn"]
		Kind.BUILDING:
			return a["index"] == b["index"]
		Kind.ITEMS, Kind.GROUND:
			return a["tile"] == b["tile"]
	return true


static func rows_for(world, subject: Dictionary) -> Array:
	match int(subject.get("kind", Kind.NONE)):
		Kind.PAWN:
			# Checked here, before the typed call: a patron can leave while their
			# card is open, and passing a freed object to a `Pawn` parameter is an
			# error before the function body can ask whether it is still there.
			if not is_instance_valid(subject["pawn"]):
				return []
			return pawn_rows(world, subject["pawn"])
		Kind.BUILDING:
			return building_rows(world, subject["index"])
		Kind.ITEMS:
			return item_rows(world, subject["tile"])
		Kind.GROUND:
			return ground_rows(world, subject["tile"])
	return []


## Only the rows the hover card shows: the name, what kind of thing it is, and
## the figures marked for it. Later subtitles head sections the card leaves out.
static func headline(rows: Array) -> Array:
	var out: Array = []
	var subtitled: bool = false
	for row in rows:
		var t: String = row["t"]
		if t == "title" or row.get("hover", false):
			out.append(row)
		elif t == "sub" and not subtitled:
			subtitled = true
			out.append(row)
	return out


# --- people -----------------------------------------------------------------

static func pawn_rows(world, pawn: Pawn) -> Array:
	var rows: Array = []
	if not is_instance_valid(pawn):
		return rows
	var brain: CustomerBrain = pawn.get_node_or_null("Brain")
	if brain != null:
		return _patron_rows(world, pawn, brain)
	var worker: Worker = pawn.get_node_or_null("Worker")
	rows.append(_title(pawn.pawn_name))
	var position: String = worker.role.title if worker != null and worker.role != null else "Staff"
	rows.append(_sub("%s · %dg a day" % [position, worker.wage() if worker != null else Ledger.WAGE_PER_STAFF]))
	if worker == null:
		rows.append(_line("Standing about.", TavernTheme.PARCHMENT_DIM, true))
		return rows

	rows.append(_stat("Doing", _capitalise(worker.status_text()), TavernTheme.CANDLE, true))
	var job: Job = worker.current
	if job != null and worker.state == Worker.State.WORKING and job.work_amount > 0.0:
		rows.append(_bar("Progress", job.progress(), "%d%%" % int(job.progress() * 100.0), TavernTheme.CANDLE, true))
	if worker.carried_count() > 0 and worker.carried_def() != null:
		rows.append(_stat("Carrying", "%d× %s (%s)" % [
			worker.carried_count(), worker.carried_def().display_name.to_lower(),
			quality_word(worker.carried_quality()).to_lower()], TavernTheme.PARCHMENT, true))
	rows.append(_stat("Done today", _tally_text(worker.done_today), TavernTheme.PARCHMENT, true))
	if world.nav != null:
		rows.append(_stat("Underfoot", "%s · %s" % [surface_name(world, pawn.tile), pace_text(world.nav.cost_at(pawn.tile))]))

	rows.append(_rule())
	# First to last, which is the order they will actually pick work up in --
	# the question being asked of a worker who is doing the wrong thing.
	var on: Array = []
	var off: PackedStringArray = PackedStringArray()
	# The position's rule first: work it forbids is "never", whatever the
	# number in the grid says.
	var working: Dictionary = worker.effective_priorities()
	for work_kind in working:
		if int(working[work_kind]) == WorkType.PRIORITY_OFF:
			off.append(WorkType.display_name(work_kind).to_lower())
		else:
			on.append(work_kind)
	on.sort_custom(func(a, b) -> bool: return int(working[a]) < int(working[b]))
	var order: PackedStringArray = PackedStringArray()
	for work_kind in on:
		order.append("%s %d" % [WorkType.display_name(work_kind).to_lower(), int(working[work_kind])])
	rows.append(_stat("Works on", ", ".join(order) if not order.is_empty() else "nothing", TavernTheme.PARCHMENT_DIM))
	if not off.is_empty():
		rows.append(_stat("Never", ", ".join(off), TavernTheme.IRON.lightened(0.2)))
	return rows


static func _patron_rows(world, pawn: Pawn, brain: CustomerBrain) -> Array:
	var rows: Array = []
	rows.append(_title(pawn.pawn_name))
	# Who they are before what they are doing: the look is what the player
	# picked them out of the crowd by.
	rows.append(_sub("Patron · %s" % pawn.look if not pawn.look.is_empty() else "Patron"))
	# And what that kind of adventurer wants, which is what to act on.
	if not brain.guest_type.wants.is_empty():
		rows.append(_stat(brain.guest_type.title, brain.guest_type.wants, TavernTheme.CANDLE, true))
	if brain.booked:
		rows.append(_stat("Booked", "came for a table booked this morning", TavernTheme.PARCHMENT, true))
	rows.append(_stat("Now", _capitalise(brain.status_text()), TavernTheme.CANDLE, true))

	var patience: float = brain.patience_fraction()
	if patience >= 0.0:
		rows.append(_bar("Patience", patience, _patience_word(patience), _patience_colour(patience), true))

	if not brain.order.is_empty():
		var lines: PackedStringArray = PackedStringArray()
		for line in brain.order:
			var def: ItemDef = ItemCatalog.get_def(line["id"])
			lines.append("%s %d/%d" % [
				def.display_name.to_lower() if def != null else "?", int(line["served"]), int(line["count"])])
		rows.append(_stat("Order", " · ".join(lines), TavernTheme.PARCHMENT, true))
		var bill: int = brain.bill_so_far()
		if bill > 0:
			rows.append(_stat("Bill so far", "%dg%s, tip %dg if they left now" % [bill,
				" +2% for the booking" if brain.booked else "", brain.tip_so_far()]))

	# The review they would write this minute. Read from the same scoring as the
	# real one, so the mood can never promise what the review then denies.
	var mood: Review = brain.mood_preview()
	rows.append({"t": "stars", "label": "Mood", "stars": mood.stars, "text": "%d/100" % mood.satisfaction,
		"value": "%d stars, %d/100" % [mood.stars, mood.satisfaction],
		"colour": _mood_colour(mood.satisfaction), "hover": true})
	rows.append(_rule())
	rows.append(_sub("What they think so far"))
	for part in [Review.Part.SEATING, Review.Part.SERVICE, Review.Part.FOOD, Review.Part.CLEANLINESS]:
		if not mood.parts.has(part):
			continue
		var value: int = int(mood.parts[part])
		var verdict: String = Review.verdict(value)
		if part == Review.Part.SERVICE and brain.order.is_empty():
			verdict = "not ordered yet"
		rows.append(_stat(Review.part_name(part), verdict, _part_colour(value)))
	rows.append(_line("“%s”" % mood.quote, TavernTheme.PARCHMENT_DIM))
	return rows


# --- buildings --------------------------------------------------------------

static func building_rows(world, index: int) -> Array:
	var rows: Array = []
	if world.build == null or index < 0 or index >= world.build.grid.placements.size():
		return rows
	var entry = world.build.grid.placements[index]
	if entry == null:
		return rows
	var def: BuildingDef = entry["def"]
	rows.append(_title(def.display_name))
	rows.append(_sub("%s · %dg" % [def.category, def.cost]))

	# Worded as a place. Appended to the subtitle it read "Kitchen · 40g ·
	# Kitchen · 96 tiles", with the building's category and the room colliding.
	if world.rooms != null:
		var room_index: int = world.rooms.room_at(entry["tiles"][0])
		if room_index >= 0:
			var room: Dictionary = world.rooms.rooms[room_index]
			var room_kind = room["kind"]
			rows.append(_line("Standing in the %s (%d tiles)" % [
				(room_kind.display_name if room_kind != null else "unnamed room").to_lower(),
				room["tiles"].size()], TavernTheme.CANDLE_DIM))

	if not entry["built"]:
		var build_job: Job = _job_for(world, index, WorkType.Kind.CONSTRUCT)
		if build_job != null and build_job.claimant != null and build_job.work_done > 0.0:
			rows.append(_bar("Building", build_job.progress(), "%s, %d%%" % [
				_claimant_name(build_job), int(build_job.progress() * 100.0)], TavernTheme.CANDLE, true))
		elif build_job != null and build_job.claimant != null:
			rows.append(_stat("State", "%s is on the way" % _claimant_name(build_job), TavernTheme.CANDLE, true))
		else:
			# The queue, and who can work it: a porter building a room's worth of
			# blueprints alone looks, from outside, like nothing happening.
			var queued: int = world.board.count_of_kind(WorkType.Kind.CONSTRUCT)
			var builders: int = 0
			for worker in world.workers:
				if is_instance_valid(worker) and worker.allows(WorkType.Kind.CONSTRUCT):
					builders += 1
			rows.append(_stat("State", "Blueprint, waiting for a builder", TavernTheme.CANDLE, true))
			if builders == 0:
				rows.append(_line("Nobody on the staff can build. Hire a porter under Staff%s." % KeyBindings.hint("staff"), TavernTheme.DANGER, true))
			else:
				rows.append(_line("%d blueprint%s queued for %d builder%s. Another porter builds it sooner." % [
					queued, "" if queued == 1 else "s", builders, "" if builders == 1 else "s"],
					TavernTheme.PARCHMENT_DIM, true))
		return rows

	if def.layer == BuildingDef.Layer.FLOOR and world.nav != null:
		var cost: float = world.nav.cost_at(entry["tiles"][0])
		rows.append(_stat("Underfoot", pace_text(cost) + (", the quickest ground there is" if cost <= NavGrid.FLOOR_COST else ", slow going"),
			TavernTheme.PARCHMENT, true))

	var recipes: Array = RecipeCatalog.for_station(def.id)
	if not recipes.is_empty():
		rows.append_array(_bench_rows(world, index, entry, recipes))
	if def.is_storage:
		rows.append_array(_storage_rows(world, entry))
	rows.append_array(_seat_rows(world, entry))
	if def.accepts_category == ItemDef.Category.REFUSE:
		var waiting: int = _dirty_tables(world)
		rows.append(_stat("Tables to clear", str(waiting) if waiting > 0 else "none",
			TavernTheme.DANGER if waiting > 0 else GOOD, true))
	if def.id == &"farm_plot" and entry["built"]:
		var growth: float = Farm.growth_of(entry)
		var crop: ItemDef = ItemCatalog.get_def(Farm.crop_of(entry))
		rows.append(_stat("Crop", crop.display_name, TavernTheme.CANDLE, true))
		var state: String = "bare: a farmer will plant it" if growth < 0.0 \
			else ("ripe: a farmer will harvest %d" % int(entry.get("harvest_remaining", Farm.YIELD.get(crop.id, 1))) if growth >= 1.0 \
			else "growing, %d%%" % int(growth * 100.0))
		rows.append(_stat("Field", state, GOOD if growth >= 1.0 else TavernTheme.PARCHMENT, true))
		if entry.has("harvest_remaining"):
			rows.append(_stat("Harvest", "Make room nearby for the remaining crop", TavernTheme.CANDLE, true))
	if def.id == &"host_stand" and world.customers != null and world.clock != null:
		rows.append_array(_booking_rows(world))
	return rows


## The day's book, on the host's stand.
static func _booking_rows(world) -> Array:
	var book: Bookings = world.customers.bookings
	var rows: Array = []
	if book.taken_day == world.clock.day:
		if book.today.is_empty():
			rows.append(_stat("Bookings", "nobody booked today: a better name brings bookings", TavernTheme.PARCHMENT_DIM, true))
		else:
			rows.append(_stat("Bookings", "%d of %d guests here: %s" % [book.arrived_guests(), book.booked_guests(),
				book.describe()], GOOD, true))
	elif world.clock.hour() < Bookings.LAST_HOUR:
		rows.append(_stat("Bookings", "a host takes today's bookings here before 11:00", TavernTheme.CANDLE, true))
	else:
		rows.append(_stat("Bookings", "none taken today: nobody was hosting this morning", TavernTheme.DANGER, true))
	return rows


static func _bench_rows(world, index: int, entry: Dictionary, recipes: Array) -> Array:
	var rows: Array = []
	var cook: Job = _recipe_job(world, index)
	if cook != null and cook.claimant != null:
		if cook.work_done > 0.0:
			rows.append(_bar(cook.label, cook.progress(), "%s, %d%%" % [
				_claimant_name(cook), int(cook.progress() * 100.0)], TavernTheme.CANDLE, true))
		else:
			rows.append(_stat("Next", "%s, %s on the way" % [cook.label, _claimant_name(cook)], TavernTheme.CANDLE, true))
	else:
		rows.append(_stat("Next", "nobody working here", TavernTheme.PARCHMENT_DIM, true))

	# What is sitting ready on and beside the bench, which is what the next
	# batch will be made from.
	var station: Dictionary = {}
	for s in world.generator.built_stations():
		if s["index"] == index:
			station = s
	if not station.is_empty():
		var held: Dictionary = {}
		for tile in station["input_tiles"]:
			var item: ItemDef = world.items.def_at(tile)
			if item != null:
				held[item.display_name.to_lower()] = int(held.get(item.display_name.to_lower(), 0)) + world.items.count_at(tile)
		var parts: PackedStringArray = PackedStringArray()
		for name in held:
			parts.append("%d %s" % [held[name], name])
		rows.append(_stat("On the bench", ", ".join(parts) if not parts.is_empty() else "nothing"))

	rows.append(_rule())
	rows.append(_sub("Makes"))
	for recipe in recipes:
		var stock: int = world.items.total_of(recipe.outputs[0]["id"]) if not recipe.outputs.is_empty() else 0
		rows.append(_stat(recipe.display_name, world.bills.status_text(recipe.id, stock), TavernTheme.CANDLE_DIM, true))
		rows.append(_line(recipe.summary(), TavernTheme.IRON))
		# Shortages matter only while the bill wants more. A paused bench is
		# short of everything by design, and listing it read as a fault. The bill
		# is read, never asked: should_produce() flips its latch.
		if not station.is_empty() and _bill_wants_more(world, recipe):
			for need in recipe.inputs:
				var have: int = world.generator.count_at_station(station, need["id"])
				if have < int(need["count"]):
					var item: ItemDef = ItemCatalog.get_def(need["id"])
					var reason: String = world.generator.feed_problem(station, need["id"])
					rows.append(_line("Needs %s: %s" % [
						item.display_name.to_lower() if item != null else String(need["id"]),
						_feed_words(reason, world.stock_of(need["id"]), world, need["id"])],
						TavernTheme.CANDLE_DIM if _feed_in_hand(reason) else TavernTheme.DANGER))
	return rows


static func _bill_wants_more(world, recipe: Recipe) -> bool:
	if not world.bills.has_bill(recipe.id):
		return true
	var bill: Dictionary = world.bills.get_bill(recipe.id)
	return bool(bill.get("enabled", true)) and not bool(bill.get("paused", false))


## The job generator's reasons are written for whoever is debugging it. These
## are the same facts, in the terms of what the player can do about them.
static func _feed_words(reason: String, in_tavern: int, world = null, id: StringName = &"") -> String:
	match reason:
		"ready to post":
			return "a worker will fetch it"
		"job already posted":
			return "a worker is fetching it"
		"no source outside the bench":
			if in_tavern > 0:
				return "none within reach"
			return _where_it_comes_from(world, id)
		"every source is already claimed":
			return "all of it is spoken for"
		"only other benches have any":
			return "only other benches have any"
		"nowhere on the bench accepts it":
			return "no room left on the bench"
	return reason


## Where more of something would come from, when there is none at all. Dough
## is made, not bought -- telling the player to order supplies for it sent them
## to the merchant for something only a prep table can provide.
static func _where_it_comes_from(world, id: StringName) -> String:
	for recipe in RecipeCatalog.all():
		for out in recipe.outputs:
			if StringName(out["id"]) != id:
				continue
			var station: BuildingDef = BuildingCatalog.get_def(recipe.station_id)
			var name: String = station.display_name.to_lower() if station != null else String(recipe.station_id)
			if world != null and world.build.grid.count_built([recipe.station_id]) > 0:
				return "none made yet; the %s makes it" % name
			return "none, and it is made at a %s: build one" % name
	return "none in the tavern; order supplies"


## A shortage somebody is already dealing with, which is not a fault.
static func _feed_in_hand(reason: String) -> bool:
	return reason == "ready to post" or reason == "job already posted"


static func _storage_rows(world, entry: Dictionary) -> Array:
	var rows: Array = []
	var used: int = 0
	var holding: PackedStringArray = PackedStringArray()
	for t in entry["tiles"]:
		var held: ItemDef = world.items.def_at(t)
		if held != null:
			used += 1
			holding.append("%d %s" % [world.items.count_at(t), held.display_name.to_lower()])
	var tiles: int = entry["tiles"].size()
	rows.append(_stat("In use", "%d of %d tiles" % [used, tiles],
		TavernTheme.DANGER if used == tiles else TavernTheme.PARCHMENT, true))
	rows.append(_stat("Holding", ", ".join(holding) if not holding.is_empty() else "nothing", TavernTheme.PARCHMENT, true))
	var filter: Dictionary = entry.get("filter", {})
	var names: PackedStringArray = PackedStringArray()
	for id in filter:
		var item: ItemDef = ItemCatalog.get_def(id)
		names.append(item.display_name.to_lower() if item != null else String(id))
	rows.append(_stat("Will hold", "anything" if names.is_empty() else ", ".join(names), TavernTheme.PARCHMENT_DIM, true))
	return rows


## For a chair or a table: who is sitting there, and whether they can.
static func _seat_rows(world, entry: Dictionary) -> Array:
	var rows: Array = []
	if world.customers == null:
		return rows
	var seating: Seating = world.customers.seating
	var mine: Array[int] = []
	for i in range(seating.seats.size()):
		var seat: Dictionary = seating.seats[i]
		if entry["tiles"].has(seat["chair"]) or entry["tiles"].has(seat["table"]):
			mine.append(i)
	if mine.is_empty():
		if entry["def"].furniture_role == &"chair":
			rows.append(_stat("Seat", "not beside a table, so nobody can sit here", TavernTheme.DANGER, true))
		return rows

	var taken: int = 0
	var dirty: bool = false
	var who: PackedStringArray = PackedStringArray()
	for i in mine:
		var sitter = seating.seats[i]["taken_by"]
		if sitter != null:
			taken += 1
			if is_instance_valid(sitter) and sitter.get("pawn") != null:
				who.append(sitter.pawn.pawn_name)
		if not seating.is_usable(i):
			dirty = true
	if mine.size() == 1:
		var state: String = "free"
		if not who.is_empty():
			state = who[0]
		elif taken > 0:
			state = "taken"
		rows.append(_stat("Seat", state, TavernTheme.PARCHMENT, true))
	else:
		rows.append(_stat("Seats", "%d, %d taken" % [mine.size(), taken], TavernTheme.PARCHMENT, true))
		if not who.is_empty():
			rows.append(_stat("Sitting", ", ".join(who)))
	if dirty:
		rows.append(_stat("Table", "dirty plates, so nobody will sit here", TavernTheme.DANGER, true))
	return rows


# --- goods ------------------------------------------------------------------

static func item_rows(world, tile: Vector2i) -> Array:
	var rows: Array = []
	var def: ItemDef = world.items.def_at(tile)
	if def == null:
		return rows
	var count: int = world.items.count_at(tile)
	rows.append(_title(def.display_name))
	rows.append(_sub("%s · %d of a possible %d here" % [category_name(def.category), count, def.stack_size]))
	if def.category != ItemDef.Category.REFUSE:
		rows.append(_stat("Quality", quality_word(world.items.quality_at(tile)), TavernTheme.PARCHMENT, true))
	if def.sell_value > 0:
		rows.append(_stat("Worth", "%dg each, %dg here" % [def.sell_value, def.sell_value * count], TavernTheme.CANDLE, true))
	elif def.purchase_price > 0:
		rows.append(_stat("Cost", "%dg each from the merchant" % def.purchase_price, TavernTheme.PARCHMENT_DIM, true))
	rows.append(_stat("Where", place_of(world, tile), TavernTheme.PARCHMENT, true))
	var spoken: int = count - world.items.available_at(tile)
	if spoken > 0:
		rows.append(_stat("Spoken for", "%d, by a job already posted" % spoken))
	if world.board.has_pickup(tile):
		rows.append(_line("Somebody is coming for it.", TavernTheme.CANDLE_DIM, true))
	return rows


## Where a stack is, in the terms that decide what happens to it next.
static func place_of(world, tile: Vector2i) -> String:
	var index: int = world.build.grid.placement_at(tile)
	if index >= 0:
		var def: BuildingDef = world.build.grid.placements[index]["def"]
		if def.is_storage:
			return "filed on the %s" % def.display_name.to_lower()
		if world.customers != null:
			for seat in world.customers.seating.seats:
				if seat["table"] == tile:
					return "on a table"
		return "on the %s" % def.display_name.to_lower()
	for station in world.generator.built_stations():
		if station["input_tiles"].has(tile):
			return "by the %s, ready for it" % station["def"].display_name.to_lower()
	if world.unloading_yard().has_point(tile):
		return "in the unloading yard"
	return "loose on the ground; staff will file it away"


## Where all of one good is, for the header's tooltip: "12 beer" says nothing
## about whether it is on a shelf or stranded by a bench.
static func stock_breakdown(world, id: StringName) -> String:
	var def: ItemDef = ItemCatalog.get_def(id)
	var name: String = def.display_name if def != null else String(id)
	var places: Dictionary = {"on shelves": 0, "by the benches": 0, "on tables": 0, "lying loose": 0, "being carried": 0}
	var benches: Dictionary = {}
	for station in world.generator.built_stations():
		for tile in station["input_tiles"]:
			benches[tile] = true
	var tables: Dictionary = {}
	if world.customers != null:
		for seat in world.customers.seating.seats:
			tables[seat["table"]] = true
	var total: int = 0
	for tile in world.items.tiles_with(id, world.plot.position):
		var n: int = world.items.count_at(tile)
		total += n
		var index: int = world.build.grid.placement_at(tile)
		if index >= 0 and world.build.grid.placements[index]["def"].is_storage:
			places["on shelves"] += n
		elif tables.has(tile):
			places["on tables"] += n
		elif benches.has(tile):
			places["by the benches"] += n
		else:
			places["lying loose"] += n
	for worker in world.workers:
		if worker.carried_def() != null and worker.carried_def().id == id:
			places["being carried"] += worker.carried_count()
			total += worker.carried_count()

	var lines: PackedStringArray = PackedStringArray(["%s: %d in the tavern" % [name, total]])
	for place in places:
		if int(places[place]) > 0:
			lines.append("  %d %s" % [places[place], place])
	for station in world.generator.built_stations():
		for recipe in station["recipes"]:
			if not recipe.outputs.is_empty() and StringName(recipe.outputs[0]["id"]) == id:
				lines.append("%s at the %s: %s" % [recipe.display_name, station["def"].display_name.to_lower(),
					world.bills.status_text(recipe.id, total)])
	return "\n".join(lines)


## Today's books so far, for the purse's tooltip.
static func purse_breakdown(world) -> String:
	var lines: PackedStringArray = PackedStringArray(["%dg in the purse" % GameState.gold, "", "Today so far"])
	var any: bool = false
	for line in Ledger.ORDER:
		var amount: int = int(world.ledger.today.get(line, 0))
		if amount == 0:
			continue
		any = true
		lines.append("  %s  %s%dg" % [Ledger.line_name(line), "+" if Ledger.is_income(line) else "-", amount])
	if not any:
		lines.append("  nothing in or out yet")
	lines.append("  Running total  %s%dg" % ["+" if world.ledger.profit() >= 0 else "", world.ledger.profit()])
	if int(world.ledger.today.get(Ledger.Line.WAGES, 0)) == 0:
		lines.append("")
		lines.append("Wages due at close: %d staff, %dg" % [world.workers.size(), world.wage_bill()])
	return "\n".join(lines)


## Who is doing what, for the headcount's tooltip.
static func people_breakdown(world) -> String:
	var lines: PackedStringArray = PackedStringArray(["Staff"])
	for worker in world.workers:
		if is_instance_valid(worker) and is_instance_valid(worker.pawn):
			lines.append("  %s: %s" % [worker.pawn.pawn_name, worker.status_text()])
	if world.customers != null:
		var counts: Dictionary = {}
		for brain in world.customers.customers:
			if not is_instance_valid(brain):
				continue
			var what: String = _guest_phase(brain.state)
			counts[what] = int(counts.get(what, 0)) + 1
		lines.append("")
		if counts.is_empty():
			lines.append("No guests in")
		else:
			lines.append("Guests")
			for what in counts:
				lines.append("  %d %s" % [counts[what], what])
	return "\n".join(lines)


static func _guest_phase(state: int) -> String:
	match state:
		CustomerBrain.State.ARRIVING, CustomerBrain.State.WALKING_TO_SEAT:
			return "coming in"
		CustomerBrain.State.SEEKING_SEAT:
			return "looking for a table"
		CustomerBrain.State.ORDERING:
			return "reading the menu"
		CustomerBrain.State.WAITING_FOR_ORDER:
			return "waiting to be served"
		CustomerBrain.State.EATING, CustomerBrain.State.PAYING:
			return "eating"
	return "leaving"


# --- ground -----------------------------------------------------------------

static func ground_rows(world, tile: Vector2i) -> Array:
	var rows: Array = []
	rows.append(_title(surface_name(world, tile)))
	var mine: bool = world.plot.has_point(tile)
	rows.append(_sub("Your land" if mine else "Beyond your boundary"))
	if _is_water(world, tile):
		rows.append(_line("Nobody walks through the river.", TavernTheme.PARCHMENT_DIM, true))
		return rows
	if world.nav != null:
		rows.append(_stat("Pace", pace_text(world.nav.cost_at(tile)), TavernTheme.PARCHMENT, true))
	if world.rooms != null:
		var room_index: int = world.rooms.room_at(tile)
		if room_index >= 0:
			var room: Dictionary = world.rooms.rooms[room_index]
			var room_kind = room["kind"]
			rows.append(_stat("Room", "%s, %d tiles" % [
				room_kind.display_name if room_kind != null else "Unnamed room", room["tiles"].size()],
				TavernTheme.CANDLE_DIM, true))
	if mine and world.nav != null and world.nav.cost_at(tile) > NavGrid.FLOOR_COST:
		rows.append(_line("Floor it and staff cross it quicker.", TavernTheme.PARCHMENT_DIM))
	elif not mine:
		rows.append(_line("Buy land to build here.", TavernTheme.PARCHMENT_DIM))
	return rows


## What a piece is for, before it is built: the build bar's line for it.
##
## Derived from the definition wherever the data says it -- recipes, storage,
## washing, water, flooring -- so a new piece describes itself. Only pieces
## whose purpose lives in code rather than data get words of their own.
static func building_blurb(def: BuildingDef) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s, %dg, %d×%d" % [def.display_name, def.cost, def.size.x, def.size.y])
	var makes: PackedStringArray = PackedStringArray()
	for recipe in RecipeCatalog.for_station(def.id):
		var made: Array = recipe.outputs.duplicate()
		for id in recipe.pick_from:
			made.append({"id": id})
		for out in made:
			var item: ItemDef = ItemCatalog.get_def(out["id"])
			if item != null and not makes.has(item.display_name.to_lower()):
				makes.append(item.display_name.to_lower())
	if not makes.is_empty():
		parts.append("makes " + " and ".join(makes))
	if def.is_storage:
		parts.append("holds one kind of goods per tile")
	if def.accepts_category == ItemDef.Category.REFUSE:
		parts.append("staff wash dirty plates here")
	if def.needs_water_within > 0:
		parts.append("must stand within %d tiles of water" % def.needs_water_within)
	if def.layer == BuildingDef.Layer.FLOOR:
		parts.append("staff walk quickest on laid floor; drag to fill an area")
	match def.id:
		&"table":
			parts.append("a chair beside it becomes a seat")
		&"chair":
			parts.append("a seat only when it stands beside a table")
		&"host_stand":
			parts.append("a host greets guests here, who then wait longer for a table, and takes the day's bookings each morning until 11:00")
		&"door":
			parts.append("the way in; walls round it make a room")
		&"serving_counter":
			parts.append("the pass: cooks plate orders here and waiters take them to the nearest tables")
		&"bar_table":
			parts.append("a bar: drinks wait on its counter, its own lemonade and beer the porters bring. Guests who want only a drink, and hate to wait, fetch their own; waiters fetch from it too")
		&"parasol_table":
			parts.append("a table under a parasol: put chairs beside it, out on the lawn")
		&"garden_fence":
			parts.append("drag it round a garden, like a wall")
		&"stone_path":
			parts.append("as quick underfoot as a laid floor: the dearest path, and the quickest")
		&"garden_path":
			parts.append("a little quicker than open ground, like the road")
		&"bed_daisy", &"bed_mixed", &"bed_border":
			parts.append("for the look of the place: people step round it when they can")
		&"grass_tall", &"grass_tall_flowers", &"grass_overgrown":
			parts.append("for the look of the place: people keep to shorter grass when they can")
		&"garden_bench", &"garden_rocks", &"garden_tree", &"garden_pine", &"lantern_post":
			parts.append("for the look of the place: nobody can walk through it")
		&"farm_plot":
			parts.append("a farmer plants and harvests it; about two trading days to grow wheat for flour, or hops")
		&"well":
			parts.append("collects rain outdoors and stores water carried in; a full well stops collecting")
		&"river_pump":
			parts.append("pumps river water slowly, for the well or storage; must touch the river")
		&"fishing_spot":
			parts.append("a fisherman fishes here, on the river bank")
	if def.encloses and def.id != &"door":
		parts.append("encloses rooms")
	return " · ".join(parts)


# --- shared wording ---------------------------------------------------------

## One word for a quality figure. BASE_QUALITY, what bought stock and an
## unremarkable cook produce, is deliberately "ordinary".
static func quality_word(quality: float) -> String:
	if quality < 0.3:
		return "Poor"
	if quality < 0.45:
		return "Plain"
	if quality <= 0.55:
		return "Ordinary"
	if quality < 0.75:
		return "Good"
	return "Excellent"


## Walking pace against the quickest ground, which is laid floor.
static func pace_text(cost: float) -> String:
	return "%d%% pace" % int(round(100.0 * NavGrid.FLOOR_COST / maxf(cost, 0.01)))


static func surface_name(world, tile: Vector2i) -> String:
	if world.build != null:
		var floor_index: int = world.build.grid.floor_index_at(tile)
		if floor_index >= 0:
			return world.build.grid.placements[floor_index]["def"].display_name
	if world.grid == null or tile.x < 0 or tile.y < 0 or tile.x >= world.grid.cols or tile.y >= world.grid.rows:
		return "Ground"
	var i: int = world.grid.index(tile.x, tile.y)
	if (world.grid.water_flags[i] & TerrainGrid.FLAG_PATH) != 0:
		return "Beaten road"
	match world.grid.cell_at(tile.x, tile.y):
		TerrainGrid.Cell.WATER:
			return "River"
		TerrainGrid.Cell.DIRT:
			return "Bare earth"
		TerrainGrid.Cell.TREE:
			return "Woodland"
		TerrainGrid.Cell.ROCK:
			return "Rock"
	return "Grass"


static func category_name(category: int) -> String:
	match category:
		ItemDef.Category.INGREDIENT:
			return "Ingredient"
		ItemDef.Category.INTERMEDIATE:
			return "Half-made"
		ItemDef.Category.PRODUCT:
			return "For sale"
		ItemDef.Category.REFUSE:
			return "Washing up"
	return "Goods"


static func _is_water(world, tile: Vector2i) -> bool:
	if world.grid == null or tile.x < 0 or tile.y < 0 or tile.x >= world.grid.cols or tile.y >= world.grid.rows:
		return false
	return world.grid.cell_at(tile.x, tile.y) == TerrainGrid.Cell.WATER


static func _tally_text(done: Dictionary) -> String:
	if done.is_empty():
		return "nothing finished yet"
	var kinds: Array = done.keys()
	kinds.sort_custom(func(a, b) -> bool: return int(done[a]) > int(done[b]))
	var parts: PackedStringArray = PackedStringArray()
	for kind in kinds:
		parts.append("%d %s" % [int(done[kind]), WorkType.display_name(kind).to_lower()])
	return ", ".join(parts)


## The work posted at a bench, by the key the generator gives it rather than by
## kind: drawing water is Gather work, not Cook, and matching on kind left the
## well reading "nobody working here" with somebody at the rope.
static func _recipe_job(world, index: int, recipe_id: StringName = &"") -> Job:
	var prefix: String = "cook:%d:" % index
	var fallback: Job = null
	for job in world.board.jobs:
		if not job.key.begins_with(prefix):
			continue
		if recipe_id != &"" and job.key != prefix + String(recipe_id):
			continue
		if job.claimant != null:
			return job
		fallback = job
	return fallback


## What one recipe is doing across every bench that can make it, for the
## production panel: who is at it, what it is waiting on, or that nothing in
## the tavern can make it yet. Returns [text, colour] pairs.
static func recipe_activity(world, recipe: Recipe) -> Array:
	var out: Array = []
	var benches: Array = []
	for station in world.generator.built_stations():
		if station["def"].id == recipe.station_id:
			benches.append(station)
	if benches.is_empty():
		var def: BuildingDef = BuildingCatalog.get_def(recipe.station_id)
		# Neutral, not red: an unbuilt well is a choice, and the warning line
		# already speaks up when a missing bench is actually costing trade.
		out.append(["Nothing can make this yet: build a %s." % (def.display_name.to_lower() if def != null else String(recipe.station_id)),
			TavernTheme.PARCHMENT_DIM])
		return out
	if world.bills.has_bill(recipe.id) and not bool(world.bills.get_bill(recipe.id).get("enabled", true)):
		out.append(["Switched off.", TavernTheme.IRON.lightened(0.2)])
		return out
	for station in benches:
		var where: String = station["def"].display_name.to_lower()
		var job: Job = _recipe_job(world, station["index"], recipe.id)
		if job != null and job.claimant != null:
			if job.work_done > 0.0:
				out.append(["%s at the %s, %d%%" % [_claimant_name(job), where, int(job.progress() * 100.0)], GOOD])
			else:
				out.append(["%s is on the way to the %s" % [_claimant_name(job), where], TavernTheme.CANDLE])
			continue
		if job != null:
			out.append(["Ready at the %s, waiting for someone free to do it" % where, TavernTheme.CANDLE])
			continue
		if not _bill_wants_more(world, recipe):
			out.append(["Enough in stock; the %s is resting" % where, TavernTheme.PARCHMENT_DIM])
			continue
		var short: PackedStringArray = PackedStringArray()
		for need in recipe.inputs:
			if world.generator.count_at_station(station, need["id"]) < int(need["count"]):
				var item: ItemDef = ItemCatalog.get_def(need["id"])
				var reason: String = world.generator.feed_problem(station, need["id"])
				short.append("%s (%s)" % [item.display_name.to_lower() if item != null else String(need["id"]),
					_feed_words(reason, world.stock_of(need["id"]), world, need["id"])])
		if short.is_empty():
			out.append(["The %s is ready to start" % where, TavernTheme.CANDLE])
		else:
			out.append(["The %s needs %s" % [where, "; ".join(short)], TavernTheme.DANGER])
	return out


static func _job_for(world, subject: int, kind: int) -> Job:
	var fallback: Job = null
	for job in world.board.jobs:
		if job.subject != subject or job.kind != kind:
			continue
		if job.claimant != null:
			return job
		fallback = job
	return fallback


static func _claimant_name(job: Job) -> String:
	var claimant = job.claimant
	if claimant != null and is_instance_valid(claimant) and claimant.get("pawn") != null:
		return claimant.pawn.pawn_name
	return "somebody"


static func _dirty_tables(world) -> int:
	if world.customers == null:
		return 0
	var seating: Seating = world.customers.seating
	var tables: Dictionary = {}
	for i in range(seating.seats.size()):
		if not seating.is_usable(i):
			tables[seating.seats[i]["table"]] = true
	return tables.size()


static func _patience_word(fraction: float) -> String:
	if fraction > 0.6:
		return "content"
	if fraction > 0.3:
		return "restless"
	return "about to leave"


static func _patience_colour(fraction: float) -> Color:
	if fraction > 0.6:
		return GOOD
	if fraction > 0.3:
		return TavernTheme.CANDLE
	return TavernTheme.DANGER


static func _mood_colour(satisfaction: int) -> Color:
	if satisfaction >= 60:
		return GOOD
	if satisfaction >= 40:
		return TavernTheme.CANDLE
	return TavernTheme.DANGER


static func _part_colour(value: int) -> Color:
	if value >= 1:
		return GOOD
	if value >= -6:
		return TavernTheme.PARCHMENT_DIM
	return TavernTheme.DANGER


static func _capitalise(text: String) -> String:
	return text if text.is_empty() else text.substr(0, 1).to_upper() + text.substr(1)


# --- row builders -----------------------------------------------------------

static func _title(text: String) -> Dictionary:
	return {"t": "title", "text": text}


static func _sub(text: String) -> Dictionary:
	return {"t": "sub", "text": text}


static func _stat(label: String, value: String, colour: Color = TavernTheme.PARCHMENT_DIM, hover: bool = false) -> Dictionary:
	return {"t": "stat", "label": label, "value": value, "colour": colour, "hover": hover}


static func _bar(label: String, fraction: float, text: String, colour: Color, hover: bool = false) -> Dictionary:
	return {"t": "bar", "label": label, "fraction": clampf(fraction, 0.0, 1.0), "text": text, "colour": colour, "hover": hover}


static func _line(text: String, colour: Color = TavernTheme.PARCHMENT_DIM, hover: bool = false) -> Dictionary:
	return {"t": "line", "text": text, "colour": colour, "hover": hover}


static func _rule() -> Dictionary:
	return {"t": "rule"}
