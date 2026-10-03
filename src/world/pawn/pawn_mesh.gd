class_name PawnMesh
extends RefCounted

## One surface per humanoid, with rigid bone weights preserving the faceted art.
## Animation still drives joint transforms; a skeleton submits all six parts
## together, including shadow passes, rather than six separate draw submissions.
##
## Each limb's mesh is authored hanging *below* its origin, so the origin is the
## pivot: a shoulder for arms, a hip for legs. Rotating the node then swings the
## limb from the right place instead of about its middle.
##
## Who someone is shows in what they wear. Staff have job-specific house
## uniforms; patrons are adventurers off the road, with original old-school
## fantasy kit -- saturated colours, metal by tier, capes and hats that read at
## the management camera's distance. Telling the two apart at a glance is not
## decoration: it is the difference between reading a busy room and squinting.

const HEIGHT: float = 1.1

const LEG_H: float = HEIGHT * 0.38
const TORSO_H: float = HEIGHT * 0.34
const HEAD_H: float = HEIGHT * 0.20
const ARM_H: float = HEIGHT * 0.30

const FACE_LEVELS: Array[float] = [0.025, 0.074, 0.125, HEAD_H * 0.87]
const FACE_RADII: Array[Vector2] = [Vector2(0.068, 0.078), Vector2(0.096, 0.096),
	Vector2(0.108, 0.100), Vector2(0.100, 0.094)]
## Open hats seat around the upper forehead, below the covered hair's apex.
const HAT_BRIM_Y: float = HEAD_H - 0.020

const BODY_W: float = 0.36
const BODY_D: float = 0.24
const LIMB_W: float = 0.12

## Adult ordinary silhouette: the waist rises inside the existing torso while
## its neck remains at the shoulder. Joints, seat height and cargo stay fixed.
const ORDINARY_TORSO_Y: float = 0.80
const ORDINARY_WAIST_RISE: float = TORSO_H * (1.0 - ORDINARY_TORSO_Y)
const ORDINARY_HEAD_SCALE := Vector3(0.78, 0.82, 0.86)

## The house uniform: a burgundy waistcoat over a white shirt, a long apron,
## dark trousers and polished boots. Retained as the legacy/default staff cut;
## StaffUniforms supplies the identifying cuts and hats for current positions.
const UNIFORM_VEST := Color("6e2233")
const UNIFORM_SHIRT := Color("e8e0cc")
const UNIFORM_TROUSER := Color("2f2b2e")
const UNIFORM_BOOT := Color("1c1917")
const CRAVAT := Color("1f1a1c")
## Staff still draw an index from this, so they consume the same randomness
## they always have; it now varies only the hair, never the clothes.
const TUNIC_COLORS: Array[Color] = [
	Color("8a3f2e"), Color("4a5d7e"), Color("6b7a3a"),
	Color("7d5b34"), Color("5f4a6b"), Color("9c7b3c"),
]
const SKIN_COLORS: Array[Color] = [
	Color("d9a77c"), Color("c08a5e"), Color("8a5f3c"), Color("f0c39c"),
]

## Adventurers' capes: red, blue, green, gold, purple, black, white, orange.
const CAPE_COLORS: Array[Color] = [
	Color("b0302a"), Color("2c52a8"), Color("2f7a3a"), Color("d0a92a"),
	Color("6b3a8c"), Color("232123"), Color("d8d6d0"), Color("c8641e"),
]
## Bronze, iron, steel, mithril, adamant, rune.
const METAL_TIERS: Array[Color] = [
	Color("987047"), Color("626b72"), Color("77858b"),
	Color("55638f"), Color("4f6f52"), Color("4f9cb3"),
]
const METAL_NAMES: Array[String] = ["bronze", "iron", "steel", "mithril", "adamant", "rune"]
const ROBE_COLORS: Array[Color] = [
	Color("2d4aa8"), Color("9e2b2b"), Color("262428"), Color("5d3a8a"),
]
const ROBE_NAMES: Array[String] = ["blue", "red", "black", "purple"]
const PARTY_HAT_COLORS: Array[Color] = [
	Color("d9322b"), Color("e8c93a"), Color("3fa64a"),
	Color("3a6ed9"), Color("8f4ac2"), Color("f2f0ea"),
]
const LEATHER := Color("6b4a2e")
const RANGER_GREEN := Color("4a6b2e")
const CHAIN := Color("7a7d80")
const BEARD := Color("c9c4b8")
const VISOR := Color("141414")

const TROUSER := Color("4a3f33")
const BOOT := Color("2e2620")
const BELT := Color("493327")
const BRASS := Color("c59c52")
const HAIR_COLORS: Array[Color] = [
	Color("36291e"), Color("614127"), Color("ac7c37"),
	Color("853e25"), Color("c0b49a"),
]

enum Look { STAFF, WARRIOR, WIZARD, RANGER, ADVENTURER, DUELIST, PILGRIM }


class Rig:
	extends RefCounted
	var root: Node3D
	var torso: Node3D
	var head: Node3D
	var arm_l: Node3D
	var arm_r: Node3D
	var leg_l: Node3D
	var leg_r: Node3D
	var skeleton: Skeleton3D
	var joints: Array[Node3D] = []
	## Where a carried item sits. Populated whether or not anything is held.
	var carry_anchor: Node3D
	## In words, for the inspector: "a steel-clad warrior", "in the house uniform".
	var description: String = ""
	## The one skinned mesh everything is drawn in, for the outline overlay.
	var body: MeshInstance3D
	## Visual preset only. Pawn stores its guest archetype independently.
	var kind: int = 0

	func sync_pose() -> void:
		for i in range(joints.size()):
			skeleton.set_bone_pose_position(i, joints[i].position)
			skeleton.set_bone_pose_rotation(i, joints[i].quaternion)


static func build(rng: RandomNumberGenerator, material: Material, is_customer: bool = false,
		uniform: Color = Color(0, 0, 0, 0)) -> Rig:
	return build_appearance(generate_appearance(rng, is_customer, uniform), material)


## Preserve the established two draws. A stored appearance and its renderer
## never draw from the movement, guest or simulation streams.
static func generate_appearance(rng: RandomNumberGenerator, is_customer: bool = false,
		uniform: Color = Color(0, 0, 0, 0)) -> CharacterAppearance:
	var palette: Array[Color] = CAPE_COLORS if is_customer else TUNIC_COLORS
	var look_index: int = rng.randi_range(0, palette.size() - 1)
	var skin_index: int = rng.randi_range(0, SKIN_COLORS.size() - 1)
	# Appearance must not consume extra simulation randomness: the same seed
	# still produces the same initial facing, idle timers and walking choices.
	# Everything below is derived from these two draws.
	var style: int = look_index + skin_index * palette.size()
	var variant: int = PawnWardrobe.variant_for_state(rng.state) if is_customer else 0
	var outfit: Dictionary = customer_outfit(style, look_index, variant) if is_customer else staff_outfit(uniform)
	var appearance := CharacterAppearance.new()
	appearance.skin = SKIN_COLORS[skin_index]
	appearance.hair = HAIR_COLORS[(style + variant * 2) % HAIR_COLORS.size()]
	appearance.body_type = (style + variant) % 2
	appearance.hair_style = variant if is_customer else style % 4
	# Derive facial variety from the established two draws; never advance a
	# worker's movement stream to choose a cosmetic expression.
	appearance.face_type = (floori(style / 4.0) + variant) % CharacterAppearance.FACE_TYPES.size()
	appearance.expression = (style + variant * 2) % CharacterAppearance.EXPRESSIONS.size()
	appearance.top = outfit["body"]
	appearance.trousers = outfit["legs"]
	appearance.boots = outfit["boots"]
	appearance.family = int(outfit.get("look", Look.STAFF))
	appearance.style = style
	appearance.cape_index = look_index
	appearance.variant = variant
	appearance.uniform = uniform
	return appearance


