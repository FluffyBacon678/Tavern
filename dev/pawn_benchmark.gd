extends Node3D

## Fixed camera, population, poses and lighting isolate pawn rendering cost.
func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().quit(1)
		return
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(8, 10, 14)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(25, 25)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(15):
		var rig := PawnMesh.build(rng, material, i >= 5)
		add_child(rig.root)
		rig.root.position = Vector3((i % 5 - 2) * 1.5, 0, (i / 5 - 1) * 2.0)
		rig.leg_l.rotation.x = 0.65
		rig.leg_r.rotation.x = -0.65
		rig.arm_l.rotation.x = -1.15 if i % 2 == 0 else -0.45
		rig.arm_r.rotation.x = -1.15 if i % 2 == 0 else 0.45
		if rig.has_method("sync_pose"):
			rig.call("sync_pose")
	await get_tree().create_timer(2).timeout
	await RenderingServer.frame_post_draw
	print("PAWN_BENCHMARK count=15 draw_calls=%d primitives=%d" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	var args := OS.get_cmdline_user_args()
	get_viewport().get_texture().get_image().save_png(args[0] if not args.is_empty() else "pawn_benchmark.png")
	get_tree().quit()
