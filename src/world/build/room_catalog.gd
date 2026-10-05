class_name RoomCatalog
extends RefCounted

## What a room has to contain to earn a name, as data.
##
## Design notes section 23 opens with "do NOT hardcode restaurant room", so
## there is no Kitchen class and no `is_dining_room()`. There is a list of
## requirements, and a room is whichever entry it satisfies. A bedroom, a
## brewery or a guest room is another entry here and nothing else anywhere.
##
## Order is significance, not priority in the usual sense: the *last* matching
## entry wins, so a room that satisfies both "Storage" and "Kitchen" is called
## a kitchen. A room that satisfies nothing is still a room -- an empty walled
## space is a room you have not furnished yet, not a bug.

class RoomKind:
	extends RefCounted
	var id: StringName
	var display_name: String
	## Each entry is { any: Array[StringName], count: int } -- at least `count`
	## pieces drawn from `any`. A list rather than one id so "a cooking station"
	## can mean an oven or a brewing vat without either being special.
	var requirements: Array = []
	## What the overlay washes this room in. Data like everything else about a
	## room kind, so a new one arrives with its own colour and nothing switches
	## on its name.
	##
	## Deliberately nothing in the timber family. The first set were warm browns
	## and ambers, which over a wooden floor is the same colour twice -- the wash
	## was technically there and effectively invisible.
	var tint: Color = Color(0.8, 0.8, 0.8)

	func _init(p_id: String, p_name: String, p_requirements: Array, p_tint: Color) -> void:
		id = StringName(p_id)
		display_name = p_name
		requirements = p_requirements
		tint = p_tint

	## Does a tally of building ids satisfy this?
	func satisfied_by(counts: Dictionary) -> bool:
		for need in requirements:
			var found: int = 0
			for candidate in need["any"]:
				found += int(counts.get(candidate, 0))
			if found < int(need["count"]):
				return false
		return true


static var _kinds: Array[RoomKind] = []


static func all() -> Array[RoomKind]:
	if _kinds.is_empty():
		_build()
	return _kinds


## The most significant kind this tally satisfies, or null for a bare room.
static func identify(counts: Dictionary) -> RoomKind:
	var best: RoomKind = null
	for kind in all():
		if kind.satisfied_by(counts):
			best = kind
	return best


static func _need(any: Array, count: int = 1) -> Dictionary:
	var ids: Array[StringName] = []
	for id in any:
		ids.append(StringName(id))
	return {"any": ids, "count": count}


static func _build() -> void:
	_kinds = [
		# Least significant first; the last match wins.
		RoomKind.new("storage", "Storage", [
			_need(["storage_shelf", "barrel"], 2),
		], Color("6f7fa8")),
		RoomKind.new("dining", "Dining Hall", [
			_need(["table"]),
			_need(["chair"]),
		], Color("c06a86")),
		RoomKind.new("brewery", "Brewery", [
			_need(["brewing_vat"]),
		], Color("5f9e63")),
		RoomKind.new("kitchen", "Kitchen", [
			_need(["oven", "brewing_vat"]),
			_need(["prep_table", "serving_counter"]),
		], Color("3f9aa8")),
	] as Array[RoomKind]
