class_name StaffRole
extends RefCounted

## A position on the staff, as in Prison Architect: what the person is hired
## as, what that costs up front and every day, and which kinds of work the
## position allows.
##
## The position is the rule; the priority grid still orders the work *inside*
## it. So a cook never hauls, however idle, and the player's remaining choice
## is which of a waiter's two jobs comes first. That is what makes hiring a
## decision: five generalists cannot be swapped for five of anything.
##
## Numbers here are measured against the demo level, not guessed -- see
## `dev/level_smoke.tscn` and docs/gameplay_testing_handoff.md. Doubled with the
## ten-minute day (2026-09-28): a day then holds about twice the trade, and at
## the old rates wages fell to 8% of takings, too little for hiring to matter.

var id: StringName
var title: String
## One line, for the hire card and the inspector.
var blurb: String
## Paid once, when hired.
var fee: int = 0
## Paid at close of business, every day they are on the books.
var wage: int = 0
## WorkType.Kind values this position may do. Everything else is refused.
var kinds: Array[int] = []
## Starting order inside the allowed kinds, lower first.
var starting: Dictionary = {}
## The position's cloth colour. StaffUniforms pairs it with an identifying cut
## and hat so the crew reads from the tavern camera.
var uniform: Color = Color("6e2233")
## False only for the legacy all-rounder, which exists so older saves load.
var hireable: bool = true
## The first day this position can be hired, for positions the tavern grows into.
var unlock_day: int = 1

static var _catalog: Array[StaffRole] = []


static func make(p_id: StringName, p_title: String, p_blurb: String, p_fee: int, p_wage: int,
		p_starting: Dictionary, p_uniform: Color, p_hireable: bool = true) -> StaffRole:
	var role := StaffRole.new()
	role.id = p_id
	role.title = p_title
	role.blurb = p_blurb
	role.fee = p_fee
	role.wage = p_wage
	role.starting = p_starting
	for kind in p_starting:
		role.kinds.append(int(kind))
	role.uniform = p_uniform
	role.hireable = p_hireable
	return role


static func all() -> Array[StaffRole]:
	if _catalog.is_empty():
		var K := WorkType.Kind
		_catalog = [
			make(&"waiter", "Waiter", "Takes orders at the table, brings the food and drink, and the bill.",
				30, 12, {K.SERVE: 1, K.BILL: 2, K.CLEAR: 3}, Color("6e2233")),
			make(&"busser", "Busser", "Clears tables, collects the bill and carries goods. Frees the waiters.",
				16, 6, {K.CLEAR: 1, K.BILL: 2, K.HAUL: 3}, Color("4d5a3a")),
			make(&"host", "Host", "Greets guests at the door. Needs a host's stand to be any use.",
				24, 10, {K.HOST: 1}, Color("24344f")),
			make(&"cook", "Cook", "Makes dough, bakes and brews, and fetches the ingredients to the bench.",
				50, 16, {K.COOK: 1}, Color("d9d2bf")),
			make(&"porter", "Porter", "Carries deliveries to the shelves, draws water, and builds.",
				20, 8, {K.HAUL: 1, K.CONSTRUCT: 2, K.GATHER: 3}, Color("6b4a2b")),
			make(&"cleaner", "Cleaner", "Washes the dishes and clears tables when the basin is empty.",
				16, 6, {K.CLEAN: 1, K.CLEAR: 2}, Color("5d5f63")),
			make(&"fisherman", "Fisherman", "Fishes from a fishing spot on the river bank, and carries the catch in. From day 2.",
				20, 8, {K.FISH: 1, K.HAUL: 2}, Color("2f5d62")),
			make(&"farmer", "Farmer", "Plants and harvests the farm plots, and carries the crop in.",
				18, 8, {K.FARM: 1, K.HAUL: 2}, Color("5e6b2f")),
			# Everybody hired before positions existed. Not on the hire list.
			make(&"hand", "Hand", "A general hand from before positions: does anything.",
				0, Ledger.WAGE_PER_STAFF * 2, WorkType.default_priorities(), Color("6e2233"), false),
		]
	var fisher: StaffRole = null
	for role in _catalog:
		if role.id == &"fisherman":
			fisher = role
	if fisher != null:
		fisher.unlock_day = 2
	return _catalog


static func of(role_id: StringName) -> StaffRole:
	for role in all():
		if role.id == role_id:
			return role
	return null


static func hireable_roles() -> Array[StaffRole]:
	var out: Array[StaffRole] = []
	for role in all():
		if role.hireable:
			out.append(role)
	return out


## The cheapest position that can do this kind of work, for "hire a ..." advice.
static func for_kind(kind: int) -> StaffRole:
	var best: StaffRole = null
	for role in hireable_roles():
		if role.kinds.has(kind) and (best == null or role.wage < best.wage):
			best = role
	return best


func allows(kind: int) -> bool:
	return kinds.has(kind)


## Every kind of work, with the ones the position forbids switched off.
func starting_priorities() -> Dictionary:
	var out: Dictionary = {}
	for kind in range(WorkType.COUNT):
		out[kind] = int(starting.get(kind, WorkType.PRIORITY_OFF))
	return out
