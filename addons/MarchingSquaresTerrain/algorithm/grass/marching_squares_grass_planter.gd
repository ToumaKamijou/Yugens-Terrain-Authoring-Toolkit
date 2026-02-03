@icon("res://addons/MarchingSquaresTerrain/editor/icons/3D_planters_icon.png")
@tool
extends MultiMeshInstance3D
class_name MarchingSquaresGrassPlanter


var _chunk : MarchingSquaresTerrainChunk
var terrain_system : MarchingSquaresTerrain


func setup(chunk: MarchingSquaresTerrainChunk, redo: bool = true):
	_chunk = chunk
	terrain_system = _chunk.terrain_system
	
	if not _chunk or not terrain_system:
		printerr("ERROR: SETUP FAILED - no chunk or terrain system found for GrassPlanter")
		return
	
	if (redo and multimesh) or not multimesh:
		multimesh = MultiMesh.new()
	multimesh.instance_count = 0
	
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.instance_count = (_chunk.dimensions.x-1) * (_chunk.dimensions.z-1) * terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	if terrain_system.grass_mesh:
		multimesh.mesh = terrain_system.grass_mesh
	else:
		multimesh.mesh = QuadMesh.new() # Create a temporary quad
	multimesh.mesh.size = terrain_system.grass_size
	
	cast_shadow = SHADOW_CASTING_SETTING_OFF


func regenerate_all_cells() -> void:
	# Safety checks:
	if not _chunk:
		printerr("ERROR: _chunk not set while regenerating cells")
		return
	
	if not terrain_system:
		printerr("ERROR: terrain_system not set while regenerating cells")
		return
	
	if not multimesh:
		setup(_chunk)
	
	if not _chunk.cell_geometry:
		_chunk.regenerate_mesh()
	
	for z in range(terrain_system.dimensions.z-1):
		for x in range(terrain_system.dimensions.x-1):
			generate_grass_on_cell(Vector2i(x, z))


