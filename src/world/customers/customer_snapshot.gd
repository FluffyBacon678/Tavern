class_name CustomerSnapshot
extends RefCounted

## A paid meal and a meal awaiting payment are different states. Keeping the
## visit across a save prevents reloads from discarding diners or billing them
## twice. Jobs remain derived from the restored orders and physical stock.

const COUNTERS: Array[String] = ["served_count", "lost_count", "lost_no_seat",
	"lost_no_service", "lost_no_menu", "takings", "dishes_left"]
const BRAIN_NUMBERS: Array[String] = ["_timer", "_patience", "_waited_for_order",
	"_waited_for_seat", "_seat_tolerance", "_menu_breadth", "_food_quality_sum",
	"_food_eaten", "_dirt_sum", "_dirt_samples", "_observe_timer"]


static func capture(director: CustomerDirector) -> Dictionary:
	var out: Dictionary = {"guests": [], "consumed": {}, "reviews": [],
		"spawn_timer": director._spawn_timer, "rng_state": str(director._rng.state),
		"rng_seed": str(director._rng.seed), "open": director.open_for_business,
		"bookings": director.bookings.capture()}
	for key in COUNTERS:
		out[key] = director.get(key)
	for id in director.consumed:
		out["consumed"][String(id)] = director.consumed[id]
	for brain in director.customers:
		if not is_instance_valid(brain) or brain.state == CustomerBrain.State.GONE:
			continue
		var pawn: Pawn = brain.pawn
		var target: Vector2i = pawn._path.back() if pawn.is_busy() and not pawn._path.is_empty() else pawn.tile
		var row: Dictionary = {"name": pawn.pawn_name, "tile": _tile(pawn.tile),
			"appearance": pawn.appearance.to_save() if pawn.appearance != null else {},
			"equipment": pawn.equipped.duplicate(), "adventurer": pawn.adventurer,
			"target": _tile(target), "pawn_seed": str(pawn._rng.seed),
			"rng_seed": str(brain._rng.seed), "rng_state": str(brain._rng.state),
			"state": brain.state, "greeted": brain.greeted, "did_order": brain._did_order,
			"chair": _tile(brain.seat),
			"exit": _tile(brain.exit_tile), "order": brain.order.duplicate(true)}
		for key in BRAIN_NUMBERS:
			row[key] = brain.get(key)
		row["_waited_for_bill"] = brain._waited_for_bill
		row["paid_at_door"] = brain._paid_at_door
		row["booked"] = brain.booked
		row["view"] = brain.view
		out["guests"].append(row)
	for review in director.day_reviews:
		var parts: Dictionary = {}
		for part in review.parts:
			parts[str(part)] = review.parts[part]
		out["reviews"].append({"patron": review.patron, "served": review.served,
			"spend": review.spend, "parts": parts, "satisfaction": review.satisfaction,
			"stars": review.stars, "quote": review.quote})
	return out


