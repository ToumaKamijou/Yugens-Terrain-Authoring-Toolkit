shader_type spatial;
render_mode diffuse_toon, depth_prepass_alpha;

group_uniforms Albedo;
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0;
uniform ivec3 chunk_size = ivec3(33, 32, 33);
uniform vec4 ground_albedo : source_color = vec4(0.392, 0.471, 0.318, 1.0);
uniform vec4 ground_albedo_2 : source_color = vec4(0.322, 0.482, 0.384, 1.0);
uniform vec4 ground_albedo_3 : source_color = vec4(0.373, 0.424, 0.294, 1.0);
uniform vec4 ground_albedo_4 : source_color = vec4(0.392, 0.475, 0.255, 1.0);
uniform vec4 ground_albedo_5 : source_color = vec4(0.29, 0.494, 0.365, 1.0);
uniform vec4 ground_albedo_6 : source_color = vec4(0.443, 0.447, 0.365, 1.0);
uniform vec4 wall_albedo : source_color = vec4(0.369, 0.337, 0.271, 1.0);
uniform vec4 wall_albedo_2 : source_color = vec4(0.4, 0.35, 0.28, 1.0);
uniform vec4 wall_albedo_3 : source_color = vec4(0.35, 0.32, 0.25, 1.0);
uniform vec4 wall_albedo_4 : source_color = vec4(0.38, 0.34, 0.27, 1.0);
uniform vec4 wall_albedo_5 : source_color = vec4(0.36, 0.33, 0.26, 1.0);
uniform vec4 wall_albedo_6 : source_color = vec4(0.42, 0.38, 0.30, 1.0);
group_uniforms;

group_uniforms Wall_Textures;
uniform sampler2D wall_tex_1 : source_color, repeat_enable;
uniform sampler2D wall_tex_2 : source_color, repeat_enable;
uniform sampler2D wall_tex_3 : source_color, repeat_enable;
uniform sampler2D wall_tex_4 : source_color, repeat_enable;
uniform sampler2D wall_tex_5 : source_color, repeat_enable;
uniform sampler2D wall_tex_6 : source_color, repeat_enable;
group_uniforms;

group_uniforms Blending;
// true = Original behavior (single material, hard edges, works with "Perfect Square Tiles")
// false = Smooth blending between materials (works with "Mixed Triangles")
uniform bool use_hard_square_edges = false;
uniform float blend_sharpness : hint_range(0.0, 10.0, 0.1) = 5.0;
uniform float blend_noise_scale : hint_range(0.0, 50.0, 1.0) = 10.0;
uniform float blend_noise_strength : hint_range(0.0, 1.0, 0.05) = 0.0;
group_uniforms;


group_uniforms Vertex_Colors;
uniform sampler2D vc_tex_rr : source_color;
uniform sampler2D vc_tex_rg : source_color;
uniform sampler2D vc_tex_rb : source_color;
uniform sampler2D vc_tex_ra : source_color;
uniform sampler2D vc_tex_gr : source_color;
uniform sampler2D vc_tex_gg : source_color;
uniform sampler2D vc_tex_gb : source_color;
uniform sampler2D vc_tex_ga : source_color;
uniform sampler2D vc_tex_br : source_color;
uniform sampler2D vc_tex_bg : source_color;
uniform sampler2D vc_tex_bb : source_color;
uniform sampler2D vc_tex_ba : source_color;
uniform sampler2D vc_tex_ar : source_color;
uniform sampler2D vc_tex_ag : source_color;
uniform sampler2D vc_tex_ab : source_color;
uniform sampler2D vc_tex_aa : source_color;
group_uniforms;

group_uniforms Shading;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.00;
group_uniforms;

// Shared varyings
varying vec3 vertex_normal;
varying vec4 custom1;
varying vec3 world_pos;

// Hard edges mode: flat material index (no interpolation)
varying flat int material_index;

// Soft blend mode: interpolated vertex colors
varying vec4 vc_color_0;
varying vec4 vc_color_1;

