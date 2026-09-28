shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float fx_time = 0.0;
uniform float rain = 0.0;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(vec3(cos(world_position.x * 4.0 - fx_time * 1.4) * 0.07, 1.0, cos(world_position.z * 6.0 + fx_time) * 0.04));
}

void fragment() {
	float ripple = sin(world_position.x * 4.0 + world_position.z * 2.3 - fx_time * 1.4);
	float cross_wave = sin(world_position.z * 8.0 + world_position.x * 1.6 + fx_time * 2.0);
	float crests = smoothstep(0.89, 1.0, ripple) * smoothstep(-0.35, 0.6, cross_wave) * 0.24;
	float rainfall = smoothstep(0.82, 1.0, ripple * cross_wave) * rain * 0.10;
	ALBEDO = COLOR.rgb * (0.91 + ripple * 0.045) + vec3(0.30, 0.42, 0.39) * (crests + rainfall);
	ROUGHNESS = 0.7;
	SPECULAR = 0.0;
	ALPHA = 0.87;
}