static func restore(director: CustomerDirector, data: Dictionary) -> void:
	for seat in director.seating.seats:
		seat["taken_by"] = null
	director.clear()
	director.reset_day_tallies()
	director.consumed.clear()
	director.dishes_left = 0
	if data.is_empty():
		return  # Legacy saves did not retain visits.
	for key in COUNTERS:
		director.set(key, int(data[key]))
	for id in data["consumed"]:
		director.consumed[StringName(id)] = int(data["consumed"][id])
	director._spawn_timer = float(data["spawn_timer"])
	director.bookings = Bookings.new()
	if data.get("bookings") is Dictionary:
		director.bookings.restore(data["bookings"])
	director.open_for_business = bool(data["open"])
	director._rng.seed = int(data["rng_seed"])
	director._rng.state = int(data["rng_state"])
	for row in data["guests"]:
		var pawn := Pawn.new()
		director._holder.add_child(pawn)
		pawn.setup(director.nav, director.terrain, _vector(row["tile"]),
			director.pawn_material, int(row["pawn_seed"]), true)
		pawn.pawn_name = row["name"]
		if row.has("appearance"):
			pawn.set_appearance(CharacterAppearance.from_save(row["appearance"], pawn.appearance),
				CharacterProfile.equipment_from_save(row.get("equipment", {})))
		# The archetype was seeded by the original outfit when the guest was
		# born, but from now on it is stored independently of their wardrobe.
		if _integer(row.get("adventurer"), -1, 6):
			pawn.adventurer = int(row["adventurer"])
		var brain := CustomerBrain.new()
		brain.name = "Brain"
		pawn.add_child(brain)
		brain.setup(pawn, director, director.seating, director.items, director.nav, int(row["rng_seed"]))
		director.attach_to_clock(pawn, brain)
		brain._rng.state = int(row["rng_state"])
		brain.state = int(row["state"])
		brain.greeted = row["greeted"]
		brain._did_order = row["did_order"]
		brain.booked = bool(row.get("booked", false))
		brain.exit_tile = _vector(row["exit"])
		brain.order = row["order"].duplicate(true)
		for line in brain.order:
			line["id"] = StringName(line["id"])
			line["count"] = int(line["count"])
			line["served"] = int(line["served"])
		for key in BRAIN_NUMBERS:
			# Preserve integer fields after JSON's numeric conversion.
			brain.set(key, int(row[key]) if typeof(brain.get(key)) == TYPE_INT else float(row[key]))
		# Saved before waiters took orders and brought bills: nothing owed yet.
		brain._waited_for_bill = float(row.get("_waited_for_bill", 0.0))
		brain._paid_at_door = bool(row.get("paid_at_door", false))
		# Saved before guests enjoyed a view: none.
		brain.view = clampf(float(row.get("view", 0.0)), 0.0, 1.0) if _number(row.get("view", 0.0)) else 0.0
		var chair: Vector2i = _vector(row["chair"])
		if director.seating.take(brain, chair):
			brain.seat = chair
		brain.left.connect(director._on_customer_left)
		director.customers.append(brain)
		if brain.state in [CustomerBrain.State.ARRIVING, CustomerBrain.State.WALKING_TO_SEAT, CustomerBrain.State.LEAVING]:
			pawn.goto(_vector(row["target"]))
	for row in data["reviews"]:
		var review := Review.new()
		review.patron = row["patron"]
		review.served = row["served"]
		review.spend = int(row["spend"])
		review.satisfaction = int(row["satisfaction"])
		review.stars = int(row["stars"])
		review.quote = row["quote"]
		for part in row["parts"]:
			review.parts[int(part)] = int(row["parts"][part])
		director.day_reviews.append(review)