// Phantom fix: Per-cell material indices (flat = no GPU interpolation)
varying flat vec2 mat_indices;
varying float mat_blend_weight;
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

// Sample material by index with albedo tints applied
vec4 sample_material_by_index(int index, vec2 uv) {
	vec4 result;
	switch(index) {
		case 0: result = texture(vc_tex_rr, uv) * ground_albedo; break;
		case 1: result = texture(vc_tex_rg, uv) * ground_albedo_2; break;
		case 2: result = texture(vc_tex_rb, uv) * ground_albedo_3; break;
		case 3: result = texture(vc_tex_ra, uv) * ground_albedo_4; break;
		case 4: result = texture(vc_tex_gr, uv) * ground_albedo_5; break;
		case 5: result = texture(vc_tex_gg, uv) * ground_albedo_6; break;
		case 6: result = texture(vc_tex_gb, uv); break;
		case 7: result = texture(vc_tex_ga, uv); break;
		case 8: result = texture(vc_tex_br, uv); break;
		case 9: result = texture(vc_tex_bg, uv); break;
		case 10: result = texture(vc_tex_bb, uv); break;
		case 11: result = texture(vc_tex_ba, uv); break;
		case 12: result = texture(vc_tex_ar, uv); break;
		case 13: result = texture(vc_tex_ag, uv); break;
		case 14: result = texture(vc_tex_ab, uv); break;
		case 15: result = vec4(0.0); break;  // VOID: fully transparent, no color contribution to blending
		default: result = texture(vc_tex_rr, uv) * ground_albedo; break;
	}
	return result;
}

// Sample wall material by index (for hard edges mode and soft blend mode)
vec4 sample_wall_by_index(int index, vec2 uv) {
	vec4 result;
	switch(clamp(index, 0, 5)) {
		case 0: result = texture(wall_tex_1, uv) * wall_albedo; break;
		case 1: result = texture(wall_tex_2, uv) * wall_albedo_2; break;
		case 2: result = texture(wall_tex_3, uv) * wall_albedo_3; break;
		case 3: result = texture(wall_tex_4, uv) * wall_albedo_4; break;
		case 4: result = texture(wall_tex_5, uv) * wall_albedo_5; break;
		case 5: result = texture(wall_tex_6, uv) * wall_albedo_6; break;
		default: result = texture(wall_tex_1, uv) * wall_albedo; break;
	}
	return result;
}

// ============================================================================
// BLENDING FUNCTIONS (for soft blend mode)
// ============================================================================

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
// the result has multiple non-zero channels causing wrong texture bleeding.
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
vec4 blend_wall_materials(vec2 uv, vec4 vc0, vec4 vc1, float sharpness) {
	// Snap interpolated colors to dominant channels to prevent bleeding
	// between floor and wall texture encodings at triangle boundaries
	vec4 snapped_vc0 = snap_to_dominant(vc0);
	vec4 snapped_vc1 = snap_to_dominant(vc1);

	float weights[16];
	calculate_blend_weights(snapped_vc0, snapped_vc1, sharpness, weights);

	// Map 16 ground slots to 6 wall slots (clamp to 0-5)
	vec4 wall_color = vec4(0.0);
	float total_weight = 0.0;

	for (int i = 0; i < 16; i++) {
		if (weights[i] > 0.01) {
			int wall_idx = clamp(i, 0, 5);  // Map to wall slots 0-5
			wall_color += sample_wall_by_index(wall_idx, uv) * weights[i];
			total_weight += weights[i];
		}
	}

	if (total_weight > 0.001) {
		wall_color /= total_weight;
	}
	return wall_color;
}

// ============================================================================
// VERTEX SHADER
// ============================================================================