## The creator, staff and patrons all use this pure, single-surface builder.
## Equipment here is cosmetic attachment data, independent of a guest's class.
static func build_appearance(appearance: CharacterAppearance, material: Material,
		equipped: Dictionary = {}, staff_role_id: StringName = &"") -> Rig:
	var outfit: Dictionary = _outfit_for(appearance, equipped, staff_role_id)
	var slender: bool = appearance.body_type == 1
	# A leaner old-school silhouette, baked into the same rig and equipment.
	# Heights and the carry point stay fixed so chairs, walking and cargo fit.
	var torso_scale := Vector3(0.79 if slender else 0.90, 1.0, 0.87 if slender else 0.90)
	var ordinary: bool = outfit.get("ordinary", false)
	var arm_scale := Vector3(0.72 if slender else 0.80, 1.05, 0.82) if ordinary else Vector3(0.78 if slender else 0.85, 1.0, 0.87)
	var leg_scale := Vector3(0.84 if slender else 0.92, 1.0, 0.92)
	var head_scale: Vector3 = ORDINARY_HEAD_SCALE if ordinary else Vector3(0.94, 0.96, 0.94)

	var rig := Rig.new()
	rig.description = outfit["description"]
	rig.kind = int(outfit.get("look", Look.STAFF))
	rig.root = Node3D.new()
	rig.root.name = "Pawn"

	var hip_y: float = LEG_H
	var shoulder_y: float = hip_y + TORSO_H

	# Torso sits on the hips, built upward from its own origin.
	rig.torso = _limb(_torso_mesh(outfit), Vector3(0.0, hip_y, 0.0), material, torso_scale)
	rig.root.add_child(rig.torso)

	rig.head = _limb(_head_mesh(appearance.skin, appearance.hair, appearance.style, outfit),
		Vector3(0.0, shoulder_y, 0.0), material, head_scale)
	rig.root.add_child(rig.head)

	# Arms and legs hang below their pivots so rotation swings from the joint.
	var hands: Color = outfit.get("hands", appearance.skin)
	var shoulder_half: float = BODY_W * 0.5
	if outfit.get("ordinary", false):
		shoulder_half -= 0.030
	elif appearance.family != Look.WARRIOR:
		shoulder_half -= 0.014
	var shoulder_x: float = shoulder_half * torso_scale.x + LIMB_W * 0.5 * arm_scale.x
	rig.arm_l = _limb(_arm_mesh(outfit["sleeve"], outfit["cuff"], hands, outfit, 1.0),
		Vector3(-shoulder_x, shoulder_y - 0.02, 0.0), material, arm_scale)
	rig.arm_r = _limb(_arm_mesh(outfit["sleeve"], outfit["cuff"], hands, outfit),
		Vector3(shoulder_x, shoulder_y - 0.02, 0.0), material, arm_scale)
	rig.root.add_child(rig.arm_l)
	rig.root.add_child(rig.arm_r)

	rig.leg_l = _limb(_leg_mesh(outfit["legs"], outfit["boots"], outfit),
		Vector3(-LIMB_W * 0.62 * torso_scale.x, hip_y, 0.0), material, leg_scale)
	rig.leg_r = _limb(_leg_mesh(outfit["legs"], outfit["boots"], outfit),
		Vector3(LIMB_W * 0.62 * torso_scale.x, hip_y, 0.0), material, leg_scale)
	rig.root.add_child(rig.leg_l)
	rig.root.add_child(rig.leg_r)

	# In front of the chest, where both hands would meet.
	rig.carry_anchor = Node3D.new()
	rig.carry_anchor.name = "Carry"
	rig.carry_anchor.position = Vector3(0.0, hip_y + TORSO_H * 0.55, BODY_D * 0.5 + 0.12)
	rig.root.add_child(rig.carry_anchor)

	_merge_rig(rig, material)
	return rig


static func _outfit_for(appearance: CharacterAppearance, equipped: Dictionary,
		staff_role_id: StringName = &"") -> Dictionary:
	# Slot IDs select a visual cut. They never change the stored appearance
	# family or the pawn's independent staff role/customer archetype.
	var wardrobe: Dictionary = StaffUniforms.equipment_for(staff_role_id) if appearance.family == Look.STAFF else {}
	var role_uniform: bool = not wardrobe.is_empty()
	var uniform_colour: Color = appearance.top
	if role_uniform:
		var role: StaffRole = StaffRole.of(staff_role_id)
		if role != null:
			uniform_colour = role.uniform
	for slot in WardrobeCatalog.SLOTS:
		if equipped.has(slot):
			# An explicit missing/unknown cosmetic suppresses the default too;
			# ownership is retained by the save parser, with a safe visual fallback.
			wardrobe.erase(slot)
		var value: Variant = equipped.get(slot, "")
		if not value is String:
			continue
		var item: String = value
		if WardrobeCatalog.known(item) and WardrobeCatalog.slot_for(item) == slot:
			wardrobe[slot] = item
	var modular: bool = wardrobe.has("body")
	for slot in ["outer", "legs", "feet", "hands", "neck", "ring"]:
		modular = modular or wardrobe.has(slot)
	modular = modular or wardrobe.get("head", "") == "cook_hat" or wardrobe.get("head", "") in KeeperWardrobeArt.STAFF_HATS
	var outfit: Dictionary
	if appearance.family < 0 or modular:
		outfit = {
			"look": -1, "description": "in a linen travelling tunic", "ordinary": true,
			"body": appearance.top, "sleeve": appearance.top,
			"cuff": appearance.top.lightened(0.1), "hands": appearance.skin,
			"legs": appearance.trousers, "boots": appearance.boots,
			"headgear": "", "back": "", "cape": null,
		}
	elif appearance.family == Look.STAFF:
		outfit = staff_outfit(appearance.top)
	else:
		# A preset selects its family explicitly; the remainder of the stored
		# style still chooses tier/dye without coupling clothing to behaviour.
		var style: int = appearance.style - posmod(appearance.style, 6) + appearance.family - 1
		outfit = customer_outfit(style, appearance.cape_index, appearance.variant)
		var old_body: Color = outfit["body"]
		if outfit["sleeve"] == old_body:
			outfit["sleeve"] = appearance.top
		outfit["body"] = appearance.top
		outfit["legs"] = appearance.trousers
		outfit["boots"] = appearance.boots
	outfit["hair_style"] = appearance.hair_style
	outfit["face_type"] = appearance.face_type
	outfit["expression"] = appearance.expression
	outfit["skin"] = appearance.skin
	outfit["wardrobe"] = wardrobe
	if role_uniform and not equipped.has("body"):
		outfit["body"] = uniform_colour
		outfit["sleeve"] = uniform_colour
		outfit["cuff"] = uniform_colour.lightened(0.1)
	for entry in [["body", "body_item"], ["outer", "outer_item"], ["legs", "legs_item"],
		["feet", "feet_item"], ["hands", "hands_item"], ["neck", "neck_item"], ["ring", "ring_item"]]:
		outfit[String(entry[1])] = String(wardrobe.get(String(entry[0]), ""))
	if wardrobe.get("body", "") == "leather_vest":
		outfit["body"] = LEATHER
		outfit["sleeve"] = appearance.top
		outfit["cuff"] = appearance.top.lightened(0.1)
	elif wardrobe.get("body", "") == "house_waistcoat":
		outfit["sleeve"] = UNIFORM_SHIRT
		outfit["cuff"] = outfit["body"].lightened(0.1)
	if wardrobe.get("hands", "") == "work_gloves":
		outfit["hands"] = LEATHER.darkened(0.12)
	if wardrobe.get("head", "") in KeeperWardrobeArt.COVERED_HATS:
		outfit["headgear"] = wardrobe["head"]
		outfit["headgear_colour"] = UNIFORM_SHIRT if wardrobe["head"] == "cook_hat" else Color("65513e")
		if wardrobe["head"] == "straw_hat":
			outfit["headgear_colour"] = Color("c9a45b")
		elif wardrobe["head"] == "headscarf":
			outfit["headgear_colour"] = Color("8eb7b4")
		elif wardrobe["head"] == "fishing_hat":
			outfit["headgear_colour"] = Color("2f5d62")
		if role_uniform and not equipped.has("head"):
			outfit["headgear_colour"] = StaffUniforms.hat_colour(staff_role_id, uniform_colour)
	if wardrobe.get("cape", "") == "travel_cape":
		outfit["cape"] = CAPE_COLORS[posmod(appearance.cape_index, CAPE_COLORS.size())]
		outfit["edge"] = BRASS.darkened(0.15)
		outfit["short_cape"] = false
		outfit["cape_pattern"] = 0
	if wardrobe.get("backpack", "") == "travel_pack":
		outfit["back"] = "pack"
		outfit["trim"] = Color("667953")
	if modular:
		var main_piece: String = String(wardrobe.get("outer", wardrobe.get("body", "linen_shirt")))
		outfit["description"] = "wearing %s" % WardrobeCatalog.item_name(main_piece).to_lower()
		if role_uniform:
			outfit["description"] = "in the %s's uniform" % String(staff_role_id)
	return outfit


