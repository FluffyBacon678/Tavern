class_name Trouble
extends RefCounted

## The one thing most plainly stopping the tavern earning right now, said in
## words a player can act on -- or "" when nothing is.
##
## The checklist says what to build; it cannot say what is going wrong. A
## tavern whose every table is under dirty plates looks perfectly calm: guests
## mill about on the grass, the day's takings sit at +0g, and nothing on screen
## explains it. The simulation already knows why each guest left. This is where
## the player gets told.
##
## Derived, never tracked, the same as `Objectives`: every call asks the world
## afresh, so a problem that has been fixed stops being reported the moment it
## is, and nothing needs saving.

const INGREDIENTS: Array[StringName] = [&"flour", &"water", &"yeast", &"malt", &"hops"]
## One or two lost guests in a day is ordinary bad luck. This many is a pattern
## worth interrupting the player about.
const LOSSES_WORTH_NAMING: int = 3


## Most urgent first: a cause before its symptoms. Out of hops explains "nothing
## to sell", and dirty plates explain "no seat", so those are checked first.
static func diagnose(world) -> String:
	if world == null or world.customers == null or world.items == null:
		return ""
	var customers = world.customers
	var seating: Seating = customers.seating

	var seats: int = seating.seats.size()
	if seats > 0:
		var blocked: int = 0
		for i in range(seats):
			if not seating.is_usable(i):
				blocked += 1
		if blocked > 0 and blocked * 2 >= seats:
			if world.build.grid.count_built([&"sink"]) == 0:
				if blocked == seats:
					return "Every table is covered in dirty plates, so nobody will sit down. Build a wash basin and staff will clear them."
				return "%d of %d seats are at tables covered in dirty plates. Build a wash basin and staff will clear them." % [
					blocked, seats]
			if not _anyone_on(world, WorkType.Kind.CLEAR):
				if not _anyone_allowed(world, WorkType.Kind.CLEAR):
					return "Dirty plates are blocking %d seats and nobody on the staff clears tables. %s" % [
						blocked, _hire_advice(WorkType.Kind.CLEAR)]
				return ("Dirty plates are blocking %d seats and nobody is set to Clear. Change it under Staff" + KeyBindings.hint("staff") + ".") % blocked

	# Work waiting that no position on the books is allowed to do. The cause
	# behind "nothing to sell" when there is no cook, and behind deliveries left
	# in the yard when there is no porter -- so it comes before those.
	if world.board != null:
		var waiting: Dictionary = {}
		for job in world.board.jobs:
			waiting[job.kind] = true
		for kind in [WorkType.Kind.COOK, WorkType.Kind.HAUL, WorkType.Kind.SERVE,
				WorkType.Kind.CLEAN, WorkType.Kind.CLEAR, WorkType.Kind.CONSTRUCT, WorkType.Kind.GATHER,
				WorkType.Kind.BILL, WorkType.Kind.FISH, WorkType.Kind.HOST, WorkType.Kind.FARM]:
			if waiting.has(kind) and not _anyone_allowed(world, kind):
				return "Nobody on the staff can %s. %s" % [_verb(kind), _hire_advice(kind)]

	# Only once goods have ever arrived: before the first order, running out is
	# the checklist's business, not a fault.
	if not world.delivered.is_empty():
		var out: PackedStringArray = PackedStringArray()
		for id in _ingredients_in_use(world):
			if world.stock_of(id) <= 0:
				var def: ItemDef = ItemCatalog.get_def(id)
				out.append(def.display_name.to_lower() if def != null else String(id))
		if not out.is_empty():
			# Auto-order has it in hand, unless it has said why it is holding back
			# or the missing goods are ones the player said never to buy.
			var auto: AutoSupply = world.auto_supply
			if auto.enabled:
				if not auto.note.is_empty():
					return auto.note
				var unbought: PackedStringArray = PackedStringArray()
				for id in _ingredients_in_use(world):
					if world.stock_of(id) <= 0 and auto.never.has(id):
						unbought.append(ItemCatalog.get_def(id).display_name.to_lower())
				if not unbought.is_empty():
					return "Out of %s, which auto restock is set never to buy. Get it yourself, or choose Allow all ingredients in Stores%s." % [
						_joined(unbought), KeyBindings.hint("supplies")]
				# Otherwise it is on its way: nothing to say, and on to the rest.
			else:
				var delivery: int = world.order_cost(world.STANDARD_ORDER)
				if GameState.gold < delivery:
					# Advice that can be followed: the standard order is out of reach,
					# so say what is not.
					return "Out of %s, and the purse (%dg) will not cover a full delivery (%dg). Order just what is missing, or demolish something for money back." % [
						_joined(out), GameState.gold, delivery]
				return "Out of %s. Enable Auto restock in Stores%s, or order ingredients manually there." % [
					_joined(out), KeyBindings.hint("supplies")]

	if customers.lost_no_menu >= LOSSES_WORTH_NAMING and customers.menu_stock() <= 0:
		return "Nothing to sell: %d guests left today without ordering." % customers.lost_no_menu
	if customers.lost_no_seat >= LOSSES_WORTH_NAMING and seating.usable_free_count() == 0:
		return "%d guests left today for want of a seat. More tables and chairs would keep them." % customers.lost_no_seat
	if customers.lost_no_service >= LOSSES_WORTH_NAMING:
		return "%d guests left today waiting for a waiter or their food. Put more staff on Serve, or hire a waiter." % customers.lost_no_service
	# Last, because debt is where the other problems end up: anything above it
	# is a cause worth fixing first.
	if GameState.gold < 0:
		return ("In debt by %dg, and wages still come out at close: %d staff, %dg a day. Let staff go under Staff" + KeyBindings.hint("staff") + ", or demolish what you do not need: unbuilt blueprints refund in full.") % [
			-GameState.gold, world.workers.size(), world.wage_bill()]
	# Before the debt, not after it: the first morning's overbuilt tavern said
	# nothing at all until midnight had already put it in the red.
	if GameState.gold < world.wage_bill():
		return ("Tonight's wages are %dg and the purse holds %dg. Takings before close have to cover it, or let staff go under Staff" + KeyBindings.hint("staff") + ".") % [
			world.wage_bill(), GameState.gold]
	return ""


