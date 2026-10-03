extends Node

## Role uniforms must follow real hires/restores without changing simulation.
var failures: int = 0
var largest: int = 0


func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	var reading: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("read="):
			reading = arg.trim_prefix("read=")
	if not reading.is_empty():
		await _restore(reading)
	else:
		_mesh_checks()
		await _world_checks()
	print("STAFF UNIFORM SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	return material


func _signature(rig: PawnMesh.Rig) -> int:
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	return hash([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_COLOR]])


func _contract(rig: PawnMesh.Rig) -> bool:
	var vertices: PackedVector3Array = rig.body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	largest = maxi(largest, vertices.size() / 3)
	var ok: bool = rig.body.mesh.get_surface_count() == 1 and rig.skeleton.get_bone_count() == 6 and vertices.size() / 3 < 1400
	var floor_y: float = INF
	for vertex in vertices:
		ok = ok and vertex.is_finite() and vertex.y >= -0.001 and vertex.y < 1.6 and absf(vertex.x) < 0.5 and absf(vertex.z) < 0.5
		floor_y = minf(floor_y, vertex.y)
	for bone in range(6):
		ok = ok and rig.skeleton.get_bone_rest(bone).basis.is_equal_approx(Basis.IDENTITY)
	return ok and is_zero_approx(floor_y) and rig.carry_anchor.position.is_equal_approx(Vector3(0, PawnMesh.LEG_H + PawnMesh.TORSO_H * 0.55, PawnMesh.BODY_D * 0.5 + 0.12))


func _mesh_checks() -> void:
	var signatures: Dictionary = {}
	var role_count: int = 0
	seed(59317)
	var expected_global: int = randi()
	seed(59317)
	for role in StaffRole.hireable_roles():
		var complete := true
		var kit: Dictionary = StaffUniforms.equipment_for(role.id)
		for slot in kit:
			complete = complete and WardrobeCatalog.slot_for(kit[slot]) == slot
		check(not kit.is_empty() and complete and kit.has("head"), "%s has a valid clothing-slot uniform and identifying hat" % role.title)
		var count: int = 0
		var contract_ok := true
		var unchanged := true
		for body in range(2):
			for hair in range(4):
				for skin in CharacterAppearance.SKIN_COLORS:
					var look := CharacterAppearance.new()
					look.family = PawnMesh.Look.STAFF
					look.top = role.uniform
					look.body_type = body
					look.hair_style = hair
					look.skin = skin
					var before: Dictionary = look.to_save()
					var rig: PawnMesh.Rig = PawnMesh.build_appearance(look, _material(), {}, role.id)
					contract_ok = contract_ok and _contract(rig)
					unchanged = unchanged and look.to_save() == before
					if body == 0 and hair == 0 and skin == CharacterAppearance.SKIN_COLORS[0]:
						signatures[_signature(rig)] = true
					count += 1
					rig.root.free()
		check(count == 40 and contract_ok and unchanged, "%s fits both builds, four hairstyles and five skins without mutating appearance, rig, floor or carry" % role.title)
		role_count += 1
	check(role_count == 8 and signatures.size() == 8, "all eight jobs have distinct rendered uniforms")
	print("STAFF JOB BUDGET: 320 combinations, largest=%d triangles" % largest)
	var layered_ok := true
	var layered_count: int = 0
	for body in range(2):
		for hair in range(4):
			for hat in KeeperWardrobeArt.COVERED_HATS:
				for outer in ["linen_apron", "waist_apron"]:
					var layered := CharacterProfile.default_owner().appearance
					layered.body_type = body
					layered.hair_style = hair
					var kit: Dictionary = {"head": hat, "body": "house_waistcoat", "outer": outer, "legs": "olive_trousers", "feet": "leather_boots", "hands": "work_gloves", "neck": "copper_pendant", "ring": "copper_ring", "cape": "travel_cape", "backpack": "travel_pack"}
					var layered_rig: PawnMesh.Rig = PawnMesh.build_appearance(layered, _material(), kit)
					layered_ok = layered_ok and _contract(layered_rig)
					layered_count += 1
					layered_rig.root.free()
	check(layered_count == 128 and layered_ok, "new hats and waistcoat/aprons fit all 128 full ten-slot travel kits without raising the 1400-triangle ceiling")
	var look := CharacterAppearance.new()
	look.family = PawnMesh.Look.STAFF
	var equipped: Dictionary = {"head": "straw_hat", "body": "leather_vest", "outer": "waist_apron", "cape": "travel_cape", "backpack": "travel_pack"}
	var copy: Dictionary = equipped.duplicate()
	var rig: PawnMesh.Rig = PawnMesh.build_appearance(look, _material(), equipped, &"waiter")
	var ordinary := look.clone()
	ordinary.family = -1
	var expected: PawnMesh.Rig = PawnMesh.build_appearance(ordinary, _material(), equipped)
	check(_signature(rig) == _signature(expected) and equipped == copy, "explicit equipped garments override role defaults without being overwritten")
	rig.root.free()
	expected.root.free()
	var unknown: PawnMesh.Rig = PawnMesh.build_appearance(look, _material(), {"head": "future_hat"}, &"waiter")
	var bare: PawnMesh.Rig = PawnMesh.build_appearance(look, _material(), {"head": ""}, &"waiter")
	check(_signature(unknown) == _signature(bare), "an unavailable explicit hat suppresses the role hat with a safe bare fallback")
	unknown.root.free()
	bare.root.free()
	var legacy: PawnMesh.Rig = PawnMesh.build_appearance(look, _material(), {}, &"hand")
	var no_role: PawnMesh.Rig = PawnMesh.build_appearance(look, _material())
	check(_signature(legacy) == _signature(no_role), "legacy all-rounder retains its original house uniform")
	legacy.root.free()
	no_role.root.free()
	check(randi() == expected_global, "building every staff uniform leaves global simulation randomness unchanged")
	print("STAFF UNIFORM BUDGET: 320 job uniforms + 128 full travel kits, largest=%d triangles" % largest)


