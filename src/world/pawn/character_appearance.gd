class_name CharacterAppearance
extends RefCounted

## Explicit cosmetic data shared by an owner, employee and visiting traveller.
## Parsing and copying never draw randomness from a world or pawn stream.
const VERSION: int = 1
const FACE_TYPES: Array[String] = ["Balanced", "Soft", "Angular", "Broad"]
const EXPRESSIONS: Array[String] = ["Warm smile", "Grin", "Calm", "Smirk", "Stern"]
const SKIN_COLORS: Array[Color] = [Color("f0c39c"), Color("d9a77c"), Color("c08a5e"), Color("8a5f3c"), Color("63412e")]
const HAIR_COLORS: Array[Color] = [Color("36291e"), Color("614127"), Color("ac7c37"), Color("853e25"), Color("c0b49a")]
const TOP_COLORS: Array[Color] = [Color("e8e0cc"), Color("587442"), Color("345793"), Color("853c52"), Color("ab7730")]
const TROUSER_COLORS: Array[Color] = [Color("586044"), Color("4a3f33"), Color("363f4a"), Color("454449")]
const BOOT_COLORS: Array[Color] = [Color("67452f"), Color("50372b"), Color("825239"), Color("454449")]

var body_type: int = 0
var skin: Color = SKIN_COLORS[1]
var hair: Color = HAIR_COLORS[1]
var hair_style: int = 0
## Optional version-one cosmetics: older profiles retain a balanced warm smile.
var face_type: int = 0
var expression: int = 0
var top: Color = TOP_COLORS[0]
var trousers: Color = TROUSER_COLORS[0]
var boots: Color = BOOT_COLORS[0]
## -1 is a custom ordinary outfit; 0 staff; 1..6 the legacy NPC outfit families.
## Family is a visual preset only. Pawn.adventurer stores guest behaviour.
var family: int = -1
var style: int = 0
var cape_index: int = 0
var variant: int = 0
var uniform: Color = Color(0, 0, 0, 0)


func to_save() -> Dictionary:
	return {"version": VERSION, "body_type": body_type, "skin": skin.to_html(),
		"hair": hair.to_html(), "hair_style": hair_style, "face_type": face_type,
		"expression": expression, "top": top.to_html(),
		"trousers": trousers.to_html(), "boots": boots.to_html(), "family": family,
		"style": style, "cape_index": cape_index, "variant": variant, "uniform": uniform.to_html()}


func clone() -> CharacterAppearance:
	return from_save(to_save())


## Invalid optional cosmetics fall back field by field; they never invalidate
## a tavern's buildings, inventory or finances. Unknown versions use the base.
static func from_save(data: Variant, fallback: CharacterAppearance = null) -> CharacterAppearance:
	var out := CharacterAppearance.new()
	if fallback != null:
		out.body_type = fallback.body_type
		out.skin = fallback.skin
		out.hair = fallback.hair
		out.hair_style = fallback.hair_style
		out.face_type = fallback.face_type
		out.expression = fallback.expression
		out.top = fallback.top
		out.trousers = fallback.trousers
		out.boots = fallback.boots
		out.family = fallback.family
		out.style = fallback.style
		out.cape_index = fallback.cape_index
		out.variant = fallback.variant
		out.uniform = fallback.uniform
	if not data is Dictionary or not _valid_integer(data.get("version"), VERSION, VERSION):
		return out
	for key in ["body_type", "hair_style", "face_type", "expression", "family", "style", "cape_index", "variant"]:
		var low: int = -1 if key == "family" else 0
		var high: int = {"body_type": 1, "hair_style": 3, "face_type": FACE_TYPES.size() - 1,
			"expression": EXPRESSIONS.size() - 1, "family": 6, "style": 63, "cape_index": 7, "variant": 3}[key]
		if _valid_integer(data.get(key), low, high):
			out.set(key, int(data[key]))
	for key in ["skin", "hair", "top", "trousers", "boots", "uniform"]:
		var value: Variant = data.get(key)
		if value is String and value.length() in [6, 8] and Color.html_is_valid(value):
			var colour := Color(value)
			if key != "uniform":
				colour.a = 1.0
			out.set(key, colour)
	return out


static func _valid_integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floor(float(value)) and value >= low and value <= high
