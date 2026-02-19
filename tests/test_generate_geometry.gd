extends GutTest

func _store_geometry(mesh: Mesh, name_: String):
	var mesh_arrays = mesh.surface_get_arrays(0)
	var vertices = mesh_arrays[Mesh.ARRAY_VERTEX]
	var uvs = mesh_arrays[Mesh.ARRAY_TEX_UV]
	#var uv2s = mesh_arrays[Mesh.ARRAY_TEX_UV2]
	var normals = mesh_arrays[Mesh.ARRAY_NORMAL]
	var indices = mesh_arrays[Mesh.ARRAY_INDEX]
	var vertex_offset := 1
	
	var file := FileAccess.open(name_, FileAccess.WRITE)
	
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

func test_full():
	var hm := [[0.0, 0.2, 0.3, 0.0, 0.0],
		[0.0, 6.5521370973587, 6.5521370973587, 6.5521370973587, 0.0],
		[0.0, 3.1415, -8.5521370973587, 7.5521370973587, 0.0],
		[0.0, 0.0, 6.5555, 6.66, 0.0]]
	_test_generate_geometry_match(hm, "full")

func test_c0():
	_test_generate_geometry_match([[0.2,0.1],[0,-0.1]], "c0.0")
	_test_generate_geometry_match([[3.2,3.1],[3,2.9]], "c0.1")
	
func test_c1_():
	_test_generate_geometry_match([[1, 0.2],[0.3, 0.1]], "c1.0")
	
func test_c2():
	_test_generate_geometry_match([[1, 1.1],[0.1, 0.15]], "c2.0")
	
func test_c3():
	_test_generate_geometry_match([[2.1, 0.9],[-0.1, 0.2]], "c3.0")
	
func test_c4():
	_test_generate_geometry_match([[1.0, 2.0],[0.0, 0.0]], "c4.0")
	
func test_c5():
	_test_generate_geometry_match([[0.0, 1.0],[0.8, 0.0]], "c5.0")
	_test_generate_geometry_match([[0.9, 0.0],[0.0, 0.7]], "c5.1")

func test_c6():
	_test_generate_geometry_match([[0.0, 2.0],[0.8, 0.0]], "c6.1")
	
func test_c7():
	_test_generate_geometry_match([[0.0, 1.1],[1.2, 1.3]], "c7.0")

func test_c8():
	_test_generate_geometry_match([[0.0, 1.1],[1.2, 2.2]], "c8.0")
	
func test_c9():
	_test_generate_geometry_match([[0.0, 1.0],[2.0, 1.0]], "c9.0")
	_test_generate_geometry_match([[0.0, 1.1],[2.1, 0.9]], "c9.1")
	
func test_c10():
	_test_generate_geometry_match([[0.0, 2.2],[1.1, 1.2]], "c10.0")

func test_c11():
	_test_generate_geometry_match([[0.0, 2.0],[1.0, 2.0]], "c11.0")

func test_c12():
	_test_generate_geometry_match([[0.0, 1.0],[2.5, 2.0]], "c12.0")

func test_c13():
	_test_generate_geometry_match([[0.0, 1.0],[3.0, 2.0]], "c13.0")
	
func test_c14():
	_test_generate_geometry_match([[0.0, 3.0],[1.0, 2.0]], "c14.0")
	
func test_c15():
	_test_generate_geometry_match([[0.0, 1.0],[2.0, 3.0]], "c15.0")
	
func test_c16():
	_test_generate_geometry_match([[0.0, 2.0],[1.0, 3.0]], "c16.0")
	
func test_c17():
	_test_generate_geometry_match([[1.0, 0.5],[0.0, 0.5]], "c17.0")
	
func test_c18():
	_test_generate_geometry_match([[0.5, 1.0],[0.5, 0.0]], "c18.0")
	
