class_name TutorialStep
extends RefCounted

## One thing the tutorial asks the player to do.
##
## Written once, used twice: the in-game TutorialDirector shows `text` and
## `why`, highlights `highlight` and checks `done`; the smoke test
## (dev/tutorial_smoke.tscn) calls `perform` -- the player's own actions --
## and checks the same `done`. A step the automated player cannot complete
## through the player's actions is a bug in the game, which is the point.
##
## `done`, `begin` and `perform` take (world, ctx): `ctx` is the tutorial's
## scratch memory, shared by all steps, for "has the view moved since this step
## began" and the like. Done-conditions read the world; nothing is ticked by
## pressing Next.

## Whether time waits while the step is done, or runs for it to happen.
enum Pace { PAUSED, RUN }

var id: String = ""
var lesson: String = ""
var text: String = ""
var why: String = ""
## What to point at. Any of:
##   {"button": "Build"}          a HUD button, by the start of its text
##   {"tiles": Rect2i}            ground to outline
##   {"role": &"porter"}          a person, by position
## A Callable returning one of those is resolved when the step begins.
var highlight = {}
var pace: int = Pace.PAUSED
## Game seconds the smoke test allows for `done` once `perform` has run.
var budget: float = 5.0
var done: Callable
var begin: Callable
var perform: Callable
## (world, ctx) -> bool: the player has plainly gone past this step without
## doing it. The director then moves on quietly instead of holding them on an
## instruction they have outgrown. Unset for anything the tutorial must teach.
var moved_on: Callable


static func make(p_id: String, p_lesson: String, p_text: String, p_why: String,
		p_done: Callable, p_perform: Callable) -> TutorialStep:
	var step := TutorialStep.new()
	step.id = p_id
	step.lesson = p_lesson
	step.text = p_text
	step.why = p_why
	step.done = p_done
	step.perform = p_perform
	return step


## Chainable setters, so the plan reads as a list.
func pointing_at(target) -> TutorialStep:
	highlight = target
	return self


func running(seconds: float) -> TutorialStep:
	pace = Pace.RUN
	budget = seconds
	return self


func starting(callable: Callable) -> TutorialStep:
	begin = callable
	return self


func unless(callable: Callable) -> TutorialStep:
	moved_on = callable
	return self


func resolved_highlight(world) -> Dictionary:
	if highlight is Callable:
		return (highlight as Callable).call(world)
	return highlight if highlight is Dictionary else {}
