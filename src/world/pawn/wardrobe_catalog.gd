class_name WardrobeCatalog
extends RefCounted

## Original cosmetic wardrobe definitions. Garment IDs and slot assignments
## are stable save data; names are presentation, not dyes or gameplay stats.
## Aprons layer over a shirt independently of a cape and backpack.
const SLOTS: Array[String] = ["head", "body", "outer", "legs", "feet", "hands", "neck", "ring", "cape", "backpack"]
const SLOT_LABELS: Dictionary = {
	"head": "Head", "body": "Shirt", "outer": "Apron / outerwear", "legs": "Trousers",
	"feet": "Footwear", "hands": "Gloves", "neck": "Neck", "ring": "Ring",
	"cape": "Cape", "backpack": "Backpack",
}
const EQUIPMENT_IDS: Dictionary = {
	"felt_hat": "head", "cook_hat": "head",
	"linen_shirt": "body", "short_sleeve_shirt": "body", "leather_vest": "body",
	"linen_apron": "outer",
	"olive_trousers": "legs", "rolled_trousers": "legs",
	"leather_boots": "feet", "work_shoes": "feet",
	"work_gloves": "hands", "copper_pendant": "neck", "copper_ring": "ring",
	"travel_cape": "cape", "travel_pack": "backpack",
	"server_cap": "head", "work_cap": "head", "host_hat": "head",
	"headscarf": "head", "fishing_hat": "head", "straw_hat": "head",
	"house_waistcoat": "body", "waist_apron": "outer",
}
const ITEM_NAMES: Dictionary = {
	"felt_hat": "Felt travelling hat", "cook_hat": "Cook's hat",
	"linen_shirt": "Linen shirt", "short_sleeve_shirt": "Short-sleeved shirt", "leather_vest": "Leather vest",
	"linen_apron": "Linen apron",
	"olive_trousers": "Traveller's trousers", "rolled_trousers": "Rolled trousers",
	"leather_boots": "Leather boots", "work_shoes": "Work shoes",
	"work_gloves": "Work gloves", "copper_pendant": "Copper pendant", "copper_ring": "Copper ring",
	"travel_cape": "Traveller's cape", "travel_pack": "Road pack",
	"server_cap": "Server's cap", "work_cap": "Work cap", "host_hat": "Host's dress cap",
	"headscarf": "Tied headscarf", "fishing_hat": "Fishing hat", "straw_hat": "Straw hat",
	"house_waistcoat": "House waistcoat", "waist_apron": "Waist apron",
}
## The demo lets players try every original garment freely. Existing saves
## receive these only through an explicit draft grant, never during load.
const STARTER_ITEMS: Array[String] = [
	"felt_hat", "cook_hat", "linen_shirt", "short_sleeve_shirt", "leather_vest",
	"linen_apron", "olive_trousers", "rolled_trousers", "leather_boots", "work_shoes",
	"work_gloves", "copper_pendant", "copper_ring", "travel_cape", "travel_pack",
	"server_cap", "work_cap", "host_hat", "headscarf", "fishing_hat", "straw_hat",
	"house_waistcoat", "waist_apron",
]


static func slots() -> Array[String]:
	return SLOTS.duplicate()


static func label(slot: String) -> String:
	return String(SLOT_LABELS.get(slot, slot.capitalize()))


static func items_for_slot(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id in STARTER_ITEMS:
		if EQUIPMENT_IDS[id] == slot:
			out.append(id)
	return out


static func item_name(id: String) -> String:
	return String(ITEM_NAMES.get(id, id.capitalize()))


static func slot_for(id: String) -> String:
	return String(EQUIPMENT_IDS.get(id, ""))


static func known(id: String) -> bool:
	return EQUIPMENT_IDS.has(id)
