shader_type spatial;


group_uniforms Albedo;
uniform sampler2D flower_texture : source_color, filter_nearest;
uniform bool use_custom_color = false;
group_uniforms;


void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
