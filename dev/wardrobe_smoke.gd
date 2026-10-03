extends Node

## Ten-slot demo wardrobe: real controls, cosmetic isolation and kit budgets.
## Logic/layout runs headless. Run windowed with shots=<prefix> for art captures.
var failures: int = 0
var shots: String = ""
var accepted_profile: CharacterProfile
var largest_triangles: int = 0
var largest_outfit: String = ""

const FULL_KIT: Dictionary = {
	"head": "cook_hat", "body": "short_sleeve_shirt", "outer": "linen_apron",
	"legs": "rolled_trousers", "feet": "work_shoes", "hands": "work_gloves",
	"neck": "copper_pendant", "ring": "copper_ring", "cape": "travel_cape",
	"backpack": "travel_pack",
}


func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			shots = arg.trim_prefix("shots=")
	_check_catalog_and_profiles()
	_check_rendered_wardrobe()
	await _check_real_editor()
	print("WARDROBE SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _old_profile() -> CharacterProfile:
	var owner := CharacterProfile.default_owner(12345)
	owner.name = "Nessa Fairbrook"
	owner.owned.assign(["linen_shirt", "olive_trousers", "leather_boots", "future_keepsake"])
	owner.equipped["ring"] = "future_keepsake"
	return owner


func _check_catalog_and_profiles() -> void:
	var slots: Array[String] = WardrobeCatalog.slots()
	check(slots.size() == 10 and slots.has("outer") and slots.has("ring"), "catalogue exposes all ten independent clothing slots")
	var complete := true
	var seen: Dictionary = {}
	for slot in slots:
		var entries: Array[String] = WardrobeCatalog.items_for_slot(slot)
		complete = complete and not entries.is_empty()
		for id in entries:
			complete = complete and WardrobeCatalog.known(id) and WardrobeCatalog.slot_for(id) == slot and not seen.has(id)
			seen[id] = true
	check(complete and seen.size() == 23, "all twenty-three original garments have one valid catalogue slot")
	var fresh := CharacterProfile.default_owner(12345)
	check(fresh.owned.size() == 23 and fresh.equipped == {"body": "linen_shirt", "legs": "olive_trousers", "feet": "leather_boots"}, "new keepers own the demo wardrobe but start with only shirt, trousers and boots equipped")
	var old := _old_profile()
	var old_save: Dictionary = old.to_save()
	var restored := CharacterProfile.from_save(JSON.parse_string(JSON.stringify(old_save)), 12345)
	check(restored.to_save() == old_save and restored.owned.size() == 4, "loading an older ownership list neither grants clothes nor changes unknown equipped keepsakes")
	restored.grant_starter_wardrobe()
	var once: Dictionary = restored.to_save()
	restored.grant_starter_wardrobe()
	check(restored.to_save() == once and restored.owned.size() == 24 and restored.equipped == old.equipped, "explicit demo grants are unique, idempotent and never auto-equip")
	var invalid: Dictionary = CharacterProfile.equipment_from_save({"head": "work_gloves", "feet": "felt_hat", "outer": "linen_apron"}, fresh.owned)
	check(invalid == {"outer": "linen_apron"}, "wrong-slot known equipment is rejected without dropping valid outerwear")
	check(CharacterProfile.equipment_from_save({"head": "felt_hat"}, ["linen_shirt"]).is_empty(), "unowned known clothing cannot be equipped through save parsing")
	var future: Dictionary = CharacterProfile.equipment_from_save({"ring": "future_keepsake", "neck": "unowned_relic"}, old.owned)
	check(future == {"ring": "future_keepsake"}, "owned future IDs survive while unowned future IDs are rejected")
	var all_slots := old.clone()
	all_slots.grant_starter_wardrobe()
	all_slots.equipped = FULL_KIT.duplicate()
	check(CharacterProfile.from_save(JSON.parse_string(JSON.stringify(all_slots.to_save()))).to_save() == all_slots.to_save(), "JSON round-trips every one of the ten equipped slots, including outerwear")


func _check_rendered_wardrobe() -> void:
	var appearance := CharacterProfile.default_owner(12345).appearance
	var alternatives: Dictionary = {"linen_shirt": "short_sleeve_shirt", "olive_trousers": "rolled_trousers", "leather_boots": "work_shoes"}
	seed(58971)
	var expected_random: int = randi()
	seed(58971)
	for id in WardrobeCatalog.STARTER_ITEMS:
		var slot: String = WardrobeCatalog.slot_for(id)
		var equipped: Dictionary = {slot: id}
		var counterfactual: Dictionary = {}
		# The three base garments are also the safe unequipped fallback. Their
		# meaningful counterfactual is the alternate garment in the same slot.
		if alternatives.has(id):
			counterfactual[slot] = alternatives[id]
		check(_signature(appearance, equipped) != _signature(appearance, counterfactual), "%s changes rendered geometry or colour from its clothing counterfactual" % id)
	var base: int = _signature(appearance, {})
	check(_signature(appearance, {"ring": "future_keepsake"}) == base, "unknown owned keepsakes render a safe base fallback")
	check(_signature(appearance, {"head": "work_gloves", "feet": "felt_hat"}) == base, "raw wrong-slot known IDs cannot turn into the wrong rendered garment")
	_check_accessory_isolation(appearance)
	var rig_ok := true
	var bounds_ok := true
	var carry_ok := true
	var outfits := 0
	for body in range(2):
		for hair in range(4):
			for shirt in ["linen_shirt", "short_sleeve_shirt", "leather_vest"]:
				for hat in ["felt_hat", "cook_hat"]:
					for lower in range(2):
						var look := appearance.clone()
						look.body_type = body
						look.hair_style = hair
						var kit: Dictionary = FULL_KIT.duplicate()
						kit["body"] = shirt
						kit["head"] = hat
						kit["legs"] = "olive_trousers" if lower == 0 else "rolled_trousers"
						kit["feet"] = "leather_boots" if lower == 0 else "work_shoes"
						var rig: PawnMesh.Rig = PawnMesh.build_appearance(look, _material(), kit)
						var contract: Dictionary = _inspect_rig(rig)
						rig_ok = rig_ok and contract["rig"]
						bounds_ok = bounds_ok and contract["bounds"]
						carry_ok = carry_ok and contract["carry"]
						var triangles: int = contract["triangles"]
						if triangles > largest_triangles:
							largest_triangles = triangles
							largest_outfit = "body%d hair%d %s %s lower%d" % [body, hair, shirt, hat, lower]
						outfits += 1
						rig.root.free()
	check(outfits == 96 and rig_ok, "all 96 fully equipped body/hair/garment combinations retain one mesh surface and six unit-scale bones")
	check(bounds_ok, "all full outfits have finite geometry, floor contact and a walking pawn's envelope")
	check(carry_ok, "all ten-slot outfits preserve the established carrying anchor")
	_check_shared_preset_wardrobe(appearance)
	print("WARDROBE BUDGET: outfits=%d largest=%d triangles (%s)" % [outfits, largest_triangles, largest_outfit])
	check(largest_triangles < 1400, "the largest fully equipped keeper stays below 1400 triangles (%d measured)" % largest_triangles)
	check(randi() == expected_random, "rendering catalogue items and full wardrobes leaves the global random stream unchanged")


func _check_shared_preset_wardrobe(appearance: CharacterAppearance) -> void:
	var shared_ok := true
	var combinations := 0
	for family in range(7):
		for body in range(2):
			var look := appearance.clone()
			look.family = family
			look.body_type = body
			look.style = family * 8
			look.variant = family % 4
			look.cape_index = family
			var before: Dictionary = look.to_save()
			var rig: PawnMesh.Rig = PawnMesh.build_appearance(look, _material(), FULL_KIT)
			var contract: Dictionary = _inspect_rig(rig)
			var ordinary := look.clone()
			ordinary.family = -1
			var same_cut: bool = _mesh_signature(rig) == _signature(ordinary, FULL_KIT)
			var unchanged: bool = look.to_save() == before
			var triangles: int = contract["triangles"]
			var row_ok: bool = contract["rig"] and contract["bounds"] and contract["carry"] and triangles < 1400 and same_cut and unchanged
			shared_ok = shared_ok and row_ok
			if not row_ok:
				print("WARDROBE FAMILY: family=%d body=%d rig=%s bounds=%s carry=%s triangles=%d ordinary_cut=%s appearance_unchanged=%s" % [family, body, contract["rig"], contract["bounds"], contract["carry"], triangles, same_cut, unchanged])
			if triangles > largest_triangles:
				largest_triangles = triangles
				largest_outfit = "preset family%d body%d full kit" % [family, body]
			combinations += 1
			rig.root.free()
	check(shared_ok and combinations == 14,
		"all seven staff/adventurer families and both builds share the explicit ten-slot ordinary cut without changing saved appearance or rig/floor/carry/budget contracts")


func _check_real_editor() -> void:
	get_window().size = Vector2i(1280, 720)
	var old := _old_profile()
	var original: Dictionary = old.to_save()
	var disk_before: String = _disk_snapshot()
	seed(60913)
	var expected_random: int = randi()
	seed(60913)
	var creator := CharacterCreator.open(self, old, true)
	await _frames(8)
	check(randi() == expected_random, "opening the wardrobe grants only its private draft and consumes no simulation randomness")
	check(old.to_save() == original and creator.draft.owned.size() == 24 and creator.draft.equipped == old.equipped, "opening an older keeper grants the demo clothes only to its draft without auto-equipping")
	if not _press(creator, "ClothingTab"):
		creator.cancel_changes()
		await _frames(2)
		return
	await _frames(3)
	var visible_pane: Control = creator.find_child("ClothingPane", true, false)
	check(visible_pane != null and visible_pane.is_visible_in_tree(), "the real Clothing tab opens its own visible pane")
	_press(creator, "SlotRing")
	var selector: OptionButton = creator.find_child("EquipmentChoice", true, false)
	check(selector != null, "the wardrobe exposes the real equipment selector")
	if selector == null:
		creator.cancel_changes()
		await _frames(2)
		return
	var future_index: int = _item_index(selector, "future_keepsake")
	check(future_index >= 0 and selector.selected == future_index and selector.is_item_disabled(future_index), "the unknown saved keepsake remains visibly selected as an unavailable safe fallback")
	var owned_before: Array[String] = creator.draft.owned.duplicate()
	check(not creator.select_equipment("ring", "unowned_relic") and creator.draft.owned == owned_before, "selecting an unowned ID cannot grant or equip it")
	check(not creator.select_equipment("head", "work_gloves") and creator.draft.equipped.get("head", "") == "", "the editor rejects a known item in the wrong clothing slot")
	creator.preview.rotate_step(0.41)
	_press(creator, "FaceView")
	await _frames(3)
	var angle: float = creator.preview.rig.root.rotation.y
	var framing: int = creator.preview.get_framing()
	var all_controls := true
	for slot in WardrobeCatalog.SLOTS:
		all_controls = _equip_through_controls(creator, slot, String(FULL_KIT[slot])) and all_controls
	await _frames(5)
	check(all_controls and creator.draft.equipped == FULL_KIT, "real slot buttons and item_selected metadata equip all ten clothing slots")
	check(is_equal_approx(creator.preview.rig.root.rotation.y, angle) and creator.preview.get_framing() == framing, "clothing changes retain preview rotation and Face framing")
	var appearance_before: Dictionary = creator.draft.appearance.to_save()
	var other_slots: Dictionary = FULL_KIT.duplicate()
	other_slots["body"] = "leather_vest"
	var changed_shirt: bool = _equip_through_controls(creator, "body", "leather_vest")
	check(changed_shirt and creator.draft.appearance.to_save() == appearance_before and creator.draft.equipped == other_slots,
		"changing the shirt preserves appearance family and every other slot, including apron, cape and backpack")
	_equip_through_controls(creator, "body", "short_sleeve_shirt")
	var dressed_signature: int = _mesh_signature(creator.preview.rig)
	var removed := _equip_through_controls(creator, "cape", "") and _equip_through_controls(creator, "head", "")
	check(removed and not creator.draft.equipped.has("cape") and not creator.draft.equipped.has("head") and _mesh_signature(creator.preview.rig) != dressed_signature, "real None entries clear headwear and cape from both draft and renderer")
	_equip_through_controls(creator, "cape", "travel_cape")
	_equip_through_controls(creator, "head", "cook_hat")
	_press(creator, "AppearanceTab")
	await _frames(3)
	check(creator.draft.equipped == FULL_KIT, "switching back to Appearance retains the full outfit")
	_press(creator, "ClothingTab")
	_press(creator, "FullBodyView")
	await _frames(5)
	var saved_draft: Dictionary = creator.draft.to_save()
	var redraws: int = creator.preview.redraw_count
	await _frames(8)
	check(creator.preview.redraw_count == redraws, "the clothing preview does not rebuild or redraw while idle")
	if DisplayServer.get_name() == "headless":
		print("NOTE: projected cook-hat and cuff/palm framing checks require a windowed viewport; layout/state checks still run headless")
	for shape in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1440, 900), Vector2i(2560, 1080)]:
		get_window().size = shape
		await _frames(8)
		var got: Vector2i = get_window().size
		print("WARDROBE WINDOW: requested=%s actual=%s viewport=%s" % [shape, got, get_viewport().get_visible_rect().size])
		if got.x < shape.x or got.y < shape.y:
			print("SKIP: wardrobe window shape %s clamped to %s" % [shape, got])
			continue
		_check_layout(creator, shape)
		check(creator.draft.to_save() == saved_draft and is_equal_approx(creator.preview.rig.root.rotation.y, angle) and creator.preview.get_framing() == CharacterPreview.Framing.FULL_BODY, "wardrobe choices, rotation and framing survive resize to %s" % shape)
		await _check_projected_views(creator, shape)
		await _shot("clothing_%dx%d" % [shape.x, shape.y])
	get_window().size = Vector2i(1280, 720)
	await _frames(8)
	creator.preview.rotate_step(-creator.preview.rig.root.rotation.y)
	await _shot("cook_front")
	creator.preview.rotate_step(PI)
	await _shot("cook_back")
	creator.preview.rotate_step(-PI)
	_press(creator, "FaceView")
	await _shot("cook_face")
	_press(creator, "HandsView")
	await _shot("cook_hands")
	creator.cancel_changes()
	await _frames(3)
	check(old.to_save() == original and _disk_snapshot() == disk_before, "canceling an edited and resized wardrobe preserves original ownership, equipment and disk saves")
	creator = CharacterCreator.open(self, old, true)
	creator.accepted.connect(func(profile: CharacterProfile) -> void: accepted_profile = profile)
	await _frames(3)
	_press(creator, "ClothingTab")
	for slot in WardrobeCatalog.SLOTS:
		_equip_through_controls(creator, slot, String(FULL_KIT[slot]))
	var accepted_expected: Dictionary = creator.draft.to_save()
	creator.accept_button.pressed.emit()
	await _frames(3)
	check(accepted_profile != null and accepted_profile.to_save() == accepted_expected and accepted_profile.equipped == FULL_KIT, "real confirmation emits the complete ten-slot wardrobe as an independent profile")
	if accepted_profile != null:
		check(CharacterProfile.from_save(JSON.parse_string(JSON.stringify(accepted_profile.to_save()))).to_save() == accepted_profile.to_save(), "the accepted outfit and demo ownership survive JSON serialization")
	check(old.to_save() == original and _disk_snapshot() == disk_before, "accepting a wardrobe emits data without mutating its input or silently writing saves")


