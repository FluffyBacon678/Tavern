class_name SaveGame
extends RefCounted

## Writing a tavern to disk and reading it back.
##
## The notable thing here is how little needs saving. Terrain, forest and the
## plot are all pure functions of the world seed, so they are regenerated rather
## than stored. The job board is not saved *at all*: `JobGenerator` derives every
## job from world state on a timer, so restoring the buildings and the goods is
## enough for the same work to be re-derived on the first scan after loading.
## That falls straight out of the "derive, do not track" decision and is worth
## preserving -- an event-driven job system would have needed serialising, and
## half-finished jobs are exactly the sort of thing that corrupts a save.
##
## Live visits and physical cargo are retained. Work claims are derived again;
## recipe inputs remain physical until a whole batch commits atomically.
##
## JSON rather than binary: a save you can open in a text editor is worth a lot
## while the format is still moving, and these files are a few kilobytes.

const FORMAT_VERSION: int = 2
const MAX_FILE_BYTES: int = 8 * 1024 * 1024
static var last_error: String = ""
static var recovered_backup: bool = false


# --- writing -------------------------------------------------------------

static func capture(world: TavernWorld) -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"tavern_name": GameState.tavern_name,
		"world_seed": world._world_seed,
		# Which designed level this is, if any. Without it a saved demo came back
		# as a plain sandbox: no goal, no deadline, no way to win.
		"level": String(world.level.id) if world.level != null else "",
		# How far through the tutorial, so a saved lesson resumes where it was.
		"tutorial_step": world.hud.tutorial.index if world.hud != null and world.hud.tutorial != null else -1,
		# The boundary, because it is no longer a constant: land can be bought.
		# Restoring a grown tavern onto a starting-sized plot would leave half of
		# it standing outside the player's own land.
		"plot": [world.plot.position.x, world.plot.position.y, world.plot.size.x, world.plot.size.y],
		"parcels_bought": world._parcels_bought,
		"gold": GameState.gold,
		"day": world.clock.day if world.clock != null else 1,
		"clock_fraction": world.clock.fraction if world.clock != null else 0.0,
		"delivered": _stringify_keys(world.delivered),
		"buildings": _capture_buildings(world),
		"items": _capture_items(world),
		"bills": _capture_bills(world),
		"ledger": _capture_ledger(world),
		"pawns": _capture_pawns(world),
		"production": {"produced": _stringify_keys(world.generator.produced),
			"consumed": _stringify_keys(world.generator.consumed)},
		"customers": CustomerSnapshot.capture(world.customers) if world.customers != null else {},
		# Standing, but not the gossip: the score has to survive because it
		# decides tomorrow's footfall, while the review text is a day's worth of
		# feedback and has no business outliving the day.
		"reputation": world.customers.reputation.to_save() if world.customers != null else {},
	}


static func _capture_buildings(world: TavernWorld) -> Array:
	var out: Array = []
	for entry in world.build.grid.placements:
		if entry == null:
			continue
		out.append({
			"def": String(entry["def"].id),
			"x": entry["origin"].x,
			"y": entry["origin"].y,
			"rot": entry["rotation"],
			"built": entry["built"],
			# A shelf the player has dedicated to bread is a decision they made
			# about their tavern, not a detail of it. Losing it on load would be
			# as annoying as losing the shelf.
			"filter": _filter_ids(entry.get("filter", {})),
		})
	return out


static func _filter_ids(filter: Dictionary) -> Array:
	var out: Array = []
	for id in filter:
		out.append(String(id))
	out.sort()
	return out


static func _capture_items(world: TavernWorld) -> Array:
	var out: Array = []
	for tile in world.items.all_tiles():
		var def: ItemDef = world.items.def_at(tile)
		if def == null:
			continue
		out.append({
			"id": String(def.id),
			"count": world.items.count_at(tile),
			"quality": world.items.quality_at(tile),
			"x": tile.x,
			"y": tile.y,
		})
	return out


