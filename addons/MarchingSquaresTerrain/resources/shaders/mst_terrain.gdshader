shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque, alpha_to_coverage, cull_disabled;

group_uniforms Terrain.Properties;
uniform ivec3 chunk_size = ivec3(33, 32, 33);
uniform vec2 cell_size = vec2(2.0, 2.0);
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0; // Experimental feature (used for rounding merge thresholds)
group_uniforms;

group_uniforms Visuals.Albedo;
uniform vec4 tex_albedo_1 : source_color = vec4(0.392, 0.471, 0.318, 1.0);
uniform vec4 tex_albedo_2 : source_color = vec4(0.322, 0.482, 0.384, 1.0);
uniform vec4 tex_albedo_3 : source_color = vec4(0.373, 0.424, 0.294, 1.0);
uniform vec4 tex_albedo_4 : source_color = vec4(0.392, 0.475, 0.255, 1.0);
uniform vec4 tex_albedo_5 : source_color = vec4(0.29, 0.494, 0.365, 1.0);
uniform vec4 tex_albedo_6 : source_color = vec4(0.443, 0.447, 0.365, 1.0);
group_uniforms;

group_uniforms Visuals.Vertex_Painting;
uniform sampler2D vc_tex_rr : source_color, filter_nearest;
uniform sampler2D vc_tex_rg : source_color, filter_nearest;
uniform sampler2D vc_tex_rb : source_color, filter_nearest;
uniform sampler2D vc_tex_ra : source_color, filter_nearest;
uniform sampler2D vc_tex_gr : source_color, filter_nearest;
uniform sampler2D vc_tex_gg : source_color, filter_nearest;
uniform sampler2D vc_tex_gb : source_color, filter_nearest;
uniform sampler2D vc_tex_ga : source_color, filter_nearest;
uniform sampler2D vc_tex_br : source_color, filter_nearest;
uniform sampler2D vc_tex_bg : source_color, filter_nearest;
uniform sampler2D vc_tex_bb : source_color, filter_nearest;
uniform sampler2D vc_tex_ba : source_color, filter_nearest;
uniform sampler2D vc_tex_ar : source_color, filter_nearest;
uniform sampler2D vc_tex_ag : source_color, filter_nearest;
uniform sampler2D vc_tex_ab : source_color, filter_nearest;
uniform sampler2D vc_tex_aa : source_color, filter_nearest;
group_uniforms;

group_uniforms Visuals.Texture_Scales;
uniform float tex_scale_1 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_2 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_3 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_4 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_5 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_6 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_7 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_8 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_9 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_10 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_11 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_12 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_13 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_14 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_15 : hint_range(0.1, 20.0, 0.1) = 1.0;
group_uniforms;

group_uniforms Effects.Blending;
// true = Original behavior (single material, hard edges, works with "Perfect Square Tiles")
// false = Smooth blending between materials (works with "Mixed Triangles")
uniform bool use_hard_textures = false;
uniform int blend_mode = 0;
uniform float blend_sharpness : hint_range(0.0, 10.0, 0.1) = 5.0;
uniform float blend_noise_scale : hint_range(0.0, 50.0, 1.0) = 10.0;
uniform float blend_noise_strength : hint_range(0.0, 1.0, 0.05) = 0.0;
group_uniforms;

group_uniforms Effects.Ridge_Ledge_Texture;
// Used for wall textures continuing onto floors
uniform bool use_ridge_texture = true;
uniform bool use_ledge_texture = true;
uniform float ridge_threshold : hint_range(0.0, 1.0) = 1.0;
uniform float ledge_threshold : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D rl_noise_texture : source_color, filter_nearest;
uniform float rl_noise_tile_size : hint_range(0.01, 1.0) = 0.075;
uniform float rl_noise_strength : hint_range(0.0, 10.0) = 10.0;
group_uniforms;

group_uniforms Effects.Hanging_Floor_Texture;
// Used for floor textures continuing onto walls
group_uniforms;

group_uniforms CellShading;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.00;
group_uniforms;

// Shared varyings
varying vec3 vertex_normal;
varying vec4 custom1;
varying vec3 world_pos;

// Ridge & Ledge varyings for noise texture calculations
varying vec4 ridge_blend_factor;
varying vec4 ledge_blend_factor;

// Hard edges mode: flat material index (no interpolation)
varying flat int material_index;

// Soft blend mode: interpolated vertex colors
varying vec4 vc_color_0;
varying vec4 vc_color_1;

