extends Node

## Two kinds of player, each given the sandbox's test house for five days:
##
##   profit  plays for the purse: cuts idle wages, keeps the menu stocked,
##           adds seats when guests are turned away, hires where told to.
##   garden  makes the place feel like a lemonade stand in a garden: a back
##           garden with lawns, flower beds, a path, an outdoor stall, tables
##           on the grass, lanterns and trees, and checks off a wishlist.
##   idle    does nothing at all, for comparison.
##
## Every move is a player's: blueprints the porters build and gold pays for,
## the hire and let-go buttons' calls, the production targets. Each evening
## the persona reads the day (summary, staff tallies, reviews) and acts the
## next morning. Deterministic at test speed, so personas compare fairly.
##
##   godot --headless --path . res://dev/persona_playtest.tscn -- persona=profit [days=5]
##   godot --path . --resolution 1920x1080 res://dev/persona_playtest.tscn -- persona=garden shots=<dir>

var persona: String = "idle"
var days: int = 5
var shots_dir: String = ""
var world: TavernWorld
var _rows: Array = []
var _notes: PackedStringArray = PackedStringArray()
var _outdoor_sitters: Dictionary = {}
var _garden_site := Vector2i(-1, -1)
## `watch=N`: an hourly line on day N -- staff, guests, open service jobs.
var watch_day: int = -1
var _last_hour: int = -1
var _lemonade_before: int = 0
var _advice: String = ""
## `fence=0`, `lemonade=0`: leave one part of the stand out, to measure it.
var with_fence: bool = true
var with_lemonade: bool = true
## `strip=id,id`: take those pieces out of the starting house, to measure them.
var strip: PackedStringArray = PackedStringArray()
## `sim=N`: the same house and map with other dice, for a spread of runs.
var sim_seed: int = 0
## `hire=role,role`: take these on before the first morning.
var first_hires: PackedStringArray = PackedStringArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("persona="):
			persona = arg.trim_prefix("persona=")
		elif arg.begins_with("days="):
			days = int(arg.trim_prefix("days="))
		elif arg.begins_with("watch="):
			watch_day = int(arg.trim_prefix("watch="))
		elif arg == "fence=0":
			with_fence = false
		elif arg == "lemonade=0":
			with_lemonade = false
		elif arg.begins_with("hire="):
			first_hires = arg.trim_prefix("hire=").split(",")
		elif arg.begins_with("sim="):
			sim_seed = int(arg.trim_prefix("sim="))
		elif arg.begins_with("strip="):
			strip = arg.trim_prefix("strip=").split(",")
		elif arg.begins_with("shots="):
			shots_dir = arg.trim_prefix("shots=")
	if not shots_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(shots_dir)
	if not GameState.begin_test_session():
		get_tree().quit(2)
		return
	SimWait.seed_run()
	GameState.full_house_start = true
	GameState.start_new_run("Persona %s" % persona, 493774, GameState.MAX_SLOTS - 1, true)
	world = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.configure(world)
	await get_tree().process_frame
	SimWait.hold(world)
	if sim_seed != 0:
		world.sim_rng.seed = hash(493774) ^ sim_seed
	for role in first_hires:
		var refused: String = world.hire(StringName(role))
		_note("  hired a %s before opening: %s" % [role, refused if not refused.is_empty() else "ok"])
	if not strip.is_empty():
		var gone: int = 0
		for i in range(world.build.grid.placements.size()):
			var entry = world.build.grid.placements[i]
			if entry != null and strip.has(String(entry["def"].id)):
				world.build.grid.remove(i)
				gone += 1
		for def in BuildingCatalog.all():
			world.build._rebuild_instances(def)
		world.nav.refresh_all()
		world.customers.seating.refresh()
		_note("  stripped %d pieces: %s" % [gone, ",".join(strip)])
	GameSettings.thought_bubbles = shots_dir.is_empty()
	_note("== %s: %d staff, %dg, %d seats" % [persona, world.workers.size(), GameState.gold,
		world.customers.seating.seats.size()])
	await _morning(1)
	SimWait.release(world)
	world.sim.speed = 4
	var frame: int = 0
	while world.clock.day <= days:
		await get_tree().process_frame
		frame += 1
		if frame % 20 == 0:
			_count_outdoor_sitters()
		if world.clock.day == watch_day and int(world.clock.hour()) != _last_hour:
			_last_hour = int(world.clock.hour())
			_watch_line()
		if world.simulation_paused:
			_evening()
			if world.clock.day >= days:
				break
			PlayerActions.press(world.hud._day_summary, "Open tomorrow")
			PlayerActions.press(world.hud._day_summary, "Keep trading")
			await get_tree().process_frame
			await _morning(world.clock.day)
	await _report()
	get_tree().quit()


