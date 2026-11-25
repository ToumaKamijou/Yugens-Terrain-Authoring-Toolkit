shader_type spatial;
render_mode unshaded, depth_test_disabled;

uniform sampler2D curve_texture : source_color;

uniform bool falloff_visible = false;
varying vec2 local_circle_pos;

void vertex() {
	local_circle_pos = VERTEX.xz;
}

void fragment() {
	if (falloff_visible) {
		// CylinderMesh UVs are not centered like a true brush disc, so drive the fade
		// from local XZ radius instead of UVs to keep the gradient locked to the edge.
		float t = 1.0 - clamp(length(local_circle_pos) * 1.82, 0.0, 1.0);
		float sample = texture(curve_texture, vec2(clamp(t, 0.01, 0.99), 0.5)).r;
		ALPHA = clamp(sample, 0.0, 1.0) * 0.6;
	} else {
		ALPHA = 0.25;
	}
}
