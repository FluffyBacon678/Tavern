extends Node

## Profile continuity, cosmetic isolation, real creator controls and old saves.
## Runs headless for logic/layout; use windowed with shots=<prefix> for art QA.
var failures: int = 0
var shots: String = ""
var accepted_profile: CharacterProfile


func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	# Keep this observer alive while the real menu uses SceneRouter.
	get_tree().current_scene = null
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			shots = arg.trim_prefix("shots=")
		elif arg.begins_with("read="):
			await _read_copy(arg.trim_prefix("read="))
			_finish()
			return
	_check_profiles()
	await _check_world_and_restart()
	await _check_creator()
	await _check_menu_cancel()
	_finish()


func _fixture_profile() -> CharacterProfile:
	var profile := CharacterProfile.default_owner(12345)
	profile.name = "Mira Ashdown"
	profile.appearance.body_type = 1
	profile.appearance.skin = CharacterAppearance.SKIN_COLORS[4]
	profile.appearance.hair = CharacterAppearance.HAIR_COLORS[3]
	profile.appearance.hair_style = 2
	profile.appearance.face_type = 3
	profile.appearance.expression = 1
	profile.appearance.top = CharacterAppearance.TOP_COLORS[2]
	profile.appearance.trousers = CharacterAppearance.TROUSER_COLORS[2]
	profile.appearance.boots = CharacterAppearance.BOOT_COLORS[1]
	profile.equipped = {"head": "cook_hat", "body": "short_sleeve_shirt", "outer": "linen_apron",
		"legs": "rolled_trousers", "feet": "work_shoes", "hands": "work_gloves",
		"neck": "copper_pendant", "ring": "copper_ring", "cape": "travel_cape", "backpack": "travel_pack"}
	return profile


