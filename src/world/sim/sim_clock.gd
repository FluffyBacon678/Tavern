class_name SimClock
extends Node

## The one place simulated time comes from.
##
## Every system that lives in game time -- the day, the job board, the staff,
## the patrons and their feet -- used to read raw frame time in its own
## _process. So there was no pause, no fast-forward, and the same seed played
## out differently on every run, which made every balance figure a matter of
## taking several samples and hoping.
##
## Now the clock turns real time into fixed steps and hands each step to every
## system in the same order. Pause is simply no steps: the tavern freezes the
## way RimWorld's does, while the camera, the hover card and the inspector all
## keep working, because they still run on real time.

## One step of game time. Sixty a second keeps walking smooth at 1x on an
## ordinary display.
const STEP: float = 1.0 / 60.0
## Pause, then the speeds: 1x, 2x, 3x and 5x. The last for the quiet hours
## of a ten-minute day, when nothing needs watching.
const SPEEDS: Array[float] = [0.0, 1.0, 2.0, 3.0, 5.0]
## A slow frame must not turn into a long burst of catch-up: past this many
## steps the backlog is dropped, and the game briefly runs slower instead.
## 5x at 60 fps is 5 steps; this leaves room down to about 15 fps at 5x.
const MAX_STEPS_PER_FRAME: int = 20

signal ticked(dt: float)
signal speed_changed(speed: int)

## Index into SPEEDS; 0 is paused.
var speed: int = 1:
	set(value):
		value = clampi(value, 0, SPEEDS.size() - 1)
		if value == speed:
			return
		if value > 0:
			_resume_speed = value
		speed = value
		speed_changed.emit(speed)
## Held by the world while the day summary is up. Separate from the player's
## pause, so dismissing the summary never unpauses a game the player paused.
var held: bool = false
## Held by the pause menu while it is open. Its own flag, for the same reason
## as `held`: closing the menu must not undo the player's own pause.
var menu_held: bool = false
## Tests only: this many steps every frame, whatever the real time. Lets a
## headless run play six days in seconds, the same way every time.
var turbo_steps: int = 0
## Game seconds elapsed. Tests wait on this rather than the wall clock.
var sim_time: float = 0.0

var _accumulated: float = 0.0
var _resume_speed: int = 1


func _process(real_delta: float) -> void:
	# Paused is paused, at any speed -- turbo included.
	if held or menu_held or speed == 0:
		_accumulated = 0.0
		return
	var steps: int = 0
	if turbo_steps > 0:
		steps = turbo_steps
	else:
		_accumulated += real_delta * SPEEDS[speed]
		steps = mini(int(_accumulated / STEP), MAX_STEPS_PER_FRAME)
		_accumulated -= float(steps) * STEP
		if _accumulated > STEP * float(MAX_STEPS_PER_FRAME):
			_accumulated = 0.0
	for i in range(steps):
		# The day can close on any step, and the summary holds time from that
		# moment -- not from the next frame. At turbo speed a frame is a whole
		# game-second, which is a lot of tavern to keep running behind a hold.
		if held or menu_held:
			_accumulated = 0.0
			break
		sim_time += STEP
		ticked.emit(STEP)


func is_paused() -> bool:
	return speed == 0


## Space: pause, or go back to whatever speed it was at before.
func toggle_pause() -> void:
	speed = 0 if speed > 0 else _resume_speed


## Connect something that lives in game time. It is stepped in the order it
## was attached, every tick, for as long as it exists.
func attach(node: Node) -> void:
	if node != null and node.has_method("sim_step") and not ticked.is_connected(node.sim_step):
		ticked.connect(node.sim_step)
