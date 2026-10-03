class_name Review
extends RefCounted

## What one patron thought of their visit, and why.
##
## Design notes section 19 is insistent on the "why": a satisfaction number with
## no reason attached is something the player can watch go down and do nothing
## about. So every component is scored separately, and the review quotes back
## whichever one dominated -- good or bad -- in the patron's own words.
##
## Price and atmosphere are in the notes and absent here, because neither has a
## lever behind it yet. Scoring a control that does not exist would be telling
## the player to fix something they cannot reach. Food quality *does* have one --
## the cook's hands, whether the player's or the staff's -- so it is scored.

enum Part {
	## Was there a full board to choose from, or one sad option?
	FOOD,
	## How long between ordering and being served.
	SERVICE,
	## How long between walking in and sitting down.
	SEATING,
	## Dirty tables, averaged over the whole visit.
	CLEANLINESS,
	## A garden to look at: flowers, trees and lanterns near the seat. Never
	## a complaint, only a pleasure; added only when there is something there.
	SURROUNDINGS,
}

## A visit where nothing went wrong and nothing was special.
const BASE: int = 50

## Best and worst each component can swing the score. Deliberately asymmetric:
## a patron notices bad service far more than good service, which is what makes
## the tavern feel like something that can be got wrong.
const SWING: Dictionary = {
	Part.FOOD: [18, -20],
	Part.SERVICE: [18, -32],
	Part.SEATING: [8, -28],
	Part.CLEANLINESS: [8, -24],
	Part.SURROUNDINGS: [10, 0],
}

var patron: String = ""
var served: bool = true
var spend: int = 0
## Part -> signed contribution to satisfaction.
var parts: Dictionary = {}
var satisfaction: int = BASE
var stars: int = 3
var quote: String = ""
## Why the food scored as it did, for a quote that names it: "menu" when there
## was little choice, "cooking" when what came was poor, "" otherwise.
var food_reason: String = ""


## Score a visit.
##
## `seat_wait`, `order_wait` and `dirt` are all fractions of what the patron
## would tolerate, which keeps the tuning of patience in one place -- the
## customer -- instead of spreading it across the scoring table as well.
## `menu` is how many things were actually on offer when they ordered.
##
## `order_wait` below zero means they never got as far as ordering, and service
## goes unscored. Blaming the waiters for a patron who never found a table would
## point the player at the wrong problem, which is the one thing a review is for.
static func write(
	p_patron: String,
	p_served: bool,
	p_spend: int,
	seat_wait: float,
	order_wait: float,
	menu: int,
	dirt: float,
	food_quality: float = -1.0,
	cares: Dictionary = {},
	beauty: float = 0.0
) -> Review:
	var r := Review.new()
	r.patron = p_patron
	r.served = p_served
	r.spend = p_spend

	r.parts[Part.SEATING] = _swing(Part.SEATING, clampf(seat_wait, 0.0, 1.0))
	r.parts[Part.CLEANLINESS] = _swing(Part.CLEANLINESS, clampf(dirt, 0.0, 1.0))

	if p_served:
		r.parts[Part.SERVICE] = _swing(Part.SERVICE, clampf(order_wait, 0.0, 1.0))
	elif order_wait >= 0.0:
		# Sat down, ordered, and was never brought anything.
		r.parts[Part.SERVICE] = SWING[Part.SERVICE][1]
	else:
		r.parts[Part.SERVICE] = 0

	# Two things decide the food: whether there was a choice, and whether what
	# they got was any good. A menu of none is why they left, so it swamps both.
	if menu <= 0:
		r.parts[Part.FOOD] = SWING[Part.FOOD][1]
	else:
		# A third dish is worth a little more again: fish, in the demo.
		var breadth: int = -4 if menu == 1 else (4 if menu == 2 else 6)
		# A guest who cares for choice feels a short menu, and a long one, more.
		breadth = int(round(float(breadth) * float(cares.get(Part.FOOD, 1.0))))
		var cooking: int = 0
		if food_quality >= 0.0:
			# BASE_QUALITY -- ordinary work by an ordinary cook -- is exactly
			# neutral, so a tavern only gains on food by doing better than that.
			cooking = int(round(lerpf(-14.0, 14.0, clampf(food_quality, 0.0, 1.0))))
		r.parts[Part.FOOD] = breadth + cooking
		if breadth + cooking < 0:
			r.food_reason = "menu" if cooking > breadth else "cooking"
	if menu <= 0:
		r.food_reason = "menu"

	# What this kind of guest cares about counts for more, good or bad.
	for part in [Part.SERVICE, Part.SEATING, Part.CLEANLINESS]:
		if cares.has(part):
			r.parts[part] = int(round(float(r.parts[part]) * float(cares[part])))

	# Surroundings only when there is something to look at, so a tavern with
	# no garden scores exactly as it always did.
	if beauty > 0.0:
		r.parts[Part.SURROUNDINGS] = int(round(lerpf(0.0, float(SWING[Part.SURROUNDINGS][0]), clampf(beauty, 0.0, 1.0))))

	var total: int = BASE
	for part in r.parts:
		total += int(r.parts[part])
	r.satisfaction = clampi(total, 0, 100)
	r.stars = clampi(int(round(float(r.satisfaction) / 20.0)), 1, 5)
	r.quote = _quote_for(r)
	return r


