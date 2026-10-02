class_name WorldScenery
extends Node3D

## Decorative only: no collision, navigation, inventory or global RNG calls.
## Rebuilt with terrain after buying land, keeping the construction area clear.
const CAPS := [900, 120, 160, 260]
var positions: Array[PackedVector3Array] = []
var batches: Array[MultiMeshInstance3D] = []


func setup(world: TavernWorld) -> void:
	name = "Scenery"
	var rng := RandomNumberGenerator.new()
	rng.seed = world._world_seed + 57291
	for i in range(CAPS.size()):
		positions.append(PackedVector3Array())
	for z in range(1, world.grid.rows - 1):
		for x in range(1, world.grid.cols - 1):
			var tile := Vector2i(x, z)
			if world.plot.grow(1).has_point(tile) or world.grid.cell_at(x, z) == TerrainGrid.Cell.WATER:
				continue
			var road: bool = false
			var shore: bool = false
			for d in TerrainGrid.NEIGHBOURS + [Vector2i.ZERO]:
				road = road or (world.grid.water_flags[world.grid.index(x + d.x, z + d.y)] & TerrainGrid.FLAG_PATH) != 0
				shore = shore or world.grid.cell_at(x + d.x, z + d.y) == TerrainGrid.Cell.WATER
			if road:
				continue
			var roll: float = rng.randf()
			var kind: int = -1
			if shore:
				kind = 3 if roll < 0.48 else (2 if roll < 0.70 else -1)
			elif world.grid.cell_at(x, z) == TerrainGrid.Cell.ROCK:
				kind = 2 if roll < 0.65 else -1
			elif roll < 0.24:
				kind = 0
			elif roll < 0.28:
				kind = 1
			if kind < 0:
				continue
			var wx: float = x + rng.randf_range(0.22, 0.78)
			var wz: float = z + rng.randf_range(0.22, 0.78)
			var height: float = world.terrain.sample_height(wx, wz)
			var minimum_height: float = TerrainMeshBuilder.WATER_LEVEL - 0.5 if kind == 3 else TerrainMeshBuilder.WATER_LEVEL + 0.02
			if height < minimum_height:
				continue
			positions[kind].append(Vector3(wx, height - 0.025, wz))
	for kind in range(CAPS.size()):
		# Shuffle with our private generator so caps thin the whole map rather
		# than deleting all detail from its southern half.
		for i in range(positions[kind].size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var old: Vector3 = positions[kind][i]
			positions[kind][i] = positions[kind][j]
			positions[kind][j] = old
		positions[kind].resize(mini(positions[kind].size(), CAPS[kind]))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Explicit white modulation is required alongside custom data on the
		# tested Compatibility renderer; otherwise these batches render black.
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _mesh(kind)
		mm.instance_count = positions[kind].size()
		for i in range(mm.instance_count):
			var scale: float = rng.randf_range(0.72, 1.25)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, rng.randf_range(0.8, 1.15), scale))
			mm.set_instance_transform(i, Transform3D(basis, positions[kind][i]))
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, Color(1, 0, 0, 0))
		var batch := MultiMeshInstance3D.new()
		batch.name = ["Grass", "Flowers", "Rocks", "Reeds"][kind]
		batch.multimesh = mm
		batch.material_override = world._opaque_material if kind == 2 else world._forest_material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.extra_cull_margin = 0.2
		add_child(batch)
		batches.append(batch)
	GameSettings.quality_changed.connect(apply_quality)
	apply_quality(GameSettings.quality)


func apply_quality(quality: int) -> void:
	var density: float = [0.30, 0.65, 1.0][quality]
	for batch in batches:
		batch.multimesh.visible_instance_count = int(batch.multimesh.instance_count * density)


static func _blade(mb: MeshBuilder, root: Vector3, tip: Vector3, width: float, colour: Color) -> void:
	var left: Vector3 = root - Vector3(width, 0, 0)
	var right: Vector3 = root + Vector3(width, 0, 0)
	mb.add_tri(left, right, tip, colour)
	mb.add_tri(right, left, tip, colour)


static func _mesh(kind: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	match kind:
		0:
			for i in range(4):
				var root := Vector3((i - 1.5) * 0.10, 0, sin(i * 2.5) * 0.11)
				_blade(mb, root, root + Vector3(sin(i) * 0.15, 0.26 + i * 0.04, 0.08), 0.07, Color("7d914c").lerp(Color("9b9c60"), i / 4.0))
		1:
			for i in range(3):
				var root := Vector3(cos(i * 2.1) * 0.16, 0, sin(i * 2.1) * 0.16)
				var top: Vector3 = root + Vector3(0.03, 0.26 + i * 0.07, 0)
				_blade(mb, root, top, 0.018, Color("596d35"))
				var petal: Color = [Color("c9b982"), Color("a59cc3"), Color("d2cbb0")][i]
				for p in range(5):
					var a: float = p * TAU / 5
					mb.add_tri(top, top + Vector3(cos(a + 0.6) * 0.12, 0.018, sin(a + 0.6) * 0.12), top + Vector3(cos(a) * 0.12, 0.018, sin(a) * 0.12), petal)
		2:
			mb.add_blob(Vector3(0, 0.10, 0), Vector3(0.38, 0.25, 0.28), 3, 5, Color("767664"))
			mb.add_cone(Vector3(-0.03, 0.24, 0), 0.19, 0.10, 5, Color("667044"), false)
			mb.add_blob(Vector3(0.28, 0.035, 0.16), Vector3(0.16, 0.10, 0.12), 2, 5, Color("9a917b"))
		3:
			for i in range(3):
				var root := Vector3((i - 1) * 0.17, 0, sin(i * 2.3) * 0.15)
				var top: Vector3 = root + Vector3(0.04, 0.7 + i * 0.12, 0.04)
				_blade(mb, root, top, 0.024, Color("778047"))
				_blade(mb, root, root + Vector3(-0.2, 0.4, 0.1), 0.07, Color("626f3b"))
				mb.add_limb(top - Vector3(0, 0.2, 0), top, 0.045, 0.04, 3, Color("6b4e30"))
	return mb.commit()
