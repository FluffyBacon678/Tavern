shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;

uniform float fx_time = 0.0;
varying float phase;

void vertex() { phase = INSTANCE_CUSTOM.x * 6.28318; }

void fragment() {
	float height = 1.0 - UV.y;
	float sway = sin(fx_time * 5.2 + height * 6.0 + phase) * 0.07 * height;
	float tongues = sin(UV.x * 24.0 + fx_time * 3.3 + phase) * 0.07;
	float taper = (1.0 - height) * 0.48;
	float flame = 1.0 - smoothstep(taper - 0.08, taper + 0.04, abs(UV.x - 0.5 + sway) + tongues * height);
	float base = smoothstep(0.0, 0.08, height);
	vec3 ember = vec3(1.0, 0.15, 0.025);
	vec3 core = vec3(1.0, 0.82, 0.25);
	ALBEDO = mix(core, ember, smoothstep(0.15, 0.90, height));
	ALPHA = flame * base * (1.0 - smoothstep(0.80, 1.0, height)) * 0.9;
}
