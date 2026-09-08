group_uniforms Terrain.Properties;
uniform ivec3 chunk_size = ivec3(33, 32, 33);
uniform vec2 cell_size = vec2(2.0, 2.0);
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0;
group_uniforms;

group_uniforms Visuals.Palette;
// NOTE: Some GPUs/devices have a 64KB limit on uniform buffers. Large uniform arrays
// (like vec4[2048]) can exceed that and cause the shader to silently fail.
// We store palette data in small lookup textures instead:
// - palette_colors_tex:  8 x 256, RGBA (float).   x=color idx (0..7), y=slot (0..255)
// - palette_weights_tex: 8 x 256, R in [0..1].    x=color idx (0..7), y=slot (0..255)
// - palette_meta_tex:    1 x 256, RGBA8 encoded:  r=count(0..8), g=blend_mode(0..3),
//                          b/a reserved, each stored as 0..255
uniform sampler2D palette_colors_tex : source_color, filter_nearest;
uniform sampler2D palette_weights_tex : filter_nearest;
uniform sampler2D palette_meta_tex : filter_nearest;
uniform sampler2D slot_albedo_tex : source_color, filter_nearest;
// Per-slot surface settings: roughness=.r, wetness_enabled=.g, wetness_mode=.b, grass_wetness=.a.
uniform sampler2D palette_surface_settings_tex : filter_nearest;
// Per-slot shared global-noise settings: strength=.r, scale=.g, enabled=.b.
uniform sampler2D palette_floor_noise_tex : filter_nearest;
uniform sampler2D palette_wall_noise_tex : filter_nearest;

group_uniforms;

group_uniforms Visuals.Prefabs;
uniform sampler2D tex_prefab_colormap : source_color;
uniform bool has_prefab_colormap = false;
group_uniforms;

group_uniforms Visuals.Vertex_Painting;
uniform sampler2DArray vc_tex_array : source_color, filter_nearest;
uniform sampler2DArray vc_normal_array : filter_linear;
uniform sampler2D vc_slot_layer_lookup_tex : filter_nearest;
uniform bool use_slot_layer_lookup = false;
uniform bool use_normal_array = false;
uniform float normal_map_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
group_uniforms;

group_uniforms Visuals.Texture_Scales;
uniform float tex_scales[256];
group_uniforms;

group_uniforms Effects.Blending;
uniform bool use_hard_textures = false;
uniform int blend_mode = 0;
uniform float blend_sharpness : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform int floor_blend_mode = 0;
uniform float blend_noise_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float blend_noise_scale : hint_range(0.0, 50.0, 1.0) = 10.0;
uniform float blend_noise_strength : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform bool use_stylized_texture_edges = true;
uniform float texture_edge_width : hint_range(0.01, 0.45, 0.01) = 0.18;
group_uniforms;

group_uniforms Effects.WallPaint;
uniform int wall_paint_count = 0;
uniform vec4 wall_paint_stamps_a[64];
uniform vec4 wall_paint_stamps_b[64];
uniform float wall_paint_plane_thickness : hint_range(0.001, 1.0, 0.001) = 0.03;
uniform float wall_paint_blend_width : hint_range(0.0, 2.0, 0.001) = 0.06;
group_uniforms;

group_uniforms Visuals.Normals;
uniform bool use_flat_normals = false;

// Detail height/noise texture used to derive a small normal perturbation.
uniform sampler2D detail_normal_texture : hint_default_white, repeat_enable, filter_linear;
uniform float detail_normal_scale : hint_range(0.001, 5.0, 0.001) = 0.25;
uniform float detail_normal_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
group_uniforms;

group_uniforms Effects.Ridge_Ledge_Texture;
uniform bool use_ridge_texture = true;
uniform bool use_ledge_texture = true;
uniform float ridge_threshold : hint_range(0.0, 1.0) = 1.0;
uniform float ledge_threshold : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D rl_noise_texture : source_color, filter_nearest;
uniform float rl_noise_tile_size : hint_range(0.01, 1.0) = 0.075;
uniform float rl_noise_strength : hint_range(0.0, 10.0) = 10.0;
uniform float global_noise_scale = 0.037;
uniform float global_noise_strength = 1.0;
// 0..1 multiplier for scroll speed (0 = off)
uniform float global_noise_scroll = 0.0;
uniform sampler2D global_noise_texture : hint_default_white, repeat_enable, filter_linear;

// Palette color selection always uses the global-noise texture (internally remapped).

#include "mst_global_wind.gdshaderinc"

group_uniforms CellShading;
uniform bool use_cell_shading = true;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.00;
// Adds a simple toon-friendly specular highlight so ROUGHNESS has a visible effect.
uniform float specular_strength : hint_range(0.0, 2.0, 0.01) = 0.5;
uniform float specular_threshold : hint_range(0.0, 1.0, 0.01) = 0.7;

// Wetness mode controls (used when slot wetness is enabled)
uniform float wet_puddle_noise_scale : hint_range(0.01, 2.0, 0.01) = 0.25;
uniform float wet_puddle_threshold : hint_range(0.0, 1.0, 0.01) = 0.55;
const float GLOSSY_PUDDLE_GLOBAL_NOISE_SCALE = 0.007;

group_uniforms;


varying vec3 vertex_normal;
varying vec3 world_normal;
varying vec3 custom1;
varying flat float nearest_wall_color_idx;
varying vec3 world_pos;
#ifdef BAKE_MODE
varying vec3 virtual_vertex;
#endif

varying vec4 ridge_blend_factor;
varying vec4 ledge_blend_factor;

varying flat int material_index;
varying flat vec3 mat_indices;
varying vec2 mat_weights;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

vec2 _mst_surface_plane_uv(vec3 wpos, vec3 n) {
	vec3 nn = normalize(n);
	// Pick an "up" that isn't parallel to the normal, so cross() is stable.
	vec3 up = (abs(nn.y) < 0.999) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t = normalize(cross(up, nn));
	vec3 b = cross(nn, t);
	return vec2(dot(wpos, t), dot(wpos, b));
}

vec2 _mst_wall_strip_uv(vec3 wpos, vec3 n) {
	vec2 horiz_n = vec2(n.x, n.z);
	float horiz_len = length(horiz_n);
	if (horiz_len <= 0.00001) {
		return _mst_surface_plane_uv(wpos, n);
	}
	horiz_n /= horiz_len;
	vec2 tangent = vec2(-horiz_n.y, horiz_n.x);
	return vec2(dot(wpos.xz, tangent), wpos.y);
}

