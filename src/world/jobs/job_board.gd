class_name JobBoard
extends RefCounted

## The global task queue.
##
## Anything that wants work done posts a Job; idle workers ask for the best one
## they are willing and able to do. Nothing on the board knows what a cook or a
## builder is -- it matches a worker's priority table against each job's kind,
## and breaks ties by distance so pawns do not cross the tavern past a nearer
## task.
##
## This is the piece the design notes lean on hardest, so it is deliberately
## small: post, claim, complete, cancel. Every future system (hauling, cooking,
## serving, cleaning) is expected to be a *poster* rather than a change here.

signal job_posted(job: Job)
signal job_completed(job: Job)
signal job_cancelled(job: Job)

var jobs: Array[Job] = []
## Needed to hold a claim on the goods a job will fetch. Optional: a board
## without one still works, it just cannot stop two jobs racing for one sack.
var items: ItemWorld
var _keys: Dictionary = {}


func post(job: Job) -> Job:
	# Claim the goods before anybody can be sent for them. A refused claim means
	# somebody else already holds them, so the job is not worth posting and the
	# generator will try again next scan against whatever is left.
	if items != null and job.needs_pickup():
		job.reservation = items.reserve([
			{"tile": job.pickup_tile, "count": job.carry_count},
		])
		if job.reservation == 0:
			return job
	jobs.append(job)
	if not job.key.is_empty():
		_keys[job.key] = true
	job_posted.emit(job)
	return job


## Is this intent already queued or being worked on? The generator runs on a
## timer over the whole world, so without this it would re-post the same haul
## every tick and bury the board in duplicates.
func has_key(key: String) -> bool:
	return _keys.has(key)


## Is some job already coming to collect from this tile?
##
## Without this check the same stack attracts two jobs -- a station asking for
## it as an ingredient and the hauler wanting to file it in storage -- and
## whichever worker arrives second finds nothing and gives up. Harmless, but it
## wastes trips and makes the board churn.
func has_pickup(tile: Vector2i) -> bool:
	for job in jobs:
		if job.pickup_tile == tile:
			return true
	return false


## Best open job for a worker, or null.
##
## Priority dominates: a priority-1 job across the map beats a priority-2 job
## underfoot, which is what makes the work matrix meaningful. Distance only
## breaks ties within the same priority.
func best_for(worker: Object, priorities: Dictionary, from_tile: Vector2i) -> Job:
	var best: Job = null
	var best_priority: int = WorkType.PRIORITY_MAX + 1
	var best_urgency: int = -1
	var best_distance: int = 1 << 30

	for job in jobs:
		if not job.can_be_offered_to(worker):
			continue
		var priority: int = priorities.get(job.kind, WorkType.PRIORITY_OFF)
		if priority == WorkType.PRIORITY_OFF:
			continue
		if priority > best_priority:
			continue
		# Chebyshev distance: matches how the pawn actually moves on a grid that
		# allows diagonals, so it does not over-value diagonal targets.
		var delta: Vector2i = job.target - from_tile
		var distance: int = maxi(absi(delta.x), absi(delta.y))
		# Priority, then urgency, then distance. Urgency separates work that
		# unblocks something from work that merely tidies, which distance alone
		# gets exactly backwards.
		var better: bool = priority < best_priority
		if not better and priority == best_priority:
			better = job.urgency > best_urgency
			if not better and job.urgency == best_urgency:
				better = distance < best_distance
		if better:
			best = job
			best_priority = priority
			best_urgency = job.urgency
			best_distance = distance
	return best


func complete(job: Job) -> void:
	_let_go(job)
	jobs.erase(job)
	_keys.erase(job.key)
	job_completed.emit(job)


