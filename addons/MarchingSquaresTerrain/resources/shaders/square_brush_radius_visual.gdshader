shader_type spatial;
render_mode unshaded, depth_test_disabled;

uniform bool falloff_visible = false;

void fragment() {
	if (falloff_visible) {
		// The square brush visual uses a PlaneMesh, so its UVs are already a centered
		// square domain. Fading from UV center keeps the falloff aligned to the square edge.
		vec2 centered_uv = abs(UV * 2.0 - 1.0);
		float edge_dist = max(centered_uv.x, centered_uv.y);
		float t = 1.0 - clamp(edge_dist, 0.0, 1.0);
		float sample = smoothstep(0.0, 0.85, t);
		ALPHA = sample * 0.6;
	} else {
		ALPHA = 0.25;
	}
}