## Interpolate between a component's best and worst by how badly it went.
static func _swing(part: int, badness: float) -> int:
	var range_pair: Array = SWING[part]
	return int(round(lerpf(float(range_pair[0]), float(range_pair[1]), badness)))


## Quote the component that decided the visit.
##
## The worst one if anything actually went wrong, because that is the part the
## player can act on. Only a visit with no complaints gets to boast about its
## best feature.
static func _quote_for(review: Review) -> String:
	var worst: int = -1
	var worst_value: int = 0
	var best: int = -1
	var best_value: int = 0
	for part in review.parts:
		var value: int = int(review.parts[part])
		if value < worst_value:
			worst_value = value
			worst = part
		if value > best_value:
			best_value = value
			best = part

	# Phrasing chosen by the patron's name, not by dice: the same visit always
	# reads the same, and no random number is taken from anything.
	var pick: int = absi(review.patron.hash())
	if worst >= 0:
		return _line(worst, false, pick, review.food_reason)
	if best >= 0:
		return _line(best, true, pick, "")
	return ["Came in, drank, left. No complaints.", "Nothing to fault. I will be back.",
		"A decent place. It did what it said."][pick % 3]


## A day's reviews used to read "The food was nothing to write home about"
## three times running. Several phrasings each, and the food complaint says
## which fix it wants: a longer menu, or better cooking.
const LINES: Dictionary = {
	"garden_good": ["Ate in the garden among the flowers. Lovely.", "Sat under the parasol with a cold drink. Perfect.",
		"Flowers, lanterns, a breeze. I will be back."],
	"food_good": ["Best bread I have had this side of the river.", "The beer alone is worth the walk.",
		"Good plain food, and plenty of it."],
	"food_menu": ["Bread or beer, and not always both. A longer menu would bring me back.",
		"Not much of a choice on the board.", "They had one thing on, and I did not want it."],
	"food_cooking": ["The food was nothing to write home about.", "The bread was stale, or near enough.",
		"I have had better beer out of a horse trough."],
	"service_good": ["Served before I had settled in.", "Quick on their feet, the staff here.",
		"The waiter was at my elbow the moment I looked up."],
	"service_bad": ["The waiter took an age.", "Sat with my hand up half the evening.",
		"Waited so long for the bill I nearly walked out without paying."],
	"seating_good": ["Walked straight to a table.", "Always a seat free, even at the busy hour.",
		"Room to sit and room to spare."],
	"seating_bad": ["Stood about with nowhere to sit.", "Every chair taken. I went elsewhere.",
		"They need more tables, and soon."],
	"clean_good": ["Clean tables, which is more than most.", "Spotless, for a roadside inn.",
		"Not a crumb on the table when I sat down."],
	"clean_bad": ["Somebody else's plates still on the table.", "Dirty cups everywhere you looked.",
		"Nobody had cleared the table in hours."],
}


static func _line(part: int, good: bool, pick: int = 0, food_reason: String = "") -> String:
	var key: String = ""
	match part:
		Part.FOOD:
			key = "food_good" if good else ("food_menu" if food_reason == "menu" else "food_cooking")
		Part.SERVICE:
			key = "service_good" if good else "service_bad"
		Part.SEATING:
			key = "seating_good" if good else "seating_bad"
		Part.CLEANLINESS:
			key = "clean_good" if good else "clean_bad"
		Part.SURROUNDINGS:
			key = "garden_good" if good else ""
	if key.is_empty():
		return ""
	var options: Array = LINES[key]
	return String(options[pick % options.size()])


static func part_name(part: int) -> String:
	match part:
		Part.FOOD: return "Food"
		Part.SERVICE: return "Service"
		Part.SEATING: return "Seating"
		Part.CLEANLINESS: return "Cleanliness"
		Part.SURROUNDINGS: return "Surroundings"
	return "Visit"


## One word for a component, so the review reads like the notes' example rather
## than like a spreadsheet.
static func verdict(value: int) -> String:
	if value >= 8:
		return "Excellent"
	if value >= 1:
		return "Good"
	if value >= -6:
		return "Fair"
	if value >= -18:
		return "Poor"
	return "Dreadful"


func star_text() -> String:
	return "%s%s" % ["*".repeat(stars), "-".repeat(5 - stars)]


func headline() -> String:
	return "%s  %s  %d/100" % [patron, star_text(), satisfaction]


## The component that did the most damage, for a day summary that has room for
## one line of advice rather than five.
func worst_part() -> int:
	var worst: int = -1
	var worst_value: int = 1
	for part in parts:
		if int(parts[part]) < worst_value:
			worst_value = int(parts[part])
			worst = part
	return worst