func _check_profiles() -> void:
	var profile := _fixture_profile()
	var restored := CharacterProfile.from_save(JSON.parse_string(JSON.stringify(profile.to_save())), 12345)
	check(restored.to_save() == profile.to_save(), "JSON preserves identity, every appearance choice, ownership and equipment")
	var clone := profile.clone()
	clone.appearance.top = Color("345678")
	clone.owned.append("future_keepsake")
	check(clone.appearance.top != profile.appearance.top and not profile.owned.has("future_keepsake"), "editing a draft does not mutate the original person")
	var fallback := CharacterProfile.from_save(null, 12345)
	check(fallback.to_save() == CharacterProfile.from_save(null, 12345).to_save(), "legacy owner defaults repeat without randomness")
	var future: Dictionary = profile.to_save()
	future["owned"].append("future_keepsake")
	future["equipped"]["ring"] = "future_keepsake"
	future["equipped"]["neck"] = "unowned_charm"
	var safe := CharacterProfile.from_save(future)
	check(safe.owned.has("future_keepsake") and not safe.equipped.has("neck"), "missing cosmetic definitions retain ownership; unowned gear is not equipped")
	var malformed: Dictionary = profile.appearance.to_save()
	malformed["body_type"] = 99
	malformed["hair_style"] = -4
	malformed["skin"] = "not-a-colour"
	var appearance := CharacterAppearance.from_save(malformed, profile.appearance)
	check(appearance.body_type == 1 and appearance.hair_style == 2 and appearance.skin == profile.appearance.skin, "invalid optional appearance fields safely retain the fallback")
	var rig := PawnMesh.build_appearance(profile.appearance, _material(), profile.equipped)
	check(rig.body.mesh.get_surface_count() == 1 and rig.skeleton.get_bone_count() == 6, "custom owner and equipped travel kit share one surface and six bones")
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var face_colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	check(face_colours.has(PawnMesh.VISOR), "small pupil geometry survives the facial detail build")
	check(face_colours.has(Color("aea68f")) and not face_colours.has(Color("e8dfc9")), "small muted eyes survive the adult face build without bright eye glints")
	var finite := true
	for vertex in arrays[Mesh.ARRAY_VERTEX]:
		finite = finite and vertex.is_finite() and vertex.y >= -0.001 and vertex.y < 1.6
	check(finite, "custom body and simultaneous cape/backpack have finite standing bounds")
	rig.root.free()
	var keeper_contract: bool = true
	var largest_keeper: int = 0
	for body in range(2):
		for hair in range(4):
			for equipped in [{}, {"head": "felt_hat", "cape": "travel_cape", "backpack": "travel_pack"}]:
				var ordinary: CharacterAppearance = CharacterProfile.default_owner(12345).appearance
				ordinary.body_type = body
				ordinary.hair_style = hair
				var base: PawnMesh.Rig = PawnMesh.build_appearance(ordinary, _material(), equipped)
				var mesh: Array = base.body.mesh.surface_get_arrays(0)
				largest_keeper = maxi(largest_keeper, (mesh[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
				keeper_contract = keeper_contract and base.body.mesh.get_surface_count() == 1 and base.skeleton.get_bone_count() == 6
				keeper_contract = keeper_contract and (mesh[Mesh.ARRAY_COLOR] as PackedColorArray).has(PawnMesh.VISOR)
				keeper_contract = keeper_contract and base.carry_anchor.position.is_equal_approx(Vector3(0, PawnMesh.LEG_H + PawnMesh.TORSO_H * 0.55, PawnMesh.BODY_D * 0.5 + 0.12))
				var floor_y: float = INF
				for vertex in mesh[Mesh.ARRAY_VERTEX]:
					floor_y = minf(floor_y, vertex.y)
					keeper_contract = keeper_contract and vertex.is_finite() and vertex.y < 1.6 and absf(vertex.x) < 0.5 and absf(vertex.z) < 0.5
				keeper_contract = keeper_contract and is_equal_approx(floor_y, 0.0)
				for bone in range(6):
					keeper_contract = keeper_contract and base.skeleton.get_bone_rest(bone).basis.get_scale().is_equal_approx(Vector3.ONE)
				base.root.free()
	check(keeper_contract, "both sculpted keeper builds and all hair/travel combinations preserve pupil, rig, carry and standing contracts")
	check(largest_keeper <= 1400, "ordinary keeper and travelling kit stay within 1400 triangles (%d measured)" % largest_keeper)


func _check_world_and_restart() -> void:
	SimWait.seed_run()
	GameState.full_house_start = true
	check(GameState.start_new_run("Character continuity", 12345, 0, true), "character fixture opens an isolated new tavern")
	GameState.owner_profile = _fixture_profile()
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	var worker: Pawn = world.pawns[0]
	var name_before: String = worker.pawn_name
	var random_before: int = worker._rng.state
	var role_before: StringName = world.workers[0].role.id
	var cargo := Node3D.new()
	worker.carry(cargo)
	worker.set_appearance(_fixture_profile().appearance, _fixture_profile().equipped)
	check(worker._rng.state == random_before and worker.pawn_name == name_before and world.workers[0].role.id == role_before, "staff appearance edits preserve RNG, identity and job role")
	check(worker.is_carrying() and cargo.get_parent() == worker._rig.carry_anchor, "wardrobe rebuild retains carried geometry on the new anchor")
	worker.carry(null)
	var guest := Pawn.new()
	add_child(guest)
	guest.setup(world.nav, world.terrain, world.plot.position + Vector2i(2, 2), _material(), 773, true)
	var archetype_before: int = guest.adventurer
	var guest_rng: int = guest._rng.state
	guest.set_appearance(_fixture_profile().appearance)
	check(guest.adventurer == archetype_before and guest._rng.state == guest_rng and guest.appearance.family == -1, "guest behavior remains independent of its edited visual family")
	var brain := CustomerBrain.new()
	brain.setup(guest, world.customers, world.customers.seating, world.items, world.nav, 444)
	check(brain.guest_type == GuestType.of(archetype_before), "customer rules still use the preserved archetype after clothing changes")
	brain.free()
	guest.queue_free()
	SimWait.configure(world)
	SimWait.release(world)
	await SimWait.seconds(world, 160.0)
	SimWait.hold(world)
	check(not world.customers.customers.is_empty(), "real visitors arrive before the appearance persistence fixture")
	if not world.customers.customers.is_empty():
		var real_guest: Pawn = world.customers.customers[0].pawn
		var type_before: GuestType = world.customers.customers[0].guest_type
		real_guest.set_appearance(_fixture_profile().appearance, _fixture_profile().equipped)
		check(world.customers.customers[0].guest_type == type_before, "a live visiting customer's preferences survive a wardrobe edit")
	check(world.save_now(), "owner and edited staff save to disk with the populated tavern")
	check(not world.has_unsaved_progress(), "saving clears the character fixture's dirty state")
	var owner_before: Dictionary = GameState.owner_profile.to_save()
	var camera_lock_before: bool = world.rig.locked
	world.hud.open_owner_profile()
	await _frames(3)
	var wardrobe: CharacterCreator = _find_creator(world.hud._hud)
	check(wardrobe != null and world.sim.menu_held and world.rig.locked, "Keeper opens a wardrobe while holding simulation and camera input")
	wardrobe.select_choice("top", 1)
	wardrobe.cancel_changes()
	await _frames(3)
	check(GameState.owner_profile.to_save() == owner_before and not world.sim.menu_held and world.rig.locked == camera_lock_before, "canceling Keeper changes neither the person nor prior pause/camera state")
	world.hud.open_owner_profile()
	await _frames(3)
	wardrobe = _find_creator(world.hud._hud)
	wardrobe.select_choice("top", 3)
	wardrobe.accept_changes()
	await _frames(3)
	check(world.has_unsaved_progress(), "an owner clothing edit while paused counts as unsaved progress")
	GameState.owner_profile = _fixture_profile()
	var snapshot := SaveGame.read(0)
	var saved_path: String = ProjectSettings.globalize_path(GameState.slot_path(0))
	await _finish_render()
	world.queue_free()
	await get_tree().process_frame
	_restart(saved_path)
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.erase("owner")
	for row in legacy["pawns"]:
		row.erase("appearance")
		row.erase("equipment")
		row.erase("adventurer")
	for row in legacy.get("customers", {}).get("guests", []):
		row.erase("appearance")
		row.erase("equipment")
		row.erase("adventurer")
	check(SaveGame.write(1, legacy), "pre-character format-2 snapshot remains valid")
	_restart(ProjectSettings.globalize_path(GameState.slot_path(1)))


func _read_copy(path: String) -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(DirAccess.copy_absolute(path, ProjectSettings.globalize_path(GameState.slot_path(0))) == OK, "fresh process copies only the fixture into its own sandbox")
	check(GameState.request_continue(0), "fresh process accepts Continue without opening a creator")
	if not GameState.load_requested:
		return
	var world: TavernWorld = load("res://src/world/world3d/world_3d.tscn").instantiate()
	add_child(world)
	SimWait.hold(world)
	var actual: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(world)))
	check(actual["buildings"] == expected["buildings"] and actual["items"] == expected["items"] and actual["gold"] == expected["gold"], "character migration/restart preserves every building, ground stack and gold")
	if expected.has("owner"):
		check(actual["owner"] == expected["owner"], "fresh process resumes the exact owner and wardrobe")
	else:
		check(GameState.owner_profile.to_save() == CharacterProfile.default_owner(int(expected["world_seed"])).to_save(), "pre-character world receives its stable default owner")
	var staff_kept: bool = actual["pawns"].size() == expected["pawns"].size()
	for i in range(mini(actual["pawns"].size(), expected["pawns"].size())):
		for key in ["name", "seed", "role", "priorities", "cargo", "appearance", "equipment", "adventurer"]:
			if expected["pawns"][i].has(key):
				staff_kept = staff_kept and expected["pawns"][i][key] == actual["pawns"][i].get(key)
	check(staff_kept, "fresh process preserves staff identity, appearance, role and cargo")
	var guests_before: Array = expected.get("customers", {}).get("guests", [])
	var guests_after: Array = actual.get("customers", {}).get("guests", [])
	var guests_kept: bool = guests_before.size() == guests_after.size()
	for i in range(mini(guests_before.size(), guests_after.size())):
		for key in ["name", "appearance", "equipment", "adventurer"]:
			if guests_before[i].has(key):
				guests_kept = guests_kept and guests_before[i][key] == guests_after[i].get(key)
	check(guests_kept, "fresh process preserves visiting character appearance and independent guest archetype")
	await _finish_render()
	world.queue_free()
	await get_tree().process_frame


func _restart(path: String) -> void:
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://dev/character_smoke.tscn", "--", "read=" + path], output, true)
	var clean := true
	for chunk in output:
		print(String(chunk).strip_edges())
		clean = clean and not String(chunk).contains("ERROR:")
	check(code == 0 and clean, "separate engine restores %s without engine errors" % path.get_file())


func _check_creator() -> void:
	var original := _fixture_profile()
	var saved_before: String = FileAccess.get_file_as_string(GameState.slot_path(0))
	get_window().size = Vector2i(1280, 720)
	seed(88273)
	var expected_random: int = randi()
	seed(88273)
	var creator := CharacterCreator.open(self, CharacterProfile.default_owner(12345))
	check(randi() == expected_random, "opening the creator leaves the global simulation seed stream alone")
	await _frames(6)
	await _shot("starter_front")
	await _check_framing(creator)
	creator.preview.rotate_step(PI)
	await _frames(3)
	await _shot("starter_back")
	seed(99812)
	expected_random = randi()
	seed(99812)
	creator.randomize_appearance()
	check(randi() == expected_random, "Randomize uses only the creator's local RNG")
	creator.cancel_changes()
	await _frames(3)
	creator = CharacterCreator.open(self, original)
	creator.accepted.connect(func(profile: CharacterProfile) -> void: accepted_profile = profile)
	await _frames(6)
	var hair_choice: OptionButton = creator.find_child("HairStyle", true, false)
	check(hair_choice != null, "creator exposes the real hairstyle selector")
	if hair_choice != null:
		hair_choice.select(3)
		hair_choice.item_selected.emit(3)
	creator.name_field.text = "A new face"
	creator.name_field.text_changed.emit("A new face")
	await _frames(3)
	await _shot("travel_front")
	creator.preview.rotate_step(PI)
	await _frames(3)
	await _shot("travel_back")
	creator.preview.rotate_step(-PI)
	check(original.name == "Mira Ashdown" and original.appearance.hair_style == 2, "creator inputs change the draft only")
	var redraws: int = creator.preview.redraw_count
	await _frames(8)
	check(creator.preview.redraw_count == redraws, "idle preview does not repeatedly rebuild its mesh")
	for shape in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1440, 900), Vector2i(2560, 1080)]:
		get_window().size = shape
		await _frames(8)
		var got: Vector2i = get_window().size
		print("CHARACTER WINDOW: requested=%s actual=%s viewport=%s" % [shape, got, get_viewport().get_visible_rect().size])
		print("CHARACTER ACTION: rect=%s" % creator.accept_button.get_global_rect())
		if got.x < shape.x or got.y < shape.y:
			print("SKIP: window shape %s clamped to %s" % [shape, got])
			continue
		check(get_viewport().get_visible_rect().encloses(creator.accept_button.get_global_rect()), "creator confirmation stays on screen at %s" % shape)
		check(creator.draft.appearance.hair_style == 3 and creator.name_field.text == "A new face", "creator retains choices across resize to %s" % shape)
		await _shot("creator_%dx%d" % [shape.x, shape.y])
	creator.cancel_changes()
	await _frames(3)
	check(FileAccess.get_file_as_string(GameState.slot_path(0)) == saved_before, "canceling creation leaves disk saves unchanged")
	creator = CharacterCreator.open(self, original)
	creator.accepted.connect(func(profile: CharacterProfile) -> void: accepted_profile = profile)
	await _frames(3)
	creator.select_choice("hair_style", 1)
	creator.accept_changes()
	await _frames(3)
	check(accepted_profile != null and accepted_profile.appearance.hair_style == 1 and original.appearance.hair_style == 2, "confirmation emits an independent selected profile")


