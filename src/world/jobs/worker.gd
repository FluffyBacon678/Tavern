class_name Worker
extends Node

## Drives a pawn through the claim / fetch / carry / work / finish cycle.
##
## Lives as a child of a Pawn rather than inside it, so the Pawn stays a generic
## body that walks and carries. A customer will be the same Pawn with no Worker
## attached; a cook will be the same Pawn with one.
##
## A job may include a *pickup*: collect goods from one tile and carry them to
## another. Keeping that in a single job rather than splitting it into "go get
## it" and "go put it down" matters, because a worker that is reassigned halfway
## would otherwise strand the goods in its hands with nothing tracking them.
##
## The awkward part of a job system is not the happy path, it is what happens
## when the world changes mid-job: the route disappears, the blueprint is
## demolished, another pawn took the last sack of flour. Everything below that
## looks defensive is one of those cases.

enum State { SEEKING, GOING_PICKUP, GOING, WORKING, HOLDING }

## Work units per second. Skills will scale this later.
const WORK_SPEED: float = 1.0
## Gap between attempts to find a job, so idle pawns do not scan the board
## every frame when there is nothing to do.
const SEEK_INTERVAL: float = 0.45
## How long to tolerate not making progress toward a job before giving it up.
const STUCK_TIMEOUT: float = 6.0
## Jobs to consider in one seek before waiting for the next interval.
const CANDIDATES_PER_SEEK: int = 5
## A job refused once stays refused for this long. Without expiry a worker
## permanently writes off work that only failed because something was in the way
## at the time -- and the world changes constantly while building.
const FORGET_FAILURES_AFTER: float = 8.0

## Why work gets abandoned, counted across every worker.
##
## A job that is claimed and never finished is invisible from the board -- it
## reads as "in progress" forever. These name which of the four ways it failed,
## and they are static because the question is always about the tavern rather
## than about one pair of hands.
static var gave_up_nowhere_to_stand: int = 0
static var gave_up_goods_gone: int = 0
static var gave_up_could_not_walk: int = 0
static var gave_up_cannot_deliver: int = 0
static var gave_up_no_route: int = 0

signal job_started(job: Job)
signal job_finished(job: Job)

var pawn: Pawn
var board: JobBoard
var nav: NavGrid
var items: ItemWorld
## The player's order of work, one number per kind. Kept whole even for kinds
## the position forbids, so a promotion does not lose the settings.
var priorities: Dictionary = {}
## What they were hired as. Decides which of `priorities` count at all.
var role: StaffRole = null

var state: int = State.SEEKING
var current: Job = null

var _seek_timer: float = 0.0
var _stand_tile := Vector2i(-1, -1)
var _stuck_timer: float = 0.0
var _forget_timer: float = FORGET_FAILURES_AFTER
var _carried_count: int = 0
var _carried_def: ItemDef = null
## Goods keep what they are worth while they are being carried. Losing it in
## transit would mean the best bread in the county arrived as ordinary bread.
var _carried_quality: float = ItemWorld.BASE_QUALITY
## Jobs finished since the day began, by WorkType.Kind. A tally rather than
## something derived, because finished work leaves nothing behind to count --
## and "what has this one actually done today?" is the question the inspector
## gets asked about a worker who looks idle.
var done_today: Dictionary = {}


func setup(p_pawn: Pawn, p_board: JobBoard, p_nav: NavGrid, p_items: ItemWorld = null) -> void:
	pawn = p_pawn
	board = p_board
	nav = p_nav
	items = p_items
	set_role(StaffRole.of(&"hand"))


## Hire into a position: its rules, and its starting order of work.
func set_role(p_role: StaffRole) -> void:
	role = p_role if p_role != null else StaffRole.of(&"hand")
	priorities = role.starting_priorities()


## Whether the position allows this kind of work at all.
func allows(kind: int) -> bool:
	return role == null or role.allows(kind)


## The priority this worker actually works to: the player's number, or off
## where the position forbids the work.
func priority_for(kind: int) -> int:
	if not allows(kind):
		return WorkType.PRIORITY_OFF
	return int(priorities.get(kind, WorkType.PRIORITY_OFF))


func effective_priorities() -> Dictionary:
	var out: Dictionary = {}
	for kind in range(WorkType.COUNT):
		out[kind] = priority_for(kind)
	return out


## What they cost at close of business.
func wage() -> int:
	return role.wage if role != null else Ledger.WAGE_PER_STAFF


