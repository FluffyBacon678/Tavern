class_name Job
extends RefCounted

## One unit of work: what kind, where, how much, and what to do when it is done.
##
## Jobs are deliberately dumb. They carry no behaviour beyond tracking progress;
## the worker drives the walk-and-work cycle and the poster supplies a callback
## for the outcome. That keeps the board reusable for hauling, cooking and
## serving without any of them knowing about each other.
##
## `failed_for` exists because the alternative -- dropping an unreachable job
## back on the board -- makes every idle worker pick it up, fail, and drop it
## again, forever. Recording who failed lets the board skip offering it back to
## the same pawn while still leaving it available to someone else.

enum State { PENDING, CLAIMED, ACTIVE, DONE, FAILED }

var kind: int = WorkType.Kind.CONSTRUCT
## The thing being worked on. The worker stands next to it, not on it.
var target: Vector2i = Vector2i.ZERO
## Seconds of work at normal speed.
var work_amount: float = 1.0
var work_done: float = 0.0
var state: int = State.PENDING
var label: String = ""
## Called with this job when the work finishes.
var on_complete: Callable = Callable()
## A removed station invalidates its old job even if cancellation was missed.
var validity: Callable = Callable()
var blocked_reason: String = ""
var _completion_retry: float = 0.0
## Identifies what this job is about, so a poster can cancel by subject --
## demolishing a blueprint has to cancel the job that would build it.
var subject: int = -1

## Optional fetch step. When set, the worker collects from here first and
## carries the goods to `target`. One job rather than two means a half-finished
## haul cannot be orphaned by a worker that dies or is reassigned between them.
var pickup_tile := Vector2i(-1, -1)
var carry_def: ItemDef = null
var carry_count: int = 1

## Stable identity for a job's *intent*, so the generator can avoid posting the
## same work twice while it is already queued or being done.
var key: String = ""

## Ranked above distance, below work priority. Higher is picked first.
##
## Exists because feeding a bench and filing goods away are the same *kind* of
## work, so a worker chose between them on distance alone -- and filing is
## always nearer, because the goods being filed are already underfoot. The
## kitchen starved beside a full larder while the staff tidied around it: over
## one run, eight ingredient deliveries against fifty-nine trips to the shelves,
## with three of five workers idle.
##
## The comment on the hauling rule claimed "feeding a workstation beats filing
## goods away", and it was only ever true of the order things were *posted* in.
var urgency: int = 0

## Claim on the stock this job intends to collect, held from the moment it is
## posted until it leaves the board.
##
## Without one, several jobs set off for the same sack and all but the first
## arrive to find it gone -- 128 wasted trips in one measured run. Checking the
## board at *posting* time is not enough: the loser can be claimed after the
## winner has already been posted.
var reservation: int = 0


var claimant: Object = null
var failed_for: Dictionary = {}


func needs_pickup() -> bool:
	return pickup_tile != Vector2i(-1, -1) and carry_def != null


func progress() -> float:
	return clampf(work_done / maxf(work_amount, 0.0001), 0.0, 1.0)


func is_open() -> bool:
	return state == State.PENDING and is_valid()


func is_valid() -> bool:
	return not validity.is_valid() or bool(validity.call())


## Add work. Returns true when the job has just been finished by this tick.
func apply_work(amount: float) -> bool:
	if state == State.DONE:
		return false
	work_done += amount
	if work_done < work_amount:
		return false
	work_done = work_amount
	_completion_retry -= amount
	if _completion_retry > 0.0:
		return false
	if on_complete.is_valid():
		var result = on_complete.call(self)
		if result is bool and not result:
			_completion_retry = 0.45
			return false
	state = State.DONE
	return true


func claim(worker: Object) -> void:
	claimant = worker
	state = State.CLAIMED


## Return the job to the board, remembering that this worker could not do it.
func release(worker: Object, permanent_for_worker: bool = true) -> void:
	if permanent_for_worker and worker != null:
		failed_for[worker.get_instance_id()] = true
	claimant = null
	state = State.PENDING


func can_be_offered_to(worker: Object) -> bool:
	return is_open() and not failed_for.has(worker.get_instance_id())
