class_name TavernNames
extends RefCounted

## A name for a new tavern, offered on the new-game page and used when the
## field is left blank.
##
## Every sandbox used to open as "The Drunken Dwarf", so three saves read as
## the same tavern three times over in the slot list. Its own dice, never the
## simulation's: a name is cosmetic and must not shift what happens in play.

const FIRST: Array[String] = [
	"Drunken", "Prancing", "Sleeping", "Golden", "Rusty", "Merry", "Wandering",
	"Crooked", "Laughing", "Silver", "Thirsty", "Jolly", "Hidden", "Leaky",
	"Copper", "Gilded", "Weary", "Lucky", "Singing", "Green",
]
const SECOND: Array[String] = [
	"Dwarf", "Pony", "Giant", "Goose", "Lantern", "Kettle", "Boar", "Badger",
	"Barrel", "Anchor", "Dragon", "Owl", "Stag", "Tankard", "Wyvern", "Fox",
	"Bell", "Hound", "Griffin", "Pike",
]


## A name not already in `taken`. `rng` makes it repeatable; without one the
## name is a fresh surprise each time.
static func pick(taken: Array = [], rng: RandomNumberGenerator = null) -> String:
	var dice: RandomNumberGenerator = rng
	if dice == null:
		dice = RandomNumberGenerator.new()
		dice.randomize()
	var name: String = ""
	for attempt in range(40):
		name = "The %s %s" % [FIRST[dice.randi() % FIRST.size()], SECOND[dice.randi() % SECOND.size()]]
		if not taken.has(name):
			return name
	return name


## The names of the taverns already saved, so a new one is not mistaken for them.
static func in_saves() -> Array:
	var out: Array = []
	for slot in range(GameState.MAX_SLOTS):
		var summary: Dictionary = GameState.slot_summary(slot)
		if not summary.is_empty():
			out.append(String(summary.get("tavern_name", "")))
	return out
