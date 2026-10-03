class_name TutorialBar
extends RefCounted

## The bar, after farming so saved tutorial indices stay valid: a bar table on
## the lawn east of the garden path, which keeps drinks on its counter, and a
## guest who fetches their own rather than wait for a waiter.

const BAR := Vector2i(6, 9)
const PARASOL := Vector2i(6, 11)


static func area(world) -> Rect2i:
	return TutorialPlan.area(world, Vector2i(5, 9), Vector2i(4, 3))


static func chairs(world) -> Array[Vector2i]:
	return [TutorialPlan.at(world, PARASOL + Vector2i(-1, 0)), TutorialPlan.at(world, PARASOL + Vector2i(2, 0))]


static func steps() -> Array[TutorialStep]:
	var lesson: String = TutorialPlan.LESSONS[10]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("stand", lesson,
		"Build a Bar Table (Dining) on the marked lawn, and a Parasol Table (Garden) below it with a chair either side.",
		"A bar keeps drinks on its counter, inside or out: its own lemonade, pressed there, and beer the porters bring.",
		func(w, _ctx) -> bool:
			return TutorialPlan.placed_in(w, [&"bar_table"], area(w)) >= 1 \
				and TutorialPlan.placed_in(w, [&"parasol_table"], area(w)) >= 1 \
				and TutorialPlan.placed_in(w, [&"chair"], area(w)) >= 2,
		func(w, _ctx) -> void:
			PlayerActions.place_all(w, &"bar_table", [TutorialPlan.at(w, BAR)])
			PlayerActions.place_all(w, &"parasol_table", [TutorialPlan.at(w, PARASOL)])
			PlayerActions.place_all(w, &"chair", chairs(w))
			PlayerActions.stop_building(w)
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w)}))
	out.append(TutorialStep.make("lemonade", lesson,
		"Run time until the first lemonade is pressed at the bar.",
		"Lemonade has a target in Stores like any meal, so lemons are bought for you. Cooks press it; the lemons and water wait on the ground beside the bar.",
		func(w, _ctx) -> bool: return TutorialPlan.made(w, [&"lemonade"]) >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(900.0).pointing_at(func(w) -> Dictionary: return {"tiles": TutorialPlan.area(w, BAR, Vector2i(2, 1))}))
	out.append(TutorialStep.make("bar_guest", lesson,
		"Watch for a guest who fetches their own drink from the bar.",
		"Guests who want only a drink, and hate to wait, take it off the counter themselves and pay on the way out: no waiter, and no tip. Patient guests, and anyone wanting a meal, are waited on.",
		func(w, _ctx) -> bool: return w.customers.bar_visits >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(900.0).pointing_at(func(w) -> Dictionary: return {"tiles": TutorialPlan.area(w, BAR, Vector2i(2, 1))}))
	return out