## Drop one specific job by its key, telling whoever had it to stop.
##
## Needed the moment the player can do a job themselves: a cook still walking to
## the oven for bread that has already been baked by hand would stand there
## producing a second loaf out of ingredients that no longer exist.
func cancel_key(key: String) -> bool:
	for job in jobs:
		if job.key != key:
			continue
		if job.claimant != null and job.claimant.has_method("abandon_job"):
			job.claimant.abandon_job()
		_let_go(job)
		jobs.erase(job)
		_keys.erase(key)
		job_cancelled.emit(job)
		return true
	return false


## Remove a job that is no longer wanted -- the blueprint was demolished, the
## ingredient was taken. Tells the claimant to stop rather than leaving it
## working on something that no longer exists.
func cancel_for_subject(subject: int) -> void:
	for job in jobs.duplicate():
		if job.subject != subject:
			continue
		if job.claimant != null and job.claimant.has_method("abandon_job"):
			job.claimant.abandon_job()
		_let_go(job)
		jobs.erase(job)
		_keys.erase(job.key)
		job_cancelled.emit(job)


## Forget that this worker previously failed at anything. Called periodically so
## a job written off because of a temporary obstruction becomes available again
## once the obstruction is gone.
func clear_failures_for(worker: Object) -> void:
	var id: int = worker.get_instance_id()
	for job in jobs:
		job.failed_for.erase(id)


## Withdraw every waiting job whose goods are no longer where it expects them.
##
## The sweep that removes jobs whose *reason* has gone never caught this, because
## the reason had not gone: the bench was still hungry, so the job stayed wanted.
## Only its source had died. Every worker in turn walked over, found nothing and
## gave up; the job went back on the board still pointing at the empty tile; and
## because its key was still registered, a replacement with a live source could
## never be posted. "Fetch Hops refused by 5" is what that looks like, and it
## stopped the brewing for nine days while the hops sat in storage.
##
## Claimed jobs are left alone -- somebody may be walking over and will find out
## for themselves -- which is also why this runs on every scan: the moment they
## give up, it becomes a waiting job and goes.
## Reopen work held by somebody who no longer exists.
##
## In Godot a freed object compares equal to null, so a job whose claimant was
## freed reads as unclaimed to every `claimant != null` check -- while its state
## still says CLAIMED, so best_for() never offers it to anyone again. The work
## was simply lost, with idle staff standing beside it. Letting a worker go
## could do exactly this; so can anything that frees a pawn in future.
func release_orphans() -> int:
	var reopened: int = 0
	for job in jobs:
		if job.state == Job.State.PENDING or job.state == Job.State.DONE:
			continue
		if is_instance_valid(job.claimant):
			continue
		# Partial work stands: whoever picks it up finishes it, not starts over.
		job.release(null)
		reopened += 1
	return reopened


func withdraw_dead_pickups() -> int:
	if items == null:
		return 0
	var withdrawn: int = 0
	for job in jobs.duplicate():
		if job.claimant != null or not job.needs_pickup():
			continue
		var here: ItemDef = items.def_at(job.pickup_tile)
		var alive: bool = (
			here != null
			and here.id == job.carry_def.id
			and items.available_at(job.pickup_tile, job.reservation) > 0
		)
		if alive:
			continue
		_let_go(job)
		jobs.erase(job)
		_keys.erase(job.key)
		job_cancelled.emit(job)
		withdrawn += 1
	return withdrawn


## Give back a job's claim on its goods. Safe to call twice.
func _let_go(job: Job) -> void:
	if items != null and job.reservation != 0:
		items.release_reservation(job.reservation)
		job.reservation = 0


func clear() -> void:
	for job in jobs:
		if job.claimant != null and job.claimant.has_method("abandon_job"):
			job.claimant.abandon_job()
		_let_go(job)
	jobs.clear()
	_keys.clear()


func open_count() -> int:
	var n: int = 0
	for job in jobs:
		if job.is_open():
			n += 1
	return n


func active_count() -> int:
	return jobs.size() - open_count()


func count_of_kind(kind: int) -> int:
	var n: int = 0
	for job in jobs:
		if job.kind == kind:
			n += 1
	return n