func generate_grass_on_cell(cell_coords: Vector2i) -> void:
	# Safety checks:
	if not _chunk:
		printerr("ERROR: MarchingSquaresGrassPlanter couldn't find a reference to _chunk")
		return
	
	if not terrain_system:
		printerr("ERROR: MarchingSquaresGrassPlanter couldn't find a reference to terrain_system")
		return
	
	if not _chunk.cell_geometry:
		printerr("ERROR: MarchingSquaresGrassPlanter couldn't find a reference to cell_geometry")
		return
	
	if not _chunk.cell_geometry.has(cell_coords):
		printerr("ERROR: MarchingSquaresGrassPlanter couldn't find a reference to cell_coords")
		return
	
	var cell_geometry = _chunk.cell_geometry[cell_coords]
	
	if not cell_geometry.has("verts") or not cell_geometry.has("uvs") or not cell_geometry.has("colors_0") or not cell_geometry.has("colors_1") or not cell_geometry.has("grass_mask") or not cell_geometry.has("is_floor"):
		printerr("ERROR: [MarchingSquaresGrassPlanter] cell_geometry doesn't have one of the following required data: 1) verts, 2) uvs, 3) colors, 4) grass_mask, 5) is_floor")
		return
	
	var points: PackedVector2Array = []
	var count = terrain_system.grass_subdivisions * terrain_system.grass_subdivisions
	
	for z in range(terrain_system.grass_subdivisions):
		for x in range(terrain_system.grass_subdivisions):
			points.append(Vector2(
				(cell_coords.x + (x + randf_range(0, 1)) / terrain_system.grass_subdivisions) * terrain_system.cell_size.x,
				(cell_coords.y + (z + randf_range(0, 1)) / terrain_system.grass_subdivisions) * terrain_system.cell_size.y
			))
	
	var index: int = (cell_coords.y * (_chunk.dimensions.x-1) + cell_coords.x) * count
	var end_index: int = index + count
	
	var verts: PackedVector3Array = cell_geometry["verts"]
	var uvs: PackedVector2Array = cell_geometry["uvs"]
	var colors_0: PackedColorArray = cell_geometry["colors_0"]
	var colors_1: PackedColorArray = cell_geometry["colors_1"]
	var grass_mask: PackedColorArray = cell_geometry["grass_mask"]
	var is_floor: Array = cell_geometry["is_floor"]
	
	for i in range(0, len(verts), 3):
		if i+2 >= len(verts):
			continue # skip incomplete triangle
		# only place grass on floors
		if not is_floor[i]:
			continue
		
		var a := verts[i]
		var b := verts[i+1]
		var c := verts[i+2]
		
		var v0 := Vector2(c.x - a.x, c.z - a.z)
		var v1 := Vector2(b.x - a.x, b.z - a.z)
		
		var dot00 := v0.dot(v0)
		var dot01 := v0.dot(v1)
		var dot11 := v1.dot(v1)
		var invDenom := 1.0/(dot00 * dot11 - dot01 * dot01)
		
		var point_index := 0
		while (point_index < len(points)):
			var v2 = Vector2(points[point_index].x - a.x, points[point_index].y - a.z)
			var dot02 := v0.dot(v2)
			var dot12 := v1.dot(v2)
			
			var u := (dot11 * dot02 - dot01 * dot12) * invDenom
			if u < 0:
				point_index += 1
				continue
			
			var v := (dot00 * dot12 - dot01 * dot02) * invDenom
			if v < 0:
				point_index += 1
				continue
			
			if u + v <= 1:
				# Point is inside triangle, won't be inside any other floor triangle
				points.remove_at(point_index)
				var p = a*(1-u-v) + b*u + c*v
				
				# Don't place grass on ledges
				var uv = uvs[i]*u + uvs[i+1]*v + uvs[i+2]*(1-u-v)
				var on_ledge: bool = uv.x > 1-_chunk.terrain_system.ledge_threshold or uv.y > 1-_chunk.terrain_system.ridge_threshold
				
				var color_0 = _chunk.get_dominant_color(colors_0[i]*u + colors_0[i+1]*v + colors_0[i+2]*(1-u-v))
				var color_1 = _chunk.get_dominant_color(colors_1[i]*u + colors_1[i+1]*v + colors_1[i+2]*(1-u-v))
				
				# Check grass mask first - green channel forces grass ON, red channel masks grass OFF
				var mask = grass_mask[i]*u + grass_mask[i+1]*v + grass_mask[i+2]*(1-u-v)
				var is_masked: bool = mask.r < 0.9999
				var force_grass_on: bool = mask.g >= 0.9999  # Preset override: force grass regardless of texture
				
				var on_grass_tex: bool = false
				var texture_id := _get_texture_id(color_0, color_1)
				
				if force_grass_on:
					# Preset has_grass=true overrides texture setting
					on_grass_tex = true
				elif texture_id == 1: # Base grass
					on_grass_tex = true
				elif texture_id >= 2 and texture_id <= 6:
					var has_grass : bool = false
					match texture_id:
						2:
							if terrain_system.tex2_has_grass:
								has_grass = true
						3:
							if terrain_system.tex3_has_grass:
								has_grass = true
						4:
							if terrain_system.tex4_has_grass:
								has_grass = true
						5:
							if terrain_system.tex5_has_grass:
								has_grass = true
						6:
							if terrain_system.tex6_has_grass:
								has_grass = true
					if has_grass:
						on_grass_tex = true
					else:
						on_grass_tex = false
				else:
					on_grass_tex = false
				
				if on_grass_tex and not on_ledge and not is_masked:
					var edge1 = b - a
					var edge2 = c - a
					var normal = edge1.cross(edge2).normalized()
					
					var right = Vector3.FORWARD.cross(normal).normalized()
					var forward = normal.cross(Vector3.RIGHT).normalized()
					
					var instance_basis = Basis(right, forward, -normal)
					
					multimesh.set_instance_transform(index, Transform3D(instance_basis, p))
					
					var has_tex : bool = false
					var material = terrain_system.terrain_material
					var tex_scale : float = terrain_system.texture_scale_1
					match texture_id:
						2:
							has_tex = true if material.get_shader_parameter("vc_tex_rg") != null else false
							tex_scale = terrain_system.texture_scale_2
						3:
							has_tex = true if material.get_shader_parameter("vc_tex_rb") != null else false
							tex_scale = terrain_system.texture_scale_3
						4:
							has_tex = true if material.get_shader_parameter("vc_tex_ra") != null else false
							tex_scale = terrain_system.texture_scale_4
						5:
							has_tex = true if material.get_shader_parameter("vc_tex_gr") != null else false
							tex_scale = terrain_system.texture_scale_5
						6:
							has_tex = true if material.get_shader_parameter("vc_tex_gg") != null else false
							tex_scale = terrain_system.texture_scale_6
						_: # Base grass
							has_tex = true if material.get_shader_parameter("vc_tex_rr") != null else false
					var terrain_image = null
					if has_tex:
						terrain_image = _get_terrain_image(texture_id)
					
					var instance_color : Color
					if terrain_image:
						var uv_x = clamp(p.x / (terrain_system.dimensions.x * terrain_system.cell_size.x), 0.0, 1.0)
						var uv_y = clamp(p.z / (terrain_system.dimensions.z * terrain_system.cell_size.y), 0.0, 1.0)
						
						uv_x *= tex_scale
						uv_y *= tex_scale
						
						uv_x = abs(fmod(uv_x, 1.0))
						uv_y = abs(fmod(uv_y, 1.0))
						
						var px = int(uv_x * (terrain_image.get_width() - 1))
						var py = int(uv_y * (terrain_image.get_height() - 1))
						
						instance_color = terrain_image.get_pixelv(Vector2(px, py))
					match texture_id:
						6:
							instance_color.a = 1.0
						5:
							instance_color.a = 0.8
						4:
							instance_color.a = 0.6
						3:
							instance_color.a = 0.4
						2:
							instance_color.a = 0.2
						_: # Base grass sprite
							instance_color.a = 0.0
					multimesh.set_instance_custom_data(index, instance_color)
				else:
					multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(9999, 9999, 9999)))
				index += 1
			else:
				point_index += 1
	
	# Fill remaining points with zero-sacaled transforms (invisible)
	while index < end_index:
		if index >= multimesh.instance_count:
			return
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(9999, 9999, 9999)))
		index += 1