void vertex() {
	vertex_normal = NORMAL;
	custom1 = CUSTOM1;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Hard edges: calculate material index here (flat = no interpolation)
	material_index = get_material_index(COLOR, CUSTOM0);

	// Soft blend: pass interpolated vertex colors to fragment
	vc_color_0 = COLOR;
	vc_color_1 = CUSTOM0;

	// CUSTOM2 contains per-cell material blend data: (mat_a/15, mat_b/15, blend_weight, use_vc_flag)
	mat_indices = vec2(CUSTOM2.r, CUSTOM2.g);
	mat_blend_weight = CUSTOM2.b;
	use_vertex_colors = CUSTOM2.a; // 1.0 = boundary cell (use vertex colors), 0.0 = flat cell (use phantom fix)
}

// ============================================================================
// FRAGMENT SHADER
// ============================================================================

void fragment() {
	vec2 tiling_factor_floor = vec2(1.0 / float(chunk_size.x), 1.0 / float(chunk_size.z));
	vec2 tiling_factor_wall = vec2(1.0 / float(chunk_size.x), 1.0 / float(chunk_size.y));
	float is_ridge = custom1.g;
	bool is_floor = dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold && is_ridge < 0.5;

	if (is_floor) {
		vec2 floor_uv = UV2 * tiling_factor_floor;
		vec4 floor_color;

		//Hard edges mode keeps original behaviour
		if (use_hard_square_edges) {
			floor_color = sample_material_by_index(material_index, floor_uv);
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
		// Flat cells: PHANTOM FIX using per-cell material indices (prevents phantom 3rd texture)
		else {
			int mat_a = int(round(mat_indices.x * 15.0));
			int mat_b = int(round(mat_indices.y * 15.0));
			float blend_weight = mat_blend_weight;

			if (blend_noise_strength > 0.0) {
				float n = noise(world_pos.xz * blend_noise_scale);
				blend_weight = clamp(blend_weight + (n - 0.5) * blend_noise_strength, 0.0, 1.0);
			}

			if (blend_sharpness > 0.0) {
				float power = 1.0 + blend_sharpness;
				if (blend_weight < 0.5) {
					blend_weight = 0.5 * pow(2.0 * blend_weight, power);
				} else {
					blend_weight = 1.0 - 0.5 * pow(2.0 * (1.0 - blend_weight), power);
				}
			}

			vec4 color_a = sample_material_by_index(mat_a, floor_uv);
			vec4 color_b = sample_material_by_index(mat_b, floor_uv);
			floor_color = mix(color_a, color_b, blend_weight);
		}


		ALBEDO = floor_color.rgb;
		ALPHA = floor_color.a;
	}
	else {
		// Wall/Ridge rendering with dual-mode support
		vec4 vertex_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
		vec3 abs_normal = abs(vertex_normal);

		vec3 tri_weights = vec3(abs_normal.x, 0.0, abs_normal.z);
		tri_weights /= (tri_weights.x + tri_weights.z);

		vec2 uv_x = vertex_pos.zy * tiling_factor_wall * 2.0;
		vec2 uv_z = vertex_pos.xy * tiling_factor_wall * 2.0;

		vec4 wall_mat_x, wall_mat_z;

		if (use_hard_square_edges) {
			// Hard edges: single material based on vertex material_index
			wall_mat_x = sample_wall_by_index(material_index, uv_x);
			wall_mat_z = sample_wall_by_index(material_index, uv_z);
		} else {
			// Soft blend: blend wall materials based on vertex colors
			float effective_sharpness = blend_sharpness;
			if (blend_noise_strength > 0.0) {
				float n = noise(world_pos.xz * blend_noise_scale);
				effective_sharpness = mix(blend_sharpness, blend_sharpness * (0.5 + n), blend_noise_strength);
			}
			wall_mat_x = blend_wall_materials(uv_x, vc_color_0, vc_color_1, effective_sharpness);
			wall_mat_z = blend_wall_materials(uv_z, vc_color_0, vc_color_1, effective_sharpness);
		}

		vec3 texture_x = wall_mat_x.rgb * tri_weights.x;
		vec3 texture_z = wall_mat_z.rgb * tri_weights.z;

		ALBEDO = texture_x + texture_z;
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