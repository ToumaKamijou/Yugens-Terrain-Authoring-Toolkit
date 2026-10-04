shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_linear_mipmap;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
// The normal-roughness is Forward+ only.
// A workaround is to use the depth buffer (see mst_sample_normal).
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, repeat_disable, filter_linear_mipmap;
#endif
uniform sampler2D rl_noise_texture : hint_default_white, repeat_enable, filter_linear;

group_uniforms Ink;
uniform vec4 ink_color : source_color = vec4(0.055, 0.05, 0.045, 0.92);
uniform float line_opacity : hint_range(0.0, 1.0, 0.01) = 0.9;
uniform float depth_edge_strength : hint_range(0.0, 4.0, 0.01) = 1.35;
uniform float normal_edge_strength : hint_range(0.0, 4.0, 0.01) = 1.15;
uniform float silhouette_strength : hint_range(0.0, 3.0, 0.01) = 0.8;
uniform float silhouette_power : hint_range(0.5, 8.0, 0.01) = 3.3;
uniform float line_wobble : hint_range(0.0, 1.0, 0.01) = 0.18;
group_uniforms;

group_uniforms Hatching;
uniform bool enable_hatching = true;
uniform float shadow_wash_opacity : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float shadow_mid_threshold : hint_range(0.0, 1.0, 0.01) = 0.38;
uniform float shadow_deep_threshold : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float light_face_cleanup : hint_range(0.0, 1.0, 0.01) = 0.92;
uniform float shadow_grouping : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float hatch_opacity : hint_range(0.0, 1.0, 0.01) = 0.31;
uniform float hatch_density : hint_range(1.0, 48.0, 0.1) = 2.4;
uniform float hatch_width : hint_range(0.01, 0.48, 0.01) = 0.07;
uniform float hatch_shadow_threshold : hint_range(0.0, 1.0, 0.01) = 0.56;
uniform float hatch_cross_threshold : hint_range(0.0, 1.0, 0.01) = 0.74;
uniform float hatch_transition_width : hint_range(0.02, 0.4, 0.01) = 0.12;
uniform float hatch_wobble : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float hatch_distance_fade_start = 10.0;
uniform float hatch_distance_fade_end = 24.0;
uniform vec3 hatch_light_direction = vec3(0.35, 0.92, 0.2);
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0;
uniform float tonal_texture_influence : hint_range(0.0, 1.0, 0.01) = 0.85;
uniform float hatch_texture_strength : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float hatch_texture_scale : hint_range(0.01, 1.0, 0.01) = 0.07;
group_uniforms;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float mst_hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float mst_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mst_hash12(i);
	float b = mst_hash12(i + vec2(1.0, 0.0));
	float c = mst_hash12(i + vec2(0.0, 1.0));
	float d = mst_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float mst_sample_depth(vec2 uv) {
	return texture(depth_texture, uv).r;
}

#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
// Angle threshold for line ~30 deg
const float MST_NORMAL_EDGE_MIN = 0.08;
const float MST_NORMAL_EDGE_MAX = 0.42;

vec3 mst_decode_normal(vec3 enc) {
	return normalize(enc * 2.0 - 1.0);
}

vec3 mst_sample_normal(vec2 uv, vec2 pixel, mat4 inv_projection) {
	return mst_decode_normal(texture(normal_roughness_texture, uv).xyz);
}

vec3 mst_center_normal(vec2 uv, vec2 pixel, mat4 inv_projection, vec3 world_normal, mat4 view_matrix) {
	return mst_sample_normal(uv, pixel, inv_projection);
}

float mst_normal_edge_weight(float depth_step) {
	return 1.0;
}
#else
// In reconstructed normals are only valid per facet. Two neighboring facets always result in a hard edge
// (even if they are coplanar). So we need to be more lenient with the edge detection threshold.
const float MST_NORMAL_EDGE_MIN = 0.55;
const float MST_NORMAL_EDGE_MAX = 1.05;

