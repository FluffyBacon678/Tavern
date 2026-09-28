class_name WorldLanterns
extends Node3D

## Small automatic wall fixtures are presentation of completed rooms, not
## inventory or a new building. Hide fixtures on lowered cutaway walls.
const MAX_VISIBLE := 4
var material := ShaderMaterial.new()
var fixtures: MultiMeshInstance3D
var _candidates: Array[Dictionary] = []


func _ready() -> void:
	material.shader = preload("res://src/world/world3d/lantern_glass.gdshader")
	var mb := MeshBuilder.new()
	var iron := Color(0.18, 0.16, 0.13, 0.0)
	mb.add_box(Vector3(-0.085, -0.13, -0.085), Vector3(0.17, 0.25, 0.17), Color("e6ac50"))
	for y in [-0.16, 0.12]:
		mb.add_box(Vector3(-0.12, y, -0.12), Vector3(0.24, 0.035, 0.24), iron)
	for x in [-0.10, 0.08]:
		for z in [-0.10, 0.08]:
			mb.add_box(Vector3(x, -0.14, z), Vector3(0.022, 0.28, 0.022), iron)
	mb.add_cone(Vector3(0, 0.155, 0), 0.17, 0.10, 4, iron)
	mb.add_box(Vector3(-0.025, 0.20, -0.025), Vector3(0.05, 0.10, 0.05), iron)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mb.commit()
	batch.instance_count = MAX_VISIBLE
	batch.visible_instance_count = 0
	fixtures = MultiMeshInstance3D.new()
	fixtures.multimesh = batch
	fixtures.material_override = material
	fixtures.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fixtures)


func rebuild(world: TavernWorld, shelter: Image) -> void:
	_candidates.clear()
	for room in world.rooms.current():
		for tile in room.tiles:
			if shelter.get_pixel(tile.x, tile.y).r < 0.5:
				continue
			for direction in Rooms.NEIGHBOURS:
				var neighbour: Vector2i = tile + direction
				var index: int = world.build.grid.object_index_at(neighbour)
				if not world.build.grid.is_built(index):
					continue
				if world.build.grid.placements[index].def.shape != BuildingDef.Shape.WALL:
					continue
				var at := Vector3(tile.x + 0.5 + direction.x * 0.36, world.terrain.plot_height + 1.05, tile.y + 0.5 + direction.y * 0.36)
				_candidates.append({"at": at, "wall": Vector2(neighbour) + Vector2(0.5, 0.5)})


func update_view(world: TavernWorld, daylight: float) -> Array[Vector3]:
	var chosen: Array[Vector3] = []
	var view: Vector2 = Vector2(world.rig.camera.global_position.x - world.rig._focus.x, world.rig.camera.global_position.z - world.rig._focus.z).normalized()
	var focus := Vector2(world.rig._focus.x, world.rig._focus.z)
	for candidate in _candidates:
		if world.cutaway.enabled and (candidate.wall - focus).dot(view) > 0.5:
			continue
		var spaced: bool = true
		for previous in chosen:
			if previous.distance_squared_to(candidate.at) < 14.0:
				spaced = false
		if not spaced:
			continue
		chosen.append(candidate.at)
		if chosen.size() == MAX_VISIBLE:
			break
	fixtures.multimesh.visible_instance_count = chosen.size()
	for i in range(chosen.size()):
		fixtures.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, chosen[i]))
	material.set_shader_parameter("glow", lerpf(1.2, 0.0, daylight))
	return chosen
