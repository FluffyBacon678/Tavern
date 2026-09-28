class_name Recipe
extends Resource

## A generic conversion: inputs, a station, work, outputs.
##
## The design notes are explicit that there must be no BakeBread() and no
## BrewBeer() -- one recipe engine, and bread and beer are data fed into it.
## Everything the tavern ever makes, up to and including stew, cheese and mead,
## is expected to be another entry in the catalog rather than another function.

## An ingredient requirement or a product, as { id: StringName, count: int }.
@export var inputs: Array = []
@export var outputs: Array = []

@export var id: StringName = &""
@export var display_name: String = ""
## Building definition id this must be performed at.
@export var station_id: StringName = &""
## Seconds of work at normal speed.
@export var work_amount: float = 4.0
## Which work priority governs it, so a cook does cooking and a brewer brewing.
@export var work_kind: int = WorkType.Kind.COOK
## A catch rather than a product: each batch is one of these, chosen by the
## simulation's dice, and `pick_most` of it at most (at least one).
@export var pick_from: Array = []
@export var pick_most: int = 1


static func make(
	p_id: String,
	p_name: String,
	p_station: String,
	p_work: float,
	p_kind: int,
	p_inputs: Array,
	p_outputs: Array
) -> Recipe:
	var r := Recipe.new()
	r.id = StringName(p_id)
	r.display_name = p_name
	r.station_id = StringName(p_station)
	r.work_amount = p_work
	r.work_kind = p_kind
	r.inputs = p_inputs
	r.outputs = p_outputs
	return r


static func ingredient(id: String, count: int) -> Dictionary:
	return {"id": StringName(id), "count": count}


func input_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in inputs:
		out.append(entry["id"])
	return out


func required_count(id: StringName) -> int:
	for entry in inputs:
		if entry["id"] == id:
			return entry["count"]
	return 0


func summary() -> String:
	var ins: PackedStringArray = PackedStringArray()
	for entry in inputs:
		var def: ItemDef = ItemCatalog.get_def(entry["id"])
		ins.append("%dx %s" % [entry["count"], def.display_name if def else entry["id"]])
	var outs: PackedStringArray = PackedStringArray()
	for entry in outputs:
		var def: ItemDef = ItemCatalog.get_def(entry["id"])
		outs.append("%dx %s" % [entry["count"], def.display_name if def else entry["id"]])
	return "%s -> %s" % [", ".join(ins), ", ".join(outs)]