vec3 mst_view_position(vec2 uv, float depth, mat4 inv_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// OpenGL keeps NDC depth in -1..1; the Vulkan-based renderers use 0..1.
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

vec3 mst_sample_normal(vec2 uv, vec2 pixel, mat4 inv_projection) {
	vec2 dx = vec2(pixel.x, 0.0);
	vec2 dy = vec2(0.0, pixel.y);
	float d0 = mst_sample_depth(uv);
	float dxp = mst_sample_depth(uv + dx);
	float dxn = mst_sample_depth(uv - dx);
	float dyp = mst_sample_depth(uv + dy);
	float dyn = mst_sample_depth(uv - dy);
	vec3 p0 = mst_view_position(uv, d0, inv_projection);
	vec3 tangent_x = (abs(dxp - d0) < abs(dxn - d0))
		? mst_view_position(uv + dx, dxp, inv_projection) - p0
		: p0 - mst_view_position(uv - dx, dxn, inv_projection);
	vec3 tangent_y = (abs(dyp - d0) < abs(dyn - d0))
		? mst_view_position(uv + dy, dyp, inv_projection) - p0
		: p0 - mst_view_position(uv - dy, dyn, inv_projection);
	vec3 normal = normalize(cross(tangent_x, tangent_y));

	vec3 to_camera = (abs(inv_projection[2][3]) < 1e-6) ? vec3(0.0, 0.0, 1.0) : normalize(-p0);
	return (dot(normal, to_camera) < 0.0) ? -normal : normal;
}

vec3 mst_center_normal(vec2 uv, vec2 pixel, mat4 inv_projection, vec3 world_normal, mat4 view_matrix) {
	return normalize((view_matrix * vec4(normalize(world_normal), 0.0)).xyz);
}

float mst_normal_edge_weight(float depth_step) {
	return 1.0 - smoothstep(0.0025, 0.015, depth_step);
}
#endif

float mst_hatch_band(float coord, float width) {
	float d = abs(fract(coord) - 0.5);
	return 1.0 - smoothstep(width, width + 0.06, d);
}

float mst_hatch_band_core(float coord, float width) {
	float d = abs(fract(coord) - 0.5);
	return 1.0 - smoothstep(width * 0.28, width * 0.78 + 0.015, d);
}

mat3 mst_surface_basis(vec3 world_normal) {
	vec3 n = normalize(world_normal);
	vec3 up = (abs(n.y) < 0.97) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(up, n));
	vec3 bitangent = normalize(cross(n, tangent));
	return mat3(tangent, bitangent, n);
}

vec2 mst_hatch_surface_uv(vec3 world_pos, vec3 world_normal) {
	mat3 basis = mst_surface_basis(world_normal);
	return vec2(
		dot(world_pos, basis[0]),
		dot(world_pos, basis[1])
	);
}

float mst_wall_factor(vec3 world_normal) {
	float up_dot = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	return 1.0 - smoothstep(wall_threshold, wall_threshold + 0.08, up_dot);
}

bool mst_is_floor(vec3 world_normal) {
	return mst_wall_factor(world_normal) < 0.5;
}

vec2 mst_wall_hatch_uv(vec3 world_pos, vec3 world_normal) {
	vec3 horiz_n = abs(normalize(vec3(world_normal.x, 0.0, world_normal.z) + vec3(0.0001, 0.0, 0.0001)));
	if (horiz_n.x >= horiz_n.z) {
		return vec2(world_pos.z, world_pos.y);
	}
	return vec2(world_pos.x, world_pos.y);
}

float mst_layered_noise(vec2 flow_uv, float scale_a, float scale_b, vec2 offset_a, vec2 offset_b) {
	vec2 noise_uv_a = flow_uv * scale_a + offset_a;
	vec2 noise_uv_b = flow_uv * scale_b + offset_b;
	float tex_noise_a = texture(rl_noise_texture, noise_uv_a).r;
	float tex_noise_b = texture(rl_noise_texture, noise_uv_b).r;
	float tex_grouped_noise = tex_noise_a * 0.68 + tex_noise_b * 0.32;
	float proc_noise_a = mst_noise(flow_uv * scale_a * 0.83 + offset_a * 17.0);
	float proc_noise_b = mst_noise(flow_uv * scale_b * 0.91 - offset_b * 13.0);
	float proc_grouped_noise = proc_noise_a * 0.6 + proc_noise_b * 0.4;
	return mix(proc_grouped_noise, tex_grouped_noise, tonal_texture_influence);
}

float mst_general_hatch_intensity(vec3 world_pos, vec3 world_normal) {
	vec2 flow_uv = mst_hatch_surface_uv(world_pos, world_normal);
	float noise_value = mst_layered_noise(
		flow_uv,
		hatch_texture_scale,
		hatch_texture_scale * 0.53,
		vec2(0.041, 0.217),
		vec2(-0.184, 0.071)
	);
	return mix(1.0 - hatch_texture_strength, 1.0 + hatch_texture_strength, noise_value);
}

