shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque, cull_disabled;

group_uniforms Albedo;
uniform sampler2D flower_texture : source_color, filter_nearest;
uniform bool should_billboard = false;
group_uniforms;

group_uniforms RNG;
uniform float rng_height_range : hint_range(0.0, 2.0, 0.1) = 0.1;
uniform float rng_size_range : hint_range(0.0, 1.0, 0.1) = 0.2;
group_uniforms;

group_uniforms Shading;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.0;
group_uniforms;

group_uniforms Visibility;
uniform float visibility_end_distance : hint_range(0.0, 10000.0, 1.0) = 0.0;
uniform float visibility_fade_margin : hint_range(0.0, 1000.0, 1.0) = 0.0;
group_uniforms;

group_uniforms Animations.Settings;
uniform bool animate_active = true;
uniform float fps : hint_range(0.0, 30.0, 1.0) = 0.0;
group_uniforms;

group_uniforms Animations.Flower_Profile;
// Flower-only response on top of the shared global wind source.
uniform float flower_wind_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float flower_stem_bend : hint_range(1.0, 2.5, 0.01) = 1.35;
uniform float flower_tip_flutter : hint_range(0.0, 1.0, 0.01) = 0.2;
group_uniforms;

#include "mst_global_wind.gdshaderinc"

varying vec3 model_origin;
varying vec4 instance_color;
varying vec3 light_vertex_position;
varying float instance_visibility;

float randf_from_id(float id) {
	return fract(sin(id * 12.9898) * 43758.5453);
}

void vertex() {
	float rand_factor = randf_from_id(float(INSTANCE_ID));

	if (rng_height_range > 0.0) {
		float y_offset = rand_factor * rng_height_range;
		VERTEX.y += y_offset;
	}
	if (rng_size_range > 0.0) {
		float size_factor = 1.0 + (rand_factor * 2.0 - 1.0) * rng_size_range * 0.5;
		if (!should_billboard)
			VERTEX.xz *= size_factor;
		else
			VERTEX.xy *= size_factor;
	}

	float rand_angle = rand_factor * TAU;
	float s = sin(rand_angle);
	float c = cos(rand_angle);
	if (!should_billboard) {
		mat2 rand_rot = mat2(vec2(c, -s), vec2(s, c));
		VERTEX.xz *= rand_rot;
	}

	vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	instance_visibility = 1.0;
	if (visibility_end_distance > 0.0) {
		float camera_distance = distance(CAMERA_POSITION_WORLD, instance_origin);
		if (visibility_fade_margin > 0.0) {
			float fade_start = max(visibility_end_distance - visibility_fade_margin, 0.0);
			instance_visibility = 1.0 - smoothstep(fade_start, visibility_end_distance, camera_distance);
		} else {
			instance_visibility = camera_distance <= visibility_end_distance ? 1.0 : 0.0;
		}
	}
	vec3 wind_world_offset = vec3(0.0);

	// Animation FPS steps the shared wind sample clock. 0 = no frames / no motion.
	// Flower profile: stronger tip lean (stem-like) with modest tip flutter.
	if (animate_active && VERTEX.y > 0.0 && fps > 0.0) {
		float bend_linear = clamp(VERTEX.y, 0.0, 1.0);
		float stem_power = clamp(flower_stem_bend, 1.0, 2.5);
		float tip_weight = pow(bend_linear, stem_power);
		float body_weight = tip_weight * tip_weight;
		float seed = fract(sin(float(INSTANCE_ID) * 91.137 + instance_origin.x * 17.0 + instance_origin.z * 7.0) * 43758.5453);
		float stepped_time = floor((TIME + seed) * fps) / fps;
		vec2 wind_vec = mst_sample_wind_vector_at_time(instance_origin.xz, seed, stepped_time);
		float wind_amount = length(wind_vec) * max(flower_wind_strength, 0.0);
		vec2 wind_dir = (wind_amount > 0.0001) ? (wind_vec / max(length(wind_vec), 0.0001)) : vec2(0.0, 0.0);
		vec2 cross_dir = vec2(-wind_dir.y, wind_dir.x);
		float flutter = sin(
			stepped_time * (max(wind_speed, 0.001) * 2.4 + 0.6) +
			seed * 6.28318 +
			bend_linear * 2.2
		);
		float sway_strength = 0.28;
		float forward_push = wind_amount * (body_weight * 0.12 + tip_weight * 0.55);
		float side_sway = flutter * wind_amount * tip_weight * flower_tip_flutter * 0.22;
		float downward_drag = wind_amount * tip_weight * 0.08;
		wind_world_offset =
			vec3(wind_dir.x, 0.0, wind_dir.y) * forward_push * sway_strength +
			vec3(cross_dir.x, 0.0, cross_dir.y) * side_sway * sway_strength;
		wind_world_offset.y -= downward_drag * sway_strength;
	}

	// Billboarding: this needs to happen AFTER other animations
	if (should_billboard) {
		vec3 cam_z = normalize(CAMERA_DIRECTION_WORLD);
		vec3 cam_y = vec3(0.0, 1.0, 0.0);
		vec3 cam_x = cross(cam_y, cam_z);
		if (length(cam_x) < 0.001) {
			cam_x = vec3(1.0, 0.0, 0.0);
		}
		cam_x = normalize(cam_x);
		cam_y = normalize(cross(cam_z, cam_x));
		mat3 spherical_billboard = mat3(cam_x, cam_y, cam_z);

		vec3 billboarded_vertex = spherical_billboard * VERTEX;
		vec3 world_position = instance_origin + billboarded_vertex + wind_world_offset;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);
	}
	else {
		vec3 world_vertex =
			MODEL_MATRIX[0].xyz * VERTEX.z +
			MODEL_MATRIX[1].xyz * -VERTEX.x +
			MODEL_MATRIX[2].xyz * VERTEX.y;

		vec3 world_position = instance_origin + world_vertex + wind_world_offset;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);
		NORMAL = normalize(
			MODEL_MATRIX[0].xyz * NORMAL.z +
			MODEL_MATRIX[1].xyz * NORMAL.x +
			MODEL_MATRIX[2].xyz * NORMAL.y
		);
		light_vertex_position = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;
	}

	model_origin = (MODELVIEW_MATRIX * vec4(0.,0.,0.,1.)).xyz;
	instance_color = INSTANCE_CUSTOM;
	if (instance_visibility <= 0.001) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec4 flower_tex = texture(flower_texture, UV);
	vec3 flower_color = flower_tex.rgb * instance_color.rgb;

	ALBEDO = flower_color;
	ALPHA = flower_tex.a * instance_color.a * instance_visibility;

	if (ALPHA < 0.1) discard;

	if (should_billboard)
		LIGHT_VERTEX = model_origin;
	else
		LIGHT_VERTEX = light_vertex_position;
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
