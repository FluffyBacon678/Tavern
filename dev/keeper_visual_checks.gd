extends RefCounted

## Additional checks inside the keeper group, so the runner remains 23 suites.
func run(group: Node, world: TavernWorld) -> void:
	_check_poses(group, world)
	_check_crowd(group, world)
	_check_guest(group, world)
	await _check_menu(group, world)


func _check_poses(group: Node, world: TavernWorld) -> void:
	var keeper: Keeper = world.keeper
	var pawn: Pawn = keeper.pawn
	var dice: int = world.sim_rng.state
	var personal_dice: int = pawn._rng.state
	var at: Vector3 = pawn.position
	var tile: Vector2i = pawn.tile
	var observer: Callable = pawn.work_visual
	for mode in [&"stir", &"pour", &"wash", &"fish"]:
		pawn.work_visual = func() -> Dictionary: return {"mode": mode, "target": at + Vector3.FORWARD}
		pawn._process(0)
		pawn._animate(0.1)
		var first: Vector3 = pawn._rig.arm_r.rotation
		for i in range(10):
			pawn._animate(0.1)
		group.check(pawn._rig.arm_r.rotation.distance_to(first) > 0.001, "%s work pose moves over game time" % mode)
	var rod: MeshInstance3D = pawn._work_rod
	var marker: MeshInstance3D = pawn._keeper_marker
	var normals: PackedVector3Array = marker.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	group.check(normals.size() > 0 and Array(normals).all(func(n: Vector3) -> bool: return n.y > 0.99),
		"keeper ground marker faces upward with Godot's winding")
	pawn.set_appearance(pawn.appearance)
	group.check(rod.get_parent() == pawn._rig.work_anchor and marker.get_parent() == pawn._rig.root,
		"a wardrobe rebuild preserves the work rod and keeper marker")
	var grip_before: Vector3 = rod.global_position
	pawn._rig.arm_r.rotation.x += 0.20
	pawn._rig.sync_pose()
	group.check(rod.global_position.distance_to(grip_before) > 0.02
		and rod.global_position.distance_to(pawn._rig.work_anchor.global_position) < 0.001,
		"the rod handle follows the moving palm, not the fixed cargo anchor")
	pawn.work_visual = observer
	pawn._process(0)
	group.check(not rod.visible, "idle keeper leaves no working rod visible")
	group.check(pawn.position == at and pawn.tile == tile and pawn._rng.state == personal_dice and world.sim_rng.state == dice,
		"poses and wardrobe rebuild leave position, tile and both dice unchanged")
	var worker: Worker = world.workers[0]
	var previous: Job = worker.current
	var state: int = worker.state
	worker.current = Job.new()
	worker.current.target = tile
	worker.state = Worker.State.WORKING
	for kind in [WorkType.Kind.FISH, WorkType.Kind.CLEAN, WorkType.Kind.COOK]:
		worker.current.kind = kind
		var request: Dictionary = worker._pose_request()
		group.check(not String(request["mode"]).is_empty() and worker.current.work_done == 0,
			"staff %s work provides a pose without completing any work" % WorkType.display_name(kind))
	worker.current = previous
	worker.state = state


func _check_crowd(group: Node, world: TavernWorld) -> void:
	var bodies: Array[Pawn] = []
	var tile: Vector2i = world.keeper.pawn.tile
	for i in range(4):
		var pawn := Pawn.new()
		world.add_child(pawn)
		pawn.setup(world.nav, world.terrain, tile, world._pawn_material, 800 + i)
		pawn.autonomous_idle = false
		pawn.set_process(false)
		bodies.append(pawn)
	Pawn._crowd_frame = -1
	var separated: bool = true
	var unchanged: bool = true
	for pawn in bodies:
		pawn._update_crowding(1.0)
		unchanged = unchanged and pawn.position == pawn.world_position_of(tile) and pawn.tile == tile \
			and pawn._crowd_offset.length() <= Pawn.SEPARATION_MAX + 0.001
	for i in range(bodies.size()):
		for j in range(i):
			separated = separated and bodies[i]._crowd_offset.distance_to(bodies[j]._crowd_offset) > 0.20
	group.check(separated, "four exact-overlap bodies get distinct stable presentation offsets")
	group.check(unchanged, "crowd offsets stay bounded and never move logical positions or tiles")
	for pawn in bodies:
		pawn.free()
	Pawn._crowd_frame = -1


