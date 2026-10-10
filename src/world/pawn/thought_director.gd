class_name ThoughtDirector
extends Node

## Keeps every bubble saying what its person is doing, a few times a second.
##
## Reads the simulation and never touches it: this runs on the frame clock,
## not game time, so it cannot change how a seeded run plays out.

const INTERVAL: float = 0.3
## A waiting guest's bubble goes red below this much patience left.
const URGENT: float = 0.3

var world  ## TavernWorld
var _timer: float = 0.0
var _were_on: bool = true


func setup(p_world) -> void:
	world = p_world
	GameSettings.changed.connect(_on_settings_changed)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or world == null:
		return
	_timer = INTERVAL
	var on: bool = GameSettings.thought_bubbles
	if not on and not _were_on:
		return
	_were_on = on
	for worker in world.workers:
		if is_instance_valid(worker) and is_instance_valid(worker.pawn):
			worker.pawn.think(worker_icon(worker) if on else "")
	if world.customers == null:
		return
	for brain in world.customers.customers:
		if is_instance_valid(brain) and is_instance_valid(brain.pawn):
			var patience: float = brain.patience_fraction()
			brain.pawn.think(guest_icon(brain) if on else "", patience >= 0.0 and patience < URGENT)


## What a member of staff is up to, as a bubble.
static func worker_icon(worker: Worker) -> String:
	var job: Job = worker.current
	if job == null:
		return "idle"
	return job_icon(job)


## The bubble for a kind of work: the staff's, the keeper's and the keeper's
## options menu all draw it.
static func job_icon(job: Job) -> String:
	match job.kind:
		WorkType.Kind.CONSTRUCT:
			return "build"
		WorkType.Kind.HAUL:
			return "haul"
		WorkType.Kind.COOK:
			if job.key.begins_with("plate:"):
				return "serve"
			return "haul" if job.carry_def != null else "cook"
		WorkType.Kind.SERVE:
			return "order" if job.key.begins_with("take:") else "serve"
		WorkType.Kind.BILL:
			return "coin"
		WorkType.Kind.CLEAN:
			return "clean"
		WorkType.Kind.CLEAR:
			return "clear"
		WorkType.Kind.HOST:
			return "host"
		WorkType.Kind.GATHER:
			return "gather"
		WorkType.Kind.FISH:
			return "fish"
		WorkType.Kind.FARM:
			return "farm"
	return ""


## What a guest wants, as a bubble.
static func guest_icon(brain: CustomerBrain) -> String:
	match brain.state:
		CustomerBrain.State.SEEKING_SEAT:
			return "seat"
		CustomerBrain.State.ORDERING:
			return "menu"
		CustomerBrain.State.READY_TO_ORDER:
			return "hand"
		CustomerBrain.State.WAITING_FOR_ORDER:
			return "wait"
		CustomerBrain.State.EATING:
			return "eat"
		CustomerBrain.State.WAITING_FOR_BILL, CustomerBrain.State.PAYING:
			return "coin"
		CustomerBrain.State.GOING_TO_BAR:
			return "order"
		CustomerBrain.State.BACK_FROM_BAR:
			return "serve" if brain.at_bar else "hand"
		CustomerBrain.State.LEAVING:
			return "happy" if brain._food_eaten > 0 else "angry"
	return ""


func _on_settings_changed() -> void:
	if world == null:
		return
	var on: bool = GameSettings.outline_people
	for pawn in world.pawns:
		if is_instance_valid(pawn):
			pawn.set_outline(on)
	if world.customers != null:
		for brain in world.customers.customers:
			if is_instance_valid(brain) and is_instance_valid(brain.pawn):
				brain.pawn.set_outline(on)
