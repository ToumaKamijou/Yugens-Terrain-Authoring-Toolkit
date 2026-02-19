@tool
extends Node
class_name MarchingSquaresGeometryBaker


signal finished(mesh: Mesh, original: MeshInstance3D, img: Image)

@export var polygon_texture_resolution := 32
	
func bake_geometry_texture(inst: MeshInstance3D, scene_tree: SceneTree) -> void:
	if not inst or not scene_tree or not inst.mesh is ArrayMesh:
		return
	var mesh: ArrayMesh = inst.mesh
	var new_mesh = ArrayMesh.new()
	
	var arrays := mesh.surface_get_arrays(0)

	var verts : PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices : PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals : PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var c0 : PackedColorArray = _to_color_array(arrays[Mesh.ARRAY_CUSTOM0])
	var c1 : PackedColorArray = _to_color_array(arrays[Mesh.ARRAY_CUSTOM1])
	var c2 : PackedColorArray = _to_color_array(arrays[Mesh.ARRAY_CUSTOM2])
	var cols : PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs : PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2s : PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	
	var new_uvs := PackedVector2Array()
	var new_verts := PackedVector3Array()
	
	var orig_verts := PackedVector3Array()
	
	var bake_verts := PackedVector3Array()
	var bake_indices := PackedInt32Array()
	var bake_uvs := PackedVector2Array()
	var bake_uv2s := PackedVector2Array()
	var bake_normals := PackedVector3Array()
	var bake_cols := PackedColorArray()
	var bake_c0 := PackedColorArray()
	var bake_c1 := PackedColorArray()
	var bake_c2 := PackedColorArray()
	
	var outset_verts := PackedVector3Array()
	
	var tri_id := 0
	
	@warning_ignore_start("integer_division")
	var atlas_res := int(pow(2, ceil(log(polygon_texture_resolution) / log(2)))) # next power of two
	var tris_per_row := (atlas_res / polygon_texture_resolution) * 2
	
	
	var num_of_triangles := indices.size()/3
	var max_texture_size := RenderingServer.get_rendering_device().limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D)
	while tris_per_row * tris_per_row/2 < num_of_triangles:
		atlas_res *= 2
		tris_per_row = atlas_res / polygon_texture_resolution * 2
	if atlas_res > max_texture_size:
		push_error("Unable to bake into atlas with polygon size of ", polygon_texture_resolution, "px: exceeds GPU texture size limits")
		return
	var quads_per_row := tris_per_row / 2
	
	for i in range(0, indices.size(), 3):
		var idx0 = indices[i]
		var idx1 = indices[i + 1]
		var idx2 = indices[i + 2]

		var row := tri_id / tris_per_row
		var col := (tri_id / 2) % (tris_per_row / 2)

		var base_vert := Vector2(col, row)

		var v0 : Vector2
		var v1 : Vector2
		var v2 : Vector2

		if tri_id % 2 == 0:
			# Pack triangle into square cell
			v0 = (base_vert + Vector2(0, 0)) / quads_per_row
			v1 = (base_vert + Vector2(1, 0)) / quads_per_row
			v2 = (base_vert + Vector2(0, 1)) / quads_per_row
		else:
			v0 = (base_vert + Vector2(1, 0)) / quads_per_row
			v1 = (base_vert + Vector2(1, 1)) / quads_per_row
			v2 = (base_vert + Vector2(0, 1)) / quads_per_row
			
		new_verts.append(verts[idx0])
		new_verts.append(verts[idx1])
		new_verts.append(verts[idx2])
		
		# calculate inset triangle to prevent texture bleeding
		var scale := (polygon_texture_resolution - 4.0) / polygon_texture_resolution
		var center := Vector2( (v0.x + v1.x + v2.x)/3.0, (v0.y + v1.y + v2.y)/3.0 )
		var vi0 := center + scale*(v0-center)
		var vi1 := center + scale*(v1-center)
		var vi2 := center + scale*(v2-center)
		
		new_uvs.append(vi0)
		new_uvs.append(vi1)
		new_uvs.append(vi2)
		
		orig_verts.append(verts[idx0])
		orig_verts.append(verts[idx1])
		orig_verts.append(verts[idx2])
		
		bake_uvs.append(uvs[idx0])
		bake_uvs.append(uvs[idx1])
		bake_uvs.append(uvs[idx2])
		
		bake_normals.append(normals[idx0])
		bake_normals.append(normals[idx1])
		bake_normals.append(normals[idx2])
			
		bake_verts.append(Vector3(vi0.x, vi0.y, 0))
		bake_verts.append(Vector3(vi1.x, vi1.y, 0))
		bake_verts.append(Vector3(vi2.x, vi2.y, 0))
		
		outset_verts.append(Vector3(v0.x, v0.y, 0))
		outset_verts.append(Vector3(v1.x, v1.y, 0))
		outset_verts.append(Vector3(v2.x, v2.y, 0))
		
		bake_uv2s.append(uv2s[idx0])
		bake_uv2s.append(uv2s[idx1])
		bake_uv2s.append(uv2s[idx2])
		
		bake_cols.append(cols[idx0])
		bake_cols.append(cols[idx1])
		bake_cols.append(cols[idx2])
		
		bake_c0.append(c0[idx0])
		bake_c0.append(c0[idx1])
		bake_c0.append(c0[idx2])
		
		bake_c1.append(c1[idx0])
		bake_c1.append(c1[idx1])
		bake_c1.append(c1[idx2])
		
		bake_c2.append(c2[idx0])
		bake_c2.append(c2[idx1])
		bake_c2.append(c2[idx2])
		
		bake_indices.append(i + 0)
		bake_indices.append(i + 1)
		bake_indices.append(i + 2)
		
		tri_id += 1
		
	var new_arrays = []
	new_arrays.resize(Mesh.ARRAY_MAX)
	
	new_arrays[Mesh.ARRAY_INDEX] = bake_indices
	new_arrays[Mesh.ARRAY_VERTEX] = new_verts
	new_arrays[Mesh.ARRAY_TEX_UV] = new_uvs
	new_arrays[Mesh.ARRAY_NORMAL] = bake_normals
	
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays, [], {}, Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_COLOR)

	# at this point we have the inset triangles, they will contain the actual color data
	# to prevent texture bleeding when we bake the texture we add a quad on each of their 
	# sides to serve as a border the colors and UVs match those of the rims of the triangle
	var s := bake_indices.size()
	for i in range(0,s,3):
		bake_indices.append(i)
		bake_indices.append(i+1+s)
		bake_indices.append(i+1)
		bake_indices.append(i)
		bake_indices.append(i+s)
		bake_indices.append(i+1+s)
		
		bake_indices.append(i+1)
		bake_indices.append(i+2+s)
		bake_indices.append(i+2)
		bake_indices.append(i+1)
		bake_indices.append(i+1+s)
		bake_indices.append(i+2+s)
		
		bake_indices.append(i)
		bake_indices.append(i+2)
		bake_indices.append(i+2+s)
		bake_indices.append(i)
		bake_indices.append(i+2+s)
		bake_indices.append(i+s)
	
	bake_verts.append_array(outset_verts)
	bake_uvs.append_array(bake_uvs)
	bake_uv2s.append_array(bake_uv2s)
	bake_normals.append_array(bake_normals)
	bake_cols.append_array(bake_cols)
	bake_c0.append_array(bake_c0)
	bake_c1.append_array(bake_c1)
	bake_c2.append_array(bake_c2)
	var bake_c3 := _pack_verts_to_float_array(orig_verts)
	bake_c3.append_array(bake_c3)
	
	
	var viewport := SubViewport.new()
	viewport.size = Vector2i(atlas_res, atlas_res)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.disable_3d = false
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	scene_tree.root.add_child(viewport)
	
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.global_transform = inst.global_transform
	
	viewport.add_child(cam)
	
	var bake_inst := MeshInstance3D.new()
	var bake_mesh = ArrayMesh.new()
	bake_inst.mesh = bake_mesh
	var bake_arrays = []
	bake_arrays.resize(Mesh.ARRAY_MAX)
	bake_arrays[Mesh.ARRAY_INDEX] = bake_indices
	bake_arrays[Mesh.ARRAY_VERTEX] = bake_verts
	bake_arrays[Mesh.ARRAY_TEX_UV] = bake_uvs
	bake_arrays[Mesh.ARRAY_TEX_UV2] = bake_uv2s
	bake_arrays[Mesh.ARRAY_NORMAL] = bake_normals
	bake_arrays[Mesh.ARRAY_COLOR] = bake_cols
	bake_arrays[Mesh.ARRAY_CUSTOM0] = _color_to_float_array(bake_c0)
	bake_arrays[Mesh.ARRAY_CUSTOM1] = _color_to_float_array(bake_c1)
	bake_arrays[Mesh.ARRAY_CUSTOM2] = _color_to_float_array(bake_c2)
	bake_arrays[Mesh.ARRAY_CUSTOM3] = bake_c3
	
	bake_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bake_arrays, [], {}, 
		mesh.surface_get_format(0) 
		| Mesh.ARRAY_FORMAT_CUSTOM3 
		| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/MarchingSquaresTerrain/resources/shaders/mst_terrain_bake.gdshader") as Shader
	_transfer_shader_props(mesh.surface_get_material(0), mat)
	bake_mesh.surface_set_material(0, mat)
	
	bake_inst.position = Vector3(-0.5, 0.5, -1)
	bake_inst.quaternion = Quaternion(1,0,0,0)

	cam.add_child(bake_inst)
	
	await scene_tree.process_frame
	await scene_tree.process_frame

	var img := viewport.get_texture().get_image()

	finished.emit(new_mesh, inst, img)
	viewport.queue_free()
	@warning_ignore_restore("integer_division")
	
