shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float fx_time = 0.0;
uniform float wind = 0.0;
varying float life;

void vertex() {
	life = fract(INSTANCE_CUSTOM.x + fx_time * 0.16);
	vec2 puff = VERTEX.xy * (0.45 + life * 1.7);
	vec3 centre = MODEL_MATRIX[3].xyz + vec3(life * life * (0.35 + wind * 1.1), life * 2.4, 0.0);
	vec3 position = centre + INV_VIEW_MATRIX[0].xyz * puff.x + INV_VIEW_MATRIX[1].xyz * puff.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(position, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float puff = 1.0 - smoothstep(0.3, 1.0, dot(p, p));
	ALBEDO = vec3(0.39, 0.40, 0.38);
	ALPHA = puff * sin(life * 3.14159) * 0.19;
}
