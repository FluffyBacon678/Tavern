shader_type sky;
render_mode disable_fog;

uniform vec3 zenith : source_color = vec3(0.32, 0.49, 0.69);
uniform vec3 horizon : source_color = vec3(0.72, 0.77, 0.78);
uniform vec3 ground : source_color = vec3(0.20, 0.26, 0.20);
uniform vec3 celestial_direction = vec3(0.0, 0.6, 0.8);
uniform float daylight = 1.0;
uniform float cloud = 0.1;
uniform float fx_time = 0.0;

// A bounded hash avoids the large sin-product rounding seams on OpenGL.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	vec3 sky_colour = mix(horizon, zenith, pow(max(direction.y, 0.0), 0.55));
	if (direction.y < 0.0) {
		sky_colour = mix(horizon, ground, smoothstep(0.0, 0.4, -direction.y));
	}
	// Radiance needs the broad palette, not tiny stars or cloud detail. This
	// keeps cubemap refresh cheap while the visible sky keeps its full detail.
	if (!AT_CUBEMAP_PASS && direction.y > 0.0) {
		vec2 field = direction.xz / (direction.y + 0.22) * 3.0 + vec2(fx_time * 0.005, fx_time * 0.0015);
		float billow = noise(field) * 0.62 + noise(field * 2.1) * 0.26 + noise(field * 4.3) * 0.12;
		float cover = smoothstep(0.59 - cloud * 0.36, 0.83 - cloud * 0.36, billow);
		vec3 cloud_colour = mix(vec3(0.12, 0.16, 0.24), vec3(0.83, 0.85, 0.83), daylight) * (1.0 - cloud * 0.23);
		float disc = smoothstep(0.9994, 0.9997, dot(direction, normalize(celestial_direction)));
		float halo = pow(max(dot(direction, normalize(celestial_direction)), 0.0), 180.0) * 0.22;
		vec3 celestial = mix(vec3(0.68, 0.78, 1.0), vec3(1.0, 0.85, 0.56), daylight);
		sky_colour += celestial * (disc + halo) * (1.0 - cover);
		vec2 star_grid = SKY_COORDS * vec2(800.0, 400.0);
		float star = step(0.994, hash(floor(star_grid))) * (1.0 - smoothstep(0.04, 0.22, length(fract(star_grid) - 0.5)));
		sky_colour += vec3(0.70, 0.80, 1.0) * star * (1.0 - daylight) * (1.0 - cover) * smoothstep(0.05, 0.3, direction.y);
		sky_colour = mix(sky_colour, cloud_colour, cover * 0.92);
	}
	COLOR = sky_colour;
}