static func valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.is_empty():
		return true
	for key in COUNTERS:
		if not _integer(data.get(key), 0, 1_000_000_000):
			return false
	for key in ["rng_seed", "rng_state"]:
		if not data.get(key) is String or not data[key].is_valid_int():
			return false
	if not _number(data.get("spawn_timer")) or not data.get("open") is bool:
		return false
	if not data.get("consumed") is Dictionary or not data.get("guests") is Array or not data.get("reviews") is Array:
		return false
	if data["guests"].size() > 160 or data["reviews"].size() > 10000:
		return false
	for id in data["consumed"]:
		if not (id is String or id is StringName):
			return false
		if ItemCatalog.get_def(StringName(id)) == null or not _integer(data["consumed"][id], 0, 1_000_000_000):
			return false
	var occupied: Dictionary = {}
	for row in data["guests"]:
		if not row is Dictionary or not row.get("name") is String or not _integer(row.get("state"), 0, CustomerBrain.State.WAITING_FOR_BILL):
			return false
		if int(row["state"]) == CustomerBrain.State.GONE:
			return false
		if row.has("_waited_for_bill") and not _number(row["_waited_for_bill"]):
			return false
		for key in ["tile", "target", "exit", "chair"]:
			if not _valid_tile(row.get(key), key == "chair"):
				return false
		for key in ["pawn_seed", "rng_seed", "rng_state"]:
			if not row.get(key) is String or not row[key].is_valid_int():
				return false
		if not row.get("greeted") is bool or not row.get("did_order") is bool or not row.get("order") is Array:
			return false
		for key in BRAIN_NUMBERS:
			if not _number(row.get(key)):
				return false
		if not _integer(row["_food_eaten"], 0, 1000) or not _integer(row["_dirt_samples"], 0, 1_000_000_000):
			return false
		if not _integer(row["_menu_breadth"], -1, ItemCatalog.all().size()):
			return false
		if row["_food_quality_sum"] < 0 or row["_food_quality_sum"] > row["_food_eaten"]:
			return false
		var chair: Vector2i = _vector(row["chair"])
		if chair != Vector2i(-1, -1):
			if occupied.has(chair):
				return false
			occupied[chair] = true
		if row["order"].size() > ItemCatalog.all().size():
			return false
		for line in row["order"]:
			if not line is Dictionary or not (line.get("id") is String or line.get("id") is StringName):
				return false
			var def: ItemDef = ItemCatalog.get_def(StringName(line["id"]))
			if def == null or def.sell_value <= 0 or not _integer(line.get("count"), 1, 100):
				return false
			if not _integer(line.get("served"), 0, int(line["count"])):
				return false
	for row in data["reviews"]:
		if not row is Dictionary or not row.get("patron") is String or not row.get("quote") is String or not row.get("served") is bool:
			return false
		if not _integer(row.get("spend"), 0, 1_000_000_000) or not _integer(row.get("satisfaction"), 0, 100) or not _integer(row.get("stars"), 1, 5):
			return false
		if not row.get("parts") is Dictionary:
			return false
		for key in row["parts"]:
			# Bounded by the enum, not its last member: naming Cleanliness here
			# dropped every guest from a save holding one garden review.
			if not str(key).is_valid_int() or int(key) < 0 or int(key) >= Review.Part.size() or not _integer(row["parts"][key], -100, 100):
				return false
	return true


## Called after the save's building rows have passed their own validation.
## A saved visit cannot claim a missing chair or two guests' copies of it.
static func valid_seats(data: Dictionary, buildings: Array) -> bool:
	if data.is_empty():
		return true
	var chairs: Dictionary = {}
	var tables: Dictionary = {}
	for row in buildings:
		if not row["built"]:
			continue
		var def: BuildingDef = BuildingCatalog.get_def(StringName(row["def"]))
		var size: Vector2i = def.rotated_size(int(row["rot"]))
		for y in range(size.y):
			for x in range(size.x):
				var tile := Vector2i(int(row["x"]) + x, int(row["y"]) + y)
				if def.furniture_role == &"chair":
					chairs[tile] = true
				elif def.furniture_role == &"table":
					tables[tile] = true
	for row in data["guests"]:
		var chair: Vector2i = _vector(row["chair"])
		var seated: bool = int(row["state"]) in [CustomerBrain.State.WALKING_TO_SEAT,
			CustomerBrain.State.ORDERING, CustomerBrain.State.READY_TO_ORDER,
			CustomerBrain.State.WAITING_FOR_ORDER, CustomerBrain.State.EATING,
			CustomerBrain.State.WAITING_FOR_BILL, CustomerBrain.State.PAYING]
		if not seated and chair == Vector2i(-1, -1):
			continue
		if not chairs.has(chair):
			return false
		var adjoining: bool = false
		for direction in Seating.ADJACENT:
			adjoining = adjoining or tables.has(chair + direction)
		if not adjoining:
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) < 1.0e12


static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and value >= low and value <= high


static func _valid_tile(value: Variant, allow_empty: bool) -> bool:
	if not value is Array or value.size() != 2:
		return false
	if not _number(value[0]) or not _number(value[1]):
		return false
	# Compared numerically, not against the literal [-1, -1]: JSON hands every
	# number back as a float, so an unseated guest's chair arrives as
	# [-1.0, -1.0] and never matched. The effect was that a diner who had paid
	# and let go of their seat failed validation and vanished on reload -- and
	# only that one case, which is why it looked like the restore was broken.
	if allow_empty and int(value[0]) == -1 and int(value[1]) == -1:
		return true
	return _integer(value[0], 0, 95) and _integer(value[1], 0, 95)


static func _tile(value: Vector2i) -> Array:
	return [value.x, value.y]


static func _vector(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))
