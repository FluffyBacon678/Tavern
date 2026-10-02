shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float fx_time = 0.0;
uniform float rain = 0.0;
uniform sampler2D ground_height : filter_linear, repeat_disable;
uniform vec2 height_size = vec2(97.0);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(vec3(cos(world_position.x * 4.0 - fx_time * 1.4) * 0.07, 1.0, cos(world_position.z * 6.0 + fx_time) * 0.04));
}

void fragment() {
	float depth = world_position.y - texture(ground_height, (world_position.xz + 0.5) / height_size).r;
	if (depth < 0.006) { discard; }
	float bend = sin(world_position.x * 0.73 + world_position.z * 0.48) * 1.4;
	float ripple = sin(world_position.x * 1.1 + world_position.z * 4.4 + bend - fx_time * 1.15);
	float cross_wave = sin(world_position.z * 2.8 - world_position.x * 0.8 + fx_time * 0.6);
	float crests = smoothstep(0.92, 1.0, ripple) * smoothstep(-0.4, 0.7, cross_wave) * 0.19;
	float rainfall = smoothstep(0.84, 1.0, ripple * cross_wave) * rain * 0.10;
	float shore = 1.0 - smoothstep(0.02, 0.25, depth);
	float foam = shore * smoothstep(0.3, 0.85, sin(depth * 45.0 - fx_time * 1.3 + bend)) * 0.22;
	vec3 water_colour = mix(vec3(0.25, 0.40, 0.34), COLOR.rgb * vec3(0.82, 1.03, 1.09), smoothstep(0.0, 0.65, depth));
	ALBEDO = water_colour * (0.96 + ripple * 0.025) + vec3(0.44, 0.53, 0.46) * (crests + rainfall + foam);
	ROUGHNESS = 0.7;
	SPECULAR = 0.0;
	ALPHA = mix(0.35, 0.89, smoothstep(0.0, 0.32, depth));
}