func _world_checks() -> void:
	SimWait.seed_run()
	GameState.full_house_start = true
	GameState.start_new_run("Uniform Test", 493774, 0, true)
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	var roles: Dictionary = {}
	var production_ok := true
	for worker in world.workers:
		roles[worker.role.id] = true
		production_ok = production_ok and worker.pawn.staff_role_id == worker.role.id and _contract(worker.pawn._rig)
	check(roles.size() == 8 and production_ok, "the real full-house crew spawns all eight valid role uniforms")
	var worker: Worker = world.workers[0]
	var pawn: Pawn = worker.pawn
	var state_before: int = pawn._rng.state
	var name_before: String = pawn.pawn_name
	var tile_before: Vector2i = pawn.tile
	var appearance_before: Dictionary = pawn.appearance.to_save()
	var old_role: StaffRole = worker.role
	var cargo := Node3D.new()
	pawn.carry(cargo)
	worker.set_role(StaffRole.of(&"cook"))
	check(pawn.staff_role_id == &"cook" and pawn._rng.state == state_before and pawn.pawn_name == name_before and pawn.tile == tile_before and pawn.appearance.to_save() == appearance_before and cargo.get_parent() == pawn._rig.carry_anchor, "a role change refreshes clothes while preserving identity, appearance, RNG, position and carried geometry")
	pawn.carry(null)
	worker.set_role(old_role)
	var portable := CharacterProfile.default_owner().appearance
	pawn.set_appearance(portable, {"head": "felt_hat", "body": "linen_shirt"})
	var expected: PawnMesh.Rig = PawnMesh.build_appearance(portable, _material(), pawn.equipped)
	check(_signature(pawn._rig) == _signature(expected), "a deliberately customized staff appearance remains its chosen outfit")
	expected.root.free()
	check(world.save_now(), "the clothed full-house crew saves in isolated slots")
	var save_path: String = ProjectSettings.globalize_path(GameState.slot_path(0))
	var metadata: Dictionary = {"signatures": [], "appearance": [], "equipment": []}
	for entry in world.pawns:
		metadata["signatures"].append(str(_signature(entry._rig)))
		metadata["appearance"].append(entry.appearance.to_save())
		metadata["equipment"].append(entry.equipped.duplicate())
	var metadata_path: String = save_path + ".uniforms"
	var file := FileAccess.open(metadata_path, FileAccess.WRITE)
	if file == null:
		check(false, "write uniform restart fixture")
		return
	file.store_string(JSON.stringify(metadata))
	file.close()
	world.queue_free()
	await get_tree().process_frame
	var output: Array = []
	var result: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://dev/staff_uniform_smoke.tscn", "--", "read=" + save_path], output, true)
	var clean := true
	for chunk in output:
		print(String(chunk).strip_edges())
		clean = clean and not String(chunk).contains("ERROR:")
	check(result == 0 and clean, "uniforms and customized clothes restore through a separate engine process")
	DirAccess.remove_absolute(metadata_path)


func _restore(path: String) -> void:
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".uniforms"))
	check(DirAccess.copy_absolute(path, ProjectSettings.globalize_path(GameState.slot_path(0))) == OK and GameState.request_continue(0), "fresh process continues the isolated uniform fixture")
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	var same: bool = world.pawns.size() == metadata["signatures"].size()
	for i in range(mini(world.pawns.size(), metadata["signatures"].size())):
		var pawn: Pawn = world.pawns[i]
		var mesh_ok: bool = str(_signature(pawn._rig)) == metadata["signatures"][i]
		# JSON stores numeric fields as floats; compare both descriptors in that
		# representation while geometry signatures remain exact.
		var appearance_ok: bool = JSON.parse_string(JSON.stringify(pawn.appearance.to_save())) == metadata["appearance"][i]
		var equipment_ok: bool = pawn.equipped == metadata["equipment"][i]
		var role_ok: bool = pawn.staff_role_id == world.workers[i].role.id
		if not mesh_ok or not appearance_ok or not equipment_ok or not role_ok:
			print("RESTORE DETAIL: %s mesh=%s appearance=%s equipment=%s role=%s signature=%s expected=%s" % [pawn.pawn_name, mesh_ok, appearance_ok, equipment_ok, role_ok, str(_signature(pawn._rig)), metadata["signatures"][i]])
			if not appearance_ok:
				print("RESTORE APPEARANCE: actual=%s expected=%s" % [pawn.appearance.to_save(), metadata["appearance"][i]])
		same = same and mesh_ok and appearance_ok and equipment_ok and role_ok
	check(same, "every restored staff member retains exact rendered clothes, saved appearance, equipment and role")
	world.queue_free()
	await get_tree().process_frame