## The original house uniform, still used without an explicit role context.
## Current position uniforms are composed from StaffUniforms' clothing slots.
static func staff_outfit(vest: Color = Color(0, 0, 0, 0)) -> Dictionary:
	if vest.a <= 0.0:
		vest = UNIFORM_VEST
	return {
		"look": Look.STAFF, "description": "in the house uniform",
		"body": vest, "shirt": UNIFORM_SHIRT, "sleeve": UNIFORM_SHIRT, "cuff": vest,
		"legs": UNIFORM_TROUSER, "boots": UNIFORM_BOOT, "headgear": "", "back": "", "cape": null,
	}


## An adventurer, chosen from the style number so it costs no randomness.
static func customer_outfit(style: int, cape_index: int, variant: int = 0) -> Dictionary:
	var cape: Color = CAPE_COLORS[cape_index % CAPE_COLORS.size()]
	var tier: int = (style / 6) % METAL_TIERS.size()
	var metal: Color = METAL_TIERS[tier]
	var outfit: Dictionary
	match style % 6:
		0:
			outfit = {
				"look": Look.WARRIOR, "description": "a %s-clad warrior" % METAL_NAMES[tier],
				"body": metal, "sleeve": metal, "cuff": metal.darkened(0.25), "hands": metal.darkened(0.3),
				"legs": metal.darkened(0.08), "boots": metal.darkened(0.35), "cape": cape,
				"headgear": "full_helm" if tier % 2 == 0 else "med_helm", "headgear_colour": metal,
				"back": "shield", "back_colour": metal, "trim": cape, "sword": true,
			}
		1:
			var robe_index: int = (style / 6) % ROBE_COLORS.size()
			var robe: Color = ROBE_COLORS[robe_index]
			outfit = {
				"look": Look.WIZARD, "description": "a wizard in %s" % ROBE_NAMES[robe_index],
				"body": robe, "sleeve": robe, "cuff": BRASS, "legs": robe.darkened(0.1),
				"boots": LEATHER.darkened(0.3), "cape": null, "robe": true,
				"headgear": "wizard_hat", "headgear_colour": robe, "beard": style % 4 == 1, "back": "staff", "jewel": Color("68c7cf"),
			}
		2:
			var ranger: Color = [RANGER_GREEN, Color("356459"), Color("657342")][(style / 6) % 3]
			outfit = {
				"look": Look.RANGER, "description": "a ranger",
				"body": LEATHER, "sleeve": ranger, "cuff": LEATHER.darkened(0.3), "hands": LEATHER,
				"legs": TROUSER, "boots": LEATHER.darkened(0.35), "cape": ranger, "short_cape": true,
				"headgear": "hood", "headgear_colour": ranger.darkened(0.1),
				"back": "quiver", "back_colour": LEATHER,
			}
		3:
			outfit = {
				"look": Look.ADVENTURER, "description": "a delver in chainmail with a bedroll",
				"body": CHAIN, "sleeve": CHAIN.darkened(0.1), "cuff": LEATHER, "legs": TROUSER,
				"boots": BOOT, "cape": null, "headgear": "coif" if (style / 6) % 2 == 0 else "",
				"headgear_colour": CHAIN, "back": "pack", "trim": cape, "sword": true,
			}
		4:
			outfit = {
				"look": Look.DUELIST, "description": "a road duelist in a feathered hat",
				"body": Color("713544"), "sleeve": Color("bda789"), "cuff": LEATHER,
				"legs": Color("363f4a"), "boots": BOOT, "cape": cape, "short_cape": true,
				"headgear": "feather_hat", "headgear_colour": Color("463c39"), "back": "", "sword": true,
			}
		_:
			outfit = {
				"look": Look.PILGRIM, "description": "a wandering sun scholar",
				"body": Color("d3c7a5"), "sleeve": Color("d3c7a5"), "cuff": Color("9a5934"),
				"legs": TROUSER, "boots": BOOT, "cape": Color("a05633"), "robe": true,
				"headgear": "hood", "headgear_colour": Color("d3c7a5"), "back": "staff", "jewel": Color("e9b953"),
			}
	PawnWardrobe.apply(outfit, style, variant)
	# Now and then, the hat everybody wanted.
	if style % 13 == 7:
		outfit["headgear"] = "party_hat"
		outfit["headgear_colour"] = PARTY_HAT_COLORS[cape_index % PARTY_HAT_COLORS.size()]
		outfit["description"] += ", in a party hat"
	outfit["style"] = style
	return outfit


