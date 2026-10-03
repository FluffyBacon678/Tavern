class_name BillBook
extends RefCounted

## Standing production orders: "maintain 10 bread", from design notes section 21.
##
## Without these a station converts every ingredient the moment it arrives, so a
## delivery is instantly turned into more bread than the tavern can sell and
## there is no such thing as managing stock. A bill is the difference between
## "make whatever you can" and "keep this much on hand".
##
## Bills are *tavern-wide per recipe* rather than per bench. "Maintain 10 bread"
## is a policy about the larder, not about one oven, and with two ovens the
## player almost certainly wants them sharing a target rather than each chasing
## its own.
##
## Hysteresis is the whole point of the two numbers. A single threshold makes a
## station flicker on and off around it, starting and abandoning work each time
## a loaf is eaten; producing up to `target` and not restarting until stock has
## fallen to `resume_below` gives it a proper duty cycle.

signal changed

## recipe id -> { target, resume_below, enabled, paused }
var bills: Dictionary = {}


func _init() -> void:
	reset_to_defaults()


## Scaled for the opening tavern rather than the notes' larger figures: at
## roughly eight loaves a day, a target of 20 would never once be reached and
## the bill would have no effect at all.
func reset_to_defaults() -> void:
	bills.clear()
	# Water is bulky and nobody wants a yard full of barrels, so the well keeps
	# a working reserve rather than running flat out.
	_set_default(&"pump_water", 10, 4)
	_set_default(&"mill_flour", 6, 2)
	_set_default(&"press_lemonade", 12, 9)
	_set_default(&"make_dough", 3, 1)
	_set_default(&"bake_bread", 10, 9)
	_set_default(&"brew_beer", 12, 11)
	# Fish: a few in hand, cleaned as they come, cooked a few at a time.
	_set_default(&"catch_fish", 8, 3)
	_set_default(&"clean_trout", 4, 1)
	_set_default(&"clean_perch", 4, 1)
	_set_default(&"fish_soup", 6, 5)
	_set_default(&"grill_fish", 6, 5)
	changed.emit()


func _set_default(recipe_id: StringName, target: int, resume_below: int) -> void:
	bills[recipe_id] = {
		"target": target,
		"resume_below": resume_below,
		"enabled": true,
		"paused": false,
	}


func has_bill(recipe_id: StringName) -> bool:
	return bills.has(recipe_id)


func get_bill(recipe_id: StringName) -> Dictionary:
	return bills.get(recipe_id, {})


## Should this recipe be worked right now, given how much of its output exists?
##
## Mutates the paused flag, so it is deliberately called once per scan rather
## than freely -- asking twice is harmless, but asking from a UI redraw would
## make the hysteresis depend on how often the panel was open.
func should_produce(recipe_id: StringName, stock: int) -> bool:
	if not bills.has(recipe_id):
		return true  # no bill means no limit
	var bill: Dictionary = bills[recipe_id]
	if not bill["enabled"]:
		return false

	if bill["paused"]:
		if stock <= bill["resume_below"]:
			bill["paused"] = false
	elif stock >= bill["target"]:
		bill["paused"] = true
	return not bill["paused"]


func set_target(recipe_id: StringName, target: int) -> void:
	if not bills.has(recipe_id):
		return
	var bill: Dictionary = bills[recipe_id]
	bill["target"] = maxi(0, target)
	# Keep the resume threshold below the target, or the bill can never pause.
	bill["resume_below"] = mini(bill["resume_below"], maxi(0, bill["target"] - 1))
	changed.emit()


func set_resume_below(recipe_id: StringName, value: int) -> void:
	if not bills.has(recipe_id):
		return
	var bill: Dictionary = bills[recipe_id]
	bill["resume_below"] = clampi(value, 0, maxi(0, bill["target"] - 1))
	changed.emit()


func set_enabled(recipe_id: StringName, on: bool) -> void:
	if not bills.has(recipe_id):
		return
	bills[recipe_id]["enabled"] = on
	changed.emit()


## Human-readable state, for the production panel.
func status_text(recipe_id: StringName, stock: int) -> String:
	if not bills.has(recipe_id):
		return "unlimited"
	var bill: Dictionary = bills[recipe_id]
	if not bill["enabled"]:
		return "off"
	if bill["paused"]:
		return "%d in store · resumes below %d" % [stock, bill["resume_below"]]
	return "%d of %d" % [stock, bill["target"]]
