class_name PawnWardrobe
extends RefCounted

## Matched dyes keep each guest coherent: one strong cloth, one quieter lining,
## and a small contrasting accent. These are cosmetic choices, never classes.
const DYES: Array[Dictionary] = [
	{"name": "cobalt", "cloth": Color("345793"), "lining": Color("c9b58b"), "trim": Color("b98a43"), "gem": Color("66bac9")},
	{"name": "plum", "cloth": Color("764373"), "lining": Color("c7b9cb"), "trim": Color("b5bdc4"), "gem": Color("e59db4")},
	{"name": "teal", "cloth": Color("28796d"), "lining": Color("b7c9b0"), "trim": Color("bf9252"), "gem": Color("7bd4b3")},
	{"name": "saffron", "cloth": Color("ab7730"), "lining": Color("d6c3a1"), "trim": Color("765244"), "gem": Color("74b9d7")},
	{"name": "wine", "cloth": Color("853c52"), "lining": Color("d3b799"), "trim": Color("c39a56"), "gem": Color("d7777e")},
	{"name": "moss", "cloth": Color("587442"), "lining": Color("c5c6a2"), "trim": Color("b68a52"), "gem": Color("b8d36c")},
	{"name": "ember", "cloth": Color("a05235"), "lining": Color("d2b58b"), "trim": Color("bc9f69"), "gem": Color("e7aa55")},
	{"name": "indigo", "cloth": Color("514885"), "lining": Color("bbb9d0"), "trim": Color("aaaeb9"), "gem": Color("af9ad8")},
]
const LEATHERS: Array[Color] = [Color("6b4a2e"), Color("50372b"), Color("825239"), Color("454449")]


## Read the existing RNG state, without drawing from it. Skin and the original
## appearance draws remain unchanged; facing, timers and saves keep their stream.
static func variant_for_state(state: int) -> int:
	return int((state ^ (state >> 17) ^ (state >> 41)) & 3)


static func apply(outfit: Dictionary, style: int, variant: int) -> void:
	var dye: Dictionary = DYES[(style / 6 + variant * 2) % DYES.size()]
	outfit["variant"] = variant
	outfit["hair_style"] = variant
	outfit["emblem"] = variant
	outfit["cape_pattern"] = variant
	outfit["accent"] = dye["gem"]
	outfit["edge"] = dye["trim"]
	outfit["book_colour"] = dye["cloth"]
	if variant == 0:
		return
	var cloth: Color = dye["cloth"]
	var lining: Color = dye["lining"]
	var trim: Color = dye["trim"]
	var leather: Color = LEATHERS[variant]
	match style % 6:
		0: # Armour remains the metal tier; dyes belong to cloth and heraldry.
			outfit["cape"] = cloth
			outfit["trim"] = cloth
			outfit["tabard"] = variant % 2 == 1
			outfit["headgear"] = "med_helm" if variant == 2 else "full_helm"
			outfit["description"] += " with %s heraldry" % dye["name"]
		1:
			outfit["body"] = cloth
			outfit["sleeve"] = cloth
			outfit["cuff"] = trim
			outfit["legs"] = cloth.darkened(0.15)
			outfit["headgear"] = "hood" if variant == 1 else ("circlet" if variant == 3 else "wizard_hat")
			outfit["headgear_colour"] = cloth
			outfit["beard"] = variant == 2
			outfit["jewel"] = dye["gem"]
			outfit["description"] = "a %s-robed mage" % dye["name"]
		2:
			outfit["body"] = leather
			outfit["sleeve"] = cloth.darkened(0.12)
			outfit["cuff"] = leather.darkened(0.2)
			outfit["hands"] = leather
			outfit["cape"] = cloth
			outfit["headgear"] = ["hood", "", "hood", "feather_hat"][variant]
			outfit["headgear_colour"] = cloth.darkened(0.1)
			outfit["description"] = "a ranger in %s with a hunting bow" % dye["name"]
		3:
			outfit["body"] = [Color("7a7d80"), Color("887658"), Color("586775"), Color("777b72")][variant]
			outfit["sleeve"] = outfit["body"].darkened(0.12)
			outfit["trim"] = cloth
			outfit["cuff"] = leather
			outfit["headgear"] = ["coif", "hood", "", "med_helm"][variant]
			outfit["headgear_colour"] = cloth if variant == 1 else outfit["body"]
			outfit["description"] = "a delver wearing %s, carrying a bedroll" % dye["name"]
		4:
			outfit["body"] = cloth
			outfit["sleeve"] = lining
			outfit["cape"] = cloth.darkened(0.12)
			outfit["cuff"] = cloth.darkened(0.2)
			outfit["headgear_colour"] = cloth.darkened(0.35)
			outfit["description"] = "a duelist in a %s doublet" % dye["name"]
		5:
			outfit["body"] = cloth if variant == 1 else lining
			outfit["sleeve"] = outfit["body"]
			outfit["cape"] = lining.darkened(0.15) if variant == 1 else cloth
			outfit["cuff"] = trim
			outfit["headgear"] = "circlet" if variant == 2 else "hood"
			outfit["headgear_colour"] = outfit["body"]
			outfit["jewel"] = dye["gem"]
			outfit["description"] = "a wandering scholar in %s and linen" % dye["name"]
