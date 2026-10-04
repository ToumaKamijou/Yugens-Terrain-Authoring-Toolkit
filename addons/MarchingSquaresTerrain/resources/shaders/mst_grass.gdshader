shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque, depth_prepass_alpha;

group_uniforms Visuals.Palette;
// Palette data is provided via lookup textures (see mst_terrain.gdshaderinc for details).
uniform sampler2D palette_colors_tex : source_color, filter_nearest;
uniform sampler2D palette_weights_tex : filter_nearest;
uniform sampler2D palette_meta_tex : filter_nearest;
uniform sampler2D palette_surface_settings_tex : filter_nearest;
uniform sampler2D palette_floor_noise_tex : filter_nearest;
uniform sampler2D slot_albedo_tex : source_color, filter_nearest;
uniform sampler2D tex_prefab_colormap : source_color;
uniform bool has_prefab_colormap = false;
group_uniforms;

group_uniforms Visuals.Textures;
uniform sampler2DArray vc_floor_tex_array : source_color, filter_nearest;
uniform bool use_floor_tex_array = false;
uniform sampler2D vc_slot_layer_lookup_tex : filter_nearest;
uniform bool use_slot_layer_lookup = false;
uniform float tex_scales[256];
uniform ivec3 chunk_size = ivec3(33, 32, 33);
uniform vec2 cell_size = vec2(2.0, 2.0);
// Legacy per-grass-sprite textures (fallback)
uniform sampler2D grass_texture_1 : source_color, filter_nearest;
uniform sampler2D grass_texture_2 : source_color, filter_nearest;
uniform sampler2D grass_texture_3 : source_color, filter_nearest;
uniform sampler2D grass_texture_4 : source_color, filter_nearest;
uniform sampler2D grass_texture_5 : source_color, filter_nearest;
uniform sampler2D grass_texture_6 : source_color, filter_nearest;
// New: small Texture2DArray for grass sprites so grass uses same runtime atlas pipeline as terrain
uniform sampler2DArray vc_grass_tex_array : source_color, filter_nearest;
uniform bool use_grass_tex_array = false;
group_uniforms;

group_uniforms Visuals.Texture_Mode;
uniform bool use_grass_tex_2 = true;
uniform bool use_grass_tex_3 = true;
uniform bool use_grass_tex_4 = true;
uniform bool use_grass_tex_5 = true;
uniform bool use_grass_tex_6 = true;
group_uniforms;

group_uniforms Visuals.Color_Mode;
uniform bool use_base_color_1 = false;
uniform bool use_base_color_2 = false;
uniform bool use_base_color_3 = false;
uniform bool use_base_color_4 = false;
uniform bool use_base_color_5 = false;
uniform bool use_base_color_6 = false;
group_uniforms;

group_uniforms Animations.Settings;
uniform bool animate_active = true;
uniform float fps : hint_range(0.0, 30.0, 1.0) = 0.0;
uniform vec4 wind_tip_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
group_uniforms;

group_uniforms Effects.Experimental;
uniform bool is_merge_round = false;
uniform float blade_variation : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0;
group_uniforms;

group_uniforms Effects.GlobalNoise;
uniform float global_noise_scale = 0.037;
uniform float global_noise_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float global_noise_scroll = 0.0;
uniform sampler2D global_noise_texture : hint_default_white, repeat_enable, filter_linear;
group_uniforms;

#include "mst_global_wind.gdshaderinc"

// Palette color selection always uses the global-noise texture (internally remapped).

group_uniforms CellShading;
uniform bool use_cell_shading = true;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.0;
group_uniforms;

group_uniforms VertexPaint;
varying vec3 world_origin;
varying vec3 vertex_normal;
group_uniforms;


varying float v_brightness;
varying vec3 v_grass_color;
varying vec3 model_origin;
varying vec2 instance_ground_uv;
varying float instance_has_ground_uv;
varying flat int instance_slot_id;
varying float v_grass_wet_mask;
varying flat int instance_id;
varying float v_wind_perspective;
varying float v_wind_tip_bend;
varying float v_wind_amount;