func _to_color_array(arr: PackedFloat32Array) -> PackedColorArray:
	assert(arr.size() % 4 == 0)
	var ret := PackedColorArray()
	for i in range(0, arr.size(), 4):
		ret.append(Color(arr[i], arr[i+1], arr[i+2], arr[i+3]))
	return ret
	
func _color_to_float_array(arr: PackedColorArray) -> PackedFloat32Array:
	var ret := PackedFloat32Array()
	for c in arr:
		ret.append(c.r)
		ret.append(c.g)
		ret.append(c.b)
		ret.append(c.a)
	return ret
	
func _pack_verts_to_float_array(verts: PackedVector3Array) -> PackedFloat32Array:
	var ret := PackedFloat32Array()
	for i in verts.size():
		ret.append(verts[i].x)
		ret.append(verts[i].y)
		ret.append(verts[i].z)
	return ret
	
func _vector2_to_float_array(arr: PackedVector2Array) -> PackedFloat32Array:
	var ret := PackedFloat32Array()
	for c in arr:
		ret.append(c.x)
		ret.append(c.y)
		ret.append(0)
	return ret
	
func _transfer_shader_props(from: ShaderMaterial, to: ShaderMaterial) -> void:
	# Get uniform list from source shader
	var uniforms := from.shader.get_shader_uniform_list()
	
	var to_uniforms := {}
	for u in to.shader.get_shader_uniform_list():
		to_uniforms[u.name] = true
	
	for uniform in uniforms:
		var prop_name: String = uniform.name

		# Check if target shader has the same parameter
		if to_uniforms.has(prop_name):
			var value = from.get_shader_parameter(prop_name)
			to.set_shader_parameter(prop_name, value)
	

