class_name Reputation
extends RefCounted

## What the town thinks of the place, and what that is worth in customers.
##
## A rolling mean over the last MEMORY visits rather than a lifetime average: a
## tavern that was bad for a week and has since been fixed has to be able to
## recover, and one coasting on an old reputation should not. That is the whole
## reason this is not just `total / count`.
##
## The window is padded with NEUTRAL for visits that have not happened yet, so
## an unknown tavern starts middling and one bad night early on does not sink
## it to nothing. It also means reputation moves slowly at first and faster once
## the place is busy, which is the right way round.
##
## Reputation feeds back into footfall. Without that it would be a number in the
## corner; with it, service quality is the thing that decides how many people
## walk through the door tomorrow, and the loop closes.

signal changed

## How many visits the town remembers.
const MEMORY: int = 20
## The score of a visit nobody has an opinion about, and where a new tavern
## starts.
const NEUTRAL: float = 55.0
## Arrivals are multiplied by this, from a ruined reputation to a famous one.
const FOOTFALL_MIN: float = 0.35
const FOOTFALL_MAX: float = 1.70
## Reviews kept for display. Shorter than MEMORY on purpose -- the day summary
## has room for a few, and the rest only matter as numbers.
const KEPT_REVIEWS: int = 12

var score: float = NEUTRAL
## Newest last. Satisfaction only: this is what the score is made of, and it is
## the only part that has to survive a save.
var window: Array[int] = []
## Newest first, for showing the player. Not persisted -- a reloaded tavern has
## its standing, but the gossip has moved on.
var reviews: Array[Review] = []


func add(review: Review) -> void:
	window.append(review.satisfaction)
	while window.size() > MEMORY:
		window.remove_at(0)
	reviews.push_front(review)
	while reviews.size() > KEPT_REVIEWS:
		reviews.pop_back()
	_recompute()


func clear() -> void:
	window.clear()
	reviews.clear()
	_recompute()


func _recompute() -> void:
	var total: float = NEUTRAL * float(maxi(MEMORY - window.size(), 0))
	for value in window:
		total += float(value)
	var next: float = total / float(MEMORY)
	if is_equal_approx(next, score):
		return
	score = next
	changed.emit()


func stars() -> int:
	return clampi(int(round(score / 20.0)), 1, 5)


func star_text() -> String:
	var n: int = stars()
	return "%s%s" % ["*".repeat(n), "-".repeat(5 - n)]


## What the town would call the place.
func label() -> String:
	if score >= 85.0:
		return "Famous"
	if score >= 70.0:
		return "Well liked"
	if score >= 55.0:
		return "Respectable"
	if score >= 40.0:
		return "Getting a name"
	if score >= 25.0:
		return "Poorly thought of"
	return "Notorious"


func footfall_multiplier() -> float:
	return lerpf(FOOTFALL_MIN, FOOTFALL_MAX, clampf(score / 100.0, 0.0, 1.0))


## Everything needed to restore the standing, and nothing else.
func to_save() -> Dictionary:
	return {"window": window.duplicate()}


func from_save(data: Dictionary) -> void:
	window.clear()
	for value in data.get("window", []):
		window.append(int(value))
	while window.size() > MEMORY:
		window.remove_at(0)
	reviews.clear()
	_recompute()


func summary() -> String:
	return "%s %s (%d/100, x%.2f footfall, %d visits remembered)" % [
		label(), star_text(), int(round(score)), footfall_multiplier(), window.size()
	]