func _check_layout(creator: CharacterCreator, shape: Vector2i) -> void:
	var view: Rect2 = get_viewport().get_visible_rect()
	var pane: Control = creator.find_child("ClothingPane", true, false)
	var slots_fit: bool = pane != null and pane.is_visible_in_tree()
	var targets_big := true
	for slot in WardrobeCatalog.SLOTS:
		var button: Button = creator.find_child("Slot" + slot.capitalize(), true, false)
		if button == null:
			slots_fit = false
			targets_big = false
			continue
		var rect: Rect2 = button.get_global_rect()
		slots_fit = slots_fit and button.is_visible_in_tree() and view.encloses(rect) and pane.get_global_rect().encloses(rect) and _unclipped(button)
		targets_big = targets_big and rect.size.x >= 24.0 and rect.size.y >= 24.0
	check(slots_fit, "all ten clothing slots fit their visible pane and screen at %s" % shape)
	check(targets_big, "every clothing slot remains at least 24x24 at %s" % shape)
	var selector: OptionButton = creator.find_child("EquipmentChoice", true, false)
	check(selector != null and selector.is_visible_in_tree() and view.encloses(selector.get_global_rect()) and _unclipped(selector), "the active equipment selector is visible and on screen at %s" % shape)
	check(creator.accept_button.is_visible_in_tree() and view.encloses(creator.accept_button.get_global_rect()), "wardrobe confirmation stays visible and on screen at %s" % shape)
	var framing_controls := true
	for name in ["FullBodyView", "FaceView", "HandsView"]:
		var button: Button = creator.find_child(name, true, false)
		framing_controls = framing_controls and button != null and button.is_visible_in_tree() and view.encloses(button.get_global_rect()) and _unclipped(button)
	check(framing_controls, "all three framing controls are visible and on screen at %s" % shape)