static func _capture_bills(world: TavernWorld) -> Dictionary:
	var out: Dictionary = {}
	for recipe_id in world.bills.bills:
		var bill: Dictionary = world.bills.bills[recipe_id]
		out[String(recipe_id)] = {
			"target": bill["target"],
			"resume_below": bill["resume_below"],
			"enabled": bill["enabled"],
			"paused": bill["paused"],
		}
	return out


static func _capture_ledger(world: TavernWorld) -> Dictionary:
	return {
		"today": _stringify_keys(world.ledger.today),
		"history": world.ledger.history.duplicate(true),
	}


static func _capture_pawns(world: TavernWorld) -> Array:
	var out: Array = []
	for i in range(world.pawns.size()):
		var pawn: Pawn = world.pawns[i]
		var priorities: Dictionary = {}
		var cargo: Dictionary = {}
		if i < world.workers.size():
			var worker: Worker = world.workers[i]
			for kind in worker.priorities:
				priorities[str(kind)] = worker.priorities[kind]
			if worker.carried_def() != null and worker.carried_count() > 0:
				cargo = {"id": String(worker.carried_def().id), "count": worker.carried_count(),
					"quality": worker.carried_quality()}
		out.append({
			"name": pawn.pawn_name,
			# The seed their looks and habits come from, so a reload brings back
			# the same person rather than a stranger with the same name.
			"seed": str(pawn._rng.seed),
			"x": pawn.tile.x,
			"y": pawn.tile.y,
			"priorities": priorities,
			"role": String(world.workers[i].role.id) if i < world.workers.size() and world.workers[i].role != null else "hand",
			"cargo": cargo,
		})
	return out


## JSON object keys must be strings; integer enum keys come back as strings and
## have to be converted on both sides or the round trip silently loses them.
static func _stringify_keys(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in source:
		out[str(key)] = source[key]
	return out


static func write(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GameState.save_dir()))
	var path: String = GameState.slot_path(slot)
	if path.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: cannot write '%s' (%d)." % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true


# --- reading -------------------------------------------------------------

## Load and parse a slot. Returns an empty dictionary for anything it cannot
## use, so every caller has exactly one failure case to handle.
##
## Reads the file itself rather than asking GameState for a summary: that is
## where the summary comes *from*, and routing through it made read() and
## slot_summary() call each other until the stack ran out. A save system that
## crashes on load is a special kind of bad, so the dependency runs one way now
## and only one way.
static func read(slot: int) -> Dictionary:
	var summary: Dictionary = _read_json(GameState.slot_path(slot))
	# A half-written file from a crash mid-save. The backup is the previous
	# good one, which is worth more than nothing.
	if summary.is_empty():
		summary = _read_json(GameState.slot_path(slot) + ".bak")
	if summary.is_empty():
		return {}
	if int(summary.get("version", 0)) != FORMAT_VERSION:
		# One format so far, so anything else is from a build that no longer
		# exists. Refusing beats loading a tavern with missing walls.
		push_warning("SaveGame: slot %d is format %s, expected %d; ignoring." % [
			slot, summary.get("version", "?"), FORMAT_VERSION
		])
		return {}
	return summary


static func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveGame: cannot open '%s' (%d)." % [path, FileAccess.get_open_error()])
		return {}
	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveGame: '%s' is not a save file; ignoring." % path)
		return {}
	return parsed as Dictionary


