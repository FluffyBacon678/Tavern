class_name GuestType
extends RefCounted

## What kind of adventurer a guest is, and so what they want from the tavern.
##
## Initially seeded by their outfit, then stored as Pawn.adventurer separately
## so wearing different clothes never changes their tastes. The ordinary
## guest (`of()` for anything unlisted) is the one the game had before types:
## every number here at 1.0 reproduces the old behaviour exactly.

var id: StringName
var title: String = "Traveller"
## One line for the hover card: what this kind of guest cares about.
var wants: String = ""
## Chance they want a dish, and a drink. At 0.7 each, most want both.
var food_chance: float = 0.7
var drink_chance: float = 0.7
var most_dishes: int = 1
var most_drinks: int = 2
## Picks the dearest dish on the menu rather than one at random.
var dearest: bool = false
## Multiplies every wait they will put up with.
var patience: float = 1.0
## Multiplies the tip.
var tip: float = 1.0
## How much each part of the review counts for them, by Review.Part. For FOOD
## only the choice on the menu is weighted, not the cooking.
var cares: Dictionary = {}

static var _types: Dictionary = {}


static func make(p_id: StringName, p_title: String, p_wants: String) -> GuestType:
	var t := GuestType.new()
	t.id = p_id
	t.title = p_title
	t.wants = p_wants
	return t


## The type for a guest's stored archetype (legacy PawnMesh.Look IDs).
static func of(look: int) -> GuestType:
	if _types.is_empty():
		_build()
	return _types.get(look, _types[-1])


static func _build() -> void:
	var L = PawnMesh.Look
	var ordinary := make(&"traveller", "Traveller", "")
	_types[-1] = ordinary

	var warrior := make(&"warrior", "Warrior", "Drinks hard: wants beer, and plenty of it.")
	warrior.drink_chance = 0.9
	warrior.most_drinks = 3
	warrior.tip = 0.8
	_types[L.WARRIOR] = warrior

	var wizard := make(&"wizard", "Wizard", "Wants a choice: a short menu disappoints them.")
	wizard.food_chance = 0.8
	wizard.patience = 1.2
	wizard.tip = 1.3
	wizard.cares = {Review.Part.FOOD: 2.0}
	_types[L.WIZARD] = wizard

	var ranger := make(&"ranger", "Ranger", "In a hurry: slow service costs you most with them.")
	ranger.patience = 0.75
	ranger.cares = {Review.Part.SERVICE: 1.5}
	_types[L.RANGER] = ranger

	var delver := make(&"delver", "Delver", "Hungry after the dungeon: often orders two plates. Tips little.")
	delver.food_chance = 0.9
	delver.most_dishes = 2
	delver.tip = 0.7
	delver.patience = 1.1
	_types[L.ADVENTURER] = delver

	var duelist := make(&"duelist", "Duelist", "Orders the dearest dish, and tips well for it.")
	duelist.dearest = true
	duelist.tip = 1.5
	duelist.patience = 0.9
	_types[L.DUELIST] = duelist

	var pilgrim := make(&"pilgrim", "Pilgrim", "Barely drinks, and minds a dirty table.")
	pilgrim.food_chance = 0.9
	pilgrim.drink_chance = 0.25
	pilgrim.patience = 1.2
	pilgrim.cares = {Review.Part.CLEANLINESS: 2.0}
	_types[L.PILGRIM] = pilgrim
