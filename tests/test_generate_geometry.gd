extends GutTest

func _store_geometry(mesh: Mesh, name: String):
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

func test_f():
	var hm := [[0.0, 0.2, 0.3, 0.0, 0.0],
		[0.0, 6.5521370973587, 6.5521370973587, 6.5521370973587, 0.0],
		[0.0, 3.1415, -8.5521370973587, 7.5521370973587, 0.0],
		[0.0, 0.0, 6.5555, 6.66, 0.0]]
	_test_generate_geometry_match(hm)

func test_c0():
	_test_generate_geometry_match([[0.2,0.1],[0,-0.1]])
	_test_generate_geometry_match([[3.2,3.1],[3,2.9]])
	
func test_c1_():
	_test_generate_geometry_match([[1, 0.2],[0.3, 0.1]])
	
func test_c2():
	_test_generate_geometry_match([[1, 1.1],[0.1, 0.15]])
	
func test_c3():
	_test_generate_geometry_match([[2.1, 0.9],[-0.1, 0.2]])
	
func test_c4():
	_test_generate_geometry_match([[1.0, 2.0],[0.0, 0.0]])
	
func test_c5():
	_test_generate_geometry_match([[0.0, 1.0],[0.8, 0.0]])
	_test_generate_geometry_match([[0.9, 0.0],[0.0, 0.7]])

func test_c5b():
	_test_generate_geometry_match([[0.0, 2.0],[0.8, 0.0]])
	
func test_c6():
	_test_generate_geometry_match([[0.0, 1.0],[1.0, 1.0]])

func test_c7():
	_test_generate_geometry_match([[0.0, 1.0],[1.0, 2.0]])
	
func test_c8():
	#_test_generate_geometry_match([[0.0, 1.0],[2.0, 1.0]])
	_test_generate_geometry_match([[0.0, 1.0],[2.0, 0.9]])
	
func test_c9():
	_test_generate_geometry_match([[0.0, 2.0],[1.0, 1.0]])

func test_c10():
	_test_generate_geometry_match([[0.0, 2.0],[1.0, 2.0]])

func test_c11():
	_test_generate_geometry_match([[0.0, 1.0],[2.0, 2.0]])

func test_c12():
	_test_generate_geometry_match([[0.0, 1.0],[3.0, 2.0]])
	
func test_c13():
	_test_generate_geometry_match([[0.0, 3.0],[1.0, 2.0]])
	
func test_c14():
	_test_generate_geometry_match([[0.0, 1.0],[2.0, 3.0]])
	
func test_c15():
	_test_generate_geometry_match([[0.0, 2.0],[1.0, 3.0]])
	
func test_c16():
	_test_generate_geometry_match([[1.0, 0.5],[0.0, 0.5]])
	
func test_c17():
	_test_generate_geometry_match([[0.5, 1.0],[0.5, 0.0]])
	
func _test_generate_geometry_match(height_map):
	var chunk := MarchingSquaresTerrainChunk.new()
	
	chunk.terrain_system = MarchingSquaresTerrain.new()
	chunk.terrain_system.dimensions = Vector3i(height_map[0].size(),50,height_map.size())
	chunk.terrain_system.cell_size = Vector2.ONE
	chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.CUBIC
	chunk.cell_factory.type = MarchingSquaresCellFactory.CellType.PROCEDURAL
	
	chunk.generate_height_map()
	chunk.height_map = height_map	
	chunk.initialize_terrain(false)
	chunk.generate_color_maps()
	chunk.generate_grass_mask_map()
	chunk.regenerate_all_cells()

	var expected = chunk.cell_geometry.duplicate_deep()
	
	_store_geometry(chunk.mesh,"expected.obj")
	
	chunk.cell_factory.type = MarchingSquaresCellFactory.CellType.AUTHORED
	chunk.regenerate_all_cells()
	
	_store_geometry(chunk.mesh,"got.obj")
	
	var current = chunk.cell_geometry
	for z in range(height_map.size()-1):
		for x in range(height_map[z].size()-1):
			var coords = Vector2i(x,z)
			var ex = expected[coords]["verts"]
			var got = current[coords]["verts"]
		
			assert_eq(got.size() % 3, 0)
			for i in range(ex.size()/3.):
				assert_has_polygon(ex, got[i*3], got[i*3+1], got[i*3+2])
	
	#TODO: update UVs and other geometry assert_eq_deep(expected, chunk.cell_geometry)
	
	chunk.queue_free()

func assert_has_polygon(expected: Array, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	assert_eq(expected.size() % 3, 0)
	for i in range(expected.size()/3.):
		if p1.is_equal_approx(expected[i*3]) and p2.is_equal_approx(expected[i*3+1]) and p3.is_equal_approx(expected[i*3+2]) or \
			p2.is_equal_approx(expected[i*3]) and p3.is_equal_approx(expected[i*3+1]) and p1.is_equal_approx(expected[i*3+2]) or \
			p3.is_equal_approx(expected[i*3]) and p1.is_equal_approx(expected[i*3+1]) and p2.is_equal_approx(expected[i*3+2]):
				return
	assert_true(false, "No matching polygon " + str(p1) + ", " + str(p2) + ", " + str(p3))
