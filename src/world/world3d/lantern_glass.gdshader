shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform float glow = 0.0;
void fragment() {
	ALBEDO = COLOR.rgb;
	// Vertex alpha is a mask for the glass, never transparency.
	EMISSION = COLOR.rgb * COLOR.a * glow;
	ROUGHNESS = 0.9;
}