float _mst_sample_wall_global_noise(vec3 wpos, vec3 n, float scale) {
	vec2 horiz_n = abs(vec2(n.x, n.z));
	float weight_sum = horiz_n.x + horiz_n.y;
	if (weight_sum <= 0.00001) {
		vec2 uv = fract(wpos.xz * scale);
		return texture(global_noise_texture, uv).r;
	}
	vec2 wall_x_uv = fract(vec2(wpos.z, wpos.y) * scale);
	vec2 wall_z_uv = fract(vec2(wpos.x, wpos.y) * scale);
	float gn_x = texture(global_noise_texture, wall_x_uv).r;
	float gn_z = texture(global_noise_texture, wall_z_uv).r;
	return (gn_x * horiz_n.x + gn_z * horiz_n.y) / weight_sum;
}

vec3 _mst_tangent_normal_to_surface(vec3 ts_normal, vec3 n) {
	vec3 nn = normalize(n);
	vec3 up = (abs(nn.y) < 0.999) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t = normalize(cross(up, nn));
	vec3 b = cross(nn, t);
	return normalize(t * ts_normal.x + b * ts_normal.y + nn * ts_normal.z);
}

vec2 _mst_blend_mask_uv(vec3 wpos, vec2 world_xz, vec3 n) {
	vec3 nn = normalize(n);
	float upness = abs(nn.y);
	return (upness > 0.85) ? world_xz : _mst_surface_plane_uv(wpos, n);
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

vec3 _mst_detail_height_to_ts(vec2 uv, float strength) {
	// Use a tiny finite difference to approximate a normal from height.
	float e = 0.002;
	float h = texture(detail_normal_texture, uv).r;
	float hx = texture(detail_normal_texture, uv + vec2(e, 0.0)).r;
	float hy = texture(detail_normal_texture, uv + vec2(0.0, e)).r;
	vec2 g = vec2(hx - h, hy - h);
	return normalize(vec3(-g.x * strength, -g.y * strength, 1.0));
}

float fbm_octaves(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) break;
		value += amplitude * cheap_noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// Cloud field based on layered value-noise fBm (ported from arlez80/cloud-shader, MIT).
// Returns gn in [0..1] where 1=no darkening, 0=fully dark cloud.
const float CLOUD_NOISE_SCALE = 0.00005;
const float CLOUD_SEED = -1000.0;
const vec2 CLOUD_SPEED = vec2(2.0, 0.0);
const vec2 CLOUD_TRANSFORM_SPEED = vec2(0.0, 0.0001);

highp float cloud_random(vec2 pos) {
	// Use continuous hash (avoid mod() discontinuities that can create line artifacts).
	return fract(sin(dot(pos, vec2(12.9898, 78.233))) * 43758.5453);
}

float cloud_value_noise(vec2 pos) {
	vec2 p = floor(pos);
	vec2 f = fract(pos);

	float v00 = cloud_random(p + vec2(0.0, 0.0));
	float v10 = cloud_random(p + vec2(1.0, 0.0));
	float v01 = cloud_random(p + vec2(0.0, 1.0));
	float v11 = cloud_random(p + vec2(1.0, 1.0));

	vec2 u = smoothstep(0.0, 1.0, f);
	return mix(mix(v00, v10, u.x), mix(v01, v11, u.x), u.y);
}

float _cloud_h(vec2 pos_a, vec2 pos_b) {
	float h = (
		cloud_value_noise(pos_a) * 8.0 +
		cloud_value_noise(pos_a * 4.2) * 8.0 +
		cloud_value_noise(pos_a * 8.4) * 8.0 +
		cloud_value_noise(pos_a * 17.6) * 8.0 +
		cloud_value_noise(pos_a * 61.8) * 4.0 +
		cloud_value_noise(pos_b * 90.1) * 4.0 +
		cloud_value_noise(pos_b * 110.1) * 0.0 +
		cloud_value_noise(pos_b * 220.0) * 0.0
	) / 46.0;
	return clamp(h, 0.0, 1.0);
}

float cloud_shadow_field(vec2 world_xz) {
	// Same CloudShadow.shader h computation, but keep it signed (h - bias) so we can anti-alias the threshold.
	float scale = global_noise_scale * 1250.0;
	vec2 p = world_xz * scale;
	vec2 pos_a = (vec2(p.x, p.y + CLOUD_SEED) + (TIME * CLOUD_SPEED)) * CLOUD_NOISE_SCALE;
	vec2 pos_b = pos_a + CLOUD_TRANSFORM_SPEED * TIME;

	// Blur/low-pass to reduce grid-aligned "digital camo" edges.
	vec2 o = vec2(0.37, 0.17);
	vec2 op = vec2(o.y, -o.x);
	float h = (
		_cloud_h(pos_a, pos_b) * 0.40 +
		_cloud_h(pos_a + o, pos_b + o) * 0.15 +
		_cloud_h(pos_a - o, pos_b - o) * 0.15 +
		_cloud_h(pos_a + op, pos_b + op) * 0.15 +
		_cloud_h(pos_a - op, pos_b - op) * 0.15
	);
	float bias = 0.4;
	return h - bias;
}

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

float get_texture_scale(int index) {
	index = clamp(index, 0, 255);
	// Keep legacy VOID slot behavior (texture_15) scale = 1.0.
	if (index == 15) return 1.0;
	return max(tex_scales[index], 0.0001);
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

int _palette_wet_mode(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return int(round(clamp(texture(palette_surface_settings_tex, vec2(0.5, v)).b, 0.0, 1.0)));
}

vec3 _palette_noise_settings(int slot, bool floor_surface) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	if (floor_surface) {
		return texture(palette_floor_noise_tex, vec2(0.5, v)).rgb;
	}
	return texture(palette_wall_noise_tex, vec2(0.5, v)).rgb;
}

vec2 _mixed_noise_settings(bool floor_surface) {
	if (use_hard_textures) {
		int hard_slot = (blend_mode == 2) ? material_index : int(round(mat_indices.x));
		vec3 hard_noise = _palette_noise_settings(hard_slot, floor_surface);
		return vec2(clamp(hard_noise.r, 0.0, 1.0) * step(0.5, hard_noise.b), max(hard_noise.g, 0.001));
	}

	int mat_a = int(round(mat_indices.x));
	int mat_b = int(round(mat_indices.y));
	int mat_c = int(round(mat_indices.z));

	float weight_a = max(0.0, mat_weights.x);
	float weight_b = max(0.0, mat_weights.y);
	float weight_c = max(0.0, 1.0 - weight_a - weight_b);
	float weight_sum = weight_a + weight_b + weight_c;
	if (weight_sum > 0.001) {
		weight_a /= weight_sum;
		weight_b /= weight_sum;
		weight_c /= weight_sum;
	}

	vec3 noise_a = _palette_noise_settings(mat_a, floor_surface);
	vec3 noise_b = _palette_noise_settings(mat_b, floor_surface);
	vec3 noise_c = _palette_noise_settings(mat_c, floor_surface);
	float enabled_a = step(0.5, noise_a.b);
	float enabled_b = step(0.5, noise_b.b);
	float enabled_c = step(0.5, noise_c.b);
	float enabled_weight = enabled_a * weight_a + enabled_b * weight_b + enabled_c * weight_c;
	if (enabled_weight <= 0.0001) {
		return vec2(0.0, max(global_noise_scale, 0.001));
	}

	float strength = (
		clamp(noise_a.r, 0.0, 1.0) * enabled_a * weight_a
		+ clamp(noise_b.r, 0.0, 1.0) * enabled_b * weight_b
		+ clamp(noise_c.r, 0.0, 1.0) * enabled_c * weight_c
	) / enabled_weight;
	float scale = (
		max(noise_a.g, 0.001) * enabled_a * weight_a
		+ max(noise_b.g, 0.001) * enabled_b * weight_b
		+ max(noise_c.g, 0.001) * enabled_c * weight_c
	) / enabled_weight;
	return vec2(strength * enabled_weight, scale);
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

vec4 get_palette_color(int tex_idx, vec2 surface_coords) {
	tex_idx = clamp(tex_idx, 0, 255);
	int color_count = _palette_count(tex_idx);

	if (color_count <= 0)
		return vec4(1.0, 1.0, 1.0, 0.0);
	if (color_count == 1)
		return sample_palette_entry(tex_idx, 0);

	int mode = _palette_blend_mode(tex_idx);
	bool gradient_mode = mode != 1 && mode != 2 && mode != 3;

	float n = 0.0;
	// Internal remap for palette blending: fixed higher-frequency sampling + inverted.
	// This keeps the UI Global Noise settings independent of palette blending behavior.
	float palette_gn_scale = gradient_mode ? 0.014 : 0.008;
	vec2 uv = fract(surface_coords * palette_gn_scale);
	n = 1.0 - texture(global_noise_texture, uv).r;
	if (gradient_mode) {
		float centered = (clamp(n, 0.0, 1.0) - 0.5) * 2.0;
		n = clamp(sign(centered) * pow(abs(centered), 0.55) * 0.5 + 0.5, 0.0, 1.0);
	} else {
		n = smoothstep(0.0, 1.0, n);
	}

	// Weighted distribution (values are normalized per slot).
	vec4 ws_lo = vec4(
		_palette_weight_or_zero(tex_idx, 0, color_count),
		_palette_weight_or_zero(tex_idx, 1, color_count),
		_palette_weight_or_zero(tex_idx, 2, color_count),
		_palette_weight_or_zero(tex_idx, 3, color_count));
	vec4 ws_hi = vec4(
		_palette_weight_or_zero(tex_idx, 4, color_count),
		_palette_weight_or_zero(tex_idx, 5, color_count),
		_palette_weight_or_zero(tex_idx, 6, color_count),
		_palette_weight_or_zero(tex_idx, 7, color_count));
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
		return sample_palette_entry(tex_idx, i0);

	} else if (mode == 2) {
		// Dithered: weights own area; only non-zero color boundaries dither.
		vec4 result = sample_palette_entry(tex_idx, i0);
		float boundary = 0.0;
		float transition = max(total * 0.09, 0.0001);
		vec2 dither_coord = floor(surface_coords * 8.0);
		float dither = hash(dither_coord);
		for (int i = 0; i < 7; i++) {
			if (i >= color_count - 1) break;
			float wi = _palette_weight_at(ws_lo, ws_hi, i);
			float wn = _palette_weight_at(ws_lo, ws_hi, i + 1);
			boundary += wi;
			if (wi <= 0.0001 || wn <= 0.0001) continue;
			float blend_t = smoothstep(boundary - transition, boundary + transition, x);
			float sel = step(dither, blend_t);
			result = mix(result, sample_palette_entry(tex_idx, i + 1), sel);
		}
		return result;

	} else if (mode == 3) {
		// Stipple: weights own area; only non-zero color boundaries checker/stipple.
		vec4 result = sample_palette_entry(tex_idx, i0);
		float boundary = 0.0;
		float transition = max(total * 0.09, 0.0001);
		float seam = 0.12;
		vec2 checker_coord = floor(surface_coords * 4.0);
		float checker = mod(checker_coord.x + checker_coord.y, 2.0);
		for (int i = 0; i < 7; i++) {
			if (i >= color_count - 1) break;
			float wi = _palette_weight_at(ws_lo, ws_hi, i);
			float wn = _palette_weight_at(ws_lo, ws_hi, i + 1);
			boundary += wi;
			if (wi <= 0.0001 || wn <= 0.0001) continue;
			float blend_t = smoothstep(boundary - transition, boundary + transition, x);
			vec4 next_color = sample_palette_entry(tex_idx, i + 1);
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
				accum_color += sample_palette_entry(tex_idx, i) * mask;
				accum_weight += mask;
			}
			band_start = band_end;
		}
		if (accum_weight > 0.0001) return accum_color / accum_weight;
		return sample_palette_entry(tex_idx, i0);
	}
}