func _check_framing(creator: CharacterCreator) -> void:
	var face_button: Button = creator.find_child("FaceView", true, false)
	var full_button: Button = creator.find_child("FullBodyView", true, false)
	var hands_button: Button = creator.find_child("HandsView", true, false)
	check(face_button != null and full_button != null and hands_button != null, "creator exposes real Full body, Face and Hands controls")
	if face_button == null or full_button == null or hands_button == null:
		return
	creator.preview.rotate_step(0.17)
	await _frames(3)
	var draft_before: Dictionary = creator.draft.to_save()
	var root_id: int = creator.preview.rig.root.get_instance_id()
	var angle: float = creator.preview.rig.root.rotation.y
	var full_head: Rect2 = _projected_bounds(creator.preview, true)
	var full_hands: Rect2 = _projected_bounds(creator.preview, false, true)
	var old_size: float = creator.preview.camera.size
	seed(71433)
	var expected_random: int = randi()
	seed(71433)
	face_button.pressed.emit()
	await _frames(4)
	check(creator.preview.get_framing() == CharacterPreview.Framing.FACE and creator.preview.camera.size < old_size
		and creator.preview.rig.root.get_instance_id() == root_id and is_equal_approx(creator.preview.rig.root.rotation.y, angle)
		and creator.draft.to_save() == draft_before, "Face control changes camera only, preserving mesh, rotation, equipment and draft")
	check(randi() == expected_random, "camera framing leaves the simulation RNG stream untouched")
	if DisplayServer.get_name() != "headless":
		var face_head: Rect2 = _projected_bounds(creator.preview, true)
		check(_inside_preview(creator.preview, face_head) and face_head.size.y >= full_head.size.y * 2.0
			and face_head.size.y >= creator.preview.viewport.size.y * 0.35, "default face is fully visible and materially larger in close-up")
	else:
		print("NOTE: rendered framing bounds require a windowed viewport; camera-state checks still run headless")
	await _shot("default_face")
	creator.preview.rotate_step(PI * 0.5)
	await _frames(3)
	await _shot("default_face_profile")
	creator.preview.rotate_step(-PI * 0.5)
	await _frames(3)
	creator.select_choice("skin", 4)
	creator.select_choice("hair", 0)
	await _frames(3)
	await _shot("dark_face")
	creator.preview.rotate_step(PI * 0.5)
	await _frames(3)
	await _shot("dark_face_profile")
	creator.preview.rotate_step(-PI * 0.5)
	creator.select_choice("skin", 1)
	creator.select_choice("hair", 1)
	await _frames(3)
	root_id = creator.preview.rig.root.get_instance_id()
	hands_button.pressed.emit()
	await _frames(4)
	check(creator.preview.get_framing() == CharacterPreview.Framing.HANDS
		and creator.preview.rig.root.get_instance_id() == root_id and creator.draft.to_save() == draft_before
		and is_equal_approx(creator.preview.rig.root.rotation.y, angle), "Hands control changes camera only and retains mesh, rotation and saved choices")
	if DisplayServer.get_name() != "headless":
		var hands: Rect2 = _projected_bounds(creator.preview, false, true)
		check(_inside_preview(creator.preview, hands) and hands.size.y >= full_hands.size.y * 2.0,
			"both hands and cuffs fit in a materially larger close-up")
	await _shot("default_hands")
	creator.preview.rotate_step(PI * 0.5)
	await _frames(3)
	await _shot("default_hands_profile")
	creator.preview.rotate_step(PI * 0.5)
	await _frames(3)
	await _shot("default_hands_back")
	creator.preview.rotate_step(-PI)
	await _frames(3)
	var hands_redraws: int = creator.preview.redraw_count
	hands_button.pressed.emit()
	await _frames(3)
	check(creator.preview.redraw_count == hands_redraws, "selecting Hands again does not request another render")
	creator.select_choice("boots", 1)
	await _frames(3)
	check(creator.preview.get_framing() == CharacterPreview.Framing.HANDS
		and is_equal_approx(creator.preview.rig.root.rotation.y, angle), "appearance edits retain Hands framing and rotation")
	creator.select_choice("boots", 0)
	face_button.pressed.emit()
	await _frames(3)
	var redraws: int = creator.preview.redraw_count
	face_button.pressed.emit()
	await _frames(3)
	check(creator.preview.redraw_count == redraws, "selecting the current framing leaves an idle preview idle")
	creator.select_choice("hair_style", 1)
	await _frames(3)
	check(creator.preview.get_framing() == CharacterPreview.Framing.FACE
		and is_equal_approx(creator.preview.rig.root.rotation.y, angle), "changing hair retains face framing and the chosen rotation")
	creator.select_choice("hair_style", 0)
	for shape in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1440, 900), Vector2i(2560, 1080)]:
		get_window().size = shape
		await _frames(8)
		var got: Vector2i = get_window().size
		print("FRAMING WINDOW: requested=%s actual=%s preview=%s" % [shape, got, creator.preview.viewport.size])
		if got.x < shape.x or got.y < shape.y:
			print("SKIP: framing shape %s clamped to %s" % [shape, got])
			continue
		check(creator.preview.get_framing() == CharacterPreview.Framing.FACE
			and is_equal_approx(creator.preview.rig.root.rotation.y, angle), "face framing and rotation survive resize to %s" % shape)
		var ui_visible: bool = true
		for control in [creator.accept_button, face_button, full_button, hands_button]:
			ui_visible = ui_visible and get_viewport().get_visible_rect().encloses(control.get_global_rect())
		check(ui_visible, "framing and confirmation controls fit at %s" % shape)
		if DisplayServer.get_name() != "headless":
			check(_inside_preview(creator.preview, _projected_bounds(creator.preview, true)), "face silhouette fits its preview at %s" % shape)
		await _shot("face_%dx%d" % [shape.x, shape.y])
		hands_button.pressed.emit()
		await _frames(3)
		check(creator.preview.get_framing() == CharacterPreview.Framing.HANDS
			and is_equal_approx(creator.preview.rig.root.rotation.y, angle), "Hands framing retains rotation at %s" % shape)
		if DisplayServer.get_name() != "headless":
			check(_inside_preview(creator.preview, _projected_bounds(creator.preview, false, true)), "both hands and cuffs fit their preview at %s" % shape)
		await _shot("hands_%dx%d" % [shape.x, shape.y])
		full_button.pressed.emit()
		await _frames(3)
		if DisplayServer.get_name() != "headless":
			check(_inside_preview(creator.preview, _projected_bounds(creator.preview)), "full-body silhouette fits its preview at %s" % shape)
		check(creator.preview.get_framing() == CharacterPreview.Framing.FULL_BODY
			and creator.draft.to_save() == draft_before, "Full body control retains all character choices at %s" % shape)
		face_button.pressed.emit()
	full_button.pressed.emit()
	creator.preview.rotate_step(-0.17)
	get_window().size = Vector2i(1280, 720)
	await _frames(6)