# --- the day ------------------------------------------------------------------------

func _evening() -> void:
	var entry: Dictionary = world.ledger.history.back() if not world.ledger.history.is_empty() else {}
	var lines: Dictionary = entry.get("lines", {})
	var c: CustomerDirector = world.customers
	var stars: float = 0.0
	for review in c.day_reviews:
		stars += float(review.stars)
	var reviews: int = c.day_reviews.size()
	var idle: int = 0
	for worker in world.workers:
		if _work_done(worker) <= 2:
			idle += 1
	var row: Dictionary = {
		"day": world.clock.day, "purse": GameState.gold, "profit": int(entry.get("profit", 0)),
		"takings": int(lines.get(Ledger.Line.TAKINGS, 0)) + int(lines.get(Ledger.Line.BOOKINGS, 0)),
		"tips": int(lines.get(Ledger.Line.TIPS, 0)), "wages": int(lines.get(Ledger.Line.WAGES, 0)),
		"supplies": int(lines.get(Ledger.Line.SUPPLIES, 0)),
		"building": int(lines.get(Ledger.Line.CONSTRUCTION, 0)) + int(lines.get(Ledger.Line.HIRING, 0)),
		"served": c.served_count, "lost_seat": c.lost_no_seat, "lost_service": c.lost_no_service,
		"lost_menu": c.lost_no_menu, "stars": stars / float(maxi(reviews, 1)),
		"reputation": c.reputation.score, "staff": world.workers.size(), "idle": idle,
		"outdoors": _outdoor_sitters.size(),
		"lemonade": int(c.consumed.get(&"lemonade", 0)) - _lemonade_before,
	}
	_lemonade_before = int(c.consumed.get(&"lemonade", 0))
	_rows.append(row)
	_outdoor_sitters.clear()
	_note("DAY %d  profit %+5dg  purse %5dg  served %2d  lost %d seat/%d service/%d menu  %.1f stars  rep %d  staff %d (%d idle)  outdoors %d  lemonade %d" % [
		row["day"], row["profit"], row["purse"], row["served"], row["lost_seat"], row["lost_service"],
		row["lost_menu"], row["stars"], int(row["reputation"]), row["staff"], row["idle"], row["outdoors"], row["lemonade"]])
	var trouble: String = Trouble.diagnose(world)
	_advice = trouble
	if not trouble.is_empty():
		_note("     advice: %s" % trouble)
	# What the reviews were made of: the average of each part, and the worst.
	var sums: Dictionary = {}
	var worst: Dictionary = {}
	for review in c.day_reviews:
		for part in review.parts:
			sums[part] = float(sums.get(part, 0.0)) + float(review.parts[part])
		var w: int = review.worst_part()
		if w >= 0:
			worst[w] = int(worst.get(w, 0)) + 1
	var parts: PackedStringArray = PackedStringArray()
	for part in sums:
		parts.append("%s %+.1f" % [Review.part_name(part), float(sums[part]) / float(maxi(reviews, 1))])
	var blamed: PackedStringArray = PackedStringArray()
	for part in worst:
		blamed.append("%s %d" % [Review.part_name(part), worst[part]])
	_note("     reviews: %s; blamed: %s" % [", ".join(parts), ", ".join(blamed)])
	if persona == "profit":
		_review_staff()


func _morning(day: int) -> void:
	match persona:
		"profit":
			await _profit_morning(day)
		"garden":
			await _garden_morning(day)
	if not shots_dir.is_empty() and day in [1, 3]:
		await _shot("day%d_morning" % day)