// Phantom fix: Per-cell material indices (flat = no GPU interpolation, supports 3 textures)
varying flat vec3 mat_indices; // mat_a, mat_b, mat_c (each /15)
varying vec2 mat_weights; // (weight_a, weight_b) - interpolated for smooth blending
varying float use_vertex_colors; // Flag: 1.0 = use vertex colors (boundary cells), 0.0 = use phantom fix

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Original: Get material index from vertex colors (used in vertex shader for hard edges)
int get_material_index(vec4 vc_col_0, vec4 vc_col_1) {
	int index = 0;
	if (vc_col_0.r > 0.1) {
		if (vc_col_1.r > 0.1) index = 0;
		else if (vc_col_1.g > 0.1) index = 1;
		else if (vc_col_1.b > 0.1) index = 2;
		else if (vc_col_1.a > 0.1) index = 3;
	}
	else if (vc_col_0.g > 0.1) {
		if (vc_col_1.r > 0.1) index = 4;
		else if (vc_col_1.g > 0.1) index = 5;
		else if (vc_col_1.b > 0.1) index = 6;
		else if (vc_col_1.a > 0.1) index = 7;
	}
	else if (vc_col_0.b > 0.1) {
		if (vc_col_1.r > 0.1) index = 8;
		else if (vc_col_1.g > 0.1) index = 9;
		else if (vc_col_1.b > 0.1) index = 10;
		else if (vc_col_1.a > 0.1) index = 11;
	}
	else if (vc_col_0.a > 0.1) {
		if (vc_col_1.r > 0.1) index = 12;
		else if (vc_col_1.g > 0.1) index = 13;
		else if (vc_col_1.b > 0.1) index = 14;
		else if (vc_col_1.a > 0.1) index = 15;
	}
	return index;
}

// Get per-texture UV scale
float get_texture_scale(int index) {
	switch(index) {
		case 0: return tex_scale_1;
		case 1: return tex_scale_2;
		case 2: return tex_scale_3;
		case 3: return tex_scale_4;
		case 4: return tex_scale_5;
		case 5: return tex_scale_6;
		case 6: return tex_scale_7;
		case 7: return tex_scale_8;
		case 8: return tex_scale_9;
		case 9: return tex_scale_10;
		case 10: return tex_scale_11;
		case 11: return tex_scale_12;
		case 12: return tex_scale_13;
		case 13: return tex_scale_14;
		case 14: return tex_scale_15;
		default: return 1.0;
	}
}

// Sample material by index with albedo tints and per-texture scaling applied
vec4 sample_material_by_index(int index, vec2 base_uv) {
	float scale = 1.0;
	if (index != 15)
		scale = get_texture_scale(index);
	vec2 uv = base_uv * scale;
	vec4 result;
	switch(index) {
		case 0: result = texture(vc_tex_rr, uv) * tex_albedo_1; break;
		case 1: result = texture(vc_tex_rg, uv) * tex_albedo_2; break;
		case 2: result = texture(vc_tex_rb, uv) * tex_albedo_3; break;
		case 3: result = texture(vc_tex_ra, uv) * tex_albedo_4; break;
		case 4: result = texture(vc_tex_gr, uv) * tex_albedo_5; break;
		case 5: result = texture(vc_tex_gg, uv) * tex_albedo_6; break;
		case 6: result = texture(vc_tex_gb, uv); break;
		case 7: result = texture(vc_tex_ga, uv); break;
		case 8: result = texture(vc_tex_br, uv); break;
		case 9: result = texture(vc_tex_bg, uv); break;
		case 10: result = texture(vc_tex_bb, uv); break;
		case 11: result = texture(vc_tex_ba, uv); break;
		case 12: result = texture(vc_tex_ar, uv); break;
		case 13: result = texture(vc_tex_ag, uv); break;
		case 14: result = texture(vc_tex_ab, uv); break;
		case 15: result = texture(vc_tex_aa, uv); break;  // VOID: fully transparent, no color contribution to blending
		default: result = texture(vc_tex_rr, uv) * tex_albedo_1; break;
	}
	return result;
}

// Sample wall material by index - uses unified texture pool (same as ground)
// Walls now use the same 16 textures as floors via sample_material_by_index()
vec4 sample_wall_by_index(int index, vec2 uv) {
	return sample_material_by_index(index, uv);
}