## Game time arrives here from the world's SimClock, in fixed steps, rather
## than per frame. The processing flag stays the switch that freezes one node --
## tests and letting staff go both use it -- and the summary's hold disables
## the node outright.
func _ready() -> void:
	set_process(true)


func sim_step(delta: float) -> void:
	if not is_processing() or not can_process():
		return
	if pawn == null or board == null:
		return
	if current != null and not current.is_valid():
		board.cancel_key(current.key)
		if current != null:
			abandon_job()

	_forget_timer -= delta
	if _forget_timer <= 0.0:
		_forget_timer = FORGET_FAILURES_AFTER
		board.clear_failures_for(self)

	match state:
		State.SEEKING:
			_process_seeking(delta)
		State.GOING_PICKUP:
			_process_going_pickup(delta)
		State.GOING:
			_process_going(delta)
		State.WORKING:
			_process_working(delta)
		State.HOLDING:
			_seek_timer -= delta
			if _seek_timer <= 0.0:
				_seek_timer = SEEK_INTERVAL
				_drop_carried_at_feet()
				if _carried_count == 0:
					_reset()


func _process_seeking(delta: float) -> void:
	_seek_timer -= delta
	if _seek_timer > 0.0:
		return
	_seek_timer = SEEK_INTERVAL

	# Try several candidates rather than one. The best job may have nowhere to
	# stand, and giving up for a whole seek interval on that basis leaves a
	# worker idle while the board is full of work it could do. Each rejection
	# marks the job, so the next call to best_for returns a different one.
	var job: Job = null
	var stand := Vector2i(-1, -1)
	var working: Dictionary = effective_priorities()
	for attempt in range(CANDIDATES_PER_SEEK):
		var candidate: Job = board.best_for(self, working, pawn.tile)
		if candidate == null:
			return
		var approach: Vector2i = candidate.pickup_tile if candidate.needs_pickup() else candidate.target
		var spot: Vector2i = nav.adjacent_walkable(approach, pawn.tile)
		if spot == Vector2i(-1, -1):
			gave_up_nowhere_to_stand += 1
			candidate.failed_for[get_instance_id()] = true
			continue
		job = candidate
		stand = spot
		break
	if job == null:
		return
	start(job, stand)


## Claim a job and set off towards it, from a stand tile already chosen.
## Returns false if the worker gave up on the spot.
func start(job: Job, stand: Vector2i) -> bool:
	job.claim(self)
	current = job
	_stand_tile = stand
	_stuck_timer = 0.0
	# Take manual control of the body: an idling pawn wandering off mid-job
	# would quietly cancel its own work.
	pawn.autonomous_idle = false

	# Already there is not "no route": find_path from a tile to itself has no
	# steps and reads as failure, which abandoned every job a worker happened to
	# be standing beside -- most often the second leg of a shelf-to-bench fetch.
	if stand != pawn.tile and not pawn.goto(stand):
		# No route at all -- a sealed room, most often. Counted because every
		# other abandonment was, and this is the one that made "refused by 5"
		# look like a mystery rather than a wall.
		gave_up_no_route += 1
		_give_up()
		return false
	state = State.GOING_PICKUP if job.needs_pickup() else State.GOING
	job_started.emit(job)
	return true


func _process_going_pickup(delta: float) -> void:
	if current == null:
		_reset()
		return
	if not _arrived(delta):
		return

	# The goods may be gone: another worker got there first, or a cook consumed
	# them. Dropping the job is correct -- the generator will re-post if there
	# is still a reason to.
	# Against this job's own claim: without the token the worker would see the
	# stock it reserved for itself as spoken for and give up on the spot.
	var available: int = items.available_at(current.pickup_tile, current.reservation) if items != null else 0
	if items == null or available <= 0 or items.def_at(current.pickup_tile).id != current.carry_def.id:
		gave_up_goods_gone += 1
		_give_up()
		return

	_carried_quality = items.quality_at(current.pickup_tile)
	_carried_count = items.take(current.pickup_tile, mini(current.carry_count, available), current.reservation)
	_carried_def = current.carry_def
	pawn.carry(items.make_carry_node(current.carry_def))

	var stand: Vector2i = nav.adjacent_walkable(current.target, pawn.tile)
	if stand == Vector2i(-1, -1) or (stand != pawn.tile and not pawn.goto(stand)):
		gave_up_cannot_deliver += 1
		_drop_carried_at_feet()
		_give_up()
		return
	_stand_tile = stand
	_stuck_timer = 0.0
	state = State.GOING


