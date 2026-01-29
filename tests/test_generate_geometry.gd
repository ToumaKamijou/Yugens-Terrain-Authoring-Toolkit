extends GutTest

func _store_geometry(mesh: Mesh, fname: String):
	var mesh_arrays = mesh.surface_get_arrays(0)
	var vertices = mesh_arrays[Mesh.ARRAY_VERTEX]
	var uvs = mesh_arrays[Mesh.ARRAY_TEX_UV]
	#var uv2s = mesh_arrays[Mesh.ARRAY_TEX_UV2]
	var normals = mesh_arrays[Mesh.ARRAY_NORMAL]
	var indices = mesh_arrays[Mesh.ARRAY_INDEX]
	var vertex_offset := 1
	
	var file := FileAccess.open(fname, FileAccess.WRITE)
	
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
	_test_generate_geometry_match_single(hm)
	
func test_f2():
	var hm := [
		[0,0.436, 0.291],
		[0,1.115, 2.125],
		[0,0.303, 0.175]]
	assert_true(_test_generate_geometry_match_single(hm))

func test_c0():
	assert_true(_test_generate_geometry_match_single([[0.2,0.1],[0,-0.1]]))
	_test_generate_geometry_match(0,0,0,0, "c0")
	
func test_c1_():
	_test_generate_geometry_match(1,0,0,0, "c1")
	
func test_c2():
	_test_generate_geometry_match(1,1,0,0, "c2")
	
func test_c3():
	_test_generate_geometry_match(2,1,0,0, "c3")
	
func test_c4():
	_test_generate_geometry_match(5,10,2,2, "c4")
	
func test_c5():
	_test_generate_geometry_match(0.0, 1.0,0.8, 0.0, "c5")
	assert_true(_test_generate_geometry_match_single([[0.9, 0.0],[0.0, 0.7]]))

func test_c5b():
	_test_generate_geometry_match(0,2,0.8,0,"c5b")
	
func test_c6():
	_test_generate_geometry_match(0,1,1,1, "c6")

func test_c7():
	_test_generate_geometry_match(0,1,1,2, "c7")
	
func test_c8():
	_test_generate_geometry_match(0,1,2,1, "c8")
	#_test_generate_geometry_match([[0.0, 1.0],[2.0, 0.9]])
	#_test_generate_geometry_match([[4, -3],
	#	[3, 3]])
	
func test_c9():
	_test_generate_geometry_match(0,2,1,1, "c9")

func test_c10():
	_test_generate_geometry_match(0,2,1,2, "c10")

func test_c11():
	_test_generate_geometry_match(0,1,2,2, "c11")

func test_c12():
	_test_generate_geometry_match(0,1,3,2, "c12")
	
func test_c13():
	_test_generate_geometry_match(0,3,1,2, "c13")
	
func test_c14():
	_test_generate_geometry_match(0,1,2,3, "c14")
	
func test_c15():
	_test_generate_geometry_match(0,2,1,3, "c15")
	
func test_c16():
	_test_generate_geometry_match(1,0.5,0,0.5, "c16")
	
func test_c17():
	_test_generate_geometry_match(0.5, 1.0,0.5, 0.0, "c17")


func _test_generate_geometry_match(ay,by,cy,dy, tname):
	_test_height_var([[ay, by], [cy, dy]], tname + "_r0")
	_test_height_var([[by, cy], [dy, ay]], tname + "_r1")
	_test_height_var([[cy, dy], [ay, by]], tname + "_r2")
	_test_height_var([[dy, ay], [by, cy]], tname + "_r3")
	
func _test_height_var(arr, tname):
	var tmp = arr[0][0] # cache to avoid acumulating float errors
	
	assert_true(_test_generate_geometry_match_single(arr), tname + "_level")
	arr[0][0] = tmp-0.1
	assert_true(_test_generate_geometry_match_single(arr), tname + "_lower")
	arr[0][0] = tmp+0.1
	assert_true(_test_generate_geometry_match_single(arr), tname + "_higher")

func _test_generate_geometry_match_single(height_map) -> bool:
	var chunk := MarchingSquaresTerrainChunk.new()
	
	chunk.terrain_system = MarchingSquaresTerrain.new()
	chunk.terrain_system.dimensions = Vector3i(height_map[0].size(),50,height_map.size())
	chunk.terrain_system.cell_size = Vector2.ONE
	chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.CUBIC
	chunk.terrain_system.chunk_cell_type = MarchingSquaresCellFactory.CellType.PROCEDURAL
	
	chunk.generate_height_map()
	chunk.height_map = height_map	
	chunk.initialize_terrain(false)
	chunk.generate_color_maps()
	chunk.generate_grass_mask_map()
	chunk.regenerate_all_cells()

	var expected = chunk.cell_geometry.duplicate_deep()
	
	_store_geometry(chunk.mesh,"expected.obj")
	
	chunk.terrain_system.prefabs = preload("uid://5nns2tpfna5l") # template 
	chunk.terrain_system.chunk_cell_type = MarchingSquaresCellFactory.CellType.AUTHORED
	chunk.regenerate_all_cells()
	
	_store_geometry(chunk.mesh,"got.obj")
	
	var current = chunk.cell_geometry
	for z in range(height_map.size()-1):
		for x in range(height_map[z].size()-1):
			var coords = Vector2i(x,z)
			var ex = expected[coords]["verts"]
			var got = current[coords]["verts"]
			
			assert_eq(got.size() % 3, 0)
			assert_eq(got.size(), ex.size())
			for i in range(ex.size()/3.):
				if not assert_has_polygon(ex, got[i*3], got[i*3+1], got[i*3+2]):
					return false
					
	
	#TODO: update UVs and other geometry assert_eq_deep(expected, chunk.cell_geometry)
	
	chunk.queue_free()
	return true

func assert_has_polygon(expected: Array, p1: Vector3, p2: Vector3, p3: Vector3) -> bool:
	assert_eq(expected.size() % 3, 0)
	for i in range(expected.size()/3.):
		if p1.is_equal_approx(expected[i*3]) and p2.is_equal_approx(expected[i*3+1]) and p3.is_equal_approx(expected[i*3+2]) or \
			p2.is_equal_approx(expected[i*3]) and p3.is_equal_approx(expected[i*3+1]) and p1.is_equal_approx(expected[i*3+2]) or \
			p3.is_equal_approx(expected[i*3]) and p1.is_equal_approx(expected[i*3+1]) and p2.is_equal_approx(expected[i*3+2]):
				return true
	#assert_true(false, "No matching polygon " + str(p1) + ", " + str(p2) + ", " + str(p3))
	return false