## Ingredients some finished bench actually uses. Hops nobody can brew with are
## not worth warning about -- that is what the demo level's missing prep table
## looks like for flour.
static func _ingredients_in_use(world) -> Array[StringName]:
	var wanted: Dictionary = {}
	for entry in world.build.grid.placements:
		if entry == null or not entry["built"]:
			continue
		for recipe in RecipeCatalog.for_station(entry["def"].id):
			for need in recipe.inputs:
				var id: StringName = StringName(need["id"])
				if INGREDIENTS.has(id):
					wanted[id] = true
	var out: Array[StringName] = []
	for id in INGREDIENTS:
		if wanted.has(id):
			out.append(id)
	return out


static func _anyone_on(world, kind: int) -> bool:
	for worker in world.workers:
		if is_instance_valid(worker) and worker.priority_for(kind) != WorkType.PRIORITY_OFF:
			return true
	return false


static func _anyone_allowed(world, kind: int) -> bool:
	for worker in world.workers:
		if is_instance_valid(worker) and worker.allows(kind):
			return true
	return false


static func _hire_advice(kind: int) -> String:
	var role: StaffRole = StaffRole.for_kind(kind)
	if role == null:
		return ""
	return ("Hire a %s under Staff" + KeyBindings.hint("staff") + ": %dg, then %dg a day.") % [role.title.to_lower(), role.fee, role.wage]


static func _verb(kind: int) -> String:
	match kind:
		WorkType.Kind.COOK: return "cook"
		WorkType.Kind.HAUL: return "carry goods"
		WorkType.Kind.SERVE: return "take orders or serve"
		WorkType.Kind.BILL: return "bring guests their bill"
		WorkType.Kind.CLEAN: return "wash the dishes"
		WorkType.Kind.CLEAR: return "clear tables"
		WorkType.Kind.CONSTRUCT: return "build"
		WorkType.Kind.GATHER: return "pump water"
		WorkType.Kind.FISH: return "fish"
		WorkType.Kind.FARM: return "farm"
	return "do that work"


static func _joined(names: PackedStringArray) -> String:
	if names.size() <= 1:
		return "".join(names)
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]