func _process_going(delta: float) -> void:
	if current == null:
		_reset()
		return
	if not _arrived(delta):
		return

	if _carried_count > 0:
		if not _deposit():
			return
	# A haul has no work in it; arriving *is* the job.
	if current.work_amount <= 0.0:
		current.state = Job.State.DONE
		if current.on_complete.is_valid():
			current.on_complete.call(current)
		_finish()
		return

	current.state = Job.State.ACTIVE
	state = State.WORKING


func _process_working(delta: float) -> void:
	if current == null:
		_reset()
		return
	# The job can be cancelled out from under the worker while it is working.
	if current.state == Job.State.DONE:
		_finish()
		return
	if current.apply_work(WORK_SPEED * delta):
		_finish()


## True once the pawn is standing where the job wants it. Handles the case where
## it stopped short because the route changed under it.
func _arrived(delta: float) -> bool:
	if pawn.is_busy():
		_stuck_timer = 0.0
		return false
	if pawn.tile == _stand_tile:
		return true
	_stuck_timer += delta
	if _stuck_timer < STUCK_TIMEOUT and pawn.goto(_stand_tile):
		return false
	gave_up_could_not_walk += 1
	_give_up()
	return false


func _deposit() -> bool:
	if items == null or _carried_def == null:
		return false
	var placed: int = items.add(_carried_def, _carried_count, current.target, _carried_quality)
	# Whatever will not fit goes on the floor near the worker rather than
	# evaporating. A stray stack is a visible problem the hauler will come back
	# for; a silently deleted one is a bug nobody notices until the books stop
	# balancing.
	if placed < _carried_count:
		placed += items.place_near(_carried_def, _carried_count - placed, pawn.tile, 6, _carried_quality, false)
	_carried_count -= placed
	if _carried_count > 0:
		return false
	_clear_cargo()
	return true


func _drop_carried_at_feet() -> void:
	if _carried_count > 0 and items != null and _carried_def != null:
		_carried_count -= items.place_near(_carried_def, _carried_count, pawn.tile, 6, _carried_quality, false)
	if _carried_count == 0:
		_clear_cargo()


func _clear_cargo() -> void:
	_carried_count = 0
	_carried_def = null
	pawn.carry(null)


## Loading cargo does not recreate the old job. It remains physically held
## until a legal drop is available, then normal derivation resumes.
func restore_cargo(def: ItemDef, count: int, quality: float) -> void:
	_carried_def = def
	_carried_count = maxi(count, 0)
	_carried_quality = quality
	if _carried_count > 0 and def != null:
		pawn.carry(items.make_carry_node(def))
		_reset()


func _finish() -> void:
	var job: Job = current
	done_today[job.kind] = int(done_today.get(job.kind, 0)) + 1
	board.complete(job)
	job_finished.emit(job)
	_reset()


## Release the job back to the board and look for something else.
func _give_up() -> void:
	_drop_carried_at_feet()
	if current != null:
		current.release(self)
	_reset()


## Called by the board when the job's subject stops existing.
func abandon_job() -> void:
	_drop_carried_at_feet()
	current = null
	pawn.stop()
	_reset()


func _reset() -> void:
	current = null
	state = State.HOLDING if _carried_count > 0 else State.SEEKING
	_stand_tile = Vector2i(-1, -1)
	_stuck_timer = 0.0
	_seek_timer = 0.0
	if pawn != null:
		pawn.autonomous_idle = _carried_count == 0


func reset_day_tally() -> void:
	done_today.clear()


## What this worker is physically holding, so stock counts can include goods in
## transit. Without it the books dip every time somebody picks something up.
func carried_def() -> ItemDef:
	return _carried_def if _carried_count > 0 else null


func carried_count() -> int:
	return _carried_count


func carried_quality() -> float:
	return _carried_quality


func status_text() -> String:
	if state == State.HOLDING:
		return "waiting for space to put down %s" % _carried_def.display_name.to_lower()
	if current == null:
		return "idle"
	match state:
		State.GOING_PICKUP:
			return "fetching %s" % (current.carry_def.display_name.to_lower() if current.carry_def else "goods")
		State.GOING:
			if _carried_count > 0:
				return "carrying %s" % (current.carry_def.display_name.to_lower() if current.carry_def else "goods")
			return "walking to %s" % WorkType.display_name(current.kind).to_lower()
		State.WORKING:
			if not current.blocked_reason.is_empty():
				return current.blocked_reason
			return "%s (%d%%)" % [current.label.to_lower(), int(current.progress() * 100.0)]
	return "idle"