static func _store_geometry(mesh: Mesh, name: String):
	var mesh_arrays = mesh.surface_get_arrays(0)
	var vertices = mesh_arrays[Mesh.ARRAY_VERTEX]
	var uvs = mesh_arrays[Mesh.ARRAY_TEX_UV]
	#var uv2s = mesh_arrays[Mesh.ARRAY_TEX_UV2]
	var normals = mesh_arrays[Mesh.ARRAY_NORMAL]
	var indices = mesh_arrays[Mesh.ARRAY_INDEX]
	var vertex_offset := 1
	
	var file := FileAccess.open(name, FileAccess.WRITE)
	
	# vertices
	for v in vertices:
		file.store_line("v %f %f %f" % [v.x, v.y, v.z])

	# uvs
	for uv in uvs:
		file.store_line("vt %f %f" % [uv.x, 1.0 - uv.y])

	# normals
	for n in normals:
		file.store_line("vn %f %f %f" % [n.x, n.y, n.z])

	# faces
	for i in range(0, indices.size(), 3):
		var a = indices[i] + vertex_offset
		var b = indices[i + 1] + vertex_offset
		var c = indices[i + 2] + vertex_offset

		file.store_line(
            "f %d/%d/%d %d/%d/%d %d/%d/%d"
			% [a, a, a, c, c, c, b, b, b]
		)
