class_name ItemDef
extends Resource

## One kind of thing that can exist in the world.
##
## Mirrors the generic item structure from the design notes: an id, a category,
## a stack size, prices and tags. Nothing here is specific to bread or beer --
## the same definition carries an ingredient, a product, and eventually a
## crafted good or a dirty dish.
##
## `shape` selects a procedural mesh rather than naming a model file, the same
## seam the building catalog uses, so prototype art can be replaced wholesale.

enum Category {
	INGREDIENT,
	INTERMEDIATE,
	PRODUCT,
	REFUSE,
}

enum Shape {
	SACK,
	JAR,
	CASK,
	BUNDLE,
	DOUGH,
	LOAF,
	MUG,
	DISHES,
	FISH,
	FILLET,
	FISH_HEAD,
	BOWL,
	FISH_PLATE,
	FRUIT,
	JUG,
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: int = Category.INGREDIENT
@export var shape: int = Shape.SACK
@export var stack_size: int = 10
## What a supplier charges. 0 means it cannot be bought.
@export var purchase_price: int = 0
## What a customer pays, or what it fetches if sold on. 0 means it is not sold.
@export var sell_value: int = 0
## Free-form labels for recipes and storage filters to match on, e.g. "grain",
## "baking". Deliberately strings so content can add its own without a code change.
@export var tags: Array[String] = []
@export var palette: Array[Color] = []


static func make(
	p_id: String,
	p_name: String,
	p_category: int,
	p_shape: int,
	p_stack: int,
	p_buy: int,
	p_sell: int,
	p_tags: Array[String],
	p_palette: Array[Color]
) -> ItemDef:
	var d := ItemDef.new()
	d.id = StringName(p_id)
	d.display_name = p_name
	d.category = p_category
	d.shape = p_shape
	d.stack_size = p_stack
	d.purchase_price = p_buy
	d.sell_value = p_sell
	d.tags = p_tags
	d.palette = p_palette
	return d


func has_tag(tag: String) -> bool:
	return tags.has(tag)
