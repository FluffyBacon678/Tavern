shader_type canvas_item;

// Draws every tree in the forest from one atlas in a single MultiMesh draw call.
// Per-instance data carries which atlas slice to sample and a per-tree phase so
// the canopy sway is desynchronised across the forest.
//
// Both channels are kept normalised to 0..1 rather than carrying raw values.
// MultiMesh custom data travels as a colour, and not every backend promises to
// preserve components outside 0..1, so nothing here relies on that.
//
// INSTANCE_CUSTOM.r = atlas slice as a UV offset (variant / atlas_slices)
// INSTANCE_CUSTOM.g = sway phase, 0..1 of a full cycle

const float TWO_PI = 6.28318530718;

uniform float atlas_slices = 18.0;
uniform float sway_amplitude = 4.0;
uniform float sway_speed = 0.5;
// Mesh-space height of one tree quad. The quad origin sits at the trunk base,
// so vertex Y runs from -tile_height (crown) to 0 (ground).
uniform float tile_height = 72.0;

void vertex() {
	float uv_offset = INSTANCE_CUSTOM.r;
	float phase = INSTANCE_CUSTOM.g * TWO_PI;

	// Height above the base, 0 at the trunk and 1 at the crown. Squaring it
	// keeps the trunk planted and concentrates the motion in the foliage.
	float up = clamp(-VERTEX.y / tile_height, 0.0, 1.0);
	VERTEX.x += sin(TIME * sway_speed + phase) * sway_amplitude * up * up;

	// Remap the quad UV into this instance slice of the horizontal atlas.
	UV.x = UV.x / atlas_slices + uv_offset;
}