static func _merge_rig(rig: Rig, material: Material) -> void:
	var parts: Array[Node3D] = [rig.torso, rig.head, rig.arm_l, rig.arm_r, rig.leg_l, rig.leg_r]
	var joints: Array[Node3D] = []
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var skin := Skin.new()
	rig.skeleton = Skeleton3D.new()
	rig.skeleton.name = "Skeleton"
	rig.root.add_child(rig.skeleton)
	for i in range(parts.size()):
		var part: MeshInstance3D = parts[i] as MeshInstance3D
		var arrays: Array = part.mesh.surface_get_arrays(0)
		var local_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in local_vertices:
			vertices.append(part.transform * vertex)
			bones.append_array(PackedInt32Array([i, 0, 0, 0]))
			weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		colors.append_array(arrays[Mesh.ARRAY_COLOR])
		rig.skeleton.add_bone("joint_%d" % i)
		rig.skeleton.set_bone_rest(i, part.transform)
		skin.add_bind(i, part.transform.affine_inverse())
		var joint := Node3D.new()
		joint.transform = part.transform
		rig.root.add_child(joint)
		joints.append(joint)
		# These temporary meshes never enter the scene tree.
		part.free()
	var merged: Array = []
	merged.resize(Mesh.ARRAY_MAX)
	merged[Mesh.ARRAY_VERTEX] = vertices
	merged[Mesh.ARRAY_NORMAL] = normals
	merged[Mesh.ARRAY_COLOR] = colors
	merged[Mesh.ARRAY_BONES] = bones
	merged[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.skin = skin
	instance.skeleton = NodePath("../Skeleton")
	instance.material_override = material
	rig.body = instance
	# Swinging arms extend beyond the standing mesh bounds.
	instance.extra_cull_margin = HEIGHT
	rig.root.add_child(instance)
	rig.torso = joints[0]
	rig.head = joints[1]
	rig.arm_l = joints[2]
	rig.arm_r = joints[3]
	rig.leg_l = joints[4]
	rig.leg_r = joints[5]
	rig.joints = joints
	rig.sync_pose()


static func _limb(mesh: ArrayMesh, at: Vector3, material: Material, shape: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if shape != Vector3.ONE:
		# Bake shape into geometry. Bone rests retain unit scale, so the same
		# walk/carry animations work for both silhouettes without stretching gear.
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(vertices.size()):
			vertices[i] *= shape
			normals[i] = (normals[i] / shape).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh
	mi.position = at
	mi.material_override = material
	return mi


static func _torso_mesh(outfit: Dictionary) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var body: Color = outfit["body"]
	var robe: bool = outfit.get("robe", false)
	if outfit.get("ordinary", false):
		KeeperWardrobeArt.torso(mb, TORSO_H, outfit)
		# Shift the complete garment, apron, buttons and ties together before
		# adding luggage. Cape/pack shoulder attachments keep their old fit.
		mb.transform_geometry(Transform3D(Basis.from_scale(Vector3(1, ORDINARY_TORSO_Y, 1)),
			Vector3(0, ORDINARY_WAIST_RISE, 0)))
		# Upper trousers belong to the hips, rather than projecting above each
		# swinging leg. This closed section bridges the higher hem at full stride
		# and during the existing torso bob, without changing either hip pivot.
		KeeperWardrobeArt.hips(mb, outfit["legs"])
	else:
		# Uniforms and armor retain their authored seams, beneath the same lean
		# body scales. Robes keep their longer hem and recognizable silhouette.
		_tapered_box(mb, -0.12 if robe else -0.045, 0.12, Vector2(0.18, 0.13),
			Vector2(0.15, 0.115), body.darkened(0.08))
		_tapered_box(mb, 0.12, TORSO_H, Vector2(0.15, 0.115), Vector2(BODY_W * 0.5, BODY_D * 0.5), body)

	match int(outfit["look"]):
		-1:
			pass  # The continuous ordinary tunic includes its collar and belt.
		Look.STAFF:
			# The shirt shows down the front between the waistcoat's panels, with
			# a dark cravat at the throat and brass buttons down one edge.
			mb.add_box(Vector3(-0.034, 0.12, 0.118), Vector3(0.068, TORSO_H - 0.12, 0.008), outfit["shirt"])
			mb.add_tri(Vector3(-0.07, TORSO_H + 0.002, 0.122), Vector3(0.0, TORSO_H - 0.11, 0.122),
				Vector3(0.07, TORSO_H + 0.002, 0.122), outfit["shirt"])
			mb.add_box(Vector3(-0.026, TORSO_H - 0.07, 0.127), Vector3(0.052, 0.055, 0.01), CRAVAT)
			for i in range(3):
				mb.add_box(Vector3(0.036, 0.15 + float(i) * 0.05, 0.126), Vector3(0.016, 0.016, 0.008), BRASS)
			# A long waist apron, down over the thighs, and its strings.
			mb.add_quad(Vector3(-0.13, -0.2, 0.15), Vector3(0.13, -0.2, 0.15),
				Vector3(0.1, 0.13, 0.136), Vector3(-0.1, 0.13, 0.136), UNIFORM_SHIRT)
			mb.add_box(Vector3(-0.155, 0.1, -0.121), Vector3(0.31, 0.03, 0.257), UNIFORM_SHIRT.darkened(0.15))
		Look.WARRIOR:
			# A ridged breastplate catches two broad values at play distance.
			for side in [-1.0, 1.0]:
				var a := Vector3(0, 0.145, 0.172)
				var b := Vector3(side * 0.13, 0.165, 0.125)
				var c := Vector3(side * 0.152, 0.32, 0.13)
				var d := Vector3(0, 0.345, 0.18)
				if side < 0:
					mb.add_quad(d, c, b, a, body.lightened(0.16))
				else:
					mb.add_quad(a, b, c, d, body.lightened(0.04))
				PawnEquipment.panel(mb, [Vector2(side * 0.09 - 0.064, 0.06), Vector2(side * 0.09 - 0.075, -0.075), Vector2(side * 0.09 + 0.065, -0.07), Vector2(side * 0.09 + 0.054, 0.06)], 0.133, 0.019, body.darkened(0.12))
			mb.add_limb(Vector3(-0.13, 0.335, 0.132), Vector3(0, 0.351, 0.18), 0.009, 0.009, 4, body.lightened(0.37))
			mb.add_limb(Vector3(0, 0.351, 0.18), Vector3(0.13, 0.335, 0.132), 0.009, 0.009, 4, body.lightened(0.37))
		Look.WIZARD, Look.PILGRIM:
			mb.add_tri(Vector3(-0.07, TORSO_H + 0.002, 0.122), Vector3(0.0, TORSO_H - 0.11, 0.122),
				Vector3(0.07, TORSO_H + 0.002, 0.122), body.darkened(0.45))
			PawnEquipment.robe(mb, body, outfit["cuff"])
			for side in [-1.0, 1.0]:
				mb.add_limb(Vector3(side * 0.08, 0.345, 0.128), Vector3(side * 0.045, 0.13, 0.145), 0.012, 0.012, 4, outfit["cuff"])
			PawnEquipment.panel(mb, [Vector2(0, 0.295), Vector2(-0.027, 0.245), Vector2(0, 0.20), Vector2(0.027, 0.245)], 0.147, 0.017, outfit["jewel"])
		Look.RANGER:
			for side in [-1.0, 1.0]:
				PawnEquipment.panel(mb, [Vector2(side * 0.072 - 0.051, 0.32), Vector2(side * 0.072 - 0.05, 0.13), Vector2(side * 0.072 + 0.05, 0.13), Vector2(side * 0.072 + 0.057, 0.32)], 0.122, 0.018, LEATHER.lightened(0.18))
			for i in range(3):
				mb.add_limb(Vector3(-0.029, 0.17 + i * 0.05, 0.153), Vector3(0.028, 0.20 + i * 0.05, 0.153), 0.005, 0.005, 4, BRASS)
			_tapered_box(mb, 0.285, 0.36, Vector2(0.17, 0.14), Vector2(0.09, 0.10), outfit["sleeve"].lightened(0.1))
		Look.ADVENTURER:
			PawnEquipment.mail(mb, Vector3(-0.12, 0.15, 0.125), 7, 4, 0.037, body)
			_tapered_box(mb, 0.29, 0.365, Vector2(0.19, 0.145), Vector2(0.09, 0.10), outfit["trim"])
			PawnEquipment.panel(mb, [Vector2(0.04, 0.30), Vector2(0.065, 0.13), Vector2(0.12, 0.10), Vector2(0.10, 0.30)], 0.152, 0.012, outfit["trim"])
		Look.DUELIST:
			mb.add_box(Vector3(-0.035, 0.12, 0.12), Vector3(0.07, 0.23, 0.018), outfit["sleeve"])
			for side in [-1.0, 1.0]:
				PawnEquipment.panel(mb, [Vector2(side * 0.11 - 0.035, 0.34), Vector2(-0.018, 0.16), Vector2(0.018, 0.16), Vector2(side * 0.11 + 0.035, 0.34)], 0.14, 0.014, body.lightened(0.15))
			for i in range(3):
				mb.add_box(Vector3(0.06, 0.15 + i * 0.047, 0.143), Vector3(0.014, 0.015, 0.012), BRASS)

	if outfit.get("tabard", false):
		PawnEquipment.tabard(mb, outfit["trim"], outfit["edge"])
	var cape = outfit.get("cape", null)
	if cape != null:
		PawnEquipment.cape(mb, cape, outfit.get("edge", BRASS.darkened(0.12)), outfit.get("short_cape", false), outfit.get("cape_pattern", 0))
	match String(outfit.get("back", "")):
		"shield":
			PawnEquipment.shield(mb, outfit["back_colour"], outfit["trim"], outfit.get("emblem", 0))
		"quiver":
			PawnEquipment.quiver_and_bow(mb, outfit.get("edge", UNIFORM_SHIRT).lightened(0.12))
			PawnEquipment.sling(mb, LEATHER.darkened(0.2))
		"pack":
			# A cape sits against the back and the pack is strapped over it. Move
			# only the luggage outward; front straps retain their shoulder anchors.
			PawnEquipment.pack(mb, outfit["trim"].darkened(0.2), -0.05 if cape != null else 0.0)
		"staff":
			PawnEquipment.staff(mb, outfit["jewel"], outfit.get("variant", 0))
			PawnEquipment.sling(mb, LEATHER)
	if int(outfit["look"]) > Look.STAFF:
		PawnEquipment.belt_kit(mb, outfit.get("accent", Color("518f85")), robe, outfit.get("book_colour", Color("38635c")))
	if outfit.get("sword", false):
		PawnEquipment.sword(mb)
	return mb.commit()


## Clipped cheek corners and a proud nose convey facing without textures.
static func _head_mesh(skin: Color, hair: Color, style: int, outfit: Dictionary) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var gear: String = String(outfit.get("headgear", ""))
	var gear_colour: Color = outfit.get("headgear_colour", hair)
	if outfit.get("ordinary", false):
		return KeeperWardrobeArt.head(skin, hair, int(outfit.get("hair_style", 0)), outfit, VISOR)
	_tapered_box(mb, -0.006, 0.049, Vector2(0.035, 0.035), Vector2(0.041, 0.037), skin.darkened(0.08))
	if gear == "full_helm":
		_chamfered_head(mb, 0.026, HEAD_H, 0.122, 0.11, gear_colour)
		mb.add_blob(Vector3(0, HEAD_H - 0.007, 0), Vector3(0.127, 0.093, 0.116), 3, 8, gear_colour.lightened(0.06))
		# Separated eye slits and a projecting nose-ridge keep the face readable.
		for side in [-1.0, 1.0]:
			mb.add_box(Vector3(side * 0.043 - 0.031, 0.142, 0.111), Vector3(0.062, 0.021, 0.012), VISOR)
			PawnEquipment.panel(mb, [Vector2(side * 0.055 - 0.036, 0.128), Vector2(side * 0.055 - 0.034, 0.037), Vector2(side * 0.055 + 0.032, 0.04), Vector2(side * 0.055 + 0.036, 0.128)], 0.112, 0.023, gear_colour.darkened(0.08))
			for i in range(2):
				mb.add_box(Vector3(side * 0.055 - 0.017, 0.064 + i * 0.026, 0.137), Vector3(0.033, 0.009, 0.007), VISOR.lightened(0.12))
		mb.add_limb(Vector3(0, 0.056, 0.135), Vector3(0, 0.235, 0.123), 0.013, 0.018, 4, gear_colour.lightened(0.35))
		mb.add_box(Vector3(-0.014, HEAD_H + 0.045, -0.073), Vector3(0.028, 0.024, 0.15), gear_colour.lightened(0.28))
		return mb.commit()

	# The skull ends underneath the hair/hood. A taller flat cap pokes through
	# the sloped crown when viewed from the management camera.
	_face_planes(mb, skin)
	if not gear in ["hood", "coif", "med_helm"]:
		_add_hair(mb, hair, int(outfit.get("hair_style", 0)), gear,
			outfit.get("edge", BRASS))
	# The bridge, two sides and underside form a small wedge, without a cube
	# sitting on the face. Eye and mouth planes remain readable from three quarters.
	var nose_l := Vector3(-0.016, 0.105, 0.100)
	var nose_r := Vector3(0.016, 0.105, 0.100)
	var bridge := Vector3(0, 0.161, 0.099)
	var tip := Vector3(0, 0.114, 0.127)
	mb.add_tri(nose_l, tip, bridge, skin.darkened(0.07))
	mb.add_tri(bridge, tip, nose_r, skin.lightened(0.025))
	mb.add_tri(nose_l, nose_r, tip, skin.darkened(0.17))
	for side in [-1.0, 1.0]:
		# Broad ink planes sit just above the cheek surface. They keep the face
		# readable without tiny projecting boxes casting heavy eye/brow shadows.
		var eye_x: float = side * 0.048
		_face_detail(mb, Vector2(eye_x - 0.014, 0.137), Vector2(eye_x + 0.014, 0.137),
			Vector2(eye_x + 0.012, 0.150), Vector2(eye_x - 0.012, 0.150), Color("c5bba6"), 0.0015)
		_face_detail(mb, Vector2(eye_x - 0.005, 0.138), Vector2(eye_x + 0.005, 0.138),
			Vector2(eye_x + 0.005, 0.150), Vector2(eye_x - 0.005, 0.150), VISOR, 0.0025)
		_face_detail(mb, Vector2(eye_x - 0.015, 0.161), Vector2(eye_x + 0.015, 0.161),
			Vector2(eye_x + 0.014, 0.168), Vector2(eye_x - 0.014, 0.169), hair.darkened(0.18), 0.0015)
		if not gear in ["hood", "coif", "med_helm"]:
			mb.add_blob(Vector3(side * 0.107, 0.112, 0.005), Vector3(0.019, 0.030, 0.023), 2, 5, skin.darkened(0.04))
	# A quieter, slightly lifted mouth replaces the rigid horizontal lip block.
	var lip: Color = skin.darkened(0.25)
	_face_detail(mb, Vector2(-0.023, 0.069), Vector2(0, 0.066),
		Vector2(0, 0.070), Vector2(-0.023, 0.072), lip, 0.0015)
	_face_detail(mb, Vector2(0, 0.066), Vector2(0.023, 0.069),
		Vector2(0.023, 0.072), Vector2(0, 0.070), lip, 0.0015)
	if outfit.get("beard", false):
		PawnEquipment.panel(mb, [Vector2(-0.072, 0.093), Vector2(-0.065, -0.015), Vector2(0, -0.105), Vector2(0.066, -0.015), Vector2(0.072, 0.093)], 0.105, 0.039, BEARD)
		mb.add_limb(Vector3(-0.035, 0.05, 0.15), Vector3(0, -0.072, 0.149), 0.017, 0.006, 4, BEARD.lightened(0.15))
	elif not outfit.get("ordinary", false) and style % 4 == 0 and gear != "coif":
		mb.add_box(Vector3(-0.072, 0.035, 0.084), Vector3(0.144, 0.06, 0.029), hair)

	match gear:
		"med_helm":
			# An open helm: a cap down to the brow, and a nose guard.
			_chamfered_head(mb, 0.169, 0.23, 0.12, 0.111, gear_colour)
			mb.add_blob(Vector3(0, 0.22, 0), Vector3(0.125, 0.068, 0.115), 3, 8, gear_colour)
			# The front opening is below the cap; side cheeks protect the jaw.
			for side in [-1.0, 1.0]:
				mb.add_box(Vector3(side * 0.105 - 0.019, 0.02, 0.016), Vector3(0.038, 0.13, 0.074), gear_colour.darkened(0.1))
			mb.add_box(Vector3(-0.012, 0.09, 0.105), Vector3(0.024, HEAD_H * 0.6 - 0.07, 0.014), gear_colour.darkened(0.15))
		"coif":
			# A rounded crown and flared hanging mail, with the front left open.
			# The circular shell must enclose the cheek corners as well as the
			# axes; an inscribed shell lets skin poke through its diagonal facets.
			mb.add_blob(Vector3(0, 0.194, -0.004), Vector3(0.15, 0.11, 0.14), 4, 8, gear_colour)
			for i in range(8):
				if i == 1 or i == 2:
					continue
				var a: float = TAU * i / 8.0
				var b: float = TAU * (i + 1) / 8.0
				mb.add_quad(Vector3(cos(a) * 0.15, -0.014, sin(a) * 0.14),
					Vector3(cos(a) * 0.15, 0.194, sin(a) * 0.14),
					Vector3(cos(b) * 0.15, 0.194, sin(b) * 0.14),
					Vector3(cos(b) * 0.15, -0.014, sin(b) * 0.14), gear_colour.darkened(0.1 if i % 2 == 0 else 0.02))
			for side in [-1.0, 1.0]:
				mb.add_limb(Vector3(side * 0.106, 0.175, 0.099), Vector3(side * 0.106, 0.007, 0.099), 0.009, 0.011, 4, gear_colour.lightened(0.18))
		"hood":
			# An open, peaked hood: the face is a real opening, not a painted box.
			mb.add_box(Vector3(-0.11, 0.0, -0.12), Vector3(0.22, 0.21, 0.055), gear_colour.darkened(0.18))
			for side in [-1.0, 1.0]:
				PawnEquipment.panel(mb, [Vector2(side * 0.112 - 0.025, 0.20), Vector2(side * 0.10 - 0.035, 0.005), Vector2(side * 0.10 + 0.035, 0.005), Vector2(side * 0.112 + 0.025, 0.20)], -0.08, 0.205, gear_colour)
			mb.add_limb(Vector3(-0.126, 0.193, 0.107), Vector3(0, 0.285, 0.104), 0.039, 0.034, 4, gear_colour.lightened(0.07))
			mb.add_limb(Vector3(0, 0.285, 0.104), Vector3(0.126, 0.193, 0.107), 0.034, 0.039, 4, gear_colour)
			mb.add_tri(Vector3(-0.135, 0.20, -0.12), Vector3(-0.135, 0.20, 0.11), Vector3(0, 0.283, 0.11), gear_colour)
			mb.add_tri(Vector3(0.135, 0.20, -0.12), Vector3(0, 0.283, 0.11), Vector3(0.135, 0.20, 0.11), gear_colour.lightened(0.06))
			mb.add_tri(Vector3(-0.135, 0.20, -0.12), Vector3(0, 0.283, 0.11), Vector3(0.135, 0.20, -0.12), gear_colour.darkened(0.06))
		"wizard_hat":
			PawnEquipment.pointed_hat(mb, HAT_BRIM_Y + 0.004, gear_colour, outfit.get("edge", BRASS))
		"circlet":
			mb.add_box(Vector3(-0.092, 0.185, 0.106), Vector3(0.184, 0.022, 0.013), outfit["edge"])
			PawnEquipment.panel(mb, [Vector2(0, 0.229), Vector2(-0.021, 0.197), Vector2(0, 0.173), Vector2(0.021, 0.197)], 0.121, 0.012, outfit["jewel"])
		"feather_hat":
			mb.add_cylinder(Vector3(0, HAT_BRIM_Y + 0.004, 0), 0.19, 0.175, 0.022, 7, gear_colour)
			PawnEquipment.cap(mb, Vector3(0, HAT_BRIM_Y + 0.004, 0), Vector3.DOWN, 0.19, 7, gear_colour.darkened(0.25))
			mb.add_cylinder(Vector3(0, HAT_BRIM_Y + 0.026, 0), 0.115, 0.087, 0.09, 7, gear_colour.lightened(0.08))
			mb.add_cylinder(Vector3(0, HAT_BRIM_Y + 0.026, 0), 0.118, 0.113, 0.029, 7, outfit["body"])
			PawnEquipment.panel(mb, [Vector2(0.09, HAT_BRIM_Y + 0.041), Vector2(0.15, HAT_BRIM_Y + 0.051), Vector2(0.235, HAT_BRIM_Y + 0.201), Vector2(0.16, HAT_BRIM_Y + 0.156)], -0.005, 0.014, UNIFORM_SHIRT)
		"felt_hat":
			# A modest road hat, with an irregular eight-sided brim and leather
			# band. No silhouette borrowed from a named outside game's item.
			mb.add_cylinder(Vector3(0, HAT_BRIM_Y, 0), 0.167, 0.156, 0.021, 8, gear_colour.darkened(0.12))
			PawnEquipment.cap(mb, Vector3(0, HAT_BRIM_Y, 0), Vector3.DOWN, 0.167, 8, gear_colour.darkened(0.24))
			mb.add_cylinder(Vector3(0, HAT_BRIM_Y + 0.021, -0.006), 0.115, 0.091, 0.074, 8, gear_colour)
			mb.add_cylinder(Vector3(0, HAT_BRIM_Y + 0.022, -0.006), 0.117, 0.112, 0.024, 8, BELT)
			mb.add_box(Vector3(0.072, HAT_BRIM_Y + 0.028, 0.077), Vector3(0.025, 0.018, 0.008), BRASS)
		"party_hat":
			# A paper crown: a band and a ring of points.
			mb.add_cylinder(Vector3(0.0, HAT_BRIM_Y + 0.004, 0.0), 0.1, 0.1, 0.035, 8, gear_colour)
			for i in range(5):
				var a: float = TAU * float(i) / 5.0
				mb.add_cone(Vector3(cos(a) * 0.07, HAT_BRIM_Y + 0.039, sin(a) * 0.07), 0.035, 0.08, 4, gear_colour)
	return mb.commit()


## Jaw, cheek and forehead planes give the face a silhouette without adding a
## noisy triangulated skin texture. Each broad side retains one flat normal.
static func _face_planes(mb: MeshBuilder, skin: Color) -> void:
	var corners: Array[Vector2] = [Vector2(-0.65, -1), Vector2(-1, -0.65),
		Vector2(-1, 0.65), Vector2(-0.65, 1), Vector2(0.65, 1),
		Vector2(1, 0.65), Vector2(1, -0.65), Vector2(0.65, -1)]
	var levels: Array[float] = FACE_LEVELS
	var radii: Array[Vector2] = FACE_RADII
	for ring in range(levels.size() - 1):
		for i in range(8):
			var j: int = (i + 1) % 8
			var a := Vector3(corners[i].x * radii[ring].x, levels[ring], corners[i].y * radii[ring].y)
			var b := Vector3(corners[j].x * radii[ring].x, levels[ring], corners[j].y * radii[ring].y)
			var c := Vector3(corners[j].x * radii[ring + 1].x, levels[ring + 1], corners[j].y * radii[ring + 1].y)
			var d := Vector3(corners[i].x * radii[ring + 1].x, levels[ring + 1], corners[i].y * radii[ring + 1].y)
			mb.add_quad(a, b, c, d, skin.darkened(0.015) if ring == 0 else skin)
			if ring == 0:
				mb.add_tri(Vector3(0, levels[0], 0), b, a, skin.darkened(0.08))
			if ring == levels.size() - 2:
				mb.add_tri(Vector3(0, levels[-1], 0), d, c, skin)


## Facial ink follows the skin slope rather than floating on a flat box front.
## The normal-area guard stays enabled, with a cutoff suitable for tiny pupils.
static func _face_detail(mb: MeshBuilder, a: Vector2, b: Vector2, c: Vector2, d: Vector2, colour: Color, lift: float) -> void:
	mb.add_quad(_face_point(a, lift), _face_point(b, lift), _face_point(c, lift), _face_point(d, lift), colour, 0.000000000001)


static func _face_point(point: Vector2, lift: float) -> Vector3:
	for i in range(FACE_LEVELS.size() - 1):
		if point.y <= FACE_LEVELS[i + 1]:
			var fraction: float = clampf(inverse_lerp(FACE_LEVELS[i], FACE_LEVELS[i + 1], point.y), 0.0, 1.0)
			return Vector3(point.x, point.y, lerpf(FACE_RADII[i].y, FACE_RADII[i + 1].y, fraction) + lift)
	return Vector3(point.x, point.y, FACE_RADII[-1].y + lift)


static func _add_hair(mb: MeshBuilder, hair: Color, style: int, gear: String, tie: Color) -> void:
	var covered: bool = gear in ["felt_hat", "feather_hat", "wizard_hat", "party_hat"]
	var crop: bool = style == 3
	var centre_y: float = 0.165 if covered or crop else 0.177
	var crown_h: float = 0.061 if covered or crop else 0.074
	mb.add_blob(Vector3(0, centre_y, -0.015), Vector3(0.117, crown_h, 0.108), 2 if crop else 3, 8, hair)
	# The nape narrows toward the neck instead of ending as a rectangular slab.
	# Keep it closed and inside the crown so turning or wearing a hat stays tidy.
	var nape_y: float = 0.09 if crop else 0.078
	_tapered_box(mb, nape_y, nape_y + (0.083 if crop else 0.11),
		Vector2(0.064, 0.014), Vector2(0.089, 0.015), hair.darkened(0.04), Vector2(0, -0.096))
	if covered:
		# Hair fits below the hat crown; two fringe planes remain visible.
		_hair_tuft(mb, Vector3(-0.096, 0.198, 0.03), Vector3(-0.01, 0.20, 0.055),
			Vector3(-0.071, 0.153, 0.107), Vector3(-0.052, 0.226, 0.064), hair)
		_hair_tuft(mb, Vector3(-0.014, 0.20, 0.055), Vector3(0.09, 0.195, 0.038),
			Vector3(0.038, 0.16, 0.106), Vector3(0.04, 0.224, 0.063), hair.lightened(0.025))
	elif style == 0:
		# Three broader locks follow the crown instead of forming a spiky row.
		for i in range(3):
			var x: float = -0.095 + float(i) * 0.060
			_hair_tuft(mb, Vector3(x, 0.216, 0.042), Vector3(x + 0.070, 0.219, 0.038),
				Vector3(x + 0.023, 0.160 + float(i % 2) * 0.010, 0.108),
				Vector3(x + 0.042, 0.244 + (0.005 if i == 1 else 0.0), 0.066), hair.lightened(0.025 if i % 2 == 0 else 0.0))
	elif style == 1:
		# A swept, wider forelock breaks symmetry without adding loose motion.
		_hair_tuft(mb, Vector3(-0.106, 0.194, 0.015), Vector3(0.055, 0.22, 0.018),
			Vector3(-0.064, 0.150, 0.109), Vector3(-0.022, 0.260, 0.060), hair)
		_hair_tuft(mb, Vector3(-0.002, 0.214, 0.019), Vector3(0.112, 0.193, 0.01),
			Vector3(0.061, 0.159, 0.104), Vector3(0.060, 0.247, 0.044), hair.lightened(0.045))
		_hair_tuft(mb, Vector3(-0.10, 0.15, -0.06), Vector3(-0.085, 0.21, 0.045),
			Vector3(-0.103, 0.103, 0.037), Vector3(-0.113, 0.17, -0.006), hair.darkened(0.06))
	elif style == 2:
		# A tied style clears the brow and is immediately different from behind.
		for side in [-1.0, 1.0]:
			_hair_tuft(mb, Vector3(side * 0.10, 0.208, -0.028), Vector3(side * 0.033, 0.224, 0.04),
				Vector3(side * 0.104, 0.114, 0.04), Vector3(side * 0.085, 0.246, 0.052), hair)
	else:
		_tapered_box(mb, 0.184, 0.203, Vector2(0.071, 0.014), Vector2(0.064, 0.010), hair, Vector2(0, 0.078))
	if style == 2:
		mb.add_blob(Vector3(0.01, 0.122, -0.135), Vector3(0.044, 0.044, 0.030), 2, 6, hair)
		mb.add_limb(Vector3(0.01, 0.105, -0.15), Vector3(0.028, -0.03, -0.16), 0.031, 0.013, 6, hair)
		mb.add_box(Vector3(-0.02, 0.094, -0.172), Vector3(0.060, 0.014, 0.038), tie)


## Four closed facets, with winding determined from the interior point. Hair
## locks stay solid from behind and retain correct outward lighting normals.
static func _hair_tuft(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var centre: Vector3 = (a + b + c + d) * 0.25
	for face in [[a, b, c], [a, d, b], [b, d, c], [c, d, a]]:
		var p: Vector3 = face[0]
		var q: Vector3 = face[1]
		var r: Vector3 = face[2]
		if (q - p).cross(r - p).dot(centre - p) > 0.0:
			mb.add_tri(p, r, q, col)
		else:
			mb.add_tri(p, q, r, col)


static func _arm_mesh(sleeve: Color, cuff: Color, hand: Color, outfit: Dictionary, thumb_side: float = -1.0) -> ArrayMesh:
	var mb := MeshBuilder.new()
	if outfit.get("ordinary", false):
		KeeperWardrobeArt.arm(mb, ARM_H, outfit, thumb_side)
		return mb.commit()
	if int(outfit["look"]) == Look.WARRIOR:
		_tapered_box(mb, -ARM_H * 0.65, 0.006, Vector2(0.047, 0.051), Vector2(0.064, 0.064), sleeve)
	else:
		# The upper cap slopes into the torso; a sleeve no longer ends as a
		# horizontal rectangular shoulder. It still swings on the same bone.
		_tapered_box(mb, -ARM_H * 0.65, -0.027, Vector2(0.047, 0.051), Vector2(0.060, 0.061), sleeve)
		_tapered_box(mb, -0.027, 0.001, Vector2(0.060, 0.061), Vector2(0.050, 0.054), sleeve)
	# Cuffs follow the sleeve facets rather than reading as wide square bricks.
	_tapered_box(mb, -ARM_H * 0.72, -ARM_H * 0.62, Vector2(0.050, 0.054), Vector2(0.052, 0.057), cuff)
	_tapered_box(mb, -ARM_H * 0.86, -ARM_H * 0.70, Vector2(0.036, 0.040), Vector2(0.043, 0.047), hand)
	_tapered_box(mb, -ARM_H, -ARM_H * 0.86, Vector2(0.041, 0.039), Vector2(0.039, 0.038), hand)
	# A small thumb wedge gives an actual hand silhouette with no finger bones.
	_hair_tuft(mb, Vector3(thumb_side * 0.037, -ARM_H * 0.86, 0.023), Vector3(thumb_side * 0.037, -ARM_H * 0.96, 0.029),
		Vector3(thumb_side * 0.069, -ARM_H * 0.91, 0.041), Vector3(thumb_side * 0.034, -ARM_H * 0.90, 0.049), hand.darkened(0.025))
	if int(outfit["look"]) == Look.WARRIOR:
		# Armour follows the shoulder bone, never the torso bob.
		mb.add_blob(Vector3(0, -0.024, 0), Vector3(0.104, 0.092, 0.097), 3, 6, sleeve.lightened(0.12))
		_tapered_box(mb, -0.12, -0.067, Vector2(0.082, 0.079), Vector2(0.09, 0.082), sleeve.darkened(0.12))
		mb.add_box(Vector3(-0.055, -0.23, 0.056), Vector3(0.11, 0.075, 0.019), sleeve.lightened(0.2))
	return mb.commit()


static func _leg_mesh(trouser: Color, boot: Color, outfit: Dictionary) -> ArrayMesh:
	var mb := MeshBuilder.new()
	if outfit.get("ordinary", false):
		KeeperWardrobeArt.leg(mb, LEG_H, outfit)
		return mb.commit()
	_tapered_box(mb, -LEG_H * 0.67, 0.015, Vector2(0.047, 0.052), Vector2(0.060, 0.065), trouser)
	_tapered_box(mb, -LEG_H + 0.025, -LEG_H + LEG_H * 0.42,
		Vector2(0.052, 0.055), Vector2(0.059, 0.060), boot)
	# A fitted, bevelled toe and thin sole retain the readable foot direction
	# without the old rectangular platform-shoe silhouette.
	_tapered_box(mb, -LEG_H + 0.016, -LEG_H + 0.070, Vector2(0.056, 0.086),
		Vector2(0.050, 0.071), boot.lightened(0.05), Vector2(0, 0.023))
	_tapered_box(mb, -LEG_H, -LEG_H + 0.018, Vector2(0.058, 0.088),
		Vector2(0.058, 0.088), boot.darkened(0.16), Vector2(0, 0.023))
	if int(outfit["look"]) == Look.WARRIOR:
		mb.add_blob(Vector3(0, -0.20, 0.064), Vector3(0.068, 0.062, 0.036), 2, 6, trouser.lightened(0.20))
		PawnEquipment.panel(mb, [Vector2(-0.041, -0.24), Vector2(-0.043, -0.355), Vector2(0.043, -0.355), Vector2(0.041, -0.24)], 0.068, 0.015, trouser)
	elif int(outfit["look"]) != Look.STAFF:
		mb.add_box(Vector3(-0.058, -LEG_H * 0.67, -0.061), Vector3(0.116, 0.020, 0.126), boot.lightened(0.12))
	return mb.commit()


static func _tapered_box(mb: MeshBuilder, bottom: float, top: float, lower: Vector2, upper: Vector2, col: Color, offset: Vector2 = Vector2.ZERO) -> void:
	# Broad planes and clipped corners look carved, without rounded smooth
	# normals. The older four-sided limbs read as square toy blocks close up.
	var corners: Array[Vector2] = [Vector2(-0.65, -1), Vector2(-1, -0.65), Vector2(-1, 0.65), Vector2(-0.65, 1), Vector2(0.65, 1), Vector2(1, 0.65), Vector2(1, -0.65), Vector2(0.65, -1)]
	for i in range(8):
		var j: int = (i + 1) % 8
		var a := Vector3(corners[i].x * lower.x + offset.x, bottom, corners[i].y * lower.y + offset.y)
		var b := Vector3(corners[j].x * lower.x + offset.x, bottom, corners[j].y * lower.y + offset.y)
		var c := Vector3(corners[j].x * upper.x + offset.x, top, corners[j].y * upper.y + offset.y)
		var d := Vector3(corners[i].x * upper.x + offset.x, top, corners[i].y * upper.y + offset.y)
		mb.add_quad(a, b, c, d, col.darkened(0.055) if i % 2 == 0 else col)
		mb.add_tri(Vector3(offset.x, top, offset.y), d, c, col.lightened(0.04))
		mb.add_tri(Vector3(offset.x, bottom, offset.y), b, a, col.darkened(0.12))


static func _chamfered_head(mb: MeshBuilder, bottom: float, top: float, width: float, depth: float, col: Color) -> void:
	var bevel: float = 0.033
	var corners: Array[Vector2] = [
		Vector2(-width + bevel, -depth), Vector2(-width, -depth + bevel),
		Vector2(-width, depth - bevel), Vector2(-width + bevel, depth),
		Vector2(width - bevel, depth), Vector2(width, depth - bevel),
		Vector2(width, -depth + bevel), Vector2(width - bevel, -depth),
	]
	for i in range(corners.size()):
		var next: int = (i + 1) % corners.size()
		var a := Vector3(corners[i].x, bottom, corners[i].y)
		var b := Vector3(corners[next].x, bottom, corners[next].y)
		var c := Vector3(corners[next].x, top, corners[next].y)
		var d := Vector3(corners[i].x, top, corners[i].y)
		mb.add_quad(a, b, c, d, col)
		mb.add_tri(Vector3(0.0, top, 0.0), d, c, col)
		mb.add_tri(Vector3(0.0, bottom, 0.0), b, a, col)


## A faint outline for telling staff from guests at a glance: the body drawn
## again a little larger, inside out, in one flat colour -- so only a thin rim
## of it shows round the edge. Gold for staff, blue for guests.
const OUTLINE_STAFF := Color(1.0, 0.78, 0.25, 0.55)
const OUTLINE_GUEST := Color(0.4, 0.75, 1.0, 0.5)
const OUTLINE_WIDTH: float = 0.032
static var _outlines: Dictionary = {}


static func outline_material(is_customer: bool) -> ShaderMaterial:
	if _outlines.has(is_customer):
		return _outlines[is_customer]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 rim : source_color = vec4(1.0);
uniform float width = 0.02;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = rim.rgb;
	ALPHA = rim.a;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("rim", OUTLINE_GUEST if is_customer else OUTLINE_STAFF)
	material.set_shader_parameter("width", OUTLINE_WIDTH)
	_outlines[is_customer] = material
	return material