// ------------- Wind Choices --------------

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
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

float cheap_noise(vec2 p) {
	vec2 warp = vec2(
		noise(p + vec2(1.7, 9.2)),
		noise(p + vec2(8.3, 2.8)));
	return noise(p + warp * 0.4) * 0.6 + noise(p * 2.1 + vec2(5.2, 1.3)) * 0.4;
}

float blade_body_weight(float blade_height) {
	return smoothstep(0.08, 0.72, blade_height);
}

float blade_tip_weight(float blade_height) {
	return smoothstep(0.42, 1.0, blade_height);
}


vec4 _palette_meta(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return texture(palette_meta_tex, vec2(0.5, v));
}

int _palette_count(int slot) {
	return int(round(_palette_meta(slot).r * 255.0));
}

int _palette_blend_mode(int slot) {
	return int(round(_palette_meta(slot).g * 255.0));
}

float _palette_roughness(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return clamp(texture(palette_surface_settings_tex, vec2(0.5, v)).r, 0.0, 1.0);
}

float _palette_wet_enabled(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return texture(palette_surface_settings_tex, vec2(0.5, v)).g;
}

float _palette_grass_wetness(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return clamp(texture(palette_surface_settings_tex, vec2(0.5, v)).a, 0.0, 1.0);
}

vec3 _palette_floor_noise_settings(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return texture(palette_floor_noise_tex, vec2(0.5, v)).rgb;
}

vec4 sample_palette_entry(int slot, int color_idx) {
	slot = clamp(slot, 0, 255);
	int idx = clamp(color_idx, 0, 7);
	float u = (float(idx) + 0.5) / 8.0;
	float v = (float(slot) + 0.5) / 256.0;
	return texture(palette_colors_tex, vec2(u, v));
}

float sample_palette_weight(int slot, int color_idx) {
	slot = clamp(slot, 0, 255);
	int idx = clamp(color_idx, 0, 7);
	float u = (float(idx) + 0.5) / 8.0;
	float v = (float(slot) + 0.5) / 256.0;
	return max(texture(palette_weights_tex, vec2(u, v)).r, 0.0);
}

float _palette_weight_or_zero(int slot, int color_idx, int color_count) {
	return (color_idx < color_count) ? sample_palette_weight(slot, color_idx) : 0.0;
}

// Palette weights are kept in two vec4s (slots 0-3 / 4-7) instead of a float[8]:
// Compatibility renderer can't access a float[8] via a runtime loop index
float _palette_weight_at(vec4 ws_lo, vec4 ws_hi, int i) {
	vec4 v = (i < 4) ? ws_lo : ws_hi;
	int j = (i < 4) ? i : i - 4;
	if (j == 0) return v.x;
	if (j == 1) return v.y;
	if (j == 2) return v.z;
	if (j == 3) return v.w;
	return 0.0;
}

