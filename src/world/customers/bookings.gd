class_name Bookings
extends RefCounted

## Tables booked for today, taken by a host at the stand each morning.
## Booked guests pay PREMIUM over the menu, booked under Ledger.Line.BOOKINGS.
##
## The user's design: a host lets people reserve, which keeps the place fuller
## at all hours, and a low rating means fewer people bother to book. So the
## number booked follows reputation and seating, and the times lean towards
## the quiet afternoon the walk-ins leave empty. Booked parties come as well
## as the day's footfall, not instead of it; they will wait longer for their
## table and hold a wait against the house less.

## Bookings are taken until this hour; after it the day's book is closed.
const LAST_HOUR: float = 11.0
## Seconds at the stand to take the day's bookings.
const WORK: float = 3.0
## Hours people book for: lunch, the afternoon lull (twice as likely), evening.
const SLOTS: Array[float] = [12.5, 13.5, 15.0, 15.0, 16.0, 16.0, 19.0, 20.5]
const MOST: int = 12
## Booked guests pay this much over the menu price.
const PREMIUM: float = 0.02

## The premium's fraction of a coin not yet paid. 2% of a 20g bill is 0.4g:
## rounded per guest it would never be paid, so it adds up across guests.
var carry: float = 0.0

## {hour, party, arrived} for each booking today.
var today: Array = []
## The day the book was last taken; 0 before any.
var taken_day: int = 0


## How many bookings a tavern gets: none below a poor name, more with seats.
static func count_for(seats: int, reputation_score: float) -> int:
	if seats <= 0:
		return 0
	var standing: float = clampf((reputation_score - 30.0) / 40.0, 0.0, 1.5)
	return clampi(int(round(float(seats) * 0.5 * standing)), 0, MOST)


func take(day: int, rng: RandomNumberGenerator, seats: int, reputation_score: float) -> int:
	today.clear()
	taken_day = day
	for i in range(count_for(seats, reputation_score)):
		today.append({"hour": SLOTS[rng.randi() % SLOTS.size()], "party": rng.randi_range(1, 2), "arrived": 0})
	today.sort_custom(func(a, b) -> bool: return a["hour"] < b["hour"])
	return today.size()


func wants_taking(day: int, hour: float) -> bool:
	return taken_day != day and hour < LAST_HOUR


## The first booking whose hour has come and whose party is not all here yet.
func due(hour: float) -> Dictionary:
	for b in today:
		if float(b["hour"]) <= hour and int(b["arrived"]) < int(b["party"]):
			return b
	return {}


## The premium on a booked guest's bill, in whole coins, carrying the rest.
func premium_on(bill: int) -> int:
	carry += float(maxi(bill, 0)) * PREMIUM
	var coins: int = int(floor(carry + 0.000001))
	carry -= float(coins)
	return coins


func booked_guests() -> int:
	var n: int = 0
	for b in today:
		n += int(b["party"])
	return n


func arrived_guests() -> int:
	var n: int = 0
	for b in today:
		n += int(b["arrived"])
	return n


## "12:30 for 2, 15:00 for 1", for the host's stand.
func describe() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for b in today:
		var h: float = float(b["hour"])
		parts.append("%02d:%02d for %d%s" % [int(h), int(round((h - floor(h)) * 60.0)), int(b["party"]),
			" (here)" if int(b["arrived"]) >= int(b["party"]) else ""])
	return ", ".join(parts)


func capture() -> Dictionary:
	return {"taken_day": taken_day, "today": today.duplicate(true), "carry": carry}


func restore(data: Dictionary) -> void:
	taken_day = int(data.get("taken_day", 0))
	carry = clampf(float(data.get("carry", 0.0)), 0.0, 1.0)
	today.clear()
	for b in data.get("today", []):
		if b is Dictionary and b.has("hour") and b.has("party"):
			today.append({"hour": float(b["hour"]), "party": clampi(int(b["party"]), 1, 4),
				"arrived": clampi(int(b.get("arrived", 0)), 0, 4)})