## Rebuild a world from saved data. The caller must already have run
## `generate(seed)` with the saved seed, so terrain and plot match.
static func apply(world: TavernWorld, data: Dictionary) -> void:
	GameState.tavern_name = String(data.get("tavern_name", ""))
	GameState.gold = int(data.get("gold", GameState.STARTING_GOLD))
	# Empty the room first, quietly. The furniture is rebuilt piece by piece
	# below, and any patron still seated would find their chair gone mid-way --
	# and a patron who has eaten pays on the way out, crediting money that was
	# never in the save. Loading on top of a live room did exactly that.
	if world.customers != null:
		for seat in world.customers.seating.seats:
			seat["taken_by"] = null
		world.customers.clear()
	# The level's rules, not its pieces: the buildings come back from the save.
	var level_id: String = String(data.get("level", ""))
	world.level = LevelCatalog.get_level(StringName(level_id)) if not level_id.is_empty() else null

	# The plot first: the builder is rebuilt from it, and everything after this
	# is placed relative to what the player actually owns.
	_apply_plot(world, data)

	_apply_buildings(world, data.get("buildings", []))
	_apply_items(world, data.get("items", []))
	_apply_bills(world, data.get("bills", {}))
	if world.level != null and world.level.is_tutorial and world.hud != null:
		world.hud.start_tutorial(maxi(0, int(data.get("tutorial_step", 0))))
	_apply_ledger(world, data.get("ledger", {}))
	_apply_pawns(world, data.get("pawns", []))

	if world.customers != null:
		world.customers.reputation.from_save(data.get("reputation", {}))

	world.delivered.clear()
	for id in data.get("delivered", {}):
		world.delivered[StringName(id)] = int(data["delivered"][id])

	if world.clock != null:
		world.clock.day = int(data.get("day", 1))
		world.clock.fraction = float(data.get("clock_fraction", 0.0))
		# A day that had already closed stays closed. Forcing paused = false
		# here resumed the tavern behind a reckoning that was never shown: wages
		# charged, books ruled off, and the next day already running with the
		# player never asked.
		world.clock.paused = world.clock.fraction >= 1.0

	# Walls restored means walkability changed, and seating has to be re-derived
	# from the furniture that just reappeared.
	world.nav.refresh_all()
	if world.customers != null:
		world.customers.seating.refresh()
		# Guests last: they need chairs to sit on and a nav grid to walk.
		_apply_customers(world, data)
	_apply_day_summary(world)
	world.hud.refresh_stats()


## Put the guests back where they were.
##
## A paid meal and a meal awaiting payment are different states, so a reload
## that dropped the room would either lose diners or bill them twice. The visit
## is checked before it is trusted -- a save file is data from disk, and a
## malformed one should cost an empty room rather than a broken tavern.
static func _apply_customers(world: TavernWorld, data: Dictionary) -> void:
	var guests: Variant = data.get("customers", {})
	# Says which check refused it. "Does not check out" is no use to anyone
	# trying to work out whether the save is corrupt or the validator is wrong.
	if not CustomerSnapshot.valid(guests):
		push_warning("SaveGame: the saved visit is malformed; the room starts empty.")
		guests = {}
	elif not CustomerSnapshot.valid_seats(guests as Dictionary, data.get("buildings", [])):
		push_warning("SaveGame: the saved visit claims seats that do not exist; the room starts empty.")
		guests = {}
	CustomerSnapshot.restore(world.customers, guests as Dictionary)


## Re-show the reckoning if the day had closed and nobody had dismissed it yet.
##
## Rebuilt from the last ledger entry rather than saved as a blob of text: the
## summary is a view of the books, and keeping a second copy of it in the file
## is how the two come to disagree.
static func _apply_day_summary(world: TavernWorld) -> void:
	if world.clock == null or not world.clock.paused:
		return
	if world.hud == null or world.hud._day_summary == null:
		return
	if world.ledger == null or world.ledger.history.is_empty():
		return
	var entry: Dictionary = world.ledger.history.back()
	world.hud._day_summary.show_day(
		entry,
		world.hud._tavern_name(),
		world.customers.reputation if world.customers != null else null,
		world.customers.day_reviews if world.customers != null else [] as Array[Review]
	)


## Restore a bought-up plot and re-level the land under it.
##
## Skipped entirely when the plot is the size it started at, so an ordinary
## tavern does not pay for a terrain rebuild on every load.
static func _apply_plot(world: TavernWorld, data: Dictionary) -> void:
	var raw: Array = data.get("plot", [])
	if raw.size() != 4:
		return
	var restored := Rect2i(int(raw[0]), int(raw[1]), int(raw[2]), int(raw[3]))
	world._parcels_bought = int(data.get("parcels_bought", 0))
	if restored == world.plot:
		return
	world.plot = restored
	var rng := RandomNumberGenerator.new()
	rng.seed = world._world_seed + world._parcels_bought
	world._reshape_land(rng)
	if world.customers != null:
		world.customers.plot = restored


