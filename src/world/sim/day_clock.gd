class_name DayClock
extends Node

## The trading day: opening hours, a rush, and a close of business.
##
## Without a clock the tavern trades forever and there is no way to play badly.
## A day that ends and has to be paid for is what turns the loop into a game --
## it is the thing every other system gets judged against.
##
## Time is a single 0..1 fraction rather than accumulated hours and minutes;
## everything else is derived from it, so speeding the day up or slowing it down
## is one number and nothing drifts out of step.

signal day_started(day: int)
signal tavern_opened
signal tavern_closed
## Emitted once at the end of trading. The clock pauses itself here: the day
## should not roll over until the player has seen the reckoning.
signal day_ended(day: int)

## Real seconds at 1x for a full turn of the clock, midnight to midnight. The
## day starts just before opening, at about 07:30, so what is actually played
## is the last 69% of it: 870 s makes a played day of about ten minutes, as
## asked for (2026-09-28). It was 180 s, which played for only two.
const DEFAULT_DAY_LENGTH: float = 870.0

const OPEN_HOUR: float = 8.0
const CLOSE_HOUR: float = 23.0

var day: int = 1
## 0.0 at midnight, 1.0 at the next midnight.
var fraction: float = OPEN_HOUR / 24.0 - 0.02
var day_length: float = DEFAULT_DAY_LENGTH
var paused: bool = false

var _was_open: bool = false
var _started: bool = false


## Game time arrives here from the world's SimClock, in fixed steps, rather
## than per frame. The processing flag stays the switch that freezes one node --
## tests and letting staff go both use it -- and the summary's hold disables
## the node outright.
func _ready() -> void:
	set_process(true)


func sim_step(delta: float) -> void:
	if not is_processing() or not can_process():
		return
	if paused:
		return

	if not _started:
		_started = true
		day_started.emit(day)

	fraction += delta / maxf(day_length, 1.0)

	var open_now: bool = is_open()
	if open_now and not _was_open:
		tavern_opened.emit()
	elif _was_open and not open_now:
		tavern_closed.emit()
	_was_open = open_now

	if fraction >= 1.0:
		fraction = 1.0
		paused = true
		day_ended.emit(day)


## Begin the next day. Called once the player has dismissed the reckoning.
func advance_day() -> void:
	day += 1
	fraction = OPEN_HOUR / 24.0 - 0.02
	_was_open = false
	_started = true
	paused = false
	day_started.emit(day)


func hour() -> float:
	return fraction * 24.0


func is_open() -> bool:
	var h: float = hour()
	return h >= OPEN_HOUR and h < CLOSE_HOUR


func clock_text() -> String:
	var h: float = hour()
	var hh: int = int(h) % 24
	var mm: int = int((h - floor(h)) * 60.0)
	return "%02d:%02d" % [hh, mm]


func phase_text() -> String:
	if not is_open():
		return "closed"
	var h: float = hour()
	if h < 11.0:
		return "morning"
	if h < 14.5:
		return "midday rush"
	if h < 17.0:
		return "afternoon"
	if h < 21.0:
		return "evening rush"
	return "late"


## How busy the road is right now, as a multiplier on the arrival rate.
##
## Two humps -- midday and evening -- with a quiet stretch between, which is what
## gives the day a shape to staff against rather than a flat trickle. This is the
## "handle a rush" pressure the design notes ask for.
func footfall() -> float:
	if not is_open():
		return 0.0
	var h: float = hour()
	var midday: float = exp(-pow((h - 12.75) / 1.7, 2.0))
	var evening: float = exp(-pow((h - 19.25) / 2.2, 2.0))
	return 0.28 + 1.5 * midday + 1.9 * evening
