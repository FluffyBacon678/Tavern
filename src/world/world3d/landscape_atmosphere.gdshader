shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform float fx_time = 0.0;
uniform float rain = 0.0;
uniform float wind = 0.0;
uniform float cloud = 0.0;
uniform bool foliage = false;
uniform sampler2D shelter_mask : filter_nearest, repeat_disable;
uniform float map_size = 96.0;
varying vec3 world_position;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (foliage) {
		float crown = smoothstep(0.8, 3.0, VERTEX.y);
		float gust = sin(fx_time * 1.7 + origin.x * 0.3 + origin.z * 0.21);
		VERTEX.x += crown * gust * (0.025 + wind * 0.075);
		VERTEX.z += crown * sin(fx_time * 1.3 + origin.x * 0.23) * wind * 0.045;
	}
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float sheltered = texture(shelter_mask, world_position.xz / map_size).r;
	float damp = rain * (1.0 - sheltered);
	float passing_cloud = sin(world_position.x * 0.13 + fx_time * 0.035) * sin(world_position.z * 0.11 - fx_time * 0.02);
	ALBEDO = COLOR.rgb * (1.0 - damp * 0.16) * (1.0 - cloud * (0.04 + 0.035 * passing_cloud));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