func _test_generate_geometry_match(height_map, chunk_name, save_only = false):
	var chunk := MarchingSquaresTerrainChunk.new()

	chunk.terrain_system = MarchingSquaresTerrain.new()
	chunk.terrain_system.enable_runtime_texture_baking = false
	chunk.terrain_system.dimensions = Vector3i(height_map[0].size(),50,height_map.size())
	chunk.terrain_system.cell_size = Vector2.ONE
	chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.CUBIC
	chunk.merge_threshold = 0.6
	
	chunk.generate_height_map()
	chunk.height_map = height_map	
	chunk.initialize_terrain(false)
	chunk.generate_color_maps()
	chunk.generate_grass_mask_map()
	chunk.regenerate_all_cells(true)

	var generated = chunk.mesh.surface_get_arrays(0)
	var success := true
	if save_only:
		_store_geometry(chunk.mesh,"tests/expected_cell_geometry/" + chunk_name + ".obj")
	else:
		var expected_mesh: Mesh = load("res://tests/expected_cell_geometry/" + chunk_name + ".obj")
		var expected = expected_mesh.surface_get_arrays(0)
		
		var indices = generated[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var idx0 = indices[i]
			var idx1 = indices[i + 1]
			var idx2 = indices[i + 2]
			
			var p1 : Vector3 = generated[Mesh.ARRAY_VERTEX][idx0]
			var p2 : Vector3 = generated[Mesh.ARRAY_VERTEX][idx1]
			var p3 : Vector3 = generated[Mesh.ARRAY_VERTEX][idx2]
			
			var uv1 : Vector2 = generated[Mesh.ARRAY_TEX_UV][idx0]
			var uv2 : Vector2 = generated[Mesh.ARRAY_TEX_UV][idx1]
			var uv3 : Vector2 = generated[Mesh.ARRAY_TEX_UV][idx2]
			
			success = success and assert_has_polygon(expected, p1, p2, p3, uv1, uv2, uv3)
	if not success:
		_store_geometry(chunk.mesh,"tests/expected_cell_geometry/" + chunk_name + "_fail.obj")
	#else:
	#	_store_geometry(chunk.mesh,"tests/expected_cell_geometry/" + chunk_name + "_success.obj")
	assert_true(true)
	chunk.queue_free()

func assert_has_polygon(expected: Array, p1: Vector3, p2: Vector3, p3: Vector3, uv1: Vector2, uv2: Vector2, uv3: Vector2) -> bool:

	var indices = expected[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		var idx0 = indices[i]
		var idx1 = indices[i + 1]
		var idx2 = indices[i + 2]
		
		var ex_p1 : Vector3 = expected[Mesh.ARRAY_VERTEX][idx0]
		var ex_p2 : Vector3 = expected[Mesh.ARRAY_VERTEX][idx1]
		var ex_p3 : Vector3 = expected[Mesh.ARRAY_VERTEX][idx2]
		var ex_uv1 : Vector2 = expected[Mesh.ARRAY_TEX_UV][idx0]
		var ex_uv2 : Vector2 = expected[Mesh.ARRAY_TEX_UV][idx1]
		var ex_uv3 : Vector2 = expected[Mesh.ARRAY_TEX_UV][idx2]

		if p1.is_equal_approx(ex_p1) and p2.is_equal_approx(ex_p2) and p3.is_equal_approx(ex_p3):
			return check_uvs(ex_uv1, ex_uv2, ex_uv3, uv1, uv2, uv3)
		elif p2.is_equal_approx(ex_p1) and p3.is_equal_approx(ex_p2) and p1.is_equal_approx(ex_p3):
			return check_uvs(ex_uv1, ex_uv2, ex_uv3, uv2, uv3, uv1)
		elif p3.is_equal_approx(ex_p1) and p1.is_equal_approx(ex_p2) and p2.is_equal_approx(ex_p3):
			return check_uvs(ex_uv1, ex_uv2, ex_uv3, uv3, uv1, uv2)
	assert_true(false, "No matching polygon " + str(p1) + ", " + str(p2) + ", " + str(p3))
	return false
	
func check_uvs(e1,e2,e3,g1,g2,g3) -> bool:
	if not (e1.is_equal_approx(g1) and e2.is_equal_approx(g2) and e3.is_equal_approx(g3)):
		assert_true(false, "UVs not matching")
		return false
	return true
