class_name WorldAtmosphere
extends Node3D

## Visual state only. Lighting, wind and rain read the saved trading clock;
## no gameplay RNG, inventory, pathfinding, weather penalties or save fields.
const RAIN_COUNTS := [350, 800, 1400]
var world: TavernWorld
var sun: DirectionalLight3D
var environment: Environment
var sky: ShaderMaterial
var state: Dictionary = {}
var effect_time: float = 0.0
var hearths: WorldHearths
var rain_batch: MultiMeshInstance3D
var rain_material := ShaderMaterial.new()
var shelter_image: Image
var shelter_texture: ImageTexture
var _grid: BuildGrid
var _dirty: bool = true
var _quality: int = -1
var _light_time: float = -100.0


func setup(p_world: TavernWorld, p_sun: DirectionalLight3D, p_environment: Environment, p_sky: ShaderMaterial) -> void:
	world = p_world
	sun = p_sun
	environment = p_environment
	sky = p_sky
	world.land_bought.connect(mark_dirty.unbind(2))
	hearths = WorldHearths.new()
	add_child(hearths)
	rain_material.shader = preload("res://src/world/world3d/rain_atmosphere.gdshader")
	shelter_image = Image.create(TavernWorld.MAP_TILES, TavernWorld.MAP_TILES, false, Image.FORMAT_RGBA8)
	shelter_image.fill(Color.BLACK)
	shelter_texture = ImageTexture.create_from_image(shelter_image)
	for material in [rain_material, world._opaque_material, world._forest_material]:
		material.set_shader_parameter("shelter_mask", shelter_texture)
	_make_rain()


func refresh_world() -> void:
	if world.build != null and _grid != world.build.grid:
		_grid = world.build.grid
		_grid.placement_added.connect(mark_dirty.unbind(1))
		_grid.placement_built.connect(mark_dirty.unbind(1))
		_grid.placement_removed.connect(mark_dirty.unbind(2))
	mark_dirty()
	_light_time = -100.0
	refresh()


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if world == null or world.clock == null or _grid == null:
		return
	refresh()


func refresh() -> void:
	if world.clock == null or _grid == null:
		return
	if _dirty:
		_rebuild_shelter()
		hearths.rebuild(world)
		_dirty = false
	state = AtmospherePalette.sample(world._world_seed, world.clock.day, world.clock.fraction)
	effect_time = fposmod(((world.clock.day - 1) + world.clock.fraction) * world.clock.day_length, 4096.0)
	if absf(effect_time - _light_time) >= 0.25:
		_apply_light()
		_light_time = effect_time
	for material in [world._opaque_material, world._forest_material]:
		material.set_shader_parameter("fx_time", effect_time)
		material.set_shader_parameter("rain", state.rain)
		material.set_shader_parameter("wind", state.wind)
		material.set_shader_parameter("cloud", state.cloud)
	world._water_material.set_shader_parameter("fx_time", effect_time)
	world._water_material.set_shader_parameter("rain", state.rain)
	rain_material.set_shader_parameter("fx_time", effect_time)
	rain_material.set_shader_parameter("rain", state.rain)
	rain_batch.visible = state.rain > 0.01
	if world.rig != null:
		rain_batch.position = Vector3(world.rig._focus.x, world.terrain.plot_height, world.rig._focus.z)
	if _quality != GameSettings.quality:
		_quality = GameSettings.quality
		rain_batch.multimesh.visible_instance_count = RAIN_COUNTS[_quality]
	hearths.update_effects(effect_time, state.wind, state.daylight, _quality)


func _apply_light() -> void:
	var daylight: float = state.daylight
	var clouds: float = state.cloud
	var warmth: float = state.warmth
	sun.light_color = Color("8ba5d3").lerp(Color("ffeacb"), daylight).lerp(Color("ffb371"), warmth * 0.65)
	sun.light_energy = lerpf(0.16, 0.95, daylight) * (1.0 - clouds * 0.55)
	sun.shadow_opacity = lerpf(0.35, 0.68, daylight) * (1.0 - clouds * 0.32)
	sun.rotation_degrees = Vector3(-lerpf(24.0, 55.0, daylight), lerpf(-80.0, 25.0, clampf((state.hour - 7.0) / 14.0, 0.0, 1.0)), 0)
	environment.ambient_light_color = Color("a4b4d0").lerp(Color("c5bc9d"), daylight).lerp(Color("acb7bf"), clouds * 0.35)
	# A floor on ambient light preserves management readability after sunset.
	environment.ambient_light_energy = lerpf(0.43, 0.70, daylight) * (1.0 - clouds * 0.10)
	sky.set_shader_parameter("zenith", Color("101c36").lerp(Color("527db1"), daylight).lerp(Color("536b7a"), clouds * 0.65 * daylight))
	sky.set_shader_parameter("horizon", Color("35445e").lerp(Color("b7c4c8"), daylight).lerp(Color("da9d7f"), warmth * 0.65))
	sky.set_shader_parameter("ground", Color("1d2630").lerp(Color("414a33"), daylight))
	sky.set_shader_parameter("celestial_direction", sun.global_basis.z)
	sky.set_shader_parameter("daylight", daylight)
	sky.set_shader_parameter("cloud", clouds)
	sky.set_shader_parameter("fx_time", effect_time)
	environment.fog_light_color = Color("344459").lerp(Color("a5ae8a"), daylight).lerp(Color("788c9c"), clouds * 0.4)
	environment.fog_density = 0.003 + clouds * 0.003 + state.rain * 0.002


func _rebuild_shelter() -> void:
	shelter_image.fill(Color.BLACK)
	for room in world.rooms.current():
		if world.rooms.is_sheltered(room):
			for tile in room["tiles"]:
				shelter_image.set_pixel(tile.x, tile.y, Color.WHITE)
	# Walls/door thresholds also shelter their footprint. Cutaways are only a
	# camera presentation and must never make rain appear inside the building.
	for entry in _grid.placements:
		if entry != null and entry["def"].encloses:
			var tile: Vector2i = entry["origin"]
			if _grid.is_built(_grid.object_index_at(tile)):
				for covered in entry["tiles"]:
					shelter_image.set_pixel(covered.x, covered.y, Color.WHITE)
	shelter_texture.update(shelter_image)


func _make_rain() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.48)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = quad
	batch.instance_count = RAIN_COUNTS[-1]
	# A private fixture seed controls only the presentation's spatial pattern.
	var rng := RandomNumberGenerator.new()
	rng.seed = 94071
	for i in range(batch.instance_count):
		batch.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-22, 22), 0, rng.randf_range(-22, 22))))
		batch.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0, 0))
	rain_batch = MultiMeshInstance3D.new()
	rain_batch.multimesh = batch
	rain_batch.material_override = rain_material
	rain_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_batch.extra_cull_margin = 12.0
	add_child(rain_batch)