vec4 _sample_slot_layer_lookup(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return texture(vc_slot_layer_lookup_tex, vec2(0.5, v));
}

vec4 get_slot_albedo_color(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return texture(slot_albedo_tex, vec2(0.5, v));
}

int _dense_texture_layer(int slot) {
	vec4 lookup = _sample_slot_layer_lookup(slot);
	if (lookup.a < 0.5) {
		return -1;
	}
	return int(round(lookup.r * 255.0));
}

vec4 sample_texture_layer(int slot, vec2 uv) {
	slot = clamp(slot, 0, 255);
	uv = fract(uv);
	if (use_slot_layer_lookup) {
		int dense_layer = _dense_texture_layer(slot);
		if (dense_layer < 0) {
			return (slot == 15) ? vec4(0.0) : vec4(1.0);
		}
		return texture(vc_tex_array, vec3(uv, float(dense_layer)));
	}
	// Legacy behavior: sample the Texture2DArray directly using the slot as the layer index.
	// Keep legacy VOID slot behavior intact.
	if (slot == 15) return texture(vc_tex_array, vec3(uv, 15.0));
	return texture(vc_tex_array, vec3(uv, float(slot)));
}

vec4 sample_material_by_index_tint(int index, vec2 base_uv, vec4 tint) {
	float scale = get_texture_scale(index);
	vec2 uv = base_uv * scale;
	vec4 tex = sample_texture_layer(index, uv);
	// Blend between texture and tint using tint.a as blend factor
	return mix(tex, tint, clamp(tint.a, 0.0, 1.0));
}

