shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque, cull_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms CellShading;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.0;
group_uniforms;

void fragment() {
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = albedo_tex.rgb;
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