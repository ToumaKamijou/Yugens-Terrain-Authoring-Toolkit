shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

group_uniforms Ink;
uniform vec4 ink_color : source_color = vec4(0.055, 0.05, 0.045, 0.92);
uniform float outline_opacity : hint_range(0.0, 1.0, 0.01) = 0.92;
uniform float outline_width_uv : hint_range(0.001, 0.08, 0.001) = 0.018;
uniform float inner_outline_mix : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float fill_opacity : hint_range(0.0, 1.0, 0.01) = 0.14;
uniform float fill_density : hint_range(1.0, 48.0, 0.1) = 15.0;
uniform float fill_patchiness : hint_range(0.0, 1.0, 0.01) = 0.38;
group_uniforms;

group_uniforms Grass;
uniform sampler2D grass_texture_1 : source_color, filter_nearest;
uniform sampler2D grass_texture_2 : source_color, filter_nearest;
uniform sampler2D grass_texture_3 : source_color, filter_nearest;
uniform sampler2D grass_texture_4 : source_color, filter_nearest;
uniform sampler2D grass_texture_5 : source_color, filter_nearest;
uniform sampler2D grass_texture_6 : source_color, filter_nearest;
uniform sampler2DArray vc_grass_tex_array : source_color, filter_nearest;
uniform bool use_grass_tex_array = false;
uniform sampler2D vc_slot_layer_lookup_tex : filter_nearest;
uniform bool use_slot_layer_lookup = false;
uniform bool use_grass_tex_2 = true;
uniform bool use_grass_tex_3 = true;
uniform bool use_grass_tex_4 = true;
uniform bool use_grass_tex_5 = true;
uniform bool use_grass_tex_6 = true;
uniform bool animate_active = true;
uniform float fps : hint_range(0.0, 30.0, 1.0) = 0.0;
uniform float blade_variation : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform bool is_merge_round = false;
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0;
uniform float global_noise_scale = 0.037;
group_uniforms;

#include "mst_global_wind.gdshaderinc"

varying vec2 v_grass_uv;
varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying flat int v_slot_id;
varying float v_outline_width_scale;

float mst_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float mst_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mst_hash(i);
	float b = mst_hash(i + vec2(1.0, 0.0));
	float c = mst_hash(i + vec2(0.0, 1.0));
	float d = mst_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float blade_body_weight(float blade_height) {
	return smoothstep(0.08, 0.72, blade_height);
}

float blade_tip_weight(float blade_height) {
	return smoothstep(0.42, 1.0, blade_height);
}

vec4 sample_slot_layer_lookup(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return texture(vc_slot_layer_lookup_tex, vec2(0.5, v));
}

int dense_texture_layer(int slot) {
	vec4 lookup = sample_slot_layer_lookup(slot);
	if (lookup.a < 0.5) {
		return -1;
	}
	return int(round(lookup.r * 255.0));
}

vec4 sample_grass_alpha_tex(int slot, vec2 uv) {
	int legacy_tex_id = clamp(slot + 1, 1, 6);
	if (use_grass_tex_array) {
		if (use_slot_layer_lookup) {
			int dense_layer = dense_texture_layer(slot);
			return (dense_layer < 0) ? vec4(0.0) : textureLod(vc_grass_tex_array, vec3(uv, float(dense_layer)), 0.0);
		}
		return textureLod(vc_grass_tex_array, vec3(uv, float(slot)), 0.0);
	}
	if (legacy_tex_id == 1) return textureLod(grass_texture_1, uv, 0.0);
	if (legacy_tex_id == 2) return use_grass_tex_2 ? textureLod(grass_texture_2, uv, 0.0) : vec4(0.0);
	if (legacy_tex_id == 3) return use_grass_tex_3 ? textureLod(grass_texture_3, uv, 0.0) : vec4(0.0);
	if (legacy_tex_id == 4) return use_grass_tex_4 ? textureLod(grass_texture_4, uv, 0.0) : vec4(0.0);
	if (legacy_tex_id == 5) return use_grass_tex_5 ? textureLod(grass_texture_5, uv, 0.0) : vec4(0.0);
	if (legacy_tex_id == 6) return use_grass_tex_6 ? textureLod(grass_texture_6, uv, 0.0) : vec4(0.0);
	return vec4(0.0);
}