func _check_guest(group: Node, world: TavernWorld) -> void:
	var pawn := Pawn.new()
	world.add_child(pawn)
	pawn.setup(world.nav, world.terrain, world.keeper.pawn.tile, world._pawn_material, 805, true)
	pawn.set_process(false)
	var brain := CustomerBrain.new()
	brain.pawn = pawn
	brain.items = world.items
	brain.state = CustomerBrain.State.BACK_FROM_BAR
	brain.at_bar = true
	brain.order = [{"id": &"beer", "served": 1, "count": 1}]
	var stock: int = world.stock_of(&"beer")
	var dice: int = world.sim_rng.state
	brain._process(0)
	group.check(is_instance_valid(pawn._display_carried) and not pawn.is_carrying(),
		"a restored bar-return state displays its purchase without creating physical cargo")
	var held: Node3D = pawn._display_carried
	brain._process(0)
	pawn.set_appearance(pawn.appearance)
	group.check(pawn._display_carried == held and held.get_parent() == pawn._rig.carry_anchor,
		"the mug is reused per frame and survives a wardrobe rebuild")
	brain.state = CustomerBrain.State.EATING
	brain._process(0)
	group.check(pawn._display_carried == null, "the guest puts the displayed purchase down on reaching the table")
	brain.state = CustomerBrain.State.BACK_FROM_BAR
	brain.order = []
	brain._process(0)
	group.check(pawn._display_carried == null and world.stock_of(&"beer") == stock and world.sim_rng.state == dice,
		"a dry bar shows no mug; displaying purchases leaves stock and dice unchanged")
	brain.free()
	pawn.free()


func _check_menu(group: Node, world: TavernWorld) -> void:
	var win: Window = group.get_window()
	var previous_size: Vector2i = win.size
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var menu := KeeperMenu.new()
	layer.add_child(menu)
	for requested in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1440, 900), Vector2i(720, 1280)]:
		win.size = requested
		for i in range(4):
			await group.get_tree().process_frame
		if win.size != requested:
			print("NOTE: keeper menu requested %s got %s; testing actual window" % [requested, win.size])
		var options: Array = []
		for i in range(24):
			options.append({"text": "Make a particularly long named tavern drink %d" % i})
		var called: Array = []
		menu.open(options, Vector2(win.size) - Vector2(2, 2), func(option: Dictionary) -> void: called.append(option))
		for i in range(4):
			await group.get_tree().process_frame
		var view: Rect2 = menu.get_viewport_rect()
		var box: Rect2 = menu._panel.get_global_rect()
		group.check(view.encloses(box), "%s: long keeper options menu stays inside viewport" % win.size)
		var scale: float = menu.get_global_transform_with_canvas().x.length()
		var rows_fit: bool = true
		for row in menu._list.get_children():
			rows_fit = rows_fit and row.size.y * scale >= 47.9 and row.size.x <= menu._scroll.size.x
		group.check(rows_fit, "%s: every keeper action has a >=48px screen target and wraps in the list" % win.size)
		menu._list.get_child(23).grab_focus()
		for i in range(4):
			await group.get_tree().process_frame
		group.check(menu._scroll.scroll_vertical > 0, "%s: final action remains reachable by scrolling or focus" % win.size)
		menu._list.get_child(23).pressed.emit()
		group.check(not menu.visible and called.size() == 1 and called[0] == options[23],
			"%s: final action closes menu and calls the selected option once" % win.size)
	win.size = previous_size
	layer.queue_free()
