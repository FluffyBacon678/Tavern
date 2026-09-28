class_name SimWait
extends RefCounted

## Test time: waiting in game seconds, and running them as fast as the machine
## allows.
##
## The long suites used to wait on the wall clock, so six real game days took a
## quarter of an hour and no two runs of the same seed came out alike: the
## simulation stepped by however long each frame happened to take. Now the
## SimClock runs a fixed number of steps per frame and the suites wait on
## `sim_time`, which makes a run both fast and repeatable. Pass `realtime`
## after `--` to watch one at ordinary speed instead.

## One game-second per rendered frame. Far past any speed a player can pick,
## and on this machine a real-length day plays out in a couple of seconds.
const TURBO_STEPS: int = 60

## Global randomness still decides one thing in the simulation -- the patron
## director's own seed, drawn when a world is built -- so a suite seeds it to
## make that repeatable too.
const RANDOM_SEED: int = 20260927


## Set a world running at test speed, unless `realtime` was asked for.
## Returns a label for the suite's banner.
static func configure(world) -> String:
	if OS.get_cmdline_user_args().has("realtime"):
		world.sim.turbo_steps = 0
		return "real time"
	world.sim.turbo_steps = TURBO_STEPS
	return "turbo, %d steps a frame" % TURBO_STEPS


## Seed the global generator before a world is made. Call it first.
static func seed_run(value: int = RANDOM_SEED) -> void:
	seed(value)


## Keep a freshly made world's clock stopped while a suite sets it up.
##
## A world made during a suite's _ready starts stepping on the very first frame;
## one made mid-frame starts on the next. Either way the suite's opening moves
## -- the purchases, the first order -- landed a frame of game time apart, and
## at turbo speed a frame is a game-second: the same branch played out
## differently depending on whether another world had run before it. Holding
## the clock until the setup is done puts every opening move at game time zero.
static func hold(world) -> void:
	world.sim.speed = 0


## Start the clock, exactly now. Everything scripted before this call happened
## at game time zero.
static func release(world) -> void:
	world.sim.speed = 1


## Wait until this many game seconds have passed in `world`.
##
## Game time does not pass while the day summary holds the clock, so a caller
## must be dismissing summaries or this waits for ever -- every suite that
## uses it does.
static func seconds(world, amount: float) -> void:
	var until: float = world.sim.sim_time + amount
	while is_instance_valid(world) and world.sim.sim_time < until:
		await world.get_tree().process_frame