func _watch_line() -> void:
	var staff: PackedStringArray = PackedStringArray()
	for worker in world.workers:
		if worker.role.id in [&"waiter", &"busser", &"cook", &"host"]:
			staff.append("%s:%s" % [worker.role.id, worker.status_text()])
	var states: Dictionary = {}
	for brain in world.customers.customers:
		if is_instance_valid(brain):
			var name: String = CustomerBrain.State.keys()[brain.state]
			states[name] = int(states.get(name, 0)) + 1
	var jobs: Dictionary = {}
	for job in world.board.jobs:
		if job.kind in [WorkType.Kind.SERVE, WorkType.Kind.BILL, WorkType.Kind.COOK, WorkType.Kind.CLEAR]:
			var k: String = "%s%s" % [WorkType.display_name(job.kind), "*" if job.claimant != null else ""]
			jobs[k] = int(jobs.get(k, 0)) + 1
	_note("  %02d:00 guests %s | jobs %s | %s" % [_last_hour, str(states), str(jobs), " ".join(staff)])
	# Where the dishes the waiting guests ordered actually are.
	var wanted: Dictionary = {}
	for brain in world.customers.customers:
		if is_instance_valid(brain):
			for line in brain.unserved():
				wanted[line["id"]] = int(wanted.get(line["id"], 0)) + int(line["count"])
	var tables: Dictionary = {}
	for seat in world.customers.seating.seats:
		tables[seat["table"]] = true
	var passes: Array = world.customers.pass_tiles()
	var where: PackedStringArray = PackedStringArray()
	for id in wanted:
		var on_tables: int = 0
		var on_pass: int = 0
		var elsewhere: int = 0
		for tile in world.items.tiles_with(id, Vector2i.ZERO):
			var n: int = world.items.count_at(tile)
			if tables.has(tile):
				on_tables += n
			elif passes.has(tile):
				on_pass += n
			else:
				elsewhere += n
		var recipe_status: String = ""
		for recipe in RecipeCatalog.all():
			if not recipe.outputs.is_empty() and recipe.outputs[0]["id"] == id:
				recipe_status = world.bills.status_text(recipe.id, world.generator._output_stock(recipe))
		where.append("%s wanted %d: tables %d, pass %d, elsewhere %d [%s]" % [id, wanted[id], on_tables, on_pass, elsewhere, recipe_status])
	if not where.is_empty():
		_note("        " + "; ".join(where))
	var blocked: PackedStringArray = PackedStringArray()
	for brain in world.customers.customers:
		if not is_instance_valid(brain) or brain.state != CustomerBrain.State.WAITING_FOR_ORDER:
			continue
		var table: Vector2i = brain.seating.table_for(brain.seat)
		var on_table: ItemDef = world.items.def_at(table)
		var lines: PackedStringArray = PackedStringArray()
		for line in brain.unserved():
			lines.append("%s%s" % [line["id"], "" if world.items.accepts(table, ItemCatalog.get_def(line["id"])) else "(refused)"])
		blocked.append("table %s holds %s; wants %s" % [table, "%s x%d" % [on_table.id, world.items.count_at(table)] if on_table != null else "nothing", ",".join(lines)])
	if not blocked.is_empty():
		_note("        waiting: " + " | ".join(blocked))
	# The stall: what it holds, what it waits on, and why.
	for station in world.generator.built_stations():
		if station["def"].id != &"market_stall":
			continue
		var press: Recipe = RecipeCatalog.get_recipe(&"press_lemonade")
		var needs: PackedStringArray = PackedStringArray()
		for need in press.inputs:
			needs.append("%s %d here, %d in the house (%s)" % [need["id"], world.generator.count_at_station(station, need["id"]),
				world.stock_of(need["id"]), world.generator.feed_problem(station, need["id"])])
		_note("        stall: %s [%s]; auto: %s" % ["; ".join(needs),
			world.bills.status_text(press.id, world.generator._output_stock(press)), world.auto_supply.note])
	var passes2: Array = world.customers.pass_tiles()
	var pass_text: PackedStringArray = PackedStringArray()
	for t in passes2:
		var d: ItemDef = world.items.def_at(t)
		pass_text.append("%s=%s" % [t, "%s x%d (avail %d)" % [d.id, world.items.count_at(t), world.items.available_at(t)] if d != null else "empty"])
	var stock_text: PackedStringArray = PackedStringArray()
	for id in wanted:
		for t in world.items.tiles_with(id, Vector2i.ZERO):
			stock_text.append("%s@%s %d/%d%s" % [id, t, world.items.available_at(t), world.items.count_at(t),
				" pickup" if world.board.has_pickup(t) else ""])
	var keys: PackedStringArray = PackedStringArray()
	for k in world.board._keys:
		if String(k).begins_with("plate:") or String(k).begins_with("serve:"):
			keys.append(String(k))
	_note("        pass: %s | stock: %s | plate/serve keys: %s" % [", ".join(pass_text), ", ".join(stock_text), ", ".join(keys)])