vec4 sample_material_by_index_with_palette_coords(int index, vec2 base_uv, vec2 palette_coords) {
	float scale = get_texture_scale(index);
	vec2 uv = base_uv * scale;
	vec4 tex = sample_texture_layer(index, uv);
	if (index == 15) return tex;
	vec4 palette = get_palette_color(index, palette_coords);
	// Heuristic: prefer assigned texture when it contains meaningful data (not a white placeholder).
	// When a real texture exists, blend the palette additively (tint/multiply) rather than fully replacing the texture.
	bool tex_has_content = (tex.a > 0.001) && (abs(tex.r - 1.0) > 0.001 || abs(tex.g - 1.0) > 0.001 || abs(tex.b - 1.0) > 0.001);
	if (tex_has_content) {
		float pal_alpha = clamp(palette.a, 0.0, 1.0);
		vec4 slot_albedo = get_slot_albedo_color(index);
		vec3 tint_target = palette.rgb;
		if (slot_albedo.a > 0.001) {
			vec3 base_albedo = max(slot_albedo.rgb, vec3(0.001));
			tint_target = clamp(palette.rgb / base_albedo, vec3(0.0), vec3(4.0));
		}
		vec3 tinted = tex.rgb * mix(vec3(1.0), tint_target, pal_alpha);
		return vec4(tinted, tex.a);
	}
	// Fallback: if texture is effectively empty/placeholder, blend with palette as before.
	return mix(tex, palette, clamp(palette.a, 0.0, 1.0));
}

vec4 sample_material_by_index(int index, vec2 base_uv) {
	return sample_material_by_index_with_palette_coords(index, base_uv, world_pos.xz);
}

bool _mst_slot_has_texture(int slot) {
	slot = clamp(slot, 0, 255);
	if (slot == 15) {
		return false;
	}
	if (use_slot_layer_lookup) {
		return _dense_texture_layer(slot) >= 0;
	}
	// Legacy arrays pad missing slots with white placeholders.
	vec4 tex = sample_texture_layer(slot, vec2(0.5));
	return (tex.a > 0.001) && (abs(tex.r - 1.0) > 0.001 || abs(tex.g - 1.0) > 0.001 || abs(tex.b - 1.0) > 0.001);
}

