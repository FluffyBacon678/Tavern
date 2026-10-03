class_name StaffUniforms
extends RefCounted

## Role is saved by Worker already. These visual defaults consume no randomness
## and never write over a person's explicit equipment or appearance descriptor.
const KITS: Dictionary = {
	"waiter": {"head": "server_cap", "body": "house_waistcoat", "outer": "waist_apron"},
	"busser": {"head": "work_cap", "body": "short_sleeve_shirt", "outer": "waist_apron"},
	"host": {"head": "host_hat", "body": "house_waistcoat", "neck": "copper_pendant"},
	"cook": {"head": "cook_hat", "body": "short_sleeve_shirt", "outer": "linen_apron"},
	"porter": {"head": "work_cap", "body": "house_waistcoat", "hands": "work_gloves"},
	"cleaner": {"head": "headscarf", "body": "short_sleeve_shirt", "outer": "linen_apron"},
	"fisherman": {"head": "fishing_hat", "body": "short_sleeve_shirt", "hands": "work_gloves"},
	"farmer": {"head": "straw_hat", "body": "short_sleeve_shirt", "legs": "rolled_trousers", "hands": "work_gloves"},
}


static func equipment_for(role_id: StringName) -> Dictionary:
	return KITS.get(String(role_id), {}).duplicate()


static func hat_colour(role_id: StringName, uniform: Color) -> Color:
	match role_id:
		&"farmer": return Color("c9a45b")
		&"cleaner": return Color("8eb7b4")
		&"cook": return Color("e8e0cc")
	return uniform
