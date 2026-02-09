extends GutTest

func test_speed():
	var benchmark := MarchingSquaresGenerationBenchmark.new()
	benchmark.test_done.connect(func(threaded_time, non_threaded_time):
		assert_lt(threaded_time, non_threaded_time)
		print("Average generation time (threaded) ", threaded_time, " ms")
		print("Average generation time (non-threaded) ", non_threaded_time, " ms")
	)
	
	const HM_WIDTH := 33
	const HM_LENGTH := 33
	const NUM_CHUNKS := 1
	
	var hm : Array[Array] = []
	for i in range(HM_WIDTH):
		var row : Array[float ]= []
		for j in range(HM_LENGTH):
			row.append(randf_range(-5,5))
		hm.append(row)
	benchmark.generate_geometry_benchmark(hm, NUM_CHUNKS)
	
