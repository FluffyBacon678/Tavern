class_name TutorialKeeper
extends RefCounted

## Your keeper, after the bar so saved tutorial indices stay valid: step in as
## the character you made, fish with the basic rod, clean the catch at the prep
## table by hand, make the bar a till, and step back out. Everything the staff
## do, the keeper can do -- for when the money runs out, or before it comes in.


static func fishing_spot(world) -> int:
	for i in range(world.build.grid.placements.size()):
		var entry = world.build.grid.placements[i]
		if entry != null and entry["built"] and entry["def"].id == &"fishing_spot":
			return i
	return -1


static func piece_at(world, spot: Vector2i) -> int:
	return world.build.grid.object_index_at(TutorialPlan.at(world, spot))


static func steps() -> Array[TutorialStep]:
	var lesson: String = TutorialPlan.LESSONS[11]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("keeper_in", lesson,
		"Press Take control (%s) to step into your tavern as your keeper." % KeyBindings.first("play_keeper"),
		"Left-click walks, or does the first thing on offer. Right-click shows every option, as in RuneScape.",
		func(w, _ctx) -> bool: return w.keeper_controls.playing,
		func(w, _ctx) -> void: w.keeper_controls.start()
	).pointing_at({"button": "Take control"}))
	out.append(TutorialStep.make("keeper_fish", lesson,
		"Right-click the fishing spot and choose Fish (basic rod).",
		"You fish like the fisherman does, and the catch comes into your hands.",
		func(w, ctx) -> bool: return w.keeper != null and w.keeper.catches > int(ctx["catches"]),
		func(w, _ctx) -> void:
			var spot: int = fishing_spot(w)
			if spot >= 0:
				w.keeper.work(spot, RecipeCatalog.get_recipe(&"catch_fish"))
			w.sim.speed = 4
	).starting(func(w, ctx) -> void: ctx["catches"] = w.keeper.catches if w.keeper != null else 0
	).running(300.0).pointing_at(func(w) -> Dictionary:
		var spot: int = fishing_spot(w)
		return {"tiles": Rect2i(w.build.grid.placements[spot]["tiles"][0], Vector2i.ONE)} if spot >= 0 else {}))
	out.append(TutorialStep.make("keeper_clean", lesson,
		"Right-click the prep table and choose Clean Trout (or Clean Perch): you carry the fish there and clean it yourself.",
		"Holding an ingredient, a recipe puts it down at the bench first. Do it yourself when there is no cook, or no money for one.",
		func(w, ctx) -> bool:
			return w.keeper != null and w.keeper.batches > int(ctx["batches"]) and w.keeper.carry_count == 0,
		func(w, _ctx) -> void:
			var keeper: Keeper = w.keeper
			if keeper == null or keeper.carry_def == null:
				return
			var recipe: Recipe = RecipeCatalog.get_recipe(&"clean_trout" if keeper.carry_def.id == &"trout" else &"clean_perch")
			keeper.work(piece_at(w, TutorialPlan.PREP), recipe)
			w.sim.speed = 4
	).starting(func(w, ctx) -> void: ctx["batches"] = w.keeper.batches if w.keeper != null else 0
	).running(300.0).pointing_at(func(w) -> Dictionary: return {"tiles": TutorialPlan.area(w, TutorialPlan.PREP, Vector2i(2, 1))}))
	out.append(TutorialStep.make("keeper_till", lesson,
		"Right-click the bar and choose Take payments here.",
		"Guests can buy what is on it and pay there, with no waiter. With nobody on the staff to take orders, every guest does.",
		func(w, _ctx) -> bool:
			var bar: int = piece_at(w, TutorialBar.BAR)
			return bar >= 0 and bool(w.build.grid.placements[bar].get("till", false)),
		func(w, _ctx) -> void: w.set_till(piece_at(w, TutorialBar.BAR), true)
	).pointing_at(func(w) -> Dictionary: return {"tiles": TutorialPlan.area(w, TutorialBar.BAR, Vector2i(2, 1))}))
	out.append(TutorialStep.make("keeper_out", lesson,
		"Press Manage (%s) to go back to running the tavern from above." % KeyBindings.first("play_keeper"),
		"Your keeper stays where they are, and is saved with the tavern. Step in again whenever you like.",
		func(w, _ctx) -> bool: return not w.keeper_controls.playing,
		func(w, _ctx) -> void: w.keeper_controls.stop()
	).pointing_at({"button": "Manage"}))
	return out