func _count_outdoor_sitters() -> void:
	for brain in world.customers.customers:
		if is_instance_valid(brain) and brain.seat != Seating.NO_SEAT and world.rooms.room_at(brain.seat) < 0:
			_outdoor_sitters[brain.get_instance_id()] = true


# --- the profit player ---------------------------------------------------------------

var _to_let_go: Array = []


func _profit_morning(day: int) -> void:
	if day == 1:
		# Fish costs nothing and grilled fish sells for 14g: keep plenty. Deeper
		# stock targets so a rush does not empty the menu.
		for target in [[&"bake_bread", 14, 8], [&"brew_beer", 18, 10], [&"grill_fish", 10, 5],
				[&"fish_soup", 10, 5], [&"catch_fish", 12, 6]]:
			world.bills.set_target(target[0], target[1])
			world.bills.set_resume_below(target[0], target[2])
		_note("  profit: deeper stock targets; fish is free, so fish dishes first")
		return
	var last: Dictionary = _rows.back()
	for worker in _to_let_go:
		if is_instance_valid(worker) and world.workers.has(worker):
			var title: String = worker.role.title
			if world.dismiss_worker(worker) == "":
				_note("  profit: let go an idle %s (saves %dg a day)" % [title.to_lower(), worker.role.wage])
	_to_let_go.clear()
	if int(last["lost_service"]) >= 4 and world.hire(&"waiter") == "":
		_note("  profit: hired a waiter (%d left waiting yesterday)" % last["lost_service"])
	if int(last["lost_seat"]) >= 3:
		var placed: int = _add_table_inside()
		_note("  profit: %s (%d turned away for a seat)" % ["added a table and two chairs" if placed > 0 else "no room for another table", last["lost_seat"]])
	if int(last["lost_menu"]) >= 4:
		for id in [&"bake_bread", &"brew_beer", &"grill_fish", &"fish_soup"]:
			var bill: Dictionary = world.bills.get_bill(id)
			world.bills.set_target(id, int(bill.get("target", 0)) + 4)
		_note("  profit: raised every stock target by 4 (%d found nothing to buy)" % last["lost_menu"])


## The least-worked member of any position with two or more, if they did
## next to nothing all day. One a night: the floor needs time to show it.
func _review_staff() -> void:
	var by_role: Dictionary = {}
	for worker in world.workers:
		var id: StringName = worker.role.id
		if not by_role.has(id):
			by_role[id] = []
		by_role[id].append(worker)
	var candidate: Worker = null
	var least: int = 1 << 30
	for id in by_role:
		var crew: Array = by_role[id]
		if crew.size() < 2:
			continue
		for worker in crew:
			var done: int = _work_done(worker)
			if done < least:
				least = done
				candidate = worker
	if candidate != null and least <= 6:
		_to_let_go.append(candidate)


func _work_done(worker: Worker) -> int:
	var n: int = 0
	for kind in worker.done_today:
		n += int(worker.done_today[kind])
	return n


