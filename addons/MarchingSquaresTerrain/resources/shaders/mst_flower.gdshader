shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque;


group_uniforms Albedo;
uniform sampler2D flower_texture : source_color, filter_nearest;
uniform bool use_custom_color = false;
uniform bool should_billboard = true;
group_uniforms;

group_uniforms Shading;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.0;
group_uniforms;

varying vec3 model_origin;
varying vec3 instance_color;

void vertex() {
	// Add wind animations that connec to the grass fps here!!!

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
	
	model_origin = (MODELVIEW_MATRIX * vec4(0.,0.,0.,1.)).xyz;
	instance_color = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec4 flower_tex = texture(flower_texture, UV);
	vec3 flower_color = use_custom_color ? flower_tex.rgb * instance_color : flower_tex.rgb;
	
	ALBEDO = flower_color;
	ALPHA = flower_tex.a;
	
	if (ALPHA < 0.1) discard;
	
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