vec4 get_grass_palette_color(int slot, vec2 world_xz) {
	slot = clamp(slot, 0, 255);
	int color_count = _palette_count(slot);
	// Match terrain empty-palette fallback (no tint) instead of a hardcoded green.
	if (color_count <= 0) return vec4(1.0, 1.0, 1.0, 0.0);
	if (color_count == 1) return sample_palette_entry(slot, 0);

	int mode = _palette_blend_mode(slot);
	bool gradient_mode = mode != 1 && mode != 2 && mode != 3;

	float n = 0.0;
	// Match terrain floor palette remap exactly (same scales / invert / curve).
	float palette_gn_scale = gradient_mode ? 0.014 : 0.008;
	vec2 uv = fract(world_xz * palette_gn_scale);
	n = 1.0 - texture(global_noise_texture, uv).r;
	if (gradient_mode) {
		float centered = (clamp(n, 0.0, 1.0) - 0.5) * 2.0;
		n = clamp(sign(centered) * pow(abs(centered), 0.55) * 0.5 + 0.5, 0.0, 1.0);
	} else {
		n = smoothstep(0.0, 1.0, n);
	}

	// Weighted distribution (values are normalized per slot).
	vec4 ws_lo = vec4(
		_palette_weight_or_zero(slot, 0, color_count),
		_palette_weight_or_zero(slot, 1, color_count),
		_palette_weight_or_zero(slot, 2, color_count),
		_palette_weight_or_zero(slot, 3, color_count));
	vec4 ws_hi = vec4(
		_palette_weight_or_zero(slot, 4, color_count),
		_palette_weight_or_zero(slot, 5, color_count),
		_palette_weight_or_zero(slot, 6, color_count),
		_palette_weight_or_zero(slot, 7, color_count));
	float total = dot(ws_lo, vec4(1.0)) + dot(ws_hi, vec4(1.0));
	if (total <= 0.0001) {
		// Equal weights (1.0) for every used color, 0.0 for the rest.
		total = float(color_count);
		ws_lo = clamp(float(color_count) - vec4(0.0, 1.0, 2.0, 3.0), 0.0, 1.0);
		ws_hi = clamp(float(color_count) - vec4(4.0, 5.0, 6.0, 7.0), 0.0, 1.0);
	}

	float x = clamp(n, 0.0, 1.0) * total;
	int i0 = 0;
	float start = 0.0;
	float w0 = ws_lo.x;
	float cum = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= color_count) break;
		float wi = _palette_weight_at(ws_lo, ws_hi, i);
		if (x < cum + wi || i == color_count - 1) {
			i0 = i;
			start = cum;
			w0 = wi;
			break;
		}
		cum += wi;
	}
	int i1 = min(i0 + 1, color_count - 1);
	float t = 0.0;
	if (w0 > 0.00001) t = clamp((x - start) / w0, 0.0, 1.0);

	if (mode == 1) {
		// Retro: hard snap by weighted ownership.
		return sample_palette_entry(slot, i0);
	} else if (mode == 2) {
		// Dithered: match terrain floor dither thresholds / 2D hash.
		vec4 result = sample_palette_entry(slot, i0);
		float boundary = 0.0;
		float transition = max(total * 0.09, 0.0001);
		vec2 dither_coord = floor(world_xz * 8.0);
		float dither = hash(dither_coord);
		for (int i = 0; i < 7; i++) {
			if (i >= color_count - 1) break;
			float wi = _palette_weight_at(ws_lo, ws_hi, i);
			float wn = _palette_weight_at(ws_lo, ws_hi, i + 1);
			boundary += wi;
			if (wi <= 0.0001 || wn <= 0.0001) continue;
			float blend_t = smoothstep(boundary - transition, boundary + transition, x);
			float sel = step(dither, blend_t);
			result = mix(result, sample_palette_entry(slot, i + 1), sel);
		}
		return result;
	} else if (mode == 3) {
		// Stipple: match terrain floor checker/seam constants.
		vec4 result = sample_palette_entry(slot, i0);
		float boundary = 0.0;
		float transition = max(total * 0.09, 0.0001);
		float seam = 0.12;
		vec2 checker_coord = floor(world_xz * 4.0);
		float checker = mod(checker_coord.x + checker_coord.y, 2.0);
		for (int i = 0; i < 7; i++) {
			if (i >= color_count - 1) break;
			float wi = _palette_weight_at(ws_lo, ws_hi, i);
			float wn = _palette_weight_at(ws_lo, ws_hi, i + 1);
			boundary += wi;
			if (wi <= 0.0001 || wn <= 0.0001) continue;
			float blend_t = smoothstep(boundary - transition, boundary + transition, x);
			vec4 next_color = sample_palette_entry(slot, i + 1);
			if (blend_t > 0.5 + seam) {
				result = next_color;
			} else if (blend_t >= 0.5 - seam) {
				result = checker > 0.5 ? next_color : result;
			}
		}
		return result;
	} else {
		// Gradient: weighted soft color bands. Slider weights define coverage; edges feather into neighbors.
		vec4 accum_color = vec4(0.0);
		float accum_weight = 0.0;
		float band_start = 0.0;
		for (int i = 0; i < 8; i++) {
			if (i >= color_count) break;
			float wi = _palette_weight_at(ws_lo, ws_hi, i);
			float band_end = band_start + wi;
			if (wi > 0.0001) {
				float w_prev = _palette_weight_at(ws_lo, ws_hi, i - 1);
				float w_next = _palette_weight_at(ws_lo, ws_hi, i + 1);
				float left_width = (i == 0) ? 0.0 : max(min(w_prev, wi) * 0.75, total * 0.004);
				float right_width = (i == color_count - 1) ? 0.0 : max(min(wi, w_next) * 0.75, total * 0.004);
				float left_mask = (i == 0) ? 1.0 : smoothstep(band_start - left_width, band_start + left_width, x);
				float right_mask = (i == color_count - 1) ? 1.0 : 1.0 - smoothstep(band_end - right_width, band_end + right_width, x);
				float mask = max(left_mask * right_mask, 0.0);
				accum_color += sample_palette_entry(slot, i) * mask;
				accum_weight += mask;
			}
			band_start = band_end;
		}
		if (accum_weight > 0.0001) return accum_color / accum_weight;
		return sample_palette_entry(slot, i0);
	}
}

