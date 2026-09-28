class_name Ledger
extends RefCounted

## The books. Every coin in or out goes through here.
##
## The point is not the arithmetic -- gold is a single integer -- it is that
## money changes become *attributable*. "You are down 40 gold" is not useful;
## "wages 60, supplies 107, takings 128" tells the player which decision was the
## bad one, which is the whole job of an end-of-day screen.
##
## Because every mutation is routed through here, nothing can quietly move the
## purse without appearing in the reckoning.

enum Line {
	TAKINGS,
	TIPS,
	SUPPLIES,
	WAGES,
	CONSTRUCTION,
	## Buying the field next door. Its own line because it is the one outgoing
	## the player will want to see separated from day-to-day building -- a bad
	## week and an expansion should not look alike in the books.
	LAND,
	## Taking somebody on: each position has a fee, paid once. Its own line so
	## a day of hiring is not mistaken for a day of bad trade.
	HIRING,
	## Money back for demolishing: the whole cost of a blueprint nobody had
	## started, half of a finished piece. Income, so a day of tearing down a
	## mistake reads as money recovered rather than as negative building.
	REFUNDS,
}

## Every line, in the order a day's books are read.
const ORDER: Array[int] = [Line.TAKINGS, Line.TIPS, Line.REFUNDS, Line.SUPPLIES,
	Line.WAGES, Line.CONSTRUCTION, Line.LAND, Line.HIRING]

## Daily wage per member of staff, charged at close of business.
##
## Tuned down from 12 after the first full day measured a 116g loss: five staff
## at 12g cost 60g against takings of roughly 50g, so the tavern could not break
## even however well it was run. The prices this is weighed against (bread 10g,
## beer 8g) come from the design notes and were left alone.
const WAGE_PER_STAFF: int = 6

var today: Dictionary = {}
var history: Array = []


func _init() -> void:
	reset_day()


func reset_day() -> void:
	today = {
		Line.TAKINGS: 0,
		Line.TIPS: 0,
		Line.SUPPLIES: 0,
		Line.WAGES: 0,
		Line.LAND: 0,
		Line.CONSTRUCTION: 0,
		Line.HIRING: 0,
		Line.REFUNDS: 0,
	}


static func line_name(line: int) -> String:
	match line:
		Line.TAKINGS: return "Takings"
		Line.TIPS: return "Tips"
		Line.SUPPLIES: return "Supplies"
		Line.WAGES: return "Wages"
		Line.LAND: return "Land"
		Line.CONSTRUCTION: return "Building"
		Line.HIRING: return "Hiring"
		Line.REFUNDS: return "Refunds"
		_: return "Other"


static func is_income(line: int) -> bool:
	return line == Line.TAKINGS or line == Line.TIPS or line == Line.REFUNDS


## Money in. Returns the amount, for convenience at call sites.
func earn(line: int, amount: int) -> int:
	if amount <= 0:
		return 0
	today[line] = today.get(line, 0) + amount
	GameState.gold += amount
	return amount


## Money out. Refuses and returns false if the purse cannot cover it, so
## affordability is checked in exactly one place rather than at every caller.
func spend(line: int, amount: int) -> bool:
	if amount <= 0:
		return true
	if GameState.gold < amount:
		return false
	today[line] = today.get(line, 0) + amount
	GameState.gold -= amount
	return true


## Wages are charged even when the purse cannot cover them -- going into debt is
## a legitimate way to lose, and silently skipping payroll would hide it.
## `owed` is the whole bill: every position has its own wage.
func charge_wages(owed: int) -> int:
	if owed <= 0:
		return 0
	today[Line.WAGES] = today.get(Line.WAGES, 0) + owed
	GameState.gold -= owed
	return owed


func income() -> int:
	return today.get(Line.TAKINGS, 0) + today.get(Line.TIPS, 0) + today.get(Line.REFUNDS, 0)


func outgoings() -> int:
	return (
		today.get(Line.SUPPLIES, 0)
		+ today.get(Line.WAGES, 0)
		+ today.get(Line.CONSTRUCTION, 0)
		+ today.get(Line.LAND, 0)
		+ today.get(Line.HIRING, 0)
	)


func profit() -> int:
	return income() - outgoings()


## File the day away and start a fresh page.
func close_day(day: int, served: int, lost: int) -> Dictionary:
	var entry: Dictionary = {
		"day": day,
		"lines": today.duplicate(),
		"profit": profit(),
		"served": served,
		"lost": lost,
		"purse": GameState.gold,
	}
	history.append(entry)
	reset_day()
	return entry
