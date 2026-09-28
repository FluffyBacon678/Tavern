extends Node

## Guard the cosmetic seam: art must not change simulation RNG or undo batching.
func _ready() -> void:
	if not OS.is_debug_build() or not GameState.begin_test_session():
		get_tree().quit(2)
		return
	var rng_ok := true
	var mesh_ok := true
	var bounds_ok := true
	var uniform_ok := true
	var deterministic_ok := true
	var styles: Dictionary = {}
	var appearances: Dictionary = {}
	var signatures: Dictionary = {}
	var max_triangles := 0
	var material := StandardMaterial3D.new()
	for customer in [false, true]:
		for value in range(4096 if customer else 256):
			var rng := RandomNumberGenerator.new()
			rng.seed = value
			var expected := RandomNumberGenerator.new()
			expected.seed = value
			var look_index: int = expected.randi_range(0, 7 if customer else 5)
			var skin_index: int = expected.randi_range(0, 3)
			if customer:
				var style: int = look_index + skin_index * 8
				var key: int = style * 4 + PawnWardrobe.variant_for_state(expected.state)
				if appearances.has(key):
					continue
				styles[style] = true
				appearances[key] = true
			var uniform := Color("186ead") if not customer and value % 2 == 0 else Color(0, 0, 0, 0)
			var rig: PawnMesh.Rig = PawnMesh.build(rng, material, customer, uniform)
			rng_ok = rng_ok and rng.state == expected.state
			var instances: Array[Node] = rig.root.find_children("*", "MeshInstance3D", true, false)
			mesh_ok = mesh_ok and instances.size() == 1 and rig.skeleton.get_bone_count() == 6
			var mesh: Mesh = (instances[0] as MeshInstance3D).mesh
			mesh_ok = mesh_ok and mesh.get_surface_count() == 1
			var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var colours: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			if uniform.a > 0:
				uniform_ok = uniform_ok and colours.has(uniform)
			if customer:
				signatures[hash([vertices, colours])] = true
				rng.seed = value
				var replay: PawnMesh.Rig = PawnMesh.build(rng, material, true)
				var replay_node: MeshInstance3D = replay.root.find_children("*", "MeshInstance3D", true, false)[0]
				var replay_arrays: Array = replay_node.mesh.surface_get_arrays(0)
				deterministic_ok = deterministic_ok and vertices == replay_arrays[Mesh.ARRAY_VERTEX] and colours == replay_arrays[Mesh.ARRAY_COLOR]
				replay.root.free()
			max_triangles = maxi(max_triangles, vertices.size() / 3)
			for vertex in vertices:
				bounds_ok = bounds_ok and vertex.is_finite() and vertex.y >= -0.001 and vertex.y < 1.6 and absf(vertex.x) < 0.5 and absf(vertex.z) < 0.5
			rig.root.free()
	var checks: Dictionary = {
		"all 32 customer styles covered": styles.size() == 32,
		"all 128 style/variant combinations reached through production seeds": appearances.size() == 128,
		"128 distinct rendered colour/geometry signatures": signatures.size() == 128,
		"rebuilding the same customer seed reproduces its appearance": deterministic_ok,
		"appearance preserves the original two RNG draws": rng_ok,
		"every character remains one surface and six bones": mesh_ok,
		"staff role colours survive the character art build": uniform_ok,
		"all vertices finite and kit stays within a walking pawn's envelope": bounds_ok,
		"largest character stays below 1400 triangles (%d measured)" % max_triangles: max_triangles < 1400,
	}
	var failures := 0
	for message in checks:
		TestOutput.check_line(checks[message], message)
		if not checks[message]:
			failures += 1
	print("ADVENTURER MESH SMOKE: %d failure(s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
