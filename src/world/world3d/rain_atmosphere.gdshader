shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform float fx_time = 0.0;
uniform float rain = 0.0;
uniform float map_size = 96.0;
uniform sampler2D shelter_mask : filter_nearest, repeat_disable;
varying vec3 world_position;
varying float drop_choice;
varying float edge_fade;

void vertex() {
	float phase = fract(INSTANCE_CUSTOM.x + fx_time * 0.83);
	vec3 centre = MODEL_MATRIX[3].xyz + vec3((1.0 - phase) * 1.1, (1.0 - phase) * 9.0, 0.0);
	// World-vertical drops, with only their width facing the camera.
	world_position = centre + INV_VIEW_MATRIX[0].xyz * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);
	drop_choice = INSTANCE_CUSTOM.y;
	edge_fade = smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.94, 1.0, phase));
}

void fragment() {
	float shelter = texture(shelter_mask, world_position.xz / map_size).r;
	if (shelter > 0.5 || drop_choice > rain || world_position.y < 0.0) { discard; }
	float line = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = vec3(0.62, 0.75, 0.83);
	ALPHA = line * edge_fade * 0.36 * smoothstep(0.0, 0.15, rain);
}
