class_name WorldHearths
extends Node3D

## Two batched transparent effects, plus at most four unshadowed local lights.
## Hearths follow finished ovens, including rotation/removal and loaded saves.
const MAX_HEARTHS := 8
var flame_material := ShaderMaterial.new()
var smoke_material := ShaderMaterial.new()
var flames: MultiMeshInstance3D
var smoke: MultiMeshInstance3D
var lights: Array[OmniLight3D] = []
var hearth_count: int = 0
var lanterns: WorldLanterns
var _world: TavernWorld
var _fire_positions: Array[Vector3] = []


func _ready() -> void:
	flame_material.shader = preload("res://src/world/world3d/hearth_flame.gdshader")
	smoke_material.shader = preload("res://src/world/world3d/hearth_smoke.gdshader")
	flames = _batch(Vector2(1.03, 0.49), flame_material, MAX_HEARTHS)
	smoke = _batch(Vector2(0.58, 0.58), smoke_material, MAX_HEARTHS * 4)
	lanterns = WorldLanterns.new()
	add_child(lanterns)
	for i in range(4):
		var light := OmniLight3D.new()
		light.light_color = Color("ff9e43")
		light.omni_range = 4.2
		light.omni_attenuation = 1.3
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		lights.append(light)


func rebuild(world: TavernWorld) -> void:
	_world = world
	_fire_positions.clear()
	lanterns.rebuild(world, world.atmosphere.shelter_image)
	var entries: Array = world.build.grid.live_of(&"oven", true)
	hearth_count = mini(entries.size(), MAX_HEARTHS)
	flames.multimesh.visible_instance_count = hearth_count
	smoke.multimesh.visible_instance_count = hearth_count * 4
	for i in range(hearth_count):
		var entry: Dictionary = entries[i]
		var base: Transform3D = world.build._placement_transform(entry["def"], entry["origin"], entry["rotation"])
		flames.multimesh.set_instance_transform(i, base * Transform3D(Basis.IDENTITY, Vector3(1.0, 0.56, 0.975)))
		flames.multimesh.set_instance_custom_data(i, Color(float(i) / MAX_HEARTHS, 0, 0, 0))
		for puff in range(4):
			var index: int = i * 4 + puff
			smoke.multimesh.set_instance_transform(index, base * Transform3D(Basis.IDENTITY, Vector3(1.58, 1.55, 0.34)))
			smoke.multimesh.set_instance_custom_data(index, Color(puff / 4.0 + i * 0.037, 0, 0, 0))
		_fire_positions.append(base * Vector3(1.0, 0.72, 1.12))


func update_effects(time: float, wind: float, daylight: float, quality: int) -> void:
	flame_material.set_shader_parameter("fx_time", time)
	smoke_material.set_shader_parameter("fx_time", time)
	smoke_material.set_shader_parameter("wind", wind)
	smoke.visible = quality != GameSettings.Quality.LOW and hearth_count > 0
	flames.visible = hearth_count > 0
	var cap: int = 2 if quality == GameSettings.Quality.LOW else 4
	var lamp_positions: Array[Vector3] = lanterns.update_view(_world, daylight)
	var fire_lights: int = mini(hearth_count, cap if daylight > 0.8 or lamp_positions.is_empty() else maxi(1, cap / 2))
	for i in range(lights.size()):
		var lamp: int = i - fire_lights
		var use_lamp: bool = lamp >= 0 and lamp < lamp_positions.size() and daylight < 0.8
		lights[i].visible = i < cap and (i < fire_lights or use_lamp)
		if i < fire_lights:
			lights[i].position = _fire_positions[i]
			lights[i].omni_range = 4.2
			lights[i].light_energy = lerpf(1.6, 0.65, daylight) * (0.94 + 0.045 * sin(time * 7.1 + i) + 0.025 * sin(time * 11.3))
		elif use_lamp:
			lights[i].position = lamp_positions[lamp] + Vector3(0, 0.12, 0)
			lights[i].omni_range = 6.0
			lights[i].light_energy = (1.0 - smoothstep(0.0, 0.8, daylight)) * 1.35


func _batch(size: Vector2, material: Material, count: int) -> MultiMeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = mesh
	batch.instance_count = count
	batch.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = batch
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 4.0
	add_child(instance)
	return instance