## Chair, table, chair in a free row of the hall's floor.
func _add_table_inside() -> int:
	var hall: Rect2i = TestHouse.hall(world)
	for y in range(hall.position.y + 1, hall.end.y - 1):
		for x in range(hall.position.x, hall.end.x - 3):
			var free: bool = true
			for dx in range(4):
				for dy in [-1, 0, 1]:
					var t := Vector2i(x + dx, y + dy)
					if world.build.grid.object_index_at(t) >= 0:
						free = false
			if not free:
				continue
			var n: int = PlayerActions.place_all(world, &"table", [Vector2i(x + 1, y)])
			n += PlayerActions.place_all(world, &"chair", [Vector2i(x, y), Vector2i(x + 3, y)])
			PlayerActions.stop_building(world)
			return n
	return 0


# --- the garden player ---------------------------------------------------------------

## The back garden, 12 x 8, the tavern along the bottom row.
## T lawn, P path, D daisies, X mixed flowers, B border flowers, G tall grass,
## F tall grass with flowers.
const GARDEN: Array[String] = [
	"GGBBBBBBBBGG",
	"GTTTTTTTTTTG",
	"DTTTTTTTTTTD",
	"DTTTPPPPTTTD",
	"XTTTPPPPTTTX",
	"XTTTTPPTTTTX",
	"DTTTTPPTTTTD",
	"FTTTTPPTTTTF",
]
const GARDEN_KEYS: Dictionary = {
	"T": &"lawn_trimmed", "P": &"garden_path", "D": &"bed_daisy", "X": &"bed_mixed",
	"B": &"bed_border", "G": &"grass_tall", "F": &"grass_tall_flowers",
}
## What a lemonade-stand garden wants, and what would stand for it here.
const WISHLIST: Array = [
	["market_stall", "a market stall with a striped awning", "building"],
	["parasol_table", "a table under a parasol", "building"],
	["garden_fence", "a low fence round the garden", "building"],
	["lemonade", "lemonade on the menu", "item"],
]


func _garden_morning(day: int) -> void:
	if day != 1:
		# A decorator, not a negligent one: last night's advice is followed.
		var hire: StringName = &""
		if _advice.contains("hire a waiter"):
			hire = &"waiter"
		elif _advice.contains("Hire a cook"):
			hire = &"cook"
		if hire != &"" and world.hire(hire) == "":
			_note("  garden: hired a %s, as advised" % hire)
		return
	for wish in WISHLIST:
		var there: bool = BuildingCatalog.get_def(StringName(wish[0])) != null if wish[2] == "building" \
			else ItemCatalog.get_def(StringName(wish[0])) != null
		_note("  garden: wants %s ... %s" % [wish[1], "found" if there else "NOT IN THE GAME"])
	# The garden and a fence round its three open sides.
	var ring: Vector2i = _site(14, 9)
	if ring.x < 0:
		_note("  garden: !! no room for a back garden")
		return
	_garden_site = ring + Vector2i(1, 1)
	var at: Vector2i = _garden_site
	var gold: int = GameState.gold
	# The ground first: one tile kind at a time, as the build bar is used.
	for key in GARDEN_KEYS:
		var tiles: Array = []
		for y in range(GARDEN.size()):
			for x in range(GARDEN[y].length()):
				if GARDEN[y][x] == key:
					tiles.append(at + Vector2i(x, y))
		PlayerActions.place_all(world, GARDEN_KEYS[key], tiles)
	# The stand: a counter on the paved square, tables on the lawn.
	var stall: StringName = &"market_stall" if BuildingCatalog.get_def(&"market_stall") != null else &"serving_counter"
	PlayerActions.place_all(world, stall, [at + Vector2i(5, 3)])
	var table: StringName = &"parasol_table" if BuildingCatalog.get_def(&"parasol_table") != null else &"table"
	for spot in [Vector2i(2, 2), Vector2i(8, 2), Vector2i(2, 5), Vector2i(8, 5)]:
		PlayerActions.place_all(world, table, [at + spot])
		PlayerActions.place_all(world, &"chair", [at + spot + Vector2i(-1, 0), at + spot + Vector2i(2, 0)])
	PlayerActions.place_all(world, &"lantern_post", [at + Vector2i(4, 6), at + Vector2i(7, 6)])
	PlayerActions.place_all(world, &"garden_tree", [at + Vector2i(0, 1)])
	PlayerActions.place_all(world, &"garden_pine", [at + Vector2i(11, 1)])
	PlayerActions.place_all(world, &"garden_bench", [at + Vector2i(2, 7)])
	if with_fence and BuildingCatalog.get_def(&"garden_fence") != null:
		# Dragged along the back and down both sides; the hall closes the fourth.
		PlayerActions.select(world, &"garden_fence")
		PlayerActions.drag(world, ring, ring + Vector2i(13, 0))
		PlayerActions.drag(world, ring + Vector2i(0, 1), ring + Vector2i(0, 8))
		PlayerActions.drag(world, ring + Vector2i(13, 1), ring + Vector2i(13, 8))
		var fenced: int = 0
		for entry in world.build.grid.placements:
			if entry != null and entry["def"].id == &"garden_fence":
				fenced += 1
		_note("  garden: fenced %d tiles" % fenced)
	# A back door where the path meets the hall.
	var hall: Rect2i = TestHouse.hall(world)
	for x in [at.x + 5, at.x + 6]:
		var wall := Vector2i(x, hall.position.y - 1)
		if at.y + GARDEN.size() == wall.y:
			PlayerActions.place_all(world, &"door", [wall])
			break
	PlayerActions.stop_building(world)
	_note("  garden: laid a back garden with an outdoor stall and four tables at %s for %dg" % [at, gold - GameState.gold])
	if ItemCatalog.get_def(&"lemonade") != null:
		# A lemonade stand keeps plenty pressed.
		world.auto_supply.set_meal(&"press_lemonade", with_lemonade, 20 if with_lemonade else 0)
		_note("  garden: lemonade target %d" % (20 if with_lemonade else 0))