func _projected_bounds(preview: CharacterPreview, head_only: bool = false, hands_only: bool = false) -> Rect2:
	var arrays: Array = preview.rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var found: bool = false
	var result := Rect2()
	for i in range(vertices.size()):
		var bone: int = bones[i * 4]
		if head_only and bone != 1:
			continue
		if hands_only:
			if bone not in [2, 3]:
				continue
			# Use the authored cuff/hand portion, then apply the actual bone pose.
			if vertices[i].y > preview.rig.skeleton.get_bone_rest(bone).origin.y - PawnMesh.ARM_H * 0.60:
				continue
		var posed: Vector3 = preview.rig.skeleton.get_bone_global_pose(bone) * preview.rig.body.skin.get_bind_pose(bone) * vertices[i]
		var pixel: Vector2 = preview.camera.unproject_position(preview.rig.root.global_transform * posed)
		if not found:
			result = Rect2(pixel, Vector2.ZERO)
			found = true
		else:
			result = result.expand(pixel)
	return result


func _inside_preview(preview: CharacterPreview, bounds: Rect2) -> bool:
	return bounds.size.x > 0 and bounds.size.y > 0 and Rect2(Vector2(2, 2), Vector2(preview.viewport.size) - Vector2(4, 4)).encloses(bounds)


