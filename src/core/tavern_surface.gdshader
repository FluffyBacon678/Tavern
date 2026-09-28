shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Greyscale detail is data, not albedo: the original palette supplies colour.
uniform sampler2D detail_atlas : filter_linear_mipmap, repeat_disable;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.52;

void fragment() {
	float style = clamp(floor(UV2.x + 0.5), 0.0, 7.0);
	vec2 cell = vec2(mod(style, 4.0), floor(style / 4.0));
	// Inset the sample so filtered atlas neighbours cannot tint a surface.
	vec2 atlas_uv = (cell * 128.0 + vec2(3.0) + fract(UV) * 122.0) / vec2(512.0, 256.0);
	float detail = texture(detail_atlas, atlas_uv).r - (128.0 / 255.0);
	ALBEDO = COLOR.rgb * (1.0 + detail * detail_strength);
	ROUGHNESS = 0.94;
	SPECULAR = 0.0;
}
