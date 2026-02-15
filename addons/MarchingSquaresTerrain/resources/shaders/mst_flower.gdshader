shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque;

group_uniforms Albedo;
uniform sampler2D flower_texture : source_color, filter_nearest;
uniform bool use_custom_color = true;
uniform bool should_billboard = true;
group_uniforms;

group_uniforms Shading;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.0;
group_uniforms;

group_uniforms Animations.Settings;
uniform bool animate_active = true;
uniform float fps : hint_range(0.0, 30.0, 1.0)= 0.0;
group_uniforms;

group_uniforms Animations.Wind;
uniform sampler2D wind_texture : source_color;
uniform vec2 wind_direction = vec2(1.0, 1.0);
uniform float wind_scale = 0.02;
uniform float wind_speed = 0.15;
group_uniforms;

varying vec3 model_origin;
varying vec3 instance_color;

float randf_from_id(float id) {
	return fract(sin(id * 12.9898) * 43758.5453);
}

void vertex() {
	if (animate_active && VERTEX.y > 0.0) {
		float left_to_right_mult = 0.2;
		// Individual sprite movement animations
		if (fps > 0.0) {
			float seed = dot(vec2(VERTEX.xz), vec2(12.9898, 78.233)) + float(INSTANCE_ID);
			float time_offset = fract(sin(seed) * 43758.5453);
			float quantized_time = floor(TIME * fps * time_offset) / fps;

			float sway = sin(quantized_time) * left_to_right_mult;

			VERTEX.x += sway;
		}
		else {
			// Wind animations (make sure you apply a texture in the shader parameters)
			float wind_time = TIME * wind_speed;
			vec2 scroll = wind_time * wind_direction;

			vec3 world_pos = MODEL_MATRIX[3].xyz;
			vec2 wind_uv = (world_pos.xy * wind_scale) + scroll;

			float wind_value = texture(wind_texture, wind_uv).r;

			float wind = wind_value * left_to_right_mult;

			float bend_factor = clamp(VERTEX.y, 0.0, 1.0);
			VERTEX += vec3(wind, 0.0, 0.0) * bend_factor;
		}
	}
	// Billboarding: this needs to happen AFTER other animations
	if (should_billboard) {
		vec3 cam_z = normalize(CAMERA_DIRECTION_WORLD);
		vec3 cam_y = vec3(0.0, 1.0, 0.0);
		vec3 cam_x = normalize(cross(cam_y, cam_z));
		mat3 spherical_billboard = mat3(cam_x, cam_y, cam_z);

		vec3 billboarded_vertex = spherical_billboard * VERTEX;

		vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec3 world_position = instance_origin + billboarded_vertex;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);
	}
	else {
		float rand_angle = randf_from_id(float(INSTANCE_ID)) * TAU;
		float s = sin(rand_angle);
		float c = cos(rand_angle);
		mat2 rand_rot = mat2(vec2(c, -s), vec2(s,  c));
		VERTEX.xz *= rand_rot;
		
		vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(instance_origin + VERTEX, 1.0);
	}
	
	model_origin = (MODELVIEW_MATRIX * vec4(0.,0.,0.,1.)).xyz;
	instance_color = INSTANCE_CUSTOM.rgb;
	if (should_billboard == false)
		instance_color *= 5.0;
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec4 flower_tex = texture(flower_texture, UV);
	vec3 flower_color = use_custom_color ? flower_tex.rgb * instance_color : flower_tex.rgb;
	
	ALBEDO = flower_color;
	ALPHA = flower_tex.a;
	
	if (ALPHA < 0.1) discard;
	
	if (should_billboard)
		LIGHT_VERTEX = model_origin;
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