void calculate_blend_weights(vec4 vc0, vec4 vc1, float sharpness, out float weights[16]) {
	// Calculate raw weights from vertex color products
	float raw_weights[16];
	raw_weights[0]  = vc0.r * vc1.r;
	raw_weights[1]  = vc0.r * vc1.g;
	raw_weights[2]  = vc0.r * vc1.b;
	raw_weights[3]  = vc0.r * vc1.a;
	raw_weights[4]  = vc0.g * vc1.r;
	raw_weights[5]  = vc0.g * vc1.g;
	raw_weights[6]  = vc0.g * vc1.b;
	raw_weights[7]  = vc0.g * vc1.a;
	raw_weights[8]  = vc0.b * vc1.r;
	raw_weights[9]  = vc0.b * vc1.g;
	raw_weights[10] = vc0.b * vc1.b;
	raw_weights[11] = vc0.b * vc1.a;
	raw_weights[12] = vc0.a * vc1.r;
	raw_weights[13] = vc0.a * vc1.g;
	raw_weights[14] = vc0.a * vc1.b;
	raw_weights[15] = vc0.a * vc1.a;

	// Apply sharpness via power function
	// float power = 1.0 + sharpness * 2.0;
	float power = 2.0 + sharpness * 2.0;
	float total = 0.0;

	for (int i = 0; i < 16; i++) {
		weights[i] = pow(max(raw_weights[i], 0.0), power);
		total += weights[i];
	}

	// Normalize weights
	if (total > 0.001) {
		for (int i = 0; i < 16; i++) {
			weights[i] /= total;
		}
	} else {
		// Fallback: find dominant material
		float max_raw = 0.0;
		int max_idx = 0;
		for (int i = 0; i < 16; i++) {
			if (raw_weights[i] > max_raw) {
				max_raw = raw_weights[i];
				max_idx = i;
			}
		}
		for (int i = 0; i < 16; i++) {
			weights[i] = (i == max_idx) ? 1.0 : 0.0;
		}
	}
}

// Snap interpolated color to dominant channel (prevents bleeding between encodings)
// When GPU interpolates vertex colors across triangles at floor/wall boundaries,
// This snaps back to the single dominant channel.
vec4 snap_to_dominant(vec4 c) {
	float max_val = max(max(c.r, c.g), max(c.b, c.a));
	if (max_val < 0.001) return vec4(1.0, 0.0, 0.0, 0.0); // Default to R channel
	vec4 result = vec4(0.0);
	if (c.r >= max_val - 0.001) result.r = 1.0;
	else if (c.g >= max_val - 0.001) result.g = 1.0;
	else if (c.b >= max_val - 0.001) result.b = 1.0;
	else result.a = 1.0;
	return result;
}

// Blend wall materials using vertex color weights (for soft blend mode)
// Now uses all 16 textures from the unified texture pool
vec4 blend_wall_materials(vec2 uv, vec4 vc0, vec4 vc1, float sharpness) {
	// Snap interpolated colors to dominant channels to prevent bleeding
	// between floor and wall texture encodings at triangle boundaries
	vec4 snapped_vc0 = snap_to_dominant(vc0);
	vec4 snapped_vc1 = snap_to_dominant(vc1);

	float weights[16];
	calculate_blend_weights(snapped_vc0, snapped_vc1, sharpness, weights);

	vec4 wall_color = vec4(0.0);
	float total_weight = 0.0;

	for (int i = 0; i < 16; i++) {
		if (weights[i] > 0.01) {
			// Use full 0-15 range - walls now use unified texture pool
			wall_color += sample_wall_by_index(i, uv) * weights[i];
			total_weight += weights[i];
		}
	}

	if (total_weight > 0.001) {
		wall_color /= total_weight;
	}
	return wall_color;
}

float get_world_noise(vec3 world_position, float tile_size) {
	// Use world XZ coordinates for consistent noise regardless of view angle
	vec2 noise_uv = world_position.xz * tile_size;
	return texture(rl_noise_texture, noise_uv).r;
}

