class_name TutorialStand
extends RefCounted

## The lemonade stand, after farming so saved tutorial indices stay valid: a
## stall that is the garden's own counter and press, a table under a parasol,
## and a guest who enjoys the view. In front of the hall, east of the path.

const STALL := Vector2i(6, 9)
const PARASOL := Vector2i(6, 11)


static func area(world) -> Rect2i:
	return TutorialPlan.area(world, Vector2i(5, 9), Vector2i(4, 3))


static func chairs(world) -> Array[Vector2i]:
	return [TutorialPlan.at(world, PARASOL + Vector2i(-1, 0)), TutorialPlan.at(world, PARASOL + Vector2i(2, 0))]


static func steps() -> Array[TutorialStep]:
	var lesson: String = TutorialPlan.LESSONS[10]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("stand", lesson,
		"In the Garden tab, build a Market Stall and a Parasol Table on the marked lawn, with a chair either side of the table.",
		"The stall is the garden's own serving counter, and a lemonade press: cooks press, waiters serve. The parasol table seats guests like any table.",
		func(w, _ctx) -> bool:
			return TutorialPlan.placed_in(w, [&"market_stall"], area(w)) >= 1 \
				and TutorialPlan.placed_in(w, [&"parasol_table"], area(w)) >= 1 \
				and TutorialPlan.placed_in(w, [&"chair"], area(w)) >= 2,
		func(w, _ctx) -> void:
			PlayerActions.place_all(w, &"market_stall", [TutorialPlan.at(w, STALL)])
			PlayerActions.place_all(w, &"parasol_table", [TutorialPlan.at(w, PARASOL)])
			PlayerActions.place_all(w, &"chair", chairs(w))
			PlayerActions.stop_building(w)
	).pointing_at(func(w) -> Dictionary: return {"tiles": area(w)}))
	out.append(TutorialStep.make("lemonade", lesson,
		"Run time until the first lemonade is pressed at the stall.",
		"Lemonade has a target in Stores like any meal, so lemons are ordered for you. The lemons and water wait on the ground beside the stall.",
		func(w, _ctx) -> bool: return TutorialPlan.made(w, [&"lemonade"]) >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(900.0).pointing_at(func(w) -> Dictionary: return {"tiles": TutorialPlan.area(w, STALL, Vector2i(2, 1))}))
	out.append(TutorialStep.make("garden_guest", lesson,
		"Watch a guest drink lemonade.",
		"Guests seated near flowers, trees and lanterns enjoy the view: they mind a wait less, and it adds to their review.",
		func(w, _ctx) -> bool: return int(w.customers.consumed.get(&"lemonade", 0)) >= 1,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(900.0))
	return out
