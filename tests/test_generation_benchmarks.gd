extends GutTest


func test_speed():
	const HM_WIDTH := 33
	const HM_LENGTH := 33
	const NUM_CHUNKS := 9
	
	var hm : Array[Array] = []
	for i in range(HM_WIDTH):
		var row : Array[float ]= []
		for j in range(HM_LENGTH):
			row.append(randf_range(-5,5))
		hm.append(row)
	_test_generate_geometry_benchmark(hm, NUM_CHUNKS)
	
func _test_generate_geometry_benchmark(height_map: Array[Array], N: int):
	var chunk := MarchingSquaresTerrainChunk.new()
	
	chunk.terrain_system = MarchingSquaresTerrain.new()
	chunk.terrain_system.dimensions = Vector3i(height_map[0].size(),50,height_map.size())
	chunk.terrain_system.cell_size = Vector2.ONE
	chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.CUBIC
	
	chunk.generate_height_map()
	chunk.height_map = height_map	
	chunk.initialize_terrain(false)
	chunk.generate_color_maps()
	chunk.generate_grass_mask_map()
	
	var sum: float = 0
	for i in range(N):
		var t0 := Time.get_ticks_msec()
		chunk.regenerate_all_cells(true)
		var t1 := Time.get_ticks_msec()
		sum += (t1-t0)
	
	var threaded_time := sum / float(N)
	print("Average generation time (threaded) ", threaded_time, " ms")
	
	sum = 0
	for i in range(N):
		var t0 := Time.get_ticks_msec()
		chunk.regenerate_all_cells(false)
		var t1 := Time.get_ticks_msec()
		sum += (t1-t0)
	
	var non_threaded_time := sum / float(N)
	print("Average generation time (non-threaded) ", non_threaded_time, " ms")
	
	assert_lt(threaded_time, non_threaded_time)
	
