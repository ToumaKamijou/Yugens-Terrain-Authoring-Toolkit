extends GutTest

func test_all_jobs_finish_on_stop() -> void:
	var pool := MarchingSquaresThreadPool.new(1)
	var mutex := Mutex.new()
	
	# using dictionary because primitives are not captured by lambda
	var helper := {"done": 0}
	
	var job := func():
		OS.delay_msec(1000)
		mutex.lock()
		helper["done"] = helper["done"] + 1
		mutex.unlock()
	
	pool.enqueue(job)
	pool.enqueue(job)
	pool.start()
	# immediate sync after start, only one worker and 1s work time ensures: 
	# - there is one job running
	# - there is one job pending
	pool.wait()
	
	# both jobs are done
	assert_eq(helper["done"], 2)
	
func test_jubs_run_in_parallel() -> void:
	if OS.get_processor_count() < 2:
		# if there is only core, this test would fail
		push_warning("Single Core CPU: skipping test")
		assert_true(true)
		return
	
	var pool := MarchingSquaresThreadPool.new(2)
	var job := func():
		OS.delay_msec(1000)
	
	var start := Time.get_ticks_msec()
	pool.enqueue(job)
	pool.enqueue(job)
	pool.start()
	pool.wait()
	
	var end := Time.get_ticks_msec()
	
	assert_lt(end-start, 1500)
	