void vertex() {
	vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	vec3 cam_z = normalize(CAMERA_DIRECTION_WORLD);
	vec3 cam_y = vec3(0.0, 1.0, 0.0);
	vec3 cam_x = cross(cam_y, cam_z);
	if (length(cam_x) < 0.001) {
		cam_x = vec3(1.0, 0.0, 0.0);
	}
	cam_x = normalize(cam_x);
	cam_y = normalize(cross(cam_z, cam_x));
	mat3 spherical_billboard = mat3(cam_x, cam_y, cam_z);

	float slotx = length(MODEL_MATRIX[0].xyz);
	float sloty = length(MODEL_MATRIX[1].xyz);
	float slotz = length(MODEL_MATRIX[2].xyz);

	float h = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float height_mult = mix(0.75, 1.25, h);
	sloty *= mix(1.0, height_mult, blade_variation);

	vec3 scaled_local = vec3(VERTEX.x * slotx, VERTEX.y * sloty, VERTEX.z * slotz);
	vec3 wind_world_offset = vec3(0.0);
	float wind_perspective = 0.0;
	float wind_tip_bend = 0.0;
	// Animation FPS steps the shared wind sample clock. 0 = no frames / no motion.
	if (animate_active && scaled_local.y > 0.0 && fps > 0.0) {
		float bend_factor = clamp(scaled_local.y / max(sloty, 0.0001), 0.0, 1.0);
		float body_weight = blade_body_weight(bend_factor);
		float tip_weight = blade_tip_weight(bend_factor);
		float sway_strength = 0.32;
		float seed = fract(sin(float(INSTANCE_ID) * 91.137 + slotx * 17.0 + slotz * 7.0) * 43758.5453);
		float stepped_time = floor((TIME + seed) * fps) / fps;
		vec2 wind_vec = mst_sample_wind_vector_at_time(instance_origin.xz, seed, stepped_time);
		float wind_amount = length(wind_vec);
		vec2 wind_dir = (wind_amount > 0.0001) ? (wind_vec / wind_amount) : vec2(0.0, 0.0);
		vec2 cross_dir = vec2(-wind_dir.y, wind_dir.x);
		float flutter = sin(
			stepped_time * (max(wind_speed, 0.001) * 3.2 + 0.8) +
			seed * 6.28318 +
			bend_factor * 3.4
		);
		float forward_push = wind_amount * (body_weight * 0.18 + tip_weight * 0.44);
		float side_sway = flutter * wind_amount * (tip_weight * 0.16);
		float downward_drag = wind_amount * (body_weight * 0.025 + tip_weight * 0.11);
		wind_world_offset =
			vec3(wind_dir.x, 0.0, wind_dir.y) * forward_push * sway_strength +
			vec3(cross_dir.x, 0.0, cross_dir.y) * side_sway * sway_strength;
		wind_world_offset.y -= downward_drag * sway_strength;
		vec2 camera_forward_xz = normalize(vec2(cam_z.x, cam_z.z) + vec2(0.0001, 0.0));
		wind_perspective = dot(wind_dir, camera_forward_xz) * wind_amount;
		wind_tip_bend = wind_amount * tip_weight;
	}

	vec3 billboarded_vertex = spherical_billboard * scaled_local;
	vec3 world_position = instance_origin + billboarded_vertex + wind_world_offset;
	v_world_pos = world_position;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);

	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_slot_id = int(round(clamp(INSTANCE_CUSTOM.a, 0.0, 1.0) * 255.0));
	vec2 grass_uv = UV;
	float tip_mask = smoothstep(0.22, 1.0, 1.0 - grass_uv.y);
	float perspective_strength = clamp(wind_perspective * 0.55, -0.35, 0.35);
	float center_pull = abs(perspective_strength) * tip_mask * 0.12;
	grass_uv.x = mix(grass_uv.x, 0.5, center_pull);
	grass_uv.y = clamp(
		grass_uv.y + perspective_strength * tip_mask * 0.18 - wind_tip_bend * tip_mask * 0.06,
		0.0,
		1.0
	);
	v_grass_uv = grass_uv;
	v_outline_width_scale = clamp(1.0 - center_pull * 3.2 - wind_tip_bend * 0.18, 0.28, 1.0);
}

void fragment() {
	float w_threshold = wall_threshold;
	if (is_merge_round && wall_threshold <= 0.0) {
		w_threshold -= 1.5;
	}
	if (dot(v_world_normal, vec3(0.0, 1.0, 0.0)) <= w_threshold) {
		discard;
	}

	vec2 uv = v_grass_uv;
	vec4 center = sample_grass_alpha_tex(v_slot_id, uv);
	float center_alpha = center.a;
	vec2 step_uv = vec2(outline_width_uv * v_outline_width_scale, outline_width_uv);
	float n1 = sample_grass_alpha_tex(v_slot_id, uv + vec2(step_uv.x, 0.0)).a;
	float n2 = sample_grass_alpha_tex(v_slot_id, uv + vec2(-step_uv.x, 0.0)).a;
	float n3 = sample_grass_alpha_tex(v_slot_id, uv + vec2(0.0, step_uv.y)).a;
	float n4 = sample_grass_alpha_tex(v_slot_id, uv + vec2(0.0, -step_uv.y)).a;
	float n5 = sample_grass_alpha_tex(v_slot_id, uv + step_uv).a;
	float n6 = sample_grass_alpha_tex(v_slot_id, uv + vec2(-step_uv.x, step_uv.y)).a;
	float n7 = sample_grass_alpha_tex(v_slot_id, uv + vec2(step_uv.x, -step_uv.y)).a;
	float n8 = sample_grass_alpha_tex(v_slot_id, uv - step_uv).a;
	float max_neighbor = max(max(max(n1, n2), max(n3, n4)), max(max(n5, n6), max(n7, n8)));
	float min_neighbor = min(min(min(n1, n2), min(n3, n4)), min(min(n5, n6), min(n7, n8)));

	float outer_edge = max_neighbor * (1.0 - step(0.5, center_alpha));
	float inner_edge = step(0.5, center_alpha) * (1.0 - min_neighbor);
	float edge = clamp(max(outer_edge, inner_edge * inner_outline_mix), 0.0, 1.0);
	float interior = step(0.5, center_alpha) * (1.0 - inner_edge);
	float fill_noise = mst_noise(v_world_pos.xz * fill_density + uv * 7.5);
	float fill_patch = smoothstep(0.5, 0.82, fill_noise);
	float fill = interior * mix(1.0, fill_patch, fill_patchiness) * fill_opacity;
	if (uv.y <= outline_width_uv * 1.5) {
		edge = 0.0;
	}

	ALBEDO = ink_color.rgb;
	ALPHA = clamp(edge * outline_opacity + fill, 0.0, 1.0) * ink_color.a;
	if (ALPHA < 0.01) {
		discard;
	}
}