vec4 get_slot_albedo_color(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return texture(slot_albedo_tex, vec2(0.5, v));
}

float get_texture_scale(int slot) {
	slot = clamp(slot, 0, 255);
	if (slot == 15) return 1.0;
	return max(tex_scales[slot], 0.0001);
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

vec4 sample_floor_texture_layer(int slot, vec2 base_uv) {
	slot = clamp(slot, 0, 255);
	vec2 uv = fract(base_uv * get_texture_scale(slot));
	if (use_slot_layer_lookup) {
		int dense_layer = dense_texture_layer(slot);
		if (dense_layer < 0) {
			return (slot == 15) ? vec4(0.0) : vec4(1.0);
		}
		return texture(vc_floor_tex_array, vec3(uv, float(dense_layer)));
	}
	if (slot == 15) return texture(vc_floor_tex_array, vec3(uv, 15.0));
	return texture(vc_floor_tex_array, vec3(uv, float(slot)));
}

vec4 sample_floor_material_color(int slot, vec2 base_uv) {
	vec4 tex = use_floor_tex_array ? sample_floor_texture_layer(slot, base_uv) : vec4(1.0);
	if (slot == 15) return tex;

	vec4 palette = get_grass_palette_color(slot, world_origin.xz);
	bool tex_has_content = (tex.a > 0.001) && (abs(tex.r - 1.0) > 0.001 || abs(tex.g - 1.0) > 0.001 || abs(tex.b - 1.0) > 0.001);
	if (tex_has_content) {
		float pal_alpha = clamp(palette.a, 0.0, 1.0);
		// Match terrain: palette as absolute tint target via albedo-normalized multiply.
		vec4 slot_albedo = get_slot_albedo_color(slot);
		vec3 tint_target = palette.rgb;
		if (slot_albedo.a > 0.001) {
			vec3 base_albedo = max(slot_albedo.rgb, vec3(0.001));
			tint_target = clamp(palette.rgb / base_albedo, vec3(0.0), vec3(4.0));
		}
		vec3 tinted = tex.rgb * mix(vec3(1.0), tint_target, pal_alpha);
		return vec4(tinted, tex.a);
	}
	return mix(tex, palette, clamp(palette.a, 0.0, 1.0));
}

void vertex() {

	// Billboarding
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
	float wind_amount_for_color = 0.0;
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
		wind_amount_for_color = wind_amount;
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
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);

	model_origin = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	instance_ground_uv = INSTANCE_CUSTOM.rg;
	instance_has_ground_uv = INSTANCE_CUSTOM.b;
	instance_slot_id = int(round(clamp(INSTANCE_CUSTOM.a, 0.0, 1.0) * 255.0));
	instance_id = INSTANCE_ID;

	int slot = instance_slot_id;
	vec3 _gc;
	bool use_base = false;
	if (slot == 0) use_base = use_base_color_1;
	else if (slot == 1) use_base = use_base_color_2;
	else if (slot == 2) use_base = use_base_color_3;
	else if (slot == 3) use_base = use_base_color_4;
	else if (slot == 4) use_base = use_base_color_5;
	else if (slot == 5) use_base = use_base_color_6;
	vec4 palette = get_grass_palette_color(slot, world_origin.xz);
	vec3 palette_col = palette.rgb;
	vec4 slot_albedo = get_slot_albedo_color(slot);
	vec3 slot_col = slot_albedo.rgb;
	vec3 base_col = slot_albedo.a > 0.5 ? slot_col : palette_col;
	float pal_alpha = clamp(palette.a, 0.0, 1.0);
	vec3 floor_sample_col = vec3(1.0);
	if (use_floor_tex_array) {
		vec2 floor_world_tile = cell_size * vec2(float(chunk_size.x - 1), float(chunk_size.z - 1));
		vec2 floor_uv = vec2(
			world_origin.x / max(floor_world_tile.x, 0.0001),
			world_origin.z / max(floor_world_tile.y, 0.0001)
		);
		floor_sample_col = sample_floor_material_color(slot, floor_uv).rgb;
	}
	if (has_prefab_colormap && instance_has_ground_uv > 0.5) {
		floor_sample_col *= texture(tex_prefab_colormap, instance_ground_uv).rgb;
	}
	vec3 sampled_floor_col = use_floor_tex_array ? floor_sample_col : mix(floor_sample_col, floor_sample_col * palette_col, pal_alpha);
	_gc = use_base ? base_col : sampled_floor_col;
	v_grass_color = _gc;
	v_grass_wet_mask = 0.0;
	v_wind_perspective = wind_perspective;
	v_wind_tip_bend = wind_tip_bend;
	v_wind_amount = wind_amount_for_color;
	if (_palette_wet_enabled(slot) > 0.5) {
		float top_half_mask = smoothstep(0.70, 0.98, 1.0 - UV.y);
		v_grass_wet_mask = clamp(_palette_grass_wetness(slot), 0.0, 1.0) * top_half_mask;
	}

	v_brightness = 1.0;

	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vertex_normal = world_normal;
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	vec3 grass_color = v_grass_color;
	int slot = clamp(int(instance_slot_id), 0, 255);
	int legacy_tex_id = clamp(slot + 1, 1, 6);
	vec2 grass_uv = UV;
	float tip_mask = smoothstep(0.22, 1.0, 1.0 - grass_uv.y);
	float perspective_strength = clamp(v_wind_perspective * 0.55, -0.35, 0.35);
	float center_pull = abs(perspective_strength) * tip_mask * 0.12;
	grass_uv.x = mix(grass_uv.x, 0.5, center_pull);
	grass_uv.y = clamp(
		grass_uv.y + perspective_strength * tip_mask * 0.18 - v_wind_tip_bend * tip_mask * 0.06,
		0.0,
		1.0
	);

	// Sample the appropriate grass texture. Prefer Texture2DArray if available.
	vec4 grass_tex = vec4(0.0);
	if (use_grass_tex_array) {
		if (use_slot_layer_lookup) {
			int dense_layer = dense_texture_layer(slot);
			grass_tex = (dense_layer < 0) ? vec4(0.0) : textureLod(vc_grass_tex_array, vec3(grass_uv, float(dense_layer)), 0.0);
		} else {
			grass_tex = textureLod(vc_grass_tex_array, vec3(grass_uv, float(slot)), 0.0);
		}
	} else {
		if (legacy_tex_id == 1) grass_tex = textureLod(grass_texture_1, grass_uv, 0.0);
		else if (legacy_tex_id == 2) grass_tex = textureLod(grass_texture_2, grass_uv, 0.0);
		else if (legacy_tex_id == 3) grass_tex = textureLod(grass_texture_3, grass_uv, 0.0);
		else if (legacy_tex_id == 4) grass_tex = textureLod(grass_texture_4, grass_uv, 0.0);
		else if (legacy_tex_id == 5) grass_tex = textureLod(grass_texture_5, grass_uv, 0.0);
		else if (legacy_tex_id == 6) grass_tex = textureLod(grass_texture_6, grass_uv, 0.0);
	}

	ALBEDO = grass_color;
	// Highlight only the upper blade tips during the strongest wind samples.
	// The color alpha controls the effect opacity, so a translucent white can
	// be used as a subtle light-catching wind cue.
	// Restrict the tint to the upper 30% of the blade. Wind deformation still
	// affects the full blade independently of this visual highlight.
	float wind_color_tip_mask = smoothstep(0.70, 1.0, 1.0 - grass_uv.y);
	float wind_strength_mask = smoothstep(0.18, 0.75, v_wind_amount) * wind_color_tip_mask;
	ALBEDO = mix(ALBEDO, wind_tip_color.rgb, wind_strength_mask * wind_tip_color.a);

	vec3 floor_noise = _palette_floor_noise_settings(slot);
	float floor_noise_strength = clamp(floor_noise.r, 0.0, 1.0) * step(0.5, floor_noise.b);
	float floor_noise_scale = clamp(floor_noise.g, 0.001, 1.0);
	if (floor_noise_strength > 0.0) {
		// Scroll intentionally disabled: grass follows the same static global-noise
		// field as terrain tinting.
		vec2 uv = fract(world_origin.xz * floor_noise_scale);
		float gn = texture(global_noise_texture, uv).r;
		// Centered multiplier: darkens and brightens around 1.0.
		float mult = mix(1.0 - floor_noise_strength, 1.0 + floor_noise_strength, clamp(gn, 0.0, 1.0));
		ALBEDO *= max(mult, 0.0);
	}

	float w_threshold = wall_threshold;
	if (is_merge_round && wall_threshold <= 0.0)
		w_threshold -= 1.5;
	if (dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > w_threshold) {
		// Alpha comes from selected layer; if using array we already sampled the correct layer.
		if (use_grass_tex_array) {
			ALPHA = grass_tex.a;
		} else {
			if (legacy_tex_id == 2) {
				ALPHA = use_grass_tex_2 ? grass_tex.a : 0.0;
			} else if (legacy_tex_id == 3) {
				ALPHA = use_grass_tex_3 ? grass_tex.a : 0.0;
			} else if (legacy_tex_id == 4) {
				ALPHA = use_grass_tex_4 ? grass_tex.a : 0.0;
			} else if (legacy_tex_id == 5) {
				ALPHA = use_grass_tex_5 ? grass_tex.a : 0.0;
			} else if (legacy_tex_id == 6) {
				ALPHA = use_grass_tex_6 ? grass_tex.a : 0.0;
			} else {
				ALPHA = grass_tex.a;
			}
		}
	} else {
		ALPHA = 0.0;
	}

	if (ALPHA < 0.1) discard;

	float grass_wet_mask = v_grass_wet_mask;
	ALBEDO *= (1.0 - 0.14 * grass_wet_mask);
	ALBEDO = mix(ALBEDO, ALBEDO * 1.05, grass_wet_mask * 0.35);
	ROUGHNESS = mix(1.0, _palette_roughness(slot), grass_wet_mask);

	ALBEDO *= v_brightness;

	LIGHT_VERTEX = model_origin;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	NdotL = clamp(NdotL, 0.0, 1.0);

	float toon_light;
	if (use_cell_shading) {
		float stepped = ceil(NdotL * float(bands)) / float(bands);
		toon_light = mix(shadow_intensity, 0.3, stepped);
	} else {
		toon_light = NdotL * 0.3;
	}

	toon_light = clamp(toon_light, 0.0, 1.0);
	vec3 light_color = mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);
	DIFFUSE_LIGHT += light_color * ATTENUATION;

	float wet_mask = clamp(v_grass_wet_mask, 0.0, 1.0);
	if (wet_mask > 0.001) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float ndoth = max(dot(NORMAL, half_vec), 0.0);
		float spec = pow(ndoth, mix(10.0, 22.0, wet_mask));
		float fres = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
		float wet_spec = (spec * 0.55 + fres * 0.25) * wet_mask;
		SPECULAR_LIGHT += LIGHT_COLOR.rgb * wet_spec * ATTENUATION;
	}
}