## A clear w x h stretch beside the hall, the nearer the better.
func _site(w: int, h: int) -> Vector2i:
	var hall: Rect2i = TestHouse.hall(world)
	var best := Vector2i(-1, -1)
	var best_gap: int = 1 << 30
	for y in range(world.plot.position.y, world.plot.end.y - h + 1):
		for x in range(world.plot.position.x, world.plot.end.x - w + 1):
			var rect := Rect2i(x, y, w, h)
			if rect.intersects(hall.grow(1)):
				continue
			var clear: bool = true
			for ty in range(rect.position.y - 1, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					var t := Vector2i(tx, ty)
					if world.build.grid.placement_at(t) >= 0 or not world.nav.is_walkable(t) or not world.build.grid.in_plot(t):
						clear = false
						break
				if not clear:
					break
			if not clear:
				continue
			var gap: int = maxi(maxi(hall.position.x - rect.end.x, rect.position.x - hall.end.x),
				maxi(hall.position.y - rect.end.y, rect.position.y - hall.end.y))
			if gap < best_gap:
				best_gap = gap
				best = rect.position
	return best


# --- reporting -------------------------------------------------------------------------

func _report() -> void:
	var total: int = 0
	var served: int = 0
	var outdoors: int = 0
	for row in _rows:
		total += int(row["profit"])
		served += int(row["served"])
		outdoors += int(row["outdoors"])
	_note("PERSONA %s: %d days, profit %+dg (purse %dg), %d served, %d seated outdoors, last stars %.1f, reputation %d" % [
		persona, _rows.size(), total, GameState.gold, served, outdoors,
		float(_rows.back()["stars"]) if not _rows.is_empty() else 0.0,
		int(world.customers.reputation.score)])
	if not shots_dir.is_empty():
		await _shot("final")
		var f := FileAccess.open(shots_dir.path_join("log.txt"), FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_notes))


func _shot(name: String) -> void:
	world.hud._hud.visible = false
	var rig: CameraRig = world.rig
	var focus: Vector2 = Vector2(TestHouse.hall(world).get_center())
	if _garden_site.x >= 0:
		focus = Vector2(_garden_site) + Vector2(6, 3)
		rig._yaw = 205.0
		rig._yaw_target = 205.0
	rig._distance = 15.0
	rig._distance_target = 15.0
	rig._pitch = 44.0
	rig._pitch_target = 44.0
	rig.focus_on(Vector3(focus.x, world.terrain.plot_height, focus.y))
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join("%s_%s.png" % [persona, name]))
	world.hud._hud.visible = true


func _note(text: String) -> void:
	print(text)
	_notes.append(text)
