class_name WorkType
extends RefCounted

## The kinds of work a pawn can be assigned.
##
## Kept as a flat enum with a priority table rather than as classes, because the
## design notes call for a RimWorld-style work matrix: every worker has a
## priority per work type, lower number wins, and 0 means "will not do this".
## That matrix is generic by construction -- adding a work type is one entry
## here and the UI, the board and the worker all pick it up.

enum Kind {
	CONSTRUCT = 0,
	HAUL = 1,
	COOK = 2,
	SERVE = 3,
	CLEAN = 4,
	HOST = 5,
	## Taking something out of the landscape rather than off a supplier: water
	## from the well today, and whatever foraging and farming the notes add
	## later. Its own kind because it is the one sort of work the player might
	## reasonably switch *off* -- free water is only free if the hands drawing it
	## had nothing better to do.
	GATHER = 6,
	## Carrying dirty dishes from the tables to a basin. Split from washing
	## (CLEAN) so the two can belong to different people, as they do in any
	## real kitchen: a busser clears, a scullion washes.
	CLEAR = 7,
	## Bringing the bill and taking the money at the table. A waiter's or a
	## busser's work: whoever collects it promptly earns the tip.
	BILL = 8,
	## Fishing from a fishing spot on the river bank.
	FISH = 9,
	## Planting and harvesting farm plots.
	FARM = 10,
}

const COUNT: int = 11

## 0 means the worker refuses this kind of work. 1 is the most urgent.
const PRIORITY_OFF: int = 0
const PRIORITY_MAX: int = 4


static func display_name(kind: int) -> String:
	match kind:
		Kind.CONSTRUCT: return "Build"
		Kind.HAUL: return "Haul"
		Kind.COOK: return "Cook"
		Kind.SERVE: return "Serve"
		Kind.CLEAN: return "Clean"
		Kind.HOST: return "Host"
		Kind.GATHER: return "Gather"
		Kind.CLEAR: return "Clear"
		Kind.BILL: return "Bill"
		Kind.FISH: return "Fish"
		Kind.FARM: return "Farm"
		_: return "Work"


## Starting priorities for a fresh general labourer.
##
## Everything is switched on, because in a tavern this small everyone mucks in
## and specialising staff is the player's job, not the game's. The ordering is
## what matters: serving first, because somebody at a table is already losing
## patience; then greeting, which is quick and stops the door losing people;
## then building and cooking, with hauling and washing filling the gaps.
##
## Hosting only ever produces work when a host's stand has been built and there
## is somebody unwelcomed at the door, so a high priority costs nothing in a
## tavern without one.
static func default_priorities() -> Dictionary:
	return {
		Kind.SERVE: 1,
		Kind.HOST: 2,
		Kind.CONSTRUCT: 2,
		Kind.COOK: 3,
		Kind.HAUL: 4,
		Kind.CLEAN: 4,
		# On, but last. Drawing water saves real money and costs real time, and
		# which of those the tavern is short of changes hour to hour -- so it
		# fills gaps by default and the player raises it when coin is tighter
		# than hands.
		Kind.GATHER: 4,
		# Clearing a table frees a seat, so it goes ahead of the washing.
		Kind.CLEAR: 3,
		# A patron waiting on the bill holds a table, like dirty plates do.
		Kind.BILL: 2,
		Kind.FISH: 4,
		Kind.FARM: 4,
	}