float _mst_slot_blend_height(int slot, vec2 base_uv) {
	// Color-only slots stay flat. Textured slots use albedo luminance so blend
	// isocontours break up along texture detail instead of forming rings.
	if (!_mst_slot_has_texture(slot)) {
		return 0.5;
	}
	float scale = get_texture_scale(slot);
	vec4 tex = sample_texture_layer(slot, base_uv * scale);
	return clamp(dot(tex.rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
}

vec4 _mst_height_blend3(
	vec4 c0, float w0, float h0,
	vec4 c1, float w1, float h1,
	vec4 c2, float w2, float h2,
	float depth
) {
	depth = max(depth, 0.001);
	float ma = w0 + h0 * depth;
	float mb = w1 + h1 * depth;
	float mc = w2 + h2 * depth;
	float mmax = max(ma, max(mb, mc));
	float b0 = max(ma - mmax + depth, 0.0);
	float b1 = max(mb - mmax + depth, 0.0);
	float b2 = max(mc - mmax + depth, 0.0);
	float bsum = max(b0 + b1 + b2, 0.0001);
	return (c0 * b0 + c1 * b1 + c2 * b2) / bsum;
}

vec4 _mst_apply_material_tint(int index, vec4 tex, vec2 palette_coords) {
	if (index == 15) return tex;
	vec4 palette = get_palette_color(index, palette_coords);
	bool tex_has_content = (tex.a > 0.001) && (abs(tex.r - 1.0) > 0.001 || abs(tex.g - 1.0) > 0.001 || abs(tex.b - 1.0) > 0.001);
	if (tex_has_content) {
		float pal_alpha = clamp(palette.a, 0.0, 1.0);
		vec4 slot_albedo = get_slot_albedo_color(index);
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

vec4 sample_wall_material_by_index(int index) {
	// Walls need a face-aligned strip projection, not a world-axis X/Z blend.
	// The old triplanar-style wall sampling smeared diagonals because 45-degree faces
	// blended two unrelated projections instead of following the actual wall tangent.
	float wall_u_scale = max(cell_size.x * float(chunk_size.x - 1), 0.0001);
	float wall_v_scale = max(cell_size.x * float(chunk_size.y - 1), 0.0001);
	vec2 wall_palette_coords = _mst_wall_strip_uv(world_pos, vertex_normal);
	vec2 wall_uv = wall_palette_coords / vec2(wall_u_scale, wall_v_scale);
	return sample_material_by_index_with_palette_coords(index, wall_uv, wall_palette_coords);
}

vec3 sample_normal_by_index(int index, vec2 base_uv) {
	float scale = get_texture_scale(index);
	vec2 uv = fract(base_uv * scale);
	int layer_index = clamp(index, 0, 255);
	if (use_slot_layer_lookup) {
		layer_index = _dense_texture_layer(layer_index);
		if (layer_index < 0) {
			return vec3(0.0, 0.0, 1.0);
		}
	}
	vec3 n = texture(vc_normal_array, vec3(uv, float(layer_index))).rgb * 2.0 - 1.0;
	if (dot(n, n) < 0.001) {
		return vec3(0.0, 0.0, 1.0);
	}
	return normalize(n);
}

vec3 _weight_onehot(int idx, float amount) {
	if (idx == 0) return vec3(amount, 0.0, 0.0);
	if (idx == 1) return vec3(0.0, amount, 0.0);
	return vec3(0.0, 0.0, amount);
}

vec3 stylized_texture_weights(vec3 weights) {
	float total = weights.x + weights.y + weights.z;
	if (total <= 0.001) return vec3(1.0, 0.0, 0.0);
	weights /= total;

	int top_idx = 0;
	float top_w = weights.x;
	if (weights.y > top_w) {
		top_idx = 1;
		top_w = weights.y;
	}
	if (weights.z > top_w) {
		top_idx = 2;
		top_w = weights.z;
	}

	float width = mix(0.05, 0.30, clamp(blend_sharpness, 0.0, 1.0));
	width = clamp(min(width, texture_edge_width), 0.01, 0.45);
	float low = 0.5 - width;
	float high = 0.5 + width;
	vec3 shaped = vec3(
		smoothstep(low, high, weights.x),
		smoothstep(low, high, weights.y),
		smoothstep(low, high, weights.z)
	);
	float shaped_total = shaped.x + shaped.y + shaped.z;
	if (shaped_total <= 0.001) {
		return _weight_onehot(top_idx, 1.0);
	}
	vec3 styled = shaped / shaped_total;

	// True three-way corners can collapse into a tiny pointed "bald" tip when the
	// third material gets pushed too low by the stylized remap. Blend a bit of the
	// original barycentric weights back in only when all three materials are
	// meaningfully present so junctions stay filled without blurring ordinary edges.
	float third_weight = min(weights.x, min(weights.y, weights.z));
	float junction_fill = smoothstep(0.10, 0.22, third_weight);
	vec3 mixed = mix(styled, weights, junction_fill * 0.20);
	float mixed_total = mixed.x + mixed.y + mixed.z;
	return mixed / max(mixed_total, 0.001);
}

vec3 blend_slot_normals(vec2 base_uv) {
	if (use_hard_textures) {
		int hard_idx = (blend_mode == 2) ? material_index : int(round(mat_indices.x));
		return sample_normal_by_index(hard_idx, base_uv);
	}

	int mat_a = int(round(mat_indices.x));
	int mat_b = int(round(mat_indices.y));
	int mat_c = int(round(mat_indices.z));

	float weight_a = max(0.0, mat_weights.x);
	float weight_b = max(0.0, mat_weights.y);
	float weight_c = max(0.0, 1.0 - weight_a - weight_b);
	float weight_sum = weight_a + weight_b + weight_c;
	if (weight_sum > 0.001) {
		weight_a /= weight_sum;
		weight_b /= weight_sum;
		weight_c /= weight_sum;
	}
	if (use_stylized_texture_edges) {
		vec3 styled_weights = stylized_texture_weights(vec3(weight_a, weight_b, weight_c));
		weight_a = styled_weights.x;
		weight_b = styled_weights.y;
		weight_c = styled_weights.z;
	}

	vec3 n = sample_normal_by_index(mat_a, base_uv) * weight_a
		+ sample_normal_by_index(mat_b, base_uv) * weight_b
		+ sample_normal_by_index(mat_c, base_uv) * weight_c;
	if (dot(n, n) < 0.001) {
		return vec3(0.0, 0.0, 1.0);
	}
	return normalize(n);
}

float get_world_noise(vec3 world_position, float tile_size) {
	vec2 noise_uv = world_position.xz * tile_size;
	return texture(rl_noise_texture, noise_uv).r;
}

void vertex() {
	vertex_normal = NORMAL;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	custom1 = CUSTOM1.rgb;
	float a = CUSTOM1.a;
	nearest_wall_color_idx = floor(a);
#ifndef BAKE_MODE
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#else
	virtual_vertex = CUSTOM3.xyz;
	world_pos = (MODEL_MATRIX * vec4(virtual_vertex, 1.0)).xyz;
#endif
	vec2 rl_uv = UV;
	float ridge_factor = max(rl_uv.x, rl_uv.y);
	float ledge_factor = ridge_factor;
	ridge_blend_factor = vec4(step(ridge_threshold, ridge_factor), 0.0, 0.0, 0.0);
	ledge_blend_factor = vec4(step(ledge_threshold, ledge_factor), 0.0, 0.0, 0.0);

	mat_indices = CUSTOM2.rgb;
	mat_weights = vec2(CUSTOM2.a, CUSTOM0.r);
	material_index = int(round(mat_indices.x));

	// Treat wall vertices explicitly via UV sentinel (walls use UV=(2,2)).
	bool is_floor = (UV.x < 1.5) && (dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold);
	if (use_flat_normals && is_floor)
		NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#ifndef BAKE_MODE
	vec4 vertex_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
#else
	vec4 vertex_pos = INV_VIEW_MATRIX * vec4(virtual_vertex, 1.0);
#endif

	vec2 tiling_factor_floor = vec2(1.0 / float(chunk_size.x - 1), 1.0 / float(chunk_size.z - 1));
	vec2 tiling_factor_wall = vec2(1.0 / float(chunk_size.x - 1), 1.0 / float(chunk_size.y - 1));
	// Treat wall vertices explicitly via UV sentinel (walls use UV=(2,2)).
	bool is_floor = (UV.x < 1.5) && (dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold);

	vec3 abs_normal = abs(vertex_normal);
	vec3 tri_weights = vec3(abs_normal.x, 0.0, abs_normal.z);
	float tri_denom = tri_weights.x + tri_weights.z;
	if (tri_denom > 0.00001) {
		tri_weights /= tri_denom;
	} else {
		// Perfectly vertical normal would yield 0/0; pick a stable fallback.
		tri_weights = vec3(0.5, 0.0, 0.5);
	}

	vec4 floor_color;
	vec3 wall_color;
	int ridge_ledge_idx = int(round(nearest_wall_color_idx));

	vec2 floor_uv = vec2(0.0);
	float out_roughness = 1.0;
	float out_wet_enabled = 0.0;
	int out_wet_mode = 0;

	if (is_floor) {
		vec2 floor_world_tile = cell_size * vec2(float(chunk_size.x - 1), float(chunk_size.z - 1));
		floor_uv = vec2(
			world_pos.x / max(floor_world_tile.x, 0.0001),
			world_pos.z / max(floor_world_tile.y, 0.0001)
		);
		int alpha_mat = 15;

		if (use_hard_textures) {
			if (blend_mode == 2) {
				out_roughness = _palette_roughness(material_index);
				out_wet_enabled = _palette_wet_enabled(material_index);
				out_wet_mode = _palette_wet_mode(material_index);
				alpha_mat = material_index;
				floor_color = sample_material_by_index(material_index, floor_uv);
			} else {
				int cell_dominant_mat = int(round(mat_indices.x));
				out_roughness = _palette_roughness(cell_dominant_mat);
				out_wet_enabled = _palette_wet_enabled(cell_dominant_mat);
				out_wet_mode = _palette_wet_mode(cell_dominant_mat);
				alpha_mat = cell_dominant_mat;
				floor_color = sample_material_by_index(cell_dominant_mat, floor_uv);
			}
		}
		else {
			int mat_a = int(round(mat_indices.x));
			int mat_b = int(round(mat_indices.y));
			int mat_c = int(round(mat_indices.z));

			float weight_a = max(0.0, mat_weights.x);
			float weight_b = max(0.0, mat_weights.y);
			float weight_c = max(0.0, 1.0 - weight_a - weight_b);

			float weight_sum = weight_a + weight_b + weight_c;
			if (weight_sum > 0.001) {
				weight_a /= weight_sum;
				weight_b /= weight_sum;
				weight_c /= weight_sum;
			}

			if (floor_blend_mode == 1) {
				// Noisy floor blending selects between the lowest-index material
				// present in the cell and the dominant alternative using world noise.
				int source_idx = -1;
				float source_w = 0.0;
				if (weight_a > 0.001) { source_idx = mat_a; source_w = weight_a; }
				if (weight_b > 0.001 && (source_idx < 0 || mat_b < source_idx)) { source_idx = mat_b; source_w = weight_b; }
				if (weight_c > 0.001 && (source_idx < 0 || mat_c < source_idx)) { source_idx = mat_c; source_w = weight_c; }

				int target_idx = mat_a;
				float target_w = weight_a;
				if (weight_b > target_w) { target_idx = mat_b; target_w = weight_b; }
				if (weight_c > target_w) { target_idx = mat_c; target_w = weight_c; }
				if (target_idx == source_idx) {
					if (mat_a != source_idx) {
						target_idx = mat_a;
					} else {
						target_idx = mat_b;
					}
				}

				float blend_noise = get_world_noise(vertex_pos.xyz, rl_noise_tile_size);
				float noise_variation = (blend_noise - 0.5) * rl_noise_strength;
				// When one side is textured and the other is color-only, raw source_w
				// isolines form concentric shells. Nudge selection with texture height.
				float select_w = source_w;
				bool src_tex = _mst_slot_has_texture(source_idx);
				bool tgt_tex = _mst_slot_has_texture(target_idx);
				if (src_tex != tgt_tex) {
					float h_tex = src_tex
						? _mst_slot_blend_height(source_idx, floor_uv)
						: _mst_slot_blend_height(target_idx, floor_uv);
					float height_term = (h_tex - 0.5) * (src_tex ? 0.45 : -0.45);
					select_w = clamp(source_w + height_term, 0.0, 1.0);
				}
				float select_source = step(blend_noise_threshold + noise_variation, select_w);
				int selected_idx = target_idx;
				if (select_source > 0.5) {
					selected_idx = source_idx;
				}
				floor_color = sample_material_by_index(selected_idx, floor_uv);
				out_roughness = _palette_roughness(selected_idx);
				out_wet_enabled = _palette_wet_enabled(selected_idx);
				out_wet_mode = _palette_wet_mode(selected_idx);
				alpha_mat = selected_idx;
			} else {
				if (blend_noise_strength > 0.0) {
				// Add a subtle waviness to material boundaries without disturbing solid interiors.
				float max_w = max(weight_a, max(weight_b, weight_c));
				float min_w = min(weight_a, min(weight_b, weight_c));
				float mid_w = (weight_a + weight_b + weight_c) - max_w - min_w;
				float top12_diff = max_w - mid_w; // ~0 on boundaries, ~1 when one material dominates
				float edge_factor = 1.0 - smoothstep(0.15, 0.55, top12_diff);

				float n = noise(world_pos.xz * blend_noise_scale);
				float noise_offset = (n - 0.5) * blend_noise_strength * edge_factor;
				weight_a = clamp(weight_a + noise_offset, 0.0, 1.0);
				weight_b = clamp(weight_b - noise_offset * 0.5, 0.0, 1.0);
				weight_c = clamp(weight_c - noise_offset * 0.5, 0.0, 1.0);
				float total = weight_a + weight_b + weight_c;
				if (total > 0.001) { weight_a /= total; weight_b /= total; weight_c /= total; }
				}

			// Always apply the response curve so 0.0 is the crispest endpoint
			// instead of accidentally bypassing sharpening and becoming softer again.
			float power = mix(5.0, 0.45, clamp(blend_sharpness, 0.0, 1.0));
			weight_a = pow(weight_a, power);
			weight_b = pow(weight_b, power);
			weight_c = pow(weight_c, power);
			float total = weight_a + weight_b + weight_c;
			if (total > 0.001) { weight_a /= total; weight_b /= total; weight_c /= total; }
			if (use_stylized_texture_edges) {
				vec3 styled_weights = stylized_texture_weights(vec3(weight_a, weight_b, weight_c));
				weight_a = styled_weights.x;
				weight_b = styled_weights.y;
				weight_c = styled_weights.z;
			}

			// Top materials for blending/alpha (uses possibly-jittered weights).
			int top1_idx = mat_a;
			int top2_idx = mat_b;
			float top1_w = weight_a;
			float top2_w = weight_b;
			if (top2_w > top1_w) {
				int ti = top1_idx; top1_idx = top2_idx; top2_idx = ti;
				float tw = top1_w; top1_w = top2_w; top2_w = tw;
			}
			if (weight_c > top1_w) {
				top2_idx = top1_idx;
				top2_w = top1_w;
				top1_idx = mat_c;
				top1_w = weight_c;
			} else if (weight_c > top2_w) {
				top2_idx = mat_c;
				top2_w = weight_c;
			}

			vec4 col_a = sample_material_by_index(mat_a, floor_uv);
			vec4 col_b = sample_material_by_index(mat_b, floor_uv);
			vec4 col_c = sample_material_by_index(mat_c, floor_uv);
			float height_a = _mst_slot_blend_height(mat_a, floor_uv);
			float height_b = _mst_slot_blend_height(mat_b, floor_uv);
			float height_c = _mst_slot_blend_height(mat_c, floor_uv);
			bool tex_a = _mst_slot_has_texture(mat_a);
			bool tex_b = _mst_slot_has_texture(mat_b);
			bool tex_c = _mst_slot_has_texture(mat_c);
			bool mixed_coverage = (
				(tex_a != tex_b && weight_a > 0.001 && weight_b > 0.001) ||
				(tex_a != tex_c && weight_a > 0.001 && weight_c > 0.001) ||
				(tex_b != tex_c && weight_b > 0.001 && weight_c > 0.001)
			);
			// Stronger depth when mixing a real texture into a flat color slot —
			// linear weight mixes expose visible contour rings otherwise.
			float height_depth = mix(0.16, 0.34, clamp(blend_sharpness, 0.0, 1.0));
			if (mixed_coverage) {
				height_depth = max(height_depth, mix(0.36, 0.55, clamp(blend_sharpness, 0.0, 1.0)));
			}
			floor_color = _mst_height_blend3(
				col_a, weight_a, height_a,
				col_b, weight_b, height_b,
				col_c, weight_c, height_c,
				height_depth
			);
			out_roughness = _palette_roughness(mat_a) * weight_a
						+ _palette_roughness(mat_b) * weight_b
						+ _palette_roughness(mat_c) * weight_c;
			out_wet_enabled = _palette_wet_enabled(top1_idx);
			out_wet_mode = _palette_wet_mode(top1_idx);
			alpha_mat = top1_idx;
			}
		}

		ALBEDO = floor_color.rgb;
		// Alpha is used as an occupancy mask (VOID slot 15).
		ALPHA = (alpha_mat == 15) ? 0.0 : 1.0;
	}
	else {
		int mat_a = int(round(mat_indices.x));
		int mat_b = int(round(mat_indices.y));
		int mat_c = int(round(mat_indices.z));

		float weight_a = max(0.0, mat_weights.x);
		float weight_b = max(0.0, mat_weights.y);
		float weight_c = max(0.0, 1.0 - weight_a - weight_b);

		float weight_sum = weight_a + weight_b + weight_c;
		if (weight_sum > 0.001) {
			weight_a /= weight_sum;
			weight_b /= weight_sum;
			weight_c /= weight_sum;
		}

		if (blend_noise_strength > 0.0) {
			// Add a subtle waviness to material boundaries without disturbing solid interiors.
			float max_w = max(weight_a, max(weight_b, weight_c));
			float min_w = min(weight_a, min(weight_b, weight_c));
			float mid_w = (weight_a + weight_b + weight_c) - max_w - min_w;
			float top12_diff = max_w - mid_w; // ~0 on boundaries, ~1 when one material dominates
			float edge_factor = 1.0 - smoothstep(0.15, 0.55, top12_diff);

			float n = noise(world_pos.xz * blend_noise_scale);
			float noise_offset = (n - 0.5) * blend_noise_strength * edge_factor;
			weight_a = clamp(weight_a + noise_offset, 0.0, 1.0);
			weight_b = clamp(weight_b - noise_offset * 0.5, 0.0, 1.0);
			weight_c = clamp(weight_c - noise_offset * 0.5, 0.0, 1.0);
			float total = weight_a + weight_b + weight_c;
			if (total > 0.001) { weight_a /= total; weight_b /= total; weight_c /= total; }
		}

		// Always apply the response curve so 0.0 is the crispest endpoint
		// instead of accidentally bypassing sharpening and becoming softer again.
		float power = mix(5.0, 0.45, clamp(blend_sharpness, 0.0, 1.0));
		weight_a = pow(weight_a, power);
		weight_b = pow(weight_b, power);
		weight_c = pow(weight_c, power);
		float total = weight_a + weight_b + weight_c;
		if (total > 0.001) { weight_a /= total; weight_b /= total; weight_c /= total; }

		out_roughness = _palette_roughness(mat_a) * weight_a
					+ _palette_roughness(mat_b) * weight_b
					+ _palette_roughness(mat_c) * weight_c;
		int dom_mat = mat_a;
		float dom_w = weight_a;
		if (weight_b > dom_w) { dom_w = weight_b; dom_mat = mat_b; }
		if (weight_c > dom_w) { dom_w = weight_c; dom_mat = mat_c; }
		out_wet_enabled = _palette_wet_enabled(dom_mat);
		out_wet_mode = _palette_wet_mode(dom_mat);

		vec4 wall_mat = sample_wall_material_by_index(mat_a) * weight_a
					+ sample_wall_material_by_index(mat_b) * weight_b
					+ sample_wall_material_by_index(mat_c) * weight_c;

		ALBEDO = wall_mat.rgb;
		ALPHA = wall_mat.a;
	}

	float blend_noise = get_world_noise(vertex_pos.xyz, rl_noise_tile_size);
	float mixed_blend_factor = 0.0;
	vec3 mixed_triplanar_color;
	if (use_ledge_texture && custom1.b > 0.5 && is_floor) {
		mixed_blend_factor = ledge_blend_factor.x;
		if (rl_noise_strength > 0.0) {
			float noise_variation = (blend_noise - 0.5) * rl_noise_strength;
			mixed_blend_factor = step(ledge_threshold + noise_variation, max(UV.x, UV.y));
		}
		vec3 rl_color = sample_material_by_index(ridge_ledge_idx, floor_uv).rgb;
		ALBEDO = mix(floor_color.rgb, rl_color, mixed_blend_factor);
		out_roughness = mix(out_roughness, _palette_roughness(ridge_ledge_idx), mixed_blend_factor);
		if (mixed_blend_factor > 0.5) {
			out_wet_enabled = _palette_wet_enabled(ridge_ledge_idx);
			out_wet_mode = _palette_wet_mode(ridge_ledge_idx);
		}
	}
	else if (use_ridge_texture && custom1.g > 0.5 && is_floor) {
		mixed_blend_factor = ridge_blend_factor.x;
		if (rl_noise_strength > 0.0) {
			float noise_variation = (blend_noise - 0.5) * rl_noise_strength;
			mixed_blend_factor = step(ridge_threshold + noise_variation, max(UV.x, UV.y));
		}
		vec3 rl_color = sample_material_by_index(ridge_ledge_idx, floor_uv).rgb;
		ALBEDO = mix(floor_color.rgb, rl_color, mixed_blend_factor);
		out_roughness = mix(out_roughness, _palette_roughness(ridge_ledge_idx), mixed_blend_factor);
		if (mixed_blend_factor > 0.5) {
			out_wet_enabled = _palette_wet_enabled(ridge_ledge_idx);
			out_wet_mode = _palette_wet_mode(ridge_ledge_idx);
		}
	}

	if (has_prefab_colormap) {
		vec4 prefab_col = texture(tex_prefab_colormap, UV);
		ALBEDO *= prefab_col.rgb;
		ALPHA *= prefab_col.a;
	}


	vec2 slot_noise = _mixed_noise_settings(is_floor);
	float slot_noise_strength = slot_noise.x;
	float slot_noise_scale = slot_noise.y;
	if (slot_noise_strength > 0.0) {
		// Scroll intentionally disabled: global noise is a static visual driver for
		// palette/texturing only.
		vec2 uv_floor = fract(world_pos.xz * slot_noise_scale);
		float gn_floor = texture(global_noise_texture, uv_floor).r;
		float gn_wall = _mst_sample_wall_global_noise(world_pos, vertex_normal, slot_noise_scale);
		float gn = is_floor ? gn_floor : gn_wall;

		// Centered multiplier: darkens and brightens around 1.0.
		float mult = mix(1.0 - slot_noise_strength, 1.0 + slot_noise_strength, clamp(gn, 0.0, 1.0));
		ALBEDO *= max(mult, 0.0);
	}

	// Wetness modes (per-slot). Uses slot roughness as the "wet" roughness target.
	float final_roughness = out_roughness;
	float wet_mask = 0.0;
	if (is_floor && out_wet_enabled > 0.5) {
		// Wetness is controlled by the wet toggle/mode; roughness is the *target* roughness when wet.
		float wet_amount = 1.0;

		// Use the detail noise (default white) as a consistent wetness breakup source.
		// NOTE: This is separate from the global noise tinting; it makes Wet/Puddles look less uniform.
		vec2 wet_uv = fract(world_pos.xz * wet_puddle_noise_scale);
		float wet_detail = texture(detail_normal_texture, wet_uv).r;
		float wet_variation = mix(0.55, 1.0, wet_detail);

		if (out_wet_mode == 0) {
			// Wet: darkening with variation (no puddle pooling).
			wet_mask = wet_amount * wet_variation;
		} else {
			// Glossy puddles: use a dedicated slower global-noise field so puddle placement
			// stays stable and seam-free instead of coming from procedural breakup.
			vec2 puddle_uv = fract(world_pos.xz * GLOSSY_PUDDLE_GLOBAL_NOISE_SCALE);
			float n = clamp(texture(global_noise_texture, puddle_uv).r * wet_variation, 0.0, 1.0);

			// Invert mask: pick "valleys" of the noise as puddles (often nicer shapes).
			n = 1.0 - n;

			// Softer threshold = more/smoother puddles.
			float t0 = wet_puddle_threshold - 0.18;
			float t1 = wet_puddle_threshold + 0.10;
			float puddle = smoothstep(t0, t1, n);
			wet_mask = wet_amount * puddle;
		}

		// Make it read more strongly in a stylized/pixel-art palette.
		float darken = (out_wet_mode == 1) ? 0.22 : 0.14;
		ALBEDO *= (1.0 - darken * clamp(wet_mask, 0.0, 1.0));

		// Make puddles reliably glossy (helps the effect read in toon/pixel art).
		float wet_target_roughness = (out_wet_mode == 1) ? min(out_roughness, 0.03) : out_roughness;
		final_roughness = mix(1.0, wet_target_roughness, clamp(wet_mask, 0.0, 1.0));
	} else if (is_floor) {
		// Toggle off: keep floors dry/matte.
		final_roughness = 1.0;
	}

	ROUGHNESS = clamp(final_roughness, 0.0, 1.0);
}

void light() {
	vec3 N = NORMAL;

	if (use_normal_array && normal_map_strength > 0.001) {
		bool is_floor = (UV.x < 1.5) && (dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold);
		vec2 normal_uv;
		if (is_floor) {
			vec2 floor_world_tile = cell_size * vec2(float(chunk_size.x - 1), float(chunk_size.z - 1));
			normal_uv = vec2(
				world_pos.x / max(floor_world_tile.x, 0.0001),
				world_pos.z / max(floor_world_tile.y, 0.0001)
			);
		} else {
			float wall_u_scale = max(cell_size.x * float(chunk_size.x - 1), 0.0001);
			float wall_v_scale = max(cell_size.x * float(chunk_size.y - 1), 0.0001);
			normal_uv = _mst_wall_strip_uv(world_pos, vertex_normal) / vec2(wall_u_scale, wall_v_scale);
		}

		vec3 nts = blend_slot_normals(normal_uv);
		nts = normalize(vec3(nts.xy * normal_map_strength, nts.z));
		vec3 n_local;
		if (is_floor) {
			n_local = normalize(vec3(nts.x, nts.z, nts.y));
		} else {
			n_local = _mst_tangent_normal_to_surface(nts, vertex_normal);
		}
		vec3 n_vs = normalize(mat3(VIEW_MATRIX) * n_local);
		N = n_vs;
	}

	// Optional detail normal to break up lighting on flat surfaces.
	if (detail_normal_strength > 0.001) {
		// Treat wall vertices explicitly via UV sentinel (walls use UV=(2,2)).
		bool is_floor = (UV.x < 1.5) && (dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold);

		vec3 abs_normal = abs(vertex_normal);
		vec3 tri_weights = vec3(abs_normal.x, 0.0, abs_normal.z);
		float denom = max(tri_weights.x + tri_weights.z, 0.00001);
		tri_weights /= denom;

		float dn = clamp(detail_normal_strength, 0.0, 1.0);
		float dn_bump = dn * 8.0;

		vec2 duv_floor = fract(world_pos.xz * detail_normal_scale);
		vec2 duv_x = fract(vec2(world_pos.z, world_pos.y) * detail_normal_scale);
		vec2 duv_z = fract(vec2(world_pos.x, world_pos.y) * detail_normal_scale);

		vec3 nts_floor = _mst_detail_height_to_ts(duv_floor, dn_bump);
		vec3 nts_x = _mst_detail_height_to_ts(duv_x, dn_bump);
		vec3 nts_z = _mst_detail_height_to_ts(duv_z, dn_bump);

		float sx = (vertex_normal.x >= 0.0) ? 1.0 : -1.0;
		float sz = (vertex_normal.z >= 0.0) ? 1.0 : -1.0;

		// Convert from tangent-space normal to a local-space normal for each projection plane.
		vec3 n_local_floor = normalize(vec3(nts_floor.x, nts_floor.z, nts_floor.y));
		vec3 n_local_x = normalize(vec3(sx * nts_x.z, nts_x.y, nts_x.x));
		vec3 n_local_z = normalize(vec3(nts_z.x, nts_z.y, sz * nts_z.z));

		vec3 n_local = is_floor ? n_local_floor : normalize(n_local_x * tri_weights.x + n_local_z * tri_weights.z);
		// Convert world-space normal to view-space (LIGHT/VIEW/NORMAL are in view-space here).
		vec3 n_vs = normalize((mat3(VIEW_MATRIX) * n_local));

		N = normalize(mix(NORMAL, n_vs, dn));
	}

	float NdotL = clamp(dot(N, LIGHT), 0.0, 1.0);
	float stepped = use_cell_shading ? (ceil(NdotL * float(bands)) / float(bands)) : NdotL;

	// Base toon weight (before attenuation).
	float toon_weight = use_cell_shading
		? mix(shadow_intensity, 0.3, stepped)
		: (NdotL * 0.3);

	float toon_light = clamp(toon_weight, 0.0, 1.0);
	vec3 direct_light = mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);
	DIFFUSE_LIGHT += direct_light * ATTENUATION;

	// Specular (needed so ROUGHNESS actually changes the look).
	// NOTE: On perfectly flat surfaces (no normal variation) spec can look very uniform.
	float r = clamp(ROUGHNESS, 0.0, 1.0);
	float gloss = 1.0 - r;
	// Treat low roughness as "wet" for highlight shaping.
	float wet = gloss;

	vec3 H = normalize(LIGHT + VIEW);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float shininess = mix(256.0, 12.0, r);
	// Wet/glossy surfaces need a broader highlight to read at low resolutions.
	shininess = mix(shininess, 32.0, wet);
	float spec = pow(NdotH, shininess) * NdotL;
	if (use_cell_shading) {
		// When wet/glossy, lower the threshold so highlights show up at low resolutions.
		float th = mix(specular_threshold, 0.08, wet);
		spec = smoothstep(th, 1.0, spec);
	}
	float wet_boost = mix(1.0, 6.0, wet);
	SPECULAR_LIGHT += LIGHT_COLOR.rgb * (specular_strength * wet_boost * spec * gloss) * ATTENUATION;

	// "Reflection-esque" wet sheen: a view-angle fresnel highlight that reads even on flat pixel-art terrain.
	float NdotV = clamp(dot(N, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - NdotV, 4.0);
	float sheen = wet * gloss * fres;
	SPECULAR_LIGHT += LIGHT_COLOR.rgb * (0.35 * sheen) * ATTENUATION;
}