void vertex() {
	vertex_normal = NORMAL;
	custom1 = CUSTOM1;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Calculate ridge and ledge blend factors
	vec2 rl_uv = UV;
	float rl_factor = max(rl_uv.x, rl_uv.y);
	float r_blend_factor = step(ridge_threshold, rl_factor);
	float l_blend_factor = step(ledge_threshold, rl_factor);
	ridge_blend_factor = vec4(r_blend_factor, 0.0, 0.0, 0.0);
	ledge_blend_factor = vec4(l_blend_factor, 0.0, 0.0, 0.0);

	// Hard edges calculate material index here (flat = no interpolation)
	material_index = get_material_index(COLOR, CUSTOM0);

	// Soft blend: pass interpolated vertex colors to fragment
	vc_color_0 = COLOR;
	vc_color_1 = CUSTOM0;

	// CUSTOM2 contains per-cell material blend data for blend with 3-texture support
	// Encoding: R=packed(mat_a,mat_b), G=mat_c/15, B=weight_a, A=weight_b (or A>=1.5 = use vertex colors)
	float packed_mats = CUSTOM2.r * 255.0;
	mat_indices.x = mod(packed_mats, 16.0) / 15.0;  // mat_a (0-15 -> 0-1)
	mat_indices.y = floor(packed_mats / 16.0) / 15.0;  // mat_b (0-15 -> 0-1)
	mat_indices.z = CUSTOM2.g;  // mat_c (already /15)
	mat_weights = vec2(CUSTOM2.b, CUSTOM2.a);  // weight_a, weight_b (interpolated for smooth blending)
	use_vertex_colors = CUSTOM2.a >= 1.5 ? 1.0 : 0.0;  // A=2.0 signals vertex colors
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec4 vertex_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);

	vec2 tiling_factor_floor = vec2(1.0 / float(chunk_size.x), 1.0 / float(chunk_size.z));
	vec2 tiling_factor_wall = vec2(1.0 / float(chunk_size.x), 1.0 / float(chunk_size.y));
	bool is_floor = dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold;

	vec4 floor_color;
	vec3 wall_color;
	if (is_floor) {
		vec2 floor_uv = UV2 * tiling_factor_floor;

		//use per-cell material to prevent provoking vertex triangule artefact at ridge and ledge boundaries
		if (use_hard_textures) {
			// Use mat_indices.x (cell_mat_a) instead of vertex-based material_index
			// floor triangles always use floor material
			if (blend_mode == 2)
				floor_color = sample_material_by_index(material_index, floor_uv);
			else {
				int cell_dominant_mat = int(round(mat_indices.x * 15.0));
				floor_color = sample_material_by_index(cell_dominant_mat, floor_uv);
			}
		}
		// Boundary cells: use vertex colors (respects height-adjusted colors, no cross-height bleeding)
		else if (use_vertex_colors > 0.5) {
			float weights[16];
			float effective_sharpness = blend_sharpness;
			if (blend_noise_strength > 0.0) {
				float n = noise(world_pos.xz * blend_noise_scale);
				effective_sharpness = mix(blend_sharpness, blend_sharpness * (0.5 + n), blend_noise_strength);
			}
			calculate_blend_weights(vc_color_0, vc_color_1, effective_sharpness, weights);

			floor_color = vec4(0.0);
			for (int i = 0; i < 16; i++) {
				if (weights[i] > 0.01) {
					floor_color += sample_material_by_index(i, floor_uv) * weights[i];
				}
			}
		}
		// Flat cells:using per-cell material indices with supports 3 textures
		else {
			int mat_a = int(round(mat_indices.x * 15.0));
			int mat_b = int(round(mat_indices.y * 15.0));
			int mat_c = int(round(mat_indices.z * 15.0));

			// Weights are passed directly via mat_weights (interpolated by GPU for smooth blending)
			float weight_a = mat_weights.x;
			float weight_b = mat_weights.y;
			float weight_c = 1.0 - weight_a - weight_b;

			// Clamp to prevent negative weights from GPU interpolation precision issues
			weight_a = max(0.0, weight_a);
			weight_b = max(0.0, weight_b);
			weight_c = max(0.0, weight_c);

			// Renormalize to ensure weights sum to 1.0
			float weight_sum = weight_a + weight_b + weight_c;
			if (weight_sum > 0.001) {
				weight_a /= weight_sum;
				weight_b /= weight_sum;
				weight_c /= weight_sum;
			}

			// Apply noise to weights if enabled
			if (blend_noise_strength > 0.0) {
				float n = noise(world_pos.xz * blend_noise_scale);
				float noise_offset = (n - 0.5) * blend_noise_strength;
				weight_a = clamp(weight_a + noise_offset, 0.0, 1.0);
				weight_b = clamp(weight_b - noise_offset * 0.5, 0.0, 1.0);
				weight_c = clamp(weight_c - noise_offset * 0.5, 0.0, 1.0);
				// Renormalize
				float total = weight_a + weight_b + weight_c;
				if (total > 0.001) {
					weight_a /= total;
					weight_b /= total;
					weight_c /= total;
				}
			}

			// Apply sharpness to weights
			if (blend_sharpness > 0.0) {
				float power = 1.0 + blend_sharpness;
				weight_a = pow(weight_a, power);
				weight_b = pow(weight_b, power);
				weight_c = pow(weight_c, power);
				// Renormalize after power function
				float total = weight_a + weight_b + weight_c;
				if (total > 0.001) {
					weight_a /= total;
					weight_b /= total;
					weight_c /= total;
				}
			}

			vec4 color_a = sample_material_by_index(mat_a, floor_uv);
			vec4 color_b = sample_material_by_index(mat_b, floor_uv);
			vec4 color_c = sample_material_by_index(mat_c, floor_uv);
			floor_color = color_a * weight_a + color_b * weight_b + color_c * weight_c;
		}

		ALBEDO = floor_color.rgb;
		ALPHA = floor_color.a;
	}
	// Wall rendering with dual-mode support
	vec3 abs_normal = abs(vertex_normal);

	vec3 tri_weights = vec3(abs_normal.x, 0.0, abs_normal.z);
	tri_weights /= (tri_weights.x + tri_weights.z);

	// Divide by cell_size to match floor UV coordinate system
	// Floor UV2 = vert.xz / cell_size, so walls need the same normalization
	vec2 uv_x = (vertex_pos.zy / cell_size.yx) * tiling_factor_wall;
	vec2 uv_z = (vertex_pos.xy / cell_size) * tiling_factor_wall;

	vec4 wall_mat_x, wall_mat_z;

	float effective_sharpness = blend_sharpness;
	if (use_hard_textures) {
		// (like blend mode) (solves triangules at ridges, but introduce it at the borders)
		wall_mat_x = blend_wall_materials(uv_x, vc_color_0, vc_color_1, effective_sharpness);
		wall_mat_z = blend_wall_materials(uv_z, vc_color_0, vc_color_1, effective_sharpness);
	} else {
		// Soft blend: blend wall materials based on vertex colors
		effective_sharpness = blend_sharpness;
		if (blend_noise_strength > 0.0) {
			float n = noise(world_pos.xz * blend_noise_scale);
			effective_sharpness = mix(blend_sharpness, blend_sharpness * (0.5 + n), blend_noise_strength);
			}
		wall_mat_x = blend_wall_materials(uv_x, vc_color_0, vc_color_1, effective_sharpness);
		wall_mat_z = blend_wall_materials(uv_z, vc_color_0, vc_color_1, effective_sharpness);
	}

	vec3 texture_x = wall_mat_x.rgb * tri_weights.x;
	vec3 texture_z = wall_mat_z.rgb * tri_weights.z;
	wall_color = texture_x + texture_z;

	if (is_floor == false) {
		ALBEDO = texture_x + texture_z;
		ALPHA = wall_mat_x.a;
	}

	float blend_noise = get_world_noise(vertex_pos.xyz, rl_noise_tile_size);
	float mixed_blend_factor = 0.0;
	vec3 mixed_triplanar_color;
	if (use_ledge_texture && custom1.b > 0.5 && is_floor == true) {
		mixed_blend_factor = ledge_blend_factor.x;
		if (rl_noise_strength > 0.0) {
			float noise_variation = (blend_noise - 0.5) * rl_noise_strength;
			mixed_blend_factor = step(ledge_threshold + noise_variation, max(UV.x, UV.y));
		}
		mixed_triplanar_color = mix(floor_color.rgb, wall_color, mixed_blend_factor);
		ALBEDO = mixed_triplanar_color;
	}
	else if (use_ridge_texture && custom1.g > 0.5 && is_floor == true) {
		mixed_blend_factor = ridge_blend_factor.x;
		if (rl_noise_strength > 0.0) {
			float noise_variation = (blend_noise - 0.5) * rl_noise_strength;
			mixed_blend_factor = step(ridge_threshold + noise_variation, max(UV.x, UV.y));
		}
		mixed_triplanar_color = mix(floor_color.rgb, wall_color, mixed_blend_factor);
		ALBEDO = mixed_triplanar_color;
	}
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	NdotL = clamp(NdotL, 0.0, 1.0);

	float stepped = ceil(NdotL * float(bands)) / float(bands);
	float toon_light = mix(shadow_intensity, 0.3, stepped);
	toon_light *= ATTENUATION;

	vec3 light_color = mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);
	DIFFUSE_LIGHT += light_color;
}