shader_type canvas_item;

// Sits between the forest and the menu.
//
// A procedural forest is visually noisy everywhere at once, which is death for
// text contrast. Two terms handle it: a flat scrim that knocks the whole scene
// back so foreground type always has something dark to sit on, and a vignette
// that deepens toward the edges to pull the eye into the centre. Together they
// read as the forest at dusk rather than as a grey sheet over a bright picture.

uniform float base_darkness : hint_range(0.0, 1.0) = 0.40;
uniform float strength : hint_range(0.0, 1.0) = 0.62;
uniform float radius : hint_range(0.1, 1.5) = 0.88;
uniform float softness : hint_range(0.01, 1.0) = 0.70;
uniform vec4 tint : source_color = vec4(0.035, 0.055, 0.035, 1.0);

void fragment() {
	// Deliberately measured in UV space rather than corrected for aspect: the
	// falloff then tracks the shape of the window, staying an even frame around
	// the content on a wide desktop and on a tall phone alike. Correcting for
	// aspect instead crushes the sides on a narrow screen.
	vec2 centred = UV - vec2(0.5);
	float d = length(centred) * 2.0;
	float vig = smoothstep(radius - softness, radius + softness, d);

	float a = clamp(base_darkness + vig * strength, 0.0, 1.0);
	COLOR = vec4(tint.rgb, a);
}