func _check_projected_views(creator: CharacterCreator, shape: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_press(creator, "FullBodyView")
	await _frames(3)
	var full: Rect2 = _projected_bounds(creator.preview)
	var full_head: Rect2 = _projected_bounds(creator.preview, true)
	# Short sleeves have their rolled cuff higher on the arm than the long
	# sleeve's .62-.72 span. Include that actual cuff, not just the bare palm.
	var cuff_ratio: float = 0.30 if creator.draft.equipped.get("body", "") == "short_sleeve_shirt" else 0.60
	var full_hands: Rect2 = _projected_bounds(creator.preview, false, true, cuff_ratio)
	print("WARDROBE FRAMING: %s Full body=%s head=%s viewport=%s" % [shape, full, full_head, creator.preview.viewport.size])
	check(_inside_preview(creator.preview, full), "fully equipped cook, including tall hat and footwear, fits Full body at %s" % shape)
	_press(creator, "FaceView")
	await _frames(3)
	var face: Rect2 = _projected_bounds(creator.preview, true)
	print("WARDROBE FRAMING: %s Face head=%s viewport=%s" % [shape, face, creator.preview.viewport.size])
	check(_inside_preview(creator.preview, face) and face.size.y >= full_head.size.y * 2.0,
		"the complete cook-hat head fits a materially larger Face view at %s" % shape)
	_press(creator, "HandsView")
	await _frames(3)
	var hands: Rect2 = _projected_bounds(creator.preview, false, true, cuff_ratio)
	print("WARDROBE FRAMING: %s Hands cuffs/palms=%s viewport=%s" % [shape, hands, creator.preview.viewport.size])
	check(_inside_preview(creator.preview, hands) and hands.size.y >= full_hands.size.y * 2.0,
		"both equipped palms and actual sleeve cuffs fit a materially larger Hands view at %s" % shape)
	_press(creator, "FullBodyView")
	await _frames(3)


func _projected_bounds(preview: CharacterPreview, head_only: bool = false,
		hands_only: bool = false, cuff_ratio: float = 0.60) -> Rect2:
	var arrays: Array = preview.rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var found := false
	var result := Rect2()
	for i in range(vertices.size()):
		var bone: int = bones[i * 4]
		if head_only and bone != 1:
			continue
		if hands_only:
			if bone not in [2, 3]:
				continue
			if vertices[i].y > preview.rig.skeleton.get_bone_rest(bone).origin.y - PawnMesh.ARM_H * cuff_ratio:
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


func _check_accessory_isolation(appearance: CharacterAppearance) -> void:
	var envelope_ok := true
	var parts_ok := true
	for body in range(2):
		var look := appearance.clone()
		look.body_type = body
		var plain: PawnMesh.Rig = PawnMesh.build_appearance(look, _material(), {})
		var torso: AABB = _bone_bounds(plain, 0)
		for slot in ["ring", "neck"]:
			var item: String = "copper_ring" if slot == "ring" else "copper_pendant"
			var rig: PawnMesh.Rig = PawnMesh.build_appearance(look, _material(), {slot: item})
			# Small jewellery may replace hidden cloth topology, but must not
			# widen the chest or change the underlying torso silhouette.
			envelope_ok = envelope_ok and torso.grow(0.001).encloses(_bone_bounds(rig, 0))
			for bone in [1, 2, 3, 4, 5]:
				if slot == "ring" and bone == 2:
					continue  # The ring is deliberately worn on this one hand.
				parts_ok = parts_ok and _bone_signature(plain, bone) == _bone_signature(rig, bone)
			rig.root.free()
		plain.root.free()
	check(envelope_ok, "a ring or pendant preserves the base torso envelope in both keeper builds")
	check(parts_ok, "jewellery leaves unrelated heads, legs and hands unchanged; the ring belongs to one hand")


func _bone_bounds(rig: PawnMesh.Rig, bone: int) -> AABB:
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var found := false
	var result := AABB()
	for i in range(vertices.size()):
		if bones[i * 4] != bone:
			continue
		if not found:
			result = AABB(vertices[i], Vector3.ZERO)
			found = true
		else:
			result = result.expand(vertices[i])
	return result


func _bone_signature(rig: PawnMesh.Rig, bone: int) -> int:
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var selected_vertices := PackedVector3Array()
	var selected_colours := PackedColorArray()
	for i in range(vertices.size()):
		if bones[i * 4] == bone:
			selected_vertices.append(vertices[i])
			selected_colours.append(colours[i])
	return hash([selected_vertices, selected_colours])


func _unclipped(control: Control) -> bool:
	var rect: Rect2 = control.get_global_rect()
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is Control and ((parent as Control).clip_contents or parent is ScrollContainer):
			if not (parent as Control).get_global_rect().encloses(rect):
				return false
		parent = parent.get_parent()
	return true


func _press(creator: CharacterCreator, name: String) -> bool:
	var button: Button = creator.find_child(name, true, false)
	if button == null:
		check(false, "real editor control %s exists" % name)
		return false
	button.pressed.emit()
	return true


func _equip_through_controls(creator: CharacterCreator, slot: String, id: String) -> bool:
	if not _press(creator, "Slot" + slot.capitalize()):
		return false
	var selector: OptionButton = creator.find_child("EquipmentChoice", true, false)
	if selector == null:
		return false
	var index: int = _item_index(selector, id)
	if index < 0 or selector.is_item_disabled(index):
		return false
	selector.select(index)
	selector.item_selected.emit(index)
	return creator.draft.equipped.get(slot, "") == id


func _item_index(selector: OptionButton, id: String) -> int:
	for i in range(selector.item_count):
		if String(selector.get_item_metadata(i)) == id:
			return i
	return -1


func _signature(appearance: CharacterAppearance, equipped: Dictionary) -> int:
	var rig: PawnMesh.Rig = PawnMesh.build_appearance(appearance, _material(), equipped)
	var value: int = _mesh_signature(rig)
	rig.root.free()
	return value


func _mesh_signature(rig: PawnMesh.Rig) -> int:
	if rig.body.mesh.get_surface_count() != 1:
		return 0
	var arrays: Array = rig.body.mesh.surface_get_arrays(0)
	return hash([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_COLOR], arrays[Mesh.ARRAY_BONES]])