func _get_terrain_image(texture_id: int) -> Image:
	var terrain_texture : Texture2D = null
	var material = terrain_system.terrain_material
	match texture_id:
		2:
			terrain_texture = material.get_shader_parameter("vc_tex_rg")
		3:
			terrain_texture = material.get_shader_parameter("vc_tex_rb")
		4:
			terrain_texture = material.get_shader_parameter("vc_tex_ra")
		5:
			terrain_texture = material.get_shader_parameter("vc_tex_gr")
		6:
			terrain_texture = material.get_shader_parameter("vc_tex_gg")
		_: # Base grass
			terrain_texture = material.get_shader_parameter("vc_tex_rr")
	if terrain_texture == null:
		printerr("ERROR: [MarchingSquaresGrassPlanter] couldn't find the terrain's ShaderMaterial texture " + str(texture_id))
		return null
	
	var img : Image = terrain_texture.get_image()
	img.decompress()
	return img


func _get_texture_id(vc_col_0: Color, vc_col_1: Color) -> int:
	var id : int = 1;
	if vc_col_0.r > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 1;
		elif vc_col_1.g > 0.9999:
			id = 2;
		elif vc_col_1.b > 0.9999:
			id = 3;
		elif vc_col_1.a > 0.9999:
			id = 4;
	elif vc_col_0.g > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 5;
		elif vc_col_1.g > 0.9999:
			id = 6;
		elif vc_col_1.b > 0.9999:
			id = 7;
		elif vc_col_1.a > 0.9999:
			id = 8;
	elif vc_col_0.b > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 9;
		elif vc_col_1.g > 0.9999:
			id = 10;
		elif vc_col_1.b > 0.9999:
			id = 11;
		elif vc_col_1.a > 0.9999:
			id = 12;
	elif vc_col_0.a > 0.9999:
		if vc_col_1.r > 0.9999:
			id = 13;
		elif vc_col_1.g > 0.9999:
			id = 14;
		elif vc_col_1.b > 0.9999:
			id = 15;
		elif vc_col_1.a > 0.9999:
			id = 16;
	return id;
