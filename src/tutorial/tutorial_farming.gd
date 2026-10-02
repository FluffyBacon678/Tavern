class_name TutorialFarming
extends RefCounted

## Appended after the original lessons so saved tutorial indices stay valid.
## The player watches real planting, but long crop growth continues afterwards.

static func field(world) -> Rect2i:
	return Rect2i(TutorialPlan.room(world).position + Vector2i(0, -4), Vector2i(3, 2))


static func plot_entry(world) -> Dictionary:
	var index: int = world.build.grid.floor_index_at(field(world).position)
	if index < 0:
		return {}
	var entry = world.build.grid.placements[index]
	return entry if entry != null and entry["def"].id == &"farm_plot" else {}


static func farmers(world) -> int:
	var count: int = 0
	for worker in world.workers:
		if is_instance_valid(worker) and worker.role.id == &"farmer":
			count += 1
	return count


static func pump_spot(world) -> Vector2i:
	var def: BuildingDef = BuildingCatalog.get_def(&"river_pump")
	var kitchen: Vector2i = TutorialPlan.at(world, TutorialPlan.PREP)
	var best := Vector2i(-1, -1)
	var distance: int = 1 << 30
	for y in range(world.plot.position.y, world.plot.end.y):
		for x in range(world.plot.position.x, world.plot.end.x):
			var tile := Vector2i(x, y)
			var d: int = absi(x - kitchen.x) + absi(y - kitchen.y)
			if d < distance and world.build.grid.placement_problem(def, tile, 0).is_empty():
				best = tile
				distance = d
	return best


static func pump_target(world) -> Vector2i:
	for entry in world.build.grid.placements:
		if entry != null and entry["def"].id == &"river_pump":
			return entry["origin"]
	return pump_spot(world)


static func steps() -> Array[TutorialStep]:
	var lesson: String = TutorialPlan.LESSONS[9]
	var out: Array[TutorialStep] = []
	out.append(TutorialStep.make("hire_farmer", lesson,
		"Open Staff and hire a Farmer.",
		"Farmers plant, harvest and carry goods. Porters still build the beds.",
		func(w, ctx) -> bool: return farmers(w) > int(ctx["farmers_before"]),
		func(w, _ctx) -> void:
			if not w.hud._priority_panel.visible:
				w.hud._priority_panel.toggle()
			PlayerActions.press(w.hud._priority_panel, "Farmer")
			w.hud._priority_panel.hide()
	).starting(func(w, ctx) -> void: ctx["farmers_before"] = farmers(w)).pointing_at({"button": "Staff"}))
	out.append(TutorialStep.make("farm_beds", lesson,
		"Pick Farm Plot in Build and drag over the six outlined tiles.",
		"These are floor pieces. Each bed holds one crop: wheat for flour, or hops for beer.",
		func(w, _ctx) -> bool: return TutorialPlan.placed_in(w, [&"farm_plot"], field(w)) >= 6,
		func(w, _ctx) -> void:
			PlayerActions.select(w, &"farm_plot")
			PlayerActions.drag(w, field(w).position, field(w).end - Vector2i.ONE)
			PlayerActions.stop_building(w)
	).pointing_at(func(w) -> Dictionary: return {"tiles": field(w)}))
	out.append(TutorialStep.make("plant_field", lesson,
		"Run time. Your porter builds the beds, then the farmer plants them.",
		"Crops need about two trading days to ripen. The farmer harvests them automatically when ready; leave room nearby for the crop.",
		func(w, _ctx) -> bool:
			var planted: int = 0
			for entry in w.build.grid.placements:
				if entry != null and entry["built"] and entry["def"].id == &"farm_plot" \
						and field(w).has_point(entry["origin"]) and Farm.growth_of(entry) >= 0.0:
					planted += 1
			return planted >= 6,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(600.0).pointing_at({"role": &"farmer"}))
	out.append(TutorialStep.make("inspect_field", lesson,
		"Click the marked farm bed to read its crop and growth progress.",
		"Wheat becomes flour at the prep table. Stores uses harvested ingredients before buying more.",
		func(w, _ctx) -> bool:
			var subject: Dictionary = w.hud.inspector.subject()
			return int(subject.get("kind", -1)) == WorldStats.Kind.BUILDING \
				and int(subject.get("index", -1)) == w.build.grid.floor_index_at(field(w).position),
		func(w, _ctx) -> void: w.hud.inspector.show_building(w.build.grid.floor_index_at(field(w).position))
	).pointing_at(func(w) -> Dictionary: return {"tiles": Rect2i(field(w).position, Vector2i.ONE)}))
	out.append(TutorialStep.make("choose_hops", lesson,
		"In the farm bed's card, choose Grow hops instead.",
		"Changing crops turns over the bed and loses its current growth. Keep the other beds growing wheat.",
		func(w, _ctx) -> bool: return not plot_entry(w).is_empty() and Farm.crop_of(plot_entry(w)) == &"hops",
		func(w, _ctx) -> void:
			w.hud.inspector.show_building(w.build.grid.floor_index_at(field(w).position))
			PlayerActions.press(w.hud.inspector, "Grow hops instead")
	).pointing_at(func(w) -> Dictionary: return {"tiles": Rect2i(field(w).position, Vector2i.ONE)}))
	out.append(TutorialStep.make("river_pump", lesson,
		"Build a River Pump on the marked bank tile.",
		"A pump must touch the river. A porter works it slowly, then carries water to the well or water storage.",
		func(w, _ctx) -> bool: return TutorialPlan.placed_in(w, [&"river_pump"], w.plot) >= 1,
		func(w, _ctx) -> void:
			w.hud.inspector.clear()
			PlayerActions.place_all(w, &"river_pump", [pump_spot(w)])
			PlayerActions.stop_building(w)
	).pointing_at(func(w) -> Dictionary: return {"tiles": Rect2i(pump_target(w), Vector2i.ONE)}))
	out.append(TutorialStep.make("build_pump", lesson,
		"Run time until the river pump is built and the hops bed is planted.",
		"The pump keeps a water reserve and stops when it has enough. Rain fills an outdoor well; a roofed well only stores carried water.",
		func(w, _ctx) -> bool:
			return w.build.grid.count_built([&"river_pump"]) >= 1 and not plot_entry(w).is_empty() \
				and Farm.crop_of(plot_entry(w)) == &"hops" and Farm.growth_of(plot_entry(w)) >= 0.0,
		func(w, _ctx) -> void: w.sim.speed = 4
	).running(600.0).pointing_at(func(w) -> Dictionary: return {"tiles": Rect2i(pump_target(w), Vector2i.ONE)}))
	out.append(TutorialStep.make("save_farm", lesson,
		"Save your tavern again from the pause menu.",
		"Your crops, growth, remaining harvest and restock choices are saved. Keep trading while the field grows.",
		func(w, ctx) -> bool: return w.saved_at_msec > int(ctx["farm_saved"]),
		func(w, _ctx) -> void:
			w.hud.open_pause_menu()
			PlayerActions.press(w.hud.pause_menu, "Save game")
			w.hud.pause_menu.close()
	).starting(func(w, ctx) -> void: ctx["farm_saved"] = w.saved_at_msec).pointing_at({"button": "Menu"}))
	return out