float mst_wall_hatch_intensity(vec3 world_pos, vec3 world_normal) {
	vec2 wall_uv = mst_wall_hatch_uv(world_pos, world_normal);
	float noise_value = mst_layered_noise(
		wall_uv,
		hatch_texture_scale * 1.2,
		hatch_texture_scale * 0.61,
		vec2(0.073, 0.211),
		vec2(-0.162, 0.049)
	);
	float breakup = smoothstep(0.18, 0.82, noise_value);
	return mix(0.62, 1.24, breakup);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = 1.0 / VIEWPORT_SIZE;

	float center_depth = mst_sample_depth(uv);
	vec3 center_normal = mst_center_normal(uv, pixel, INV_PROJECTION_MATRIX, v_world_normal, VIEW_MATRIX);

	float wobble_field = (mst_noise(v_world_pos.xz * 0.23 + TIME * 0.03) - 0.5) * line_wobble;
	vec2 wobble_offset = pixel * wobble_field * 1.35;

	vec2 offsets[8] = vec2[](
		vec2(pixel.x, 0.0),
		vec2(-pixel.x, 0.0),
		vec2(0.0, pixel.y),
		vec2(0.0, -pixel.y),
		vec2(pixel.x, pixel.y),
		vec2(-pixel.x, pixel.y),
		vec2(pixel.x, -pixel.y),
		vec2(-pixel.x, -pixel.y)
	);

	float depth_edge = 0.0;
	float normal_edge = 0.0;
	for (int i = 0; i < 8; i++) {
		vec2 sample_uv = uv + offsets[i] + wobble_offset;
		float sample_depth = mst_sample_depth(sample_uv);
		vec3 sample_normal = mst_sample_normal(sample_uv, pixel, INV_PROJECTION_MATRIX);
		float depth_step = abs(sample_depth - center_depth) * depth_edge_strength * 18.0;
		depth_edge = max(depth_edge, depth_step);
		normal_edge = max(normal_edge, length(sample_normal - center_normal) * mst_normal_edge_weight(depth_step));
	}

	depth_edge = smoothstep(0.0025, 0.015, depth_edge);
	normal_edge = smoothstep(MST_NORMAL_EDGE_MIN, MST_NORMAL_EDGE_MAX, normal_edge * normal_edge_strength);

	vec3 world_view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float silhouette_raw = pow(1.0 - abs(dot(normalize(v_world_normal), world_view_dir)), silhouette_power) * silhouette_strength;
	float silhouette = smoothstep(0.72, 1.02, silhouette_raw + wobble_field * 0.06);
	vec3 stable_light_dir = normalize(hatch_light_direction);
	float wall_factor = mst_wall_factor(v_world_normal);
	vec3 wall_normal = normalize(vec3(v_world_normal.x, 0.0, v_world_normal.z) + vec3(0.0001, 0.0, 0.0001));
	vec3 wall_light_dir = normalize(vec3(stable_light_dir.x, 0.0, stable_light_dir.z) + vec3(0.0001, 0.0, 0.0001));
	float light_facing = dot(normalize(v_world_normal), stable_light_dir);
	float wall_light_facing = dot(wall_normal, wall_light_dir);
	light_facing = mix(light_facing, wall_light_facing * 0.45 + 0.15, wall_factor);
	float direct_light = clamp(light_facing, 0.0, 1.0);
	float tonal_shadow = clamp(1.0 - direct_light, 0.0, 1.0);
	float grouped_shadow = mix(tonal_shadow, smoothstep(0.18, 0.9, tonal_shadow), shadow_grouping);
	float wall_shadow_floor = mix(0.52, 0.68, wall_factor);
	grouped_shadow = max(grouped_shadow, wall_shadow_floor * wall_factor);
	float shadow_side_mask = 1.0 - smoothstep(0.34, 0.76, direct_light);
	float light_cleanup_mask = 1.0 - smoothstep(
		1.0 - light_face_cleanup,
		clamp(1.0 - light_face_cleanup + 0.22, 0.0, 1.0),
		direct_light
	);
	shadow_side_mask = mix(shadow_side_mask, 1.0, wall_factor * 0.72);
	light_cleanup_mask = mix(light_cleanup_mask, 1.0, wall_factor * 0.88);
	float shadow_mask = smoothstep(
		hatch_shadow_threshold - hatch_transition_width * 0.6,
		hatch_shadow_threshold + hatch_transition_width * 0.45,
		grouped_shadow
	) * shadow_side_mask * light_cleanup_mask;
	float cross_mask = smoothstep(
		max(hatch_cross_threshold, hatch_shadow_threshold + hatch_transition_width * 0.18),
		1.0,
		grouped_shadow
	) * shadow_side_mask * light_cleanup_mask;
	float shadow_wash = 0.0;
	if (enable_hatching) {
		float mid_wash = smoothstep(
			shadow_mid_threshold - hatch_transition_width,
			shadow_mid_threshold + hatch_transition_width * 0.75,
			grouped_shadow
		);
		float deep_wash = smoothstep(
			shadow_deep_threshold - hatch_transition_width * 0.7,
			shadow_deep_threshold + hatch_transition_width * 0.55,
			grouped_shadow
		);
		shadow_wash = max(mid_wash * 0.55, deep_wash) * shadow_wash_opacity * shadow_side_mask;
	}

	float hatch = 0.0;
	if (enable_hatching) {
		float camera_distance = distance(CAMERA_POSITION_WORLD, v_world_pos);
		float hatch_distance_fade = 1.0 - smoothstep(hatch_distance_fade_start, hatch_distance_fade_end, camera_distance);
		bool is_floor = mst_is_floor(v_world_normal);
		vec2 hatch_uv = is_floor ? mst_hatch_surface_uv(v_world_pos, v_world_normal) : mst_wall_hatch_uv(v_world_pos, v_world_normal);
		float hatch_noise = (mst_noise(hatch_uv * 0.21 + 11.7) - 0.5) * hatch_wobble;
		float tonal_focus = clamp(shadow_mask + cross_mask * 0.55, 0.0, 1.0);
		float hatch_intensity = is_floor ? mst_general_hatch_intensity(v_world_pos, v_world_normal) : mst_wall_hatch_intensity(v_world_pos, v_world_normal);
		float line_breakup_a = 1.0;
		float line_breakup_b = 1.0;
		float hatch_b_weight = 0.82;
		if (!is_floor) {
			float wall_breakup_noise = texture(rl_noise_texture, hatch_uv * (hatch_texture_scale * 1.45) + vec2(0.11, -0.07)).r;
			float wall_breakup_mask = smoothstep(0.22, 0.88, wall_breakup_noise);
			hatch_noise += (wall_breakup_noise - 0.5) * (hatch_wobble * 1.8 + 0.06);
			hatch_intensity *= mix(0.94, 1.16, wall_breakup_mask);
			float wall_line_noise_a = texture(rl_noise_texture, hatch_uv * (hatch_texture_scale * 1.55) + vec2(0.37, 0.19)).r;
			float wall_line_noise_b = texture(rl_noise_texture, hatch_uv * (hatch_texture_scale * 1.48) + vec2(-0.29, 0.41)).r;
			line_breakup_a = mix(0.88, 1.0, smoothstep(0.28, 0.78, wall_line_noise_a));
			line_breakup_b = mix(0.92, 1.0, smoothstep(0.3, 0.76, wall_line_noise_b));
			tonal_focus = max(tonal_focus, cross_mask * 0.9);
			hatch_b_weight = 1.05;
		}
		vec2 dir_a = normalize(vec2(0.82, 0.57));
		vec2 dir_b = normalize(vec2(-0.71, 0.69));
		float coord_a = dot(hatch_uv, dir_a) * hatch_density + hatch_noise;
		float coord_b = dot(hatch_uv, dir_b) * hatch_density + hatch_noise * 0.85;
		float hatch_a_band = mst_hatch_band(coord_a, hatch_width);
		float hatch_b_band = mst_hatch_band(coord_b, hatch_width * 1.08);
		float hatch_a_core = mst_hatch_band_core(coord_a, hatch_width);
		float hatch_b_core = mst_hatch_band_core(coord_b, hatch_width * 1.08);
		float hatch_a = hatch_a_band * shadow_mask * line_breakup_a * mix(0.82, 1.0, hatch_a_core);
		float hatch_b = hatch_b_band * cross_mask * line_breakup_b * mix(0.82, 1.0, hatch_b_core);
		hatch = max(hatch_a, hatch_b * hatch_b_weight) * hatch_opacity * tonal_focus * hatch_distance_fade * hatch_intensity;
	}

	// Do not apply the tonal wash/hatching to broad, flat ground faces. Keep it
	// on walls and angled corner faces, where it provides useful form separation.
	float surface_normal_up = abs(normalize(v_world_normal).y);
	float non_flat_surface = 1.0 - smoothstep(0.92, 0.995, surface_normal_up);
	// Screen-space depth/normal edges see grass blades in front of the terrain.
	// Restrict those edge tests to walls/corners so flat terrain does not ink
	// every blade silhouette.
	float outline_edges = max(depth_edge, normal_edge) * non_flat_surface;
	float outline_mask = max(outline_edges, silhouette);
	outline_mask = clamp(outline_mask * line_opacity, 0.0, 1.0);
	float tonal_mask = clamp(max(shadow_wash, hatch) * non_flat_surface, 0.0, 1.0);
	float ink_mask = clamp(max(outline_mask, tonal_mask), 0.0, 1.0) * ink_color.a;

	ALBEDO = ink_color.rgb;
	ALPHA = ink_mask;
}
