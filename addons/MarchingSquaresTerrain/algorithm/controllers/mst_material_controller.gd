extends RefCounted
class_name MSTMaterialController


var terrain


func _init(terrain_owner) -> void:
	terrain = terrain_owner


func direction_vector_from_degrees(degrees: float) -> Vector2:
	var radians := deg_to_rad(degrees)
	return Vector2(sin(radians), cos(radians)).normalized()


func direction_degrees_from_vector(direction: Vector2) -> float:
	if direction.length_squared() <= 0.000001:
		return 45.0
	var dir := direction.normalized()
	return wrapf(rad_to_deg(atan2(dir.x, dir.y)), 0.0, 360.0)


func apply_global_wind(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("wind_noise_texture", terrain.wind_noise_texture)
	material.set_shader_parameter("wind_direction_degrees", terrain.wind_direction_degrees)
	material.set_shader_parameter("wind_direction", terrain.wind_direction)
	material.set_shader_parameter("wind_speed", terrain.wind_speed)
	material.set_shader_parameter("wind_strength", terrain.wind_strength)
	material.set_shader_parameter("wind_scale", terrain.wind_scale)
	material.set_shader_parameter("wind_gust_strength", terrain.wind_gust_strength)
	material.set_shader_parameter("wind_gust_speed", terrain.wind_gust_speed)
	material.set_shader_parameter("wind_mode", terrain.wind_mode)
	material.set_shader_parameter("wind_tip_color", terrain.wind_tip_color)


func get_flower_planter_material(planter) -> ShaderMaterial:
	if planter == null:
		return null
	var mesh : Mesh = null
	if planter.get("flower_mesh") is Mesh:
		mesh = planter.flower_mesh as Mesh
	elif planter is MultiMeshInstance3D and planter.multimesh != null:
		mesh = planter.multimesh.mesh
	if mesh == null:
		return null
	if mesh is PrimitiveMesh and (mesh as PrimitiveMesh).material is ShaderMaterial:
		return (mesh as PrimitiveMesh).material as ShaderMaterial
	if mesh.get_surface_count() > 0:
		return mesh.surface_get_material(0) as ShaderMaterial
	return null


func apply_flower_wind_profile(material: ShaderMaterial) -> void:
	if material == null:
		return
	apply_global_wind(material)
	material.set_shader_parameter("fps", terrain.animation_fps)
	material.set_shader_parameter("animate_active", true)
	material.set_shader_parameter("flower_wind_strength", terrain.flower_wind_strength)
	material.set_shader_parameter("flower_stem_bend", terrain.flower_stem_bend)
	material.set_shader_parameter("flower_tip_flutter", terrain.flower_tip_flutter)


func sync_flower_wind_materials() -> void:
	if terrain == null:
		return
	for child in terrain.get_children():
		if not (child is MarchingSquaresFlowerPlanter):
			continue
		apply_flower_wind_profile(get_flower_planter_material(child))


func sync_wind_state(refresh_chunks: bool = true) -> void:
	apply_global_wind(terrain.terrain_material)
	if terrain.grass_mesh != null and terrain.grass_mesh.material is ShaderMaterial:
		apply_grass_wind_profile(terrain.grass_mesh.material as ShaderMaterial)
	for chunk in terrain.chunks.values():
		if chunk == null or not is_instance_valid(chunk) or chunk.grass_planter == null:
			continue
		var multimesh: MultiMesh = chunk.grass_planter.multimesh
		if multimesh != null and multimesh.mesh != null and multimesh.mesh.material is ShaderMaterial:
			apply_grass_wind_profile(multimesh.mesh.material as ShaderMaterial)
	sync_flower_wind_materials()
	if refresh_chunks and terrain.is_inside_tree():
		terrain.refresh_chunk_surface_materials()


func apply_grass_wind_profile(material: ShaderMaterial) -> void:
	if material == null:
		return
	apply_global_wind(material)
	material.set_shader_parameter("fps", terrain.animation_fps)
	material.set_shader_parameter("animate_active", true)


func sync_global_noise_to_grass() -> void:
	if terrain.grass_mesh == null or terrain.terrain_material == null:
		return
	var grass_mat := terrain.grass_mesh.material as ShaderMaterial
	if grass_mat == null:
		return
	grass_mat.set_shader_parameter("global_noise_texture", terrain.global_noise_texture)
	grass_mat.set_shader_parameter("chunk_size", terrain.dimensions)
	grass_mat.set_shader_parameter("cell_size", terrain.cell_size)
	grass_mat.set_shader_parameter("blade_variation", terrain.grass_random_scale)
	apply_grass_wind_profile(grass_mat)
	grass_mat.set_shader_parameter("vc_floor_tex_array", terrain._runtime_texture_array)
	grass_mat.set_shader_parameter("use_floor_tex_array", terrain._runtime_texture_array != null)
	for parameter_name in ["global_noise_scale", "global_noise_strength", "global_noise_scroll"]:
		var value = terrain.terrain_material.get_shader_parameter(parameter_name)
		if value != null:
			grass_mat.set_shader_parameter(parameter_name, value)
	apply_grass_wind_profile(grass_mat)
	sync_prefab_material_state()


func sync_prefab_material_state() -> void:
	var has_map := terrain.prefab_set != null and terrain.prefab_set.color_map != null
	var color_map : Texture2D = terrain.prefab_set.color_map if has_map else null
	if terrain.terrain_material != null:
		terrain.terrain_material.set_shader_parameter("tex_prefab_colormap", color_map)
		terrain.terrain_material.set_shader_parameter("has_prefab_colormap", has_map)
	if terrain.grass_mesh != null and terrain.grass_mesh.material is ShaderMaterial:
		var grass_mat := terrain.grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("tex_prefab_colormap", color_map)
		grass_mat.set_shader_parameter("has_prefab_colormap", has_map)
