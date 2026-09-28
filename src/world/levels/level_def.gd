class_name LevelDef
extends RefCounted

## A designed starting situation: a tavern somebody already built, and a target.
##
## Distinct from the scenario layouts in `dev/`, which exist to exercise systems
## and build for free. A level is content: it is what a player loads, it is
## costed against the purse it hands out, and it is meant to be *unbalanced* in
## specific ways the player has to notice and fix.
##
## Data, not code. Everything here is a list or a number, so a second level is
## another entry in the catalog and nothing else anywhere -- the same rule the
## building, item and recipe catalogs follow.

## One piece of the starting tavern: what, where, turned how far.
class Piece:
	extends RefCounted
	var id: StringName
	var tile: Vector2i
	var rotation: int

	func _init(p_id: String, p_tile: Vector2i, p_rotation: int = 0) -> void:
		id = StringName(p_id)
		tile = p_tile
		rotation = p_rotation


## Where the level's building stands on the plot, from its north-west corner.
## Pieces are placed from it, and so is anything a test adds to the building.
var origin: Vector2i = Vector2i.ZERO
var id: StringName = &""
var display_name: String = ""
## Shown once when the level opens. Says what you have inherited, never what to
## do about it -- working that out is the game.
var briefing: String = ""
var tavern_name: String = ""
var world_seed: int = 0
var starting_gold: int = 0
## Laid out relative to the plot's corner, so the level survives a change to
## where the plot sits on the map.
var pieces: Array[Piece] = []
## Goods already in the larder, as { id: count }.
var stock: Dictionary = {}

## The target, and the day it must be met by. Zero days means "no deadline".
var goal_gold: int = 0
## The tutorial: no goal, no briefing, and the TutorialDirector runs the show.
var is_tutorial: bool = false
var goal_days: int = 0
var goal_text: String = ""


enum Outcome { OPEN, WON, LOST }


## Won, lost, or still to play for -- judged at each close of business, since
## the goal says "by the end of day N".
##
## Derived from the ledger's closed days rather than tracked, so it survives a
## reload with nothing extra saved, and cannot drift. It used to read the live
## purse, which let a goal be "met" on day nine after the deadline had passed,
## and un-met again by a morning's wages.
func outcome(world) -> int:
	return int(_decision(world)["outcome"])


## The day the outcome was settled, or -1 while it is still open.
func decided_on(world) -> int:
	return int(_decision(world)["day"])


func _decision(world) -> Dictionary:
	if goal_gold <= 0 or world == null or world.ledger == null:
		return {"outcome": Outcome.OPEN, "day": -1}
	var closes: Array = world.ledger.history.duplicate()
	closes.sort_custom(func(a, b) -> bool: return int(a["day"]) < int(b["day"]))
	for entry in closes:
		var day: int = int(entry.get("day", 0))
		if goal_days > 0 and day > goal_days:
			break
		if int(entry.get("purse", 0)) >= goal_gold:
			return {"outcome": Outcome.WON, "day": day}
		if goal_days > 0 and day == goal_days:
			return {"outcome": Outcome.LOST, "day": day}
	return {"outcome": Outcome.OPEN, "day": -1}


func progress_text(world) -> String:
	if goal_gold <= 0:
		return ""
	match outcome(world):
		Outcome.WON:
			return "%s — done by the close of day %d" % [goal_text, decided_on(world)]
		Outcome.LOST:
			return "%s — missed; trading on" % goal_text
	if goal_days > 0:
		return "%s — %dg of %dg, day %d of %d" % [
			goal_text, GameState.gold, goal_gold, world.clock.day, goal_days]
	return "%s — %dg of %dg" % [goal_text, GameState.gold, goal_gold]


## What the day summary announces on the close that settled it, or {} on any
## other close. Shown once, on that day, not every evening after.
func verdict_for(world, day: int) -> Dictionary:
	var decision: Dictionary = _decision(world)
	if int(decision["day"]) != day:
		return {}
	var purse: int = 0
	for entry in world.ledger.history:
		if int(entry.get("day", -1)) == day:
			purse = int(entry.get("purse", 0))
	if int(decision["outcome"]) == Outcome.WON:
		var early: String = ""
		if goal_days > 0 and day < goal_days:
			early = ", %d day%s early" % [goal_days - day, "" if goal_days - day == 1 else "s"]
		return {"won": true, "title": "%s is yours" % tavern_name,
			"text": "%dg in the purse at the close of day %d%s. The goal was %dg by day %d." % [
				purse, day, early, goal_gold, goal_days]}
	return {"won": false, "title": "Short of the mark",
		"text": "%dg at the close of day %d, against %dg. Keep trading to see it through, or try the level again from the menu." % [
			purse, day, goal_gold]}