static func _apply_buildings(world: TavernWorld, rows: Array) -> void:
	world.build.setup(world.grid.cols, world.grid.rows, world.plot, world.terrain, world.terrain.plot_height)
	for row in rows:
		var def: BuildingDef = BuildingCatalog.get_def(StringName(row["def"]))
		if def == null:
			push_warning("SaveGame: unknown building '%s'; skipped." % row["def"])
			continue
		var index: int = world.build.place_programmatic(
			def, Vector2i(int(row["x"]), int(row["y"])), int(row["rot"]), not bool(row["built"])
		)
		if index >= 0 and row.has("filter"):
			world.build.grid.set_filter(index, row["filter"])


static func _apply_items(world: TavernWorld, rows: Array) -> void:
	world.items.clear()
	for row in rows:
		var def: ItemDef = ItemCatalog.get_def(StringName(row["id"]))
		if def == null:
			push_warning("SaveGame: unknown item '%s'; skipped." % row["id"])
			continue
		world.items.place_near(
			def, int(row["count"]), Vector2i(int(row["x"]), int(row["y"])),
			6, float(row.get("quality", ItemWorld.BASE_QUALITY))
		)


static func _apply_bills(world: TavernWorld, saved: Dictionary) -> void:
	for id in saved:
		var recipe_id := StringName(id)
		if not world.bills.has_bill(recipe_id):
			continue
		var bill: Dictionary = world.bills.bills[recipe_id]
		bill["target"] = int(saved[id]["target"])
		bill["resume_below"] = int(saved[id]["resume_below"])
		bill["enabled"] = bool(saved[id]["enabled"])
		bill["paused"] = bool(saved[id]["paused"])


static func _apply_ledger(world: TavernWorld, saved: Dictionary) -> void:
	world.ledger.reset_day()
	for key in saved.get("today", {}):
		world.ledger.today[int(key)] = int(saved["today"][key])
	world.ledger.history = saved.get("history", []).duplicate(true)


static func _apply_pawns(world: TavernWorld, rows: Array) -> void:
	for pawn in world.pawns:
		pawn.queue_free()
	world.pawns.clear()
	world.workers.clear()

	var holder: Node = world.get_node_or_null("Pawns")
	if holder != null:
		holder.queue_free()
	holder = Node3D.new()
	holder.name = "Pawns"
	world.add_child(holder)

	for row in rows:
		# Saved before positions existed: a general hand, on the old wage.
		var role: StaffRole = StaffRole.of(StringName(row.get("role", "hand")))
		var looks: int = int(String(row.get("seed", ""))) if String(row.get("seed", "")).is_valid_int() else world.sim_rng.randi()
		world.bootstrap._add_pawn(holder, looks, role)
		if world.pawns.is_empty():
			continue
		var pawn: Pawn = world.pawns[world.pawns.size() - 1]
		pawn.pawn_name = String(row["name"])
		var tile := Vector2i(int(row["x"]), int(row["y"]))
		if world.nav.is_walkable(tile):
			pawn.tile = tile
			pawn.position = pawn.world_position_of(tile)
		var worker: Worker = world.workers[world.workers.size() - 1]
		for kind in row.get("priorities", {}):
			worker.priorities[int(kind)] = int(row["priorities"][kind])
		# What they were carrying. Captured on every save and, until the chaos
		# test tried saving mid-haul, never put back: a hauler with six barrels
		# of water came back empty-handed, and the barrels were simply gone.
		var cargo: Dictionary = row.get("cargo", {})
		if not cargo.is_empty():
			var def: ItemDef = ItemCatalog.get_def(StringName(cargo.get("id", "")))
			if def != null:
				worker.restore_cargo(def, int(cargo.get("count", 0)),
					float(cargo.get("quality", ItemWorld.BASE_QUALITY)))