func _inspect_rig(rig: PawnMesh.Rig) -> Dictionary:
	var rig_ok: bool = rig.body.mesh.get_surface_count() == 1 and rig.skeleton.get_bone_count() == 6 and rig.root.find_children("*", "MeshInstance3D", true, false).size() == 1
	for i in range(rig.skeleton.get_bone_count()):
		rig_ok = rig_ok and rig.skeleton.get_bone_rest(i).basis.get_scale().is_equal_approx(Vector3.ONE)
	var vertices: PackedVector3Array = rig.body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var finite := true
	var lowest := INF
	for vertex in vertices:
		finite = finite and vertex.is_finite() and vertex.y >= -0.001 and vertex.y < 1.6 and absf(vertex.x) < 0.5 and absf(vertex.z) < 0.5
		lowest = minf(lowest, vertex.y)
	finite = finite and absf(lowest) <= 0.001
	var anchor := Vector3(0, PawnMesh.LEG_H + PawnMesh.TORSO_H * 0.55, PawnMesh.BODY_D * 0.5 + 0.12)
	return {"rig": rig_ok, "bounds": finite, "carry": rig.carry_anchor.position.is_equal_approx(anchor), "triangles": vertices.size() / 3}


func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	return material


func _disk_snapshot() -> String:
	var rows: Array[String] = []
	for slot in range(3):
		var path: String = GameState.slot_path(slot)
		rows.append(FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>")
	return JSON.stringify(rows)


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _shot(label: String) -> void:
	if shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(shots + "_" + label + ".png") == OK, "capture %s" % label)