func _check_menu_cancel() -> void:
	var state_before: Dictionary = {"slot": GameState.active_slot, "seed": GameState.world_seed, "new": GameState.new_run_pending, "load": GameState.load_requested, "owner": GameState.owner_profile.to_save()}
	var menu: Control = load("res://src/ui/main_menu/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	menu._scenario = "sandbox"
	menu._chosen_slot = 2
	menu._open_page(menu.Page.NEW, false)
	menu._name_field.text = "The Copper Cup"
	menu._seed_field.text = "32777"
	menu._on_start()
	await _frames(4)
	get_window().size = Vector2i(1024, 768)
	await _frames(6)
	var creator: CharacterCreator = _find_creator(menu)
	check(creator != null, "New game opens character creation before starting the run")
	if creator != null:
		creator.cancel_changes()
	await _frames(3)
	var state_after: Dictionary = {"slot": GameState.active_slot, "seed": GameState.world_seed, "new": GameState.new_run_pending, "load": GameState.load_requested, "owner": GameState.owner_profile.to_save()}
	check(state_before == state_after, "backing out of the real new-game creator leaves slot/run/owner intent untouched")
	check(menu._name_field.text == "The Copper Cup" and menu._seed_field.text == "32777" and menu._chosen_slot == 2, "scenario, tavern, seed and slot choices survive creator resize and Back")
	menu._on_start()
	await _frames(3)
	creator = _find_creator(menu)
	creator.name_field.text = "Nessa Fairbrook"
	creator.name_field.text_changed.emit("Nessa Fairbrook")
	creator.select_choice("top", 1)
	creator.select_choice("body_type", 1)
	var selected: CharacterProfile = creator.draft.clone()
	creator.accept_button.pressed.emit()
	await SceneRouter.transition_finished
	var world: TavernWorld = get_tree().current_scene
	SimWait.hold(world)
	check(GameState.tavern_name == "The Copper Cup" and GameState.world_seed == 32777 and GameState.active_slot == 2, "actual creator confirmation starts the selected new tavern")
	check(GameState.owner_profile.to_save() == selected.to_save() and GameState.owner_profile.name != GameState.tavern_name, "actual new game receives the selected person separately from its tavern name")
	check(world.save_now(), "actual new game saves successfully")
	var selected_json: Dictionary = JSON.parse_string(JSON.stringify(selected.to_save()))
	check(SaveGame.read(2).get("owner") == selected_json, "every selected new-game character field reaches the JSON disk save")
	await _finish_render()
	get_tree().current_scene = null
	world.queue_free()
	await _frames(2)


func _find_creator(node: Node) -> CharacterCreator:
	if node is CharacterCreator:
		return node
	for child in node.get_children():
		var found := _find_creator(child)
		if found != null:
			return found
	return null


func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	return material


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _finish_render() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _shot(label: String) -> void:
	if shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _finish_render()
	check(get_viewport().get_texture().get_image().save_png(shots + "_" + label + ".png") == OK, "capture %s" % label)


func _finish() -> void:
	print("CHARACTER SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
