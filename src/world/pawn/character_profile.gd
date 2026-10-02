class_name CharacterProfile
extends RefCounted

## A stable person owns cosmetics independently of what is currently worn.
## The catalogue supplies original garments, not economy or equipment stats.
const VERSION: int = 1
## Compatibility names remain available to existing callers.
const SLOTS: Array[String] = WardrobeCatalog.SLOTS
const EQUIPMENT_IDS: Dictionary = WardrobeCatalog.EQUIPMENT_IDS
const STARTER_ITEMS: Array[String] = WardrobeCatalog.STARTER_ITEMS

var person_id: String = ""
var name: String = "Rowan"
var appearance: CharacterAppearance = CharacterAppearance.new()
var owned: Array[String] = []
var equipped: Dictionary = {}


static func default_owner(seed: int = 0) -> CharacterProfile:
	var out := CharacterProfile.new()
	out.person_id = "owner_%s" % str(seed)
	out.owned.assign(STARTER_ITEMS)
	out.equipped = {"body": "linen_shirt", "legs": "olive_trousers", "feet": "leather_boots"}
	return out


## Called explicitly on a creator draft for this free demo wardrobe. Loading
## an existing person does not grant anything or alter their saved ownership.
func grant_starter_wardrobe() -> void:
	for id in STARTER_ITEMS:
		if not owned.has(id):
			owned.append(id)


func to_save() -> Dictionary:
	return {"version": VERSION, "person_id": person_id, "name": name,
		"appearance": appearance.to_save() if appearance != null else CharacterAppearance.new().to_save(),
		"owned": owned.duplicate(), "equipped": equipped.duplicate()}


func clone() -> CharacterProfile:
	return from_save(to_save())


static func from_save(data: Variant, seed: int = 0) -> CharacterProfile:
	var out: CharacterProfile = default_owner(seed)
	if not data is Dictionary or not CharacterAppearance._valid_integer(data.get("version"), VERSION, VERSION):
		return out
	if data.get("person_id") is String and not data["person_id"].strip_edges().is_empty():
		out.person_id = data["person_id"].strip_edges().left(80)
	if data.get("name") is String and not data["name"].strip_edges().is_empty():
		out.name = data["name"].strip_edges().left(32)
	out.appearance = CharacterAppearance.from_save(data.get("appearance"), out.appearance)
	if data.get("owned") is Array:
		out.owned.clear()
		for id in data["owned"]:
			# Unknown IDs may belong to a newer catalogue. Retain ownership;
			# the renderer can use a plain outfit until that definition returns.
			if id is String and not id.is_empty() and id.length() <= 80 and not out.owned.has(id):
				out.owned.append(id)
			if out.owned.size() >= 256:
				break
	if data.get("equipped") is Dictionary:
		out.equipped = equipment_from_save(data["equipped"], out.owned)
	else:
		# Even a malformed ownership list must not equip an unowned item.
		for slot in out.equipped.keys():
			if not out.owned.has(out.equipped[slot]):
				out.equipped.erase(slot)
	return out


static func equipment_from_save(data: Variant, ownership: Variant = null) -> Dictionary:
	var out: Dictionary = {}
	if not data is Dictionary:
		return out
	for slot in SLOTS:
		var id: Variant = data.get(slot)
		if not id is String or id.is_empty() or id.length() > 80:
			continue
		if ownership is Array and not ownership.has(id):
			continue
		if EQUIPMENT_IDS.has(id) and EQUIPMENT_IDS[id] != slot:
			continue
		out[slot] = id
	return out
